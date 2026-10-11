/*
 * Copyright 2026 Hongen Wang All rights reserved.
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

import 'package:proxypin/utils/big5_table.dart';

/// 纯 Dart 的 Big5-HKSCS 编解码器。
///
/// 采用 WHATWG Encoding Standard 的算法与索引表，因此无需任何平台原生支持，
/// 在 Android / iOS / Windows / Linux / macOS / Web 上行为完全一致。
/// 表里同时包含标准 Big5 的全部字符和 HKSCS 扩展字符，所以 Big5 也用同一份实现。
class Big5HkscsCodec extends Encoding {
  /// 展示用的名字（Big5 / Big5-HKSCS）。
  final String codecName;

  const Big5HkscsCodec([this.codecName = 'Big5-HKSCS']);

  @override
  String get name => codecName;

  @override
  Converter<List<int>, String> get decoder => const Big5HkscsDecoder();

  @override
  Converter<String, List<int>> get encoder => const Big5HkscsEncoder();
}

Uint32List? _cachedIndex;

/// 小端 Uint32 索引表，懒加载一次。
Uint32List get _index {
  final cached = _cachedIndex;
  if (cached != null) return cached;
  var bytes = base64.decode(big5IndexBase64);
  if (bytes.offsetInBytes % 4 != 0) bytes = Uint8List.fromList(bytes);
  final list = Uint32List.view(bytes.buffer, bytes.offsetInBytes, big5IndexLength);
  _cachedIndex = list;
  return list;
}

final Map<int, int> _encodeMap = () {
  final map = <int, int>{};
  final table = _index;
  for (var pointer = 0; pointer < table.length; pointer++) {
    final cp = table[pointer];
    if (cp != 0) map.putIfAbsent(cp, () => pointer);
  }
  return map;
}();

/// 指针 -> 字节对。
int _leadOf(int pointer) => 0x81 + (pointer ~/ 157);

int _trailOf(int pointer) {
  var trail = pointer % 157;
  trail += trail < 0x3F ? 0x40 : 0x62;
  return trail;
}

/// Big5-HKSCS 解码。
class Big5HkscsDecoder extends Converter<List<int>, String> {
  const Big5HkscsDecoder();

  @override
  String convert(List<int> input) {
    final table = _index;
    final out = <int>[];
    var i = 0;
    while (i < input.length) {
      final lead = input[i];
      if (lead < 0x80) {
        out.add(lead);
        i += 1;
        continue;
      }
      if (i + 1 >= input.length) {
        out.add(0xFFFD);
        i += 1;
        continue;
      }
      final trail = input[i + 1];
      final validTrail =
          (trail >= 0x40 && trail <= 0x7E) || (trail >= 0xA1 && trail <= 0xFE);
      if (lead < 0x81 || lead > 0xFE || !validTrail) {
        out.add(0xFFFD);
        i += 1;
        continue;
      }

      final pointer =
          (lead - 0x81) * 157 + (trail < 0x7F ? trail - 0x40 : trail - 0x62);
      // WHATWG 规定的 4 个「一个指针产出两个码点」的特例。
      switch (pointer) {
        case 1133:
          out
            ..add(0x00CA)
            ..add(0x0304);
          break;
        case 1135:
          out
            ..add(0x00CA)
            ..add(0x030C);
          break;
        case 1164:
          out
            ..add(0x00EA)
            ..add(0x0304);
          break;
        case 1166:
          out
            ..add(0x00EA)
            ..add(0x030C);
          break;
        default:
          final cp = pointer >= 0 && pointer < table.length ? table[pointer] : 0;
          out.add(cp != 0 ? cp : 0xFFFD);
      }
      i += 2;
    }
    return String.fromCharCodes(out);
  }
}

/// Big5-HKSCS 编码。无法表示的字符输出 '?'（0x3F），不会抛异常。
class Big5HkscsEncoder extends Converter<String, List<int>> {
  const Big5HkscsEncoder();

  @override
  Uint8List convert(String input) {
    final out = BytesBuilder();
    for (final rune in input.runes) {
      if (rune < 0x80) {
        out.addByte(rune);
        continue;
      }
      final pointer = _encodeMap[rune];
      if (pointer == null) {
        out.addByte(0x3F);
        continue;
      }
      out.addByte(_leadOf(pointer));
      out.addByte(_trailOf(pointer));
    }
    return out.toBytes();
  }
}
