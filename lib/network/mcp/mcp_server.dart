import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:proxypin/network/http/websocket.dart';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/components/host_filter.dart';
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
import 'package:proxypin/mcp/capture/flow_store.dart';
import 'package:proxypin/mcp/protocol/mcp_actions.dart';
import 'package:proxypin/mcp/protocol/mcp_tool.dart';
import 'package:proxypin/mcp/transport/mcp_stdio_bridge.dart';
import 'package:proxypin/mcp/transport/setup_script.dart';
import 'package:proxypin/network/mcp/mcp_bridge.dart';
import 'package:proxypin/network/mcp/mcp_runtime.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/calc_engine.dart';
import 'package:proxypin/network/util/grpc_decoder.dart';
import 'package:proxypin/network/util/capture_diagnose.dart';
import 'package:proxypin/network/util/security_audit.dart';
import 'package:proxypin/network/util/security_rule_store.dart';
import 'package:proxypin/network/util/quic/quic_1rtt.dart';
import 'package:proxypin/network/util/quic/quic_keylog.dart';
import 'package:proxypin/network/util/quic/quic_probe.dart';
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

  /// 重启 MCP 服务器（用于端口、局域网访问、鉴权等运行期配置变更后）。
  ///
  /// 这里必须用 `persistState: false` 停止：默认的 [stop] 会把
  /// `mcpEnabled` 写成 false，紧接着 [start] 的启用检查会直接返回，
  /// 表现为「点一下设置开关，MCP 服务就显示未运行」。
  Future<void> restart() async {
    await stop(persistState: false);
    await start(force: true);
  }

  /// 启动 MCP 服务器。
  ///
  /// [force] 为 true 时忽略配置里的启用开关，用于用户在设置中显式触发的重启
  /// （切换局域网 / 鉴权等），同时也能自愈此前被误写成「已停止」的配置。
  Future<void> start({bool force = false}) async {
    try {
      if (isRunning) return;

      var config = await Configuration.instance;

      // 检查是否启用 MCP 服务（force 表示这是用户的显式操作，跳过该检查）
      if (!config.mcpEnabled && !force) {
        logger.i('MCP Server is disabled by configuration, skipping start');
        return;
      }

      _port = config.mcpPort;
      _redactEnabled = config.mcpRedactEnabled;

      // 安全默认：仅监听回环地址；如需局域网访问，由用户在设置中显式开启 mcpAllowLan
      final bindAddress =
          config.mcpAllowLan ? io.InternetAddress.anyIPv4 : io.InternetAddress.loopbackIPv4;
      _server = await io.HttpServer.bind(bindAddress, _port!);
      _lastError = null; // 清除之前的错误
      logger.i('MCP Server listening on http://${bindAddress.address}:$_port '
          '(allowLan=${config.mcpAllowLan})');

      // 局域网模式：生成/复用 Bearer token（与官方实现一致），并写握手文件供 stdio 桥发现端口
      _lanMode = config.mcpAllowLan;
      // 运行期开关同步到工具运行时
      McpToolRuntime.strictValidation = config.mcpStrictValidation;
      McpMetrics.instance.markStarted();
      _authEnabled = config.mcpAuthEnabled;
      if (_lanMode && _authEnabled) {
        _token = (config.mcpToken?.isNotEmpty ?? false) ? config.mcpToken : generateToken();
        config.mcpToken = _token;
        ConfigAutoSave.markChanged();
        logger.i('MCP LAN mode: Bearer token required for remote clients');
      } else {
        _token = null;
        if (_lanMode) {
          logger.w('MCP LAN mode without auth (mcpAuthEnabled=false): any host on the LAN can read traffic');
        }
      }
      unawaited(_writeHandshake());

      _server!.listen((request) {
        // CORS 处理
        if (request.method == 'OPTIONS') {
          _handleOptions(request);
          return;
        }

        // 局域网模式鉴权（/health 放行，便于客户端探测存活）
        if (request.uri.path != '/health' && !_authorized(request)) {
          final unauthorized = request.response;
          unauthorized.statusCode = io.HttpStatus.unauthorized;
          unauthorized.headers.contentType = io.ContentType.json;
          unauthorized.write(jsonEncode({
            'error': 'Unauthorized: send Authorization: Bearer <token>',
          }));
          unauthorized.close();
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
        } else if (path == '/mcp/setup.sh' || path == '/mcp/setup.ps1') {
          // 一键配置脚本：客户端在自己的机器上执行，脚本内嵌本服务的 endpoint 与 token
          final host = request.headers.host ?? '127.0.0.1:$_port';
          final endpoint = 'http://$host/mcp';
          final script = path.endsWith('.sh')
              ? McpSetupScript.shell(endpoint: endpoint, token: _token ?? '')
              : McpSetupScript.powershell(endpoint: endpoint, token: _token ?? '');
          final response = request.response;
          response.headers.contentType = io.ContentType('text', 'plain', charset: 'utf-8');
          response.write(script);
          response.close();
        } else if (path == '/health' || path == '/healthz') {
          // 健康检查端点，供客户端探测服务是否可用（保持轻量：只回状态与关键水位）
          final response = request.response;
          response.headers.contentType = io.ContentType.json;
          response.headers.add('Access-Control-Allow-Origin', '*');
          final m = McpMetrics.instance;
          response.write(jsonEncode({
            'status': 'ok',
            'server': 'ProxyPin MCP',
            'version': appVersion,
            'protocol_version': protocolVersion,
            'lan_mode': _lanMode,
            'auth_enabled': _authEnabled,
            'inflight': m.inflight,
          }));
          response.close();
        } else if (path == '/metrics') {
          // 运行指标：供外部监控 / 排查「服务是否健康、哪个工具在拖后腿」
          final response = request.response;
          response.headers.contentType = io.ContentType.json;
          response.headers.add('Access-Control-Allow-Origin', '*');
          response.write(jsonEncode({
            'server': 'ProxyPin MCP',
            'version': appVersion,
            'protocol_version': protocolVersion,
            'sessions': _streamSessions.length,
            'sse_connections': _sseConnections.length,
            'metrics': McpMetrics.instance.toJson(),
            'gate': McpToolRuntime.gate.toJson(),
            'audit_buffered': McpAuditLog.instance.length,
          }));
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

    // stdio 桥的握手文件与运行端口绑定，停止时一并清理
    await _removeHandshake();
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
            'serverInfo': {'name': 'ProxyPin MCP', 'version': appVersion},
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
            // 统一入口：参数校验 → 并发闸 → per-tool 超时 → 指标与审计
            final result = await _runTool(name, args,
                caller: _lanMode ? 'lan' : 'loopback');
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
      _runTool(name, args, caller: 'internal');

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

  // ==================== 上游 proxypin v1.3.2 官方工具接入 ====================
  //
  // 本 fork 的 MCP 是唯一服务主体（协议 2026-07-28 + Streamable HTTP / SSE）。
  // 官方那套（规则 CRUD、脚本、Hosts、SSL、重放构造、收藏等）在这里作为
  // 「官方工具源」注册进来，与自有工具合成同一张工具表，对外只有一套工具清单。
  // 同名工具（generate_code / update_script）以本 fork 实现为准。

  static const Set<String> _nativeToolNames = {'generate_code', 'update_script'};

  /// 语义与自建工具重复、从工具表隐藏的官方工具（实现保留，可随时恢复）：
  /// clear_session ≡ clear_requests；replay_flow ≡ replay_request。
  static const Set<String> _shadowedOfficialTools = {'clear_session', 'replay_flow'};

  /// 官方工具源的默认脱敏开关（启动时从配置读取，默认开启）
  bool _redactEnabled = true;

  /// 局域网模式的 Bearer token（桌面回环模式为 null）
  String? _token;
  bool _lanMode = false;

  /// 是否启用局域网 Bearer 鉴权（用户可关；关闭时局域网无鉴权，UI 需显式警示）
  bool _authEnabled = true;

  /// 当前局域网鉴权 token（桌面回环模式返回 null）
  String? get token => _token;

  /// 是否绑定在非回环地址上（移动端局域网接入）
  bool get lanMode => _lanMode;

  /// 生成 48 位十六进制随机 token
  static String generateToken() {
    final random = math.Random.secure();
    return List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// 请求鉴权：仅局域网模式生效；[io.HttpRequest] 携带 Bearer token 或 ?token= 查询参数均可。
  bool _authorized(io.HttpRequest request) {
    final expected = _token;
    if (!_lanMode || !_authEnabled || expected == null || expected.isEmpty) return true;
    final auth = request.headers.value('authorization') ?? '';
    final bearer = auth.toLowerCase().startsWith('bearer ') ? auth.substring(7).trim() : '';
    final query = request.uri.queryParameters['token'] ?? '';
    return bearer == expected || query == expected;
  }

  /// 握手文件：stdio 桥是独立进程、不共享内存，靠该文件发现当前 HTTP 端口。
  Future<void> _writeHandshake() async {
    try {
      final file = await McpStdioBridge.handshakeFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'port': _port,
        'lan': _lanMode,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (e) {
      logger.w('MCP handshake write failed: $e');
    }
  }

  Future<void> _removeHandshake() async {
    try {
      final file = await McpStdioBridge.handshakeFile();
      if (await file.exists()) await file.delete();
    } catch (e) {
      logger.w('MCP handshake cleanup failed: $e');
    }
  }

  McpActions? _officialActions;
  FlowStore? _officialFlowStore;
  List<McpTool>? _officialToolCache;

  /// 惰性构建官方工具源：抓包索引与 UI 同源（挂到同一个 [ProxyServer]）。
  List<McpTool> _officialTools() {
    if (_officialToolCache != null) return _officialToolCache!;
    if (_officialActions == null) {
      final store = FlowStore();
      _officialFlowStore = store;
      try {
        ProxyServer.current?.addListener(store);
      } catch (e) {
        logger.w('MCP official FlowStore attach failed: $e');
      }
      _officialActions = McpActions(
        store: store,
        onClearSession: () async => McpBridge().onClearUI?.call(),
        redactEnabled: () => _redactEnabled,
      );
    }
    _officialToolCache = _officialActions!.tools();
    return _officialToolCache!;
  }

  List<Map<String, dynamic>> _officialToolsJson() {
    try {
      return _officialTools()
          .where((t) => !_nativeToolNames.contains(t.name))
          .where((t) => !_shadowedOfficialTools.contains(t.name))
          .map((t) => t.toJson())
          .toList();
    } catch (e) {
      logger.w('MCP official tools unavailable: $e');
      return const [];
    }
  }

  /// 工具分组（用于 get_tool_catalog）：按能力归类，便于模型快速定位工具。
  String _toolGroup(String name) {
    if (name.startsWith('tap_') ||
        name.startsWith('swipe_') ||
        name.startsWith('input_') ||
        name.startsWith('key_') ||
        const {'screenshot', 'dump_ui', 'long_press', 'get_current_activity', 'get_device_info',
            'open_accessibility_settings'}.contains(name)) {
      return 'device';
    }
    if (name.contains('security') ||
        name.contains('sensitive') ||
        name.startsWith('analyze_auth') ||
        name.startsWith('api_security') ||
        name.startsWith('api_key') ||
        name == 'calculate_entropy') {
      return 'security';
    }
    if (name.contains('ssl') || name.contains('cert')) return 'ssl';
    if (name.contains('breakpoint') || name.contains('intercept')) return 'breakpoint';
    if (name.contains('environment')) return 'environment';
    if (name.contains('weak') || name.contains('network_condition') || name.contains('profile')) {
      return 'network_condition';
    }
    if (name.contains('rewrite') ||
        name.contains('rule') ||
        name.contains('block') ||
        name.contains('host') ||
        name.contains('map') ||
        name.contains('favorite') ||
        name.contains('redirect')) {
      return 'rules';
    }
    if (name.contains('script')) return 'scripts';
    if (name.contains('quic')) return 'quic';
    if (name.contains('websocket')) return 'websocket';
    if (name.startsWith('start_') ||
        name.startsWith('stop_') ||
        name.contains('proxy_status') ||
        name.startsWith('set_config')) {
      return 'server';
    }
    if (name.contains('performance') || name.contains('diagnose') || name.contains('memory')) {
      return 'runtime';
    }
    if (name == 'keep_alive') return 'server';
    if (name == 'calculator' || name == 'batch' || name == 'decode_grpc') return 'runtime';
    if (name == 'get_mcp_audit') return 'meta';
    if (name.startsWith('mcp') || name.contains('catalog') || name.contains('client_setup')) return 'meta';
    if (name.contains('har') ||
        name.contains('curl') ||
        name.contains('code') ||
        name.contains('compare') ||
        name.contains('replay') ||
        name.contains('statistics') ||
        name.contains('summary') ||
        name.contains('domain') ||
        name.contains('similar') ||
        name.contains('endpoint') ||
        name.contains('request') ||
        name.contains('traffic')) {
      return 'capture';
    }
    return 'other';
  }

  Future<dynamic> _executeOfficialTool(String name, Map<String, dynamic> args) async {
    for (final tool in _officialTools()) {
      if (tool.name == name) return await tool.handler(args);
    }
    throw Exception('Unknown tool: $name');
  }

  /// 工具表构建结果（纯静态定义，构建一次即可，避免每次 tools/list 都重建 90+ 条长描述）
  List<Map<String, dynamic>>? _toolsListCache;

  List<Map<String, dynamic>> _getToolsList() =>
      _toolsListCache ??= _buildToolsList();

  List<Map<String, dynamic>> _buildToolsList() {
    return [
      {
        'name': 'set_config',
        'description':
            'Update ProxyPin configuration (system proxy, SSL capture). Call this when ' 
            'the user wants to turn system-wide proxy or HTTPS decryption on or off, or ' 
            'change which hosts get captured.',
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
        'name': 'export_har',
        'description':
            'Export captured requests to HAR (HTTP Archive) format. Call this when the ' 
            'user wants to save traffic into a file, or hand it to another tool such as ' 
            'Chrome DevTools, Charles or Postman.',
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
        'description':
            'Import HAR (HTTP Archive) data into the current ProxyPin session. Call this ' 
            'when the user has a .har file from another tool and wants to inspect or ' 
            'replay it inside ProxyPin.',
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
            'Search and filter captured HTTP requests by URL, method, status code, header ' 
            'or body content. Call this when the user asks for a subset such as all 500 ' 
            'responses or every request containing a token, instead of listing ' 
            'everything.',
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
            'Generate code for a specific request in Python, JavaScript, Go, Node.js or ' 
            'cURL. Call this when the user wants to reproduce a captured call in code; ' 
            'use get_curl when only a shell one-liner is needed.',
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
        'description':
            'Generate a cURL command for a specific request. Call this when the user ' 
            'wants a quick copy-paste shell command; use generate_code when a real ' 
            'language binding is needed.',
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
            'List recent HTTP requests, with domain and time filters, paging and a ' 
            'compact mode for token-efficient reads. Call this first when the user asks ' 
            'to see traffic, then follow up with get_request_details for a specific id.',
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
            'domain': {
              'type': 'string',
              'description': 'Filter by host / domain keyword',
            },
            'since_time': {
              'type': 'string',
              'description': 'Only requests at/after this time (YYYY-MM-DD or YYYY-MM-DD HH:mm)',
            },
            'end_time': {
              'type': 'string',
              'description': 'Only requests at/before this time (YYYY-MM-DD or YYYY-MM-DD HH:mm)',
            },
            'page': {
              'type': 'integer',
              'description': 'Page index (0-based) to page through older data (default 0)',
            },
            'compact': {
              'type': 'boolean',
              'description':
                  'If true, return core fields only (id/method/url/status/duration/contentType) to cut tokens',
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
- bodyEncoding='none': Empty body

Call this when the user asks for the headers or body of one specific request; take the
request_id from get_recent_requests or search_requests.''',
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
        'description':
            'Start the ProxyPin server on a specific port. Call this when the user wants ' 
            'to begin capturing, or right after stop_proxy; use get_proxy_status first if ' 
            'unsure whether it is already running.',
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
        'description':
            'Stop the ProxyPin proxy server and release the listening port. Call this when the user asks to stop '
                'capturing traffic, or before changing ports/config that require a restart.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'get_proxy_status',
        'description':
            'Get the current status of the proxy server (running, port, address, LAN ' 
            'mode). Call this when you need to know whether capture is active, or before ' 
            'starting and stopping it.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'clear_requests',
        'description':
            'Clear all captured requests (session history and UI list). Call this when ' 
            'the user wants a fresh start or to free memory; it discards data, so confirm ' 
            'unless the traffic is obviously disposable.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'replay_request',
        'description':
            'Replay (resend) a captured HTTP request. Call this when the user wants to ' 
            'repeat a call, for example to reproduce a bug or to verify a fix after ' 
            'changing a script or a rewrite rule.',
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
        'name': 'update_script',
        'description':
            'Create or update a JavaScript script that rewrites requests and responses. ' 
            'Call this when the user wants to inject, mock or sign traffic; check ' 
            'get_scripts or get_script_detail first if the script may already exist.',
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
        'description':
            'List all configured JavaScript rewrite scripts with their enabled state and match rules. Call this when '
                'the user asks which scripts exist, or before editing one with update_script.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'get_statistics',
        'description':
            'Get statistics of captured requests (methods, status codes, domains, sizes, ' 
            'durations). Call this when the user asks for an overview such as the error ' 
            'rate or the busiest domains.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'compare_requests',
        'description':
            'Compare two requests side by side. Call this when the user wants to know ' 
            'what differs between two calls, such as before and after a fix, or two login ' 
            'attempts.',
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
            'Find requests similar to a given one (same URL pattern, method). Call this ' 
            'when the user wants to see every call to the same endpoint, for example to ' 
            'check whether a behaviour is consistent.',
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
            'Extract and group unique API endpoints from captured traffic. Call this when ' 
            'the user wants the API surface of a host or an app rather than individual ' 
            'requests.',
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
        'name': 'find_sensitive_data',
        'description':
            'Search captured requests for sensitive data: passwords, API keys, tokens, ' 
            'secrets, private keys, phone numbers and ID cards. Call this when the user ' 
            'asks whether secrets leak in traffic, or wants a request checked before ' 
            'sharing it.',
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
            'Get cookie analysis for a domain or request (names, values, HttpOnly, ' 
            'Secure, domains). Call this when the user asks about session cookies or why ' 
            'a request appears unauthenticated.',
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
            'Get a traffic summary for one domain (methods, status codes, average ' 
            'duration, error count). Call this when the user asks how a particular host ' 
            'is behaving.',
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
      // ==================== Breakpoint Debugging Tools (1.3.1+) ====================
      {
        'name': 'toggle_breakpoint',
        'description':
            'Enable or disable breakpoint debugging globally. Call this when the user ' 
            'wants to pause traffic for manual inspection; pair it with ' 
            'get_pending_intercepts, approve_intercept and reject_intercept.',
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
            'Add a weak-network simulation rule for a URL pattern (bandwidth limit, ' 
            'latency, jitter, packet loss or offline). Call this when the user wants to ' 
            'test how an app behaves on a poor connection.',
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
            'Create a custom weak-network profile with specific parameters (bandwidth, ' 
            'latency, jitter, loss rate). Call this before add_weak_network_rule when ' 
            'none of the built-in profiles match the conditions to simulate.',
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
        'description':
            'List all weak-network simulation rules and profiles. Call this when the user ' 
            'asks which network conditions are configured, or to get a profile_id for ' 
            'add_weak_network_rule.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'remove_weak_network_rule',
        'description':
            'Remove a weak-network rule by URL pattern. Call this when the user wants to ' 
            'stop simulating poor conditions for a specific pattern.',
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
            'Enable or disable weak-network simulation globally. Call this when the user ' 
            'wants to turn the feature on or off without deleting individual rules.',
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
            'List all environments and their variables, and which one is active. Call ' 
            'this when the user asks what variables exist, or before switching ' 
            'environments.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'set_environment_variable',
        'description':
            'Set or update an environment variable, referenced in requests as ' 
            '{{variable_name}}. Call this when the user wants to change a value such as a ' 
            'host, token or version across many requests at once.',
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
            'Create a new named environment (e.g. Dev, Staging, Prod). Call this when the ' 
            'user needs a separate variable set for a different backend, then use ' 
            'set_active_environment to switch to it.',
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
            'Set the active environment by id, or pass null to deactivate it (only Global ' 
            'remains). Call this when the user wants requests to pick up a different ' 
            'variable set.',
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
            'Remove a named environment by id; the Global environment cannot be removed. ' 
            'Call this when the user wants to delete a variable set that is no longer ' 
            'needed.',
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
            'Enable or disable the environment variable feature globally. Call this when ' 
            'the user wants {{...}} placeholders left untouched, for example while ' 
            'debugging substitution.',
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
            'Get Android device info (model, brand, Android version, WiFi IP, root and ' 
            'accessibility status). Call this first when device automation is needed: the ' 
            'root and accessibility flags tell you which other device tools will actually ' 
            'work.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'get_current_activity',
        'description':
            'Get the current foreground activity and package name. Call this when the ' 
            'user asks which app is in front, or before driving a specific app with the ' 
            'tap and input tools.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'dump_ui',
        'description':
            'Dump the current Android UI hierarchy as a JSON array of elements. Call this ' 
            'when you need to locate a control by text or id before tapping it, which is ' 
            'more reliable than guessing coordinates.',
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
        'description':
            'Perform a tap at the given screen coordinates. Call this when the user wants ' 
            'to press somewhere on the device; prefer dump_ui to find the coordinates ' 
            'rather than guessing.',
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
            'Perform a long press at the given coordinates for a duration. Call this when ' 
            'a plain tap is not enough, for example to open a context menu or trigger a ' 
            'copy action.',
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
        'description':
            'Perform a swipe gesture from one point to another. Call this when the user ' 
            'wants to scroll a list, dismiss a card or reveal a drawer; adjust the ' 
            'duration for a fling instead of a slow drag.',
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
            'Send a hardware key event. Keycodes: 3=HOME, 4=BACK, 26=POWER, 82=MENU, ' 
            '187=RECENTS. Call this when the user wants to navigate back or home, or wake ' 
            'the screen.',
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
        'description':
            'Set text on the currently focused input element. Call this when the user ' 
            'wants to type into a field; tap it first so that it has focus.',
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
            'Take a screenshot and return it as Base64 PNG (requires root). Call this ' 
            'when the user wants to see the current screen, or to visually confirm the ' 
            'result of a tap or input sequence.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'open_accessibility_settings',
        'description':
            'Open the Android accessibility settings page. Call this when the ' 
            'accessibility permission is missing and the device tools (tap, dump_ui, ' 
            'screenshot) are failing for that reason.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'shell',
        'description':
            'Execute a shell command on the device, optionally with root, Shizuku or ' 
            'Dhizuku. Call this when the user needs something the dedicated tools do not ' 
            'cover; it is powerful, so keep commands narrow and reversible.',
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
            'Get all requests and responses currently paused by breakpoint interception. ' 
            'Call this when the user wants to see what is waiting for a decision, then ' 
            'approve_intercept or reject_intercept each one.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'approve_intercept',
        'description':
            'Approve (release) a paused intercept, optionally modifying the request ' 
            'first. Call this to let a frozen request continue, with or without edits.',
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
            'Reject a paused intercept; the request is aborted and the response is ' 
            'dropped. Call this when the user wants to block a specific call rather than ' 
            'edit it.',
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
        'description':
            'Get all WebSocket messages currently paused by interception. Call this when ' 
            'the user wants to inspect or decide on frozen WebSocket frames.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'resume_websocket_message',
        'description':
            'Resume (release) a paused WebSocket message, optionally replacing the ' 
            'payload. Call this to let a frozen frame through, with or without edits.',
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
        'description':
            'Abort a paused WebSocket message so it is dropped. Call this when the user ' 
            'wants to block a specific frame.',
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
      },
      {
        'name': 'diagnose_capture',
        'description':
            'Run a read-only self-check of the capture pipeline: whether the proxy server is running, '
                'whether the system proxy points at this app, whether the CA certificate is trusted, '
                'and whether any traffic arrived recently. Returns structured findings plus actionable '
                'suggestions. Call this first when the user says requests cannot be captured, pages fail '
                'to load, or traffic suddenly stops.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'get_quic_sessions',
        'description':
            'List QUIC/HTTP-3 connections observed by the passive VPN probe, with per-session '
                'metadata (SNI host, QUIC version, remote endpoint, packet/byte counts, last-seen) and '
                'a rolling 10-minute traffic timeline. Also reports how many TLS key-log entries have '
                'been imported and, for sessions whose keys are available, a preview of decrypted '
                '1-RTT stream data. HTTP/3 HEADERS are decoded with QPACK (static + dynamic table; '
                'dynamic table state is reconstructed per connection from the QPACK encoder stream) '
                'and returned as structured headers. Call this when the user asks which apps/domains '
                'use QUIC, why a QUIC connection cannot be decrypted, or wants an overview of QUIC '
                'traffic.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'host_filter': {
              'type': 'string',
              'description': 'Only return sessions whose SNI host contains this text (optional)',
            },
            'limit': {
              'type': 'integer',
              'description': 'Maximum number of sessions to return (default 50)',
            },
          },
        },
      },
      {
        'name': 'get_security_audit',
        'description':
            'Run the passive security self-audit over already-captured traffic: flags cleartext '
                'HTTP, leaked secrets/tokens, cookies missing Secure/HttpOnly, missing security '
                'response headers, verbose server fingerprints, over-permissive CORS, unsigned or '
                'expiring JWTs, plus two injection traces visible in the responses themselves — '
                'database error messages echoed back (sqli) and request parameters reflected into '
                'HTML without encoding (xss). Every check is passive and read-only: it only inspects '
                'traffic you already captured and never sends requests, injects payloads or probes '
                'targets. Returns counts per severity and per category, plus the matched issues with '
                'fix suggestions. Call this when the user asks whether the captured API has security '
                'problems, whether input handling looks unsafe, or wants a security review of recent '
                'traffic.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'severity': {
              'type': 'string',
              'enum': ['high', 'medium', 'low', 'info'],
              'description': 'Only return issues of this severity (optional)',
            },
            'category': {
              'type': 'string',
              'description': 'Only return issues in these categories, comma separated '
                  '(transport, headers, credentials, sqli, xss, disclosure, privacy, custom)',
            },
            'limit': {
              'type': 'integer',
              'description': 'Maximum number of issues to return (default 100)',
            },
          },
        },
      },
      {
        'name': 'get_performance_metrics',
        'description':
            'Report runtime performance metrics: process memory usage (current and peak RSS) and '
                'aggregate capture statistics (request counts by method/status/domain, total size, '
                'average duration, error count). Call this when the user asks how much memory the app '
                'uses, whether capture is slowing things down, or wants a performance overview.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      // ---- 合并后的扩展工具 ----
      {
        'name': 'get_ssl_proxying_list',
        'description':
            'Show the SSL (HTTPS) capture scope: whitelist and blacklist domain rules and whether each is '
                'enabled. Call this when the user asks why some HTTPS traffic is not decrypted, or wants to see '
                'the current SSL capture rules.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'get_tool_catalog',
        'description':
            'Return this server\'s tool catalog grouped by capability (capture / rules / scripts / ssl / device / '
                'security / environment / runtime / meta ...). Call this first when the task is broad or you are '
                'unsure which tool to use, then call tools/list for the full JSON schema of the ones you need.',
        'inputSchema': {'type': 'object', 'properties': {}},
      },
      {
        'name': 'get_client_setup',
        'description':
            'Return connection details for hooking an AI client up to this ProxyPin MCP server: endpoint, '
                'whether a Bearer token is required, and ready-to-paste commands for Claude Code / Codex / curl, '
                'plus the desktop stdio bridge command. Call this when the user asks how to connect an IDE or CLI.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'client': {
              'type': 'string',
              'description': 'Optional: claude | codex | cursor | curl | stdio (omit to get all)',
            },
          },
        },
      },
      {
        'name': 'keep_alive',
        'description':
            'Manage Android keep-alive for this app (or another package) so the MCP server and '
                'capture keep running in the background. Actions: status | enable | disable | apply | '
                'restore. It works through the adb-shell command set (deviceidle whitelist, appops '
                'RUN_*_IN_BACKGROUND, am set-inactive) executed over Shizuku, root or Dhizuku - no '
                'extra app install is needed, but one of those permission channels must be available. '
                'Call this when the user asks why capture stops in the background, wants the app to '
                'survive battery optimisation, or asks to turn keep-alive on or off.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': ['status', 'enable', 'disable', 'apply', 'restore'],
              'description': 'status=query only; enable/disable=persist the setting and apply; '
                  'apply=force apply now; restore=undo the changes (default status)',
            },
            'mode': {
              'type': 'string',
              'enum': ['auto', 'root', 'shizuku', 'dhizuku'],
              'description': 'Permission channel: auto picks the best available (default auto)',
            },
            'package': {
              'type': 'string',
              'description': 'Target package name; omit to use this app itself',
            },
          },
        },
      },
      {
        'name': 'get_mcp_audit',
        'description':
            'Read the MCP server audit log: recent tool calls with caller, duration, success flag, '
                'error message and argument names (argument values are never recorded, to avoid '
                'leaking captured traffic or credentials). Call this when the user asks what tools '
                'were called, why an AI client failed, or wants to review recent MCP activity.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'limit': {
              'type': 'integer',
              'description': 'Maximum number of records to return (default 50, newest last)',
            },
            'tool': {
              'type': 'string',
              'description': 'Only return records for this tool name (optional)',
            },
            'only_failed': {
              'type': 'boolean',
              'description': 'Only return failed calls (optional)',
            },
          },
        },
      },
      {
        'name': 'calculator',
        'description':
            'One entry point for 27 calculation / conversion operations - the whole calculator. '
                'Pick `op`, then pass the matching arguments. Binary ops: int_convert (any-precision '
                'integer to hex/dec/bin/oct plus 8/16/32/64-bit signed-unsigned complement, '
                'big/little-endian hex and ASCII), bitwise (and/or/xor/not/shl/shr/sar/rol/ror), '
                'endian_swap, ieee754 (float32/64 bit layout), crc (crc32/crc16_ccitt/crc16_modbus/'
                'crc16_xmodem/crc16_ibm), hash (md5/sha1/sha256/sha512), mod_op (mod_pow/mod_inverse/'
                'gcd/lcm), codec (base64/base64url/hex/url). Arithmetic: add, subtract, multiply, '
                'division, modulo, sum, floor, ceiling, round (exact for integers via big integers). '
                'Statistics: mean, median, mode, min, max. Trigonometry: sin, cos, tan, arcsin, '
                'arccos, arctan, degrees_to_radians, radians_to_degrees. Call this when analysing '
                'captured traffic and you need to decode an integer field, check a CRC, fix an '
                'endianness mistake, or do arithmetic the model should not guess at.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'op': {
              'type': 'string',
              'enum': [
                'int_convert', 'bitwise', 'endian_swap', 'ieee754', 'crc', 'hash', 'mod_op', 'codec',
                'add', 'subtract', 'multiply', 'division', 'modulo', 'sum', 'floor', 'ceiling', 'round',
                'mean', 'median', 'mode', 'min', 'max',
                'sin', 'cos', 'tan', 'arcsin', 'arccos', 'arctan',
                'degrees_to_radians', 'radians_to_degrees',
              ],
              'description': 'Which operation to run',
            },
            'value': {'type': ['string', 'number'], 'description': 'Primary input (accepts "0x..", "0b..", decimal)'},
            'a': {'type': ['string', 'number'], 'description': 'Operand A'},
            'b': {'type': ['string', 'number'], 'description': 'Operand B / shift amount'},
            'values': {'type': 'array', 'description': 'Numeric array for sum / statistics ops'},
            'width': {'type': 'integer', 'description': 'Bit width for int_convert / bitwise (default 64 / 32)'},
            'widthBytes': {'type': 'integer', 'description': 'Byte width for endian_swap'},
            'operation': {'type': 'string', 'description': 'Bitwise operation name'},
            'shift': {'type': 'integer', 'description': 'Shift/rotate amount'},
            'precision': {'type': 'string', 'enum': ['float32', 'float64'], 'description': 'IEEE754 precision'},
            'algorithm': {'type': 'string', 'description': 'CRC or hash algorithm name'},
            'action': {'type': 'string', 'description': 'Sub-action for crc/hash/mod_op/codec'},
            'data': {'type': ['string', 'number'], 'description': 'Payload for crc / hash'},
            'input': {'type': ['string', 'number'], 'description': 'Payload for codec / ieee754'},
            'inputFormat': {'type': 'string', 'enum': ['hex', 'utf8', 'base64'], 'description': 'How to read data'},
            'base': {'type': ['string', 'number'], 'description': 'mod_pow base'},
            'exponent': {'type': ['string', 'number'], 'description': 'mod_pow exponent'},
            'modulus': {'type': ['string', 'number'], 'description': 'modulus'},
          },
          'required': ['op'],
        },
      },
      {
        'name': 'decode_grpc',
        'description':
            'Decode a gRPC over HTTP/2 message without its .proto file: split the length-prefixed '
                'frames, walk the protobuf wire format to recover field numbers, types and values '
                '(nested messages included), and read grpc-status / grpc-message from the trailers. '
                'Call this when you captured an application/grpc request or response and need to know '
                'which service method was called, what fields were on the wire, or why the call failed.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'body': {'type': 'string', 'description': 'Raw gRPC message body (hex or base64, see bodyFormat)'},
            'bodyFormat': {'type': 'string', 'enum': ['hex', 'base64'], 'description': 'How to read body (default hex)'},
            'contentType': {'type': 'string', 'description': 'Message content-type, e.g. application/grpc'},
            'path': {'type': 'string', 'description': 'HTTP/2 :path, e.g. /pkg.Service/Method'},
            'grpcStatus': {'type': ['string', 'number'], 'description': 'Trailer grpc-status, if captured'},
            'grpcMessage': {'type': 'string', 'description': 'Trailer grpc-message, if captured'},
          },
          'required': ['body'],
        },
      },
      {
        'name': 'batch',
        'description':
            'Run several MCP tool calls inside one request and chain their results, avoiding a '
                'round trip per step. `steps` is an ordered array of {"tool": name, "args": {...}}; a '
                'later step can pull a value out of an earlier result with a reference object of the '
                'form {"\$step": 0, "field": "result.hex"} (field supports dotted paths). Steps run in '
                'order; by default it stops at the first failure (set stop_on_error=false to continue). '
                'Nesting batch inside batch is rejected. Call this when a task needs several dependent '
                'steps, such as decode a base64 field then swap endianness then compute its CRC.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'steps': {
              'type': 'array',
              'description': 'Ordered list of {"tool": "...", "args": {...}} objects (max 20)',
            },
            'stop_on_error': {
              'type': 'boolean',
              'description': 'Stop at the first failed step (default true)',
            },
          },
          'required': ['steps'],
        },
      },
      // 官方工具源（同名者已在本表中提供，见 _nativeToolNames）
      ..._officialToolsJson(),
    ];
  }

  /// gRPC 解析：拆长度前缀帧 + protobuf wire format 盲解，不需要 .proto 也能看字段。
  ///
  /// 「解密」在这里分两层：TLS 那层由 MITM 解决了，剩下的 gRPC 语义层
  /// （长度前缀分帧、protobuf 字段、trailer 里的 grpc-status）由解码器补上。
  Map<String, dynamic> _decodeGrpc(Map<String, dynamic> args) {
    final raw = (args['body'] ?? '').toString();
    if (raw.isEmpty) {
      return {'error': 'body is required'};
    }
    final format = (args['bodyFormat'] ?? 'hex').toString().toLowerCase();
    Uint8List bytes;
    try {
      bytes = _bytesOf(raw, format);
    } catch (e) {
      return {'error': 'cannot parse body as $format: $e'};
    }
    final trailers = <String, String>{};
    if (args['grpcStatus'] != null) {
      trailers['grpc-status'] = '${args['grpcStatus']}';
    }
    if (args['grpcMessage'] != null) {
      trailers['grpc-message'] = '${args['grpcMessage']}';
    }
    final decoded = GrpcDecoder.decode(
      bytes,
      contentType: args['contentType']?.toString(),
      trailers: trailers.isEmpty ? null : trailers,
      path: args['path']?.toString(),
    );
    decoded['summary'] = GrpcDecoder.summarize(decoded);
    return decoded;
  }

  /// 把 hex / base64 文本还原成字节。
  static Uint8List _bytesOf(String raw, String format) {
    if (format == 'base64') {
      return base64Decode(raw.trim());
    }
    var hex = raw.trim().replaceAll(RegExp(r'^0x', caseSensitive: false), '');
    hex = hex.replaceAll(RegExp(r'[\s:_-]'), '');
    if (hex.length.isOdd) {
      hex = '0$hex';
    }
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  /// 单次 batch 允许的最大步数（防止一次请求把服务拖住）。
  static const int maxBatchSteps = 20;

  /// 通用批处理：在一个请求里按序执行多个工具，并支持引用前序结果。
  ///
  /// 引用语法：`{"$step": 0, "field": "result.hex"}` —— 取第 0 步结果的
  /// `result.hex` 字段（field 支持 `a.b` 点路径，省略 field 则取整份结果）。
  /// 每一步都复用 [_runTool]，因此参数校验、并发闸、超时、指标与审计一个都不少。
  Future<Map<String, dynamic>> _handleBatch(Map<String, dynamic> args) async {
    final rawSteps = args['steps'];
    if (rawSteps is! List || rawSteps.isEmpty) {
      return {'error': 'steps must be a non-empty array of {"tool": ..., "args": {...}}'};
    }
    if (rawSteps.length > maxBatchSteps) {
      return {'error': 'too many steps: ${rawSteps.length} (max $maxBatchSteps)'};
    }
    final stopOnError = args['stop_on_error'] as bool? ?? true;
    final results = <Map<String, dynamic>>[];

    for (var i = 0; i < rawSteps.length; i++) {
      final raw = rawSteps[i];
      if (raw is! Map) {
        return {'error': 'step $i is not an object'};
      }
      final tool = raw['tool']?.toString();
      if (tool == null || tool.isEmpty) {
        return {'error': 'step $i is missing "tool"'};
      }
      if (tool == 'batch') {
        return {'error': 'step $i: nested batch is not allowed'};
      }
      final resolved = _resolveStepRefs(raw['args'], results);
      if (resolved is! Map) {
        return {'error': 'step $i: args must be an object'};
      }
      final Map<String, dynamic> callArgs = Map<String, dynamic>.from(resolved);
      // batch 已经持有并发名额，内部步骤不再重复申请，避免互等死锁
      final result = await _runTool(tool, callArgs, caller: 'batch', acquireSlot: false);
      final ok = !(result is Map && result.containsKey('error'));
      results.add({
        'step': i,
        'tool': tool,
        'ok': ok,
        if (!ok) 'error': result is Map ? result['error']?.toString() : '$result',
        'result': result,
      });
      if (!ok && stopOnError) break;
    }

    return {
      'steps_total': rawSteps.length,
      'steps_run': results.length,
      'completed': results.where((r) => r['ok'] == true).length,
      'results': results,
    };
  }

  /// 递归解析步骤参数里的 `{"$step": n, "field": "..."}` 引用。
  dynamic _resolveStepRefs(dynamic node, List<Map<String, dynamic>> results) {
    if (node is Map) {
      if (node.containsKey(r'$step')) {
        final index = (node[r'$step'] as num?)?.toInt();
        if (index == null || index < 0 || index >= results.length) {
          return {'error': 'invalid \$step reference at step $index'};
        }
        dynamic value = results[index]['result'];
        final field = node['field']?.toString();
        if (field != null && field.isNotEmpty) {
          for (final part in field.split('.')) {
            if (value is Map && value.containsKey(part)) {
              value = value[part];
            } else {
              return {'error': 'field "$field" not found in step $index result'};
            }
          }
        }
        return value;
      }
      final mapped = <String, dynamic>{};
      for (final entry in node.entries) {
        mapped[entry.key.toString()] = _resolveStepRefs(entry.value, results);
      }
      return mapped;
    }
    if (node is List) {
      return node.map((e) => _resolveStepRefs(e, results)).toList();
    }
    return node;
  }

  /// 应用保活设置入口（供设置页调用）：开关变化后立即生效。
  Future<Map<String, dynamic>> setKeepAlive(bool enabled) =>
      _handleKeepAlive({'action': enabled ? 'enable' : 'disable'});

  /// 参数强校验开关（供设置页调用）：立即生效，无需重启服务。
  void setStrictValidation(bool enabled) {
    McpToolRuntime.strictValidation = enabled;
  }

  /// 本应用包名（与 android/app/build.gradle 的 applicationId 一致）。
  static const String _appPackage = 'com.network.proxy';

  /// 保活：把目标包加入电池优化白名单并解除后台限制。
  ///
  /// 命令集就是 adb shell 语义（deviceidle / appops / am），通过 Shizuku、root 或
  /// Dhizuku 任一通道执行；不安装任何额外组件，也不需要重启设备。
  Future<Map<String, dynamic>> _handleKeepAlive(Map<String, dynamic> args) async {
    final action = (args['action'] as String? ?? 'status').toLowerCase();
    final mode = (args['mode'] as String?)?.toLowerCase();
    final pkgArg = (args['package'] as String?)?.trim();
    final target = (pkgArg == null || pkgArg.isEmpty) ? _appPackage : pkgArg;
    final config = await Configuration.instance;

    // 只允许包名字符集，避免命令注入
    if (!RegExp(r'^[A-Za-z0-9._]+$').hasMatch(target)) {
      return {'error': 'Invalid package name: $target'};
    }

    if (action == 'status') {
      final probe = 'dumpsys deviceidle whitelist | grep -F "$target" ; '
          'cmd appops get "$target" RUN_IN_BACKGROUND ; '
          'cmd appops get "$target" RUN_ANY_IN_BACKGROUND';
      final out = await McpScreen.shell(probe, useSu: false, mode: mode, timeoutMs: 15000);
      return {
        'package': target,
        'keep_alive_enabled': config.mcpKeepAlive,
        'mode': mode ?? 'auto',
        'raw': out,
      };
    }

    if (action == 'enable' || action == 'disable') {
      config.mcpKeepAlive = action == 'enable';
      ConfigAutoSave.markChanged();
    }

    if (action == 'apply' || action == 'enable') {
      return _keepAliveApply(target, mode);
    }
    if (action == 'restore' || action == 'disable') {
      return _keepAliveRestore(target, mode);
    }
    return {
      'error': 'Unknown action "$action"; expected status | enable | disable | apply | restore',
    };
  }

  Future<Map<String, dynamic>> _keepAliveApply(String pkg, String? mode) async {
    final commands = <String>[
      'dumpsys deviceidle whitelist +$pkg',
      'cmd appops set $pkg RUN_IN_BACKGROUND allow',
      'cmd appops set $pkg RUN_ANY_IN_BACKGROUND allow',
      'am set-inactive $pkg false',
    ];
    final results = <Map<String, dynamic>>[];
    for (final command in commands) {
      try {
        final out = await McpScreen.shell(command, useSu: false, mode: mode, timeoutMs: 15000);
        results.add({'command': command, 'ok': true, 'output': out});
      } catch (e) {
        results.add({'command': command, 'ok': false, 'error': e.toString()});
      }
    }
    final failed = results.where((r) => r['ok'] != true).length;
    return {
      'package': pkg,
      'action': 'apply',
      'mode': mode ?? 'auto',
      'applied': results.length - failed,
      'failed': failed,
      'details': results,
      'note': failed == 0
          ? 'Keep-alive applied. If the permission channel was unavailable, check Shizuku/root status first.'
          : 'Some commands failed - usually means no shell-level channel (Shizuku/root/Dhizuku) is available.',
    };
  }

  Future<Map<String, dynamic>> _keepAliveRestore(String pkg, String? mode) async {
    final commands = <String>[
      'dumpsys deviceidle whitelist -$pkg',
      'cmd appops set $pkg RUN_IN_BACKGROUND default',
      'cmd appops set $pkg RUN_ANY_IN_BACKGROUND default',
    ];
    final results = <Map<String, dynamic>>[];
    for (final command in commands) {
      try {
        final out = await McpScreen.shell(command, useSu: false, mode: mode, timeoutMs: 15000);
        results.add({'command': command, 'ok': true, 'output': out});
      } catch (e) {
        results.add({'command': command, 'ok': false, 'error': e.toString()});
      }
    }
    return {
      'package': pkg,
      'action': 'restore',
      'mode': mode ?? 'auto',
      'details': results,
    };
  }

  Map<String, Map<String, dynamic>>? _schemaIndexCache;

  /// 工具名 → inputSchema 的索引（供统一参数校验）。
  ///
  /// 自有工具与官方工具源合并后构建一次并缓存。schema 里声明得不准的工具
  /// 只是校验不到，不会因为缺 schema 而被拒绝调用。
  Map<String, Map<String, dynamic>> _schemaIndex() {
    final cached = _schemaIndexCache;
    if (cached != null) return cached;
    final index = <String, Map<String, dynamic>>{};
    for (final tool in [..._getToolsList(), ..._officialToolsJson()]) {
      final name = tool['name'];
      final schema = tool['inputSchema'];
      if (name is String && schema is Map) {
        index[name] = Map<String, dynamic>.from(schema);
      }
    }
    _schemaIndexCache = index;
    return index;
  }

  /// 全部工具调用的统一入口：Schema 校验 → 并发闸 → per-tool 超时 → 指标与审计。
  Future<dynamic> _runTool(String name, Map<String, dynamic> args,
      {String caller = 'http', bool acquireSlot = true}) {
    return McpToolRuntime.run(
      name,
      args,
      () => _executeTool(name, args),
      inputSchema: _schemaIndex()[name],
      caller: caller,
      acquireSlot: acquireSlot,
    );
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

      case 'diagnose_capture':
        // 抓包链路只读自检：与界面「抓包自检」同一份结论，便于 AI 先诊断再建议
        final diagnoseRequests = McpBridge().source.toList();
        final diagnoseResult = await CaptureDiagnose.run(diagnoseRequests);
        return diagnoseResult.toJson();

      case 'get_quic_sessions':
        // QUIC 连接概览：会话元数据 + 10 分钟时间轴 + 密钥日志状态 + 已解密流预览
        final quicHostFilter = (args['host_filter'] as String?)?.toLowerCase();
        final quicLimit = (args['limit'] as num?)?.toInt() ?? 50;
        final quicNow = DateTime.now();
        final allQuic = QuicProbe.instance.sessions
          ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
        final quicSessions = (quicHostFilter == null || quicHostFilter.isEmpty)
            ? allQuic
            : allQuic
                .where((s) => s.host.toLowerCase().contains(quicHostFilter))
                .toList();
        final quicKeylog = QuicKeylogStore.instance;
        return {
          'total_sessions': allQuic.length,
          'returned': quicSessions.length > quicLimit ? quicLimit : quicSessions.length,
          'keylog': {
            'imported': !quicKeylog.isEmpty,
            'entries': quicKeylog.entryCount,
            'connections': quicKeylog.connectionCount,
            'hint': quicKeylog.isEmpty
                ? '未导入密钥日志：QUIC 业务数据受 TLS 1.3 加密无法旁路解密，'
                    '需要目标应用导出 SSLKEYLOGFILE 后在 App 内导入。'
                : '已导入密钥日志；命中连接的 1-RTT 客户端方向流数据会自动解密。',
          },
          'timeline': {
            'window_minutes':
                (QuicProbe.timelineBucketCount * QuicProbe.timelineBucketMs) ~/ 60000,
            'bucket_seconds': QuicProbe.timelineBucketMs ~/ 1000,
            'packets': QuicProbe.instance.timelinePackets(),
            'bytes': QuicProbe.instance.timelineBytes(),
          },
          'sessions': quicSessions.take(quicLimit).map((s) {
            return {
              'host': s.host.isEmpty ? '(no SNI)' : s.host,
              'version': s.version,
              'remote': s.remote,
              'dcid': s.dcid,
              'packets': s.packets,
              'frames': s.frames,
              'bytes': s.bytes,
              'first_seen': s.firstSeen.toIso8601String(),
              'last_seen': s.lastSeen.toIso8601String(),
              'last_seen_ago_seconds': quicNow.difference(s.lastSeen).inSeconds,
              'decrypted_streams': s.decrypted.length,
              // QPACK 动态表状态（由本连接的编码器单向流 0x02 还原，上游 #489）
              'qpack_dynamic_table': {
                'insert_count': s.qpackTable.insertCount,
                'live_entries': s.qpackTable.length,
                'capacity': s.qpackTable.capacity,
                'evicted': s.qpackTable.evicted,
              },
              'decrypted': s.decrypted.take(20).map((d) {
                return {
                  'stream_id': d.streamId,
                  'stream_type': d.uniStreamType == null
                      ? null
                      : h3UniStreamTypeName(d.uniStreamType!),
                  'frame': http3FrameName(d.frameType),
                  'length': d.length,
                  'fin': d.fin,
                  // HTTP/3 HEADERS 帧经 QPACK 解出的头部字段（含动态表，上游 #489）
                  if (d.headers.isNotEmpty) 'headers_unresolved': d.headersUnresolved,
                  if (d.headers.isNotEmpty)
                    'headers': d.headers.map((h) => {'name': h.name, 'value': h.value}).toList(),
                  'preview': d.preview,
                };
              }).toList(),
            };
          }).toList(),
        };

      case 'get_security_audit':
        // 对已抓流量跑被动安全自检（只读：不发送请求、不投递载荷）
        final auditRequests = McpBridge().source.toList();
        final auditLimit = (args['limit'] as num?)?.toInt() ?? 100;
        final auditSeverity = args['severity'] as String?;
        final auditCategoryArg = args['category'] as String?;
        final auditCategories = (auditCategoryArg == null || auditCategoryArg.trim().isEmpty)
            ? null
            : auditCategoryArg
                .split(',')
                .map((s) => s.trim().toLowerCase())
                .where((s) => s.isNotEmpty)
                .toSet();
        final auditStore = await SecurityRuleStore.instance;
        final auditReport = SecurityAuditor.audit(
          auditRequests,
          customRules: auditStore.rules,
          onlyCategories: auditCategories,
        );
        final auditIssues = (auditSeverity == null || auditSeverity.isEmpty)
            ? auditReport.issues
            : auditReport.issues
                .where((i) => i.severity.name == auditSeverity)
                .toList();
        return {
          'scanned_requests': auditReport.scannedRequests,
          'total_issues': auditReport.issues.length,
          'clean': auditReport.isClean,
          'by_category': auditReport.byCategory,
          'summary': {
            'high': auditReport.count(SecuritySeverity.high),
            'medium': auditReport.count(SecuritySeverity.medium),
            'low': auditReport.count(SecuritySeverity.low),
            'info': auditReport.count(SecuritySeverity.info),
          },
          'returned': auditIssues.length > auditLimit ? auditLimit : auditIssues.length,
          'issues': auditIssues.take(auditLimit).map((i) {
            return {
              'rule': i.rule,
              'category': SecurityAuditor.categoryOf(i.rule),
              'severity': i.severity.name,
              'title': i.title,
              'method': i.method,
              'url': i.url,
              'detail': i.detail,
              'suggestion': i.suggestion,
              'request_id': i.requestId,
            };
          }).toList(),
        };

      case 'get_performance_metrics':
        // 进程内存 + 抓包聚合统计
        final rss = io.ProcessInfo.currentRss;
        final maxRss = io.ProcessInfo.maxRss;
        return {
          'memory': {
            'current_rss_bytes': rss,
            'current_rss_mb': double.parse((rss / 1024 / 1024).toStringAsFixed(1)),
            'peak_rss_bytes': maxRss,
            'peak_rss_mb': double.parse((maxRss / 1024 / 1024).toStringAsFixed(1)),
          },
          'capture': McpBridge().getStatistics(),
          'captured_requests': McpBridge().source.length,
          // MCP 服务自身的运行指标（调用量/失败率/并发水位），区别于上面的抓包统计
          'mcp': {
            'metrics': McpMetrics.instance.toJson(),
            'gate': McpToolRuntime.gate.toJson(),
            'audit_buffered': McpAuditLog.instance.length,
            'strict_validation': McpToolRuntime.strictValidation,
          },
        };

      case 'calculator':
        final calcOp = (args['op'] ?? '').toString();
        if (calcOp.isEmpty) {
          return {'error': 'op is required', 'supported': CalcEngine.operations};
        }
        return CalcEngine.run(calcOp, args);

      case 'decode_grpc':
        return _decodeGrpc(args);

      case 'batch':
        return await _handleBatch(args);

      case 'keep_alive':
        return await _handleKeepAlive(args);

      case 'get_mcp_audit':
        final auditLimit = (args['limit'] as num?)?.toInt() ?? 50;
        final auditTool = args['tool'] as String?;
        final auditOnlyFailed = args['only_failed'] as bool?;
        final records = McpAuditLog.instance.recent(
          limit: auditLimit,
          tool: auditTool,
          onlyFailed: auditOnlyFailed,
        );
        return {
          'buffered': McpAuditLog.instance.length,
          'returned': records.length,
          'records': records.map((r) => r.toJson()).toList(),
        };

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
        final page = (args['page'] as num?)?.toInt() ?? 0;
        final urlFilter = args['url_filter'] as String?;
        final method = args['method'] as String?;
        final domain = args['domain'] as String?;
        final compact = args['compact'] == true;
        final since = _parseTimeArg(args['since_time'] as String?);
        final until = _parseTimeArg(args['end_time'] as String?);

        // 取到目标页所需的最大条数，再按时间范围过滤 + 分页（借鉴 MCP4HttpCanary 的 AI 友好输出）
        var requests = McpBridge().getRecentRequests(
          limit: (page + 1) * limit,
          urlFilter: urlFilter,
          method: method,
          domain: domain,
        );

        if (since != null || until != null) {
          requests = requests.where((r) {
            if (since != null && r.requestTime.isBefore(since)) return false;
            if (until != null && r.requestTime.isAfter(until)) return false;
            return true;
          }).toList();
        }

        final start = page * limit;
        final pageItems =
            start < requests.length ? requests.skip(start).take(limit).toList() : <HttpRequest>[];

        if (compact) {
          return pageItems.map(_compactRequestJson).toList();
        }
        return pageItems.map((r) => McpBridge.requestToJson(r)).toList();

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


      case 'get_ssl_proxying_list':
        {
          Map<String, dynamic> pack(bool enabled, List<RegExp> rules) => {
                'enabled': enabled,
                'count': rules.length,
                'rules': rules.map((r) => r.pattern).toList(),
              };
          return {
            'whitelist': pack(HostFilter.whitelist.enabled, HostFilter.whitelist.list),
            'blacklist': pack(HostFilter.blacklist.enabled, HostFilter.blacklist.list),
            'semantics':
                '白名单启用时只解密名单内域名；黑名单启用时跳过名单内域名（规则可写 host 或 URL 前缀）。',
          };
        }

      case 'get_tool_catalog':
        {
          final groups = <String, List<String>>{};
          for (final t in _getToolsList()) {
            final name = t['name']?.toString() ?? '';
            if (name.isEmpty || name == 'get_tool_catalog') continue;
            groups.putIfAbsent(_toolGroup(name), () => <String>[]).add(name);
          }
          for (final v in groups.values) {
            v.sort();
          }
          final sortedKeys = groups.keys.toList()..sort();
          return {
            'total': groups.values.fold<int>(0, (a, b) => a + b.length),
            'groups': {for (final k in sortedKeys) k: groups[k]},
            'note': '按能力分组；完整 JSON Schema 请调用 tools/list。',
          };
        }

      case 'get_client_setup':
        {
          final port = _port ?? 9010;
          final loopback = 'http://127.0.0.1:$port/mcp';
          final tok = _token;
          final want = args['client']?.toString().toLowerCase();
          final out = <String, dynamic>{
            'endpoint': _lanMode ? 'http://<device-ip>:$port/mcp' : loopback,
            'transport': 'streamable-http',
            'bearer_token_required': _lanMode,
            if (_lanMode) 'bearer_token': tok,
            'stdio_bridge': 'ProxyPin App 以 --mcp-stdio 参数启动即作为 stdio 桥转发到本地 HTTP',
          };
          final claude = 'claude mcp add proxypin -s user --transport http $loopback';
          final codex = 'codex mcp add proxypin --url $loopback';
          final curl =
              'curl -s $loopback -H "Content-Type: application/json" -d \'{"jsonrpc":"2.0","id":1,"method":"tools/list"}\'';
          if (want == null || want.isEmpty) {
            out['commands'] = {
              'claude_code': claude,
              'codex': codex,
              'curl': curl,
            };
          } else {
            out['command'] = switch (want) {
              'claude' => claude,
              'codex' => codex,
              'curl' => curl,
              'stdio' => out['stdio_bridge'],
              'cursor' => '在 Cursor 的 mcpServers 中配置: {"proxypin": {"url": "$loopback"}}',
              _ => 'unknown client: $want (可选 claude | codex | cursor | curl | stdio)',
            };
          }
          return out;
        }

      default:
        // 自有工具未命中：转交官方工具源（规则 CRUD / 脚本 / Hosts / SSL / 构造请求等）
        try {
          return await _executeOfficialTool(name, args);
        } on ToolException catch (e) {
          // 可预期的参数/状态错误，直接回给模型，不吞成堆栈
          return {'error': e.message, 'tool': name};
        }
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
  /// 解析时间参数（支持 `YYYY-MM-DD` 或 `YYYY-MM-DD HH:mm`），无法解析返回 null
  DateTime? _parseTimeArg(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim().replaceFirst(' ', 'T'));
  }

  /// 精简版请求 JSON（仅核心字段，降低 AI 读取 token，借鉴 MCP4HttpCanary）
  Map<String, dynamic> _compactRequestJson(HttpRequest r) {
    return {
      'id': r.requestId,
      'method': r.method.name,
      'url': r.requestUrl,
      'status': r.response?.status.code,
      'duration': r.response?.responseTime.difference(r.requestTime).inMilliseconds,
      'contentType': r.response?.headers.contentType,
    };
  }

  Map<String, dynamic> _compareHeaders(
    Map<String, dynamic> h1,
    Map<String, dynamic> h2,
  ) {
    // 上游 #901 起 toMap() 对多值头返回 List，这里统一按字符串比较，避免类型断言崩溃
    String s(dynamic v) => v is List ? v.join(', ') : v.toString();
    var added = <String, dynamic>{};
    var removed = <String, dynamic>{};
    var changed = <String, Map<String, String>>{};

    // 检查新增和修改
    h2.forEach((key, value) {
      if (!h1.containsKey(key)) {
        added[key] = value;
      } else if (s(h1[key]) != s(value)) {
        changed[key] = {'old': s(h1[key]), 'new': s(value)};
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
