import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/code_lint.dart';

void main() {
  LintReport run(String src) => CodeLint.check(src, langLabel: 'C#', langKey: 'csharp');

  group('C# 打进半个名字', () {
    test('裸词行不报缺分号，改报「这个名字没有声明过」', () {
      const src = 'using System;\n\nclass A {\n  void M() {\n    Console.WriteLine("hi");\n    cons\n  }\n}\n';
      final r = run(src);
      expect(r.diagnostics.where((d) => d.code == 'missing-semicolon'), isEmpty);
      final unknown = r.diagnostics.where((d) => d.code == 'unknown-identifier').toList();
      expect(unknown.length, 1);
      expect(unknown.first.line, 6);
      expect(unknown.first.message, contains('Console'));
    });

    test('Console.W 这种半截名字链也不报缺分号', () {
      const src = 'class A {\n  void M() {\n    Console.W\n  }\n}';
      final r = run(src);
      expect(r.diagnostics.where((d) => d.code == 'missing-semicolon'), isEmpty);
    });

    test('真正的语句忘了分号照报（不放过真错误）', () {
      const src = 'class A {\n  void M() {\n    var x = 1\n    Console.WriteLine(x);\n  }\n}';
      final r = run(src);
      expect(r.diagnostics.where((d) => d.code == 'missing-semicolon').length, 1);
    });

    test('using System; 是正确代码，不该被任何规则报', () {
      const src = 'using System;\n\nnamespace Demo {\n  class A { }\n}\n';
      final r = run(src);
      expect(r.diagnostics, isEmpty);
    });

    test('拼错一个字母也能猜出来', () {
      const src = 'class A {\n  void M() {\n    Console.WriteLine("x");\n    Consle\n  }\n}';
      final r = run(src);
      final unknown = r.diagnostics.where((d) => d.code == 'unknown-identifier').toList();
      expect(unknown.length, 1);
      expect(unknown.first.message, contains('Console'));
    });

    test('声明过的名字（在别处出现过）不报', () {
      const src = 'class A {\n  void M() {\n    var total = 0;\n    total\n  }\n}';
      final r = run(src);
      expect(r.diagnostics.where((d) => d.code == 'unknown-identifier'), isEmpty);
    });

    test('成员名拼错会提示（Console.WritLine）', () {
      const src = 'class A {\n  void M() {\n    Console.WritLine("x");\n  }\n}';
      final r = run(src);
      final list = r.diagnostics.where((e) => e.code == 'member-spelling').toList();
      expect(list.length, 1);
      expect(list.first.message, contains('WriteLine'));
    });

    test('常见的短成员名不会被乱猜（Add 不会变成 Any）', () {
      const src = 'class A {\n  void M() {\n    list.Add(1);\n  }\n}';
      expect(run(src).diagnostics.where((e) => e.code == 'member-spelling'), isEmpty);
    });

    test('拼对的成员名不报', () {
      const src = 'class A {\n  void M() {\n    Console.WriteLine("x");\n  }\n}';
      expect(run(src).diagnostics.where((e) => e.code == 'member-spelling'), isEmpty);
    });

    test('unknown-identifier 是一份可关闭的规则', () {
      const src = 'class A {\n  void M() {\n    Console.WriteLine("hi");\n    cons\n  }\n}';
      final off = CodeLint.check(src,
          langLabel: 'C#', langKey: 'csharp', disabledRules: const {'unknown-identifier'});
      expect(off.diagnostics, isEmpty);
      expect(LintRules.byCode('unknown-identifier'), isNotNull);
    });
  });
}
