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

// ARTEX（AI 自主渗透测试系统，Go 后端 + Next.js 前端）的轻量客户端。
//
// 为什么不内置 WebView：ARTEX 的控制台是完整的 Next.js 应用，要跑 JS + 大量
// 路由，塞进 Flutter 需要一个 webview 依赖（这个仓库刻意不引，Windows/Linux
// 还得额外原生实现）。所以这里只做「能连上、能看状态、能看任务、能一键跳过去」，
// 真正的交互仍然交给系统浏览器 —— 和 ARTEX 官方安卓套壳（com.artex.app）的定位
// 一致，只是把「套壳 WebView」换成了「系统浏览器 + token 直链」。
//
// 接口（对着 ARTEX v0.3.x 的 server/server.go 核对过）：
//   GET  /api/health          → {"ok":true,"service":"artex","version":"..."}   免鉴权
//   GET  /api/stats           → {"engine_mode":...,"llm_configured":...,...}    需鉴权
//   POST /api/auth/login      → {"token":"..."}   (用户名固定 "ARTEX")
//   GET  /api/auth/status     → {"initialized":bool}                            免鉴权
//   GET  /api/tasks           → {"tasks":[...],"active":"..."}                  需鉴权
//
// 鉴权：`Authorization: Bearer <jwt>`；SSE/直链也支持 `?token=`，所以「用浏览器
// 打开」可以直接把 token 拼进 URL，用户不用再登一次。

import 'dart:convert';
import 'dart:io';

/// 连接到的 ARTEX 实例的概况。
class ArtexHealth {
  final bool ok;
  final String version;
  final int ms;

  const ArtexHealth({required this.ok, required this.version, required this.ms});
}

/// /api/tasks 里的一条任务（只取界面上要用的字段）。
class ArtexTask {
  final String id;
  final String name;
  final String status;
  final String goal;
  final int goalsTotal;
  final int goalsMet;
  final int findingsCritical;
  final int findingsHigh;
  final int lastActivityUnix;

  const ArtexTask({
    required this.id,
    required this.name,
    required this.status,
    required this.goal,
    required this.goalsTotal,
    required this.goalsMet,
    required this.findingsCritical,
    required this.findingsHigh,
    required this.lastActivityUnix,
  });

  factory ArtexTask.fromJson(Map<String, dynamic> m) {
    int asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('${v ?? ''}') ?? 0;
    }

    final f = m['findings'];
    final findings = f is Map ? Map<String, dynamic>.from(f) : const <String, dynamic>{};
    return ArtexTask(
      id: '${m['id'] ?? ''}',
      name: '${m['name'] ?? ''}',
      status: '${m['status'] ?? 'created'}',
      goal: '${m['goal'] ?? m['description'] ?? ''}',
      goalsTotal: asInt(m['goals_total']),
      goalsMet: asInt(m['goals_met']),
      findingsCritical: asInt(findings['critical']),
      findingsHigh: asInt(findings['high']),
      lastActivityUnix: asInt(m['last_activity_unix']),
    );
  }

  String get displayName => name.isEmpty ? id : name;
}

/// 一次请求的失败原因（给界面直接显示，不要抛裸异常文本）。
class ArtexException implements Exception {
  final String message;
  const ArtexException(this.message);

  @override
  String toString() => message;
}

class ArtexClient {
  /// 规范化后的服务基址（不含结尾斜杠）。
  final String baseUrl;

  /// 登录后拿到的 JWT（内存里放着，持久化由页面决定）。
  String? token;

  ArtexClient(String baseUrl, {this.token}) : baseUrl = _normalize(baseUrl);

  /// 用户可能只填了 `192.168.1.10:8787`，补成 http://；去掉结尾斜杠。
  static String _normalize(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('$baseUrl$path');
    return query == null ? u : u.replace(queryParameters: {...u.queryParameters, ...query});
  }

  /// 用浏览器打开控制台的地址：带上 token 省一次登录。
  String consoleUrl() {
    final t = token;
    if (t == null || t.isEmpty) return baseUrl;
    return '$baseUrl/?token=${Uri.encodeQueryComponent(t)}';
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  /// 发一个请求并把 JSON 解出来。非 2xx 时尽量用服务端给的 message。
  Future<dynamic> _send(String method, Uri uri, {Object? body}) async {
    if (baseUrl.isEmpty) throw const ArtexException('请先填服务端地址');
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      // 自签证书 / 内网 IP 常见，这里不阻断（用户连的是自己的实例）。
      client.badCertificateCallback = (cert, host, port) => true;
      final req = await client.openUrl(method, uri).timeout(const Duration(seconds: 10));
      _headers.forEach(req.headers.set);
      if (body != null) {
        final data = utf8.encode(jsonEncode(body));
        req.headers.contentType = ContentType.json;
        req.headers.contentLength = data.length;
        req.add(data);
      }
      final resp = await req.close().timeout(const Duration(seconds: 20));
      final raw = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        String msg = 'HTTP ${resp.statusCode}';
        try {
          final m = jsonDecode(raw);
          if (m is Map && m['message'] != null) msg = '${m['message']}';
          if (m is Map && m['error'] != null) msg = '${m['error']}';
        } catch (_) {
          if (raw.trim().isNotEmpty && raw.length < 200) msg = raw.trim();
        }
        throw ArtexException(msg);
      }
      if (raw.trim().isEmpty) return null;
      return jsonDecode(raw);
    } on ArtexException {
      rethrow;
    } on SocketException catch (e) {
      throw ArtexException('连不上：${e.osError?.message ?? e.message}');
    } catch (e) {
      throw ArtexException('$e');
    } finally {
      client?.close(force: true);
    }
  }

  /// 连通性 + 版本（这个接口免鉴权，所以未登录也能先测通不通）。
  Future<ArtexHealth> health() async {
    final started = DateTime.now();
    final data = await _send('GET', _uri('/api/health'));
    final ms = DateTime.now().difference(started).inMilliseconds;
    final m = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
    return ArtexHealth(ok: m['ok'] == true, version: '${m['version'] ?? ''}', ms: ms);
  }

  /// 登录：用户名在 ARTEX 里是固定的 "ARTEX"，只需要密码。
  Future<String> login(String password) async {
    final data = await _send('POST', _uri('/api/auth/login'), body: {
      'username': 'ARTEX',
      'password': password,
    });
    final m = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
    final t = '${m['token'] ?? ''}';
    if (t.isEmpty) throw const ArtexException('登录成功但没拿到 token');
    token = t;
    return t;
  }

  /// 是否已经初始化过密码（新实例要先在网页端设密码）。
  Future<bool> authInitialized() async {
    final data = await _send('GET', _uri('/api/auth/status'));
    final m = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
    return m['initialized'] == true;
  }

  Future<Map<String, dynamic>> stats() async {
    final data = await _send('GET', _uri('/api/stats'));
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<({List<ArtexTask> tasks, String active})> tasks() async {
    final data = await _send('GET', _uri('/api/tasks'));
    final m = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final list = m['tasks'];
    final out = <ArtexTask>[];
    if (list is List) {
      for (final e in list) {
        if (e is Map) out.add(ArtexTask.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return (tasks: out, active: '${m['active'] ?? ''}');
  }
}
