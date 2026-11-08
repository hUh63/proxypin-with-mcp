// 冲突标记识别/消解：这些函数一旦算错就会吃掉相邻的正常代码，全部锁用例。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/merge_conflicts.dart';

void main() {
  const twoWay = 'a\n'
      '<<<<<<< HEAD\n'
      'mine1\n'
      'mine2\n'
      '=======\n'
      'theirs1\n'
      '>>>>>>> feature\n'
      'b\n';

  const diff3 = 'a\n'
      '<<<<<<< HEAD\n'
      'mine\n'
      '||||||| merged common ancestors\n'
      'base1\n'
      'base2\n'
      '=======\n'
      'theirs\n'
      '>>>>>>> feature\n'
      'b\n';

  group('findConflicts', () {
    test('没标记时返回空', () {
      expect(findConflicts('a\nb\n'), isEmpty);
      expect(findConflicts(''), isEmpty);
    });

    test('两路冲突：行号与内容正确', () {
      final b = findConflicts(twoWay);
      expect(b.length, 1);
      expect(b[0].startLine, 1);
      expect(b[0].endLine, 6);
      expect(b[0].ours, ['mine1', 'mine2']);
      expect(b[0].theirs, ['theirs1']);
      expect(b[0].base, isEmpty);
      expect(b[0].label, 'HEAD');
    });

    test('三路冲突（diff3）：base 段单独取出', () {
      final b = findConflicts(diff3);
      expect(b.length, 1);
      expect(b[0].ours, ['mine']);
      expect(b[0].base, ['base1', 'base2']);
      expect(b[0].theirs, ['theirs']);
      expect(b[0].endLine, 8);
    });

    test('只有半个标记不算冲突', () {
      expect(findConflicts('<<<<<<< HEAD\nmine\n'), isEmpty);
      expect(findConflicts('=======\n标题\n'), isEmpty);
      expect(findConflicts('<<<<<<< HEAD\nmine\n=======\n'), isEmpty);
    });

    test('多个冲突块', () {
      final text = '$twoWay\n$twoWay';
      final b = findConflicts(text);
      expect(b.length, 2);
      expect(b[1].startLine, greaterThan(b[0].endLine));
    });

    test('未闭合的外层不吞掉内层', () {
      const text = '<<<<<<< HEAD\n'
          '<<<<<<< HEAD\n'
          'x\n'
          '=======\n'
          'y\n'
          '>>>>>>> b\n';
      final b = findConflicts(text);
      // 第一块（外层未闭合）被放弃，只识别出内层这一块
      expect(b.length, 1);
      expect(b[0].ours, ['x']);
      expect(b[0].theirs, ['y']);
    });

    test('缩进的标记也认', () {
      const text = '  <<<<<<< HEAD\n  a\n  =======\n  b\n  >>>>>>> x\n';
      final b = findConflicts(text);
      expect(b.length, 1);
      expect(b[0].ours, ['  a']);
    });

    test('残留的 >>>>>>> 单独出现不算', () {
      expect(findConflicts('>>>>>>> a\nb\n'), isEmpty);
    });
  });

  group('applyConflicts', () {
    test('采用当前分支', () {
      final b = findConflicts(twoWay);
      final out = applyConflicts(twoWay, b, {0: ConflictChoice.ours});
      expect(out, 'a\nmine1\nmine2\nb\n');
      expect(findConflicts(out), isEmpty);
    });

    test('采用传入分支', () {
      final b = findConflicts(twoWay);
      final out = applyConflicts(twoWay, b, {0: ConflictChoice.theirs});
      expect(out, 'a\ntheirs1\nb\n');
    });

    test('两边都留', () {
      final b = findConflicts(twoWay);
      final out = applyConflicts(twoWay, b, {0: ConflictChoice.both});
      expect(out, 'a\nmine1\nmine2\ntheirs1\nb\n');
    });

    test('三路的 base', () {
      final b = findConflicts(diff3);
      final out = applyConflicts(diff3, b, {0: ConflictChoice.base});
      expect(out, 'a\nbase1\nbase2\nb\n');
    });

    test('没选中的块保持原样', () {
      final text = '$twoWay\n$twoWay';
      final b = findConflicts(text);
      final out = applyConflicts(text, b, {1: ConflictChoice.theirs});
      expect(findConflicts(out).length, 1);
    });

    test('多个块一起消解（倒序替换不串行）', () {
      final text = 'p\n$twoWay\n$twoWay\nq\n';
      final b = findConflicts(text);
      final out = applyConflicts(text, b, {
        0: ConflictChoice.ours,
        1: ConflictChoice.theirs,
      });
      expect(findConflicts(out), isEmpty);
      expect(out, 'p\na\nmine1\nmine2\nb\n\na\ntheirs1\nb\n\nq\n');
    });

    test('末行是 >>>>>>> 时不越界', () {
      const text = '<<<<<<< H\na\n=======\nb\n>>>>>>> x';
      final b = findConflicts(text);
      final out = applyConflicts(text, b, {0: ConflictChoice.theirs});
      expect(out, 'b');
    });

    test('choices 为空时原样返回', () {
      final b = findConflicts(twoWay);
      expect(applyConflicts(twoWay, b, const {}), twoWay);
    });
  });

  test('conflictCount', () {
    expect(conflictCount('$twoWay\n$twoWay'), 2);
    expect(conflictCount('a\n'), 0);
  });
}
