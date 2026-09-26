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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/util/backup_service.dart';
import 'package:proxypin/network/util/file_read.dart';
import 'package:proxypin/network/util/logger.dart';

/// 桌面端备份管理页面
class DesktopBackupManagement extends StatefulWidget {
  final Configuration configuration;

  const DesktopBackupManagement({super.key, required this.configuration});

  @override
  State<DesktopBackupManagement> createState() => _DesktopBackupManagementState();
}

class _BackupFile {
  final String path;
  final String name;
  final int size;
  final DateTime modified;

  _BackupFile({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });
}

class _DesktopBackupManagementState extends State<DesktopBackupManagement> {
  List<_BackupFile> _backups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() => _isLoading = true);
    try {
      // 与写入端（Configuration 自动备份）保持一致：备份位于数据目录（~/.proxypin，便携模式下为程序目录）下的 proxypin_backups
      final home = await FileRead.homeDir();
      final backupDir = Directory('${home.path}${Platform.pathSeparator}proxypin_backups');

      if (await backupDir.exists()) {
        final files = await backupDir.list().toList();
        final backupFiles = <_BackupFile>[];

        for (var entity in files) {
          if (entity is File && entity.path.endsWith('.json')) {
            final stat = await entity.stat();
            backupFiles.add(_BackupFile(
              path: entity.path,
              name: entity.path.split(Platform.pathSeparator).last,
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

  /// 立即创建一份全量备份（配置 + 证书 + 脚本 + 管理器数据 + 工作区）。
  ///
  /// 补的缺口：这页原先只有查看/恢复/导出/删除，**没有创建入口**，而自动备份
  /// 又因没有任何调用点从未触发——备份列表永远是空的。
  Future<void> _createBackup() async {
    final localizations = AppLocalizations.of(context)!;
    setState(() => _isLoading = true);
    try {
      final info = await BackupService.create();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.backupCreated(info.name, info.items.length))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(localizations.backupFailed(e.toString()))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
      await _loadBackups();
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.desktopBackupManagement),
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
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _openBackupFolder,
            tooltip: localizations.openBackupFolder,
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
                        localizations.autoBackupToUserDir,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _backups.length,
                  itemBuilder: (context, index) {
                    final backup = _backups[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: index == 0 ? Colors.green : Colors.blue,
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
                          '${_formatFileSize(backup.size)} • ${_formatTime(backup.modified)}${index == 0 ? ' • ${localizations.latestBackup}' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) => _handleAction(context, backup, value),
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
                              value: 'view',
                              child: Row(
                                children: [
                                  const Icon(Icons.visibility, size: 20),
                                  const SizedBox(width: 8),
                                  Text(localizations.viewBackup),
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
                                  const Icon(Icons.delete, size: 20, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Text(localizations.deleteBackup,
                                      style: const TextStyle(color: Colors.red)),
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

  Future<void> _openBackupFolder() async {
    final localizations = AppLocalizations.of(context)!;
    // 与写入端保持一致：备份目录位于数据目录下的 proxypin_backups
    final home = await FileRead.homeDir();
    final backupDir = '${home.path}${Platform.pathSeparator}proxypin_backups';
    final dir = Directory(backupDir);

    if (await dir.exists()) {
      // 在文件管理器中打开
      if (Platform.isWindows) {
        await Process.run('explorer', [backupDir]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [backupDir]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [backupDir]);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.backupDirNotFound)),
      );
    }
  }

  void _handleAction(BuildContext context, _BackupFile backup, String action) async {
    switch (action) {
      case 'restore':
        await _restoreBackup(context, backup);
        break;
      case 'view':
        await _viewBackup(context, backup);
        break;
      case 'export':
        await _exportBackup(context, backup);
        break;
      case 'delete':
        await _deleteBackup(context, backup);
        break;
    }
  }

  Future<void> _restoreBackup(BuildContext context, _BackupFile backup) async {
    final localizations = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.backupConfirmRestore),
        content: Text(localizations.backupRestoreConfirmDesktop(backup.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localizations.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text(localizations.restoreBackup),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final file = File(backup.path);
        final content = await file.readAsString();
        final decoded = jsonDecode(content);

        // 全量备份（BackupService 生成）含配置 + 证书 + 脚本 + 工作区，走多文件恢复。
        // 注意不能直接丢给 importConfig —— 顶层不是扁平配置对象，那样会解析成
        // 一份「全是默认值」的配置并覆盖掉用户设置。
        if (decoded is Map && decoded['format'] == 'proxypin-backup') {
          final result = await BackupService.restore(file);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(localizations.backupRestoredSummary(
                  result.restored,
                  result.configApplied ? localizations.backupAppliedSuffix : '',
                  result.failed > 0 ? localizations.backupFailedSuffix(result.failed) : '')),
            ));
          }
          return;
        }

        final parsed = await ConfigImportExport.importConfig(content);
        // 以前这里把 importConfig 的返回值丢掉了 —— 它只是「构造一个新对象」，
        // 不改单例，所以「恢复」其实什么都没做，却还提示了成功。
        widget.configuration.applyJson(parsed.toJson());
        await widget.configuration.flushConfig();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizations.backupRestored)),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizations.backupRestoreFailed(e.toString()))),
          );
        }
      }
    }
  }

  Future<void> _viewBackup(BuildContext context, _BackupFile backup) async {
    final localizations = AppLocalizations.of(context)!;
    try {
      final content = await File(backup.path).readAsString();
      if (!context.mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(localizations.backupViewTitle(backup.name)),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: SingleChildScrollView(
              child: SelectableText(
                content,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(localizations.close),
            ),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(localizations.backupCopied)),
                );
              },
              icon: const Icon(Icons.copy),
              label: Text(localizations.copy),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.backupViewFailed(e.toString()))),
        );
      }
    }
  }

  Future<void> _exportBackup(BuildContext context, _BackupFile backup) async {
    final localizations = AppLocalizations.of(context)!;
    final content = await File(backup.path).readAsString();
    final result = await FilePicker.saveFile(
      dialogTitle: localizations.backupExportDialogTitle,
      fileName: backup.name,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: utf8.encode(content),
    );

    if (result != null) {
      try {
        await File(result.path).writeAsBytes(utf8.encode(content));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizations.backupExportSuccess)),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizations.backupExportFailed(e.toString()))),
          );
        }
      }
    }
  }

  Future<void> _deleteBackup(BuildContext context, _BackupFile backup) async {
    final localizations = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.backupConfirmDelete),
        content: Text(localizations.backupDeleteConfirmDesktop(backup.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localizations.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(localizations.deleteBackup),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await File(backup.path).delete();
        await _loadBackups();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizations.backupDeleted)),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizations.backupDeleteFailed(e.toString()))),
          );
        }
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatTime(DateTime time) {
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
