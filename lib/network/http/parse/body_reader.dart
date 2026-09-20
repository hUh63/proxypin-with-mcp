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

import '../codec.dart';
import 'chunked_decoder.dart';

class Result {
  final bool isDone;
  final bool supportedParse;

  Uint8List? body;

  Result(this.isDone, {this.body, this.supportedParse = true});
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

    if (_chunkedDecoder != null) {
      _readChunked(data);
    } else {
      _readFixedLengthContent(data);
    }

    if (_done) {
      var body = _bodyBuffer.toBytes();
      _bodyBuffer.clear();
      return Result(true, body: body);
    }

    return Result(false);
  }

  void _readFixedLengthContent(Uint8List data) {
    if (message.contentLength > 0) {
      _bodyBuffer.add(data);
    }

    if (message.contentLength == -1 || _bodyBuffer.length >= message.contentLength) {
      _done = true;
    }
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
