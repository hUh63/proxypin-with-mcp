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

/// QPACK 字段段解码（上游 #489 的延续）。
///
/// HTTP/3 的 HEADERS 帧内容是 QPACK 编码的字段段（RFC 9204）。覆盖：
///
/// - Encoded Field Section Prefix（Required Insert Count / Delta Base → 计算 Base）
/// - Indexed Field Line（静态表 / 动态表）
/// - Literal Field Line With Name Reference（静态表 / 动态表名字）
/// - Literal Field Line With Literal Name
/// - Indexed / Literal Field Line With Post-Base Name/Index（动态表后基引用）
/// - Huffman 解码（字符串，复用 HPACK 的表——RFC 9204 明确 QPACK 与 HPACK 用同一套 Huffman 码）
///
/// **动态表**：字段段里引用动态表的字段行，只要调用方传入了对应连接的动态表副本
/// （见 [QpackDynamicTable] / [QpackEncoderStreamDecoder]），即可解出真实的 name/value。
/// 若连接尚未提供编码器指令流（拿不到动态表状态），这类字段行仍以 `:dynamic-*` 占位标出，
/// 并置 [QpackDecodeResult.unresolvedDynamicTable]。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:proxypin/network/http/h2/hpack/huffman_table.dart';
import 'package:proxypin/network/util/quic/qpack_dynamic_table.dart';
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

  /// 字段段是否引用了动态表（信息性，无论是否解出）
  final bool usedDynamicTable;

  /// 是否存在**未能解出**的动态表引用（此时对应字段以占位符呈现）
  final bool unresolvedDynamicTable;

  /// 解码时动态表的已插入条目数（诊断用）
  final int dynamicTableInsertCount;

  /// 解析出错时的说明（此时 [fields] 可能为空）
  final String? error;

  const QpackDecodeResult({
    required this.fields,
    this.usedDynamicTable = false,
    this.unresolvedDynamicTable = false,
    this.dynamicTableInsertCount = 0,
    this.error,
  });

  /// 无错误且动态表引用全部解出
  bool get isClean => error == null && !unresolvedDynamicTable;
}

class _QpackException implements Exception {
  final String message;
  const _QpackException(this.message);
}

/// QPACK 字段段解码器（无状态，动态表状态由调用方按连接传入）
class QpackDecoder {
  /// 单个字段段最多解出多少个字段（防御异常数据）
  static const int maxFields = 128;

  /// 解码一个字段段。
  ///
  /// [dynamicTable] 为该连接上"编码请求头的一方"的动态表副本；
  /// 未提供或状态不足时，动态表引用以占位符呈现。
  static QpackDecodeResult decode(Uint8List data, {QpackDynamicTable? dynamicTable}) {
    final reader = _QpackReader(data);
    var usedDynamic = false;
    var unresolved = false;
    try {
      // 前缀（RFC 9204 §4.5.1 图 12）：
      //   Required Insert Count（8 位前缀整数）
      //   S(1) + Delta Base（7 位前缀整数）——S 是该字节最高位，
      //   会被 7 位前缀的掩码忽略，因此先单独取出。
      final encodedInsertCount = reader.readInt(8);
      final sign = (reader.peekByte() & 0x80) != 0;
      final deltaBase = reader.readInt(7);

      // 还原 Base：由 Required Insert Count 与 Delta Base 计算（RFC 9204 §4.5.1.1）
      var base = 0;
      var dynamicReady = false;
      if (dynamicTable != null) {
        final requiredInsertCount = _requiredInsertCount(encodedInsertCount, dynamicTable);
        if (requiredInsertCount != null && requiredInsertCount <= dynamicTable.insertCount) {
          base = sign ? requiredInsertCount - deltaBase - 1 : requiredInsertCount + deltaBase;
          dynamicReady = true;
        }
      }

      /// 解析前基/后基动态索引到绝对索引并取条目
      QpackDynamicEntry? entryAt(int absoluteIndex) =>
          dynamicReady && absoluteIndex >= 0 ? dynamicTable!.getAbsolute(absoluteIndex) : null;

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
            final entry = entryAt(base - index - 1); // 前基：绝对索引 = Base - 相对索引 - 1
            if (entry != null) {
              fields.add(QpackHeaderField(entry.name, entry.value));
            } else {
              unresolved = true;
              fields.add(QpackHeaderField(':dynamic-index', '动态表索引 $index'));
            }
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
            final entry = entryAt(base - nameIndex - 1);
            if (entry != null) {
              fields.add(QpackHeaderField(entry.name, value));
            } else {
              unresolved = true;
              fields.add(QpackHeaderField(':dynamic-name', value));
            }
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
          // 0001 Index(4+)：后基索引（绝对索引 = Base + 后缀索引）
          final index = reader.readInt(4);
          usedDynamic = true;
          final entry = entryAt(base + index);
          if (entry != null) {
            fields.add(QpackHeaderField(entry.name, entry.value));
          } else {
            unresolved = true;
            fields.add(QpackHeaderField(':post-base-index', '动态表后缀索引 $index'));
          }
        } else {
          // 0000 N NameIndex(3+)：后基名字引用
          final index = reader.readInt(3);
          final value = reader.readString();
          usedDynamic = true;
          final entry = entryAt(base + index);
          if (entry != null) {
            fields.add(QpackHeaderField(entry.name, value));
          } else {
            unresolved = true;
            fields.add(QpackHeaderField(':post-base-name', value));
          }
        }
      }

      return QpackDecodeResult(
        fields: fields,
        usedDynamicTable: usedDynamic,
        unresolvedDynamicTable: unresolved,
        dynamicTableInsertCount: dynamicTable?.insertCount ?? 0,
      );
    } on _QpackException catch (e) {
      return QpackDecodeResult(
        fields: const [],
        usedDynamicTable: usedDynamic,
        unresolvedDynamicTable: unresolved,
        dynamicTableInsertCount: dynamicTable?.insertCount ?? 0,
        error: e.message,
      );
    }
  }

  /// 由编码后的 Required Insert Count 还原真实值（RFC 9204 §4.5.1.1）。
  ///
  /// 无法还原（超出范围 / 掩码不一致）返回 null。
  static int? _requiredInsertCount(int encodedInsertCount, QpackDynamicTable table) {
    if (encodedInsertCount == 0) return 0;
    final maxEntries = table.maxEntries;
    if (maxEntries <= 0) return null;
    final fullRange = 2 * maxEntries;
    if (encodedInsertCount > fullRange) return null;

    final maxValue = table.insertCount + maxEntries;
    final maxWrapped = (maxValue ~/ fullRange) * fullRange;
    var requiredInsertCount = maxWrapped + encodedInsertCount;
    if (requiredInsertCount > maxValue) {
      if (requiredInsertCount <= fullRange) return null;
      requiredInsertCount -= fullRange;
    }
    if (requiredInsertCount == 0) return null;
    return requiredInsertCount;
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
