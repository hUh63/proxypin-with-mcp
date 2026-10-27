import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/code_lint.dart';

void main() {
  LintReport run(String src, {bool style = false}) => CodeLint.check(
        src,
        langLabel: 'C#',
        langKey: 'csharp',
        styleRules: style,
      );

  group('排版风格（默认关）', () {
    test('默认不报风格问题', () {
      const src = 'class A {\n  int x = 1;   \n\n\n\n  int y = 2;\n}';
      final r = run(src);
      expect(r.diagnostics.where((d) => LintRules.styleCodes.contains(d.code)), isEmpty);
    });

    test('打开后才报：行尾空格 / 连续空行 / 文件末尾换行', () {
      const src = 'class A {\n  int x = 1;   \n\n\n\n  int y = 2;\n}';
      final r = run(src, style: true);
      expect(r.diagnostics.where((d) => d.code == 'trailing-space'), isNotEmpty);
      expect(r.diagnostics.where((d) => d.code == 'blank-lines'), isNotEmpty);
      expect(r.diagnostics.where((d) => d.code == 'eof-newline'), isNotEmpty);
    });

    test('行尾空格可一键删除，且只删空格不碰内容', () {
      const src = 'class A {\n  int x = 1;   \n}\n';
      final r = run(src, style: true);
      final d = r.diagnostics.firstWhere((e) => e.code == 'trailing-space');
      expect(d.replacement, '');
      final fixed = CodeLint.applyFixes(src, [d]);
      expect(fixed.contains('int x = 1;   '), isFalse);
      expect(fixed.contains('int x = 1;'), isTrue);
    });

    test('CRLF 文件不会被当成满屏行尾空格', () {
      const src = 'class A {\r\n  int x = 1;\r\n}\r\n';
      final r = run(src, style: true);
      expect(r.diagnostics.where((d) => d.code == 'trailing-space'), isEmpty);
    });

    test('文件末尾有换行就不报', () {
      const src = 'class A {\n}\n';
      final r = run(src, style: true);
      expect(r.diagnostics.where((d) => d.code == 'eof-newline'), isEmpty);
    });

    test('风格规则可以被单独关掉（即使开了 styleRules）', () {
      const src = 'class A {\n}\n';
      final r = CodeLint.check(src,
          langLabel: 'C#',
          langKey: 'csharp',
          styleRules: true,
          disabledRules: const {'eof-newline'});
      expect(r.diagnostics.where((d) => d.code == 'eof-newline'), isEmpty);
    });

    test('LintRules 里三条风格规则都有 style 标记', () {
      for (final code in LintRules.styleCodes) {
        final rule = LintRules.byCode(code);
        expect(rule, isNotNull, reason: code);
        expect(rule!.style, isTrue, reason: code);
      }
    });
  });
}
