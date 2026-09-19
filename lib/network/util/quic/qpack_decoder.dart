/*
 * Copyright 2025 Hongen Wang All rights reserved.
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

/// QPACK 字段段解码（**简化子集**，上游 #489 的延续）。
///
/// HTTP/3 的 HEADERS 帧内容是 QPACK 编码的字段段（RFC 9204）。本实现只覆盖
/// **不需要动态表同步**的部分，足以解出绝大多数请求/响应头：
///
/// - Encoded Field Section Prefix（Required Insert Count / Delta Base）
/// - Indexed Field Line（静态表）
/// - Literal Field Line With Name Reference（静态表名字）
/// - Literal Field Line With Literal Name
/// - Huffman 解码（字符串，复用 HPACK 的表——RFC 9204 明确 QPACK 与 HPACK 用同一套 Huffman 码）
///
/// **不支持**：动态表（Dynamic Table / post-base 引用）——这类字段行会以
/// `:dynamic-*` 占位标出，并置 [QpackDecodeResult.usedDynamicTable]。
/// 动态表要求按顺序跟踪编码器指令流、跨帧维护插入/淘汰状态，复杂度远超本子集。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:proxypin/network/http/h2/hpack/huffman_table.dart';
import 'package:proxypin/network/util/quic/qpack_static_table.dart';

/// 解出的一个 HTTP/3 头部字段
class QpackHeaderField {
  final String name;
  final String value;

  const QpackHeaderField(this.name, this.value);
}

/// 一次字段段解码的结果
class QpackDecodeResult {
  final List<QpackHeaderField> fields;

  /// 是否引用了动态表（引用部分以占位符呈现）
  final bool usedDynamicTable;

  /// 解析出错时的说明（此时 [fields] 可能为空）
  final String? error;

  const QpackDecodeResult({
    required this.fields,
    this.usedDynamicTable = false,
    this.error,
  });

  bool get isClean => error == null && !usedDynamicTable;
}

class _QpackException implements Exception {
  final String message;
  const _QpackException(this.message);
}

/// QPACK 字段段解码器（无状态）
class QpackDecoder {
  /// 单个字段段最多解出多少个字段（防御异常数据）
  static const int maxFields = 128;

  static QpackDecodeResult decode(Uint8List data) {
    final reader = _QpackReader(data);
    var usedDynamic = false;
    try {
      // 前缀（RFC 9204 §4.5.1 图 12）：Required Insert Count（8 位前缀整数）
      // 之后**总是**跟着 S(1) + Delta Base(7 位前缀整数)。S 位于该字节最高位，
      // 会被 7 位前缀的掩码忽略，这里直接跳过。
      reader.readInt(8); // Required Insert Count
      reader.readInt(7); // Delta Base

      final fields = <QpackHeaderField>[];
      while (reader.hasRemaining && fields.length < maxFields) {
        final b = reader.peekByte();

        if ((b & 0x80) != 0) {
          // 1 T Index(6+)：索引字段行
          final t = (b >> 6) & 1;
          final index = reader.readInt(6);
          if (t == 1) {
            final entry = QpackStaticTable.lookup(index);
            fields.add(entry == null
                ? QpackHeaderField('?', '未知静态索引 $index')
                : QpackHeaderField(entry[0], entry[1]));
          } else {
            usedDynamic = true;
            fields.add(QpackHeaderField(':dynamic-index', '动态表索引 $index'));
          }
        } else if ((b & 0xc0) == 0x40) {
          // 01 N T NameIndex(4+)：名字引用静态/动态表
          final t = (b >> 4) & 1;
          final nameIndex = reader.readInt(4);
          final value = reader.readString();
          if (t == 1) {
            final name = QpackStaticTable.nameAt(nameIndex) ?? '?';
            fields.add(QpackHeaderField(name, value));
          } else {
            usedDynamic = true;
            fields.add(QpackHeaderField(':dynamic-name', value));
          }
        } else if ((b & 0xe0) == 0x20) {
          // 001 N H NameLen(3+)：字面名字 + 字面值
          // 注意：名字的 H 位是 bit3、长度是 3 位前缀（与 value 的 7 位前缀不同）
          final nameHuffman = (b & 0x08) != 0;
          final nameLength = reader.readInt(3);
          final name = _decodeString(reader.readBytes(nameLength), nameHuffman);
          final value = reader.readString();
          fields.add(QpackHeaderField(name, value));
        } else if ((b & 0xf0) == 0x10) {
          // 0001 Index(4+)：post-base 索引（动态表）
          final index = reader.readInt(4);
          usedDynamic = true;
          fields.add(QpackHeaderField(':post-base-index', '动态表后缀索引 $index'));
        } else {
          // 0000 N NameIndex(3+)：post-base 名字引用（动态表）
          final index = reader.readInt(3);
          final value = reader.readString();
          usedDynamic = true;
          fields.add(QpackHeaderField(':post-base-name', value));
        }
      }

      return QpackDecodeResult(fields: fields, usedDynamicTable: usedDynamic);
    } on _QpackException catch (e) {
      return QpackDecodeResult(fields: const [], usedDynamicTable: usedDynamic, error: e.message);
    }
  }

  static String _decodeString(Uint8List bytes, bool huffman) {
    if (!huffman) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    try {
      // QPACK 与 HPACK 使用同一套 Huffman 码（RFC 9204 §4.1.2）
      return utf8.decode(http2HuffmanCodec.decode(bytes), allowMalformed: true);
    } catch (_) {
      // Huffman 表损坏或含 EOS，退回原始字节，避免整体失败
      return utf8.decode(bytes, allowMalformed: true);
    }
  }
}

/// QPACK 字段段的字节读取器（整数 / 字符串按 RFC 9204 §4.1 的编码规则）
class _QpackReader {
  final Uint8List data;
  int pos = 0;

  _QpackReader(this.data);

  bool get hasRemaining => pos < data.length;

  int peekByte() {
    if (pos >= data.length) throw const _QpackException('数据提前结束');
    return data[pos];
  }

  /// 读一个 [prefixBits] 位前缀整数（RFC 7541 §5.1 / RFC 9204 §4.1.1）
  int readInt(int prefixBits) {
    if (pos >= data.length) throw const _QpackException('数据提前结束');
    final mask = (1 << prefixBits) - 1;
    var value = data[pos] & mask;
    pos++;
    if (value < mask) return value;

    var shift = 0;
    while (true) {
      if (pos >= data.length) throw const _QpackException('数据提前结束');
      final b = data[pos++];
      value += (b & 0x7f) << shift;
      shift += 7;
      if ((b & 0x80) == 0) break;
      if (shift > 56) throw const _QpackException('整数过大');
    }
    return value;
  }

  Uint8List readBytes(int length) {
    if (length < 0 || pos + length > data.length) {
      throw const _QpackException('数据提前结束');
    }
    final out = Uint8List.sublistView(data, pos, pos + length);
    pos += length;
    return out;
  }

  /// 读一个字符串（7 位前缀长度 + H 位 + 字节，RFC 9204 §4.1.2）
  String readString() {
    final huffman = (peekByte() & 0x80) != 0;
    final length = readInt(7);
    return QpackDecoder._decodeString(readBytes(length), huffman);
  }
}
