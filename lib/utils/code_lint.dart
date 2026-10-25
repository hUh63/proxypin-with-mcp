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

// 多语言语法检查（静态、零依赖、纯 Dart）。
//
// 为什么不用真编译器：手机上没有 python/gcc/javac，「语法检查」只能靠增量词法扫描。
// 所以这里按**语言画像**（LintProfile）分派，画像从 [langFamilyOf] 的族信息推导，
// 再由语言专属表覆盖 —— 新增语言不用写新检查器，只需要落进某个族。
//
// 检查项（按顺序，都是「能给出可执行修法」的）：
//   1. 字符串 / 块注释未闭合            → error
//   2. 括号不配平（多余 / 缺失 / 错配）  → error / warning
//   3. 语句行缺分号（仅分号语言）        → warning，可一键补
//   4. 关键字大小写写错（console→Console）→ info，可一键改
//   5. Python 式缩进异常（tab/空格混用、冒号后没缩进）→ warning
//   6. `if (x = 1)` 把赋值当条件        → warning
//   7. JSON / XML 直接走严格解析器，给出行列 → error
//
// 设计原则与 [JsCompiler] 一致：**宁可漏报，不可误报**，所有结论都带明确的
// 行:列与修法，自动修复只做「删一个字符 / 补一个字符 / 改大小写」这类确定动作。
library;

import 'dart:convert';

import 'package:proxypin/utils/code_keywords.dart';
import 'package:proxypin/utils/lang_meta.dart';
import 'package:xml/xml.dart';

/// 诊断严重程度。
enum LintSeverity {
  /// 语法错误，代码跑不起来。
  error,

  /// 可能出错 / 不符合该语言习惯。
  warning,

  /// 只是提醒（例如大小写不符）。
  info,
}

/// 一条诊断。
class LintDiagnostic {
  /// 1 开始的行号。
  final int line;

  /// 1 开始的列号。
  final int column;

  /// 在全文里的字符偏移。
  final int start;

  /// 命中的字符数（可为 0，表示「在某处插入」）。
  final int length;

  final LintSeverity severity;

  /// 规则标识（unclosed-string / extra-bracket / missing-semicolon / case-mismatch …）。
  final String code;

  final String message;

  /// 人能读的修法说明。
  final String? suggestion;

  /// 一键修复时替换 [start, start+length) 的文本；null 表示不可自动修。
  final String? replacement;

  const LintDiagnostic({
    required this.line,
    required this.column,
    required this.start,
    required this.length,
    required this.severity,
    required this.code,
    required this.message,
    this.suggestion,
    this.replacement,
  });

  bool get fixable => replacement != null;

  @override
  String toString() => 'line $line:$column ${severity.name} [$code] $message';
}

/// 一次检查的结果。
class LintReport {
  final List<LintDiagnostic> diagnostics;
  final LintProfile profile;
  final String language;

  /// 文本过大，已跳过检查。
  final bool skipped;

  const LintReport({
    required this.diagnostics,
    required this.profile,
    required this.language,
    this.skipped = false,
  });

  static const LintReport empty = LintReport(
    diagnostics: <LintDiagnostic>[],
    profile: LintProfile(),
    language: '',
  );

  int get errorCount => diagnostics.where((d) => d.severity == LintSeverity.error).length;

  int get warningCount => diagnostics.where((d) => d.severity == LintSeverity.warning).length;

  int get infoCount => diagnostics.where((d) => d.severity == LintSeverity.info).length;

  bool get isEmpty => diagnostics.isEmpty;

  /// 可自动修复的诊断数。
  int get fixableCount => diagnostics.where((d) => d.fixable).length;

  LintSeverity? get worst {
    if (errorCount > 0) return LintSeverity.error;
    if (warningCount > 0) return LintSeverity.warning;
    if (infoCount > 0) return LintSeverity.info;
    return null;
  }
}

/// 语言画像：决定「这个语言怎么识别字符串/注释/块/语句结束」。
class LintProfile {
  /// XML / HTML 这类标记语言。
  final bool markup;

  /// JSON（走严格解析器）。
  final bool json;

  /// 缩进敏感（Python / YAML / Ruby…）。
  final bool indented;

  /// 语句必须以分号结束。
  final bool semicolons;

  /// 支持三引号字符串（Python / Kotlin / Swift…）。
  final bool tripleQuote;

  /// 严格标记：走 XML 解析器（xml / svg / xhtml）。
  final bool strictMarkup;

  /// 什么都不查（HTML / Vue / Svelte 这类模板语法，静态扫描误报太多）。
  final bool skipAll;

  /// 「冒号结尾必须缩进」的语言（Python / Ruby / Julia）。
  final bool blockIndent;

  /// `#` 行注释。
  final bool hashComment;

  /// `--` 行注释（SQL / Lua / Haskell）。
  final bool sqlComment;

  /// `//` 行注释（C 家族）。
  final bool slashComment;

  /// 块注释定界符（C 家族 `/* */`、标记语言 `<!-- -->`）。
  final (String, String)? blockComment;

  /// 供 UI 展示的规则标签（技术词，不翻译）。
  final List<String> traits;

  const LintProfile({
    this.markup = false,
    this.json = false,
    this.indented = false,
    this.semicolons = false,
    this.tripleQuote = false,
    this.strictMarkup = false,
    this.skipAll = false,
    this.blockIndent = false,
    this.hashComment = false,
    this.sqlComment = false,
    this.slashComment = false,
    this.blockComment,
    this.traits = const <String>[],
  });
}

/// 语法检查入口。
class CodeLint {
  /// 超过这个字符数就不检查（避免在 UI 线程上卡死）。
  static const int maxCheckLength = 2 * 1024 * 1024;

  /// 按语言名 / 语言 key 推导画像。
  ///
  /// 顺序：先按 key 命中语言专属表，再退回 [langFamilyOf] 的族信息，
  /// 最后是「纯文本」这种什么都没有的空画像。
  static LintProfile profileOf(String langLabel, String? langKey) {
    final key = (langKey ?? '').toLowerCase();
    final label = langLabel.toLowerCase();
    final family = langFamilyOf(key: key.isEmpty ? null : key, label: langLabel);

    final json = key == 'json' || label == 'json';
    final markup = const <String>{'xml', 'html', 'xhtml', 'svg', 'vue', 'svelte'}.contains(key) ||
        label.contains('xml') ||
        label.contains('html');
    // 严格 XML 才交给解析器；HTML / Vue / Svelte 的模板语法（自闭合标签、{{ }}）
    // 用静态扫描误报太多，直接不查。
    final strictMarkup = const <String>{'xml', 'xhtml', 'svg'}.contains(key) ||
        (key.isEmpty && label.contains('xml'));
    final skipAll = markup && !strictMarkup;
    final blockIndent = key == 'python' || key == 'ruby' || key == 'julia' || label.startsWith('python');
    final indented = const <String>{
          'python', 'yaml', 'yml', 'ruby', 'toml', 'ini', 'makefile', 'dockerfile', //
          'cmake', 'nginx', 'properties', 'julia', 'coffeescript', 'sass', 'stylus',
        }.contains(key) ||
        label.startsWith('python');
    final semicolons = const <String>{
      'c', 'cpp', 'csharp', 'cs', 'java', 'javascript', 'typescript', //
      'dart', 'php', 'objectivec', 'objc', 'groovy', 'scala', 'zig',
    }.contains(key);
    final tripleQuote = const <String>{
          'python', 'kotlin', 'swift', 'groovy', 'scala', 'julia', 'dart',
        }.contains(key) ||
        label.startsWith('python');
    final hashComment = family == LangFamily.hash ||
        const <String>{
          'python', 'ruby', 'perl', 'r', 'yaml', 'yml', 'bash', 'sh', 'shell', 'zsh', //
          'powershell', 'ps1', 'makefile', 'dockerfile', 'cmake', 'nginx', 'toml', 'ini',
          'properties', 'elixir', 'julia', 'coffeescript', 'conf', 'dotenv',
        }.contains(key) ||
        label.startsWith('python') ||
        label.startsWith('shell');
    final sqlComment =
        family == LangFamily.sql || const <String>{'sql', 'lua', 'haskell', 'ada'}.contains(key);
    final slashComment = family == LangFamily.c || family == LangFamily.lisp;

    (String, String)? blockComment;
    if (family == LangFamily.c) blockComment = ('/*', '*/');
    if (family == LangFamily.xml) blockComment = ('<!--', '-->');

    final traits = <String>['brackets'];
    if (json) {
      traits.insert(0, 'json');
    } else if (markup) {
      traits.insert(0, 'markup');
    }
    if (semicolons) traits.add('semicolon');
    if (indented) traits.add('indent');

    return LintProfile(
      markup: markup,
      json: json,
      strictMarkup: strictMarkup,
      skipAll: skipAll,
      blockIndent: blockIndent,
      indented: indented,
      semicolons: semicolons,
      tripleQuote: tripleQuote,
      hashComment: hashComment,
      sqlComment: sqlComment,
      slashComment: slashComment,
      blockComment: blockComment,
      traits: List<String>.unmodifiable(traits),
    );
  }

  /// 检查整份文本。返回按位置排序的诊断。
  static LintReport check(String source, {required String langLabel, String? langKey}) {
    final profile = profileOf(langLabel, langKey);
    if (source.length > maxCheckLength) {
      return LintReport(
        diagnostics: const <LintDiagnostic>[],
        profile: profile,
        language: langLabel,
        skipped: true,
      );
    }
    if (source.trim().isEmpty) {
      return LintReport(diagnostics: const <LintDiagnostic>[], profile: profile, language: langLabel);
    }

    final index = _LineIndex(source);
    final out = <LintDiagnostic>[];

    void add(
      int start,
      int length,
      LintSeverity severity,
      String code,
      String message, {
      String? suggestion,
      String? replacement,
    }) {
      final offset = start < 0 ? 0 : (start > source.length ? source.length : start);
      final line = index.lineOf(offset);
      out.add(LintDiagnostic(
        line: line + 1,
        column: offset - index.starts[line] + 1,
        start: offset,
        length: length,
        severity: severity,
        code: code,
        message: message,
        suggestion: suggestion,
        replacement: replacement,
      ));
    }

    if (profile.skipAll) {
      // 模板语言：不产出诊断（但仍返回画像，UI 可以展示规则）。
    } else if (profile.json) {
      _checkJson(source, add);
    } else if (profile.strictMarkup) {
      _checkMarkup(source, add);
    } else {
      _scanAndCheck(source, profile, langLabel, langKey, add);
    }

    out.sort((a, b) {
      final byPos = a.start.compareTo(b.start);
      return byPos != 0 ? byPos : a.severity.index.compareTo(b.severity.index);
    });
    return LintReport(diagnostics: out, profile: profile, language: langLabel);
  }

  /// 把一批可自动修复的诊断写回文本。
  ///
  /// 从后往前替换，重叠的（前一处修改已经覆盖了它）直接跳过，避免错位。
  static String applyFixes(String source, Iterable<LintDiagnostic> diagnostics) {
    final fixes = diagnostics.where((d) => d.fixable).toList()
      ..sort((a, b) => b.start.compareTo(a.start));
    var out = source;
    var guard = -1; // 上一次修改的起点，本次修改的右边界不能越过它
    for (final d in fixes) {
      final end = d.start + d.length;
      if (end > out.length) continue;
      if (guard >= 0 && end > guard) continue;
      out = out.replaceRange(d.start, end, d.replacement!);
      guard = d.start;
    }
    return out;
  }

  // ------------------------------ JSON / XML ------------------------------

  static void _checkJson(String src, _Add add) {
    try {
      jsonDecode(src);
    } on FormatException catch (e) {
      final offset = (e.offset ?? 0).clamp(0, src.length);
      add(offset, 1, LintSeverity.error, 'json-header', 'JSON: ${e.message}',
          suggestion: '检查该位置附近的引号、逗号与括号');
    }
  }

  static void _checkMarkup(String src, _Add add) {
    try {
      XmlDocument.parse(src);
    } catch (e) {
      final message = e.toString();
      add(0, 0, LintSeverity.error, 'markup', 'XML: $message', suggestion: '检查标签是否成对闭合');
    }
  }

  // ------------------------------ 词法扫描 ------------------------------

  static const int _lf = 10;
  static const int _quote = 0x22;
  static const int _apos = 0x27;
  static const int _backslash = 0x5c;

  static bool _isIdStart(int c) =>
      c == 0x24 ||
      c == 0x5f ||
      (c >= 0x41 && c <= 0x5a) ||
      (c >= 0x61 && c <= 0x7a) ||
      c > 0x7f;

  static bool _isIdPart(int c) => _isIdStart(c) || (c >= 0x30 && c <= 0x39);

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static void _scanAndCheck(
    String src,
    LintProfile p,
    String langLabel,
    String? langKey,
    _Add add,
  ) {
    final n = src.length;
    final units = src.codeUnits.toList();
    final idents = <_Ident>[];
    final stack = <_Open>[];
    // 每行的「行首栈顶符号」与「本行新增的未闭合开括号数」：
    // 判断这一行是不是「语句还没写完」要用的两个量。
    final lineTops = <int>[];
    final lineDeltas = <int>[];
    var lineStartDepth = 0;
    var lineTop = 0;
    var i = 0;
    var inLineComment = false;
    String? blockEnd;

    while (i < n) {
      final c = src.codeUnitAt(i);

      if (c == _lf) {
        lineTops.add(lineTop);
        lineDeltas.add(stack.length - lineStartDepth);
        lineStartDepth = stack.length;
        lineTop = stack.isEmpty ? 0 : stack.last.ch;
      }

      if (inLineComment) {
        if (c != _lf) units[i] = 32;
        else inLineComment = false;
        i++;
        continue;
      }

      if (blockEnd != null) {
        if (src.startsWith(blockEnd!, i)) {
          for (var k = 0; k < blockEnd!.length && i + k < n; k++) {
            units[i + k] = 32;
          }
          i += blockEnd!.length;
          blockEnd = null;
          continue;
        }
        if (c != _lf) units[i] = 32;
        i++;
        continue;
      }

      // 注释起始
      if (p.slashComment && c == 0x2f && i + 1 < n) {
        final c2 = src.codeUnitAt(i + 1);
        if (c2 == 0x2f) {
          inLineComment = true;
          units[i] = 32;
          units[i + 1] = 32;
          i += 2;
          continue;
        }
        if (c2 == 0x2a && p.blockComment != null) {
          blockEnd = p.blockComment!.$2;
          units[i] = 32;
          units[i + 1] = 32;
          i += 2;
          continue;
        }
      }
      if (p.sqlComment && c == 0x2d && i + 1 < n && src.codeUnitAt(i + 1) == 0x2d) {
        inLineComment = true;
        units[i] = 32;
        units[i + 1] = 32;
        i += 2;
        continue;
      }
      if (p.hashComment && c == 0x23) {
        inLineComment = true;
        units[i] = 32;
        i++;
        continue;
      }
      if (p.blockComment != null && src.startsWith(p.blockComment!.$1, i)) {
        blockEnd = p.blockComment!.$2;
        for (var k = 0; k < p.blockComment!.$1.length; k++) {
          units[i + k] = 32;
        }
        i += p.blockComment!.$1.length;
        continue;
      }

      // 字符串
      if (c == _quote || c == _apos) {
        if (p.tripleQuote &&
            i + 2 < n &&
            src.codeUnitAt(i + 1) == c &&
            src.codeUnitAt(i + 2) == c) {
          final start = i;
          i += 3;
          var closed = false;
          while (i < n) {
            final ch = src.codeUnitAt(i);
            if (ch == _backslash) {
              i += 2;
              continue;
            }
            if (ch == c &&
                i + 2 < n &&
                src.codeUnitAt(i + 1) == c &&
                src.codeUnitAt(i + 2) == c) {
              i += 3;
              closed = true;
              break;
            }
            i++;
          }
          if (!closed) {
            add(start, 3, LintSeverity.error, 'unclosed-string', '三引号字符串未闭合',
                suggestion: '补上结尾的 ${String.fromCharCode(c) * 3}');
          }
          continue;
        }

        final start = i;
        i++;
        var closed = false;
        while (i < n) {
          final ch = src.codeUnitAt(i);
          if (ch == _backslash) {
            i += 2;
            continue;
          }
          if (ch == c) {
            // SQL 用 '' 表示一个单引号
            if (p.sqlComment && i + 1 < n && src.codeUnitAt(i + 1) == c) {
              i += 2;
              continue;
            }
            i++;
            closed = true;
            break;
          }
          if (ch == _lf) break; // 普通字符串不跨行
          i++;
        }
        if (!closed) {
          add(start, 1, LintSeverity.error, 'unclosed-string', '字符串未闭合',
              suggestion: '这一行的引号没有配对，检查是否漏了结尾的 ${String.fromCharCode(c)}');
        }
        continue;
      }

      // 标识符
      if (_isIdStart(c)) {
        final start = i;
        i++;
        while (i < n && _isIdPart(src.codeUnitAt(i))) {
          i++;
        }
        idents.add(_Ident(src.substring(start, i), start));
        continue;
      }

      // 数字（跳过，避免把 1.0e5 之类当成标识符）
      if (_isDigit(c)) {
        i++;
        while (i < n) {
          final ch = src.codeUnitAt(i);
          if (_isIdPart(ch) || ch == 0x2e) {
            i++;
          } else {
            break;
          }
        }
        continue;
      }

      // 括号
      if (c == 0x7b || c == 0x28 || c == 0x5b) {
        stack.add(_Open(c, i));
        i++;
        continue;
      }
      if (c == 0x7d || c == 0x29 || c == 0x5d) {
        if (stack.isEmpty) {
          add(i, 1, LintSeverity.error, 'extra-bracket', '多余的 ${String.fromCharCode(c)}：前面没有对应的开括号',
              suggestion: '删掉这个括号', replacement: '');
        } else {
          final open = stack.removeLast();
          final want = open.ch == 0x7b
              ? 0x7d
              : open.ch == 0x28
                  ? 0x29
                  : 0x5d;
          if (c != want) {
            add(i, 1, LintSeverity.error, 'bracket-mismatch',
                '括号不匹配：这里应该是 ${String.fromCharCode(want)}（对应第 ${_lineOfOffset(src, open.at)} 行的 ${String.fromCharCode(open.ch)}）');
          }
        }
        i++;
        continue;
      }

      i++;
    }

    // 收尾：未闭合括号
    if (stack.isNotEmpty) {
      final tail = StringBuffer();
      for (final open in stack.reversed) {
        tail.writeCharCode(open.ch == 0x7b
            ? 0x7d
            : open.ch == 0x28
                ? 0x29
                : 0x5d);
      }
      add(
        n,
        0,
        LintSeverity.error,
        'unclosed-bracket',
        '有 ${stack.length} 个括号没有闭合（最后一个在第 ${_lineOfOffset(src, stack.last.at)} 行）',
        suggestion: '在末尾补上 $tail',
        replacement: tail.toString(),
      );
    }

    // 分号
    if (p.semicolons) {
      _checkSemicolons(src, String.fromCharCodes(units), lineTops, lineDeltas, add);
    }

    // 大小写
    _checkCase(src, idents, langLabel, langKey, add);

    // 缩进
    if (p.indented) _checkIndent(src, p.blockIndent, add);

    // if / while 里把 = 当 ==
    if (p.semicolons || p.slashComment) _checkAssignmentCondition(src, add);
  }

  static void _checkSemicolons(
      String src, String masked, List<int> lineTops, List<int> lineDeltas, _Add add) {
    final rawLines = src.split('\n');
    final maskLines = masked.split('\n');
    var offset = 0;
    const skipHeads = <String>[
      'case ', 'default', 'else', 'do', 'try', 'finally', 'catch', 'template', //
      '@', '#', 'public:', 'private:', 'protected:', 'internal:', '//', '/*', '*',
      '}', 'auto ', 'using ', 'import ', 'package ', 'namespace ', '#region',
    ];

    for (var line = 0; line < maskLines.length && line < rawLines.length; line++) {
      final mask = maskLines[line];
      final lineStart = offset;
      offset += rawLines[line].length + 1;

      final trimmedRight = _trimRight(mask);
      if (trimmedRight.isEmpty) continue;
      // 整行都在注释里
      if (mask.trim().isEmpty) continue;

      // 语句跨行：本行内有没闭合的开括号，或行首就处在 ( / [ 里面。
      // 注意不能只看「栈深 > 0」——函数体的 { 一直开着，那样会把整个函数体都跳过。
      if (line < lineDeltas.length) {
        if (lineDeltas[line] > 0) continue;
        final top = lineTops[line];
        if (top == 0x28 || top == 0x5b) continue;
      }

      final head = mask.trimLeft();
      var skip = false;
      for (final h in skipHeads) {
        if (head.startsWith(h)) {
          skip = true;
          break;
        }
      }
      if (skip) continue;

      final lastChar = trimmedRight[trimmedRight.length - 1];
      if (';{}),]:'.contains(lastChar)) continue;
      // 运算符 / 逗号结尾 → 语句没结束
      if ('+-*/%&|^<>=,:?([.~!'.contains(lastChar)) continue;

      // 下一行以 { 或 : 开头 → 本行是块头
      var nextHead = '';
      for (var k = line + 1; k < maskLines.length; k++) {
        final t = maskLines[k].trim();
        if (t.isEmpty) continue;
        nextHead = t;
        break;
      }
      if (nextHead.startsWith('{') || nextHead.startsWith(':') || nextHead.startsWith('=>')) {
        continue;
      }

      // 上一行是运算符结尾 → 本行是续行
      if (line > 0) {
        final prev = _trimRight(maskLines[line - 1]);
        if (prev.isNotEmpty) {
          final pc = prev[prev.length - 1];
          if ('+-*/%&|^<>=,:?(['.contains(pc)) continue;
        }
      }

      // 行首是 . 或 ? 之类（链式调用续行）也不需要分号
      if (head.startsWith('.') || head.startsWith('?') || head.startsWith(')') || head.startsWith(']')) {
        continue;
      }

      final insertAt = lineStart + trimmedRight.length;
      add(
        insertAt,
        0,
        LintSeverity.warning,
        'missing-semicolon',
        '这行可能缺少分号',
        suggestion: '补上 ;',
        replacement: ';',
      );
    }
  }

  static void _checkCase(
    String src,
    List<_Ident> idents,
    String langLabel,
    String? langKey,
    _Add add,
  ) {
    if (idents.isEmpty) return;
    final known = _knownWords(langLabel, langKey);
    if (known.isEmpty) return;

    final declared = <String>{};
    for (final m
        in RegExp(r'\b(?:class|interface|struct|enum|namespace|function|func|def|var|let|const|val|record|macro)\s+([A-Za-z_$][\w$]*)')
            .allMatches(src)) {
      declared.add(m.group(1)!);
    }

    final seen = <String>{};
    final counts = <String, int>{};
    for (final id in idents) {
      counts[id.text] = (counts[id.text] ?? 0) + 1;
    }

    var emitted = 0;
    for (final id in idents) {
      if (emitted >= 20) break;
      final text = id.text;
      if (text.length < 3) continue;
      if (declared.contains(text)) continue;
      if (seen.contains(text)) continue;
      final canonical = known[text.toLowerCase()];
      if (canonical == null || canonical == text) continue;
      // 该词在文中还有别的写法（用户自己定义的同名不同形）→ 不动
      if ((counts[canonical] ?? 0) > 0) continue;
      seen.add(text);
      emitted++;
      add(
        id.start,
        text.length,
        LintSeverity.info,
        'case-mismatch',
        '「$text」大小写可能写错了，该语言里写作「$canonical」',
        suggestion: '改成 $canonical',
        replacement: canonical,
      );
    }
  }

  static void _checkIndent(String src, bool blockIndent, _Add add) {
    final lines = src.split('\n');
    var offset = 0;
    var prevIndent = 0;
    var prevTrimmed = '';
    for (final raw in lines) {
      final lineStart = offset;
      offset += raw.length + 1;
      final trimmed = raw.trimLeft();
      if (trimmed.isEmpty) continue;
      final indent = raw.length - trimmed.length;
      final lead = raw.substring(0, indent);

      if (lead.contains(' ') && lead.contains('\t')) {
        add(lineStart, indent, LintSeverity.warning, 'mixed-indent', '这一行同时用了空格和制表符缩进',
            suggestion: '统一改成空格（该语言对缩进敏感）');
      }

      if (blockIndent && prevTrimmed.endsWith(':') && !prevTrimmed.startsWith('#')) {
        if (indent <= prevIndent) {
          final newIndent = ' ' * (prevIndent + 4);
          add(lineStart, indent, LintSeverity.warning, 'block-indent',
              '上一行以「:」结尾，这一行应该缩进一层',
              suggestion: '把这一行再缩进 4 个空格',
              replacement: newIndent + trimmed);
        }
      }

      prevIndent = indent;
      prevTrimmed = _trimRight(raw);
    }
  }

  static void _checkAssignmentCondition(String src, _Add add) {
    final re = RegExp(r'\b(?:if|while)\s*\(');
    for (final m in re.allMatches(src)) {
      var i = m.end;
      var depth = 1;
      final start = i;
      while (i < src.length && depth > 0) {
        final c = src[i];
        if (c == '(') depth++;
        if (c == ')') depth--;
        if (depth == 0) break;
        i++;
      }
      if (depth != 0) continue;
      final inner = src.substring(start, i);
      for (var k = 0; k < inner.length; k++) {
        if (inner[k] != '=') continue;
        final prev = k > 0 ? inner[k - 1] : '';
        final next = k + 1 < inner.length ? inner[k + 1] : '';
        if (next == '=' || prev == '=' || prev == '!' || prev == '<' || prev == '>' || prev == ':') {
          continue;
        }
        if (next == '>') continue;
        add(start + k, 1, LintSeverity.warning, 'assign-in-condition',
            '条件里用了赋值「=」，是不是想写「==」？',
            suggestion: '如果不是故意赋值，改成 ==');
        break;
      }
    }
  }

  // ------------------------------ 已知词（大小写纠错用） ------------------------------

  static final Map<String, Map<String, String>> _knownCache = <String, Map<String, String>>{};

  /// 该语言的关键字 / 内置类型表 → 「小写 → 正式写法」。
  ///
  /// 同一个 lowercase 对应多个正式写法时（例如 C# 的 `Object`/`object`）直接丢弃，
  /// 宁可不建议，也不给错的建议。
  static Map<String, String> _knownWords(String langLabel, String? langKey) {
    final cacheKey = '${langKey ?? ''}|$langLabel';
    final cached = _knownCache[cacheKey];
    if (cached != null) return cached;

    // forLanguage 的 key 是非空 String（默认 ''），langKey 可能为 null。
    final words = CodeKeywords.forLanguage(langLabel, langKey ?? '');
    final lower = <String, String>{};
    final dup = <String>{};
    for (final w in words) {
      if (w.length < 3) continue;
      if (!_isIdStart(w.codeUnitAt(0))) continue;
      final l = w.toLowerCase();
      if (l == w) continue; // 全小写词（关键字）不作大小写纠错目标
      final existing = lower[l];
      if (existing != null && existing != w) dup.add(l);
      lower[l] = w;
    }
    for (final d in dup) {
      lower.remove(d);
    }
    _knownCache[cacheKey] = lower;
    return lower;
  }

  // ------------------------------ 工具 ------------------------------

  static String _trimRight(String s) {
    var end = s.length;
    while (end > 0) {
      final c = s.codeUnitAt(end - 1);
      if (c == 32 || c == 9 || c == 13) {
        end--;
      } else {
        break;
      }
    }
    return end == s.length ? s : s.substring(0, end);
  }

  static int _lineOfOffset(String src, int offset) {
    var line = 1;
    final limit = offset < src.length ? offset : src.length;
    for (var i = 0; i < limit; i++) {
      if (src.codeUnitAt(i) == _lf) line++;
    }
    return line;
  }
}

typedef _Add = void Function(
  int start,
  int length,
  LintSeverity severity,
  String code,
  String message, {
  String? suggestion,
  String? replacement,
});

class _Ident {
  final String text;
  final int start;
  const _Ident(this.text, this.start);
}

class _Open {
  final int ch;
  final int at;
  const _Open(this.ch, this.at);
}

/// 行首偏移索引（行号 ↔ 偏移）。
class _LineIndex {
  final List<int> starts;

  _LineIndex(String src) : starts = _build(src);

  static List<int> _build(String src) {
    final list = <int>[0];
    for (var i = 0; i < src.length; i++) {
      if (src.codeUnitAt(i) == 10) list.add(i + 1);
    }
    return list;
  }

  /// 0 开始的行号。
  int lineOf(int offset) {
    var lo = 0;
    var hi = starts.length - 1;
    if (offset <= 0) return 0;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (starts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}
