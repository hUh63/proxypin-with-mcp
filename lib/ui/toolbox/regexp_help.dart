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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';

/// 正则表达式帮助文档。
///
/// 文档正文保持中文单语（与工具箱「使用指南」的既有约定一致）：
/// 正则语法与示例本身跨语言通用，逐条翻译收益极低。
class RegexpHelpPage extends StatefulWidget {
  const RegexpHelpPage({super.key});

  @override
  State<RegexpHelpPage> createState() => _RegexpHelpPageState();
}

class _HelpEntry {
  /// 符号 / 写法
  final String symbol;

  /// 说明
  final String desc;

  /// 示例（可空）
  final String? example;

  const _HelpEntry(this.symbol, this.desc, {this.example});
}

class _HelpSection {
  final String title;
  final String? intro;
  final List<_HelpEntry> entries;

  /// 该节是否为「速查表」（带复制按钮）
  final bool cheatsheet;

  const _HelpSection(this.title, this.entries, {this.intro, this.cheatsheet = false});
}

final List<_HelpSection> _sections = [
  _HelpSection('学习须知', const [
    _HelpEntry('什么是正则表达式',
        '一种用来描述文本模式的方法，可以匹配、查找、替换文本中的特定片段。几乎所有编程语言与文本编辑器都支持它。'),
    _HelpEntry('为什么用', '更快更精确地处理文本：批量查找、格式清洗、日志提取、字段校验都靠它。'),
    _HelpEntry('阅读顺序', '建议先看「元字符」「重复匹配」「字符集合」「分组与捕获」，再看「修饰符」「替换表达式」。'),
  ], intro: '本节是本工具内置帮助的索引，可配合搜索框快速定位语法。'),
  _HelpSection('元字符与普通字符', const [
    _HelpEntry('. * + ? [ ] ^ \$ | ( ) { } \\', '元字符，均有特殊含义，要匹配它们本身需要加反斜杠转义，如 \\. 匹配句点。'),
    _HelpEntry('普通字符', '除元字符外的字符，一串普通字符只匹配与自身相等的文本，如 abc 匹配 "abc"。'),
  ], intro: '元字符是正则的"保留字"，先记住这份清单，后面每条都在讲其中一个。'),
  _HelpSection('匹配任意字符', const [
    _HelpEntry('.', '匹配一个任意字符。默认不匹配换行符，除非开启 DotAll 修饰符 (?s)。',
        example: 'a.c 匹配 "abc"、"adc"；a..c 匹配 "abdc"、"axzc"'),
    _HelpEntry('需要几个写几个', '要匹配多少个任意字符就写多少个 .，数量不确定时改用重复匹配。'),
  ]),
  _HelpSection('重复匹配', const [
    _HelpEntry('*', '前一个字符或分组重复 0 次或多次。', example: 'ab*c 匹配 "ac"、"abc"、"abbc"'),
    _HelpEntry('+', '前一个字符或分组重复 1 次或多次。', example: 'ab+c 匹配 "abc"、"abbc"、"abbbc"'),
    _HelpEntry('?', '前一个字符或分组重复 0 次或 1 次。', example: 'ab?c 匹配 "ac"、"abc"'),
    _HelpEntry('{n}', '恰好重复 n 次。', example: 'ab{5}c 匹配 "abbbbbc"'),
    _HelpEntry('{n,}', '至少重复 n 次。', example: 'ab{2,}c 匹配 "abbc"、"abbbc"'),
    _HelpEntry('{n,m}', '重复 n 到 m 次。', example: 'ab{0,2}c 匹配 "ac"、"abc"、"abbc"'),
    _HelpEntry('贪婪匹配', '量词默认尽可能多地匹配：a.*b 在 "<h>AB</h>…B" 这类文本里会匹配到最后一个 b。'),
    _HelpEntry('非贪婪匹配', '在量词后加 ? 变为尽可能少匹配：*? +? ?? {n,}? {n,m}?。',
        example: '<.+> 会贪婪吃下整个 "<h>ABC</h>"；<.+?> 只匹配 "<h>"'),
  ], intro: '有了重复匹配就能写"以 a 开头以 b 结尾"这类模式：a.*b。'),
  _HelpSection('字符集合', const [
    _HelpEntry('[abc]', '匹配括号内任意一个字符。'),
    _HelpEntry('[a-z]', '用 - 表示范围，匹配 a 到 z 中的一个字母。'),
    _HelpEntry('[_a-zA-Z]', '多种写法可组合：一个下划线或英文字母。'),
    _HelpEntry('[^0-9]', '开头加 ^ 表示取反：任意一个非数字字符。'),
    _HelpEntry('字符类可内嵌', r'[a-z\d] 等价于 [a-z0-9]，\d \w \s 等都能放进集合里。'),
  ]),
  _HelpSection('边界匹配', const [
    _HelpEntry('^', '匹配输入（或多行模式下每行）的开始。', example: '^abc 匹配以 "abc" 开头的串'),
    _HelpEntry('\$', '匹配输入（或多行模式下每行）的结尾。', example: 'xyz\$ 匹配以 "xyz" 结尾的串'),
    _HelpEntry(r'\b', '单词边界。', example: r'\bword\b 匹配 "word"，不匹配 "sword" / "words"'),
    _HelpEntry(r'\B', '非单词边界。', example: r'er\B 匹配 "verb" 中的 er，不匹配 "never" 中的 er'),
  ], intro: '多行模式下 ^ 与 \$ 匹配每行首尾（本工具可用修饰符 (?m) 开启）。'),
  _HelpSection('分组匹配', const [
    _HelpEntry('( )', '把一段正则括起来成为整体，同时成为捕获组。', example: 'word+ 是 d 重复，如 "worddd"；(word)+ 是整体重复，如 "wordword"'),
  ], intro: '分组解决"量词只作用于前一个字符"的问题。'),
  _HelpSection('选择匹配', const [
    _HelpEntry('|', '匹配左边或右边，作用范围是所在分组或整个表达式。', example: 'cat|dog 匹配 "cat" 或 "dog"；g(oo|uar)d 匹配 "good" 或 "guard"'),
  ]),
  _HelpSection('捕获组与反向引用', const [
    _HelpEntry('( ) 的编号', '按左括号从左到右从 1 开始编号。', example: 'a(b(c)) 中 1 号组是 "bc"，2 号组是 "c"'),
    _HelpEntry(r'\1', '反向引用第 num 个捕获组。', example: r'(.)\1 匹配两个连续相同字符'),
    _HelpEntry('(?: )', '非捕获组：只分组不捕获，编号不受影响。', example: '(?:a+)(b+) 只有一个捕获组'),
    _HelpEntry('(?<name>)', '命名捕获组（Dart / JS 等支持），可用名字取组。'),
  ], intro: '捕获组可用于反向引用，也用于替换表达式引用。'),
  _HelpSection('预查（零宽断言）', const [
    _HelpEntry('(?= )', '正向肯定预查：后面必须出现指定内容。', example: 'Windows(?=XP) 匹配 "WindowsXP" 里的 Windows'),
    _HelpEntry('(?! )', '正向否定预查：后面不能出现指定内容。', example: 'Windows(?!XP) 匹配 "Windows11" 里的 Windows'),
    _HelpEntry('(?<= )', '反向肯定预查：前面必须是指定内容。', example: '(?<=XP)Windows 匹配 "XPWindows" 里的 Windows'),
    _HelpEntry('(?<! )', '反向否定预查：前面不能是指定内容。', example: '(?<!XP)Windows 匹配 "11Windows" 里的 Windows'),
  ], intro: '预查不消耗字符，也不产生捕获组。'),
  _HelpSection('转义与转义序列', const [
    _HelpEntry(r'\. \\', '元字符前加反斜杠变成普通字符：\\. 匹配句点，\\\\ 匹配反斜杠。'),
    _HelpEntry(r'[\^\-]', '在 [ ] 内用 \\ 可让 - 和 ^ 变回普通字符：匹配 "^" 或 "-"。'),
    _HelpEntry(r'\d / \D', '数字字符 / 非数字字符，等价 [0-9] / [^0-9]。'),
    _HelpEntry(r'\w / \W', '单词字符 / 非单词字符，等价 [A-Za-z0-9_] / [^A-Za-z0-9_]。'),
    _HelpEntry(r'\s / \S', '空白字符 / 非空白字符，等价 [ \\f\\n\\r\\t\\v] / [^ \\f\\n\\r\\t\\v]。'),
    _HelpEntry(r'\uXXXX', 'Unicode 转义：\\u00A9 匹配 ©；也可写作 \\u{1F600} 匹配 emoji。'),
    _HelpEntry(r'\xNN', '十六进制转义：\\x41 匹配 "A"。'),
    _HelpEntry(r'\num', '反向引用第 num 个捕获组：\\(.\\)\\1 匹配两个连续相同字符。'),
    _HelpEntry(r'\n \r \t \f \v', '换行 / 回车 / 制表 / 换页 / 垂直制表符。'),
  ]),
  _HelpSection('修饰符', const [
    _HelpEntry('(?i)', '不区分大小写。', example: '(?i)hello 匹配 "hello"、"Hello"、"HELLO"'),
    _HelpEntry('(?m)', '多行模式：^ \$ 匹配每行首尾，而不只是整段的首尾。'),
    _HelpEntry('(?s)', 'DotAll：. 也匹配换行符。'),
    _HelpEntry('(?u)', 'Unicode 模式：按 Unicode 标准处理大小写与转义。'),
    _HelpEntry('(?-i) (?-m) (?-s) (?-u)', '在修饰符字母前加 - 取消该修饰符。',
        example: '(?i)a(?-i)a 匹配 "aa" 与 "Aa"：第一个 a 不区分大小写，第二个区分'),
  ], intro: '本工具基于 Dart 正则引擎，不支持把 (?i) 这类内联修饰符写进模式里；'
      '请改用工具栏上的 i / m / s / u 开关，效果等价。下表中的 (?i) 写法是通用正则概念，供理解用。'),
  _HelpSection('替换表达式', const [
    _HelpEntry(r'$n', '引用第 n 个捕获组，n 从 1 开始。', example: r'(\d+)-(\d+) 配 $2-$1 可把 "000-111" 换成 "111-000"'),
    _HelpEntry(r'${n}', 'n ≥ 10 时必须用花括号写法，如 \${10}。'),
    _HelpEntry(r'$0', '引用整个匹配到的文本。', example: r'配 "$0" 可给匹配内容加双引号'),
    _HelpEntry(r'\$', '要替换出字面量 \$ 字符时写 \\\$，否则会被当成组引用。'),
    _HelpEntry(r'\\', '要替换出字面量反斜杠时写 \\\\。'),
    _HelpEntry(r'\n \r \t', '替换串中的换行 / 回车 / 制表符。'),
    _HelpEntry('未定义的组', '引用了不存在的组会得到空串，不会报错。'),
  ], intro: r'本工具支持 $0、$n、${n}、\$、\\、\n\r\t 的完整语义。'),
  _HelpSection('替换中的大小写处理（扩展）', const [
    _HelpEntry(r'\l', '把紧随其后那次组引用的第一个字符转小写。'),
    _HelpEntry(r'\u', '把紧随其后那次组引用的第一个字符转大写。'),
    _HelpEntry(r'\L', '把紧随其后那次组引用的结果整体转小写。'),
    _HelpEntry(r'\U', '把紧随其后那次组引用的结果整体转大写。'),
    _HelpEntry(r'\L$0', '把整个匹配转为小写。'),
    _HelpEntry(r'\u$2', '把第 2 组内容的第一个字符转大写，其余不变。'),
    _HelpEntry(r'\u\L$0', '把整个匹配的第一个字符转大写、其余转小写。'),
    _HelpEntry(r'\l\l${10}', '把第 10 组内容的第一、二个字符转小写，其余不变。'),
  ],
      intro: '这组写法不是正则规范，而是文本编辑器（MT）的扩展，其它软件未必支持；本工具已兼容。',
      cheatsheet: false),
  _HelpSection('常用正则速查', const [
    _HelpEntry(r'\d{4}-\d{2}-\d{2}', '日期 YYYY-MM-DD'),
    _HelpEntry(r'\d{1,3}(\.\d{1,3}){3}', 'IPv4 地址'),
    _HelpEntry(r'[\w.%+-]+@[\w.-]+\.[A-Za-z]{2,}', '邮箱'),
    _HelpEntry(r'https?://[\w.-]+(?:/[\w./?%&=-]*)?', 'URL'),
    _HelpEntry(r'1[3-9]\d{9}', '中国大陆手机号'),
    _HelpEntry(r'[\u4e00-\u9fa5]+', '中文字符'),
    _HelpEntry(r'<([a-zA-Z][\w-]*)(?:\s[^<>]*)?>', 'HTML/XML 开标签'),
    _HelpEntry(r'\s+$', '行尾空白（多行模式下用）'),
    _HelpEntry(r'^\s*$', '空行（多行模式下用）'),
    _HelpEntry(r'(\w+)\s+\1', '重复出现的单词'),
    _HelpEntry(r'(\d{3})\d{4}(\d{4})', '手机号打码，替换为 \$1****\$2'),
    _HelpEntry(r'[\u200b\u200c\u200d\ufeff]', '零宽字符（清理隐藏字符）'),
  ], intro: '点条目右侧的复制按钮即可取用；实际使用时建议按需收窄。', cheatsheet: true),
  _HelpSection('常见陷阱与性能', const [
    _HelpEntry('贪婪导致误匹配', '尽量用非贪婪 *? +? 或收窄字符集（[^"]* 优于 .*）。'),
    _HelpEntry('回溯爆炸', '避免 (a+)+ 这类嵌套量词；长文本上慎用 .*.*。'),
    _HelpEntry('字符类的坑', '[] 内大部分元字符失去特殊含义，但 ] \\ ^ - 仍需注意位置或转义。'),
    _HelpEntry('语言差异', '反向引用 \\1、命名组、\\p{..} 等在不同语言支持度不同；本工具基于 Dart 正则引擎。'),
    _HelpEntry('unicode 开关', r'\\u{..} 与 \\p{..} 需要开启 u 修饰符才能按预期工作。'),
  ]),
];

class _RegexpHelpPageState extends State<RegexpHelpPage> {
  String _query = '';

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  bool _matches(_HelpSection s) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    if (s.title.toLowerCase().contains(q)) return true;
    if (s.intro != null && s.intro!.toLowerCase().contains(q)) return true;
    return s.entries.any((e) =>
        e.symbol.toLowerCase().contains(q) ||
        e.desc.toLowerCase().contains(q) ||
        (e.example?.toLowerCase().contains(q) ?? false));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _sections.where(_matches).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.regexpHelp, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        centerTitle: true,
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: TextField(
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: localizations.regexpHelpSearchHint,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(child: Text(localizations.regexpNoMatch, style: const TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
                  itemCount: visible.length,
                  itemBuilder: (context, i) => _sectionCard(visible[i]),
                ),
        ),
      ]),
    );
  }

  Widget _sectionCard(_HelpSection section) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(section.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: primary)),
          if (section.intro != null) ...[
            const SizedBox(height: 4),
            Text(section.intro!, style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
          ],
          const SizedBox(height: 6),
          ...section.entries.map((e) => _entryRow(e, section.cheatsheet)),
        ]),
      ),
    );
  }

  Widget _entryRow(_HelpEntry e, bool canCopy) {
    final mono = TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          constraints: const BoxConstraints(minWidth: 78),
          padding: const EdgeInsets.only(right: 8, top: 1),
          child: Text(e.symbol, style: mono),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.desc, style: const TextStyle(fontSize: 13)),
            if (e.example != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('例如：${e.example}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600], fontFamily: 'monospace')),
              ),
          ]),
        ),
        if (canCopy)
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: localizations.copy,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: e.symbol));
              FlutterToastr.show(localizations.copied, context, duration: 2);
            },
          ),
      ]),
    );
  }
}
