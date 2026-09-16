import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/desktop/setting/backup_management.dart';

/// 桌面端配置管理页面 - 导入/导出配置
class DesktopConfigManagement extends StatefulWidget {
  final ProxyServer proxyServer;

  const DesktopConfigManagement({
    super.key,
    required this.proxyServer,
  });

  @override
  State<DesktopConfigManagement> createState() => _DesktopConfigManagementState();
}

class _DesktopConfigManagementState extends State<DesktopConfigManagement> {
  late ProxyServer proxyServer;
  late Configuration configuration;

  @override
  void initState() {
    super.initState();
    proxyServer = widget.proxyServer;
    configuration = widget.proxyServer.configuration;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('配置管理'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection([
            ListTile(
              leading: const Icon(Icons.file_download, color: Colors.green),
              title: const Text('导出配置'),
              subtitle: const Text('将当前配置导出为 JSON 文件，用于备份或分享'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _exportConfig(context),
            ),
            const Divider(height: 0, thickness: 0.3),
            ListTile(
              leading: const Icon(Icons.file_upload, color: Colors.blue),
              title: const Text('导入配置'),
              subtitle: const Text('从 JSON 文件导入配置，会覆盖当前配置'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _importConfig(context),
            ),
            const Divider(height: 0, thickness: 0.3),
            ListTile(
              leading: const Icon(Icons.content_copy, color: Colors.teal),
              title: const Text('复制配置到剪贴板'),
              subtitle: const Text('生成配置文本，粘贴到其它设备即可导入（无需传文件）'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _exportToClipboard(context),
            ),
            const Divider(height: 0, thickness: 0.3),
            ListTile(
              leading: const Icon(Icons.content_paste, color: Colors.orange),
              title: const Text('从剪贴板导入配置'),
              subtitle: const Text('读取剪贴板里的配置文本，会覆盖当前配置'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _importFromClipboard(context),
            ),
            const Divider(height: 0, thickness: 0.3),
            ListTile(
              leading: const Icon(Icons.backup, color: Colors.purple),
              title: const Text('备份管理'),
              subtitle: const Text('查看、恢复或删除自动备份的配置文件'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => Dialog(
                    child: SizedBox(
                      width: 700,
                      height: 600,
                      child: DesktopBackupManagement(configuration: configuration),
                    ),
                  ),
                );
              },
            ),
          ]),
          const SizedBox(height: 16),
          Card(
            color: Colors.orange.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Text(
                        '注意事项',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '• 导出配置会包含所有代理设置、过滤规则、MCP 配置等\n'
                    '• 导入配置会完全覆盖当前配置，请谨慎操作\n'
                    '• 建议定期导出配置进行备份\n'
                    '• 配置文件为 JSON 格式，可用文本编辑器查看',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(List<Widget> tiles) => Card(
        color: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.13)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: tiles),
      );

  /// 导出配置
  Future<void> _exportConfig(BuildContext context) async {
    BuildContext? dialogContext;

    void closeDialog() {
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }
    }

    try {
      // 显示进度对话框（非阻塞，避免阻塞后续导出与保存逻辑）
      unawaited(showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          dialogContext = ctx;
          return AlertDialog(
            title: const Row(
              children: [
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('正在导出配置'),
              ],
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('正在生成配置文件...'),
                SizedBox(height: 16),
                LinearProgressIndicator(minHeight: 6),
              ],
            ),
          );
        },
      ));

      // 生成默认文件名
      final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final defaultName = 'proxypin_config_$timestamp.json';

      // 导出配置
      final jsonStr = configuration.exportConfig();
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));

      // 关闭进度对话框后再弹出系统保存对话框，避免两个模态叠加
      closeDialog();
      await Future.delayed(const Duration(milliseconds: 50));

      // 使用 FilePicker 保存文件
      Uri? outputPath = await FilePicker.saveFile(
        dialogTitle: '选择保存位置',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );

      // 用户取消保存
      if (outputPath == null) {
        return;
      }

      if (mounted) {
        FlutterToastr.show(
          '配置已导出到：${outputPath.path}',
          context,
          duration: 3,
          backgroundColor: Colors.green,
        );
        logger.i('配置已导出到：${outputPath.path}');
      }
    } catch (e) {
      closeDialog();
      logger.e('导出配置失败', error: e, stackTrace: StackTrace.current);
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

  /// 导入配置
  Future<void> _importConfig(BuildContext context) async {
    try {
      // file_picker 12.x API: 直接使用 FilePicker.pickFiles() 而非 FilePicker.platform.pickFiles()
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (files == null || files.isEmpty) {
        return;
      }

      final file = files.first;
      // file_picker 12.x: 使用 readAsBytes() 而非直接访问 bytes 属性
      final bytes = await file.readAsBytes();
      if (bytes == null) {
        FlutterToastr.show('无法读取文件', context, duration: 2, backgroundColor: Colors.red);
        return;
      }

      final jsonStr = utf8.decode(bytes);
      final newConfig = await ConfigImportExport.importConfig(jsonStr);
      _applyImportedConfig(newConfig);

      if (mounted) {
        FlutterToastr.show('配置导入成功，部分设置可能需要重启应用后生效', context, duration: 3, backgroundColor: Colors.green);
        logger.i('配置已导入');
        setState(() {});
      }
    } catch (e) {
      logger.e('导入配置失败', error: e, stackTrace: StackTrace.current);
      if (mounted) {
        FlutterToastr.show(
          '导入失败：${e.toString()}',
          context,
          duration: 3,
          backgroundColor: Colors.red,
        );
      }
    }
  }

  /// 上游 #920：把配置文本复制到剪贴板，省掉"导出文件 → 传输 → 导入文件"的来回
  Future<void> _exportToClipboard(BuildContext context) async {
    try {
      final jsonStr = configuration.exportConfig();
      await Clipboard.setData(ClipboardData(text: jsonStr));
      if (mounted) {
        FlutterToastr.show('配置已复制到剪贴板，在其它设备粘贴导入即可', context, duration: 3, backgroundColor: Colors.green);
        logger.i('配置已复制到剪贴板');
      }
    } catch (e) {
      logger.e('复制配置到剪贴板失败', error: e, stackTrace: StackTrace.current);
      if (mounted) {
        FlutterToastr.show('复制失败：${e.toString()}', context, duration: 3, backgroundColor: Colors.red);
      }
    }
  }

  /// 上游 #920：从剪贴板读取配置文本并导入
  Future<void> _importFromClipboard(BuildContext context) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty) {
        if (mounted) {
          FlutterToastr.show('剪贴板里没有文本', context, duration: 2, backgroundColor: Colors.orange);
        }
        return;
      }
      if (!text.startsWith('{')) {
        if (mounted) {
          FlutterToastr.show('剪贴板内容不是配置 JSON，请先复制配置文本', context, duration: 3, backgroundColor: Colors.red);
        }
        return;
      }

      final newConfig = await ConfigImportExport.importConfig(text);
      _applyImportedConfig(newConfig);

      if (mounted) {
        FlutterToastr.show('配置导入成功，部分设置可能需要重启应用后生效', context, duration: 3, backgroundColor: Colors.green);
        logger.i('配置已从剪贴板导入');
        setState(() {});
      }
    } catch (e) {
      logger.e('从剪贴板导入配置失败', error: e, stackTrace: StackTrace.current);
      if (mounted) {
        FlutterToastr.show('导入失败：${e.toString()}', context, duration: 3, backgroundColor: Colors.red);
      }
    }
  }

  /// 把导入的配置写入当前实例（文件导入与剪贴板导入共用）
  void _applyImportedConfig(Configuration newConfig) {
    configuration.port = newConfig.port;
    configuration.enableSsl = newConfig.enableSsl;
    configuration.startup = newConfig.startup;
    configuration.enableSystemProxy = newConfig.enableSystemProxy;
    configuration.enableSocks5 = newConfig.enableSocks5;
    configuration.proxyPassDomains = newConfig.proxyPassDomains;
    configuration.externalProxy = newConfig.externalProxy;
    configuration.appWhitelist = newConfig.appWhitelist;
    configuration.appWhitelistEnabled = newConfig.appWhitelistEnabled;
    configuration.appBlacklist = newConfig.appBlacklist;
    configuration.historyCacheTime = newConfig.historyCacheTime;
    configuration.mcpPort = newConfig.mcpPort;
    configuration.mcpEnabled = newConfig.mcpEnabled;
    configuration.mcpAutoStart = newConfig.mcpAutoStart;
    configuration.mcpToolsEnabled = newConfig.mcpToolsEnabled;
    configuration.enabledHttp2 = newConfig.enabledHttp2;
    configuration.flushConfig();
  }
}
