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

// 「打开文本文件」的统一入口：带容错解码。
//
// 直接 `File.readAsString()` 是**严格 UTF-8**：国内很常见的 GBK 文本
// （.txt / .properties / 老项目源码）会直接抛异常，用户看到的就是「文件打不开」。
// 这里按 BOM → UTF-8（严格）→ GBK → Latin-1 的顺序退让，最后一级保证永远能打开
// （乱码总比打不开好，至少还能看出结构）。

import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart' as charset;

/// 单文件读取上限（超过就先截断，避免把一个几 GB 的日志整份塞进内存）。
const int kTextFileMaxBytes = 8 * 1024 * 1024;

/// 读取结果：正文 + 识别到的编码名（用于提示用户）。
class TextFileContent {
  final String text;
  final String encoding;
  final bool truncated;

  const TextFileContent({required this.text, required this.encoding, this.truncated = false});
}

/// 目录能不能真的读（不是「选到了但用不了」）。
///
/// Android 的目录选择器走 SAF，可能返回 `content://` 或权限受限的路径 ——
/// 用 `Directory(path).list()` 才会暴露问题。选完目录就探一次，比等用户点了
/// 「查找引用 / 开始比较」才发现扫不到东西要早得多。
Future<bool> isDirectoryReadable(String path) async {
  if (path.isEmpty) return false;
  try {
    final dir = Directory(path);
    if (!await dir.exists()) return false;
    // 空目录也算可读：只要能 list 成功（不抛）就行。
    await for (final _ in dir.list(followLinks: false)) {
      return true;
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// 读一个文本文件，失败时按 GBK / Latin-1 退让。**不会抛异常**（读不到返回空串）。
Future<TextFileContent> readTextFileLenient(File file, {int maxBytes = kTextFileMaxBytes}) async {
  List<int> bytes;
  var truncated = false;
  try {
    final len = await file.length();
    if (len > maxBytes) {
      truncated = true;
      final raf = await file.open();
      try {
        bytes = await raf.read(maxBytes);
      } finally {
        await raf.close();
      }
    } else {
      bytes = await file.readAsBytes();
    }
  } catch (_) {
    return const TextFileContent(text: '', encoding: 'unknown');
  }
  return TextFileContent(
    text: decodeTextBytesLenient(bytes),
    encoding: _detectEncoding(bytes),
    truncated: truncated,
  );
}

/// 把字节解码成文本，按 BOM → UTF-8 → GBK → Latin-1 退让。
String decodeTextBytesLenient(List<int> bytes) {
  if (bytes.isEmpty) return '';
  // BOM 优先：UTF-8 / UTF-16LE / UTF-16BE
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: false);
  }
  // 严格 UTF-8：能过就是 UTF-8（绝大多数情况）
  try {
    return utf8.decode(bytes);
  } catch (_) {
    // 落到 GBK
  }
  try {
    final gbk = charset.Charset.getByName('gbk');
    if (gbk != null) return gbk.decode(bytes);
  } catch (_) {
    // 再落到 Latin-1
  }
  return latin1.decode(bytes, allowInvalid: true);
}

String _detectEncoding(List<int> bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return 'UTF-8 BOM';
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) return 'UTF-16LE';
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) return 'UTF-16BE';
  try {
    utf8.decode(bytes);
    return 'UTF-8';
  } catch (_) {
    return 'GBK';
  }
}

String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(littleEndian ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(units);
}
