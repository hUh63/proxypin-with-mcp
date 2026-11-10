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
import 'dart:io';

import 'package:proxypin/network/components/manager/script_manager.dart';
import 'package:proxypin/network/mcp/mcp_server.dart';
import 'package:proxypin/network/mcp/script_workflow_engine.dart';
import 'package:proxypin/network/util/logger.dart';

/// 定时任务动作的**公共执行器**。
///
/// 之前这份逻辑只写在「MCP 自动化」页面的 `_executeTaskDescriptor` 里，
/// 并且靠页面 `initState` 才注册给 [McpScheduler]。后果是：重启 App 后
/// 若用户没进过那个设置页，调度器里的任务到期时找不到执行器，
/// `_runTask` 一行 `logger.w` 就把任务跳过——**定时任务静默不执行**，
/// 而列表里任务还好好躺着。
///
/// 所以执行逻辑下沉到网络层，App 启动即注册，与 UI 是否打开无关。
class McpTaskExecutor {
  McpTaskExecutor._();

  /// 注册到 [McpScheduler]（幂等，重复调用无副作用）。
  static void install() => _installed = true;

  static bool _installed = false;

  static bool get installed => _installed;

  /// 执行一条动作描述（`mcp_tasks.json` 里持久化的结构）：
  /// `{type: 0 脚本 / 1 工具 / 2 工作流 / 3 Webhook, name, script|tool|workflow|webhookUrl}`
  static Future<void> run(Map<String, dynamic> desc) async {
    final type = desc['type'] is int ? desc['type'] as int : int.tryParse('${desc['type']}') ?? 1;
    final taskName = '${desc['name'] ?? ''}';
    try {
      switch (type) {
        case 0:
          await _runScript(taskName, '${desc['script'] ?? ''}');
        case 1:
          await _runTool(taskName, '${desc['tool'] ?? ''}');
        case 2:
          await _runWorkflow(taskName, desc['workflow']);
        case 3:
          await _postWebhook(taskName, '${desc['webhookUrl'] ?? ''}');
        default:
          logger.w('[$taskName] 未知的动作类型：$type');
          return;
      }
      logger.i('[$taskName] 定时任务动作执行完成 (type=$type)');
    } catch (e, s) {
      // 单个动作失败不能中断同任务里的后续动作（调度器循环里还有一层保护，
      // 这里再兜一次，避免异常冒到 Timer 回调里变成未捕获错误）。
      logger.e('[$taskName] 定时任务动作执行失败 (type=$type)', error: e, stackTrace: s);
    }
  }

  static Future<void> _runScript(String taskName, String name) async {
    if (name.isEmpty) return;
    final mgr = await ScriptManager.instance;
    for (final s in mgr.list) {
      if (s.name == name) {
        await mgr.runStandalone(s);
        return;
      }
    }
    logger.w('[$taskName] 脚本不存在：$name');
  }

  static Future<void> _runTool(String taskName, String name) async {
    if (name.isEmpty) return;
    final res = await McpServer().executeTool(name, {});
    logger.i('[$taskName] 工具 $name 返回：$res');
  }

  static Future<void> _runWorkflow(String taskName, dynamic raw) async {
    if (raw is! Map) return;
    final wf = Map<String, dynamic>.from(raw);
    final name = '${wf['name'] ?? ''}';
    final engine = ScriptWorkflowEngine.instance;
    // 优先按 id/name 命中已注册的工作流（引擎里的对象才是可执行的）
    ScriptWorkflow? target;
    final id = '${wf['id'] ?? ''}';
    if (id.isNotEmpty) target = engine.getWorkflow(id);
    if (target == null && name.isNotEmpty) {
      for (final w in engine.getWorkflows()) {
        if (w.name == name) {
          target = w;
          break;
        }
      }
    }
    if (target == null) {
      logger.w('[$taskName] 工作流未注册，跳过：${name.isEmpty ? id : name}');
      return;
    }
    final ctx = await engine.executeWorkflow(target.id);
    logger.i('[$taskName] 工作流 ${target.name} 成功 ${ctx.successCount} 个节点');
  }

  static Future<void> _postWebhook(String taskName, String url) async {
    if (!url.startsWith('http')) return;
    // App 自己就是代理：这里的 HttpClient 必须绕过自身代理链，
    // 否则开 VPN 抓包时 webhook 会被自己的代理拦下来（AI 分析也踩过同样的坑）。
    final client = HttpClient()..findProxy = ((_) => 'DIRECT');
    try {
      client.connectionTimeout = const Duration(seconds: 15);
      final req = await client.postUrl(Uri.parse(url));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'task': taskName,
        'timestamp': DateTime.now().toIso8601String(),
      }));
      final res = await req.close().timeout(const Duration(seconds: 20));
      await res.drain<void>();
      logger.i('[$taskName] Webhook 响应：${res.statusCode}');
    } finally {
      client.close(force: true);
    }
  }
}
