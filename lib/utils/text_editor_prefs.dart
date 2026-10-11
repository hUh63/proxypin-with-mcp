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
import 'package:shared_preferences/shared_preferences.dart';

/// 文本编辑器的显示 / 排版偏好（「更多 → 设置」里可调，全局共享）。
///
/// 与编辑器实例无关，改完之后所有打开的文档都会用新设置重建编辑区。
class TextEditorPrefs {
  /// 字号。
  final double fontSize;

  /// 行距倍数。
  final double lineHeight;

  /// 是否显示行号栏。
  final bool showGutter;

  /// 行号栏与正文之间是否画分隔线。
  final bool gutterDivider;

  /// 是否显示缩进参考线。
  final bool guideLines;

  /// 是否允许折叠代码。
  final bool enableFolding;

  /// 缩进是否用制表符（否则用空格）。
  final bool useTabs;

  /// 一个制表符等于几个空格。
  final int tabSize;

  /// 回车时是否延续当前行的缩进（内核开关）。
  final bool autoIndent;

  /// 双指捏合缩放编辑器字号。
  final bool pinchZoom;

  /// 启用放大镜（底部显示当前行的放大视图）。
  final bool magnifier;

  /// 「语法」子菜单里启用的语言（label 列表）。为空表示全部启用。
  final List<String> enabledLangs;

  /// 「更多」菜单里隐藏的菜单项 id。
  final List<String> hiddenMenu;

  /// 长按浮动菜单里显示的项 id。为空表示默认（全不显示自定义项）。
  final List<String> floatMenu;

  const TextEditorPrefs({
    this.fontSize = 13,
    this.lineHeight = 1.0,
    this.showGutter = true,
    this.gutterDivider = false,
    this.guideLines = false,
    this.enableFolding = true,
    this.useTabs = false,
    this.tabSize = 4,
    this.autoIndent = true,
    this.pinchZoom = true,
    this.magnifier = false,
    this.enabledLangs = const <String>[],
    this.hiddenMenu = const <String>[],
    this.floatMenu = const <String>[],
  });

  TextEditorPrefs copyWith({
    double? fontSize,
    double? lineHeight,
    bool? showGutter,
    bool? gutterDivider,
    bool? guideLines,
    bool? enableFolding,
    bool? useTabs,
    int? tabSize,
    bool? autoIndent,
    bool? pinchZoom,
    bool? magnifier,
    List<String>? enabledLangs,
    List<String>? hiddenMenu,
    List<String>? floatMenu,
  }) {
    return TextEditorPrefs(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      showGutter: showGutter ?? this.showGutter,
      gutterDivider: gutterDivider ?? this.gutterDivider,
      guideLines: guideLines ?? this.guideLines,
      enableFolding: enableFolding ?? this.enableFolding,
      useTabs: useTabs ?? this.useTabs,
      tabSize: tabSize ?? this.tabSize,
      autoIndent: autoIndent ?? this.autoIndent,
      pinchZoom: pinchZoom ?? this.pinchZoom,
      magnifier: magnifier ?? this.magnifier,
      enabledLangs: enabledLangs ?? this.enabledLangs,
      hiddenMenu: hiddenMenu ?? this.hiddenMenu,
      floatMenu: floatMenu ?? this.floatMenu,
    );
  }

  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'showGutter': showGutter,
        'gutterDivider': gutterDivider,
        'guideLines': guideLines,
        'enableFolding': enableFolding,
        'useTabs': useTabs,
        'tabSize': tabSize,
        'autoIndent': autoIndent,
        'pinchZoom': pinchZoom,
        'magnifier': magnifier,
        'enabledLangs': enabledLangs,
        'hiddenMenu': hiddenMenu,
        'floatMenu': floatMenu,
      };

  static List<String> _strList(dynamic v) {
    if (v is List) return v.whereType<String>().toList();
    return const <String>[];
  }

  static TextEditorPrefs fromJson(Map<String, dynamic> json) {
    return TextEditorPrefs(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 13,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.0,
      showGutter: json['showGutter'] as bool? ?? true,
      gutterDivider: json['gutterDivider'] as bool? ?? false,
      guideLines: json['guideLines'] as bool? ?? false,
      enableFolding: json['enableFolding'] as bool? ?? true,
      useTabs: json['useTabs'] as bool? ?? false,
      tabSize: (json['tabSize'] as num?)?.toInt() ?? 4,
      autoIndent: json['autoIndent'] as bool? ?? true,
      pinchZoom: json['pinchZoom'] as bool? ?? true,
      magnifier: json['magnifier'] as bool? ?? false,
      enabledLangs: _strList(json['enabledLangs']),
      hiddenMenu: _strList(json['hiddenMenu']),
      floatMenu: _strList(json['floatMenu']),
    );
  }
}

/// 全局编辑器偏好：一个可监听的值，编辑器与设置页共用。
class TextEditorPrefsStore {
  TextEditorPrefsStore._();

  static const String _key = 'text_editor_prefs_v1';

  static final ValueNotifier<TextEditorPrefs> notifier =
      ValueNotifier(const TextEditorPrefs());

  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await SharedPreferencesAsync().getString(_key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        notifier.value = TextEditorPrefs.fromJson(decoded);
      }
    } catch (_) {
      // 读取失败保持默认。
    }
  }

  static Future<void> update(TextEditorPrefs prefs) async {
    notifier.value = prefs;
    try {
      await SharedPreferencesAsync().setString(_key, jsonEncode(prefs.toJson()));
    } catch (_) {
      // 落盘失败不影响本次会话。
    }
  }
}
