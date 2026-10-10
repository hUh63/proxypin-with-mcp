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

  /// HTTP 报文：方法 / 常见请求头 / 行结束符。
  static const List<ToolSnippet> http = [
    ToolSnippet('GET ', 'GET '),
    ToolSnippet('POST ', 'POST '),
    ToolSnippet('PUT ', 'PUT '),
    ToolSnippet('DELETE ', 'DELETE '),
    ToolSnippet('PATCH ', 'PATCH '),
    ToolSnippet('HEAD ', 'HEAD '),
    ToolSnippet('OPTIONS ', 'OPTIONS '),
    ToolSnippet('Host: ', 'Host: '),
    ToolSnippet('Content-Type: ', 'Content-Type: '),
    ToolSnippet('Authorization: ', 'Authorization: '),
    ToolSnippet('Cookie: ', 'Cookie: '),
    ToolSnippet('Accept: ', 'Accept: '),
    ToolSnippet('User-Agent: ', 'User-Agent: '),
    ToolSnippet(r'\r\n', r'\r\n'),
  ];

  /// JavaScript 常用符号 / 片段。
  static const List<ToolSnippet> javascript = [
    ToolSnippet('{ }', '{}'),
    ToolSnippet('[ ]', '[]'),
    ToolSnippet('( )', '()'),
    ToolSnippet('=>', '=>'),
    ToolSnippet(';', ';'),
    ToolSnippet(',', ', '),
    ToolSnippet('.', '.'),
    ToolSnippet(': ', ': '),
    ToolSnippet('===', '==='),
    ToolSnippet('!==', '!=='),
    ToolSnippet('&&', '&&'),
    ToolSnippet('||', '||'),
    ToolSnippet('??', '??'),
    ToolSnippet('?.', '?.'),
    ToolSnippet('function ', 'function '),
    ToolSnippet('return ', 'return '),
    ToolSnippet('async ', 'async '),
    ToolSnippet('await ', 'await '),
    ToolSnippet('console.log()', 'console.log()'),
    ToolSnippet('JSON.parse()', 'JSON.parse()'),
    ToolSnippet('JSON.stringify()', 'JSON.stringify()'),
    ToolSnippet(r'`${}`', r'`${}`'),
  ];

  /// TypeScript 常用符号 / 片段。
  static const List<ToolSnippet> typescript = [
    ToolSnippet('interface ', 'interface '),
    ToolSnippet('type ', 'type '),
    ToolSnippet('enum ', 'enum '),
    ToolSnippet('export ', 'export '),
    ToolSnippet('import ', 'import '),
    ToolSnippet('readonly ', 'readonly '),
    ToolSnippet('string', 'string'),
    ToolSnippet('number', 'number'),
    ToolSnippet('boolean', 'boolean'),
    ToolSnippet('void', 'void'),
    ToolSnippet('any', 'any'),
    ToolSnippet('(): ', '(): '),
    ToolSnippet('?: ', '?: '),
    ToolSnippet('<>', '<>'),
    ToolSnippet('as ', 'as '),
    ToolSnippet('{ }', '{}'),
    ToolSnippet('[ ]', '[]'),
    ToolSnippet('( )', '()'),
    ToolSnippet('=>', '=>'),
    ToolSnippet(';', ';'),
    ToolSnippet('return ', 'return '),
    ToolSnippet('console.log()', 'console.log()'),
  ];

  /// CSS 常用属性 / 语法。
  static const List<ToolSnippet> css = [
    ToolSnippet('{ }', '{}'),
    ToolSnippet(': ', ': '),
    ToolSnippet(';', ';'),
    ToolSnippet('.class', '.class'),
    ToolSnippet('#id', '#id'),
    ToolSnippet('/* */', '/*  */'),
    ToolSnippet('@media', '@media '),
    ToolSnippet('@import', '@import '),
    ToolSnippet('!important', ' !important'),
    ToolSnippet('px', 'px'),
    ToolSnippet('rem', 'rem'),
    ToolSnippet('%', '%'),
    ToolSnippet('display:', 'display: '),
    ToolSnippet('position:', 'position: '),
    ToolSnippet('margin:', 'margin: '),
    ToolSnippet('padding:', 'padding: '),
    ToolSnippet('color:', 'color: '),
    ToolSnippet('background:', 'background: '),
    ToolSnippet('flex', 'display: flex;'),
    ToolSnippet('var(--)', 'var(--)'),
  ];

  /// SQL 常用关键字。
  static const List<ToolSnippet> sql = [
    ToolSnippet('SELECT ', 'SELECT '),
    ToolSnippet('FROM ', 'FROM '),
    ToolSnippet('WHERE ', 'WHERE '),
    ToolSnippet('JOIN ', 'JOIN '),
    ToolSnippet('LEFT JOIN ', 'LEFT JOIN '),
    ToolSnippet('INNER JOIN ', 'INNER JOIN '),
    ToolSnippet('ON ', 'ON '),
    ToolSnippet('GROUP BY ', 'GROUP BY '),
    ToolSnippet('ORDER BY ', 'ORDER BY '),
    ToolSnippet('LIMIT ', 'LIMIT '),
    ToolSnippet('INSERT INTO ', 'INSERT INTO '),
    ToolSnippet('VALUES ', 'VALUES '),
    ToolSnippet('UPDATE ', 'UPDATE '),
    ToolSnippet('SET ', 'SET '),
    ToolSnippet('DELETE FROM ', 'DELETE FROM '),
    ToolSnippet('COUNT(*)', 'COUNT(*)'),
    ToolSnippet(' AS ', ' AS '),
    ToolSnippet(' AND ', ' AND '),
    ToolSnippet(' OR ', ' OR '),
    ToolSnippet('NULL', 'NULL'),
    ToolSnippet(';', ';'),
  ];

  /// YAML 常用结构。
  static const List<ToolSnippet> yaml = [
    ToolSnippet('key: ', 'key: '),
    ToolSnippet('- ', '- '),
    ToolSnippet('- key: ', '- key: '),
    ToolSnippet('# ', '# '),
    ToolSnippet('---', '---'),
    ToolSnippet('|', '|'),
    ToolSnippet('>', '>'),
    ToolSnippet('[]', '[]'),
    ToolSnippet('{}', '{}'),
    ToolSnippet('true', 'true'),
    ToolSnippet('false', 'false'),
    ToolSnippet('null', 'null'),
  ];

  /// Markdown 常用语法。
  static const List<ToolSnippet> markdown = [
    ToolSnippet('# ', '# '),
    ToolSnippet('## ', '## '),
    ToolSnippet('### ', '### '),
    ToolSnippet('**bold**', '**bold**'),
    ToolSnippet('*italic*', '*italic*'),
    ToolSnippet('~~del~~', '~~del~~'),
    ToolSnippet('[text](url)', '[text](url)'),
    ToolSnippet('![alt](url)', '![alt](url)'),
    ToolSnippet('`code`', '`code`'),
    ToolSnippet('```', '```'),
    ToolSnippet('> ', '> '),
    ToolSnippet('- ', '- '),
    ToolSnippet('1. ', '1. '),
    ToolSnippet('- [ ] ', '- [ ] '),
    ToolSnippet('| a | b |', '| a | b |\n|---|---|\n|  |  |'),
    ToolSnippet('---', '---'),
  ];

  /// Bash / Shell 常用语法。
  static const List<ToolSnippet> bash = [
    ToolSnippet('#!/bin/bash', '#!/bin/bash'),
    ToolSnippet(r'$', r'$'),
    ToolSnippet(' | ', ' | '),
    ToolSnippet(' > ', ' > '),
    ToolSnippet(' >> ', ' >> '),
    ToolSnippet(' && ', ' && '),
    ToolSnippet(' || ', ' || '),
    ToolSnippet(';', ';'),
    ToolSnippet(r'$( )', r'$( )'),
    ToolSnippet(r'${}', r'${}'),
    ToolSnippet('if', 'if [ ]; then\n\nfi'),
    ToolSnippet('for', 'for x in ; do\n\n done'),
    ToolSnippet('echo ', 'echo '),
    ToolSnippet('cd ', 'cd '),
    ToolSnippet('ls ', 'ls '),
    ToolSnippet('grep ', 'grep '),
    ToolSnippet('sed ', 'sed '),
    ToolSnippet('awk ', 'awk '),
    ToolSnippet('curl ', 'curl '),
    ToolSnippet('chmod +x ', 'chmod +x '),
  ];

  /// Python 常用语法。
  static const List<ToolSnippet> python = [
    ToolSnippet('def ', 'def '),
    ToolSnippet('class ', 'class '),
    ToolSnippet('return ', 'return '),
    ToolSnippet('import ', 'import '),
    ToolSnippet('from ', 'from '),
    ToolSnippet('if __name__', 'if __name__ == "__main__":'),
    ToolSnippet('print()', 'print()'),
    ToolSnippet('lambda ', 'lambda '),
    ToolSnippet('self', 'self'),
    ToolSnippet('None', 'None'),
    ToolSnippet('True', 'True'),
    ToolSnippet('False', 'False'),
    ToolSnippet('[]', '[]'),
    ToolSnippet('{}', '{}'),
    ToolSnippet('()', '()'),
    ToolSnippet(':', ':'),
    ToolSnippet('f""', 'f""'),
    ToolSnippet('@', '@'),
  ];

  /// Java 常用语法。
  static const List<ToolSnippet> java = [
    ToolSnippet('public class ', 'public class '),
    ToolSnippet('main()', 'public static void main(String[] args) {}'),
    ToolSnippet('private ', 'private '),
    ToolSnippet('public ', 'public '),
    ToolSnippet('static ', 'static '),
    ToolSnippet('void ', 'void '),
    ToolSnippet('new ', 'new '),
    ToolSnippet('return ', 'return '),
    ToolSnippet('System.out.println()', 'System.out.println()'),
    ToolSnippet('String', 'String'),
    ToolSnippet('int', 'int'),
    ToolSnippet('boolean', 'boolean'),
    ToolSnippet('import ', 'import '),
    ToolSnippet('@Override', '@Override'),
    ToolSnippet('extends ', 'extends '),
    ToolSnippet('implements ', 'implements '),
    ToolSnippet('{ }', '{}'),
    ToolSnippet(';', ';'),
  ];

  /// Go 常用语法。
  static const List<ToolSnippet> go = [
    ToolSnippet('package ', 'package '),
    ToolSnippet('import ', 'import '),
    ToolSnippet('func ', 'func '),
    ToolSnippet('return ', 'return '),
    ToolSnippet('if err != nil', 'if err != nil {\n\treturn\n}'),
    ToolSnippet('for ', 'for '),
    ToolSnippet(':=', ':='),
    ToolSnippet('var ', 'var '),
    ToolSnippet('struct ', 'type  struct {\n\n}'),
    ToolSnippet('interface ', 'type  interface {\n\n}'),
    ToolSnippet('error', 'error'),
    ToolSnippet('nil', 'nil'),
    ToolSnippet('defer ', 'defer '),
    ToolSnippet('go ', 'go '),
    ToolSnippet('chan ', 'chan '),
    ToolSnippet('fmt.Println()', 'fmt.Println()'),
  ];

  /// Dart 常用语法。
  static const List<ToolSnippet> dart = [
    ToolSnippet('class ', 'class '),
    ToolSnippet('void ', 'void '),
    ToolSnippet('final ', 'final '),
    ToolSnippet('var ', 'var '),
    ToolSnippet('const ', 'const '),
    ToolSnippet('late ', 'late '),
    ToolSnippet('required ', 'required '),
    ToolSnippet('return ', 'return '),
    ToolSnippet('Future', 'Future'),
    ToolSnippet('async ', 'async '),
    ToolSnippet('await ', 'await '),
    ToolSnippet('@override', '@override'),
    ToolSnippet('=>', '=>'),
    ToolSnippet('{ }', '{}'),
    ToolSnippet('[ ]', '[]'),
    ToolSnippet('( )', '()'),
    ToolSnippet(';', ';'),
    ToolSnippet(': ', ': '),
  ];

  /// 按文本编辑页的语言标签选出对应的常用符号集。
  static List<ToolSnippet> forLanguage(String langLabel) {
    switch (langLabel) {
      case 'HTTP':
        return http;
      case 'JSON':
        return json;
      case 'XML / HTML':
        return xml;
      case 'JavaScript':
        return javascript;
      case 'TypeScript':
        return typescript;
      case 'CSS':
        return css;
      case 'SQL':
        return sql;
      case 'YAML':
        return yaml;
      case 'Markdown':
        return markdown;
      case 'Bash':
        return bash;
      case 'Python':
        return python;
      case 'Java':
        return java;
      case 'Go':
        return go;
      case 'Dart':
        return dart;
      default:
        return editor;
    }
  }
}



/// 「快捷插入」条目的持久化存储。
///
/// 约定：未自定义（键不存在或为空串）时返回 null，调用方回退到内置默认；
/// 用户清空后写入 `[]`，表示"确实不要任何条目"。
/// 文本编辑页按语言生成持久化 scope：每种格式各自记住自己的自定义条目。
String editorSnippetScope(String langLabel) =>
    'editor_${langLabel.replaceAll(RegExp('[^A-Za-z0-9]'), '_').toLowerCase()}';

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

  /// 全局「共用符号库」存储键：任意页面新增过的自定义条目都进这里，跨页共享。
  static const String customKey = 'tool_snippets_custom_v1';

  /// 读取共用符号库。
  static Future<List<ToolSnippet>> loadCustom() async {
    try {
      final raw = await SharedPreferencesAsync().getString(customKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map(ToolSnippet.fromJson).whereType<ToolSnippet>().toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveCustom(List<ToolSnippet> items) async {
    await SharedPreferencesAsync().setString(customKey, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  /// 追加进共用符号库（按插入文本去重），返回追加后的完整库。
  static Future<List<ToolSnippet>> appendCustom(Iterable<ToolSnippet> items) async {
    final cur = await loadCustom();
    final seen = <String>{for (final e in cur) e.insert};
    final out = <ToolSnippet>[...cur];
    for (final e in items) {
      if (e.insert.isEmpty || seen.contains(e.insert)) continue;
      seen.add(e.insert);
      out.add(e);
    }
    if (out.length != cur.length) await saveCustom(out);
    return out;
  }
}

