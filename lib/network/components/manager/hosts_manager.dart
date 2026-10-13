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
  static Future<HostsManager> get instance async {
    if (_instance == null) {
      _instance = HostsManager._();
      await _instance?.load();
    }
    return _instance!;
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

    var config = jsonDecode(json);
    enabled = config['enabled'] == true;
    list.clear();
    config['list']?.forEach((element) {
      var hostsItem = HostsItem.fromJson(element);

      if (hostsItem.parent != null) {
        var children = _folderMap[hostsItem.parent!] ??= [];
        children.add(hostsItem);
        return;
      }

      if (hostsItem.isFolder) {
        _folderMap[hostsItem.id] ??= [];
      }
      list.add(hostsItem);
    });
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
    (await configFile).writeAsString(json);
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

    HostsItem? found;

    for (var item in list) {
      if (!item.enabled) continue;

      if (item.isFolder) {
        var list = _folderMap[item.id];
        if (list == null) continue;
        for (var it in list) {
          if (it.enabled && it.match(host) && it.matchesPort(port)) {
            found = it;
            break;
          }
        }
        if (found != null) break;
        continue;
      }

      if (item.match(host) && item.matchesPort(port)) {
        found = item;
        break;
      }
    }

    if (found != null) {
      found.hitCount++;
      hitCounts[found.id] = (hitCounts[found.id] ?? 0) + 1;
    }
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
