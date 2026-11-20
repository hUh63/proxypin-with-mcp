import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_diff.dart';

void main() {
  final begin = RegExp(r'^\s*//\s*GENERATED');
  final end = RegExp(r'^\s*//\s*END GENERATED');

  group('ignoredRegionLines', () {
    test('区间内（含起止行）都被忽略', () {
      const t = 'a\n// GENERATED\nx\ny\n// END GENERATED\nb';
      expect(ignoredRegionLines(t, begin, end), {1, 2, 3, 4});
    });

    test('同一行同时命中 start/end 时只忽略这一行', () {
      final b = RegExp(r'BEGIN');
      final e = RegExp(r'END');
      const t = 'a\nBEGIN END\nb';
      expect(ignoredRegionLines(t, b, e), {1});
    });

    test('end 从未出现时忽略到文件尾', () {
      const t = 'a\n// GENERATED\nx\ny';
      expect(ignoredRegionLines(t, begin, end), {1, 2, 3});
    });

    test('没有标记时为空集', () {
      expect(ignoredRegionLines('a\nb', begin, end), isEmpty);
    });

    test('空文本', () {
      expect(ignoredRegionLines('', begin, end), isEmpty);
    });

    test('多个区间', () {
      const t = '// GENERATED\nx\n// END GENERATED\nm\n// GENERATED\ny\n// END GENERATED';
      expect(ignoredRegionLines(t, begin, end), {0, 1, 2, 4, 5, 6});
    });
  });

  group('diffLines 忽略区域', () {
    test('两侧同样的模板段落视为相同', () {
      const l = 'head\n// GENERATED\nA\n// END GENERATED\ntail';
      const r = 'head\n// GENERATED\nB\n// END GENERATED\ntail';
      final d = diffLines(l, r, ignoreRegionBegin: begin, ignoreRegionEnd: end);
      expect(d.every((x) => x.type == LineDiffType.equal), isTrue);
    });

    test('只有一侧有模板段落时算差异', () {
      const l = 'head\n// GENERATED\nA\n// END GENERATED\ntail';
      const r = 'head\ntail';
      final d = diffLines(l, r, ignoreRegionBegin: begin, ignoreRegionEnd: end);
      expect(d.where((x) => x.type != LineDiffType.equal), isNotEmpty);
    });

    test('区域外的改动仍能检出', () {
      const l = 'head\n// GENERATED\nA\n// END GENERATED\ntail1';
      const r = 'head\n// GENERATED\nB\n// END GENERATED\ntail2';
      final d = diffLines(l, r, ignoreRegionBegin: begin, ignoreRegionEnd: end);
      final changed = d.where((x) => x.type != LineDiffType.equal).toList();
      expect(changed.length, 2); // tail1 删 + tail2 增（或被配对成一处修改）
      expect(changed.any((x) => x.text.contains('tail')), isTrue);
    });

    test('alignedDiffRows 透传参数', () {
      const l = 'a\n// GENERATED\nx\n// END GENERATED';
      const r = 'a\n// GENERATED\ny\n// END GENERATED';
      final rows = alignedDiffRows(l, r, ignoreRegionBegin: begin, ignoreRegionEnd: end);
      expect(rows.every((x) => x.type == DiffRowType.equal), isTrue);
    });
  });
}
