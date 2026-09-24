/*
 * Copyright 2023 Hongen Wang
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
import 'dart:typed_data';

/// gRPC over HTTP/2 解码器。
///
/// 先说清楚「解密」这个词在这里的含义：gRPC 本身不加密，加密的是它脚下的 TLS。
/// 我们做 MITM，TLS 那层已经解掉了，拿到的是明文 HTTP/2 帧。真正缺的是 gRPC 的
/// **语义层**，一共两件事：
///
/// 1. **长度前缀分帧**——gRPC 消息体是 `1 字节压缩标志 + 4 字节大端长度 + payload`
///    的重复拼接，一个 DATA 帧里可能挤着好几条消息，也可能半条消息跨帧；
/// 2. **protobuf 盲解**——payload 是 protobuf，没有 `.proto` 文件时拿不到字段名，
///    但 **wire format 是自描述的**，能解出「字段号 + 类型 + 值」，嵌套消息还能递归。
///
/// 所以这里不依赖任何 schema，就能把「调了哪个方法、状态是几、收了什么字段」摊开。
class GrpcDecoder {
  GrpcDecoder._();

  /// 单次最多拆多少条消息，防止畸形长度把内存吃爆
  static const int maxFrames = 64;

  /// protobuf 嵌套递归深度上限
  static const int maxDepth = 6;

  /// 单个消息最多解析多少字段
  static const int maxFields = 200;

  /// content-type 是否像 gRPC（含 gRPC-Web）
  static bool looksLikeGrpc(String? contentType) {
    if (contentType == null || contentType.isEmpty) {
      return false;
    }
    return contentType.toLowerCase().contains('application/grpc');
  }

  /// gRPC 标准状态码。抓包里 `grpc-status` 是数字，直接翻成人能看的名词。
  static const Map<int, String> statusNames = {
    0: 'OK',
    1: 'CANCELLED',
    2: 'UNKNOWN',
    3: 'INVALID_ARGUMENT',
    4: 'DEADLINE_EXCEEDED',
    5: 'NOT_FOUND',
    6: 'ALREADY_EXISTS',
    7: 'PERMISSION_DENIED',
    8: 'RESOURCE_EXHAUSTED',
    9: 'FAILED_PRECONDITION',
    10: 'ABORTED',
    11: 'OUT_OF_RANGE',
    12: 'UNIMPLEMENTED',
    13: 'INTERNAL',
    14: 'UNAVAILABLE',
    15: 'DATA_LOSS',
    16: 'UNAUTHENTICATED',
  };

  /// 从 HTTP/2 的伪头里取服务与方法：`:path` 形如 `/package.Service/Method`。
  static Map<String, String> serviceOf(String? path) {
    if (path == null) {
      return const {};
    }
    final segs = path.split('/').where((e) => e.isNotEmpty).toList();
    if (segs.length >= 2) {
      return {'service': segs[0], 'method': segs[1]};
    }
    if (segs.length == 1) {
      return {'service': segs[0], 'method': ''};
    }
    return const {};
  }

  /// 完整解码入口。
  ///
  /// [body] 是已解密的 HTTP/2 消息体（响应体或请求体）；
  /// [trailers] 是 HTTP/2 trailers（gRPC 的状态就藏在这里）。
  static Map<String, dynamic> decode(
    Uint8List body, {
    String? contentType,
    Map<String, String>? trailers,
    String? path,
    int maxBytes = 512 * 1024,
  }) {
    final out = <String, dynamic>{
      'is_grpc': looksLikeGrpc(contentType) || _hasGrpcTrailer(trailers),
      'content_type': contentType,
    };
    final svc = serviceOf(path);
    if (svc.isNotEmpty) {
      out['service'] = svc['service'];
      out['method'] = svc['method'];
    }

    // 状态：优先 trailers（正常路径），其次 headers 里的 grpc-status
    final tr = <String, String>{};
    if (trailers != null) {
      for (final e in trailers.entries) {
        final k = e.key.toLowerCase();
        if (k.startsWith('grpc-')) {
          tr[k] = e.value;
        }
      }
    }
    if (tr.isNotEmpty) {
      out['trailers'] = tr;
    }
    final statusRaw = tr['grpc-status'];
    if (statusRaw != null) {
      final code = int.tryParse(statusRaw.trim());
      out['status'] = statusRaw;
      out['status_name'] = code == null ? 'UNKNOWN' : (statusNames[code] ?? 'UNRECOGNIZED($code)');
    }
    final msg = tr['grpc-message'];
    if (msg != null && msg.isNotEmpty) {
      out['message'] = Uri.decodeComponent(msg);
    }

    // 消息体分帧
    if (body.isNotEmpty) {
      final truncated = body.length > maxBytes;
      final view = truncated ? Uint8List.sublistView(body, 0, maxBytes) : body;
      final frames = splitFrames(view);
      final list = <Map<String, dynamic>>[];
      for (var i = 0; i < frames.length; i++) {
        list.add(_frameToJson(frames[i], i));
      }
      out['frames'] = list;
      out['frame_count'] = frames.length;
      if (truncated) {
        out['body_truncated'] = true;
        out['body_bytes'] = body.length;
      }
      if (frames.isEmpty) {
        out['note'] = 'no complete gRPC frame found (length prefix may be truncated)';
      }
    }
    return out;
  }

  static bool _hasGrpcTrailer(Map<String, String>? trailers) {
    if (trailers == null) {
      return false;
    }
    return trailers.keys.any((k) => k.toLowerCase().startsWith('grpc-'));
  }

  static Map<String, dynamic> _frameToJson(GrpcFrame frame, int index) {
    final out = <String, dynamic>{
      'index': index,
      'compressed': frame.compressed,
      'length': frame.payload.length,
    };
    final fields = parseProto(frame.payload);
    if (fields.isNotEmpty) {
      out['fields'] = fields.map((f) => f.toJson()).toList();
    }
    final text = _asText(frame.payload);
    if (text != null) {
      out['text'] = text;
    } else if (fields.isEmpty) {
      out['hex'] = _hexOf(frame.payload, 256);
    }
    return out;
  }

  /// 拆长度前缀帧。遇到不完整/超长的长度前缀就停下（不猜、不丢）。
  static List<GrpcFrame> splitFrames(Uint8List data, {int max = maxFrames}) {
    final out = <GrpcFrame>[];
    var offset = 0;
    while (offset + 5 <= data.length && out.length < max) {
      final compressed = data[offset] == 1;
      final length = (data[offset + 1] << 24) |
          (data[offset + 2] << 16) |
          (data[offset + 3] << 8) |
          data[offset + 4];
      if (length < 0 || offset + 5 + length > data.length) {
        break;
      }
      final payload = Uint8List.sublistView(data, offset + 5, offset + 5 + length);
      out.add(GrpcFrame(compressed: compressed, payload: payload));
      offset += 5 + length;
    }
    return out;
  }

  /// protobuf wire format 盲解（不需要 .proto）。
  static List<ProtoField> parseProto(Uint8List data, {int depth = 0}) {
    final fields = <ProtoField>[];
    if (data.isEmpty || depth > maxDepth) {
      return fields;
    }
    var i = 0;
    while (i < data.length && fields.length < maxFields) {
      final tag = _readVarint(data, i);
      if (tag == null) {
        break;
      }
      i = tag.next;
      final number = tag.value >> 3;
      final wireType = tag.value & 0x7;
      if (number == 0) {
        break;
      }
      switch (wireType) {
        case 0: // varint
          final v = _readVarint(data, i);
          if (v == null) {
            return fields;
          }
          i = v.next;
          fields.add(ProtoField(number, wireType, v.value));
          break;
        case 1: // fixed64
          if (i + 8 > data.length) {
            return fields;
          }
          fields.add(ProtoField(
              number, wireType, ByteData.sublistView(data, i, i + 8).getUint64(0, Endian.little)));
          i += 8;
          break;
        case 2: // length-delimited
          final len = _readVarint(data, i);
          if (len == null) {
            return fields;
          }
          i = len.next;
          final size = len.value;
          if (size < 0 || i + size > data.length) {
            return fields;
          }
          final sub = Uint8List.sublistView(data, i, i + size);
          i += size;
          fields.add(_lengthDelimited(number, sub, depth));
          break;
        case 5: // fixed32
          if (i + 4 > data.length) {
            return fields;
          }
          fields.add(ProtoField(
              number, wireType, ByteData.sublistView(data, i, i + 4).getUint32(0, Endian.little)));
          i += 4;
          break;
        default:
          // 3/4 是已废弃的 group，6/7 非法——解析到此为止，别硬猜
          return fields;
      }
    }
    return fields;
  }

  /// length-delimited 可能是三种东西：字符串、嵌套消息、纯二进制。
  /// 判定顺序：可打印文本 → 嵌套消息 → 原始字节。
  static ProtoField _lengthDelimited(int number, Uint8List sub, int depth) {
    if (sub.isEmpty) {
      return ProtoField(number, 2, const <ProtoField>[], kind: 'message');
    }
    final text = _asText(sub);
    if (text != null) {
      return ProtoField(number, 2, text, kind: 'string');
    }
    if (depth < maxDepth) {
      final nested = parseProto(sub, depth: depth + 1);
      // 只有当嵌套解析「干净地吃完整段」才认它是消息，否则会把随机字节解成垃圾字段
      if (nested.isNotEmpty && _consumesAll(sub)) {
        return ProtoField(number, 2, nested, kind: 'message');
      }
    }
    return ProtoField(number, 2, sub, kind: 'bytes');
  }

  /// 复算一遍嵌套解析是否恰好走完整个 buffer——避免把二进制误判成消息。
  static bool _consumesAll(Uint8List data) {
    return _protoLength(data) == data.length;
  }

  /// 返回能干净解析的字节数；解析不动就返回 -1。
  static int _protoLength(Uint8List data) {
    var i = 0;
    var guard = 0;
    while (i < data.length) {
      if (guard++ > maxFields) {
        return -1;
      }
      final tag = _readVarint(data, i);
      if (tag == null) {
        return -1;
      }
      i = tag.next;
      final number = tag.value >> 3;
      final wireType = tag.value & 0x7;
      if (number == 0) {
        return -1;
      }
      switch (wireType) {
        case 0:
          final v = _readVarint(data, i);
          if (v == null) {
            return -1;
          }
          i = v.next;
          break;
        case 1:
          i += 8;
          break;
        case 2:
          final len = _readVarint(data, i);
          if (len == null) {
            return -1;
          }
          i = len.next + len.value;
          break;
        case 5:
          i += 4;
          break;
        default:
          return -1;
      }
      if (i > data.length) {
        return -1;
      }
    }
    return i;
  }

  /// 读 varint（最多 10 字节）。返回 null 表示越界或超长。
  static _Varint? _readVarint(Uint8List data, int start) {
    var result = 0;
    var shift = 0;
    var i = start;
    while (i < data.length && shift < 64) {
      final b = data[i];
      result |= (b & 0x7F) << shift;
      i++;
      if ((b & 0x80) == 0) {
        return _Varint(result, i);
      }
      shift += 7;
    }
    return null;
  }

  /// 能当文本看就返回文本（要求高可打印率，避免把二进制当乱码字符串展示）。
  static String? _asText(Uint8List data) {
    if (data.isEmpty) {
      return null;
    }
    String decoded;
    try {
      decoded = utf8.decode(data);
    } catch (_) {
      return null;
    }
    if (decoded.isEmpty) {
      return null;
    }
    var printable = 0;
    for (final r in decoded.runes) {
      if (r == 0x09 || r == 0x0A || r == 0x0D || (r >= 0x20 && r != 0x7F)) {
        printable++;
      }
    }
    if (printable / decoded.runes.length < 0.9) {
      return null;
    }
    return decoded;
  }

  static String _hexOf(Uint8List data, int limit) {
    final n = data.length > limit ? limit : data.length;
    final sb = StringBuffer();
    for (var i = 0; i < n; i++) {
      sb.write(data[i].toRadixString(16).padLeft(2, '0'));
    }
    if (data.length > n) {
      sb.write('...(共 ${data.length} 字节)');
    }
    return sb.toString();
  }

  /// 一行摘要，用于列表/审计里的「一眼看懂」。
  static String summarize(Map<String, dynamic> decoded) {
    final parts = <String>[];
    final svc = decoded['service'];
    final method = decoded['method'];
    if (svc != null && method != null && '$method'.isNotEmpty) {
      parts.add('$svc/$method');
    }
    final status = decoded['status_name'];
    if (status != null) {
      parts.add('status=$status');
    }
    final count = decoded['frame_count'];
    if (count != null) {
      parts.add('$count msg');
    }
    return parts.isEmpty ? 'gRPC' : parts.join(' · ');
  }
}

/// 一条 gRPC 消息（长度前缀拆出来的单帧）
class GrpcFrame {
  final bool compressed;
  final Uint8List payload;

  const GrpcFrame({required this.compressed, required this.payload});
}

/// protobuf 字段（无 schema 时的 best-effort 结果）
class ProtoField {
  final int number;
  final int wireType;
  final Object? value;

  /// string / message / bytes / varint / fixed32 / fixed64
  final String kind;

  const ProtoField(this.number, this.wireType, this.value, {this.kind = 'varint'});

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      'field': number,
      'wire_type': wireType,
      'kind': kind,
    };
    final v = value;
    if (v is List<ProtoField>) {
      out['fields'] = v.map((e) => e.toJson()).toList();
    } else if (v is Uint8List) {
      out['bytes'] = v.length;
      out['hex'] = _preview(v);
    } else {
      out['value'] = v;
    }
    return out;
  }

  static String _preview(Uint8List v) {
    final n = v.length > 64 ? 64 : v.length;
    final sb = StringBuffer();
    for (var i = 0; i < n; i++) {
      sb.write(v[i].toRadixString(16).padLeft(2, '0'));
    }
    if (v.length > n) {
      sb.write('…');
    }
    return sb.toString();
  }
}

class _Varint {
  final int value;
  final int next;

  const _Varint(this.value, this.next);
}
