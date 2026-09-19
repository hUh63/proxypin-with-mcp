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

/// QPACK 动态表与编码器指令流解码（RFC 9204 §3.2 / §4.3，上游 #489 延续）。
///
/// 上一版 QPACK 解码只覆盖静态表；动态表要求按顺序跟踪编码器的指令流、跨帧维护
/// 插入 / 淘汰状态。本文件补齐这部分：
///
/// - [QpackDynamicTable]：编码器侧动态表的**解码器副本**（插入 / 淘汰 / 绝对・相对索引）；
/// - [QpackEncoderStreamDecoder]：消费编码器单向流（stream type `0x02`）上的指令——
///   `Set Dynamic Table Capacity` / `Insert With Name Reference` / `Insert With Literal Name` / `Duplicate`。
///
/// 边界（诚实）：动态表只在服务端通过 `SETTINGS_QPACK_MAX_TABLE_CAPACITY` 允许时才被客户端使用；
/// 我们只解密**客户端方向**的包，看不到服务端 SETTINGS，因此无法确知真实的最大容量。
/// 这里按 RFC 9204 §3.2.3 的推荐值 [QpackDynamicTable.defaultMaxCapacity]（4096）计算 `MaxEntries`，
/// 用于前缀 Required Insert Count 的回绕还原；若实际最大容量不同且连接插入数极大，
/// 该回绕还原可能不成立（罕见，届时以占位标注）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:proxypin/network/http/h2/hpack/huffman_table.dart';
import 'package:proxypin/network/util/quic/qpack_static_table.dart';

/// 动态表中的一个条目
class QpackDynamicEntry {
  final String name;
  final String value;

  const QpackDynamicEntry(this.name, this.value);

  /// RFC 9204 §3.2.1：条目大小 = 名字字节数 + 值字节数 + 32
  int get size => name.length + value.length + entryOverhead;

  static const int entryOverhead = 32;
}

/// 动态表数据不足（需要更多字节才能解析完一条指令）
class _NeedMoreBytes implements Exception {
  const _NeedMoreBytes();
}

/// 指令无法解析（数据流已错位）
class _CorruptStream implements Exception {
  final String message;
  const _CorruptStream(this.message);
}

/// 动态表（编码器侧副本）。
///
/// 绝对索引从 0 开始、随插入单调递增且**不因淘汰而回退**；列表里只保留尚未淘汰的条目。
class QpackDynamicTable {
  /// RFC 9204 §3.2.3 推荐默认容量
  static const int defaultMaxCapacity = 4096;

  /// 条目固定开销（RFC 9204 §3.2.1）
  static const int entryOverhead = QpackDynamicEntry.entryOverhead;

  /// 允许的最大容量（SETTINGS_QPACK_MAX_TABLE_CAPACITY；未知时取默认值）
  final int maxCapacity;

  /// 当前容量（由 `Set Dynamic Table Capacity` 指令设置，不得超过 [maxCapacity]）
  int capacity;

  /// 新条目追加在末尾；下标 0 为当前仍存活的最早条目
  final List<QpackDynamicEntry> _entries = [];

  /// 已插入条目总数 = 下一个待插入条目的绝对索引（RFC 9204 的 TotalNumberOfInserts）
  int _insertCount = 0;

  /// 累计淘汰条目数（诊断用）
  int evicted = 0;

  QpackDynamicTable({this.maxCapacity = defaultMaxCapacity}) : capacity = maxCapacity;

  /// 已插入条目总数（绝对索引空间的大小）
  int get insertCount => _insertCount;

  /// 当前存活条目数
  int get length => _entries.length;

  bool get isEmpty => _entries.isEmpty;

  /// 当前占用字节数
  int get size {
    var total = 0;
    for (final e in _entries) {
      total += e.size;
    }
    return total;
  }

  /// MaxEntries = floor(MaxTableCapacity / 32)（RFC 9204 §4.5.1.1）
  int get maxEntries => maxCapacity ~/ entryOverhead;

  /// 设置当前容量并立即按新容量淘汰（RFC 9204 §4.3.1.1）
  void setCapacity(int newCapacity) {
    if (newCapacity < 0) return;
    capacity = newCapacity > maxCapacity ? maxCapacity : newCapacity;
    _evictUntilFits(0);
  }

  /// 插入一个条目，返回其绝对索引
  int insert(String name, String value) {
    final entry = QpackDynamicEntry(name, value);
    if (entry.size > capacity) {
      // 放不进当前容量：按规范该条目无法被插入，这里清空并仍推进插入计数，
      // 以保持与编码器的绝对索引对齐（避免后续引用整体错位）。
      _entries.clear();
      _insertCount++;
      return _insertCount - 1;
    }
    _evictUntilFits(entry.size);
    _entries.add(entry);
    _insertCount++;
    return _insertCount - 1;
  }

  /// 按绝对索引取条目；越界或已被淘汰返回 null
  QpackDynamicEntry? getAbsolute(int absoluteIndex) {
    final oldestAbsolute = _insertCount - _entries.length;
    if (absoluteIndex < oldestAbsolute || absoluteIndex >= _insertCount) {
      return null;
    }
    return _entries[absoluteIndex - oldestAbsolute];
  }

  /// 按相对索引取条目：0 表示最新插入的条目（RFC 9204 §3.2.6）
  QpackDynamicEntry? getRelative(int relativeIndex) {
    if (relativeIndex < 0) return null;
    return getAbsolute(_insertCount - 1 - relativeIndex);
  }

  void clear() {
    _entries.clear();
  }

  /// 从最早条目开始淘汰，直到再插入 [incoming] 字节也能放下
  void _evictUntilFits(int incoming) {
    while (_entries.isNotEmpty && size + incoming > capacity) {
      _entries.removeAt(0);
      evicted++;
    }
  }
}

/// 编码器单向流解码器（有状态，可跨多个 STREAM 帧增量投喂）。
///
/// 指令之间无边界标记，因此必须**按顺序**消费；遇到不完整指令时暂存等待后续字节，
/// 遇到错位指令则停止（此后不再解析，避免连锁误读）。
class QpackEncoderStreamDecoder {
  final QpackDynamicTable table;

  final List<int> _buffer = [];
  int _pos = 0;

  /// 成功应用的指令数
  int appliedCount = 0;

  /// 是否已因错位而停止解析
  bool broken = false;

  /// 最近一次错位说明
  String? lastError;

  QpackEncoderStreamDecoder(this.table);

  /// 追加编码器流字节并尽可能多地应用完整指令
  void addData(Uint8List data) {
    if (data.isEmpty || broken) return;
    _buffer.addAll(data);
    _applyAll();
    _compact();
  }

  void _applyAll() {
    while (true) {
      final start = _pos;
      try {
        _applyOne();
        appliedCount++;
      } on _NeedMoreBytes {
        _pos = start; // 回退到指令起点，等待更多字节
        return;
      } on _CorruptStream catch (e) {
        _pos = start;
        broken = true;
        lastError = e.message;
        return;
      }
      if (_pos >= _buffer.length) return;
    }
  }

  /// 应用一条指令（不完整时抛 [_NeedMoreBytes]，错位时抛 [_CorruptStream]）
  void _applyOne() {
    final reader = _StreamReader(_buffer, _pos);
    final b = reader.peek();

    if ((b & 0x80) != 0) {
      // 1 T Index(6+)：以名字引用插入
      final t = (b >> 6) & 1;
      final index = reader.readInt(6);
      final value = _readString(reader);
      final String name;
      if (t == 1) {
        name = QpackStaticTable.nameAt(index) ?? '';
      } else {
        final entry = table.getRelative(index);
        if (entry == null) {
          throw _CorruptStream('编码器流引用了未知的动态表条目（相对索引 $index）');
        }
        name = entry.name;
      }
      table.insert(name, value);
    } else if ((b & 0xc0) == 0x40) {
      // 01 H NameLen(3+)：以字面名字插入（H 为 bit5，长度是 3 位前缀）
      final nameHuffman = (b & 0x20) != 0;
      final nameLength = reader.readInt(3);
      final name = _decodeString(reader.readBytes(nameLength), nameHuffman);
      final value = _readString(reader);
      table.insert(name, value);
    } else if ((b & 0xe0) == 0x20) {
      // 001 Capacity(5+)：设置动态表容量
      final capacity = reader.readInt(5);
      if (capacity > table.maxCapacity) {
        throw _CorruptStream('编码器流设置的容量 $capacity 超过允许的最大值 ${table.maxCapacity}');
      }
      table.setCapacity(capacity);
    } else {
      // 000 Index(5+)：复制条目
      final index = reader.readInt(5);
      final entry = table.getRelative(index);
      if (entry == null) {
        throw _CorruptStream('编码器流引用了未知的动态表条目（相对索引 $index）');
      }
      table.insert(entry.name, entry.value);
    }

    _pos = reader.pos;
  }

  String _readString(_StreamReader reader) {
    final huffman = (reader.peek() & 0x80) != 0;
    final length = reader.readInt(7);
    return _decodeString(reader.readBytes(length), huffman);
  }

  static String _decodeString(Uint8List bytes, bool huffman) {
    if (!huffman) {
      return _decodeBytes(bytes);
    }
    try {
      // QPACK 与 HPACK 共用同一套 Huffman 码（RFC 9204 §4.1.2）
      return _decodeBytes(http2HuffmanCodec.decode(bytes));
    } catch (_) {
      return _decodeBytes(bytes);
    }
  }

  /// 头部字段是字节串，绝大多数为 UTF-8；按 UTF-8 尽力解码，非法字节不抛错。
  static String _decodeBytes(List<int> bytes) =>
      utf8.decode(bytes, allowMalformed: true);

  /// 丢弃已消费的前缀，避免缓冲无限增长
  void _compact() {
    if (_pos == 0) return;
    if (_pos >= _buffer.length) {
      _buffer.clear();
      _pos = 0;
      return;
    }
    if (_pos > 4096 && _pos * 2 > _buffer.length) {
      _buffer.removeRange(0, _pos);
      _pos = 0;
    }
  }
}

/// 字节读取器：数据不足时抛 [_NeedMoreBytes]
class _StreamReader {
  final List<int> data;
  int pos;

  _StreamReader(this.data, this.pos);

  int peek() {
    if (pos >= data.length) throw const _NeedMoreBytes();
    return data[pos];
  }

  /// 读一个 [prefixBits] 位前缀整数（RFC 9204 §4.1.1）
  int readInt(int prefixBits) {
    if (pos >= data.length) throw const _NeedMoreBytes();
    final mask = (1 << prefixBits) - 1;
    var value = data[pos] & mask;
    pos++;
    if (value < mask) return value;

    var shift = 0;
    while (true) {
      if (pos >= data.length) throw const _NeedMoreBytes();
      final b = data[pos++];
      value += (b & 0x7f) << shift;
      shift += 7;
      if ((b & 0x80) == 0) break;
      if (shift > 56) throw const _CorruptStream('整数过大');
    }
    return value;
  }

  Uint8List readBytes(int length) {
    if (length < 0) throw const _CorruptStream('长度非法');
    if (pos + length > data.length) throw const _NeedMoreBytes();
    final out = Uint8List.fromList(data.sublist(pos, pos + length));
    pos += length;
    return out;
  }
}
