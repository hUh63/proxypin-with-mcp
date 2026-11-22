import 'text_diff.dart';

/// 一次「算差异」任务的输入。
///
/// 拆出来的原因：几 MB 的文本做行级 LCS 在 UI 线程上要卡 1~2 秒（手机上更久），
/// 得能整体丢到 isolate 里跑。而 [RegExp] 不能跨 isolate 传递，所以这里存的是
/// **正则源码字符串**，进 isolate 之后再编译。
class DiffJobArgs {
  final String left;
  final String right;

  final bool ignoreCase;
  final bool ignoreWhitespace;
  final bool ignoreTrailingWhitespace;
  final bool ignoreBlankLines;
  final bool ignoreComments;

  /// 按行号对齐（不做 LCS，左第 i 行对右第 i 行）。
  final bool alignByLine;

  /// 识别「搬家」的块（整段删 + 整段增且内容一致）。
  final bool detectMoved;

  final String? ignoreLinePattern;
  final String? ignoreRegionBegin;
  final String? ignoreRegionEnd;

  /// 相似度配对阈值，千分比。
  final int pairSimilarity;

  /// 忽略数字差异（时间戳 / id / 耗时这类「同一行只差一个数」）。
  final bool ignoreNumbers;

  const DiffJobArgs({
    required this.left,
    required this.right,
    this.ignoreCase = false,
    this.ignoreWhitespace = false,
    this.ignoreTrailingWhitespace = false,
    this.ignoreBlankLines = false,
    this.ignoreComments = false,
    this.alignByLine = false,
    this.detectMoved = true,
    this.ignoreLinePattern,
    this.ignoreRegionBegin,
    this.ignoreRegionEnd,
    this.pairSimilarity = 500,
    this.ignoreNumbers = false,
  });

  /// 两侧文本总长，用来判断值不值得起 isolate。
  int get totalChars => left.length + right.length;
}

/// 一次「算差异」任务的结果。
class DiffJobResult {
  final List<LineDiff> diffs;
  final List<DiffBlock> blocks;
  final DiffStats stats;

  /// 参与「搬家」的块下标（删除侧与新增侧都算）。
  final Set<int> movedEnds;

  const DiffJobResult({
    required this.diffs,
    required this.blocks,
    required this.stats,
    required this.movedEnds,
  });
}

/// 空文本按 0 行算（与 `''.split('\n')` 得到 1 个空行不同）。
List<String> _linesOf(String text) =>
    text.isEmpty ? const <String>[] : text.split('\n');

RegExp? _reOf(String? pattern) {
  if (pattern == null || pattern.isEmpty) return null;
  try {
    return RegExp(pattern);
  } catch (_) {
    return null;
  }
}

/// 纯计算，不碰任何 widget / controller，可安全地在 isolate 里跑。
DiffJobResult runDiffJob(DiffJobArgs a) {
  final lineRe = _reOf(a.ignoreLinePattern);
  final regionBegin = _reOf(a.ignoreRegionBegin);
  final regionEnd = _reOf(a.ignoreRegionEnd);

  final diffs = a.alignByLine
      ? diffLinesByPosition(a.left, a.right,
          ignoreCase: a.ignoreCase,
          ignoreWhitespace: a.ignoreWhitespace,
          ignoreTrailingWhitespace: a.ignoreTrailingWhitespace,
          ignoreBlankLines: a.ignoreBlankLines,
          ignoreComments: a.ignoreComments,
          ignoreLinePattern: lineRe)
      : diffLines(a.left, a.right,
          ignoreCase: a.ignoreCase,
          ignoreWhitespace: a.ignoreWhitespace,
          ignoreTrailingWhitespace: a.ignoreTrailingWhitespace,
          ignoreBlankLines: a.ignoreBlankLines,
          ignoreComments: a.ignoreComments,
          ignoreLinePattern: lineRe,
          ignoreRegionBegin: regionBegin,
          ignoreRegionEnd: regionEnd,
          ignoreNumbers: a.ignoreNumbers);

  final blocks = buildDiffBlocks(diffs,
      ignoreCase: a.ignoreCase,
      ignoreWhitespace: a.ignoreWhitespace,
      ignoreTrailingWhitespace: a.ignoreTrailingWhitespace,
      ignoreBlankLines: a.ignoreBlankLines,
      ignoreComments: a.ignoreComments,
      pairSimilarity: a.pairSimilarity,
      ignoreNumbers: a.ignoreNumbers);

  var movedEnds = <int>{};
  if (a.detectMoved && blocks.isNotEmpty) {
    final lns = _linesOf(a.left);
    final rns = _linesOf(a.right);
    // 逐块内容比对是 O(行数)：超大文件跳过，那种场景下没人逐个块看「搬家」标记。
    if (lns.length <= 20000 && rns.length <= 20000) {
      try {
        for (final m in detectMovedBlocks(blocks,
            leftSource: lns,
            rightSource: rns,
            ignoreCase: a.ignoreCase,
            ignoreWhitespace: a.ignoreWhitespace || a.ignoreTrailingWhitespace)) {
          movedEnds.add(m.fromBlock);
          movedEnds.add(m.toBlock);
        }
      } catch (_) {
        movedEnds = <int>{};
      }
    }
  }

  return DiffJobResult(
    diffs: diffs,
    blocks: blocks,
    stats: diffStats(blocks),
    movedEnds: movedEnds,
  );
}

/// `compute` 的入口：只用可跨 isolate 传递的基本类型。
DiffJobResult runDiffJobFromMap(Map<String, Object?> m) => runDiffJob(DiffJobArgs(
      left: (m['left'] as String?) ?? '',
      right: (m['right'] as String?) ?? '',
      ignoreCase: m['ignoreCase'] == true,
      ignoreWhitespace: m['ignoreWhitespace'] == true,
      ignoreTrailingWhitespace: m['ignoreTrailingWhitespace'] == true,
      ignoreBlankLines: m['ignoreBlankLines'] == true,
      ignoreComments: m['ignoreComments'] == true,
      alignByLine: m['alignByLine'] == true,
      detectMoved: m['detectMoved'] != false,
      ignoreLinePattern: m['ignoreLinePattern'] as String?,
      ignoreRegionBegin: m['ignoreRegionBegin'] as String?,
      ignoreRegionEnd: m['ignoreRegionEnd'] as String?,
      pairSimilarity: (m['pairSimilarity'] as int?) ?? 500,
      ignoreNumbers: m['ignoreNumbers'] == true,
    ));
