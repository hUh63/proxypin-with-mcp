/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/h2/h2_codec.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/channel/network.dart';
import 'package:proxypin/network/util/byte_buf.dart';
import 'package:proxypin/network/util/byte_utils.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/system_proxy.dart';
import 'package:proxypin/network/util/socks5.dart';
import 'package:proxypin/network/util/attribute_keys.dart';
import 'package:proxy_manager/proxy_manager.dart';

import '../channel/channel.dart';
import 'codec.dart';
import 'h2/frame.dart';
import 'h2/setting.dart';

class HttpClients {
  static Future<Channel> startConnect(HostAndPort hostAndPort, {Duration timeout = const Duration(seconds: 3)}) {
    String host = hostAndPort.host;
    //说明支持ipv6
    if (host.startsWith("[") && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }

    return Socket.connect(host, hostAndPort.port, timeout: timeout).then((socket) {
      if (socket.address.type != InternetAddressType.unix) {
        socket.setOption(SocketOption.tcpNoDelay, true);
      }
      return Channel(socket);
    });
  }

  ///代理建立连接
  static Future<Channel> proxyConnect(
      HttpRequest request, HostAndPort hostAndPort, ChannelHandler<HttpResponse> handler, ChannelContext channelContext,
      {ProxyInfo? proxyInfo}) async {
    var client = Client()..initChannel((channel) => channel.dispatcher.channelHandle(HttpClientCodec(), handler));

    if (proxyInfo == null) {
      var proxyTypes = hostAndPort.isSsl() ? ProxyTypes.https : ProxyTypes.http;
      proxyInfo = await SystemProxy.getSystemProxy(proxyTypes);
    }

    HostAndPort connectHost = proxyInfo == null ? hostAndPort : HostAndPort.host(proxyInfo.host, proxyInfo.port!);
    var channel = await client.connect(connectHost, channelContext);

    if (proxyInfo != null) {
      await connectRequest(channelContext, hostAndPort, channel, proxyInfo: proxyInfo);
    }

    if (hostAndPort.isSsl()) {
      await channel.startSecureSocket(channelContext,
          host: hostAndPort.host, supportedProtocols: request.protocolVersion == "HTTP/2" ? ["h2", "http/1.1"] : null);
      if (channelContext.serverChannel?.selectedProtocol == "h2") {
        // 检查是否需要从 HTTP/2 降级到 HTTP/1.1 (#871)
        final shouldFallback = channelContext.getAttribute<bool>(AttributeKeys.h2FallbackToHttp1) == true;
        if (shouldFallback) {
          logger.w('[${channel.id}] HTTP/2 连接降级到 HTTP/1.1');
          channelContext.putAttribute(AttributeKeys.h2FallbackToHttp1, null); // 清除标记
          request.protocolVersion = "HTTP/1.1";
          channel.dispatcher.listen(channel, channelContext);
        } else {
          await Http2ClientHandler(handler).listen(channel, channelContext);
        }
      } else {
        request.protocolVersion = "HTTP/1.1";
        channel.dispatcher.listen(channel, channelContext);
      }
    }

    logger.d(
        "request ${hostAndPort.host}:${hostAndPort.port} ${request.protocolVersion} ${channelContext.serverChannel?.selectedProtocol ?? ''}");

    return channel;
  }

  ///发起代理连接请求
  static Future<Channel> connectRequest(ChannelContext channelContext, HostAndPort hostAndPort, Channel channel,
      {ProxyInfo? proxyInfo}) async {
    // 上游 #825：SOCKS5 上游代理使用二进制握手，不发送 HTTP CONNECT
    if (proxyInfo?.isSocks5 == true) {
      await Socks5Connect.handshake(channelContext, hostAndPort, channel, proxyInfo!);
      return channel;
    }

    ChannelHandler handler = channel.dispatcher.handler;
    //代理 发送connect请求
    var httpResponseHandler = HttpResponseHandler();
    channel.dispatcher.handler = httpResponseHandler;

    HttpRequest proxyRequest = HttpRequest(HttpMethod.connect, '${hostAndPort.host}:${hostAndPort.port}');
    proxyRequest.headers.set(HttpHeaders.HOST, '${hostAndPort.host}:${hostAndPort.port}');

    //proxy Authorization
    if (proxyInfo?.isAuthenticated == true) {
      String auth = base64Encode(utf8.encode("${proxyInfo?.username}:${proxyInfo?.password}"));
      proxyRequest.headers.set(HttpHeaders.PROXY_AUTHORIZATION, 'Basic $auth');
    }

    await channel.write(channelContext, proxyRequest);
    var response = await httpResponseHandler.getResponse(const Duration(seconds: 5));

    channel.dispatcher.handler = handler;

    if (!response.status.isSuccessful()) {
      throw Exception("$hostAndPort Proxy failed to establish tunnel "
          "(${response.status.code} ${response..status.reasonPhrase})");
    }

    return channel;
  }

  /// 建立连接
  static Future<Channel> connect(Uri uri, ChannelHandler handler, ChannelContext channelContext) async {
    Client client = Client()
      ..initChannel((channel) => channel.dispatcher.handle(HttpResponseCodec(), HttpRequestCodec(), handler));
    if (uri.scheme == "https" || uri.scheme == "wss") {
      return client.secureConnect(HostAndPort.of(uri.toString()), channelContext);
    }

    return client.connect(HostAndPort.of(uri.toString()), channelContext);
  }

  /// 发送get请求
  static Future<HttpResponse> get(String url, {Duration timeout = const Duration(seconds: 3)}) async {
    HttpRequest msg = HttpRequest(HttpMethod.get, url);
    return request(HostAndPort.of(url), msg, timeout: timeout);
  }

  /// 发送请求 - 带重试机制 (#892)
  static Future<HttpResponse> request(HostAndPort hostAndPort, HttpRequest request,
      {Duration timeout = const Duration(seconds: 3), int retryCount = 2}) async {
    int attempts = 0;
    Exception? lastError;

    while (attempts <= retryCount) {
      try {
        var httpResponseHandler = HttpResponseHandler();

        var client = Client()
          ..initChannel(
              (channel) => channel.dispatcher.handle(HttpResponseCodec(), HttpRequestCodec(), httpResponseHandler));

        ChannelContext channelContext = ChannelContext();
        Channel channel = await client.connect(hostAndPort, channelContext);
        await channel.write(channelContext, request);

        return await httpResponseHandler.getResponse(timeout).whenComplete(() => channel.close());
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        attempts++;
        if (attempts <= retryCount) {
          // 指数退避：100ms, 200ms, 400ms...
          await Future.delayed(Duration(milliseconds: 100 * attempts));
        }
      }
    }

    throw lastError ?? Exception('Request failed after ${retryCount + 1} attempts');
  }

  /// 发送代理请求
  static Future<HttpResponse> proxyRequest(HttpRequest request,
      {ProxyInfo? proxyInfo, Duration timeout = const Duration(seconds: 30)}) async {
    if (request.headers.host == null || request.headers.host?.trim().isEmpty == true) {
      try {
        var uri = Uri.parse(request.requestUrl);
        request.headers.host = '${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      } catch (_) {}
    }

    ChannelContext channelContext = ChannelContext();
    var httpResponseHandler = HttpResponseHandler();
    request.hostAndPort ??= HostAndPort.of(request.requestUrl);

    Channel channel =
        await proxyConnect(request, proxyInfo: proxyInfo, request.hostAndPort!, httpResponseHandler, channelContext);

    if (!request.uri.startsWith("/")) {
      Uri? uri = request.requestUri;
      // 裸域名（如 https://example.com）的 uri.path 为空，需要补一个 "/"，
      final path = uri!.path.isEmpty ? '/' : uri.path;
      request = request.copy(uri: '$path${uri.hasQuery ? '?${uri.query}' : ''}');
    }

    if (channel.selectedProtocol == 'h2') {
      request.headers.remove(HttpHeaders.HOST);
      request.streamId = 1;
    }
    await channel.write(channelContext, request);
    return httpResponseHandler.getResponse(timeout).whenComplete(() => channel.close());
  }
}

class Http2ClientHandler {
  static const int FLAG_ACK = 0x1;

  /// 窗口归还阈值：累计接收 DATA 字节达到该值时，向上游发送连接级 WINDOW_UPDATE。
  /// 否则连接级窗口（默认 65535）耗尽后上游将停止发送，大响应存在挂起风险。
  static const int _windowUpdateThreshold = 32768;

  ByteBuf byteBuf = ByteBuf();
  Http2ResponseDecoder decoder = Http2ResponseDecoder();
  final ChannelHandler<HttpResponse> handler;

  /// 连接级已消费但未归还的字节数
  int _connectionWindowPending = 0;

  /// 各流已消费但未归还的字节数（流级窗口耗尽同样会导致上游停止发送）
  final Map<int, int> _streamWindowPending = {};

  Http2ClientHandler(this.handler);

  Future<void> listen(Channel channel, ChannelContext channelContext) async {
    channel.dispatcher.encoder = Http2RequestDecoder();
    channel.dispatcher.decoder = decoder;

    channel.socket.listen((data) => onData(channelContext, channel, data),
        onError: (error, trace) => handler.exceptionCaught(channelContext, channel, error, trace: trace),
        onDone: () => handler.channelInactive(channelContext, channel));

    await channel.writeBytes(Http2Codec.connectionPrefacePRI);

    //发送setting
    final streamSetting = StreamSetting();
    streamSetting.headTableSize = 65536;
    streamSetting.initialWindowSize = 1048896;
    streamSetting.maxHeaderListSize = 262144;

    var payload = Uint8List(6 * 3);
    int offset = 0;
    // SETTINGS_HEADER_TABLE_SIZE
    setInt16(payload, offset, 1);
    offset += 2;
    setInt32(payload, offset, streamSetting.headTableSize);
    offset += 4;

    // SETTINGS_INITIAL_WINDOW_SIZE
    setInt16(payload, offset, 4);
    offset += 2;
    setInt32(payload, offset, streamSetting.initialWindowSize);
    offset += 4;

    //SETTINGS_MAX_FRAME_SIZE（此前误写为 maxHeaderListSize，导致声明的帧上限与实现不一致）
    setInt16(payload, offset, 6);
    offset += 2;
    setInt32(payload, offset, streamSetting.maxFrameSize);
    offset += 4;

    var settingFrame = FrameHeader(payload.length, FrameType.settings, 0, 0);
    var buffer = settingFrame.encode()..addAll(payload);
    await channel.writeBytes(buffer);

    // 连接建立后立即扩大连接级接收窗口（默认 65535 对大响应过小）
    await channel.writeBytes(buildWindowUpdateFrame(0, 1048576 - 65535));
  }

  void onData(ChannelContext channelContext, Channel channel, Uint8List data) {
    byteBuf.add(data);
    var decodeResult = decoder.decode(channelContext, byteBuf);

    if (!decodeResult.isDone) {
      return;
    }

    byteBuf.clearRead();

    if (decodeResult.forward != null) {
      // 统计本批次透传帧中的 DATA 字节，按需归还接收窗口
      releaseWindow(channel, decodeResult.forward!);

      ByteBuf buffer = ByteBuf(decodeResult.forward);

      FrameHeader? frameHeader = FrameReader.readFrameHeader(buffer);
      logger.d("Http2ClientHandler forward ${frameHeader?.type}");
      if (frameHeader?.type == FrameType.settings) {
        // 检查是否需要发送 ACK
        if (frameHeader!.hasAckFlag == false) {
          // 发送带有 ACK 标志的 SETTINGS 帧
          var ackFrame = FrameHeader(0, FrameType.settings, FLAG_ACK, 0);
          channel.writeBytes(ackFrame.encode());
        }
      }

      return;
    }

    // 完整响应结束：归还该流剩余窗口并清理
    final streamId = decodeResult.data?.streamId ?? 0;
    _streamWindowPending.remove(streamId);
    releaseWindow(channel, null);

    handler.channelRead(channelContext, channel, decodeResult.data!);
  }

  /// 解析透传帧，累计 DATA 帧字节数；连接级达到阈值或单流达到 512KB 时发送 WINDOW_UPDATE
  void releaseWindow(Channel channel, List<int>? forward) {
    void flush() {
      if (_connectionWindowPending >= _windowUpdateThreshold) {
        channel.writeBytes(buildWindowUpdateFrame(0, _connectionWindowPending));
        _connectionWindowPending = 0;
      }
      _streamWindowPending.removeWhere((streamId, pending) {
        if (pending >= 524288) {
          channel.writeBytes(buildWindowUpdateFrame(streamId, pending));
          return true;
        }
        return false;
      });
    }

    if (forward == null) {
      flush();
      return;
    }

    // 遍历 forward 中的帧，累计 DATA 帧的 payload 长度
    final buffer = ByteBuf(forward);
    while (buffer.readableBytes() >= 9) {
      final header = FrameReader.readFrameHeader(buffer);
      if (header == null) break;
      final payloadLength = header.length;
      if (buffer.readableBytes() < payloadLength) break;
      if (header.type == FrameType.data) {
        _connectionWindowPending += payloadLength;
        _streamWindowPending[header.streamIdentifier] =
            (_streamWindowPending[header.streamIdentifier] ?? 0) + payloadLength;
      }
      buffer.skipBytes(payloadLength);
    }
    flush();
  }

  /// 构造 WINDOW_UPDATE 帧（streamId=0 为连接级）
  static Uint8List buildWindowUpdateFrame(int streamId, int increment) {
    final frame = Uint8List(13);
    // length = 4
    frame[0] = 0;
    frame[1] = 0;
    frame[2] = 4;
    // type = 8 (WINDOW_UPDATE)
    frame[3] = 8;
    // flags = 0
    frame[4] = 0;
    // stream id
    final sid = streamId & 0x7FFFFFFF;
    frame[5] = (sid >> 24) & 0xFF;
    frame[6] = (sid >> 16) & 0xFF;
    frame[7] = (sid >> 8) & 0xFF;
    frame[8] = sid & 0xFF;
    // window size increment（最高位保留，必须为 0）
    final inc = increment & 0x7FFFFFFF;
    frame[9] = (inc >> 24) & 0xFF;
    frame[10] = (inc >> 16) & 0xFF;
    frame[11] = (inc >> 8) & 0xFF;
    frame[12] = inc & 0xFF;
    return frame;
  }
}

class HttpResponseHandler extends ChannelHandler<HttpResponse> {
  Completer<HttpResponse> _completer = Completer<HttpResponse>();

  @override
  Future<void> channelRead(ChannelContext channelContext, Channel channel, HttpResponse msg) async {
    // log.i("[${channel.id}] Response $msg");
    if (!_completer.isCompleted) {
      _completer.complete(msg);
    }
  }

  Future<HttpResponse> getResponse(Duration duration) {
    return _completer.future.timeout(duration);
  }

  void resetResponse() {
    _completer = Completer<HttpResponse>();
  }
}
