import 'dart:async';
import 'dart:convert' show latin1;
import 'dart:io';
import 'dart:typed_data';

import 'package:proxypin/native/process_info.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/handle/relay_handle.dart';
import 'package:proxypin/network/mqtt/mqtt_relay_handler.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/handle/websocket_handle.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/network/util/attribute_keys.dart';
import 'package:proxypin/network/util/byte_buf.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/process_info.dart';
import 'package:proxypin/network/handle/sse_handle.dart';
import 'package:proxypin/network/handle/http_proxy_handle.dart';

import '../util/task_queue.dart';

class ChannelDispatcher extends ChannelHandler<Uint8List> {
  late Decoder decoder;
  late Encoder encoder;
  late ChannelHandler handler;

  final ByteBuf buffer = ByteBuf();

  //h2 stream dependency Sequential exec
  SequentialTaskQueue taskQueue = SequentialTaskQueue();

  /// HTTP/1.1 读事件串行化专用队列。
  ///
  /// `Socket.listen` 的回调不会等待返回的 Future：上一条读事件若在
  /// `channelRead` 的 `await`（如 `remoteChannel.writeBytes`）期间尚未结束，
  /// 下一条读事件就会并发进入并再次读写**同一个** `buffer`，
  /// 造成帧边界/请求体交错（详见 docs/network_robustness.md §1）。
  /// 这里把每个读事件排入本队列，保证同一连接内读处理严格串行。
  ///
  /// 注意：这里**不**改用 taskQueue（其 id 语义是 h2 streamId、且带依赖排序），
  /// 也**不**把 `channelRead` 内部的递归改成队列任务——那会自锁；
  /// 本方案只闸住「两个 socket 读事件之间」的重叠，递归仍在同一任务内完成。
  final SequentialTaskQueue readQueue = SequentialTaskQueue();
  int _readSeq = 0;

  //正在处理中的读事件(HTTP/1.1 不走 taskQueue). 两处 listen(Network.listen / ChannelDispatcher.listen)
  //都汇聚到本 dispatcher 的 channelRead/channelInactive, 故在此层等待可覆盖所有连接类型.
  //channelInactive 需等待其完成再关闭对端连接, 避免服务端关闭时提前关闭客户端连接导致 socket hang up.
  final Set<Completer<void>> _pendingReads = {};

  void handle(Decoder decoder, Encoder encoder, ChannelHandler handler) {
    this.encoder = encoder;
    this.decoder = decoder;
    this.handler = handler;
  }

  void channelHandle(Codec codec, ChannelHandler handler) {
    handle(codec, codec, handler);
  }

  /// 监听
  void listen(Channel channel, ChannelContext channelContext) {
    buffer.clear();
    channel.socket.done.onError((error, StackTrace trace) {
      logger.e('[${channelContext.clientChannel?.id}] secureSocket done error', error: error, stackTrace: trace);
      channel.dispatcher.exceptionCaught(channelContext, channel, error, trace: trace);
      return null;
    });
    final subscription = channel.socket.listen((data) => enqueueRead(channelContext, channel, data),
        onError: (error, trace) => channel.dispatcher.exceptionCaught(channelContext, channel, error, trace: trace),
        onDone: () => channel.dispatcher.channelInactive(channelContext, channel));
    // 记录读订阅：通道关闭时取消，避免停止后仍有残留回调处理数据
    channel.attachSocketSubscription(subscription);
  }

  /// 把一次 socket 读事件排入串行队列（HTTP/1.1 读事件串行化的统一入口）。
  ///
  /// 所有读事件入口（[listen] 与 `Network.onEvent`）都必须走这里，
  /// 否则仍会有并发读事件改写共享 [buffer]。
  void enqueueRead(ChannelContext channelContext, Channel channel, Uint8List data) {
    readQueue.add(++_readSeq, null, () => channelRead(channelContext, channel, data),
        onError: (error, trace) => exceptionCaught(channelContext, channel, error, trace: trace));
  }

  @override
  void channelActive(ChannelContext context, Channel channel) {
    handler.channelActive(context, channel);
  }

  ///远程转发请求
  Future<void> remoteForward(ChannelContext channelContext, HostAndPort remote) async {
    var clientChannel = channelContext.clientChannel!;
    Channel? remoteChannel =
        channelContext.serverChannel ?? await channelContext.connectServerChannel(remote, RelayHandler(clientChannel));
    ProxyInfo? proxyInfo = channelContext.getAttribute(AttributeKeys.proxyInfo);
    if (clientChannel.isSsl && !remoteChannel.isSsl) {
      //代理认证
      if (proxyInfo?.isAuthenticated == true) {
        await HttpClients.connectRequest(channelContext, remote, remoteChannel, proxyInfo: proxyInfo);
      }

      await remoteChannel.secureSocket(channelContext, host: channelContext.getAttribute(AttributeKeys.domain));
    }

    relay(channelContext, clientChannel, remoteChannel);
  }

  /// 转发请求
  void relay(ChannelContext channelContext, Channel clientChannel, Channel remoteChannel) {
    var rawCodec = RawCodec();
    clientChannel.dispatcher.channelHandle(rawCodec, RelayHandler(remoteChannel));
    remoteChannel.dispatcher.channelHandle(rawCodec, RelayHandler(clientChannel));

    var body = buffer.bytes;
    buffer.clear();
    handler.channelRead(channelContext, clientChannel, body);
  }

  @override
  Future<void> channelRead(ChannelContext channelContext, Channel channel, Uint8List msg) async {
    //同步注册: 在首个 await 之前登记, 保证 onDone(channelInactive) 触发时本次读事件已在集合中
    final pending = Completer<void>();
    _pendingReads.add(pending);

    //手机扫码连接转发远程
    HostAndPort? remote = channelContext.getAttribute(AttributeKeys.remote);
    buffer.add(msg);

    try {
      if (remote != null) {
        await remoteForward(channelContext, remote);
        return;
      }

      Channel? remoteChannel = channelContext.getAttribute(channel.id);

      //大body 不解析直接转发
      if (buffer.length > Codec.maxBodyLength && handler is! RelayHandler && handler is! MqttRelayHandler && remoteChannel != null) {
        logger.w("[$channel] forward large body");
        relay(channelContext, channel, remoteChannel);
        return;
      }

      var decodeResult = decoder.decode(channelContext, buffer);

      //If the body does not support parsing, forward directly
      if (decodeResult.supportedParse == false) {
        await notSupportedForward(channelContext, channel, decodeResult);
        return;
      }

      if (decodeResult.forward != null) {
        buffer.clearRead();

        if (remoteChannel != null) {
          await remoteChannel.writeBytes(decodeResult.forward!);
        } else if (channelContext.isHttp2PriorKnowledge && identical(channel, channelContext.clientChannel)) {
          channelContext.bufferHttp2Frames(decodeResult.forward!);
          await channelContext.sendInitialHttp2Settings();
        } else {
          logger.w("[$channel] forward remoteChannel is null");
        }

        if (decodeResult.data == null) {
          return;
        }
      }

      if (!decodeResult.isDone) {
        return;
      }

      var length = buffer.length;
      buffer.clearRead();

      var data = decodeResult.data;
      if (data is HttpMessage) {
        data.packageSize ??= length;
        data.remoteHost = channel.remoteSocketAddress.host;
        data.remotePort = channel.remoteSocketAddress.port;
      }

      if (data is HttpRequest) {
        if (data.protocolVersion == 'HTTP/2') {
          final request = data;
          final sent = channelContext.http2Requests.submit(request.streamId!, () async {
            await prepareRequest(channelContext, channel, request);
            if (channelContext.http2Requests.canForward(request.streamId!)) {
              await handler.channelRead(channelContext, channel, request);
            }
          });
          final guarded = sent.catchError((Object error, StackTrace trace) {
            onError(channelContext, channel, error, trace: trace);
          });
          // 先排空现有帧，不能等较大流号发送后才去解析较小流号的后续 DATA。
          if (buffer.isReadable()) await channelRead(channelContext, channel, Uint8List(0));
          await guarded;
          return;
        }
        await prepareRequest(channelContext, channel, data);
      }

      if (data is HttpResponse) {
        data.request ??= channelContext.currentRequest;
        data.requestId = data.request?.requestId ?? data.requestId;
      }

      //websocket协议
      if (data is HttpResponse && data.isWebSocket && remoteChannel != null) {
        onWebSocketHandle(channelContext, channel, data);
        return;
      }

      if (data is HttpMessage && channelContext.containsStreamDependency(data.streamId)) {
        taskQueue.add(data.streamId!, channelContext.getStreamDependency(data.streamId!)?.streamDependency,
            () => handler.channelRead(channelContext, channel, data),
            onError: (error, stackTrace) => onError(channelContext, channel, error, trace: stackTrace));
      } else {
        await handler.channelRead(channelContext, channel, data!);
      }

      // h2 streaming 请求：HEADERS 帧 emit 后，buffer 里可能还留着已到达的 DATA
      // 帧字节（HEADERS 之后同一次 socket 读入的内容）。此时不再触发新的
      // channelRead（Chrome 已经把整段字节发到 socket），需要主动把剩余字节
      // 交给 decoder，让 DATA 帧走 forward 透传到远端。
      // 只做一次：递归调用里 decodeResult.data == null，走完 forward 后 return。
      if (data is HttpMessage && data.streamingBody && buffer.isReadable()) {
        Channel? remote = channelContext.getAttribute(channel.id);
        if (remote == null) {
          logger.e("[$channel] h2 streaming but remoteChannel is null, drop buffered data");
          buffer.clear();
        } else {
          await channelRead(channelContext, channel, Uint8List(0));
        }
      } else if (data is HttpMessage && data.protocolVersion == 'HTTP/2' && buffer.isReadable()) {
        // 一个TCP读事件可能包含多个完整流；不能依赖下一次socket事件继续解码。
        await channelRead(channelContext, channel, Uint8List(0));
      }
    } catch (error, trace) {
      onError(channelContext, channel, error, trace: trace);
    } finally {
      _pendingReads.remove(pending);
      if (!pending.isCompleted) pending.complete();
    }
  }

  Future<void> prepareRequest(ChannelContext channelContext, Channel channel, HttpRequest data) async {
    channelContext.currentRequest = data;
    data.hostAndPort ??= channelContext.host ?? getHostAndPort(data, ssl: channel.isSsl);
    if (data.headers.host != null && data.headers.host?.contains(":") == false) {
      data.hostAndPort?.host = data.headers.host!;
    }
    await _fixAndroidVpnPort(channelContext, channel, data);
    data.processInfo ??= await ProcessInfoUtils.getProcessByPort(channel.remoteSocketAddress, data.remoteDomain()!);
  }

  /// 修正 Android VPN 透明代理明文 HTTP 请求的目标端口。
  ///
  /// 客户端把请求当作直连发出时（uri 是路径而非绝对 URI），端口只能从 Host 头解析；
  /// 若 Host 头未携带端口（例如 `curl -H "Host: x" http://x:10120/`），
  /// [HostAndPort.of] 会兜底成 80，导致上游连接被拨到错误端口（#530）。
  /// 此时向 VPN 侧查真实目的端口进行覆盖。
  ///
  /// SSL / HTTP2 走 SNI 嗅探或 `:authority`，已经拿到正确端口；
  /// 其它明文情况（绝对 URI / Host 头自带端口）[getHostAndPort] 也能处理。
  Future<void> _fixAndroidVpnPort(ChannelContext channelContext, Channel channel, HttpRequest data) async {
    if (!Platform.isAndroid ||
        channel.isSsl ||
        data.protocolVersion == 'HTTP/2' ||
        !data.uri.startsWith("/") ||
        data.headers.host?.contains(":") == true ||
        data.hostAndPort == null) {
      return;
    }

    final vpnRemote = await ProcessInfoPlugin.getRemoteAddressByPort(channel.remoteSocketAddress.port);
    if (vpnRemote != null && vpnRemote.port != data.hostAndPort!.port) {
      data.hostAndPort = data.hostAndPort!.copyWith(port: vpnRemote.port);
    }
  }

  void onError(ChannelContext channelContext, Channel channel, dynamic error, {StackTrace? trace}) {
    logger.e(
        "[${channelContext.clientChannel?.id}] channelRead error isSsl:${channel.isSsl} client: ${channelContext.clientChannel?.selectedProtocol} server: ${channelContext.serverChannel?.selectedProtocol} ${String.fromCharCodes(buffer.bytes)}",
        error: error,
        stackTrace: trace);
    buffer.clear();
    exceptionCaught(channelContext, channel, error, trace: trace);
  }

  /// websocket 处理
  void onWebSocketHandle(ChannelContext channelContext, Channel channel, HttpResponse data) {
    Channel remoteChannel = channelContext.getAttribute(channel.id);

    data.request?.response = data;
    channelContext.host =
        channelContext.host?.copyWith(scheme: channel.isSsl ? HostAndPort.wssScheme : HostAndPort.wsScheme);
    channelContext.currentRequest?.hostAndPort = channelContext.host;

    logger.d("webSocket ${data.request?.hostAndPort}");
    remoteChannel.write(channelContext, data);

    channelContext.listener?.onResponse(channelContext, data);

    var rawCodec = RawCodec();
    channel.dispatcher.channelHandle(rawCodec, WebSocketChannelHandler(remoteChannel, data));
    remoteChannel.dispatcher.channelHandle(rawCodec, WebSocketChannelHandler(channel, data.request!));
  }

  /// SSE 处理 (text/event-stream)
  void onSseHandle(ChannelContext channelContext, Channel channel, HttpResponse response, List<int>? initialBody) {
    Channel remoteChannel = channelContext.getAttribute(channel.id);
    channelContext.currentRequest?.response = response;
    response.request ??= channelContext.currentRequest;
    channelContext.listener?.onResponse(channelContext, response);

    remoteChannel.write(channelContext, response);

    // Switch to raw streaming: server->client uses SseChannelHandler; client->server just relays
    var rawCodec = RawCodec();
    channel.dispatcher.channelHandle(rawCodec, SseChannelHandler(remoteChannel, response));
    remoteChannel.dispatcher.channelHandle(rawCodec, RelayHandler(channel));

    // Flush any initial body bytes that were already read alongside the
    // headers. Feed them straight to the new handler — going through `buffer`
    // would replay the response-line/headers we already consumed, corrupting
    // the SSE stream.
    if (initialBody != null && initialBody.isNotEmpty) {
      buffer.clear();
      handler.channelRead(channelContext, channel, Uint8List.fromList(initialBody));
    }
  }

  Future<void> notSupportedForward(ChannelContext channelContext, Channel channel, DecoderResult decodeResult) async {
    // relay() 会把本 dispatcher 的 handler 换成 RelayHandler，故先捕获当前 handler，
    // 供后续给“不支持解析”的响应补跑响应拦截器（上游 #956）使用。
    final currentHandler = handler;
    Channel? remoteChannel = channelContext.getAttribute(channel.id);

    // If this is an SSE response, switch to SSE streaming mode instead of generic relay
    if (decodeResult.data is HttpResponse) {
      var response = decodeResult.data as HttpResponse;
      if (response.headers.contentType.toLowerCase().startsWith('text/event-stream') && remoteChannel != null) {
        logger.d("[$channel] switch to SSE streaming");
        onSseHandle(channelContext, channel, response, decodeResult.forward);
        return;
      }
    }

    // 没有可转发的对端通道（例如游离的 "200 Connection established" 代理应答），
    // 无法透传，直接丢弃并关闭连接，避免对 null 强制解包导致崩溃。
    if (remoteChannel == null) {
      logger.w("[$channel] not supported parse and remoteChannel is null, close channel");
      channel.close();
      return;
    }

    // ── #956 受限放开 ──────────────────────────────────────────────
    // 定长且已完整到达的响应体，允许「缓冲 → 跑拦截器 → 改写回写」；
    // 条件不满足时完全走下面的原样转发，行为与放开前逐字节一致，
    // 因此 close-delimited / 分片大 body 等流式场景不受影响。
    if (decodeResult.data is HttpResponse) {
      final handled = await _tryRewriteUnsupportedResponse(
          channelContext, channel, decodeResult.data as HttpResponse, currentHandler);
      if (handled) return;
    }

    // Fallback: generic relay for unsupported body types.
    // `forward` is a view into the same buffer (decoder only advanced the
    // reader index), and `relay` flushes the raw buffer via `.bytes`, so it
    // must NOT be appended here or the body would be sent twice.
    relay(channelContext, channel, remoteChannel);

    if (decodeResult.data is HttpResponse) {
      var response = decodeResult.data as HttpResponse;
      logger.w("[$channel] not supported parse ${response.headers.contentType}");
      response.request ??= channelContext.currentRequest;
      channelContext.currentRequest?.response = response;
      // 上游 #956：close-delimited 等“不支持解析”的响应原样转发时不经 handler，
      // 会导致脚本/重写等的 onResponse 静默失效；此处对响应补跑一次拦截器链。
      final request = response.request;
      if (currentHandler is HttpResponseProxyHandler && request != null) {
        try {
          await currentHandler.interceptUnsupportedResponse(request, response);
        } catch (e, s) {
          logger.e("[$channel] intercept unsupported response failed", error: e, stackTrace: s);
        }
      }
      channelContext.listener?.onResponse(channelContext, response);
    }
  }

  /// #956 受限放开：尝试对「不支持解析」的响应做缓冲-改写-回写。
  ///
  /// 返回 true 表示本次已接管转发与后续通知（调用方不得再 relay）；
  /// 返回 false 表示条件不成立，需回退到原样转发（拦截器尚未运行）。
  ///
  /// 仅当**同时**满足下列条件才接管，任一不满足即回退：
  /// 1. 声明了 `Content-Length`（流式/close-delimited 无此头，天然排除）；
  /// 2. body 已在本缓冲区**完整到达**（`buffer.length - headEnd == contentLength`）；
  /// 3. 体量不超过 [Codec.maxBodyLength]（避免大 body 驻留内存）。
  Future<bool> _tryRewriteUnsupportedResponse(
      ChannelContext channelContext, Channel channel, HttpResponse response, ChannelHandler currentHandler) async {
    final raw = buffer.bytes;
    final headEnd = _headerEndIndex(raw);
    final declared = response.headers.contentLength;
    if (headEnd <= 0 || declared <= 0 || declared > Codec.maxBodyLength || raw.length - headEnd != declared) {
      return false;
    }

    final request = response.request ?? channelContext.currentRequest;
    response.request ??= request;
    final originalBody = Uint8List.sublistView(raw, headEnd);
    response.body = originalBody;

    if (currentHandler is HttpResponseProxyHandler && request != null) {
      try {
        await currentHandler.interceptUnsupportedResponse(request, response);
      } catch (e, s) {
        logger.e("[$channel] intercept unsupported response failed", error: e, stackTrace: s);
      }
    }
    channelContext.currentRequest?.response = response;
    channelContext.listener?.onResponse(channelContext, response);

    final List<int>? newBody = response.body;
    if (newBody == null || _sameBytes(newBody, originalBody)) {
      // body 未被改写：按原字节转发（与放开前完全一致）。
      buffer.clear();
      handler.channelRead(channelContext, channel, raw);
      return true;
    }

    final head = _replaceContentLength(Uint8List.sublistView(raw, 0, headEnd), newBody.length);
    if (head == null) {
      // 找不到可改写的 Content-Length（异常写法）：安全起见按原字节转发，
      // 本次脚本改写被丢弃并告警，绝不发出长度不符的报文。
      logger.w("[$channel] cannot adjust Content-Length, keep original body");
      buffer.clear();
      handler.channelRead(channelContext, channel, raw);
      return true;
    }

    final out = Uint8List(head.length + newBody.length);
    out.setAll(0, head);
    out.setAll(head.length, newBody);
    buffer.clear();
    handler.channelRead(channelContext, channel, out);
    logger.d("[$channel] not-supported response body rewritten ($declared -> ${newBody.length} bytes)");
    return true;
  }

  /// 返回 header 段结束位置（`\r\n\r\n` 之后的下标），找不到返回 -1。
  static int _headerEndIndex(Uint8List raw) {
    for (var i = 0; i + 3 < raw.length; i++) {
      if (raw[i] == 13 && raw[i + 1] == 10 && raw[i + 2] == 13 && raw[i + 3] == 10) return i + 4;
    }
    for (var i = 0; i + 1 < raw.length; i++) {
      if (raw[i] == 10 && raw[i + 1] == 10) return i + 2;
    }
    return -1;
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 用 latin1 就地替换头部里的 Content-Length 数值，保持其它字节不变。
  static Uint8List? _replaceContentLength(Uint8List head, int newLength) {
    final text = latin1.decode(head, allowInvalid: true);
    final pattern = RegExp(r'([Cc]ontent-[Ll]ength:\s*)\d+');
    if (!pattern.hasMatch(text)) return null;
    final replaced = text.replaceFirstMapped(pattern, (m) => '${m.group(1)}$newLength');
    return Uint8List.fromList(latin1.encode(replaced));
  }

  @override
  exceptionCaught(ChannelContext channelContext, Channel channel, dynamic error, {StackTrace? trace}) {
    handler.exceptionCaught(channelContext, channel, error, trace: trace);
  }

  @override
  channelInactive(ChannelContext channelContext, Channel channel) async {
    if (identical(channel, channelContext.clientChannel)) channelContext.http2Requests.close();
    await taskQueue.waitForAll();
    // 等待已排队的读事件处理完成（读事件串行化队列），再判断是否还有在途读事件。
    await readQueue.waitForAll();
    //等待正在处理中的读事件完成(例如 HTTP/1.1 响应写回客户端), 避免服务端关闭时提前关闭对端连接导致 socket hang up。
    // 加超时上限：任一读事件因对端不释放而长期挂起时不再无限等待，避免连接/socket 永久悬挂。
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (_pendingReads.isNotEmpty && DateTime.now().isBefore(deadline)) {
      await Future.wait(_pendingReads.map((c) => c.future).toList());
    }
    if (_pendingReads.isNotEmpty) {
      logger.w("[$channel] channelInactive pending reads wait timeout, close anyway");
    }
    channel.isOpen = false;
    handler.channelInactive(channelContext, channel);
  }
}

class RawCodec extends Codec<Uint8List, List<int>> {
  @override
  DecoderResult<Uint8List> decode(ChannelContext channelContext, ByteBuf byteBuf, {bool resolveBody = true}) {
    var decoderResult = DecoderResult<Uint8List>()..data = byteBuf.readAvailableBytes();
    return decoderResult;
  }

  @override
  List<int> encode(ChannelContext channelContext, dynamic data) {
    return data as List<int>;
  }
}

abstract interface class ChannelInitializer {
  void initChannel(Channel channel);
}
