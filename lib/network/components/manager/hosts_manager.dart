/*
 * Copyright 2024 Hongen Wang All rights reserved.
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

import 'package:proxypin/network/util/random.dart';
import 'package:proxypin/storage/path.dart';
import 'package:proxypin/network/util/url_pattern.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/serial_file_writer.dart';

/// Hosts manager
/// @author wanghongen
class HostsManager {
  static String separator = Platform.pathSeparator;

  static HostsManager? _instance;
  bool enabled = true;
  final List<HostsItem> list = [];

  /// 本次运行累计命中次数（key = HostsItem.id），不持久化。
  final Map<String, int> hitCounts = {};

  final Map<String, List<HostsItem>> _folderMap = {};

  HostsManager._();

  /// Singleton
  /// 初始化中的 Future：并发首次访问共用同一次加载
  ///
  /// 「判空 → await 读盘 → 赋值」在并发首访时会各自初始化一遍：后一个实例覆盖
  /// 前一个，而调用方可能已经拿到旧实例 —— 表现为规则列表被清空/重复、刚加的
  /// 规则时有时无（这些 getter 都跑在每条请求的匹配路径上）。
  static Future<HostsManager>? _loading;

  static Future<HostsManager> get instance async {
    final cached = _instance;
    if (cached != null) {
      return cached;
    }
    final loading = _loading;
    if (loading != null) {
      return loading;
    }
    final future = _create();
    _loading = future;
    try {
      return await future;
    } finally {
      _loading = null;
    }
  }

  static Future<HostsManager> _create() async {
    final manager = HostsManager._();
    await manager.load();
    _instance = manager;
    return manager;
  }

  static File? _configFile;

  static Future<File> get configFile async {
    if (_configFile != null) return _configFile!;

    final path = await Paths.homePath();
    var file = File('$path${separator}hosts.json');
    if (!await file.exists()) {
      await file.create();
    }
    _configFile = file;
    return file;
  }

  /// Load
  Future<void> load() async {
    var json = await (await configFile).readAsString();
    if (json.isEmpty) return;

    // 配置损坏时不能让 Hosts 功能整体起不来（以前 jsonDecode 一抛，instance
    // 每次访问都抛异常）。逐条容错，坏记录跳过。
    try {
      var config = jsonDecode(json);
      // 缺 enabled 字段（更早版本的配置文件）时按「开启」处理，与字段默认值一致；
      // 旧实现 `== true` 会让升级后的用户规则集体失效。
      enabled = config['enabled'] != false;
      list.clear();
      // 重复 load 时若不清，文件夹里的子项会不断累积。
      _folderMap.clear();
      final items = config['list'];
      if (items is List) {
        for (final element in items) {
          try {
            if (element is! Map) continue;
            var hostsItem = HostsItem.fromJson(Map<String, dynamic>.from(element));

            if (hostsItem.parent != null) {
              var children = _folderMap[hostsItem.parent!] ??= [];
              children.add(hostsItem);
              continue;
            }

            if (hostsItem.isFolder) {
              _folderMap[hostsItem.id] ??= [];
            }
            list.add(hostsItem);
          } catch (e) {
            logger.w('跳过无法解析的 Hosts 规则: $e');
          }
        }
      }
    } catch (e) {
      logger.e('Hosts 配置解析失败，按空配置处理', error: e);
    }
  }

  /// Save
  Future<void> flushConfig() async {
    var config = List.from(list);
    for (var values in _folderMap.values) {
      config.addAll(values);
    }

    var json = jsonEncode({
      'enabled': enabled,
      'list': config.map((e) => e.toJson()).toList(),
    });
    // 以前没 await：写入失败静默、且紧接着的读可能拿到旧/空内容。
    await SerialFileWriter.writeString(await configFile, json);
  }

  List<HostsItem> getFolderList(String parent) {
    return _folderMap[parent] ?? [];
  }

  Future<void> addHosts(HostsItem item) async {
    if (item.parent == null) {
      list.add(item);
    } else {
      var children = _folderMap[item.parent!] ??= [];
      children.add(item);
    }
  }

  /// 查找匹配的连接目标。
  ///
  /// [port] 为连接端口；规则若限定了端口则必须一致（null 视为不限端口）。
  Future<HostsItem?> getHosts(String host, [int? port]) async {
    if (!enabled) return null;

    // 先收集全部命中项再挑最优。旧实现「命中即 break」按列表插入顺序决定，
    // 先加的通配 `*.example.com → 127.0.0.1` 会永远压住后加的精确
    // `api.example.com → 10.0.0.5`，且没有任何提示。
    final matches = <HostsItem>[];
    void consider(HostsItem it) {
      if (it.enabled && !it.isFolder && it.match(host) && it.matchesPort(port)) {
        matches.add(it);
      }
    }

    for (var item in list) {
      if (item.isFolder) {
        final children = _folderMap[item.id];
        if (children == null) continue;
        for (var it in children) {
          consider(it);
        }
      } else {
        consider(item);
      }
    }

    if (matches.isEmpty) return null;

    int score(HostsItem it) {
      var s = it.host.contains('*') ? 0 : 100; // 精确 > 通配
      if (it.port != null) s += 10; // 限定端口更具体
      s += it.host.length.clamp(0, 90); // 更长的模式更具体
      return s;
    }

    matches.sort((a, b) => score(b).compareTo(score(a)));
    final found = matches.first;
    found.hitCount++;
    hitCounts[found.id] = (hitCounts[found.id] ?? 0) + 1;
    return found;
  }

  /// 命中次数（按规则 id）。
  int hitsOf(HostsItem item) => hitCounts[item.id] ?? item.hitCount;

  /// 清空命中统计。
  void resetHits() {
    hitCounts.clear();
    for (var item in list) {
      item.hitCount = 0;
      for (var it in _folderMap[item.id] ?? const <HostsItem>[]) {
        it.hitCount = 0;
      }
    }
  }

  removeHosts(Iterable<HostsItem> items) async {
    if (items.isEmpty) return;
    for (var item in items) {
      if (item.parent == null) {
        list.remove(item);
        if (item.isFolder) {
          _folderMap.remove(item.id);
        }
      } else {
        var children = _folderMap[item.parent!] ??= [];
        children.remove(item);
      }
    }
    flushConfig();
  }
}

class HostsItem {
  bool enabled = true;
  bool isFolder = false;
  final String id;
  String? parent;
  String host;
  String? toAddress;
  RegExp? _hostReg;

  /// 只对该端口的目标生效；null 表示不限端口。
  int? port;

  /// 本次运行中该规则的命中次数（不持久化，仅供 UI 展示与排查）。
  int hitCount = 0;

  HostsItem(
      {String? id,
      required this.host,
      this.toAddress,
      this.port,
      required this.enabled,
      this.isFolder = false,
      this.parent})
      : id = id ?? generateId();

  static String generateId() {
    return DateTime.now().millisecondsSinceEpoch.toRadixString(36) + RandomUtil.randomString(4);
  }

  //匹配url
  bool match(String domain) {
    if (host != _hostReg?.pattern) _hostReg = null;
    _hostReg ??= UrlPattern.toHostRegExp(host);
    return _hostReg!.hasMatch(domain);
  }

  /// 端口是否匹配：规则未限定端口时一律通过。
  bool matchesPort(int? targetPort) => port == null || port == targetPort;

  /// 生效的展示字符串，如 `192.168.1.10:8443`。
  String get displayAddress {
    final addr = toAddress ?? '';
    if (port == null || addr.isEmpty) return addr;
    if (addr.contains(':')) return '[$addr]:$port';
    return '$addr:$port';
  }

  HostsItem copyWith({String? host, String? toAddress, int? port, bool clearPort = false, bool? enabled}) {
    return HostsItem(
      id: id,
      host: host ?? this.host,
      toAddress: toAddress ?? this.toAddress,
      port: clearPort ? null : (port ?? this.port),
      enabled: enabled ?? this.enabled,
      isFolder: isFolder,
      parent: parent,
    );
  }

  factory HostsItem.fromJson(Map<String, dynamic> json) {
    return HostsItem(
      id: json['id'],
      host: json['host'],
      toAddress: json['toAddress'],
      port: json['port'] is int ? json['port'] as int : null,
      enabled: json['enabled'],
      parent: json['parent'],
      isFolder: json['isFolder'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'parent': parent,
      'enabled': enabled,
      'isFolder': isFolder,
      'host': host,
      'toAddress': toAddress,
      if (port != null) 'port': port,
    };
  }
}
