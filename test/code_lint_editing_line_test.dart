import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/code_lint.dart';

void main() {
  group('editingLine', () {
    test('光标所在行的「缺分号」不报，其它行照报', () {
      const src = 'class A {\n  int x = 1\n  int y = 2\n}';
      // 不传 editingLine：两行都报
      final all = CodeLint.check(src, langLabel: 'C#', langKey: 'csharp');
      expect(all.diagnostics.where((d) => d.code == 'missing-semicolon').length, 2);

      // 光标在第 2 行：只报第 3 行
      final editing = CodeLint.check(src,
          langLabel: 'C#', langKey: 'csharp', editingLine: 2);
      final missing = editing.diagnostics.where((d) => d.code == 'missing-semicolon').toList();
      expect(missing.length, 1);
      expect(missing.first.line, 3);
    });

    test('未闭合字符串同理（打了一半的引号不报）', () {
      const src = 'class A {\n  String s = "abc\n  int x = 1;\n}';
      final editing = CodeLint.check(src,
          langLabel: 'C#', langKey: 'csharp', editingLine: 2);
      expect(editing.diagnostics.where((d) => d.code == 'unclosed-string'), isEmpty);
      final all = CodeLint.check(src, langLabel: 'C#', langKey: 'csharp');
      expect(all.diagnostics.where((d) => d.code == 'unclosed-string'), isNotEmpty);
    });

    test('不影响其它类型的问题（全角标点照报）', () {
      const src = 'class A {\n  int x = 1；\n}';
      final editing = CodeLint.check(src,
          langLabel: 'C#', langKey: 'csharp', editingLine: 2);
      expect(editing.diagnostics, isNotEmpty);
    });

    test('incompleteCodes 是一份可审计的白名单', () {
      expect(CodeLint.incompleteCodes.contains('missing-semicolon'), isTrue);
      expect(CodeLint.incompleteCodes.contains('unclosed-string'), isTrue);
      // 「硬错误」不该被编辑行豁免
      expect(CodeLint.incompleteCodes.contains('full-width'), isFalse);
    });
  });
}
