// 粘贴时按光标所在行对齐缩进（VS / VS Code 的 "Reindent on paste"）。
//
// 为什么单独抽出来：这段逻辑要处理「整段代码粘到 if 里面」「Tab 与空格混用」
// 「中间夹空行」这些情况，算错了就是整段代码缩进错位，在编辑器里很难逐行发现。

/// 计算一行开头连续空白（空格 / Tab）的**字符数**。
int leadingBlankChars(String line) {
  var n = 0;
  while (n < line.length) {
    final c = line.codeUnitAt(n);
    if (c != 0x20 && c != 0x09) break;
    n++;
  }
  return n;
}

/// 把多行剪贴板内容的后续行对齐到 [baseIndent]。
///
/// 规则：
/// - 单行、或光标所在行没有缩进 → 原样返回；
/// - 首行不处理（它接在光标后面，缩进由光标位置决定）；
/// - 其余行的公共最小缩进会被剥掉，再统一补上 [baseIndent]；
/// - 整段本身是顶格的（最小缩进为 0）时，所有行一起右移 [baseIndent]；
/// - 空行保持空（不补缩进，避免「空行里带一堆空格」）。
String reindentPasted(String clip, String baseIndent) {
  if (baseIndent.isEmpty) return clip;
  if (!clip.contains('\n')) return clip;
  final lines = clip.split('\n');
  if (lines.length < 2) return clip;

  var min = -1;
  for (var i = 1; i < lines.length; i++) {
    final l = lines[i];
    if (l.trim().isEmpty) continue;
    final n = leadingBlankChars(l);
    if (min < 0 || n < min) min = n;
  }
  // 找不到非空行（粘贴的全是空行）：不做任何改动
  if (min < 0) return clip;

  final out = <String>[lines.first];
  for (var i = 1; i < lines.length; i++) {
    final l = lines[i];
    if (l.trim().isEmpty) {
      out.add('');
      continue;
    }
    out.add('$baseIndent${l.substring(min)}');
  }
  return out.join('\n');
}

/// 去掉多行文本每行开头「行号前缀」。
///
/// 从聊天、文档、工单、代码评审页复制的代码经常带行号：
/// ```
/// 12:   foo();
/// 13:   bar();
/// ```
/// 或者 `12|`、`12\t`、`12.` 这几种变体。手机上没法像桌面那样手动删，
/// 粘进编辑器就是一片语法错误，所以在这里兜掉。
///
/// 判据（三选一，且**至少两行**命中才动手，避免把正文里的「1. 第一步」误删）：
///   - `^\s*(\d+)[:|\t]\s?`
///   - `^\s*(\d+)\.\s`
/// 命中的行统一按「前缀宽度」处理：取连续命中行的最小宽度做整体裁剪，
/// 保留每行原本的相对缩进。
String stripLineNumbers(String text) {
  if (!text.contains('\n')) return text;
  final lines = text.split('\n');
  final r1 = RegExp(r'^[ \t]*(\d+)[:|\t] ?');
  final r2 = RegExp(r'^[ \t]*(\d+)\. ');

  var hit = 0;
  var minWidth = -1;
  // 只统计「连续编号」的段落：行号应当递增（差 1），否则不是行号
  var lastNo = -1;
  var run = 0;
  var bestRunStart = -1;
  var bestRunLen = 0;
  var curStart = -1;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final m = r1.firstMatch(line) ?? r2.firstMatch(line);
    if (m == null) {
      run = 0;
      continue;
    }
    final no = int.tryParse(m.group(1) ?? '');
    if (no == null) {
      run = 0;
      continue;
    }
    if (run > 0 && no != lastNo + 1) {
      run = 0;
    }
    if (run == 0) curStart = i;
    run++;
    lastNo = no;
    hit++;
    final w = m.end;
    if (minWidth < 0 || w < minWidth) minWidth = w;
    if (run > bestRunLen) {
      bestRunLen = run;
      bestRunStart = curStart;
    }
  }
  // 少于 2 行连续编号：不动
  if (hit < 2 || bestRunLen < 2 || bestRunStart < 0) return text;
  // 至少连续 2 行才算（上面已经保证），另外要求整体命中的行占比过半
  if (hit * 2 < lines.where((l) => l.trim().isNotEmpty).length) return text;

  final out = <String>[];
  for (final line in lines) {
    final m = r1.firstMatch(line) ?? r2.firstMatch(line);
    if (m == null) {
      out.add(line);
      continue;
    }
    final cut = m.end < line.length ? m.end : line.length;
    out.add(line.substring(cut));
  }
  return out.join('\n');
}
