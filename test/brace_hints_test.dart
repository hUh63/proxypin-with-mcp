import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/brace_hints.dart';

void main() {
  group('闭合括号提示', () {
    test('类与方法都能识别，嵌套各自独立', () {
      const src = '''
class Foo {
  void bar() {
    var x = 1;
    x++;
  }
}''';
      final hints = closingBraceHints(src, minBlockLines: 3);
      expect(hints.map((e) => e.text), containsAll(['bar', 'Foo']));
      // bar 的 } 在第 5 行（0 起），Foo 的 } 在第 6 行
      final byName = {for (final h in hints) h.text: h.line};
      expect(byName['bar'], 5);
      expect(byName['Foo'], 6);
    });

    test('if / for 这类控制块不标', () {
      const src = '''
void f() {
  if (a) {
    print(1);
    print(2);
    print(3);
  }
}''';
      final hints = closingBraceHints(src, minBlockLines: 3);
      expect(hints.map((e) => e.text), ['f']);
    });

    test('字符串里的花括号不影响配对', () {
      const src = '''
void a() {
  var s = "} {{{";
  var t = 'x{';
}
void b() {
  var y = 1;
  var z = 2;
}''';
      final hints = closingBraceHints(src, minBlockLines: 3);
      expect(hints.map((e) => e.text), containsAll(['a', 'b']));
    });

    test('注释里的花括号不影响配对', () {
      const src = '''
void a() {
  // 这里有一个 }
  /* 这里有两个 } } */
  var x = 1;
}''';
      final hints = closingBraceHints(src, minBlockLines: 3);
      expect(hints.length, 1);
      expect(hints.first.text, 'a');
      expect(hints.first.line, 4);
    });

    test('块跨度太小的不标', () {
      const src = 'void a() {\n  x();\n}';
      expect(closingBraceHints(src, minBlockLines: 4), isEmpty);
      expect(closingBraceHints(src, minBlockLines: 2), hasLength(1));
    });

    test('列号落在行末', () {
      const src = 'void abc() {\n  1;\n  2;\n  3;\n  }';
      final h = closingBraceHints(src, minBlockLines: 3).single;
      expect(h.text, 'abc');
      expect(h.column, '  }'.length);
      expect(h.line, 4);
    });

    test('# 作为行注释符时生效（python/shell 风格）', () {
      const src = 'def f():\n    d = {\n    }  # }\n    pass\n';
      final hints = closingBraceHints(src, lineComment: '#', minBlockLines: 1);
      // 字典块 span 只有 1 行，minBlockLines=1 时算上；但没名字 → 不标
      expect(hints, isEmpty);
    });

    test('上限生效', () {
      final sb = StringBuffer();
      for (var i = 0; i < 50; i++) {
        sb.writeln('void f$i() {');
        sb.writeln('  a();');
        sb.writeln('  b();');
        sb.writeln('}');
      }
      expect(closingBraceHints(sb.toString(), minBlockLines: 2, maxHints: 10),
          hasLength(10));
    });
  });
}
