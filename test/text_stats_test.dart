import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_stats.dart';

void main() {
  group('基础', () {
    test('空文本', () {
      final s = TextStats.of('');
      expect(s.isEmpty, isTrue);
      expect(s.lines, 0);
      expect(s.chars, 0);
    });

    test('单行单词', () {
      final s = TextStats.of('abc');
      expect(s.lines, 1);
      expect(s.words, 1);
      expect(s.chars, 3);
      expect(s.charsNoSpace, 3);
      expect(s.bytes, 3);
      expect(s.maxLineLength, 3);
      expect(s.longestLine, 1);
      expect(s.paragraphs, 1);
    });

    test('多个空格分隔的词', () {
      expect(TextStats.of('a b  c').words, 3);
      expect(TextStats.of('  a  ').words, 1);
    });

    test('含空白的字符统计', () {
      final s = TextStats.of('a b');
      expect(s.chars, 3);
      expect(s.charsNoSpace, 2);
    });
  });

  group('行数', () {
    test('两行', () {
      expect(TextStats.of('a\nb').lines, 2);
    });

    test('末尾换行不多算一行', () {
      expect(TextStats.of('a\n').lines, 1);
      expect(TextStats.of('a\n\n').lines, 2);
    });

    test('CRLF 不把 \\r 当内容', () {
      final s = TextStats.of('abc\r\ndef');
      expect(s.lines, 2);
      expect(s.charsNoSpace, 6);
      expect(s.maxLineLength, 3);
    });
  });

  group('最长行', () {
    test('取最长那行和行号', () {
      final s = TextStats.of('aaa\nbbbb\ncc');
      expect(s.maxLineLength, 4);
      expect(s.longestLine, 2);
    });

    test('最后一行也参与比较', () {
      final s = TextStats.of('a\nbbbbbb');
      expect(s.maxLineLength, 6);
      expect(s.longestLine, 2);
    });

    test('空行不影响', () {
      final s = TextStats.of('aa\n\n\nbb');
      expect(s.maxLineLength, 2);
      expect(s.longestLine, 1);
    });
  });

  group('段落', () {
    test('连续非空行算一段', () {
      expect(TextStats.of('a\nb\n\nc').paragraphs, 2);
    });

    test('没有空行只有一段', () {
      expect(TextStats.of('a\nb\nc').paragraphs, 1);
    });
  });

  group('中文与字节', () {
    test('中文按字符数算，字节是 UTF-8 三倍', () {
      final s = TextStats.of('你好世界');
      expect(s.chars, 4);
      expect(s.charsNoSpace, 4);
      expect(s.words, 1);
      expect(s.bytes, 12);
    });

    test('emoji 占 4 字节（代理对）', () {
      final s = TextStats.of('😀');
      expect(s.chars, 2); // UTF-16 两个 code unit
      expect(s.bytes, 4);
    });
  });

  group('ofRange', () {
    test('取一段', () {
      final s = TextStats.ofRange('hello world', 6, 11);
      expect(s.chars, 5);
      expect(s.words, 1);
    });

    test('越界被 clamp', () {
      expect(TextStats.ofRange('abc', -5, 99).chars, 3);
    });

    test('反着传也行', () {
      expect(TextStats.ofRange('abcdef', 5, 2).chars, 3);
    });

    test('空区间', () {
      expect(TextStats.ofRange('abc', 2, 2).isEmpty, isTrue);
    });
  });
}
