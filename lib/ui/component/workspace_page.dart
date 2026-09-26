/*
 * Copyright 2023 Hongen Wang
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
import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/workspace_server.dart';
import 'package:proxypin/storage/histories.dart';
import 'package:proxypin/storage/workspaces.dart';

/// 工作区页。
///
/// 本地工作区 = 按项目/环境把抓包数据分开存（文件是标准 HAR，可单独分享）。
/// 自定义服务端 = 把你自己的服务端接进来做共享/备份（契约极小，见
/// `docs/workspace_guide.md`）。两者独立：不配服务端也能正常用本地工作区。
class WorkspacePage extends StatefulWidget {
  /// 当前抓包列表（用于「保存当前抓包」）。为空时该操作会提示。
  final Iterable<HttpRequest>? requestContainer;

  const WorkspacePage({super.key, this.requestContainer});

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  WorkspaceStorage? _storage;
  List<Workspace> _items = const [];
  WorkspaceServerConfig _config = const WorkspaceServerConfig(baseUrl: '');
  bool _busy = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final storage = await WorkspaceStorage.instance;
    final config = await WorkspaceServer.loadConfig();
    if (!mounted) return;
    setState(() {
      _storage = storage;
      _items = storage.items;
      _config = config;
      _busy = false;
    });
  }

  void _toast(String msg, {int seconds = 5}) {
    FlutterToastr.show(msg, context, rootNavigator: true, duration: seconds);
  }

  // ---------- 本地操作 ----------

  Future<void> _create() async {
    final name = await _promptText(
      title: localizations.wsPageNew,
      label: localizations.wsPageNameHint,
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }
    final storage = _storage;
    if (storage == null) {
      return;
    }
    await storage.create(name.trim());
    await _reloadItems();
  }

  Future<void> _rename(Workspace ws) async {
    final name = await _promptText(
      title: localizations.wsPageRenameTitle,
      label: localizations.name,
      initial: ws.name,
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }
    await _storage?.update(ws.id, name: name.trim());
    await _reloadItems();
  }

  Future<void> _remove(Workspace ws) async {
    final ok = await _confirm(
      title: localizations.wsPageDeleteTitle,
      content: localizations.wsPageDeleteConfirm(ws.displayName),
    );
    if (!ok) {
      return;
    }
    await _storage?.remove(ws.id);
    await _reloadItems();
  }

  /// 把当前抓包列表存进工作区（覆盖式）。
  Future<void> _saveCurrent(Workspace ws) async {
    final requests = widget.requestContainer;
    if (requests == null || requests.isEmpty) {
      _toast(localizations.wsPageNoCaptureData);
      return;
    }
    setState(() => _busy = true);
    try {
      await _storage?.saveRequests(ws.id, List<HttpRequest>.from(requests));
      _toast(localizations.wsPageSavedTo(requests.length, ws.displayName));
    } catch (e) {
      _toast(localizations.wsPageSaveFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _reloadItems();
  }

  /// 把工作区数据导入为一个历史记录（可在「历史」里查看/回放）。
  Future<void> _restore(Workspace ws) async {
    setState(() => _busy = true);
    try {
      final requests = await _storage?.loadRequests(ws.id) ?? const <HttpRequest>[];
      if (requests.isEmpty) {
        _toast(localizations.wsPageEmptyWorkspace);
        return;
      }
      final history = await HistoryStorage.instance;
      await history.addRequests(requests, name: ws.displayName);
      _toast(localizations.wsPageImportedToHistory(requests.length));
    } catch (e) {
      _toast(localizations.wsPageImportFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- 服务端操作 ----------

  Future<void> _editConfig() async {
    final baseUrl = await _promptText(
      title: localizations.wsPageServerTitle,
      label: localizations.wsPageServerUrlHint,
      initial: _config.baseUrl,
    );
    if (baseUrl == null) {
      return;
    }
    final token = await _promptText(
      title: localizations.wsPageTokenTitle,
      label: 'Bearer token',
      initial: _config.token,
    );
    if (token == null) {
      return;
    }
    final config = WorkspaceServerConfig(baseUrl: baseUrl.trim(), token: token.trim());
    await WorkspaceServer.saveConfig(config);
    if (!mounted) return;
    setState(() => _config = config);
    _toast(config.isValid
        ? localizations.wsPageServerSaved
        : localizations.wsPageServerCleared);
  }

  Future<void> _push(Workspace ws) async {
    if (!_config.isValid) {
      _toast(localizations.wsPageServerNeeded);
      return;
    }
    setState(() => _busy = true);
    try {
      final har = await _storage?.harJson(ws.id) ?? '';
      final id = await WorkspaceServer.push(
        _config,
        name: ws.displayName,
        description: ws.description,
        harJson: har,
        serverId: ws.serverId,
      );
      if (id.isNotEmpty) {
        await _storage?.markSynced(ws.id, id);
      }
      _toast(localizations.wsPagePushed(har.length));
    } catch (e) {
      _toast(localizations.wsPagePushFailed('$e'), seconds: 7);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _reloadItems();
  }

  /// 从服务端拉取列表，为每个远端工作区在本地建一条并拉下数据。
  Future<void> _pullList() async {
    if (!_config.isValid) {
      _toast(localizations.wsPageServerNeeded);
      return;
    }
    setState(() => _busy = true);
    final storage = _storage;
    try {
      final remote = await WorkspaceServer.list(_config);
      if (remote.isEmpty) {
        _toast(localizations.wsPageServerNoWorkspaces);
        return;
      }
      var pulled = 0;
      for (final item in remote) {
        final serverId = '${item['id'] ?? item['_id'] ?? ''}';
        if (serverId.isEmpty) {
          continue;
        }
        final name = '${item['name'] ?? serverId}';
        var local = _items.where((w) => w.serverId == serverId).toList();
        final ws = local.isNotEmpty
            ? local.first
            : await storage!.create(name, description: '${item['description'] ?? ''}');
        if (ws.serverId == null) {
          await storage?.markSynced(ws.id, serverId);
        }
        final har = await WorkspaceServer.pull(_config, serverId);
        if (har.trim().isNotEmpty) {
          await storage?.writeHarJson(ws.id, har);
          pulled++;
        }
      }
      _toast(localizations.wsPagePulled(pulled));
    } catch (e) {
      _toast(localizations.wsPagePullFailed('$e'), seconds: 7);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _reloadItems();
  }

  // ---------- 工具 ----------

  Future<void> _reloadItems() async {
    final storage = _storage ?? await WorkspaceStorage.instance;
    await storage.refresh();
    if (!mounted) return;
    setState(() => _items = storage.items);
  }

  Future<String?> _promptText({required String title, required String label, String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localizations.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(localizations.confirm)),
        ],
      ),
    );
  }

  Future<bool> _confirm({required String title, required String content}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(localizations.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(localizations.confirm)),
        ],
      ),
    );
    return r == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(localizations.wsPageTitle, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(tooltip: localizations.wsPageServerTooltip, onPressed: _editConfig, icon: const Icon(Icons.cloud_outlined)),
          IconButton(tooltip: localizations.refresh, onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _serverCard(),
                const SizedBox(height: 14),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _create,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(localizations.wsPageNew),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _pullList,
                      icon: const Icon(Icons.cloud_download_outlined, size: 18),
                      label: Text(localizations.wsPagePullFromServer),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Text(
                      localizations.wsPageEmptyHint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  )
                else
                  ..._items.map(_workspaceCard),
              ],
            ),
    );
  }

  Widget _serverCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_config.isValid ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                    size: 18, color: _config.isValid ? Colors.green : Colors.grey),
                const SizedBox(width: 6),
                Text(localizations.wsPageCustomServer,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _config.isValid
                  ? _config.baseUrl
                  : localizations.wsPageServerNotConfiguredHint,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _workspaceCard(Workspace ws) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(ws.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                ),
                if (ws.serverId != null)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.cloud_done_outlined, size: 15, color: Colors.green),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              localizations.wsPageItemMeta(
                  ws.requestCount, ws.updatedAt.toString().split('.').first),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _action(localizations.wsPageSaveCurrent, Icons.download_outlined, () => _saveCurrent(ws)),
                _action(localizations.wsPageImportToHistory, Icons.history, () => _restore(ws)),
                _action(localizations.wsPagePushToServer, Icons.cloud_upload_outlined, () => _push(ws)),
                _action(localizations.rename, Icons.edit_outlined, () => _rename(ws)),
                _action(localizations.delete, Icons.delete_outline, () => _remove(ws), danger: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(String label, IconData icon, VoidCallback onTap, {bool danger = false}) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : onTap,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        visualDensity: VisualDensity.compact,
        foregroundColor: danger ? Colors.red : null,
      ),
    );
  }
}
