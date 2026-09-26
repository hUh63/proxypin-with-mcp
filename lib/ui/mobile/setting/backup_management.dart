import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/util/backup_service.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/file_read.dart';

/// 备份管理页面 - 查看/恢复/删除配置备份
class BackupManagement extends StatefulWidget {
  const BackupManagement({super.key});

  @override
  State<StatefulWidget> createState() => _BackupManagementState();
}

class _BackupManagementState extends State<BackupManagement> {
  List<BackupFile> _backups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() => _isLoading = true);
    try {
      final separator = Platform.pathSeparator;
      final home = await FileRead.homeDir();
      final backupDir = '${home.path}${separator}proxypin_backups';
      final dir = Directory(backupDir);

      if (await dir.exists()) {
        final files = await dir.list().toList();
        final backupFiles = <BackupFile>[];

        for (var entity in files) {
          if (entity is File && entity.path.endsWith('.json')) {
            final stat = await entity.stat();
            backupFiles.add(BackupFile(
              path: entity.path,
              name: entity.path.split(separator).last,
              size: stat.size,
              modified: stat.modified,
            ));
          }
        }

        // 按修改时间倒序排序（最新的在前）
        backupFiles.sort((a, b) => b.modified.compareTo(a.modified));
        _backups = backupFiles;
      } else {
        _backups = [];
      }
    } catch (e) {
      logger.e('加载备份列表失败', error: e, stackTrace: StackTrace.current);
      _backups = [];
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 立即创建一份全量备份（配置 + 证书 + 脚本 + 各管理器数据 + 工作区）。
  ///
  /// 补的是一个很实在的缺口：以前这页只有「查看 / 恢复 / 导出 / 删除」，
  /// **没有任何创建入口**，而自动备份又因为没有任何调用点从未触发过——
  /// 也就是说备份功能整体是死的：你看到的列表永远是空的。
  Future<void> _createBackup() async {
    final localizations = AppLocalizations.of(context)!;
    setState(() => _isLoading = true);
    try {
      final info = await BackupService.create();
      if (!mounted) return;
      FlutterToastr.show(
        localizations.backupCreated(info.name, info.items.length),
        context,
        rootNavigator: true,
        duration: 4,
      );
    } catch (e) {
      if (!mounted) return;
      FlutterToastr.show(localizations.backupFailed(e.toString()), context, rootNavigator: true, duration: 5);
    } finally {
      if (mounted) setState(() => _isLoading = false);
      await _loadBackups();
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          localizations.desktopBackupManagement,
          style: const TextStyle(fontSize: 16),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt),
            onPressed: _isLoading ? null : _createBackup,
            tooltip: localizations.backupNow,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBackups,
            tooltip: localizations.refresh,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _backups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_open,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        localizations.noBackupFiles,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        localizations.backupAutoToAppDataDir,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _backups.length,
                  itemBuilder: (context, index) {
                    final backup = _backups[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: index == 0
                              ? Colors.green
                              : Colors.blue,
                          child: Icon(
                            index == 0 ? Icons.star : Icons.description,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          backup.name,
                          style: TextStyle(
                            fontWeight: index == 0 ? FontWeight.bold : null,
                          ),
                        ),
                        subtitle: Text(
                          '${_formatFileSize(backup.size)} • ${_formatTime(localizations, backup.modified)}${index == 0 ? ' • ${localizations.latestBackup}' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) =>
                              _handleAction(context, backup, value),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'restore',
                              child: Row(
                                children: [
                                  const Icon(Icons.restore, size: 20),
                                  const SizedBox(width: 8),
                                  Text(localizations.restoreBackup),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'export',
                              child: Row(
                                children: [
                                  const Icon(Icons.share, size: 20),
                                  const SizedBox(width: 8),
                                  Text(localizations.exportBackup),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  const Icon(Icons.delete,
                                      size: 20, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Text(
                                    localizations.deleteBackup,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _handleAction(
      BuildContext context, BackupFile backup, String action) async {
    switch (action) {
      case 'restore':
        await _restoreBackup(context, backup);
        break;
      case 'export':
        await _exportBackup(context, backup);
        break;
      case 'delete':
        await _deleteBackup(context, backup);
        break;
    }
  }

  Future<void> _restoreBackup(
      BuildContext context, BackupFile backup) async {
    final localizations = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.backupConfirmRestore),
        content: Text(
          localizations.backupRestoreConfirm(backup.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(localizations.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: Text(localizations.backupOk),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final file = File(backup.path);
      final jsonStr = await file.readAsString();
      final decoded = jsonDecode(jsonStr);

      // 全量备份（BackupService 生成）：含配置 + 证书 + 脚本 + 工作区
      if (decoded is Map && decoded['format'] == 'proxypin-backup') {
        final result = await BackupService.restore(file);
        if (mounted) {
          FlutterToastr.show(
            result.configApplied
                ? localizations.backupRestoredApplied(result.restored)
                : localizations.backupRestoredNotApplied(result.restored,
                    result.failed > 0 ? localizations.backupFailedSuffix(result.failed) : ''),
            context,
            rootNavigator: true,
            duration: 5,
          );
          Navigator.of(context).pop(true);
        }
        return;
      }

      // 老格式：只有一个扁平配置对象
      final newConfig = await ConfigImportExport.importConfig(jsonStr);

      // 全量应用：以前这里是逐字段复制，只搬了 18 个，MCP 局域网/保活/AI/QUIC
      // 拦截这些后来新增的配置会被整个丢掉。applyJson 与 fromJson 共用一份赋值。
      final config = await Configuration.instance;
      config.applyJson(newConfig.toJson());

      // 刷新配置
      config.flushConfig();

      if (mounted) {
        FlutterToastr.show(
          localizations.backupConfigRestored,
          context,
          duration: 2,
          backgroundColor: Colors.green,
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      logger.e('恢复备份失败', error: e, stackTrace: StackTrace.current);
      if (mounted) {
        FlutterToastr.show(
          localizations.backupRestoreFailed(e.toString()),
          context,
          duration: 3,
          backgroundColor: Colors.red,
        );
      }
    }
  }

  Future<void> _exportBackup(
      BuildContext context, BackupFile backup) async {
    final localizations = AppLocalizations.of(context)!;
    try {
      final file = File(backup.path);
      final bytes = await file.readAsBytes();

      final outputPath = await FilePicker.saveFile(
        dialogTitle: localizations.backupChooseSaveLocation,
        fileName: backup.name,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );

      if (outputPath != null && mounted) {
        FlutterToastr.show(
          localizations.backupExportedTo(outputPath),
          context,
          duration: 2,
          backgroundColor: Colors.green,
        );
      }
    } catch (e) {
      logger.e('导出备份失败', error: e, stackTrace: StackTrace.current);
      if (mounted) {
        FlutterToastr.show(
          localizations.backupExportFailed(e.toString()),
          context,
          duration: 3,
          backgroundColor: Colors.red,
        );
      }
    }
  }

  Future<void> _deleteBackup(
      BuildContext context, BackupFile backup) async {
    final localizations = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.backupConfirmDelete),
        content: Text(localizations.backupDeleteConfirm(backup.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(localizations.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(localizations.deleteBackup),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final file = File(backup.path);
      await file.delete();
      await _loadBackups();

      if (mounted) {
        FlutterToastr.show(
          localizations.backupDeleted,
          context,
          duration: 2,
          backgroundColor: Colors.green,
        );
      }
    } catch (e) {
      logger.e('删除备份失败', error: e, stackTrace: StackTrace.current);
      if (mounted) {
        FlutterToastr.show(
          localizations.backupDeleteFailed(e.toString()),
          context,
          duration: 3,
          backgroundColor: Colors.red,
        );
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatTime(AppLocalizations localizations, DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return localizations.backupJustNow;
    if (diff.inHours < 1) return localizations.quicMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return localizations.quicHoursAgo(diff.inHours);
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }
}

class BackupFile {
  final String path;
  final String name;
  final int size;
  final DateTime modified;

  BackupFile({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });
}
