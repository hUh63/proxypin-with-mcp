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

import 'dart:typed_data';

import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';

import '../codec.dart';
import 'chunked_decoder.dart';

class Result {
  final bool isDone;
  final bool supportedParse;

  Uint8List? body;

  /// 本次 [BodyReader.readBody] 实际消费的输入字节数，供上层把「不属于本条消息」
  /// 的字节退回给 buffer（HTTP/1.1 pipelining：同一次读入可能含后续消息）。
  ///
  /// 取值约定：
  ///  - `>= 0`：精确消费量（固定长度 body 路径）；
  ///  - `-1`  ：全部消费（chunked / 原样转发等路径，多余字节由各自机制保存）。
  final int consumedBytes;

  Result(this.isDone, {this.body, this.supportedParse = true, this.consumedBytes = -1});
}

class BodyReader {
  final HttpMessage message;

  /// 超过解析上限时是否可以交给上层"原样转发"（对端连接已建立）。
  ///
  /// 响应方向总是可以（客户端通道 + 上游通道都在）；请求方向在还没连上上游时
  /// 不能——那样会把请求体静默丢掉，所以那种情况保持原有报错。
  final bool canRelay;

  /// 超过解析上限后，仍保留多少字节用于界面展示（上游 #701）
  static const int maxPreviewBytes = 256 * 1024;

  final BytesBuilder _bodyBuffer = BytesBuilder();

  /// chunked 解码器，仅在 Transfer-Encoding: chunked 时创建；
  /// 内部自行处理 chunk-size 行、chunk 内容尾部 \r\n、chunk-extension、trailer
  /// headers 等跨 TCP 包边界的分片情况。
  final ChunkedDecoder? _chunkedDecoder;

  bool _done = false;

  /// 已判定超过解析上限（上游 #701）：此后不再解析，交给上层原样转发
  bool _oversize = false;

  BodyReader(this.message, {this.canRelay = false})
      : _chunkedDecoder = message.headers.isChunked ? ChunkedDecoder() : null;

  Result readBody(Uint8List data) {
    if (_oversize) {
      // 已超限：不再累积，也不再回传字节——dispatch 层已切换为原样转发，
      // 保留在它自己 buffer 里的原始字节会完整送达对端。
      return Result(false, supportedParse: false);
    }

    if (_bodyBuffer.length + data.length > Codec.maxBodyLength) {
      // 上游 #701：此前直接抛 ParserException，用户看到的是"报错 + 响应为空"。
      // 改为放弃解析、降级为原样转发：客户端仍能拿到完整响应，
      // 列表里也能看到头部与前若干字节，同时不会把巨量 body 攒在内存里。
      if (!canRelay) {
        // 无可转发的对端（例如尚未连上上游的请求中段）：保持原行为，宁可报错也不静默丢包
        _bodyBuffer.clear();
        throw ParserException('Body length exceeds ${Codec.maxBodyLength}');
      }

      final received = _bodyBuffer.length + data.length;
      final prefix = _bodyBuffer.toBytes();
      _bodyBuffer.clear();
      _oversize = true;

      message.body = prefix.length > maxPreviewBytes ? prefix.sublist(0, maxPreviewBytes) : prefix;
      message.bodyTruncated = true;
      message.originalBodyLength = message.contentLength > 0 ? message.contentLength : received;
      return Result(false, supportedParse: false);
    }

    if (message.headers.contentType == 'video/x-flv' || message.headers.contentType.startsWith("text/event-stream")) {
      //Directly forward without processing for now
      return Result(false, supportedParse: false, body: data);
    }

    // 响应既没有 Content-Length 也没有 Transfer-Encoding: chunked 时,按
    // HTTP 语义 body 由连接关闭定界。直接原始转发,保留原始定界并让上游
    // 关闭信号传递给客户端;否则 body 会被当空处理丢掉,客户端一直等不到
    // 完整响应导致超时(issue #844)。
    // 仅当 Content-Length 头缺失时判定(显式 CL:0 是空 body,不属于
    // close-delimited);204/304/205 等无 body 状态码走原有解析路径。
    var msg = message;
    if (msg is HttpResponse &&
        msg.status.code >= 200 &&
        msg.status.code != 204 &&
        msg.status.code != 304 &&
        msg.status.code != 205 &&
        msg.headers.get(HttpHeaders.CONTENT_LENGTH) == null &&
        !msg.headers.isChunked) {
      return Result(false, supportedParse: false, body: data);
    }

    // chunked 路径内部有 carry 缓冲，多余字节由解码器保留，这里不精确回报消费量；
    // 固定长度路径按 Content-Length 精确消费，剩余字节必须退回给上层。
    final int consumed;
    if (_chunkedDecoder != null) {
      _readChunked(data);
      consumed = -1;
    } else {
      consumed = _readFixedLengthContent(data);
    }

    if (_done) {
      var body = _bodyBuffer.toBytes();
      _bodyBuffer.clear();
      return Result(true, body: body, consumedBytes: consumed);
    }

    return Result(false, consumedBytes: consumed);
  }

  /// 按 Content-Length 读取固定长度 body，返回本次实际消费的字节数。
  ///
  /// 关键：只能消费属于本条消息的字节。早先的实现无条件 `_bodyBuffer.add(data)`，
  /// 而调用方传入的是「本 buffer 当前全部可读字节」——当客户端把多个请求合并到
  /// 同一次写入（HTTP/1.1 pipelining）时，第一个请求的 body 会把后续请求的字节
  /// 一并吞掉，上层再 clearRead() 就把它们永久丢掉了。
  int _readFixedLengthContent(Uint8List data) {
    if (message.contentLength > 0) {
      final int need = message.contentLength - _bodyBuffer.length;
      final int take = need <= 0 ? 0 : (data.length < need ? data.length : need);
      if (take > 0) {
        _bodyBuffer.add(Uint8List.sublistView(data, 0, take));
      }
      if (_bodyBuffer.length >= message.contentLength) {
        _done = true;
      }
      return take;
    }

    // contentLength <= 0：没有 body 可消费。
    //  - 请求没有 Content-Length 头（HttpHeaders.contentLength 此时返回 0），
    //    按 RFC 7230 请求即无 body；
    //  - Content-Length: 0 同样是空 body。
    // 两种情况都不消费输入字节——同一次读入里紧跟的下一个请求必须留在 buffer 里。
    _done = true;
    return 0;
  }

  void _readChunked(Uint8List data) {
    final Uint8List payload;
    try {
      payload = _chunkedDecoder!.feed(data);
    } on FormatException catch (e) {
      throw ParserException(e.message);
    }
    if (payload.isNotEmpty) {
      _bodyBuffer.add(payload);
    }
    if (_chunkedDecoder!.isDone) {
      _done = true;
    }
  }
}
