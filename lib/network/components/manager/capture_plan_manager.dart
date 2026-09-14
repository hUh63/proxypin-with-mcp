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
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/path.dart';

/// 采集方案（借鉴 proxypin-mcp-workbench 的 Capture Plan 思路）。
///
/// 把「一次抓包任务」沉淀成可复用模板：一组包含 / 排除域名规则，
/// 加一份人工操作步骤清单。方案只描述「抓什么、怎么抓」——
/// 它不会自动操作目标 App、重放接口或改写线上数据，
/// 只是把「过滤用哪些域名」交给用户一键应用到域名过滤器，
/// 保持调试代理的中立定位。
class CapturePlanStep {
  final String id;
  final String title;
  final String description;

  const CapturePlanStep({required this.id, required this.title, required this.description});

  factory CapturePlanStep.fromJson(Map<String, dynamic> json) => CapturePlanStep(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'description': description};

  CapturePlanStep copyWith({String? id, String? title, String? description}) => CapturePlanStep(
        id: id ?? this.id,
        title: title ?? this.title,
        description: description ?? this.description,
      );
}

class CapturePlan {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String id;
  final String name;
  final String appName;
  final String description;
  final bool enabled;
  final bool builtIn;
  final List<String> includeDomains;
  final List<String> excludeDomains;
  final List<CapturePlanStep> steps;

  const CapturePlan({
    this.schemaVersion = currentSchemaVersion,
    required this.id,
    required this.name,
    this.appName = '',
    this.description = '',
    this.enabled = true,
    this.builtIn = false,
    this.includeDomains = const [],
    this.excludeDomains = const [],
    this.steps = const [],
  });

  factory CapturePlan.fromJson(Map<String, dynamic> json) => CapturePlan(
        schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        appName: json['appName']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        enabled: json['enabled'] != false,
        builtIn: json['builtIn'] == true,
        includeDomains: _domainList(json['includeDomains']),
        excludeDomains: _domainList(json['excludeDomains']),
        steps: (json['steps'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => CapturePlanStep.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
      );

  CapturePlan copyWith({
    String? name,
    String? appName,
    String? description,
    bool? enabled,
    List<String>? includeDomains,
    List<String>? excludeDomains,
    List<CapturePlanStep>? steps,
  }) =>
      CapturePlan(
        schemaVersion: schemaVersion,
        id: id,
        name: name ?? this.name,
        appName: appName ?? this.appName,
        description: description ?? this.description,
        enabled: enabled ?? this.enabled,
        builtIn: builtIn,
        includeDomains: includeDomains ?? this.includeDomains,
        excludeDomains: excludeDomains ?? this.excludeDomains,
        steps: steps ?? this.steps,
      );

  /// 该主机是否落在本方案的包含域名内（且未被排除域名命中）。
  bool matchesHost(String host) => CaptureDomainMatcher.matches(
        host,
        includeDomains: includeDomains,
        excludeDomains: excludeDomains,
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'appName': appName,
        'description': description,
        'enabled': enabled,
        'builtIn': builtIn,
        'includeDomains': [...includeDomains]..sort(),
        'excludeDomains': [...excludeDomains]..sort(),
        'steps': steps.map((step) => step.toJson()).toList(growable: false),
      };

  static List<String> _domainList(dynamic value) => (value as List? ?? const [])
      .map((item) => CaptureDomainMatcher.normalizePattern(item.toString()))
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
}

/// 域名规则匹配：支持 `example.com`（精确）与 `*.example.com`（子域通配）。
class CaptureDomainMatcher {
  const CaptureDomainMatcher._();

  static String normalizePattern(String value) {
    var normalized = value.trim().toLowerCase();
    while (normalized.endsWith('.')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static bool isValidPattern(String value) {
    final normalized = normalizePattern(value);
    if (normalized.isEmpty || normalized.contains(RegExp(r'[/\\\s:?#\[\]]'))) return false;
    final host = normalized.startsWith('*.') ? normalized.substring(2) : normalized;
    if (host.isEmpty || host.startsWith('.') || host.endsWith('.') || host.contains('..')) return false;
    return RegExp(r'^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$').hasMatch(host);
  }

  /// 把规则转换成域名过滤器接受的写法。`*` 由 [HostList.add] 统一展开为正则 `.*`，
  /// 因此这里保持原样，与「域名过滤 - 导入」的既有行为一致。
  static String toHostPattern(String value) => normalizePattern(value);

  static bool matches(
    String host, {
    required Iterable<String> includeDomains,
    Iterable<String> excludeDomains = const [],
  }) {
    final normalizedHost = normalizePattern(host);
    if (normalizedHost.isEmpty) return false;
    final includes = includeDomains.map(normalizePattern).where(isValidPattern).toList(growable: false);
    if (includes.isEmpty || !includes.any((pattern) => _matchesPattern(normalizedHost, pattern))) return false;
    final excludes = excludeDomains.map(normalizePattern).where(isValidPattern);
    return !excludes.any((pattern) => _matchesPattern(normalizedHost, pattern));
  }

  static bool _matchesPattern(String host, String pattern) {
    if (!pattern.startsWith('*.')) return host == pattern;
    final suffix = pattern.substring(2);
    return host == suffix || host.endsWith('.$suffix');
  }
}

/// 内置采集方案：开箱即用的任务模板（不含具体业务域名，由用户自行补充）。
class BuiltInCapturePlans {
  const BuiltInCapturePlans._();

  static const mobileTroubleshoot = CapturePlan(
    id: 'builtin.mobile-app-troubleshoot',
    name: '移动端 App 抓包排查',
    appName: '任意移动 App',
    description: '从零确认代理连通性，再定位目标 App 的请求，适合首次对某个 App 抓包或排查加载异常。',
    builtIn: true,
    steps: [
      CapturePlanStep(
        id: 'connect',
        title: '确认手机已连上代理',
        description: '把手机 Wi-Fi 代理指向本机局域网地址与抓包端口，确认能看到其他 App 的请求。',
      ),
      CapturePlanStep(
        id: 'ca',
        title: '信任根证书',
        description: '在手机上安装并完全信任 ProxyPin 根证书，否则 HTTPS 正文只能看到密文。',
      ),
      CapturePlanStep(
        id: 'target',
        title: '只留目标 App',
        description: '关闭其他应用的后台活动，或用「应用筛选」只保留目标 App，减少无关请求干扰。',
      ),
      CapturePlanStep(
        id: 'reproduce',
        title: '复现并核对',
        description: '在目标 App 里复现操作，回到请求列表核对接口、状态码与响应内容。',
      ),
    ],
  );

  static const apiReview = CapturePlan(
    id: 'builtin.api-review',
    name: '接口清单梳理',
    appName: '任意客户端',
    description: '把一个功能的全部请求抓齐，整理成接口清单，适合做接口梳理与联调核对。',
    builtIn: true,
    steps: [
      CapturePlanStep(
        id: 'scope',
        title: '圈定域名范围',
        description: '在方案里填入目标业务域名，一键应用到域名过滤器，只保留相关请求。',
      ),
      CapturePlanStep(
        id: 'collect',
        title: '走完整个功能流程',
        description: '在客户端里把目标功能的每个步骤都操作一遍，确保接口尽量抓全。',
      ),
      CapturePlanStep(
        id: 'catalog',
        title: '导出接口清单',
        description: '打开「API 端点」工具，从抓包数据提取端点，可导出 OpenAPI / Postman / JSON。',
      ),
    ],
  );

  static const values = [mobileTroubleshoot, apiReview];
}

/// 采集方案管理器（本地 JSON 持久化）。
class CapturePlanManager extends ChangeNotifier {
  static const String _fileName = 'capture_plans.json';
  static CapturePlanManager? _instance;

  final List<CapturePlan> _plans = [];

  static Future<CapturePlanManager> get instance async {
    if (_instance == null) {
      final manager = CapturePlanManager._internal();
      await manager._load();
      _instance = manager;
    }
    return _instance!;
  }

  CapturePlanManager._internal();

  List<CapturePlan> get plans => List.unmodifiable(_plans);

  Future<void> _load() async {
    _plans.clear();
    try {
      final file = await Paths.getPath(_fileName);
      final content = await file.readAsString();
      if (content.trim().isNotEmpty) {
        final decoded = jsonDecode(content);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final plan = CapturePlan.fromJson(Map<String, dynamic>.from(item));
              if (plan.id.isNotEmpty) {
                _plans.add(plan);
              }
            }
          }
        }
      }
    } catch (e) {
      logger.e('采集方案解析失败', error: e);
    }

    // 内置方案：文件里已有同 id 的条目时以文件为准（保留用户的启用开关与域名补充），
    // 仅当缺失时才补入。
    for (final builtin in BuiltInCapturePlans.values) {
      if (!_plans.any((plan) => plan.id == builtin.id)) {
        _plans.insert(0, builtin);
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final file = await Paths.getPath(_fileName);
      await file.writeAsString(jsonEncode(_plans.map((plan) => plan.toJson()).toList(growable: false)));
    } catch (e) {
      logger.e('采集方案保存失败', error: e);
    }
  }

  Future<CapturePlan> add(CapturePlan plan) async {
    _plans.add(plan);
    await _save();
    notifyListeners();
    return plan;
  }

  Future<void> update(CapturePlan plan) async {
    final index = _plans.indexWhere((item) => item.id == plan.id);
    if (index < 0) {
      _plans.add(plan);
    } else {
      _plans[index] = plan;
    }
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _plans.removeWhere((plan) => plan.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final index = _plans.indexWhere((plan) => plan.id == id);
    if (index < 0) return;
    _plans[index] = _plans[index].copyWith(enabled: enabled);
    await _save();
    notifyListeners();
  }

  CapturePlan? byId(String id) {
    for (final plan in _plans) {
      if (plan.id == id) return plan;
    }
    return null;
  }

  /// 把方案的域名规则写入域名过滤器并持久化。
  ///
  /// 包含域名 → 白名单（并启用）；排除域名 → 黑名单（并启用）。
  /// 白名单非空时不在白名单内的请求都会被过滤，因此这是「只抓目标域名」的语义。
  static Future<void> applyToFilter(CapturePlan plan, {Configuration? configuration}) async {
    final whitelist = HostFilter.whitelist;
    final blacklist = HostFilter.blacklist;
    for (final domain in plan.includeDomains) {
      whitelist.add(CaptureDomainMatcher.toHostPattern(domain));
    }
    for (final domain in plan.excludeDomains) {
      blacklist.add(CaptureDomainMatcher.toHostPattern(domain));
    }
    if (plan.includeDomains.isNotEmpty) {
      whitelist.enabled = true;
    }
    if (plan.excludeDomains.isNotEmpty) {
      blacklist.enabled = true;
    }
    try {
      final config = configuration ?? await Configuration.instance;
      await config.flushConfig();
    } catch (e) {
      logger.e('应用采集方案失败', error: e);
    }
  }
}
