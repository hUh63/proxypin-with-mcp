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

    test('markup is split into strict xml and html tag checking', () {
      expect(CodeLint.profileOf('XML', 'xml').strictMarkup, isTrue);
      expect(CodeLint.profileOf('HTML', 'html').htmlTags, isTrue);
      expect(CodeLint.profileOf('HTML', 'html').skipAll, isFalse);
      expect(CodeLint.profileOf('JSON', 'json').json, isTrue);
      expect(CodeLint.profileOf('Markdown', 'markdown').fenceCheck, isTrue);
      expect(CodeLint.profileOf('SQL', 'sql').caseSensitive, isFalse);
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

  group('false-positive guards', () {
    test('rust lifetimes are not strings', () {
      final report = CodeLint.check("fn f<'a>(x: &'a str) {}\n", langLabel: 'Rust', langKey: 'rust');
      expect(report.diagnostics.where((e) => e.code == 'unclosed-string'), isEmpty);
      expect(report.diagnostics.where((e) => e.code == 'unclosed-bracket'), isEmpty);
    });

    test('js regex literal does not swallow the rest of the line', () {
      const src = r'var re = /https?:\/\//;' '\nvar t = 1;\n';
      final report = CodeLint.check(src, langLabel: 'JavaScript', langKey: 'javascript');
      expect(report.diagnostics.where((e) => e.code == 'missing-semicolon'), isEmpty);
    });

    test('c++ if with initializer is not an assignment typo', () {
      final report = CodeLint.check('void g() {\n  if (auto p = f()) { }\n}\n',
          langLabel: 'C++', langKey: 'cpp');
      expect(report.diagnostics.where((e) => e.code == 'assign-in-condition'), isEmpty);
    });

    test('sql is case insensitive so no casing suggestions', () {
      final report = CodeLint.check('select * from t;\n', langLabel: 'SQL', langKey: 'sql');
      expect(report.diagnostics.where((e) => e.code == 'case-mismatch'), isEmpty);
    });

    test('jsonc is an info, not an error', () {
      final report = CodeLint.check('{\n  // note\n  "a": 1\n}', langLabel: 'JSON', langKey: 'json');
      expect(report.errorCount, 0);
      expect(report.diagnostics.where((e) => e.code == 'jsonc'), isNotEmpty);
    });

    test('c# verbatim string is not unterminated', () {
      final report = CodeLint.check('class A {\n  string s = @"C:\\\\temp";\n}\n',
          langLabel: 'C#', langKey: 'csharp');
      expect(report.diagnostics.where((e) => e.code == 'unclosed-string'), isEmpty);
    });
  });

  group('languages with keyword blocks', () {
    test('bash if without fi', () {
      final report = CodeLint.check('if [ -f x ]; then\n  echo hi\n', langLabel: 'Shell', langKey: 'bash');
      expect(report.diagnostics.where((e) => e.code == 'block-unclosed'), isNotEmpty);
    });

    test('bash single-line if is balanced', () {
      final report = CodeLint.check('if [ -f x ]; then echo hi; fi\n', langLabel: 'Shell', langKey: 'bash');
      expect(report.diagnostics.where((e) => e.code.startsWith('block-')), isEmpty);
    });

    test('lua function without end', () {
      final report = CodeLint.check('function f()\n  print(1)\n', langLabel: 'Lua', langKey: 'lua');
      expect(report.diagnostics.where((e) => e.code == 'block-unclosed'), isNotEmpty);
    });

    test('ruby def ... end is balanced', () {
      final report = CodeLint.check('def f\n  puts 1\nend\n', langLabel: 'Ruby', langKey: 'ruby');
      expect(report.diagnostics.where((e) => e.code.startsWith('block-')), isEmpty);
    });
  });

  group('html / markdown / config formats', () {
    test('unclosed html tag', () {
      final report = CodeLint.check('<div><p>hi</div>', langLabel: 'HTML', langKey: 'html');
      expect(report.errorCount, greaterThan(0));
    });

    test('void tags are not required to close', () {
      final report = CodeLint.check('<div><br><img src="a"></div>', langLabel: 'HTML', langKey: 'html');
      expect(report.diagnostics, isEmpty);
    });

    test('script content is not parsed as tags', () {
      final report = CodeLint.check('<div><script>var a = 1 < 2;</script></div>',
          langLabel: 'HTML', langKey: 'html');
      expect(report.diagnostics, isEmpty);
    });

    test('unclosed markdown fence', () {
      final report = CodeLint.check('# t\n```js\nvar a = 1;\n', langLabel: 'Markdown', langKey: 'markdown');
      expect(report.diagnostics.where((e) => e.code == 'fence-unclosed'), isNotEmpty);
    });

    test('ini line without separator', () {
      final report = CodeLint.check('a=1\nb\n', langLabel: 'INI', langKey: 'ini');
      expect(report.diagnostics.where((e) => e.code == 'ini-line'), isNotEmpty);
    });

    test('yaml forbids tab indentation', () {
      final report = CodeLint.check('a:\n\tb: 1\n', langLabel: 'YAML', langKey: 'yaml');
      expect(report.diagnostics.where((e) => e.code == 'yaml-tab'), isNotEmpty);
    });

    test('makefile recipe needs a tab', () {
      final report = CodeLint.check('all:\n  echo hi\n', langLabel: 'Makefile', langKey: 'makefile');
      expect(report.diagnostics.where((e) => e.code == 'makefile-tab'), isNotEmpty);
    });

    test('css declaration without semicolon', () {
      final report = CodeLint.check('a {\n  color: red\n  margin: 0;\n}\n', langLabel: 'CSS', langKey: 'css');
      expect(report.diagnostics.where((e) => e.code == 'css-semicolon'), isNotEmpty);
    });
  });

  group('full-width punctuation', () {
    test('chinese semicolon in code is flagged', () {
      final report = CodeLint.check('class A {\n  int x = 1\uff1b\n}\n', langLabel: 'C#', langKey: 'csharp');
      expect(report.diagnostics.where((e) => e.code == 'full-width'), isNotEmpty);
    });

    test('full-width punctuation inside strings is fine', () {
      final report = CodeLint.check('class A {\n  var s = "a\uff1bb";\n}\n', langLabel: 'C#', langKey: 'csharp');
      expect(report.diagnostics.where((e) => e.code == 'full-width'), isEmpty);
    });
  });

  group('programming languages get a console, formats do not', () {
    test('code languages are programming', () {
      expect(CodeLint.profileOf('C#', 'csharp').programming, isTrue);
      expect(CodeLint.profileOf('Python', 'python').programming, isTrue);
      expect(CodeLint.profileOf('Dart', 'dart').programming, isTrue);
      expect(CodeLint.profileOf('Shell', 'bash').programming, isTrue);
    });

    test('data / markup / config / prose are not', () {
      for (final pair in [
        ['JSON', 'json'],
        ['XML', 'xml'],
        ['HTML', 'html'],
        ['YAML', 'yaml'],
        ['Markdown', 'markdown'],
        ['Plain Text', 'plaintext'],
        ['CSS', 'css'],
        ['INI', 'ini'],
      ]) {
        expect(CodeLint.profileOf(pair[0], pair[1]).programming, isFalse, reason: pair[0]);
      }
    });
  });

  group('rule switches', () {
    test('disabled rule stops producing diagnostics', () {
      final report = CodeLint.check('class A {\n  int x = 1\n}\n',
          langLabel: 'C#', langKey: 'csharp', disabledRules: {'missing-semicolon'});
      expect(report.diagnostics.where((e) => e.code == 'missing-semicolon'), isEmpty);
    });
  });

  group('incremental check', () {
    test('appending keeps the old diagnostics and adds the new one', () {
      final padded = 'class A {\n  int x = 1\n}\n' + ('// pad\n' * 6000);
      final previous = CodeLint.check(padded, langLabel: 'C#', langKey: 'csharp');
      expect(previous.diagnostics.where((e) => e.code == 'missing-semicolon'), isNotEmpty);

      final current = '${padded}  int y = 2\n';
      final incremental = CodeLint.checkIncremental(
        previous: padded,
        previousReport: previous,
        current: current,
        langLabel: 'C#',
        langKey: 'csharp',
      );
      final missing = incremental.diagnostics.where((e) => e.code == 'missing-semicolon').toList();
      expect(missing.length, greaterThanOrEqualTo(1));
      // 新诊断的行号应落在追加的那一行（不在文件开头）
      expect(missing.map((e) => e.line).reduce((a, b) => a > b ? a : b), greaterThan(6000));
    });

    test('editing in the middle falls back to a full check', () {
      final previousText = 'class A {\n  int x = 1\n}\n';
      final previous = CodeLint.check(previousText, langLabel: 'C#', langKey: 'csharp');
      final edited = 'class A {\n  int x = 1;\n}\n';
      final report = CodeLint.checkIncremental(
        previous: previousText,
        previousReport: previous,
        current: edited,
        langLabel: 'C#',
        langKey: 'csharp',
      );
      expect(report.diagnostics.where((e) => e.code == 'missing-semicolon'), isEmpty);
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
