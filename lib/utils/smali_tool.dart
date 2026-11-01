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

// Smali 小工具：转正则 / 提取字符串常量 / 描述符转 Java。
//
// 这三件事都是写 hook 规则时的日常动作（找方法、抠常量、看类型），
// 跟「破解」没关系 —— 分析自己的 App、写单元测试、做兼容适配都用得上。

import 'dart:convert';
import 'dart:typed_data';

class SmaliTool {
  SmaliTool._();

  /// 把一段 smali 标识（类名 / 方法签名 / 字段）转成**可搜索的正则**。
  ///
  /// 只转义正则元字符，不做模糊化 —— 结果要能直接粘进搜索框或代码里。
  static String toRegex(String input) {
    final buf = StringBuffer();
    const meta = r'\^$.|?*+()[]{}';
    for (final ch in input.split('')) {
      if (meta.contains(ch)) {
        buf.write('\\');
      }
      buf.write(ch);
    }
    return buf.toString();
  }

  /// 从 smali 源码里提取所有 `const-string` 常量（含 `const-string/jumbo`）。
  ///
  /// 返回去重后的值列表（保持出现顺序）。带转义 `\n` 之类会解一层。
  static List<String> extractStringConstants(String smali) {
    final out = <String>[];
    final seen = <String>{};
    final re = RegExp(r'const-string(?:/jumbo)?\s+v\d+\s*,\s*"((?:[^"\\]|\\.)*)"');
    for (final m in re.allMatches(smali)) {
      final raw = m.group(1) ?? '';
      final value = _unescapeSmali(raw);
      if (seen.add(value)) out.add(value);
    }
    return out;
  }

  /// 从 smali 源码里提取所有被调用的方法（`invoke-*`），返回 `Lcls;->name(sig)ret` 形式。
  static List<String> extractInvocations(String smali) {
    final out = <String>[];
    final seen = <String>{};
    final re = RegExp(r'invoke-[\w/-]+\s+\{[^}]*\},\s*(L[^;]+;|\[+L[^;]+;)->([\w<>$]+)\(([^)]*)\)(\S+)');
    for (final m in re.allMatches(smali)) {
      final cls = m.group(1) ?? '';
      final name = m.group(2) ?? '';
      final args = m.group(3) ?? '';
      final ret = m.group(4) ?? '';
      final sig = '$cls->$name($args)$ret';
      if (seen.add(sig)) out.add(sig);
    }
    return out;
  }

  /// 把类型描述符转成 Java 写法：`Ljava/lang/String;` → `java.lang.String`，
  /// `[I` → `int[]`，`Lcom/a/B;[I` 这种连写也能逐个转。
  static String descriptorsToJava(String input) {
    // 先处理「描述符列表」（方法参数那种连写），再兜底单点替换。
    final re = RegExp(r'(\[+)?([ZBSCIJFD]|L[^;]+;)');
    final buf = StringBuffer();
    var i = 0;
    for (final m in re.allMatches(input)) {
      if (m.start > i) buf.write(input.substring(i, m.start));
      final dims = m.group(1)?.length ?? 0;
      final body = m.group(2) ?? '';
      final base = switch (body) {
        'Z' => 'boolean',
        'B' => 'byte',
        'S' => 'short',
        'C' => 'char',
        'I' => 'int',
        'J' => 'long',
        'F' => 'float',
        'D' => 'double',
        'V' => 'void',
        _ => body.startsWith('L') ? body.substring(1, body.length - 1).replaceAll('/', '.') : body,
      };
      buf.write(base);
      for (var d = 0; d < dims; d++) {
        buf.write('[]');
      }
      i = m.end;
    }
    if (i < input.length) buf.write(input.substring(i));
    return buf.toString();
  }

  /// smali 字符串里的转义解一层（`\n` `\t` `\"` `\\` `\uXXXX`）。
  static String _unescapeSmali(String raw) {
    if (!raw.contains('\\')) return raw;
    final buf = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final ch = raw[i];
      if (ch != '\\' || i + 1 >= raw.length) {
        buf.write(ch);
        continue;
      }
      final next = raw[i + 1];
      switch (next) {
        case 'n':
          buf.write('\n');
          i++;
        case 't':
          buf.write('\t');
          i++;
        case 'r':
          buf.write('\r');
          i++;
        case '"':
          buf.write('"');
          i++;
        case '\\':
          buf.write('\\');
          i++;
        case 'u':
          if (i + 5 < raw.length) {
            final hex = raw.substring(i + 2, i + 6);
            final code = int.tryParse(hex, radix: 16);
            if (code != null) {
              buf.writeCharCode(code);
              i += 5;
              continue;
            }
          }
          buf.write(ch);
        default:
          buf.write(next);
          i++;
      }
    }
    return buf.toString();
  }
}

/// CRC32（IEEE 802.3，zip/apk 用的那个多项式）。
class Crc32Tool {
  Crc32Tool._();

  static final Uint32List _table = _buildTable();

  static Uint32List _buildTable() {
    final table = Uint32List(256);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      table[i] = c;
    }
    return table;
  }

  /// 计算 CRC32（返回值范围 0..0xFFFFFFFF）。
  static int compute(List<int> bytes, {int offset = 0, int? length}) {
    var crc = 0xFFFFFFFF;
    final end = offset + (length ?? (bytes.length - offset));
    for (var i = offset; i < end && i < bytes.length; i++) {
      crc = _table[(crc ^ bytes[i]) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static String hex(int crc) => crc.toRadixString(16).toUpperCase().padLeft(8, '0');
}

/// zip 里的一个条目（中央目录里的一条记录）。
class ZipEntryInfo {
  final String name;
  final int crc;
  final int compressedSize;
  final int uncompressedSize;
  final int method;

  /// 中央目录记录的绝对偏移（改 CRC 用）。
  final int cdOffset;

  /// 对应本地文件头（local file header）的绝对偏移。
  final int localOffset;

  const ZipEntryInfo({
    required this.name,
    required this.crc,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.method,
    required this.cdOffset,
    required this.localOffset,
  });
}

/// 读写 zip 的 CRC 字段（只动那 4 个字节，不重打包）。
class ZipCrcEditor {
  ZipCrcEditor._();

  /// 解析中央目录，列出全部条目。不是 zip 就返回 null。
  static List<ZipEntryInfo>? readEntries(Uint8List bytes) {
    final eocd = _findEocd(bytes);
    if (eocd < 0) return null;
    final count = _u16(bytes, eocd + 10);
    var p = _u32(bytes, eocd + 16);
    final out = <ZipEntryInfo>[];
    for (var i = 0; i < count; i++) {
      if (p + 46 > bytes.length || _u32(bytes, p) != 0x02014b50) break;
      final nameLen = _u16(bytes, p + 28);
      final extraLen = _u16(bytes, p + 30);
      final commentLen = _u16(bytes, p + 32);
      final localOffset = _u32(bytes, p + 42);
      final name = utf8.decode(bytes.sublist(p + 46, (p + 46 + nameLen).clamp(0, bytes.length)),
          allowMalformed: true);
      out.add(ZipEntryInfo(
        name: name,
        crc: _u32(bytes, p + 16),
        compressedSize: _u32(bytes, p + 20),
        uncompressedSize: _u32(bytes, p + 24),
        method: _u16(bytes, p + 10),
        cdOffset: p,
        localOffset: localOffset,
      ));
      p += 46 + nameLen + extraLen + commentLen;
    }
    return out;
  }

  /// 把第 [index] 个条目的 CRC32 改成 [newCrc]（中央目录 + 本地头两处都改）。
  ///
  /// 返回改好的新字节（**不**原地修改，调用方自己决定写哪个文件）。
  /// 语义提醒：改完之后 zip 的 CRC 校验必然对不上（数据没变），这是这个工具的
  /// 本意 —— 用于对「只看目录 CRC」的校验做一致性测试。
  static Uint8List patchEntryCrc(Uint8List bytes, int index, int newCrc) {
    final entries = readEntries(bytes);
    if (entries == null || index < 0 || index >= entries.length) return bytes;
    final e = entries[index];
    final out = Uint8List.fromList(bytes);
    _w32(out, e.cdOffset + 16, newCrc);
    // 本地头：签名 + 相对 14 的 crc 字段（先确认签名在，避免误写）。
    final lo = e.localOffset;
    if (lo + 30 <= out.length && _u32(out, lo) == 0x04034b50) {
      _w32(out, lo + 14, newCrc);
    }
    return out;
  }

  /// 找 EOCD（末尾 22 字节 + 最多 64KB 注释，所以从后往前扫）。
  static int _findEocd(Uint8List b) {
    final start = b.length - 22;
    final limit = start - 0xFFFF;
    for (var i = start; i >= 0 && i >= limit; i--) {
      if (b[i] == 0x50 && b[i + 1] == 0x4b && b[i + 2] == 0x05 && b[i + 3] == 0x06) return i;
    }
    return -1;
  }

  static int _u16(Uint8List b, int o) => (b[o] & 0xFF) | ((b[o + 1] & 0xFF) << 8);

  static int _u32(Uint8List b, int o) =>
      (b[o] & 0xFF) | ((b[o + 1] & 0xFF) << 8) | ((b[o + 2] & 0xFF) << 16) | ((b[o + 3] & 0xFF) << 24);

  static void _w32(Uint8List b, int o, int v) {
    b[o] = v & 0xFF;
    b[o + 1] = (v >> 8) & 0xFF;
    b[o + 2] = (v >> 16) & 0xFF;
    b[o + 3] = (v >> 24) & 0xFF;
  }
}
