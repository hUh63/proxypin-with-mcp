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

import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/path.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一份备份的概览信息。
class BackupFileInfo {
  final File file;
  final DateTime time;
  final int sizeBytes;
  final List<String> items;
  final List<String> skipped;

  BackupFileInfo({
    required this.file,
    required this.time,
    required this.sizeBytes,
    this.items = const [],
    this.skipped = const [],
  });

  String get name => file.uri.pathSegments.isEmpty ? file.path : file.uri.pathSegments.last;

  /// 是否含配置以外的数据（证书 / 脚本 / 工作区）
  bool get full => items.any((e) => e != 'config.cnf');
}

/// 恢复结果
class BackupRestoreResult {
  final int restored;
  final int failed;
  final bool configApplied;
  final String? error;

  BackupRestoreResult({
    required this.restored,
    required this.failed,
    required this.configApplied,
    this.error,
  });
}

/// 备份服务。
///
/// 说清楚和旧实现的关系：原先的「自动备份」只把**配置 JSON** 存下来，而且
/// 那个 `autoBackupConfig()` **全仓没有任何调用点**——开关是摆设，从未触发过。
/// 恢复端还有两个问题：移动端逐字段复制（40+ 个字段只搬了 18 个），
/// 桌面端把 `importConfig` 的返回值丢掉（等于什么都没做）。
///
/// 这里补齐三件事：**真的会触发**、**备的东西是完整的**、**恢复是真恢复**。
///
/// 打包格式用「单个 JSON + base64」，而不是 zip：一是没有编解码 API 变动的风险，
/// 二是这个文件本身就是自描述的（改配置、传云端都方便）。
///
/// 不备份历史抓包流水（体积大、且历史本身有独立导出），只备份
/// **配置 + 证书 + 脚本 + 各管理器的持久化数据 + 工作区**。
class BackupService {
  BackupService._();

  static const String _dirName = 'proxypin_backups';
  static const String _lastAutoKey = 'lastAutoBackupAt';

  /// 最多保留多少份（自动备份超出后从最旧的开始删）
  static const int maxBackups = 10;

  /// 单个备份的总内联上限，超过就不再收后续文件（记进 skipped）
  static const int inlineLimitBytes = 24 * 1024 * 1024;

  /// 备份的顶层文件后缀（配置文件、证书、私钥、p12、管理器持久化数据）
  static const List<String> _includeSuffixes = ['.json', '.cnf', '.crt', '.pem', '.p12'];

  /// 备份的目录（递归）
  static const List<String> _includeDirs = ['scripts', 'workspaces'];

  /// 明确排除的顶层条目
  static const List<String> _excludeNames = ['proxypin_backups', 'logs', 'history', 'proxypin_data'];

  // ---------- 目录 ----------

  static Future<Directory> directory() async {
    final home = await Paths.homePath();
    final dir = Directory('$home${Platform.pathSeparator}$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 收集要备份的东西：返回 相对路径 → 绝对文件
  static Future<Map<String, File>> _collect() async {
    final home = Directory(await Paths.homePath());
    final out = <String, File>{};

    await for (final entity in home.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.isEmpty ? entity.path : entity.uri.pathSegments.last;
      if (_excludeNames.contains(name)) {
        continue;
      }
      if (!_includeSuffixes.any(name.toLowerCase().endsWith)) {
        continue;
      }
      out[name] = entity;
    }

    for (final dirName in _includeDirs) {
      final dir = Directory('${home.path}${Platform.pathSeparator}$dirName');
      if (!await dir.exists()) {
        continue;
      }
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final rel = '$dirName/${entity.path.substring(dir.path.length + 1)}';
        out[rel] = entity;
      }
    }
    return out;
  }

  // ---------- 创建 ----------

  /// 创建一份全量备份，返回备份文件。
  static Future<BackupFileInfo> create() async {
    final config = await Configuration.instance;
    final files = <String, String>{};
    final items = <String>[];
    final skipped = <String>[];
    var total = 0;

    for (final entry in (await _collect()).entries) {
      try {
        final bytes = await entry.value.readAsBytes();
        if (total + bytes.length > inlineLimitBytes) {
          skipped.add(entry.key);
          continue;
        }
        total += bytes.length;
        files[entry.key] = base64Encode(bytes);
        items.add(entry.key);
      } catch (e) {
        skipped.add(entry.key);
        logger.w('[Backup] skip ${entry.key}: $e');
      }
    }

    final payload = <String, dynamic>{
      'format': 'proxypin-backup',
      'version': 2,
      'createdAt': DateTime.now().toIso8601String(),
      'appVersion': '1.3.2',
      // 配置单独存成 JSON（不是 base64），方便人工查看和传给云端
      'config': json.decode(config.exportConfig()),
      'files': files,
      if (items.isNotEmpty) 'items': items,
      if (skipped.isNotEmpty) 'skipped': skipped,
    };

    final dir = await directory();
    final ts = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final file = File('${dir.path}${Platform.pathSeparator}backup_$ts.json');
    await file.writeAsString(json.encode(payload));
    await _cleanupOld();

    final size = await file.length();
    logger.i('[Backup] created $file (${items.length} files, $size bytes, skipped=${skipped.length})');
    return BackupFileInfo(
      file: file,
      time: DateTime.now(),
      sizeBytes: size,
      items: items,
      skipped: skipped,
    );
  }

  /// 列出已有备份（新建的在前）。
  static Future<List<BackupFileInfo>> list() async {
    final dir = await directory();
    final out = <BackupFileInfo>[];
    try {
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) {
          continue;
        }
        final stat = await entity.stat();
        final name = entity.uri.pathSegments.isEmpty ? entity.path : entity.uri.pathSegments.last;
        out.add(BackupFileInfo(
          file: entity,
          time: stat.modified,
          sizeBytes: stat.size,
          items: _tagsOf(name),
        ));
      }
    } catch (e) {
      logger.e('[Backup] list failed: $e');
    }
    out.sort((a, b) => b.time.compareTo(a.time));
    return out;
  }

  /// 从文件名猜一下内容标签（仅用于列表展示，不做判断依据）
  static List<String> _tagsOf(String name) {
    if (name.contains('proxypin_config_')) {
      return const ['config.cnf'];
    }
    return const ['full'];
  }

  // ---------- 恢复 ----------

  /// 从备份文件恢复。返回恢复结果（含失败计数与配置是否生效）。
  static Future<BackupRestoreResult> restore(File file) async {
    final raw = await file.readAsString();
    final decoded = json.decode(raw);
    if (decoded is! Map) {
      return BackupRestoreResult(restored: 0, failed: 0, configApplied: false, error: '不是合法的备份文件');
    }

    final home = await Paths.homePath();
    var restored = 0;
    var failed = 0;

    // 1) 文件
    final files = decoded['files'];
    if (files is Map) {
      for (final entry in files.entries) {
        final rel = '${entry.key}';
        // 防路径穿越：备份文件可能被篡改，绝不能让它写到数据目录之外
        if (rel.contains('..') || rel.startsWith('/') || rel.contains('\\..')) {
          failed++;
          continue;
        }
        try {
          final target = File('$home${Platform.pathSeparator}$rel');
          await target.parent.create(recursive: true);
          await target.writeAsBytes(base64Decode('${entry.value}'));
          restored++;
        } catch (e) {
          logger.w('[Backup] restore $rel failed: $e');
          failed++;
        }
      }
    }

    // 2) 配置
    var configApplied = false;
    final configJson = decoded['config'];
    if (configJson is Map) {
      try {
        final config = await Configuration.instance;
        config.applyJson(Map<String, dynamic>.from(configJson));
        await config.flushConfig();
        configApplied = true;
      } catch (e) {
        logger.e('[Backup] apply config failed: $e');
        failed++;
      }
    }

    logger.i('[Backup] restored $restored files (failed=$failed, config=$configApplied)');
    return BackupRestoreResult(
      restored: restored,
      failed: failed,
      configApplied: configApplied,
    );
  }

  /// 删除一份备份。
  static Future<void> remove(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      logger.e('[Backup] remove failed: $e');
    }
  }

  // ---------- 自动备份 ----------

  /// 上一次自动备份的时间
  static Future<DateTime?> lastAutoBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastAutoKey);
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  /// 到点就自动备份一次。
  ///
  /// 这是旧实现缺的那一环——`autoBackupConfig()` 有实现、有开关，却没有任何
  /// 调用点，所以「自动备份」从来没发生过。现在由启动流程调用它。
  ///
  /// 返回新建的备份（没到点或未开启则返回 null）。
  static Future<BackupFileInfo?> autoBackupIfDue(Configuration config) async {
    if (!config.autoBackupEnabled) {
      return null;
    }
    final intervalHours = config.autoBackupIntervalHours <= 0 ? 24 : config.autoBackupIntervalHours;
    final last = await lastAutoBackup();
    final now = DateTime.now();
    if (last != null && now.difference(last).inHours < intervalHours) {
      return null;
    }
    try {
      final info = await create();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastAutoKey, now.toIso8601String());
      return info;
    } catch (e) {
      logger.e('[Backup] auto backup failed: $e');
      return null;
    }
  }

  /// 启动时调用：等冷启动忙完再读配置，到点就备份一次。
  ///
  /// 故意延迟几秒：冷启动时各 manager 都在抢 IO，备份是后台行为，没必要挤进去。
  /// 失败一概吞掉——备份出问题不该影响应用使用。
  static Future<void> autoBackupNow() async {
    await Future.delayed(const Duration(seconds: 8));
    try {
      final config = await Configuration.instance;
      final info = await autoBackupIfDue(config);
      if (info != null) {
        logger.i('[Backup] auto backup done: ${info.name}');
      }
    } catch (e) {
      logger.w('[Backup] auto backup skipped: $e');
    }
  }

  /// 清掉超出保留数量的旧备份（只删本服务生成的 `backup_*.json`）。
  static Future<void> _cleanupOld() async {
    try {
      final dir = await directory();
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          files.add(entity);
        }
      }
      if (files.length <= maxBackups) {
        return;
      }
      final stats = <MapEntry<File, DateTime>>[];
      for (final f in files) {
        stats.add(MapEntry(f, (await f.stat()).modified));
      }
      stats.sort((a, b) => a.value.compareTo(b.value));
      for (var i = 0; i < stats.length - maxBackups; i++) {
        await stats[i].key.delete();
      }
    } catch (e) {
      logger.w('[Backup] cleanup failed: $e');
    }
  }
}
