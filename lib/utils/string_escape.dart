// 「把文本变成字符串字面量 / 变回来」——开发者日常最烦的一步。
//
// 典型场景：把一段多行 SQL 或 JSON 塞进一行日志、把日志里的 `\n` 还原成真换行、
// 把文件内容粘进 JSON 配置。手机上手工改这些转义几乎不可能。

/// 支持的转义方言。[language] 只影响少量细节（如单引号是否转义）。
enum EscapeDialect {
  /// C / Java / JS / Dart / Go / Python 双引号字符串
  cLike,

  /// JSON 字符串（与 C 类似，但只认 `"`）
  json,

  /// SQL 单引号字符串：`'` 变成 `''`，反斜杠不转义（标准 SQL）
  sql,

  /// 正则字面量：转义正则元字符（`.` `*` `+` `?` `(` `)` `[` `]` `{` `}` `^` `$` `|` `\`）
  regex,
}

/// 是否会在生成的字面量两侧加引号（[EscapeDialect.sql] / [EscapeDialect.regex] 不加）。
bool _quotesFor(EscapeDialect d) => d == EscapeDialect.cLike || d == EscapeDialect.json;

/// 把文本转义成字面量内容。`wrap` 为 true 时连同引号一起返回。
String escapeText(String text, {EscapeDialect dialect = EscapeDialect.cLike, bool wrap = true}) {
  final buf = StringBuffer();
  if (wrap && _quotesFor(dialect)) buf.write('"');
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (dialect == EscapeDialect.sql) {
      if (c == "'") {
        buf.write("''");
      } else {
        buf.write(c);
      }
      continue;
    }
    if (dialect == EscapeDialect.regex) {
      const meta = r'.*+?()[]{}^$|' '\\';
      if (meta.contains(c)) buf.write('\\');
      buf.write(c);
      continue;
    }
    switch (c) {
      case '\\':
        buf.write('\\\\');
      case '"':
        buf.write('\\"');
      case '\n':
        buf.write(r'\n');
      case '\r':
        buf.write(r'\r');
      case '\t':
        buf.write(r'\t');
      case '\b':
        buf.write(r'\b');
      case '\f':
        buf.write(r'\f');
      default:
        final code = c.codeUnitAt(0);
        if (code < 0x20) {
          buf.write('\\u${code.toRadixString(16).padLeft(4, '0')}');
        } else {
          buf.write(c);
        }
    }
  }
  if (wrap && _quotesFor(dialect)) buf.write('"');
  return buf.toString();
}

/// [escapeText] 的逆操作：把字面量内容还原成原始文本。
///
/// 识别 `\\` `\"` `\'` `\n` `\r` `\t` `\b` `\f` `\0` `\uXXXX` `\xNN`；
/// 其它 `\x` 原样保留（宁可少还原，也不要把用户的正文吃掉）。
/// 两侧的引号会自动去掉。
String unescapeText(String text) {
  var t = text.trim();
  if (t.length >= 2) {
    final first = t[0];
    final last = t[t.length - 1];
    if ((first == '"' || first == "'") && first == last) {
      t = t.substring(1, t.length - 1);
    }
  }
  // SQL 的单引号转义：'' → '
  final buf = StringBuffer();
  var i = 0;
  while (i < t.length) {
    final c = t[i];
    if (c == "'" && i + 1 < t.length && t[i + 1] == "'") {
      buf.write("'");
      i += 2;
      continue;
    }
    if (c != '\\' || i + 1 >= t.length) {
      buf.write(c);
      i++;
      continue;
    }
    final n = t[i + 1];
    switch (n) {
      case 'n':
        buf.write('\n');
        i += 2;
      case 'r':
        buf.write('\r');
        i += 2;
      case 't':
        buf.write('\t');
        i += 2;
      case 'b':
        buf.write('\b');
        i += 2;
      case 'f':
        buf.write('\f');
        i += 2;
      case '0':
        buf.write('\u0000');
        i += 2;
      case '\\':
        buf.write('\\');
        i += 2;
      case '"':
        buf.write('"');
        i += 2;
      case "'":
        buf.write("'");
        i += 2;
      case 'u':
        if (i + 6 <= t.length) {
          final hex = t.substring(i + 2, i + 6);
          final v = int.tryParse(hex, radix: 16);
          if (v != null) {
            buf.writeCharCode(v);
            i += 6;
            break;
          }
        }
        buf.write(n);
        i += 2;
      case 'x':
        if (i + 4 <= t.length) {
          final hex = t.substring(i + 2, i + 4);
          final v = int.tryParse(hex, radix: 16);
          if (v != null) {
            buf.writeCharCode(v);
            i += 4;
            break;
          }
        }
        buf.write(n);
        i += 2;
      default:
        // 不认识的转义：保留反斜杠，别把正文吃掉
        buf.write(c);
        buf.write(n);
        i += 2;
    }
  }
  return buf.toString();
}
