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

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:proxypin/event/event_bus.dart';
import 'package:proxypin/network/components/manager/script_manager.dart';
import 'package:proxypin/network/components/js/script_engine.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/mcp/mcp_event_automation.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/path.dart';
import 'package:proxypin/network/util/serial_file_writer.dart';

/// 规则优先级
enum RulePriority { low, normal, high, critical }

/// 条件类型
enum ConditionType {
  httpRequest,
  networkStatus,
  proxyStatus,
  systemStatus,
  custom,
}

/// 操作符
enum Operator {
  equals,
  notEquals,
  greaterThan,
  lessThan,
  greaterThanOrEqual,
  lessThanOrEqual,
  contains,
  startsWith,
  endsWith,
  matches,
  inList,
  notInList,
  exists,
  notExists,
}

/// 动作类型
enum ActionType {
  log,
  notify,
  stopCapture,
  startCapture,
  exportData,
  executeScript,
  sendWebhook,
  custom,
}

/// 动作回调类型
typedef ActionCallback = Future<void> Function(dynamic context, Map<String, dynamic>? params);

/// 规则执行记录
class RuleExecutionRecord {
  final String ruleId;
  final DateTime timestamp;
  final bool matched;
  final String? action;
  
  RuleExecutionRecord(this.ruleId, this.matched, this.action) 
      : timestamp = DateTime.now();
}

/// 规则类
class Rule {
  final String id;
  final String name;
  final String description;
  final List<Condition> conditions;
  final List<Action> actions;
  final RulePriority priority;
  bool enabled;
  final DateTime? expiresAt;

  Rule({
    required this.id,
    required this.name,
    this.description = '',
    required this.conditions,
    required this.actions,
    this.priority = RulePriority.normal,
    this.enabled = true,
    this.expiresAt,
  });

  /// 检查规则是否过期
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// 检查规则是否可用
  bool get isAvailable => enabled && !isExpired;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'conditions': conditions.map((c) => c.toJson()).toList(),
        'actions': actions.map((a) => a.toJson()).toList(),
        'priority': priority.name,
        'enabled': enabled,
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
      };

  factory Rule.fromJson(Map<String, dynamic> json) => Rule(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        conditions: (json['conditions'] as List<dynamic>? ?? [])
            .map((e) => Condition.fromJson(e as Map<String, dynamic>))
            .toList(),
        actions: (json['actions'] as List<dynamic>? ?? [])
            .map((e) => Action.fromJson(e as Map<String, dynamic>))
            .toList(),
        priority: _enumByName(RulePriority.values, json['priority'] as String?, RulePriority.normal),
        enabled: json['enabled'] as bool? ?? true,
        expiresAt: json['expiresAt'] == null ? null : DateTime.tryParse(json['expiresAt'] as String),
      );
}

/// 条件类
class Condition {
  final ConditionType type;
  final String field;
  final Operator operator;
  final dynamic value;

  Condition({
    required this.type,
    required this.field,
    required this.operator,
    required this.value,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'field': field,
        'operator': operator.name,
        'value': _encodeValue(value),
      };

  factory Condition.fromJson(Map<String, dynamic> json) => Condition(
        type: _enumByName(ConditionType.values, json['type'] as String?, ConditionType.custom),
        field: json['field'] as String,
        operator: _enumByName(Operator.values, json['operator'] as String?, Operator.equals),
        value: _decodeValue(json['value']),
      );

  /// 评估条件是否匹配
  bool evaluate(dynamic context) {
    final actualValue = _getFieldValue(context, field);
    
    switch (operator) {
      case Operator.equals:
        return actualValue == value;
      case Operator.notEquals:
        return actualValue != value;
      case Operator.greaterThan:
        return _compare(actualValue, value) > 0;
      case Operator.lessThan:
        return _compare(actualValue, value) < 0;
      case Operator.greaterThanOrEqual:
        return _compare(actualValue, value) >= 0;
      case Operator.lessThanOrEqual:
        return _compare(actualValue, value) <= 0;
      case Operator.contains:
        return actualValue.toString().contains(value.toString());
      case Operator.startsWith:
        return actualValue.toString().startsWith(value.toString());
      case Operator.endsWith:
        return actualValue.toString().endsWith(value.toString());
      case Operator.matches: {
        if (value is RegExp) return value.hasMatch(actualValue.toString());
        // 用户可手填正则，非法模式（"(" / "[a-" / "*foo"）会让 RegExp()
        // 抛 FormatException。旧实现无保护，every() 随之中断，后续所有规则
        // （含 critical）都不再评估，执行历史里连一条记录都留不下。
        try {
          return RegExp(value.toString()).hasMatch(actualValue.toString());
        } catch (_) {
          return false;
        }
      }
      case Operator.inList:
        if (value is List) {
          return value.contains(actualValue);
        }
        return false;
      case Operator.notInList:
        if (value is List) {
          return !value.contains(actualValue);
        }
        return true;
      case Operator.exists:
        return actualValue != null;
      case Operator.notExists:
        return actualValue == null;
    }
  }

  /// 获取字段值（支持 ConditionType 感知的字段提取）
  dynamic _getFieldValue(dynamic context, String field) {
    if (context == null) return null;

    // 优先按条件自身类型提取（无论 context 是否包含 type 字段）
    if (type != ConditionType.httpRequest && type != ConditionType.custom) {
      if (context is Map) {
        return _getConditionContextField(context, type, field);
      }
    }

    // 兼容旧版：按 context 中的 type 推断
    if (context is Map) {
      // 不能 `as String?` 强转：context 由调用方构造，type 偶尔会是非字符串值，
      // 强转会在响应热路径上抛 TypeError 打断整轮规则评估。
      final rawType = context['type'];
      final typeStr = rawType is String ? rawType : (rawType == null ? null : '$rawType');
      if (typeStr != null) {
        final detectedType = _enumByName(ConditionType.values, typeStr, ConditionType.custom);
        if (detectedType != ConditionType.httpRequest && detectedType != ConditionType.custom) {
          return _getConditionContextField(context, detectedType, field);
        }
      }
    }

    // 通用嵌套字段提取（httpRequest 或 custom）
    final parts = field.split('.');
    dynamic result = context;

    for (final part in parts) {
      if (result is Map) {
        result = result[part];
      } else if (result is HttpRequest) {
        result = _getHttpRequestField(result, part);
      } else {
        return null;
      }

      if (result == null) break;
    }

    return result;
  }

  /// 获取非 HTTP 条件类型的上下文字段
  dynamic _getConditionContextField(Map context, ConditionType type, String field) {
    switch (type) {
      case ConditionType.proxyStatus:
        switch (field) {
          case 'status':
            final v = context['status'];
            return v is ProxyStatus ? v.name : v;
          case 'type':
            return 'proxyStatus';
          case 'timestamp':
            return context['timestamp'];
          default:
            return context[field];
        }
      case ConditionType.networkStatus:
        switch (field) {
          case 'status':
            final v = context['status'];
            return v is NetworkStatus ? v.name : v;
          case 'type':
            return context['type'] ?? context['networkType'];
          case 'timestamp':
            return context['timestamp'];
          default:
            return context[field];
        }
      case ConditionType.systemStatus:
        switch (field) {
          case 'memoryUsage':
            return context['memoryUsage'];
          case 'captureCount':
            return context['captureCount'];
          case 'diskUsage':
            return context['diskUsage'];
          case 'cpuUsage':
            return context['cpuUsage'];
          default:
            return context[field];
        }
      default:
        return context[field];
    }
  }

  /// 获取 HttpRequest 字段
  dynamic _getHttpRequestField(HttpRequest request, String field) {
    switch (field) {
      case 'url':
        return request.requestUrl;
      case 'method':
        return request.methodLabel;
      case 'statusCode':
        return request.response?.status.code;
      case 'duration':
        return request.response != null 
            ? request.response!.responseTime.difference(request.requestTime).inMilliseconds 
            : 0;
      case 'requestSize':
        return request.contentLength;
      case 'responseSize':
        return request.response?.contentLength ?? 0;
      case 'host':
        return request.hostAndPort?.host ?? request.requestUri?.host;
      case 'path':
        return request.path;
      case 'contentType':
        return request.headers.contentType;
      case 'responseContentType':
        return request.response?.headers.contentType;
      default:
        return null;
    }
  }

  /// 比较两个值
  int _compare(dynamic a, dynamic b) {
    if (a is num && b is num) {
      return a.compareTo(b);
    }
    if (a is DateTime && b is DateTime) {
      return a.compareTo(b);
    }
    // 数值条件常以字符串形式保存（"200" / "1.5"）。纯字典序比较会把 "1000" 判成
    // 小于 "200"，`bodySize > 200` 这类条件结果直接反了。
    final na = _asDouble(a);
    final nb = _asDouble(b);
    if (na != null && nb != null) {
      return na.compareTo(nb);
    }
    return '$a'.compareTo('$b');
  }

  /// 尽量把任意值解析成 double；解析不出返回 null。
  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }
}

/// 动作类
class Action {
  final ActionType type;
  final String? target;
  final Map<String, dynamic>? parameters;
  final ActionCallback? callback;

  Action({
    required this.type,
    this.target,
    this.parameters,
    this.callback,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (target != null) 'target': target,
        if (parameters != null) 'parameters': parameters,
      };

  factory Action.fromJson(Map<String, dynamic> json) => Action(
        type: _enumByName(ActionType.values, json['type'] as String?, ActionType.log),
        target: json['target'] as String?,
        parameters: json['parameters'] as Map<String, dynamic>?,
      );

  /// 执行动作
  Future<void> execute(dynamic context) async {
    if (callback != null) {
      await callback!(context, parameters);
    } else if (type == ActionType.sendWebhook) {
      // Webhook 动作实现：发送 HTTP POST 请求到指定 URL
      await _executeWebhook(context, parameters);
    } else if (type == ActionType.executeScript) {
      // 脚本执行动作增强：支持多种脚本类型
      await _executeScript(context, parameters);
    } else if (type == ActionType.log) {
      logger.i('规则动作[log]: target=$target params=$parameters');
    } else if (type == ActionType.notify) {
      // 通知动作：经 EventBus 发布，由 UI 层展示 toast 通知
      final title = parameters?['title'] as String? ?? 'ProxyPin 规则引擎';
      final message = target ?? parameters?['message'] as String? ?? '规则触发通知';
      logger.i('规则动作[notify]: $title - $message');
      try {
        EventBus().publish(GenericEvent('notification', data: {'title': title, 'message': message}));
      } catch (e) {
        logger.e('规则动作[notify] 发布失败：$e');
      }
    } else if (type == ActionType.stopCapture || type == ActionType.startCapture) {
      // 抓包启停动作：经 EventBus 发布控制事件，由 UI 层（持有 ProxyServer 引用）执行
      final action = type == ActionType.stopCapture ? 'stop' : 'start';
      logger.i('规则动作[${type.name}]: 发布抓包控制事件');
      try {
        EventBus().publish(GenericEvent('mcp_capture_control', data: {'action': action}));
      } catch (e) {
        logger.e('规则动作[${type.name}] 发布失败：$e');
      }
    } else {
      logger.i('规则动作[${type.name}]: target=$target params=$parameters');
    }
  }

  /// 执行 Webhook 动作
  Future<void> _executeWebhook(dynamic context, Map<String, dynamic>? params) async {
    try {
      final url = params?['url'] as String?;
      if (url == null || url.isEmpty) {
        logger.w('Webhook URL 未指定');
        return;
      }

      final payload = params?['payload'] as Map<String, dynamic>? ?? {};
      final headers = Map<String, String>.from(params?['headers'] ?? {});
      headers['Content-Type'] = 'application/json';

      // 从上下文获取请求信息
      if (context != null) {
        payload['timestamp'] = DateTime.now().toIso8601String();
        payload['source'] = 'ProxyPin Rule Engine';
      }

      logger.i('发送 Webhook 到：$url');
      // 动作是串行 await 的：不可达但建连不返回的地址（黑洞 IP、内网蜜罐）
      // 会把整条规则评估链挂住数分钟，后续规则的动作全部不执行。
      final response = await http
          .post(Uri.parse(url), headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 10));
      logger.i('Webhook 响应：${response.statusCode}');
    } catch (e) {
      logger.e('Webhook 发送失败：$e');
    }
  }

  /// 执行脚本动作（增强版）
  Future<void> _executeScript(dynamic context, Map<String, dynamic>? params) async {
    try {
      final scriptType = params?['type'] as String? ?? 'dart';
      final scriptContent = params?['content'] as String?;
      final scriptPath = params?['path'] as String? ?? params?['name'] as String?;

      if (scriptContent == null && scriptPath == null) {
        logger.w('脚本内容或路径未指定');
        return;
      }

      // 优先按名称复用 ScriptManager.runStandalone（请求绑定模型，含 env 副作用）
      if (scriptPath != null && scriptPath.isNotEmpty) {
        final mgr = await ScriptManager.instance;
        for (final s in mgr.list) {
          if (s.name == scriptPath) {
            await mgr.runStandalone(s);
            return;
          }
        }
      }

      logger.i('执行脚本：type=$scriptType, path=$scriptPath');
      
      switch (scriptType) {
        case 'dart':
          // Dart 脚本执行（需要隔离环境）
          await _executeDartScript(scriptContent, scriptPath, context);
          break;
        case 'javascript':
          // JavaScript 脚本执行（通过 JS 引擎）
          await _executeJavaScript(scriptContent, scriptPath, context);
          break;
        case 'shell':
          // Shell 脚本执行（仅 Android/桌面）
          await _executeShellScript(scriptContent, scriptPath, context);
          break;
        case 'python':
          // Python 脚本执行（需要 Python 环境）
          await _executePythonScript(scriptContent, scriptPath, context);
          break;
        default:
          logger.w('不支持的脚本类型：$scriptType');
      }
    } catch (e) {
      logger.e('脚本执行失败：$e');
    }
  }

  /// 执行 Dart 脚本：按名称查找 ScriptManager 注册脚本，走 runStandalone（含 env 副作用）
  Future<void> _executeDartScript(String? content, String? path, dynamic context) async {
    if (path != null && path.isNotEmpty) {
      final mgr = await ScriptManager.instance;
      for (final s in mgr.list) {
        if (s.name == path) {
          await mgr.runStandalone(s);
          return;
        }
      }
    }
    // 无注册脚本时仅记录；Dart 内联脚本需要 Isolate 隔离执行，暂留为扩展点
    logger.i('执行 Dart 脚本（内联）：content=$content');
  }

  /// 执行 JavaScript 脚本：通过 flutter_js 引擎真实执行
  Future<void> _executeJavaScript(String? content, String? path, dynamic context) async {
    // 优先按名称复用 ScriptManager 注册脚本
    if (path != null && path.isNotEmpty) {
      final mgr = await ScriptManager.instance;
      for (final s in mgr.list) {
        if (s.name == path) {
          await mgr.runStandalone(s);
          return;
        }
      }
    }
    // 内联 JavaScript：通过 flutterJs 引擎直接执行
    if (content == null || content.isEmpty) {
      logger.w('JavaScript 内容为空');
      return;
    }
    try {
      final mgr = await ScriptManager.instance;
      await ScriptManager.flutterJsPool.run((flutterJs) async {
        final jsResult = await flutterJs.evaluateAsync(
          'var context = {}; $content\n  onRequest(context, {})');
        return await JavaScriptEngine.jsResultResolve(flutterJs, jsResult);
      });
      logger.i('JavaScript 内联脚本执行完成');
    } catch (e, st) {
      logger.e('JavaScript 脚本执行失败', error: e, stackTrace: st);
    }
  }

  /// 执行 Shell 脚本
  Future<void> _executeShellScript(String? content, String? path, dynamic context) async {
    logger.i('执行 Shell 脚本');
    // Shell 已预留执行入口，需 ROOT/Shizuku 权限
  }

  /// 执行 Python 脚本
  Future<void> _executePythonScript(String? content, String? path, dynamic context) async {
    logger.i('执行 Python 脚本');
    // Python 已预留执行入口，可通过 FFI 集成
  }
}

/// 枚举名 -> 枚举值（未知/缺失时回退到 fallback）
T _enumByName<T extends Enum>(Iterable<T> values, String? name, T fallback) {
  if (name == null) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// 序列化条件值：RegExp 等非 JSON 类型编码为标记 Map
dynamic _encodeValue(dynamic value) {
  if (value is RegExp) {
    return {'__regexp__': value.pattern};
  }
  if (value is List) {
    return value.map(_encodeValue).toList();
  }
  if (value is Map) {
    return value.map((k, v) => MapEntry(k, _encodeValue(v)));
  }
  return value; // String / num / bool / null
}

/// 反序列化条件值
dynamic _decodeValue(dynamic value) {
  if (value is Map && value.containsKey('__regexp__')) {
    final rawPattern = value['__regexp__'];
    final pattern = rawPattern is String ? rawPattern : '$rawPattern';
    try {
      return RegExp(pattern);
    } on FormatException {
      // 用户手填的非法正则（"(" / "[a-" / "*foo"）：降级成普通字符串，
      // 交给 evaluate 里 matches 分支的 try/catch 处理。否则反序列化阶段就抛异常，
      // 整条规则会被 loadRules 的逐条容错静默丢弃（用户配的规则凭空消失）。
      return pattern;
    }
  }
  if (value is List) {
    return value.map(_decodeValue).toList();
  }
  if (value is Map) {
    return value.map((k, v) => MapEntry(k, _decodeValue(v)));
  }
  return value;
}

/// MCP 条件规则引擎
/// 支持基于条件的自动化决策和资源管理
/// @author wanghongen
/// 2026-08-12
class McpRuleEngine {
  static final McpRuleEngine _instance = McpRuleEngine._internal();
  factory McpRuleEngine() => _instance;
  McpRuleEngine._internal();

  // 规则列表
  final List<Rule> _rules = [];
  
  // 规则执行历史
  final List<RuleExecutionRecord> _executionHistory = [];
  static const int _maxHistorySize = 50;

  // ==================== 规则管理 ====================

  /// 添加规则
  void addRule(Rule rule) {
    _rules.add(rule);
    logger.i('添加规则：${rule.name} (${rule.id})');
    _sortRules();
  }

  /// 移除规则
  void removeRule(String ruleId) {
    _rules.removeWhere((rule) => rule.id == ruleId);
    logger.d('移除规则：$ruleId');
  }

  /// 启用规则
  void enableRule(String ruleId) {
    final rule = _rules.firstWhere((r) => r.id == ruleId, orElse: () => throw Exception('Rule not found'));
    // 由于规则是不可变的，需要替换
    final index = _rules.indexWhere((r) => r.id == ruleId);
    if (index != -1) {
      _rules[index] = Rule(
        id: rule.id,
        name: rule.name,
        description: rule.description,
        conditions: rule.conditions,
        actions: rule.actions,
        priority: rule.priority,
        enabled: true,
        expiresAt: rule.expiresAt,
      );
    }
  }

  /// 禁用规则
  void disableRule(String ruleId) {
    final index = _rules.indexWhere((r) => r.id == ruleId);
    if (index != -1) {
      final rule = _rules[index];
      _rules[index] = Rule(
        id: rule.id,
        name: rule.name,
        description: rule.description,
        conditions: rule.conditions,
        actions: rule.actions,
        priority: rule.priority,
        enabled: false,
        expiresAt: rule.expiresAt,
      );
    }
  }

  /// 按优先级排序规则
  void _sortRules() {
    _rules.sort((a, b) {
      // 先按启用状态排序
      if (a.isAvailable != b.isAvailable) {
        return a.isAvailable ? -1 : 1;
      }
      // 再按优先级排序
      return b.priority.index - a.priority.index;
    });
  }

  /// 获取所有规则
  List<Rule> getRules() => List.unmodifiable(_rules);

  /// 获取规则列表（只读）
  List<Rule> get rules => List.unmodifiable(_rules);

  /// 清除所有规则
  void clearRules() {
    _rules.clear();
    logger.d('清除所有规则');
  }

  /// 更新规则（整体替换，用于编辑）
  void updateRule(String ruleId, Rule newRule) {
    final index = _rules.indexWhere((r) => r.id == ruleId);
    if (index != -1) {
      _rules[index] = newRule;
      logger.i('更新规则：${newRule.name} ($ruleId)');
      _sortRules();
    }
  }

  /// 持久化规则到 mcp_rules.json
  Future<void> saveRules() async {
    try {
      final file = await Paths.getPath('mcp_rules.json');
      final data = _rules.map((r) => r.toJson()).toList();
      await SerialFileWriter.writeString(file, jsonEncode(data));
    } catch (e, st) {
      logger.e('保存规则失败', error: e, stackTrace: st);
    }
  }

  /// 从 mcp_rules.json 加载规则
  Future<void> loadRules() async {
    try {
      final file = await Paths.getPath('mcp_rules.json');
      if (!await file.exists()) return;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return;
      final decoded = jsonDecode(content);
      if (decoded is! List) {
        logger.w('mcp_rules.json 格式不是数组，忽略');
        return;
      }

      // 逐条解析后再整体替换。旧实现先 clear() 再 map(...)：任意一条坏数据
      // （旧版本写入 / 手工编辑缺 id、name）抛 TypeError 后 addAll 中断，
      // 外层 catch 吞掉 → 内存规则表变空/残缺；用户随后新增一条规则就会
      // 把残缺表写回磁盘，原规则永久丢失。
      final loaded = <Rule>[];
      var skipped = 0;
      for (final item in decoded) {
        if (item is! Map) {
          skipped++;
          continue;
        }
        try {
          loaded.add(Rule.fromJson(Map<String, dynamic>.from(item)));
        } catch (e) {
          skipped++;
          logger.w('跳过无法解析的规则：$e');
        }
      }
      _rules
        ..clear()
        ..addAll(loaded);
      _sortRules();
      logger.i('已加载 ${_rules.length} 条规则${skipped > 0 ? '（跳过 $skipped 条）' : ''}');
    } catch (e, st) {
      logger.e('加载规则失败', error: e, stackTrace: st);
    }
  }

  // ==================== 规则评估 ====================

  /// 评估并执行规则
  Future<void> evaluate(dynamic context) async {
    for (final rule in _rules) {
      if (!rule.isAvailable) continue;

      // 检查所有条件是否匹配
      final allMatched = rule.conditions.every((condition) => condition.evaluate(context));
      
      // 记录执行历史
      _executionHistory.add(RuleExecutionRecord(rule.id, allMatched, allMatched ? 'executed' : 'skipped'));
      if (_executionHistory.length > _maxHistorySize) {
        _executionHistory.removeAt(0);
      }

      if (allMatched) {
        logger.i('规则匹配：${rule.name}');
        
        // 执行所有动作
        for (final action in rule.actions) {
          try {
            await action.execute(context);
          } catch (e, stackTrace) {
            logger.e('规则动作执行失败：${rule.name}', error: e, stackTrace: stackTrace);
          }
        }
        
        // 如果规则是 critical 优先级，执行后停止后续规则评估
        if (rule.priority == RulePriority.critical) {
          break;
        }
      }
    }
  }

  /// 获取执行历史
  List<RuleExecutionRecord> getExecutionHistory({int? limit}) {
    if (limit == null) return List.unmodifiable(_executionHistory);
    final start = _executionHistory.length - limit.clamp(0, _executionHistory.length);
    return _executionHistory.sublist(start);
  }

  // ==================== 便捷评估方法 ====================

  /// 便捷评估代理状态变化
  void evaluateProxyStatus(String status) {
    unawaited(evaluate({
      'type': 'proxyStatus',
      'status': status,
      'timestamp': DateTime.now().toIso8601String(),
    }).catchError((e, s) {
      logger.e('代理状态规则评估失败', error: e, stackTrace: s);
    }));
  }

  /// 便捷评估网络状态变化
  void evaluateNetworkStatus(String status) {
    unawaited(evaluate({
      'type': 'networkStatus',
      'status': status,
      'timestamp': DateTime.now().toIso8601String(),
    }).catchError((e, s) {
      logger.e('网络状态规则评估失败', error: e, stackTrace: s);
    }));
  }

  // ==================== 预定义规则构建器 ====================

  /// 创建 HTTP 请求规则
  static Rule createHttpRequestRule({
    required String id,
    required String name,
    String? urlPattern,
    String? method,
    int? minStatusCode,
    int? maxStatusCode,
    int? minDuration,
    int? maxDuration,
    required List<Action> actions,
    RulePriority priority = RulePriority.normal,
  }) {
    final conditions = <Condition>[];
    
    if (urlPattern != null) {
      conditions.add(Condition(
        type: ConditionType.httpRequest,
        field: 'url',
        operator: Operator.matches,
        value: RegExp(urlPattern),
      ));
    }
    
    if (method != null) {
      conditions.add(Condition(
        type: ConditionType.httpRequest,
        field: 'method',
        operator: Operator.equals,
        value: method,
      ));
    }
    
    if (minStatusCode != null) {
      conditions.add(Condition(
        type: ConditionType.httpRequest,
        field: 'statusCode',
        operator: Operator.greaterThanOrEqual,
        value: minStatusCode,
      ));
    }
    
    if (maxStatusCode != null) {
      conditions.add(Condition(
        type: ConditionType.httpRequest,
        field: 'statusCode',
        operator: Operator.lessThanOrEqual,
        value: maxStatusCode,
      ));
    }
    
    if (minDuration != null) {
      conditions.add(Condition(
        type: ConditionType.httpRequest,
        field: 'duration',
        operator: Operator.greaterThanOrEqual,
        value: minDuration,
      ));
    }
    
    if (maxDuration != null) {
      conditions.add(Condition(
        type: ConditionType.httpRequest,
        field: 'duration',
        operator: Operator.lessThanOrEqual,
        value: maxDuration,
      ));
    }

    return Rule(
      id: id,
      name: name,
      conditions: conditions,
      actions: actions,
      priority: priority,
    );
  }

  /// 创建资源管理规则
  static Rule createResourceManagementRule({
    required String id,
    required String name,
    int? maxMemoryUsage,
    int? maxCaptureCount,
    int? maxFileSize,
    required List<Action> actions,
  }) {
    final conditions = <Condition>[];
    
    if (maxMemoryUsage != null) {
      conditions.add(Condition(
        type: ConditionType.systemStatus,
        field: 'memoryUsage',
        operator: Operator.greaterThan,
        value: maxMemoryUsage,
      ));
    }
    
    if (maxCaptureCount != null) {
      conditions.add(Condition(
        type: ConditionType.systemStatus,
        field: 'captureCount',
        operator: Operator.greaterThan,
        value: maxCaptureCount,
      ));
    }
    
    if (maxFileSize != null) {
      conditions.add(Condition(
        type: ConditionType.systemStatus,
        field: 'diskUsage',
        operator: Operator.greaterThan,
        value: maxFileSize,
      ));
    }

    return Rule(
      id: id,
      name: name,
      conditions: conditions,
      actions: actions,
      priority: RulePriority.high,
    );
  }
}

/// 使用示例
class McpRuleEngineExample {
  /// 示例：自动记录慢请求
  static void setupSlowRequestLogging() {
    final engine = McpRuleEngine();
    
    final rule = McpRuleEngine.createHttpRequestRule(
      id: 'slow_request_log',
      name: '慢请求日志',
      minDuration: 5000, // 超过 5 秒
      actions: [
        Action(
          type: ActionType.log,
          parameters: {'level': 'warning', 'message': '检测到慢请求'},
        ),
      ],
    );
    
    engine.addRule(rule);
  }

  /// 示例：自动导出错误请求
  static void setupErrorExport() {
    final engine = McpRuleEngine();
    
    final rule = McpRuleEngine.createHttpRequestRule(
      id: 'error_export',
      name: '错误请求自动导出',
      minStatusCode: 400,
      actions: [
        Action(
          type: ActionType.exportData,
          parameters: {'format': 'har', 'autoSave': true},
        ),
      ],
    );
    
    engine.addRule(rule);
  }

  /// 示例：内存保护规则
  static void setupMemoryProtection() {
    final engine = McpRuleEngine();
    
    final rule = McpRuleEngine.createResourceManagementRule(
      id: 'memory_protection',
      name: '内存保护',
      maxMemoryUsage: 500, // MB
      actions: [
        Action(
          type: ActionType.log,
          parameters: {'message': '内存使用过高，自动清理缓存'},
        ),
        Action(
          type: ActionType.custom,
          callback: (context, params) async {
            // 调用清理缓存的逻辑
            logger.i('执行内存清理');
          },
        ),
      ],
    );
    
    engine.addRule(rule);
  }

  /// 示例：自动停止大文件下载
  static void setupLargeFileBlock() {
    final engine = McpRuleEngine();
    
    final rule = McpRuleEngine.createHttpRequestRule(
      id: 'large_file_block',
      name: '大文件下载拦截',
      actions: [
        Action(
          type: ActionType.custom,
          callback: (context, params) async {
            if (context is HttpRequest) {
              final size = context.response?.contentLength ?? 0;
              if (size > 100 * 1024 * 1024) { // 100MB
                logger.w('拦截大文件下载：${context.requestUrl}');
              }
            }
          },
        ),
      ],
    );
    
    engine.addRule(rule);
  }
}
