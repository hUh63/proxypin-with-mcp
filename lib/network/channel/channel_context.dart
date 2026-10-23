import 'dart:async';
import 'dart:typed_data';

import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/h2/frame.dart';
import 'package:proxypin/network/http/h2/setting.dart';
import 'package:proxypin/network/http/h2/request_queue.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/attribute_keys.dart';
import 'package:proxypin/network/util/process_info.dart';
import 'package:proxypin/utils/lang.dart';

import '../bin/listener.dart';
import 'network.dart';

///
class ChannelContext {
  final Map<String, Object> _attributes = {};

  //和本地客户端的连接
  Channel? clientChannel;

  //和远程服务端的连接
  Channel? serverChannel;

  // 建立服务端连接 / TLS 握手耗时（毫秒），供「分阶段耗时」展示
  int? connectTimeMs;
  int? tlsTimeMs;

  /// 当前正在执行 [Decoder.decode] 的通道。
  ///
  /// 编解码器本身不知道它服务的是哪条连接，而 HTTP/2 分流必须按「这条连接」
  /// 自己的 ALPN 结果判断：客户端通道协商为 h2 时，上游明文通道
  /// （ProxyPin → 外部代理）收到的 `HTTP/1.1 200 Connection established`
  /// 绝不能被交给 h2 解码器，否则应答被吞掉、CONNECT 等待 5 秒超时（上游 #969）。
  ///
  /// 由 [ChannelDispatcher.channelRead] 在每次同步 decode 之前写入；
  /// decode 内部没有 await，因此不存在两个通道交错覆盖的窗口。
  Channel? decodingChannel;

  // 明文连接没有ALPN，识别完整前置帧后由两端编解码器共用此状态。
  bool isHttp2PriorKnowledge = false;
  final BytesBuilder _pendingHttp2Frames = BytesBuilder();
  Future<Channel>? _connectingServerChannel;
  bool _http2SettingsSent = false;
  bool _http2SettingsAckPending = false;
  final http2Requests = Http2RequestQueue();
  final _forwardedHttp2Streams = <int>{};
  final _pendingHttp2StreamFrames = <int, BytesBuilder>{};

  /// 是否启用 h2 ↔ HTTP/1.1 协议转换（上游 v1.4.0 引入）。
  ///
  /// 该特性把 h2 客户端的多 stream 请求串行翻译成 h1 发往上游，再把 h1 响应
  /// 编码回 h2。实现与 #969 修复（decodingChannel）、读事件串行队列、
  /// 写背压三块加固耦合很深，尚未在真机验证；关闭时会话按原有路径处理
  /// （旧行为：h2 客户端 + h1 上游仍可正常收发，只是没有 stream 串行化保障）。
  static const bool enableHttp2Translation = false;

  /// 客户端 ALPN 协商了 h2，但上游 TLS 未选择 h2（h1-only 服务器或中间盒），
  /// 需要 h2 ↔ HTTP/1.1 协议转换。仅适用于 TLS ALPN 场景；
  /// 明文 h2c prior-knowledge 走原文转发，不在此列。
  bool get isHttp2Translation {
    if (!enableHttp2Translation) return false;
    final clientProtocol = clientChannel?.selectedProtocol;
    if (clientProtocol != 'h2' && clientProtocol != 'h2-14') return false;
    final server = serverChannel;
    if (server == null || !server.isSsl) return false;
    final serverProtocol = server.selectedProtocol;
    return serverProtocol != 'h2' && serverProtocol != 'h2-14';
  }

  // ---- h2 ↔ h1 协议转换状态 ----
  // HTTP/1.1 上游同一时刻只能承载一个请求（响应按序到达）。翻译模式下用
  // 单槽 + 屏障串行化：请求写完后等响应完整写回客户端再放行下一个 h2 stream，
  // 保证响应关联不错乱，也避免在老旧服务器上使用脆弱的 pipelining。
  HttpRequest? _pendingTranslatedRequest;
  Completer<void>? _translatedResponseDone;
  bool _translationPrefaceSent = false;

  /// 翻译模式下客户端原始 h2 帧的剥离器：只把 DATA 载荷透传给 h1 上游。
  final h2ToH1FrameStripper = H2ToH1FrameStripper();

  HttpRequest? get pendingTranslatedRequest => _pendingTranslatedRequest;

  /// 本连接是否曾经处于协议转换模式。上游关闭后 selectedProtocol 不可再读
  /// （isOpen=false 时返回 null），isHttp2Translation 会失真，需要用这个粘性标记。
  bool get wasHttp2Translation => _translationPrefaceSent;

  /// 翻译模式下给客户端补发代理自己的 h2 服务端前言（真实上游是 h1，没有
  /// SETTINGS 可转发，而 h2 客户端要求首帧必须是 SETTINGS）。大窗口避免
  /// 流控 stall：转换层不参与逐帧流控。
  Future<void> sendTranslationServerPreface() async {
    if (_translationPrefaceSent || clientChannel == null) return;
    _translationPrefaceSent = true;
    _http2SettingsAckPending = true; // 客户端回的 SETTINGS ACK 由解码侧消费，不转发给 h1 上游

    // SETTINGS_INITIAL_WINDOW_SIZE = 1GB
    var payload = Uint8List(6);
    payload[0] = 0; payload[1] = 4; // identifier 4
    payload[2] = 0x3F; payload[3] = 0xFF; payload[4] = 0xFF; payload[5] = 0xFF;
    await clientChannel!.writeBytes(FrameHeader(payload.length, FrameType.settings, 0, 0).encode()..addAll(payload));

    // 连接级 WINDOW_UPDATE += 1GB
    var increment = Uint8List(4);
    increment[0] = 0x3F; increment[1] = 0xFF; increment[2] = 0xFF; increment[3] = 0xFF;
    await clientChannel!.writeBytes(FrameHeader(4, FrameType.windowUpdate, 0, 0).encode()..addAll(increment));
  }

  Future<void> beginTranslatedRequest(HttpRequest request) async {
    await sendTranslationServerPreface();
    // 防御：理论上 Http2RequestQueue 已保证串行，异常残留时等上一个屏障释放
    await _translatedResponseDone?.future;
    _pendingTranslatedRequest = request;
    _translatedResponseDone = Completer<void>();
  }

  Future<void> waitTranslatedResponse() => _translatedResponseDone?.future ?? Future.value();

  /// 响应完整写回客户端（或连接关闭/出错）后释放屏障，放行下一个 stream。
  void completeTranslatedResponse() {
    _pendingTranslatedRequest = null;
    final done = _translatedResponseDone;
    _translatedResponseDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  Future<Channel?> get readyServerChannel async {
    final connecting = _connectingServerChannel;
    if (connecting != null) return await connecting;
    return serverChannel;
  }

  void bufferHttp2Frames(List<int> bytes) => _pendingHttp2Frames.add(bytes);

  Future<void> sendInitialHttp2Settings() async {
    if (_http2SettingsSent) return;
    _http2SettingsSent = true;
    _http2SettingsAckPending = true;
    // 客户端可以等服务端前置帧后才发送:authority，不能双方一直等待。
    await clientChannel!.writeBytes(FrameHeader(0, FrameType.settings, 0, 0).encode());
  }

  bool consumeInitialHttp2SettingsAck() {
    if (!_http2SettingsAckPending) return false;
    _http2SettingsAckPending = false;
    return true;
  }

  EventListener? listener;

  //http2 stream
  final Map<int, Pair<HttpRequest?, HttpResponse?>> _streams = {};
  final Map<int, HeadersFrame> _streamDependency = {};

  ChannelContext();

  //创建服务端连接
  Future<Channel> connectServerChannel(HostAndPort hostAndPort, ChannelHandler channelHandler) {
    // 调用方经过异步处理后可能仍持有旧的 null；这里同时复核在建和已建连接。
    final connecting = _connectingServerChannel;
    if (connecting != null) return connecting;
    final connected = serverChannel;
    if (connected != null) {
      currentRequest?.connectionReused = true;
      return Future.value(connected);
    }
    return _connectingServerChannel ??= _connectServerChannel(hostAndPort, channelHandler);
  }

  Future<Channel> _connectServerChannel(HostAndPort hostAndPort, ChannelHandler channelHandler) async {
    try {
      final connectStart = DateTime.now();
      serverChannel = await startConnect(hostAndPort, channelHandler, this);
      connectTimeMs = DateTime.now().difference(connectStart).inMilliseconds;
      final trigger = currentRequest;
      if (trigger != null) {
        trigger.connectTimeMs = connectTimeMs;
        trigger.connectionReused = false;
      }
      putAttribute(clientChannel!.id, serverChannel);
      putAttribute(serverChannel!.id, clientChannel);
      // :authority到达前还不知道目标，前置帧和SETTINGS不能在此之前丢弃。
      while (_pendingHttp2Frames.isNotEmpty) {
        await serverChannel!.writeBytes(_pendingHttp2Frames.takeBytes());
      }
      return serverChannel!;
    } finally {
      _connectingServerChannel = null;
    }
  }

  /// 建立连接
  static Future<Channel> startConnect(
      HostAndPort hostAndPort, ChannelHandler handler, ChannelContext channelContext) async {
    var client = Client()..initChannel((channel) => channel.dispatcher.channelHandle(HttpClientCodec(), handler));

    return client.connect(hostAndPort, channelContext);
  }

  T? getAttribute<T>(String key) {
    if (!_attributes.containsKey(key)) {
      return null;
    }
    return _attributes[key] as T;
  }

  void putAttribute(String key, Object? value) {
    if (value == null) {
      _attributes.remove(key);
      return;
    }
    _attributes[key] = value;
  }

  HostAndPort? get host => getAttribute(AttributeKeys.host);

  set host(HostAndPort? host) => putAttribute(AttributeKeys.host, host);

  HttpRequest? get currentRequest => getAttribute(AttributeKeys.request);

  set currentRequest(HttpRequest? request) => putAttribute(AttributeKeys.request, request);

  set processInfo(ProcessInfo? processInfo) => putAttribute(AttributeKeys.processInfo, processInfo);

  ProcessInfo? get processInfo => getAttribute(AttributeKeys.processInfo);

  StreamSetting? setting;

  HttpRequest? putStreamRequest(int streamId, HttpRequest request) {
    var old = _streams[streamId]?.key;
    http2Requests.register(streamId);
    _streams[streamId] = Pair(request, null);
    return old;
  }

  /// 大正文流的 DATA 不能抢在它尚未转发的 HEADERS 之前到达上游。
  bool bufferPendingHttp2StreamFrame(int streamId, List<int> bytes) {
    if (_forwardedHttp2Streams.contains(streamId)) return false;
    if (http2Requests.canForward(streamId)) {
      _pendingHttp2StreamFrames.putIfAbsent(streamId, BytesBuilder.new).add(bytes);
    }
    return true;
  }

  Future<void> writeForwardedRequest(Channel remote, HttpRequest request) async {
    if (request.protocolVersion != 'HTTP/2') {
      await remote.write(this, request);
      return;
    }
    final streamId = request.streamId!;
    if (!http2Requests.canForward(streamId)) return;

    // h2 -> h1 协议转换：请求会以 HTTP/1.1 编码（见 HttpCodec.encode），
    // 此处串行化并等响应写回客户端后才放行下一个 stream。
    final translated = isHttp2Translation;
    if (translated) await beginTranslatedRequest(request);

    try {
      // encode/add 在首次 await 前完成，先写 HEADERS，再写之前缓存的 DATA。
      final writes = <Future<void>>[remote.write(this, request)];
      final buffered = _pendingHttp2StreamFrames.remove(streamId);
      if (buffered != null) {
        // 转换模式下缓存的是客户端原始 h2 帧，只能透传 DATA 载荷
        writes.add(remote.writeBytes(translated ? h2ToH1FrameStripper.strip(buffered.takeBytes()) : buffered.takeBytes()));
      }
      _forwardedHttp2Streams.add(streamId);
      await Future.wait(writes);
      if (translated) await waitTranslatedResponse();
    } catch (_) {
      if (translated) completeTranslatedResponse();
      rethrow;
    }
  }

  /// 被客户端 RST_STREAM 取消的流 id。
  ///
  /// 取消后 `_streams` 里已无该流上下文，若后续仍收到它的 DATA 帧，
  /// `getMessage` 返回 null 会被当成「HEADERS 未到」而**原样转发**给上游——
  /// 但该流在上游从未打开，转发是协议违例（上游会报错/断连）。
  /// 因此记录取消过的流，供解码器丢弃其残留帧。
  final Set<int> _cancelledStreams = {};

  /// 取消流记录的保留上限，避免长连接上无界增长（h2 流 id 单调递增、不会复用）。
  static const int _maxCancelledStreams = 100000;

  bool isStreamCancelled(int streamId) => _cancelledStreams.contains(streamId);

  void markStreamCancelled(int streamId) {
    _cancelledStreams.add(streamId);
    while (_cancelledStreams.length > _maxCancelledStreams) {
      _cancelledStreams.remove(_cancelledStreams.first);
    }
  }

  /// 上游尚未打开的流不能收到 RST_STREAM，否则会牵连其它复用请求。
  bool cancelHttp2Request(int streamId) {
    final forwarded = _forwardedHttp2Streams.contains(streamId);
    http2Requests.cancel(streamId);
    markStreamCancelled(streamId);
    removeStream(streamId);
    return forwarded;
  }

  void putStreamResponse(int streamId, HttpResponse response) {
    var pair = _streams[streamId];
    if (pair == null) {
      pair = Pair(null, response);
      _streams[streamId] = pair;
    }

    pair.key?.response = response;
    response.request = pair.key;
    pair.value = response;
  }

  HttpRequest? getStreamRequest(int streamId) {
    return _streams[streamId]?.key;
  }

  HttpResponse? getStreamResponse(int streamId) {
    return _streams[streamId]?.value;
  }

  void removeStream(int streamId) {
    _streams.remove(streamId);
    _streamDependency.remove(streamId);
    _forwardedHttp2Streams.remove(streamId);
    _pendingHttp2StreamFrames.remove(streamId);
  }

  void put(int streamId, HeadersFrame frame) {
    _streamDependency[streamId] = frame;
  }

  HeadersFrame? removeStreamDependency(int streamId) {
    return _streamDependency.remove(streamId);
  }

  HeadersFrame? getStreamDependency(int streamId) {
    return _streamDependency[streamId];
  }

  bool containsStreamDependency(int? streamId) {
    if (streamId == null) return false;
    return _streamDependency.containsKey(streamId);
  }
}

/// h2 → HTTP/1.1 协议转换时，客户端原始帧流的剥离器。
///
/// 翻译模式下客户端发来的连接前言、SETTINGS/PING/WINDOW_UPDATE/GOAWAY 等
/// 控制帧没有 h1 对应物，全部丢弃；只有 DATA 帧的载荷是 h1 请求体的字节流
/// （大 body streaming upload 时请求头里已有 Content-Length）。
/// 输入保证是完整帧（解码器只在帧完整时才放入 forward），但跨调用仍做残留缓冲防御。
class H2ToH1FrameStripper {
  static final List<int> _preface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".codeUnits;
  static const int _dataFrameType = 0; // FrameType.data

  bool _prefaceConsumed = false;
  final BytesBuilder _leftover = BytesBuilder();

  List<int> strip(List<int> bytes) {
    var input = BytesBuilder(copy: false)
      ..add(_leftover.takeBytes())
      ..add(bytes);
    var data = input.takeBytes();
    var offset = 0;
    var out = BytesBuilder(copy: false);

    if (!_prefaceConsumed) {
      if (data.length < _preface.length && _matchesPreface(data)) {
        // 前言拆包到达：攒够 24 字节再判定（前缀不匹配的流直接按帧解析）
        _leftover.add(data);
        return out.takeBytes();
      }
      _prefaceConsumed = true;
      // 连接前言只会出现在最开头
      if (data.length >= _preface.length && _matchesPreface(data)) {
        offset = _preface.length;
      }
    }
    while (data.length - offset >= 9) {
      int length = (data[offset] << 16) | (data[offset + 1] << 8) | data[offset + 2];
      int type = data[offset + 3];
      if (data.length - offset - 9 < length) break; // 不完整，留到下次
      if (type == _dataFrameType && length > 0) {
        out.add(data.sublist(offset + 9, offset + 9 + length));
      }
      offset += 9 + length;
    }

    if (offset < data.length) {
      _leftover.add(data.sublist(offset));
    }
    return out.takeBytes();
  }

  /// data 不足前言全长时按前缀匹配
  bool _matchesPreface(List<int> data) {
    final n = data.length < _preface.length ? data.length : _preface.length;
    for (int i = 0; i < n; i++) {
      if (data[i] != _preface[i]) return false;
    }
    return true;
  }
}
