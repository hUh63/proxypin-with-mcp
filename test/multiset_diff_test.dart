// 「忽略行顺序」比较：只看两侧各自多出哪几行，不关心排列。
// 每条用例都锁住「多出来的是哪几行 + 行号对不对」，因为这是这个词表/白名单场景的唯一价值。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_diff.dart';

void main() {
  group('diffAsMultiset', () {
    test('两侧完全一致', () {
      final r = diffAsMultiset(['a', 'b', 'c'], ['a', 'b', 'c']);
      expect(r.isEmpty, isTrue);
      expect(r.count, 0);
    });

    test('内容相同、顺序不同 —— 视为无差异（这正是它存在的理由）', () {
      final r = diffAsMultiset(['a', 'b', 'c'], ['c', 'a', 'b']);
      expect(r.isEmpty, isTrue);
    });

    test('左侧多一行：只有右侧没有的那条被列出来', () {
      final r = diffAsMultiset(['a', 'b', 'extra'], ['a', 'b']);
      expect(r.onlyLeft.length, 1);
      expect(r.onlyLeft.first.text, 'extra');
      expect(r.onlyLeft.first.line, 2);
      expect(r.onlyRight, isEmpty);
    });

    test('右侧多一行', () {
      final r = diffAsMultiset(['a'], ['a', 'new']);
      expect(r.onlyRight.length, 1);
      expect(r.onlyRight.first.text, 'new');
      expect(r.onlyLeft, isEmpty);
    });

    test('重复计数：左 3 次、右 1 次 → 左侧多出 2 行（取靠后的两处）', () {
      final r = diffAsMultiset(['x', 'x', 'x'], ['x']);
      expect(r.onlyLeft.length, 2);
      expect(r.onlyLeft.map((e) => e.line).toList(), <int>[1, 2]);
    });

    test('重复计数：两侧各 2 次算平', () {
      final r = diffAsMultiset(['x', 'x', 'y'], ['y', 'x', 'x']);
      expect(r.isEmpty, isTrue);
    });

    test('ignoreCase 生效', () {
      expect(diffAsMultiset(['Hello'], ['hello']).onlyLeft.length, 1);
      expect(diffAsMultiset(['Hello'], ['hello'], ignoreCase: true).isEmpty, isTrue);
    });

    test('ignoreWhitespace 生效（行内空白全抹）', () {
      expect(diffAsMultiset(['a  b'], ['a b']).onlyLeft.length, 1);
      expect(diffAsMultiset(['a  b'], ['a b'], ignoreWhitespace: true).isEmpty, isTrue);
    });

    test('空行参与比较（两侧都空 → 相同）', () {
      expect(diffAsMultiset([''], ['']).isEmpty, isTrue);
    });

    test('整侧为空', () {
      final r = diffAsMultiset(const <String>[], ['a', 'b']);
      expect(r.onlyLeft, isEmpty);
      expect(r.onlyRight.length, 2);
    });
  });
}
