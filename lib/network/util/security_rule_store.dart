/*
 * Copyright 2023 Hongen Wang All rights reserved.
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
import 'package:proxypin/network/util/security_audit.dart';
import 'package:proxypin/storage/path.dart';

/// 安全自检的自定义规则存储（本地 JSON 持久化）。
///
/// 与内置规则互补：内置规则覆盖通用问题，自定义规则用来描述
/// 「自家业务的敏感字段 / 内部标记」等场景。
class SecurityRuleStore extends ChangeNotifier {
  static const String _fileName = 'security_rules.json';
  static SecurityRuleStore? _instance;

  final List<CustomSecurityRule> _rules = [];

  static Future<SecurityRuleStore> get instance async {
    if (_instance == null) {
      final store = SecurityRuleStore._internal();
      await store._load();
      _instance = store;
    }
    return _instance!;
  }

  SecurityRuleStore._internal();

  List<CustomSecurityRule> get rules => List.unmodifiable(_rules);

  Future<void> _load() async {
    _rules.clear();
    try {
      final file = await Paths.getPath(_fileName);
      final content = await file.readAsString();
      if (content.trim().isNotEmpty) {
        final decoded = jsonDecode(content);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final rule = CustomSecurityRule.fromJson(Map<String, dynamic>.from(item));
              if (rule.id.isNotEmpty) {
                _rules.add(rule);
              }
            }
          }
        }
      }
    } catch (e) {
      logger.e('自定义安全规则解析失败', error: e);
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final file = await Paths.getPath(_fileName);
      await file.writeAsString(jsonEncode(_rules.map((rule) => rule.toJson()).toList(growable: false)));
    } catch (e) {
      logger.e('自定义安全规则保存失败', error: e);
    }
  }

  Future<void> add(CustomSecurityRule rule) async {
    _rules.add(rule);
    await _save();
    notifyListeners();
  }

  Future<void> update(CustomSecurityRule rule) async {
    final index = _rules.indexWhere((item) => item.id == rule.id);
    if (index < 0) {
      _rules.add(rule);
    } else {
      _rules[index] = rule;
    }
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _rules.removeWhere((rule) => rule.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final index = _rules.indexWhere((rule) => rule.id == id);
    if (index < 0) return;
    _rules[index] = _rules[index].copyWith(enabled: enabled);
    await _save();
    notifyListeners();
  }

  /// 批量导入：按「名称 + 范围 + 表达式」判重，重复的跳过；
  /// 返回实际新增的规则数量（便于导入后给出准确提示）。
  Future<int> importRules(List<CustomSecurityRule> incoming) async {
    var added = 0;
    for (final rule in incoming) {
      final duplicated = _rules.any((item) =>
          item.name == rule.name && item.target == rule.target && item.pattern == rule.pattern);
      if (duplicated) continue;
      _rules.add(CustomSecurityRule(
        id: '${DateTime.now().microsecondsSinceEpoch}-$added',
        name: rule.name,
        enabled: rule.enabled,
        target: rule.target,
        matchType: rule.matchType,
        pattern: rule.pattern,
        severity: rule.severity,
        suggestion: rule.suggestion,
      ));
      added++;
    }
    if (added > 0) {
      await _save();
      notifyListeners();
    }
    return added;
  }
}
