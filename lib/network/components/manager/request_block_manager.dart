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

import 'package:proxypin/storage/path.dart';
import 'package:proxypin/network/util/url_pattern.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/serial_file_writer.dart';

/// 请求屏蔽
/// @author wanghongen
/// 2024/02/02
class RequestBlockManager {
  static RequestBlockManager? _instance;
  bool enabled = true;
  List<RequestBlockItem> list = [];
  final File _storageFile;

  RequestBlockManager._(this._storageFile);

  ///单例
  static Future<RequestBlockManager> get instance async {
    if (_instance == null) {
      var file = await configFile();
      _instance = RequestBlockManager._(file);
      await _instance?._load();
    }
    return _instance!;
  }

  static Future<File> configFile() async {
    // 便携模式下配置随程序目录存放（上游 #285）
    var directory = await Paths.homePath();
    var file = File('$directory${Platform.pathSeparator}request_block.json');
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return file;
  }

  ///加载
  Future<void> _load() async {
    var json = await _storageFile.readAsString();
    if (json.isEmpty) return;
    // 配置文件被写坏/手工改过时不能让整个屏蔽功能起不来（以前 jsonDecode 一抛，
    // instance 每次访问都抛异常，请求屏蔽直接不可用）。逐条容错 + 保留默认值。
    try {
      var config = jsonDecode(json);
      // 缺 enabled 字段（更早版本的配置文件）时按「开启」处理。
      enabled = config['enabled'] != false;
      list.clear();
      final items = config['list'];
      if (items is List) {
        for (final element in items) {
          try {
            if (element is Map) list.add(RequestBlockItem.fromJson(Map<String, dynamic>.from(element)));
          } catch (e) {
            logger.w('跳过无法解析的屏蔽规则: $e');
          }
        }
      }
    } catch (e) {
      logger.e('请求屏蔽配置解析失败，按空配置处理', error: e);
    }
  }

  Future<void> addBlockRequest(RequestBlockItem item) async {
    list.add(item);
    await flushConfig();
  }

  Future<void> removeBlockRequest(int index) async {
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    await flushConfig();
  }

  /// 是否启用
  bool enableBlockRequest(String url) {
    if (!enabled) {
      return false;
    }
    return list.any((element) => element.match(url, BlockType.blockRequest));
  }

  bool enableBlockResponse(String url) {
    if (!enabled) {
      return false;
    }
    return list.any((element) => element.match(url, BlockType.blockResponse));
  }

  ///刷新配置
  Future<void> flushConfig() async {
    await SerialFileWriter.writeString(_storageFile, jsonEncode({'enabled': enabled, 'list': list}));
  }
}

enum BlockType {
  blockRequest('屏蔽请求'),
  blockResponse('屏蔽响应');

  //名称
  final String label;

  const BlockType(this.label);
  static BlockType nameOf(String name) {
    return BlockType.values.firstWhere((element) => element.name == name,
        orElse: () => BlockType.blockRequest);
  }
}

class RequestBlockItem {
  bool enabled = true;
  String url;
  BlockType type;
  RegExp? urlReg;

  RequestBlockItem(this.enabled, this.url, this.type);

  //匹配url
  bool match(String matchUrl, BlockType blockType) {
    urlReg ??= UrlPattern.toHostRegExp(url);
    return enabled && type == blockType && urlReg!.hasMatch(matchUrl);
  }

  factory RequestBlockItem.fromJson(Map<String, dynamic> json) {
    final url = json['url']?.toString() ?? '';
    // 空 URL 规则会匹配到几乎所有请求（等于「屏蔽全部」），必须当坏数据跳过。
    if (url.trim().isEmpty) {
      throw const FormatException('request block rule missing url');
    }
    // enabled 缺省视为启用（更早版本不写这个键）；写成 "true"/1 也容忍。
    final rawEnabled = json['enabled'];
    final enabled = rawEnabled is bool ? rawEnabled : '$rawEnabled' != 'false';
    return RequestBlockItem(enabled, url, BlockType.nameOf('${json['type']}'));
  }

  Map<String, dynamic> toJson() {
    return {'enabled': enabled, 'url': url, 'type': type.name};
  }

  @override
  String toString() {
    return toJson().toString();
  }
}
