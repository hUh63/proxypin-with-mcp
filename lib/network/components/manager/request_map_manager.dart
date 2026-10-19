import 'dart:convert';
import 'dart:io';

import 'package:proxypin/storage/path.dart';

import '../../util/logger.dart';
import '../../util/random.dart';
import '../../util/url_pattern.dart';
import 'package:proxypin/network/util/serial_file_writer.dart';

class RequestMapManager {
  static RequestMapManager? _instance;

  static String separator = Platform.pathSeparator;

  RequestMapManager._internal();

  final Map<RequestMapRule, RequestMapItem> _mapItemsCache = {};

  bool enabled = true;

  //存储所有的请求映射规则
  List<RequestMapRule> rules = [];

  ///单例
  static Future<RequestMapManager> get instance async {
    if (_instance == null) {
      _instance = RequestMapManager._internal();
      await _instance?.reloadConfig();
    }
    return _instance!;
  }

  //添加规则
  Future<void> addRule(RequestMapRule rule, RequestMapItem item) async {
    final path = await Paths.homePath();
    String itemPath = "${separator}request_map$separator${RandomUtil.randomString(16)}.json";
    var file = File(path + itemPath);
    await file.create(recursive: true);
    final itemJson = jsonEncode(item.toJson());
    await SerialFileWriter.writeString(file, itemJson);

    rule.itemPath = itemPath;
    _mapItemsCache[rule] = item;
    rules.add(rule);

    await flushConfig();
  }

  //update rule
  Future<void> updateRule(RequestMapRule rule, RequestMapItem item) async {
    rule.updatePathReg();
    if (rule.itemPath != null) {
      final path = await Paths.homePath();
      var file = File('$path${rule.itemPath}');
      await SerialFileWriter.writeString(file, jsonEncode(item.toJson()));
    }
    _mapItemsCache[rule] = item;
    await flushConfig();
  }

  //删除规则
  Future<void> deleteRule(int index) async {
    if (index < 0 || index >= rules.length) return;
    var item = rules.removeAt(index);
    // 缓存里还挂着这个规则对应的映射内容，不清掉会一直占内存，
    // 而且下次新增规则若复用同一对象会读到陈旧内容。
    _mapItemsCache.remove(item);
    final itemPath = item.itemPath;
    if (itemPath != null && itemPath.isNotEmpty) {
      try {
        final home = await Paths.homePath();
        final file = File(home + itemPath);
        if (await file.exists()) await file.delete();
      } catch (e) {
        logger.w('删除请求映射文件失败: $itemPath', error: e);
      }
    }
    // 以前删完不落盘：rules 只在内存里移除，重启后规则全部复活。
    await flushConfig();
  }

  //根据url和类型查找匹配的规则
  RequestMapRule? findMatch(String url) {
    for (var rule in rules) {
      if (rule.match(url)) {
        return rule;
      }
    }
    return null;
  }

  Future<RequestMapItem?> getMapItem(RequestMapRule rule) async {
    if (_mapItemsCache.containsKey(rule)) {
      return _mapItemsCache[rule];
    }

    if (rule.itemPath != null) {
      final path = await Paths.homePath();
      var file = File('$path$separator${rule.itemPath}');
      if (await file.exists()) {
        var content = await file.readAsString();
        if (content.isNotEmpty) {
          try {
            var item = RequestMapItem.fromJson(jsonDecode(content));
            _mapItemsCache[rule] = item;
            return item;
          } catch (e) {
            // 映射文件被写坏/手工改过时不要让整条请求失败，按「无映射」处理。
            logger.e('请求映射文件解析失败: ${file.path}', error: e);
            return null;
          }
        }
      }
    }
    return null;
  }

  static Future<File> get _path async {
    final path = await Paths.homePath();
    var file = File('$path${Platform.pathSeparator}request_map.json');
    if (!await file.exists()) {
      await file.create();
    }
    return file;
  }

  ///重新加载配置
  Future<void> reloadConfig() async {
    List<RequestMapRule> list = [];
    var file = await _path;
    logger.d("reload request map config from ${file.path}");

    if (await file.exists()) {
      var content = await file.readAsString();
      if (content.isEmpty) {
        return;
      }
      var config = jsonDecode(content);
      enabled = config['enabled'] == true;
      for (var entry in config['list']) {
        list.add(RequestMapRule.fromJson(entry));
      }
    }
    rules = list;
    _mapItemsCache.clear();
  }

  ///保存配置
  Future<void> flushConfig() async {
    var file = await _path;
    if (!await file.exists()) {
      await file.create(recursive: true);
    }

    var config = {
      'enabled': enabled,
      'list': rules.map((e) => e.toJson()).toList(),
    };

    await SerialFileWriter.writeString(file, jsonEncode(config));
  }
}

enum RequestMapType {
  local("本地"),
  script("脚本"),
  ;

  //名称
  final String label;

  const RequestMapType(this.label);

  static RequestMapType fromName(String name) {
    return values.firstWhere((element) => element.name == name || element.label == name, orElse: () {
      logger.w('未知的请求映射类型: $name，回退到 ${values.first.name}');
      return values.first;
    });
  }
}

class RequestMapRule {
  bool enabled;
  RequestMapType type;

  String? name;
  String url;
  RegExp _urlReg;
  String? itemPath;

  RequestMapRule({this.enabled = true, this.name, required this.url, required this.type, this.itemPath})
      : _urlReg = UrlPattern.toRegExp(url);

  bool match(String url) {
    if (enabled) {
      return _urlReg.hasMatch(url);
    }
    return false;
  }

  /// 从json中创建
  factory RequestMapRule.fromJson(Map<dynamic, dynamic> map) {
    return RequestMapRule(
        enabled: map['enabled'] == true,
        name: map['name'],
        url: map['url'],
        type: RequestMapType.fromName(map['type']),
        itemPath: map['itemPath']);
  }

  void updatePathReg() {
    _urlReg = UrlPattern.toRegExp(url);
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'enabled': enabled,
      'url': url,
      'type': type.name,
      'itemPath': itemPath,
    };
  }
}

class RequestMapItem {
  String? script;

  int? statusCode;
  Map<String, String>? headers;

  //body
  String? body;

  String? bodyType;

  String? bodyFile;

  RequestMapItem({this.script, this.statusCode, this.headers, this.body, this.bodyType, this.bodyFile});

  /// 从json中创建
  factory RequestMapItem.fromJson(Map<dynamic, dynamic> map) {
    return RequestMapItem(
      script: map['script'],
      statusCode: map['statusCode'],
      headers: (map['headers'] as Map?)?.cast<String, String>(),
      body: map['body'],
      bodyType: map['bodyType'],
      bodyFile: map['bodyFile'],
    );
  }

  Map<String, Object?> toJson() {
    return {
      'script': script,
      'statusCode': statusCode,
      'headers': headers,
      'body': body,
      'bodyType': bodyType,
      'bodyFile': bodyFile,
    };
  }
}

enum MapBodyType {
  text("文本"),
  file("文件");

  final String label;

  const MapBodyType(this.label);
}
