import 'dart:convert';
import 'dart:io';

import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/storage/path.dart';
import 'package:proxypin/network/util/logger.dart';

class RequestBreakpointRule {
  bool enabled;
  String? name;
  String url;

  bool interceptRequest;
  bool interceptResponse;

  // Optional HTTP method matching; null means match any method
  HttpMethod? method;

  RequestBreakpointRule({
    this.enabled = true,
    this.name,
    required this.url,
    this.interceptRequest = true,
    this.interceptResponse = true,
    this.method,
  });

  // 已编译正则缓存，避免每个请求都重新编译（match 在请求热路径上）
  RegExp? _urlReg;

  bool match(String url, {HttpMethod? method}) {
    if (!enabled) return false;
    if (this.method != null && method != null && this.method != method)
      return false;
    return (_urlReg ??= RegExp(this.url)).hasMatch(url);
  }

  factory RequestBreakpointRule.fromJson(Map<dynamic, dynamic> map) {
    HttpMethod? method;
    try {
      if (map['method'] != null) {
        final parsed = HttpMethod.valueOf(map['method']);
        // 非法方法名降级为「不按方法过滤」。HttpMethod.valueOf 现在返回
        // HttpMethod.unknown 而不是抛异常，这里必须显式转 null——否则
        // unknown 会当成一个真实方法，把所有自定义方法请求都拦下来。
        method = parsed == HttpMethod.unknown ? null : parsed;
      }
    } catch (e) {
      logger.e(
        'Failed to parse HTTP method from request intercept rule',
        error: e,
      );
    }

    return RequestBreakpointRule(
      enabled: map['enabled'] ?? true,
      name: map['name'],
      url: map['url'] ?? '',
      interceptRequest: map['interceptRequest'] ?? true,
      interceptResponse: map['interceptResponse'] ?? true,
      method: method,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'name': name,
      'url': url,
      'interceptRequest': interceptRequest,
      'interceptResponse': interceptResponse,
      'method': method?.name,
    };
  }
}

class RequestBreakpointManager {
  static RequestBreakpointManager? _instance;

  RequestBreakpointManager._();

  static Future<RequestBreakpointManager> get instance async {
    if (_instance == null) {
      _instance = RequestBreakpointManager._();
      await _instance!.load();
    }
    return _instance!;
  }

  bool enabled = true;
  List<RequestBreakpointRule> list = [];

  Future<void> load() async {
    try {
      var home = await Paths.homePath();
      var file = File('$home${Platform.pathSeparator}request_breakpoint.json');
      if (await file.exists()) {
        var json = jsonDecode(await file.readAsString());
        enabled = json['enabled'] ?? false;
        list = (json['list'] as List? ?? [])
            .map((e) => RequestBreakpointRule.fromJson(e))
            .toList();
      }
    } catch (e) {
      logger.e('Failed to load request breakpoint config', error: e);
    }
  }

  Future<void> save() async {
    try {
      var home = await Paths.homePath();
      var file = File('$home${Platform.pathSeparator}request_breakpoint.json');
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      var json = {
        'enabled': enabled,
        'list': list.map((e) => e.toJson()).toList(),
      };
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      logger.e('Failed to save request breakpoint config', error: e);
    }
  }

  void add(RequestBreakpointRule rule) {
    list.add(rule);
    save();
  }

  void remove(RequestBreakpointRule rule) {
    list.remove(rule);
    save();
  }
}
