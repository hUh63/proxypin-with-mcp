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
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/cloud_client.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/workspaces.dart';
import 'package:proxypin/ui/component/utils.dart';

/// 云端页面：账号 / 工作区托管 / 实时协同 / 团队成员。
///
/// 服务端自己部署（`docs/cloud_server_guide.md` 里有可直接运行的 Node 实现）。
/// 不配也能用本地功能，这里只是把「多台设备 / 多个人看同一批数据」接起来。
class CloudPage extends StatefulWidget {
  const CloudPage({super.key});

  @override
  State<CloudPage> createState() => _CloudPageState();
}

class _CloudPageState extends State<CloudPage> {
  final _baseUrl = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _inviteName = TextEditingController();

  bool _busy = false;
  bool _realtime = false;
  CloudAccount? _account;
  List<Map<String, dynamic>> _cloudWorkspaces = const [];
  List<Map<String, dynamic>> _members = const [];
  final List<String> _eventLog = [];
  StreamSubscription<CloudEvent>? _eventSub;
  StreamSubscription<bool>? _statusSub;

  AppLocalizations get localizations => AppLocalizations.of(context)!;
  bool get _isCN => localizations.localeName == 'zh';

  @override
  void initState() {
    super.initState();
    _load();
    // 实时事件 → 刷新列表 + 记一条日志（别人改了东西时这里能看见）
    _eventSub = CloudRealtime.instance.events.listen((event) {
      if (!mounted) return;
      setState(() {
        _eventLog.insert(0, '${event.at.toString().split('.').first}  ${event.type}  ${event.by}');
        if (_eventLog.length > 30) {
          _eventLog.removeLast();
        }
      });
      if (event.type.startsWith('workspace.')) {
        _loadCloudWorkspaces();
      }
    });
    _statusSub = CloudRealtime.instance.status.listen((ok) {
      if (mounted) {
        setState(() => _realtime = ok);
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _statusSub?.cancel();
    _baseUrl.dispose();
    _username.dispose();
    _password.dispose();
    _inviteName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final url = await CloudClient.baseUrl();
    final account = await CloudClient.account();
    if (!mounted) return;
    setState(() {
      _baseUrl.text = url;
      _account = account;
      _realtime = CloudRealtime.instance.connected;
    });
    if (account != null) {
      await _loadCloudWorkspaces();
    }
  }

  void _toast(String msg, {int seconds = 5, bool error = false}) {
    // backgroundColor 是非空参数，不能传 null，所以按状态分两次调用
    if (error) {
      FlutterToastr.show(msg, context,
          rootNavigator: true, duration: seconds, backgroundColor: Colors.red);
    } else {
      FlutterToastr.show(msg, context, rootNavigator: true, duration: seconds);
    }
  }

  Future<void> _saveBaseUrl() async {
    await CloudClient.setBaseUrl(_baseUrl.text);
    if (!mounted) return;
    _toast(_isCN ? '服务端地址已保存' : 'Server URL saved', seconds: 2);
  }

  Future<void> _auth({required bool register}) async {
    final user = _username.text.trim();
    final pass = _password.text;
    if (user.isEmpty || pass.isEmpty) {
      _toast(_isCN ? '请填写用户名和密码' : 'Enter username and password', error: true);
      return;
    }
    setState(() => _busy = true);
    final result = register
        ? await CloudClient.register(user, pass)
        : await CloudClient.login(user, pass);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.$1) {
      _toast(_isCN ? '失败：${result.$2}' : 'Failed: ${result.$2}', seconds: 6, error: true);
      return;
    }
    _password.clear();
    await _load();
    _toast(_isCN ? '已登录' : 'Signed in', seconds: 2);
  }

  Future<void> _logout() async {
    await CloudClient.logout();
    if (!mounted) return;
    setState(() {
      _account = null;
      _cloudWorkspaces = const [];
      _members = const [];
      _realtime = false;
    });
    _toast(_isCN ? '已退出登录' : 'Signed out', seconds: 2);
  }

  Future<void> _loadCloudWorkspaces() async {
    try {
      final list = await CloudClient.listWorkspaces();
      if (!mounted) return;
      setState(() => _cloudWorkspaces = list);
    } catch (e) {
      logger.w('[Cloud] list workspaces failed: $e');
    }
  }

  Future<void> _loadMembers() async {
    try {
      final list = await CloudClient.listMembers();
      if (!mounted) return;
      setState(() => _members = list);
    } catch (e) {
      logger.w('[Cloud] list members failed: $e');
    }
  }

  /// 把选中的本地工作区推到云端。
  Future<void> _pushLocal() async {
    final storage = await WorkspaceStorage.instance;
    final locals = storage.items;
    if (locals.isEmpty) {
      _toast(_isCN ? '本地还没有工作区' : 'No local workspace yet');
      return;
    }
    final picked = await showDialog<Workspace>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(_isCN ? '选择要推送的工作区' : 'Pick a workspace',
            style: const TextStyle(fontSize: 16)),
        children: locals
            .map((w) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, w),
                  child: Text('${w.displayName}（${w.requestCount}）'),
                ))
            .toList(),
      ),
    );
    if (picked == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final har = await storage.harJson(picked.id);
      final r = await CloudClient.pushWorkspace(
        name: picked.displayName,
        description: picked.description,
        harJson: har,
        serverId: picked.serverId,
      );
      if (r['_error'] != null) {
        _toast(_isCN ? '推送失败：${r['_error']}' : 'Push failed: ${r['_error']}', seconds: 7, error: true);
      } else {
        final id = '${r['id'] ?? r['_id'] ?? ''}';
        if (id.isNotEmpty) {
          await storage.markSynced(picked.id, id);
        }
        _toast(_isCN ? '已推送到云端' : 'Pushed to cloud', seconds: 3);
        await _loadCloudWorkspaces();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 把云端的工作区拉到本地（新建或覆盖同名项）。
  Future<void> _pullRemote(Map<String, dynamic> item) async {
    final id = '${item['id'] ?? item['_id'] ?? ''}';
    if (id.isEmpty) {
      return;
    }
    setState(() => _busy = true);
    try {
      final storage = await WorkspaceStorage.instance;
      final result = await CloudClient.pullWorkspace(id);
      if (result.$1.isEmpty) {
        _toast(_isCN ? '云端这份是空的' : 'Remote workspace is empty', error: true);
        return;
      }
      final name = '${item['name'] ?? id}';
      final existing = storage.items.where((w) => w.serverId == id).toList();
      final ws = existing.isNotEmpty ? existing.first : await storage.create(name);
      if (ws.serverId == null) {
        await storage.markSynced(ws.id, id);
      }
      final count = await storage.writeHarJson(ws.id, result.$1);
      _toast(_isCN ? '已拉到本地（$count 条）' : 'Pulled $count requests', seconds: 4);
    } catch (e) {
      _toast(_isCN ? '拉取失败：$e' : 'Pull failed: $e', seconds: 7, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteRemote(Map<String, dynamic> item) async {
    final id = '${item['id'] ?? item['_id'] ?? ''}';
    if (id.isEmpty) {
      return;
    }
    // 云端副本删掉就找不回来了，先确认
    showConfirmDialog(context,
        title: _isCN ? '删除' : 'Delete',
        content: _isCN
            ? '删除云端的这份工作区副本？删除后无法恢复。'
            : 'Remove this workspace copy from the cloud? This cannot be undone.',
        onConfirm: () async {
          await CloudClient.deleteWorkspace(id);
          await _loadCloudWorkspaces();
          _toast(_isCN ? '已删除云端副本' : 'Removed from cloud', seconds: 3);
        });
  }

  Future<void> _toggleRealtime(bool on) async {
    if (on) {
      await CloudRealtime.instance.reconnect();
      // 连上与否由状态流反馈
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      if (!CloudRealtime.instance.connected) {
        _toast(_isCN ? '实时连接失败，检查服务端与登录状态' : 'Realtime connect failed', error: true);
      }
    } else {
      await CloudRealtime.instance.disconnect();
    }
    if (mounted) {
      setState(() => _realtime = CloudRealtime.instance.connected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(_isCN ? '云端协同' : 'Cloud', style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: _isCN ? '刷新' : 'Refresh',
            onPressed: _busy
                ? null
                : () async {
                    await _loadCloudWorkspaces();
                    await _loadMembers();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _serverCard(),
          const SizedBox(height: 12),
          _accountCard(),
          if (_account != null) ...[
            const SizedBox(height: 12),
            _realtimeCard(),
            const SizedBox(height: 12),
            _workspaceCard(),
            const SizedBox(height: 12),
            _memberCard(),
          ],
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
            Text(_isCN ? '服务端' : 'Server', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _baseUrl,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'http://10.0.0.5:8788',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _busy ? null : _saveBaseUrl, child: Text(_isCN ? '保存' : 'Save')),
            const SizedBox(height: 4),
            Text(
              _isCN
                  ? '自己部署的服务端地址。文档里有可直接运行的 Node 实现（含账号与实时推送）。'
                  : 'Your own server. A runnable Node implementation ships with the docs.',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountCard() {
    final account = _account;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(account != null ? Icons.person : Icons.person_outline,
                  size: 18, color: account != null ? Colors.green : Colors.grey),
              const SizedBox(width: 6),
              Text(_isCN ? '账号' : 'Account', style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (account != null)
                TextButton(onPressed: _logout, child: Text(_isCN ? '退出登录' : 'Sign out')),
            ]),
            if (account != null)
              Text(account.displayName.isEmpty ? account.username : account.displayName,
                  style: const TextStyle(fontSize: 13))
            else ...[
              TextField(
                controller: _username,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                    labelText: _isCN ? '用户名' : 'Username', isDense: true, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _password,
                obscureText: true,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                    labelText: _isCN ? '密码' : 'Password', isDense: true, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              Row(children: [
                FilledButton(
                    onPressed: _busy ? null : () => _auth(register: false),
                    child: Text(_isCN ? '登录' : 'Sign in')),
                const SizedBox(width: 10),
                OutlinedButton(
                    onPressed: _busy ? null : () => _auth(register: true),
                    child: Text(_isCN ? '注册' : 'Register')),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _realtimeCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(_realtime ? Icons.sync : Icons.sync_disabled,
                  size: 18, color: _realtime ? Colors.green : Colors.grey),
              const SizedBox(width: 6),
              Text(_isCN ? '实时协同' : 'Realtime',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Switch(value: _realtime, onChanged: _busy ? null : _toggleRealtime),
            ]),
            Text(
              _realtime
                  ? (_isCN ? '已连接，别人的改动会实时推过来' : 'Connected — changes from others arrive live')
                  : (_isCN ? '未连接' : 'Not connected'),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            if (_eventLog.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _eventLog
                      .take(6)
                      .map((e) => Text(e,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10)))
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _workspaceCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.cloud_outlined, size: 18),
              const SizedBox(width: 6),
              Text(_isCN ? '云端工作区' : 'Cloud workspaces',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            FilledButton.tonal(
                onPressed: _busy ? null : _pushLocal,
                child: Text(_isCN ? '把本地工作区推上去' : 'Push a local workspace')),
            const SizedBox(height: 8),
            if (_cloudWorkspaces.isEmpty)
              Text(_isCN ? '云端暂无工作区' : 'Nothing on the server yet',
                  style: const TextStyle(fontSize: 12, color: Colors.grey))
            else
              ..._cloudWorkspaces.map((item) {
                final id = '${item['id'] ?? item['_id'] ?? ''}';
                final name = '${item['name'] ?? id}';
                final count = item['requestCount'] ?? 0;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(name, style: const TextStyle(fontSize: 13)),
                  subtitle: Text('$count · ${item['updatedAt'] ?? ''}',
                      style: const TextStyle(fontSize: 10)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: _isCN ? '拉到本地' : 'Pull',
                        icon: const Icon(Icons.download_outlined, size: 18),
                        onPressed: _busy ? null : () => _pullRemote(item),
                      ),
                      IconButton(
                        tooltip: _isCN ? '删除云端副本' : 'Delete on server',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: _busy ? null : () => _deleteRemote(item),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _memberCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.group_outlined, size: 18),
              const SizedBox(width: 6),
              Text(_isCN ? '团队成员' : 'Team', style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 6),
            if (_members.isEmpty)
              Text(_isCN ? '（点右上角刷新查看）' : '(tap refresh)',
                  style: const TextStyle(fontSize: 12, color: Colors.grey))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _members
                    .map((m) => Chip(
                          label: Text('${m['username'] ?? ''}', style: const TextStyle(fontSize: 11)),
                          avatar: Icon(
                            m['online'] == true ? Icons.circle : Icons.circle_outlined,
                            size: 10,
                            color: m['online'] == true ? Colors.green : Colors.grey,
                          ),
                        ))
                    .toList(),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _inviteName,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                      labelText: _isCN ? '邀请用户名' : 'Invite user',
                      isDense: true,
                      border: const OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _busy
                    ? null
                    : () async {
                        final name = _inviteName.text.trim();
                        if (name.isEmpty) return;
                        final r = await CloudClient.invite(name);
                        if (!mounted) return;
                        _toast(r.$1 ? (_isCN ? '已邀请 $name' : 'Invited $name') : (_isCN ? '邀请失败：${r.$2}' : 'Invite failed: ${r.$2}'),
                            error: !r.$1);
                        _inviteName.clear();
                        await _loadMembers();
                      },
                child: Text(_isCN ? '邀请' : 'Invite'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
