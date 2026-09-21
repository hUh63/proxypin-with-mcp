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

/// WebSocket 拦截规则匹配模式
enum RuleMatchMode {
  contains,    // 包含
  startsWith,  // 开头
  endsWith,    // 结尾
  regex,       // 正则表达式
  exact        // 完全匹配
}

/// 帧级动作（上游 #839 Feature Request 1）
enum WsFrameAction {
  observe, // 仅匹配记录，不干预转发（默认，兼容旧规则）
  rewrite, // 改写帧内容
  drop, // 丢弃该帧
  delay, // 延迟转发
  duplicate, // 重复发送一帧
}

/// WebSocket 拦截规则
class WebSocketRule {
  final String id;
  final String name;
  final String pattern;      // URL 匹配模式
  final RuleMatchMode mode;  // 匹配模式
  final bool enabled;        // 是否启用
  final bool interceptOutgoing;  // 是否拦截发出的消息
  final bool interceptIncoming;  // 是否拦截接收的消息
  final String? description; // 规则描述

  /// 帧级动作（上游 #839 FR1）。observe 表示只匹配、不改动字节，
  /// 老规则同校后就是这个值，行为与以前一致。
  final WsFrameAction action;

  /// 帧内容匹配条件；为空表示匹配该方向的所有帧
  final String? payloadPattern;

  /// rewrite 动作使用的新内容
  final String? replacement;

  /// delay 动作的延迟毫秒数
  final int delayMs;

  final DateTime createdAt;
  final DateTime updatedAt;

  WebSocketRule({
    required this.id,
    required this.name,
    required this.pattern,
    this.mode = RuleMatchMode.contains,
    this.enabled = true,
    this.interceptOutgoing = true,
    this.interceptIncoming = true,
    this.description,
    this.action = WsFrameAction.observe,
    this.payloadPattern,
    this.replacement,
    this.delayMs = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 检查 URL 是否匹配此规则
  bool matches(String url) {
    if (!enabled) return false;
    
    switch (mode) {
      case RuleMatchMode.contains:
        return url.contains(pattern);
      case RuleMatchMode.startsWith:
        return url.startsWith(pattern);
      case RuleMatchMode.endsWith:
        return url.endsWith(pattern);
      case RuleMatchMode.exact:
        return url == pattern;
      case RuleMatchMode.regex:
        try {
          return RegExp(pattern).hasMatch(url);
        } catch (e) {
          return false;
        }
    }
  }

  /// 帧内容是否命中本规则的 payloadPattern（上游 #839 FR1）。
  /// pattern 为空时表示不限内容，该方向所有帧都算命中。
  bool matchesPayload(String payload) {
    final pattern = payloadPattern;
    if (pattern == null || pattern.isEmpty) return true;

    switch (mode) {
      case RuleMatchMode.contains:
        return payload.contains(pattern);
      case RuleMatchMode.startsWith:
        return payload.startsWith(pattern);
      case RuleMatchMode.endsWith:
        return payload.endsWith(pattern);
      case RuleMatchMode.exact:
        return payload == pattern;
      case RuleMatchMode.regex:
        try {
          return RegExp(pattern).hasMatch(payload);
        } catch (e) {
          return false;
        }
    }
  }

  /// 从 JSON 创建规则
  factory WebSocketRule.fromJson(Map<String, dynamic> json) {
    return WebSocketRule(
      id: json['id'] as String,
      name: json['name'] as String,
      pattern: json['pattern'] as String,
      mode: RuleMatchMode.values.firstWhere(
        (e) => e.name == json['mode'],
        orElse: () => RuleMatchMode.contains,
      ),
      enabled: json['enabled'] as bool? ?? true,
      interceptOutgoing: json['interceptOutgoing'] as bool? ?? true,
      interceptIncoming: json['interceptIncoming'] as bool? ?? true,
      description: json['description'] as String?,
      action: WsFrameAction.values.firstWhere(
        (e) => e.name == json['action'],
        orElse: () => WsFrameAction.observe,
      ),
      payloadPattern: json['payloadPattern'] as String?,
      replacement: json['replacement'] as String?,
      delayMs: json['delayMs'] as int? ?? 0,
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt'] as String) 
          : null,
      updatedAt: json['updatedAt'] != null 
          ? DateTime.parse(json['updatedAt'] as String) 
          : null,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'pattern': pattern,
      'mode': mode.name,
      'enabled': enabled,
      'interceptOutgoing': interceptOutgoing,
      'interceptIncoming': interceptIncoming,
      'description': description,
      'action': action.name,
      'payloadPattern': payloadPattern,
      'replacement': replacement,
      'delayMs': delayMs,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 复制并修改规则
  WebSocketRule copyWith({
    String? name,
    String? pattern,
    RuleMatchMode? mode,
    bool? enabled,
    bool? interceptOutgoing,
    bool? interceptIncoming,
    String? description,
    WsFrameAction? action,
    String? payloadPattern,
    String? replacement,
    int? delayMs,
  }) {
    return WebSocketRule(
      id: id,
      name: name ?? this.name,
      pattern: pattern ?? this.pattern,
      mode: mode ?? this.mode,
      enabled: enabled ?? this.enabled,
      interceptOutgoing: interceptOutgoing ?? this.interceptOutgoing,
      interceptIncoming: interceptIncoming ?? this.interceptIncoming,
      description: description ?? this.description,
      action: action ?? this.action,
      payloadPattern: payloadPattern ?? this.payloadPattern,
      replacement: replacement ?? this.replacement,
      delayMs: delayMs ?? this.delayMs,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'WebSocketRule(id: $id, name: $name, pattern: $pattern, mode: $mode, enabled: $enabled)';
  }
}
