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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:proxypin/network/util/logger.dart';

class WebSocketFrame {
  final bool fin;

  /*
      0x00 denotes a continuation frame
      0x01 表示一个text frame
      0x02 表示一个binary frame
      0x03 ~~ 0x07 are reserved for further non-control frames,为将来的非控制消息片段保留测操作码
      0x08 表示连接关闭
      0x09 表示 ping (心跳检测相关)
      0x0a 表示 pong (心跳检测相关)
   */
  final int opcode; //4bit
  final bool mask; //1bit
  final int maskingKey;

  final int payloadLength;
  final Uint8List payloadData;

  bool isFromClient = false;
  DateTime time;

  WebSocketFrame({
    required this.fin,
    required this.opcode,
    required this.mask,
    required this.payloadLength,
    required this.maskingKey,
    required this.payloadData,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  bool get isText => opcode == 0x01;

  bool get isBinary => opcode == 0x02;

  String get payloadDataAsString {
    if (opcode == 0x08) {
      return '连接关闭';
    }
    if (opcode == 0x02) {
      return '二进制数据';
    }
    try {
      return utf8.decode(payloadData);
    } catch (e) {
      return String.fromCharCodes(payloadData);
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'fin': fin,
      'opcode': opcode,
      'mask': mask,
      'maskingKey': maskingKey,
      'payloadLength': payloadLength,
      // use base64 to avoid binary corruption in JSON
      'payloadData': base64Encode(payloadData),
      'isFromClient': isFromClient,
      'time': time.millisecondsSinceEpoch,
    };
  }

  factory WebSocketFrame.fromJson(Map<String, dynamic> json) {
    final payload = base64Decode(json['payloadData']?.toString() ?? '');
    final frame = WebSocketFrame(
      fin: json['fin'] == true,
      opcode: (json['opcode'] ?? 0) as int,
      mask: json['mask'] == true,
      payloadLength: (json['payloadLength'] ?? payload.length) as int,
      maskingKey: (json['maskingKey'] ?? 0) as int,
      payloadData: Uint8List.fromList(payload),
      time: json['time'] == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch((json['time'] as num).toInt()),
    );
    frame.isFromClient = json['isFromClient'] == true;
    return frame;
  }
}

///websocket 解码器
class WebSocketDecoder {
  ByteBuffer buffer = ByteBuffer();

  WebSocketFrame? decode(Uint8List newData) {
    buffer.putBytes(newData);
    int? frameLen = _tryFrameLength(buffer.bytes);
    if (frameLen == null) {
      return null;
    }

    try {
      WebSocketFrame frame = _parseWebSocketFrame(buffer.bytes);
      buffer.removeBytes(frameLen);
      return frame;
    } catch (e, stackTrace) {
      logger.e("WebSocket decode error", error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Returns the total byte length of the next frame in [data], or null if
  /// the data is incomplete or contains an invalid opcode.
  int? _tryFrameLength(Uint8List data) {
    if (data.length < 2) {
      return null;
    }

    var reader = ByteData.sublistView(data);

    var opcode = reader.getUint8(0) & 0x0f;
    if (opcode > 0xA) {
      return null;
    }

    var mask = reader.getUint8(1) >> 7;
    int payloadStart = 2;
    int payloadLength = reader.getUint8(1) & 0x7f;

    if (payloadLength == 126) {
      if (data.length < 4) return null;
      payloadLength = reader.getUint16(2);
      payloadStart += 2;
    } else if (payloadLength == 127) {
      if (data.length < 10) return null;
      payloadLength = reader.getUint64(2);
      payloadStart += 8;
    }

    if (mask == 1) {
      if (data.length < payloadStart + 4) {
        return null;
      }
      payloadStart += 4;
    }

    if (data.length < payloadStart + payloadLength) {
      return null;
    }

    return payloadStart + payloadLength;
  }

  WebSocketFrame _parseWebSocketFrame(Uint8List data) {
    var reader = ByteData.sublistView(data);

    var fin = reader.getUint8(0) >> 7;
    //解析 rsv1
    var rsv1 = (reader.getUint8(0) >> 6) & 0x01;

    var opcode = reader.getUint8(0) & 0x0f;

    var mask = reader.getUint8(1) >> 7;
    int payloadLength = reader.getUint8(1) & 0x7f;

    int payloadStart = 2;

    if (payloadLength == 126) {
      payloadLength = reader.getUint16(2);
      payloadStart += 2;
    } else if (payloadLength == 127) {
      payloadLength = reader.getUint64(2);
      payloadStart += 8;
    }

    var maskingKey = 0;
    if (mask == 1) {
      maskingKey = reader.getUint32(payloadStart);
      payloadStart += 4;
    }

    int payloadDataLength = payloadLength;
    if (payloadStart + payloadDataLength > data.length) {
      payloadDataLength = data.length - payloadStart;
      logger.w("Payload data length exceeds available data, truncating.");
    }

    var payloadData = data.sublist(payloadStart, payloadStart + payloadDataLength);

    if (mask == 1) {
      payloadData = unmaskPayload(payloadData, maskingKey);
    }

    if (rsv1 == 1) {
      //inflate
      payloadData = decompress(payloadData);
    }

    return WebSocketFrame(
      fin: fin == 1,
      opcode: opcode,
      mask: mask == 1,
      maskingKey: maskingKey,
      payloadLength: payloadLength,
      payloadData: payloadData,
    );
  }

  ZLibDecoder? _decoder;

  ZLibDecoder _ensureDecoder() => _decoder ?? ZLibDecoder(raw: true);

  Uint8List decompress(Uint8List msg) {
    try {
      return Uint8List.fromList(_ensureDecoder().convert(msg));
    } catch (e) {
      logger.e("Decompression error", error: e);
      return msg;
    }
  }

  Uint8List unmaskPayload(Uint8List payloadData, int maskingKey) {
    var unmaskedData = Uint8List(payloadData.length);
    for (var i = 0; i < payloadData.length; i++) {
      var keyByte = (maskingKey >> ((3 - (i % 4)) * 8)) & 0xff;
      unmaskedData[i] = payloadData[i] ^ keyByte;
    }
    return unmaskedData;
  }
}

/// 暂停的 WebSocket 帧（用于 MCP 拦截）
class PausedWebSocketFrame {
  final String frameId;
  final String url;
  final bool isOutgoing; // true=客户端发出，false=服务端返回
  Uint8List payload;
  final int opcode;
  final DateTime pausedAt;

  PausedWebSocketFrame({
    required this.frameId,
    required this.url,
    required this.isOutgoing,
    required this.payload,
    required this.opcode,
    required this.pausedAt,
  });

  String get payloadPreview {
    if (opcode == 0x08) return '[Connection Close]';
    if (opcode == 0x09) return '[Ping]';
    if (opcode == 0x0A) return '[Pong]';
    if (opcode == 0x02) return '[Binary Data]';
    try {
      var text = utf8.decode(payload, allowMalformed: true);
      if (text.length > 100) return text.substring(0, 100) + '...';
      return text;
    } catch (e) {
      return '[Binary: ${payload.length} bytes]';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'frameId': frameId,
      'url': url,
      'direction': isOutgoing ? 'outgoing' : 'incoming',
      'opcode': opcode,
      'payload': base64Encode(payload),
      'payloadPreview': payloadPreview,
      'pausedAt': pausedAt.toIso8601String(),
    };
  }
}

/// WebSocket 字节累积缓冲。
///
/// 旧实现每次 `putBytes` 都新建 `Uint8List(totalLen)` 再做两次 `setAll`，
/// 当 TCP 分片很碎而帧很大时形成 **O(n²)** 拷贝；这里改为 `BytesBuilder` 追加，
/// 且只在读取时物化一次（带缓存），一次 `decode` 里多次读 `bytes` 不再重复分配。
class ByteBuffer {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  /// 物化缓存，避免重复 `toBytes()`。
  Uint8List? _cache;

  Uint8List get bytes => _cache ??= _builder.toBytes();

  void putBytes(Uint8List newBytes) {
    if (newBytes.isEmpty) return;
    _builder.add(newBytes);
    _cache = null;
  }

  void clear() {
    _builder.clear();
    _cache = Uint8List(0);
  }

  void removeBytes(int count) {
    if (count <= 0) return;
    final current = bytes;
    if (count >= current.length) {
      _builder.clear();
      _cache = Uint8List(0);
    } else {
      // 仅剩「移走已消费前缀」这一次必要拷贝（无读游标时的下限）。
      _builder
        ..clear()
        ..add(current.sublist(count));
      _cache = null;
    }
  }
}
