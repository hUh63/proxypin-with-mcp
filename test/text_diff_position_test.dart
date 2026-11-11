// 「按行号对齐」：不做内容匹配，左第 i 行直接对右第 i 行。
// 它的价值就在于「插一行不会把下面全部挪位」，所以每条用例都锁住行号关系。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_diff.dart';

void main() {
  group('diffLinesByPosition', () {
    test('行数相同、部分行改动', () {
      final diffs = diffLinesByPosition('a\nb\nc', 'a\nB\nc');
      // 中间一行输出成相邻的 delete + insert（交给 blocks 配对成「修改」）
      expect(diffs.length, 4);
      expect(diffs[0].type, LineDiffType.equal);
      expect(diffs[1].type, LineDiffType.delete);
      expect(diffs[1].leftLine, 2);
      expect(diffs[2].type, LineDiffType.insert);
      expect(diffs[2].rightLine, 2);
      expect(diffs[3].type, LineDiffType.equal);
    });

    test('左侧多一行：多出来的算删除，且不移动其它行的行号', () {
      final diffs = diffLinesByPosition('a\nb\nc', 'a\nc');
      // 按行号对齐时 b(第2行) 对 c(第2行) → 不相同 → 修改；第 3 行左边有右边没有 → 删除
      final stats = diffStats(buildDiffBlocks(diffs));
      expect(stats.deleted, 1);
      // 关键：第 3 行的右行号不存在，但左边的 a/c 位置没被挪动
      expect(diffs.first.leftLine, 1);
      expect(diffs.last.type, LineDiffType.delete);
      expect(diffs.last.leftLine, 3);
    });

    test('内容对齐会把下面整段挪位，按行号不会', () {
      const a = 'head\nx\ny\nz\ntail';
      const b = 'head\nNEW\nx\ny\nz\ntail';
      // 内容对齐：只多了一行，全部其它行仍然是 equal
      final byContent = diffStats(buildDiffBlocks(diffLines(a, b)));
      expect(byContent.added, 1);
      // 按行号：从第 2 行起全部错位，每一行都算「改」
      final byPos = diffStats(buildDiffBlocks(diffLinesByPosition(a, b)));
      expect(byPos.added, 1);
      expect(byPos.modified, greaterThanOrEqualTo(3));
    });

    test('完全相同时全是 equal', () {
      final diffs = diffLinesByPosition('a\nb\nc', 'a\nb\nc');
      expect(diffs.every((d) => d.type == LineDiffType.equal), isTrue);
      expect(diffs.length, 3);
    });

    test('CRLF 与 LF 同内容不算差异', () {
      final diffs = diffLinesByPosition('a\r\nb\r\n', 'a\nb\n');
      expect(diffs.every((d) => d.type == LineDiffType.equal), isTrue);
    });

    test('忽略大小写 / 行尾空白同样生效', () {
      final diffs = diffLinesByPosition('Foo  \nbar', 'foo\nBAR',
          ignoreCase: true, ignoreTrailingWhitespace: true);
      expect(diffs.every((d) => d.type == LineDiffType.equal), isTrue);
    });

    test('空文本与单侧空文本不崩', () {
      expect(diffLinesByPosition('', '').length, 1); // 一行空行
      final diffs = diffLinesByPosition('a\nb', '');
      expect(diffs.where((d) => d.type == LineDiffType.delete).length, 2);
    });
  });

  group('alignedDiffRows(alignByLine: true)', () {
    test('行号严格一一对应', () {
      // 用有共同前缀的行：「修改」是靠相似度配对判出来的，单字符行 'b' vs 'B' 相似度为 0，
      // 引擎会当成「删一行 + 加一行」，那样测的就不是行号对应了。
      final rows = alignedDiffRows('a\nvalue=1\nc', 'a\nvalue=2\nc', alignByLine: true);
      expect(rows.length, 3);
      expect(rows[0].type, DiffRowType.equal);
      expect(rows[1].type, DiffRowType.modified);
      expect(rows[1].leftLine, 2);
      expect(rows[1].rightLine, 2);
      expect(rows[2].type, DiffRowType.equal);
    });

    test('一侧更长时，多出来的行单独成行（不串位）', () {
      final rows = alignedDiffRows('a\nb\nc\nd', 'a\nb', alignByLine: true);
      expect(rows.length, 4);
      expect(rows[0].leftLine, 1);
      expect(rows[1].leftLine, 2);
      expect(rows[2].type, DiffRowType.deleted);
      expect(rows[2].leftLine, 3);
      expect(rows[2].rightLine, isNull);
      expect(rows[3].leftLine, 4);
    });
  });
}
