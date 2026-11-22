import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_diff.dart';
import 'package:proxypin/utils/text_diff_job.dart';

String _sig(List<DiffRow> rows) =>
    rows.map((r) => '${r.type.index}:${r.leftLine}:${r.rightLine}').join(',');

void main() {
  group('复用已算好的 diffs 拼对齐行', () {
    test('与 alignedDiffRows 结果一致（含新增/删除/修改）', () {
      const a = 'line1\nline2\nline3\nline4';
      const b = 'line1\nlineX\nline3\nline4\nline5';
      final diffs = diffLines(a, b);
      final reuse = alignedRowsFromDiffs(diffs);
      final direct = alignedDiffRows(a, b);
      expect(_sig(reuse), _sig(direct));
    });

    test('相似度阈值同样生效', () {
      final diffs = diffLines('abc', 'abd');
      expect(alignedRowsFromDiffs(diffs, pairSimilarity: 300).first.type,
          DiffRowType.modified);
      expect(
          alignedRowsFromDiffs(diffs, pairSimilarity: 990)
              .map((r) => r.type)
              .toSet()
              .contains(DiffRowType.modified),
          isFalse);
    });
  });

  group('isolate 任务包', () {
    test('runDiffJob 与手工调用结果一致', () {
      const a = 'x\ny\nz';
      const b = 'x\nY\nz';
      final r = runDiffJob(const DiffJobArgs(left: a, right: b));
      final blocks = buildDiffBlocks(diffLines(a, b));
      expect(r.blocks.length, blocks.length);
      expect(r.stats.modified, diffStats(blocks).modified);
    });

    test('alignByLine 走按行号对齐', () {
      const a = 'a\nb\nc';
      const b = 'a\nc';
      final r = runDiffJob(const DiffJobArgs(left: a, right: b, alignByLine: true));
      expect(r.blocks, isNotEmpty);
    });

    test('非法正则被静默忽略而不是抛', () {
      final r = runDiffJob(
          const DiffJobArgs(left: 'a\nb', right: 'a\nc', ignoreLinePattern: '['));
      expect(r.blocks, isNotEmpty);
    });

    test('搬家识别只在两行以上时才配对', () {
      // 两行内容整体挪到文件末尾：LCS 会优先匹配更长的 X/Y/Z，
      // 于是产生「纯删 2 行 + 纯增 2 行」，这才符合「搬家」的判据。
      const a = 'move1\nmove2\nX\nY\nZ';
      const b = 'X\nY\nZ\nmove1\nmove2';
      final r = runDiffJob(const DiffJobArgs(left: a, right: b));
      expect(r.movedEnds, isNotEmpty);
    });

    test('单行搬移不标记（误报率太高）', () {
      const a = 'm\nX\nY\nZ';
      const b = 'X\nY\nZ\nm';
      final r = runDiffJob(const DiffJobArgs(left: a, right: b));
      expect(r.movedEnds, isEmpty);
    });

    test('map 入口与直接构造等价', () {
      final fromMap = runDiffJobFromMap({
        'left': 'a\nb',
        'right': 'a\nc',
        'pairSimilarity': 300,
      });
      final direct = runDiffJob(
          const DiffJobArgs(left: 'a\nb', right: 'a\nc', pairSimilarity: 300));
      expect(fromMap.stats.modified, direct.stats.modified);
      expect(fromMap.blocks.length, direct.blocks.length);
    });
  });
}
