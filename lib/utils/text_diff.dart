/*
 * Copyright 2026 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// 行级文本对比：Patience Diff（错位时用 lookahead 兜底）。
//
// LCS 会跨远距离匹配（左第 1 行的 `abc` 跟右第 80 行的 `abc` 算公共行），
// 让用户看到"行号错开几十行"的错位结果，对人工对比反直觉。
// 改用 Bram Cohen 的 Patience Diff：
//
//   1. 切公共前缀 / 后缀，直接 emit equal；
//   2. 在剩下的中间段里，找"在两边各自唯一、且都出现"的行作锚点；
//   3. 锚点按 a-index 排序后对 b-index 求 LIS——LIS 上的锚点保证两边顺序一致；
//   4. 用这些锚点把段切短，递归对比每个子段；
//   5. 找不到锚点的小段退化成"双指针 + 短窗前瞻"。
//
// 行配对（块内的删除行 ↔ 新增行）不再"按位置硬配"，而是按**内容相似度**做
// 加权 LCS 配对：只有足够像的两行才算「修改」，否则拆成「删除 + 新增」。
// 这样 `1111` 不会配到 `222`（相似度 0）上，而是配到更像的 `11` 上。
//
// 比较时可选忽略大小写 / 忽略空白（用归一化的 key 比较，显示仍是原文）。

/// 前瞻窗口：基线段（无锚点）里发现错位时往前找几行。
/// Patience 切完之后段通常不长，4 已经够用；调大对工程不敏感。
const int _lookahead = 4;

/// 行配对的相似度阈值（千分比）：两行字符 LCS 占比达到 50% 才认为「同一行的改写」。
const int _pairSimilarity = 500;

/// 配对 DP 的规模上限：块太大时退化为按位置配对，避免 O(m²n²) 卡顿。
const int _pairMaxCells = 20000;

final RegExp _whiteSpace = RegExp(r'\s+');

enum LineDiffType { equal, insert, delete }

class LineDiff {
  final LineDiffType type;
  final String text;

  /// 该行在左侧文本里的 1-based 行号；insert 类型为 null
  final int? leftLine;

  /// 该行在右侧文本里的 1-based 行号；delete 类型为 null
  final int? rightLine;

  const LineDiff(this.type, this.text, {this.leftLine, this.rightLine});
}

/// 归一化 key：仅用于「是否相同」的比较，不改变显示文本。
String _normKey(String s, bool ignoreCase, bool ignoreWhitespace,
    [bool ignoreTrailingWhitespace = false,
    bool ignoreBlankLines = false,
    bool ignoreComments = false]) {
  var k = s;
  // 忽略注释：整行注释当作空行，行尾 ` //` 之后丢掉。
  // 只做这两种最常见的形式，不做跨行块注释（对纯文本对比来说误伤比收益大）。
  if (ignoreComments) {
    k = _stripCommentForCompare(k);
    if (k.trim().isEmpty) return '';
  }
  // 忽略空白行：整篇的空行都归一成空串，于是「一边多几个空行」不再算差异。
  // 只影响比较用的 key，显示仍是原文（Beyond Compare 的「忽略空白行」）。
  if (ignoreBlankLines && k.trim().isEmpty) return '';
  // 行尾 \r 是「换行符风格」不是内容：CRLF 与 LF 的文件必须逐行能对上，
  // 否则整篇都会被标成修改（Windows/macOS 互传文件时最常踩）。
  if (k.endsWith('\r')) k = k.substring(0, k.length - 1);
  if (ignoreWhitespace) {
    k = k.replaceAll(_whiteSpace, '');
  } else if (ignoreTrailingWhitespace) {
    k = k.trimRight();
  }
  if (ignoreCase) k = k.toLowerCase();
  return k;
}

/// 对比用的注释剥离（粗略）：整行注释清空，行尾 ` //` 之后丢掉。
String _stripCommentForCompare(String s) {
  final t = s.trimLeft();
  if (t.startsWith('//') || t.startsWith('*') || t.startsWith('#')) return '';
  final i = s.indexOf(' //');
  return i < 0 ? s : s.substring(0, i);
}

/// 计算两段文本的行级差异，按出现顺序返回。
List<LineDiff> diffLines(String left, String right,
    {bool ignoreCase = false,
    bool ignoreWhitespace = false,
    bool ignoreTrailingWhitespace = false,
    bool ignoreBlankLines = false,
    bool ignoreComments = false}) {
  // 用 split('\n') 而不是 LineSplitter：保留尾部空行的差异（"a\n" vs "a"）
  final a = left.split('\n');
  final b = right.split('\n');
  final aK = a
      .map((s) => _normKey(s, ignoreCase, ignoreWhitespace, ignoreTrailingWhitespace,
          ignoreBlankLines, ignoreComments))
      .toList();
  final bK = b
      .map((s) => _normKey(s, ignoreCase, ignoreWhitespace, ignoreTrailingWhitespace,
          ignoreBlankLines, ignoreComments))
      .toList();
  final out = <LineDiff>[];
  _diffRange(a, aK, b, bK, 0, a.length, 0, b.length, out);
  if (!ignoreBlankLines) return out;
  // 「忽略空白行」必须在 diff 之后再做一遍：把整段「只涉及空行」的增删丢掉。
  // 只在 _normKey 里归一成空串是不够的——那样「右边多两行空行」仍然会算出两处增行，
  // 只是两行内容都成了空串（第一版就栽在这，用例才把它抓出来）。
  return _dropBlankOnlyDiffs(
      out, a, b, ignoreCase, ignoreWhitespace, ignoreTrailingWhitespace, ignoreComments);
}

/// 丢掉「一整段差异里全是空行」的那些段。
List<LineDiff> _dropBlankOnlyDiffs(List<LineDiff> diffs, List<String> a, List<String> b,
    bool ignoreCase, bool ignoreWhitespace, bool ignoreTrailingWhitespace, bool ignoreComments) {
  bool isBlank(LineDiff d) =>
      _normKey(d.text, ignoreCase, ignoreWhitespace, ignoreTrailingWhitespace,
          true, ignoreComments)
          .isEmpty;
  final out = <LineDiff>[];
  var i = 0;
  while (i < diffs.length) {
    if (diffs[i].type == LineDiffType.equal) {
      out.add(diffs[i]);
      i++;
      continue;
    }
    final start = i;
    while (i < diffs.length && diffs[i].type != LineDiffType.equal) {
      i++;
    }
    // 段内保留非空行；整段都是空行时整段丢弃（= 这段本来就没差异）。
    for (var k = start; k < i; k++) {
      if (!isBlank(diffs[k])) out.add(diffs[k]);
    }
  }
  return out;
}

void _diffRange(List<String> a, List<String> aK, List<String> b, List<String> bK, int aLo, int aHi, int bLo,
    int bHi, List<LineDiff> out) {
  // 1. 公共前缀
  while (aLo < aHi && bLo < bHi && aK[aLo] == bK[bLo]) {
    out.add(LineDiff(LineDiffType.equal, a[aLo], leftLine: aLo + 1, rightLine: bLo + 1));
    aLo++;
    bLo++;
  }
  // 2. 公共后缀（先记长度，最后 emit）
  var suffix = 0;
  while (aLo < aHi - suffix && bLo < bHi - suffix && aK[aHi - 1 - suffix] == bK[bHi - 1 - suffix]) {
    suffix++;
  }
  final aEnd = aHi - suffix;
  final bEnd = bHi - suffix;

  // 3. 中间段：找锚点切分
  if (aLo < aEnd || bLo < bEnd) {
    final anchors = _findAnchors(aK, aLo, aEnd, bK, bLo, bEnd);
    if (anchors.isEmpty) {
      _lookaheadDiff(a, aK, b, bK, aLo, aEnd, bLo, bEnd, out);
    } else {
      var prevA = aLo, prevB = bLo;
      for (final anchor in anchors) {
        _diffRange(a, aK, b, bK, prevA, anchor.aIdx, prevB, anchor.bIdx, out);
        out.add(LineDiff(
          LineDiffType.equal,
          a[anchor.aIdx],
          leftLine: anchor.aIdx + 1,
          rightLine: anchor.bIdx + 1,
        ));
        prevA = anchor.aIdx + 1;
        prevB = anchor.bIdx + 1;
      }
      _diffRange(a, aK, b, bK, prevA, aEnd, prevB, bEnd, out);
    }
  }

  // 4. 公共后缀
  for (var k = 0; k < suffix; k++) {
    out.add(LineDiff(
      LineDiffType.equal,
      a[aEnd + k],
      leftLine: aEnd + k + 1,
      rightLine: bEnd + k + 1,
    ));
  }
}

class _Anchor {
  final int aIdx;
  final int bIdx;
  const _Anchor(this.aIdx, this.bIdx);
}

/// 在 [aLo,aHi) × [bLo,bHi) 内找"两边各自唯一且都出现"的行，作为对齐锚点。
/// 返回的锚点已按 a-index 升序排列，且对应的 b-index 也单调递增（LIS 保证）。
List<_Anchor> _findAnchors(List<String> aK, int aLo, int aHi, List<String> bK, int bLo, int bHi) {
  // 统计每行出现次数 + 第一次出现的下标
  final aCount = <String, int>{};
  final aIdx = <String, int>{};
  for (var i = aLo; i < aHi; i++) {
    final s = aK[i];
    final c = aCount[s];
    if (c == null) {
      aCount[s] = 1;
      aIdx[s] = i;
    } else {
      aCount[s] = c + 1;
    }
  }
  final bCount = <String, int>{};
  final bIdx = <String, int>{};
  for (var i = bLo; i < bHi; i++) {
    final s = bK[i];
    final c = bCount[s];
    if (c == null) {
      bCount[s] = 1;
      bIdx[s] = i;
    } else {
      bCount[s] = c + 1;
    }
  }

  final candidates = <_Anchor>[];
  aCount.forEach((s, ca) {
    if (ca == 1 && bCount[s] == 1) {
      candidates.add(_Anchor(aIdx[s]!, bIdx[s]!));
    }
  });
  if (candidates.isEmpty) return const [];

  candidates.sort((x, y) => x.aIdx.compareTo(y.aIdx));
  return _longestIncreasingSubsequence(candidates);
}

/// 在按 a-index 排序的候选里，找 b-index 严格递增的最长子序列。
/// 这是 Patience Sort 的标准用法：O(n log n)，并通过 prev 指针重建子序列。
List<_Anchor> _longestIncreasingSubsequence(List<_Anchor> sortedByA) {
  final n = sortedByA.length;
  if (n == 0) return const [];

  // tailIdx[k] = 长度 (k+1) 的递增子序列里 b-index 最小的那条所在的 sortedByA 下标
  final tailIdx = <int>[];
  final prev = List<int>.filled(n, -1);

  for (var i = 0; i < n; i++) {
    final bv = sortedByA[i].bIdx;
    var lo = 0, hi = tailIdx.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sortedByA[tailIdx[mid]].bIdx < bv) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0) prev[i] = tailIdx[lo - 1];
    if (lo == tailIdx.length) {
      tailIdx.add(i);
    } else {
      tailIdx[lo] = i;
    }
  }

  // 从最后一条 tail 顺着 prev 重建
  final result = <_Anchor>[];
  var k = tailIdx.last;
  while (k >= 0) {
    result.add(sortedByA[k]);
    k = prev[k];
  }
  return result.reversed.toList();
}

/// 段内没有锚点时的兜底：双指针 + 短窗前瞻。
/// 不等时在 [_lookahead]² 个候选 (di, dj) 里找最近匹配点；找不到就当作"同行修改"。
void _lookaheadDiff(List<String> a, List<String> aK, List<String> b, List<String> bK, int aLo, int aHi, int bLo,
    int bHi, List<LineDiff> out) {
  var i = aLo, j = bLo;
  while (i < aHi && j < bHi) {
    if (aK[i] == bK[j]) {
      out.add(LineDiff(LineDiffType.equal, a[i], leftLine: i + 1, rightLine: j + 1));
      i++;
      j++;
      continue;
    }
    int bestDi = -1, bestDj = -1, bestSum = 1 << 30;
    for (var sum = 1; sum <= _lookahead * 2 && sum < bestSum; sum++) {
      for (var di = 0; di <= sum; di++) {
        final dj = sum - di;
        if (di > _lookahead || dj > _lookahead) continue;
        final ii = i + di;
        final jj = j + dj;
        if (ii >= aHi || jj >= bHi) continue;
        if (aK[ii] == bK[jj]) {
          bestDi = di;
          bestDj = dj;
          bestSum = sum;
          break;
        }
      }
    }
    if (bestDi >= 0) {
      for (var x = 0; x < bestDi; x++) {
        out.add(LineDiff(LineDiffType.delete, a[i], leftLine: i + 1));
        i++;
      }
      for (var x = 0; x < bestDj; x++) {
        out.add(LineDiff(LineDiffType.insert, b[j], rightLine: j + 1));
        j++;
      }
    } else {
      out.add(LineDiff(LineDiffType.delete, a[i], leftLine: i + 1));
      out.add(LineDiff(LineDiffType.insert, b[j], rightLine: j + 1));
      i++;
      j++;
    }
  }
  while (i < aHi) {
    out.add(LineDiff(LineDiffType.delete, a[i], leftLine: i + 1));
    i++;
  }
  while (j < bHi) {
    out.add(LineDiff(LineDiffType.insert, b[j], rightLine: j + 1));
    j++;
  }
}

// ---------- 行配对（按相似度） ----------

/// 两行的相似度（千分比，0..1000）：字符级 LCS 长度占较长行长度的比例。
int _similarityScore(String l, String r) {
  if (l == r) return 1000;
  final a = l.codeUnits;
  final b = r.codeUnits;
  final m = a.length;
  final n = b.length;
  if (m == 0 || n == 0) return 0;
  // 超长行（压缩后的 JS/CSS 一行十几万字符）做字符级 LCS 是 O(m·n)：10⁵×10⁵
  // 直接把 isolate 卡死。这类行反正整行都算「修改」，配不配对结果一样，
  // 用「共同前缀比例」给个粗分即可。
  if (m > 2000 || n > 2000) {
    final lim = m < n ? m : n;
    var same = 0;
    while (same < lim && a[same] == b[same]) {
      same++;
    }
    return (same * 1000) ~/ lim;
  }
  var prev = List<int>.filled(n + 1, 0);
  for (var i = 1; i <= m; i++) {
    final cur = List<int>.filled(n + 1, 0);
    final ai = a[i - 1];
    for (var j = 1; j <= n; j++) {
      if (ai == b[j - 1]) {
        cur[j] = prev[j - 1] + 1;
      } else {
        cur[j] = cur[j - 1] > prev[j] ? cur[j - 1] : prev[j];
      }
    }
    prev = cur;
  }
  final lcs = prev[n];
  final denom = m > n ? m : n;
  return (lcs * 1000) ~/ denom;
}

/// 在一段「删除行 × 新增行」之间做**相似度加权 LCS 配对**：
/// 保序（不交叉），只把相似度 ≥ [_pairSimilarity] 的行配成「修改」。
List<({int left, int right})> _pairLines(List<String> leftTexts,
    List<String> rightTexts, bool ignoreCase, bool ignoreWhitespace,
    [bool ignoreTrailingWhitespace = false,
    bool ignoreBlankLines = false,
    bool ignoreComments = false]) {
  final m = leftTexts.length;
  final n = rightTexts.length;
  if (m == 0 || n == 0) return const <({int left, int right})>[];

  // 大块退化为按位置配对，避免 O(m²n²) 卡顿。
  if (m * n > _pairMaxCells) {
    final cnt = m < n ? m : n;
    return [for (var k = 0; k < cnt; k++) (left: k, right: k)];
  }

  final lk = leftTexts
      .map((s) => _normKey(s, ignoreCase, ignoreWhitespace, ignoreTrailingWhitespace,
          ignoreBlankLines, ignoreComments))
      .toList();
  final rk = rightTexts
      .map((s) => _normKey(s, ignoreCase, ignoreWhitespace, ignoreTrailingWhitespace,
          ignoreBlankLines, ignoreComments))
      .toList();

  final sim = List.generate(m, (_) => List<int>.filled(n, 0));
  for (var i = 0; i < m; i++) {
    for (var j = 0; j < n; j++) {
      sim[i][j] = _similarityScore(lk[i], rk[j]);
    }
  }

  // dp[i][j] = 前 i 个删除行 / 前 j 个新增行能得到的最大相似度总和
  final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      var best = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
      final s = sim[i - 1][j - 1];
      if (s >= _pairSimilarity) {
        final diag = dp[i - 1][j - 1] + s;
        if (diag > best) best = diag;
      }
      dp[i][j] = best;
    }
  }

  final pairs = <({int left, int right})>[];
  var i = m, j = n;
  while (i > 0 && j > 0) {
    final s = sim[i - 1][j - 1];
    if (s >= _pairSimilarity && dp[i][j] == dp[i - 1][j - 1] + s) {
      pairs.add((left: i - 1, right: j - 1));
      i--;
      j--;
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      i--;
    } else {
      j--;
    }
  }
  return pairs.reversed.toList();
}

/// 字符级差异：标记"两条配对的差异行"中各自被改动的字符范围。
///
/// 给 [diffLines] 出来的"连续 delete + 连续 insert"块在 UI 层做行配对后，
/// 把每对 (left, right) 喂进来：返回左字符串中"被删除/改动"的字符段，
/// 和右字符串中"被新增/改动"的字符段。range 用 [start, end) 半开区间。
class CharDiff {
  /// 在 left 字符串里被改动 / 删除的字符范围（[start, end) 半开）。
  final List<({int start, int end})> leftRanges;

  /// 在 right 字符串里被改动 / 新增的字符范围（[start, end) 半开）。
  final List<({int start, int end})> rightRanges;

  const CharDiff({required this.leftRanges, required this.rightRanges});
}

/// 字符级 LCS 回溯。作用在 utf16 code units 上：
/// 直接用 String.codeUnits 比较避免 emoji / 中文之类多字节字符被中间切开（Dart String
/// 索引本就是 utf16，所以 codeUnits 跟 substring 索引天然一致）。
CharDiff diffChars(String left, String right) {
  final a = left.codeUnits;
  final b = right.codeUnits;
  final m = a.length;
  final n = b.length;

  final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
  for (var i = 0; i < m; i++) {
    for (var j = 0; j < n; j++) {
      if (a[i] == b[j]) {
        dp[i + 1][j + 1] = dp[i][j] + 1;
      } else {
        dp[i + 1][j + 1] = dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
      }
    }
  }

  // 回溯收集 delete/insert 单字符位置；相邻位置合并成区间。
  final leftPos = <int>[];
  final rightPos = <int>[];
  var i = m, j = n;
  while (i > 0 && j > 0) {
    if (a[i - 1] == b[j - 1]) {
      i--;
      j--;
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      leftPos.add(i - 1);
      i--;
    } else {
      rightPos.add(j - 1);
      j--;
    }
  }
  while (i > 0) {
    leftPos.add(i - 1);
    i--;
  }
  while (j > 0) {
    rightPos.add(j - 1);
    j--;
  }

  return CharDiff(leftRanges: _mergeAdjacent(leftPos), rightRanges: _mergeAdjacent(rightPos));
}

/// 把递减的位置列表合并成连续区间。`positions` 由回溯产生，是降序排列的索引。
List<({int start, int end})> _mergeAdjacent(List<int> positions) {
  if (positions.isEmpty) return const [];
  positions.sort();
  final ranges = <({int start, int end})>[];
  var start = positions.first;
  var prev = start;
  for (var k = 1; k < positions.length; k++) {
    final p = positions[k];
    if (p == prev + 1) {
      prev = p;
    } else {
      ranges.add((start: start, end: prev + 1));
      start = p;
      prev = p;
    }
  }
  ranges.add((start: start, end: prev + 1));
  return ranges;
}

/// 一段连续的差异（相邻的 delete / insert 行聚合而成），供 UI 做导航、
/// 整块替换与「新增 / 修改 / 删除」分类。[leftStart] / [rightStart] 是块在
/// 左 / 右文本里的 0-based 起始行号（纯增块的 [leftLines] 为空，反之亦然）。
class DiffBlock {
  /// 块在左文本里的起始行号（0-based）。
  final int leftStart;

  /// 块在右文本里的起始行号（0-based）。
  final int rightStart;

  /// 被删除行的 0-based 行号（按出现顺序）。
  final List<int> leftLines;

  /// 被新增行的 0-based 行号（按出现顺序）。
  final List<int> rightLines;

  /// 相似度配对结果：**在本块 [leftLines] / [rightLines] 里的下标**。
  /// 只有它非空，块才算「修改」块；未出现在配对里的行分别算纯删除 / 纯新增。
  final List<({int left, int right})> pairs;

  const DiffBlock({
    required this.leftStart,
    required this.rightStart,
    required this.leftLines,
    required this.rightLines,
    this.pairs = const <({int left, int right})>[],
  });

  /// 存在相似度配对的行 —— 视为「修改」块。
  bool get isModify => pairs.isNotEmpty;

  /// 左右配对（同行修改）的行数。
  int get pairedCount => pairs.length;

  /// 本块第 [i] 个删除行（[leftLines] 下标）配对到的新增行下标；未配对返回 null。
  int? rightLocalOfLeft(int i) {
    for (final p in pairs) {
      if (p.left == i) return p.right;
    }
    return null;
  }

  /// 本块第 [j] 个新增行（[rightLines] 下标）配对到的删除行下标；未配对返回 null。
  int? leftLocalOfRight(int j) {
    for (final p in pairs) {
      if (p.right == j) return p.left;
    }
    return null;
  }
}

/// 把 [diffLines] 的结果按「连续的差异行」聚合为一个个 [DiffBlock]，并对每个
/// 块内做相似度配对（[ignoreCase] / [ignoreWhitespace] 一起参与配对判定）。
/// 这是 UI 侧「新增 / 修改 / 删除」分类与上一处 / 下一处导航的唯一真源。
List<DiffBlock> buildDiffBlocks(List<LineDiff> diffs,
    {bool ignoreCase = false,
    bool ignoreWhitespace = false,
    bool ignoreTrailingWhitespace = false,
    bool ignoreBlankLines = false,
    bool ignoreComments = false}) {
  final blocks = <DiffBlock>[];
  List<int>? leftLines;
  List<int>? rightLines;
  List<String>? leftTexts;
  List<String>? rightTexts;
  int? leftStart;
  int? rightStart;
  var li = 0, ri = 0;

  void flush() {
    if (leftLines != null) {
      final pairs = _pairLines(leftTexts ?? const [], rightTexts ?? const [],
          ignoreCase, ignoreWhitespace, ignoreTrailingWhitespace, ignoreBlankLines,
          ignoreComments);
      blocks.add(DiffBlock(
        leftStart: leftStart!,
        rightStart: rightStart!,
        leftLines: leftLines!,
        rightLines: rightLines!,
        pairs: pairs,
      ));
    }
    leftLines = null;
    rightLines = null;
    leftTexts = null;
    rightTexts = null;
    leftStart = null;
    rightStart = null;
  }

  for (final d in diffs) {
    switch (d.type) {
      case LineDiffType.equal:
        flush();
        li++;
        ri++;
      case LineDiffType.delete:
        leftLines ??= <int>[];
        rightLines ??= <int>[];
        leftTexts ??= <String>[];
        rightTexts ??= <String>[];
        leftStart ??= li;
        rightStart ??= ri;
        leftLines!.add(li);
        leftTexts!.add(d.text);
        li++;
      case LineDiffType.insert:
        leftLines ??= <int>[];
        rightLines ??= <int>[];
        leftTexts ??= <String>[];
        rightTexts ??= <String>[];
        leftStart ??= li;
        rightStart ??= ri;
        rightLines!.add(ri);
        rightTexts!.add(d.text);
        ri++;
    }
  }
  flush();
  return blocks;
}

/// 对比统计：新增 / 删除 / 修改（修改 = 块内相似度配对成功的行数）。
class DiffStats {
  final int added;
  final int deleted;
  final int modified;

  const DiffStats({required this.added, required this.deleted, required this.modified});

  bool get identical => added == 0 && deleted == 0 && modified == 0;
}

DiffStats diffStats(List<DiffBlock> blocks) {
  var added = 0, deleted = 0, modified = 0;
  for (final b in blocks) {
    final paired = b.pairedCount;
    modified += paired;
    added += b.rightLines.length - paired;
    deleted += b.leftLines.length - paired;
  }
  return DiffStats(added: added, deleted: deleted, modified: modified);
}

/// 对齐行的类型（用于「并排对齐视图」）。
enum DiffRowType { equal, modified, added, deleted }

/// 「并排对齐视图」的一行：左右各一格，缺失侧为 null（对应空白占位）。
class DiffRow {
  final DiffRowType type;
  final int? leftLine; // 1-based
  final String? leftText;
  final int? rightLine; // 1-based
  final String? rightText;

  /// 非 null 表示这是「折叠未变区域」的摘要行：值是它所代表的原始行区间起点
  /// （在未折叠的行列表里的下标），点击它即展开这一段。见 UI 侧 `_visibleRows`。
  final int? foldFrom;

  const DiffRow(this.type, this.leftLine, this.leftText, this.rightLine, this.rightText,
      {this.foldFrom});

  /// 是否是「N 行未变」的折叠摘要行（可点击展开）。
  bool get isFold => foldFrom != null;
}

/// 把两段文本转成**逐行对齐**的行列表：equal 同行；一段删除 + 一段新增按**相似度**
/// 配对成 modified，没配上的行分别作为 deleted / added。用来渲染左右行号对齐的
/// 并排视图，解决「各显示自己行号、多段差异看不出对应关系」的问题。
List<DiffRow> alignedDiffRows(String left, String right,
    {bool ignoreCase = false,
    bool ignoreWhitespace = false,
    bool ignoreTrailingWhitespace = false,
    bool ignoreBlankLines = false,
    bool ignoreComments = false}) {
  final diffs = diffLines(left, right,
      ignoreCase: ignoreCase,
      ignoreWhitespace: ignoreWhitespace,
      ignoreTrailingWhitespace: ignoreTrailingWhitespace,
      ignoreBlankLines: ignoreBlankLines,
      ignoreComments: ignoreComments);
  final rows = <DiffRow>[];
  var i = 0;
  while (i < diffs.length) {
    final d = diffs[i];
    if (d.type == LineDiffType.equal) {
      rows.add(DiffRow(DiffRowType.equal, d.leftLine, d.text, d.rightLine, d.text));
      i++;
      continue;
    }
    final dels = <LineDiff>[];
    final ins = <LineDiff>[];
    while (i < diffs.length && diffs[i].type == LineDiffType.delete) {
      dels.add(diffs[i]);
      i++;
    }
    while (i < diffs.length && diffs[i].type == LineDiffType.insert) {
      ins.add(diffs[i]);
      i++;
    }
    if (dels.isEmpty && ins.isEmpty) {
      i++;
      continue;
    }
    final pairs = _pairLines(
      dels.map((e) => e.text).toList(),
      ins.map((e) => e.text).toList(),
      ignoreCase,
      ignoreWhitespace,
      ignoreTrailingWhitespace,
    );
    // 按左行顺序输出：配对的算 modified，没配上的算 deleted；右侧未配对的算 added。
    final leftToRight = <int, int>{for (final p in pairs) p.left: p.right};
    final pairedRight = <int>{for (final p in pairs) p.right};
    for (var k = 0; k < dels.length; k++) {
      final r = leftToRight[k];
      if (r != null) {
        rows.add(DiffRow(DiffRowType.modified, dels[k].leftLine, dels[k].text, ins[r].rightLine, ins[r].text));
      } else {
        rows.add(DiffRow(DiffRowType.deleted, dels[k].leftLine, dels[k].text, null, null));
      }
    }
    for (var k = 0; k < ins.length; k++) {
      if (pairedRight.contains(k)) continue;
      rows.add(DiffRow(DiffRowType.added, null, null, ins[k].rightLine, ins[k].text));
    }
  }
  return rows;
}


/// 把**连续未变**的行折叠成一行摘要（对标 VS Code 的 Fold Unchanged Regions）。
///
/// - 连续等值行超过 [threshold] 才折；
/// - [expanded] 里存的是「被折叠段在未折叠列表里的起始下标」，用户可以逐段展开；
/// - 摘要文案由 [label] 给（引擎不碰 i18n）。
///
/// 返回的新列表里，折叠行是 `DiffRow(equal, null, label, null, label, foldFrom: 起点)`，
/// UI 侧靠 `DiffRow.isFold` / `DiffRow.foldFrom` 判断并可点击展开。
List<DiffRow> foldUnchangedRuns(
  List<DiffRow> rows, {
  int threshold = 6,
  Set<int> expanded = const {},
  required String Function(int count) label,
}) {
  final out = <DiffRow>[];
  var i = 0;
  while (i < rows.length) {
    if (rows[i].type != DiffRowType.equal) {
      out.add(rows[i]);
      i++;
      continue;
    }
    var j = i;
    while (j < rows.length && rows[j].type == DiffRowType.equal) {
      j++;
    }
    final count = j - i;
    if (count > threshold && !expanded.contains(i)) {
      final text = label(count);
      out.add(DiffRow(DiffRowType.equal, null, text, null, text, foldFrom: i));
    } else {
      out.addAll(rows.sublist(i, j));
    }
    i = j;
  }
  return out;
}

// ==================== 三方合并 ====================

/// 三方合并里某个变更区的取值来源。
enum MergeChoice {
  /// 用「我的」这一版。
  mine,

  /// 用「他的」这一版。
  theirs,

  /// 两边都不采纳，保留基线内容。
  base,
}

/// 三方合并（base / mine / theirs）里的一**个变更区**：基线行区间
/// `[baseStart, baseEnd)` 分别被 my / theirs 换成 [mineLines] / [theirsLines]。
///
/// 与 git 的 hunk 同义：只覆盖「至少一侧改过」的行段，未改动的部分不进这个列表。
class MergeRegion {
  /// 基线起始行号（0-based，含）。
  final int baseStart;

  /// 基线结束行号（0-based，不含）。纯插入时 `baseStart == baseEnd`。
  final int baseEnd;

  /// 基线在该区间的原始行。
  final List<String> baseLines;

  /// 「我的」在该区间对应的行（已含我在区间内的插入 / 排除我的删除）。
  final List<String> mineLines;

  /// 「他的」在该区间对应的行。
  final List<String> theirsLines;

  /// 用户当前的选择。冲突区默认取 [MergeChoice.mine]，方便「先全用我的、再逐条改」。
  MergeChoice choice;

  MergeRegion({
    required this.baseStart,
    required this.baseEnd,
    required this.baseLines,
    required this.mineLines,
    required this.theirsLines,
    MergeChoice? choice,
  }) : choice = choice ?? MergeChoice.mine;

  /// 我在这个区间里改过内容。
  bool get mineChanged => !sameLineLists(mineLines, baseLines);

  /// 他在这区间里改过内容。
  bool get theirsChanged => !sameLineLists(theirsLines, baseLines);

  /// 两侧都改、且改成了不同结果 —— 需要人工决策。
  bool get conflict => mineChanged && theirsChanged && !sameLineLists(mineLines, theirsLines);

  /// 不需要人工决策（只一侧改，或两侧改成了同一个结果）。
  bool get autoResolved => !conflict;

  /// 本区最终会输出的行。
  List<String> get chosenLines => switch (choice) {
        MergeChoice.mine => mineLines,
        MergeChoice.theirs => theirsLines,
        MergeChoice.base => baseLines,
      };
}

/// [mergeThreeWay] 的结果。
class MergeResult {
  /// 基线全文按 `\n` 切出的行。
  final List<String> baseLines;
  final List<String> mineLines;
  final List<String> theirsLines;

  /// 全部变更区，按 [MergeRegion.baseStart] 升序、互不重叠。
  final List<MergeRegion> regions;

  const MergeResult({
    required this.baseLines,
    required this.mineLines,
    required this.theirsLines,
    required this.regions,
  });

  /// 需要人工决策的区数。
  int get conflicts => regions.where((r) => r.conflict).length;

  /// 自动解决的区数。
  int get autoCount => regions.length - conflicts;

  bool get hasConflict => conflicts > 0;

  /// 按当前选择拼出合并结果。
  ///
  /// [markers] 为 true 时冲突区输出 git 风格的 `<<<<<<< / ======= / >>>>>>>` 标记，
  /// 方便丢给外部工具或人工二次处理；否则直接输出所选内容。
  String compose({bool markers = false}) {
    final out = <String>[];
    var cursor = 0;
    for (final r in regions) {
      if (r.baseStart > cursor) out.addAll(baseLines.sublist(cursor, r.baseStart));
      if (markers && r.conflict) {
        out.add('<<<<<<< mine');
        out.addAll(r.mineLines);
        out.add('=======');
        out.addAll(r.theirsLines);
        out.add('>>>>>>> theirs');
      } else {
        out.addAll(r.chosenLines);
      }
      cursor = r.baseEnd;
    }
    if (cursor < baseLines.length) out.addAll(baseLines.sublist(cursor));
    return out.join('\n');
  }
}

/// 两个行列表内容完全相同（逐行比较）。
bool sameLineLists(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 取「基线区间 `[s, e]` 在这一侧对应的行」。
///
/// 闭区间是刻意的：`e` 端点上的**纯插入**属于本区间（例如「删掉 b、换成 X」这种
/// 改动块，删除是 `[1,2)`、插入点在边界 2，若按半开区间就会把 X 丢掉）。
/// 相邻区间在 [mergeThreeWay] 里已经先合并成一个，所以不会被两个区间重复收集。
List<String> _mapRange(List<LineDiff> diffs, int s, int e) {
  final out = <String>[];
  var b = 0;
  for (final d in diffs) {
    switch (d.type) {
      case LineDiffType.equal:
        if (b >= s && b < e) out.add(d.text);
        b++;
      case LineDiffType.delete:
        // 该基线行在自己这一侧被删掉，不进结果（但基线游标要前进）。
        b++;
      case LineDiffType.insert:
        if (b >= s && b <= e) out.add(d.text);
    }
  }
  return out;
}

/// 三方合并（对标 git merge-file / WinMerge 三栏 / KDiff3 / Meld）。
///
/// 做法：分别求 `base→mine`、`base→theirs` 的变更块，按**基线行区间**把两侧的
/// 变更对齐；区间重叠或首尾相接的合成一个 [MergeRegion]。每区再用内容比较判定
/// 「只一侧改 / 两侧改成同一结果 / 真冲突」。
///
/// 这是 diff3 的常用简化实现：不追求与 git 逐字节一致（git 还做行内合并），
/// 但对「同一处被两边分别改过」的冲突判定是等价的，足够用于人工合并。
MergeResult mergeThreeWay(String base, String mine, String theirs,
    {bool ignoreCase = false, bool ignoreWhitespace = false}) {
  final baseLines = base.split('\n');
  final mineLines = mine.split('\n');
  final theirsLines = theirs.split('\n');

  final diffsM = diffLines(base, mine, ignoreCase: ignoreCase, ignoreWhitespace: ignoreWhitespace);
  final diffsT = diffLines(base, theirs, ignoreCase: ignoreCase, ignoreWhitespace: ignoreWhitespace);

  final spans = <({int start, int end})>[];
  for (final b in buildDiffBlocks(diffsM, ignoreCase: ignoreCase, ignoreWhitespace: ignoreWhitespace)) {
    spans.add((start: b.leftStart, end: b.leftStart + b.leftLines.length));
  }
  for (final b in buildDiffBlocks(diffsT, ignoreCase: ignoreCase, ignoreWhitespace: ignoreWhitespace)) {
    spans.add((start: b.leftStart, end: b.leftStart + b.leftLines.length));
  }
  if (spans.isEmpty) {
    return MergeResult(
        baseLines: baseLines, mineLines: mineLines, theirsLines: theirsLines, regions: const []);
  }

  spans.sort((a, b) => a.start != b.start ? a.start.compareTo(b.start) : a.end.compareTo(b.end));
  final merged = <({int start, int end})>[];
  for (final sp in spans) {
    if (merged.isEmpty) {
      merged.add(sp);
      continue;
    }
    final last = merged.last;
    // 重叠、或首尾相接（含纯插入点落在边界上）都并成一区。
    if (sp.start <= last.end) {
      merged[merged.length - 1] = (start: last.start, end: sp.end > last.end ? sp.end : last.end);
    } else {
      merged.add(sp);
    }
  }

  final regions = <MergeRegion>[];
  for (final m in merged) {
    final s = m.start.clamp(0, baseLines.length);
    final e = m.end.clamp(s, baseLines.length);
    final region = MergeRegion(
      baseStart: s,
      baseEnd: e,
      baseLines: baseLines.sublist(s, e),
      mineLines: _mapRange(diffsM, s, e),
      theirsLines: _mapRange(diffsT, s, e),
    );
    // 只有「他」改过时默认取「他」——否则自动合并会把他的改动整段丢掉。
    if (!region.mineChanged && region.theirsChanged) region.choice = MergeChoice.theirs;
    regions.add(region);
  }

  return MergeResult(
      baseLines: baseLines, mineLines: mineLines, theirsLines: theirsLines, regions: regions);
}
