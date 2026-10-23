import 'dart:convert';
import 'dart:io';

import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/file_read.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/serial_file_writer.dart';

class RequestCryptoManager {
  static String separator = Platform.pathSeparator;

  static RequestCryptoManager? _instance;

  RequestCryptoManager._();

  /// 初始化中的 Future：并发首次访问共用同一次加载
  ///
  /// 「判空 → await 读盘 → 赋值」在并发首访时会各自初始化一遍：后者覆盖
  /// _instance，前者手里那份已被 clear() 过 → 规则时有时无、刚加的规则不生效。
  static Future<RequestCryptoManager>? _loading;

  static Future<RequestCryptoManager> get instance async {
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

  static Future<RequestCryptoManager> _create() async {
    final config = await _loadRequestCryptoConfig();
    final manager = RequestCryptoManager._();
    await manager._reload(config);
    _instance = manager;
    return manager;
  }

  bool enabled = true;
  List<CryptoRule> rules = [];

  Future<void> _reload(Map<String, dynamic>? map) async {
    if (map == null) {
      return;
    }

    enabled = map['enabled'] == true;
    final list = map['rules'] as List<dynamic>? ?? const [];
    rules = [];
    for (final element in list) {
      try {
        rules.add(CryptoRule.fromJson(Map<String, dynamic>.from(element)));
      } catch (e) {
        logger.e('加载请求加解密配置失败 $element', error: e);
      }
    }
  }

  Future<void> reloadConfig() async {
    final config = await _loadRequestCryptoConfig();
    await _reload(config);
  }

  static Future<Map<String, dynamic>?> _loadRequestCryptoConfig() async {
    final home = await FileRead.homeDir();
    final file = File(
      '${home.path}${Platform.pathSeparator}request_crypto.json',
    );
    if (!await file.exists()) {
      return null;
    }
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      logger.i('加载请求加解密配置文件 [$file]');
      return json;
    } catch (e, stack) {
      logger.e('解析请求加解密配置失败', error: e, stackTrace: stack);
      return null;
    }
  }

  Future<void> flushConfig() async {
    final home = await FileRead.homeDir();
    final file = File(
      '${home.path}${Platform.pathSeparator}request_crypto.json',
    );
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    final json = jsonEncode(toJson());
    logger.i('刷新请求加解密配置文件 ${file.path}');
    await SerialFileWriter.writeString(file, json);
  }

  /// Get the first matching rule for the given URL and optional field name
  CryptoRule? getMatchingRule(HttpMessage message) {
    final url = message.requestUrl;
    if (url == null) return null;
    if (!enabled) return null;
    for (final rule in rules) {
      if (!rule.enabled || !rule.matches(url)) continue;
      return rule;
    }
    return null;
  }

  /// Add a new crypto rule to the manager
  Future<void> addRule(CryptoRule rule) async {
    rules.add(rule);
  }

  /// Update an existing rule at [index]
  Future<void> updateRule(int index, CryptoRule rule) async {
    if (index < 0 || index >= rules.length) return;
    rules[index] = rule;
  }

  /// Remove a single rule by index
  Future<void> removeRule(int index) async {
    if (index < 0 || index >= rules.length) return;
    rules.removeAt(index);
  }

  /// Remove multiple rules. Indexes should be sorted or will be sorted descending.
  Future<void> removeIndex(List<int> indexes) async {
    indexes.sort((a, b) => b.compareTo(a));
    for (final i in indexes) {
      if (i >= 0 && i < rules.length) {
        rules.removeAt(i);
      }
    }
  }

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'rules': rules.map((e) => e.toJson()).toList(),
  };
}

class CryptoRule {
  final String name;
  final String urlPattern;
  final String? field; // single field supported
  bool enabled;
  final CryptoKeyConfig config;

  CryptoRule({
    required this.name,
    required this.urlPattern,
    this.field,
    required this.enabled,
    required this.config,
  });

  RegExp? _urlReg;
  bool? _urlRegValid;

  bool matches(String url) {
    try {
      if (_urlReg == null) {
        _urlReg = RegExp(urlPattern);
        _urlRegValid = true;
      }
      if (_urlRegValid == true) {
        return _urlReg!.hasMatch(url);
      }
      return url.contains(urlPattern);
    } catch (_) {
      _urlRegValid = false;
      return url.contains(urlPattern);
    }
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'name': name,
      'urlPattern': urlPattern,
      'field': field,
      'enabled': enabled,
      'config': config.toJson(),
    };
    return map;
  }

  factory CryptoRule.fromJson(Map<String, dynamic> json) {
    return CryptoRule(
      name: json['name'] ?? '',
      urlPattern: json['urlPattern'] ?? '',
      field: json['field'],
      enabled: json['enabled'] ?? true,
      config: CryptoKeyConfig.fromJson(
        Map<String, dynamic>.from(json['config'] ?? {}),
      ),
    );
  }

  CryptoRule copyWith({
    String? name,
    String? urlPattern,
    String? field,
    bool? enabled,
    CryptoKeyConfig? config,
  }) {
    return CryptoRule(
      name: name ?? this.name,
      urlPattern: urlPattern ?? this.urlPattern,
      field: field ?? this.field,
      enabled: enabled ?? this.enabled,
      config: config ?? this.config,
    );
  }

  /// Legacy constructor used by UI to create a default empty AesRule
  static CryptoRule newRule() {
    return CryptoRule(
      name: '',
      urlPattern: '',
      field: '',
      enabled: true,
      config: CryptoKeyConfig.defaults(),
    );
  }
}

class CryptoKeyConfig {
  final String key;
  final String iv;
  final String ivSource; // 'manual' or 'prefix'
  final int ivPrefixLength;
  final String mode;
  final String padding;
  final int keyLength;

  const CryptoKeyConfig({
    required this.key,
    required this.iv,
    required this.ivSource,
    required this.ivPrefixLength,
    required this.mode,
    required this.padding,
    required this.keyLength,
  });

  factory CryptoKeyConfig.defaults() {
    return const CryptoKeyConfig(
      key: '',
      iv: '',
      ivSource: 'manual',
      ivPrefixLength: 16,
      mode: 'ECB',
      padding: 'PKCS7',
      keyLength: 128,
    );
  }

  bool get isReady {
    if (key.trim().isEmpty) return false;
    if (mode != 'CBC') return true;
    // for CBC, either manual IV provided or prefix mode selected
    if (ivSource == 'prefix') return true;
    return iv.trim().isNotEmpty;
  }

  CryptoKeyConfig copyWith({
    String? key,
    String? iv,
    String? ivSource,
    int? ivPrefixLength,
    String? mode,
    String? padding,
    int? keyLength,
  }) {
    return CryptoKeyConfig(
      key: key ?? this.key,
      iv: iv ?? this.iv,
      ivSource: ivSource ?? this.ivSource,
      ivPrefixLength: ivPrefixLength ?? this.ivPrefixLength,
      mode: mode ?? this.mode,
      padding: padding ?? this.padding,
      keyLength: keyLength ?? this.keyLength,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'key': key,
      'iv': iv,
      'ivSource': ivSource,
      'ivPrefixLength': ivPrefixLength,
      'mode': mode,
      'padding': padding,
      'keyLength': keyLength,
    };
  }

  factory CryptoKeyConfig.fromJson(Map<String, dynamic> json) {
    return CryptoKeyConfig(
      key: json['key'] ?? '',
      iv: json['iv'] ?? '',
      ivSource: json['ivSource'] ?? 'manual',
      ivPrefixLength: json['ivPrefixLength'] ?? 16,
      mode: json['mode'] ?? 'ECB',
      padding: json['padding'] ?? 'PKCS7',
      keyLength: json['keyLength'] ?? 128,
    );
  }
}
