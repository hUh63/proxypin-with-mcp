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

/// 查找框的「历史记录」与「收藏」。
///
/// 历史在每次回车查找时自动记录（去重、置顶、最多保留 [maxHistory] 条）；
/// 收藏由用户手动加星，永远排在最前。两者都只存在本地。
class FindHistory {
  FindHistory._();

  static const String _kHistory = 'find_history_v1';
  static const String _kFavorites = 'find_favorites_v1';

  /// 历史最多保留多少条。
  static const int maxHistory = 30;

  static Future<List<String>> loadHistory() async => _load(_kHistory);

  static Future<List<String>> loadFavorites() async => _load(_kFavorites);

  static Future<List<String>> _load(String key) async {
    try {
      final raw = await SharedPreferencesAsync().getString(key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().where((e) => e.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _save(String key, List<String> items) async {
    try {
      await SharedPreferencesAsync().setString(key, jsonEncode(items));
    } catch (_) {
      // 落盘失败不影响本次会话。
    }
  }

  /// 记录一次查找（去重，最近的排最前），返回新历史。
  static Future<List<String>> record(String query) async {
    final q = query.trim();
    if (q.isEmpty) return loadHistory();
    final cur = await loadHistory();
    final out = <String>[q, ...cur.where((e) => e != q)];
    if (out.length > maxHistory) out.removeRange(maxHistory, out.length);
    await _save(_kHistory, out);
    return out;
  }

  static Future<List<String>> clearHistory() async {
    await _save(_kHistory, const []);
    return const [];
  }

  /// 加 / 取消收藏，返回新收藏列表。
  static Future<List<String>> toggleFavorite(String query) async {
    final q = query.trim();
    if (q.isEmpty) return loadFavorites();
    final cur = await loadFavorites();
    final out = cur.contains(q)
        ? cur.where((e) => e != q).toList()
        : <String>[q, ...cur];
    await _save(_kFavorites, out);
    return out;
  }
}
