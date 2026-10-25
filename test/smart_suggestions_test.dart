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
import 'package:proxypin/utils/smart_suggestions.dart';

void main() {
  group('contextual suggestions with an empty prefix', () {
    test('inside a block after `{` suggests statements used by this file', () {
      const doc = 'void main() {\n  print(1);\n  print(2);\n  if (x) {\n    ';
      final list = SmartSuggestions.suggest(
        language: 'Dart',
        key: 'dart',
        documentText: doc,
        linePrefix: '    ',
        prefix: '',
        cursorOffset: doc.length,
      );
      expect(list, isNotEmpty);
      // 「这份文件里高频出现的行首词」应当排在候选里
      expect(list.any((e) => e == 'print' || e == 'if' || e == 'return'), isTrue);
    });

    test('after `=` suggests literals of that language', () {
      final list = SmartSuggestions.suggest(
        language: 'Python',
        key: 'python',
        documentText: 'x = 1\n',
        linePrefix: 'y = ',
        prefix: '',
        cursorOffset: 14,
      );
      expect(list, contains('None'));
    });

    test('after `}` suggests else / return', () {
      const doc = 'void main() {\n  if (x) {\n  }\n';
      final list = SmartSuggestions.suggest(
        language: 'Dart',
        key: 'dart',
        documentText: doc,
        linePrefix: '',
        prefix: '',
        cursorOffset: doc.length,
      );
      expect(list.any((e) => e == 'else' || e == 'return'), isTrue);
    });

    test('non-programming languages do not get code keyword lists', () {
      // JSON 不走上下文联想，仍由 _json 的结构提示处理
      final list = SmartSuggestions.suggest(
        language: 'JSON',
        key: 'json',
        documentText: '{"a": 1}',
        linePrefix: '',
        prefix: '',
        cursorOffset: 8,
      );
      expect(list.any((e) => e == 'print' || e == 'return'), isFalse);
    });

    test('result is capped so the popup stays usable', () {
      final list = SmartSuggestions.suggest(
        language: 'Dart',
        key: 'dart',
        documentText: 'void main() {\n',
        linePrefix: '',
        prefix: '',
        cursorOffset: 14,
      );
      expect(list.length, lessThanOrEqualTo(20));
    });
  });
}
