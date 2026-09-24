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
import 'dart:convert';
import 'dart:io';

import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/path.dart';
import 'package:proxypin/utils/har.dart';

/// 一个工作区：按项目/环境把抓包数据单独收起来。
///
/// 数据落盘用的是 HAR 格式（复用 [Har] 的读写），所以工作区文件本身就是
/// 标准 HAR——可以直接丢给别的工具看，也能被「导入」回来。
class Workspace {
  final String id;
  String name;
  String description;
  final DateTime createdAt;
  DateTime updatedAt;

  /// 已保存的请求条数
  int requestCount;

  /// 同步到自定义服务端后，服务端分配的 id
  String? serverId;

  /// 最后一次同步时间
  DateTime? syncedAt;

  Workspace({
    required this.id,
    required this.name,
    this.description = '',
    required this.createdAt,
    required this.updatedAt,
    this.requestCount = 0,
    this.serverId,
    this.syncedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'requestCount': requestCount,
        if (serverId != null) 'serverId': serverId,
        if (syncedAt != null) 'syncedAt': syncedAt!.toIso8601String(),
      };

  factory Workspace.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return Workspace(
      id: '${json['id'] ?? now.millisecondsSinceEpoch.toRadixString(36)}',
      name: '${json['name'] ?? 'workspace'}',
      description: '${json['description'] ?? ''}',
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? now,
      updatedAt: DateTime.tryParse('${json['updatedAt']}') ?? now,
      requestCount: json['requestCount'] is int ? json['requestCount'] as int : 0,
      serverId: json['serverId'] == null ? null : '${json['serverId']}',
      syncedAt: json['syncedAt'] == null ? null : DateTime.tryParse('${json['syncedAt']}'),
    );
  }

  String get displayName => name.isEmpty ? id : name;
}

/// 工作区存储：`<home>/workspaces/index.json` 存索引，`<home>/workspaces/<id>/data.har` 存数据。
class WorkspaceStorage {
  static WorkspaceStorage? _instance;
  final List<Workspace> _items = [];

  WorkspaceStorage._();

  static Future<WorkspaceStorage> get instance async {
    final cached = _instance;
    if (cached != null) {
      return cached;
    }
    final storage = WorkspaceStorage._();
    await storage._load();
    _instance = storage;
    return storage;
  }

  List<Workspace> get items => List.unmodifiable(_items);

  Workspace? find(String id) {
    for (final w in _items) {
      if (w.id == id) {
        return w;
      }
    }
    return null;
  }

  // ---------- 落盘 ----------

  static Future<Directory> _dir() async {
    final home = await Paths.homePath();
    final dir = Directory('$home${Platform.pathSeparator}workspaces');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> _indexFile() async {
    final dir = await _dir();
    return File('${dir.path}${Platform.pathSeparator}index.json');
  }

  Future<void> _load() async {
    try {
      final file = await _indexFile();
      if (!await file.exists()) {
        return;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return;
      }
      final decoded = json.decode(raw);
      if (decoded is List) {
        _items.clear();
        for (final e in decoded) {
          if (e is Map) {
            _items.add(Workspace.fromJson(Map<String, dynamic>.from(e)));
          }
        }
      }
    } catch (e) {
      logger.e('[Workspace] load index failed: $e');
    }
  }

  Future<void> _saveIndex() async {
    try {
      final file = await _indexFile();
      await file.writeAsString(json.encode(_items.map((e) => e.toJson()).toList()));
    } catch (e) {
      logger.e('[Workspace] save index failed: $e');
    }
  }

  /// 重新从磁盘读取（外部改动后调用）。
  Future<void> refresh() async {
    _items.clear();
    await _load();
  }

  // ---------- 增删改 ----------

  Future<Workspace> create(String name, {String description = ''}) async {
    final now = DateTime.now();
    final ws = Workspace(
      id: now.microsecondsSinceEpoch.toRadixString(36),
      name: name.trim().isEmpty ? 'workspace' : name.trim(),
      description: description,
      createdAt: now,
      updatedAt: now,
    );
    _items.insert(0, ws);
    await _saveIndex();
    return ws;
  }

  Future<void> update(String id, {String? name, String? description}) async {
    final ws = find(id);
    if (ws == null) {
      return;
    }
    if (name != null && name.trim().isNotEmpty) {
      ws.name = name.trim();
    }
    if (description != null) {
      ws.description = description;
    }
    ws.updatedAt = DateTime.now();
    await _saveIndex();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((e) => e.id == id);
    await _saveIndex();
    try {
      final dir = await _dir();
      final sub = Directory('${dir.path}${Platform.pathSeparator}$id');
      if (await sub.exists()) {
        await sub.delete(recursive: true);
      }
    } catch (e) {
      logger.e('[Workspace] remove data failed: $e');
    }
  }

  // ---------- 数据 ----------

  static Future<File> _dataFile(String id) async {
    final dir = await _dir();
    final sub = Directory('${dir.path}${Platform.pathSeparator}$id');
    if (!await sub.exists()) {
      await sub.create(recursive: true);
    }
    return File('${sub.path}${Platform.pathSeparator}data.har');
  }

  /// 把一批请求存进工作区（覆盖式）。
  Future<void> saveRequests(String id, List<HttpRequest> requests) async {
    final file = await _dataFile(id);
    final ws = find(id);
    await Har.writeFile(requests, file, title: ws?.displayName ?? id);
    if (ws != null) {
      ws.requestCount = requests.length;
      ws.updatedAt = DateTime.now();
      await _saveIndex();
    }
  }

  /// 读回工作区里的请求。
  Future<List<HttpRequest>> loadRequests(String id) async {
    final file = await _dataFile(id);
    if (!await file.exists()) {
      return const [];
    }
    try {
      return await Har.readFile(file);
    } catch (e) {
      logger.e('[Workspace] read har failed: $e');
      return const [];
    }
  }

  /// 原始 HAR JSON（同步给服务端时用）。
  Future<String> harJson(String id) async {
    final file = await _dataFile(id);
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  /// 用服务端下发的 HAR JSON 覆盖本地工作区数据。
  Future<int> writeHarJson(String id, String harJson) async {
    final file = await _dataFile(id);
    await file.writeAsString(harJson);
    final requests = await loadRequests(id);
    final ws = find(id);
    if (ws != null) {
      ws.requestCount = requests.length;
      ws.updatedAt = DateTime.now();
      await _saveIndex();
    }
    return requests.length;
  }

  /// 记录同步信息。
  Future<void> markSynced(String id, String serverId) async {
    final ws = find(id);
    if (ws == null) {
      return;
    }
    ws.serverId = serverId;
    ws.syncedAt = DateTime.now();
    await _saveIndex();
  }
}
