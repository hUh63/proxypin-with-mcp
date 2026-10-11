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

/// 自定义语法定义。
///
/// proxypin 的高亮来自 re_highlight 的内置语言表（编译期构建的 Mode，运行时无法
/// 由用户书写正则），因此自定义语法采用「借用内置高亮 + 自定外观」的方式：
///
/// * [name] —— 显示名，也是写入文档的语法名（与内置语言重名会被拒绝）；
/// * [baseKey] —— 借用哪个内置语言的高亮（空串 = 纯文本，不做高亮）；
/// * [family] —— 注释 / 格式化按哪个语言族走（null = 跟随 [baseKey]）。
///
/// 这样「内部用 `#` 注释、结构却像 C」这类语言也能拿到注释切换、格式化和全套
/// 智能补全，而不需要用户去手写语法文件。
@immutable
class CustomLang {
  final String name;
  final String baseKey;

  /// 显式指定的注释 / 格式化族；null 表示跟随 [baseKey]。
  final LangFamily? family;

  const CustomLang({required this.name, this.baseKey = '', this.family});

  CustomLang copyWith({String? name, String? baseKey, LangFamily? family, bool clearFamily = false}) {
    return CustomLang(
      name: name ?? this.name,
      baseKey: baseKey ?? this.baseKey,
      family: clearFamily ? null : (family ?? this.family),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'base': baseKey,
        if (family != null) 'family': family!.name,
      };

  factory CustomLang.fromJson(Map<String, dynamic> json) {
    final rawName = json['name'];
    final rawBase = json['base'];
    final name = rawName is String ? rawName.trim() : '';
    final base = rawBase is String ? rawBase.trim() : '';
    return CustomLang(name: name, baseKey: base, family: familyFromName(json['family']));
  }

  /// 把族名解析成 [LangFamily]（无法识别返回 null）。
  static LangFamily? familyFromName(Object? value) {
    if (value is! String || value.isEmpty) return null;
    for (final f in LangFamily.values) {
      if (f.name == value) return f;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is CustomLang && other.name == name && other.baseKey == baseKey && other.family == family;

  @override
  int get hashCode => Object.hash(name, baseKey, family);
}

/// 自定义语法的本地存储（`custom_langs.json`）。
///
/// 同时负责「语法配置」的导入 / 导出：导出内容 = 自定义语法 + 语言显示勾选，
/// 便于换机迁移或团队内共享同一套语法清单。
class CustomLangStore extends ChangeNotifier {
  static const String _fileName = 'custom_langs.json';

  /// 导出文件的类型标记 / 版本号。
  static const String fileType = 'proxypin.syntax';
  static const int fileVersion = 1;

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

  /// 覆盖式导入（清空后写入）。返回写入条数。
  Future<int> replaceAll(List<CustomLang> langs) async {
    _langs
      ..clear()
      ..addAll(langs);
    await _save();
    _bump();
    return _langs.length;
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
