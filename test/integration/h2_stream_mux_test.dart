/*
 * HTTP/2（h2c 明文前置知识）多流与流取消端到端测试。
 *
 * 与既有 test/h2c_proxy_test.dart 的互补点（那边关注前置帧 / 多流合并 / 连接复用）：
 *   1) **上游乱序响应不串流**：/slow 延迟 600ms、/fast 立即返回，两条响应在两个流上
 *      严格各自归属（:status/body/流号对应），证明代理按 streamId 分发而不是按到达顺序。
 *   2) **RST_STREAM 取消已转发的流**：客户端 reset → 上游必须真实收到 reset；
 *      该流此后再无 HEADERS 转发；被取消的流不得再收到响应；连接与后续新流不受影响。
 *   3) **RST 与后续请求同批到达**：reset 只转发一次，新流正常。
 *   4) **多 DATA 帧的大响应体**：跨帧拼接顺序与流号归属正确，POST 字节不串流。
 *
 * 全链路真实 socket：raw h2c client → proxypin 代理(真实 Server) → raw h2c 上游。
 * 不打 integration 标签，CI 会真实执行。
 */
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/network.dart';
import 'package:proxypin/network/handle/http_proxy_handle.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/h2/hpack/hpack.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/file_read.dart';

@Timeout(Duration(seconds: 90))

const _preface = 'PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n';
const _endStream = 1;
const _endHeaders = 4;
const _slowDelay = Duration(milliseconds: 600);

List<int> _frame(int type, int flags, int stream, List<int> body) => [
      body.length >> 16,
      (body.length >> 8) & 255,
      body.length & 255,
      type,
      flags,
      (stream >> 24) & 127,
      (stream >> 16) & 255,
      (stream >> 8) & 255,
      stream & 255,
      ...body,
    ];

/// HTTP/2 帧切分（跨 TCP 读也能粘回完整帧）。
class _FrameBuffer {
  final bytes = <int>[];

  List<(int, int, int, List<int>)> add(List<int> incoming) {
    bytes.addAll(incoming);
    final frames = <(int, int, int, List<int>)>[];
    while (bytes.length >= 9) {
      final length = (bytes[0] << 16) | (bytes[1] << 8) | bytes[2];
      if (bytes.length < length + 9) break;
      final stream = ((bytes[5] & 127) << 24) | (bytes[6] << 16) | (bytes[7] << 8) | bytes[8];
      frames.add((bytes[3], bytes[4], stream, bytes.sublist(9, length + 9)));
      bytes.removeRange(0, length + 9);
    }
    return frames;
  }
}

class _Capture extends EventListener {
  final requests = <HttpRequest>[];
  final responses = <HttpResponse>[];

  @override
  void onRequest(Channel channel, HttpRequest request) => requests.add(request);

  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) => responses.add(response);
}

/// 客户端：一条 h2c 连接上开多个流，按流号收响应（HPACK 解码器必须整连接复用）。
class _Peer {
  final io.Socket socket;
  final encoder = HPackEncoder();
  final decoder = HPackDecoder();
  final _frames = _FrameBuffer();
  final headers = <int, Map<String, String>>{};
  final _bodies = <int, List<int>>{};
  final _done = <int, Completer<void>>{};
  final settings = Completer<void>();
  final rstSent = <int>[];

  _Peer(this.socket) {
    socket.listen((bytes) {
      for (final (type, flags, stream, payload) in _frames.add(bytes)) {
        if (type == 4 && flags == 0) {
          socket.add(_frame(4, 1, 0, []));
          if (!settings.isCompleted) settings.complete();
        }
        if (type == 1) {
          headers[stream] = {for (final header in decoder.decode(payload)) header.nameString: header.valueString};
        }
        if (type == 0) _bodies.putIfAbsent(stream, () => []).addAll(payload);
        if ((type == 0 || type == 1) && (flags & _endStream) != 0) {
          _done.putIfAbsent(stream, Completer<void>.new).complete();
        }
      }
    });
  }

  List<int> request(int stream, int originPort, String path, {String? body}) {
    _done.putIfAbsent(stream, Completer<void>.new);
    final payload = body == null ? <int>[] : utf8.encode(body);
    return [
      ..._frame(1, body == null ? (_endHeaders | _endStream) : _endHeaders, stream, encoder.encode([
        Header.ascii(':method', body == null ? 'GET' : 'POST'),
        Header.ascii(':scheme', 'http'),
        Header.ascii(':authority', '127.0.0.1:$originPort'),
        Header.ascii(':path', path),
        if (body != null) Header.ascii('content-length', '${payload.length}'),
      ])),
      if (body != null) ..._frame(0, _endStream, stream, payload),
    ];
  }

  List<int> reset(int stream) {
    rstSent.add(stream);
    return _frame(3, 0, stream, [0, 0, 0, 0]);
  }

  void begin(int stream) => _done.putIfAbsent(stream, Completer<void>.new);

  Future<void> done(int stream, {Duration timeout = const Duration(seconds: 10)}) =>
      _done.putIfAbsent(stream, Completer<void>.new).future.timeout(timeout);

  String body(int stream) => utf8.decode(_bodies[stream] ?? const <int>[]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Server proxy;
  late io.ServerSocket origin;
  late io.Directory work;
  late _Capture capture;
  late int proxyPort;
  final sockets = <io.Socket>[];
  final errors = <Object>[];

  // 上游侧观测点
  final originPaths = <int, String>{};
  final originRst = <int>[];
  final originHeadersAfterReset = <int>[];
  final originBodies = <int, String>{};
  var originConnections = 0;
  String? previousHome;

  setUpAll(() async {
    previousHome = FileRead.userHome;
    work = await io.Directory.systemTemp.createTemp('proxypin-h2-mux-');
    FileRead.userHome = work.path;
  });

  tearDownAll(() async {
    FileRead.userHome = previousHome;
    try {
      await work.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    originPaths.clear();
    originRst.clear();
    originHeadersAfterReset.clear();
    originBodies.clear();
    originConnections = 0;
    errors.clear();
    capture = _Capture();

    // ---- 上游：真实 h2c 服务（裸 socket + HPACK） ----
    origin = await io.ServerSocket.bind(io.InternetAddress.loopbackIPv4, 0);
    origin.listen((socket) {
      sockets.add(socket);
      originConnections++;
      var awaitingPreface = true;
      final prefix = <int>[];
      final frames = _FrameBuffer();
      final decoder = HPackDecoder();
      final encoder = HPackEncoder();

      void reply(int stream, String text, {int chunks = 1}) {
        if (originRst.contains(stream)) return; // 已取消的流不再回包（真实服务端行为）
        final bytes = utf8.encode(text);
        final head = _frame(1, _endHeaders, stream, encoder.encode([
          Header.ascii(':status', '200'),
          Header.ascii('content-type', 'text/plain'),
          Header.ascii('content-length', '${bytes.length}'),
        ]));
        final data = <int>[];
        for (var i = 0; i < chunks; i++) {
          final from = (bytes.length * i) ~/ chunks;
          final to = (bytes.length * (i + 1)) ~/ chunks;
          data.addAll(_frame(0, i == chunks - 1 ? _endStream : 0, stream, bytes.sublist(from, to)));
        }
        socket.add(<int>[...head, ...data]);
      }

      socket.listen((incoming) {
        List<int> bytes = incoming;
        if (awaitingPreface) {
          prefix.addAll(bytes);
          if (prefix.length < _preface.length) return;
          expect(prefix.sublist(0, _preface.length), ascii.encode(_preface));
          awaitingPreface = false;
          bytes = prefix.sublist(_preface.length);
          socket.add(_frame(4, 0, 0, []));
        }
        for (final (type, flags, stream, payload) in frames.add(bytes)) {
          if (type == 4 && flags == 0) socket.add(_frame(4, 1, 0, []));
          if (type == 6 && flags == 0) socket.add(_frame(6, 1, 0, payload));
          if (type == 3) {
            originRst.add(stream);
            continue;
          }
          if (type == 1) {
            if (originRst.contains(stream)) originHeadersAfterReset.add(stream);
            originPaths[stream] =
                {for (final h in decoder.decode(payload)) h.nameString: h.valueString}[':path'] ?? '';
          }
          if (type == 0) {
            originBodies[stream] = (originBodies[stream] ?? '') + utf8.decode(payload);
          }
          if ((type == 0 || type == 1) && (flags & _endStream) != 0) {
            final path = originPaths[stream] ?? '';
            final body = originBodies[stream] ?? '';
            if (path.startsWith('/slow')) {
              Future<void>.delayed(_slowDelay).then((_) => reply(stream, '$path|$body'));
            } else if (path.startsWith('/big')) {
              reply(stream, '$path|$body|${'B' * 3000}', chunks: 3);
            } else {
              reply(stream, '$path|$body');
            }
          }
        }
      }, onError: (Object e) => errors.add(e), onDone: () {});
    });

    final config = Configuration.fromJson({
      'enableSsl': false,
      'enableSocks5': false,
      'enableSystemProxy': false,
      'enabledHttp2': false,
    });
    proxy = Server(config, listener: capture);
    proxy.initChannel((channel) {
      channel.dispatcher.channelHandle(HttpServerCodec(), HttpProxyChannelHandler(listener: capture, interceptors: []));
    });
    proxyPort = (await proxy.bind(0)).port;
  });

  tearDown(() async {
    for (final socket in sockets) {
      try {
        socket.destroy();
      } catch (_) {}
    }
    sockets.clear();
    await proxy.stop();
    await origin.close();
  });

  Future<_Peer> peer() async {
    final socket = await io.Socket.connect(io.InternetAddress.loopbackIPv4, proxyPort);
    sockets.add(socket);
    final p = _Peer(socket);
    socket.add([...ascii.encode(_preface), ..._frame(4, 0, 0, [])]);
    await p.settings.future.timeout(const Duration(seconds: 5));
    return p;
  }

  Future<bool> waitUntil(bool Function() ok, {Duration timeout = const Duration(seconds: 5)}) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (ok()) return true;
      if (DateTime.now().isAfter(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('多流并发：上游乱序响应严格按 streamId 归属，不串流', () async {
    final p = await peer();
    p.socket.add([
      ...p.request(1, origin.port, '/slow'),
      ...p.request(3, origin.port, '/fast'),
    ]);

    await p.done(3);
    expect(p.headers[3]?[':status'], '200');
    expect(p.body(3), '/fast|');
    expect(p.headers.containsKey(1), isFalse, reason: '/slow 未到延迟时间前不得有响应');

    await p.done(1);
    expect(p.headers[1]?[':status'], '200');
    expect(p.body(1), '/slow|', reason: '两条响应绝不能互换（必须按 streamId 分发）');

    expect(capture.requests, hasLength(2));
    expect(capture.requests.map((r) => r.path).toSet(), {'/slow', '/fast'});
    expect(capture.responses, hasLength(2));
    expect(capture.responses.map((r) => r.request?.path).toSet(), {'/slow', '/fast'});
    expect(capture.requests.every((r) => r.protocolVersion == 'HTTP/2'), isTrue);
    expect(originConnections, 1, reason: '同一条客户端连接应复用同一个上游连接');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('RST_STREAM：取消已转发到上游的流（reset 真实到达上游，且该流不再有响应）', () async {
    final p = await peer();
    p.begin(1);
    p.socket.add(p.request(1, origin.port, '/slow'));

    // 等上游确实已收到该流的 HEADERS（这才叫「已转发的流」）
    expect(await waitUntil(() => originPaths.containsKey(1)), isTrue, reason: '上游未收到流 1 的请求');

    p.socket.add(p.reset(1));
    expect(await waitUntil(() => originRst.contains(1)), isTrue, reason: '客户端 RST 必须被转发到上游');
    expect(originRst, [1]);

    // 连接仍可用：新流正常完成
    p.socket.add(p.request(3, origin.port, '/after-reset'));
    await p.done(3);
    expect(p.body(3), '/after-reset|');
    expect(p.headers[3]?[':status'], '200');
    expect(originPaths[3], '/after-reset');
    expect(originHeadersAfterReset, isEmpty, reason: '已取消的流不得再向上游打开');

    // 被取消的流不应再收到响应（上游收到 reset 后不回包，代理也不应伪造）
    var gotResponseFor1 = false;
    try {
      await p.done(1, timeout: _slowDelay + const Duration(milliseconds: 400));
      gotResponseFor1 = true;
    } catch (_) {
      gotResponseFor1 = false;
    }
    expect(gotResponseFor1, isFalse, reason: '已取消的流不应收到响应');

    expect(capture.requests.map((r) => r.path).toSet(), {'/slow', '/after-reset'});
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('RST 与后续请求同批到达：reset 只转发一次，新流不受牵连', () async {
    final p = await peer();
    p.begin(1);
    p.socket.add(p.request(1, origin.port, '/slow'));
    expect(await waitUntil(() => originPaths.containsKey(1)), isTrue);

    // 同一批字节里：reset(1) + 新流 3
    p.socket.add([...p.reset(1), ...p.request(3, origin.port, '/coalesced')]);
    await p.done(3);
    expect(p.body(3), '/coalesced|');
    expect(await waitUntil(() => originRst.contains(1)), isTrue);
    expect(originRst.where((s) => s == 1), hasLength(1), reason: 'reset 不能重复转发');
    expect(originPaths[1], '/slow', reason: '流 1 不应被同批的新请求覆盖');
    expect(originPaths[3], '/coalesced');
    expect(originHeadersAfterReset, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('多 DATA 帧的大响应：跨帧拼接顺序与流号归属正确，POST 字节不串流', () async {
    final p = await peer();
    final pad = 'B' * 3000;
    p.socket.add([
      ...p.request(1, origin.port, '/big/one', body: 'alpha'),
      ...p.request(3, origin.port, '/big/two', body: 'beta'),
    ]);

    await p.done(1);
    await p.done(3);
    expect(p.body(1), '/big/one|alpha|$pad', reason: '3 个 DATA 帧必须按序重组且不与流 3 混合');
    expect(p.body(3), '/big/two|beta|$pad');
    expect(p.headers[1]?['content-length'], '${'/big/one|alpha|$pad'.length}');
    expect(capture.requests.map((r) => utf8.decode(r.body ?? const <int>[])).toSet(), {'alpha', 'beta'});
    expect(capture.responses.map((r) => r.bodyAsString).toSet(), {'/big/one|alpha|$pad', '/big/two|beta|$pad'});
    expect(originBodies[1], 'alpha');
    expect(originBodies[3], 'beta');
  }, timeout: const Timeout(Duration(seconds: 30)));
}
