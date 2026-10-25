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

// 本地学习「这个人会写哪些词」。
//
// 补全候选的排序原本只看「前缀匹配 + 上下文位置」。同一个人写同一种语言时，
// 常用词其实非常集中：他一天里打 fifty 次 `print`，就基本不会再打 `console`。
// 这里记两件事——**弹过什么**（shown）和**真的用了什么**（accepted）——然后
// 用「对数频次 + 命中率」给候选加权，下次把这个人的习惯往前排。
//
// 只存在本机、按语言分开、每语言最多 200 个词；写盘节流 3 秒，不会在打字时抖。
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// 补全候选的本地使用统计（纯 Dart，无 flutter 依赖，便于单测）。
class SuggestionStats {
  SuggestionStats._();

  static const String _prefsKey = 'suggestion_stats_v1';

  /// 每种语言最多记多少个词（超出淘汰频次最低的）。
  static const int _maxWordsPerLang = 200;

  /// 「弹过」的记录上限：只记最近这么多条，避免无界。
  static const int _maxShownEntries = 4000;

  /// 写盘节流间隔。
  static const Duration flushDelay = Duration(seconds: 3);

  /// 语言 → 词 → 接受次数。
  static final Map<String, Map<String, int>> _accepted = <String, Map<String, int>>{};

  /// 语言 → 词 → 弹出次数。
  static final Map<String, Map<String, int>> _shown = <String, Map<String, int>>{};

  static bool _loaded = false;
  static bool _dirty = false;
  static Timer? _flushTimer;
  static Future<void>? _loading;

  /// 载入偏好（可重复调用，只有第一次真正读盘）。
  ///
  /// 补全路径是同步的，不能等 IO —— 所以调用方用 `unawaited(ensureLoaded())`
  /// 提前热身即可，未载入前 [weight] 全部返回 0（等价于「还没学过」）。
  static Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    final pending = _loading;
    if (pending != null) return pending;
    return _loading = _load().whenComplete(() => _loading = null);
  }

  static Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw);
        if (map is Map) {
          _readInto(_accepted, map['accepted']);
          _readInto(_shown, map['shown']);
        }
      }
    } catch (_) {
      // 坏数据当「没学过」处理，下次写入自动覆盖
    }
    _loaded = true;
  }

  /// 逐条容错地读回来（一份坏记录不该让整份统计作废）。
  static void _readInto(Map<String, Map<String, int>> target, dynamic raw) {
    if (raw is! Map) return;
    raw.forEach((key, value) {
      if (key is! String || value is! Map) return;
      final bucket = <String, int>{};
      value.forEach((k, v) {
        if (k is! String) return;
        if (v is int && v > 0) {
          bucket[k] = v;
        } else if (v is num && v > 0) {
          bucket[k] = v.toInt();
        }
      });
      if (bucket.isNotEmpty) target[key] = bucket;
    });
  }

  /// 记录「这些候选被弹出过」。[words] 只放上下文联想真正列出来的词。
  static void recordShown(String language, Iterable<String> words) {
    final lang = normalize(language);
    if (lang.isEmpty) return;
    final bucket = _shown.putIfAbsent(lang, () => <String, int>{});
    var changed = false;
    for (final w in words) {
      final word = w.trim();
      if (word.isEmpty || word.length > 40) continue;
      if (bucket.length >= _maxShownEntries && !bucket.containsKey(word)) continue;
      bucket[word] = (bucket[word] ?? 0) + 1;
      changed = true;
    }
    if (changed) _markDirty();
  }

  /// 记录「用户真的用了这条」。
  static void recordAccepted(String language, String word) {
    final lang = normalize(language);
    final w = word.trim();
    if (lang.isEmpty || w.isEmpty || w.length > 40) return;
    final bucket = _accepted.putIfAbsent(lang, () => <String, int>{});
    bucket[w] = (bucket[w] ?? 0) + 1;
    _evictIfNeeded(bucket);
    _markDirty();
  }

  /// 只用一次就忘了：删掉某条统计（规则被关掉、候选被删等场景）。
  static void forget(String language, String word) {
    final lang = normalize(language);
    if (lang.isEmpty) return;
    final a = _accepted[lang];
    final s = _shown[lang];
    var changed = false;
    if (a != null && a.remove(word) != null) changed = true;
    if (s != null && s.remove(word) != null) changed = true;
    if (changed) _markDirty();
  }

  /// 清空某个语言（或全部）的统计。
  static void clear([String? language]) {
    if (language == null) {
      _accepted.clear();
      _shown.clear();
    } else {
      final lang = normalize(language);
      _accepted.remove(lang);
      _shown.remove(lang);
    }
    _markDirty();
    unawaited(flush());
  }

  /// 某个词的权重（0 表示没学过）。对数频次 + 命中率，避免「偶尔弹一次就永远置顶」。
  static double weight(String language, String word) {
    final lang = normalize(language);
    if (lang.isEmpty) return 0;
    final accepted = _accepted[lang]?[word] ?? 0;
    final shown = _shown[lang]?[word] ?? 0;
    if (accepted == 0 && shown == 0) return 0;
    final freq = accepted <= 0 ? 0.0 : math.log(accepted + 1) / math.ln2;
    final rate = shown <= 0 ? (accepted > 0 ? 0.5 : 0.0) : accepted / shown;
    return freq + rate * 2;
  }

  /// 按学到的权重重排候选：权重高的在前，权重相同保持原顺序。
  ///
  /// 原顺序是有语义的（上下文联想里「更贴当前场景」的排在前面），
  /// 所以这里必须稳定——只有真正学过的词才会移动位置。
  static List<String> rank(String language, List<String> words) {
    if (words.length < 2) return words;
    if (_accepted.isEmpty && _shown.isEmpty) return words;
    final lang = normalize(language);
    if (lang.isEmpty) return words;
    final weights = <String, double>{};
    var max = 0.0;
    for (final w in words) {
      final v = weight(lang, w);
      if (v > 0) {
        weights[w] = v;
        if (v > max) max = v;
      }
    }
    if (weights.isEmpty) return words;
    final indexed = <int>[];
    for (var i = 0; i < words.length; i++) {
      indexed.add(i);
    }
    indexed.sort((a, b) {
      final wa = weights[words[a]] ?? 0;
      final wb = weights[words[b]] ?? 0;
      if (wa != wb) return wb.compareTo(wa);
      return a.compareTo(b);
    });
    return [for (final i in indexed) words[i]];
  }

  /// 某语言里学到的词数（供设置页/调试展示）。
  static int learnedCount([String? language]) {
    if (language == null) {
      return _accepted.values.fold(0, (sum, e) => sum + e.length);
    }
    return _accepted[normalize(language)]?.length ?? 0;
  }

  /// 立刻写盘（应用退出、切换文档等时机）。
  static Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (!_dirty) return;
    _dirty = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode({
        'accepted': _accepted,
        'shown': _shown,
      }));
    } catch (_) {
      _dirty = true; // 写失败留待下次
    }
  }

  /// 仅供测试：重置内存状态。
  static void resetForTest() {
    _accepted.clear();
    _shown.clear();
    _loaded = false;
    _dirty = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    _loading = null;
  }

  /// 仅供测试：不落盘地塞入统计数据。
  static void seedForTest({
    Map<String, Map<String, int>>? accepted,
    Map<String, Map<String, int>>? shown,
  }) {
    resetForTest();
    _loaded = true;
    if (accepted != null) _accepted.addAll(accepted);
    if (shown != null) _shown.addAll(shown);
  }

  static String normalize(String language) => language.trim().toLowerCase();

  static void _evictIfNeeded(Map<String, int> bucket) {
    if (bucket.length <= _maxWordsPerLang) return;
    final keys = bucket.keys.toList()
      ..sort((a, b) => (bucket[a] ?? 0).compareTo(bucket[b] ?? 0));
    final drop = bucket.length - _maxWordsPerLang;
    for (var i = 0; i < drop && i < keys.length; i++) {
      bucket.remove(keys[i]);
    }
  }

  static void _markDirty() {
    _dirty = true;
    _flushTimer ??= Timer(flushDelay, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }
}
