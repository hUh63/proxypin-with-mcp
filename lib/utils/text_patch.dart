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

// ------------------------------ 反向：把补丁应用回去 ------------------------------

/// 一个 hunk 的解析结果（只在内部用）。
class _RawHunk {
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;

  /// 已剥掉前缀的行，`kind` 是 ' '(上下文) / '-'(旧侧) / '+'(新侧)。
  final List<(String kind, String text)> items;

  const _RawHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.items,
  });
}

/// 应用补丁的结果。
class PatchApplyResult {
  /// 是否**全部** hunk 都打上了。
  final bool ok;

  /// 应用后的文本（部分失败时也返回「能打上的那部分」，方便自己判断）。
  final String text;

  /// 成功应用的 hunk 数。
  final int applied;

  /// 失败的 hunk 序号（1 起，按补丁里出现的顺序）。
  final List<int> failed;

  /// 解析阶段的整体错误（比如根本不是补丁）；null 表示解析成功。
  final String? error;

  const PatchApplyResult({
    required this.ok,
    required this.text,
    required this.applied,
    required this.failed,
    this.error,
  });
}

/// 把 unified diff 应用到 [target] 上。
///
/// 用途：对比页导出的 `.patch` 贴回来，把「改过的那一侧」还原成另一侧 ——
/// 相当于 Beyond Compare 的反向同步，也顺便验证「导出的补丁到底能不能打」。
///
/// [reverse] 为 true 时把 `+` / `-` 对调（等于撤销这个补丁）。
///
/// 匹配策略（比 `patch(1)` 宽松，适合手工导出的补丁）：
/// 1. 先按 hunk 头里的行号定位；内容对不上就在附近 ±[fuzz] 行内平移找；
/// 2. 单个 hunk 打不上不影响其它 hunk，结果里会列出失败序号；
/// 3. 一律按「行」处理，换行符统一成 `\n` 后再拼回去。
PatchApplyResult applyUnifiedPatch(
  String target,
  String patch, {
  bool reverse = false,
  int fuzz = 200,
}) {
  final parsed = _parsePatch(patch);
  if (parsed.error != null) {
    return PatchApplyResult(
        ok: false, text: target, applied: 0, failed: const <int>[], error: parsed.error);
  }
  final hunks = parsed.hunks;

  // 统一换行后按行切成数组，末尾换行单独记（split 会多给一个空串）。
  //
  // 空目标没有「原来的末尾」可参考，按「文本文件都以换行结束」处理：
  // 补丁本身也表达不了「末尾没有换行」（生成时那一个换行已经被摘掉）。
  final endsWithNewline = target.isEmpty ? true : target.endsWith('\n');
  final lines = <String>[];
  if (target.isNotEmpty) {
    lines.addAll(target.replaceAll('\r\n', '\n').split('\n'));
    if (endsWithNewline && lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  }

  var applied = 0;
  final failed = <int>[];
  // 每打一条，后面 hunk 的行号基准都会平移；用 delta 记累计偏移。
  var delta = 0;

  for (var idx = 0; idx < hunks.length; idx++) {
    final h = hunks[idx];
    final oldSide = <String>[];
    final newSide = <String>[];
    for (final it in h.items) {
      var kind = it.$1;
      if (reverse) {
        if (kind == '-') {
          kind = '+';
        } else if (kind == '+') {
          kind = '-';
        }
      }
      if (kind == ' ' || kind == '-') oldSide.add(it.$2);
      if (kind == ' ' || kind == '+') newSide.add(it.$2);
    }

    final wantStart = (reverse ? h.newStart : h.oldStart) - 1 + delta;
    int? at;
    for (var d = 0; d <= fuzz; d++) {
      // 由近及远：先原地，再往前、往后
      for (final c in d == 0 ? <int>[wantStart] : <int>[wantStart + d, wantStart - d]) {
        if (_matchesAt(lines, c, oldSide)) {
          at = c;
          break;
        }
      }
      if (at != null) break;
    }
    if (at == null) {
      failed.add(idx + 1);
      continue;
    }
    lines.replaceRange(at, at + oldSide.length, newSide);
    delta += newSide.length - oldSide.length;
    applied++;
  }

  var out = lines.join('\n');
  if (endsWithNewline && out.isNotEmpty) out += '\n';
  return PatchApplyResult(ok: failed.isEmpty, text: out, applied: applied, failed: failed);
}

/// [lines] 从 [at] 起是否正好等于 [want]。
bool _matchesAt(List<String> lines, int at, List<String> want) {
  if (at < 0 || at + want.length > lines.length) return false;
  for (var i = 0; i < want.length; i++) {
    if (lines[at + i] != want[i]) return false;
  }
  return true;
}

class _ParsedPatch {
  final List<_RawHunk> hunks;
  final String? error;
  const _ParsedPatch(this.hunks, this.error);
}

/// 解析 unified diff。只认 `@@ -a,b +c,d @@` 开头的块，
/// 文件头（`---` / `+++` / `diff --git` / `index`）一律跳过。
_ParsedPatch _parsePatch(String patch) {
  final hunks = <_RawHunk>[];
  final all = patch.replaceAll('\r\n', '\n').split('\n');
  final headerRe = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@');

  int? oldStart;
  var oldCount = 0;
  var newStart = 0;
  var newCount = 0;
  var items = <(String, String)>[];

  void flush() {
    if (oldStart == null) return;
    hunks.add(_RawHunk(
      oldStart: oldStart!,
      oldCount: oldCount,
      newStart: newStart,
      newCount: newCount,
      items: _trimToCounts(items, oldCount, newCount),
    ));
    oldStart = null;
    items = <(String, String)>[];
  }

  for (final line in all) {
    final m = headerRe.firstMatch(line);
    if (m != null) {
      flush();
      oldStart = int.parse(m.group(1)!);
      oldCount = m.group(2) == null ? 1 : int.parse(m.group(2)!);
      newStart = int.parse(m.group(3)!);
      newCount = m.group(4) == null ? 1 : int.parse(m.group(4)!);
      continue;
    }
    if (oldStart == null) continue; // 还没进第一个块
    if (line.startsWith('\\')) continue; // \ No newline at end of file
    if (line.isEmpty) {
      // 补丁文本末尾的空行（split 的产物）：块内计数满了就不再计入
      if (_countOld(items) >= oldCount && _countNew(items) >= newCount) continue;
      items.add((' ', ''));
      continue;
    }
    final c = line[0];
    if (c == ' ' || c == '-' || c == '+') {
      items.add((c, line.substring(1)));
      if (_countOld(items) >= oldCount && _countNew(items) >= newCount) flush();
    }
  }
  flush();

  if (hunks.isEmpty) {
    return const _ParsedPatch(<_RawHunk>[], '没有找到 @@ 块，看起来不是 unified diff');
  }
  return _ParsedPatch(hunks, null);
}

int _countOld(List<(String, String)> items) => items.where((e) => e.$1 != '+').length;

int _countNew(List<(String, String)> items) => items.where((e) => e.$1 != '-').length;

/// 按块头声明的行数裁掉多余的行（补丁里 @ 之外的空白、尾部空行）。
List<(String, String)> _trimToCounts(
    List<(String, String)> items, int oldCount, int newCount) {
  final out = <(String, String)>[];
  var o = 0;
  var n = 0;
  for (final it in items) {
    final addsOld = it.$1 != '+';
    final addsNew = it.$1 != '-';
    if (addsOld && o >= oldCount) continue;
    if (addsNew && n >= newCount) continue;
    if (addsOld) o++;
    if (addsNew) n++;
    out.add(it);
  }
  return out;
}
