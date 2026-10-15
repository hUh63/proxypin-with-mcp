/*
 * 补充协议端到端测试：WebSocket（握手 + 帧收发 + 帧分片/粘包/二进制/关闭）、
 * SSE（增量推送 + 逐字节分片 + 事件语法 + 负向不误判）。
 *
 * 全链路真实 socket：客户端 → proxypin 代理(真实 Server) → 真实上游服务。
 *   - WebSocket：手工发 Upgrade 请求（绝对形式走代理），独立算 SHA-1 校验
 *     101 的 Sec-WebSocket-Accept，再发 masked 帧、读回显帧，并断言代理侧
 *     onMessage 收到双向明文帧。
 *   - SSE：上游以 chunked 增量下发 text/event-stream，断言客户端侧增量到达
 *     与代理侧 SseChannelHandler 的逐事件解析结果。
 *
 * 不打 integration 标签，CI 会真实执行。
 */
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/network.dart';
import 'package:proxypin/network/handle/http_proxy_handle.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/util/file_read.dart';

@Timeout(Duration(seconds: 120))

const _wsGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

String _acceptOf(String key) => base64.encode(SHA1Digest().process(Uint8List.fromList(utf8.encode('$key$_wsGuid'))));

int _indexOfDoubleCrlf(List<int> b, [int from = 0]) {
  for (var i = from; i + 3 < b.length; i++) {
    if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) return i;
  }
  return -1;
}

Map<String, String> _parseHeaders(String head) {
  final headers = <String, String>{};
  for (final line in head.split('\r\n').skip(1)) {
    final c = line.indexOf(':');
    if (c > 0) headers[line.substring(0, c).trim().toLowerCase()] = line.substring(c + 1).trim();
  }
  return headers;
}

class _Capture extends EventListener {
  final List<HttpRequest> requests = [];
  final List<HttpResponse> responses = [];
  final List<(WebSocketFrame, bool)> messages = [];

  List<String> get fromClient => messages.where((m) => m.$2).map((m) => m.$1.payloadDataAsString).toList();
  List<String> get fromServer => messages.where((m) => !m.$2).map((m) => m.$1.payloadDataAsString).toList();

  @override
  void onRequest(Channel channel, HttpRequest request) => requests.add(request);

  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) => responses.add(response);

  @override
  void onMessage(Channel channel, HttpMessage message, WebSocketFrame frame) => messages.add((frame, frame.isFromClient));
}

/// 轮询等待（避免复杂异步编排，10ms 粒度足够）。
Future<bool> _waitUntil(bool Function() ok, {Duration timeout = const Duration(seconds: 10)}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    if (ok()) return true;
    if (DateTime.now().isAfter(deadline)) return ok();
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// WebSocket 客户端：同一缓冲里既解析握手响应，也切出服务端帧。
class _WsClient {
  final io.Socket socket;
  final List<int> bytes = [];
  final List<({int opcode, List<int> payload})> frames = [];
  bool closed = false;

  /// 握手响应头必须先被消费掉，否则 _pump 会把 HTTP 状态行当成帧头解析出「伪帧」。
  bool _headersConsumed = false;

  _WsClient(this.socket) {
    socket.listen((data) {
      bytes.addAll(data);
      _pump();
    }, onError: (_) {}, onDone: () => closed = true);
  }

  void _pump() {
    if (!_headersConsumed) return;
    while (true) {
      if (bytes.length < 2) return;
      if ((bytes[1] & 0x80) != 0) return; // 服务端帧不得 masked
      final opcode = bytes[0] & 0x0F;
      var len = bytes[1] & 0x7F;
      var offset = 2;
      if (len == 126) {
        if (bytes.length < 4) return;
        len = (bytes[2] << 8) | bytes[3];
        offset = 4;
      } else if (len == 127) {
        return; // 用例不涉及超长帧
      }
      if (bytes.length < offset + len) return;
      frames.add((opcode: opcode, payload: bytes.sublist(offset, offset + len)));
      bytes.removeRange(0, offset + len);
    }
  }

  bool get headersReady => _indexOfDoubleCrlf(bytes) >= 0;

  String get statusLine => latin1.decode(bytes.sublist(0, _indexOfDoubleCrlf(bytes))).split('\r\n').first;

  Map<String, String> get headers => _parseHeaders(latin1.decode(bytes.sublist(0, _indexOfDoubleCrlf(bytes))));

  void consumeHeaders() {
    bytes.removeRange(0, _indexOfDoubleCrlf(bytes) + 4);
    _headersConsumed = true;
    _pump();
  }

  List<String> get texts =>
      frames.where((f) => f.opcode == 0x1).map((f) => utf8.decode(f.payload)).toList(growable: false);

  void sendText(String text) => socket.add(_maskedFrame(0x1, utf8.encode(text)));

  void sendBinary(List<int> payload) => socket.add(_maskedFrame(0x2, payload));

  void sendClose() => socket.add(_maskedFrame(0x8, const [0x03, 0xE8]));

  void sendRaw(List<int> data) => socket.add(data);
}

/// 客户端 -> 服务端：必须 masked。
List<int> _maskedFrame(int opcode, List<int> payload) {
  expect(payload.length, lessThan(126), reason: '用例只构造短帧');
  const mask = [0x11, 0x22, 0x33, 0x44];
  final frame = <int>[0x80 | opcode, 0x80 | payload.length, ...mask];
  for (var i = 0; i < payload.length; i++) {
    frame.add(payload[i] ^ mask[i % 4]);
  }
  return frame;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late io.Directory work;
  late Server proxy;
  late io.HttpServer origin;
  late _Capture capture;
  late int proxyPort;
  late int originPort;
  final sockets = <io.Socket>[];
  String? previousHome;

  setUpAll(() async {
    previousHome = FileRead.userHome;
    work = await io.Directory.systemTemp.createTemp('proxypin-ws-sse-');
    FileRead.userHome = work.path;
  });

  tearDownAll(() async {
    FileRead.userHome = previousHome;
    try {
      await work.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    capture = _Capture();

    origin = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    originPort = origin.port;
    origin.listen((req) async {
      switch (req.uri.path) {
        case '/ws':
          final ws = await io.WebSocketTransformer.upgrade(req);
          ws.listen((message) {
            if (message is String) {
              ws.add('echo:$message');
            } else {
              ws.add(message);
            }
          }, onError: (_) {}, cancelOnError: true);
          return;

        case '/sse':
          req.response.headers.contentType = io.ContentType('text', 'event-stream');
          req.response.headers.chunkedTransferEncoding = true;
          // 第一个事件：分两段写（同一事件跨 chunk）
          req.response.write('data: par');
          await req.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          req.response.write('t-one\n\n');
          await req.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 250));
          req.response.write('event: tick\nid: 7\ndata: part-two\n\n');
          await req.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await req.response.close();
          return;

        case '/sse/byte':
          req.response.headers.contentType = io.ContentType('text', 'event-stream');
          req.response.headers.chunkedTransferEncoding = true;
          // 逐字节写：多字节 UTF-8 字符会跨 chunk 断开（增量解码必须拼回）
          for (final b in utf8.encode('data: 中文-逐字节\n\n')) {
            req.response.add([b]);
            await req.response.flush();
          }
          await req.response.close();
          return;

        case '/sse/multi':
          req.response.headers.contentType = io.ContentType('text', 'event-stream');
          req.response.headers.chunkedTransferEncoding = true;
          req.response.write(': 这是注释行\n');
          req.response.write('data: line-a\n');
          req.response.write('data: line-b\n');
          req.response.write('\n');
          await req.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 30));
          req.response.write('event: tick\n');
          req.response.write('retry: 1500\n');
          req.response.write('unknown: ignored\n');
          req.response.write('data: single\n');
          req.response.write('\n');
          await req.response.flush();
          await req.response.close();
          return;

        case '/plain':
          // 负向用例：普通 chunked 文本不能被当成 SSE 解析
          req.response.headers.contentType = io.ContentType('text', 'plain');
          req.response.headers.chunkedTransferEncoding = true;
          req.response.write('data: 这看起来像事件但不是\n\n');
          await req.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 30));
          req.response.write('second-chunk');
          await req.response.flush();
          await req.response.close();
          return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    });

    final config = Configuration.fromJson({
      'enableSsl': false,
      'enableSocks5': false,
      'enableSystemProxy': false,
      'enabledHttp2': false,
    });
    proxy = Server(config, listener: capture);
    proxy.initChannel((channel) {
      channel.dispatcher.handle(
        HttpRequestCodec(),
        HttpResponseCodec(),
        HttpProxyChannelHandler(listener: capture, interceptors: []),
      );
    });
    proxyPort = (await proxy.bind(0)).port;
  });

  tearDown(() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    sockets.clear();
    await proxy.stop();
    await origin.close(force: true);
  });

  Future<io.Socket> connect() async {
    final socket = await io.Socket.connect(io.InternetAddress.loopbackIPv4, proxyPort);
    sockets.add(socket);
    return socket;
  }

  /// 建立 WS 连接并完成握手（返回已完成握手的客户端）。
  Future<_WsClient> upgrade() async {
    final socket = await connect();
    final client = _WsClient(socket);
    final key = base64.encode(List<int>.generate(16, (i) => i + 1));
    client.sendRaw(ascii.encode('GET http://127.0.0.1:$originPort/ws HTTP/1.1\r\n'
        'Host: 127.0.0.1:$originPort\r\n'
        'Upgrade: websocket\r\n'
        'Connection: Upgrade\r\n'
        'Sec-WebSocket-Key: $key\r\n'
        'Sec-WebSocket-Version: 13\r\n'
        '\r\n'));
    expect(await _waitUntil(() => client.headersReady), isTrue, reason: '未收到 101 响应头');
    expect(client.statusLine, 'HTTP/1.1 101 Switching Protocols');
    expect(client.headers['upgrade']?.toLowerCase(), 'websocket');
    expect(client.headers['connection']?.toLowerCase(), contains('upgrade'));
    expect(client.headers['sec-websocket-accept'], _acceptOf(key), reason: '代理必须原样透传上游握手签名');
    client.consumeHeaders();
    return client;
  }

  /// SSE 客户端：只关心原始字节流（与 server 帧解析无关）。
  Future<({io.Socket socket, List<int> bytes})> sseRequest(String path) async {
    final socket = await connect();
    final bytes = <int>[];
    socket.listen(bytes.addAll, onError: (_) {}, onDone: () {});
    socket.add(ascii.encode('GET http://127.0.0.1:$originPort$path HTTP/1.1\r\n'
        'Host: 127.0.0.1:$originPort\r\n'
        'Accept: text/event-stream\r\n'
        '\r\n'));
    expect(await _waitUntil(() => _indexOfDoubleCrlf(bytes) >= 0), isTrue, reason: '未收到响应头');
    return (socket: socket, bytes: bytes);
  }

  group('WebSocket', () {
    test('握手 + 双向文本帧收发 + 代理侧明文帧捕获', () async {
      final client = await upgrade();

      client.sendText('ping-1');
      expect(await _waitUntil(() => client.texts.isNotEmpty), isTrue, reason: '未收到第 1 个回显帧');
      expect(client.texts.first, 'echo:ping-1');

      client.sendText('ping-2');
      expect(await _waitUntil(() => client.texts.length >= 2), isTrue, reason: '未收到第 2 个回显帧');
      expect(client.texts, ['echo:ping-1', 'echo:ping-2']);

      // 代理侧必须同时看到两个方向的明文帧
      expect(
          await _waitUntil(() =>
              capture.fromClient.containsAll(['ping-1', 'ping-2']) && capture.fromServer.containsAll(['echo:ping-1', 'echo:ping-2'])),
          isTrue,
          reason: '代理侧未捕获双向明文帧：${capture.messages.map((m) => '${m.$2}/${m.$1.payloadDataAsString}').toList()}');

      // 握手请求 / 101 响应也必须是明文可见的
      expect(capture.requests.single.method, HttpMethod.get);
      expect(capture.requests.single.requestUrl, 'http://127.0.0.1:$originPort/ws');
      expect(capture.requests.single.headers.get('Upgrade'), 'websocket');
      expect(capture.responses.any((r) => r.status.code == 101), isTrue);

      client.socket.destroy();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('同一次 TCP 写入里粘包多个帧：代理必须逐帧解码且顺序正确', () async {
      final client = await upgrade();

      // 3 个文本帧合并到一次 socket 写入（模拟 Nagle / TLS 记录合并）
      client.sendRaw([..._maskedFrame(0x1, utf8.encode('a1')), ..._maskedFrame(0x1, utf8.encode('a2')), ..._maskedFrame(0x1, utf8.encode('a3'))]);

      expect(await _waitUntil(() => client.texts.length >= 3), isTrue, reason: '粘包帧未全部回显');
      expect(client.texts, ['echo:a1', 'echo:a2', 'echo:a3']);

      expect(await _waitUntil(() => capture.fromClient.length >= 3), isTrue);
      expect(capture.fromClient, ['a1', 'a2', 'a3'], reason: '代理侧必须按帧边界逐个解出，不能丢帧或粘成一帧');

      client.socket.destroy();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('帧跨 TCP 读分片（逐字节写入）：代理仍能拼出完整帧', () async {
      final client = await upgrade();

      final frame = _maskedFrame(0x1, utf8.encode('split-frame'));
      for (final byte in frame) {
        client.sendRaw([byte]);
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }

      expect(await _waitUntil(() => client.texts.contains('echo:split-frame')), isTrue,
          reason: '逐字节喂入后回显帧未到达：${client.texts}');
      expect(await _waitUntil(() => capture.fromClient.contains('split-frame')), isTrue,
          reason: '代理侧未能从逐字节分片中拼出完整帧：${capture.fromClient}');
      expect(capture.fromClient.where((t) => t == 'split-frame'), hasLength(1), reason: '不能重复产出同一帧');

      client.socket.destroy();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('二进制帧原样转发；关闭帧导致连接收尾', () async {
      final client = await upgrade();

      const payload = [0x00, 0x01, 0x02, 0xFF, 0x7F];
      client.sendBinary(payload);
      expect(await _waitUntil(() => client.frames.any((f) => f.opcode == 0x2)), isTrue, reason: '未收到二进制回显帧');
      final echoed = client.frames.firstWhere((f) => f.opcode == 0x2);
      expect(echoed.payload, payload, reason: '二进制负载必须原样转发');
      expect(capture.messages.any((m) => m.$2 && m.$1.opcode == 0x2), isTrue, reason: '代理侧应记录客户端二进制帧');

      client.sendClose();
      final sawClose = await _waitUntil(() => client.frames.any((f) => f.opcode == 0x8) || client.closed,
          timeout: const Duration(seconds: 5));
      expect(sawClose, isTrue, reason: '发送关闭帧后应收到关闭帧或连接被关闭');

      client.socket.destroy();
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('SSE', () {
    test('chunked 增量下发：客户端侧增量到达，代理侧逐事件解析', () async {
      final (:socket, :bytes) = await sseRequest('/sse');
      final headEnd = _indexOfDoubleCrlf(bytes);
      final head = latin1.decode(bytes.sublist(0, headEnd));
      final headers = _parseHeaders(head);
      expect(head.split('\r\n').first, 'HTTP/1.1 200 OK');
      expect(headers['content-type'], startsWith('text/event-stream'));
      expect(headers['transfer-encoding']?.toLowerCase(), 'chunked', reason: '流式响应必须保留 chunked 编码');
      bytes.removeRange(0, headEnd + 4);

      expect(await _waitUntil(() => utf8.decode(bytes, allowMalformed: true).contains('part-one')), isTrue,
          reason: '第一个事件未到达客户端');
      final firstAt = DateTime.now();

      expect(await _waitUntil(() => utf8.decode(bytes, allowMalformed: true).contains('part-two')), isTrue,
          reason: '第二个事件未到达客户端');
      final secondAt = DateTime.now();
      expect(secondAt.difference(firstAt).inMilliseconds, greaterThanOrEqualTo(100),
          reason: 'SSE 必须增量推送，不能被缓冲到最后一次性返回');

      final body = utf8.decode(bytes, allowMalformed: true);
      expect(body, contains('data: part-one'));
      expect(body, contains('event: tick'));
      expect(body, contains('id: 7'));

      expect(await _waitUntil(() => capture.messages.map((m) => m.$1.payloadDataAsString).contains('part-one')), isTrue,
          reason: '代理侧未解析出第一个事件：${capture.messages.map((m) => m.$1.payloadDataAsString).toList()}');
      expect(await _waitUntil(() => capture.messages.any((m) => m.$1.payloadDataAsString.contains('part-two'))), isTrue);
      final frames = capture.messages.map((m) => m.$1.payloadDataAsString).toList();
      final second = frames.firstWhere((f) => f.contains('part-two'));
      expect(second, contains('event: tick'), reason: 'event 字段应作为标签前缀保留');
      expect(second, contains('id: 7'));

      socket.destroy();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('逐字节分片喂入：多字节 UTF-8 跨 chunk 也必须正确解析（不出现乱码）', () async {
      final (:socket, :bytes) = await sseRequest('/sse/byte');
      bytes.removeRange(0, _indexOfDoubleCrlf(bytes) + 4);

      expect(await _waitUntil(() => utf8.decode(bytes, allowMalformed: true).contains('中文-逐字节')), isTrue,
          reason: '客户端侧未收到完整事件');

      // 代理侧：必须恰好解析出一个事件帧，且内容不是乱码
      expect(await _waitUntil(() => capture.messages.isNotEmpty), isTrue, reason: '代理侧未解析出任何事件');
      await Future<void>.delayed(const Duration(milliseconds: 200)); // 给可能的额外帧留出时间
      final frames = capture.messages.map((m) => m.$1.payloadDataAsString).toList();
      expect(frames, ['中文-逐字节'], reason: '逐字节分片不得产生多余/空/乱码帧：$frames');
      expect(frames.single.contains('\uFFFD'), isFalse, reason: '增量 UTF-8 解码不应产生替换字符');
      expect(capture.messages.single.$1.isFromClient, isFalse, reason: 'SSE 帧属于服务端 -> 客户端方向');

      socket.destroy();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('事件语法：注释忽略、多行 data 合并、event/retry 作为标签保留', () async {
      final (:socket, :bytes) = await sseRequest('/sse/multi');
      bytes.removeRange(0, _indexOfDoubleCrlf(bytes) + 4);

      expect(await _waitUntil(() => capture.messages.length >= 2), isTrue,
          reason: '应解析出 2 个事件：${capture.messages.map((m) => m.$1.payloadDataAsString).toList()}');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final frames = capture.messages.map((m) => m.$1.payloadDataAsString).toList();
      expect(frames, hasLength(2), reason: '注释行不得产出事件帧：$frames');
      expect(frames[0], 'line-a\nline-b', reason: '多行 data 必须按序合并');
      expect(frames[1], contains('event: tick'));
      expect(frames[1], contains('retry: 1500'));
      expect(frames[1], endsWith('single'));
      expect(frames[1].contains('unknown'), isFalse, reason: '未知字段应被忽略');

      // 客户端侧收到的原始字节必须与上游一致（chunk 框架/内容都不能被改写）
      final body = utf8.decode(bytes, allowMalformed: true);
      expect(body, contains(': 这是注释行'));
      expect(body, contains('data: line-a'));
      expect(body, contains('data: line-b'));
      expect(body, contains('unknown: ignored'));

      socket.destroy();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('负向：普通 chunked text/plain 不得被当成 SSE 解析', () async {
      final (:socket, :bytes) = await sseRequest('/plain');
      final headEnd = _indexOfDoubleCrlf(bytes);
      final headers = _parseHeaders(latin1.decode(bytes.sublist(0, headEnd)));
      expect(headers['content-type'], startsWith('text/plain'));
      bytes.removeRange(0, headEnd + 4);

      expect(await _waitUntil(() => utf8.decode(bytes, allowMalformed: true).contains('second-chunk')), isTrue,
          reason: '普通流式响应也应被完整转发给客户端');
      expect(utf8.decode(bytes, allowMalformed: true), contains('data: 这看起来像事件但不是'));

      // 代理侧不应产生任何「事件帧」
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(capture.messages.where((m) => m.$1.opcode == 0x1 && !m.$2), isEmpty,
          reason: '非 text/event-stream 响应不得进入 SSE 解析：${capture.messages.map((m) => m.$1.payloadDataAsString).toList()}');

      socket.destroy();
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
