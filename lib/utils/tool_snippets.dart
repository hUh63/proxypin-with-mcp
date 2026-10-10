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
    // 常用模式
    ToolSnippet('邮箱', r'[\w.%+-]+@[\w.-]+\.[A-Za-z]{2,}'),
    ToolSnippet('URL', r'''https?://[^\s"'<>]+'''),
    ToolSnippet('IPv4', r'(\d{1,3}\.){3}\d{1,3}'),
    ToolSnippet('手机号', r'1[3-9]\d{9}'),
    ToolSnippet('日期', r'\d{4}-\d{2}-\d{2}'),
    ToolSnippet('时间', r'([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?'),
    ToolSnippet('中文', r'[\u4e00-\u9fa5]+'),
    ToolSnippet('整数', r'-?\d+'),
    ToolSnippet('小数', r'-?\d+(\.\d+)?'),
    ToolSnippet('十六进制颜色', r'#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})\b'),
    ToolSnippet('身份证', r'\d{17}[\dXx]'),
    ToolSnippet('邮编', r'[1-9]\d{5}'),
    ToolSnippet('用户名', r'[A-Za-z][A-Za-z0-9_]{3,15}'),
    ToolSnippet('强密码', r'(?=.*[a-z])(?=.*[A-Z])(?=.*\d)[A-Za-z\d@$!%*?&]{8,}'),
    ToolSnippet('HTML 标签', r'<([a-zA-Z][\w-]*)\b[^>]*>(.*?)</\1>'),
    ToolSnippet('双引号内容', r'"([^"\\]|\\.)*"'),
    ToolSnippet('首尾空白', r'^\s+|\s+$'),
    ToolSnippet('连续空行', r'(\r?\n){2,}'),
    ToolSnippet('重复单词', r'\b(\w+)\s+\1\b'),
    ToolSnippet('驼峰转下划线', '([a-z0-9])([A-Z])'),
    ToolSnippet('匹配整行', '^.*$'),
  ];

  /// 文本编辑页：常用符号 / 全角标点 / 数学与特殊符号 / 制表符与空白。
  static const List<ToolSnippet> editor = [
    // 箭头
    ToolSnippet('→', '→'),
    ToolSnippet('←', '←'),
    ToolSnippet('↑', '↑'),
    ToolSnippet('↓', '↓'),
    ToolSnippet('↔', '↔'),
    ToolSnippet('⇒', '⇒'),
    ToolSnippet('⇔', '⇔'),
    ToolSnippet('⇄', '⇄'),
    ToolSnippet('⟶', '⟶'),
    ToolSnippet('⟵', '⟵'),
    ToolSnippet('↩', '↩'),
    ToolSnippet('↪', '↪'),
    ToolSnippet('⇧', '⇧'),
    ToolSnippet('⇩', '⇩'),
    // 勾叉 / 星 / 几何
    ToolSnippet('✓', '✓'),
    ToolSnippet('✗', '✗'),
    ToolSnippet('✔', '✔'),
    ToolSnippet('✘', '✘'),
    ToolSnippet('☑', '☑'),
    ToolSnippet('☐', '☐'),
    ToolSnippet('★', '★'),
    ToolSnippet('☆', '☆'),
    ToolSnippet('●', '●'),
    ToolSnippet('○', '○'),
    ToolSnippet('◆', '◆'),
    ToolSnippet('◇', '◇'),
    ToolSnippet('■', '■'),
    ToolSnippet('□', '□'),
    ToolSnippet('▪', '▪'),
    ToolSnippet('▫', '▫'),
    ToolSnippet('▲', '▲'),
    ToolSnippet('△', '△'),
    ToolSnippet('▼', '▼'),
    ToolSnippet('▽', '▽'),
    ToolSnippet('▶', '▶'),
    ToolSnippet('◀', '◀'),
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
    ToolSnippet('∝', '∝'),
    ToolSnippet('∵', '∵'),
    ToolSnippet('∴', '∴'),
    ToolSnippet('∫', '∫'),
    ToolSnippet('∂', '∂'),
    ToolSnippet('∆', '∆'),
    ToolSnippet('∇', '∇'),
    ToolSnippet('≡', '≡'),
    ToolSnippet('≌', '≌'),
    ToolSnippet('≫', '≫'),
    ToolSnippet('≪', '≪'),
    ToolSnippet('⊕', '⊕'),
    ToolSnippet('⊗', '⊗'),
    ToolSnippet('∈', '∈'),
    ToolSnippet('∉', '∉'),
    ToolSnippet('⊂', '⊂'),
    ToolSnippet('⊃', '⊃'),
    ToolSnippet('∪', '∪'),
    ToolSnippet('∩', '∩'),
    ToolSnippet('∅', '∅'),
    ToolSnippet('∀', '∀'),
    ToolSnippet('∃', '∃'),
    ToolSnippet('∠', '∠'),
    ToolSnippet('⊥', '⊥'),
    ToolSnippet('∥', '∥'),
    // 标点 / 符号
    ToolSnippet('—', '—'),
    ToolSnippet('–', '–'),
    ToolSnippet('…', '…'),
    ToolSnippet('·', '·'),
    ToolSnippet('•', '•'),
    ToolSnippet('‥', '‥'),
    ToolSnippet('※', '※'),
    ToolSnippet('†', '†'),
    ToolSnippet('‡', '‡'),
    ToolSnippet('§', '§'),
    ToolSnippet('¶', '¶'),
    ToolSnippet('№', '№'),
    ToolSnippet('℡', '℡'),
    ToolSnippet('°', '°'),
    ToolSnippet('‰', '‰'),
    ToolSnippet('℃', '℃'),
    ToolSnippet('℉', '℉'),
    ToolSnippet('µ', 'µ'),
    ToolSnippet('Ω', 'Ω'),
    ToolSnippet('Å', 'Å'),
    // 货币
    ToolSnippet('€', '€'),
    ToolSnippet('£', '£'),
    ToolSnippet('¥', '¥'),
    ToolSnippet('$', '$'),
    ToolSnippet('¢', '¢'),
    ToolSnippet('₩', '₩'),
    ToolSnippet('₹', '₹'),
    ToolSnippet('₽', '₽'),
    // 圈号 / 罗马数字
    ToolSnippet('①', '①'),
    ToolSnippet('②', '②'),
    ToolSnippet('③', '③'),
    ToolSnippet('④', '④'),
    ToolSnippet('⑤', '⑤'),
    ToolSnippet('⑩', '⑩'),
    ToolSnippet('㈠', '㈠'),
    ToolSnippet('㈡', '㈡'),
    ToolSnippet('Ⅰ', 'Ⅰ'),
    ToolSnippet('Ⅱ', 'Ⅱ'),
    ToolSnippet('Ⅲ', 'Ⅲ'),
    ToolSnippet('Ⅳ', 'Ⅳ'),
    ToolSnippet('Ⅴ', 'Ⅴ'),
    // 其他
    ToolSnippet('♠', '♠'),
    ToolSnippet('♥', '♥'),
    ToolSnippet('♦', '♦'),
    ToolSnippet('♣', '♣'),
    ToolSnippet('♪', '♪'),
    ToolSnippet('♫', '♫'),
    ToolSnippet('☀', '☀'),
    ToolSnippet('☂', '☂'),
    ToolSnippet('©', '©'),
    ToolSnippet('®', '®'),
    ToolSnippet('™', '™'),
    // 全角标点
    ToolSnippet('，', '，'),
    ToolSnippet('。', '。'),
    ToolSnippet('、', '、'),
    ToolSnippet('；', '；'),
    ToolSnippet('：', '：'),
    ToolSnippet('！', '！'),
    ToolSnippet('？', '？'),
    ToolSnippet('“”', '“”'),
    ToolSnippet('‘’', '‘’'),
    ToolSnippet('《》', '《》'),
    ToolSnippet('【】', '【】'),
    ToolSnippet('「」', '「」'),
    ToolSnippet('『』', '『』'),
    ToolSnippet('〈〉', '〈〉'),
    ToolSnippet('（）', '（）'),
    // 空白 / 制表
    ToolSnippet('Tab', '\t'),
    ToolSnippet('CRLF', '\r\n'),
    ToolSnippet('LF', '\n'),
    ToolSnippet('NBSP', '\u00a0'),
    ToolSnippet('零宽空格', '\u200b'),
    ToolSnippet('全角空格', '\u3000'),
    ToolSnippet('BOM', '\ufeff'),
  ];

  /// JSON 查看页：结构符号 / 字面量 / 转义。
  static const List<ToolSnippet> json = [
    ToolSnippet('{ }', '{}'),
    ToolSnippet('[ ]', '[]'),
    ToolSnippet('\"key\": ', '\"key\": '),
    ToolSnippet('\"key\": \"value\"', '\"key\": \"value\"'),
    ToolSnippet('\"value\"', '\"value\"'),
    ToolSnippet(': ', ': '),
    ToolSnippet(', ', ', '),
    ToolSnippet('null', 'null'),
    ToolSnippet('true', 'true'),
    ToolSnippet('false', 'false'),
    ToolSnippet('0', '0'),
    ToolSnippet('1', '1'),
    ToolSnippet('\"\"', '\"\"'),
    ToolSnippet('空数组', '[]'),
    ToolSnippet('空对象', '{}'),
    ToolSnippet('对象数组', '[\n  {},\n  {}\n]'),
    ToolSnippet('转义引号', '\\\"'),
    ToolSnippet('转义反斜杠', '\\\\'),
    ToolSnippet('换行转义', '\\n'),
    ToolSnippet('制表转义', '\\t'),
    ToolSnippet('Unicode 转义', '\\u0000'),
  ];

  /// XML / HTML 查看页：标签 / 属性 / 注释 / CDATA / 实体。
  static const List<ToolSnippet> xml = [
    ToolSnippet('<?xml ?>', '<?xml version=\"1.0\" encoding=\"UTF-8\"?>'),
    ToolSnippet('<!DOCTYPE html>', '<!DOCTYPE html>'),
    ToolSnippet('<!-- -->', '<!--  -->'),
    ToolSnippet('<![CDATA[ ]]>', '<![CDATA[  ]]>'),
    ToolSnippet('xmlns=', 'xmlns=\"\"'),
    ToolSnippet('id=', 'id=\"\"'),
    ToolSnippet('class=', 'class=\"\"'),
    ToolSnippet('style=', 'style=\"\"'),
    ToolSnippet('name=', 'name=\"\"'),
    ToolSnippet('type=', 'type=\"\"'),
    ToolSnippet('value=', 'value=\"\"'),
    ToolSnippet('content=', 'content=\"\"'),
    ToolSnippet('href=', 'href=\"\"'),
    ToolSnippet('src=', 'src=\"\"'),
    ToolSnippet('alt=', 'alt=\"\"'),
    ToolSnippet('<div></div>', '<div></div>'),
    ToolSnippet('<span></span>', '<span></span>'),
    ToolSnippet('<p></p>', '<p></p>'),
    ToolSnippet('<a href="">', '<a href=\"\"></a>'),
    ToolSnippet('<img src="">', '<img src=\"\" alt=\"\">'),
    ToolSnippet('<input />', '<input type=\"text\" />'),
    ToolSnippet('<button></button>', '<button></button>'),
    ToolSnippet('<ul><li></li></ul>', '<ul>\n  <li></li>\n</ul>'),
    ToolSnippet('<table></table>', '<table>\n  <tr><td></td></tr>\n</table>'),
    ToolSnippet('<link rel="">', '<link rel=\"stylesheet\" href=\"\">'),
    ToolSnippet('<script></script>', '<script></script>'),
    ToolSnippet('<style></style>', '<style></style>'),
    ToolSnippet('<meta charset>', '<meta charset=\"UTF-8\">'),
    ToolSnippet('&amp;', '&amp;'),
    ToolSnippet('&lt;', '&lt;'),
    ToolSnippet('&gt;', '&gt;'),
    ToolSnippet('&quot;', '&quot;'),
    ToolSnippet('&apos;', '&apos;'),
    ToolSnippet('&nbsp;', '&nbsp;'),
  ];

  /// HTTP 报文：方法 / 常见请求头 / 行结束符。
  static const List<ToolSnippet> http = [
    ToolSnippet('GET / HTTP/1.1', 'GET / HTTP/1.1'),
    ToolSnippet('POST  HTTP/1.1', 'POST  HTTP/1.1'),
    ToolSnippet('HTTP/1.1 200 OK', 'HTTP/1.1 200 OK'),
    ToolSnippet('GET ', 'GET '),
    ToolSnippet('POST ', 'POST '),
    ToolSnippet('PUT ', 'PUT '),
    ToolSnippet('DELETE ', 'DELETE '),
    ToolSnippet('PATCH ', 'PATCH '),
    ToolSnippet('HEAD ', 'HEAD '),
    ToolSnippet('OPTIONS ', 'OPTIONS '),
    ToolSnippet('Host: ', 'Host: '),
    ToolSnippet('Content-Type: ', 'Content-Type: '),
    ToolSnippet('Content-Type: json', 'Content-Type: application/json'),
    ToolSnippet('Content-Type: form', 'Content-Type: application/x-www-form-urlencoded'),
    ToolSnippet('Content-Length: ', 'Content-Length: '),
    ToolSnippet('Authorization: ', 'Authorization: '),
    ToolSnippet('Authorization: Bearer ', 'Authorization: Bearer '),
    ToolSnippet('Cookie: ', 'Cookie: '),
    ToolSnippet('Set-Cookie: ', 'Set-Cookie: '),
    ToolSnippet('Accept: ', 'Accept: '),
    ToolSnippet('Accept: json', 'Accept: application/json'),
    ToolSnippet('Accept-Encoding: ', 'Accept-Encoding: gzip, deflate, br'),
    ToolSnippet('User-Agent: ', 'User-Agent: '),
    ToolSnippet('Referer: ', 'Referer: '),
    ToolSnippet('Origin: ', 'Origin: '),
    ToolSnippet('Cache-Control: ', 'Cache-Control: no-cache'),
    ToolSnippet('Connection: ', 'Connection: keep-alive'),
    ToolSnippet('X-Forwarded-For: ', 'X-Forwarded-For: '),
    ToolSnippet('X-Request-Id: ', 'X-Request-Id: '),
    ToolSnippet('\r\n', '\r\n'),
  ];

  /// JavaScript 常用语法 / 片段。
  static const List<ToolSnippet> javascript = [
    ToolSnippet('const ', 'const '),
    ToolSnippet('let ', 'let '),
    ToolSnippet('var ', 'var '),
    ToolSnippet('function ', 'function '),
    ToolSnippet('async function ', 'async function '),
    ToolSnippet('async () =>', 'async () => {}'),
    ToolSnippet('() =>', '() => {}'),
    ToolSnippet('return ', 'return '),
    ToolSnippet('await ', 'await '),
    ToolSnippet('if (', 'if ()'),
    ToolSnippet('else {', 'else {\n\n}'),
    ToolSnippet('for (const ', 'for (const x of ) {\n\n}'),
    ToolSnippet('for (let i', 'for (let i = 0; i < ; i++) {\n\n}'),
    ToolSnippet('while (', 'while ()'),
    ToolSnippet('switch (', 'switch () {\ncase :\n}'),
    ToolSnippet('try {', 'try {\n\n} catch (e) {\n\n}'),
    ToolSnippet('throw new Error()', 'throw new Error()'),
    ToolSnippet('console.log()', 'console.log()'),
    ToolSnippet('setTimeout()', 'setTimeout(() => {\n\n}, 0)'),
    ToolSnippet('setInterval()', 'setInterval(() => {\n\n}, 1000)'),
    ToolSnippet('addEventListener()', "addEventListener('click', () => {})"),
    ToolSnippet('querySelector()', "document.querySelector('')"),
    ToolSnippet('document.', 'document.'),
    ToolSnippet('window.', 'window.'),
    ToolSnippet('JSON.parse()', 'JSON.parse()'),
    ToolSnippet('JSON.stringify()', 'JSON.stringify()'),
    ToolSnippet('Object.keys()', 'Object.keys()'),
    ToolSnippet('Object.entries()', 'Object.entries()'),
    ToolSnippet('Object.assign()', 'Object.assign()'),
    ToolSnippet('Array.from()', 'Array.from()'),
    ToolSnippet('Array.isArray()', 'Array.isArray()'),
    ToolSnippet('.map()', '.map()'),
    ToolSnippet('.filter()', '.filter()'),
    ToolSnippet('.reduce()', '.reduce()'),
    ToolSnippet('.forEach()', '.forEach()'),
    ToolSnippet('.includes()', '.includes()'),
    ToolSnippet('.indexOf()', '.indexOf()'),
    ToolSnippet('.slice()', '.slice()'),
    ToolSnippet('.splice()', '.splice()'),
    ToolSnippet('.join()', '.join()'),
    ToolSnippet('.split()', '.split()'),
    ToolSnippet('.replace()', '.replace()'),
    ToolSnippet('.trim()', '.trim()'),
    ToolSnippet('.then()', '.then()'),
    ToolSnippet('.catch()', '.catch()'),
    ToolSnippet('import { } from ', 'import {  } from '),
    ToolSnippet('export default ', 'export default '),
    ToolSnippet('export const ', 'export const '),
    ToolSnippet('require()', 'require()'),
    ToolSnippet('module.exports', 'module.exports'),
    ToolSnippet('Promise.all()', 'Promise.all()'),
    ToolSnippet('=> ', '=> '),
    ToolSnippet('...', '...'),
    ToolSnippet('===', '==='),
    ToolSnippet('!==', '!=='),
    ToolSnippet('&&', '&&'),
    ToolSnippet('||', '||'),
    ToolSnippet('??', '??'),
    ToolSnippet('?.', '?.'),
    ToolSnippet('{ }', '{}'),
    ToolSnippet('[ ]', '[]'),
    ToolSnippet('( )', '()'),
    ToolSnippet(';', ';'),
    ToolSnippet(',', ', '),
    ToolSnippet(': ', ': '),
    ToolSnippet(r'`${ }`', r'`${}`'),
  ];

  /// TypeScript 常用语法 / 片段。
  static const List<ToolSnippet> typescript = [
    ToolSnippet('interface ', 'interface  {\n\n}'),
    ToolSnippet('type ', 'type  = '),
    ToolSnippet('enum ', 'enum  {\n\n}'),
    ToolSnippet('namespace ', 'namespace '),
    ToolSnippet('declare ', 'declare '),
    ToolSnippet('export ', 'export '),
    ToolSnippet('export default ', 'export default '),
    ToolSnippet('export type ', 'export type '),
    ToolSnippet('import ', 'import '),
    ToolSnippet('import type ', 'import type '),
    ToolSnippet('abstract ', 'abstract '),
    ToolSnippet('implements ', 'implements '),
    ToolSnippet('extends ', 'extends '),
    ToolSnippet('readonly ', 'readonly '),
    ToolSnippet('private ', 'private '),
    ToolSnippet('public ', 'public '),
    ToolSnippet('protected ', 'protected '),
    ToolSnippet('static ', 'static '),
    ToolSnippet('as ', 'as '),
    ToolSnippet('satisfies ', 'satisfies '),
    ToolSnippet('keyof ', 'keyof '),
    ToolSnippet('typeof ', 'typeof '),
    ToolSnippet('infer ', 'infer '),
    ToolSnippet('async ', 'async '),
    ToolSnippet('await ', 'await '),
    ToolSnippet('function ', 'function '),
    ToolSnippet('const ', 'const '),
    ToolSnippet('let ', 'let '),
    ToolSnippet('return ', 'return '),
    ToolSnippet('string', 'string'),
    ToolSnippet('number', 'number'),
    ToolSnippet('boolean', 'boolean'),
    ToolSnippet('void', 'void'),
    ToolSnippet('any', 'any'),
    ToolSnippet('unknown', 'unknown'),
    ToolSnippet('never', 'never'),
    ToolSnippet('object', 'object'),
    ToolSnippet('Partial<', 'Partial<>'),
    ToolSnippet('Required<', 'Required<>'),
    ToolSnippet('Readonly<', 'Readonly<>'),
    ToolSnippet('Record<', 'Record<, >'),
    ToolSnippet('Pick<', 'Pick<, >'),
    ToolSnippet('Omit<', 'Omit<, >'),
    ToolSnippet('Promise<', 'Promise<>'),
    ToolSnippet('Array<', 'Array<>'),
    ToolSnippet('(): void =>', '(): void => {}'),
    ToolSnippet('?: ', '?: '),
    ToolSnippet('??', '??'),
    ToolSnippet('??=', '??='),
    ToolSnippet('?.', '?.'),
    ToolSnippet('=>', '=>'),
    ToolSnippet('<>', '<>'),
    ToolSnippet('{ }', '{}'),
    ToolSnippet('[ ]', '[]'),
    ToolSnippet('( )', '()'),
    ToolSnippet(';', ';'),
    ToolSnippet('console.log()', 'console.log()'),
    ToolSnippet(r'`${ }`', r'`${}`'),
  ];

  /// CSS 常用属性 / 语法片段。
  static const List<ToolSnippet> css = [
    ToolSnippet('{ }', '{}'),
    ToolSnippet(': ', ': '),
    ToolSnippet(';', ';'),
    ToolSnippet('.class', '.class'),
    ToolSnippet('#id', '#id'),
    ToolSnippet('* ', '* '),
    ToolSnippet(':root', ':root'),
    ToolSnippet(':hover', ':hover'),
    ToolSnippet('::before', '::before'),
    ToolSnippet('::after', '::after'),
    ToolSnippet(':nth-child()', ':nth-child()'),
    ToolSnippet('> ', ' > '),
    ToolSnippet('+ ', ' + '),
    ToolSnippet('[attr]', '[]'),
    ToolSnippet('/* */', '/*  */'),
    ToolSnippet('!important', ' !important'),
    ToolSnippet('@media', '@media (max-width: 768px) {\n\n}'),
    ToolSnippet('@keyframes', '@keyframes  {\n\n}'),
    ToolSnippet('@import', '@import '),
    ToolSnippet('@font-face', '@font-face {\n\n}'),
    ToolSnippet('@supports', '@supports () {\n\n}'),
    ToolSnippet('display: flex;', 'display: flex;'),
    ToolSnippet('display: grid;', 'display: grid;'),
    ToolSnippet('display: none;', 'display: none;'),
    ToolSnippet('position: absolute;', 'position: absolute;'),
    ToolSnippet('position: relative;', 'position: relative;'),
    ToolSnippet('margin: 0 auto;', 'margin: 0 auto;'),
    ToolSnippet('padding: ', 'padding: '),
    ToolSnippet('color: ', 'color: '),
    ToolSnippet('background: ', 'background: '),
    ToolSnippet('font-size: ', 'font-size: '),
    ToolSnippet('font-weight: ', 'font-weight: '),
    ToolSnippet('line-height: ', 'line-height: '),
    ToolSnippet('text-align: center;', 'text-align: center;'),
    ToolSnippet('justify-content: center;', 'justify-content: center;'),
    ToolSnippet('align-items: center;', 'align-items: center;'),
    ToolSnippet('flex: 1;', 'flex: 1;'),
    ToolSnippet('grid-template-columns', 'grid-template-columns: repeat(12, minmax(0, 1fr));'),
    ToolSnippet('gap: ', 'gap: '),
    ToolSnippet('width: 100%;', 'width: 100%;'),
    ToolSnippet('height: 100%;', 'height: 100%;'),
    ToolSnippet('overflow: hidden;', 'overflow: hidden;'),
    ToolSnippet('border-radius: ', 'border-radius: '),
    ToolSnippet('box-shadow', 'box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);'),
    ToolSnippet('cursor: pointer;', 'cursor: pointer;'),
    ToolSnippet('opacity: ', 'opacity: '),
    ToolSnippet('transition', 'transition: all 0.3s ease;'),
    ToolSnippet('transform', 'transform: translate(-50%, -50%);'),
    ToolSnippet('z-index: ', 'z-index: '),
    ToolSnippet('calc()', 'calc()'),
    ToolSnippet('var(--)', 'var(--)'),
    ToolSnippet('rgba()', 'rgba(0, 0, 0, 0.5)'),
    ToolSnippet('px', 'px'),
    ToolSnippet('rem', 'rem'),
    ToolSnippet('%', '%'),
  ];

  /// SQL 常用关键字 / 片段。
  static const List<ToolSnippet> sql = [
    ToolSnippet('SELECT ', 'SELECT '),
    ToolSnippet('SELECT * FROM ', 'SELECT * FROM '),
    ToolSnippet('FROM ', 'FROM '),
    ToolSnippet('WHERE ', 'WHERE '),
    ToolSnippet('JOIN ', 'JOIN '),
    ToolSnippet('LEFT JOIN ', 'LEFT JOIN '),
    ToolSnippet('RIGHT JOIN ', 'RIGHT JOIN '),
    ToolSnippet('INNER JOIN ', 'INNER JOIN '),
    ToolSnippet('FULL JOIN ', 'FULL JOIN '),
    ToolSnippet('CROSS JOIN ', 'CROSS JOIN '),
    ToolSnippet('ON ', 'ON '),
    ToolSnippet('GROUP BY ', 'GROUP BY '),
    ToolSnippet('ORDER BY ', 'ORDER BY '),
    ToolSnippet('HAVING ', 'HAVING '),
    ToolSnippet('LIMIT ', 'LIMIT '),
    ToolSnippet('OFFSET ', 'OFFSET '),
    ToolSnippet('UNION ALL', 'UNION ALL'),
    ToolSnippet('DISTINCT ', 'DISTINCT '),
    ToolSnippet('INSERT INTO ', 'INSERT INTO '),
    ToolSnippet('VALUES ', 'VALUES '),
    ToolSnippet('UPDATE ', 'UPDATE '),
    ToolSnippet('SET ', 'SET '),
    ToolSnippet('DELETE FROM ', 'DELETE FROM '),
    ToolSnippet('CREATE TABLE ', 'CREATE TABLE  (\n\n);'),
    ToolSnippet('ALTER TABLE ', 'ALTER TABLE '),
    ToolSnippet('DROP TABLE ', 'DROP TABLE '),
    ToolSnippet('CREATE INDEX ', 'CREATE INDEX  ON  ();'),
    ToolSnippet('PRIMARY KEY', 'PRIMARY KEY'),
    ToolSnippet('FOREIGN KEY', 'FOREIGN KEY'),
    ToolSnippet('NOT NULL', 'NOT NULL'),
    ToolSnippet('DEFAULT ', 'DEFAULT '),
    ToolSnippet('AUTO_INCREMENT', 'AUTO_INCREMENT'),
    ToolSnippet('COUNT(*)', 'COUNT(*)'),
    ToolSnippet('SUM()', 'SUM()'),
    ToolSnippet('AVG()', 'AVG()'),
    ToolSnippet('MAX()', 'MAX()'),
    ToolSnippet('MIN()', 'MIN()'),
    ToolSnippet('COALESCE()', 'COALESCE()'),
    ToolSnippet('CASE WHEN ', 'CASE WHEN  THEN  ELSE  END'),
    ToolSnippet('IS NULL', 'IS NULL'),
    ToolSnippet('IS NOT NULL', 'IS NOT NULL'),
    ToolSnippet('LIKE ', "LIKE '%"),
    ToolSnippet('IN (', 'IN ()'),
    ToolSnippet('BETWEEN ', 'BETWEEN  AND '),
    ToolSnippet('EXISTS (', 'EXISTS ()'),
    ToolSnippet('AS ', ' AS '),
    ToolSnippet(' AND ', ' AND '),
    ToolSnippet(' OR ', ' OR '),
    ToolSnippet('NULL', 'NULL'),
    ToolSnippet('ASC', 'ASC'),
    ToolSnippet('DESC', 'DESC'),
    ToolSnippet(';', ';'),
  ];

  /// YAML 常用结构。
  static const List<ToolSnippet> yaml = [
    ToolSnippet('---', '---'),
    ToolSnippet('...', '...'),
    ToolSnippet('key: ', 'key: '),
    ToolSnippet('key: value', 'key: value'),
    ToolSnippet('- ', '- '),
    ToolSnippet('- item', '- item'),
    ToolSnippet('- key: ', '- key: '),
    ToolSnippet('# ', '# '),
    ToolSnippet('nested:', 'key:\n  nested: '),
    ToolSnippet('map: {}', 'map: {}'),
    ToolSnippet('list: []', 'list: []'),
    ToolSnippet('|', '|'),
    ToolSnippet('|-', '|-'),
    ToolSnippet('|+', '|+'),
    ToolSnippet('>', '>'),
    ToolSnippet('>-', '>-'),
    ToolSnippet('&anchor', '&anchor '),
    ToolSnippet('*alias', '*alias'),
    ToolSnippet('<<: *', '<<: *'),
    ToolSnippet('!!str', '!!str '),
    ToolSnippet('true', 'true'),
    ToolSnippet('false', 'false'),
    ToolSnippet('null', 'null'),
    ToolSnippet('~', '~'),
    ToolSnippet('[]', '[]'),
    ToolSnippet('{}', '{}'),
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
    ToolSnippet('表格 2 列', '| 列 1 | 列 2 |\n| --- | --- |\n|  |  |'),
    ToolSnippet('表格 3 列', '| 列 1 | 列 2 | 列 3 |\n| --- | --- | --- |\n|  |  |  |'),
    ToolSnippet('表格 3 列(居中)', '| 列 1 | 列 2 | 列 3 |\n| :---: | :---: | :---: |\n|  |  |  |'),
    ToolSnippet('代码块', '```\n\n```'),
    ToolSnippet('提示块', '> **Note**\n> '),
    ToolSnippet('分隔线', '---'),
    ToolSnippet('目录项', '- [标题](#锚点)'),
    ToolSnippet('脚注', '[^1]'),
    ToolSnippet('折叠块', '<details>\n<summary>展开</summary>\n\n</details>'),
  ];

  /// Bash / Shell 常用语法。
  static const List<ToolSnippet> bash = [
    ToolSnippet('#!/bin/bash', '#!/bin/bash'),
    ToolSnippet('#!/bin/sh', '#!/bin/sh'),
    ToolSnippet('set -euo pipefail', 'set -euo pipefail'),
    ToolSnippet(r'$', r'$'),
    ToolSnippet(' | ', ' | '),
    ToolSnippet(' > ', ' > '),
    ToolSnippet(' >> ', ' >> '),
    ToolSnippet('2>&1', ' 2>&1'),
    ToolSnippet('/dev/null', ' /dev/null'),
    ToolSnippet(' && ', ' && '),
    ToolSnippet(' || ', ' || '),
    ToolSnippet(';', ';'),
    ToolSnippet(r'$( )', r'$( )'),
    ToolSnippet(r'${}', r'${}'),
    ToolSnippet(r'${1:-}', r'${1:-}'),
    ToolSnippet('$1', '$1'),
    ToolSnippet('$@', '$@'),
    ToolSnippet(r'$?', r'$?'),
    ToolSnippet('if [ ]', 'if [  ]; then\n\nfi'),
    ToolSnippet('if [[ ]]', 'if [[  ]]; then\n\nfi'),
    ToolSnippet('elif', 'elif [  ]; then'),
    ToolSnippet('else', 'else\n\nfi'),
    ToolSnippet('for in', 'for x in ; do\n\n done'),
    ToolSnippet('for ((', 'for ((i = 0; i < ; i++)); do\n\n done'),
    ToolSnippet('while read', 'while read -r line; do\n\n done'),
    ToolSnippet('case ', 'case  in\n  ) ;;\n  *) ;;\nesac'),
    ToolSnippet('case in esac', 'case  in\n\n  *) ;;\nesac'),
    ToolSnippet('function ', 'function  {\n\n}'),
    ToolSnippet('local ', 'local '),
    ToolSnippet('export ', 'export '),
    ToolSnippet('read -p ', 'read -p \"\" '),
    ToolSnippet('trap ', 'trap  EXIT'),
    ToolSnippet('exit ', 'exit '),
    ToolSnippet('test -f ', 'test -f '),
    ToolSnippet('test -d ', 'test -d '),
    ToolSnippet('echo ', 'echo '),
    ToolSnippet('printf ', 'printf '),
    ToolSnippet('cd ', 'cd '),
    ToolSnippet('ls -l', 'ls -l'),
    ToolSnippet('pwd', 'pwd'),
    ToolSnippet('cat ', 'cat '),
    ToolSnippet('grep -rn ', 'grep -rn '),
    ToolSnippet('sed -i ', 'sed -i '),
    ToolSnippet('awk ', 'awk '),
    ToolSnippet('cut -d', "cut -d',' -f1"),
    ToolSnippet('tr ', 'tr '),
    ToolSnippet('sort | uniq -c', 'sort | uniq -c'),
    ToolSnippet('head -n ', 'head -n '),
    ToolSnippet('tail -f ', 'tail -f '),
    ToolSnippet('find . -name', "find . -name '*'"),
    ToolSnippet('xargs ', 'xargs '),
    ToolSnippet('curl ', 'curl -sSL '),
    ToolSnippet('wget ', 'wget '),
    ToolSnippet('tar -czf', 'tar -czf .tar.gz '),
    ToolSnippet('unzip ', 'unzip '),
    ToolSnippet('chmod +x ', 'chmod +x '),
    ToolSnippet('chown ', 'chown '),
    ToolSnippet('mkdir -p ', 'mkdir -p '),
    ToolSnippet('ps aux', 'ps aux'),
    ToolSnippet('kill -9 ', 'kill -9 '),
    ToolSnippet('df -h', 'df -h'),
    ToolSnippet('du -sh ', 'du -sh '),
  ];

  /// Python 常用语法 / 片段。
  static const List<ToolSnippet> python = [
    // 结构
    ToolSnippet('def ', 'def '),
    ToolSnippet('class ', 'class '),
    ToolSnippet('async def ', 'async def '),
    ToolSnippet('if ', 'if '),
    ToolSnippet('elif ', 'elif '),
    ToolSnippet('else:', 'else:'),
    ToolSnippet('for ', 'for '),
    ToolSnippet('while ', 'while '),
    ToolSnippet('try:', 'try:'),
    ToolSnippet('except ', 'except '),
    ToolSnippet('finally:', 'finally:'),
    ToolSnippet('with ', 'with '),
    ToolSnippet('match ', 'match '),
    ToolSnippet('case ', 'case '),
    ToolSnippet('return ', 'return '),
    ToolSnippet('yield ', 'yield '),
    ToolSnippet('await ', 'await '),
    ToolSnippet('lambda ', 'lambda '),
    ToolSnippet('raise ', 'raise '),
    ToolSnippet('assert ', 'assert '),
    ToolSnippet('global ', 'global '),
    ToolSnippet('nonlocal ', 'nonlocal '),
    ToolSnippet('pass', 'pass'),
    ToolSnippet('break', 'break'),
    ToolSnippet('continue', 'continue'),
    ToolSnippet('del ', 'del '),
    // 导入
    ToolSnippet('import ', 'import '),
    ToolSnippet('from ', 'from '),
    ToolSnippet('from x import ', 'from  import '),
    ToolSnippet('if __name__', 'if __name__ == \"__main__\":'),
    // 内置函数
    ToolSnippet('print()', 'print()'),
    ToolSnippet('len()', 'len()'),
    ToolSnippet('range()', 'range()'),
    ToolSnippet('enumerate()', 'enumerate()'),
    ToolSnippet('zip()', 'zip()'),
    ToolSnippet('sorted()', 'sorted()'),
    ToolSnippet('reversed()', 'reversed()'),
    ToolSnippet('sum()', 'sum()'),
    ToolSnippet('min()', 'min()'),
    ToolSnippet('max()', 'max()'),
    ToolSnippet('abs()', 'abs()'),
    ToolSnippet('round()', 'round()'),
    ToolSnippet('map()', 'map()'),
    ToolSnippet('filter()', 'filter()'),
    ToolSnippet('isinstance()', 'isinstance()'),
    ToolSnippet('open()', 'open()'),
    ToolSnippet('str()', 'str()'),
    ToolSnippet('int()', 'int()'),
    ToolSnippet('float()', 'float()'),
    ToolSnippet('list()', 'list()'),
    ToolSnippet('dict()', 'dict()'),
    ToolSnippet('set()', 'set()'),
    ToolSnippet('tuple()', 'tuple()'),
    ToolSnippet('super()', 'super()'),
    // 类 / 装饰器
    ToolSnippet('self', 'self'),
    ToolSnippet('def __init__', 'def __init__(self):'),
    ToolSnippet('@property', '@property'),
    ToolSnippet('@staticmethod', '@staticmethod'),
    ToolSnippet('@classmethod', '@classmethod'),
    // 字面量 / 运算符
    ToolSnippet('None', 'None'),
    ToolSnippet('True', 'True'),
    ToolSnippet('False', 'False'),
    ToolSnippet('not ', 'not '),
    ToolSnippet(' and ', ' and '),
    ToolSnippet(' or ', ' or '),
    ToolSnippet(' in ', ' in '),
    ToolSnippet(' is ', ' is '),
    ToolSnippet('f\"\"', 'f\"\"'),
    ToolSnippet('r\"\"', 'r\"\"'),
    ToolSnippet('-> ', '-> '),
    ToolSnippet('*args', '*args'),
    ToolSnippet('**kwargs', '**kwargs'),
    ToolSnippet('==', '=='),
    ToolSnippet('!=', '!='),
    ToolSnippet('//', '//'),
    ToolSnippet('+=', '+='),
    ToolSnippet('[]', '[]'),
    ToolSnippet('{}', '{}'),
    ToolSnippet('()', '()'),
    ToolSnippet(':', ':'),
    ToolSnippet('# ', '# '),
  ];

  /// Java 常用语法 / 片段。
  static const List<ToolSnippet> java = [
    ToolSnippet('class ', 'class '),
    ToolSnippet('interface ', 'interface '),
    ToolSnippet('enum ', 'enum '),
    ToolSnippet('record ', 'record '),
    ToolSnippet('public class ', 'public class '),
    ToolSnippet('main()', 'public static void main(String[] args) {}'),
    ToolSnippet('private ', 'private '),
    ToolSnippet('public ', 'public '),
    ToolSnippet('protected ', 'protected '),
    ToolSnippet('static ', 'static '),
    ToolSnippet('final ', 'final '),
    ToolSnippet('abstract ', 'abstract '),
    ToolSnippet('void ', 'void '),
    ToolSnippet('var ', 'var '),
    ToolSnippet('new ', 'new '),
    ToolSnippet('return ', 'return '),
    ToolSnippet('throw ', 'throw '),
    ToolSnippet('throws ', 'throws '),
    ToolSnippet('synchronized ', 'synchronized '),
    ToolSnippet('if (', 'if ()'),
    ToolSnippet('for (', 'for (int i = 0; i < ; i++) {}'),
    ToolSnippet('while (', 'while ()'),
    ToolSnippet('switch (', 'switch ()'),
    ToolSnippet('try {', 'try {\n\n} catch (Exception e) {\n\n}'),
    ToolSnippet('catch (', 'catch (Exception e) {\n\n}'),
    ToolSnippet('System.out.println()', 'System.out.println()'),
    ToolSnippet('String.format()', 'String.format()'),
    ToolSnippet('Integer.parseInt()', 'Integer.parseInt()'),
    ToolSnippet('List<', 'List<>'),
    ToolSnippet('Map<', 'Map<>'),
    ToolSnippet('Set<', 'Set<>'),
    ToolSnippet('new ArrayList<>()', 'new ArrayList<>()'),
    ToolSnippet('new HashMap<>()', 'new HashMap<>()'),
    ToolSnippet('Optional', 'Optional'),
    ToolSnippet('Stream', 'Stream'),
    ToolSnippet('String', 'String'),
    ToolSnippet('int', 'int'),
    ToolSnippet('long', 'long'),
    ToolSnippet('double', 'double'),
    ToolSnippet('boolean', 'boolean'),
    ToolSnippet('import ', 'import '),
    ToolSnippet('package ', 'package '),
    ToolSnippet('@Override', '@Override'),
    ToolSnippet('@Test', '@Test'),
    ToolSnippet('@Autowired', '@Autowired'),
    ToolSnippet('extends ', 'extends '),
    ToolSnippet('implements ', 'implements '),
    ToolSnippet('-> ', '-> '),
    ToolSnippet('::', '::'),
    ToolSnippet('{ }', '{}'),
    ToolSnippet(';', ';'),
  ];

  /// Go 常用语法 / 片段。
  static const List<ToolSnippet> go = [
    ToolSnippet('package ', 'package '),
    ToolSnippet('import ', 'import '),
    ToolSnippet('func ', 'func '),
    ToolSnippet('func main()', 'func main() {\n\n}'),
    ToolSnippet('return ', 'return '),
    ToolSnippet('type ', 'type '),
    ToolSnippet('struct ', 'type  struct {\n\n}'),
    ToolSnippet('interface ', 'type  interface {\n\n}'),
    ToolSnippet('map[', 'map[string]'),
    ToolSnippet('[]byte', '[]byte'),
    ToolSnippet('[]string', '[]string'),
    ToolSnippet('var ', 'var '),
    ToolSnippet('const ', 'const '),
    ToolSnippet(':=', ':='),
    ToolSnippet('if ', 'if '),
    ToolSnippet('if err != nil', 'if err != nil {\n\treturn\n}'),
    ToolSnippet('else {', 'else {\n\n}'),
    ToolSnippet('for ', 'for '),
    ToolSnippet('for i := 0', 'for i := 0; i < ; i++ {\n\n}'),
    ToolSnippet('for range ', 'for _, v := range  {\n\n}'),
    ToolSnippet('switch ', 'switch  {\ncase :\n\n}'),
    ToolSnippet('case ', 'case '),
    ToolSnippet('defer ', 'defer '),
    ToolSnippet('go func()', 'go func() {\n\n}()'),
    ToolSnippet('chan ', 'chan '),
    ToolSnippet('select {', 'select {\ncase :\n\n}'),
    ToolSnippet('make(', 'make('),
    ToolSnippet('append(', 'append('),
    ToolSnippet('len(', 'len('),
    ToolSnippet('cap(', 'cap('),
    ToolSnippet('copy(', 'copy('),
    ToolSnippet('delete(', 'delete('),
    ToolSnippet('error', 'error'),
    ToolSnippet('nil', 'nil'),
    ToolSnippet('panic(', 'panic('),
    ToolSnippet('recover()', 'recover()'),
    ToolSnippet('fmt.Println()', 'fmt.Println()'),
    ToolSnippet('fmt.Printf()', 'fmt.Printf()'),
    ToolSnippet('fmt.Sprintf()', 'fmt.Sprintf()'),
    ToolSnippet('fmt.Errorf()', 'fmt.Errorf()'),
    ToolSnippet('errors.New()', 'errors.New()'),
    ToolSnippet('strings.', 'strings.'),
    ToolSnippet('strconv.', 'strconv.'),
    ToolSnippet('time.', 'time.'),
    ToolSnippet('log.', 'log.'),
    ToolSnippet('json.Marshal()', 'json.Marshal()'),
    ToolSnippet('json.Unmarshal()', 'json.Unmarshal()'),
    ToolSnippet('context.Context', 'context.Context'),
    ToolSnippet('sync.WaitGroup', 'sync.WaitGroup'),
    ToolSnippet('sync.Mutex', 'sync.Mutex'),
    ToolSnippet('<-', '<-'),
  ];

  /// Dart 常用语法 / 片段。
  static const List<ToolSnippet> dart = [
    ToolSnippet('main()', 'void main() {\n\n}'),
    ToolSnippet('import ', 'import '),
    ToolSnippet('class ', 'class '),
    ToolSnippet('abstract class ', 'abstract class '),
    ToolSnippet('extends ', 'extends '),
    ToolSnippet('mixin ', 'mixin '),
    ToolSnippet('enum ', 'enum '),
    ToolSnippet('void ', 'void '),
    ToolSnippet('final ', 'final '),
    ToolSnippet('var ', 'var '),
    ToolSnippet('const ', 'const '),
    ToolSnippet('late ', 'late '),
    ToolSnippet('late final ', 'late final '),
    ToolSnippet('static ', 'static '),
    ToolSnippet('required ', 'required '),
    ToolSnippet('factory ', 'factory '),
    ToolSnippet('get ', 'get '),
    ToolSnippet('set ', 'set '),
    ToolSnippet('operator ', 'operator '),
    ToolSnippet('return ', 'return '),
    ToolSnippet('Future<', 'Future<'),
    ToolSnippet('Future<void>', 'Future<void> '),
    ToolSnippet('Stream<', 'Stream<'),
    ToolSnippet('List<', 'List<'),
    ToolSnippet('Map<', 'Map<'),
    ToolSnippet('Set<', 'Set<'),
    ToolSnippet('async ', 'async '),
    ToolSnippet('async* ', 'async* '),
    ToolSnippet('await ', 'await '),
    ToolSnippet('yield ', 'yield '),
    ToolSnippet('try {', 'try {\n\n} catch (e) {\n\n}'),
    ToolSnippet('catch (e)', 'catch (e) {\n\n}'),
    ToolSnippet('finally {', 'finally {\n\n}'),
    ToolSnippet('throw ', 'throw '),
    ToolSnippet('if (', 'if ()'),
    ToolSnippet('for (', 'for (var i = 0; i < ; i++) {}'),
    ToolSnippet('while (', 'while ()'),
    ToolSnippet('switch (', 'switch () {\ncase :\n}'),
    ToolSnippet('print()', 'print()'),
    ToolSnippet('toString()', 'toString()'),
    ToolSnippet('@override', '@override'),
    ToolSnippet('@Deprecated', '@Deprecated'),
    ToolSnippet('=>', '=>'),
    ToolSnippet('??', '??'),
    ToolSnippet('??=', '??='),
    ToolSnippet('?.', '?.'),
    ToolSnippet('..', '..'),
    ToolSnippet('...', '...'),
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

  /// 从共用库里删掉某条（按插入文本定位），返回剩余库。
  static Future<List<ToolSnippet>> removeCustom(String insert) async {
    final cur = await loadCustom();
    final out = cur.where((e) => e.insert != insert).toList();
    if (out.length != cur.length) await saveCustom(out);
    return out;
  }

  /// 修改共用库里的某条（[oldInsert] 定位；插入文本也可以一起改），返回新库。
  static Future<List<ToolSnippet>> updateCustom(
      String oldInsert, ToolSnippet updated) async {
    final cur = await loadCustom();
    var changed = false;
    final out = <ToolSnippet>[];
    for (final e in cur) {
      if (e.insert == oldInsert) {
        out.add(updated);
        changed = true;
      } else {
        out.add(e);
      }
    }
    if (changed) await saveCustom(out);
    return out;
  }

  /// 清空共用库。
  static Future<void> clearCustom() => saveCustom(const []);
}

