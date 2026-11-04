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

// ARTEX 会话状态：一个页面里所有面板共用的一份数据 + 所有动作。
//
// 为什么单独抽出来：7 个页签（概览/任务/发现/工具/日志/工作区/服务）读的是同一
// 批远端数据，动作（刷新、建任务、跑工具）也会互相影响（跑完工具要找发现、建完
// 任务要进工作区）。放在页面 State 里会让 setState 抖动整个 TabBarView；抽成
// ChangeNotifier 后每个面板自己 listen，互不牵连。

import 'package:flutter/foundation.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/components/ai_analyzer.dart';
import 'package:proxypin/network/util/artex_client.dart';
import 'package:proxypin/network/util/artex_service.dart';
import 'package:proxypin/network/util/artex_web_server.dart';

class ArtexSession extends ChangeNotifier {
  String baseUrl = 'http://127.0.0.1:8787';
  String termuxUser = '';
  String? token;

  /// 外部后端（Termux）启动参数：以前只存在配置里没人用，现在「高级」里能改。
  String artexAddr = '127.0.0.1:8787';
  String artexProxyAddr = '127.0.0.1:8788';
  String artexPgDsn = 'postgres://postgres@127.0.0.1:5432/artex?sslmode=disable';

  ArtexClient? client;

  ArtexHealth? health;
  Map<String, dynamic> stats = const <String, dynamic>{};
  Map<String, dynamic> llm = const <String, dynamic>{};

  List<ArtexTask> tasks = const <ArtexTask>[];
  String activeTask = '';

  List<ArtexFinding> findings = const <ArtexFinding>[];
  List<ArtexLogLine> logs = const <ArtexLogLine>[];
  List<ArtexTool> tools = const <ArtexTool>[];
  List<ArtexWorkspaceEntry> workspace = const <ArtexWorkspaceEntry>[];
  String workspaceTaskId = '';

  ArtexServiceStatus service = ArtexServiceStatus.unknown;
  String serviceLog = '';

  String? lastError;
  bool busy = false;
  bool connected = false;

  /// 页面销毁后仍在飞的请求回来时会 notify，ChangeNotifier 在 dispose 之后
  /// notify 会抛「used after dispose」——所有通知都走 [_notify] 兜一层。
  bool _disposed = false;

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 当前连接的客户端（没有就现造一个，便于「先测连通再登录」）。
  ArtexClient ensureClient() {
    final c = client;
    if (c != null && c.baseUrl == ArtexClient.normalize(baseUrl)) {
      c.token = token;
      return c;
    }
    final created = ArtexClient(baseUrl, token: token);
    client = created;
    return created;
  }

  /// 读配置（不自动重连，由页面决定）。
  ///
  /// 唯一真源是 [Configuration]：MCP 的 artex_* 工具读的是同一份，避免 UI 存
  /// SharedPreferences、AI 读配置导致「界面连得上、AI 连不上」。
  Future<void> loadPrefs() async {
    try {
      final conf = await Configuration.instance;
      if (conf.artexEmbedded) {
        // 内置服务端：原生面板也走本地页面服务（它已经把 /api 接到内置后端）
        try {
          await ArtexWebServer.instance.start(base: '');
          baseUrl = ArtexWebServer.instance.origin;
        } catch (_) {
          baseUrl = 'http://127.0.0.1:8787';
        }
      } else {
        baseUrl = conf.artexBaseUrl.trim().isEmpty
            ? 'http://127.0.0.1:8787'
            : conf.artexBaseUrl.trim();
      }
      final t = conf.artexToken;
      token = (t == null || t.isEmpty) ? null : t;
      termuxUser = conf.artexTermuxUser;
      artexAddr = conf.artexAddr;
      artexProxyAddr = conf.artexProxyAddr;
      artexPgDsn = conf.artexPgDsn;
    } catch (e) {
      debugPrint('artex loadPrefs: $e');
    }
    _notify();
  }

  Future<void> savePrefs() async {
    try {
      final conf = await Configuration.instance;
      conf.artexBaseUrl = baseUrl.trim();
      conf.artexToken = (token == null || token!.isEmpty) ? null : token;
      conf.artexTermuxUser = termuxUser;
      if (artexAddr.trim().isNotEmpty) conf.artexAddr = artexAddr.trim();
      if (artexProxyAddr.trim().isNotEmpty) conf.artexProxyAddr = artexProxyAddr.trim();
      if (artexPgDsn.trim().isNotEmpty) conf.artexPgDsn = artexPgDsn.trim();
      await conf.flushConfig();
    } catch (e) {
      debugPrint('artex savePrefs: $e');
    }
  }

  void _begin() {
    busy = true;
    lastError = null;
    _notify();
  }

  void _end([String? error]) {
    busy = false;
    lastError = error;
    _notify();
  }

  /// 连接：先测健康（免鉴权），有密码就登录；本机回环免 token 也放行。
  ///
  /// 返回空串表示成功，否则是给用户看的失败原因。
  Future<String> connect({String password = ''}) async {
    _begin();
    final c = ensureClient();
    try {
      final h = await c.health();
      health = h;
      if (!h.ok) {
        _end('health ok=false');
        return 'health ok=false';
      }
      final pwd = password.trim();
      if (pwd.isNotEmpty) {
        await c.login(pwd);
        token = c.token;
        await savePrefs();
      }
      // token 有可能失效（重启后 JWT 过期）：stats 失败且是 401 就提示重登。
      stats = await c.stats();
      try {
        llm = await c.llmStatus();
      } catch (_) {
        llm = const <String, dynamic>{};
      }
      final t = await c.tasks();
      tasks = t.tasks;
      activeTask = t.active;
      connected = true;
      service = await ArtexService.status(termuxUser);
      _end();
      return '';
    } on ArtexException catch (e) {
      connected = false;
      _end(e.message);
      return e.message;
    } catch (e) {
      connected = false;
      _end('$e');
      return '$e';
    }
  }

  /// 轻量刷新（不重新登录）。
  Future<void> refresh({bool findings = false, bool logs = false, bool tools = false}) async {
    final c = client;
    if (c == null || !connected || busy) return;
    busy = true;
    _notify();
    try {
      health = await c.health();
      stats = await c.stats();
      try {
        llm = await c.llmStatus();
      } catch (_) {
        // 老后端没有 /api/llm/status：保留上一次的值，不影响其它面板
      }
      final t = await c.tasks();
      tasks = t.tasks;
      activeTask = t.active;
      if (findings) this.findings = await c.findings(taskId: activeTask.isEmpty ? null : activeTask);
      if (logs) this.logs = await c.logs(limit: 50);
      if (tools) this.tools = await c.tools();
      lastError = null;
    } on ArtexException catch (e) {
      lastError = e.message;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<String> loadFindings({String? taskId}) async {
    final c = client;
    if (c == null) return 'not connected';
    try {
      findings = await c.findings(taskId: taskId ?? (activeTask.isEmpty ? null : activeTask));
      _notify();
      return '';
    } on ArtexException catch (e) {
      lastError = e.message;
      _notify();
      return e.message;
    }
  }

  Future<String> loadLogs({int limit = 50}) async {
    final c = client;
    if (c == null) return 'not connected';
    try {
      logs = await c.logs(limit: limit);
      lastError = null;
      _notify();
      return '';
    } on ArtexException catch (e) {
      lastError = e.message;
      _notify();
      return e.message;
    }
  }

  Future<String> loadTools() async {
    final c = client;
    if (c == null) return 'not connected';
    try {
      tools = await c.tools();
      _notify();
      return '';
    } on ArtexException catch (e) {
      lastError = e.message;
      _notify();
      return e.message;
    }
  }

  Future<String> loadWorkspace(String taskId) async {
    final c = client;
    if (c == null) return 'not connected';
    workspaceTaskId = taskId;
    try {
      workspace = await c.workspace(taskId);
      lastError = null;
      _notify();
      return '';
    } on ArtexException catch (e) {
      workspace = const <ArtexWorkspaceEntry>[];
      lastError = e.message;
      _notify();
      return e.message;
    }
  }

  Future<({bool ok, String text, Map<String, dynamic> raw})> createTask({
    required String description,
    String goal = '',
    String name = '',
  }) async {
    final c = client;
    if (c == null) return (ok: false, text: 'not connected', raw: const <String, dynamic>{});
    try {
      final raw = await c.createTask(description: description, goal: goal, name: name);
      await refresh();
      return (ok: true, text: '', raw: raw);
    } on ArtexException catch (e) {
      return (ok: false, text: e.message, raw: const <String, dynamic>{});
    }
  }

  Future<String> controlTask(String id, String action) async {
    final c = client;
    if (c == null) return 'not connected';
    try {
      await c.controlTask(id, action);
      await refresh();
      return '';
    } on ArtexException catch (e) {
      return e.message;
    }
  }

  Future<String> addGoal(String id, String goal) async {
    final c = client;
    if (c == null) return 'not connected';
    try {
      await c.addGoal(id, goal);
      await refresh();
      return '';
    } on ArtexException catch (e) {
      return e.message;
    }
  }

  // ---------------------------------------------------------------- AI
  //
  // ARTEX 不再需要单独配模型：直接用 App「设置 → AI 分析」那套 OpenAI 兼容
  // 配置（Configuration.aiEnabled / aiBaseUrl / aiApiKey / aiModel）。这里只做
  // 状态展示与转发，配置本身永远只有一份。

  bool get aiReady => AiAnalyzer.isConfigured;

  /// 给界面看的一行摘要：模型 · 地址（未配置时说明去哪配）。
  String get aiLabel {
    final c = Configuration.loaded;
    if (c == null) return '';
    if (!aiReady) return '未配置';
    return '${c.aiModel} · ${c.aiBaseUrl}';
  }

  /// 自检：能连上并且能返回内容才算通过。
  Future<({bool ok, String text})> testAi() async {
    final c = client;
    if (c != null && connected) {
      final r = await c.testLlm();
      return r;
    }
    if (!aiReady) {
      return (
        ok: false,
        text: '还没有配置 AI：请在「设置 → MCP Connection → AI 分析」填写接口地址、API Key 和模型。'
      );
    }
    try {
      final t = await AiAnalyzer.chat([
        {'role': 'user', 'content': '回复两个字：可用'}
      ]);
      return (ok: true, text: t);
    } catch (e) {
      return (ok: false, text: 'AI 调用失败：$e');
    }
  }

  /// 对话：优先经过后端（内置时它也只是转发到同一套 App AI 配置），
  /// 后端没连上就直接调 App 的 AI，保证「打开就能问」。
  Future<({bool ok, String text})> chat(String text, {String taskId = ''}) async {
    final msg = text.trim();
    if (msg.isEmpty) return (ok: false, text: '内容为空');
    final c = client;
    if (c != null && connected) {
      try {
        return (ok: true, text: await c.chat(msg, taskId: taskId));
      } on ArtexException catch (e) {
        // 后端不支持 /api/chat 时退回直连，而不是把 404 甩给用户
        if (!e.message.startsWith('HTTP 404') &&
            !e.message.startsWith('HTTP 405')) {
          return (ok: false, text: e.message);
        }
      }
    }
    if (!aiReady) {
      return (
        ok: false,
        text: '还没有配置 AI：请在「设置 → MCP Connection → AI 分析」填写接口地址、API Key 和模型。'
      );
    }
    try {
      final r = await AiAnalyzer.chat([
        {'role': 'user', 'content': msg}
      ]);
      return (ok: true, text: r);
    } catch (e) {
      return (ok: false, text: 'AI 调用失败：$e');
    }
  }

  Future<ArtexRunResult> runTool(String key, Map<String, dynamic> params) async {
    final c = client;
    if (c == null) {
      return const ArtexRunResult(
        ok: false,
        output: 'not connected',
        exitCode: -1,
        ms: 0,
        raw: <String, dynamic>{},
      );
    }
    return c.runTool(key, params);
  }

  /// 本地服务：状态 + 日志尾巴一起刷新。
  Future<void> refreshService({bool withLog = false}) async {    service = await ArtexService.status(termuxUser);
    if (withLog) {
      final r = await ArtexService.tailLog(termuxUser);
      serviceLog = r.output;
    }
    _notify();
  }
}
