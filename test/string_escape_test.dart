// 转义/反转义：这一对函数一旦不对称，用户粘出来的字面量就是坏的，
// 而且坏得很隐蔽（多一个反斜杠编译能过、运行结果错）。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/string_escape.dart';

void main() {
  group('escapeText', () {
    test('C 风格：换行 / 引号 / 反斜杠', () {
      expect(escapeText('a\nb"c\\d'), r'"a\nb\"c\\d"');
    });

    test('制表符与回车', () {
      expect(escapeText('a\tb\r'), r'"a\tb\r"');
    });

    test('JSON 方言', () {
      expect(escapeText('a\tb', dialect: EscapeDialect.json), r'"a\tb"');
    });

    test('SQL：单引号双写，不转义反斜杠', () {
      expect(escapeText("it's a\\b", dialect: EscapeDialect.sql), "it''s a\\b");
    });

    test('正则元字符', () {
      expect(escapeText('a.b*c', dialect: EscapeDialect.regex),
          r'a\.b\*c');
      expect(escapeText('(x)[y]{z}', dialect: EscapeDialect.regex),
          r'\(x\)\[y\]\{z\}');
    });

    test('控制字符转 \\u 形式', () {
      expect(escapeText('\u0001'), r'"\u0001"');
    });

    test('不加引号', () {
      expect(escapeText('a b', wrap: false), r'a b');
    });
  });

  group('unescapeText', () {
    test('往返一致', () {
      const src = 'line1\nline2\t"q"\\end';
      expect(unescapeText(escapeText(src)), src);
    });

    test('去掉外层引号（单双都行）', () {
      expect(unescapeText('"abc"'), 'abc');
      expect(unescapeText("'abc'"), 'abc');
      expect(unescapeText('abc'), 'abc');
    });

    test('常见转义', () {
      expect(unescapeText(r'a\nb\tc'), 'a\nb\tc');
      expect(unescapeText(r'\"q\"'), '"q"');
      expect(unescapeText(r'a\\b'), r'a\b');
    });

    test('SQL 单引号还原', () {
      expect(unescapeText("it''s"), "it's");
    });

    test('\\u 与 \\x', () {
      expect(unescapeText(r'\u0041'), 'A');
      expect(unescapeText(r'\x41'), 'A');
      expect(unescapeText(r'\uZZZZ'), r'uZZZZ');
    });

    test('不认识的转义原样保留（别把正文吃掉）', () {
      expect(unescapeText(r'a\qb'), r'a\qb');
      expect(unescapeText(r'C:\temp\new'), 'C:\temp\new');
    });

    test('末尾孤立反斜杠不崩', () {
      expect(unescapeText('abc\\'), 'abc\\');
    });
  });
}
