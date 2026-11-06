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
import 'package:proxypin/utils/code_snippets.dart';

void main() {
  test('常用语言都能取到片段', () {
    const langs = {
      'Dart': 'dart',
      'Java': 'java',
      'Python': 'python',
      'JavaScript': 'javascript',
      'TypeScript': 'typescript',
      'Go': 'go',
      'C#': 'csharp',
      'C++': 'cpp',
      'C': 'c',
      'PHP': 'php',
      'Ruby': 'ruby',
      'Kotlin': 'kotlin',
      'Swift': 'swift',
      'Rust': 'rust',
      'SQL': 'sql',
      'HTML': 'html',
      'CSS': 'css',
      'Shell': 'bash',
    };
    for (final e in langs.entries) {
      final list = CodeSnippets.forLanguage(e.key, e.value);
      expect(list, isNotEmpty, reason: '${e.key} 应该有片段');
      // 通用兜底不应该被语言命中（有的话说明别名表漏了这个语言）
      expect(list.length, greaterThanOrEqualTo(3), reason: e.key);
    }
  });

  test('未知语言退回通用片段', () {
    final list = CodeSnippets.forLanguage('Plain Text', 'plaintext');
    expect(list, isNotEmpty);
    expect(list.first.label, 'if');
  });

  test('label 里带语言名也能识别（如 HTML, XML）', () {
    final list = CodeSnippets.forLanguage('HTML, XML');
    expect(list.any((s) => s.label == 'HTML5'), isTrue);
  });

  test('每个模板最多一个 $0 占位符', () {
    for (final lang in const [
      'dart', 'java', 'python', 'javascript', 'go', 'csharp',
      'c', 'cpp', 'php', 'ruby', 'kotlin', 'swift', 'rust',
      'sql', 'html', 'css', 'bash',
    ]) {
      for (final s in CodeSnippets.forLanguage(lang, lang)) {
        final n = r'$0'.allMatches(s.body).length;
        expect(n, lessThanOrEqualTo(1), reason: '${lang}/${s.label} 有 $n 个 \$0');
      }
    }
  });

  test('模板不以换行开头、不含制表符硬缩进', () {
    for (final lang in ['dart', 'java', 'python', 'javascript']) {
      for (final s in CodeSnippets.forLanguage(lang, lang)) {
        expect(s.body.startsWith('\n'), isFalse, reason: s.label);
        expect(s.body.contains('\t'), isFalse, reason: '${s.label} 用了 Tab');
        expect(s.label.trim(), isNotEmpty);
      }
    }
  });

  test('label 不重复', () {
    for (final lang in ['dart', 'java', 'python', 'javascript', 'go', 'csharp']) {
      final labels =
          CodeSnippets.forLanguage(lang, lang).map((s) => s.label).toList();
      expect(labels.toSet().length, labels.length, reason: lang);
    }
  });

  test('languageCount 覆盖到两位数', () {
    expect(CodeSnippets.languageCount, greaterThanOrEqualTo(10));
  });
}
