import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/channel/network.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';

/// 上游 #969：外部代理 + 客户端 h2 时，CONNECT 的 200 应答被吞掉，HTTPS 请求 5 秒超时。
///
/// 三个缺口：
///  1. `HttpCodec.decode()` 用 *客户端通道* 的 ALPN 决定是否走 h2，却被上游通道的
///     解码器执行 —— 客户端协商 h2 时，上游明文通道收到的
///     `HTTP/1.1 200 Connection established` 被交给 h2 解码器，永远产不出响应；
///  2. `pendingConnectResponse` 只在 `HttpClientCodec.encode()` 置位，而 MITM + 外部
///     代理链路的通道由裸 codec（`HttpResponseCodec` + `HttpRequestCodec`）构造；
///  3. `connectRequest()` 期间临时替换 handler，异常路径不还原。
class _NoopHandler extends ChannelHandler<Uint8List> {}

void main() {
  group('resolveDecodeProtocol（按所属通道取 ALPN）', () {
    test('已知解码通道是明文时，绝不回退到客户端 h2', () {
      // 客户端 App ↔ ProxyPin 协商 h2，但 ProxyPin → 外部代理是明文 HTTP/1.1。
      expect(resolveDecodeProtocol(hasDecodingChannel: true, decodingProtocol: null, clientProtocol: 'h2'), isNull);
      expect(resolveDecodeProtocol(hasDecodingChannel: true, decodingProtocol: null, clientProtocol: 'h2_14'), isNull);
    });

    test('解码通道自己的协议生效', () {
      expect(resolveDecodeProtocol(hasDecodingChannel: true, decodingProtocol: 'h2', clientProtocol: 'http/1.1'),
          'h2');
      expect(resolveDecodeProtocol(hasDecodingChannel: true, decodingProtocol: 'http/1.1', clientProtocol: 'h2'),
          'http/1.1');
    });

    test('拿不到解码通道时才回退客户端协议', () {
      expect(resolveDecodeProtocol(hasDecodingChannel: false, decodingProtocol: null, clientProtocol: 'h2'), 'h2');
      expect(resolveDecodeProtocol(hasDecodingChannel: false, decodingProtocol: null, clientProtocol: null), isNull);
    });
  });

  test('裸 codec 通道上的 CONNECT：200 能解出来，handler 也还原', () async {
    // 假外部代理：收到 CONNECT 后回 200 并保持连接（无 Content-Length、不关闭）。
    final proxyServer = await ServerSocket.bind('127.0.0.1', 0);
    final proxyDone = Completer<void>();
    proxyServer.listen((socket) {
      final buf = <int>[];
      socket.listen((data) {
        buf.addAll(data);
        final text = String.fromCharCodes(buf);
        if (text.contains('\r\n\r\n') && !proxyDone.isCompleted) {
          socket.add('HTTP/1.1 200 Connection established\r\n\r\n'.codeUnits);
          proxyDone.complete();
        }
      }, onError: (_) {});
    });

    final channelContext = ChannelContext();
    final handler = _NoopHandler();
    // 注意：decoder 是裸 HttpResponseCodec、encoder 是 HttpRequestCodec，
    // 与 HttpClients.connect(uri, ...) 建立的通道一致 —— HttpClientCodec.encode()
    // 不会执行，pendingConnectResponse 只能由 connectRequest 自己置位。
    final client = Client()..initChannel((channel) => channel.dispatcher.handle(HttpResponseCodec(), HttpRequestCodec(), handler));
    final channel = await client.connect(HostAndPort.host('127.0.0.1', proxyServer.port), channelContext);
    channelContext.serverChannel ??= channel;

    final started = DateTime.now();
    await HttpClients.connectRequest(channelContext, HostAndPort.host('example.test', 443), channel);
    final elapsed = DateTime.now().difference(started);

    expect(elapsed.inSeconds, lessThan(3), reason: '不应等待 5 秒超时');
    expect(channel.dispatcher.handler, same(handler), reason: '临时 handler 必须还原');

    channel.close();
    await proxyServer.close();
  });

  test('connectRequest 失败路径也会还原 handler', () async {
    // 代理直接回 407，connectRequest 会抛异常；此前 handler 会残留 HttpResponseHandler。
    final proxyServer = await ServerSocket.bind('127.0.0.1', 0);
    proxyServer.listen((socket) {
      final buf = <int>[];
      socket.listen((data) {
        buf.addAll(data);
        if (String.fromCharCodes(buf).contains('\r\n\r\n')) {
          socket.add('HTTP/1.1 407 Proxy Authentication Required\r\nContent-Length: 0\r\n\r\n'.codeUnits);
        }
      }, onError: (_) {});
    });

    final channelContext = ChannelContext();
    final handler = _NoopHandler();
    final client = Client()..initChannel((channel) => channel.dispatcher.handle(HttpResponseCodec(), HttpRequestCodec(), handler));
    final channel = await client.connect(HostAndPort.host('127.0.0.1', proxyServer.port), channelContext);
    channelContext.serverChannel ??= channel;

    await expectLater(
      HttpClients.connectRequest(channelContext, HostAndPort.host('example.test', 443), channel),
      throwsA(isA<Exception>()),
    );
    expect(channel.dispatcher.handler, same(handler), reason: '异常路径也必须还原');

    channel.close();
    await proxyServer.close();
  });
}
