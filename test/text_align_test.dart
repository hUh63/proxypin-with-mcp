// 行整理：对齐 / 删空行 / 合并空行。算错就是整篇缩进乱掉，所以逐条锁用例。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_align.dart';

void main() {
  group('alignByDelimiter', () {
    test('按 = 对齐', () {
      const src = 'a = 1\nlongName = 2\nb = 3';
      expect(alignByDelimiter(src), 'a        = 1\nlongName = 2\nb        = 3');
    });

    test('保留缩进', () {
      const src = '  a = 1\n  bb = 2';
      expect(alignByDelimiter(src), '  a  = 1\n  bb = 2');
    });

    test('没有可对齐的行时原样返回', () {
      const src = 'a\nb\nc';
      expect(alignByDelimiter(src), src);
    });

    test('优先用 => 而不是 =', () {
      const src = 'x => 1\nyyy => 2';
      expect(alignByDelimiter(src), 'x   => 1\nyyy => 2');
    });

    test('跳过冒号开头的行（不把行首空前缀算进去）', () {
      const src = ': bad\nk: v\nkk: v';
      expect(alignByDelimiter(src), ': bad\nk  : v\nkk : v');
    });

    test('空行原样保留', () {
      const src = 'a = 1\n\nbb = 2';
      expect(alignByDelimiter(src), 'a  = 1\n\nbb = 2');
    });

    test('注释行不参与候选判断', () {
      const src = '// note = x\nk = v';
      // 只有一行带 `=` 的非注释行 → 不构成「至少两行」 → 原样
      expect(alignByDelimiter(src), src);
    });
  });

  group('removeBlankLines', () {
    test('删掉空行与纯空白行', () {
      expect(removeBlankLines('a\n\n  \nb'), 'a\nb');
    });

    test('没有空行时不变', () {
      expect(removeBlankLines('a\nb'), 'a\nb');
    });

    test('全空时返回空串', () {
      expect(removeBlankLines('\n \n'), '');
    });
  });

  group('collapseBlankLines', () {
    test('连续空行收成一个', () {
      expect(collapseBlankLines('a\n\n\n\nb'), 'a\n\nb');
    });

    test('保留 maxKeep', () {
      expect(collapseBlankLines('a\n\n\n\nb', maxKeep: 2), 'a\n\n\nb');
    });

    test('不动结尾换行', () {
      expect(collapseBlankLines('a\nb\n'), 'a\nb\n');
    });

    test('单个空行不变', () {
      expect(collapseBlankLines('a\n\nb'), 'a\n\nb');
    });
  });
}
