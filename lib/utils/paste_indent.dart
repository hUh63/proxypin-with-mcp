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
