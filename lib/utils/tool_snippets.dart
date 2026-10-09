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

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 工具页「快捷插入」条目：显示名 + 要插入的文本。
///
/// 默认条目的显示名直接用插入文本本身（正则元字符、符号本身即跨语言通用），
/// 因此不需要参与 l10n；只有用户自定义时才会出现自定标题。
class ToolSnippet {
  final String label;
  final String insert;

  const ToolSnippet(this.label, this.insert);

  Map<String, dynamic> toJson() => {'label': label, 'insert': insert};

  static ToolSnippet? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final insert = raw['insert'] as String? ?? '';
    if (insert.isEmpty) return null;
    final label = raw['label'] as String? ?? '';
    return ToolSnippet(label.isEmpty ? insert : label, insert);
  }
}

/// 各工具页的内置快捷插入条目。
class ToolSnippetDefaults {
  ToolSnippetDefaults._();

  /// 正则工具页：元字符 / 字符类 / 分组断言 / 量词 / 常用片段 / 替换引用。
  static const List<ToolSnippet> regexp = [
    // 单字符元字符
    ToolSnippet('.', '.'),
    ToolSnippet('*', '*'),
    ToolSnippet('+', '+'),
    ToolSnippet('?', '?'),
    ToolSnippet('^', '^'),
    ToolSnippet(r'$', r'$'),
    ToolSnippet('|', '|'),
    ToolSnippet(r'\', r'\'),
    ToolSnippet('()', '()'),
    ToolSnippet('[]', '[]'),
    ToolSnippet('{}', '{}'),
    // 字符类
    ToolSnippet(r'\d', r'\d'),
    ToolSnippet(r'\D', r'\D'),
    ToolSnippet(r'\w', r'\w'),
    ToolSnippet(r'\W', r'\W'),
    ToolSnippet(r'\s', r'\s'),
    ToolSnippet(r'\S', r'\S'),
    ToolSnippet(r'\b', r'\b'),
    ToolSnippet(r'\B', r'\B'),
    // 量词
    ToolSnippet('{n}', '{n}'),
    ToolSnippet('{n,}', '{n,}'),
    ToolSnippet('{n,m}', '{n,m}'),
    ToolSnippet('*?', '*?'),
    ToolSnippet('+?', '+?'),
    ToolSnippet('??', '??'),
    // 分组 / 断言
    ToolSnippet('(?:)', '(?:)'),
    ToolSnippet('(?=)', '(?=)'),
    ToolSnippet('(?!)', '(?!)'),
    ToolSnippet('(?<=)', '(?<=)'),
    ToolSnippet('(?<!)', '(?<!)'),
    // 常用片段
    ToolSnippet(r'\d+', r'\d+'),
    ToolSnippet('[a-zA-Z]+', '[a-zA-Z]+'),
    ToolSnippet(r'[\u4e00-\u9fa5]+', r'[\u4e00-\u9fa5]+'),
    ToolSnippet(r'\w+@\w+\.\w+', r'\w+@\w+\.\w+'),
    ToolSnippet(r'https?://\S+', r'https?://\S+'),
    ToolSnippet(r'\d{4}-\d{2}-\d{2}', r'\d{4}-\d{2}-\d{2}'),
    ToolSnippet(r'(\d{1,3}\.){3}\d{1,3}', r'(\d{1,3}\.){3}\d{1,3}'),
    ToolSnippet('^.*' + r'$', '^.*\$'),
    // 替换引用
    ToolSnippet(r'$0', r'$0'),
    ToolSnippet(r'$1', r'$1'),
    ToolSnippet(r'\$', r'\$'),
    ToolSnippet(r'\n', r'\n'),
    ToolSnippet(r'\t', r'\t'),
  ];

  /// 文本编辑页：常用符号 / 全角标点 / 数学与特殊符号 / 制表符与空白。
  static const List<ToolSnippet> editor = [
    // 箭头
    ToolSnippet('→', '→'),
    ToolSnippet('←', '←'),
    ToolSnippet('↑', '↑'),
    ToolSnippet('↓', '↓'),
    ToolSnippet('⇒', '⇒'),
    ToolSnippet('⇔', '⇔'),
    // 勾叉与星号
    ToolSnippet('✓', '✓'),
    ToolSnippet('✗', '✗'),
    ToolSnippet('★', '★'),
    ToolSnippet('☆', '☆'),
    ToolSnippet('●', '●'),
    ToolSnippet('○', '○'),
    ToolSnippet('◆', '◆'),
    ToolSnippet('◇', '◇'),
    // 数学
    ToolSnippet('≠', '≠'),
    ToolSnippet('≤', '≤'),
    ToolSnippet('≥', '≥'),
    ToolSnippet('±', '±'),
    ToolSnippet('×', '×'),
    ToolSnippet('÷', '÷'),
    ToolSnippet('∞', '∞'),
    ToolSnippet('√', '√'),
    ToolSnippet('≈', '≈'),
    ToolSnippet('∑', '∑'),
    ToolSnippet('π', 'π'),
    // 常用符号
    ToolSnippet('§', '§'),
    ToolSnippet('¶', '¶'),
    ToolSnippet('©', '©'),
    ToolSnippet('®', '®'),
    ToolSnippet('™', '™'),
    ToolSnippet('°', '°'),
    ToolSnippet('€', '€'),
    ToolSnippet('£', '£'),
    // 全角标点
    ToolSnippet('，', '，'),
    ToolSnippet('。', '。'),
    ToolSnippet('、', '、'),
    ToolSnippet('；', '；'),
    ToolSnippet('：', '：'),
    ToolSnippet('“”', '“”'),
    ToolSnippet('‘’', '‘’'),
    ToolSnippet('《》', '《》'),
    ToolSnippet('（)', '（）'),
    // 空白与制表
    ToolSnippet('Tab', '\t'),
    ToolSnippet('CRLF', '\r\n'),
    ToolSnippet('NBSP', '\u00a0'),
    ToolSnippet('零宽空格', '\u200b'),
    ToolSnippet('全角空格', '\u3000'),
  ];

  /// JSON 查看页：结构符号 / 字面量 / 转义。
  static const List<ToolSnippet> json = [
    ToolSnippet('{ }', '{}'),
    ToolSnippet('[ ]', '[]'),
    ToolSnippet('"key"', '"key"'),
    ToolSnippet('"value"', '"value"'),
    ToolSnippet(':', ': '),
    ToolSnippet(',', ','),
    ToolSnippet('null', 'null'),
    ToolSnippet('true', 'true'),
    ToolSnippet('false', 'false'),
    ToolSnippet('0', '0'),
    ToolSnippet(r'\"', r'\"'),
    ToolSnippet(r'\\', r'\\'),
    ToolSnippet(r'\n', r'\n'),
    ToolSnippet(r'\t', r'\t'),
    ToolSnippet(r'\u', r'\u'),
  ];

  /// XML 查看页：标签 / 属性 / 注释 / CDATA / 实体。
  static const List<ToolSnippet> xml = [
    ToolSnippet('<tag>', '<tag>'),
    ToolSnippet('</tag>', '</tag>'),
    ToolSnippet('<tag/>', '<tag/>'),
    ToolSnippet('<tag></tag>', '<tag></tag>'),
    ToolSnippet('=""', '=""'),
    ToolSnippet('<!-- -->', '<!-- -->'),
    ToolSnippet('<![CDATA[]]>', '<![CDATA[]]>'),
    ToolSnippet('<?xml?>', '<?xml version="1.0" encoding="UTF-8"?>'),
    ToolSnippet('&lt;', '&lt;'),
    ToolSnippet('&gt;', '&gt;'),
    ToolSnippet('&amp;', '&amp;'),
    ToolSnippet('&quot;', '&quot;'),
    ToolSnippet('&apos;', '&apos;'),
  ];
}


/// 「快捷插入」条目的持久化存储。
///
/// 约定：未自定义（键不存在或为空串）时返回 null，调用方回退到内置默认；
/// 用户清空后写入 `[]`，表示"确实不要任何条目"。
class ToolSnippetStore {
  ToolSnippetStore._();

  static String _key(String scope) => 'tool_snippets_v1_$scope';

  /// 返回用户自定义列表；未自定义过返回 null。
  static Future<List<ToolSnippet>?> load(String scope) async {
    try {
      final raw = await SharedPreferencesAsync().getString(_key(scope));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded.map(ToolSnippet.fromJson).whereType<ToolSnippet>().toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String scope, List<ToolSnippet> items) async {
    await SharedPreferencesAsync()
        .setString(_key(scope), jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  /// 恢复内置默认（写入空串，下次 load 返回 null）。
  static Future<void> reset(String scope) async {
    await SharedPreferencesAsync().setString(_key(scope), '');
  }
}
