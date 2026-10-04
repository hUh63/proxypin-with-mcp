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

/// 正则工具与编辑器共用的正则能力：修饰符、替换表达式展开、捕获组枚举。

/// 正则修饰符集合（对应 `(?ims u)` 语义）。
class RegexpFlags {
  /// i：不区分大小写
  final bool ignoreCase;

  /// m：多行模式（^ $ 匹配每行首尾）
  final bool multiLine;

  /// s：DotAll（. 匹配换行符）
  final bool dotAll;

  /// u：Unicode 模式
  final bool unicode;

  const RegexpFlags({
    this.ignoreCase = false,
    this.multiLine = false,
    this.dotAll = false,
    this.unicode = false,
  });

  RegexpFlags copyWith({bool? ignoreCase, bool? multiLine, bool? dotAll, bool? unicode}) {
    return RegexpFlags(
      ignoreCase: ignoreCase ?? this.ignoreCase,
      multiLine: multiLine ?? this.multiLine,
      dotAll: dotAll ?? this.dotAll,
      unicode: unicode ?? this.unicode,
    );
  }

  /// 生成人类可读的修饰符描述，如 `ims`；全关时为空串。
  ///
  /// 注意：Dart（以及 JS）正则**不支持** `(?i)` 这类内联修饰符，
  /// 因此这里只用于展示，不能拿来拼进 pattern 编译。
  String get label {
    final flags = StringBuffer();
    if (ignoreCase) flags.write('i');
    if (multiLine) flags.write('m');
    if (dotAll) flags.write('s');
    if (unicode) flags.write('u');
    return flags.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is RegexpFlags &&
      other.ignoreCase == ignoreCase &&
      other.multiLine == multiLine &&
      other.dotAll == dotAll &&
      other.unicode == unicode;

  @override
  int get hashCode => Object.hash(ignoreCase, multiLine, dotAll, unicode);
}

/// 编译正则；语法错误时返回 null。
RegExp? compileRegExp(String pattern, RegexpFlags flags) {
  if (pattern.isEmpty) return null;
  try {
    return RegExp(
      pattern,
      caseSensitive: !flags.ignoreCase,
      multiLine: flags.multiLine,
      dotAll: flags.dotAll,
      unicode: flags.unicode,
    );
  } catch (_) {
    return null;
  }
}

/// 单个捕获组的取值。
class CaptureGroup {
  final int index;
  final String? value;

  const CaptureGroup(this.index, this.value);
}

/// 枚举某个匹配的捕获组（不含 0 号整体匹配）。
List<CaptureGroup> captureGroupsOf(Match match) {
  final groups = <CaptureGroup>[];
  for (var i = 1; i <= match.groupCount; i++) {
    groups.add(CaptureGroup(i, match.group(i)));
  }
  return groups;
}

/// 替换表达式展开（与 MT 文本编辑器兼容的语义）。
///
/// 支持：
/// - `$0` / `$1` … `$9`：引用捕获组，`$0` 为整体匹配；
/// - `${n}`：引用第 n 组（n ≥ 10 时必须用这种写法）；
/// - `\$` → 字面量 `$`，`\\` → 字面量 `\`；
/// - `\n` / `\r` / `\t`：换行 / 回车 / 制表符；
/// - `\l` / `\u`：把**紧随其后**那次组引用结果的第一（或累计若干）个字符转小写 / 大写；
/// - `\L` / `\U`：把紧随其后的组引用结果整体转小写 / 大写。
///
/// 大小写处理属 MT 扩展（非正则规范），其它工具未必支持。
String expandReplacement(String replacement, Match match) {
  final out = StringBuffer();
  final perChar = <String>[]; // 'l' / 'u' 待应用的单字符大小写操作
  String? wholeCase; // 'L' / 'U' 整体大小写
  var i = 0;

  while (i < replacement.length) {
    final ch = replacement[i];

    if (ch == r'\' && i + 1 < replacement.length) {
      final next = replacement[i + 1];
      switch (next) {
        case r'$':
          out.write(r'$');
          i += 2;
          continue;
        case r'\':
          out.write(r'\');
          i += 2;
          continue;
        case 'n':
          out.write('\n');
          i += 2;
          continue;
        case 'r':
          out.write('\r');
          i += 2;
          continue;
        case 't':
          out.write('\t');
          i += 2;
          continue;
        case 'l':
          perChar.add('l');
          i += 2;
          continue;
        case 'u':
          perChar.add('u');
          i += 2;
          continue;
        case 'L':
          wholeCase = 'L';
          i += 2;
          continue;
        case 'U':
          wholeCase = 'U';
          i += 2;
          continue;
      }
      // 未知转义：原样输出下一个字符
      out.write(next);
      i += 2;
      continue;
    }

    if (ch == r'$') {
      final parsed = _parseGroupRef(replacement, i);
      if (parsed == null) {
        out.write(r'$');
        i += 1;
        continue;
      }
      final value = _matchGroup(match, parsed.index);
      out.write(_applyCase(value, perChar, wholeCase));
      perChar.clear();
      wholeCase = null;
      i = parsed.end;
      continue;
    }

    out.write(ch);
    i += 1;
  }

  return out.toString();
}

class _GroupRef {
  final int index;
  final int end;

  const _GroupRef(this.index, this.end);
}

/// 从 [start]（`$` 所在下标）解析组引用，失败返回 null（表示字面量 `$`）。
_GroupRef? _parseGroupRef(String s, int start) {
  if (start + 1 >= s.length) return null;
  var i = start + 1;

  if (s[i] == '{') {
    final close = s.indexOf('}', i);
    if (close < 0) return null;
    final numStr = s.substring(i + 1, close);
    final n = int.tryParse(numStr);
    if (n == null) return null;
    return _GroupRef(n, close + 1);
  }

  final begin = i;
  while (i < s.length && _isDigit(s.codeUnitAt(i))) {
    i++;
  }
  if (i == begin) return null;
  return _GroupRef(int.parse(s.substring(begin, i)), i);
}

bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

String _matchGroup(Match match, int index) {
  if (index == 0) return match.group(0) ?? '';
  if (index < 0 || index > match.groupCount) return '';
  return match.group(index) ?? '';
}

/// 应用 `\l \u \L \U` 的大小写处理。
String _applyCase(String value, List<String> perChar, String? wholeCase) {
  var result = value;

  if (perChar.isNotEmpty) {
    final headLen = perChar.length < result.length ? perChar.length : result.length;
    final head = result.substring(0, headLen);
    final tail = result.substring(headLen);
    final buffer = StringBuffer();
    for (var j = 0; j < head.length; j++) {
      final c = head[j];
      buffer.write(perChar[j] == 'l' ? c.toLowerCase() : c.toUpperCase());
    }
    buffer.write(tail);
    result = buffer.toString();
  }

  if (wholeCase == 'L') return result.toLowerCase();
  if (wholeCase == 'U') return result.toUpperCase();
  return result;
}

/// 用替换表达式对 [input] 整体替换，返回 (结果, 替换次数)。
///
/// 与 `String.replaceAllMapped` 的区别是替换串走 [expandReplacement]，
/// 因此支持 `$0`、`${n}`、`\$`、`\l\U` 等写法。
({String text, int count}) replaceWithExpansion(String input, RegExp regex, String replacement) {
  var count = 0;
  final text = input.replaceAllMapped(regex, (match) {
    count++;
    return expandReplacement(replacement, match);
  });
  return (text: text, count: count);
}
