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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/util/file_read.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/system_proxy.dart';
import 'package:proxypin/utils/platform.dart';

class Configuration {
  ///代理相关配置
  int port = 9099;

  //是否启用https抓包
  bool enableSsl = Platforms.isMobile();

  //是否设置系统代理
  bool enableSystemProxy = true;

  //代理忽略域名
  String proxyPassDomains = SystemProxy.proxyPassDomains;

  //enabled socks5 proxy
  bool enableSocks5 = true;

  //外部代理
  ProxyInfo? externalProxy;

  //白名单应用
  List<String> appWhitelist = [];

  //白名单应用是否启用
  bool appWhitelistEnabled = true;

  //应用黑名单
  List<String>? appBlacklist;

  //远程连接 不持久化保存
  String? remoteHost;

  bool enabledHttp2 = false; // 是否启用http2

  //历史记录缓存时间
  int historyCacheTime = 0;

  //MCP Server 端口
  int mcpPort = 9010;

  //MCP Server 是否启用
  bool mcpEnabled = true;

  //MCP Server 是否随应用启动自动启动
  bool mcpAutoStart = true;

  //MCP 工具启用状态（工具名 -> 是否启用），默认全部启用
  Map<String, bool> mcpToolsEnabled = {};

  //默认是否启动
  bool startup = false;

  //AI 分析（OpenAI 兼容接口，上游 #582）
  bool aiEnabled = false;
  String aiBaseUrl = "https://api.openai.com/v1";
  String aiApiKey = "";
  String aiModel = "gpt-4o-mini";

  //AI Agent 模式：允许 AI 自动调用 ProxyPin 功能（MCP 工具），关闭时仅对话
  bool aiAgentEnabled = false;
  int aiAgentMaxRounds = 3; // 单次问答最大工具循环轮数
  String aiAgentExtraPrompt = ""; // 用户附加的 Agent 系统指令

  //QUIC 拦截（Android VPN 层丢弃 UDP:443，强制应用回落 TCP HTTP 以便可抓包，上游 #489）
  bool blockQuic = true;

  //QUIC 元数据探测：VPN 捕获 UDP:443 首包解密 Initial 提取 SNI/版本等连接元数据（上游 #489）
  bool quicProbeEnabled = true;

  //双向认证 mTLS（与上游服务器 TLS 握手时提供客户端证书，上游 #366）
  bool mtlsEnabled = false;
  String? mtlsChainPath; // 客户端证书链 PEM
  String? mtlsKeyPath;   // 客户端私钥 PEM（未加密）

  //自动备份配置
  bool autoBackupEnabled = true; // 是否启用自动备份
  int autoBackupIntervalHours = 24; // 自动备份间隔（小时）

  Configuration._();

  /// 单例
  static Configuration? _instance;

  static Future<Configuration> get instance async {
    if (_instance == null) {
      try {
        var loadConfig = await _loadConfig();
        _instance = Configuration.fromJson(loadConfig);
      } catch (e) {
        logger.e('初始化配置失败', error: e, stackTrace: StackTrace.current);
        _instance = Configuration._();
      }
    }
    return _instance!;
  }

  /// 同步获取已加载的配置（未加载时返回 null，用于非异步场景）
  static Configuration? get loaded => _instance;

  /// 加载配置
  Configuration.fromJson(Map<String, dynamic> config) {
    port = config['port'] ?? port;
    enableSsl = config['enableSsl'] == true;
    startup = config['startup'] ?? Platforms.isDesktop();
    aiEnabled = config['aiEnabled'] ?? false;
    aiBaseUrl = config['aiBaseUrl'] ?? "https://api.openai.com/v1";
    aiApiKey = config['aiApiKey'] ?? "";
    aiModel = config['aiModel'] ?? "gpt-4o-mini";
    aiAgentEnabled = config['aiAgentEnabled'] ?? false;
    aiAgentMaxRounds = config['aiAgentMaxRounds'] ?? 3;
    aiAgentExtraPrompt = config['aiAgentExtraPrompt'] ?? "";
    blockQuic = config['blockQuic'] ?? true;
    quicProbeEnabled = config['quicProbeEnabled'] ?? true;
    mtlsEnabled = config['mtlsEnabled'] ?? false;
    mtlsChainPath = config['mtlsChainPath'];
    mtlsKeyPath = config['mtlsKeyPath'];
    enableSystemProxy = config['enableSystemProxy'] ?? (config['enableDesktop'] ?? true);
    enableSocks5 = config['enableSocks5'] ?? true;
    enabledHttp2 = config['enabledHttp2'] ?? false;

    proxyPassDomains = config['proxyPassDomains'] ?? SystemProxy.proxyPassDomains;
    historyCacheTime = config['historyCacheTime'] ?? 0;
    mcpPort = config['mcpPort'] ?? 9010;
    mcpEnabled = config['mcpEnabled'] ?? true;
    mcpAutoStart = config['mcpAutoStart'] ?? true;
    if (config['mcpToolsEnabled'] is Map) {
      mcpToolsEnabled = (config['mcpToolsEnabled'] as Map)
          .map((key, value) => MapEntry(key.toString(), value == true));
    }
    if (config['externalProxy'] != null) {
      externalProxy = ProxyInfo.fromJson(config['externalProxy']);
    }
    appWhitelist = List<String>.from(config['appWhitelist'] ?? []);
    appWhitelistEnabled = config['appWhitelistEnabled'] ?? true;
    appBlacklist = config['appBlacklist'] == null ? null : List<String>.from(config['appBlacklist']);
    HostFilter.whitelist.load(config['whitelist']);
    HostFilter.blacklist.load(config['blacklist']);
    autoBackupEnabled = config['autoBackupEnabled'] ?? true;
    autoBackupIntervalHours = config['autoBackupIntervalHours'] ?? 24;
  }

  /// 配置文件
  static Future<File> configFile() async {
    var separator = Platform.pathSeparator;
    var home = await FileRead.homeDir();
    return File("${home.path}${separator}config.cnf");
  }

  /// 刷新配置文件
  Future<void> flushConfig() async {
    var file = await configFile();
    var exists = await file.exists();
    if (!exists) {
      file = await file.create(recursive: true);
    }
    HostFilter.whitelist.toJson();
    HostFilter.blacklist.toJson();
    var json = jsonEncode(toJson());
    logger.d('Refresh configuration file $runtimeType ${toJson()}');
    file.writeAsString(json);
  }

  /// 加载配置文件
  static Future<Map<String, dynamic>> _loadConfig() async {
    var file = await configFile();
    var exits = await file.exists();
    if (!exits) {
      return {};
    }

    Map<String, dynamic> config = jsonDecode(await file.readAsString());
    logger.i('加载配置文件 [$file]');
    return config;
  }

  Map<String, dynamic> toJson() {
    return {
      'port': port,
      'enableSsl': enableSsl,
      'startup': startup,
      'aiEnabled': aiEnabled,
      'aiBaseUrl': aiBaseUrl,
      'aiApiKey': aiApiKey,
      'aiModel': aiModel,
      'aiAgentEnabled': aiAgentEnabled,
      'aiAgentMaxRounds': aiAgentMaxRounds,
      if (aiAgentExtraPrompt.isNotEmpty) 'aiAgentExtraPrompt': aiAgentExtraPrompt,
      'blockQuic': blockQuic,
      'quicProbeEnabled': quicProbeEnabled,
      'mtlsEnabled': mtlsEnabled,
      if (mtlsChainPath != null) 'mtlsChainPath': mtlsChainPath,
      if (mtlsKeyPath != null) 'mtlsKeyPath': mtlsKeyPath,
      'enableSystemProxy': enableSystemProxy,
      'enableSocks5': enableSocks5,
      'proxyPassDomains': proxyPassDomains,
      'externalProxy': externalProxy?.toJson(),
      'appWhitelist': appWhitelist,
      'appWhitelistEnabled': appWhitelistEnabled,
      'appBlacklist': appBlacklist,
      'historyCacheTime': historyCacheTime,
      'mcpPort': mcpPort,
      'mcpEnabled': mcpEnabled,
      'mcpAutoStart': mcpAutoStart,
      'mcpToolsEnabled': mcpToolsEnabled,
      'enabledHttp2': enabledHttp2,
      'autoBackupEnabled': autoBackupEnabled,
      'autoBackupIntervalHours': autoBackupIntervalHours,
      'whitelist': HostFilter.whitelist.toJson(),
      'blacklist': HostFilter.blacklist.toJson(),
    };
  }
}

/// 导出配置到 JSON 字符串（用于备份/分享）
extension ConfigurationExport on Configuration {
  String exportConfig() {
    return jsonEncode(toJson());
  }
}

/// 配置导入工具类
class ConfigImportExport {
  /// 从 JSON 字符串导入配置
  static Future<Configuration> importConfig(String jsonStr) async {
    try {
      Map<String, dynamic> config = jsonDecode(jsonStr);
      return Configuration.fromJson(config);
    } catch (e) {
      logger.e('导入配置失败', error: e, stackTrace: StackTrace.current);
      rethrow;
    }
  }

  /// 导出配置文件到指定路径
  static Future<String> exportConfigToFile(String? customPath) async {
    final config = await Configuration.instance;
    final jsonStr = config.exportConfig();
    
    String targetPath;
    if (customPath != null && customPath.isNotEmpty) {
      targetPath = customPath;
    } else {
      final separator = Platform.pathSeparator;
      final home = await FileRead.homeDir();
      final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      targetPath = '${home.path}${separator}proxypin_config_$timestamp.json';
    }
    
    final file = File(targetPath);
    await file.create(recursive: true);
    await file.writeAsString(jsonStr);
    logger.i('配置已导出到：$targetPath');
    return targetPath;
  }

  /// 从文件导入配置
  static Future<Configuration> importConfigFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('配置文件不存在', filePath);
    }
    final jsonStr = await file.readAsString();
    return importConfig(jsonStr);
  }

  /// 自动备份配置（中期优化）
  /// 备份到应用数据目录，保留最近 7 份备份
  static Future<String> autoBackupConfig() async {
    try {
      final config = await Configuration.instance;
      final jsonStr = config.exportConfig();
      
      final separator = Platform.pathSeparator;
      final home = await FileRead.homeDir();
      final backupDir = '${home.path}${separator}proxypin_backups';
      final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final backupPath = '$backupDir${separator}proxypin_config_$timestamp.json';
      
      // 创建备份目录
      final dir = Directory(backupDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 写入备份文件
      final file = File(backupPath);
      await file.create(recursive: true);
      await file.writeAsString(jsonStr);
      
      // 清理旧备份（保留最近 7 份）
      await _cleanupOldBackups(backupDir, maxBackups: 7);
      
      logger.i('配置自动备份：$backupPath');
      return backupPath;
    } catch (e) {
      logger.e('自动备份配置失败', error: e, stackTrace: StackTrace.current);
      rethrow;
    }
  }

  /// 清理旧备份文件
  static Future<void> _cleanupOldBackups(String backupDir, {int maxBackups = 7}) async {
    try {
      final dir = Directory(backupDir);
      if (!await dir.exists()) return;
      
      final files = await dir.list().toList();
      final configFiles = files
          .whereType<File>()
          .where((f) => f.path.contains('proxypin_config_'))
          .toList();
      
      if (configFiles.length > maxBackups) {
        // 按修改时间排序，删除最旧的文件
        configFiles.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
        
        final toDelete = configFiles.length - maxBackups;
        for (var i = 0; i < toDelete; i++) {
          await configFiles[i].delete();
          logger.d('删除旧备份：${configFiles[i].path}');
        }
      }
    } catch (e) {
      logger.w('清理旧备份失败', error: e);
    }
  }
}

/// 配置自动保存（MCP 自动化第一阶段）
/// 配置变更时自动保存，防止配置丢失
class ConfigAutoSave {
  static Timer? _saveTimer;
  static bool _enabled = true;
  
  /// 启用自动保存
  static void enable() {
    _enabled = true;
  }
  
  /// 禁用自动保存
  static void disable() {
    _enabled = false;
    _saveTimer?.cancel();
  }
  
  /// 配置变更时调用（防抖 2 秒）
  static void markChanged() {
    if (!_enabled) return;
    
    _saveTimer?.cancel();
    _saveTimer = Timer(Duration(seconds: 2), () async {
      try {
        final config = await Configuration.instance;
        await config.flushConfig();
        logger.d('配置自动保存成功');
      } catch (e) {
        logger.e('配置自动保存失败', error: e);
      }
    });
  }
}
