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
// 设计要点
// 1. **按语言画像分派**，不按语言各写一套：画像（LintProfile）从 lang_meta 的语言族
//    推导出「注释语法 / 字符串语法 / 要不要分号 / 是否缩进敏感 / 块怎么闭合」，
//    190+ 种语言自动落族；新增语言只要落进某个族就有检查能力。
// 2. **宁可漏报，不可误报**。每条规则都为真实代码里的合法写法留了豁免：字符串与
//    注释里的括号、C 预处理行、VB 的单行 If、C++ 的 if (auto x = f())、Rust 的
//    生命周期 'a、C# 的逐字字符串 @"..."、JS 的正则字面量……见各规则注释。
// 3. **不只查大括号语言**：bash / lua / ruby / matlab / pascal / vb / fortran / ada
//    这类用 end 收尾的语言走「块关键字配对」；HTML 走标签配平；Markdown 查代码围栏；
//    ini/properties 查行格式；YAML 查 tab 缩进；Makefile 查命令行是否用了 tab。
// 4. 消息中英双语：check(chinese: ...)，非中文用户看到英文而不是中文。
library;

import 'dart:convert';

import 'package:proxypin/utils/code_keywords.dart';
import 'package:proxypin/utils/lang_meta.dart';
import 'package:xml/xml.dart';

/// 诊断严重程度。
enum LintSeverity { error, warning, info }

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

  /// 只要某一级别的诊断（UI 过滤用）。
  LintReport filter(Set<LintSeverity> levels) => LintReport(
        diagnostics: diagnostics.where((d) => levels.contains(d.severity)).toList(growable: false),
        profile: profile,
        language: language,
        skipped: skipped,
      );
}

/// 语言画像：决定「这个语言怎么识别字符串 / 注释 / 块 / 语句结束」。
class LintProfile {
  /// 语言 key（小写，re_highlight 的标识），用于语言专属规则。
  final String key;

  /// XML / HTML 这类标记语言。
  final bool markup;

  /// 严格标记：走 XML 解析器（xml / svg / xhtml）。
  final bool strictMarkup;

  /// HTML 家族：只做标签配平（不做括号/分号）。
  final bool htmlTags;

  /// 完全不做语法扫描（纯文本、Markdown 正文、HTTP 报文等）。
  final bool skipAll;

  /// 是「编程语言」而不是数据格式 / 标记语言 / 配置文件 / 纯文本。
  ///
  /// 控制台只对编程语言开放：JSON、YAML、Markdown、纯文本这些没有「运行时」概念，
  /// 给一个能算表达式的控制台只会让人困惑。
  final bool programming;

  /// 只看代码围栏（Markdown）。
  final bool fenceCheck;

  /// JSON（走严格解析器）。
  final bool json;

  /// 缩进敏感（Python / YAML / Ruby…）。
  final bool indented;

  /// 「冒号结尾必须缩进」的语言（Python / Ruby / Julia）。
  final bool blockIndent;

  /// 语句必须以分号结束。
  final bool semicolons;

  /// 大小写敏感（SQL / VB / Pascal / Fortran / Ada 不敏感，跳过大小写纠错）。
  final bool caseSensitive;

  /// 支持三引号字符串（Python / Kotlin / Swift…）。
  final bool tripleQuote;

  /// Rust：单引号可能是生命周期标记（'a），不是字符串。
  final bool rustApostrophe;

  /// C#：支持逐字字符串 @"..." 与原始字符串 """..."""。
  final bool atVerbatim;

  /// JS / TS：支持正则字面量 /.../。
  final bool jsRegex;

  /// CSS 家族：块内声明需要分号。
  final bool cssDecls;

  /// ini / properties / toml：每行必须是 key = value 或 [section]。
  final bool iniLike;

  /// YAML：禁止 tab 缩进。
  final bool yamlLike;

  /// Makefile：命令行必须用 tab。
  final bool makefileLike;

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
    this.key = '',
    this.markup = false,
    this.strictMarkup = false,
    this.htmlTags = false,
    this.skipAll = false,
    this.programming = false,
    this.fenceCheck = false,
    this.json = false,
    this.indented = false,
    this.blockIndent = false,
    this.semicolons = false,
    this.caseSensitive = true,
    this.tripleQuote = false,
    this.rustApostrophe = false,
    this.atVerbatim = false,
    this.jsRegex = false,
    this.cssDecls = false,
    this.iniLike = false,
    this.yamlLike = false,
    this.makefileLike = false,
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
  static LintProfile profileOf(String langLabel, String? langKey) {
    final key = (langKey ?? '').toLowerCase();
    final label = langLabel.toLowerCase();
    final family = langFamilyOf(key: key.isEmpty ? null : key, label: langLabel);
    bool oneOf(List<String> list) => list.contains(key);

    final json = key == 'json' || label == 'json';
    final htmlTags = oneOf(['html', 'htm', 'vue', 'svelte']) ||
        (key.isEmpty && (label.contains('html') || label.contains('vue')));
    final strictMarkup = oneOf(['xml', 'svg', 'xhtml']) || (key.isEmpty && label.contains('xml'));
    final fenceCheck = oneOf(['markdown', 'md']) || label.contains('markdown');
    final plain = oneOf(['plaintext', 'text', 'log', 'diff', 'http', 'csv']) ||
        label == 'plain text' ||
        label.contains('plain');
    final skipAll = fenceCheck || plain;
    final markup = htmlTags || strictMarkup;

    final indented = oneOf([
          'python', 'yaml', 'yml', 'ruby', 'toml', 'ini', 'makefile', 'dockerfile', //
          'cmake', 'nginx', 'properties', 'julia', 'coffeescript', 'sass', 'stylus',
        ]) ||
        label.startsWith('python');
    final blockIndent =
        key == 'python' || key == 'ruby' || key == 'julia' || label.startsWith('python');
    final semicolons = oneOf([
      'c', 'cpp', 'csharp', 'cs', 'java', 'javascript', 'typescript', //
      'dart', 'php', 'objectivec', 'objc', 'groovy', 'scala', 'zig',
    ]);
    final caseSensitive =
        !oneOf(['sql', 'vb', 'vbnet', 'visualbasic', 'pascal', 'delphi', 'fortran', 'ada', 'basic']);
    final tripleQuote = oneOf([
          'python', 'kotlin', 'swift', 'groovy', 'scala', 'julia', 'dart', 'csharp', 'cs',
        ]) ||
        label.startsWith('python');
    final hashComment = family == LangFamily.hash ||
        oneOf([
          'python', 'ruby', 'perl', 'r', 'yaml', 'yml', 'bash', 'sh', 'shell', 'zsh', //
          'powershell', 'ps1', 'makefile', 'dockerfile', 'cmake', 'nginx', 'toml', 'ini',
          'properties', 'elixir', 'julia', 'coffeescript', 'conf', 'dotenv',
        ]) ||
        label.startsWith('python') ||
        label.startsWith('shell');
    final sqlComment =
        family == LangFamily.sql || oneOf(['sql', 'lua', 'haskell', 'ada']);
    final slashComment = family == LangFamily.c || family == LangFamily.lisp;

    final yamlLikeKeys = oneOf(['yaml', 'yml']);
    final iniLikeKeys = oneOf(['ini', 'properties', 'conf', 'dotenv', 'toml']);

    (String, String)? blockComment;
    if (family == LangFamily.c) blockComment = ('/*', '*/');
    if (family == LangFamily.xml) blockComment = ('<!--', '-->');

    final traits = <String>['brackets'];
    if (json) {
      traits.insert(0, 'json');
    } else if (strictMarkup) {
      traits.insert(0, 'xml');
    } else if (htmlTags) {
      traits.insert(0, 'tags');
    } else if (fenceCheck) {
      traits.insert(0, 'fence');
    } else if (plain) {
      traits.insert(0, 'plain');
    }
    if (semicolons) traits.add('semicolon');
    if (indented) traits.add('indent');
    if (_pairRules.containsKey(key)) traits.add('blocks');

    final cssDecls = oneOf(['css', 'scss', 'less', 'sass', 'stylus']);
    final programming = !(json ||
        markup ||
        skipAll ||
        yamlLikeKeys ||
        iniLikeKeys ||
        key == 'makefile' ||
        cssDecls ||
        plain) &&
        (key.isNotEmpty ||
            !(label.contains('text') || label.contains('plain') || label.contains('log')));

    return LintProfile(
      key: key,
      markup: markup,
      strictMarkup: strictMarkup,
      htmlTags: htmlTags,
      skipAll: skipAll,
      programming: programming,
      fenceCheck: fenceCheck,
      json: json,
      indented: indented,
      blockIndent: blockIndent,
      semicolons: semicolons,
      caseSensitive: caseSensitive,
      tripleQuote: tripleQuote,
      rustApostrophe: key == 'rust',
      atVerbatim: key == 'csharp' || key == 'cs',
      jsRegex: key == 'javascript' || key == 'typescript' || key == 'coffeescript',
      cssDecls: cssDecls,
      iniLike: iniLikeKeys,
      yamlLike: yamlLikeKeys,
      makefileLike: key == 'makefile',
      hashComment: hashComment,
      sqlComment: sqlComment,
      slashComment: slashComment,
      blockComment: blockComment,
      traits: List<String>.unmodifiable(traits),
    );
  }

  /// 检查整份文本。返回按位置排序的诊断。
  ///
  /// [chinese] 决定消息语言：中文用户看中文，其余看英文。
  /// 「这一行还没写完」类的诊断：光标就停在这行时不该报。
  ///
  /// 真实 IDE 在补全阶段不会因为你刚打了半个词就喊「缺分号」——编译器只在
  /// 整个语句/表达式结束时才判断完整性。这里给编辑器一个「编辑中行」的口子。
  static const Set<String> incompleteCodes = <String>{
    'missing-semicolon',
    'unclosed-string',
    'unclosed-bracket',
    'extra-bracket',
    'block-unclosed',
    'fence-unclosed',
    'tag-unclosed',
    'markup',
    'json-header',
  };

  static LintReport check(
    String source, {
    required String langLabel,
    String? langKey,
    bool chinese = true,
    Set<String> disabledRules = const <String>{},
    int? editingLine,
  }) {
    final profile = profileOf(langLabel, langKey);
    final ctx = _Ctx(chinese);
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
      if (disabledRules.contains(code)) return;
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
      if (profile.fenceCheck) _checkFences(source, ctx, add);
    } else if (profile.json) {
      _checkJson(source, ctx, add);
    } else if (profile.strictMarkup) {
      _checkMarkup(source, ctx, add);
    } else if (profile.htmlTags) {
      _checkHtmlTags(source, ctx, add);
    } else {
      _scanAndCheck(source, profile, langLabel, langKey, ctx, add);
    }

    // 光标所在行（用户正在打的那行）不报「还没写完」类问题：
    // 刚敲到 `cons`、`Console.W` 就说缺分号，是这条路最吵的地方。
    if (editingLine != null) {
      out.removeWhere((d) => d.line == editingLine && incompleteCodes.contains(d.code));
    }
    out.sort((a, b) {
      final byPos = a.start.compareTo(b.start);
      return byPos != 0 ? byPos : a.severity.index.compareTo(b.severity.index);
    });
    return LintReport(diagnostics: out, profile: profile, language: langLabel);
  }

  /// 把一批可自动修复的诊断写回文本。
  static String applyFixes(String source, Iterable<LintDiagnostic> diagnostics) {
    final fixes = diagnostics.where((d) => d.fixable).toList()
      ..sort((a, b) => b.start.compareTo(a.start));
    var out = source;
    var guard = -1;
    for (final d in fixes) {
      final end = d.start + d.length;
      if (end > out.length) continue;
      if (guard >= 0 && end > guard) continue;
      out = out.replaceRange(d.start, end, d.replacement!);
      guard = d.start;
    }
    return out;
  }

  /// 增量检查：只在「纯追加」且文本已经很大时启用，其余走全量。
  ///
  /// 编辑器里最常见的改动是「在末尾继续打字」，而大文件全量重扫会越来越慢。
  /// 这里保留旧诊断里未受影响的部分，只对新增片段再做一次检查；
  /// 跨行的结论（括号未闭合、标签未闭合、块未闭合、JSON/XML 整体解析）
  /// 在追加后可能失效，一律丢弃重算。
  static LintReport checkIncremental({
    required String previous,
    required LintReport previousReport,
    required String current,
    required String langLabel,
    String? langKey,
    bool chinese = true,
    Set<String> disabledRules = const <String>{},
    int? editingLine,
  }) {
    LintReport full() => check(current,
        langLabel: langLabel,
        langKey: langKey,
        chinese: chinese,
        disabledRules: disabledRules,
        editingLine: editingLine);
    if (previous.length < 32768 ||
        current.length < previous.length ||
        !current.startsWith(previous)) {
      return full();
    }
    // 只在「整篇结构」上才有意义的诊断：增量片段单独看必然报（缺右括号、标签没闭合、
    // JSON 解析不了…），所以这些一律交给全量检查，增量里直接丢弃。
    const volatile = <String>{
      'unclosed-bracket', 'unclosed-string', 'markup', 'json-header', 'jsonc', //
      'tag-unclosed', 'tag-unmatched', 'tag-mismatch', 'extra-bracket',
      'block-unclosed', 'fence-unclosed',
    };
    // 回退到**行首**再做增量。
    //
    // 直接 `substring(previous.length)` 几乎总是从某一行的中间切开的（上一版末尾
    // 通常不是换行），而检查器是按「完整文档」写的：从半行开始会让缩进判断失去参照、
    // 第一行的列号也对不上。对齐到行首后，被重算的那一行正好是「用户正在打的那行」，
    // 前半部分的旧诊断丢弃，交给新结果统一给出。
    var boundary = previous.lastIndexOf('\n');
    boundary = boundary < 0 ? 0 : boundary + 1;
    final delta = current.substring(boundary);
    final tail = check(delta,
        langLabel: langLabel,
        langKey: langKey,
        chinese: chinese,
        disabledRules: disabledRules);
    final startLine = _lineNoOf(current, boundary);

    final merged = <LintDiagnostic>[];
    for (final d in previousReport.diagnostics) {
      // 起点在重算区间内，或跨过边界的诊断，一律丢弃（会被下面重新算出来）。
      if (d.start >= boundary || d.start + d.length > boundary) continue;
      if (volatile.contains(d.code)) continue;
      merged.add(d);
    }
    for (final d in tail.diagnostics) {
      if (volatile.contains(d.code)) continue;
      final offset = d.start + boundary;
      final line = startLine + d.line - 1;
      merged.add(LintDiagnostic(
        line: line,
        column: d.column,
        start: offset,
        length: d.length,
        severity: d.severity,
        code: d.code,
        message: d.message,
        suggestion: d.suggestion,
        replacement: d.replacement != null ? d.replacement : null,
      ));
    }
    if (editingLine != null) {
      merged.removeWhere((d) => d.line == editingLine && incompleteCodes.contains(d.code));
    }
    merged.sort((a, b) {
      final byPos = a.start.compareTo(b.start);
      return byPos != 0 ? byPos : a.severity.index.compareTo(b.severity.index);
    });
    return LintReport(diagnostics: merged, profile: profileOf(langLabel, langKey), language: langLabel);
  }

  static int _lineNoOf(String src, int offset) {
    var line = 1;
    final limit = offset < src.length ? offset : src.length;
    for (var i = 0; i < limit; i++) {
      if (src.codeUnitAt(i) == _lf) line++;
    }
    return line;
  }

  // ------------------------------ JSON / XML ------------------------------

  static void _checkJson(String src, _Ctx ctx, _Add add) {
    try {
      jsonDecode(src);
      return;
    } on FormatException catch (e) {
      final offset = (e.offset ?? 0).clamp(0, src.length);
      // JSONC（带注释 / 尾逗号）：很多配置文件长这样，当硬错误会误报。
      // 去掉注释与尾逗号还能解析，就只提示「严格的 JSON 解析器会拒绝」。
      if (_parsesAsJsonc(src)) {
        add(offset, 1, LintSeverity.info, 'jsonc', ctx.t('这是 JSONC（含注释或尾逗号），严格 JSON 解析器会拒绝', 'JSONC (comments/trailing comma) - strict JSON parsers reject this'));
        return;
      }
      add(offset, 1, LintSeverity.error, 'json-header', 'JSON: ${e.message}',
          suggestion: ctx.t('检查该位置附近的引号、逗号与括号', 'check quotes, commas and brackets near here'));
    }
  }

  static bool _parsesAsJsonc(String src) {
    try {
      // 去掉行注释 / 块注释 / 尾逗号
      var text = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
      // 注意：replaceAll 不支持 $1 分组引用，必须用 replaceAllMapped。
      text = text.replaceAllMapped(RegExp(r'(^|[\s\[,])//[^\n]*'), (m) => m.group(1) ?? '');
      text = text.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');
      jsonDecode(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  static void _checkMarkup(String src, _Ctx ctx, _Add add) {
    try {
      XmlDocument.parse(src);
    } catch (e) {
      add(0, 0, LintSeverity.error, 'markup', 'XML: ${e.toString()}',
          suggestion: ctx.t('检查标签是否成对闭合', 'check that every tag is closed'));
    }
  }

  // ------------------------------ 词法扫描 ------------------------------

  static const int _lf = 10;
  static const int _quote = 0x22;
  static const int _apos = 0x27;
  static const int _backslash = 0x5c;

  static bool _isIdStart(int c) =>
      c == 0x24 || c == 0x5f || (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a) || c > 0x7f;

  static bool _isIdPart(int c) => _isIdStart(c) || (c >= 0x30 && c <= 0x39);

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static void _scanAndCheck(
    String src,
    LintProfile p,
    String langLabel,
    String? langKey,
    _Ctx ctx,
    _Add add,
  ) {
    final n = src.length;
    final units = src.codeUnits.toList();
    final idents = <_Ident>[];
    final stack = <_Open>[];
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
        // JS 正则字面量：/ 出现在运算符、括号、逗号之后时是正则，不是除号或注释。
        // 不处理会把 /abc/ 里的 // 当成行注释，整行后面的代码全被「吃掉」。
        if (p.jsRegex && _looksLikeRegexStart(src, i)) {
          final end = _skipRegexLiteral(src, i);
          if (end > i) {
            i = end;
            continue;
          }
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
        // 例外：CSS 的 #id（css 家族本就不开 hashComment）、Rust 的 #[attr]（族是 c）
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

      // C# 逐字字符串 @"..."：内部只有 "" 表示一个引号，反斜杠不转义。
      if (p.atVerbatim && c == 0x40 && i + 1 < n && src.codeUnitAt(i + 1) == _quote) {
        final start = i;
        i += 2;
        var closed = false;
        while (i < n) {
          if (src.codeUnitAt(i) == _quote) {
            if (i + 1 < n && src.codeUnitAt(i + 1) == _quote) {
              i += 2;
              continue;
            }
            i++;
            closed = true;
            break;
          }
          i++;
        }
        if (!closed) {
          add(start, 2, LintSeverity.error, 'unclosed-string', ctx.t('逐字字符串未闭合', 'unterminated verbatim string'),
              suggestion: ctx.t('补上结尾的引号', 'add the closing quote'));
        }
        continue;
      }

      // 字符串
      if (c == _quote || c == _apos) {
        // Rust 生命周期：'a、'static —— 不是字符串。
        if (p.rustApostrophe && c == _apos && i + 1 < n && _isIdStart(src.codeUnitAt(i + 1))) {
          final next = i + 2 < n ? src.codeUnitAt(i + 2) : 32;
          if (next != _apos) {
            i++;
            continue;
          }
        }
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
            add(start, 3, LintSeverity.error, 'unclosed-string', ctx.t('三引号字符串未闭合', 'unterminated triple-quoted string'),
                suggestion: ctx.t('补上结尾的三引号', 'add the closing triple quote'));
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
            if (p.sqlComment && i + 1 < n && src.codeUnitAt(i + 1) == c) {
              i += 2;
              continue;
            }
            i++;
            closed = true;
            break;
          }
          if (ch == _lf) break;
          i++;
        }
        if (!closed) {
          add(start, 1, LintSeverity.error, 'unclosed-string', ctx.t('字符串未闭合', 'unterminated string'),
              suggestion: ctx.t('这一行的引号没有配对，检查是否漏了结尾引号', 'the quote is not paired - check the closing quote'));
        }
        continue;
      }

      // 全角标点混进代码（中文输入法最容易踩的坑，扫描时才知道在不在字符串里）
      final fullWidth = _fullWidthOf(c);
      if (fullWidth != null) {
        add(
            i,
            1,
            LintSeverity.warning,
            'full-width',
            ctx.t('代码里混入了全角符号「$fullWidth」', 'full-width character "$fullWidth" in code'),
            suggestion: ctx.t('换成半角符号', 'use the ASCII version'));
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

      if (_isDigit(c)) {
        i++;
        // 只吃 ASCII 字母数字（0x1F、1e3、1_000）：不能用 _isIdPart，
        // 它把 >0x7f 也算进去，中文输入法的全角标点会被当成数字尾巴吃掉。
        while (i < n) {
          final ch = src.codeUnitAt(i);
          final ascii =
              (ch >= 0x30 && ch <= 0x39) || (ch >= 0x61 && ch <= 0x7a) || (ch >= 0x41 && ch <= 0x5a) || ch == 0x5f;
          if (ascii || ch == 0x2e) {
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
          add(i, 1, LintSeverity.error, 'extra-bracket',
              ctx.t('多余的 ${String.fromCharCode(c)}：前面没有对应的开括号', 'extra ${String.fromCharCode(c)}: no matching opener'),
              suggestion: ctx.t('删掉这个括号', 'delete it'), replacement: '');
        } else {
          final open = stack.removeLast();
          final want = open.ch == 0x7b
              ? 0x7d
              : open.ch == 0x28
                  ? 0x29
                  : 0x5d;
          if (c != want) {
            add(
                i,
                1,
                LintSeverity.error,
                'bracket-mismatch',
                ctx.t(
                    '括号不匹配：这里应该是 ${String.fromCharCode(want)}（对应第 ${_lineOfOffset(src, open.at)} 行的 ${String.fromCharCode(open.ch)}）',
                    'mismatched bracket: expected ${String.fromCharCode(want)} for the ${String.fromCharCode(open.ch)} on line ${_lineOfOffset(src, open.at)}'));
          }
        }
        i++;
        continue;
      }

      i++;
    }

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
        ctx.t('有 ${stack.length} 个括号没有闭合（最后一个在第 ${_lineOfOffset(src, stack.last.at)} 行）',
            '${stack.length} unclosed bracket(s), last one on line ${_lineOfOffset(src, stack.last.at)}'),
        suggestion: ctx.t('在末尾补上 $tail', 'append $tail'),
        replacement: tail.toString(),
      );
    }

    if (p.semicolons) _checkSemicolons(src, String.fromCharCodes(units), lineTops, lineDeltas, ctx, add);
    if (p.caseSensitive) _checkCase(src, idents, langLabel, langKey, ctx, add);
    if (p.indented) _checkIndent(src, p.blockIndent, ctx, add);
    if (p.semicolons || p.slashComment) _checkAssignmentCondition(src, langLabel, ctx, add);
    if (p.cssDecls) _checkCssDecls(src, ctx, add);
    if (p.iniLike) _checkIni(src, ctx, add);
    if (p.yamlLike) _checkYaml(src, ctx, add);
    if (p.makefileLike) _checkMakefile(src, ctx, add);
    _checkBlockPairs(src, String.fromCharCodes(units), p.key, ctx, add);
  }

  /// `/` 之前是「值」结束的字符时才是除法，否则是正则字面量起始。
  static bool _looksLikeRegexStart(String src, int slashIndex) {
    var k = slashIndex - 1;
    while (k >= 0) {
      final c = src[k];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        k--;
        continue;
      }
      return '(,=:[!&|?{};+-*%~^<>'.contains(c);
    }
    return true;
  }

  /// 从 `/` 开始跳过一个正则字面量，返回结束位置（含标志位）；失败返回 -1。
  static int _skipRegexLiteral(String src, int start) {
    var i = start + 1;
    var inClass = false;
    while (i < src.length) {
      final c = src[i];
      if (c == '\\') {
        i += 2;
        continue;
      }
      if (c == '\n') return -1;
      if (c == '[') inClass = true;
      if (c == ']') inClass = false;
      if (c == '/' && !inClass) {
        i++;
        while (i < src.length && RegExp(r'[a-z]').hasMatch(src[i])) {
          i++;
        }
        return i;
      }
      i++;
    }
    return -1;
  }

  // ------------------------------ 分号 ------------------------------

  static void _checkSemicolons(
    String src,
    String masked,
    List<int> lineTops,
    List<int> lineDeltas,
    _Ctx ctx,
    _Add add,
  ) {
    final rawLines = src.split('\n');
    final maskLines = masked.split('\n');
    var offset = 0;
    // 这些行首是「块头 / 预处理 / 标签 / 修饰符」，本来就不该有分号。
    // 只有「块头 / 预处理 / 标签 / 注释」才不需要分号。
    // return / throw / yield / static / using / import 这些后面照样要分号，
    // 列进来会把真错误放过去（漏报比误报更难发现）。
    const skipHeads = <String>[
      'case ', 'default', 'else', 'do', 'try', 'finally', 'catch', 'template', //
      '@', '#', 'public:', 'private:', 'protected:', 'internal:', '//', '/*', '*', '}',
    ];

    for (var line = 0; line < maskLines.length && line < rawLines.length; line++) {
      final mask = maskLines[line];
      final lineStart = offset;
      offset += rawLines[line].length + 1;

      final trimmedRight = _trimRight(mask);
      if (trimmedRight.isEmpty) continue;
      if (mask.trim().isEmpty) continue;

      // 语句跨行：本行有没闭合的开括号，或行首就处在 ( / [ 里面。
      // 不能只看「栈深 > 0」——函数体的 { 一直开着，那样会把整个函数体都跳过。
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
      // 单独的 `}` / `};` 之后的行首，或者行首是 `label:` 形式
      if (RegExp(r'^[\w$]+\s*:\s*$').hasMatch(head)) continue;

      final lastChar = trimmedRight[trimmedRight.length - 1];
      if (';{}),]:'.contains(lastChar)) continue;
      if ('+-*/%&|^<>=,:?([.~!'.contains(lastChar)) continue;

      // 下一行以 { 或 : 开头 → 本行是块头 / 构造初始化列表
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
      if (head.startsWith('.') || head.startsWith('?') || head.startsWith(')') || head.startsWith(']')) {
        continue;
      }

      add(
        lineStart + trimmedRight.length,
        0,
        LintSeverity.warning,
        'missing-semicolon',
        ctx.t('这行可能缺少分号', 'missing semicolon'),
        suggestion: ctx.t('补上 ;', 'add ;'),
        replacement: ';',
      );
    }
  }

  // ------------------------------ 大小写 ------------------------------

  static void _checkCase(
    String src,
    List<_Ident> idents,
    String langLabel,
    String? langKey,
    _Ctx ctx,
    _Add add,
  ) {
    if (idents.isEmpty) return;
    final known = _knownWords(langLabel, langKey);
    if (known.isEmpty) return;

    final declared = <String>{};
    for (final m in RegExp(
            r'\b(?:class|interface|struct|enum|namespace|function|func|def|var|let|const|val|record|macro|type)\s+([A-Za-z_$][\w$]*)')
        .allMatches(src)) {
      declared.add(m.group(1)!);
    }

    final counts = <String, int>{};
    for (final id in idents) {
      counts[id.text] = (counts[id.text] ?? 0) + 1;
    }
    // 一个词如果写错了一次、后面又写对过，说明用户知道正确写法，不必提示。
    final seen = <String>{};
    var emitted = 0;
    for (final id in idents) {
      if (emitted >= 12) break;
      final text = id.text;
      if (text.length < 3) continue;
      if (declared.contains(text)) continue;
      if (seen.contains(text)) continue;
      final canonical = known[text.toLowerCase()];
      if (canonical == null || canonical == text) continue;
      if ((counts[canonical] ?? 0) > 0) continue;
      seen.add(text);
      emitted++;
      add(
        id.start,
        text.length,
        LintSeverity.info,
        'case-mismatch',
        ctx.t('「$text」大小写可能写错了，该语言里写作「$canonical」',
            '"$text" may be misspelled - it is written "$canonical" in this language'),
        suggestion: ctx.t('改成 $canonical', 'change to $canonical'),
        replacement: canonical,
      );
    }
  }

  // ------------------------------ 缩进 ------------------------------

  static void _checkIndent(String src, bool blockIndent, _Ctx ctx, _Add add) {
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
        add(lineStart, indent, LintSeverity.warning, 'mixed-indent',
            ctx.t('这一行同时用了空格和制表符缩进', 'this line mixes spaces and tabs'),
            suggestion: ctx.t('统一改成空格（该语言对缩进敏感）', 'use spaces only'));
      }

      if (blockIndent && prevTrimmed.endsWith(':') && !prevTrimmed.startsWith('#')) {
        if (indent <= prevIndent) {
          final newIndent = ' ' * (prevIndent + 4);
          add(lineStart, indent, LintSeverity.warning, 'block-indent',
              ctx.t('上一行以「:」结尾，这一行应该缩进一层', 'previous line ends with ":" - this line should be indented'),
              suggestion: ctx.t('再缩进 4 个空格', 'indent by 4 spaces'), replacement: newIndent + trimmed);
        }
      }

      prevIndent = indent;
      prevTrimmed = _trimRight(raw);
    }
  }

  // ------------------------------ 条件里赋值 ------------------------------

  static void _checkAssignmentCondition(String src, String langLabel, _Ctx ctx, _Add add) {
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
      // C++/C# 的 if (auto p = f()) / if (var x = ...) 是合法的初始化语句。
      if (RegExp(r'^\s*(auto|const|var|let|int|long|float|double|char|bool|bool\?|[A-Z][\w<>?]*)\s+[\w$]+\s*=')
          .hasMatch(inner)) {
        continue;
      }
      for (var k = 0; k < inner.length; k++) {
        if (inner[k] != '=') continue;
        final prev = k > 0 ? inner[k - 1] : '';
        final next = k + 1 < inner.length ? inner[k + 1] : '';
        if (next == '=' || prev == '=' || prev == '!' || prev == '<' || prev == '>' || prev == ':' || prev == '~') {
          continue;
        }
        if (next == '>') continue;
        add(
          start + k,
          1,
          LintSeverity.warning,
          'assign-in-condition',
          ctx.t('条件里用了赋值「=」，是不是想写「==」？', 'assignment "=" inside a condition - did you mean "=="?'),
          suggestion: ctx.t('如果不是故意赋值，改成 ==', 'use == unless the assignment is intended'),
        );
        break;
      }
    }
  }

  // ------------------------------ 块关键字配对（非大括号语言） ------------------------------

  static void _checkBlockPairs(String src, String masked, String key, _Ctx ctx, _Add add) {
    final rules = _pairRules[key];
    if (rules == null || rules.isEmpty) return;
    final lines = masked.split('\n');
    final opens = List<int>.filled(rules.length, 0);
    final closes = List<int>.filled(rules.length, 0);
    final lastLine = List<int>.filled(rules.length, -1);

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      for (var r = 0; r < rules.length; r++) {
        final rule = rules[r];
        final hasOpen = rule.open.hasMatch(line);
        final closeCount = rule.close.allMatches(line).length;
        // 同一行里既开又关（`if ...; fi` / `begin x end`）：自平衡，不计。
        if (hasOpen && closeCount > 0) {
          lastLine[r] = i;
          continue;
        }
        if (hasOpen) opens[r]++;
        if (closeCount > 0) closes[r] += closeCount;
        if (hasOpen || closeCount > 0) lastLine[r] = i;
      }
    }

    for (var r = 0; r < rules.length; r++) {
      final diff = opens[r] - closes[r];
      if (diff == 0) continue;
      final rule = rules[r];
      final at = _offsetOfLine(src, lastLine[r] < 0 ? lines.length - 1 : lastLine[r]);
      if (diff > 0) {
        add(
          at,
          0,
          LintSeverity.warning,
          'block-unclosed',
          ctx.t('${rule.name} 少了 ${diff} 个「${rule.closeName}」', '${rule.name} is missing $diff "${rule.closeName}"'),
          suggestion: ctx.t('检查是不是有块没有闭合', 'check for an unclosed block'),
        );
      } else {
        add(
          at,
          0,
          LintSeverity.warning,
          'block-extra',
          ctx.t('多出 ${-diff} 个「${rule.closeName}」，没有对应的「${rule.openName}」',
              '${-diff} extra "${rule.closeName}" without a matching "${rule.openName}"'),
          suggestion: ctx.t('删掉多余的收尾关键字', 'remove the extra terminator'),
        );
      }
    }
  }

  // ------------------------------ HTML 标签配平 ------------------------------

  static const Set<String> _voidTags = <String>{
    'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', //
    'param', 'source', 'track', 'wbr', '!doctype',
  };

  static void _checkHtmlTags(String src, _Ctx ctx, _Add add) {
    // script / style 里的 `<` 不是标签，先整体挖掉（长度用空格补齐以保留偏移）。
    var text = src;
    for (final tag in <String>['script', 'style']) {
      text = text.replaceAllMapped(
        RegExp('<$tag\\b[^>]*>[\\s\\S]*?</$tag\\s*>', caseSensitive: false),
        (m) => ' ' * m.group(0)!.length,
      );
    }

    final re = RegExp(
        "<!--[\\s\\S]*?-->|<![^>]*>|<\\?[^>]*\\?>|<\\/?([a-zA-Z][\\w:-]*)((?:\\\"[^\\\"]*\\\"|'[^']*'|[^>\\\"'])*)>");
    final stack = <(String, int)>[];
    for (final m in re.allMatches(text)) {
      final raw = m.group(0)!;
      if (raw.startsWith('<!--') || raw.startsWith('<!') || raw.startsWith('<?')) continue;
      final name = (m.group(1) ?? '').toLowerCase();
      if (name.isEmpty) continue;
      final selfClose = raw.endsWith('/>') || _voidTags.contains(name);
      final isClose = raw.startsWith('</');
      if (isClose) {
        if (stack.isEmpty) {
          add(m.start, raw.length, LintSeverity.error, 'tag-unmatched',
              ctx.t('多余的 </$name>：前面没有对应的开标签', 'extra </$name>: no matching open tag'));
          continue;
        }
        final (openName, openAt) = stack.removeLast();
        if (openName != name) {
          add(
              m.start,
              raw.length,
              LintSeverity.error,
              'tag-mismatch',
              ctx.t('标签不匹配：<$openName>（第 ${_lineOfOffset(src, openAt)} 行）被 </$name> 关闭',
                  'tag mismatch: <$openName> (line ${_lineOfOffset(src, openAt)}) closed by </$name>'));
        }
      } else if (!selfClose) {
        stack.add((name, m.start));
      }
    }
    if (stack.isNotEmpty) {
      final (name, at) = stack.last;
      add(
        src.length,
        0,
        LintSeverity.error,
        'tag-unclosed',
        ctx.t('有 ${stack.length} 个标签没有闭合（最后一个 <$name> 在第 ${_lineOfOffset(src, at)} 行）',
            '${stack.length} unclosed tag(s), last one <$name> on line ${_lineOfOffset(src, at)}'),
        suggestion: ctx.t('补上 </$name>', 'append </$name>'),
      );
    }
  }

  // ------------------------------ Markdown 围栏 ------------------------------

  static void _checkFences(String src, _Ctx ctx, _Add add) {
    final lines = src.split('\n');
    var offset = 0;
    var backticks = 0;
    var tildes = 0;
    var lastBacktickOffset = 0;
    var lastTildeOffset = 0;
    for (final line in lines) {
      final head = line.trimLeft();
      if (head.startsWith('```')) {
        backticks++;
        lastBacktickOffset = offset;
      } else if (head.startsWith('~~~')) {
        tildes++;
        lastTildeOffset = offset;
      }
      offset += line.length + 1;
    }
    if (backticks.isOdd) {
      add(lastBacktickOffset, 3, LintSeverity.warning, 'fence-unclosed',
          ctx.t('代码块围栏 ``` 没有闭合', 'code fence ``` is not closed'),
          suggestion: ctx.t('在文末补一行 ```', 'add a closing ``` line'));
    }
    if (tildes.isOdd) {
      add(lastTildeOffset, 3, LintSeverity.warning, 'fence-unclosed',
          ctx.t('代码块围栏 ~~~ 没有闭合', 'code fence ~~~ is not closed'),
          suggestion: ctx.t('在文末补一行 ~~~', 'add a closing ~~~ line'));
    }
  }

  // ------------------------------ ini / properties ------------------------------

  static void _checkIni(String src, _Ctx ctx, _Add add) {
    final lines = src.split('\n');
    var offset = 0;
    final seen = <String>{};
    String? section;
    for (final line in lines) {
      final lineStart = offset;
      offset += line.length + 1;
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith(';')) continue;
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        section = trimmed;
        seen.clear();
        continue;
      }
      // properties / ini 支持行尾反斜杠续行
      if (trimmed.endsWith('\\')) continue;
      final eq = trimmed.indexOf('=');
      final colon = trimmed.indexOf(':');
      final sep = eq >= 0 ? eq : colon;
      if (sep <= 0) {
        add(lineStart, line.length, LintSeverity.warning, 'ini-line',
            ctx.t('这一行既不是 [section] 也不是 key = value', 'not a [section] and not key = value'),
            suggestion: ctx.t('补上 = 与值，或改成注释', 'add "= value" or make it a comment'));
        continue;
      }
      final name = trimmed.substring(0, sep).trim().toLowerCase();
      if (!seen.add(name)) {
        add(lineStart, sep, LintSeverity.info, 'ini-duplicate',
            ctx.t('「${trimmed.substring(0, sep).trim()}」在 ${section ?? '全局'} 段里重复出现',
                'duplicate key "${trimmed.substring(0, sep).trim()}" in ${section ?? 'global'}'));
      }
    }
  }

  // ------------------------------ YAML ------------------------------

  static void _checkYaml(String src, _Ctx ctx, _Add add) {
    final lines = src.split('\n');
    var offset = 0;
    for (final line in lines) {
      final lineStart = offset;
      offset += line.length + 1;
      final trimmed = line.trimLeft();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      if (line.startsWith('\t')) {
        add(lineStart, 1, LintSeverity.error, 'yaml-tab',
            ctx.t('YAML 不允许用 tab 缩进', 'YAML does not allow tab indentation'),
            suggestion: ctx.t('换成空格', 'use spaces'));
      }
    }
  }

  // ------------------------------ Makefile ------------------------------

  static void _checkMakefile(String src, _Ctx ctx, _Add add) {
    final lines = src.split('\n');
    var offset = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineStart = offset;
      offset += line.length + 1;
      if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
      if (line.startsWith('\t')) continue;
      // 上一行是 target（含冒号、不以 tab 开头）而本行用空格缩进 → 命令行的 tab 被编辑器换成了空格
      if (line.startsWith('  ') && i > 0) {
        final prev = lines[i - 1].trimRight();
        if (prev.contains(':') && !prev.startsWith('\t') && !prev.endsWith('\\')) {
          add(lineStart, line.length - line.trimLeft().length, LintSeverity.error, 'makefile-tab',
              ctx.t('Makefile 的命令行必须以 tab 开头', 'Makefile recipe lines must start with a tab'),
              suggestion: ctx.t('把行首缩进换成 tab', 'replace the indentation with a tab'));
        }
      }
    }
  }

  // ------------------------------ CSS 声明 ------------------------------

  static void _checkCssDecls(String src, _Ctx ctx, _Add add) {
    final lines = src.split('\n');
    var offset = 0;
    var depth = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineStart = offset;
      offset += line.length + 1;
      for (final ch in line.split('')) {
        if (ch == '{') depth++;
        if (ch == '}') depth = depth > 0 ? depth - 1 : 0;
      }
      final trimmed = _trimRight(line).trim();
      if (trimmed.isEmpty || depth == 0) continue;
      if (trimmed.startsWith('//') || trimmed.startsWith('/*') || trimmed.startsWith('*')) continue;
      if (trimmed.startsWith('@')) continue;
      final last = trimmed[trimmed.length - 1];
      if (';{},'.contains(last)) continue;
      if (!trimmed.contains(':')) continue;
      // 值跨行（下一行缩进更深或本行以 ( , [ 结尾）→ 不判
      var nextHead = '';
      for (var k = i + 1; k < lines.length; k++) {
        final t = lines[k].trim();
        if (t.isEmpty) continue;
        nextHead = t;
        break;
      }
      if (nextHead.startsWith('}') || nextHead.startsWith(')')) continue;
      add(
        lineStart + _trimRight(line).length,
        0,
        LintSeverity.warning,
        'css-semicolon',
        ctx.t('这条声明可能缺少分号', 'missing semicolon after this declaration'),
        suggestion: ctx.t('补上 ;', 'add ;'),
        replacement: ';',
      );
    }
  }

  // ------------------------------ 已知词（大小写纠错用） ------------------------------

  static final Map<String, Map<String, String>> _knownCache = <String, Map<String, String>>{};

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

  static String? _fullWidthOf(int c) {
    switch (c) {
      case 0xFF1B:
        return '；';
      case 0xFF0C:
        return '，';
      case 0xFF08:
        return '（';
      case 0xFF09:
        return '）';
      case 0xFF1D:
        return '＝';
      case 0x201C:
        return '“';
      case 0x201D:
        return '”';
      case 0x2018:
        return '‘';
      case 0x2019:
        return '’';
      case 0xFF5B:
        return '｛';
      case 0xFF5D:
        return '｝';
      case 0xFF05:
        return '％';
      case 0xFF1A:
        return '：';
      case 0x3002:
        return '。';
      case 0xFF01:
        return '！';
    }
    return null;
  }

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

  static int _offsetOfLine(String src, int line) {
    if (line <= 0) return 0;
    var count = 0;
    for (var i = 0; i < src.length; i++) {
      if (src.codeUnitAt(i) == _lf) {
        count++;
        if (count == line) return i + 1;
      }
    }
    return src.length;
  }

  static int _lineOfOffset(String src, int offset) {
    var line = 1;
    final limit = offset < src.length ? offset : src.length;
    for (var i = 0; i < limit; i++) {
      if (src.codeUnitAt(i) == _lf) line++;
    }
    return line;
  }

  /// 非大括号语言的「块关键字配对」表。
  ///
  /// 只统计**行首**的开关键字（Ruby 的 `x = 1 if y` 这种修饰语不算），
  /// 且同一行里既开又关（`if ...; fi`）的跳过，避免误报。
  static final Map<String, List<_PairRule>> _pairRules = <String, List<_PairRule>>{
    'bash': <_PairRule>[
      _PairRule(RegExp(r'^\s*if\b'), RegExp(r'\bfi\b'), 'if … fi', 'if', 'fi'),
      _PairRule(RegExp(r'^\s*case\b'), RegExp(r'\besac\b'), 'case … esac', 'case', 'esac'),
      _PairRule(RegExp(r'^\s*(for|while|until|select)\b'), RegExp(r'\bdone\b'), '循环 … done', '循环', 'done'),
    ],
    'sh': <_PairRule>[
      _PairRule(RegExp(r'^\s*if\b'), RegExp(r'\bfi\b'), 'if … fi', 'if', 'fi'),
      _PairRule(RegExp(r'^\s*case\b'), RegExp(r'\besac\b'), 'case … esac', 'case', 'esac'),
      _PairRule(RegExp(r'^\s*(for|while|until|select)\b'), RegExp(r'\bdone\b'), '循环 … done', '循环', 'done'),
    ],
    'zsh': <_PairRule>[
      _PairRule(RegExp(r'^\s*if\b'), RegExp(r'\bfi\b'), 'if … fi', 'if', 'fi'),
      _PairRule(RegExp(r'^\s*case\b'), RegExp(r'\besac\b'), 'case … esac', 'case', 'esac'),
      _PairRule(RegExp(r'^\s*(for|while|until|select)\b'), RegExp(r'\bdone\b'), '循环 … done', '循环', 'done'),
    ],
    'lua': <_PairRule>[
      _PairRule(RegExp(r'^\s*(if|for|while|function)\b'), RegExp(r'^\s*end\b'), 'block … end', 'block', 'end'),
      _PairRule(RegExp(r'^\s*repeat\b'), RegExp(r'^\s*until\b'), 'repeat … until', 'repeat', 'until'),
    ],
    'ruby': <_PairRule>[
      _PairRule(
          RegExp(r'^\s*(if|unless|case|begin|while|until|for|def|class|module|do)\b'),
          RegExp(r'^\s*end\b'),
          'block … end',
          'block',
          'end'),
    ],
    'crystal': <_PairRule>[
      _PairRule(RegExp(r'^\s*(if|unless|case|def|class|module|while|until|begin)\b'), RegExp(r'^\s*end\b'),
          'block … end', 'block', 'end'),
    ],
    'elixir': <_PairRule>[
      _PairRule(RegExp(r'^\s*(def|defp|defmodule|if|unless|case|cond|with|for|try|receive)\b'),
          RegExp(r'^\s*end\b'), 'block … end', 'block', 'end'),
    ],
    'matlab': <_PairRule>[
      _PairRule(RegExp(r'^\s*(if|for|parfor|while|switch|function|try)\b'), RegExp(r'^\s*end\b'), 'block … end',
          'block', 'end'),
    ],
    'octave': <_PairRule>[
      _PairRule(RegExp(r'^\s*(if|for|while|switch|function|try)\b'), RegExp(r'^\s*end\b'), 'block … end',
          'block', 'end'),
    ],
    'pascal': <_PairRule>[
      _PairRule(RegExp(r'^\s*begin\b', caseSensitive: false), RegExp(r'^\s*end\b', caseSensitive: false),
          'begin … end', 'begin', 'end'),
    ],
    'delphi': <_PairRule>[
      _PairRule(RegExp(r'^\s*begin\b', caseSensitive: false), RegExp(r'^\s*end\b', caseSensitive: false),
          'begin … end', 'begin', 'end'),
    ],
    'vb': <_PairRule>[
      _PairRule(
          RegExp(r'^\s*(public |private |protected |friend |shared )*(sub|function|class|module|property)\b',
              caseSensitive: false),
          RegExp(r'^\s*end\s+(sub|function|class|module|property)\b', caseSensitive: false),
          'Sub/Function … End Sub',
          'Sub/Function',
          'End Sub'),
    ],
    'vbnet': <_PairRule>[
      _PairRule(
          RegExp(r'^\s*(public |private |protected |friend |shared )*(sub|function|class|module|property)\b',
              caseSensitive: false),
          RegExp(r'^\s*end\s+(sub|function|class|module|property)\b', caseSensitive: false),
          'Sub/Function … End Sub',
          'Sub/Function',
          'End Sub'),
    ],
    'fortran': <_PairRule>[
      _PairRule(RegExp(r'^\s*do\b', caseSensitive: false), RegExp(r'^\s*end\s*do\b', caseSensitive: false),
          'do … end do', 'do', 'end do'),
      _PairRule(RegExp(r'^\s*if\b.*\bthen\b', caseSensitive: false), RegExp(r'^\s*end\s*if\b', caseSensitive: false),
          'if … end if', 'if', 'end if'),
      // 只认「单独一行的 end」，否则 end do / end if 会被重复计数
      _PairRule(RegExp(r'^\s*(subroutine|function)\b', caseSensitive: false),
          RegExp(r'^\s*end\s*$', caseSensitive: false), 'function … end', 'subroutine/function', 'end'),
    ],
    'ada': <_PairRule>[
      _PairRule(RegExp(r'^\s*begin\b', caseSensitive: false), RegExp(r'^\s*end\b', caseSensitive: false),
          'begin … end', 'begin', 'end'),
    ],
  };
}

class _PairRule {
  final RegExp open;
  final RegExp close;

  /// 人类可读的名字，例如 `if … fi`。
  final String name;
  final String openName;
  final String closeName;

  const _PairRule(this.open, this.close, this.name, this.openName, this.closeName);
}

/// 双语消息。
class _Ctx {
  final bool chinese;
  const _Ctx(this.chinese);

  String t(String zh, String en) => chinese ? zh : en;
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

/// 一条可开关的检查规则。
class LintRule {
  final String code;
  final String nameZh;
  final String nameEn;

  const LintRule(this.code, this.nameZh, this.nameEn);
}

/// 全部规则清单（设置面板按这个列出开关）。
class LintRules {
  static const List<LintRule> all = <LintRule>[
    LintRule('unclosed-string', '字符串 / 块注释未闭合', 'Unterminated string or comment'),
    LintRule('unclosed-bracket', '括号未闭合', 'Unclosed bracket'),
    LintRule('extra-bracket', '多余的括号', 'Extra bracket'),
    LintRule('bracket-mismatch', '括号类型不匹配', 'Mismatched bracket'),
    LintRule('missing-semicolon', '缺少分号', 'Missing semicolon'),
    LintRule('case-mismatch', '大小写可能写错', 'Possible casing mistake'),
    LintRule('mixed-indent', '缩进混用空格与 tab', 'Mixed spaces and tabs'),
    LintRule('block-indent', '缺少一级缩进', 'Missing indentation'),
    LintRule('assign-in-condition', '条件里用了赋值', 'Assignment inside condition'),
    LintRule('full-width', '代码里混入全角符号', 'Full-width character in code'),
    LintRule('json-header', 'JSON 语法错误', 'JSON syntax error'),
    LintRule('jsonc', 'JSONC（注释 / 尾逗号）', 'JSONC (comments / trailing comma)'),
    LintRule('markup', 'XML 语法错误', 'XML syntax error'),
    LintRule('tag-unmatched', '多余的闭合标签', 'Unmatched closing tag'),
    LintRule('tag-mismatch', '标签不匹配', 'Mismatched tag'),
    LintRule('tag-unclosed', '标签未闭合', 'Unclosed tag'),
    LintRule('fence-unclosed', '代码围栏未闭合', 'Unclosed code fence'),
    LintRule('ini-line', 'ini 行格式错误', 'Bad ini line'),
    LintRule('ini-duplicate', 'ini 重复键', 'Duplicate ini key'),
    LintRule('yaml-tab', 'YAML 用了 tab 缩进', 'YAML tab indentation'),
    LintRule('makefile-tab', 'Makefile 命令行不是 tab', 'Makefile recipe not tab-indented'),
    LintRule('css-semicolon', 'CSS 声明缺分号', 'CSS missing semicolon'),
    LintRule('block-unclosed', '代码块未闭合（if/fi、begin/end…）', 'Unclosed block (if/fi, begin/end…)'),
    LintRule('block-extra', '多余的块结尾', 'Extra block terminator'),
  ];

  static LintRule? byCode(String code) {
    for (final rule in all) {
      if (rule.code == code) return rule;
    }
    return null;
  }
}
