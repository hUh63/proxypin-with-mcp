/*
 * WebSocket 实时流量推送服务（上游 #756）
 *
 * 让 AI 助手（如 Claude Code）或外部工具通过 WebSocket 实时订阅 ProxyPin 的抓包流量，
 * 并以简单双向协议查询状态与历史记录。
 *
 * 协议（服务端 → 客户端，JSON 文本）：
 *   { "type": "config",   "data": { port, historyEnabled, clientCount } }
 *   { "type": "request",  "data": { id, method, url, headers, size, time } }
 *   { "type": "response", "data": { id, method, url, status, size, costMs, time } }
 *   { "type": "message",  "data": { id, url, direction, opcode, binary, payload, payloadLength, time } }
 *   { "type": "pong" | "result" | "error", ... }
 *
 * 客户端 → 服务端（命令）：
 *   { "action": "ping" }
 *   { "action": "status" }
 *   { "action": "list_histories" }
 *   { "action": "get_history", "name": "<会话名>" }
 *
 * 说明：为避免流量洪泛，实时推送只含元数据（不含请求/响应 body）；
 * WebSocket 帧仅在文本帧时输出 payload（截断至 [_maxPayloadChars]）。
 */
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/histories.dart';

class WsTrafficServer implements EventListener {
  static final WsTrafficServer instance = WsTrafficServer._();

  WsTrafficServer._();

  io.HttpServer? _server;
  final Set<io.WebSocket> _clients = {};

  /// 单帧 payload 推送上限，避免大帧撑爆客户端
  static const int _maxPayloadChars = 4096;

  int get clientCount => _clients.length;

  bool get isRunning => _server != null;

  io.HttpServer? get server => _server;

  Configuration? get _configuration => Configuration.loaded;

  /// 启动（端口被占用等异常仅记录日志，不影响抓包主流程）
  Future<void> start(Configuration configuration) async {
    if (_server != null) {
      return;
    }
    final server = await io.HttpServer.bind(
      io.InternetAddress.anyIPv4,
      configuration.wsTrafficPort,
      shared: true,
    );
    _server = server;
    server.listen(_handleRequest, onError: (e) => log.e('WsTrafficServer error', error: e));
    log.i('WsTrafficServer listening on ${server.port}');
  }

  Future<void> stop() async {
    for (final ws in List<io.WebSocket>.of(_clients)) {
      try {
        await ws.close(io.WebSocketStatus.goingAway);
      } catch (_) {}
    }
    _clients.clear();
    final server = _server;
    _server = null;
    try {
      await server?.close(force: true);
    } catch (_) {}
  }

  /// 配置变更时通知已连接客户端
  void broadcastConfig() {
    _broadcast({'type': 'config', 'data': _configPayload()});
  }

  Map<String, dynamic> _configPayload() {
    final c = _configuration;
    return {
      'port': _server?.port,
      'historyEnabled': c?.wsTrafficHistoryEnabled ?? true,
      'clientCount': _clients.length,
    };
  }

  Future<void> _handleRequest(io.HttpRequest request) async {
    if (!io.WebSocketTransformer.isUpgradeRequest(request)) {
      // 便于浏览器/工具自检：非升级请求给出简短说明
      request.response
        ..statusCode = io.HttpStatus.ok
        ..headers.contentType = io.ContentType('application', 'json', charset: 'utf-8')
        ..write(jsonEncode({
          'service': 'ProxyPin WsTrafficServer',
          'hint': '请使用 WebSocket 连接（ws://<host>:<port>）',
        }));
      await request.response.close();
      return;
    }

    try {
      final ws = await io.WebSocketTransformer.upgrade(request);
      _attach(ws);
    } catch (e, t) {
      log.e('WsTrafficServer upgrade 失败', error: e, stackTrace: t);
    }
  }

  void _attach(io.WebSocket ws) {
    _clients.add(ws);
    // 内置心跳：30s 无响应自动断开，保证 clientCount 准确
    ws.pingInterval = const Duration(seconds: 30);
    log.i('WsTrafficServer client connected, total=${_clients.length}');

    // 连接即下发当前配置
    _send(ws, {'type': 'config', 'data': _configPayload()});

    ws.listen(
      (data) => _handleClientMessage(ws, data),
      onDone: () => _detach(ws),
      onError: (e) {
        log.e('WsTrafficServer client error', error: e);
        _detach(ws);
      },
      cancelOnError: true,
    );
  }

  void _detach(io.WebSocket ws) {
    if (_clients.remove(ws)) {
      log.i('WsTrafficServer client disconnected, total=${_clients.length}');
    }
  }

  Future<void> _handleClientMessage(io.WebSocket ws, dynamic data) async {
    Map<String, dynamic>? message;
    try {
      message = jsonDecode(data.toString()) as Map<String, dynamic>;
    } catch (_) {
      _send(ws, {'type': 'error', 'message': '无效的 JSON 命令'});
      return;
    }

    final action = message['action']?.toString();
    switch (action) {
      case 'ping':
        _send(ws, {'type': 'pong', 'time': DateTime.now().millisecondsSinceEpoch});
        break;
      case 'status':
        _send(ws, {'type': 'result', 'action': 'status', 'data': _statusPayload()});
        break;
      case 'list_histories':
        await _listHistories(ws);
        break;
      case 'get_history':
        await _getHistory(ws, message['name']?.toString());
        break;
      default:
        _send(ws, {'type': 'error', 'message': '未知命令: $action'});
    }
  }

  Map<String, dynamic> _statusPayload() {
    final proxy = ProxyServer.current;
    return {
      'captureRunning': proxy?.isRunning ?? false,
      'proxyPort': proxy?.port,
      'wsPort': _server?.port,
      'clientCount': _clients.length,
      'historyEnabled': _configuration?.wsTrafficHistoryEnabled ?? true,
      'time': DateTime.now().millisecondsSinceEpoch,
    };
  }

  Future<void> _listHistories(io.WebSocket ws) async {
    if (!(_configuration?.wsTrafficHistoryEnabled ?? true)) {
      _send(ws, {'type': 'error', 'message': '历史访问已在偏好设置中关闭'});
      return;
    }
    try {
      final storage = await HistoryStorage.instance;
      final list = storage.histories
          .map((h) => {
                'name': h.name,
                'requestLength': h.requestLength,
                'fileSize': h.fileSize,
                'createTime': h.createTime.millisecondsSinceEpoch,
              })
          .toList();
      _send(ws, {'type': 'result', 'action': 'list_histories', 'data': list});
    } catch (e) {
      _send(ws, {'type': 'error', 'message': '读取历史失败: $e'});
    }
  }

  Future<void> _getHistory(io.WebSocket ws, String? name) async {
    if (!(_configuration?.wsTrafficHistoryEnabled ?? true)) {
      _send(ws, {'type': 'error', 'message': '历史访问已在偏好设置中关闭'});
      return;
    }
    if (name == null || name.isEmpty) {
      _send(ws, {'type': 'error', 'message': 'get_history 需要 name 参数'});
      return;
    }
    try {
      final storage = await HistoryStorage.instance;
      final matched = storage.histories.where((h) => h.name == name);
      if (matched.isEmpty) {
        _send(ws, {'type': 'error', 'message': '未找到历史会话: $name'});
        return;
      }
      final item = matched.first;
      final requests = await storage.getRequests(item);
      final data = requests
          .take(500) // 单次最多 500 条，避免响应过大
          .map((r) => {
                'id': r.requestId,
                'method': r.method.name,
                'url': r.requestUrl,
                'status': r.response?.status.code,
                'time': r.requestTime.millisecondsSinceEpoch,
              })
          .toList();
      _send(ws, {
        'type': 'result',
        'action': 'get_history',
        'name': name,
        'total': requests.length,
        'data': data,
      });
    } catch (e) {
      _send(ws, {'type': 'error', 'message': '读取会话失败: $e'});
    }
  }

  // ==================== 流量事件 ====================

  @override
  void onRequest(Channel channel, HttpRequest request) {
    if (_clients.isEmpty) return;
    _broadcast({
      'type': 'request',
      'data': {
        'id': request.requestId,
        'method': request.method.name,
        'url': request.requestUrl,
        'headers': _safeHeaders(request.headers),
        'size': request.contentLength,
        'time': request.requestTime.millisecondsSinceEpoch,
      },
    });
  }

  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) {
    if (_clients.isEmpty) return;
    final request = response.request;
    _broadcast({
      'type': 'response',
      'data': {
        'id': response.requestId,
        'method': request?.method.name,
        'url': request?.requestUrl,
        'status': response.status.code,
        'size': response.contentLength,
        'costMs': request == null ? null : response.responseTime.difference(request.requestTime).inMilliseconds,
        'time': response.responseTime.millisecondsSinceEpoch,
      },
    });
  }

  @override
  void onMessage(Channel channel, HttpMessage message, WebSocketFrame frame) {
    if (_clients.isEmpty) return;
    final isText = frame.isText;
    String? payload;
    if (isText) {
      final text = frame.payloadDataAsString;
      payload = text.length > _maxPayloadChars ? '${text.substring(0, _maxPayloadChars)}…' : text;
    }

    String? url;
    if (message is HttpRequest) {
      url = message.requestUrl;
    } else if (message is HttpResponse) {
      url = message.request?.requestUrl;
    }

    _broadcast({
      'type': 'message',
      'data': {
        'id': message.requestId,
        'url': url,
        'direction': frame.isFromClient == true ? 'client_to_server' : 'server_to_client',
        'opcode': frame.opcode,
        'binary': !isText,
        'payloadLength': frame.payloadLength,
        'payload': payload,
        'time': DateTime.now().millisecondsSinceEpoch,
      },
    });
  }

  /// 只输出首值，避免多值头把消息撑大
  Map<String, dynamic> _safeHeaders(Object headers) {
    try {
      final map = <String, dynamic>{};
      (headers as dynamic).forEach((name, List<String> values) {
        map[name.toString()] = values.isEmpty ? '' : values.first;
      });
      return map;
    } catch (_) {
      return const {};
    }
  }

  void _send(io.WebSocket ws, Map<String, dynamic> message) {
    try {
      ws.add(jsonEncode(message));
    } catch (e) {
      _detach(ws);
    }
  }

  void _broadcast(Map<String, dynamic> message) {
    if (_clients.isEmpty) return;
    final encoded = jsonEncode(message);
    for (final ws in List<io.WebSocket>.of(_clients)) {
      try {
        ws.add(encoded);
      } catch (_) {
        _detach(ws);
      }
    }
  }
}
