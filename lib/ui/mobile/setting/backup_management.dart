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
    setState(() => _isLoading = true);
    try {
      final info = await BackupService.create();
      if (!mounted) return;
      FlutterToastr.show(
        '已创建备份：${info.name}（${info.items.length} 项）',
        context,
        rootNavigator: true,
        duration: 4,
      );
    } catch (e) {
      if (!mounted) return;
      FlutterToastr.show('备份失败：$e', context, rootNavigator: true, duration: 5);
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
        title: const Text(
          '备份管理',
          style: TextStyle(fontSize: 16),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt),
            onPressed: _isLoading ? null : _createBackup,
            tooltip: '立即备份（配置+证书+脚本+工作区）',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBackups,
            tooltip: '刷新',
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
                        '配置会自动备份到应用数据目录',
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
                          '${_formatFileSize(backup.size)} • ${_formatTime(backup.modified)}${index == 0 ? ' • 最新' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) =>
                              _handleAction(context, backup, value),
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
                                  Icon(Icons.delete,
                                      size: 20, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text(
                                    '删除',
                                    style: TextStyle(color: Colors.red),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认恢复'),
        content: Text(
          '恢复备份 "${backup.name}" 会覆盖当前配置，确定要继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('确定'),
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
                ? '已恢复 ${result.restored} 个文件，配置已生效'
                : '已恢复 ${result.restored} 个文件（配置未生效${result.failed > 0 ? '，${result.failed} 项失败' : ''}）',
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
          '配置已恢复',
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
          '恢复失败：${e.toString()}',
          context,
          duration: 3,
          backgroundColor: Colors.red,
        );
      }
    }
  }

  Future<void> _exportBackup(
      BuildContext context, BackupFile backup) async {
    try {
      final file = File(backup.path);
      final bytes = await file.readAsBytes();

      final outputPath = await FilePicker.saveFile(
        dialogTitle: '选择保存位置',
        fileName: backup.name,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );

      if (outputPath != null && mounted) {
        FlutterToastr.show(
          '已导出到：$outputPath',
          context,
          duration: 2,
          backgroundColor: Colors.green,
        );
      }
    } catch (e) {
      logger.e('导出备份失败', error: e, stackTrace: StackTrace.current);
      if (mounted) {
        FlutterToastr.show(
          '导出失败：${e.toString()}',
          context,
          duration: 3,
          backgroundColor: Colors.red,
        );
      }
    }
  }

  Future<void> _deleteBackup(
      BuildContext context, BackupFile backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除备份 "${backup.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
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
          '备份已删除',
          context,
          duration: 2,
          backgroundColor: Colors.green,
        );
      }
    } catch (e) {
      logger.e('删除备份失败', error: e, stackTrace: StackTrace.current);
      if (mounted) {
        FlutterToastr.show(
          '删除失败：${e.toString()}',
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

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
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
