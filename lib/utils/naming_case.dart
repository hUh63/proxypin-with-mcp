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

// 标识符命名风格转换（对标 VS Code 的 Transform to Camel / Pascal / Snake /
// Kebab / Constant Case）。
//
// 纯函数、无 flutter 依赖，可以单测。拆词规则刻意保持「宽松」：
//   · 非字母数字一律当分隔符（snake_case、kebab-case、空格、点号都能拆）；
//   · 小写→大写处断词（camelCase → camel|Case）；
//   · 连续大写后接小写时在最后一个大写前断（HTTPServer → HTTP|Server）；
//   · 数字并入当前词（v2 → v2，不会拆成 v|2，否则 camelCase 会把 v2 变 v2 之外的东西）。

/// 命名风格。
enum NamingCase { camel, pascal, snake, kebab, constant }

/// 把标识符/短语拆成词。空串返回空列表。
List<String> splitIdentifierWords(String input) {
  final words = <String>[];
  final buf = StringBuffer();

  void flush() {
    if (buf.isNotEmpty) {
      words.add(buf.toString());
      buf.clear();
    }
  }

  for (var i = 0; i < input.length; i++) {
    final c = input.codeUnitAt(i);
    final isUpper = c >= 65 && c <= 90;
    final isLower = c >= 97 && c <= 122;
    final isDigit = c >= 48 && c <= 57;
    if (!isUpper && !isLower && !isDigit) {
      flush();
      continue;
    }
    if (isUpper && buf.isNotEmpty) {
      final prev = input.codeUnitAt(i - 1);
      final prevUpper = prev >= 65 && prev <= 90;
      final next = i + 1 < input.length ? input.codeUnitAt(i + 1) : -1;
      final nextLower = next >= 97 && next <= 122;
      if (!prevUpper || nextLower) flush();
    }
    buf.writeCharCode(c);
  }
  flush();
  return words;
}

/// 按风格把词拼回去。
String joinIdentifierWords(List<String> words, NamingCase style) {
  if (words.isEmpty) return '';

  String cap(String w) =>
      w.length <= 1 ? w.toUpperCase() : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';

  return switch (style) {
    NamingCase.camel => '${words.first.toLowerCase()}${words.skip(1).map(cap).join()}',
    NamingCase.pascal => words.map(cap).join(),
    NamingCase.snake => words.map((w) => w.toLowerCase()).join('_'),
    NamingCase.kebab => words.map((w) => w.toLowerCase()).join('-'),
    NamingCase.constant => words.map((w) => w.toUpperCase()).join('_'),
  };
}

/// 一步完成「拆词 → 按风格重组」。输入没有可识别的单词时原样返回。
String convertNamingCase(String input, NamingCase style) {
  final words = splitIdentifierWords(input);
  if (words.isEmpty) return input;
  return joinIdentifierWords(words, style);
}

/// 按菜单/配置里的字符串 id 找风格；未知 id 返回 null。
NamingCase? namingCaseOf(String id) {
  for (final v in NamingCase.values) {
    if (v.name == id) return v;
  }
  return null;
}
