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

// 「语法检查规则开关」的持久化 —— 按语言分开记。
//
// 之前的实现是一份全局集合：在 C# 里关掉「缺少分号」，写 Python 时那条规则
// 也跟着不查了。可这两件事本来没关系——人在不同语言里容忍的误报根本不同。
//
// 现在的模型很简单：
//   * `*`        一份「默认集合」，没单独设置过的语言都用它；
//   * `<语言>`    该语言自己的完整集合，一旦设置就完全取代默认。
// 所以「只对 C# 关掉分号」和「对所有语言关掉分号」是两条清晰的路，不会互相污染。
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 语法检查规则开关的按语言持久化（纯 Dart，无 flutter 依赖）。
class LintPrefs {
  LintPrefs._();

  /// 当前格式的 key。
  static const String prefsKey = 'code_lint_disabled_v2';

  /// 旧版（单集合）的 key，启动时迁移一次。
  static const String legacyKey = 'code_lint_disabled_v1';

  /// 「默认集合」的伪语言名。
  static const String globalKey = '*';

  static final Map<String, Set<String>> _map = <String, Set<String>>{};
  static bool _loaded = false;
  static Future<void>? _loading;

  /// 载入偏好（可重复调用，只读一次盘）。
  static Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    final pending = _loading;
    if (pending != null) return pending;
    return _loading = _load().whenComplete(() => _loading = null);
  }

  static Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (key is! String) return;
            final set = _asStringSet(value);
            if (set != null) _map[key] = set;
          });
        }
      } else {
        // 迁移旧格式：单集合当作「默认集合」，这样升级后行为不变。
        final legacy = prefs.getStringList(legacyKey);
        if (legacy != null && legacy.isNotEmpty) {
          _map[globalKey] = legacy.toSet();
          await _persist(prefs);
        }
      }
    } catch (_) {
      // 坏数据按「全部规则开启」处理
    }
    _loaded = true;
  }

  static Set<String>? _asStringSet(dynamic value) {
    if (value is! List) return null;
    final set = <String>{};
    for (final item in value) {
      if (item is String && item.isNotEmpty) set.add(item);
    }
    return set;
  }

  /// 某语言「实际生效」的关闭集合：有独立设置用自己的，否则用默认。
  static Set<String> disabledFor(String language) {
    final key = normalize(language);
    final own = _map[key];
    if (own != null) return Set<String>.from(own);
    final fallback = _map[globalKey];
    return fallback == null ? <String>{} : Set<String>.from(fallback);
  }

  /// 默认集合（没单独设置过的语言用它）。
  static Set<String> globalDefault() => Set<String>.from(_map[globalKey] ?? const <String>{});

  /// 该语言是否有独立设置（UI 用来显示「已单独设置」标记）。
  static bool hasOverride(String language) => _map.containsKey(normalize(language));

  /// 保存某语言的独立设置。
  static Future<void> setFor(String language, Set<String> disabled) async {
    final key = normalize(language);
    if (key.isEmpty || key == globalKey) return;
    if (disabled.isEmpty) {
      // 空的独立设置没有意义（等于「和默认一样没关」）——直接去掉这份覆盖，
      // 这样以后改默认集合它会跟着变。
      _map.remove(key);
    } else {
      _map[key] = Set<String>.from(disabled);
    }
    await _save();
  }

  /// 把一份集合写成「默认」，并清掉所有语言的独立设置。
  static Future<void> applyToAll(Set<String> disabled) async {
    _map.clear();
    if (disabled.isNotEmpty) _map[globalKey] = Set<String>.from(disabled);
    await _save();
  }

  /// 清掉所有独立设置，只保留默认集合。
  static Future<void> clearOverrides() async {
    final keep = _map[globalKey];
    _map.clear();
    if (keep != null && keep.isNotEmpty) _map[globalKey] = keep;
    await _save();
  }

  /// 单独设置过的语言列表（供调试/设置页展示）。
  static List<String> overrides() =>
      _map.keys.where((k) => k != globalKey).toList()..sort();

  /// 仅供测试：重置内存状态。
  static void resetForTest() {
    _map.clear();
    _loaded = false;
    _loading = null;
  }

  /// 仅供测试：直接塞入状态。
  static void seedForTest(Map<String, Set<String>> value) {
    resetForTest();
    _loaded = true;
    value.forEach((k, v) => _map[k] = Set<String>.from(v));
  }

  /// 语言标识归一：取小写。编辑器传 re_highlight 的 key（如 `csharp`、`dart`）。
  static String normalize(String language) {
    final key = language.trim().toLowerCase();
    if (key.isEmpty) return globalKey;
    if (key == globalKey) return globalKey;
    return key;
  }

  static Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _persist(prefs);
    } catch (_) {
      // 忽略：下次保存会重试
    }
  }

  static Future<void> _persist(SharedPreferences prefs) async {
    final payload = <String, List<String>>{};
    _map.forEach((key, value) {
      if (value.isEmpty) return;
      final list = value.toList()..sort();
      payload[key] = list;
    });
    await prefs.setString(prefsKey, jsonEncode(payload));
  }
}
