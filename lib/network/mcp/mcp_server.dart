import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:proxypin/network/http/websocket.dart';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/components/manager/hosts_manager.dart';
import 'package:proxypin/network/components/manager/request_block_manager.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/components/manager/rewrite_rule.dart';
import 'package:proxypin/network/components/manager/script_manager.dart';
import 'package:proxypin/network/components/manager/request_breakpoint_manager.dart';
import 'package:proxypin/network/components/manager/network_condition_manager.dart';
import 'package:proxypin/network/components/manager/environment_manager.dart';
import 'package:proxypin/network/components/request_breakpoint.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/mcp/mcp_bridge.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:proxypin/network/util/random.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/native/mcp_screen.dart';
import 'package:proxypin/native/vpn.dart';
import 'package:flutter/material.dart';

class McpServer {
  static final McpServer _instance = McpServer._internal();

  factory McpServer() => _instance;

  McpServer._internal();

  io.HttpServer? _server;
  int? _port;
  String? _lastError;

  int get port => _port ?? 9010;

  /// 上次启动错误信息（端口冲突等），供 UI 展示
  String? get lastError => _lastError;

  /// MCP 协议版本：最新稳定版 2026-07-28（无状态核心）
  /// 同时兼容旧版 2024-11-05 / 2025-11-25（initialize 握手路径）
  static const String protocolVersion = '2026-07-28';

  /// 兼容的旧版协议版本列表（仍支持握手路径）
  static const List<String> legacyProtocolVersions = [
    '2024-11-05',
    '2025-03-26',
    '2025-06-18',
    '2025-11-25',
  ];

  /// 是否启用 Streamable HTTP（新式传输，支持 /mcp 端点与会话）
  static const bool streamableHttpEnabled = true;

  /// 是否启用 2026-07-28 无状态模式（Stateless Core）
  /// 无状态模式下：不要求 initialize 握手、不创建 Mcp-Session-Id，
  /// 请求通过 MCP-Protocol-Version / Mcp-Method / Mcp-Name 头或 _meta 字段自描述
  static const bool statelessEnabled = true;

  // Streamable HTTP 会话管理（sessionId -> 该会话的 SSE 输出流）
  final Map<String, _StreamableSession> _streamSessions = {};

  // SSE 连接池 — 使用 List 的 copy-then-iterate 模式保证并发安全
  final List<io.HttpResponse> _sseConnections = [];

  /// SSE 连接数上限：防止（尤其开启局域网访问后）未认证客户端无限建连耗尽资源（DoS）。
  static const int maxSseConnections = 32;

  /// 线程安全地添加 SSE 连接。超过上限时返回 false，调用方应主动关闭该连接。
  bool _addSseConnection(io.HttpResponse response) {
    if (_sseConnections.length >= maxSseConnections) {
      logger.i('MCP SSE connection rejected: limit $maxSseConnections reached');
      return false;
    }
    _sseConnections.add(response);
    return true;
  }

  /// 线程安全地移除 SSE 连接
  void _removeSseConnection(io.HttpResponse response) {
    _sseConnections.remove(response);
  }

  /// 获取 SSE 连接列表的快照（避免遍历时被并发修改）
  List<io.HttpResponse> _snapshotSseConnections() =>
      List<io.HttpResponse>.from(_sseConnections);

  // SSE 心跳定时器
  Timer? _heartbeatTimer;

  // 状态变化回调
  VoidCallback? onStatusChanged;

  /// 用户自定义 Roots（UI 编辑后经 [setRoots] 注入，优先于内置默认值展示）
  List<Map<String, dynamic>> _customRoots = [];

  /// 更新自定义 Roots 列表（由自动化配置页在增删改后调用，立即对 roots/list 生效）
  void setRoots(List<Map<String, dynamic>> roots) {
    _customRoots = List<Map<String, dynamic>>.from(roots);
  }

  /// 当前生效的 Roots 列表（自定义 + 内置默认，按 uri 去重）
  List<Map<String, dynamic>> getRoots() {
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final r in [..._customRoots, ..._getRootsList()]) {
      final uri = r['uri']?.toString() ?? '';
      if (uri.isEmpty || seen.contains(uri)) continue;
      seen.add(uri);
      result.add(r);
    }
    return result;
  }

  bool get isRunning => _server != null;

  /// 重启 MCP 服务器（用于端口变更后）
  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> start() async {
    try {
      if (isRunning) return;

      var config = await Configuration.instance;

      // 检查是否启用 MCP 服务
      if (!config.mcpEnabled) {
        logger.i('MCP Server is disabled by configuration, skipping start');
        return;
      }

      _port = config.mcpPort;

      // 安全默认：仅监听回环地址；如需局域网访问，由用户在设置中显式开启 mcpAllowLan
      final bindAddress =
          config.mcpAllowLan ? io.InternetAddress.anyIPv4 : io.InternetAddress.loopbackIPv4;
      _server = await io.HttpServer.bind(bindAddress, _port!);
      _lastError = null; // 清除之前的错误
      logger.i('MCP Server listening on http://${bindAddress.address}:$_port '
          '(allowLan=${config.mcpAllowLan})');

      _server!.listen((request) {
        // CORS 处理
        if (request.method == 'OPTIONS') {
          _handleOptions(request);
          return;
        }

        final path = request.uri.path;
        if (path == '/sse') {
          _handleSse(request);
        } else if (path == '/messages') {
          _handleMessages(request);
        } else if (path == '/mcp') {
          if (streamableHttpEnabled) {
            _handleStreamableHttp(request);
          } else {
            _handleMcp(request);
          }
        } else if (path == '/health') {
          // 健康检查端点，供客户端探测服务是否可用
          final response = request.response;
          response.headers.contentType = io.ContentType.json;
          response.headers.add('Access-Control-Allow-Origin', '*');
          response.write(
            jsonEncode({'status': 'ok', 'server': 'ProxyPin MCP'}),
          );
          response.close();
        } else {
          final response = request.response;
          response.statusCode = io.HttpStatus.notFound;
          response.close();
        }
      });

      // 监听 Bridge 的请求完成事件，推送到 SSE
      McpBridge().onRequestCompleted = (log) {
        _broadcastEvent('resource', {
          'uri': 'proxypin://requests/latest',
          // 可以在这里推送增量更新
        });
      };
      // 启动 SSE 心跳保活（每 30 秒发送 ping）
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _broadcastEvent('ping', {
          'timestamp': DateTime.now().toIso8601String(),
        });
      });

      // 通知状态变化
      onStatusChanged?.call();

      // 运行状态持久化：启动成功后同步启用标记，避免重启后状态与预期不一致
      config.mcpEnabled = true;
      ConfigAutoSave.markChanged();
    } catch (e) {
      _lastError = e.toString();
      logger.e('Failed to start MCP server', error: e);
    }
  }

  /// [persistState] 为 true 时将"手动停止"写入配置（重启不自动拉起）；
  /// 应用退出清理等场景传 false，避免误把自动清理当成用户操作。
  Future<void> stop({bool persistState = true}) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    // 取消会话过期定时器并清理会话，避免服务停止后 Timer 仍在后台挂起（泄漏）
    for (var session in _streamSessions.values) {
      session.expiry?.cancel();
      session.expiry = null;
      session.stream = null;
    }
    _streamSessions.clear();

    // 关闭所有 SSE 连接（先取快照再遍历）
    for (var conn in _snapshotSseConnections()) {
      try {
        await conn.close();
      } catch (e) {
        // ignore
      }
    }
    _sseConnections.clear();

    // 清除回调
    McpBridge().onRequestCompleted = null;

    await _server?.close();
    _server = null;

    // 清理 Streamable HTTP 会话
    _streamSessions.clear();
    // 手动停止时清除错误状态
    _lastError = null;
    // 通知状态变化
    onStatusChanged?.call();

    // 运行状态持久化：手动停止后写入配置，重启应用不再自动拉起
    if (persistState) {
      try {
        var config = await Configuration.instance;
        config.mcpEnabled = false;
        ConfigAutoSave.markChanged();
      } catch (e) {
        logger.w('Failed to persist MCP stop state', error: e);
      }
    }
  }

  void _handleOptions(io.HttpRequest request) {
    final response = request.response;
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.headers.add('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
    response.headers.add(
      'Access-Control-Allow-Headers',
      'Content-Type, Accept',
    );
    response.close();
  }

  void _handleSse(io.HttpRequest request) {
    final response = request.response;
    response.headers.contentType = io.ContentType('text', 'event-stream');
    response.headers.add('Cache-Control', 'no-cache');
    response.headers.add('Connection', 'keep-alive');
    response.headers.add('Access-Control-Allow-Origin', '*');

    // 发送 endpoint 告知客户端 POST 地址
    final endpoint = '/messages';
    response.write('event: endpoint\ndata: $endpoint\n\n');
    response.flush();

    if (!_addSseConnection(response)) {
      response.write('event: error\ndata: too many concurrent connections\n\n');
      response.close();
      return;
    }

    logger.i('New MCP SSE connection');

    response.done
        .then((_) {
          _removeSseConnection(response);
          logger.i('MCP SSE connection closed');
        })
        .catchError((e) {
          _removeSseConnection(response);
        });
  }

  Future<void> _handleMessages(io.HttpRequest request) async {
    if (request.method != 'POST') {
      final response = request.response;
      response.headers.add('Access-Control-Allow-Origin', '*');
      response.statusCode = 405; // Method Not Allowed
      response.close();
      return;
    }

    try {
      final content = await utf8.decoder.bind(request).join();
      if (content.isEmpty) {
        final response = request.response;
        response.headers.add('Access-Control-Allow-Origin', '*');
        response.statusCode = io.HttpStatus.badRequest;
        response.close();
        return;
      }

      // 先设置 CORS 和 Content-Type，确保异常时响应也包含 CORS 头
      final response = request.response;
      response.headers.contentType = io.ContentType.json;
      response.headers.add('Access-Control-Allow-Origin', '*');

      final decoded = jsonDecode(content);
      if (decoded is List) {
        // 批量请求
        final results = <Map<String, dynamic>>[];
        for (var item in decoded) {
          final result = await _processJsonRpc(Map<String, dynamic>.from(item as Map));
          if (result != null) results.add(result);
        }
        if (results.isEmpty) {
          response.statusCode = 202;
        } else {
          response.write(jsonEncode(results));
        }
      } else if (decoded is Map) {
        final result = await _processJsonRpc(Map<String, dynamic>.from(decoded));
        if (result != null) {
          response.write(jsonEncode(result));
        } else {
          // 通知类消息不需要返回内容，返回 202 Accepted
          response.statusCode = 202;
        }
      } else {
        response.statusCode = io.HttpStatus.badRequest;
        response.write(jsonEncode({
          'jsonrpc': '2.0',
          'id': null,
          'error': {'code': -32600, 'message': 'Invalid Request'}
        }));
      }
      response.close();
    } catch (e) {
      logger.e('MCP Message Error', error: e);
      final response = request.response;
      response.headers.set('Access-Control-Allow-Origin', '*');
      response.statusCode = io.HttpStatus.internalServerError;
      response.write(jsonEncode({'error': e.toString()}));
      await response.close();
    }
  }

  /// 处理 /mcp 端点 - Streamable HTTP 传输
  /// POST: JSON-RPC 请求/响应
  /// GET: SSE 流式连接
  Future<void> _handleMcp(io.HttpRequest request) async {
    if (request.method == 'GET') {
      // SSE 流式连接
      final response = request.response;
      response.headers.add('Access-Control-Allow-Origin', '*');
      response.headers.contentType = io.ContentType('text', 'event-stream');
      response.headers.add('Cache-Control', 'no-cache');
      response.headers.add('Connection', 'keep-alive');

      final endpoint = '/mcp';
      response.write('event: endpoint\ndata: $endpoint\n\n');
      response.flush();

      if (!_addSseConnection(response)) {
        response.write('event: error\ndata: too many concurrent connections\n\n');
        await response.close();
        return;
      }

      logger.i('New MCP streamable HTTP connection');

      response.done
          .then((_) {
            _removeSseConnection(response);
            logger.i('MCP streamable HTTP connection closed');
          })
          .catchError((e) {
            _removeSseConnection(response);
          });
      return;
    }

    if (request.method != 'POST') {
      final response = request.response;
      response.headers.add('Access-Control-Allow-Origin', '*');
      response.statusCode = 405;
      response.close();
      return;
    }

    try {
      final content = await utf8.decoder.bind(request).join();
      if (content.isEmpty) {
        final response = request.response;
        response.headers.add('Access-Control-Allow-Origin', '*');
        response.statusCode = io.HttpStatus.badRequest;
        response.close();
        return;
      }

      // 先设置 CORS 和 Content-Type，确保异常时响应也包含 CORS 头
      final response = request.response;
      response.headers.add('Access-Control-Allow-Origin', '*');
      response.headers.contentType = io.ContentType.json;

      // 支持批量请求
      final decoded = jsonDecode(content);

      if (decoded is List) {
        // 批量请求
        final results = <Map<String, dynamic>>[];
        for (var item in decoded) {
          final result = await _processJsonRpc(Map<String, dynamic>.from(item as Map));
          if (result != null) {
            results.add(result);
          }
        }
        if (results.isEmpty) {
          // 纯通知批：按规范不返回响应体
          response.statusCode = 202;
        } else {
          response.write(jsonEncode(results));
        }
      } else if (decoded is Map) {
        final result = await _processJsonRpc(Map<String, dynamic>.from(decoded));

        if (result != null) {
          response.write(jsonEncode(result));
        } else {
          response.statusCode = 202;
        }
      } else {
        response.statusCode = io.HttpStatus.badRequest;
        response.write(jsonEncode({
          'jsonrpc': '2.0',
          'id': null,
          'error': {'code': -32600, 'message': 'Invalid Request'}
        }));
      }
      response.close();
    } catch (e) {
      logger.e('MCP /mcp Error', error: e);
      final response = request.response;
      response.headers.set('Access-Control-Allow-Origin', '*');
      response.statusCode = io.HttpStatus.internalServerError;
      response.write(jsonEncode({'error': e.toString()}));
      await response.close();
    }
  }

  /// 生成 MCP 会话 ID
  String _generateSessionId() {
    return RandomUtil.randomString(32);
  }

  /// Streamable HTTP 传输处理（MCP 最新传输方式）
  /// GET /mcp: 建立 SSE 流（可携带 Mcp-Session-Id）
  /// POST /mcp: JSON-RPC 请求（可携带 Mcp-Session-Id 并返回流式响应）
  Future<void> _handleStreamableHttp(io.HttpRequest request) async {
    if (request.method == 'GET') {
      _handleStreamableHttpGet(request);
      return;
    }
    if (request.method != 'POST') {
      final response = request.response;
      _setCorsHeaders(response);
      response.statusCode = io.HttpStatus.methodNotAllowed;
      response.close();
      return;
    }

    try {
      final content = await utf8.decoder.bind(request).join();
      final response = request.response;
      _setCorsHeaders(response);
      response.headers.contentType = io.ContentType.json;

      if (content.trim().isEmpty) {
        response.statusCode = io.HttpStatus.badRequest;
        response.write(jsonEncode({'error': 'empty request body'}));
        await response.close();
        return;
      }

      final decoded = jsonDecode(content);
      final requests = decoded is List
          ? decoded.cast<dynamic>().toList()
          : [decoded];
      final responses = <Map<String, dynamic>>[];

      // 2026-07-28 无状态模式：客户端通过 MCP-Protocol-Version 头声明协议版本
      // 无状态模式不使用会话，直接处理请求
      final clientProtocol = request.headers.value('MCP-Protocol-Version');

      for (final item in requests) {
        if (item is! Map) continue;
        final jsonRpc = Map<String, dynamic>.from(item);

        // 无状态模式：校验请求头与 body 一致性（-32020），并解析 _meta 中的协议版本
        if (statelessEnabled &&
            clientProtocol != null &&
            clientProtocol != '2024-11-05') {
          final metaResult = _applyStatelessHeaders(request, jsonRpc);
          if (metaResult != null) {
            responses.add(metaResult);
            continue;
          }
        }

        final result = await _processJsonRpc(jsonRpc);
        if (result != null) responses.add(result);
      }

      // 会话建立：仅旧版（2024-11-05 等握手协议）在 initialize 成功后返回会话 ID
      // 无状态模式（2026-07-28）不创建会话
      final sessionId = _getOrCreateSession(request, decoded);
      if (sessionId != null) {
        response.headers.set('Mcp-Session-Id', sessionId);
      }

      if (responses.isEmpty) {
        response.statusCode = io.HttpStatus.accepted;
      } else if (decoded is List) {
        response.write(jsonEncode(responses));
      } else {
        response.write(jsonEncode(responses.first));
      }
      await response.close();
    } catch (e) {
      logger.e('MCP /mcp streamable error', error: e);
      try {
        final response = request.response;
        _setCorsHeaders(response);
        response.statusCode = io.HttpStatus.internalServerError;
        response.write(jsonEncode({'error': e.toString()}));
        await response.close();
      } catch (_) {
        // response already closed
      }
    }
  }

  /// 2026-07-28 无状态模式：校验 MCP-Protocol-Version / Mcp-Method / Mcp-Name 头
  /// 与 JSON-RPC body 一致性。不一致时返回 -32020 错误。
  /// 返回 null 表示校验通过，可继续正常处理。
  Map<String, dynamic>? _applyStatelessHeaders(
    io.HttpRequest request,
    Map<String, dynamic> jsonRpc,
  ) {
    final headerVersion = request.headers.value('MCP-Protocol-Version');
    final headerMethod = request.headers.value('Mcp-Method');
    final headerName = request.headers.value('Mcp-Name');

    // body 中的协议版本（_meta 字段）与头不一致时拒绝
    final metaVersion = (jsonRpc['_meta'] is Map)
        ? (jsonRpc['_meta'] as Map)['protocolVersion']
        : null;
    if (headerVersion != null &&
        metaVersion != null &&
        headerVersion != metaVersion) {
      return {
        'jsonrpc': '2.0',
        'id': jsonRpc['id'],
        'error': {
          'code': -32020,
          'message':
              'MCP-Protocol-Version header ($headerVersion) does not match _meta.protocolVersion ($metaVersion)',
        },
      };
    }

    // 头部 method 与 body method 不一致时拒绝
    final bodyMethod = jsonRpc['method'];
    if (headerMethod != null &&
        bodyMethod != null &&
        headerMethod != bodyMethod) {
      return {
        'jsonrpc': '2.0',
        'id': jsonRpc['id'],
        'error': {
          'code': -32020,
          'message':
              'Mcp-Method header ($headerMethod) does not match body method ($bodyMethod)',
        },
      };
    }

    return null;
  }

  /// 根据请求提取或创建 Streamable HTTP 会话
  String? _getOrCreateSession(io.HttpRequest request, dynamic decoded) {
    // 客户端请求头中带的会话 ID
    final existingId = request.headers.value('Mcp-Session-Id');
    if (existingId != null && _streamSessions.containsKey(existingId)) {
      return existingId;
    }

    // 仅对 initialize 请求创建新会话
    final isInitialize = decoded is Map && decoded['method'] == 'initialize';
    if (!isInitialize) return null;

    final sessionId = _generateSessionId();
    final session = _StreamableSession();
    // 清理过期会话（简单保护：超过 1 小时未使用）；定时器保存引用以便停止服务时取消
    session.expiry = Timer(const Duration(hours: 1), () {
      _streamSessions.remove(sessionId);
    });
    _streamSessions[sessionId] = session;
    return sessionId;
  }

  /// GET /mcp — 建立 SSE 输出流（Streamable HTTP 的 GET 模式）
  void _handleStreamableHttpGet(io.HttpRequest request) {
    final response = request.response;
    _setCorsHeaders(response);
    response.headers.contentType = io.ContentType('text', 'event-stream');
    response.headers.add('Cache-Control', 'no-cache');
    response.headers.add('Connection', 'keep-alive');

    // 关联到会话（若有）
    final sessionId = request.headers.value('Mcp-Session-Id');
    if (sessionId != null && _streamSessions.containsKey(sessionId)) {
      _streamSessions[sessionId]!.stream = response;
      logger.i('MCP streamable HTTP session $sessionId connected (GET)');
    }

    response.write('event: endpoint\ndata: /mcp\n\n');
    response.flush();

    if (!_addSseConnection(response)) {
      response.write('event: error\ndata: too many concurrent connections\n\n');
      response.close();
      return;
    }
    response.done
        .then((_) {
          _removeSseConnection(response);
          if (sessionId != null &&
              _streamSessions[sessionId]?.stream == response) {
            _streamSessions[sessionId]!.stream = null;
          }
        })
        .catchError((_) {
          _removeSseConnection(response);
          if (sessionId != null &&
              _streamSessions[sessionId]?.stream == response) {
            _streamSessions[sessionId]!.stream = null;
          }
        });
  }

  /// 设置统一的 CORS 头
  void _setCorsHeaders(io.HttpResponse response) {
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.headers.add('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
    response.headers.add(
      'Access-Control-Allow-Headers',
      'Content-Type, Accept, Mcp-Session-Id, MCP-Protocol-Version, Mcp-Method, Mcp-Name, Last-Event-ID',
    );
    response.headers.add('Access-Control-Expose-Headers', 'Mcp-Session-Id');
  }

  /// 工具是否启用（可在设置中单独开关）
  bool _isToolEnabled(String name) {
    return McpBridge().isToolEnabled(name);
  }

  /// 广播 SSE 事件
  void _broadcastEvent(String event, Object data) {
    var deadConnections = <io.HttpResponse>[];
    // 使用快照遍历，避免遍历期间被并发修改
    for (var conn in _snapshotSseConnections()) {
      try {
        conn.write('event: $event\n');
        conn.write('data: ${jsonEncode(data)}\n');
        conn.write('\n');
        // 立即刷新确保数据及时发送，避免缓冲延迟
        conn.flush();
      } catch (e) {
        // 标记死连接以便移除
        deadConnections.add(conn);
      }
    }
    // 清理失败的连接
    if (deadConnections.isNotEmpty) {
      for (var conn in deadConnections) {
        _removeSseConnection(conn);
      }
    }
  }

  /// 配置变更时通知所有 SSE 客户端刷新
  void _notifyConfigChanged(String category, [Map<String, dynamic>? details]) {
    _broadcastEvent('config_changed', {
      'category': category,
      'timestamp': DateTime.now().toIso8601String(),
      if (details != null) ...details,
    });
  }

  Future<Map<String, dynamic>?> _processJsonRpc(
    Map<String, dynamic> request,
  ) async {
    final method = request['method'];
    final id = request['id'];

    // JSON-RPC Response 结构
    Map<String, dynamic> response(dynamic result) {
      return {'jsonrpc': '2.0', 'id': id, 'result': result};
    }

    Map<String, dynamic> error(int code, String message) {
      return {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };
    }

    try {
      switch (method) {
        case 'initialize':
          // 协议协商：客户端声明支持的版本，服务端返回双方共同支持的最高版本
          // 2026-07-28 无状态客户端通常不再发 initialize，但保留兼容
          var negotiated = protocolVersion;
          final params = request['params'] as Map<String, dynamic>?;
          final clientVersion = params?['protocolVersion'] as String?;
          if (clientVersion != null) {
            if (legacyProtocolVersions.contains(clientVersion)) {
              // 旧版客户端：回复其版本，走有状态握手路径
              negotiated = clientVersion;
            }
            // 客户端版本比服务端新或相同：返回服务端版本
          }
          return response({
            'protocolVersion': negotiated,
            'capabilities': {
              'tools': {'listChanged': false},
              'resources': {},
              'prompts': {'listChanged': false},
              // 注意：roots 属于"客户端能力"（由服务端向客户端发起 roots/list），
              // 不应声明为服务端能力，故此处不再声明
              'completions': {},
            },
            'serverInfo': {'name': 'ProxyPin MCP', 'version': '1.3.1'},
          });

        case 'notifications/initialized':
          // 通知类消息不需要返回响应
          return null;

        case 'notifications/cancelled':
          // 客户端取消请求通知，不需要返回响应
          logger.i('Received cancellation notification: ${request['params']}');
          return null;

        case 'tools/list':
          return response({
            'tools': _getToolsList()
                .where((t) => _isToolEnabled(t['name'] as String))
                .toList(),
          });

        case 'tools/call':
          final params = request['params'] as Map<String, dynamic>?;
          if (params == null) {
            return error(-32602, 'Missing params');
          }
          final name = params['name'];
          if (name is! String || name.isEmpty) {
            return error(-32602, 'Invalid params: name is required');
          }
          final rawArgs = params['arguments'];
          final Map<String, dynamic> args =
              rawArgs is Map ? Map<String, dynamic>.from(rawArgs) : {};
          try {
            // 超时保护：避免设备类工具（MethodChannel）等长时间挂起占用连接
            final result = await _executeTool(name, args).timeout(const Duration(seconds: 120));
            // 统一错误语义：工具内部以 {'error': ...} 表示失败时，按 MCP 规范标记 isError
            final isErr = result is Map && result.containsKey('error');
            return response({
              'content': [
                {'type': 'text', 'text': jsonEncode(result)},
              ],
              if (isErr) 'isError': true,
            });
          } catch (e) {
            // MCP 规范：工具执行错误应作为结果返回（isError: true），而非 JSON-RPC 错误
            return response({
              'content': [
                {
                  'type': 'text',
                  'text': jsonEncode({'error': e.toString()}),
                },
              ],
              'isError': true,
            });
          }

        case 'resources/list':
          return response({
            'resources': [
              {
                'uri': 'proxypin://requests/latest',
                'name': 'Latest Requests',
                'mimeType': 'application/json',
              },
              {
                'uri': 'proxypin://config/current',
                'name': 'Current Configuration',
                'mimeType': 'application/json',
              },
              {
                'uri': 'proxypin://breakpoints/rules',
                'name': 'Breakpoint Rules',
                'mimeType': 'application/json',
              },
              {
                'uri': 'proxypin://network/conditions',
                'name': 'Weak Network Configuration',
                'mimeType': 'application/json',
              },
              {
                'uri': 'proxypin://environments/list',
                'name': 'Environment Variables',
                'mimeType': 'application/json',
              },
            ],
          });

        case 'resources/read':
          final params = request['params'] as Map<String, dynamic>?;
          if (params == null) {
            return error(-32602, 'Missing params');
          }
          final uri = params['uri'];
          final content = await _readResource(uri);
          return response({
            'contents': [
              {
                'uri': uri,
                'mimeType': 'application/json',
                'text': jsonEncode(content),
              },
            ],
          });

        case 'ping':
          return response({});

        // MCP 2026-07-28: Prompts 支持
        case 'prompts/list':
          return response({
            'prompts': _getPromptsList(),
          });

        case 'prompts/get':
          final promptParams = request['params'] as Map<String, dynamic>?;
          if (promptParams == null) {
            return error(-32602, 'Missing params');
          }
          final promptName = promptParams['name'] as String?;
          if (promptName == null) {
            return error(-32602, 'Missing prompt name');
          }
          final prompt = _getPrompt(promptName);
          if (prompt == null) {
            return error(-32602, 'Prompt not found: $promptName');
          }
          return response(prompt);

        // MCP 2026-07-28: Roots 支持
        case 'roots/list':
          return response({
            'roots': getRoots(),
          });

        // MCP 2026-07-28: Completions 支持
        case 'completion/complete':
          final completionParams = request['params'] as Map<String, dynamic>?;
          if (completionParams == null) {
            return error(-32602, 'Missing params');
          }
          final ref = completionParams['ref'] as Map<String, dynamic>?;
          final argument = completionParams['argument'] as Map<String, dynamic>?;
          final result = await _handleCompletion(ref, argument);
          return response(result);

        default:
          return error(-32601, 'Method not found: $method');
      }
    } catch (e, stack) {
      logger.e('MCP Execution Error', error: e, stackTrace: stack);
      return error(-32603, 'Internal error: $e');
    }
  }

  /// 获取全部可用工具列表（供 UI 页面展示，不经过启用过滤）
  List<Map<String, dynamic>> getTools() => _getToolsList();

  /// 供 AI Agent 对话页执行 MCP 工具（文本协议自动调用）
  Future<dynamic> executeTool(String name, Map<String, dynamic> args) =>
      _executeTool(name, args);

  /// 获取全部可用工具列表（别名，供 UI 页面调用）
  List<Map<String, dynamic>> getToolList() => _getToolsList();

  /// 供 UI 调用的 MCP 请求方法（直接调用内部处理逻辑）
  Future<Map<String, dynamic>?> sendRequest(String method, [Map<String, dynamic>? params]) async {
    try {
      final request = {
        'jsonrpc': '2.0',
        'id': 1,
        'method': method,
        if (params != null) 'params': params,
      };
      final result = await _processJsonRpc(request);
      if (result is Map<String, dynamic>) {
        return result['result'] as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      logger.e('MCP sendRequest error: $method', error: e);
      return null;
    }
  }

  /// 获取 Prompts 列表（供 UI 调用）
  List<Map<String, dynamic>> getPrompts() => _getPromptsList();

  /// 获取具体提示模板（供 UI 调用，返回 messages/arguments）
  Map<String, dynamic>? getPrompt(String name) => _getPrompt(name);

  // ==================== MCP 2026-07-28: Prompts 支持 ====================

  /// 获取可用提示模板列表
  List<Map<String, dynamic>> _getPromptsList() {
    return [
      {
        'name': 'api_security_check',
        'description': 'Analyze API security (auth, sensitive data, encryption)',
        'arguments': [
          {
            'name': 'request_id',
            'description': 'Request ID to analyze',
            'required': true,
          },
        ],
      },
      {
        'name': 'performance_analysis',
        'description': 'Analyze request performance and suggest optimizations',
        'arguments': [
          {
            'name': 'domain',
            'description': 'Domain to analyze',
            'required': false,
          },
          {
            'name': 'threshold_ms',
            'description': 'Performance threshold in milliseconds',
            'required': false,
          },
        ],
      },
      {
        'name': 'traffic_summary',
        'description': 'Generate traffic summary for a time period',
        'arguments': [
          {
            'name': 'minutes',
            'description': 'Time range in minutes',
            'required': false,
          },
        ],
      },
    ];
  }

  /// 获取具体提示模板
  Map<String, dynamic>? _getPrompt(String name) {
    final prompts = _getPromptsList();
    final prompt = prompts.firstWhere((p) => p['name'] == name,
        orElse: () => {'name': ''});
    if (prompt['name']!.isEmpty) return null;

    // 返回完整的 prompt 消息结构
    return {
      'name': name,
      'description': prompt['description'],
      'messages': [
        {
          'role': 'user',
          'content': {
            'type': 'text',
            'text': 'Please help me ${prompt['description']}. '
                'I will provide the necessary data.',
          },
        },
      ],
      'arguments': prompt['arguments'],
    };
  }

  // ==================== MCP 2026-07-28: Roots 支持 ====================

  /// 获取项目根目录列表
  List<Map<String, dynamic>> _getRootsList() {
    return [
      {
        'uri': 'proxypin://workspace',
        'name': 'ProxyPin Workspace',
      },
      {
        'uri': 'proxypin://captures',
        'name': 'Capture Files',
      },
      {
        'uri': 'proxypin://scripts',
        'name': 'Script Files',
      },
    ];
  }

  // ==================== MCP 2026-07-28: Completions 支持 ====================

  /// 处理自动完成请求
  Future<Map<String, dynamic>> _handleCompletion(
    Map<String, dynamic>? ref,
    Map<String, dynamic>? argument,
  ) async {
    final completions = <Map<String, dynamic>>[];

    // 根据 ref 类型提供不同的完成建议
    if (ref != null) {
      final refType = ref['type'] as String?;
      final refName = ref['name'] as String?;

      if (refType == 'ref/tool' && refName == 'tools/call') {
        // 工具调用时的参数完成
        final toolName = argument?['name'] as String?;
        if (toolName != null) {
          final tools = _getToolsList();
          final tool = tools.firstWhere((t) => t['name'] == toolName,
              orElse: () => {'name': ''});
          if (tool['name']!.isNotEmpty) {
            final schema = tool['inputSchema'] as Map<String, dynamic>?;
            final properties = schema?['properties'] as Map<String, dynamic>?;
            if (properties != null) {
              for (var prop in properties.keys) {
                completions.add({
                  'value': prop,
                  'description': 'Parameter: $prop',
                });
              }
            }
          }
        }
      } else if (refType == 'ref/resource' && refName == 'resources/read') {
        // 资源读取时的 URI 完成
        final resources = [
          'proxypin://requests/latest',
          'proxypin://config/current',
          'proxypin://breakpoints/rules',
          'proxypin://network/conditions',
          'proxypin://environments/list',
        ];
        for (var uri in resources) {
          completions.add({'value': uri, 'description': 'Resource URI'});
        }
      }
    }

    // 根据 argument 名称提供完成建议
    if (argument != null) {
      final argName = argument['name'] as String?;
      final argValue = argument['value'] as String?;

      switch (argName) {
        case 'domain':
          // 从最近请求中提取域名建议
          final recentDomains = McpBridge().getRecentRequests(limit: 50)
              .map((r) {
                try {
                  return Uri.parse(r.requestUrl).host;
                } catch (_) {
                  return null;
                }
              })
              .where((h) => h != null && h!.isNotEmpty)
              .toSet()
              .take(10);
          for (var domain in recentDomains) {
            completions.add({'value': domain!, 'description': 'Recent domain'});
          }
          break;

        case 'method':
          final methods = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS'];
          for (var method in methods) {
            if (argValue == null || method.startsWith(argValue)) {
              completions.add({'value': method, 'description': 'HTTP method'});
            }
          }
          break;

        case 'url_pattern':
          // 从最近请求中提取 URL 模式建议
          final recentUrls = McpBridge().getRecentRequests(limit: 20)
              .map((r) => r.requestUrl)
              .toSet()
              .take(10);
          for (var url in recentUrls) {
            completions.add({'value': url, 'description': 'Recent URL'});
          }
          break;
      }
    }

    return {
      'completion': {
        'values': completions.map((c) => c['value'] as String).toList(),
        'total': completions.length,
        'hasMore': completions.length > 10,
      },
      'details': completions,
    };
  }

  List<Map<String, dynamic>> _getToolsList() {
    return [
      {
        'name': 'set_config',
        'description':
            'Update ProxyPin configuration (System Proxy, SSL Capture).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'system_proxy': {
              'type': 'boolean',
              'description': 'Enable/Disable system proxy',
            },
            'ssl_capture': {
              'type': 'boolean',
              'description': 'Enable/Disable SSL capture (MITM)',
            },
          },
        },
      },
      {
        'name': 'add_host_mapping',
        'description': 'Add a domain mapping (like hosts file).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'domain': {
              'type': 'string',
              'description': 'Domain name (e.g. example.com)',
            },
            'ip': {
              'type': 'string',
              'description': 'Target IP or domain (e.g. 127.0.0.1)',
            },
          },
          'required': ['domain', 'ip'],
        },
      },
      {
        'name': 'add_response_rewrite',
        'description':
            'Mock/Rewrite response (headers, status code, or body) for a specific URL.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'url_pattern': {
              'type': 'string',
              'description': 'URL pattern to match (e.g. "api.com/users")',
            },
            'rewrite_type': {
              'type': 'string',
              'description': 'Type: updateHeader, updateStatusCode, updateBody',
              'enum': ['updateHeader', 'updateStatusCode', 'updateBody'],
            },
            'key': {
              'type': 'string',
              'description':
                  'Header name (for updateHeader) or "body" for body replacement',
            },
            'value': {
              'type': 'string',
              'description':
                  'New value (header value, status code, or body content)',
            },
          },
          'required': ['url_pattern', 'rewrite_type', 'value'],
        },
      },
      {
        'name': 'export_har',
        'description': 'Export captured requests to HAR (HTTP Archive) format.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'limit': {
              'type': 'integer',
              'description': 'Max requests to export (default 100)',
            },
            'request_ids': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'Specific request IDs to export',
            },
          },
        },
      },
      {
        'name': 'import_har',
        'description': 'Import HAR (HTTP Archive) data into ProxyPin session.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'har_content': {
              'type': 'string',
              'description': 'HAR JSON content string',
            },
          },
          'required': ['har_content'],
        },
      },
      {
        'name': 'search_requests',
        'description':
            'Search and filter captured HTTP requests with powerful filters.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': 'Keyword in URL'},
            'method': {
              'type': 'string',
              'description': 'HTTP Method (GET, POST...)',
            },
            'status_code': {
              'type': 'string',
              'description': 'Status code pattern (e.g. "200", "4xx", "5xx")',
            },
            'domain': {'type': 'string', 'description': 'Domain name filter'},
            'header_search': {
              'type': 'string',
              'description':
                  'Search in request/response headers (key or value)',
            },
            'request_body_search': {
              'type': 'string',
              'description': 'Search in request body',
            },
            'response_body_search': {
              'type': 'string',
              'description': 'Search in response body',
            },
            'min_duration': {
              'type': 'integer',
              'description': 'Minimum duration in ms',
            },
            'max_duration': {
              'type': 'integer',
              'description': 'Maximum duration in ms',
            },
            'limit': {
              'type': 'integer',
              'description': 'Max results (default 20)',
            },
          },
        },
      },
      {
        'name': 'generate_code',
        'description':
            'Generate code for a specific request in Python, JavaScript, Go, Node.js, or cURL.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description': 'The ID of the request',
            },
            'language': {
              'type': 'string',
              'description': 'Target language: python, js, go, nodejs, curl',
              'enum': ['python', 'js', 'go', 'nodejs', 'curl'],
            },
          },
          'required': ['request_id', 'language'],
        },
      },
      {
        'name': 'get_curl',
        'description': 'Generate cURL command for a specific request.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description': 'The ID of the request',
            },
          },
          'required': ['request_id'],
        },
      },
      {
        'name': 'get_recent_requests',
        'description':
            'Get a list of recent HTTP requests (Legacy, use search_requests instead).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'limit': {
              'type': 'integer',
              'description': 'Max number of requests (default 20)',
            },
            'url_filter': {
              'type': 'string',
              'description': 'Filter by URL keyword',
            },
            'method': {
              'type': 'string',
              'description': 'Filter by HTTP Method (GET, POST...)',
            },
          },
        },
      },
      {
        'name': 'get_request_details',
        'description':
            '''Get full details (headers, body) of a specific request.

Response includes:
- request.body: Request body content
- request.bodySize: Body size in bytes
- request.bodyEncoding: Encoding type ('utf8', 'base64', or 'none')
- response.body: Response body content
- response.bodySize: Body size in bytes
- response.bodyEncoding: Encoding type ('utf8', 'base64', or 'none')

Body Encoding Rules:
- bodyEncoding='utf8': Text data (JSON, HTML, XML, etc.), use directly
- bodyEncoding='base64': Binary data (images, files, etc.), decode with base64.b64decode() in Python
- bodyEncoding='none': Empty body''',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description': 'The ID of the request',
            },
          },
          'required': ['request_id'],
        },
      },
      {
        'name': 'start_proxy',
        'description': 'Start the ProxyPin server on a specific port.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'port': {
              'type': 'integer',
              'description': 'Port number (default 9099)',
            },
          },
        },
      },
      {
        'name': 'stop_proxy',
        'description': 'Stop the ProxyPin server.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'get_proxy_status',
        'description': 'Get current status of the proxy server.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'clear_requests',
        'description':
            'Clear all captured requests (session history and UI list).',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'replay_request',
        'description': 'Replay/resend a captured HTTP request.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description': 'The ID of the request to replay',
            },
          },
          'required': ['request_id'],
        },
      },
      {
        'name': 'block_url',
        'description': 'Block requests or responses matching a URL pattern.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'url_pattern': {
              'type': 'string',
              'description': 'URL pattern to block (supports wildcard *)',
            },
            'block_type': {
              'type': 'string',
              'description': 'Type: blockRequest or blockResponse',
              'enum': ['blockRequest', 'blockResponse'],
            },
          },
          'required': ['url_pattern', 'block_type'],
        },
      },
      {
        'name': 'add_request_rewrite',
        'description':
            'Add a request rewrite rule (modify headers, query params, or body).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'url_pattern': {
              'type': 'string',
              'description': 'URL pattern to match',
            },
            'rewrite_type': {
              'type': 'string',
              'description': 'Type: updateHeader, updateQueryParam, updateBody',
              'enum': ['updateHeader', 'updateQueryParam', 'updateBody'],
            },
            'key': {
              'type': 'string',
              'description':
                  'Header name, query param name, or "body" for body replacement',
            },
            'value': {'type': 'string', 'description': 'New value'},
          },
          'required': ['url_pattern', 'rewrite_type', 'key', 'value'],
        },
      },
      {
        'name': 'update_script',
        'description':
            'Update or create a JavaScript script for request/response modification.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'description': 'Script name'},
            'url_pattern': {
              'type': 'string',
              'description': 'URL pattern to match (supports wildcard *)',
            },
            'script_content': {
              'type': 'string',
              'description': 'JavaScript code (onRequest/onResponse functions)',
            },
          },
          'required': ['name', 'url_pattern', 'script_content'],
        },
      },
      {
        'name': 'get_scripts',
        'description': 'Get all configured scripts.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'get_statistics',
        'description':
            'Get statistics of captured requests (methods, status codes, domains, etc.).',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'compare_requests',
        'description':
            'Compare two requests side by side (useful for debugging API changes).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id_1': {
              'type': 'string',
              'description': 'First request ID',
            },
            'request_id_2': {
              'type': 'string',
              'description': 'Second request ID',
            },
          },
          'required': ['request_id_1', 'request_id_2'],
        },
      },
      {
        'name': 'find_similar_requests',
        'description':
            'Find requests similar to a given request (same URL pattern, method, etc.).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description': 'Reference request ID',
            },
            'limit': {
              'type': 'integer',
              'description': 'Max results (default 10)',
            },
          },
          'required': ['request_id'],
        },
      },
      {
        'name': 'extract_api_endpoints',
        'description':
            'Extract and group unique API endpoints from captured requests.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'domain_filter': {
              'type': 'string',
              'description': 'Filter by domain (optional)',
            },
          },
        },
      },
      // ==================== 安全分析工具（2.x 增强） ====================
      {
        'name': 'analyze_auth',
        'description':
            'Analyze authentication information in requests (Authorization headers, tokens, cookies, API keys).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description':
                  'Specific request ID (optional, defaults to recent 100)',
            },
          },
        },
      },
      {
        'name': 'find_sensitive_data',
        'description':
            'Search requests for sensitive data: passwords, API keys, secrets, tokens, private keys, phone numbers, ID cards.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description':
                  'Specific request ID (optional, defaults to recent 100)',
            },
            'search_body': {
              'type': 'boolean',
              'description': 'Search request bodies (default true)',
            },
          },
        },
      },
      {
        'name': 'get_cookie_info',
        'description':
            'Get cookie analysis for a domain or request (names, values, HttpOnly, Secure, domains).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'domain': {
              'type': 'string',
              'description': 'Domain to filter (e.g. example.com)',
            },
            'request_id': {
              'type': 'string',
              'description': 'Specific request ID (overrides domain)',
            },
          },
        },
      },
      {
        'name': 'get_domain_summary',
        'description':
            'Get traffic statistics summary for a domain (methods, status codes, avg duration, error count).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'domain': {
              'type': 'string',
              'description': 'Domain to analyze (required)',
            },
          },
          'required': ['domain'],
        },
      },
      {
        'name': 'calculate_entropy',
        'description':
            'Calculate Shannon entropy of a string (for evaluating randomness / key strength).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'text': {
              'type': 'string',
              'description': 'Text to analyze (required)',
            },
          },
          'required': ['text'],
        },
      },
      // ==================== Breakpoint Debugging Tools (1.3.1+) ====================
      {
        'name': 'add_breakpoint_rule',
        'description':
            'Add a breakpoint rule to intercept requests or responses for debugging. The request will be paused until manually resumed via UI.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'url_pattern': {
              'type': 'string',
              'description':
                  'URL regex pattern to match (e.g. "api.example.com/v1/.*")',
            },
            'name': {'type': 'string', 'description': 'Rule name (optional)'},
            'intercept_request': {
              'type': 'boolean',
              'description': 'Intercept request (default true)',
            },
            'intercept_response': {
              'type': 'boolean',
              'description': 'Intercept response (default true)',
            },
            'method': {
              'type': 'string',
              'description':
                  'HTTP method filter (GET, POST, etc.). Empty = all methods',
              'enum': [
                'GET',
                'POST',
                'PUT',
                'DELETE',
                'PATCH',
                'HEAD',
                'OPTIONS',
              ],
            },
            'enabled': {
              'type': 'boolean',
              'description': 'Enable the rule (default true)',
            },
          },
          'required': ['url_pattern'],
        },
      },
      {
        'name': 'remove_breakpoint_rule',
        'description': 'Remove a breakpoint rule by URL pattern.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'url_pattern': {
              'type': 'string',
              'description': 'URL pattern of the rule to remove',
            },
          },
          'required': ['url_pattern'],
        },
      },
      {
        'name': 'list_breakpoint_rules',
        'description': 'List all breakpoint rules and their status.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'toggle_breakpoint',
        'description':
            'Enable or disable the breakpoint debugging feature globally.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'enabled': {
              'type': 'boolean',
              'description': 'true to enable, false to disable',
            },
          },
          'required': ['enabled'],
        },
      },
      // ==================== Weak Network Simulation Tools (1.3.1+) ====================
      {
        'name': 'add_weak_network_rule',
        'description':
            'Add a weak network simulation rule for a URL pattern. Simulates bandwidth limiting, latency, jitter, packet loss, or offline mode.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'url_pattern': {
              'type': 'string',
              'description': 'URL pattern to match (supports wildcard *)',
            },
            'profile_id': {
              'type': 'string',
              'description':
                  'Preset profile ID. Built-in: weak, slow, g2, g3, g4, g5, wifi. Or use a custom profile ID.',
            },
            'enabled': {
              'type': 'boolean',
              'description': 'Enable this rule (default true)',
            },
          },
          'required': ['url_pattern', 'profile_id'],
        },
      },
      {
        'name': 'add_custom_network_profile',
        'description':
            'Create a custom weak network profile with specific parameters.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'description': 'Profile name'},
            'upload_kbps': {
              'type': 'integer',
              'description':
                  'Upload bandwidth limit in kbps (null = unlimited)',
            },
            'download_kbps': {
              'type': 'integer',
              'description':
                  'Download bandwidth limit in kbps (null = unlimited)',
            },
            'request_latency_ms': {
              'type': 'integer',
              'description': 'Request latency in milliseconds (default 0)',
            },
            'response_latency_ms': {
              'type': 'integer',
              'description': 'Response latency in milliseconds (default 0)',
            },
            'jitter_ms': {
              'type': 'integer',
              'description': 'Jitter in milliseconds (default 0)',
            },
            'loss_rate': {
              'type': 'number',
              'description': 'Packet loss rate 0.0-1.0 (default 0)',
            },
            'offline': {
              'type': 'boolean',
              'description': 'Simulate offline mode (default false)',
            },
          },
          'required': ['name'],
        },
      },
      {
        'name': 'list_weak_network_rules',
        'description': 'List all weak network simulation rules and profiles.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'remove_weak_network_rule',
        'description': 'Remove a weak network rule by URL pattern.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'url_pattern': {
              'type': 'string',
              'description': 'URL pattern of the rule to remove',
            },
          },
          'required': ['url_pattern'],
        },
      },
      {
        'name': 'toggle_weak_network',
        'description':
            'Enable or disable the weak network simulation feature globally.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'enabled': {
              'type': 'boolean',
              'description': 'true to enable, false to disable',
            },
          },
          'required': ['enabled'],
        },
      },
      // ==================== Environment Variable Tools (1.3.1+) ====================
      {
        'name': 'list_environments',
        'description':
            'List all environments and their variables. Shows which environment is currently active.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'set_environment_variable',
        'description':
            'Set or update an environment variable. Variables can be referenced in requests using {{variable_name}} syntax.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'key': {'type': 'string', 'description': 'Variable name'},
            'value': {
              'type': 'string',
              'description': 'Variable value (null to delete)',
            },
            'environment_id': {
              'type': 'string',
              'description':
                  'Target environment ID (default: global or active environment)',
            },
            'enabled': {
              'type': 'boolean',
              'description': 'Enable the variable (default true)',
            },
          },
          'required': ['key'],
        },
      },
      {
        'name': 'create_environment',
        'description':
            'Create a new named environment (e.g. Dev, Staging, Prod).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'description': 'Environment name'},
          },
          'required': ['name'],
        },
      },
      {
        'name': 'set_active_environment',
        'description':
            'Set the active environment by ID, or pass null to deactivate (only Global remains).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'environment_id': {
              'type': 'string',
              'description':
                  'Environment ID to activate, or empty string to deactivate',
            },
          },
        },
      },
      {
        'name': 'remove_environment',
        'description':
            'Remove a named environment by ID. Cannot remove the Global environment.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'environment_id': {
              'type': 'string',
              'description': 'Environment ID to remove',
            },
          },
          'required': ['environment_id'],
        },
      },
      {
        'name': 'toggle_environment_variables',
        'description':
            'Enable or disable the environment variable feature globally.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'enabled': {
              'type': 'boolean',
              'description': 'true to enable, false to disable',
            },
          },
          'required': ['enabled'],
        },
      },
      // ==================== Device Control Tools (Android only) ====================
      {
        'name': 'get_device_info',
        'description':
            'Get Android device info (model, brand, Android version, WiFi IP, root/accessibility status).',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'get_current_activity',
        'description': 'Get the current foreground activity/package name.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'dump_ui',
        'description':
            'Dump the current Android UI hierarchy as JSON array of elements.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'clickable_only': {
              'type': 'boolean',
              'description': 'Only include clickable elements (default false)',
            },
            'package_filter': {
              'type': 'string',
              'description': 'Filter by package name',
            },
          },
        },
      },
      {
        'name': 'tap_screen',
        'description': 'Perform a tap at the given screen coordinates.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'x': {'type': 'integer', 'description': 'X coordinate'},
            'y': {'type': 'integer', 'description': 'Y coordinate'},
          },
          'required': ['x', 'y'],
        },
      },
      {
        'name': 'long_press',
        'description':
            'Perform a long press at the given coordinates for a duration.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'x': {'type': 'integer', 'description': 'X coordinate'},
            'y': {'type': 'integer', 'description': 'Y coordinate'},
            'duration': {
              'type': 'integer',
              'description': 'Press duration in ms (default 50)',
            },
          },
          'required': ['x', 'y'],
        },
      },
      {
        'name': 'swipe_screen',
        'description': 'Perform a swipe gesture from one point to another.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'x1': {'type': 'integer', 'description': 'Start X'},
            'y1': {'type': 'integer', 'description': 'Start Y'},
            'x2': {'type': 'integer', 'description': 'End X'},
            'y2': {'type': 'integer', 'description': 'End Y'},
            'duration': {
              'type': 'integer',
              'description': 'Swipe duration in ms (default 300)',
            },
          },
          'required': ['x1', 'y1', 'x2', 'y2'],
        },
      },
      {
        'name': 'key_event',
        'description':
            'Send a key event. Keycodes: 3=HOME, 4=BACK, 26=POWER, 82=MENU, 187=RECENTS.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'keycode': {
              'type': 'integer',
              'description':
                  'Android keycode (3=HOME, 4=BACK, 26=POWER, 82=MENU, 187=RECENTS)',
            },
          },
          'required': ['keycode'],
        },
      },
      {
        'name': 'input_text',
        'description': 'Set text on the currently focused input element.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'text': {'type': 'string', 'description': 'Text to input'},
          },
          'required': ['text'],
        },
      },
      {
        'name': 'screenshot',
        'description':
            'Take a screenshot and return as Base64 PNG (requires root).',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'open_accessibility_settings',
        'description': 'Open the Android accessibility settings page.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'shell',
        'description':
            'Execute a shell command on the device (optionally with root, Shizuku or Dhizuku).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'command': {
              'type': 'string',
              'description': 'Shell command to execute',
            },
            'use_su': {
              'type': 'boolean',
              'description': 'Use root (su) for execution (default false)',
            },
            'mode': {
              'type': 'string',
              'enum': ['auto', 'root', 'shizuku', 'dhizuku'],
              'description':
                  'Permission mode: root=su, shizuku=Shizuku service, dhizuku=Dhizuku device owner, auto=pick best available (default auto)',
            },
            'timeout_ms': {
              'type': 'integer',
              'description': 'Timeout in milliseconds (default 10000)',
            },
          },
          'required': ['command'],
        },
      },
      {
        'name': 'get_pending_intercepts',
        'description':
            'Get all requests/responses currently paused by breakpoint interception.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'approve_intercept',
        'description':
            'Approve (release) a paused intercept. Optionally modify the request before releasing.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description': 'ID of the paused intercept',
            },
            'modifier': {
              'type': 'object',
              'description':
                  'Optional request modifications: method, url, headers, body',
              'properties': {
                'method': {'type': 'string'},
                'url': {'type': 'string'},
                'headers': {'type': 'object'},
                'body': {'type': 'string'},
              },
            },
          },
          'required': ['request_id'],
        },
      },
      {
        'name': 'reject_intercept',
        'description':
            'Reject a paused intercept. Request is aborted, response is dropped.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'request_id': {
              'type': 'string',
              'description': 'ID of the paused intercept',
            },
            'reason': {
              'type': 'string',
              'description': 'Rejection reason (optional)',
            },
          },
          'required': ['request_id'],
        },
      },
      // ==================== WebSocket Message Tools (v1.6.0+) ====================
      {
        'name': 'get_paused_websocket_messages',
        'description': 'Get all WebSocket messages currently paused by interception.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'resume_websocket_message',
        'description': 'Resume (release) a paused WebSocket message. Optionally modify the payload before releasing.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'frame_id': {
              'type': 'string',
              'description': 'ID of the paused WebSocket frame',
            },
            'payload': {
              'type': 'string',
              'description': 'Optional modified payload (text messages only)',
            },
          },
          'required': ['frame_id'],
        },
      },
      {
        'name': 'abort_websocket_message',
        'description': 'Abort a paused WebSocket message. The message will be dropped.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'frame_id': {
              'type': 'string',
              'description': 'ID of the paused WebSocket frame',
            },
            'reason': {
              'type': 'string',
              'description': 'Abort reason (optional)',
            },
          },
          'required': ['frame_id'],
        },
      },    ];
  }

  Future<dynamic> _executeTool(String name, Map<String, dynamic> args) async {
    // 工具启用检查：被禁用的工具返回错误，不执行
    if (!_isToolEnabled(name)) {
      return {
        'error':
            'Tool is disabled: $name. Enable it in the MCP settings page first.',
      };
    }
    switch (name) {
      case 'set_config':
        var config = await Configuration.instance;
        var changed = false;

        if (args.containsKey('system_proxy')) {
          bool enable = args['system_proxy'];
          config.enableSystemProxy = enable;
          if (ProxyServer.current?.isRunning == true) {
            if (Platforms.isDesktop()) {
              // 桌面端：直接调用 setSystemProxyEnable
              await ProxyServer.current?.setSystemProxyEnable(enable);
            } else if (Vpn.isVpnStarted) {
              // 移动端：VPN 运行时需要重启 VPN 以应用新的 system_proxy 设置
              Vpn.restartVpn("127.0.0.1", ProxyServer.current!.port, config);
            }
          }
          changed = true;
        }

        if (args.containsKey('ssl_capture')) {
          bool enable = args['ssl_capture'];
          config.enableSsl = enable;
          ProxyServer.current?.enableSsl = enable;
          changed = true;
        }

        if (changed) await config.flushConfig();
        return {
          'status': 'success',
          'system_proxy': config.enableSystemProxy,
          'ssl_capture': config.enableSsl,
        };

      case 'add_host_mapping':
        final domain = args['domain'];
        final ip = args['ip'];
        var hostsManager = await HostsManager.instance;
        await hostsManager.addHosts(
          HostsItem(host: domain, toAddress: ip, enabled: true),
        );
        await hostsManager.flushConfig();
        return {
          'status': 'success',
          'message': 'Added host mapping: $domain -> $ip',
        };

      case 'add_response_rewrite':
        final urlPattern = args['url_pattern'];
        final rewriteTypeStr = args['rewrite_type'] ?? 'updateBody';
        final key = args['key'];
        final value = args['value'];

        try {
          var manager = await RequestRewriteManager.instance;

          RewriteItem item;
          RuleType ruleType;

          if (rewriteTypeStr == 'updateHeader') {
            // updateHeader 属于修改类型，应使用 responseUpdate
            ruleType = RuleType.responseUpdate;
            item = RewriteItem(RewriteType.updateHeader, true)
              ..key = key
              ..value = value;
          } else if (rewriteTypeStr == 'updateStatusCode') {
            // replaceResponseStatus 属于替换类型，使用 responseReplace
            ruleType = RuleType.responseReplace;
            item = RewriteItem(RewriteType.replaceResponseStatus, true)
              ..statusCode = int.tryParse(value) ?? 200;
          } else {
            // updateBody -> replaceResponseBody 属于替换类型，使用 responseReplace
            ruleType = RuleType.responseReplace;
            item = RewriteItem(RewriteType.replaceResponseBody, true)
              ..body = value;
          }

          var rule = RequestRewriteRule(
            type: ruleType,
            url: urlPattern,
            name: 'MCP: Response $rewriteTypeStr for $urlPattern',
          );

          await manager.addRule(rule, [item]);
          await manager.flushRequestRewriteConfig();
          return {
            'status': 'success',
            'message': 'Added response rewrite rule for $urlPattern',
          };
        } catch (e) {
          return {'error': 'Failed to add response rewrite rule: $e'};
        }

      case 'export_har':
        final limit = (args['limit'] as num?)?.toInt() ?? 100;
        final requestIds = args['request_ids'];

        var list = McpBridge().source;
        if (requestIds != null) {
          list = list.where((r) => requestIds.contains(r.requestId)).toList();
        } else {
          // 默认导出最近的
          list = list.reversed.take(limit).toList();
        }

        return _generateHar(list);

      case 'import_har':
        final content = args['har_content'];
        try {
          var json = jsonDecode(content);
          var entries = json['log']['entries'] as List;
          int count = 0;
          for (var entry in entries) {
            var req = _parseHarEntry(entry);
            if (req != null) {
              McpBridge().addRequest(req);
              count++;
            }
          }
          return {'status': 'success', 'imported_count': count};
        } catch (e) {
          return {'error': 'Failed to import HAR: $e'};
        }

      case 'search_requests':
        final limit = (args['limit'] as num?)?.toInt() ?? 20;
        final query = args['query'] as String?;
        final method = args['method'] as String?;
        final statusCode = args['status_code'] as String?;
        final domain = args['domain'] as String?;
        final headerSearch = args['header_search'] as String?;
        final requestBodySearch = args['request_body_search'] as String?;
        final responseBodySearch = args['response_body_search'] as String?;
        final minDuration = (args['min_duration'] as num?)?.toInt();
        final maxDuration = (args['max_duration'] as num?)?.toInt();

        try {
          // 委托给 McpBridge 的增强过滤方法
          var list = McpBridge().getRecentRequests(
            limit: limit,
            urlFilter: query,
            method: method,
            statusCode: statusCode,
            domain: domain,
            headerSearch: headerSearch,
            requestBodySearch: requestBodySearch,
            responseBodySearch: responseBodySearch,
            minDuration: minDuration,
            maxDuration: maxDuration,
          );

          return list
              .map(
                (r) => {
                  'id': r.requestId,
                  'url': r.requestUrl,
                  'method': r.method.name,
                  'statusCode': r.response?.status.code,
                  'contentType': r.response?.headers.contentType,
                  'timestamp': r.requestTime.toIso8601String(),
                  'duration': r.response != null
                      ? r.response!.responseTime
                            .difference(r.requestTime)
                            .inMilliseconds
                      : 0,
                },
              )
              .toList();
        } catch (e) {
          return {'error': 'Failed to search requests: $e'};
        }

      case 'generate_code':
        final id = args['request_id'];
        final lang = args['language'];

        try {
          var req = McpBridge().source.firstWhere((r) => r.requestId == id);
          String code;
          if (lang == 'python') {
            code = _generatePythonCode(req);
          } else if (lang == 'js' || lang == 'javascript') {
            code = _generateJsCode(req);
          } else if (lang == 'go' || lang == 'golang') {
            code = _generateGoCode(req);
          } else if (lang == 'node' || lang == 'nodejs') {
            code = _generateNodeJsCode(req);
          } else {
            code = _generateCurl(req);
          }
          return {'code': code, 'language': lang};
        } catch (e) {
          return {'error': 'Request not found or generation failed: $e'};
        }

      case 'get_curl':
        final id = args['request_id'];
        try {
          var req = McpBridge().source.firstWhere((r) => r.requestId == id);
          return {'curl': _generateCurl(req)};
        } catch (e) {
          return {'error': 'Request not found'};
        }

      case 'get_request_details':
        final id = args['request_id'];

        final req = McpBridge().getRequestById(id);
        if (req == null) return {'error': 'Request not found'};

        return McpBridge.requestToJson(req, includeBody: true);

      case 'start_proxy':
        int port = (args['port'] as num?)?.toInt() ?? 9099;
        var config = await Configuration.instance;
        config.port = port;
        if (ProxyServer.current?.isRunning == true) {
          await ProxyServer.current?.stop();
        }
        var server = ProxyServer(config);
        // 重新注册 McpBridge 监听器，确保代理重启后仍能接收流量事件
        server.addListener(McpBridge());
        await server.start();
        return {'status': 'started', 'port': port};

      case 'stop_proxy':
        await ProxyServer.current?.stop();
        return {'status': 'stopped'};

      case 'get_proxy_status':
        final isRunning = ProxyServer.current?.isRunning ?? false;
        final port = ProxyServer.current?.port;
        return {'isRunning': isRunning, 'port': port};

      case 'clear_requests':
        // 调用真正的清除方法（对应UI垃圾桶图标）
        final success = McpBridge().clearWithUI();
        if (success) {
          return {
            'status': 'cleared',
            'message': 'All requests cleared (UI and storage)',
          };
        } else {
          // 降级方案：只清空内存容器
          McpBridge().clear();
          return {
            'status': 'cleared',
            'message': 'Requests cleared from memory only',
          };
        }

      case 'replay_request':
        final id = args['request_id'];
        try {
          var req = McpBridge().source.firstWhere((r) => r.requestId == id);

          var startTime = DateTime.now();
          var response = await HttpClients.proxyRequest(
            req,
            timeout: const Duration(seconds: 30),
          );

          return {
            'status': 'success',
            'response': {
              'statusCode': response.status.code,
              'statusText': response.status.reasonPhrase,
              'headers': response.headers.toMap(),
              'body': response.bodyAsString,
              'duration': response.responseTime
                  .difference(startTime)
                  .inMilliseconds,
            },
          };
        } catch (e) {
          return {'error': 'Failed to replay request: $e'};
        }

      case 'block_url':
        final urlPattern = args['url_pattern'];
        final blockTypeStr = args['block_type'];

        try {
          var manager = await RequestBlockManager.instance;
          var blockType = BlockType.nameOf(blockTypeStr);
          var item = RequestBlockItem(true, urlPattern, blockType);
          manager.addBlockRequest(item);
          return {
            'status': 'success',
            'message': 'Added block rule for $urlPattern',
          };
        } catch (e) {
          return {'error': 'Failed to add block rule: $e'};
        }

      case 'add_request_rewrite':
        final urlPattern = args['url_pattern'];
        final rewriteTypeStr = args['rewrite_type'];
        final key = args['key'];
        final value = args['value'];

        try {
          var manager = await RequestRewriteManager.instance;

          RewriteItem item;
          RuleType ruleType;

          if (rewriteTypeStr == 'updateHeader') {
            // updateHeader 属于修改类型，使用 requestUpdate
            ruleType = RuleType.requestUpdate;
            item = RewriteItem(RewriteType.updateHeader, true)
              ..key = key
              ..value = value;
          } else if (rewriteTypeStr == 'updateQueryParam') {
            // updateQueryParam 属于修改类型，使用 requestUpdate
            ruleType = RuleType.requestUpdate;
            item = RewriteItem(RewriteType.updateQueryParam, true)
              ..key = key
              ..value = value;
          } else {
            // updateBody -> replaceRequestBody 属于替换类型，使用 requestReplace
            ruleType = RuleType.requestReplace;
            item = RewriteItem(RewriteType.replaceRequestBody, true)
              ..body = value;
          }

          var rule = RequestRewriteRule(
            type: ruleType,
            url: urlPattern,
            name: 'MCP: $rewriteTypeStr $key',
          );

          await manager.addRule(rule, [item]);
          await manager.flushRequestRewriteConfig();
          return {
            'status': 'success',
            'message': 'Added request rewrite rule for $urlPattern',
          };
        } catch (e) {
          return {'error': 'Failed to add request rewrite rule: $e'};
        }

      case 'update_script':
        final name = args['name'];
        final urlPattern = args['url_pattern'];
        final scriptContent = args['script_content'];

        try {
          var manager = await ScriptManager.instance;

          var existingIndex = manager.list.indexWhere((s) => s.name == name);

          if (existingIndex >= 0) {
            var item = manager.list[existingIndex];
            item.urls = [urlPattern];
            item.urlRegs = null;
            await manager.updateScript(item, scriptContent);
            await manager.flushConfig();
            return {'status': 'success', 'message': 'Updated script: $name'};
          } else {
            var item = ScriptItem(true, name, [urlPattern]);
            await manager.addScript(item, scriptContent);
            await manager.flushConfig();
            return {'status': 'success', 'message': 'Created script: $name'};
          }
        } catch (e) {
          return {'error': 'Failed to update script: $e'};
        }

      case 'get_scripts':
        try {
          var manager = await ScriptManager.instance;
          var scripts = manager.list
              .map(
                (s) => {
                  'name': s.name,
                  'enabled': s.enabled,
                  'urls': s.urls,
                  'scriptPath': s.scriptPath,
                },
              )
              .toList();
          return {'scripts': scripts, 'enabled': manager.enabled};
        } catch (e) {
          return {'error': 'Failed to get scripts: $e'};
        }

      case 'get_recent_requests':
        final limit = (args['limit'] as num?)?.toInt() ?? 20;
        final urlFilter = args['url_filter'] as String?;
        final method = args['method'] as String?;

        final requests = McpBridge().getRecentRequests(
          limit: limit,
          urlFilter: urlFilter,
          method: method,
        );

        return requests.map((r) => McpBridge.requestToJson(r)).toList();

      case 'get_statistics':
        return McpBridge().getStatistics();

      case 'compare_requests':
        final id1 = args['request_id_1'];
        final id2 = args['request_id_2'];

        final req1 = McpBridge().getRequestById(id1);
        final req2 = McpBridge().getRequestById(id2);

        if (req1 == null) return {'error': 'Request 1 not found'};
        if (req2 == null) return {'error': 'Request 2 not found'};

        // Header 差异对比
        var reqHeaders1 = req1.headers.toMap();
        var reqHeaders2 = req2.headers.toMap();
        var respHeaders1 = req1.response?.headers.toMap() ?? {};
        var respHeaders2 = req2.response?.headers.toMap() ?? {};

        var headerDiff = _compareHeaders(reqHeaders1, reqHeaders2);
        var respHeaderDiff = _compareHeaders(respHeaders1, respHeaders2);

        // Body 差异对比（如果是 JSON）
        var bodyDiff = _compareBody(req1.bodyAsString, req2.bodyAsString);
        var respBodyDiff = _compareBody(
          req1.response?.bodyAsString ?? '',
          req2.response?.bodyAsString ?? '',
        );

        return {
          'request_1': McpBridge.requestToJson(req1, includeBody: true),
          'request_2': McpBridge.requestToJson(req2, includeBody: true),
          'comparison': {
            'same_url': req1.requestUrl == req2.requestUrl,
            'same_method': req1.method == req2.method,
            'same_status':
                req1.response?.status.code == req2.response?.status.code,
            'duration_diff':
                (req1.response?.responseTime
                        .difference(req1.requestTime)
                        .inMilliseconds ??
                    0) -
                (req2.response?.responseTime
                        .difference(req2.requestTime)
                        .inMilliseconds ??
                    0),
            'request_header_diff': headerDiff,
            'response_header_diff': respHeaderDiff,
            'request_body_diff': bodyDiff,
            'response_body_diff': respBodyDiff,
          },
        };

      case 'find_similar_requests':
        final refId = args['request_id'] as String;
        final limit = (args['limit'] as num?)?.toInt() ?? 10;

        final refReq = McpBridge().getRequestById(refId);
        if (refReq == null) return {'error': 'Reference request not found'};

        try {
          var refUri = Uri.parse(refReq.requestUrl);
          var refPath = refUri.path;

          // 查找相似的请求（相同路径模式和方法）
          var similar = McpBridge().source
              .where((req) {
                if (req.requestId == refId) return false; // 排除自己
                if (req.method != refReq.method) return false; // 方法必须相同

                try {
                  var uri = Uri.parse(req.requestUrl);
                  // 相同域名和路径
                  return uri.host == refUri.host && uri.path == refPath;
                } catch (e) {
                  return false;
                }
              })
              .take(limit)
              .toList();

          return {
            'reference': McpBridge.requestToJson(refReq),
            'similar_requests': similar
                .map((r) => McpBridge.requestToJson(r))
                .toList(),
            'count': similar.length,
          };
        } catch (e) {
          return {'error': 'Failed to find similar requests: $e'};
        }

      case 'extract_api_endpoints':
        final domainFilter = args['domain_filter'];

        try {
          var requests = McpBridge().source;
          var endpoints = <String, ApiEndpoint>{};

          for (var req in requests) {
            try {
              var uri = Uri.parse(req.requestUrl);

              // 域名过滤
              if (domainFilter != null && !uri.host.contains(domainFilter)) {
                continue;
              }

              var key = '${req.method.name} ${uri.host}${uri.path}';

              if (!endpoints.containsKey(key)) {
                endpoints[key] = ApiEndpoint(
                  req.method.name,
                  uri.host,
                  uri.path,
                );
              }

              endpoints[key]!.addRequest(req);
            } catch (e) {
              // 忽略解析失败的 URL
            }
          }

          // 转换为列表并按请求数量排序
          var result = endpoints.values.toList();
          result.sort((a, b) => b.count.compareTo(a.count));

          return {
            'endpoints': result.map((e) => e.toJson()).toList(),
            'total_unique': result.length,
          };
        } catch (e) {
          return {'error': 'Failed to extract endpoints: $e'};
        }

      // ==================== 安全分析工具（2.x 增强） ====================
      case 'analyze_auth':
        // 分析请求中的认证信息（Authorization 头、Cookie、Token、ApiKey）
        try {
          final requestId = args['request_id'] as String?;
          final requests = requestId != null
              ? McpBridge().source
                    .where((r) => r.requestId == requestId)
                    .toList()
              : McpBridge().source.take(100).toList();

          final findings = <Map<String, dynamic>>[];
          for (var req in requests) {
            var authHeader = req.headers.get('authorization');
            if (authHeader != null && authHeader.isNotEmpty) {
              findings.add({
                'type': 'authorization_header',
                'request_id': req.requestId,
                'url': req.requestUrl,
                'scheme': authHeader.split(' ').first,
                'preview': authHeader.length > 40
                    ? '${authHeader.substring(0, 40)}...'
                    : authHeader,
              });
            }

            // 常见 Token 头
            for (var header in [
              'x-api-key',
              'api-key',
              'x-token',
              'token',
              'x-access-token',
              'x-auth-token',
            ]) {
              var val = req.headers.get(header);
              if (val != null && val.isNotEmpty) {
                findings.add({
                  'type': 'token_header',
                  'request_id': req.requestId,
                  'url': req.requestUrl,
                  'header': header,
                  'preview': val.length > 40
                      ? '${val.substring(0, 40)}...'
                      : val,
                });
              }
            }

            // URL 中的 token 参数
            try {
              var uri = Uri.parse(req.requestUrl);
              for (var param in [
                'token',
                'access_token',
                'api_key',
                'apikey',
                'sign',
                'sig',
              ]) {
                if (uri.queryParameters.containsKey(param)) {
                  var val = uri.queryParameters[param]!;
                  findings.add({
                    'type': 'url_query_token',
                    'request_id': req.requestId,
                    'url': req.requestUrl,
                    'param': param,
                    'preview': val.length > 40
                        ? '${val.substring(0, 40)}...'
                        : val,
                  });
                }
              }
            } catch (e, st) {
              // URL 解析失败时静默忽略（可能是无效 URL）
              debugPrint('[MCP Security] URL parse error: $e\n$st');
            }

            // Cookie 中的会话标识
            var cookieHeader = req.headers.get('cookie');
            if (cookieHeader != null && cookieHeader.isNotEmpty) {
              var cookies = _parseCookies(cookieHeader);
              for (var c in cookies) {
                var name = (c['name'] ?? '').toLowerCase();
                if (name.contains('session') ||
                    name.contains('token') ||
                    name.contains('auth') ||
                    name.contains('jwt')) {
                  findings.add({
                    'type': 'cookie',
                    'request_id': req.requestId,
                    'url': req.requestUrl,
                    'cookie_name': c['name'],
                    'preview': (c['value'] ?? '').length > 40
                        ? '${c['value']!.substring(0, 40)}...'
                        : c['value'],
                  });
                }
              }
            }
          }

          return {
            'count': findings.length,
            'requests_scanned': requestId != null ? 1 : requests.length,
            'findings': findings,
            'warning': 'Sensitive credentials detected. Handle with care.',
          };
        } catch (e) {
          return {'error': 'Failed to analyze auth: $e'};
        }

      case 'find_sensitive_data':
        // 在请求/响应中搜索敏感数据（密钥、密码、手机号、身份证等）
        try {
          final requestId = args['request_id'] as String?;
          final searchBody = args['search_body'] as bool? ?? true;
          final requests = requestId != null
              ? McpBridge().source
                    .where((r) => r.requestId == requestId)
                    .toList()
              : McpBridge().source.take(100).toList();

          // 敏感模式列表（非 raw 字符串，正则中 \\ 表示 \）
          final patterns = <Map<String, String>>[
            {
              'name': 'password',
              'regex':
                  "(?i)(password|passwd|pwd)\\s*[=:]\\s*[\"']?([^\"'&\\s,;]{4,})",
            },
            {
              'name': 'api_key',
              'regex':
                  "(?i)(api[_-]?key|apikey)\\s*[=:]\\s*[\"']?([^\"'&\\s,;]{8,})",
            },
            {
              'name': 'secret',
              'regex':
                  "(?i)(secret|client[_-]?secret)\\s*[=:]\\s*[\"']?([^\"'&\\s,;]{8,})",
            },
            {
              'name': 'token',
              'regex':
                  "(?i)(access[_-]?token|auth[_-]?token|bearer)\\s*[=:]\\s*[\"']?([^\"'&\\s,;]{8,})",
            },
            {
              'name': 'private_key',
              'regex': '-----BEGIN [A-Z ]*PRIVATE KEY-----',
            },
            {'name': 'phone', 'regex': r'(?<!\d)1[3-9]\d{9}(?!\d)'},
            {
              'name': 'id_card',
              'regex':
                  r'(?<!\d)[1-9]\d{5}(?:18|19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\d{3}[\dXx](?!\d)',
            },
            {
              'name': 'email',
              'regex': r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
            },
          ];

          final findings = <Map<String, dynamic>>[];
          for (var req in requests) {
            // 请求头
            req.headers.forEach((key, values) {
              for (var v in values) {
                for (var p in patterns) {
                  try {
                    var re = RegExp(p['regex']!);
                    if (re.hasMatch('$key: $v')) {
                      findings.add({
                        'type': p['name'],
                        'location': 'request_header',
                        'request_id': req.requestId,
                        'url': req.requestUrl,
                        'detail':
                            '$key: ${v.length > 60 ? v.substring(0, 60) : v}',
                      });
                    }
                  } catch (e, st) {
                    // 正则表达式无效时静默忽略
                    debugPrint('[MCP Security] Header regex error: $e\n$st');
                  }
                }
              }
            });

            // 请求体
            if (searchBody) {
              var body = req.bodyAsString;
              if (body.isNotEmpty) {
                for (var p in patterns) {
                  try {
                    var re = RegExp(p['regex']!);
                    var match = re.firstMatch(body);
                    if (match != null) {
                      findings.add({
                        'type': p['name'],
                        'location': 'request_body',
                        'request_id': req.requestId,
                        'url': req.requestUrl,
                        'detail': match.group(0)!.length > 80
                            ? match.group(0)!.substring(0, 80)
                            : match.group(0),
                      });
                    }
                  } catch (e, st) {
                    // 正则表达式无效时静默忽略
                    debugPrint('[MCP Security] Body regex error: $e\n$st');
                  }
                }
              }
            }
          }

          return {
            'count': findings.length,
            'requests_scanned': requestId != null ? 1 : requests.length,
            'findings': findings,
          };
        } catch (e) {
          return {'error': 'Failed to find sensitive data: $e'};
        }

      case 'get_cookie_info':
        // 分析某个域的 Cookie（名称、值、过期时间、HttpOnly 等）
        try {
          final domain = args['domain'] as String?;
          final requestId = args['request_id'] as String?;

          var requests = McpBridge().source;
          if (requestId != null) {
            requests = requests.where((r) => r.requestId == requestId).toList();
          } else if (domain != null) {
            requests = requests.where((r) {
              try {
                return Uri.parse(r.requestUrl).host.contains(domain);
              } catch (_) {
                return false;
              }
            }).toList();
          }

          final cookieMap = <String, Map<String, dynamic>>{};
          for (var req in requests.take(500)) {
            var cookieHeader = req.headers.get('cookie');
            if (cookieHeader != null && cookieHeader.isNotEmpty) {
              for (var c in _parseCookies(cookieHeader)) {
                var name = c['name'] ?? '';
                var value = c['value'] ?? '';
                if (!cookieMap.containsKey(name)) {
                  cookieMap[name] = {
                    'name': name,
                    'value_preview': value.length > 30
                        ? '${value.substring(0, 30)}...'
                        : value,
                    'domains': <String>[],
                    'request_count': 0,
                    'http_only': false,
                    'secure': false,
                  };
                }
                try {
                  var host = Uri.parse(req.requestUrl).host;
                  if (!(cookieMap[name]!['domains'] as List).contains(host)) {
                    (cookieMap[name]!['domains'] as List).add(host);
                  }
                } catch (e, st) {
                  // URL 解析失败时静默忽略（可能是无效 URL）
                  debugPrint('[MCP Security] Cookie URL parse error: $e\n$st');
                }
                cookieMap[name]!['request_count'] =
                    (cookieMap[name]!['request_count'] as int) + 1;
              }
            }

            // Set-Cookie 响应头
            var setCookieHeaders = <String>[];
            req.response?.headers.forEach((key, values) {
              if (key.toLowerCase() == 'set-cookie') {
                setCookieHeaders.addAll(values);
              }
            });
            for (var sc in setCookieHeaders) {
              var parts = sc.split(';');
              var kv = parts.first.split('=');
              if (kv.length == 2) {
                var name = kv[0].trim();
                var value = kv[1].trim();
                if (!cookieMap.containsKey(name)) {
                  cookieMap[name] = {
                    'name': name,
                    'value_preview': value.length > 30
                        ? '${value.substring(0, 30)}...'
                        : value,
                    'domains': <String>[],
                    'request_count': 0,
                    'http_only': false,
                    'secure': false,
                  };
                }
                cookieMap[name]!['http_only'] = parts.any(
                  (p) => p.trim().toLowerCase() == 'httponly',
                );
                cookieMap[name]!['secure'] = parts.any(
                  (p) => p.trim().toLowerCase() == 'secure',
                );
                var expires = parts.firstWhere(
                  (p) => p.trim().toLowerCase().startsWith('expires='),
                  orElse: () => '',
                );
                if (expires.isNotEmpty) {
                  cookieMap[name]!['expires'] = expires.trim().substring(
                    'expires='.length,
                  );
                }
              }
            }
          }

          return {
            'domain':
                domain ?? (requestId != null ? 'request_$requestId' : 'all'),
            'total_cookies': cookieMap.length,
            'cookies': cookieMap.values.toList(),
          };
        } catch (e) {
          return {'error': 'Failed to get cookie info: $e'};
        }

      case 'get_domain_summary':
        // 汇总某个域名的请求统计（方法分布、状态码、平均耗时、数据量）
        try {
          final domain = args['domain'] as String?;
          if (domain == null || domain.isEmpty) {
            return {'error': 'domain parameter is required'};
          }

          final requests = McpBridge().source.where((r) {
            try {
              return Uri.parse(r.requestUrl).host.contains(domain);
            } catch (_) {
              return false;
            }
          }).toList();

          final methods = <String, int>{};
          final statusCodes = <int, int>{};
          var totalDuration = 0;
          var totalSize = 0;
          var errorCount = 0;

          for (var req in requests) {
            methods[req.method.name] = (methods[req.method.name] ?? 0) + 1;
            totalSize += req.packageSize ?? 0;
            var res = req.response;
            if (res != null) {
              var code = res.status.code;
              statusCodes[code] = (statusCodes[code] ?? 0) + 1;
              totalDuration += res.responseTime
                  .difference(req.requestTime)
                  .inMilliseconds;
              if (code >= 400) errorCount++;
            }
          }

          return {
            'domain': domain,
            'total_requests': requests.length,
            'methods': methods,
            'status_codes': statusCodes,
            'avg_duration_ms': requests.isEmpty
                ? 0
                : (totalDuration / requests.length).round(),
            'error_count': errorCount,
            'total_size_bytes': totalSize,
          };
        } catch (e) {
          return {'error': 'Failed to get domain summary: $e'};
        }

      case 'calculate_entropy':
        // 计算字符串的香农熵（用于评估随机性/密钥强度）
        try {
          final text = args['text'] as String? ?? args['value'] as String?;
          if (text == null || text.isEmpty) {
            return {'error': 'text parameter is required'};
          }

          var freq = <int, int>{};
          for (var code in text.codeUnits) {
            freq[code] = (freq[code] ?? 0) + 1;
          }
          var length = text.length;
          var entropy = 0.0;
          freq.forEach((_, count) {
            var p = count / length;
            entropy -= p * (p == 0 ? 0 : _log2(p));
          });

          // 参考 https://github.com/danielmiessler/SecLists 常见弱密钥模式
          var isWeak = text.length < 16 || entropy < 3.0;
          var hints = <String>[];
          if (text.length < 16) hints.add('长度过短（<16），可能是弱密钥');
          if (entropy < 3.0) hints.add('熵值低（<3.0），字符分布过于单一');

          return {
            'entropy': double.parse(entropy.toStringAsFixed(4)),
            'length': text.length,
            'unique_chars': freq.length,
            'is_weak': isWeak,
            'hints': hints,
          };
        } catch (e) {
          return {'error': 'Failed to calculate entropy: $e'};
        }

      // ==================== Device Control Tools (Android only) ====================
      case 'get_device_info':
        if (!McpScreen.isSupported) {
          return {'error': 'Device control is only available on Android'};
        }
        try {
          return await McpScreen.getDeviceInfo();
        } catch (e) {
          return {'error': 'Failed to get device info: $e'};
        }

      case 'get_current_activity':
        if (!McpScreen.isSupported) {
          return {'error': 'Device control is only available on Android'};
        }
        try {
          var activity = await McpScreen.getCurrentActivity();
          return {'activity': activity};
        } catch (e) {
          return {'error': 'Failed to get current activity: $e'};
        }

      case 'dump_ui':
        if (!McpScreen.isSupported) {
          return {'error': 'Device control is only available on Android'};
        }
        try {
          var clickableOnly = args['clickable_only'] as bool? ?? false;
          var packageFilter = args['package_filter'] as String?;
          var uiJson = await McpScreen.dumpUi(
            clickableOnly: clickableOnly,
            packageFilter: packageFilter,
          );
          return {'ui': jsonDecode(uiJson)};
        } catch (e) {
          return {'error': 'Failed to dump UI: $e'};
        }

      case 'tap_screen':
        if (!McpScreen.isSupported) {
          return {'error': 'Device control is only available on Android'};
        }
        try {
          var x = (args['x'] as num).toInt();
          var y = (args['y'] as num).toInt();
          var success = await McpScreen.tap(x, y);
          return {'success': success};
        } catch (e) {
          return {'error': 'Failed to tap: $e'};
        }

      case 'long_press':
        if (!McpScreen.isSupported) {
          return {'error': 'Device control is only available on Android'};
        }
        try {
          var x = (args['x'] as num).toInt();
          var y = (args['y'] as num).toInt();
          var duration = (args['duration'] as num?)?.toInt() ?? 50;
          var success = await McpScreen.click(x, y, duration: duration);
          return {'success': success};
        } catch (e) {
          return {'error': 'Failed to long press: $e'};
        }

      case 'swipe_screen':
        if (!McpScreen.isSupported) {
          return {'error': 'Device control is only available on Android'};
        }
        try {
          var x1 = (args['x1'] as num).toInt();
          var y1 = (args['y1'] as num).toInt();
          var x2 = (args['x2'] as num).toInt();
          var y2 = (args['y2'] as num).toInt();
          var duration = (args['duration'] as num?)?.toInt() ?? 300;
          var success = await McpScreen.swipe(
            x1,
            y1,
            x2,
            y2,
            duration: duration,
          );
          return {'success': success};
        } catch (e) {
          return {'error': 'Failed to swipe: $e'};
        }

      case 'key_event':
        if (!McpScreen.isSupported) {
          return {'error': 'Device control is only available on Android'};
        }
        try {
          var keycode = (args['keycode'] as num).toInt();
          var success = await McpScreen.keyEvent(keycode);
          return {'success': success};
        } catch (e) {
          return {'error': 'Failed to send key event: $e'};
        }

      case 'input_text':
        if (!McpScreen.isSupported) {
          return {'error': 'Device control is only available on Android'};
        }
        try {
          var text = args['text'] as String;
          var success = await McpScreen.inputText(text);
          return {'success': success};
        } catch (e) {
          return {'error': 'Failed to input text: $e'};
        }

      case 'screenshot':
        if (!McpScreen.isSupported) {
          return {'error': 'Device control is only available on Android'};
        }
        try {
          var base64 = await McpScreen.screenshot();
          return {'image': base64, 'format': 'png_base64'};
        } catch (e) {
          return {'error': 'Failed to take screenshot: $e'};
        }

      case 'open_accessibility_settings':
        if (!McpScreen.isSupported) {
          return {'error': 'Device control is only available on Android'};
        }
        try {
          var success = await McpScreen.openAccessibilitySettings();
          return {'success': success};
        } catch (e) {
          return {'error': 'Failed to open accessibility settings: $e'};
        }

      case 'shell':
        if (!McpScreen.isSupported) {
          return {'error': 'Device control is only available on Android'};
        }
        try {
          var command = args['command'] as String;
          var useSu = args['use_su'] as bool? ?? false;
          var mode = args['mode'] as String?;
          var timeoutMs = (args['timeout_ms'] as num?)?.toInt() ?? 10000;
          return await McpScreen.shell(
            command,
            useSu: useSu,
            mode: mode,
            timeoutMs: timeoutMs,
          );
        } catch (e) {
          return {'error': 'Failed to execute shell command: $e'};
        }

      // ==================== Breakpoint Debugging Tools (1.3.1+) ====================
      case 'add_breakpoint_rule':
        try {
          final urlPattern = args['url_pattern'] as String;
          final ruleName = args['name'] as String? ?? 'MCP Breakpoint';
          final interceptRequest = args['intercept_request'] as bool? ?? true;
          final interceptResponse = args['intercept_response'] as bool? ?? true;
          final methodStr = args['method'] as String?;
          final enabled = args['enabled'] as bool? ?? true;

          HttpMethod? method;
          if (methodStr != null && methodStr.isNotEmpty) {
            method = HttpMethod.valueOf(methodStr);
          }

          var manager = await RequestBreakpointManager.instance;
          var rule = RequestBreakpointRule(
            enabled: enabled,
            name: ruleName,
            url: urlPattern,
            interceptRequest: interceptRequest,
            interceptResponse: interceptResponse,
            method: method,
          );
          manager.add(rule);
          _notifyConfigChanged('breakpoint', {
            'action': 'add',
            'url': urlPattern,
          });
          return {
            'status': 'success',
            'message': 'Added breakpoint rule for $urlPattern',
            'rule': rule.toJson(),
          };
        } catch (e) {
          return {'error': 'Failed to add breakpoint rule: $e'};
        }

      case 'remove_breakpoint_rule':
        try {
          final urlPattern = args['url_pattern'] as String;
          var manager = await RequestBreakpointManager.instance;
          manager.list.removeWhere((r) => r.url == urlPattern);
          await manager.save();
          _notifyConfigChanged('breakpoint', {
            'action': 'remove',
            'url': urlPattern,
          });
          return {
            'status': 'success',
            'message': 'Removed breakpoint rule for $urlPattern',
          };
        } catch (e) {
          return {'error': 'Failed to remove breakpoint rule: $e'};
        }

      case 'list_breakpoint_rules':
        try {
          var manager = await RequestBreakpointManager.instance;
          return {
            'enabled': manager.enabled,
            'rules': manager.list.map((r) => r.toJson()).toList(),
            'total': manager.list.length,
          };
        } catch (e) {
          return {'error': 'Failed to list breakpoint rules: $e'};
        }

      case 'toggle_breakpoint':
        try {
          final enabled = args['enabled'] as bool;
          var manager = await RequestBreakpointManager.instance;
          manager.enabled = enabled;
          await manager.save();
          _notifyConfigChanged('breakpoint', {
            'action': 'toggle',
            'enabled': enabled,
          });
          return {'status': 'success', 'enabled': manager.enabled};
        } catch (e) {
          return {'error': 'Failed to toggle breakpoint: $e'};
        }

      // ==================== MCP 拦截队列工具（2.x 增强） ====================
      case 'get_pending_intercepts':
        try {
          final items = RequestBreakpointInterceptor.instance
              .pendingIntercepts();
          return {'count': items.length, 'intercepts': items};
        } catch (e) {
          return {'error': 'Failed to get pending intercepts: $e'};
        }

      case 'approve_intercept':
        try {
          final requestId = args['request_id'] as String;
          final modifier = args['modifier'] as Map<String, dynamic>?;
          final interceptor = RequestBreakpointInterceptor.instance;

          if (interceptor.isRequestPaused(requestId)) {
            // 请求拦截：可携带 modifier 修改请求后放行
            if (modifier != null && modifier.isNotEmpty) {
              // 通过 toJson/fromJson 重建并应用修改
              final original = interceptor.pendingIntercepts().firstWhere(
                (e) => e['id'] == requestId,
                orElse: () => {},
              );
              if (original.isNotEmpty) {
                final req = interceptor.getPausedRequest(requestId);
                if (req != null) {
                  final json = req.toJson();
                  if (modifier['method'] is String) {
                    json['method'] = modifier['method'];
                  }
                  if (modifier['url'] is String) {
                    json['uri'] = modifier['url'];
                  }
                  if (modifier['headers'] is Map) {
                    // 规范化 headers：支持 Map<String, String> 或 Map<String, List<String>>
                    final rawHeaders = modifier['headers'] as Map;
                    final normalized = <String, List<String>>{};
                    rawHeaders.forEach((k, v) {
                      if (v is List) {
                        normalized[k.toString()] = v
                            .map((e) => e.toString())
                            .toList();
                      } else {
                        normalized[k.toString()] = [v.toString()];
                      }
                    });
                    json['headers'] = normalized;
                  }
                  if (modifier['body'] is String) {
                    json['body'] = modifier['body'];
                  }
                  final modified = HttpRequest.fromJson(json);
                  interceptor.resumeRequest(requestId, modified);
                  return {
                    'status': 'approved',
                    'id': requestId,
                    'type': 'request',
                    'modified': true,
                  };
                }
              }
            }
            // 无修改：放行原请求
            interceptor.resumeRequest(requestId, null);
            return {'status': 'approved', 'id': requestId, 'type': 'request'};
          }

          if (interceptor.isResponsePaused(requestId)) {
            // 响应拦截：放行原响应（响应修改请使用响应重写规则）
            interceptor.resumeResponse(requestId, null);
            return {'status': 'approved', 'id': requestId, 'type': 'response'};
          }

          return {'error': 'No pending intercept with id: $requestId'};
        } catch (e) {
          return {'error': 'Failed to approve intercept: $e'};
        }

      case 'reject_intercept':
        try {
          final requestId = args['request_id'] as String;
          final reason = args['reason'] as String? ?? 'Rejected by user';
          final interceptor = RequestBreakpointInterceptor.instance;

          if (interceptor.isResponsePaused(requestId)) {
            // 响应拦截：拒绝即丢弃响应
            interceptor.resumeResponse(requestId, null);
            return {
              'status': 'rejected',
              'id': requestId,
              'type': 'response',
              'reason': reason,
            };
          } else if (interceptor.isRequestPaused(requestId)) {
            // 请求拦截：拒绝即中止请求（resume null 会 abort）
            interceptor.resumeRequest(requestId, null);
            return {
              'status': 'rejected',
              'id': requestId,
              'type': 'request',
              'reason': reason,
            };
          }
          return {'error': 'No pending intercept with id: $requestId'};
        } catch (e) {
          return {'error': 'Failed to reject intercept: $e'};
        }

      // ==================== WebSocket Message Tools (v1.6.0+) ====================
      case 'get_paused_websocket_messages':
        try {
          final paused = McpBridge().getPausedWebSocketMessages();
          return {
            'status': 'success',
            'count': paused.length,
            'messages': paused.map((m) => {
              'frame_id': m.frameId,
              'url': m.url,
              'direction': m.isOutgoing ? 'outgoing' : 'incoming',
              'payload_preview': m.payloadPreview,
              'paused_at': m.pausedAt,
            }).toList(),
          };
        } catch (e) {
          return {'error': 'Failed to get paused WebSocket messages: $e'};
        }

      case 'resume_websocket_message':
        try {
          final frameId = args['frame_id'] as String;
          final payload = args['payload'] as String?;
          final result = await McpBridge().resumeWebSocketMessage(frameId, payload: payload);
          return {
            'status': result ? 'resumed' : 'failed',
            'frame_id': frameId,
            'modified': payload != null,
          };
        } catch (e) {
          return {'error': 'Failed to resume WebSocket message: $e'};
        }

      case 'abort_websocket_message':
        try {
          final frameId = args['frame_id'] as String;
          final reason = args['reason'] as String? ?? 'Aborted by user';
          final result = await McpBridge().abortWebSocketMessage(frameId, reason: reason);
          return {
            'status': result ? 'aborted' : 'failed',
            'frame_id': frameId,
            'reason': reason,
          };
        } catch (e) {
          return {'error': 'Failed to abort WebSocket message: $e'};
        }


      // ==================== Weak Network Simulation Tools (1.3.1+) ====================
      case 'add_weak_network_rule':
        try {
          final urlPattern = args['url_pattern'] as String;
          final profileId = args['profile_id'] as String;
          final enabled = args['enabled'] as bool? ?? true;

          var manager = await NetworkConditionManager.instance;

          // Validate profile exists
          var profile = manager.findProfile(profileId);
          if (profile == null) {
            return {
              'error':
                  'Profile not found: $profileId. Available: ${manager.allProfiles.map((p) => p.id).join(", ")}',
            };
          }

          var rule = NetworkConditionRule(
            enabled: enabled,
            url: urlPattern,
            profileId: profileId,
          );
          manager.rules.add(rule);
          await manager.flushConfig();
          _notifyConfigChanged('weak_network', {
            'action': 'add_rule',
            'url': urlPattern,
          });
          return {
            'status': 'success',
            'message':
                'Added weak network rule for $urlPattern with profile $profileId',
            'rule': rule.toJson(),
          };
        } catch (e) {
          return {'error': 'Failed to add weak network rule: $e'};
        }

      case 'add_custom_network_profile':
        try {
          final name = args['name'] as String;
          final uploadKbps = (args['upload_kbps'] as num?)?.toInt();
          final downloadKbps = (args['download_kbps'] as num?)?.toInt();
          final requestLatencyMs =
              (args['request_latency_ms'] as num?)?.toInt() ?? 0;
          final responseLatencyMs =
              (args['response_latency_ms'] as num?)?.toInt() ?? 0;
          final jitterMs = (args['jitter_ms'] as num?)?.toInt() ?? 0;
          final lossRate = (args['loss_rate'] as num?)?.toDouble() ?? 0.0;
          final offline = args['offline'] as bool? ?? false;

          var manager = await NetworkConditionManager.instance;
          var profile = NetworkConditionProfile(
            id: NetworkConditionManager.newCustomId(),
            name: name,
            uploadKbps: uploadKbps,
            downloadKbps: downloadKbps,
            requestLatencyMs: requestLatencyMs,
            responseLatencyMs: responseLatencyMs,
            jitterMs: jitterMs,
            lossRate: lossRate,
            offline: offline,
          );
          await manager.upsertCustomProfile(profile);
          _notifyConfigChanged('weak_network', {
            'action': 'add_profile',
            'name': name,
          });
          return {
            'status': 'success',
            'message': 'Created custom network profile: $name',
            'profile': profile.toJson(),
          };
        } catch (e) {
          return {'error': 'Failed to create custom network profile: $e'};
        }

      case 'list_weak_network_rules':
        try {
          var manager = await NetworkConditionManager.instance;
          return {
            'enabled': manager.enabled,
            'rules': manager.rules.map((r) => r.toJson()).toList(),
            'builtin_profiles': NetworkConditionProfile.builtin
                .map((p) => p.toJson())
                .toList(),
            'custom_profiles': manager.customProfiles
                .map((p) => p.toJson())
                .toList(),
            'total_rules': manager.rules.length,
          };
        } catch (e) {
          return {'error': 'Failed to list weak network rules: $e'};
        }

      case 'remove_weak_network_rule':
        try {
          final urlPattern = args['url_pattern'] as String;
          var manager = await NetworkConditionManager.instance;
          manager.rules.removeWhere((r) => r.url == urlPattern);
          await manager.flushConfig();
          _notifyConfigChanged('weak_network', {
            'action': 'remove_rule',
            'url': urlPattern,
          });
          return {
            'status': 'success',
            'message': 'Removed weak network rule for $urlPattern',
          };
        } catch (e) {
          return {'error': 'Failed to remove weak network rule: $e'};
        }

      case 'toggle_weak_network':
        try {
          final enabled = args['enabled'] as bool;
          var manager = await NetworkConditionManager.instance;
          manager.enabled = enabled;
          await manager.flushConfig();
          _notifyConfigChanged('weak_network', {
            'action': 'toggle',
            'enabled': enabled,
          });
          return {'status': 'success', 'enabled': manager.enabled};
        } catch (e) {
          return {'error': 'Failed to toggle weak network: $e'};
        }

      // ==================== Environment Variable Tools (1.3.1+) ====================
      case 'list_environments':
        try {
          var manager = await EnvironmentManager.instance;
          return {
            'enabled': manager.enabled,
            'active_id': manager.activeId,
            'active_name': manager.active?.name,
            'environments': manager.environments
                .map((e) => e.toJson())
                .toList(),
            'flat_variables': manager.flatMap(),
            'total_environments': manager.environments.length,
          };
        } catch (e) {
          return {'error': 'Failed to list environments: $e'};
        }

      case 'set_environment_variable':
        try {
          final key = args['key'] as String;
          final value = args['value'] as String?;
          final environmentId = args['environment_id'] as String?;
          final enabled = args['enabled'] as bool? ?? true;

          var manager = await EnvironmentManager.instance;

          // Determine target environment
          Environment target;
          if (environmentId != null && environmentId.isNotEmpty) {
            // Find by explicit ID; return error if not found
            var found = manager.environments.firstWhere(
              (e) => e.id == environmentId,
              orElse: () => Environment(id: '', name: ''),
            );
            if (found.id.isEmpty) {
              return {'error': 'Environment not found: $environmentId'};
            }
            target = found;
          } else {
            // Default: write to active environment or Global
            target = manager.active ?? manager.global;
          }

          if (value == null) {
            // Delete the variable
            target.variables.removeWhere((v) => v.key == key);
          } else {
            // Update or add
            var existing = target.variables.firstWhere(
              (v) => v.key == key,
              orElse: () => EnvironmentVariable(key: '', value: ''),
            );
            if (existing.key.isNotEmpty) {
              existing.value = value;
              existing.enabled = enabled;
            } else {
              target.variables.add(
                EnvironmentVariable(key: key, value: value, enabled: enabled),
              );
            }
          }
          await manager.flushConfig();
          _notifyConfigChanged('environment', {
            'action': 'set_variable',
            'key': key,
          });
          return {
            'status': 'success',
            'message': value == null
                ? 'Deleted variable $key from ${target.name}'
                : 'Set variable $key=$value in ${target.name}',
            'environment': target.name,
          };
        } catch (e) {
          return {'error': 'Failed to set environment variable: $e'};
        }

      case 'create_environment':
        try {
          final name = args['name'] as String;
          var manager = await EnvironmentManager.instance;
          var env = Environment(id: RandomUtil.randomString(8), name: name);
          manager.upsertEnvironment(env);
          await manager.flushConfig();
          _notifyConfigChanged('environment', {
            'action': 'create',
            'name': name,
          });
          return {
            'status': 'success',
            'message': 'Created environment: $name',
            'environment': env.toJson(),
          };
        } catch (e) {
          return {'error': 'Failed to create environment: $e'};
        }

      case 'set_active_environment':
        try {
          final environmentId = args['environment_id'] as String?;
          var manager = await EnvironmentManager.instance;

          if (environmentId == null || environmentId.isEmpty) {
            manager.setActive(null);
          } else {
            // Verify the environment exists and is not Global
            var env = manager.environments.firstWhere(
              (e) => e.id == environmentId && !e.isGlobal,
              orElse: () => Environment(id: '', name: ''),
            );
            if (env.id.isEmpty) {
              return {'error': 'Named environment not found: $environmentId'};
            }
            manager.setActive(environmentId);
          }
          await manager.flushConfig();
          _notifyConfigChanged('environment', {
            'action': 'set_active',
            'active_id': manager.activeId,
          });
          return {
            'status': 'success',
            'active_id': manager.activeId,
            'active_name': manager.active?.name,
          };
        } catch (e) {
          return {'error': 'Failed to set active environment: $e'};
        }

      case 'remove_environment':
        try {
          final environmentId = args['environment_id'] as String;
          var manager = await EnvironmentManager.instance;

          // Prevent removing Global
          if (environmentId == 'global') {
            return {'error': 'Cannot remove the Global environment'};
          }

          manager.removeEnvironment(environmentId);
          await manager.flushConfig();
          _notifyConfigChanged('environment', {
            'action': 'remove',
            'environment_id': environmentId,
          });
          return {
            'status': 'success',
            'message': 'Removed environment: $environmentId',
          };
        } catch (e) {
          return {'error': 'Failed to remove environment: $e'};
        }

      case 'toggle_environment_variables':
        try {
          final enabled = args['enabled'] as bool;
          var manager = await EnvironmentManager.instance;
          manager.setEnabled(enabled);
          await manager.flushConfig();
          _notifyConfigChanged('environment', {
            'action': 'toggle',
            'enabled': enabled,
          });
          return {'status': 'success', 'enabled': manager.enabled};
        } catch (e) {
          return {'error': 'Failed to toggle environment variables: $e'};
        }

      default:
        throw Exception('Unknown tool: $name');
    }
  }

  String _generateCurl(HttpRequest req) {
    var sb = StringBuffer();
    sb.write("curl -X ${req.method.name} '${req.requestUrl}'");

    req.headers.forEach((key, values) {
      for (var v in values) {
        sb.write(" -H '$key: $v'");
      }
    });

    var body = req.bodyAsString;
    if (body.isNotEmpty) {
      var escapedBody = body.replaceAll("'", "'\\''");
      sb.write(" -d '$escapedBody'");
    }

    if (req.headers.contentEncoding == 'gzip') {
      sb.write(" --compressed");
    }
    return sb.toString();
  }

  String _generatePythonCode(HttpRequest req) {
    var sb = StringBuffer();
    sb.writeln("import requests");
    sb.writeln();
    sb.writeln("url = \"${req.requestUrl}\"");
    sb.writeln();

    sb.writeln("headers = {");
    req.headers.forEach((key, values) {
      // Python requests usually takes the first value if multiple, or list
      var val = values.length == 1 ? values.first : values.join(',');
      // Escape quotes
      val = val.replaceAll('"', '\\"');
      sb.writeln("    \"$key\": \"$val\",");
    });
    sb.writeln("}");
    sb.writeln();

    var body = req.bodyAsString;
    if (body.isNotEmpty) {
      // Try to pretty print JSON if possible
      try {
        // Check if it's json
        if (req.headers.contentType.contains("json")) {
          // Use json parameter
          sb.writeln(
            "payload = $body",
          ); // Assume body is valid json string, maybe problematic if not formatted
          // Safe way: treat as string then json.loads? Or just raw string
          // Let's just use data for now to be safe
          sb.writeln(
            "response = requests.request(\"${req.method.name}\", url, headers=headers, data='''$body''')",
          );
        } else {
          sb.writeln(
            "response = requests.request(\"${req.method.name}\", url, headers=headers, data='''$body''')",
          );
        }
      } catch (e) {
        sb.writeln(
          "response = requests.request(\"${req.method.name}\", url, headers=headers, data='''$body''')",
        );
      }
    } else {
      sb.writeln(
        "response = requests.request(\"${req.method.name}\", url, headers=headers)",
      );
    }

    sb.writeln();
    sb.writeln("print(response.text)");
    return sb.toString();
  }

  String _generateJsCode(HttpRequest req) {
    var sb = StringBuffer();
    sb.writeln("const url = \"${req.requestUrl}\";");
    sb.writeln("const options = {");
    sb.writeln("  method: \"${req.method.name}\",");
    sb.writeln("  headers: {");
    req.headers.forEach((key, values) {
      var val = values.join(',');
      val = val.replaceAll('"', '\\"');
      sb.writeln("    \"$key\": \"$val\",");
    });
    sb.writeln("  },");

    var body = req.bodyAsString;
    if (body.isNotEmpty) {
      // 转义 backtick 和 ${} 防止模板字符串注入
      var escapedBody = body
          .replaceAll('\\', '\\\\')
          .replaceAll('`', '\\`')
          .replaceAll('\$', '\\\$');
      sb.writeln("  body: `$escapedBody`");
    }
    sb.writeln("};");
    sb.writeln();
    sb.writeln("fetch(url, options)");
    sb.writeln("  .then(response => response.text())");
    sb.writeln("  .then(result => console.log(result))");
    sb.writeln("  .catch(error => console.error('error', error));");
    return sb.toString();
  }

  /// 生成 Go 语言请求代码（net/http）
  String _generateGoCode(HttpRequest req) {
    var sb = StringBuffer();
    sb.writeln("package main");
    sb.writeln();
    sb.writeln("import (");
    sb.writeln("    \"fmt\"");
    sb.writeln("    \"io\"");
    sb.writeln("    \"net/http\"");
    sb.writeln("    \"strings\"");
    sb.writeln(")");
    sb.writeln();
    sb.writeln("func main() {");
    sb.writeln("    url := \"${req.requestUrl}\"");
    sb.writeln("    method := \"${req.method.name}\"");

    var body = req.bodyAsString;
    if (body.isNotEmpty) {
      var escapedBody = body.replaceAll('"', '\\"').replaceAll('\n', '\\n');
      sb.writeln("    payload := strings.NewReader(\"$escapedBody\")");
    } else {
      sb.writeln("    var payload io.Reader");
    }
    sb.writeln();
    sb.writeln("    req, err := http.NewRequest(method, url, payload)");
    sb.writeln("    if err != nil {");
    sb.writeln("        fmt.Println(err)");
    sb.writeln("        return");
    sb.writeln("    }");
    req.headers.forEach((key, values) {
      for (var v in values) {
        var val = v.replaceAll('"', '\\"');
        sb.writeln("    req.Header.Add(\"$key\", \"$val\")");
      }
    });
    sb.writeln();
    sb.writeln("    res, err := http.DefaultClient.Do(req)");
    sb.writeln("    if err != nil {");
    sb.writeln("        fmt.Println(err)");
    sb.writeln("        return");
    sb.writeln("    }");
    sb.writeln("    defer res.Body.Close()");
    sb.writeln("    bodyBytes, _ := io.ReadAll(res.Body)");
    sb.writeln("    fmt.Println(string(bodyBytes))");
    sb.writeln("}");
    return sb.toString();
  }

  /// 生成 Node.js 原生 http/https 请求代码（fetch 之外的选择）
  String _generateNodeJsCode(HttpRequest req) {
    var sb = StringBuffer();
    sb.writeln("const http = require('http');");
    sb.writeln("const https = require('https');");
    sb.writeln();
    sb.writeln("const url = new URL(\"${req.requestUrl}\");");
    sb.writeln("const options = {");
    sb.writeln("  method: \"${req.method.name}\",");
    sb.writeln("  hostname: url.hostname,");
    sb.writeln("  port: url.port || (url.protocol === 'https:' ? 443 : 80),");
    sb.writeln("  path: url.pathname + url.search,");
    sb.writeln("  headers: {");
    req.headers.forEach((key, values) {
      var val = values.join(',');
      val = val.replaceAll('"', '\\"');
      sb.writeln("    \"$key\": \"$val\",");
    });
    sb.writeln("  }");
    sb.writeln("};");
    sb.writeln();
    sb.writeln("const client = url.protocol === 'https:' ? https : http;");
    sb.writeln("const req = client.request(options, (res) => {");
    sb.writeln("  let data = '';");
    sb.writeln("  res.on('data', (chunk) => { data += chunk; });");
    sb.writeln("  res.on('end', () => { console.log(data); });");
    sb.writeln("});");
    var body = req.bodyAsString;
    if (body.isNotEmpty) {
      var escapedBody = body.replaceAll('`', '\\`').replaceAll('\$', '\\\$');
      sb.writeln("req.write(`$escapedBody`);");
    }
    sb.writeln("req.end();");
    return sb.toString();
  }

  Map<String, dynamic> _generateHar(Iterable<HttpRequest> requests) {
    var entries = [];
    for (var req in requests) {
      var response = req.response;
      var duration = response != null
          ? response.responseTime.difference(req.requestTime).inMilliseconds
          : 0;

      entries.add({
        "startedDateTime": req.requestTime.toIso8601String(),
        "time": duration,
        "request": {
          "method": req.method.name,
          "url": req.requestUrl,
          "httpVersion": req.protocolVersion,
          "cookies": _parseCookies(req.headers.get('cookie')),
          "headers": req.headers.entries
              .map((e) => {"name": e.key, "value": e.value.join(',')})
              .toList(),
          "queryString": _parseQueryString(req.requestUrl),
          "headersSize": -1,
          "bodySize": req.packageSize ?? -1,
          "postData": req.bodyAsString.isNotEmpty
              ? {"mimeType": req.headers.contentType, "text": req.bodyAsString}
              : null,
        },
        "response": {
          "status": response?.status.code ?? 0,
          "statusText": response?.status.reasonPhrase ?? "",
          "httpVersion": response?.protocolVersion ?? "HTTP/1.1",
          "cookies": [],
          "headers":
              response?.headers.entries
                  .map((e) => {"name": e.key, "value": e.value.join(',')})
                  .toList() ??
              [],
          "content": {
            "size": response?.body?.length ?? 0,
            "mimeType": response?.headers.contentType ?? "",
            "text": response?.bodyAsString,
          },
          "redirectURL": "",
          "headersSize": -1,
          "bodySize": response?.packageSize ?? -1,
        },
        "cache": {},
        "timings": {"send": 0, "wait": duration, "receive": 0},
      });
    }

    return {
      "log": {
        "version": "1.2",
        "creator": {"name": "ProxyPin MCP", "version": "1.0"},
        "entries": entries,
      },
    };
  }

  HttpRequest? _parseHarEntry(Map<String, dynamic> entry) {
    try {
      var requestJson = entry['request'];
      var url = requestJson['url'];
      var method = requestJson['method'];
      var req = HttpRequest(HttpMethod.valueOf(method), url);

      if (entry['startedDateTime'] != null) {
        req.requestTime = DateTime.parse(entry['startedDateTime']);
      }

      // Headers
      if (requestJson['headers'] != null) {
        for (var h in requestJson['headers']) {
          req.headers.add(h['name'], h['value']);
        }
      }

      // Body
      if (requestJson['postData'] != null &&
          requestJson['postData']['text'] != null) {
        req.body = utf8.encode(requestJson['postData']['text']);
      }

      // Response
      var responseJson = entry['response'];
      if (responseJson != null) {
        var status = responseJson['status'];
        var statusText = responseJson['statusText'];
        var res = HttpResponse(
          HttpStatus(
            status is num
                ? status.toInt()
                : (int.tryParse(status.toString()) ?? 0),
            statusText?.toString() ?? "",
          ),
        );

        if (responseJson['headers'] != null) {
          for (var h in responseJson['headers']) {
            res.headers.add(h['name'], h['value']);
          }
        }

        if (responseJson['content'] != null &&
            responseJson['content']['text'] != null) {
          res.body = utf8.encode(responseJson['content']['text']);
        }

        res.request = req;
        // Calculate response time from duration
        var time = entry['time'] ?? 0;
        res.responseTime = req.requestTime.add(
          Duration(milliseconds: time is num ? time.toInt() : 0),
        );
        req.response = res;
      }

      return req;
    } catch (e) {
      logger.e("Failed to parse HAR entry", error: e);
      return null;
    }
  }

  Future<dynamic> _readResource(String uri) async {
    if (uri == 'proxypin://requests/latest') {
      return McpBridge()
          .getRecentRequests(limit: 50)
          .map((r) => McpBridge.requestToJson(r))
          .toList();
    } else if (uri == 'proxypin://config/current') {
      var config = await Configuration.instance;
      // 脱敏：不向前端/客户端暴露 aiApiKey、mTLS 私钥路径、上游代理口令
      return Configuration.redactSecrets(config.toJson());
    } else if (uri == 'proxypin://breakpoints/rules') {
      var manager = await RequestBreakpointManager.instance;
      return {
        'enabled': manager.enabled,
        'rules': manager.list.map((r) => r.toJson()).toList(),
      };
    } else if (uri == 'proxypin://network/conditions') {
      var manager = await NetworkConditionManager.instance;
      return {
        'enabled': manager.enabled,
        'rules': manager.rules.map((r) => r.toJson()).toList(),
        'custom_profiles': manager.customProfiles
            .map((p) => p.toJson())
            .toList(),
      };
    } else if (uri == 'proxypin://environments/list') {
      var manager = await EnvironmentManager.instance;
      return {
        'enabled': manager.enabled,
        'active_id': manager.activeId,
        'environments': manager.environments.map((e) => e.toJson()).toList(),
        'flat_variables': manager.flatMap(),
      };
    }
    throw Exception('Resource not found: $uri');
  }

  /// 比较两个 Header Map 的差异
  Map<String, dynamic> _compareHeaders(
    Map<String, String> h1,
    Map<String, String> h2,
  ) {
    var added = <String, String>{};
    var removed = <String, String>{};
    var changed = <String, Map<String, String>>{};

    // 检查新增和修改
    h2.forEach((key, value) {
      if (!h1.containsKey(key)) {
        added[key] = value;
      } else if (h1[key] != value) {
        changed[key] = {'old': h1[key]!, 'new': value};
      }
    });

    // 检查删除
    h1.forEach((key, value) {
      if (!h2.containsKey(key)) {
        removed[key] = value;
      }
    });

    return {
      'added': added,
      'removed': removed,
      'changed': changed,
      'has_diff': added.isNotEmpty || removed.isNotEmpty || changed.isNotEmpty,
    };
  }

  /// 比较两个 Body 的差异（支持 JSON）
  Map<String, dynamic> _compareBody(String body1, String body2) {
    if (body1 == body2) {
      return {'same': true, 'type': 'identical'};
    }

    // 尝试作为 JSON 对比
    try {
      var json1 = jsonDecode(body1);
      var json2 = jsonDecode(body2);

      if (json1 is Map && json2 is Map) {
        return {
          'same': false,
          'type': 'json',
          'diff': _compareJsonObjects(json1, json2),
        };
      }
    } catch (e) {
      // 不是 JSON，按文本对比
    }

    return {
      'same': false,
      'type': 'text',
      'length_diff': body2.length - body1.length,
      'body1_length': body1.length,
      'body2_length': body2.length,
    };
  }

  /// 比较两个 JSON 对象
  Map<String, dynamic> _compareJsonObjects(Map json1, Map json2) {
    var added = <String, dynamic>{};
    var removed = <String, dynamic>{};
    var changed = <String, Map<String, dynamic>>{};

    // 检查新增和修改
    json2.forEach((key, value) {
      if (!json1.containsKey(key)) {
        added[key.toString()] = value;
      } else if (json1[key] != value) {
        changed[key.toString()] = {'old': json1[key], 'new': value};
      }
    });

    // 检查删除
    json1.forEach((key, value) {
      if (!json2.containsKey(key)) {
        removed[key.toString()] = value;
      }
    });

    return {'added': added, 'removed': removed, 'changed': changed};
  }

  /// 解析 Cookie 字符串为 HAR 格式
  /// 计算以 2 为底的对数
  double _log2(double x) => x <= 0 ? 0 : math.log(x) / math.ln2;

  List<Map<String, String>> _parseCookies(String? cookieHeader) {
    if (cookieHeader == null || cookieHeader.isEmpty) return [];

    var cookies = <Map<String, String>>[];
    var parts = cookieHeader.split(';');

    for (var part in parts) {
      var trimmed = part.trim();
      var index = trimmed.indexOf('=');
      if (index > 0) {
        var name = trimmed.substring(0, index);
        var value = trimmed.substring(index + 1);
        cookies.add({'name': name, 'value': value});
      }
    }

    return cookies;
  }

  /// 解析 URL 查询参数为 HAR 格式
  List<Map<String, String>> _parseQueryString(String url) {
    try {
      var uri = Uri.parse(url);
      return uri.queryParameters.entries
          .map((e) => {'name': e.key, 'value': e.value})
          .toList();
    } catch (e) {
      return [];
    }
  }
}

/// API 端点信息类
class ApiEndpoint {
  final String method;
  final String domain;
  final String path;
  final List<HttpRequest> requests = [];
  final Set<int> statusCodes = {};

  ApiEndpoint(this.method, this.domain, this.path);

  void addRequest(HttpRequest req) {
    requests.add(req);
    if (req.response?.status.code != null) {
      statusCodes.add(req.response!.status.code);
    }
  }

  int get count => requests.length;

  Map<String, dynamic> toJson() {
    return {
      'method': method,
      'domain': domain,
      'path': path,
      'count': count,
      'status_codes': statusCodes.toList()..sort(),
    };
  }
}

/// Streamable HTTP 会话（保存该会话的 SSE 输出流，用于服务端推送）
class _StreamableSession {
  io.HttpResponse? stream;

  /// 会话过期定时器（保存引用，停止服务时统一取消，避免 Timer 泄漏）
  Timer? expiry;
}
