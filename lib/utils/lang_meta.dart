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

/// 语言族：按「注释语法 / 结构风格」把 190+ 种语言归类。
///
/// 编辑器里凡是按语言分派的能力（注释切换、格式化、关键字补全、符号条）都先
/// 归到族，再按族给出通用实现，最后才用语言专属表覆盖 —— 这样新增语言不会再
/// 掉进「什么都没有」的默认分支。
enum LangFamily {
  /// `//` + `/* … */`（C 家族）
  c,

  /// `#`
  hash,

  /// `--`
  sql,

  /// `<!-- … -->`
  xml,

  /// `;`（Lisp 家族）
  lisp,

  /// `%`
  percent,

  /// `'`
  vb,

  /// `REM` / `::`
  batch,

  /// `!`
  fortran,

  /// 没有注释语法（协议、数据格式、纯文本等）
  none,
}

/// 格式化器类型。
enum FormatKind {
  json,
  xml,
  css,
  js,

  /// 通用大括号缩进重排（只改每行前导空白，不动正文）。
  brace,
  none,
}

/// key -> 族。key 即 re_highlight 里的小写语言标识。
const Map<String, LangFamily> _familyByKey = {
  // ---- C 家族 ----
  '1c': LangFamily.c, 'actionscript': LangFamily.c, 'angelscript': LangFamily.c,
  'arcade': LangFamily.c, 'arduino': LangFamily.c, 'asciidoc': LangFamily.c,
  'aspectj': LangFamily.c, 'axapta': LangFamily.c, 'c': LangFamily.c,
  'cal': LangFamily.c, 'ceylon': LangFamily.c, 'clean': LangFamily.c,
  'coq': LangFamily.c, 'cpp': LangFamily.c, 'csp': LangFamily.c,
  'csharp': LangFamily.c, 'd': LangFamily.c, 'dart': LangFamily.c,
  'delphi': LangFamily.c, 'dts': LangFamily.c, 'dust': LangFamily.c,
  'flix': LangFamily.c, 'fsharp': LangFamily.c, 'gams': LangFamily.c,
  'glsl': LangFamily.c, 'gml': LangFamily.c, 'go': LangFamily.c,
  'golo': LangFamily.c, 'gradle': LangFamily.c, 'groovy': LangFamily.c,
  'haml': LangFamily.c, 'haxe': LangFamily.c, 'hsp': LangFamily.c,
  'isbl': LangFamily.c, 'java': LangFamily.c, 'javascript': LangFamily.c,
  'jboss-cli': LangFamily.c, 'kotlin': LangFamily.c, 'lasso': LangFamily.c,
  'leaf': LangFamily.c, 'livecodeserver': LangFamily.c, 'lsl': LangFamily.c,
  'mathematica': LangFamily.c, 'maxima': LangFamily.c, 'mel': LangFamily.c,
  'mizar': LangFamily.c, 'monkey': LangFamily.c, 'node-repl': LangFamily.c,
  'objectivec': LangFamily.c, 'ocaml': LangFamily.c, 'openscad': LangFamily.c,
  'oxygene': LangFamily.c, 'parser3': LangFamily.c, 'php': LangFamily.c,
  'pony': LangFamily.c, 'processing': LangFamily.c, 'protobuf': LangFamily.c,
  'q': LangFamily.c, 'qml': LangFamily.c, 'reasonml': LangFamily.c,
  'rsl': LangFamily.c, 'ruleslanguage': LangFamily.c, 'rust': LangFamily.c,
  'sas': LangFamily.c, 'scala': LangFamily.c, 'scilab': LangFamily.c,
  'sml': LangFamily.c, 'sqf': LangFamily.c, 'stan': LangFamily.c,
  'stata': LangFamily.c, 'step21': LangFamily.c, 'stylus': LangFamily.c,
  'swift': LangFamily.c, 'taggerscript': LangFamily.c, 'thrift': LangFamily.c,
  'tp': LangFamily.c, 'typescript': LangFamily.c, 'vala': LangFamily.c,
  'verilog': LangFamily.c, 'wren': LangFamily.c, 'xl': LangFamily.c,
  'xquery': LangFamily.c, 'zephir': LangFamily.c,
  'julia': LangFamily.hash,

  // ---- hash 家族 ----
  'apache': LangFamily.hash, 'awk': LangFamily.hash, 'bash': LangFamily.hash,
  'capnproto': LangFamily.hash, 'cmake': LangFamily.hash,
  'coffeescript': LangFamily.hash, 'crmsh': LangFamily.hash,
  'crystal': LangFamily.hash, 'dockerfile': LangFamily.hash,
  'dsconfig': LangFamily.hash, 'elixir': LangFamily.hash,
  'gherkin': LangFamily.hash, 'graphql': LangFamily.hash, 'gn': LangFamily.hash,
  'ldif': LangFamily.hash, 'livescript': LangFamily.hash,
  'makefile': LangFamily.hash, 'nestedtext': LangFamily.hash,
  'nginx': LangFamily.hash, 'nim': LangFamily.hash, 'nix': LangFamily.hash,
  'perl': LangFamily.hash, 'mojolicious': LangFamily.hash,
  'pf': LangFamily.hash, 'powershell': LangFamily.hash,
  'profile': LangFamily.hash, 'properties': LangFamily.hash,
  'puppet': LangFamily.hash, 'python': LangFamily.hash,
  'python-repl': LangFamily.hash, 'r': LangFamily.hash,
  'rib': LangFamily.hash, 'roboconf': LangFamily.hash,
  'routeros': LangFamily.hash, 'shell': LangFamily.hash,
  'smali': LangFamily.hash, 'subunit': LangFamily.hash,
  'tcl': LangFamily.hash, 'yaml': LangFamily.hash,

  // ---- sql 家族 ----
  'ada': LangFamily.sql, 'applescript': LangFamily.sql, 'elm': LangFamily.sql,
  'haskell': LangFamily.sql, 'lua': LangFamily.sql,
  'moonscript': LangFamily.sql, 'n1ql': LangFamily.sql,
  'pgsql': LangFamily.sql, 'sql': LangFamily.sql, 'vhdl': LangFamily.sql,

  // ---- xml 家族 ----
  'django': LangFamily.xml, 'erb': LangFamily.xml, 'handlebars': LangFamily.xml,
  'markdown': LangFamily.xml, 'php-template': LangFamily.xml,
  'twig': LangFamily.xml, 'vbscript-html': LangFamily.xml,
  'vue': LangFamily.xml, 'xml': LangFamily.xml,

  // ---- lisp 家族 ----
  'abnf': LangFamily.lisp, 'armasm': LangFamily.lisp,
  'autohotkey': LangFamily.lisp, 'autoit': LangFamily.lisp,
  'avrasm': LangFamily.lisp, 'clojure': LangFamily.lisp,
  'clojure-repl': LangFamily.lisp, 'cos': LangFamily.lisp,
  'dns': LangFamily.lisp, 'ebnf': LangFamily.lisp, 'gcode': LangFamily.lisp,
  'ini': LangFamily.lisp, 'lisp': LangFamily.lisp, 'llvm': LangFamily.lisp,
  'mipsasm': LangFamily.lisp, 'nsis': LangFamily.lisp,
  'purebasic': LangFamily.lisp, 'scheme': LangFamily.lisp,
  'wasm': LangFamily.lisp, 'x86asm': LangFamily.lisp,
  'hy': LangFamily.lisp,

  // ---- percent / 其它 ----
  'erlang': LangFamily.percent, 'erlang-repl': LangFamily.percent,
  'latex': LangFamily.percent, 'matlab': LangFamily.percent,
  'mercury': LangFamily.percent, 'prolog': LangFamily.percent,
  'gauss': LangFamily.percent,

  // ---- vb ----
  'basic': LangFamily.vb, 'smalltalk': LangFamily.vb, 'vbnet': LangFamily.vb,
  'vbscript': LangFamily.vb, 'vim': LangFamily.vb,

  // ---- batch / fortran ----
  'dos': LangFamily.batch, 'fortran': LangFamily.fortran,
  'irpf90': LangFamily.fortran,

  // ---- 无注释 ----
  'accesslog': LangFamily.none, 'bnf': LangFamily.none,
  'brainfuck': LangFamily.none, 'diff': LangFamily.none,
  'excel': LangFamily.none, 'fix': LangFamily.none, 'http': LangFamily.none,
  'inform7': LangFamily.none, 'json': LangFamily.none,
  'plaintext': LangFamily.none, 'tap': LangFamily.none,
  'ldifx': LangFamily.none, 'cos-repl': LangFamily.none,
};

/// 按语言名（`Mode.name` 的规范化形式）兜底识别族。
const Map<String, LangFamily> _familyByName = {
  'plaintext': LangFamily.none, 'xmlhtml': LangFamily.xml,
  'http': LangFamily.none, 'json': LangFamily.none,
  'markdown': LangFamily.xml, 'javascript': LangFamily.c,
  'typescript': LangFamily.c, 'livescript': LangFamily.hash,
  'visualbasic': LangFamily.vb, 'vbnet': LangFamily.vb,
  'intelx86assembly': LangFamily.lisp, 'x86assembly': LangFamily.lisp,
  'objectivec': LangFamily.c, 'c': LangFamily.c, 'csharp': LangFamily.c,
  '1centeprise': LangFamily.c, 'postgresql': LangFamily.sql,
  'plaintexts': LangFamily.none, 'shellsession': LangFamily.hash,
  'yaml': LangFamily.hash, 'toml': LangFamily.hash,
};

/// 规范化：小写并去掉非字母数字。
String normalizeLang(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

LangFamily _guessFamily(String normalized) {
  if (normalized.isEmpty) return LangFamily.c;
  const hashHints = ['python', 'ruby', 'perl', 'shell', 'bash', 'yaml', 'toml',
    'makefile', 'docker', 'powershell', 'cmake', 'nginx', 'ini', 'r', 'julia',
    'elixir', 'crystal', 'nim', 'coffee', 'awk', 'nix', 'graphql', 'tcl'];
  const sqlHints = ['sql', 'haskell', 'lua', 'ada', 'elm', 'vhdl'];
  const xmlHints = ['html', 'xml', 'vue', 'svg', 'handlebars', 'twig'];
  for (final h in hashHints) {
    if (normalized == h || normalized.startsWith(h)) return LangFamily.hash;
  }
  for (final h in sqlHints) {
    if (normalized.startsWith(h)) return LangFamily.sql;
  }
  for (final h in xmlHints) {
    if (normalized.contains(h)) return LangFamily.xml;
  }
  return LangFamily.c;
}

/// 取语言族。[key] 是 re_highlight 的小写标识（最准），[label] 是展示名（兜底）。
LangFamily langFamilyOf({String? key, String? label}) {
  if (key != null && key.isNotEmpty) {
    final f = _familyByKey[key];
    if (f != null) return f;
  }
  if (label != null && label.isNotEmpty) {
    final norm = normalizeLang(label);
    final f = _familyByName[norm];
    if (f != null) return f;
    return _guessFamily(norm);
  }
  return LangFamily.c;
}

/// 某个族的行注释前缀（null = 没有行注释）。
String? familyLineComment(LangFamily family) {
  switch (family) {
    case LangFamily.c:
      return '//';
    case LangFamily.hash:
      return '#';
    case LangFamily.sql:
      return '--';
    case LangFamily.lisp:
      return ';';
    case LangFamily.percent:
      return '%';
    case LangFamily.vb:
      return "'";
    case LangFamily.batch:
      return 'REM';
    case LangFamily.fortran:
      return '!';
    case LangFamily.xml:
    case LangFamily.none:
      return null;
  }
}

/// 某个族的块注释定界符（null = 没有块注释）。
(String, String)? familyBlockComment(LangFamily family) {
  switch (family) {
    case LangFamily.c:
      return ('/*', '*/');
    case LangFamily.xml:
      return ('<!--', '-->');
    case LangFamily.sql:
      // Haskell / Lua 等用 --[[ ]]；这里给最常见的 SQL 风格，保持保守。
      return null;
    case LangFamily.hash:
    case LangFamily.lisp:
    case LangFamily.percent:
    case LangFamily.vb:
    case LangFamily.batch:
    case LangFamily.fortran:
    case LangFamily.none:
      return null;
  }
}

/// 按 key / label 取行注释前缀。
String? lineCommentOf({String? key, String? label}) =>
    familyLineComment(langFamilyOf(key: key, label: label));

/// 按 key / label 取块注释定界符。
(String, String)? blockCommentOf({String? key, String? label}) =>
    familyBlockComment(langFamilyOf(key: key, label: label));

/// key -> 格式化器类型。
const Map<String, FormatKind> _formatByKey = {
  'json': FormatKind.json, 'xml': FormatKind.xml,
  'css': FormatKind.css, 'scss': FormatKind.css, 'less': FormatKind.css,
  'javascript': FormatKind.js, 'typescript': FormatKind.js,
  'vue': FormatKind.xml, 'handlebars': FormatKind.xml,
  'django': FormatKind.xml, 'twig': FormatKind.xml,
  'erb': FormatKind.xml, 'php-template': FormatKind.xml,
};

/// 按 key / label 决定用哪种格式化器。
FormatKind formatKindOf({String? key, String? label}) {
  if (key != null) {
    final k = _formatByKey[key];
    if (k != null) return k;
  }
  final family = langFamilyOf(key: key, label: label);
  final norm = normalizeLang(label ?? '');
  switch (family) {
    case LangFamily.xml:
      return FormatKind.xml;
    case LangFamily.none:
      // 数据格式里有结构的仍然可以排序/缩进。
      if (norm.contains('json')) return FormatKind.json;
      if (norm.contains('http')) return FormatKind.none;
      return FormatKind.none;
    case LangFamily.c:
      // 缩进敏感的脚本语言不重排。
      if (norm.contains('markdown') || norm.contains('asciidoc')) {
        return FormatKind.none;
      }
      return FormatKind.brace;
    case LangFamily.hash:
      // Python 等缩进语言不做大括号重排。
      if (norm.contains('python') || norm.contains('yaml') ||
          norm.contains('makefile') || norm.contains('markdown')) {
        return FormatKind.none;
      }
      return FormatKind.brace;
    case LangFamily.sql:
      return FormatKind.brace;
    case LangFamily.lisp:
    case LangFamily.percent:
    case LangFamily.vb:
    case LangFamily.batch:
    case LangFamily.fortran:
      return FormatKind.none;
  }
}

/// 通用大括号缩进重排。
///
/// 只重写每一行的**前导空白**，行内内容逐字保留（含字符串、注释里的空白），
/// 因此对任何 C 风格语言都是安全的；缩进敏感语言请在调用前排除。
String reindentBraces(
  String text, {
  int tabSize = 4,
  bool useTabs = false,
  bool keepBlankLines = true,
}) {
  final indentUnit = useTabs ? '\t' : ' ' * tabSize;
  final lines = text.split('\n');
  final out = <String>[];
  var depth = 0;
  var inBlockComment = false;

  bool startsWithCloser(String s) {
    if (s.isEmpty) return false;
    final c = s[0];
    return c == '}' || c == ')' || c == ']';
  }

  for (var line in lines) {
    final trimmedRight = line.replaceAll(RegExp(r'[ \t]+$'), '');
    final trimmed = trimmedRight.trim();
    if (trimmed.isEmpty) {
      out.add(keepBlankLines ? '' : '');
      continue;
    }

    // 首行是闭合括号时，先退一级。
    var lineDepth = depth;
    if (startsWithCloser(trimmed)) {
      lineDepth = depth > 0 ? depth - 1 : 0;
    }

    out.add('${indentUnit * lineDepth}$trimmed');

    // 统计本行对深度的净影响（跳过字符串与注释里的括号）。
    var i = 0;
    var inString = false;
    var stringQuote = '';
    while (i < trimmed.length) {
      final ch = trimmed[i];
      if (inBlockComment) {
        if (ch == '*' && i + 1 < trimmed.length && trimmed[i + 1] == '/') {
          inBlockComment = false;
          i += 2;
          continue;
        }
        i += 1;
        continue;
      }
      if (inString) {
        if (ch == '\\') {
          i += 2;
          continue;
        }
        if (ch == stringQuote) inString = false;
        i += 1;
        continue;
      }
      if (ch == '/' && i + 1 < trimmed.length) {
        if (trimmed[i + 1] == '/') break;
        if (trimmed[i + 1] == '*') {
          inBlockComment = true;
          i += 2;
          continue;
        }
      }
      if (ch == '"' || ch == "'" || ch == '`') {
        inString = true;
        stringQuote = ch;
        i += 1;
        continue;
      }
      if (ch == '{' || ch == '(' || ch == '[') {
        depth += 1;
      } else if (ch == '}' || ch == ')' || ch == ']') {
        depth -= 1;
        if (depth < 0) depth = 0;
      }
      i += 1;
    }
  }

  return out.join('\n');
}
