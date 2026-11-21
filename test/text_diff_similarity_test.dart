import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_diff.dart';

void main() {
  test('相似度阈值影响「修改」与「删+增」的判定', () {
    final diffs = diffLines('abc', 'abd');
    final loose = buildDiffBlocks(diffs, pairSimilarity: 300);
    final strict = buildDiffBlocks(diffs, pairSimilarity: 990);
    expect(loose.first.pairs, isNotEmpty, reason: '阈值低时应配成一处修改');
    expect(strict.first.pairs, isEmpty, reason: '阈值高时应算作删除 + 新增');
  });

  test('默认阈值仍是 500‰', () {
    final diffs = diffLines('hello world', 'hello worle');
    final blocks = buildDiffBlocks(diffs);
    expect(blocks.first.pairs, isNotEmpty);
  });

  test('完全不同的行在宽松阈值下也不配对', () {
    final diffs = diffLines('aaaa', 'zzzz');
    final blocks = buildDiffBlocks(diffs, pairSimilarity: 100);
    expect(blocks.first.pairs, isEmpty);
  });
}
