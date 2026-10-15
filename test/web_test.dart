/*
 * 代理 CONNECT + TLS 隧道探测单测。
 *
 * 原文件是 @Tags(['integration']) 的“假测试”：只有 print，无断言。
 * 这里改为真断言：
 *   - 纯确定性部分：HttpRequestCodec 把 CONNECT 请求编码成合法 HTTP/1.1 报文；
 *   - 真实链路部分：连本机代理 127.0.0.1:7890，发 CONNECT 建隧道、再 TLS 握手取回响应字节。
 *
 * **保留 @Tags(['integration'])**：真实链路需要本机已运行一个 HTTP 代理（7890）并访问外网，
 * CI 容器里不成立，故由 `flutter test --exclude-tags integration` 跳过。
 * 若只需验证编解码，请见 test/http_codec_pipeline_test.dart（无 socket 依赖，CI 真跑）。
 */

@Tags(['integration'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/http.dart';

void main() {
  test('CONNECT 请求编码为合法 HTTP/1.1 报文', () {
    final codec = HttpRequestCodec();
    final ctx = ChannelContext();
    final request = HttpRequest(HttpMethod.connect, 'www.v2ex.com:443');
    request.headers.set('user-agent', 'Dart/3.0 (dart:io)');
    request.headers.set('accept-encoding', 'gzip');
    request.headers.set(HttpHeaders.hostHeader, 'www.v2ex.com:443');

    final encoded = String.fromCharCodes(codec.encode(ctx, request));

    expect(encoded, startsWith('CONNECT www.v2ex.com:443 HTTP/1.1\r\n'));
    expect(encoded.toLowerCase(), contains('host: www.v2ex.com:443'));
    expect(encoded.toLowerCase(), contains('accept-encoding: gzip'));
    expect(encoded.endsWith('\r\n\r\n'), isTrue, reason: '请求头必须以空行结束：$encoded');
  });

  test('经本地代理建立 CONNECT + TLS 隧道并收到响应字节', () async {
    final task = await Socket.startConnect('127.0.0.1', 7890);
    final socket = await task.socket;
    if (socket.address.type != InternetAddressType.unix) {
      socket.setOption(SocketOption.tcpNoDelay, true);
    }

    const host = 'www.v2ex.com:443';
    final codec = HttpRequestCodec();
    final ctx = ChannelContext();

    // --- 第一步：CONNECT，等代理回 "200 Connection established" ---
    final connectOk = Completer<void>();
    StreamSubscription<List<int>>? subscription;
    subscription = socket.listen((event) {
      subscription?.pause();
      if (!connectOk.isCompleted) connectOk.complete();
    });

    final connectRequest = HttpRequest(HttpMethod.connect, host);
    connectRequest.headers.set('user-agent', 'Dart/3.0 (dart:io)');
    connectRequest.headers.set('accept-encoding', 'gzip');
    connectRequest.headers.set(HttpHeaders.hostHeader, host);
    socket.add(codec.encode(ctx, connectRequest));
    await socket.flush();
    await connectOk.future.timeout(const Duration(seconds: 15));

    // --- 第二步：在隧道上做 TLS 握手 ---
    final secureSocket = await SecureSocket.secure(
      socket,
      host: 'www.v2ex.com',
      onBadCertificate: (certificate) => true,
    );
    expect(secureSocket.peerCertificate, isNotNull);

    // --- 第三步：发 GET，断言拿回 HTTP 响应字节 ---
    final reply = Completer<List<int>>();
    subscription = secureSocket.listen((event) {
      subscription?.pause();
      if (!reply.isCompleted) reply.complete(event);
      subscription?.resume();
    });

    final getRequest = HttpRequest(HttpMethod.get, '/');
    getRequest.headers.set(HttpHeaders.hostHeader, host);
    secureSocket.add(codec.encode(ctx, getRequest));
    await secureSocket.flush();

    final bytes = await reply.future.timeout(const Duration(seconds: 20));
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes), contains('HTTP/1.'));

    await secureSocket.close();
  });
}
