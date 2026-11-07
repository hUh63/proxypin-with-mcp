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

// ARTEX 控制台（客户端）。
//
// ARTEX 的真实形态：Termux 里的 Go 服务（:8787 API / :8788 抓包代理），web UI
// 已弃用、内置 LLM 引擎常驻 idle。它只负责「任务容器 + 存储 + 工具池」，决策由
// 人（本页）或 AI（MCP 的 artex_* 工具）来做。
//
// 所以这页做两件事：
//   1. **手动**：概览/任务/发现/工具/日志/工作区/服务 七个面板，覆盖 health、
//      stats、tasks、findings、logs、tools、run_tool、workspace 全部接口；
//   2. **本地运行**：用 root 调 `su <termux用户> -c '...'` 起 PG + ARTEX、看
//      PID、tail 日志，命令与 Termux 里手敲的一致（见 ArtexService）。
// AI 控制走 MCP 的 artex_* 工具，两者共用同一份配置（Configuration）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/artex_service.dart';
import 'package:proxypin/network/util/artex_session.dart';
import 'package:proxypin/ui/component/ai_analysis.dart';
import 'package:proxypin/ui/toolbox/artex_panels.dart';
import 'package:url_launcher/url_launcher.dart';

class ArtexPage extends StatefulWidget {
  const ArtexPage({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ArtexPage()),
    );
  }

  @override
  State<ArtexPage> createState() => _ArtexPageState();
}

class _ArtexPageState extends State<ArtexPage> with SingleTickerProviderStateMixin {
  final ArtexSession _session = ArtexSession();
  late final TabController _tabs = TabController(length: 7, vsync: this);

  final _base = TextEditingController(text: 'http://127.0.0.1:8787');
  final _password = TextEditingController();
  bool _autoTried = false;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await _session.loadPrefs();
    if (!mounted) return;
    setState(() => _base.text = _session.baseUrl);
    // 之前连过就自动连一次，省得每次进来都要点。
    if (!_autoTried) {
      _autoTried = true;
      final r = await _session.connect();
      if (r.isNotEmpty) {
        // 自动连失败很正常（ARTEX 没起），不打扰用户，留在设置界面即可。
        debugPrint('artex auto connect: $r');
      }
    }
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    _session.dispose();
    _tabs.dispose();
    _base.dispose();
    _password.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    FlutterToastr.show(msg, context, duration: 2);
  }

  Future<void> _connect() async {
    final loc = AppLocalizations.of(context)!;
    final base = _base.text.trim();
    if (base.isEmpty) {
      _toast(loc.artexNoAddress);
      return;
    }
    _session.baseUrl = base;
    await _session.savePrefs();
    final err = await _session.connect(password: _password.text);
    if (!mounted) return;
    if (err.isEmpty) {
      _toast(loc.artexConnected);
    } else {
      _toast(err);
    }
  }

  Future<void> _openConsole() async {
    final loc = AppLocalizations.of(context)!;
    final c = _session.client;
    final url = c?.consoleUrl() ?? _session.baseUrl;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _toast(loc.artexNoAddress);
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _editAddress() async {
    final loc = AppLocalizations.of(context)!;
    final c = TextEditingController(text: _session.baseUrl);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.artexAddress),
        content: TextField(
          controller: c,
          decoration: InputDecoration(hintText: 'http://127.0.0.1:8787'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(loc.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(loc.save)),
        ],
      ),
    );
    final text = c.text.trim();
    c.dispose();
    if (ok != true || text.isEmpty) return;
    _session.baseUrl = text;
    if (!mounted) return;
    setState(() => _base.text = text);
    await _session.savePrefs();
    await _connect();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final connected = _session.connected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ARTEX'),
        actions: [
          IconButton(
            tooltip: loc.artexAiTitle,
            icon: const Icon(Icons.smart_toy_outlined),
            onPressed: () => ArtexChatSheet.show(context, _session),
          ),
          if (connected)
            IconButton(
              tooltip: loc.refresh,
              icon: const Icon(Icons.refresh),
              onPressed: _session.busy ? null : () => _session.refresh(),
            ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'console':
                  await _openConsole();
                  break;
                case 'address':
                  await _editAddress();
                  break;
                case 'refresh':
                  await _session.refresh(findings: true, logs: true, tools: true);
                  break;
                case 'disconnect':
                  setState(() => _session.connected = false);
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'console', child: Text(loc.artexOpenConsole)),
              PopupMenuItem(value: 'address', child: Text(loc.artexAddress)),
              PopupMenuItem(value: 'refresh', child: Text(loc.refresh)),
              if (connected)
                PopupMenuItem(value: 'disconnect', child: Text(loc.artexDisconnect)),
            ],
          ),
        ],
        bottom: connected
            ? TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: loc.artexTabOverview),
                  Tab(text: loc.artexTabTasks),
                  Tab(text: loc.artexTabFindings),
                  Tab(text: loc.artexTabTools),
                  Tab(text: loc.artexTabLogs),
                  Tab(text: loc.artexTabWorkspace),
                  Tab(text: loc.artexAiTitle),
                ],
              )
            : null,
      ),
      body: connected ? _body() : _setup(),
    );
  }

  Widget _body() {
    return Column(
      children: [
        if (_session.busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              ArtexOverviewPanel(
                session: _session,
                onRefresh: () => _session.refresh(findings: true, logs: true),
                onOpenConsole: _openConsole,
                onOpenService: () => _tabs.animateTo(6),
              ),
              ArtexTasksPanel(session: _session),
              ArtexFindingsPanel(session: _session),
              ArtexToolsPanel(session: _session),
              ArtexLogsPanel(session: _session),
              ArtexWorkspacePanel(session: _session),
              ArtexServicePanel(session: _session, onToast: _toast),
            ],
          ),
        ),
      ],
    );
  }

  /// 未连接时的落地页：地址 + 密码 + 一键本地启动。
  Widget _setup() {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ARTEX', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(loc.artexHint,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor, height: 1.5)),
                const SizedBox(height: 14),
                TextField(
                  controller: _base,
                  decoration: InputDecoration(
                    labelText: loc.artexAddress,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: loc.artexPassword,
                    helperText: loc.artexPasswordHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _session.busy ? null : _connect,
                        icon: const Icon(Icons.link, size: 18),
                        label: Text(loc.artexConnect),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _openConsole,
                      child: Text(loc.artexOpenConsole),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // 独立运行不需要 Termux：这里只放「AI 配置」和「内置服务端」两件事。
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  _session.aiReady ? Icons.smart_toy : Icons.smart_toy_outlined,
                  size: 20,
                  color: _session.aiReady
                      ? Colors.green
                      : theme.colorScheme.error,
                ),
                title: Text(_session.aiReady
                    ? loc.artexAiConfigured
                    : loc.artexAiNotConfigured),
                subtitle: Text(
                  _session.aiReady ? _session.aiLabel : loc.artexAiShared,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final saved = await showAiSettingsDialog(context);
                      if (!mounted) return;
                      setState(() {});
                      if (saved == true) _toast(loc.artexAiSaved);
                    },
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text(loc.artexAiOpen),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.dns, size: 20),
            title: Text(loc.artexEmbeddedTitle),
            subtitle: Text(loc.artexEmbeddedBody,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
          ),
        ),
        if (!ArtexService.supported)
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline, size: 20),
              title: Text(loc.artexNotAndroid),
              subtitle: Text(loc.artexRemoteOnlyHint, style: theme.textTheme.bodySmall),
            ),
          ),
        if (_session.lastError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text(_session.lastError!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(loc.artexWorkflowBody,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.65)),
          ),
        ),
        const SizedBox(height: 10),
        if (_session.busy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}
