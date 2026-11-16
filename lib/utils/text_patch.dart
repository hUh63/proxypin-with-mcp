import 'text_diff.dart';

/// 把两份文本的差异输出成 **unified diff**（\*.patch / \*.diff）。
///
/// 格式与 `git diff` / `diff -u` 一致，可以直接 `git apply` / `patch -p1`：
///
/// ```
/// --- a/foo.txt
/// +++ b/foo.txt
/// @@ -1,4 +1,5 @@
///  same
/// -old
/// +new
/// +extra
///  same
/// ```
///
/// 相比「导出报告 / Markdown」，补丁是**机器可读**的：能提交、能回放、能给别人打。
class PatchHunk {
  /// 左侧起始行（1 起；行数为 0 时按 unified diff 约定退一行写）。
  final int leftStart;
  final int leftCount;
  final int rightStart;
  final int rightCount;

  /// 块内每一行，已带 ` ` / `-` / `+` 前缀（不含行尾换行符）。
  final List<String> lines;

  const PatchHunk({
    required this.leftStart,
    required this.leftCount,
    required this.rightStart,
    required this.rightCount,
    required this.lines,
  });

  String get header => '@@ -${_range(leftStart, leftCount)} +${_range(rightStart, rightCount)} @@';

  /// 区间写法：行数 1 时可省略 `,1`；行数 0 时起点要退一行。
  static String _range(int start, int count) {
    if (count == 0) return '${start - 1},0';
    if (count == 1) return '$start';
    return '$start,$count';
  }
}

/// 生成 unified diff 的块列表。
///
/// [context] 是每个块上下保留的相同行数（git 默认 3）。
/// [ignore*] 与对比页的忽略开关一致：**只影响「算不算差异」**，输出里仍然是原文。
List<PatchHunk> buildPatchHunks(
  String left,
  String right, {
  int context = 3,
  bool ignoreCase = false,
  bool ignoreWhitespace = false,
  bool ignoreTrailingWhitespace = false,
  bool ignoreBlankLines = false,
  bool ignoreComments = false,
}) {
  // 文本末尾的换行不是一个「空行」：'a\nb\n' 是 2 行，diffLines 因为要保留
  // 「末尾是否多一个换行」的差异会把它切成 3 段（最后一段为空），直接拿去写
  // patch 会多出一条 ` ` 空行 + 一个空行，`git apply` 会认为文件末尾多了一行。
  // 这里先摘掉末尾那一个换行再比较。
  final l = left.endsWith('\n') ? left.substring(0, left.length - 1) : left;
  final r = right.endsWith('\n') ? right.substring(0, right.length - 1) : right;
  // 空文件是 0 行，不是「一个空行」：不特判的话，从空文件新建的补丁头会写成
  // `-1,1`（说原文件有一行空行），`git apply` 就会在目标里凭空留一个空行。
  if (l.isEmpty || r.isEmpty) {
    final onlyRight = l.isEmpty;
    final src = onlyRight ? r : l;
    if (src.isEmpty) return const <PatchHunk>[];
    final lines = src.split('\n').map((e) => (onlyRight ? '+' : '-') + e).toList();
    return <PatchHunk>[
      PatchHunk(
        leftStart: 1,
        leftCount: onlyRight ? 0 : lines.length,
        rightStart: 1,
        rightCount: onlyRight ? lines.length : 0,
        lines: lines,
      )
    ];
  }

  final diffs = diffLines(
    l,
    r,
    ignoreCase: ignoreCase,
    ignoreWhitespace: ignoreWhitespace,
    ignoreTrailingWhitespace: ignoreTrailingWhitespace,
    ignoreBlankLines: ignoreBlankLines,
    ignoreComments: ignoreComments,
  );
  final n = diffs.length;
  if (n == 0) return const <PatchHunk>[];

  // 1) 先把「差异段 ± context」收集成区间；两段挨着或重叠就合并，
  //    否则同一行会出现在两个 @@ 里，打补丁时会重复应用。
  final ranges = <List<int>>[];
  var i = 0;
  while (i < n) {
    if (diffs[i].type == LineDiffType.equal) {
      i++;
      continue;
    }
    final from = i;
    while (i < n && diffs[i].type != LineDiffType.equal) {
      i++;
    }
    final to = i;
    final s = from - context < 0 ? 0 : from - context;
    final e = to + context > n ? n : to + context;
    if (ranges.isNotEmpty && s <= ranges.last[1]) {
      if (e > ranges.last[1]) ranges.last[1] = e;
    } else {
      ranges.add(<int>[s, e]);
    }
  }

  // 2) 每段生成一个 hunk
  final hunks = <PatchHunk>[];
  for (final r in ranges) {
    final s = r[0];
    final e = r[1];
    final lines = <String>[];
    var leftCount = 0;
    var rightCount = 0;
    var leftStart = 0;
    var rightStart = 0;
    for (var k = s; k < e; k++) {
      final d = diffs[k];
      switch (d.type) {
        case LineDiffType.equal:
          lines.add(' ${d.text}');
          leftCount++;
          rightCount++;
          if (leftStart == 0 && d.leftLine != null) leftStart = d.leftLine!;
          if (rightStart == 0 && d.rightLine != null) rightStart = d.rightLine!;
        case LineDiffType.delete:
          lines.add('-${d.text}');
          leftCount++;
          if (leftStart == 0 && d.leftLine != null) leftStart = d.leftLine!;
        case LineDiffType.insert:
          lines.add('+${d.text}');
          rightCount++;
          if (rightStart == 0 && d.rightLine != null) rightStart = d.rightLine!;
      }
    }
    // 一侧完全没有行（纯新增 / 纯删除整块）时，起点要落在「被插入的位置」
    if (leftStart == 0 || rightStart == 0) {
      int? ls = leftStart == 0 ? null : leftStart;
      int? rs = rightStart == 0 ? null : rightStart;
      for (var k = s - 1; k >= 0 && (ls == null || rs == null); k--) {
        ls ??= diffs[k].leftLine;
        rs ??= diffs[k].rightLine;
      }
      leftStart = leftStart != 0 ? leftStart : (ls ?? 1);
      rightStart = rightStart != 0 ? rightStart : (rs ?? 1);
    }
    hunks.add(PatchHunk(
      leftStart: leftStart,
      leftCount: leftCount,
      rightStart: rightStart,
      rightCount: rightCount,
      lines: lines,
    ));
  }
  return hunks;
}

/// 完整补丁文本（含 `--- / +++` 文件头）。内容完全相同时返回空串。
///
/// [leftName] / [rightName] 只用于头部文件名展示；要 `git apply -p1` 时用
/// `a/<path>` 与 `b/<path>` 更顺手。
String buildUnifiedPatch(
  String left,
  String right, {
  String leftName = 'a.txt',
  String rightName = 'b.txt',
  int context = 3,
  bool ignoreCase = false,
  bool ignoreWhitespace = false,
  bool ignoreTrailingWhitespace = false,
  bool ignoreBlankLines = false,
  bool ignoreComments = false,
}) {
  final hunks = buildPatchHunks(
    left,
    right,
    context: context,
    ignoreCase: ignoreCase,
    ignoreWhitespace: ignoreWhitespace,
    ignoreTrailingWhitespace: ignoreTrailingWhitespace,
    ignoreBlankLines: ignoreBlankLines,
    ignoreComments: ignoreComments,
  );
  if (hunks.isEmpty) return '';
  final sb = StringBuffer()
    ..writeln('--- $leftName')
    ..writeln('+++ $rightName');
  for (final h in hunks) {
    sb.writeln(h.header);
    for (final l in h.lines) {
      sb.writeln(l);
    }
  }
  return sb.toString();
}

/// 摘要：几个块、增删各几行（用于按钮上显示 `3 块 +5 -2`）。
({int hunks, int added, int removed}) patchSummary(
  String left,
  String right, {
  int context = 3,
  bool ignoreCase = false,
  bool ignoreWhitespace = false,
  bool ignoreTrailingWhitespace = false,
  bool ignoreBlankLines = false,
  bool ignoreComments = false,
}) {
  final hunks = buildPatchHunks(
    left,
    right,
    context: context,
    ignoreCase: ignoreCase,
    ignoreWhitespace: ignoreWhitespace,
    ignoreTrailingWhitespace: ignoreTrailingWhitespace,
    ignoreBlankLines: ignoreBlankLines,
    ignoreComments: ignoreComments,
  );
  var added = 0;
  var removed = 0;
  for (final h in hunks) {
    for (final l in h.lines) {
      if (l.startsWith('+')) added++;
      if (l.startsWith('-')) removed++;
    }
  }
  return (hunks: hunks.length, added: added, removed: removed);
}
