/// 「闭合括号注释」——VS 的 *Show closing brace comments*。
///
/// 在块结束的 `}` 后面浮一个灰色的块名，读者一眼知道这行收的是哪个类/函数。
/// 纯语法扫描，不做类型推断，所以对任何语言都安全：认不出名字的块（`if`/`for`
/// 之类）直接不标。
library;

/// 一条闭合括号提示。
class ClosingBraceHint {
  /// 所在行（0 起）。
  final int line;

  /// 所在列（该行的行末，0 起）。
  final int column;

  /// 显示的块名。
  final String text;

  const ClosingBraceHint({
    required this.line,
    required this.column,
    required this.text,
  });

  @override
  String toString() => 'ClosingBraceHint($line:$column $text)';
}

/// 这些词出现在「名字」位置时说明是真控制语句而不是声明。
const Set<String> _controlWords = {
  'if', 'else', 'for', 'foreach', 'while', 'do', 'switch', 'case', 'try',
  'catch', 'finally', 'lock', 'fixed', 'using', 'with', 'unless', 'when',
  'match', 'return', 'await', 'yield', 'new', 'throw', 'super', 'this',
  'synchronized', 'assert', 'defer', 'go', 'select', 'loop', 'guard',
};

bool _isControlHead(String head) {
  final m = RegExp(r'^([A-Za-z_$][\w$]*)').firstMatch(head);
  if (m == null) return false;
  return _controlWords.contains(m.group(1));
}

/// 从「`{` 所在行、`{` 之前的片段」里猜这个块叫什么。
///
/// 只做三件很有把握的事：`class Foo` 这类声明、`func bar(` 这类函数定义、
/// 以及 `bar(` 这种「名字 + 括号」的形态。猜不到就返回 null（宁可不标）。
String? _blockNameOf(String lineText, int braceColumn) {
  if (braceColumn <= 0 || braceColumn > lineText.length) return null;
  final head = lineText.substring(0, braceColumn).trim();
  if (head.isEmpty) return null;

  final decl = RegExp(
          r'\b(?:class|struct|interface|trait|impl|enum|union|record|namespace|module|object|protocol|extension)\s+([A-Za-z_$][\w$]*)')
      .firstMatch(head);
  if (decl != null) return decl.group(1);

  final fn = RegExp(
          r'\b(?:function|func|def|fn|sub|proc|method|constructor)\s+([A-Za-z_$][\w$]*)')
      .firstMatch(head);
  if (fn != null) return fn.group(1);

  if (_isControlHead(head)) return null;

  // `bar(...) {`：取第一个「名字 + (」。
  for (final m in RegExp(r'([A-Za-z_$][\w$]*)\s*\(').allMatches(head)) {
    final name = m.group(1)!;
    if (_controlWords.contains(name)) continue;
    return name;
  }
  return null;
}

/// 扫一遍文本，返回所有需要显示的闭合括号提示。
///
/// - [lineComment] 该语言的行注释起始符（`//`、`#`、`--`…），用来跳过注释里的括号；
/// - [minBlockLines] 块跨度小于这个行数就不标（单行块的提示只会变成噪音）；
/// - [maxHints] 上限，防止压缩后的单行文件把提示塞满。
List<ClosingBraceHint> closingBraceHints(
  String text, {
  String lineComment = '//',
  int minBlockLines = 4,
  int maxHints = 300,
}) {
  if (text.isEmpty || text.length > 2000000) return const [];
  final lines = text.split('\n');
  final out = <ClosingBraceHint>[];
  final stack = <({int line, String? name})>[];

  var line = 0;
  var lineStart = 0;
  String? quote;
  var blockComment = false;
  var lineCommentOn = false;

  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c == 0x0A) {
      line++;
      lineStart = i + 1;
      lineCommentOn = false;
      continue;
    }
    if (lineCommentOn) continue;
    if (blockComment) {
      if (c == 0x2A && i + 1 < text.length && text.codeUnitAt(i + 1) == 0x2F) {
        blockComment = false;
        i++;
      }
      continue;
    }
    if (quote != null) {
      if (c == 0x5C) {
        i++;
        continue;
      }
      if (c == quote.codeUnitAt(0)) quote = null;
      continue;
    }

    // 注释起始：`//`、`/*`、以及语言自己的行注释符（`#`/`--`）
    if (c == 0x2F && i + 1 < text.length) {
      final n = text.codeUnitAt(i + 1);
      if (n == 0x2F) {
        lineCommentOn = true;
        i++;
        continue;
      }
      if (n == 0x2A) {
        blockComment = true;
        i++;
        continue;
      }
    }
    if (lineComment.isNotEmpty &&
        lineComment != '//' &&
        text.startsWith(lineComment, i)) {
      lineCommentOn = true;
      i += lineComment.length - 1;
      continue;
    }
    if (c == 0x22 || c == 0x27 || c == 0x60) {
      quote = String.fromCharCode(c);
      continue;
    }

    if (c == 0x7B) {
      final col = i - lineStart;
      stack.add((
        line: line,
        name: col <= 0 ? null : _blockNameOf(lines[line], col),
      ));
    } else if (c == 0x7D) {
      if (stack.isEmpty) continue;
      final open = stack.removeLast();
      final name = open.name;
      if (name == null) continue;
      if (line - open.line < minBlockLines) continue;
      out.add(ClosingBraceHint(
        line: line,
        column: lines[line].length,
        text: name,
      ));
      if (out.length >= maxHints) break;
    }
  }
  return out;
}
