/*
 * Copyright 2026 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/code_lint.dart';

void main() {
  group('language profile', () {
    test('csharp needs semicolons, python does not', () {
      expect(CodeLint.profileOf('C#', 'csharp').semicolons, isTrue);
      expect(CodeLint.profileOf('Python', 'python').semicolons, isFalse);
      expect(CodeLint.profileOf('Python', 'python').blockIndent, isTrue);
    });

    test('markup is split into strict xml and skipped html', () {
      expect(CodeLint.profileOf('XML', 'xml').strictMarkup, isTrue);
      expect(CodeLint.profileOf('HTML', 'html').skipAll, isTrue);
      expect(CodeLint.profileOf('JSON', 'json').json, isTrue);
    });
  });

  group('brackets', () {
    test('missing closing brace is reported and fixable', () {
      final report = CodeLint.check('void main() {\n  print(1);\n', langLabel: 'Dart', langKey: 'dart');
      final d = report.diagnostics.where((e) => e.code == 'unclosed-bracket').toList();
      expect(d, hasLength(1));
      expect(d.first.severity, LintSeverity.error);
      expect(d.first.replacement, '}');
    });

    test('extra closing brace is reported and removable', () {
      final report = CodeLint.check('int x = 1;\n}\n', langLabel: 'Java', langKey: 'java');
      final d = report.diagnostics.where((e) => e.code == 'extra-bracket').toList();
      expect(d, hasLength(1));
      expect(d.first.line, 2);
      expect(d.first.replacement, '');
    });

    test('balanced code has no diagnostics', () {
      final report = CodeLint.check(
        'class A {\n  void f() {\n    print("hi");\n  }\n}\n',
        langLabel: 'Dart',
        langKey: 'dart',
      );
      expect(report.diagnostics, isEmpty);
    });

    test('braces inside strings and comments are ignored', () {
      final report = CodeLint.check(
        '// a stray {\nvar s = "}";\nvoid f() { }\n',
        langLabel: 'Dart',
        langKey: 'dart',
      );
      expect(report.diagnostics.where((e) => e.code.contains('bracket')), isEmpty);
    });
  });

  group('semicolons', () {
    test('missing semicolon inside a function body is reported', () {
      final report = CodeLint.check(
        'class A {\n  int x = 1\n}\n',
        langLabel: 'C#',
        langKey: 'csharp',
      );
      final d = report.diagnostics.where((e) => e.code == 'missing-semicolon').toList();
      expect(d, hasLength(1));
      expect(d.first.line, 2);
      expect(d.first.replacement, ';');
    });

    test('statement continuation is not flagged', () {
      const src = 'void f() {\n'
          '  var a = 1 +\n'
          '      2;\n'
          '  var b = foo(\n'
          '      1,\n'
          '      2);\n'
          '}\n';
      final report = CodeLint.check(src, langLabel: 'Dart', langKey: 'dart');
      expect(report.diagnostics.where((e) => e.code == 'missing-semicolon'), isEmpty);
    });

    test('python gets no semicolon diagnostics', () {
      final report = CodeLint.check('def f():\n    x = 1\n', langLabel: 'Python', langKey: 'python');
      expect(report.diagnostics.where((e) => e.code == 'missing-semicolon'), isEmpty);
    });
  });

  group('strings', () {
    test('unclosed string on one line is reported', () {
      final report = CodeLint.check(
        'var s = "abc;\nvar t = 1;\n',
        langLabel: 'JavaScript',
        langKey: 'javascript',
      );
      final d = report.diagnostics.where((e) => e.code == 'unclosed-string').toList();
      expect(d, hasLength(1));
      expect(d.first.line, 1);
    });

    test('sql doubled quotes are not treated as two strings', () {
      final report = CodeLint.check(
        "SELECT 'it''s' FROM t;\n",
        langLabel: 'SQL',
        langKey: 'sql',
      );
      expect(report.diagnostics.where((e) => e.code == 'unclosed-string'), isEmpty);
    });
  });

  group('identifier casing', () {
    test('console is suggested as Console for C#', () {
      final report = CodeLint.check(
        'class A {\n  void F() {\n    console.WriteLine("hi");\n  }\n}\n',
        langLabel: 'C#',
        langKey: 'csharp',
      );
      final d = report.diagnostics.where((e) => e.code == 'case-mismatch').toList();
      expect(d, isNotEmpty);
      expect(d.first.message, contains('console'));
      expect(d.first.replacement, 'Console');
      expect(d.first.severity, LintSeverity.info);
    });

    test('declared names are never rewritten', () {
      final report = CodeLint.check(
        'class consolex {\n}\nclass A {\n  void F() {\n    consolex x = null;\n  }\n}\n',
        langLabel: 'C#',
        langKey: 'csharp',
      );
      expect(report.diagnostics.where((e) => e.code == 'case-mismatch'), isEmpty);
    });
  });

  group('indent', () {
    test('body after colon must be indented', () {
      final report = CodeLint.check('def f():\nprint(1)\n', langLabel: 'Python', langKey: 'python');
      final d = report.diagnostics.where((e) => e.code == 'block-indent').toList();
      expect(d, hasLength(1));
      expect(d.first.line, 2);
    });

    test('mixed tabs and spaces are reported', () {
      final report = CodeLint.check('def f():\n \tprint(1)\n', langLabel: 'Python', langKey: 'python');
      expect(report.diagnostics.where((e) => e.code == 'mixed-indent'), isNotEmpty);
    });

    test('yaml keys are not treated as python blocks', () {
      final report = CodeLint.check('a:\nb: 1\n', langLabel: 'YAML', langKey: 'yaml');
      expect(report.diagnostics.where((e) => e.code == 'block-indent'), isEmpty);
    });
  });

  group('assignment in condition', () {
    test('if (x = 1) is flagged', () {
      final report = CodeLint.check('void f() {\n  if (x = 1) { }\n}\n', langLabel: 'C', langKey: 'c');
      expect(report.diagnostics.where((e) => e.code == 'assign-in-condition'), isNotEmpty);
    });

    test('if (x == 1) is not flagged', () {
      final report = CodeLint.check('void f() {\n  if (x == 1) { }\n}\n', langLabel: 'C', langKey: 'c');
      expect(report.diagnostics.where((e) => e.code == 'assign-in-condition'), isEmpty);
    });
  });

  group('json / markup', () {
    test('trailing comma json is an error', () {
      final report = CodeLint.check('{"a": 1,}', langLabel: 'JSON', langKey: 'json');
      expect(report.errorCount, greaterThan(0));
    });

    test('valid json has no diagnostics', () {
      final report = CodeLint.check('{"a": [1, 2]}', langLabel: 'JSON', langKey: 'json');
      expect(report.diagnostics, isEmpty);
    });

    test('broken xml is an error, html is skipped', () {
      expect(CodeLint.check('<a><b></a>', langLabel: 'XML', langKey: 'xml').errorCount, greaterThan(0));
      expect(CodeLint.check('<div><br></div>', langLabel: 'HTML', langKey: 'html').diagnostics, isEmpty);
    });
  });

  group('applyFixes', () {
    test('fixes are applied from the end so offsets stay valid', () {
      const src = 'class A {\n  int x = 1\n  int y = 2\n}\n';
      final report = CodeLint.check(src, langLabel: 'C#', langKey: 'csharp');
      final fixed = CodeLint.applyFixes(src, report.diagnostics);
      expect(fixed, contains('int x = 1;'));
      expect(fixed, contains('int y = 2;'));
      // 修好之后不应该再报同类问题
      expect(
        CodeLint.check(fixed, langLabel: 'C#', langKey: 'csharp')
            .diagnostics
            .where((e) => e.code == 'missing-semicolon'),
        isEmpty,
      );
    });

    test('too large input is skipped', () {
      final big = 'a' * (CodeLint.maxCheckLength + 1);
      final report = CodeLint.check(big, langLabel: 'Plain Text', langKey: 'plaintext');
      expect(report.skipped, isTrue);
      expect(report.diagnostics, isEmpty);
    });
  });
}
