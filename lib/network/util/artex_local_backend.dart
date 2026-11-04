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
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/components/ai_analyzer.dart';
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
        'llm_configured': aiReady,
        'workers': 0,
      };

  // ------------------------------------------------------------------ AI
  //
  // ARTEX 自己不内置模型：**复用 App「设置 → AI 分析」那套 OpenAI 兼容配置**
  // （Configuration.aiEnabled / aiBaseUrl / aiApiKey / aiModel）。
  // 这样用户在设置里填一次，抓包分析、AI 对话、ARTEX 三处都能用，不用重复配。

  bool get aiReady => AiAnalyzer.isConfigured;

  Map<String, dynamic> get llmSummary {
    final c = Configuration.loaded;
    return {
      'ok': true,
      'provider': 'proxypin-ai',
      'engine': 'embedded',
      'source': 'app-settings',
      'enabled': c?.aiEnabled ?? false,
      'configured': aiReady,
      'base_url': c?.aiBaseUrl ?? '',
      'model': c?.aiModel ?? '',
      'has_key': (c?.aiApiKey ?? '').isNotEmpty,
      'agent': c?.aiAgentEnabled ?? false,
      'label': aiReady ? '已配置（App 设置）' : '未配置',
    };
  }

  /// 前端改 AI 配置时写回 App 设置（与设置页同一份，不另存一套）。
  Future<Map<String, dynamic>> _applyLlmConfig(Map<String, dynamic> body) async {
    // 前端可能把配置包一层（{llm:{...}} / {config:{...}}），先摊平。
    var src = body;
    for (final k in const ['llm', 'config', 'data', 'settings']) {
      final inner = body[k];
      if (inner is Map) {
        src = {...body, ...inner.map((key, v) => MapEntry('$key', v))};
        break;
      }
    }
    final c = await Configuration.instance;
    final base = '${src['base_url'] ?? src['baseUrl'] ?? src['endpoint'] ?? ''}'.trim();
    final model = '${src['model'] ?? src['model_name'] ?? ''}'.trim();
    final key = '${src['api_key'] ?? src['apiKey'] ?? src['key'] ?? ''}'.trim();
    if (base.isNotEmpty) c.aiBaseUrl = base;
    if (model.isNotEmpty) c.aiModel = model;
    if (key.isNotEmpty) c.aiApiKey = key;
    if (src.containsKey('enabled')) c.aiEnabled = src['enabled'] == true;
    if (src.containsKey('agent')) c.aiAgentEnabled = src['agent'] == true;
    // 填了地址和 key 却忘了打开开关：直接替用户打开，否则「配好了还是不能用」。
    if (c.aiApiKey.isNotEmpty && c.aiBaseUrl.isNotEmpty) c.aiEnabled = true;
    await c.flushConfig();
    _log('info', 'llm', 'AI 配置已更新（来自 ARTEX 前端）');
    return llmSummary;
  }

  /// 统一 AI 调用：异常转成可读中文，不让前端拿到 HTML 错误页。
  Future<({bool ok, String text})> _ask(String prompt,
      {List<Map<String, String>> history = const []}) async {
    if (!aiReady) {
      return (
        ok: false,
        text: '还没有配置 AI。请到 App「设置 → MCP Connection → AI 分析」'
            '填写接口地址、API Key 和模型；填好后这里的对话、分析和任务指令都能直接用。'
      );
    }
    try {
      final messages = <Map<String, String>>[
        ...history,
        {'role': 'user', 'content': prompt},
      ];
      final text = await AiAnalyzer.chat(messages);
      return (ok: true, text: text);
    } catch (e) {
      logger.w('$e');
      return (ok: false, text: 'AI 调用失败：$e');
    }
  }


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

  /// 内置工具池（来自「ARTEX 渗透系统运维与作战链路」的 webpt 十件套）。
  ///
  /// 内置服务端**不执行**这些脚本（没有 shell / 目标环境），但把清单返回给前端，
  /// 「系统 → 工具」页面不会是空的；点运行会得到一句明确说明，而不是 404。
  static const List<Map<String, dynamic>> builtinTools = [
    {
      'tool_key': 'webpt_port_scan',
      'name': '端口扫描',
      'description': 'TCP 端口扫描 + banner 抓取（内置可运行：限 200 端口 / 32 并发）',
      'local': true,
      'params': {'target': '', 'ports': '1-1000', 'banner': '1'},
    },
    {
      'tool_key': 'webpt_subdomain_enum',
      'name': '子域枚举',
      'description': 'DNS 解析常见前缀（含泛解析检测，内置可运行）',
      'local': true,
      'params': {'domain': '', 'wordlist': 'none'},
    },
    {
      'tool_key': 'webpt_dir_brute',
      'name': '目录爆破',
      'description': '按常见/自定义路径探目录（限 80 条 / 6 并发，内置可运行）',
      'local': true,
      'params': {'url': '', 'wordlist': '', 'extensions': 'php,html,bak'},
    },
    {
      'tool_key': 'webpt_sqli_detect',
      'name': 'SQL 注入探测',
      'description': '按参数形态探测 SQLi',
      'params': {'url': '', 'body': 'none', 'method': 'GET'},
    },
    {
      'tool_key': 'webpt_xss_detect',
      'name': 'XSS 探测',
      'description': '参数值放 FUZZ 占位',
      'params': {'url': '', 'method': 'GET'},
    },
    {
      'tool_key': 'webpt_ssrf_probe',
      'name': 'SSRF 探测',
      'description': '云元数据 / 内网回连',
      'params': {'url': '', 'mode': 'metadata'},
    },
    {
      'tool_key': 'webpt_jwt_attack',
      'name': 'JWT 攻击',
      'description': 'none / kid / 弱口令爆破',
      'params': {'token': '', 'mode': 'none', 'wordlist': 'none'},
    },
    {
      'tool_key': 'webpt_password_spray',
      'name': '口令喷洒',
      'description': '慢速喷洒（仅授权目标）',
      'params': {'url': '', 'users': '', 'passwords': ''},
    },
    {
      'tool_key': 'webpt_webshell_gen',
      'name': 'WebShell 生成',
      'description': '仅授权测试，产物落在工作区',
      'params': {'lang': 'php', 'pass': '', 'mode': 'simple', 'filename': ''},
    },
    {
      'tool_key': 'webpt_hash_id',
      'name': '哈希识别',
      'description': '识别类型并给出 hashcat mode（内置可运行）',
      'local': true,
      'params': {'hash': ''},
    },
  ];

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
      final llm = llmSummary;
      _json(request, {
        'ok': true,
        'status': 'ok',
        'service': 'artex',
        'version': 'embedded',
        'engine': 'embedded',
        'llm_configured': aiReady,
        'llm': llm,
      });
      return true;
    }

    // ---------------- AI（复用 App 设置里的 OpenAI 兼容配置） ----------------
    if (path == '/api/llm' ||
        path == '/api/llm/status' ||
        path == '/api/llm/config' ||
        path == '/api/settings/llm' ||
        path == '/api/system/llm' ||
        path == '/api/engine/status') {
      if (method == 'GET') {
        _json(request, llmSummary);
      } else {
        _json(request, {'ok': true, ...await _applyLlmConfig(body)});
      }
      return true;
    }

    // 测试连通性：发一句最短的话，判断「能连上 + 能返回」
    if (path == '/api/llm/test' || path == '/api/llm/ping') {
      final r = await _ask('回复两个字：可用');
      _log(r.ok ? 'info' : 'warn', 'llm', r.ok ? 'AI 自检通过' : 'AI 自检失败');
      _json(request, {'ok': r.ok, 'reply': r.text, 'configured': aiReady});
      return true;
    }

    // AI 前端对话页/悬浮助手：POST {messages:[{role,content}]} 或 {message:"..."}
    if (path == '/api/chat' ||
        path == '/api/llm/chat' ||
        path == '/api/assistant/chat' ||
        path == '/api/agent/chat') {
      final history = <Map<String, String>>[];
      final raw = body['messages'];
      if (raw is List) {
        for (final m in raw) {
          if (m is Map) {
            final role = '${m['role'] ?? 'user'}';
            final content = '${m['content'] ?? m['text'] ?? ''}';
            if (content.isEmpty) continue;
            history.add({
              'role': role == 'assistant' || role == 'system' ? role : 'user',
              'content': content,
            });
          }
        }
      }
      var prompt = '${body['message'] ?? body['prompt'] ?? body['content'] ?? ''}'.trim();
      if (prompt.isEmpty && history.isNotEmpty) {
        final last = history.removeLast();
        prompt = last['content'] ?? '';
      }
      if (prompt.isEmpty) {
        _json(request, {'ok': false, 'error': 'message is empty'}, status: 400);
        return true;
      }
      final r = await _ask(prompt, history: history.take(20).toList());
      if (r.ok) _log('info', 'llm', 'AI 对话：${_short(prompt, 40)}');
      _json(request, {
        'ok': r.ok,
        'content': r.text,
        'reply': r.text,
        'message': {'role': 'assistant', 'content': r.text},
        'configured': aiReady,
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
          // 真调 AI（App 设置里那套接口）。没有配置就给明确指引，不假装在跑。
          final text = '${body['message'] ?? body['content'] ?? ''}'.trim();
          if (text.isEmpty) {
            _json(request, {'ok': false, 'error': 'message is empty'}, status: 400);
            return true;
          }
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
          final convs =
              _conversations.where((c) => '${c['task_id']}' == id).toList();
          final recent = convs.length > 12
              ? convs.sublist(convs.length - 12)
              : convs;
          final history = <Map<String, String>>[
            for (final m in recent)
              if ('${m['content'] ?? ''}'.trim().isNotEmpty)
                {
                  'role': '${m['role']}' == 'assistant' ? 'assistant' : 'user',
                  'content': '${m['content']}',
                }
          ];
          if (history.isNotEmpty) history.removeLast(); // 刚写入的这条由 prompt 带
          final fCount =
              _findings.where((f) => '${f['task_id']}' == id).length;
          final ctx = StringBuffer()
            ..writeln('【ARTEX 任务上下文】')
            ..writeln('名称：${task['name'] ?? task['title'] ?? id}')
            ..writeln('状态：${task['status'] ?? 'created'}')
            ..writeln('目标：${task['goal'] ?? (task['goals'] is List ? (task['goals'] as List).join('；') : '')}')
            ..writeln('已知发现：$fCount 条')
            ..writeln()
            ..writeln(text);
          final r = await _ask(ctx.toString(), history: history);
          if (r.ok) {
            _conversations.add({
              'id': 'conv-${_seq++}',
              'task_id': id,
              'role': 'assistant',
              'content': r.text,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            });
            task['last_activity_unix'] =
                DateTime.now().millisecondsSinceEpoch ~/ 1000;
            task['updated_at'] = DateTime.now().toUtc().toIso8601String();
            _log('info', 'task', '任务 $id AI 对话回复');
          } else {
            _log('warn', 'task', '任务 $id AI 对话失败');
          }
          _scheduleSave();
          _json(request, {
            'ok': r.ok,
            'configured': aiReady,
            'content': r.text,
            'reply': r.text,
            'messages': [
              {'role': 'assistant', 'content': r.text}
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
      final rest = path.substring('/api/conversations'.length);
      final id = rest.startsWith('/') ? rest.substring(1) : '';
      final taskId = query['task_id'] ??
          query['taskId'] ??
          (id.startsWith('task-') ? id : '');
      var list = _conversations;
      if (taskId.isNotEmpty) {
        list = list.where((c) => '${c['task_id']}' == taskId).toList();
      } else if (id.isNotEmpty) {
        list = list.where((c) => '${c['id']}' == id).toList();
      }
      _json(request, {
        'conversations': list,
        'messages': list,
        'total': list.length,
      });
      return true;
    }

    // 工具池：返回内置清单；真正执行需要外部后端
    if (path == '/api/tools' || path == '/api/tools/custom' || path == '/api/tool-pool') {
      _json(request, {'tools': builtinTools, 'total': builtinTools.length});
      return true;
    }
    if (path.startsWith('/api/tools') && method != 'GET') {
      // 少数几个纯本地就能干活的工具真的执行（不需要 shell / 外部后端），
      // 其余明确说明不执行 —— 这比「全都不能跑」有用得多。
      final key = '${body['tool_key'] ?? body['key'] ?? body['name'] ?? ''}';
      final rawParams = body['params'] ?? body['arguments'];
      final params = rawParams is Map
          ? rawParams.map((k, v) => MapEntry('$k', v))
          : <String, dynamic>{};
      final started = DateTime.now();
      final result = await _runBuiltinTool(key, params);
      if (result != null) {
        result['ms'] = DateTime.now().difference(started).inMilliseconds;
        _log('info', 'tool', '本机执行 $key → ${result['ok'] == true ? 'ok' : 'fail'}');
        _json(request, result);
        return true;
      }
      _json(request, {
        'ok': false,
        'error': 'embedded backend does not run scanners',
        'hint': '内置服务端只在本机执行「哈希识别」「端口扫描」，并记录任务/发现/日志；'
            '其余 webpt 工具需要目标机器上的 shell 环境，请在「高级」里配外部后端。',
      }, status: 200);
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

  // ------------------------------------------------------------ 本机工具
  //
  // 只有「不需要 shell、不产生攻击流量」的少数工具能在纯 Dart 里做：
  //   * 哈希识别 —— 纯字符串判断；
  //   * 端口扫描 —— Socket.connect，限 200 端口 / 32 并发 / 单口 700ms。
  // 其余 webpt 脚本必须跑在目标机器上，内置后端只回一句明确说明。

  Future<Map<String, dynamic>?> _runBuiltinTool(
      String key, Map<String, dynamic> params) async {
    switch (key) {
      case 'webpt_hash_id':
        return _hashId('${params['hash'] ?? params['value'] ?? ''}');
      case 'webpt_port_scan':
        return _portScan(
          '${params['target'] ?? params['host'] ?? ''}',
          '${params['ports'] ?? '1-1000'}',
          '${params['banner'] ?? '1'}' != '0',
        );
      case 'webpt_subdomain_enum':
        return _subdomainEnum('${params['domain'] ?? params['target'] ?? ''}');
      case 'webpt_dir_brute':
        return _dirBrute(
          '${params['url'] ?? params['target'] ?? ''}',
          '${params['wordlist'] ?? ''}',
        );
      default:
        return null;
    }
  }

  static Map<String, dynamic> _hashId(String raw) {
    final h = raw.trim();
    if (h.isEmpty) {
      return {'ok': false, 'error': 'hash 为空'};
    }
    const modes = {
      'MD5': '0',
      'NTLM': '1000',
      'SHA-1': '100',
      'SHA-224': '1300',
      'SHA-256': '1400',
      'SHA-384': '10800',
      'SHA-512': '1700',
      'bcrypt': '3200',
      'MD5 crypt': '500',
      'SHA-256 crypt': '7400',
      'SHA-512 crypt': '1800',
      'Argon2': '无（hashcat 需单独模式）',
    };
    String type = '';
    if (h.startsWith(r'$2a$') || h.startsWith(r'$2b$') || h.startsWith(r'$2y$')) {
      type = 'bcrypt';
    } else if (h.startsWith(r'$argon2')) {
      type = 'Argon2';
    } else if (h.startsWith(r'$1$')) {
      type = 'MD5 crypt';
    } else if (h.startsWith(r'$5$')) {
      type = 'SHA-256 crypt';
    } else if (h.startsWith(r'$6$')) {
      type = 'SHA-512 crypt';
    } else if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(h)) {
      type = switch (h.length) {
        32 => 'MD5',
        40 => 'SHA-1',
        56 => 'SHA-224',
        64 => 'SHA-256',
        96 => 'SHA-384',
        128 => 'SHA-512',
        _ => '',
      };
    }
    final hexOnly = RegExp(r'^[0-9a-fA-F]+$').hasMatch(h);
    if (type.isEmpty) {
      return {
        'ok': true,
        'output': '识别不出：长度 ${h.length}，${hexOnly ? '看起来是十六进制但长度不匹配常见算法' : '含有非十六进制字符'}。\n'
            '常见长度：MD5/NTLM 32、SHA-1 40、SHA-256 64、SHA-512 128。',
        'type': '',
      };
    }
    // 32 位十六进制既可能是 MD5 也可能是 NTLM，长度无法区分。
    final hint = type == 'MD5' ? '（也可能是 NTLM，hashcat 分别用 0 / 1000）' : '';
    return {
      'ok': true,
      'type': type,
      'output': '类型：$type$hint\n长度：${h.length}\nhashcat mode：${modes[type] ?? '未知'}',
    };
  }

  static List<int> _parsePorts(String spec) {
    final out = <int>{};
    for (final part in spec.split(',')) {
      final s = part.trim();
      if (s.isEmpty) continue;
      final dash = s.indexOf('-');
      if (dash > 0) {
        final a = int.tryParse(s.substring(0, dash).trim());
        final b = int.tryParse(s.substring(dash + 1).trim());
        if (a == null || b == null) continue;
        final lo = a < b ? a : b;
        final hi = a < b ? b : a;
        for (var p = lo; p <= hi && out.length < 200; p++) {
          if (p > 0 && p < 65536) out.add(p);
        }
      } else {
        final p = int.tryParse(s);
        if (p != null && p > 0 && p < 65536) out.add(p);
      }
      if (out.length >= 200) break;
    }
    final list = out.toList()..sort();
    return list;
  }

  /// 端口扫描：32 并发、单口 700ms、上限 200 个端口 —— 用户主动、限速，
  /// 不做无限并发（那既慢又容易被对方当成攻击）。
  Future<Map<String, dynamic>> _portScan(
      String target, String ports, bool banner) async {
    final host = target.trim();
    if (host.isEmpty) {
      return {'ok': false, 'error': 'target 为空'};
    }
    final list = _parsePorts(ports);
    if (list.isEmpty) {
      return {'ok': false, 'error': 'ports 解析为空（示例：80,443 或 1-1000）'};
    }
    final queue = List<int>.from(list);
    final open = <int, String>{};
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final port = queue.removeAt(0);
        Socket? socket;
        try {
          socket = await Socket.connect(host, port,
              timeout: const Duration(milliseconds: 700));
          var head = '';
          if (banner) {
            try {
              socket.write('HEAD / HTTP/1.0\r\nHost: $host\r\n\r\n');
              await socket.flush();
              final data = await socket.first.timeout(const Duration(milliseconds: 500));
              head = utf8.decode(data, allowMalformed: true)
                  .split('\n')
                  .first
                  .trim();
            } catch (_) {
              // 非 HTTP 服务不回包很正常
            }
          }
          open[port] = head;
        } catch (_) {
          // 关闭 / 过滤 —— 正常结果
        } finally {
          try {
            socket?.destroy();
          } catch (_) {}
        }
      }
    }

    final workers = list.length < 32 ? list.length : 32;
    await Future.wait(List<Future<void>>.generate(workers, (_) => worker()));
    final ordered = open.keys.toList()..sort();
    final buf = StringBuffer()
      ..writeln('$host：扫描 ${list.length} 个端口，开放 ${ordered.length} 个');
    for (final p in ordered) {
      final h = open[p] ?? '';
      buf.writeln(h.isEmpty ? '  $p/tcp open' : '  $p/tcp open  $h');
    }
    if (ordered.isEmpty) buf.writeln('  （没有开放端口，或被防火墙过滤）');
    return {'ok': true, 'output': buf.toString(), 'open': ordered};
  }

  // ---------------------------------------------------------- 子域枚举

  /// 常用前缀：不带任何「攻击载荷」性质，就是互联网上最常见的服务名。
  /// 用户要更全就自己传 wordlist。
  static const List<String> _subPrefixes = [
    'www', 'm', 'mobile', 'api', 'app', 'admin', 'manage', 'portal', 'login',
    'sso', 'auth', 'account', 'user', 'mail', 'smtp', 'imap', 'pop', 'webmail',
    'dev', 'test', 'stage', 'staging', 'uat', 'beta', 'demo', 'sandbox',
    'prod', 'pre', 'preview', 'release', 'git', 'gitlab', 'jenkins', 'ci',
    'cd', 'build', 'monitor', 'status', 'grafana', 'kibana', 'log', 'logs',
    'db', 'mysql', 'redis', 'mongo', 'es', 'search', 'static', 'cdn', 'img',
    'image', 'upload', 'download', 'file', 'files', 'oss', 'media', 'video',
    'pay', 'payment', 'order', 'shop', 'store', 'blog', 'news', 'help',
    'support', 'docs', 'doc', 'wiki', 'oa', 'erp', 'crm', 'hr', 'mailgw',
  ];

  Future<Map<String, dynamic>> _subdomainEnum(String raw) async {
    var domain = raw.trim().toLowerCase();
    if (domain.isEmpty) return {'ok': false, 'error': 'domain 为空'};
    domain = domain.replaceFirst(RegExp(r'^[a-z]+://'), '');
    final slash = domain.indexOf('/');
    if (slash > 0) domain = domain.substring(0, slash);
    if (domain.startsWith('www.')) domain = domain.substring(4);
    if (!domain.contains('.')) {
      return {'ok': false, 'error': '域名格式不对，示例：example.com'};
    }

    // 泛解析检测：随便挑一个几乎不可能存在的子域，能解析说明 *.domain 全通，
    // 这时枚举出来的「命中」全是假的 —— 必须告诉用户，否则等于在骗人。
    var wildcard = false;
    try {
      final probe = await InternetAddress.lookup(
              'nx-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}.$domain')
          .timeout(const Duration(milliseconds: 1500));
      wildcard = probe.isNotEmpty;
    } catch (_) {
      wildcard = false;
    }

    final queue = List<String>.from(_subPrefixes);
    final hits = <String>[];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final prefix = queue.removeAt(0);
        final host = '$prefix.$domain';
        try {
          final list =
              await InternetAddress.lookup(host).timeout(const Duration(milliseconds: 1500));
          if (list.isNotEmpty) hits.add('$host → ${list.first.address}');
        } catch (_) {
          // 解析失败就是没有，正常
        }
      }
    }

    await Future.wait(List<Future<void>>.generate(16, (_) => worker()));
    hits.sort();
    final buf = StringBuffer()
      ..writeln('$domain：查 ${_subPrefixes.length} 个常见前缀，命中 ${hits.length} 个');
    if (wildcard) {
      buf.writeln('⚠ 该域名疑似泛解析（任意子域都能解析），下面的结果不可信，'
          '请用真实 DNS 记录核对。');
    }
    for (final h in hits) {
      buf.writeln('  $h');
    }
    if (hits.isEmpty && !wildcard) buf.writeln('  （没有命中）');
    return {'ok': true, 'output': buf.toString(), 'hits': hits, 'wildcard': wildcard};
  }

  // ---------------------------------------------------------- 目录探测

  /// 兜底路径：都是「站点常见的公开入口」，不含任何绕过/攻击性质的名字。
  static const List<String> _defaultDirs = [
    'admin', 'login', 'api', 'api/v1', 'api/v2', 'user', 'account', 'home',
    'index.php', 'index.html', 'robots.txt', 'sitemap.xml', 'favicon.ico',
    'static/', 'assets/', 'css/', 'js/', 'images/', 'img/', 'upload/', 'uploads/',
    'backup/', 'bak/', 'old/', 'test/', 'dev/', 'tmp/', 'logs/', 'log/',
    'config/', 'conf/', 'data/', 'db/', 'install/', 'setup/', 'console/',
    'manage/', 'about', 'contact', 'search', 'news', 'help', 'status',
  ];

  Future<Map<String, dynamic>> _dirBrute(String raw, String words) async {
    var base = raw.trim();
    if (base.isEmpty) return {'ok': false, 'error': 'url 为空'};
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'http://$base';
    }
    if (!base.endsWith('/')) base = '$base/';
    final uri = Uri.tryParse(base);
    if (uri == null || uri.host.isEmpty) {
      return {'ok': false, 'error': 'url 不合法，示例：https://example.com/'};
    }

    final custom = words
        .split(RegExp(r'[,\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final paths = (custom.isEmpty ? _defaultDirs : custom).take(80).toList();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..findProxy = ((_) => 'DIRECT') // 探目标站必须直连，否则结果是代理的
      ..badCertificateCallback = (cert, host, port) => true;

    final queue = List<String>.from(paths);
    final found = <String>[];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final path = queue.removeAt(0);
        final url = '$base${path.startsWith('/') ? path.substring(1) : path}';
        try {
          final req = await client.getUrl(Uri.parse(url));
          req.followRedirects = false;
          req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (compatible; ARTEX)');
          final resp = await req.close().timeout(const Duration(seconds: 5));
          final code = resp.statusCode;
          final len = resp.contentLength;
          // 只读第一个块就够（要的是状态码），整份 drain 遇到大文件会卡很久。
          try {
            await resp
                .take(1)
                .drain<void>()
                .timeout(const Duration(seconds: 3), onTimeout: () {});
          } catch (_) {
            // body 读不完不影响结论
          }
          // 404 之外都值得看一眼；401/403 说明路径存在只是要权限。
          if (code != 404) {
            found.add('  $code  $path${len >= 0 ? '  ($len B)' : ''}');
          }
        } catch (_) {
          // 超时/连接失败：跳过
        }
      }
    }

    final started = DateTime.now();
    // 8 并发 × 5s 超时 × 80 条 ≈ 最坏 50s，仍在常见 HTTP 客户端超时之内
    await Future.wait(List<Future<void>>.generate(8, (_) => worker()));
    client.close(force: true);
    final ms = DateTime.now().difference(started).inMilliseconds;
    found.sort();
    final buf = StringBuffer()
      ..writeln('$base：探测 ${paths.length} 条路径（$ms ms），非 404 共 ${found.length} 条'
          '${custom.isEmpty ? '（用内置常见路径，可在 wordlist 里自定义）' : ''}');
    for (final f in found) {
      buf.writeln(f);
    }
    if (found.isEmpty) buf.writeln('  （全部 404 / 连接失败）');
    return {'ok': true, 'output': buf.toString(), 'found': found};
  }

  static String _short(String s, int max) {
    final t = s.replaceAll('\n', ' ').trim();
    return t.length <= max ? t : '${t.substring(0, max)}…';
  }

  String _activeTaskId() {
    for (final t in _tasks) {
      final s = '${t['status']}';
      if (s == 'running' || s == 'active') return '${t['id']}';
    }
    return '';
  }

  void _log(String level, String tag, String text) {    _logs.add({
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
