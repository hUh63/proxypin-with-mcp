import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_diff.dart';

/// 造一批对齐行：`equal` 用同一行文本，`modified` 左右不同。
List<DiffRow> buildRows(List<String> kinds) {
  final rows = <DiffRow>[];
  var line = 1;
  for (final k in kinds) {
    switch (k) {
      case 'e':
        rows.add(DiffRow(DiffRowType.equal, line, 'same', line, 'same'));
        line++;
      case 'm':
        rows.add(DiffRow(DiffRowType.modified, line, 'left', line, 'right'));
        line++;
      case 'a':
        rows.add(DiffRow(DiffRowType.added, null, null, line, 'added'));
        line++;
      case 'd':
        rows.add(DiffRow(DiffRowType.deleted, line, 'deleted', null, null));
        line++;
    }
  }
  return rows;
}

void main() {
  group('foldUnchangedRuns', () {
    String label(int n) => '⋯ $n lines';

    test('短段不折叠', () {
      final rows = buildRows(['e', 'e', 'm', 'e', 'e']);
      final folded = foldUnchangedRuns(rows, threshold: 6, label: label);
      expect(folded.length, rows.length);
      expect(folded.every((r) => !r.isFold), isTrue);
    });

    test('长段折叠成一行摘要，并记录起点', () {
      final rows = buildRows(['e', 'e', 'e', 'e', 'e', 'e', 'e', 'm']);
      final folded = foldUnchangedRuns(rows, threshold: 6, label: label);
      expect(folded.first.isFold, isTrue);
      expect(folded.first.foldFrom, 0);
      expect(folded.first.leftText, '⋯ 7 lines');
      // 摘要行后面就是那条 modified
      expect(folded[1].type, DiffRowType.modified);
    });

    test('展开过的段不再折叠', () {
      final rows = buildRows(['e', 'e', 'e', 'e', 'e', 'e', 'e', 'm']);
      final folded = foldUnchangedRuns(rows, threshold: 6, expanded: {0}, label: label);
      expect(folded.length, rows.length);
      expect(folded.any((r) => r.isFold), isFalse);
    });

    test('差异行原样保留，不被合并', () {
      final rows = buildRows(['m', 'a', 'd', 'm']);
      final folded = foldUnchangedRuns(rows, threshold: 6, label: label);
      expect(folded.length, 4);
      expect(folded.map((r) => r.type).toList(), [
        DiffRowType.modified,
        DiffRowType.added,
        DiffRowType.deleted,
        DiffRowType.modified,
      ]);
    });

    test('多段同时折叠，起点各不相同', () {
      final rows = buildRows([
        'e', 'e', 'e', 'e', 'e', 'e', 'e', // 0..6 折叠
        'm', // 7
        'e', 'e', 'e', 'e', 'e', 'e', 'e', 'e', // 8..15 折叠
        'm', // 16
      ]);
      final folded = foldUnchangedRuns(rows, threshold: 6, label: label);
      final folds = folded.where((r) => r.isFold).toList();
      expect(folds, hasLength(2));
      expect(folds[0].foldFrom, 0);
      expect(folds[1].foldFrom, 8);
    });

    test('空列表与全等值列表', () {
      expect(foldUnchangedRuns(const <DiffRow>[], label: label), isEmpty);
      final rows = buildRows(['e', 'e', 'e']);
      final folded = foldUnchangedRuns(rows, threshold: 2, label: label);
      expect(folded, hasLength(1));
      expect(folded.first.isFold, isTrue);
    });
  });
}
