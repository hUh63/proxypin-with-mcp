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

// ARTEX 内置服务端（Dart 实现）—— 让 ARTEX 成为**独立工具**，不依赖 Termux / root / PG。
//
// 背景：ARTEX 官方后端（Go，v0.3.x/2.x）硬依赖 PostgreSQL（db/db.go 里
// `sql.Open("pgx", dsn)` + PG 专属 schema：JSONB、text[]、advisory lock），
// 手机里跑不了 PG。但它的前端（Next.js 静态站）只认同源 `/api/**`，
// 所以这里用 Dart 把「服务端」补上：
//   * 任务 / 发现 / 日志 落本地 JSON（应用私有目录），离线可用；
//   * 认证走单用户免密（本地容器，和 ARTEX_TRUST_LOOPBACK=1 的定位一致）；
//   * 未知端点返回**结构合法的空响应**（GET→[]，其它→{}），前端不会白屏；
//   * `/api/logs/stream`、`/api/update/stream` 这类 SSE 保持长连接 + 心跳，
//     避免前端重连风暴。
//
// 配了外部后端地址时，[ArtexWebServer] 优先反代到外部，这套只做兜底。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:proxypin/network/util/logger.dart';

class ArtexLocalBackend {
  static final ArtexLocalBackend instance = ArtexLocalBackend._();

  ArtexLocalBackend._();

  static const String _dirName = 'artex_embedded';
  static const String _fileName = 'data.json';

  final List<Map<String, dynamic>> _tasks = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _findings = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _logs = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _conversations = <Map<String, dynamic>>[];

  int _seq = 1;
  bool _loaded = false;
  Future<void>? _loading;
  Timer? _saveTimer;
  bool _dirty = false;

  /// 只读统计（给概览用）。
  Map<String, dynamic> get stats => {
        'tasks': _tasks.length,
        'findings': _findings.length,
        'conversations': _conversations.length,
        'engine_mode': 'embedded',
        'llm_configured': false,
        'workers': 0,
      };

  // ------------------------------------------------------------------ 存储

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory('${dir.path}/$_dirName');
    if (!await d.exists()) await d.create(recursive: true);
    return File('${d.path}/$_fileName');
  }

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final raw = await f.readAsString();
        if (raw.trim().isNotEmpty) {
          final m = jsonDecode(raw);
          if (m is Map) {
            _readList(m['tasks'], _tasks);
            _readList(m['findings'], _findings);
            _readList(m['logs'], _logs);
            _readList(m['conversations'], _conversations);
            _seq = (m['seq'] is num) ? (m['seq'] as num).toInt() : _seq;
          }
        }
      }
    } catch (e) {
      logger.w('[ArtexLocal] load failed: $e');
    }
    _loaded = true;
  }

  static void _readList(Object? src, List<Map<String, dynamic>> into) {
    if (src is! List) return;
    for (final e in src) {
      if (e is Map) into.add(e.map((k, v) => MapEntry('$k', v)));
    }
  }

  /// 合并写盘（1.2s 防抖）：建任务/加发现时不会每次都写文件。
  void _scheduleSave() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1200), () => unawaited(_save()));
  }

  Future<void> _save() async {
    if (!_dirty) return;
    _dirty = false;
    try {
      final f = await _file();
      final payload = jsonEncode({
        'seq': _seq,
        'tasks': _tasks,
        'findings': _findings,
        'logs': _logs,
        'conversations': _conversations,
      });
      await f.writeAsString(payload, flush: true);
    } catch (e) {
      logger.w('[ArtexLocal] save failed: $e');
    }
  }

  Future<void> flush() => _save();

  // ------------------------------------------------------------------ 路由

  bool get _isApi => true;

  bool handles(String path) => _isApi && (path == '/api' || path.startsWith('/api/'));

  /// 处理一个 `/api/**` 请求。返回 true 表示已写响应。
  Future<bool> handle(HttpRequest request) async {
    await ensureLoaded();
    final path = request.uri.path;
    final method = request.method.toUpperCase();
    final query = request.uri.queryParameters;
    Map<String, dynamic> body = const <String, dynamic>{};
    if (method == 'POST' || method == 'PUT' || method == 'PATCH') {
      try {
        final raw = await utf8.decodeStream(request);
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) body = decoded.map((k, v) => MapEntry('$k', v));
        }
      } catch (_) {
        body = const <String, dynamic>{};
      }
    }

    // 健康检查（前端用它决定「后端在不在」）
    if (path == '/api/health') {
      _json(request, {
        'ok': true,
        'status': 'ok',
        'service': 'artex',
        'version': 'embedded',
        'engine': 'embedded',
        'llm_configured': false,
      });
      return true;
    }

    // 认证：本地单用户，任何凭据都发同一个内置 token（等价 TRUST_LOOPBACK）
    if (path.startsWith('/api/auth') || path == '/api/users' || path == '/api/user') {
      _json(request, {
        'ok': true,
        'initialized': true,
        'token': 'embedded',
        'user': {'id': 1, 'username': 'ARTEX', 'role': 'admin'},
        'users': [
          {'id': 1, 'username': 'ARTEX', 'role': 'admin'}
        ],
      });
      return true;
    }

    if (path.startsWith('/api/setup')) {
      _json(request, {'ok': true, 'initialized': true, 'done': true});
      return true;
    }

    if (path == '/api/stats' || path == '/api/status' || path == '/api/overview') {
      _json(request, stats);
      return true;
    }

    // 流式端点：保持连接 + 心跳（前端 EventSource 会一直挂着）
    if (path.endsWith('/stream')) {
      return _stream(request);
    }

    // 任务
    if (path == '/api/tasks' && method == 'GET') {
      final status = query['status'];
      final list = status == null || status.isEmpty
          ? _tasks
          : _tasks.where((t) => '${t['status']}' == status).toList();
      _json(request, {
        'tasks': list,
        'total': list.length,
        'active': _activeTaskId(),
      });
      return true;
    }

    if (path == '/api/tasks' && (method == 'POST' || method == 'PUT')) {
      final id = 'task-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
      final now = DateTime.now().toUtc().toIso8601String();
      final description = '${body['description'] ?? body['intent'] ?? ''}';
      final goal = '${body['goal'] ?? ''}';
      final name = '${body['name'] ?? body['title'] ?? ''}';
      final task = <String, dynamic>{
        'id': id,
        'name': name.isEmpty ? (description.isEmpty ? '未命名任务' : description.split('\n').first) : name,
        'title': name,
        'description': description,
        'intent': description,
        'goal': goal,
        'goals': goal.isEmpty ? <String>[] : <String>[goal],
        'goals_met': 0,
        'status': 'created',
        'progress': 0,
        'findings': {'critical': 0, 'high': 0, 'total': 0},
        'created_at': now,
        'updated_at': now,
        'last_activity_unix': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'embedded': true,
      };
      _tasks.insert(0, task);
      // 长时间使用不会无限增长（内置存储是给「本机记录」用的）
      if (_tasks.length > 500) _tasks.removeRange(500, _tasks.length);
      _log('info', 'task', '创建任务 $id（内置服务端）');
      _scheduleSave();
      _json(request, {'ok': true, ...task});
      return true;
    }

    final taskMatch = RegExp(r'^/api/tasks/([^/]+)(?:/([^/]+))?(?:/(.+))?$').firstMatch(path);
    if (taskMatch != null) {
      final id = taskMatch.group(1)!;
      final action = taskMatch.group(2) ?? '';
      final task = _tasks.firstWhere(
        (t) => '${t['id']}' == id,
        orElse: () => <String, dynamic>{},
      );
      if (task.isEmpty) {
        _json(request, {'ok': false, 'error': 'task not found'}, status: 404);
        return true;
      }
      switch (action) {
        case '':
          _json(request, task);
          return true;
        case 'control':
          final act = '${body['action'] ?? ''}';
          task['status'] = switch (act) {
            'pause' => 'paused',
            'resume' => 'running',
            'stop' => 'stopped',
            _ => task['status'],
          };
          task['updated_at'] = DateTime.now().toUtc().toIso8601String();
          _log('info', 'engine', '任务 $id → ${task['status']}');
          _scheduleSave();
          _json(request, {'ok': true, 'status': task['status']});
          return true;
        case 'goals':
        case 'goal':
          final g = '${body['goal'] ?? ''}';
          if (g.isNotEmpty) {
            final goals = (task['goals'] is List)
                ? List<dynamic>.from(task['goals'] as List)
                : <dynamic>[];
            goals.add(g);
            task['goals'] = goals;
          }
          _scheduleSave();
          _json(request, {'ok': true, 'goals': task['goals'] ?? const <String>[]});
          return true;
        case 'chat':
          // 没有本地 LLM：把用户消息记进会话，回一条明确说明（不假装在跑）
          final text = '${body['message'] ?? body['content'] ?? ''}';
          if (_conversations.length > 2000) {
            _conversations.removeRange(0, _conversations.length - 2000);
          }
          _conversations.add({
            'id': 'conv-${_seq++}',
            'task_id': id,
            'role': 'user',
            'content': text,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
          _scheduleSave();
          _json(request, {
            'ok': true,
            'messages': [
              {
                'role': 'assistant',
                'content': '当前是 App 内置服务端：没有接 LLM，也不会自动执行工具。'
                    '任务与发现都记在本机，需要真实扫描请在设置里填外部后端地址。',
              }
            ],
          });
          return true;
        case 'workspace':
        case 'files':
          _json(request, {'files': <dynamic>[], 'entries': <dynamic>[], 'total': 0});
          return true;
        default:
          _json(request, {'ok': true});
          return true;
      }
    }

    // 发现（2.2.7 挂在 exploration 下，老版本是 /api/findings）
    if (path.startsWith('/api/exploration/findings') || path == '/api/findings') {
      final taskId = query['task_id'] ?? '${body['task_id'] ?? ''}';
      final list = taskId.isEmpty
          ? _findings
          : _findings.where((f) => '${f['task_id']}' == taskId).toList();
      _json(request, {
        'findings': list,
        'total': list.length,
        if (method == 'POST') 'ok': true,
      });
      return true;
    }

    // 日志
    if (path.startsWith('/api/logs')) {
      final limit = int.tryParse('${query['limit'] ?? ''}') ?? 200;
      final start = _logs.length > limit ? _logs.length - limit : 0;
      _json(request, {
        'logs': _logs.sublist(start),
        'total': _logs.length,
        'lines': _logs.sublist(start).map((e) => '${e['text']}').toList(),
      });
      return true;
    }

    if (path.startsWith('/api/conversations')) {
      _json(request, {'conversations': _conversations, 'total': _conversations.length});
      return true;
    }

    // 兜底：结构合法的空响应，前端不会白屏
    if (method == 'GET') {
      _json(request, <String, dynamic>{'items': <dynamic>[], 'total': 0});
    } else {
      _json(request, <String, dynamic>{'ok': true});
    }
    return true;
  }

  String _activeTaskId() {
    for (final t in _tasks) {
      final s = '${t['status']}';
      if (s == 'running' || s == 'active') return '${t['id']}';
    }
    return '';
  }

  void _log(String level, String tag, String text) {
    _logs.add({
      'seq': _seq++,
      'ts': DateTime.now().toUtc().toIso8601String(),
      'level': level,
      'tag': tag,
      'text': text,
    });
    if (_logs.length > 2000) _logs.removeRange(0, _logs.length - 2000);
  }

  void addFinding(Map<String, dynamic> finding) {
    _findings.insert(0, {
      'id': 'finding-${_seq++}',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      ...finding,
    });
    if (_findings.length > 2000) _findings.removeRange(2000, _findings.length);
    _scheduleSave();
  }

  /// SSE：挂住连接 + 定期心跳（前端 EventSource 断线会重连风暴）。
  Future<bool> _stream(HttpRequest request) async {
    final res = request.response;
    res.statusCode = 200;
    res.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
    res.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    res.bufferOutput = false;
    res.write(': connected\n\n');
    await res.flush();
    var closed = false;
    // 只在连接存活期间心跳；客户端断开时 flush 会抛，捕获后退出
    final timer = Timer.periodic(const Duration(seconds: 15), (t) async {
      if (closed) {
        t.cancel();
        return;
      }
      try {
        res.write(': ping\n\n');
        await res.flush();
      } catch (_) {
        closed = true;
        t.cancel();
      }
    });
    // 最多挂 30 分钟，避免忘记关的连接常驻
    Timer(const Duration(minutes: 30), () {
      closed = true;
      timer.cancel();
      unawaited(() async {
        try {
          await res.close();
        } catch (_) {
          // 客户端已断开
        }
      }());
    });
    // 注意：SSE 都是 GET，请求体为空，`request.listen` 的 onDone 会**立刻**触发；
    // 用它判断断开会让心跳马上停掉（前端表现为日志页不再刷新）。这里只靠
    // flush 抛异常来判断对端已断。
    return true;
  }

  void _json(HttpRequest request, Object data, {int status = 200}) {
    final res = request.response;
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(data));
    unawaited(res.close());
  }
}
