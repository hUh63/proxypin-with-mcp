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

/// 代码结构启发式：判断「这一行属于哪个函数」。
///
/// 「调用层次」只需要回答「谁在调用这个东西」—— 对每一处命中往上找最近的那层
/// 函数声明就够用了，不需要真正的语法解析。混语言（Dart/Java/JS/Python/Go…）
/// 的缩进与声明形态差异很大，所以这里全部按「缩进 + 括号 + 关键字黑名单」做启发，
/// 判不出来就归到顶层，不猜。
class CodeSymbols {
  CodeSymbols._();

  /// 缩进宽度（Tab 记 2 列）。
  static int indentOf(String line) {
    var n = 0;
    for (var i = 0; i < line.length; i++) {
      final c = line.codeUnitAt(i);
      if (c == 32) {
        n++;
      } else if (c == 9) {
        n += 2;
      } else {
        break;
      }
    }
    return n;
  }

  /// 这些词后面跟括号但不是「函数声明」。
  static const Set<String> notFunctionWords = {
    'if', 'for', 'while', 'switch', 'catch', 'else', 'do', 'try', 'return',
    'new', 'await', 'yield', 'case', 'when', 'match', 'unless', 'assert',
    'throw', 'print', 'super', 'this', 'sizeof', 'typeof', 'delete', 'in',
    'using', 'lock', 'foreach', 'synchronized',
  };

  static bool _isIdentChar(int c) =>
      (c >= 97 && c <= 122) ||
      (c >= 65 && c <= 90) ||
      (c >= 48 && c <= 57) ||
      c == 95 ||
      c == 36;

  /// 取一行里「最后一个 `(` 前面那个标识符」。
  ///
  /// 为什么不用正则从行首找第一个标识符：`func (s *Svc) Run() {` 里第一个
  /// 标识符是 `func`（Go 的关键字），从前往后匹配会拿到它而不是 `Run`。
  /// 声明行里函数名总是紧挨着 **最后一个** 左括号，从后往前取才稳。
  static String? nameBeforeLastParen(String line) {
    final paren = line.lastIndexOf('(');
    if (paren <= 0) return null;
    var k = paren - 1;
    while (k >= 0 && (line.codeUnitAt(k) == 32 || line.codeUnitAt(k) == 9)) {
      k--;
    }
    final end = k + 1;
    while (k >= 0 && _isIdentChar(line.codeUnitAt(k))) {
      k--;
    }
    if (end <= k + 1) return null;
    return line.substring(k + 1, end);
  }

  /// 从 [hitLine]（0-based）往上找包住它的函数名；找不到返回 null。
  ///
  /// [maxLookBack] 限制最多往上翻多少行（默认 300），避免在超长函数里扫全文。
  static String? enclosingCaller(List<String> lines, int hitLine,
      {int maxLookBack = 300}) {
    if (hitLine < 0 || hitLine >= lines.length) return null;
    final hitIndent = indentOf(lines[hitLine]);
    // 从命中行的**上一行**开始：命中行本身是「调用处」，不可能是外层函数声明
    for (var i = hitLine - 1; i >= 0 && i > hitLine - maxLookBack; i--) {
      final raw = lines[i];
      final t = raw.trim();
      if (t.isEmpty ||
          t.startsWith('//') ||
          t.startsWith('*') ||
          t.startsWith('/*') ||
          t.startsWith('#')) {
        continue;
      }
      // 同一层或更深的行不是「外层函数」
      if (indentOf(raw) >= hitIndent) continue;
      if (t.endsWith(';') || t.endsWith(',')) continue;
      final name = nameBeforeLastParen(t);
      if (name == null || name.isEmpty) continue;
      if (notFunctionWords.contains(name)) continue;
      return name;
    }
    return null;
  }

  /// 取 [line] 上「声明」的名字（`void foo(` → `foo`，`class Foo {` → `Foo`）。
  /// 判不出来返回 null。
  static String? declaredName(String line) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('//') || t.startsWith('*')) return null;
    final fn = nameBeforeLastParen(t);
    if (fn != null && fn.isNotEmpty && !notFunctionWords.contains(fn)) {
      return fn;
    }
    final cls = RegExp(
            r'^(?:export\s+)?(?:public\s+|private\s+|protected\s+|abstract\s+|final\s+|sealed\s+)*'
            r'(?:class|struct|interface|enum|record|namespace|module)\s+([A-Za-z_$][\w$]*)')
        .firstMatch(t);
    return cls?.group(1);
  }
}
