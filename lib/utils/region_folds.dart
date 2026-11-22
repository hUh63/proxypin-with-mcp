/// `#region` / `#endregion` 折叠标记的扫描。
///
/// 各家的写法都认：
/// ```
/// #region 说明            (C# / Dart / 自定义)
/// // #region 说明         (VS Code、Dart 插件)
/// //region 说明           (JetBrains)
/// /* #region 说明 */      (块注释)
/// <!-- #region 说明 -->    (HTML)
/// ```
/// 大小写不敏感，可以嵌套；没闭合的 region 一直延续到文件末尾（和 VS 一致，
/// 少写一个 `#endregion` 不至于整页都不折叠）。
library;

/// 一个可折叠的 region。
class RegionFold {
  /// `#region` 所在行（0 起）——折叠箭头画在这里。
  final int startLine;

  /// `#endregion` 所在行（0 起）。
  final int endLine;

  const RegionFold({required this.startLine, required this.endLine});

  @override
  String toString() => 'RegionFold($startLine..$endLine)';
}

final _beginRe = RegExp(r'^#?\s*region\b', caseSensitive: false);
final _endRe = RegExp(r'^#?\s*endregion\b', caseSensitive: false);

/// 去掉行首的注释符，方便用同一套规则匹配。
///
/// `#` 刻意不剥：它既可能是 C 系的行注释，也是 `#region` 自身的标记符，
/// 剥掉之后 `#region` 就只能靠裸 `region` 匹配，容易把普通单词认成标记。
String _stripCommentShell(String line) {
  var s = line.trim();
  var changed = true;
  while (changed) {
    changed = false;
    for (final p in const ['//', '/*', '<!--', '*']) {
      if (s.startsWith(p)) {
        s = s.substring(p.length).trimLeft();
        changed = true;
      }
    }
  }
  for (final p in const ['*/', '-->']) {
    if (s.endsWith(p)) s = s.substring(0, s.length - p.length).trimRight();
  }
  return s;
}

/// 扫出所有 region 折叠范围，按起始行升序。
///
/// [maxFolds] 是防御上限：真遇到几百个 region 的文件，全部折叠也没有意义，
/// 而且折叠箭头会挤满行号栏。
List<RegionFold> scanRegionFolds(String text, {int maxFolds = 400}) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  final open = <int>[];
  final out = <RegionFold>[];
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    // 先做一次便宜的预筛：含 region 字样的行才去剥壳。
    final lower = raw.toLowerCase();
    if (!lower.contains('region')) continue;
    final bare = _stripCommentShell(raw);
    if (_endRe.hasMatch(bare)) {
      if (open.isEmpty) continue; // 多余的 #endregion，忽略
      final start = open.removeLast();
      if (i > start) {
        out.add(RegionFold(startLine: start, endLine: i));
        if (out.length >= maxFolds) break;
      }
      continue;
    }
    if (_beginRe.hasMatch(bare)) open.add(i);
  }
  // 没闭合的：延续到文件末尾（最后一行如果是空行也不算，免得折出个空块）
  for (final start in open.reversed) {
    var end = lines.length - 1;
    while (end > start && lines[end].trim().isEmpty) {
      end--;
    }
    if (end > start) out.add(RegionFold(startLine: start, endLine: end));
  }
  out.sort((a, b) => a.startLine.compareTo(b.startLine));
  return out;
}
