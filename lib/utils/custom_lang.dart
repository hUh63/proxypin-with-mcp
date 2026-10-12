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

import 'package:flutter/foundation.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/path.dart';
import 'package:proxypin/utils/lang_meta.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

/// 用户自定义语法。
///
/// 与「借用内置高亮」不同，这里的高亮是**运行时按用户配置构造**的：
/// re_highlight 的 [Mode] 是普通 Dart 类，字段全部公开，因此可以由关键字列表、
/// 注释定界符、字符串定界符、数字规则直接拼出一个可用的高亮器。
///
/// 这样即便某门语言（公司内部 DSL、新语言、模板语法）re_highlight 里没有，
/// 用户也能自己把关键字填进去，拿到**高亮 + 补全**，而不必迁就内置列表。
///
/// [baseKey] 是可选的“起点”：填了就以内置语言为基础（此时关键字为空则直接用
/// 内置 Mode）；留空则完全由 [keywords] / [builtIns] / [literals] 构造。
@immutable
class CustomLang {
  final String name;

  /// 借用哪个内置语言作为基础（空串 = 纯自定义）。
  final String? baseKey;

  /// 关键字（高亮为 keyword，同时进入补全候选）。
  final List<String> keywords;

  /// 内置类型 / 标准库函数（高亮为 built_in，同时进入补全候选）。
  final List<String> builtIns;

  /// 字面量（true / false / null 等，高亮为 literal，同时进入补全候选）。
  final List<String> literals;

  /// 注释 / 格式化族（null = 跟随 [baseKey]；纯自定义时默认按 hash 处理）。
  final LangFamily? family;

  /// 行注释定界符覆盖（null = 用族默认）。
  final String? lineComment;

  /// 块注释定界符覆盖（null = 用族默认）。
  final String? blockOpen;
  final String? blockClose;

  /// 是否忽略大小写（SQL / VB / Fortran 这类语言需要）。
  final bool caseInsensitive;

  const CustomLang({
    required this.name,
    this.baseKey,
    this.keywords = const [],
    this.builtIns = const [],
    this.literals = const [],
    this.family,
    this.lineComment,
    this.blockOpen,
    this.blockClose,
    this.caseInsensitive = false,
  });

  bool get isEmptyHighlight =>
      (baseKey == null || baseKey!.isEmpty) &&
      keywords.isEmpty &&
      builtIns.isEmpty &&
      literals.isEmpty;

  /// 进入补全候选的全部词。
  List<String> get allWords => [...keywords, ...builtIns, ...literals];

  /// 解析注释族：显式指定优先，否则跟随基础语言，最后按 hash 兜底。
  LangFamily get resolvedFamily =>
      family ?? (baseKey != null && baseKey!.isNotEmpty ? langFamilyOf(key: baseKey) : LangFamily.hash);

  String? get resolvedLineComment => lineComment ?? familyLineComment(resolvedFamily);

  (String, String)? get resolvedBlockComment {
    if (blockOpen != null && blockClose != null && blockOpen!.isNotEmpty && blockClose!.isNotEmpty) {
      return (blockOpen!, blockClose!);
    }
    return familyBlockComment(resolvedFamily);
  }

  CustomLang copyWith({
    String? name,
    String? baseKey,
    List<String>? keywords,
    List<String>? builtIns,
    List<String>? literals,
    LangFamily? family,
    String? lineComment,
    String? blockOpen,
    String? blockClose,
    bool? caseInsensitive,
    bool clearBase = false,
    bool clearFamily = false,
    bool clearComments = false,
  }) {
    return CustomLang(
      name: name ?? this.name,
      baseKey: clearBase ? null : (baseKey ?? this.baseKey),
      keywords: keywords ?? this.keywords,
      builtIns: builtIns ?? this.builtIns,
      literals: literals ?? this.literals,
      family: clearFamily ? null : (family ?? this.family),
      lineComment: clearComments ? null : (lineComment ?? this.lineComment),
      blockOpen: clearComments ? null : (blockOpen ?? this.blockOpen),
      blockClose: clearComments ? null : (blockClose ?? this.blockClose),
      caseInsensitive: caseInsensitive ?? this.caseInsensitive,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (baseKey != null && baseKey!.isNotEmpty) 'base': baseKey,
        if (keywords.isNotEmpty) 'keywords': keywords,
        if (builtIns.isNotEmpty) 'builtIns': builtIns,
        if (literals.isNotEmpty) 'literals': literals,
        if (family != null) 'family': family!.name,
        if (lineComment != null) 'lineComment': lineComment,
        if (blockOpen != null) 'blockOpen': blockOpen,
        if (blockClose != null) 'blockClose': blockClose,
        if (caseInsensitive) 'caseInsensitive': true,
      };

  factory CustomLang.fromJson(Map<String, dynamic> json) {
    List<String> strList(Object? raw) =>
        raw is List ? raw.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toList() : const [];
    final base = (json['base'] as String? ?? '').trim();
    final open = (json['blockOpen'] as String? ?? '').trim();
    final close = (json['blockClose'] as String? ?? '').trim();
    return CustomLang(
      name: (json['name'] as String? ?? '').trim(),
      baseKey: base.isEmpty ? null : base,
      keywords: strList(json['keywords']),
      builtIns: strList(json['builtIns']),
      literals: strList(json['literals']),
      family: _familyFromName(json['family']),
      lineComment: (json['lineComment'] as String? ?? '').trim().isEmpty ? null : (json['lineComment'] as String).trim(),
      blockOpen: open.isEmpty ? null : open,
      blockClose: close.isEmpty ? null : close,
      caseInsensitive: json['caseInsensitive'] as bool? ?? false,
    );
  }

  static LangFamily? _familyFromName(Object? value) {
    if (value is! String || value.isEmpty) return null;
    for (final f in LangFamily.values) {
      if (f.name == value) return f;
    }
    return null;
  }

  static LangFamily? familyFromName(Object? value) => _familyFromName(value);

  /// 构造高亮 [Mode]。
  ///
  /// * 有基础语言且用户没填任何关键字 → 直接复用内置 Mode（零开销、效果最好）；
  /// * 否则按用户配置拼一个：关键字 / 内置函数 / 字面量 + 注释 + 字符串 + 数字。
  Mode? buildMode([Mode? base]) {
    final baseMode = base ?? (baseKey != null && baseKey!.isNotEmpty ? builtinAllLanguages[baseKey!] : null);
    if (allWords.isEmpty) return baseMode;
    // 以基础语言为底、叠加用户关键字的情况交给 re_highlight 处理不了，
    // 这里选择「用户配置优先」：自建 Mode，保证用户填的词一定被高亮与补全。
    final contains = <Mode>[];
    final line = resolvedLineComment;
    if (line != null && line.isNotEmpty) {
      contains.add(Mode(scope: 'comment', begin: _re(line), end: '\\\$', relevance: 0));
    }
    final block = resolvedBlockComment;
    if (block != null && block.$1.isNotEmpty && block.$2.isNotEmpty) {
      contains.add(Mode(scope: 'comment', begin: _re(block.$1), end: _re(block.$2), relevance: 0));
    }
    // 字符串：单引号 / 双引号 / 反引号（存在才加）
    for (final q in ['"', "'", '`']) {
      contains.add(Mode(
        scope: 'string',
        begin: _re(q),
        end: _re(q),
        illegal: '\\n',
        contains: <Mode>[Mode(begin: '\\\\\\\\.', relevance: 0)],
      ));
    }
    // 数字
    contains.add(Mode(scope: 'number', begin: '\\\\b\\\\d+(\\\\.\\\\d+)?', relevance: 0));

    return Mode(
      name: name,
      caseInsensitive: caseInsensitive,
      keywords: <String, dynamic>{
        if (keywords.isNotEmpty) 'keyword': keywords.join(' '),
        if (builtIns.isNotEmpty) 'built_in': builtIns.join(' '),
        if (literals.isNotEmpty) 'literal': literals.join(' '),
      },
      contains: contains,
      relevance: 0,
    );
  }

  /// 把定界符转成正则片段（转义正则元字符）。
  static String _re(String delimiter) => delimiter.replaceAllMapped(
        RegExp(r'[.*+?^${}()|\[\]\\]'),
        (m) => '\\${m[0]}',
      );

  @override
  bool operator ==(Object other) =>
      other is CustomLang &&
      other.name == name &&
      other.baseKey == baseKey &&
      listEquals(other.keywords, keywords) &&
      listEquals(other.builtIns, builtIns) &&
      listEquals(other.literals, literals) &&
      other.family == family &&
      other.lineComment == lineComment &&
      other.blockOpen == blockOpen &&
      other.blockClose == blockClose &&
      other.caseInsensitive == caseInsensitive;

  @override
  int get hashCode => Object.hash(name, baseKey, Object.hashAll(keywords), Object.hashAll(builtIns),
      Object.hashAll(literals), family, lineComment, blockOpen, blockClose, caseInsensitive);
}

/// 自定义语法的本地存储（`custom_langs.json`），兼导 / 导入语法配置。
class CustomLangStore extends ChangeNotifier {
  static const String _fileName = 'custom_langs.json';

  /// 导出文件的类型标记 / 版本号。
  static const String fileType = 'proxypin.syntax';
  static const int fileVersion = 2;

  static CustomLangStore? _instance;

  /// 同步读取入口：编辑器构建语言列表时用，未加载时返回空表。
  static CustomLangStore? get instanceOrNull => _instance;

  static List<CustomLang> get current => _instance?._langs ?? const <CustomLang>[];

  /// 每次内容变化自增，用于让编辑器的语言列表缓存失效。
  static int revision = 0;

  final List<CustomLang> _langs = [];

  List<CustomLang> get langs => List.unmodifiable(_langs);

  static Future<CustomLangStore> get instance async {
    if (_instance == null) {
      final store = CustomLangStore._internal();
      await store._load();
      _instance = store;
    }
    return _instance!;
  }

  CustomLangStore._internal();

  bool containsName(String name) => _langs.any((l) => l.name == name);

  Future<void> _load() async {
    _langs.clear();
    try {
      final file = await Paths.getPath(_fileName);
      final content = await file.readAsString();
      if (content.trim().isNotEmpty) {
        final decoded = jsonDecode(content);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final lang = CustomLang.fromJson(Map<String, dynamic>.from(item));
              if (lang.name.isNotEmpty) _langs.add(lang);
            }
          }
        }
      }
    } catch (e) {
      logger.e('自定义语法解析失败', error: e);
    }
    revision++;
  }

  Future<void> _save() async {
    try {
      final file = await Paths.getPath(_fileName);
      await file.writeAsString(jsonEncode(_langs.map((l) => l.toJson()).toList(growable: false)));
    } catch (e) {
      logger.e('自定义语法保存失败', error: e);
    }
  }

  Future<void> add(CustomLang lang) async {
    _langs.add(lang);
    await _save();
    _bump();
  }

  /// [oldName] 是修改前的名字（改名时要按旧名定位）。
  Future<void> update(String oldName, CustomLang lang) async {
    final index = _langs.indexWhere((l) => l.name == oldName);
    if (index < 0) {
      _langs.add(lang);
    } else {
      _langs[index] = lang;
    }
    await _save();
    _bump();
  }

  Future<void> remove(String name) async {
    _langs.removeWhere((l) => l.name == name);
    await _save();
    _bump();
  }

  /// 合并导入：同名覆盖、新名追加。返回 (新增数, 覆盖数)。
  Future<(int, int)> merge(List<CustomLang> langs) async {
    var added = 0;
    var updated = 0;
    for (final lang in langs) {
      final index = _langs.indexWhere((l) => l.name == lang.name);
      if (index < 0) {
        _langs.add(lang);
        added++;
      } else {
        _langs[index] = lang;
        updated++;
      }
    }
    await _save();
    _bump();
    return (added, updated);
  }

  /// 生成导出文件的文本内容。
  String buildExportPayload(List<String> enabledLangs) {
    final payload = <String, dynamic>{
      'type': fileType,
      'version': fileVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'enabledLangs': enabledLangs,
      'customLangs': _langs.map((l) => l.toJson()).toList(growable: false),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// 解析导出文件。返回 (自定义语法, 语言显示勾选)；勾选为 null 表示文件未携带。
  ///
  /// 兼容两种写法：完整导出对象，或直接是一个自定义语法数组。
  static (List<CustomLang>, List<String>?) parseExport(String text) {
    final decoded = jsonDecode(text);
    List<dynamic> rawLangs;
    List<String>? enabled;
    if (decoded is List) {
      rawLangs = decoded;
    } else if (decoded is Map) {
      final raw = decoded['customLangs'] ?? decoded['langs'];
      if (raw is! List) {
        throw const FormatException('missing customLangs');
      }
      rawLangs = raw;
      final e = decoded['enabledLangs'];
      if (e is List) {
        enabled = e.whereType<String>().toList(growable: false);
      }
    } else {
      throw const FormatException('unsupported syntax file');
    }
    final langs = rawLangs
        .whereType<Map>()
        .map((item) => CustomLang.fromJson(Map<String, dynamic>.from(item)))
        .where((l) => l.name.isNotEmpty)
        .toList();
    return (langs, enabled);
  }

  void _bump() {
    revision++;
    notifyListeners();
  }
}
