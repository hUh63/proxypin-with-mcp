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
  bool get _isCN => localizations.localeName == 'zh';

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
      title: _isCN ? '新建工作区' : 'New workspace',
      label: _isCN ? '名称（如「支付模块」「测试环境」）' : 'Name',
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
      title: _isCN ? '重命名工作区' : 'Rename workspace',
      label: _isCN ? '名称' : 'Name',
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
      title: _isCN ? '删除工作区' : 'Delete workspace',
      content: _isCN
          ? '「${ws.displayName}」及其本地数据会被删除，无法恢复。'
          : '"${ws.displayName}" and its local data will be deleted.',
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
      _toast(_isCN ? '当前没有抓包数据可保存' : 'No captured requests to save');
      return;
    }
    setState(() => _busy = true);
    try {
      await _storage?.saveRequests(ws.id, List<HttpRequest>.from(requests));
      _toast(_isCN ? '已保存 ${requests.length} 条到「${ws.displayName}」' : 'Saved ${requests.length} requests');
    } catch (e) {
      _toast(_isCN ? '保存失败：$e' : 'Save failed: $e');
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
        _toast(_isCN ? '工作区里没有数据' : 'Workspace is empty');
        return;
      }
      final history = await HistoryStorage.instance;
      await history.addRequests(requests, name: ws.displayName);
      _toast(_isCN ? '已导入 ${requests.length} 条到历史' : 'Imported ${requests.length} requests to history');
    } catch (e) {
      _toast(_isCN ? '导入失败：$e' : 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- 服务端操作 ----------

  Future<void> _editConfig() async {
    final baseUrl = await _promptText(
      title: _isCN ? '工作区服务端' : 'Workspace server',
      label: _isCN ? '服务端地址（如 http://10.0.0.5:8787）' : 'Base URL',
      initial: _config.baseUrl,
    );
    if (baseUrl == null) {
      return;
    }
    final token = await _promptText(
      title: _isCN ? '访问令牌（可留空）' : 'Token (optional)',
      label: _isCN ? 'Bearer token' : 'Bearer token',
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
        ? (_isCN ? '已保存服务端配置' : 'Server config saved')
        : (_isCN ? '已清空服务端配置' : 'Server config cleared'));
  }

  Future<void> _push(Workspace ws) async {
    if (!_config.isValid) {
      _toast(_isCN ? '请先配置工作区服务端' : 'Configure the workspace server first');
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
      _toast(_isCN ? '已推送到服务端（${har.length} 字节）' : 'Pushed to server');
    } catch (e) {
      _toast(_isCN ? '推送失败：$e' : 'Push failed: $e', seconds: 7);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _reloadItems();
  }

  /// 从服务端拉取列表，为每个远端工作区在本地建一条并拉下数据。
  Future<void> _pullList() async {
    if (!_config.isValid) {
      _toast(_isCN ? '请先配置工作区服务端' : 'Configure the workspace server first');
      return;
    }
    setState(() => _busy = true);
    final storage = _storage;
    try {
      final remote = await WorkspaceServer.list(_config);
      if (remote.isEmpty) {
        _toast(_isCN ? '服务端没有工作区' : 'Server has no workspaces');
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
      _toast(_isCN ? '已拉取 $pulled 个工作区' : 'Pulled $pulled workspaces');
    } catch (e) {
      _toast(_isCN ? '拉取失败：$e' : 'Pull failed: $e', seconds: 7);
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
        title: Text(_isCN ? '工作区' : 'Workspaces', style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(tooltip: _isCN ? '服务端配置' : 'Server', onPressed: _editConfig, icon: const Icon(Icons.cloud_outlined)),
          IconButton(tooltip: _isCN ? '刷新' : 'Refresh', onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh)),
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
                      label: Text(_isCN ? '新建工作区' : 'New workspace'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _pullList,
                      icon: const Icon(Icons.cloud_download_outlined, size: 18),
                      label: Text(_isCN ? '从服务端拉取' : 'Pull from server'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Text(
                      _isCN
                          ? '还没有工作区。建一个，把当前抓包存进去，就能按项目分开管理。'
                          : 'No workspace yet. Create one and save the current capture into it.',
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
                Text(_isCN ? '自定义服务端' : 'Custom server',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _config.isValid
                  ? _config.baseUrl
                  : (_isCN
                      ? '未配置。只用本地工作区的话不需要它；想共享/备份到自己的服务器再填。'
                      : 'Not configured. Only needed if you want to share/backup to your own server.'),
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
              '${ws.requestCount} ${_isCN ? '条' : 'requests'} · ${ws.updatedAt.toString().split('.').first}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _action(_isCN ? '保存当前抓包' : 'Save current', Icons.download_outlined, () => _saveCurrent(ws)),
                _action(_isCN ? '导入到历史' : 'Import to history', Icons.history, () => _restore(ws)),
                _action(_isCN ? '推送到服务端' : 'Push', Icons.cloud_upload_outlined, () => _push(ws)),
                _action(_isCN ? '重命名' : 'Rename', Icons.edit_outlined, () => _rename(ws)),
                _action(_isCN ? '删除' : 'Delete', Icons.delete_outline, () => _remove(ws), danger: true),
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
