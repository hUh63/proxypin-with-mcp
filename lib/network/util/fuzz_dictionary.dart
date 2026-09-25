/*
 * Copyright 2023 Hongen Wang
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

import 'package:flutter_js/flutter_js.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一个 Fuzz 字典：一组取值。
///
/// 三种来源，可以叠加：
/// - [entries]：手填，或从文本文件导入（一行一条）；
/// - [script]：一段 JS，执行后把数组赋给 `result` 变量；
/// - 内置种子：[FuzzDictionaryStore.builtinSeeds]。
///
/// 定位说明：工具**不预置攻击载荷库**。内置的只是一组边界值 / 类型异常串，
/// 真正的取值由你自己填、导入或用脚本算出来 —— 这样它是个通用的取值发生器，
/// 而不是拿来就能打别人站的成套字典。
class FuzzDictionary {
  final String name;
  final List<String> entries;
  final String? script;

  /// 内置只读字典（不可编辑/删除）
  final bool builtin;

  const FuzzDictionary({
    required this.name,
    this.entries = const [],
    this.script,
    this.builtin = false,
  });

  bool get hasScript => script != null && script!.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'name': name,
        'entries': entries,
        if (hasScript) 'script': script,
      };

  static FuzzDictionary fromJson(Map<String, dynamic> json) => FuzzDictionary(
        name: (json['name'] ?? '').toString(),
        entries: ((json['entries'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        script: json['script']?.toString(),
      );

  FuzzDictionary copyWith({String? name, List<String>? entries, String? script}) =>
      FuzzDictionary(
        name: name ?? this.name,
        entries: entries ?? this.entries,
        script: script ?? this.script,
        builtin: builtin,
      );
}

/// 字典的持久化 + 脚本执行。
class FuzzDictionaryStore {
  static const String _prefsKey = 'fuzz_dictionaries_v1';

  /// 内置种子：边界值与类型异常串（**不是**攻击载荷）。
  ///
  /// 给的是「输入校验测试」的起点 —— 空值、超长、类型不对、特殊字符、
  /// 路径片段这些，用来观察后端怎么处理异常输入。
  static const List<String> builtinSeeds = [
    '',
    ' ',
    'test',
    '中文',
    'null',
    'undefined',
    'true',
    'false',
    '0',
    '-1',
    '99999999999999999999',
    'NaN',
    '[]',
    '{}',
    "1'",
    '1"',
    '<b>',
    '&',
    '%00',
    '../',
    '\\',
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  ];

  /// 内置字典（只读）
  static List<FuzzDictionary> builtins() => const [
        FuzzDictionary(name: '边界值 / 类型异常', entries: builtinSeeds, builtin: true),
      ];

  /// 读取用户自定义字典
  static Future<List<FuzzDictionary>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => FuzzDictionary.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.name.isNotEmpty)
          .toList();
    } catch (e) {
      logger.w('Fuzz 字典读取失败，按空处理: $e');
      return [];
    }
  }

  /// 保存用户自定义字典（整体覆盖）
  static Future<void> save(List<FuzzDictionary> dictionaries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(dictionaries
          .where((e) => !e.builtin)
          .map((e) => e.toJson())
          .toList()),
    );
  }

  /// 执行字典脚本，取 `result` 数组。
  ///
  /// 约定：脚本把结果数组赋给全局 `result`，例如
  /// ```js
  /// result = ['a', 'b'];
  /// // 或按规律生成：
  /// result = Array.from({length: 8}, (_, i) => 'x'.repeat(i + 1));
  /// ```
  /// 返回值统一转成字符串列表。执行失败会抛异常，由调用方提示。
  static Future<List<String>> runScript(String script) async {
    final runtime = getJavascriptRuntime(xhr: false);
    try {
      final res = runtime.evaluate(script);
      if (res.isError) {
        throw Exception(res.stringResult);
      }
      final json = runtime.evaluate(
          'JSON.stringify(typeof result === "undefined" ? [] : result)');
      if (json.isError) {
        throw Exception(json.stringResult);
      }
      final decoded = jsonDecode(json.stringResult);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
      throw Exception('脚本的 result 不是数组');
    } finally {
      runtime.dispose();
    }
  }

  /// 展开一个字典的全部取值（静态条目 + 脚本产物，去重保序）
  static Future<List<String>> resolve(FuzzDictionary dictionary) async {
    final out = <String>[];
    void add(String v) {
      if (!out.contains(v)) out.add(v);
    }

    for (final e in dictionary.entries) {
      add(e);
    }
    if (dictionary.hasScript) {
      for (final e in await runScript(dictionary.script!)) {
        add(e);
      }
    }
    return out;
  }
}
