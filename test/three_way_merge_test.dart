import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_diff.dart';

void main() {
  group('mergeThreeWay', () {
    test('只「我的」改过 → 自动取我的', () {
      const base = 'a\nb\nc';
      const mine = 'a\nB\nc';
      const theirs = 'a\nb\nc';
      final r = mergeThreeWay(base, mine, theirs);
      expect(r.regions, hasLength(1));
      expect(r.regions.first.conflict, isFalse);
      expect(r.regions.first.choice, MergeChoice.mine);
      expect(r.compose(), 'a\nB\nc');
      expect(r.conflicts, 0);
    });

    test('只「他的」改过 → 自动取他的', () {
      const base = 'a\nb\nc';
      const mine = 'a\nb\nc';
      const theirs = 'a\nb\nC';
      final r = mergeThreeWay(base, mine, theirs);
      expect(r.regions.first.conflict, isFalse);
      expect(r.compose(), 'a\nb\nC');
    });

    test('两侧改不同位置 → 两处都生效', () {
      const base = '1\n2\n3\n4\n5';
      const mine = 'ONE\n2\n3\n4\n5';
      const theirs = '1\n2\n3\n4\nFIVE';
      final r = mergeThreeWay(base, mine, theirs);
      expect(r.conflicts, 0);
      expect(r.regions, hasLength(2));
      expect(r.compose(), 'ONE\n2\n3\n4\nFIVE');
    });

    test('两侧同位置改成同一结果 → 不算冲突', () {
      const base = 'a\nb\nc';
      const mine = 'a\nX\nc';
      const theirs = 'a\nX\nc';
      final r = mergeThreeWay(base, mine, theirs);
      expect(r.conflicts, 0);
      expect(r.regions, hasLength(1));
      expect(r.compose(), 'a\nX\nc');
    });

    test('两侧同位置改成不同结果 → 冲突，默认取我的', () {
      const base = 'a\nb\nc';
      const mine = 'a\nMINE\nc';
      const theirs = 'a\nTHEIRS\nc';
      final r = mergeThreeWay(base, mine, theirs);
      expect(r.conflicts, 1);
      expect(r.regions.first.conflict, isTrue);
      expect(r.compose(), 'a\nMINE\nc');
      // 切到他的
      r.regions.first.choice = MergeChoice.theirs;
      expect(r.compose(), 'a\nTHEIRS\nc');
      // 保留基线
      r.regions.first.choice = MergeChoice.base;
      expect(r.compose(), 'a\nb\nc');
    });

    test('同一位置的纯插入冲突', () {
      const base = 'a\nc';
      const mine = 'a\nfrom-mine\nc';
      const theirs = 'a\nfrom-theirs\nc';
      final r = mergeThreeWay(base, mine, theirs);
      expect(r.conflicts, 1);
      expect(r.regions.first.baseStart, 1);
      expect(r.regions.first.baseEnd, 1);
      expect(r.compose(), 'a\nfrom-mine\nc');
      r.regions.first.choice = MergeChoice.theirs;
      expect(r.compose(), 'a\nfrom-theirs\nc');
      // 选基线 = 两边插入都不要
      r.regions.first.choice = MergeChoice.base;
      expect(r.compose(), 'a\nc');
    });

    test('一方删除、另一方修改同一行 → 冲突', () {
      const base = 'a\nb\nc';
      const mine = 'a\nc';
      const theirs = 'a\nB-changed\nc';
      final r = mergeThreeWay(base, mine, theirs);
      expect(r.conflicts, 1);
      expect(r.compose(), 'a\nc'); // 默认取我的 = 删除
      r.regions.first.choice = MergeChoice.theirs;
      expect(r.compose(), 'a\nB-changed\nc');
    });

    test('两侧在不同位置追加 → 顺序保持基线顺序', () {
      const base = 'head\ntail';
      const mine = 'head\nmine-line\ntail';
      const theirs = 'head\ntail\ntheirs-line';
      final r = mergeThreeWay(base, mine, theirs);
      expect(r.conflicts, 0);
      expect(r.compose(), 'head\nmine-line\ntail\ntheirs-line');
    });

    test('三方完全一致 → 没有变更区，compose 等于原文', () {
      const base = 'x\ny';
      final r = mergeThreeWay(base, base, base);
      expect(r.regions, isEmpty);
      expect(r.compose(), base);
    });

    test('冲突标记导出（git 风格）', () {
      const base = 'a\nb\nc';
      const mine = 'a\nMINE\nc';
      const theirs = 'a\nTHEIRS\nc';
      final r = mergeThreeWay(base, mine, theirs);
      final marked = r.compose(markers: true);
      expect(marked, contains('<<<<<<< mine'));
      expect(marked, contains('======='));
      expect(marked, contains('>>>>>>> theirs'));
      expect(marked, contains('MINE'));
      expect(marked, contains('THEIRS'));
    });

    test('非冲突区在 markers 模式下仍输出所选内容', () {
      const base = '1\n2\n3';
      const mine = '1\n2\nTHREE';
      const theirs = '1\n2\n3';
      final r = mergeThreeWay(base, mine, theirs);
      expect(r.compose(markers: true), '1\n2\nTHREE');
    });

    test('忽略空白后两侧一致 → 视为未改动，保留基线', () {
      const base = 'a\nb\nc';
      const mine = 'a\n  b  \nc';
      const theirs = 'a\n\tb\nc';
      final r = mergeThreeWay(base, mine, theirs, ignoreWhitespace: true);
      expect(r.conflicts, 0);
      // 忽略空白 = 两边都「没改」，所以没有变更区，compose 就是基线原文。
      expect(r.regions, isEmpty);
      expect(r.compose(), 'a\nb\nc');
    });

    test('忽略空白时「我的」有实质改动 → 输出我这一版原文', () {
      const base = 'a\nb\nc';
      const mine = 'a\n  B  \nc';
      const theirs = 'a\nb\nc';
      final r = mergeThreeWay(base, mine, theirs, ignoreWhitespace: true);
      expect(r.conflicts, 0);
      // 输出的是「我」这一版原文（含它的空白），不会把空白吃掉。
      expect(r.compose(), 'a\n  B  \nc');
    });
  });
}

/// 非冲突区在 markers 模式下仍输出所选内容（补充：多区混合）。
