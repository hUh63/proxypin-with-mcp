/*
 * 网络层读路径的真实流量压测。
 *
 * 对应 docs/network_robustness.md：
 *   §1 读事件串行化（同一连接内读处理严格串行、共享 buffer 不被并发改写）
 *   §3 O(n²) 拷贝（大 body 切帧/累积）
 *   §4 channelRead 迭代化（一次读入多帧不再压栈）
 *
 * 全部走**真实 socket**（proxy -> origin），不打 integration 标签，
 * 因此 CI 上会真实执行——这是这几项改动的主要验证手段。
 */
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/network.dart';
import 'package:proxypin/network/handle/http_proxy_handle.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/file_read.dart';

// 若读路径出现自循环/死锁，宁可让用例超时失败，也不要让 CI 无限挂起。
@Timeout(Duration(minutes: 3))

/// 简单事件监听器：只记录计数，避免把 body 全留在内存里影响压测本身。
class _CountingListener extends EventListener {
  int requests = 0;
  int responses = 0;

  @override
  void onRequest(Channel channel, HttpRequest request) => requests++;

  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) => responses++;
}

/// 诊断用：包装 HttpProxyChannelHandler，记录「解码后真正交给代理的请求」。
/// 用来区分问题是「proxy 没解出后续请求」还是「解出来了但响应没回写」。
class _RecordingHandler extends ChannelHandler<HttpRequest> {
  final HttpProxyChannelHandler inner;
  final List<String> arrived = [];

  _RecordingHandler(this.inner);

  @override
  void channelActive(ChannelContext c, Channel ch) => inner.channelActive(c, ch);

  @override
  Future<void> channelRead(ChannelContext c, Channel ch, HttpRequest msg) {
    arrived.add('${msg.method.name} ${msg.pathAndQuery}');
    return inner.channelRead(c, ch, msg);
  }

  @override
  void channelInactive(ChannelContext c, Channel ch) => inner.channelInactive(c, ch);

  @override
  void exceptionCaught(ChannelContext c, Channel ch, dynamic error, {StackTrace? trace}) =>
      inner.exceptionCaught(c, ch, error, trace: trace);
}

/// 造一段可校验的伪随机数据（固定 seed，便于定位不一致的位置）。
Uint8List makePayload(int length, [int seed = 42]) {
  final rnd = Random(seed);
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = rnd.nextInt(256);
  }
  return out;
}

/// 分片写入，模拟 TCP 碎片 / 慢客户端。
Future<void> writeFragmented(io.Socket socket, List<int> data,
    {int fragment = 8192, Duration gap = Duration.zero}) async {
  var offset = 0;
  while (offset < data.length) {
    final end = min(offset + fragment, data.length);
    socket.add(data.sublist(offset, end));
    offset = end;
    if (gap > Duration.zero) await Future.delayed(gap);
  }
}

/// 读一个 HTTP/1.1 响应头（到 \r\n\r\n），返回 (状态行, 头, 剩余字节)。
///
/// 注意不能先读 `it.current`——首次 `moveNext` 之前访问会抛 StateError。
Future<(String, Map<String, String>, List<int>)> readHead(StreamIterator<List<int>> it) async {
  final buf = <int>[];
  var idx = -1;
  while (idx < 0) {
    if (!await it.moveNext()) {
      throw StateError('响应头未结束：${latin1.decode(buf.sublist(0, min(buf.length, 200)))}');
    }
    buf.addAll(it.current);
    idx = _indexOfDoubleCrlf(buf);
  }
  final headText = latin1.decode(buf.sublist(0, idx));
  final rest = buf.sublist(idx + 4);
  final lines = headText.split('\r\n');
  final headers = <String, String>{};
  for (final line in lines.skip(1)) {
    final c = line.indexOf(':');
    if (c > 0) headers[line.substring(0, c).trim().toLowerCase()] = line.substring(c + 1).trim();
  }
  return (lines.first, headers, rest);
}

int _indexOfDoubleCrlf(List<int> b) {
  for (var i = 0; i + 3 < b.length; i++) {
    if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) return i;
  }
  return -1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Server proxy;
  late io.HttpServer origin;
  late io.Directory work;
  String? previousHome;
  late int proxyPort;
  late int originPort;
  late _CountingListener listener;
  late _RecordingHandler recorder;

  // origin 收到的 body 校验和 + 长度，供断言
  final originReceived = <String, int>{};

  setUpAll(() async {
    previousHome = FileRead.userHome;
    work = await io.Directory.systemTemp.createTemp('proxypin-stress-');
    FileRead.userHome = work.path;
  });

  tearDownAll(() async {
    FileRead.userHome = previousHome;
    await work.delete(recursive: true);
  });

  setUp(() async {
    originReceived.clear();

    // 上游：按路径回不同内容；POST 则回显 body 的字节和，用于校验完整性。
    origin = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    origin.listen((req) async {
      final chunks = <int>[];
      await for (final chunk in req) {
        chunks.addAll(chunk);
      }
      final key = req.uri.path;
      // 用 FNV-1a 做校验和，避免把大 body 存起来
      var hash = 0x811c9dc5;
      for (final b in chunks) {
        hash = ((hash ^ b) * 0x01000193) & 0xFFFFFFFF;
      }
      originReceived[key] = hash;

      if (req.uri.path.startsWith('/down')) {
        final size = int.tryParse(req.uri.queryParameters['n'] ?? '') ?? 1024;
        final payload = makePayload(size, 7);
        req.response.headers.contentLength = payload.length;
        req.response.headers.contentType = io.ContentType.binary;
        req.response.add(payload);
        await req.response.close();
        return;
      }

      final reply = '${chunks.length}:$hash';
      req.response.headers.contentType = io.ContentType.text;
      req.response.write(reply);
      await req.response.close();
    });
    originPort = origin.port;

    final config = Configuration.fromJson({
      'enableSsl': false,
      'enableSocks5': false,
      'enableSystemProxy': false,
      'enabledHttp2': false,
    });
    listener = _CountingListener();
    proxy = Server(config, listener: listener);
    proxy.initChannel((channel) {
      final inner = HttpProxyChannelHandler(listener: listener, interceptors: []);
      recorder = _RecordingHandler(inner);
      channel.dispatcher.channelHandle(HttpServerCodec(), recorder);
    });
    proxyPort = (await proxy.bind(0)).port;
  });

  tearDown(() async {
    await proxy.stop();
    await origin.close(force: true);
  });

  /// 通过代理发一个请求，返回 (状态码, 响应体文本)。
  Future<(int, String)> proxyRequest(io.Socket socket, StreamIterator<List<int>> it, String method, String path,
      {List<int>? body, Map<String, String>? extraHeaders}) async {
    final head = StringBuffer('$method http://127.0.0.1:$originPort$path HTTP/1.1\r\n')
      ..write('Host: 127.0.0.1:$originPort\r\n')
      ..write('Connection: keep-alive\r\n');
    extraHeaders?.forEach((k, v) => head.write('$k: $v\r\n'));
    if (body != null) head.write('Content-Length: ${body.length}\r\n');
    head.write('\r\n');
    socket.add(latin1.encode(head.toString()));
    if (body != null) socket.add(body);

    final (statusLine, headers, rest) = await readHead(it);
    final code = int.parse(statusLine.split(' ')[1]);
    var payload = rest;
    final len = int.tryParse(headers['content-length'] ?? '');
    if (len != null) {
      while (payload.length < len) {
        if (!await it.moveNext()) break;
        payload.addAll(it.current);
      }
    }
    return (code, utf8.decode(payload.sublist(0, min(payload.length, len ?? payload.length)), allowMalformed: true));
  }

  test('§3/§4 大 body 上传：2MB 经代理转发后字节完全一致', () async {
    final body = makePayload(2 * 1024 * 1024);
    final socket = await io.Socket.connect('127.0.0.1', proxyPort);
    final it = StreamIterator(socket);

    final (code, reply) = await proxyRequest(socket, it, 'POST', '/up', body: body);
    expect(code, 200);

    // origin 侧校验和与客户端一致
    var hash = 0x811c9dc5;
    for (final b in body) {
      hash = ((hash ^ b) * 0x01000193) & 0xFFFFFFFF;
    }
    expect(reply, '${body.length}:$hash', reason: '上游收到的字节必须与客户端发出的完全一致');
    expect(originReceived['/up'], hash);

    socket.destroy();
  });

  test('§3/§4 大 body 下载：2MB 响应经代理返回后字节完全一致', () async {
    const size = 2 * 1024 * 1024;
    final socket = await io.Socket.connect('127.0.0.1', proxyPort);
    final it = StreamIterator(socket);

    final head = 'GET http://127.0.0.1:$originPort/down?n=$size HTTP/1.1\r\n'
        'Host: 127.0.0.1:$originPort\r\n'
        'Connection: keep-alive\r\n\r\n';
    socket.add(latin1.encode(head));

    final (statusLine, headers, rest) = await readHead(it);
    expect(int.parse(statusLine.split(' ')[1]), 200);
    expect(int.tryParse(headers['content-length'] ?? ''), size);

    final expected = makePayload(size, 7);
    var got = rest.length;
    var mismatch = -1;
    for (var i = 0; i < rest.length && i < size; i++) {
      if (rest[i] != expected[i]) {
        mismatch = i;
        break;
      }
    }
    while (got < size && mismatch < 0) {
      if (!await it.moveNext()) break;
      final chunk = it.current;
      for (var i = 0; i < chunk.length && got + i < size; i++) {
        if (chunk[i] != expected[got + i]) {
          mismatch = got + i;
          break;
        }
      }
      got += chunk.length;
      if (mismatch >= 0) break;
    }
    expect(mismatch, -1, reason: '第 $mismatch 字节与期望不一致');
    expect(got, greaterThanOrEqualTo(size));

    socket.destroy();
  });

  // 诊断版：把「proxy 解码后收到几个请求」「listener 记了几个请求/响应」打出来，
  // 再在 8 秒内做一次读响应尝试。目的是区分：
  //   A. proxy 只解出首个请求（→ 解码/读循环问题）
  //   B. proxy 解出全部但响应没回写（→ 回写路径问题）
  test('§1 pipelining 诊断：一次写入 10 个请求，观测 proxy 收到几个',
      timeout: const Timeout(Duration(seconds: 25)), () async {
    final rawOrigin = await io.ServerSocket.bind(io.InternetAddress.loopbackIPv4, 0);
    final originConn = <io.Socket>[];
    var matchedAtOrigin = 0;
    rawOrigin.listen((socket) {
      originConn.add(socket);
      final pending = <int>[];
      var headerEnd = -1;
      var contentLength = 0;
      socket.listen((incoming) {
        pending.addAll(incoming);
        while (true) {
          if (headerEnd < 0) {
            final idx = _indexOfDoubleCrlf(pending);
            if (idx < 0) return;
            headerEnd = idx + 4;
            final head = latin1.decode(pending.sublist(0, idx));
            final m = RegExp(r'content-length:\s*(\d+)', caseSensitive: false).firstMatch(head);
            contentLength = m == null ? 0 : int.parse(m.group(1)!);
          }
          final total = headerEnd + contentLength;
          if (pending.length < total) return;
          final bodyLen = total - headerEnd;
          pending.removeRange(0, total);
          headerEnd = -1;
          contentLength = 0;
          matchedAtOrigin++;
          final payload = utf8.encode('$bodyLen');
          socket.add(latin1.encode('HTTP/1.1 200 OK\r\n'
              'Content-Length: ${payload.length}\r\n'
              'Connection: keep-alive\r\n\r\n'));
          socket.add(payload);
        }
      });
    });

    const n = 10;
    final socket = await io.Socket.connect('127.0.0.1', proxyPort);

    final buf = StringBuffer();
    for (var i = 0; i < n; i++) {
      final body = utf8.encode('req-$i-${'x' * (i * 37)}');
      buf.write('POST http://127.0.0.1:${rawOrigin.port}/p$i HTTP/1.1\r\n');
      buf.write('Host: 127.0.0.1:${rawOrigin.port}\r\n');
      buf.write('Connection: keep-alive\r\n');
      buf.write('Content-Length: ${body.length}\r\n\r\n');
      socket.add(latin1.encode(buf.toString()));
      buf.clear();
      socket.add(body);
    }

    // 收集客户端实际收到的字节（3 秒上限），不做 HTTP 解析，只统计数据
    final received = <int>[];
    final sub = socket.listen((d) => received.addAll(d));
    await Future.delayed(const Duration(seconds: 3));
    await sub.cancel();

    final text = latin1.decode(received, allowMalformed: true);
    final okCount = 'HTTP/1.1 200 OK'.allMatches(text).length;
    // ignore: avoid_print
    print('DIAG-PIPE2 客户端收到 ${received.length} 字节, 其中 200 响应 $okCount 个');
    // ignore: avoid_print
    print('DIAG-PIPE2 origin 收到 $matchedAtOrigin 个请求');
    // ignore: avoid_print
    print('DIAG-PIPE2 listener requests=${listener.requests} responses=${listener.responses}');

    socket.destroy();
    for (final c in originConn) {
      c.destroy();
    }
    await rawOrigin.close();

    expect(okCount, n, reason: '客户端应收到 $n 个响应，实际 $okCount 个（收到 ${received.length} 字节）');
  });

  test('慢客户端：分片 + 间隔发送 1MB body，上游收到完整数据', () async {
    final body = makePayload(1024 * 1024, 99);
    final socket = await io.Socket.connect('127.0.0.1', proxyPort);
    final it = StreamIterator(socket);

    final head = 'POST http://127.0.0.1:$originPort/slow HTTP/1.1\r\n'
        'Host: 127.0.0.1:$originPort\r\n'
        'Connection: keep-alive\r\n'
        'Content-Length: ${body.length}\r\n\r\n';
    socket.add(latin1.encode(head));
    // 16KB 一片、每片间隔 2ms：约 64 片，制造大量「读事件与解析重叠」的机会
    await writeFragmented(socket, body, fragment: 16 * 1024, gap: const Duration(milliseconds: 2));

    final (statusLine, headers, rest) = await readHead(it);
    expect(int.parse(statusLine.split(' ')[1]), 200);
    final len = int.tryParse(headers['content-length'] ?? '') ?? 0;
    var payload = rest;
    while (payload.length < len) {
      if (!await it.moveNext()) break;
      payload.addAll(it.current);
    }

    var hash = 0x811c9dc5;
    for (final b in body) {
      hash = ((hash ^ b) * 0x01000193) & 0xFFFFFFFF;
    }
    expect(utf8.decode(payload.sublist(0, min(payload.length, len))), '${body.length}:$hash');

    socket.destroy();
  });

  test('高压：40 并发连接 × 每条 5 个请求，全部 200 且 body 校验一致', () async {
    const connections = 40;
    const perConn = 5;

    Future<void> runOne(int connIndex) async {
      final socket = await io.Socket.connect('127.0.0.1', proxyPort);
      final it = StreamIterator(socket);
      try {
        for (var i = 0; i < perConn; i++) {
          final body = makePayload(4096 + i * 1000, connIndex * 100 + i);
          final (code, reply) = await proxyRequest(socket, it, 'POST', '/c$connIndex-$i', body: body);
          expect(code, 200);
          var hash = 0x811c9dc5;
          for (final b in body) {
            hash = ((hash ^ b) * 0x01000193) & 0xFFFFFFFF;
          }
          expect(reply, '${body.length}:$hash', reason: '连接 $connIndex 第 $i 个请求的 body 被破坏');
        }
      } finally {
        socket.destroy();
      }
    }

    await Future.wait(List.generate(connections, runOne));
  });

  test('混合压力：小请求与大 body 交替，200 次全部成功', () async {
    const rounds = 200;
    final socket = await io.Socket.connect('127.0.0.1', proxyPort);
    final it = StreamIterator(socket);
    try {
      for (var i = 0; i < rounds; i++) {
        final big = i % 10 == 0;
        final body = big ? makePayload(256 * 1024, i) : utf8.encode('small-$i');
        final (code, reply) = await proxyRequest(socket, it, 'POST', '/mix$i', body: body);
        expect(code, 200, reason: '第 $i 轮失败');
        var hash = 0x811c9dc5;
        for (final b in body) {
          hash = ((hash ^ b) * 0x01000193) & 0xFFFFFFFF;
        }
        expect(reply, '${body.length}:$hash', reason: '第 $i 轮 body 校验失败');
      }
    } finally {
      socket.destroy();
    }
  });
}
