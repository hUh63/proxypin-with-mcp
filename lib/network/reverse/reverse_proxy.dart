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

import 'package:flutter/foundation.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/attribute_keys.dart';
import 'package:proxypin/network/util/random.dart';
import 'package:proxypin/network/util/logger.dart';

/// 一条反向代理路由规则：把某个路径前缀的请求转发到指定上游。
///
/// 与正向代理的区别：客户端不再指定目标，目标由这里按路径决定。适合本地调试
/// 前端调用（把 `api.example.com` 指到 `127.0.0.1:3000` 而不改代码）、给不同
/// 微服务挂不同上游、或者把线上流量引到本地。
class ReverseProxyRule {
  final String id;

  /// 匹配的路径前缀，始终以 `/` 开头。`/` 表示兜底（匹配所有路径）。
  final String prefix;

  /// 上游地址，形如 `http://127.0.0.1:3000` 或 `https://api.example.com`。
  final String target;

  /// 转发时是否去掉 [prefix]。例如前缀 `/api` + 去前缀，则 `/api/users` → `/users`。
  final bool stripPrefix;

  /// 转发时覆盖的 Host 头；留空则用上游自身的 host。
  final String? hostHeader;

  /// 附加到转发请求上的 header（同名覆盖）。
  final Map<String, String> headers;

  final bool enabled;

  const ReverseProxyRule({
    required this.id,
    required this.prefix,
    required this.target,
    this.stripPrefix = false,
    this.hostHeader,
    this.headers = const {},
    this.enabled = true,
  });

  ReverseProxyRule copyWith({
    String? prefix,
    String? target,
    bool? stripPrefix,
    String? hostHeader,
    bool clearHostHeader = false,
    Map<String, String>? headers,
    bool? enabled,
  }) {
    return ReverseProxyRule(
      id: id,
      prefix: prefix ?? this.prefix,
      target: target ?? this.target,
      stripPrefix: stripPrefix ?? this.stripPrefix,
      hostHeader: clearHostHeader ? null : (hostHeader ?? this.hostHeader),
      headers: headers ?? this.headers,
      enabled: enabled ?? this.enabled,
    );
  }

  /// 规范化前缀：保证以 `/` 开头，去掉尾部多余的 `/`（根路径除外）。
  static String normalizePrefix(String value) {
    var p = value.trim();
    if (p.isEmpty) return '/';
    if (!p.startsWith('/')) p = '/$p';
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  bool get isValid {
    if (target.trim().isEmpty) return false;
    final uri = Uri.tryParse(target.trim());
    return uri != null && uri.host.isNotEmpty;
  }

  /// 上游连接目标。
  HostAndPort? get upstream {
    final uri = Uri.tryParse(target.trim());
    if (uri == null || uri.host.isEmpty) return null;
    final scheme = uri.scheme.isEmpty ? HostAndPort.httpScheme : '${uri.scheme}://';
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    return HostAndPort(scheme, uri.host, port);
  }

  /// 路径是否命中本规则（按前缀，且要求落在路径分段边界上）。
  bool matchPath(String path) {
    if (!enabled || !isValid) return false;
    final p = normalizePrefix(prefix);
    if (p == '/') return true;
    if (!path.startsWith(p)) return false;
    // `/api` 不应命中 `/apixyz`
    final rest = path.substring(p.length);
    return rest.isEmpty || rest.startsWith('/') || rest.startsWith('?');
  }

  /// 按 [stripPrefix] 改写路径；前缀被剥离后若为空则回退成 `/`。
  String rewritePath(String path) {
    final p = normalizePrefix(prefix);
    if (!stripPrefix || p == '/') return path.isEmpty ? '/' : path;
    if (!path.startsWith(p)) return path.isEmpty ? '/' : path;
    final rest = path.substring(p.length);
    if (rest.isEmpty) return '/';
    return rest.startsWith('/') ? rest : '/$rest';
  }

  static String _generateId() =>
      DateTime.now().millisecondsSinceEpoch.toRadixString(36) + RandomUtil.randomString(4);

  /// 命中优先级：前缀越长越精确。
  int get weight => normalizePrefix(prefix).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'prefix': prefix,
        'target': target,
        if (stripPrefix) 'stripPrefix': true,
        if (hostHeader != null && hostHeader!.isNotEmpty) 'hostHeader': hostHeader,
        if (headers.isNotEmpty) 'headers': headers,
        'enabled': enabled,
      };

  factory ReverseProxyRule.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'];
    return ReverseProxyRule(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? (json['id'] as String).trim()
          : _generateId(),
      prefix: normalizePrefix(json['prefix'] as String? ?? '/'),
      target: (json['target'] as String? ?? '').trim(),
      stripPrefix: json['stripPrefix'] == true,
      hostHeader: (json['hostHeader'] as String?)?.trim(),
      headers: rawHeaders is Map
          ? rawHeaders.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReverseProxyRule && other.id == id && other.prefix == prefix && other.target == target;

  @override
  int get hashCode => Object.hash(id, prefix, target);
}

/// 反向代理：按路径把请求转发到不同上游，复用抓包/改写/断点/脚本处理链。
///
/// 实现方式是**只改写请求目标**（`HttpRequest.hostAndPort` 与 uri），之后完全走
/// 现有的正向代理转发路径，因此反代进来的流量同样会出现在抓包列表里，也能被
/// Map Local、断点、脚本这些规则命中。
class ReverseProxy {
  ReverseProxy._();

  /// 总开关。
  static bool enabled = false;

  /// 监听端口（与正向代理端口互相独立）。
  static int port = 8888;

  static List<ReverseProxyRule> _rules = const [];

  static List<ReverseProxyRule> get rules => List.unmodifiable(_rules);

  /// 命中统计（key = 规则 id），仅本次运行。
  static final Map<String, int> hitCounts = {};

  static void load({required bool enabled, required int port, required List<ReverseProxyRule> rules}) {
    ReverseProxy.enabled = enabled;
    ReverseProxy.port = port;
    _rules = List.unmodifiable(rules.where((r) => r.isValid));
  }

  static bool get hasRules => _rules.isNotEmpty;

  static int hitsOf(ReverseProxyRule rule) => hitCounts[rule.id] ?? 0;

  static void resetHits() {
    hitCounts.clear();
    logger.d('反向代理命中统计已重置');
  }

  /// 按「最长前缀优先」查找匹配规则。
  static ReverseProxyRule? match(String path) {
    if (!enabled || _rules.isEmpty) return null;
    ReverseProxyRule? best;
    for (final rule in _rules) {
      if (!rule.matchPath(path)) continue;
      if (best == null || rule.weight > best.weight) best = rule;
    }
    return best;
  }

  /// 改写请求目标。
  ///
  /// 命中返回 true（调用方继续走正常转发），未命中返回 false（调用方应回 502）。
  static bool rewrite(ChannelContext channelContext, HttpRequest request) {
    final rule = match(request.path);
    if (rule == null) return false;

    final upstream = rule.upstream;
    if (upstream == null) return false;

    final upstreamUri = Uri.tryParse(rule.target.trim());
    if (upstreamUri == null) return false;

    // 1. 路径：可选剥离前缀，再拼上上游自带的 base path
    final basePath = upstreamUri.path.isEmpty || upstreamUri.path == '/' ? '' : upstreamUri.path;
    final newPath = '${basePath}${rule.rewritePath(request.path)}';
    final query = request.requestUri?.hasQuery == true ? request.requestUri!.query : null;
    request.uri = query == null || query.isEmpty ? newPath : '$newPath?$query';

    // 2. 目标：换成上游的 host:port（scheme 决定后续是否 TLS）
    request.hostAndPort = upstream;

    // 3. Host 头：默认用上游 host（含端口），也可显式指定
    final hostValue = rule.hostHeader?.isNotEmpty == true
        ? rule.hostHeader!
        : '${upstreamUri.host}${upstreamUri.hasPort ? ':${upstreamUri.port}' : ''}';
    request.headers.set('host', hostValue);

    // 4. 附加 header
    rule.headers.forEach((name, value) {
      if (name.trim().isNotEmpty) request.headers.set(name.trim(), value);
    });

    // 5. 标记，便于 UI / 排查识别这是反代转发
    request.headers.set('X-ProxyPin-Reverse-Proxy', rule.id);
    channelContext.putAttribute(AttributeKeys.reverseProxyRule, rule.id);

    hitCounts[rule.id] = (hitCounts[rule.id] ?? 0) + 1;
    logger.d('[ReverseProxy] ${request.methodLabel} ${request.path} -> ${rule.target}');
    return true;
  }

  static List<Map<String, dynamic>> toJson() => _rules.map((r) => r.toJson()).toList(growable: false);

  static List<ReverseProxyRule> parseRules(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => ReverseProxyRule.fromJson(Map<String, dynamic>.from(e)))
        .where((r) => r.isValid)
        .toList(growable: false);
  }

  /// 默认规则示例（UI 里「新建」时用作占位，不写入配置）。
  @visibleForTesting
  static ReverseProxyRule sample() => const ReverseProxyRule(
        id: 'sample',
        prefix: '/api',
        target: 'http://127.0.0.1:3000',
      );
}
