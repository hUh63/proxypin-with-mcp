import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_edit_ops.dart';

void main() {
  group('stripTrailingWhitespace', () {
    test('去掉行尾空格与制表符', () {
      expect(stripTrailingWhitespace('a  \nb\t\nc'), 'a\nb\nc');
      expect(stripTrailingWhitespace('a \t \nb'), 'a\nb');
    });

    test('保留缩进与行首空白', () {
      expect(stripTrailingWhitespace('    indented  \n\ttabbed\t'), '    indented\n\ttabbed');
    });

    test('保留 CRLF 结构（只处理行尾空白，不碰 \\r 前后）', () {
      // \r 会被当作行尾字符的一部分保留下来（换行符归一化是另一件事）
      expect(stripTrailingWhitespace('a  \r\nb'), 'a\r\nb');
    });

    test('空串与无空白文本原样返回', () {
      expect(stripTrailingWhitespace(''), '');
      expect(stripTrailingWhitespace('abc\ndef'), 'abc\ndef');
    });

    test('只有空白的行会被清空', () {
      expect(stripTrailingWhitespace('a\n   \nb'), 'a\n\nb');
    });
  });

  group('countTrailingWhitespaceLines', () {
    test('计数', () {
      expect(countTrailingWhitespaceLines('a  \nb\nc\t'), 2);
      expect(countTrailingWhitespaceLines('a\nb'), 0);
      expect(countTrailingWhitespaceLines(''), 0);
    });
  });

  group('guessIndent', () {
    test('空格缩进 → 取最小非零缩进', () {
      expect(guessIndent('  a\n    b\n  c'), (false, 2));
      expect(guessIndent('    a\n        b'), (false, 4));
    });

    test('Tab 行更多 → 用 Tab', () {
      expect(guessIndent('\ta\n\tb\n  c'), (true, 4));
    });

    test('没有缩进 → 默认 4 空格', () {
      expect(guessIndent('a\nb\nc'), (false, 4));
      expect(guessIndent(''), (false, 4));
    });

    test('缩进 1 个空格不当作 tabSize（低于 2 时回默认）', () {
      expect(guessIndent(' a\n b'), (false, 4));
    });
  });
}
