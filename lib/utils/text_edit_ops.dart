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

// 文本编辑里反复用到、且值得单测的纯文本操作。

import 'dart:math';

final RegExp _trailingWhitespace = RegExp(r'[ \t]+$');

/// 跨行版本：`multiLine` 让 `$` 匹配每行结尾，用来做「有没有行尾空白」的快判。
final RegExp _trailingWhitespaceMl = RegExp(r'[ \t]+\r?$', multiLine: true);

/// 去掉每行行尾的空格与制表符（VS Code 的 trimTrailingWhitespace）。
///
/// 只动行尾，缩进、换行符（`\n` / `\r\n`）都原样保留：
/// `a \r\n b ` → `a\r\n b`。
String stripTrailingWhitespace(String text) {
  if (text.isEmpty) return text;
  // 快路径：没有行尾空白就别做 split/join（几 MB 文件能省几十毫秒）。
  if (!_trailingWhitespaceMl.hasMatch(text)) return text;
  return text.split('\n').map(_trimLine).join('\n');
}

/// 修剪单行：CRLF 文件里行尾空白在 `\r` **之前**，先把 `\r` 摘下来再 trim，
/// 否则一个字都删不掉（Windows 上存的文本全是这种情况）。
String _trimLine(String line) {
  if (line.endsWith('\r')) {
    return '${line.substring(0, line.length - 1).replaceFirst(_trailingWhitespace, '')}\r';
  }
  return line.replaceFirst(_trailingWhitespace, '');
}

/// 有多少行带行尾空白（用于「修剪了 N 行」的提示，也用于判断是否需要改动）。
int countTrailingWhitespaceLines(String text) {
  if (text.isEmpty) return 0;
  var count = 0;
  for (final line in text.split('\n')) {
    if (_trimLine(line) != line) count++;
  }
  return count;
}

/// 按内容猜缩进：返回 (是否用 Tab, tabSize)。
///
/// 规则和 VS 的 Detect Indentation 一致：看「以缩进开头的行」里 Tab 多还是空格多；
/// 空格占多时取**最小的非零缩进**当 tabSize（2 空格的项目不会被猜成 4）。
(bool useTabs, int tabSize) guessIndent(String text, {int maxLines = 3000}) {
  var tabLines = 0;
  var spaceLines = 0;
  var minSpace = 0;
  final lines = text.split('\n');
  final limit = min(lines.length, maxLines);
  for (var i = 0; i < limit; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    if (line.startsWith('\t')) {
      tabLines++;
      continue;
    }
    var n = 0;
    while (n < line.length && line.codeUnitAt(n) == 32) {
      n++;
    }
    if (n == 0) continue;
    spaceLines++;
    if (minSpace == 0 || n < minSpace) minSpace = n;
  }
  if (tabLines > spaceLines) return (true, 4);
  if (minSpace >= 2 && minSpace <= 8) return (false, minSpace);
  return (false, 4);
}
