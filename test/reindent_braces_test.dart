import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/lang_meta.dart';

void main() {
  group('reindentBraces', () {
    test('普通嵌套按大括号缩进', () {
      const src = 'class A {\nvoid f() {\nint x = 1;\n}\n}';
      expect(
        reindentBraces(src, tabSize: 2),
        'class A {\n  void f() {\n    int x = 1;\n  }\n}',
      );
    });

    test('行首连续闭合括号按个数退级', () {
      // `}))` 要退三级；以前只退一级，会越缩越深。
      const src = 'foo(bar(\n{\na: 1\n}\n));';
      final out = reindentBraces(src, tabSize: 2);
      final lines = out.split('\n');
      expect(lines.last, '));');
    });

    test('字符串与注释里的括号不影响缩进', () {
      const src = 'void f() {\nprint("{{{");\n// }}}\nint y = 2;\n}';
      final out = reindentBraces(src, tabSize: 2);
      final lines = out.split('\n');
      // print / 注释行都在第一层，y 也还在第一层
      expect(lines[1].startsWith('  print'), isTrue);
      expect(lines[3].startsWith('  int y'), isTrue);
    });

    test('useTabs 用制表符缩进', () {
      const src = 'a {\nb;\n}';
      expect(reindentBraces(src, useTabs: true), 'a {\n\tb;\n}');
    });

    test('空行保持为空（不留行尾空白）', () {
      const src = 'a {\n   \nb;\n}';
      expect(reindentBraces(src, tabSize: 2), 'a {\n\n  b;\n}');
    });
  });

  group('formatKindOf', () {
    test('纯文本不提供格式化', () {
      expect(formatKindOf(key: '', label: 'Plain Text'), FormatKind.none);
    });

    test('Markdown / YAML / Python 不做大括号重排', () {
      expect(formatKindOf(key: 'markdown', label: 'Markdown'), FormatKind.none);
      expect(formatKindOf(key: 'yaml', label: 'YAML'), FormatKind.none);
      expect(formatKindOf(key: 'python', label: 'Python'), FormatKind.none);
    });

    test('JSON / XML / CSS / JS 各有专用格式化器', () {
      expect(formatKindOf(key: 'json', label: 'JSON'), FormatKind.json);
      expect(formatKindOf(key: 'xml', label: 'XML / HTML'), FormatKind.xml);
      expect(formatKindOf(key: 'css', label: 'CSS'), FormatKind.css);
      expect(formatKindOf(key: 'javascript', label: 'JavaScript'), FormatKind.js);
    });
  });
}
