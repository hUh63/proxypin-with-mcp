import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/code_lint.dart';

void main() {
  LintReport run(String src) => CodeLint.check(src, langLabel: 'C#', langKey: 'csharp');

  List<String> codes(LintReport r) => r.diagnostics.map((d) => d.code).toList();

  group('语句形状（会直接导致编译不过）', () {
    test('方法调用漏了分号要报（以前 `)` 结尾被整类放过）', () {
      const src = 'class A {\n  void M() {\n    Console.WriteLine("hi")\n  }\n}';
      final r = run(src);
      expect(codes(r), contains('missing-semicolon'));
      final d = r.diagnostics.firstWhere((e) => e.code == 'missing-semicolon');
      expect(d.line, 3);
    });

    test('索引表达式漏了分号要报', () {
      const src = 'class A {\n  void M() {\n    int[] xs = new int[3];\n    xs[0]\n  }\n}';
      expect(codes(run(src)), contains('missing-semicolon'));
    });

    test('构造函数声明不会因为 `)` 结尾被误报', () {
      const src = 'class A {\n  A()\n  {\n  }\n}';
      expect(codes(run(src)), isNot(contains('missing-semicolon')));
    });

    test('if 后面漏了左括号要报', () {
      const src = 'class A {\n  void M() {\n    if x > 0 {\n    }\n  }\n}';
      final r = run(src);
      expect(codes(r), contains('missing-paren'));
      final d = r.diagnostics.firstWhere((e) => e.code == 'missing-paren');
      expect(d.line, 3);
      expect(d.severity, LintSeverity.error);
    });

    test('正常的 if / for 不报', () {
      const src = 'class A {\n  void M() {\n    if (x > 0) {\n      for (var i = 0; i < 3; i++) {\n      }\n    }\n  }\n}';
      expect(codes(run(src)), isNot(contains('missing-paren')));
    });

    test('switch 表达式不算「缺括号」', () {
      const src = 'class A {\n  void M() {\n    var s = x switch { 1 => "a", _ => "b" };\n  }\n}';
      expect(codes(run(src)), isNot(contains('missing-paren')));
    });

    test('case 后面缺冒号要报，且能一键补上', () {
      const src = 'class A {\n  void M() {\n    switch (x) {\n      case 1\n        break;\n    }\n  }\n}';
      final r = run(src);
      final d = r.diagnostics.firstWhere((e) => e.code == 'case-colon');
      expect(d.line, 4);
      expect(d.replacement, ':');
    });

    test('case 1: 不报', () {
      const src = 'class A {\n  void M() {\n    switch (x) {\n      case 1:\n        break;\n      default:\n        break;\n    }\n  }\n}';
      expect(codes(run(src)), isNot(contains('case-colon')));
    });

    test('#region 少了 #endregion 要报', () {
      const src = '#region Demo\nclass A { }\n';
      final r = run(src);
      expect(codes(r), contains('unclosed-preproc'));
    });

    test('#if / #endif 配对时不报', () {
      const src = '#if DEBUG\nclass A { }\n#endif\n';
      expect(codes(run(src)), isNot(contains('unclosed-preproc')));
    });

    test('#endregion 多出来要报', () {
      const src = '#endregion\nclass A { }\n';
      expect(codes(run(src)), contains('unclosed-preproc'));
    });

    test('C# 泛型约束行不会被当成缺分号', () {
      const src = 'class A<T>\n  where T : class\n{\n}\n';
      expect(codes(run(src)), isNot(contains('missing-semicolon')));
    });

    test('类型声明后面缺 { 时报「缺 {」而不是「缺分号」', () {
      const src = 'class A\n  int x;\n';
      final r = run(src);
      expect(codes(r), contains('type-body'));
      expect(codes(r), isNot(contains('missing-semicolon')));
    });

    test('新规则可单独关闭', () {
      const src = 'class A {\n  void M() {\n    if x > 0 {\n    }\n  }\n}';
      final r = CodeLint.check(src,
          langLabel: 'C#', langKey: 'csharp', disabledRules: const {'missing-paren'});
      expect(codes(r), isNot(contains('missing-paren')));
      expect(LintRules.byCode('missing-paren'), isNotNull);
      expect(LintRules.byCode('case-colon'), isNotNull);
      expect(LintRules.byCode('unclosed-preproc'), isNotNull);
    });
  });
}
