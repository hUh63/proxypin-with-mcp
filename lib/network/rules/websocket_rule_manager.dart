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
import 'package:shared_preferences/shared_preferences.dart';
import 'websocket_rule.dart';

/// WebSocket 规则管理器 - 使用 SharedPreferences 持久化存储规则
class WebSocketRuleManager {
  static final WebSocketRuleManager _instance = WebSocketRuleManager._internal();
  factory WebSocketRuleManager() => _instance;
  WebSocketRuleManager._internal();

  static const String _rulesKey = 'websocket_intercept_rules';
  static const String _globalEnabledKey = 'websocket_intercept_global_enabled';

  final List<WebSocketRule> _rules = [];
  bool _globalEnabled = false;
  bool _initialized = false;

  /// 初始化 - 从 SharedPreferences 加载规则
  Future<void> init() async {
    if (_initialized) return;
    
    final prefs = await SharedPreferences.getInstance();
    await _loadRules(prefs);
    _globalEnabled = prefs.getBool(_globalEnabledKey) ?? false;
    _initialized = true;
  }

  /// 从 SharedPreferences 加载规则
  Future<void> _loadRules(SharedPreferences prefs) async {
    final rulesJson = prefs.getString(_rulesKey);
    if (rulesJson != null && rulesJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(rulesJson);
        _rules.clear();
        _rules.addAll(
          decoded.map((e) => WebSocketRule.fromJson(e as Map<String, dynamic>)),
        );
      } catch (e) {
        // JSON 解析失败，使用空规则列表
        _rules.clear();
      }
    }
  }

  /// 保存规则到 SharedPreferences
  Future<void> _saveRules(SharedPreferences prefs) async {
    final rulesJson = jsonEncode(_rules.map((r) => r.toJson()).toList());
    await prefs.setString(_rulesKey, rulesJson);
  }

  /// 获取所有规则
  List<WebSocketRule> get rules => List.unmodifiable(_rules);

  /// 获取启用的规则
  List<WebSocketRule> get enabledRules => 
      _rules.where((r) => r.enabled).toList();

  /// 获取全局启用状态
  bool get globalEnabled => _globalEnabled;

  /// 设置全局启用状态
  Future<void> setGlobalEnabled(bool enabled) async {
    _globalEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_globalEnabledKey, enabled);
  }

  /// 添加规则
  Future<WebSocketRule> addRule({
    required String name,
    required String pattern,
    RuleMatchMode mode = RuleMatchMode.contains,
    bool enabled = true,
    bool interceptOutgoing = true,
    bool interceptIncoming = true,
    String? description,
    WsFrameAction action = WsFrameAction.observe,
    String? payloadPattern,
    String? replacement,
    int delayMs = 0,
  }) async {
    final rule = WebSocketRule(
      id: 'rule_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      pattern: pattern,
      mode: mode,
      enabled: enabled,
      interceptOutgoing: interceptOutgoing,
      interceptIncoming: interceptIncoming,
      description: description,
      action: action,
      payloadPattern: payloadPattern,
      replacement: replacement,
      delayMs: delayMs,
    );

    _rules.add(rule);
    final prefs = await SharedPreferences.getInstance();
    await _saveRules(prefs);
    
    return rule;
  }

  /// 更新规则
  Future<bool> updateRule(String ruleId, WebSocketRule updatedRule) async {
    final index = _rules.indexWhere((r) => r.id == ruleId);
    if (index == -1) return false;
    
    _rules[index] = updatedRule;
    final prefs = await SharedPreferences.getInstance();
    await _saveRules(prefs);
    
    return true;
  }

  /// 删除规则
  Future<bool> deleteRule(String ruleId) async {
    final index = _rules.indexWhere((r) => r.id == ruleId);
    if (index == -1) return false;
    
    _rules.removeAt(index);
    final prefs = await SharedPreferences.getInstance();
    await _saveRules(prefs);
    
    return true;
  }

  /// 切换规则启用状态
  Future<bool> toggleRule(String ruleId) async {
    final index = _rules.indexWhere((r) => r.id == ruleId);
    if (index == -1) return false;
    
    final rule = _rules[index];
    _rules[index] = rule.copyWith(enabled: !rule.enabled);
    final prefs = await SharedPreferences.getInstance();
    await _saveRules(prefs);
    
    return true;
  }

  /// 检查 URL 是否匹配任何启用的规则
  bool matchesAnyRule(String url) {
    if (!_globalEnabled) return false;
    return enabledRules.any((rule) => rule.matches(url));
  }

  /// 获取匹配 URL 的规则列表
  List<WebSocketRule> getMatchingRules(String url) {
    if (!_globalEnabled) return [];
    return enabledRules.where((rule) => rule.matches(url)).toList();
  }

  /// 检查是否应该拦截 WebSocket 消息
  InterceptDecision shouldIntercept(String url, bool isOutgoing) {
    if (!_globalEnabled) {
      return InterceptDecision(shouldIntercept: false, reason: '全局拦截已禁用');
    }
    
    final matchingRules = getMatchingRules(url);
    if (matchingRules.isEmpty) {
      return InterceptDecision(shouldIntercept: false, reason: '无匹配规则');
    }
    
    // 检查方向
    final directionRules = isOutgoing 
        ? matchingRules.where((r) => r.interceptOutgoing).toList()
        : matchingRules.where((r) => r.interceptIncoming).toList();
    
    if (directionRules.isEmpty) {
      return InterceptDecision(
        shouldIntercept: false, 
        reason: '无匹配${isOutgoing ? "发出" : "接收"}方向的规则',
      );
    }
    
    return InterceptDecision(
      shouldIntercept: true,
      reason: '匹配 ${directionRules.length} 条规则',
      matchedRules: directionRules,
    );
  }

  /// 清空所有规则
  Future<void> clearAllRules() async {
    _rules.clear();
    final prefs = await SharedPreferences.getInstance();
    await _saveRules(prefs);
  }

  /// 导出规则为 JSON 字符串
  Future<String> exportRules() async {
    return jsonEncode(_rules.map((r) => r.toJson()).toList());
  }

  /// 从 JSON 字符串导入规则
  Future<bool> importRules(String jsonStr) async {
    try {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      _rules.clear();
      _rules.addAll(
        decoded.map((e) => WebSocketRule.fromJson(e as Map<String, dynamic>)),
      );
      final prefs = await SharedPreferences.getInstance();
      await _saveRules(prefs);
      return true;
    } catch (e) {
      return false;
    }
  }
}

/// 拦截决策结果
class InterceptDecision {
  final bool shouldIntercept;
  final String reason;
  final List<WebSocketRule> matchedRules;

  InterceptDecision({
    required this.shouldIntercept,
    required this.reason,
    this.matchedRules = const [],
  });

  @override
  String toString() {
    return 'InterceptDecision(should: $shouldIntercept, reason: $reason, rules: ${matchedRules.length})';
  }
}
