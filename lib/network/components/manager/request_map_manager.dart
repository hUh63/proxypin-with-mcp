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
  /// 初始化中的 Future：并发首次访问共用同一次加载
  ///
  /// 「判空 → await 读盘 → 赋值」在并发首访时会各自初始化一遍：后一个实例覆盖
  /// 前一个，而调用方可能已经拿到旧实例 —— 表现为规则列表被清空/重复、刚加的
  /// 规则时有时无（这些 getter 都跑在每条请求的匹配路径上）。
  static Future<RequestMapManager>? _loading;

  static Future<RequestMapManager> get instance async {
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

  static Future<RequestMapManager> _create() async {
    final manager = RequestMapManager._internal();
    await manager.reloadConfig();
    _instance = manager;
    return manager;
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

    final itemPath = rule.itemPath;
    if (itemPath == null) return null;

    // 整段包 try：文件被删、内容不是合法 UTF-8、homePath 解析失败都会抛异常，
    // 而本方法跑在转发主路径上，抛出去等于让这条请求直接失败（应视为「无映射」）。
    try {
      final path = await Paths.homePath();
      var file = File('$path$separator$itemPath');
      if (!await file.exists()) return null;
      var content = await file.readAsString();
      if (content.isEmpty) return null;
      var item = RequestMapItem.fromJson(jsonDecode(content));
      _mapItemsCache[rule] = item;
      return item;
    } catch (e) {
      // 映射文件被写坏/手工改过/读不出来时不要让整条请求失败，按「无映射」处理。
      logger.e('请求映射文件读取或解析失败: $itemPath', error: e);
      return null;
    }
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
      final config = jsonDecode(content);
      if (config is! Map) {
        logger.w('request_map.json 格式异常（不是对象），本次不加载');
        return;
      }
      // 旧版本保存的配置可能没有 enabled 字段：缺省视为启用，
      // 否则升级后所有映射规则会静默失效（与 hosts/重写规则的约定保持一致）。
      enabled = config['enabled'] != false;
      final rawList = config['list'];
      if (rawList is List) {
        for (final entry in rawList) {
          if (entry is! Map) continue;
          try {
            list.add(RequestMapRule.fromJson(entry));
          } catch (e) {
            logger.w('跳过无法解析的请求映射规则', error: e);
          }
        }
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
    final url = map['url'];
    if (url is! String || url.isEmpty) {
      throw const FormatException('request map rule missing url');
    }
    return RequestMapRule(
        // 缺 enabled 字段视为启用（旧版本不写这个键）
        enabled: map['enabled'] != false,
        name: map['name']?.toString(),
        url: url,
        type: RequestMapType.fromName('${map['type']}'),
        itemPath: map['itemPath']?.toString());
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
    // 映射文件可能被手工编辑过：statusCode 写成 "200"、headers 值写成数字
    // 都很常见，裸强转会抛 TypeError 让整条映射失效（请求直接打到真实后端）。
    final rawStatus = map['statusCode'];
    final statusCode = rawStatus is num ? rawStatus.toInt() : int.tryParse('${rawStatus ?? ''}');
    Map<String, String>? headers;
    final rawHeaders = map['headers'];
    if (rawHeaders is Map) {
      headers = {};
      rawHeaders.forEach((k, v) {
        final value = v is List ? v.join(',') : '${v ?? ''}';
        headers!['$k'] = value;
      });
    }
    return RequestMapItem(
      script: map['script']?.toString(),
      statusCode: statusCode,
      headers: headers,
      body: map['body']?.toString(),
      bodyType: map['bodyType']?.toString(),
      bodyFile: map['bodyFile']?.toString(),
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
