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

// 进制 / 字节 / 浮点之间的互转（纯 Dart，便于单测）。
//
// 这批能力来自两个参考工具：
//   · 「编码工具箱 Pro Max」的「进制互转 / 字符串与 ASCII 互转 / 浮点数与进制互转 /
//     字节数组解码」；
//   · 通用的二进制调试习惯（看包体、看浮点位模式）。
//
// 设计取舍：
//   · 进制互转一律走 BigInt，32 位溢出、负数（含补码写法）都不会算错；
//   · 字节侧统一「空格/逗号/0x 前缀都认」，从日志里直接粘一段就能解；
//   · 浮点只做 float32 / float64 的位模式，这是实际会用到的那两种。

import 'dart:convert';
import 'dart:typed_data';

class NumConvert {
  NumConvert._();

  /// 任意 2~36 进制互转。返回 null 表示输入不是该进制下的合法整数。
  static String? radix(String input, {required int from, required int to}) {
    if (from < 2 || from > 36 || to < 2 || to > 36) return null;
    var text = input.trim();
    if (text.isEmpty) return null;
    // 允许 0x / 0b / 0o 前缀（当它跟 from 一致时去掉）。
    final lower = text.toLowerCase();
    if (text.startsWith('-')) {
      final rest = radix(text.substring(1), from: from, to: to);
      return rest == null ? null : '-$rest';
    }
    if (lower.startsWith('0x')) {
      text = text.substring(2);
    } else if (lower.startsWith('0b')) {
      text = text.substring(2);
    } else if (lower.startsWith('0o')) {
      text = text.substring(2);
    }
    text = text.replaceAll(RegExp(r'[\s,_]'), '');
    if (text.isEmpty) return null;
    final value = BigInt.tryParse(text, radix: from);
    if (value == null) return null;
    return value.toRadixString(to).toUpperCase();
  }

  /// 文本 → 十进制字节序列（"Hi" → "72 105"）。
  static String textToBytes(String input, {int radix = 10, bool pad = false}) {
    final bytes = utf8.encode(input);
    return bytes.map((b) {
      final s = b.toRadixString(radix).toUpperCase();
      return pad && radix == 16 ? s.padLeft(2, '0') : s;
    }).join(' ');
  }

  /// 字节序列 → 文本。分隔符随便（空格 / 逗号 / 0x 前缀 / 换行都行）。
  /// 非法输入返回 null；含非法 UTF-8 时退成「逐字节 Latin-1」，至少不丢数据。
  static String? bytesToText(String input) {
    final bytes = parseBytes(input);
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  /// 宽松解析字节序列：认 `0x1f`、`1f`、`31`、`1F,2e`、`[1, 2, 3]`；
  /// 十进制/十六进制混写时按「有 a-f 就当十六进制」逐段判断。
  static Uint8List? parseBytes(String input) {
    final cleaned = input.replaceAll(RegExp(r'[\[\]\(\)\{\}]'), ' ');
    final parts = cleaned.split(RegExp(r'[\s,;|]+')).where((e) => e.isNotEmpty);
    final out = <int>[];
    for (var part in parts) {
      var p = part;
      if (p.toLowerCase().startsWith('0x')) p = p.substring(2);
      if (p.isEmpty) continue;
      // 含 a-f 就按十六进制，否则按十进制（`72 105` 这类十进制 ASCII 最常见）。
      final hex = p.toLowerCase().contains(RegExp(r'[a-f]'));
      final v = int.tryParse(p, radix: hex ? 16 : 10);
      if (v == null) return null;
      if (v < 0 || v > 255) return null;
      out.add(v);
    }
    return out.isEmpty ? null : Uint8List.fromList(out);
  }

  /// double/float 的位模式（十六进制）。[asFloat32] 用 32 位（网络包里的 float）。
  static String? doubleToHex(String value, {bool asFloat32 = false}) {
    final v = double.tryParse(value.trim());
    if (v == null) return null;
    if (asFloat32) {
      final data = ByteData(4)..setFloat32(0, v);
      return '0x${data.getUint32(0).toRadixString(16).toUpperCase().padLeft(8, '0')}';
    }
    final data = ByteData(8)..setFloat64(0, v);
    return '0x${data.getUint64(0).toRadixString(16).toUpperCase().padLeft(16, '0')}';
  }

  /// 位模式 → double/float（传进来可以是 0x40490FDB / 40490FDB）。
  static double? hexToDouble(String hex, {bool asFloat32 = false}) {
    var h = hex.trim().toLowerCase().replaceFirst('0x', '');
    if (h.isEmpty) return null;
    final bits = BigInt.tryParse(h, radix: 16);
    if (bits == null) return null;
    try {
      if (asFloat32) {
        if (bits > BigInt.from(0xFFFFFFFF)) return null;
        final data = ByteData(4)..setUint32(0, bits.toInt());
        return data.getFloat32(0);
      }
      final data = ByteData(8)..setUint64(0, bits.toInt());
      return data.getFloat64(0);
    } catch (_) {
      return null;
    }
  }

  /// 从一段日志里把 `[12, 34, 56]` / `0x0c 0x22` 这类字节数组全抠出来并解码。
  ///
  /// 逆向 / 调试时日志里刷一大片 byte 数组，一个个粘进工具箱太慢，
  /// 这里一次性全解（找不到花括号包围时退化成「整段按字节解析」）。
  static List<({String raw, String text})> decodeByteArrays(String input) {
    final out = <({String raw, String text})>[];
    final pattern = RegExp(r'\[\s*(?:0x[0-9a-fA-F]{1,2}\s*,\s*)*0x[0-9a-fA-F]{1,2}\s*(?:,\s*0x[0-9a-fA-F]{1,2}\s*)*\]'
        r'|\[\s*\d{1,3}\s*(?:,\s*\d{1,3}\s*)*\]');
    for (final m in pattern.allMatches(input)) {
      final raw = m.group(0)!;
      final text = bytesToText(raw);
      if (text != null && text.isNotEmpty) out.add((raw: raw, text: text));
    }
    if (out.isNotEmpty) return out;
    final single = bytesToText(input);
    if (single != null && single.isNotEmpty) out.add((raw: input.trim(), text: single));
    return out;
  }

  /// 字符串反转（按 rune 反，不会把 emoji 劈成两半）。
  static String reverse(String input) => String.fromCharCodes(input.runes.toList().reversed);

  /// 大小写：upper / lower / title / swap。
  static String changeCase(String input, String mode) {
    switch (mode) {
      case 'upper':
        return input.toUpperCase();
      case 'lower':
        return input.toLowerCase();
      case 'title':
        return input.replaceAllMapped(
            RegExp(r'\b\w'), (m) => m.group(0)!.toUpperCase());
      case 'swap':
        final buf = StringBuffer();
        for (final ch in input.split('')) {
          final up = ch.toUpperCase();
          final low = ch.toLowerCase();
          if (ch == up && ch != low) {
            buf.write(low);
          } else if (ch == low && ch != up) {
            buf.write(up);
          } else {
            buf.write(ch);
          }
        }
        return buf.toString();
    }
    return input;
  }
}
