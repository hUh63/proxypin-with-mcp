// 行级整理：按分隔符对齐、删空行、合并连续空行。
//
// 这类操作在「整理配置文件 / 环境变量 / 一坨赋值语句」时最常用，
// 但手改极易把缩进和顺序弄乱，所以做成纯函数并锁用例。

/// 对齐时优先尝试的分隔符（顺序即优先级）。
const List<String> _delimiterCandidates = <String>['=>', '=', ':', '//'];

/// 一行是不是「整行注释」（对齐时跳过，避免把注释的冒号也算进去）。
bool _isCommentLine(String trimmed) {
  return trimmed.startsWith('//') ||
      trimmed.startsWith('#') ||
      trimmed.startsWith('*') ||
      trimmed.startsWith(';');
}

/// 按分隔符对齐多行。
///
/// - [delimiter] 为空时按 `=>` → `=` → `:` → `//` 的顺序挑「至少两行都有」的那个；
/// - 只动「含该分隔符且分隔符前不是空」的行，其余原样；
/// - 缩进保持不变，只在分隔符前补空格（至少一个）；
/// - 整行注释参与对齐（否则注释会显得参差），但**空行**跳过。
String alignByDelimiter(String text, {String? delimiter}) {
  if (text.isEmpty) return text;
  final lines = text.split('\n');

  String? delim = delimiter;
  if (delim == null || delim.isEmpty) {
    for (final c in _delimiterCandidates) {
      final hits = lines.where((l) {
        final t = l.trimLeft();
        if (_isCommentLine(t)) return false;
        final i = l.indexOf(c);
        return i > 0 && l.substring(0, i).trim().isNotEmpty;
      }).length;
      if (hits >= 2) {
        delim = c;
        break;
      }
    }
  }
  if (delim == null || delim.isEmpty) return text;

  // 第一遍：算「分隔符前」的最大宽度
  final prefixWidth = <int, int>{};
  var maxWidth = 0;
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final at = l.indexOf(delim);
    if (at <= 0) continue;
    final prefix = l.substring(0, at);
    if (prefix.trim().isEmpty) continue;
    final w = prefix.trimRight().length;
    prefixWidth[i] = w;
    if (w > maxWidth) maxWidth = w;
  }
  if (prefixWidth.isEmpty) return text;

  // 第二遍：重排
  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final w = prefixWidth[i];
    if (w == null) {
      out.add(l);
      continue;
    }
    final at = l.indexOf(delim);
    final head = l.substring(0, at).trimRight();
    final rest = l.substring(at);
    final pad = maxWidth - w + 1;
    out.add('$head${' ' * pad}$rest');
  }
  return out.join('\n');
}

/// 删掉所有空行（只含空白字符的行也算空行）。
String removeBlankLines(String text) {
  if (!text.contains('\n')) return text.trim().isEmpty ? '' : text;
  final out = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
  return out.join('\n');
}

/// 把连续空行合并成最多 [maxKeep] 个（默认 1）。
///
/// 别人提交的代码里经常夹着三四个连续空行，读起来很散。
String collapseBlankLines(String text, {int maxKeep = 1}) {
  if (!text.contains('\n')) return text;
  final lines = text.split('\n');
  final out = <String>[];
  var blanks = 0;
  for (final l in lines) {
    if (l.trim().isEmpty) {
      blanks++;
      // 末尾的空行不额外保留（否则「合并空行」会把文件撑长）
      if (blanks <= maxKeep) out.add('');
    } else {
      blanks = 0;
      out.add(l);
    }
  }
  // 不动结尾：文件末尾有没有换行是用户的既有风格，改它会让 diff 多出一行。
  return out.join('\n');
}
