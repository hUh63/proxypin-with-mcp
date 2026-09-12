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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('备份管理'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBackups,
            tooltip: '刷新',
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _openBackupFolder,
            tooltip: '打开备份目录',
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
                        '暂无备份文件',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '配置会自动备份到用户目录',
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
                          '${_formatFileSize(backup.size)} • ${_formatTime(backup.modified)}${index == 0 ? ' • 最新' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) => _handleAction(context, backup, value),
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'restore',
                              child: Row(
                                children: [
                                  Icon(Icons.restore, size: 20),
                                  SizedBox(width: 8),
                                  Text('恢复'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'view',
                              child: Row(
                                children: [
                                  Icon(Icons.visibility, size: 20),
                                  SizedBox(width: 8),
                                  Text('查看'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'export',
                              child: Row(
                                children: [
                                  Icon(Icons.share, size: 20),
                                  SizedBox(width: 8),
                                  Text('导出'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, size: 20, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('删除', style: TextStyle(color: Colors.red)),
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
        const SnackBar(content: Text('备份目录不存在')),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认恢复'),
        content: Text('确定要恢复备份文件 "${backup.name}" 吗？\n\n当前配置将被覆盖。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('恢复'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final content = await File(backup.path).readAsString();
        await ConfigImportExport.importConfig(content);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('备份已恢复')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('恢复失败：$e')),
          );
        }
      }
    }
  }

  Future<void> _viewBackup(BuildContext context, _BackupFile backup) async {
    try {
      final content = await File(backup.path).readAsString();
      if (!context.mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('查看备份：${backup.name}'),
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
              child: const Text('关闭'),
            ),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制到剪贴板')),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('复制'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('查看失败：$e')),
        );
      }
    }
  }

  Future<void> _exportBackup(BuildContext context, _BackupFile backup) async {
    final content = await File(backup.path).readAsString();
    final result = await FilePicker.saveFile(
      dialogTitle: '导出备份文件',
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
            const SnackBar(content: Text('导出成功')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导出失败：$e')),
          );
        }
      }
    }
  }

  Future<void> _deleteBackup(BuildContext context, _BackupFile backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除备份文件 "${backup.name}" 吗？\n\n此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
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
            const SnackBar(content: Text('备份已删除')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败：$e')),
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
