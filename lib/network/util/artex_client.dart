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

// ARTEX 客户端（headless 渗透工具箱的完整 REST 封装）。
//
// ARTEX 本身是跑在 Termux 原生环境里的 Go 服务（:8787 API，:8788 抓包代理），
// web UI 已弃用、内置 LLM 引擎常驻 idle —— 也就是说它只是个「任务容器 + 存储 +
// 工具池」，真正的决策由人（本页手动操作）或 AI（MCP 工具）来做。
//
// 所以这里的定位是**客户端**：把 15 个能力全部映射成可点/可调的界面，而不是
// 只做一个「打开浏览器」。字段名各版本略有差异，解析一律走宽松取值 + 保留原始
// JSON（详情页直接看 raw），这样服务端字段变了页面也不会白屏。
//
// 端点（对着 SKILL.md 的记录 + 实测接口）：
//   GET  /api/health                         免鉴权
//   GET  /api/auth/status                    {"initialized":bool}
//   POST /api/auth/login                     {"token":"..."}（用户名固定 ARTEX）
//   GET  /api/stats
//   GET  /api/tasks?status=&limit=           {"tasks":[...],"active":"..."}
//   POST /api/tasks                          {description,goal,name}
//   GET  /api/tasks/{id}
//   POST /api/tasks/{id}/control             {action:"pause"|"resume"}
//   POST /api/tasks/{id}/goals               {goal}
//   GET  /api/findings?task_id=&limit=
//   GET  /api/findings/{id}
//   GET  /api/logs?limit=
//   GET  /api/llm/status
//   GET  /api/tasks/{id}/workspace
//   GET  /api/tasks/{id}/workspace/file?path=
//   GET  /api/tools        （内置 71 + webpt 10）
//   GET  /api/tools/custom
//   POST /api/tools/custom/test              {tool_key, params}（绕开 engine 直跑）
//
// 本机回环（ARTEX_TRUST_LOOPBACK=1）免 token，所以空 token 也照常发请求。

import 'dart:convert';
import 'dart:io';

/// 一次请求的失败原因（给界面直接显示，不要抛裸异常文本）。
class ArtexException implements Exception {
  final String message;
  const ArtexException(this.message);

  @override
  String toString() => message;
}

Map<String, dynamic> artexMap(Object? v) {
  if (v is Map) {
    return v.map((key, value) => MapEntry('$key', value));
  }
  return const <String, dynamic>{};
}

int artexInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is bool) return v ? 1 : 0;
  return int.tryParse('${v ?? ''}') ?? fallback;
}

String artexText(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  return '$v';
}

/// 若干候选键里取第一个非空的文本。
String artexFirstText(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = artexText(m[k]);
    if (v.isNotEmpty) return v;
  }
  return '';
}

int artexFirstInt(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    if (m[k] != null) return artexInt(m[k]);
  }
  return 0;
}

/// /api/health 的结果。
class ArtexHealth {
  final bool ok;
  final String service;
  final String version;
  final int ms;

  const ArtexHealth({
    required this.ok,
    required this.service,
    required this.version,
    required this.ms,
  });
}

/// 任务（列表与详情共用，详情多带 description/goals/scope）。
class ArtexTask {
  final String id;
  final String name;
  final String status;
  final String description;
  final String goal;
  final List<String> goals;
  final int goalsMet;
  final int findingsCritical;
  final int findingsHigh;
  final int findingsTotal;
  final int lastActivityUnix;
  final Map<String, dynamic> raw;

  const ArtexTask({
    required this.id,
    required this.name,
    required this.status,
    required this.description,
    required this.goal,
    required this.goals,
    required this.goalsMet,
    required this.findingsCritical,
    required this.findingsHigh,
    required this.findingsTotal,
    required this.lastActivityUnix,
    required this.raw,
  });

  factory ArtexTask.fromJson(Map<String, dynamic> m) {
    final findings = artexMap(m['findings'] ?? m['finding_counts']);
    final goalsRaw = m['goals'];
    final goals = <String>[];
    if (goalsRaw is List) {
      for (final g in goalsRaw) {
        if (g is String) {
          goals.add(g);
        } else if (g is Map) {
          final t = artexFirstText(artexMap(g), const ['goal', 'text', 'title', 'desc']);
          if (t.isNotEmpty) goals.add(t);
        }
      }
    }
    final goal = artexFirstText(m, const ['goal', 'objective', 'target']);
    return ArtexTask(
      id: artexFirstText(m, const ['id', 'task_id', 'uuid']),
      name: artexFirstText(m, const ['name', 'title']),
      status: artexFirstText(m, const ['status', 'state']).ifEmpty('created'),
      description: artexFirstText(m, const ['description', 'intent', 'brief']),
      goal: goal,
      goals: goals,
      goalsMet: artexFirstInt(m, const ['goals_met', 'met_goals', 'goals_done']),
      findingsCritical: artexFirstInt(findings, const ['critical']),
      findingsHigh: artexFirstInt(findings, const ['high']),
      findingsTotal: artexFirstInt(findings, const ['total']) == 0
          ? artexFirstInt(m, const ['findings_total', 'finding_count'])
          : artexFirstInt(findings, const ['total']),
      lastActivityUnix: artexFirstInt(m, const ['last_activity_unix', 'updated_unix', 'updated_at']),
      raw: m,
    );
  }

  String get displayName => name.isEmpty ? id : name;

  bool get isRunning => status == 'running' || status == 'active' || status == 'executing';

  bool get isPaused => status == 'paused' || status == 'suspended';
}

/// 一条发现（findings）。
class ArtexFinding {
  final String id;
  final String taskId;
  final String title;
  final String severity;
  final String createdAt;
  final Map<String, dynamic> raw;

  const ArtexFinding({
    required this.id,
    required this.taskId,
    required this.title,
    required this.severity,
    required this.createdAt,
    required this.raw,
  });

  factory ArtexFinding.fromJson(Map<String, dynamic> m) {
    final sev = artexFirstText(m, const ['severity', 'risk', 'level']).toLowerCase();
    return ArtexFinding(
      id: artexFirstText(m, const ['id', 'finding_id']),
      taskId: artexFirstText(m, const ['task_id', 'task']),
      title: artexFirstText(m, const ['title', 'name', 'summary', 'description']),
      severity: sev.isEmpty ? 'info' : sev,
      createdAt: artexFirstText(m, const ['created_at', 'created', 'time', 'ts']),
      raw: m,
    );
  }
}

/// 引擎日志一行。
class ArtexLogLine {
  final String text;
  final String level;
  final String time;

  const ArtexLogLine({required this.text, required this.level, required this.time});

  factory ArtexLogLine.fromJson(Object? v) {
    if (v is String) return ArtexLogLine(text: v, level: '', time: '');
    final m = artexMap(v);
    final text = artexFirstText(m, const ['msg', 'message', 'line', 'text', 'log']);
    final level = artexFirstText(m, const ['level', 'lvl']);
    final time = artexFirstText(m, const ['time', 'ts', 'timestamp', 'at']);
    if (text.isEmpty && m.isNotEmpty) {
      return ArtexLogLine(text: jsonEncode(m), level: level, time: time);
    }
    return ArtexLogLine(text: text, level: level, time: time);
  }
}

/// tool pool 里的一条工具。
class ArtexTool {
  final String key;
  final String name;
  final String description;
  final String kind;
  final Map<String, dynamic> params;
  final Map<String, dynamic> raw;

  const ArtexTool({
    required this.key,
    required this.name,
    required this.description,
    required this.kind,
    required this.params,
    required this.raw,
  });

  factory ArtexTool.fromJson(Map<String, dynamic> m) {
    final key = artexFirstText(m, const ['tool_key', 'key', 'id', 'name']);
    final params = artexMap(m['params'] ?? m['parameters'] ?? m['args']);
    return ArtexTool(
      key: key,
      name: artexFirstText(m, const ['title', 'name', 'label']).ifEmpty(key),
      description: artexFirstText(m, const ['description', 'desc', 'help']),
      kind: artexFirstText(m, const ['kind', 'type', 'source']).ifEmpty('builtin'),
      params: params,
      raw: m,
    );
  }
}

/// 任务工作空间里的一个文件/目录。
class ArtexWorkspaceEntry {
  final String path;
  final int size;
  final bool isDir;
  final String modified;

  const ArtexWorkspaceEntry({
    required this.path,
    required this.size,
    required this.isDir,
    required this.modified,
  });

  factory ArtexWorkspaceEntry.fromJson(Object? v) {
    if (v is String) {
      return ArtexWorkspaceEntry(
        path: v,
        size: 0,
        isDir: v.endsWith('/'),
        modified: '',
      );
    }
    final m = artexMap(v);
    final p = artexFirstText(m, const ['path', 'name', 'file', 'rel']);
    final dir = m['is_dir'] == true || m['dir'] == true || p.endsWith('/');
    return ArtexWorkspaceEntry(
      path: p,
      size: artexFirstInt(m, const ['size', 'bytes']),
      isDir: dir,
      modified: artexFirstText(m, const ['modified', 'mtime', 'updated_at', 'time']),
    );
  }
}

/// 直跑工具的结果。
class ArtexRunResult {
  final bool ok;
  final String output;
  final int exitCode;
  final int ms;
  final Map<String, dynamic> raw;

  const ArtexRunResult({
    required this.ok,
    required this.output,
    required this.exitCode,
    required this.ms,
    required this.raw,
  });
}

/// `ifEmpty` 便捷方法（避免到处写三元）。
extension _ArtexStringX on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class ArtexClient {
  /// 规范化后的服务基址（不含结尾斜杠）。
  final String baseUrl;

  /// 登录后拿到的 JWT（持久化由调用方决定）。
  String? token;

  ArtexClient(String baseUrl, {this.token}) : baseUrl = normalize(baseUrl);

  /// 用户可能只填了 `192.168.1.10:8787`，补成 http://；去掉结尾斜杠。
  static String normalize(String raw) {
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
    if (query == null || query.isEmpty) return u;
    return u.replace(queryParameters: {...u.queryParameters, ...query});
  }

  /// 浏览器打开用的地址（带 token 省一次登录）。
  String consoleUrl({String path = '/'}) {
    final t = token;
    if (t == null || t.isEmpty) return '$baseUrl$path';
    return '$baseUrl$path?token=${Uri.encodeQueryComponent(t)}';
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  /// 发一个请求并解析 JSON。非 2xx 尽量用服务端给的 message。
  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (baseUrl.isEmpty) throw const ArtexException('请先填服务端地址');
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      // 自签证书 / 内网 IP 常见，这里不阻断（用户连的是自己的实例）。
      client.badCertificateCallback = (cert, host, port) => true;
      final req = await client
          .openUrl(method, _uri(path, query))
          .timeout(const Duration(seconds: 10));
      _headers.forEach(req.headers.set);
      if (body != null) {
        final data = utf8.encode(jsonEncode(body));
        req.headers.contentType = ContentType.json;
        req.headers.contentLength = data.length;
        req.add(data);
      }
      final resp = await req.close().timeout(timeout);
      final raw = await resp.transform(utf8.decoder).join().timeout(timeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        var msg = 'HTTP ${resp.statusCode}';
        try {
          final m = jsonDecode(raw);
          final mm = artexMap(m);
          final cand = artexFirstText(mm, const ['message', 'error', 'detail', 'msg']);
          if (cand.isNotEmpty) msg = cand;
          else if (m is List) msg = 'HTTP ${resp.statusCode}';
        } catch (_) {
          if (raw.trim().isNotEmpty && raw.length < 300) msg = raw.trim();
        }
        throw ArtexException(msg);
      }
      if (raw.trim().isEmpty) return null;
      try {
        return jsonDecode(raw);
      } catch (_) {
        // 工作空间读文件之类的纯文本接口
        return raw;
      }
    } on ArtexException {
      rethrow;
    } on SocketException catch (e) {
      throw ArtexException('连不上：${e.osError?.message ?? e.message}');
    } on TimeoutException {
      throw const ArtexException('请求超时（ARTEX 可能正在跑重查询）');
    } catch (e) {
      throw ArtexException('$e');
    } finally {
      client?.close(force: true);
    }
  }

  /// 依次尝试若干候选路径：404/405/501 就换下一个。
  ///
  /// ARTEX 各版本端点命名不完全一致（`/api/findings` 与
  /// `/api/tasks/{id}/findings` 都出现过），逐个试比写死一个更耐升级。
  Future<dynamic> _sendAny(
    String method,
    List<String> paths, {
    Object? body,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    ArtexException? last;
    for (final p in paths) {
      try {
        return await _send(method, p, body: body, query: query, timeout: timeout);
      } on ArtexException catch (e) {
        if (e.message.startsWith('HTTP 404') ||
            e.message.startsWith('HTTP 405') ||
            e.message.startsWith('HTTP 501')) {
          last = e;
          continue;
        }
        rethrow;
      }
    }
    throw last ?? const ArtexException('没有可用的接口路径');
  }

  // ------------------------------ 基础 ------------------------------

  Future<ArtexHealth> health() async {
    final started = DateTime.now();
    final data = await _send('GET', '/api/health', timeout: const Duration(seconds: 6));
    final ms = DateTime.now().difference(started).inMilliseconds;
    final m = artexMap(data);
    return ArtexHealth(
      ok: m['ok'] == true || m['status'] == 'ok' || m['healthy'] == true,
      service: artexFirstText(m, const ['service', 'name']),
      version: artexFirstText(m, const ['version', 'ver', 'build']),
      ms: ms,
    );
  }

  Future<bool> authInitialized() async {
    final data = await _send('GET', '/api/auth/status', timeout: const Duration(seconds: 8));
    final m = artexMap(data);
    return m['initialized'] == true;
  }

  /// 登录：用户名在 ARTEX 里是固定的 "ARTEX"，只需要密码。
  Future<String> login(String password) async {
    final data = await _send('POST', '/api/auth/login', body: {
      'username': 'ARTEX',
      'password': password,
    });
    final t = artexFirstText(artexMap(data), const ['token', 'access_token', 'jwt']);
    if (t.isEmpty) throw const ArtexException('登录成功但没拿到 token');
    token = t;
    return t;
  }

  Future<Map<String, dynamic>> stats() async {
    final data = await _sendAny('GET', const ['/api/stats', '/api/stats/summary']);
    return artexMap(data);
  }

  Future<Map<String, dynamic>> llmStatus() async {
    final data = await _sendAny('GET', const ['/api/llm/status', '/api/engine/status']);
    return artexMap(data);
  }

  /// 任意 GET（高级/调试用）。
  Future<dynamic> rawGet(String path) => _send('GET', path);

  // ------------------------------ 任务 ------------------------------

  Future<({List<ArtexTask> tasks, String active})> tasks({String? status, int limit = 100}) async {
    final data = await _send('GET', '/api/tasks', query: {
      if (status != null && status.isNotEmpty) 'status': status,
      'limit': '$limit',
    });
    final m = artexMap(data);
    final list = m['tasks'] ?? (data is List ? data : null);
    final out = <ArtexTask>[];
    if (list is List) {
      for (final e in list) {
        if (e is Map) out.add(ArtexTask.fromJson(artexMap(e)));
      }
    }
    final active = m['active'] is Map
        ? artexFirstText(artexMap(m['active']), const ['id', 'task_id', 'name'])
        : artexText(m['active'] ?? m['active_task'] ?? m['active_task_id']);
    return (tasks: out, active: active);
  }

  Future<Map<String, dynamic>> task(String id) async {
    final data = await _sendAny('GET', ['/api/tasks/$id', '/api/tasks/$id/detail']);
    return artexMap(data);
  }

  Future<Map<String, dynamic>> createTask({
    required String description,
    String goal = '',
    String name = '',
  }) async {
    final data = await _send('POST', '/api/tasks', body: {
      'description': description,
      if (goal.isNotEmpty) 'goal': goal,
      if (name.isNotEmpty) 'name': name,
    });
    return artexMap(data);
  }

  Future<Map<String, dynamic>> controlTask(String id, String action) async {
    final data = await _sendAny('POST', [
      '/api/tasks/$id/control',
      '/api/tasks/$id/$action',
    ], body: {
      'action': action,
    });
    return artexMap(data);
  }

  Future<Map<String, dynamic>> addGoal(String id, String goal) async {
    final data = await _sendAny('POST', [
      '/api/tasks/$id/goals',
      '/api/tasks/$id/goal',
    ], body: {
      'goal': goal,
    });
    return artexMap(data);
  }

  // ------------------------------ 发现 ------------------------------

  Future<List<ArtexFinding>> findings({String? taskId, int limit = 200}) async {
    final data = await _sendAny('GET', [
      if (taskId != null && taskId.isNotEmpty) '/api/tasks/$taskId/findings',
      '/api/findings',
    ], query: {
      if (taskId != null && taskId.isNotEmpty) 'task_id': taskId,
      'limit': '$limit',
    });
    final list = data is List ? data : (artexMap(data)['findings'] ?? artexMap(data)['items']);
    final out = <ArtexFinding>[];
    if (list is List) {
      for (final e in list) {
        if (e is Map) out.add(ArtexFinding.fromJson(artexMap(e)));
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  Future<Map<String, dynamic>> finding(String id) async {
    final data = await _sendAny('GET', ['/api/findings/$id', '/api/finding/$id']);
    return artexMap(data);
  }

  // ------------------------------ 日志 ------------------------------

  Future<List<ArtexLogLine>> logs({int limit = 50}) async {
    final data = await _sendAny('GET', const [
      '/api/logs',
      '/api/engine/logs',
      '/api/log',
    ], query: {'limit': '$limit'});
    final list = data is List ? data : (artexMap(data)['logs'] ?? artexMap(data)['lines']);
    final out = <ArtexLogLine>[];
    if (list is List) {
      for (final e in list) {
        out.add(ArtexLogLine.fromJson(e));
      }
    } else if (data is String) {
      for (final line in data.split('\n')) {
        if (line.trim().isNotEmpty) out.add(ArtexLogLine(text: line, level: '', time: ''));
      }
    }
    return out;
  }

  // ------------------------------ 工具池 ------------------------------

  Future<List<ArtexTool>> tools() async {
    final out = <ArtexTool>[];
    final seen = <String>{};
    Future<void> take(String path, String kind) async {
      Object? data;
      try {
        data = await _send('GET', path);
      } on ArtexException {
        return;
      }
      final list = data is List
          ? data
          : (artexMap(data)['tools'] ?? artexMap(data)['items'] ?? artexMap(data)['data']);
      if (list is! List) return;
      for (final e in list) {
        if (e is! Map) continue;
        final m = artexMap(e);
        final t = ArtexTool.fromJson(m);
        if (t.key.isEmpty) continue;
        if (!seen.add(t.key)) continue;
        out.add(ArtexTool(
          key: t.key,
          name: t.name,
          description: t.description,
          kind: kind,
          params: t.params,
          raw: t.raw,
        ));
      }
    }

    await take('/api/tools', 'builtin');
    await take('/api/tools/custom', 'custom');
    out.sort((a, b) {
      // webpt 十件套排前面（最常用），其余按字母序。
      final aw = a.key.startsWith('webpt_') ? 0 : 1;
      final bw = b.key.startsWith('webpt_') ? 0 : 1;
      if (aw != bw) return aw - bw;
      return a.key.compareTo(b.key);
    });
    return out;
  }

  /// 注册/更新自定义工具（`exec` 模板里用 `{param}` 占位）。
  Future<Map<String, dynamic>> registerTool(Map<String, dynamic> tool) async {
    final data = await _sendAny('POST', const ['/api/tools/custom', '/api/tools/custom/register'],
        body: tool);
    return artexMap(data);
  }

  /// 直跑工具（绕开 engine idle）。参数必须含 tool_key + params 两个键。
  Future<ArtexRunResult> runTool(String toolKey, Map<String, dynamic> params) async {
    final started = DateTime.now();
    final data = await _sendAny('POST', const [
      '/api/tools/custom/test',
      '/api/tools/run',
      '/api/tools/custom/run',
    ], body: {
      'tool_key': toolKey,
      'params': params,
    }, timeout: const Duration(seconds: 180));
    final ms = DateTime.now().difference(started).inMilliseconds;
    final m = artexMap(data);
    final output = artexFirstText(m, const ['output', 'stdout', 'result', 'data', 'log']);
    final err = artexFirstText(m, const ['stderr', 'error']);
    final ok = m['ok'] == true ||
        m['success'] == true ||
        (m['ok'] == null && m['error'] == null && err.isEmpty);
    var text = output;
    if (text.isEmpty && data is String) text = data;
    if (!ok && text.isEmpty) text = err;
    if (text.isEmpty && m.isNotEmpty) text = const JsonEncoder.withIndent('  ').convert(m);
    return ArtexRunResult(
      ok: ok,
      output: text,
      exitCode: artexFirstInt(m, const ['exit_code', 'code', 'status']),
      ms: ms,
      raw: m.isNotEmpty ? m : {'raw': data},
    );
  }

  // ------------------------------ 工作区 ------------------------------

  Future<List<ArtexWorkspaceEntry>> workspace(String taskId) async {
    final data = await _sendAny('GET', [
      '/api/tasks/$taskId/workspace',
      '/api/workspace',
    ], query: {'task_id': taskId});
    final list = data is List
        ? data
        : (artexMap(data)['files'] ?? artexMap(data)['entries'] ?? artexMap(data)['items']);
    final out = <ArtexWorkspaceEntry>[];
    if (list is List) {
      for (final e in list) {
        out.add(ArtexWorkspaceEntry.fromJson(e));
      }
    }
    return out;
  }

  Future<String> readWorkspace(String taskId, String path) async {
    final data = await _sendAny('GET', [
      '/api/tasks/$taskId/workspace/file',
      '/api/workspace/file',
    ], query: {'task_id': taskId, 'path': path});
    if (data is String) return data;
    final m = artexMap(data);
    final content = artexFirstText(m, const ['content', 'data', 'text', 'body']);
    if (content.isNotEmpty) return content;
    if (m.isNotEmpty) return const JsonEncoder.withIndent('  ').convert(m);
    return '$data';
  }
}

/// 给 MCP 用的紧凑视图（token 友好：只给判断要用的字段 + 截断）。
Map<String, dynamic> artexTaskBrief(ArtexTask t) => {
      'id': t.id,
      'name': t.name,
      'status': t.status,
      if (t.goal.isNotEmpty) 'goal': t.goal,
      if (t.description.isNotEmpty) 'description': _clip(t.description, 400),
      'goals_met': t.goalsMet,
      'findings': {'critical': t.findingsCritical, 'high': t.findingsHigh, 'total': t.findingsTotal},
      if (t.goals.isNotEmpty) 'goals': t.goals.take(20).toList(),
    };

Map<String, dynamic> artexFindingBrief(ArtexFinding f) => {
      'id': f.id,
      if (f.taskId.isNotEmpty) 'task_id': f.taskId,
      'severity': f.severity,
      'title': _clip(f.title, 300),
      if (f.createdAt.isNotEmpty) 'created_at': f.createdAt,
    };

String _clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}…';
