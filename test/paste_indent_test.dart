import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/paste_indent.dart';

void main() {
  group('leadingBlankChars', () {
    test('空格与 Tab 都算', () {
      expect(leadingBlankChars('    abc'), 4);
      expect(leadingBlankChars('\t\tabc'), 2);
      expect(leadingBlankChars('abc'), 0);
      expect(leadingBlankChars(''), 0);
      expect(leadingBlankChars('   '), 3);
    });
  });

  group('reindentPasted', () {
    test('基线为空时原样返回', () {
      const clip = 'a\n  b';
      expect(reindentPasted(clip, ''), clip);
    });

    test('单行原样返回', () {
      expect(reindentPasted('hello', '    '), 'hello');
    });

    test('多行整体右移', () {
      const clip = 'x = 1\nif a:\n    y = 2';
      expect(reindentPasted(clip, '  '),
          'x = 1\n  if a:\n      y = 2');
    });

    test('首行不动', () {
      const clip = '  first\n  second';
      expect(reindentPasted(clip, '\t'), '  first\n\tsecond');
    });

    test('顶格内容整体右移（粘进缩进位置）', () {
      const clip = 'a\n  b\nc';
      expect(reindentPasted(clip, '    '), 'a\n      b\n    c');
    });

    test('空行不补缩进', () {
      const clip = 'a\n  b\n\n  c';
      expect(reindentPasted(clip, '  '), 'a\n  b\n\n  c');
    });

    test('Tab 缩进的内容也能被对齐', () {
      const clip = 'a\n\tb\n\tc';
      expect(reindentPasted(clip, '    '), 'a\n    b\n    c');
    });

    test('全是空行时原样返回', () {
      const clip = '\n\n\n';
      expect(reindentPasted(clip, '  '), clip);
    });

    test('公共缩进取最小值', () {
      const clip = 'a\n    b\n  c\n      d';
      expect(reindentPasted(clip, '-'), 'a\n-  b\n-c\n-    d');
    });
  });

  group('stripLineNumbers', () {
    test('冒号前缀', () {
      expect(stripLineNumbers('1: a\n2: b\n3: c'), 'a\nb\nc');
    });
    test('竖线与制表符前缀', () {
      expect(stripLineNumbers(' 1| a\n 2| b'), 'a\nb');
      expect(stripLineNumbers('1\ta\n2\tb'), 'a\nb');
    });
    test('点号前缀', () {
      expect(stripLineNumbers('1. a\n2. b'), 'a\nb');
    });
    test('保留相对缩进', () {
      expect(stripLineNumbers('12:   a\n13:     b'), '  a\n    b');
    });
    test('单行不动', () {
      expect(stripLineNumbers('1: a'), '1: a');
    });
    test('正文里的有序列表不动（不连续/占比低）', () {
      const text = '1. 第一步\n这里有一些说明\n还有更多说明\n2. 第二步';
      expect(stripLineNumbers(text), text);
    });
    test('编号不连续不动整段', () {
      const text = '1: a\n5: b\n9: c\n这里是正文\n更多正文';
      expect(stripLineNumbers(text), text);
    });
    test('无行号原样返回', () {
      expect(stripLineNumbers('a\nb'), 'a\nb');
      expect(stripLineNumbers(''), '');
    });
  });
}
