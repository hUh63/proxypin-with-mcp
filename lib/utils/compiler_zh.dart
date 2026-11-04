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

// 编译器诊断中文化（数据来自 `assets/compiler_zh.sed`，GCC 官方中文翻译整理）。
//
// 定位：编辑器「检查」里的「编译日志」入口。把 gcc / clang / g++ 的英文诊断
// 翻译成中文，并保留原文（很多报错要拿英文去搜）。
//
// 实现取舍：**不用正则**。这份 sed 表是从 GCC 的 po 消息生成的，规则里到处是
// `\.` `\[` `\*` 这类转义；直接当正则用会既慢又容易误匹配（`.` 变通配）。
// 这里把规则还原成「英文原文 → 中文」，按**字面包含**替换，长句优先 ——
// 对「消息翻译」这个任务来说既准又快（4000 条 × 每行一个 contains）。
//
// 首字加载 305KB JSON，约几十毫秒；结果按行缓存，重复行不重复翻。

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class CompilerZh {
  static final CompilerZh instance = CompilerZh._();

  CompilerZh._();

  static const String _asset = 'assets/compiler_zh.json';

  /// 规则按英文长度降序：先替换长句，避免短句把长句的片段吃掉。
  List<MapEntry<String, String>> _rules = const <MapEntry<String, String>>[];
  Future<void>? _loading;
  bool _loaded = false;

  /// 行级缓存：编译日志里同一行（模板化消息）经常重复出现。
  final Map<String, String> _cache = <String, String>{};

  bool get loaded => _loaded;

  int get ruleCount => _rules.length;

  /// 精选：**完整句式**的中文（人工维护 30 条高频报错）。
  ///
  /// 那份 sed 表是从 GCC 的 po 拆句得来的，逐条替换出来会是「对 'foo(int)'」
  /// 这种半截中文（po 里本来就是片段拼接）。所以高频错误先用这层整句翻译，
  /// 命中就不再去走 sed 表 —— 可读性差别很大。
  static const List<List<String>> _curated = <List<String>>[
    ["expected ';' before", '此处缺少分号：'],
    ["expected ';' at end of", '语句末尾缺少分号：'],
    ["expected ')' before", '此处缺少右括号：'],
    ["expected ')' at end of", '此处缺少右括号：'],
    ["expected '}' at end of input", '文件末尾缺少右花括号 }'],
    ['expected expression before', '这里需要一个表达式：'],
    ['expected declaration', '这里应该是一条声明（是不是多写了符号/括号？）'],
    ['expected primary-expression', '这里需要一个表达式'],
    ["' was not declared in this scope", '未在此作用域中声明'],
    ['was not declared in this scope', '未在此作用域中声明'],
    ['no matching function for call to', '没有找到匹配的函数调用：'],
    ['no matching constructor for initialization of', '没有找到匹配的构造函数：'],
    ['too few arguments to function', '函数实参太少：'],
    ['too many arguments to function', '函数实参太多：'],
    ['invalid conversion from', '无效的类型转换，从'],
    ['cannot convert', '无法转换'],
    ['redefinition of', '重复定义：'],
    ['conflicting declaration', '声明冲突：'],
    ['unused variable', '变量声明了但没用到：'],
    ['unused parameter', '形参没用上：'],
    ['control reaches end of non-void function', '有返回值的函数走到末尾却没有 return'],
    ['comparison between signed and unsigned', '有符号数与无符号数比较（容易出错）'],
    ['implicit declaration of function', '隐式声明了函数（缺少头文件声明）：'],
    ['incompatible implicit declaration of built-in function', '内置函数声明不兼容：'],
    ['unknown type name', '未知的类型名：'],
    ['array subscript is above array bounds', '数组下标越界（超过上界）'],
    ['array subscript is below array bounds', '数组下标越界（小于下界）'],
    ['case label not within a switch statement', 'case 标号不在 switch 语句里'],
    ['undefined reference to', '链接失败：找不到符号'],
    ['multiple definition of', '符号被重复定义：'],
    ['No such file or directory', '文件或目录不存在'],
    ['Permission denied', '没有权限'],
    ['Segmentation fault', '段错误（访问了非法内存）'],
    ['stack smashing detected', '检测到栈溢出（缓冲区写越界）'],
    ['double free or corruption', '重复释放或堆被破坏'],
    ['integer expressions', '整数表达式'],
    ["' to '", "'，转换为 '"],
    ["error: ", '错误：'],
    ["fatal error: ", '致命错误：'],
    ["warning: ", '警告：'],
    ["note: ", '提示：'],
  ];

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString(_asset);
      final data = jsonDecode(raw);
      final list = data is Map ? data['rules'] : null;
      final out = <MapEntry<String, String>>[];
      if (list is List) {
        for (final e in list) {
          if (e is! List || e.length < 2) continue;
          final en = '${e[0]}'.trim();
          final zh = '${e[1]}'.trim();
          if (en.length < 6 || zh.isEmpty) continue;
          out.add(MapEntry(en, zh));
        }
      }
      // 保持 sed 文件里的原始顺序：那份表按「先长后短、先特例后通用」排过，
      // 重排会让片段替换的组合错位。
      _rules = out;
    } catch (_) {
      _rules = const <MapEntry<String, String>>[];
    }
    _loaded = true;
  }

  bool _hasChinese(String s) {
    for (final c in s.codeUnits) {
      if (c >= 0x4e00 && c <= 0x9fff) return true;
    }
    return false;
  }

  /// 单行翻译：命中规则就替换成中文，没命中原样返回。
  String translateLine(String line) {
    if (!_loaded || _rules.isEmpty || line.trim().isEmpty) return line;
    final cached = _cache[line];
    if (cached != null) return cached;
    // 已经是中文（或中英混排）就不再翻：二次替换只会把结果弄乱。
    if (_hasChinese(line)) {
      _remember(line, line);
      return line;
    }
    var out = line;
    // 1) 精选整句优先
    var curatedHit = false;
    for (final c in _curated) {
      if (out.contains(c[0])) {
        out = out.replaceAll(c[0], c[1]);
        curatedHit = true;
      }
    }
    // 2) 命中精选就不再走 sed 表：那份表是片段，会把整句拆碎
    if (curatedHit) {
      // gcc 的消息里 `'}' token` 这种尾巴在中文里没有意义
      out = out.replaceAll(' token', '');
    } else {
      for (final r in _rules) {
        if (out.contains(r.key)) {
          out = out.replaceAll(r.key, r.value);
        }
      }
    }
    _remember(line, out);
    return out;
  }

  void _remember(String from, String to) {
    if (_cache.length > 2000) _cache.clear();
    _cache[from] = to;
  }

  /// 整段翻译（保留换行与缩进）。
  String translate(String text) {
    if (!_loaded || _rules.isEmpty || text.isEmpty) return text;
    final buf = StringBuffer();
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) buf.write('\n');
      buf.write(translateLine(lines[i]));
    }
    return buf.toString();
  }
}
