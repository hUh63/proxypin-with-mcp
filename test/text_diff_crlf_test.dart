// CRLF / LF 混用的文件：Windows 与 macOS 之间传文件时最常踩。
// 比较键早就把行尾 \r 剥掉了，但「显示文本」与「字符级高亮」拿到的是原始行，
// 于是同内容的两行会多出一个不可见字符、还可能被标成「改动了最后一个字符」。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_diff.dart';

void main() {
  group('行尾 CRLF', () {
    test('同内容 CRLF vs LF 不算差异', () {
      final diffs = diffLines('a\r\nb\r\nc\r\n', 'a\nb\nc\n');
      expect(diffs.every((d) => d.type == LineDiffType.equal), isTrue);
      final blocks = buildDiffBlocks(diffs);
      expect(blocks, isEmpty);
    });

    test('显示文本不带 \\r', () {
      final rows = alignedDiffRows('a\r\nb\r\n', 'a\nb\n');
      expect(rows.length, greaterThanOrEqualTo(2));
      for (final r in rows) {
        expect(r.leftText ?? '', isNot(contains('\r')));
        expect(r.rightText ?? '', isNot(contains('\r')));
      }
    });

    test('内容真不同时仍能识别', () {
      final diffs = diffLines('a\r\nb\r\n', 'a\nB\n');
      final stats = diffStats(buildDiffBlocks(diffs));
      expect(stats.modified, 1);
    });

    test('行数不变（剥 \\r 不影响索引）', () {
      final rows = alignedDiffRows('x\r\ny\nz\r\n', 'x\r\ny\nz\r\n');
      expect(rows.length, 3);
      expect(rows[0].leftLine, 1);
      expect(rows[2].leftLine, 3);
    });

    test('混合换行：一侧 CRLF 一侧 LF 且中间有新增行', () {
      final diffs = diffLines('a\r\nc\r\n', 'a\nb\nc\n');
      final stats = diffStats(buildDiffBlocks(diffs));
      expect(stats.added, 1);
      expect(stats.deleted + stats.modified, 0);
    });

    test('纯 CRLF 空行也算同一行', () {
      final diffs = diffLines('a\r\n\r\nb\r\n', 'a\n\nb\n');
      expect(diffs.every((d) => d.type == LineDiffType.equal), isTrue);
    });
  });

  group('行尾 CR 归一后合并/统一视图', () {
    test('mergeTwoWay 用右栏时保留原样行数', () {
      final diffs = diffLines('a\r\nb\r\n', 'a\nB\n');
      final blocks = buildDiffBlocks(diffs);
      final merged = mergeTwoWay(
        leftLines: const ['a\r', 'b\r'],
        rightLines: const ['a', 'B'],
        blocks: blocks,
        useRight: (i) => true,
      );
      final lines = merged.split('\n');
      expect(lines.length, 2);
      expect(lines[1], 'B');
    });

    test('mergeTwoWay 用左栏时保留左侧原文（含 \\r）', () {
      final diffs = diffLines('a\r\nb\r\n', 'a\nB\n');
      final blocks = buildDiffBlocks(diffs);
      final merged = mergeTwoWay(
        leftLines: const ['a\r', 'b\r'],
        rightLines: const ['a', 'B'],
        blocks: blocks,
        useRight: (i) => false,
      );
      expect(merged.split('\n')[1], 'b\r');
    });
  });
}
