// Git 合并冲突标记的识别与消解。
//
// 之所以独立成纯函数：冲突块的行号一旦算错，替换就会「吃掉」相邻的正常代码，
// 而在编辑器里手工验证一份几百行的冲突文件非常费劲。
//
// 支持两种标记：
//   两路：<<<<<<< HEAD / ======= / >>>>>>>
//   三路：<<<<<<< HEAD / ||||||| base / ======= / >>>>>>>（git merge.conflictStyle=diff3）
/// 消解冲突时采用哪一侧的内容。
enum ConflictChoice {
  /// 当前分支（`<<<<<<<` 与 `=======` 之间）
  ours,

  /// 传入分支（`=======` 与 `>>>>>>>` 之间）
  theirs,

  /// 两边都留（先 ours 后 theirs）
  both,

  /// 合并基线（diff3 才有；没有 base 段时等同 ours）
  base,
}

/// 一个冲突块。[startLine]/[endLine] 都是 0-based，且**包含**标记行本身。
class ConflictBlock {
  final int startLine;
  final int endLine;

  /// 「当前分支」内容行（不含标记行）。
  final List<String> ours;

  /// 基线内容行（diff3 才有，否则为空）。
  final List<String> base;

  /// 「传入分支」内容行。
  final List<String> theirs;

  /// `<<<<<<<` 后面的说明（通常是 HEAD 或分支名）。
  final String label;

  const ConflictBlock({
    required this.startLine,
    required this.endLine,
    required this.ours,
    required this.base,
    required this.theirs,
    required this.label,
  });

  /// 这个块一共占多少行（含 3~4 个标记行）。
  int get lineCount => endLine - startLine + 1;

  /// 消解后应该写回的内容行。
  List<String> resolve(ConflictChoice choice) {
    switch (choice) {
      case ConflictChoice.ours:
        return ours;
      case ConflictChoice.theirs:
        return theirs;
      case ConflictChoice.both:
        return [...ours, ...theirs];
      case ConflictChoice.base:
        return base.isEmpty ? ours : base;
    }
  }
}

/// 扫出文本里所有**成对完整**的冲突块。
///
/// 只有「`<<<<<<<` → `=======` → `>>>>>>>` 顺序齐全」才算一块：单独一行 `=======`
/// 是 Markdown 标题下划线、单独的 `<<<<<<<` 可能只是注释分隔符，不能当冲突处理。
List<ConflictBlock> findConflicts(String text) {
  if (!text.contains('<<<<<<<')) return const <ConflictBlock>[];
  final lines = text.split('\n');
  final out = <ConflictBlock>[];

  for (var i = 0; i < lines.length; i++) {
    if (!_isMarker(lines[i], '<<<<<<<')) continue;
    final label = lines[i].substring(7).trim();
    var baseAt = -1;
    var midAt = -1;
    var endAt = -1;
    for (var j = i + 1; j < lines.length; j++) {
      final l = lines[j];
      // 嵌套的 <<<<<<< 说明上一个块没闭合，放弃它从新的开始
      if (_isMarker(l, '<<<<<<<')) break;
      if (_isMarker(l, '|||||||')) {
        if (baseAt < 0 && midAt < 0) baseAt = j;
        continue;
      }
      if (_isMarker(l, '=======')) {
        if (midAt < 0) {
          midAt = j;
        }
        continue;
      }
      if (_isMarker(l, '>>>>>>>')) {
        if (midAt >= 0) endAt = j;
        break;
      }
    }
    if (midAt < 0 || endAt < 0) continue;

    final oursEnd = baseAt >= 0 && baseAt < midAt ? baseAt : midAt;
    out.add(ConflictBlock(
      startLine: i,
      endLine: endAt,
      ours: lines.sublist(i + 1, oursEnd),
      base: baseAt >= 0 && baseAt < midAt ? lines.sublist(baseAt + 1, midAt) : const [],
      theirs: lines.sublist(midAt + 1, endAt),
      label: label,
    ));
    i = endAt;
  }
  return out;
}

/// 标记行判定：允许行首缩进（有些人会缩进冲突块），但标记字符数必须够。
bool _isMarker(String line, String marker) {
  final t = line.trimLeft();
  if (t.length < marker.length) return false;
  return t.startsWith(marker);
}

/// 按 [choices] 消解冲突（下标对应 [findConflicts] 的结果）。
///
/// [choices] 里没有的块保持原样。返回新文本，行尾换行符与原文一致。
String applyConflicts(String text, List<ConflictBlock> blocks,
    Map<int, ConflictChoice> choices) {
  if (blocks.isEmpty || choices.isEmpty) return text;
  final lines = text.split('\n');
  // 倒序替换：前面的块行号不受后面改动影响
  final order = choices.keys
      .where((i) => i >= 0 && i < blocks.length && blocks[i].endLine < lines.length)
      .toList()
    ..sort((a, b) => blocks[b].startLine.compareTo(blocks[a].startLine));
  final out = List<String>.of(lines);
  for (final idx in order) {
    final b = blocks[idx];
    out.replaceRange(b.startLine, b.endLine + 1, b.resolve(choices[idx]!));
  }
  return out.join('\n');
}

/// 文本里还剩几个冲突块（消解后用来提示「还有 N 处没处理」）。
int conflictCount(String text) => findConflicts(text).length;
