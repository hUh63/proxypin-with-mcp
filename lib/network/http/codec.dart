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

import 'dart:math';
import 'dart:typed_data';

import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/parse/body_reader.dart';
import 'package:proxypin/network/http/constants.dart';
import 'package:proxypin/network/http/h2/h2_codec.dart';
import 'package:proxypin/network/http/parse/http_parser.dart';
import 'package:proxypin/network/util/byte_buf.dart';

import 'http.dart';
import 'http_headers.dart';

/// 选择用于 HTTP/2 分流的 ALPN 结果。
///
/// [hasDecodingChannel] 表示是否知道「正在解码哪条连接」。知道时**必须**用它自己的
/// 协商结果——包括「没有协商出 h2」（null）这种情况，绝不能回退到客户端通道的 h2。
/// 上游 #969：MITM + 外部代理时，上游明文通道的解码器若按客户端 h2 分流，
/// `HTTP/1.1 200 Connection established` 会被交给 h2 解码器吞掉，CONNECT 等待超时。
/// 只有确实拿不到通道信息（纯单元调用）时才退回 [clientProtocol]。
String? resolveDecodeProtocol({
  required bool hasDecodingChannel,
  String? decodingProtocol,
  String? clientProtocol,
}) {
  return hasDecodingChannel ? decodingProtocol : clientProtocol;
}

class ParserException implements Exception {
  final String message;
  final String? source;

  ParserException(this.message, [this.source]);

  @override
  String toString() {
    return 'ParserException{message: $message source: $source}';
  }
}

enum State {
  readInitial,
  readHeader,
  body,
  done,
}

class DecoderResult<T> {
  bool isDone = true;
  T? data;
  bool supportedParse;

  //转发消息
  List<int>? forward;

  DecoderResult({this.isDone = true, this.supportedParse = true});
}

/// 解码
abstract interface class Decoder<T> {
  /// 解码 如果返回null说明数据不完整
  DecoderResult<T> decode(ChannelContext channelContext, ByteBuf byteBuf);
}

/// 支持在连接关闭时收尾 close-delimited 响应体的解码器。
abstract interface class CloseDelimitedBodyFinalizer {
  DecoderResult? finishCloseDelimitedBody();
}

/// 编码
abstract interface class Encoder<T> {
  List<int> encode(ChannelContext channelContext, T data);
}

/// 编解码器
abstract class Codec<D, E> implements Decoder<D>, Encoder<E> {
  static const int defaultMaxInitialLineLength = 1024000; // 1M
  static const int maxBodyLength = 4096000; // 4M
}

/// http编解码
abstract class HttpCodec<T extends HttpMessage> implements Codec<T, T>, CloseDelimitedBodyFinalizer {
  final HttpParse _httpParse = HttpParse();
  Http2Codec<T>? _h2Codec;
  State _state = State.readInitial;

  /// 本条消息已解析的 header 字节数。单行有 [HttpParse.defaultMaxLength] 限制，
  /// 但「很多行」没有：对端可以发几十万条短 header 把 buffer 与 HttpHeaders 一起撑爆。
  static const int maxHeaderBlockBytes = 512 * 1024;
  int _headerBytes = 0;

  late DecoderResult<T> result;

  BodyReader? bodyReader;

  /// 由客户端编解码器在编码 CONNECT 时置位：下一个响应是该 CONNECT 的
  /// "200 Connection established" 应答，没有 body。解码器在响应完成时自行
  /// 消费清除，不依赖调用方设置 currentRequest，也无需调用方还原。
  bool pendingConnectResponse = false;

  /// h2 → h1 协议转换时，请求行里的协议版本要写成 HTTP/1.1（消息对象本身保持
  /// HTTP/2，抓包数据照原样展示）。
  String? _encodeProtocolVersionOverride;

  String protocolVersionOf(T message) => _encodeProtocolVersionOverride ?? message.protocolVersion;

  T createMessage(List<String> reqLine);

  Http2Codec<T> getH2Codec() {
    return _h2Codec ??= (this is HttpRequestCodec ? Http2RequestDecoder() : Http2ResponseDecoder()) as Http2Codec<T>;
  }

  @override
  DecoderResult<T> decode(ChannelContext channelContext, ByteBuf data) {
    // 优先用「正在解码的这条连接」的 ALPN 结果，只在拿不到时退回客户端通道。
    // 用 clientChannel 会让上游通道的解码器按客户端协议走 h2（上游 #969）。
    final decodingChannel = channelContext.decodingChannel;
    var protocol = resolveDecodeProtocol(
        hasDecodingChannel: decodingChannel != null,
        decodingProtocol: decodingChannel?.selectedProtocol,
        // 兜底按通道角色取：响应解码看上游、请求解码看客户端。一律用客户端
        // 协议会让上游字节被当 h2 帧解析（上游 v1.4.0 的同名修复）。
        clientProtocol: this is HttpResponseCodec
            ? channelContext.serverChannel?.selectedProtocol
            : channelContext.clientChannel?.selectedProtocol);

    if (this is HttpRequestCodec &&
        _state == State.readInitial &&
        channelContext.clientChannel?.isSsl != true &&
        Http2Codec.hasConnectionPrefacePrefix(data)) {
      if (data.readableBytes() < Http2Codec.connectionPrefacePRI.length) {
        return DecoderResult<T>(isDone: false);
      }
      channelContext.isHttp2PriorKnowledge = true;
    }

    if (channelContext.isHttp2PriorKnowledge || protocol == HttpConstants.h2 || protocol == HttpConstants.h2_14) {
      return getH2Codec().decode(channelContext, data);
    }

    //请求行
    if (_state == State.readInitial) {
      init();
      var initialLine = _readInitialLine(data);
      if (initialLine.isEmpty) {
        return result;
      }
      result.data = createMessage(initialLine);
      _state = State.readHeader;
    }

    //请求头
    try {
      if (_state == State.readHeader) {
        _readHeader(data, result.data!, channelContext);
      }

      //请求体
      if (_state == State.body) {
        // HEAD 响应无 body；CONNECT 的 "200 Connection established" 应答也无
        // body。两种来源都要识别：
        //  - [pendingConnectResponse]：本端刚编码发出 CONNECT（如 App 内部重放走本地代理）；
        //  - currentRequest == CONNECT：ProxyPin 串联上游代理时解码上游的 200。
        // 这些响应必须走原有解析路径，不能按无 Content-Length 响应进 raw relay，否则 TLS 隧道被接管。
        bool isConnectResponse = pendingConnectResponse ||
            (this is HttpResponseCodec && channelContext.currentRequest?.method == HttpMethod.connect);

        bool resolveBody = channelContext.currentRequest?.method != HttpMethod.head && !isConnectResponse;
        Result? bodyResult;
        if (resolveBody) {
          // 取出当前全部可读字节交给 body 解析器；它按 Content-Length 精确消费，
          // 并把「不属于本条消息」的剩余字节数回报出来。
          final bodyBytes = data.readAvailableBytes();
          bodyResult = bodyReader!.readBody(bodyBytes);
          if (bodyResult.consumedBytes >= 0 && bodyResult.consumedBytes < bodyBytes.length) {
            // HTTP/1.1 pipelining：同一次读入可能紧跟下一个请求，
            // 把多读的字节退回 buffer，供下一轮 decode 解析，避免请求被丢弃。
            data.unreadBytes(bodyBytes.length - bodyResult.consumedBytes);
          }
        }
        if (!resolveBody || bodyResult?.isDone == true) {
          _state = State.done;
          result.data!.body = bodyResult?.body;
        }

        //If the body does not support parsing, forward directly
        if (bodyResult != null && !bodyResult.supportedParse) {
          result.supportedParse = false;
          result.forward = bodyResult.body;
          return result;
        }
      }

      if (_state == State.done) {
        result.data!.body = _convertBody(result.data!.body);
        result.data!.completeTime = DateTime.now();
        _state = State.readInitial;
        pendingConnectResponse = false; // CONNECT 应答已读完，自动消费
        _headerBytes = 0;
        result.isDone = true;
        return result;
      }
    } catch (e) {
      _state = State.readInitial;
      rethrow;
    }

    return result;
  }

  void init() {
    bodyReader = null;
    _headerBytes = 0;
    result = DecoderResult(isDone: false);
  }

  void initialLine(BytesBuilder buffer, T message);

  @override
  List<int> encode(ChannelContext channelContext, T message) {
    // h2 -> h1 协议转换：客户端 ALPN 协商了 h2，但上游 TLS 未选择 h2。
    // 请求按 HTTP/1.1 编码发往上游（上游 v1.4.0）。
    final bool translateH2ToH1 =
        this is HttpRequestCodec && message.protocolVersion == "HTTP/2" && channelContext.isHttp2Translation;
    // h1 -> h2：上游的 HTTP/1.1 响应按 h2 帧写回客户端（streamId 由响应处理器挂上）。
    final bool translateH1ToH2 = this is HttpResponseCodec &&
        message.protocolVersion != "HTTP/2" &&
        message.streamId != null &&
        channelContext.isHttp2Translation;

    if (message.protocolVersion == "HTTP/2" && !translateH2ToH1) {
      return getH2Codec().encode(channelContext, message);
    }
    if (translateH1ToH2) {
      return getH2Codec().encode(channelContext, message);
    }

    BytesBuilder builder = BytesBuilder();
    //请求行
    if (translateH2ToH1) _encodeProtocolVersionOverride = HttpMessage.http1Version;
    try {
      initialLine(builder, message);
    } finally {
      _encodeProtocolVersionOverride = null;
    }

    List<int>? body = message.body;

    //请求头
    bool isChunked = message.headers.isChunked;
    // Only drop chunked encoding when we actually have the full body to
    // re-frame as Content-Length. For streaming responses (body == null,
    // e.g. SSE/video handoff), keep Transfer-Encoding: chunked so the header
    // stays consistent with the chunk-framed bytes we relay afterwards.
    if (body == null) {
      // body 为 null（断点里把请求体清空、copy() 后丢失 body）时，头里可能还留着
      // 原来的 Content-Length / chunked：发出去就是「声明 N 字节、实际 0 字节」，
      // 上游会一直等 body，或在 keep-alive 上把下一个请求的字节当成本次的 body。
      message.headers.remove(HttpHeaders.TRANSFER_ENCODING);
      if (message.contentLength != 0) {
        message.headers.remove(HttpHeaders.CONTENT_LENGTH);
      }
    } else {
      message.headers.remove(HttpHeaders.TRANSFER_ENCODING);
      if (body.isNotEmpty || isChunked) {
        message.headers.contentLength = body.length;
      } else if (message.contentLength != 0) {
        message.headers.remove(HttpHeaders.CONTENT_LENGTH);
      }
    }

    // h2 请求没有 Host 头（主机在 :authority 里），HTTP/1.1 上游要求 Host。
    // 直接写入字节流，不改动消息对象（保持抓包数据原样）。
    if (translateH2ToH1 && message is HttpRequest && message.headers.host == null) {
      final hostAndPort = message.hostAndPort;
      if (hostAndPort != null) {
        final defaultPort = hostAndPort.scheme == HostAndPort.httpScheme ? 80 : 443;
        final authority = hostAndPort.port == defaultPort ? hostAndPort.host : '${hostAndPort.host}:${hostAndPort.port}';
        builder
          ..add(HttpHeaders.HOST.codeUnits)
          ..addByte(HttpConstants.colon)
          ..addByte(HttpConstants.sp)
          ..add(authority.codeUnits)
          ..addByte(HttpConstants.cr)
          ..addByte(HttpConstants.lf);
      }
    }

    message.headers.forEach((key, values) {
      for (var v in values) {
        builder
          ..add(key.codeUnits)
          ..addByte(HttpConstants.colon)
          ..addByte(HttpConstants.sp)
          ..add(v.codeUnits)
          ..addByte(HttpConstants.cr)
          ..addByte(HttpConstants.lf);
      }
    });
    builder.addByte(HttpConstants.cr);
    builder.addByte(HttpConstants.lf);

    //请求体
    builder.add(body ?? Uint8List(0));
    return builder.toBytes();
  }

  //读取起始行
  List<String> _readInitialLine(ByteBuf data) {
    int maxSize = min(data.readableBytes(), Codec.defaultMaxInitialLineLength);
    return _httpParse.parseInitialLine(data, maxSize);
  }

  //读取请求头
  void _readHeader(ByteBuf data, T message, ChannelContext channelContext) {
    final before = data.readerIndex;
    if (_httpParse.parseHeaders(data, message.headers)) {
      _state = State.body;
      // 超过解析上限时可降级为"原样转发"的前提：客户端通道与上游通道都已建立（上游 #701）
      bodyReader = BodyReader(message,
          canRelay: channelContext.clientChannel != null && channelContext.serverChannel != null,
          bufferCloseDelimited: channelContext.bufferCloseDelimited);
      return;
    }

    // header 还没读完：累计已消费字节，防止「很多条短 header」无限累积。
    _headerBytes += data.readerIndex - before;
    if (_headerBytes > maxHeaderBlockBytes) {
      throw FormatException('HTTP header block too large: $_headerBytes bytes');
    }
  }

  /// 上游连接关闭时调用：把缓冲中的 close-delimited body 产出为完整消息。
  @override
  DecoderResult<T>? finishCloseDelimitedBody() {
    var reader = bodyReader;
    if (reader == null || _state != State.body) {
      return null;
    }
    var r = reader.finish();
    if (!r.isDone) {
      return null;
    }
    result.data!.body = _convertBody(r.body);
    result.data!.completeTime = DateTime.now();
    result.forward = null;
    result.supportedParse = true;
    result.isDone = true;
    _state = State.readInitial;
    pendingConnectResponse = false;
    _headerBytes = 0;
    return result;
  }

  //转换body
  List<int>? _convertBody(List<int>? bytes) {
    if (bytes == null) {
      return null;
    }
    return bytes;
  }
}

/// http请求编解码
class HttpRequestCodec extends HttpCodec<HttpRequest> {
  @override
  HttpRequest createMessage(List<String> reqLine) {
    // 畸形请求行（如只有 `GET /`）：以前的 reqLine[2] 会抛 RangeError，
    // 让整条连接被关掉；协议版本缺失时按 HTTP/1.1 兜底。
    if (reqLine.length < 2) {
      throw FormatException('Invalid request line: $reqLine');
    }
    final methodName = reqLine[0];
    HttpMethod httpMethod = HttpMethod.valueOf(methodName);
    return HttpRequest(httpMethod, reqLine[1],
        protocolVersion: reqLine.length > 2 ? reqLine[2] : 'HTTP/1.1',
        rawMethod: httpMethod == HttpMethod.unknown ? methodName : null);
  }

  @override
  void initialLine(BytesBuilder buffer, HttpRequest message) {
    String uri = message.uri;

    //http scheme 输入地址和host不一致
    if (uri.startsWith(HostAndPort.httpScheme) &&
        (message.requestUri?.host != message.headers.host && message.headers.host?.contains(':') != true)) {
      uri = message.requestUri?.replace(host: message.headers.host).toString() ?? uri;
    }

    //请求行
    buffer
      ..add(message.methodLabel.codeUnits)
      ..addByte(HttpConstants.sp)
      ..add(uri.codeUnits)
      ..addByte(HttpConstants.sp)
      ..add(protocolVersionOf(message).codeUnits)
      ..addByte(HttpConstants.cr)
      ..addByte(HttpConstants.lf);
  }
}

/// http响应编解码
class HttpResponseCodec extends HttpCodec<HttpResponse> {
  @override
  HttpResponse createMessage(List<String> reqLine) {
    // 状态码缺失/非数字（畸形或非标准服务端）不能让整条连接解码失败
    var httpStatus = HttpStatus(int.tryParse(reqLine[1].trim()) ?? 0, reqLine[2]);
    return HttpResponse(httpStatus, protocolVersion: reqLine[0]);
  }

  @override
  void initialLine(BytesBuilder buffer, HttpResponse message) {
    //状态行
    buffer.add(message.protocolVersion.codeUnits);
    buffer.addByte(HttpConstants.sp);
    buffer.add(message.status.code.toString().codeUnits);
    buffer.addByte(HttpConstants.sp);
    buffer.add(message.status.reasonPhrase.codeUnits);
    buffer.addByte(HttpConstants.cr);
    buffer.addByte(HttpConstants.lf);
  }
}

class HttpServerCodec extends Codec<HttpRequest, HttpResponse> {
  HttpRequestCodec requestCodec = HttpRequestCodec();
  HttpResponseCodec responseCodec = HttpResponseCodec();

  @override
  DecoderResult<HttpRequest> decode(ChannelContext channelContext, ByteBuf byteBuf) {
    return requestCodec.decode(channelContext, byteBuf);
  }

  @override
  List<int> encode(ChannelContext channelContext, HttpResponse data) {
    return responseCodec.encode(channelContext, data);
  }
}

class HttpClientCodec extends Codec<HttpResponse, HttpRequest> {
  HttpRequestCodec requestCodec = HttpRequestCodec();
  HttpResponseCodec responseCodec = HttpResponseCodec();

  @override
  DecoderResult<HttpResponse> decode(ChannelContext channelContext, ByteBuf byteBuf) {
    return responseCodec.decode(channelContext, byteBuf);
  }

  @override
  List<int> encode(ChannelContext channelContext, HttpRequest data) {
    // 编码 CONNECT 后，下一个响应是无 body 的 "200 Connection established"，
    // 通知响应解码器内部标记，无需调用方设置/还原 currentRequest。
    if (data.method == HttpMethod.connect) {
      responseCodec.pendingConnectResponse = true;
    }
    return requestCodec.encode(channelContext, data);
  }
}
