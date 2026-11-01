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

// ARTEX 控制台（轻量）：连你自己的 ARTEX 实例，看状态与任务，一键跳去网页端。
//
// 和 ARTEX 官方安卓套壳的区别：那边内嵌 WebView 跑整个 Next.js，这边只做客户端
// 能做的事 —— 状态、任务、跳转。好处是不引入 webview 依赖、跨平台一致，
// 坏处是真正的任务编排还得回浏览器（按钮已带 token，点开就是登录态）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/artex_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class ArtexPage extends StatefulWidget {
  const ArtexPage({super.key});

  @override
  State<ArtexPage> createState() => _ArtexPageState();
}

class _ArtexPageState extends State<ArtexPage> {
  static const String _kBase = 'artex_base_url';
  static const String _kToken = 'artex_token';

  final _base = TextEditingController(text: 'http://127.0.0.1:8787');
  final _password = TextEditingController();

  ArtexClient? _client;
  ArtexHealth? _health;
  Map<String, dynamic> _stats = const {};
  List<ArtexTask> _tasks = const [];
  String _activeTask = '';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final sp = SharedPreferencesAsync();
    final base = await sp.getString(_kBase);
    final token = await sp.getString(_kToken);
    if (!mounted) return;
    setState(() {
      if (base != null && base.isNotEmpty) _base.text = base;
      if (token != null && token.isNotEmpty) {
        _client = ArtexClient(_base.text, token: token);
      }
    });
    // 之前连过就直接刷新一次状态，省得用户每次进来都要点。
    if (token != null && token.isNotEmpty && base != null && base.isNotEmpty) {
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _base.dispose();
    _password.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    FlutterToastr.show(msg, context, duration: 2);
  }

  /// 连接：先测健康（免鉴权），再按需要登录，然后拉状态与任务。
  Future<void> _connect() async {
    final loc = AppLocalizations.of(context)!;
    if (_busy) return;
    final base = _base.text.trim();
    if (base.isEmpty) {
      _toast(loc.artexNoAddress);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = ArtexClient(base, token: _client?.token);
    try {
      final health = await client.health();
      if (!health.ok) throw const ArtexException('服务端返回 ok=false');
      // 有密码就登录一次；没密码就沿用已保存的 token。
      final pwd = _password.text;
      if (pwd.isNotEmpty) {
        await client.login(pwd);
        await SharedPreferencesAsync().setString(_kToken, client.token ?? '');
      } else if ((client.token ?? '').isEmpty) {
        final initialized = await client.authInitialized();
        throw ArtexException(initialized ? loc.artexNeedPassword : loc.artexNotInitialized);
      }
      await SharedPreferencesAsync().setString(_kBase, base);
      final stats = await client.stats();
      final t = await client.tasks();
      if (!mounted) return;
      setState(() {
        _client = client;
        _health = health;
        _stats = stats;
        _tasks = t.tasks;
        _activeTask = t.active;
        _busy = false;
      });
      _toast(loc.artexConnected);
    } on ArtexException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  /// 已连上时的刷新（不重新登录）。
  Future<void> _refresh() async {
    final client = _client;
    if (client == null || _busy) return;
    setState(() => _busy = true);
    try {
      final stats = await client.stats();
      final t = await client.tasks();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _tasks = t.tasks;
        _activeTask = t.active;
        _error = null;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _openConsole() async {
    final loc = AppLocalizations.of(context)!;
    final client = _client ?? ArtexClient(_base.text);
    if (client.baseUrl.isEmpty) {
      _toast(loc.artexNoAddress);
      return;
    }
    final uri = Uri.tryParse(client.consoleUrl());
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _toast('${loc.fail}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ARTEX'),
        actions: [
          if (_client != null)
            IconButton(tooltip: loc.refresh, icon: const Icon(Icons.refresh), onPressed: _refresh),
          IconButton(tooltip: loc.artexOpenConsole, icon: const Icon(Icons.open_in_browser), onPressed: _openConsole),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
        children: [
          TextField(
            controller: _base,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: loc.artexAddress,
              hintText: 'http://192.168.1.10:8787',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _password,
                obscureText: true,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  labelText: loc.artexPassword,
                  hintText: loc.artexPasswordHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : _connect,
              child: Text(_busy ? '…' : loc.artexConnect),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            loc.artexHint,
            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(_error!,
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
                ),
              ]),
            ),
          ],
          if (_health != null) ...[
            const SizedBox(height: 12),
            _statusCard(loc, theme),
          ],
          if (_tasks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              Text(loc.artexTasks, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text('${_tasks.length}', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
            ]),
            const SizedBox(height: 4),
            for (final t in _tasks) _taskTile(t, theme),
          ],
        ],
      ),
    );
  }

  Widget _statusCard(AppLocalizations loc, ThemeData theme) {
    final h = _health!;
    final mode = '${_stats['engine_mode'] ?? '-'}';
    final llm = _stats['llm_configured'] == true;
    final assets = '${_stats['assets'] ?? '-'}';
    final traffic = _stats['traffic'];
    Widget row(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(width: 82, child: Text(k, style: const TextStyle(fontSize: 12))),
            Expanded(
              child: Text(v,
                  style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: color),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.check_circle, size: 15, color: Colors.green.shade600),
          const SizedBox(width: 5),
          Text('${loc.artexVersion} ${h.version}',
              style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace')),
          const Spacer(),
          Text('${h.ms} ms', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
        ]),
        const Divider(height: 12),
        row(loc.artexEngine, mode),
        row(loc.artexLlm, llm ? loc.artexYes : loc.artexNo,
            color: llm ? Colors.green.shade700 : theme.colorScheme.error),
        row(loc.artexAssets, assets),
        if (traffic is Map)
          row(loc.artexTraffic, traffic.entries.take(4).map((e) => '${e.key}=${e.value}').join(' ')),
        if (_activeTask.isNotEmpty) row(loc.artexActiveTask, _activeTask),
      ]),
    );
  }

  Widget _taskTile(ArtexTask t, ThemeData theme) {
    final running = t.status == 'running';
    final color = switch (t.status) {
      'running' => Colors.green.shade600,
      'paused' => Colors.orange.shade700,
      'done' => Colors.blueGrey,
      'failed' => theme.colorScheme.error,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    final bits = <String>[
      t.status,
      if (t.goalsTotal > 0) '${t.goalsMet}/${t.goalsTotal} goals',
      if (t.findingsCritical > 0) 'C${t.findingsCritical}',
      if (t.findingsHigh > 0) 'H${t.findingsHigh}',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: Icon(running ? Icons.play_circle : Icons.circle_outlined, size: 18, color: color),
        title: Text(t.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(bits.join(' · '),
            style: TextStyle(fontSize: 11, color: color, fontFamily: 'monospace')),
        onTap: () {
          // 点任务直接跳到它的详情页（带 token，打开就是登录态）。
          final client = _client;
          if (client == null) return;
          final url = '${client.baseUrl}/tasks/${Uri.encodeComponent(t.id)}'
              '${client.token != null ? '?token=${Uri.encodeQueryComponent(client.token!)}' : ''}';
          final uri = Uri.tryParse(url);
          if (uri == null) return;
          // catchError 的回调必须返回同类型值（Future<bool>），这里用 try/catch 更省事。
          unawaited(() async {
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (e) {
              _toast('$e');
            }
          }());
        },
      ),
    );
  }
}
