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
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/mobile/setting/backup_management.dart';

/// 配置管理页面 - 导入/导出配置
class ConfigManagement extends StatefulWidget {
  final ProxyServer proxyServer;

  const ConfigManagement({
    super.key,
    required this.proxyServer,
  });

  @override
  State<StatefulWidget> createState() => _ConfigManagementState();
}

class _ConfigManagementState extends State<ConfigManagement> {
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
    AppLocalizations localizations = AppLocalizations.of(context)!;
    final borderColor = Theme.of(context).dividerColor.withValues(alpha: 0.13);
    final dividerColor = Theme.of(context).dividerColor.withValues(alpha: 0.22);

    Widget section(List<Widget> tiles) => Card(
          color: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: borderColor),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: tiles),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          localizations.cfgManagement,
          style: const TextStyle(fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          section([
            ListTile(
              leading: const Icon(Icons.file_download, color: Colors.green),
              title: Text(localizations.cfgExport),
              subtitle: Text(localizations.cfgExportDesc),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _exportConfig(context, localizations),
            ),
            Divider(height: 0, thickness: 0.3, color: dividerColor),
            ListTile(
              leading: const Icon(Icons.file_upload, color: Colors.blue),
              title: Text(localizations.cfgImport),
              subtitle: Text(localizations.cfgImportDesc),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _importConfig(context, localizations),
            ),
            Divider(height: 0, thickness: 0.3, color: dividerColor),
            ListTile(
              leading: const Icon(Icons.content_copy, color: Colors.teal),
              title: Text(localizations.cfgCopyToClipboard),
              subtitle: Text(localizations.cfgCopyToClipboardDesc),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _exportToClipboard(context),
            ),
            Divider(height: 0, thickness: 0.3, color: dividerColor),
            ListTile(
              leading: const Icon(Icons.content_paste, color: Colors.orange),
              title: Text(localizations.cfgImportFromClipboard),
              subtitle: Text(localizations.cfgImportFromClipboardDesc),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _importFromClipboard(context),
            ),
            Divider(height: 0, thickness: 0.3, color: dividerColor),
            ListTile(
              leading: const Icon(Icons.backup, color: Colors.purple),
              title: Text(localizations.desktopBackupManagement),
              subtitle: Text(localizations.cfgBackupDesc),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const BackupManagement()),
                );
              },
            ),
          ]),
          const SizedBox(height: 12),
          Card(
            color: Colors.orange.withValues(alpha: 0.1),
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        localizations.cfgNotice,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    localizations.cfgNoticeBody,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 导出配置
  Future<void> _exportConfig(
      BuildContext context, AppLocalizations localizations) async {
    double exportProgress = 0.0;
    bool isExporting = false;
    BuildContext? dialogContext;

    try {
      // 显示进度对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          dialogContext = ctx;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Row(
                  children: [
                    const CircularProgressIndicator(strokeWidth: 2, value: null),
                    const SizedBox(width: 12),
                    Text(localizations.cfgExporting),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(localizations.cfgExportPreparing),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: exportProgress > 0 ? exportProgress : null,
                      minHeight: 6,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      exportProgress > 0
                          ? '${(exportProgress * 100).toInt()}%'
                          : localizations.cfgPreparing,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                actions: [
                  if (!isExporting)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(localizations.close),
                    ),
                ],
              );
            },
          );
        },
      );

      // 生成默认文件名
      final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final defaultName = 'proxypin_config_$timestamp.json';

      // 导出配置
      final jsonStr = configuration.exportConfig();
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));

      // 关闭进度对话框后再弹出系统保存对话框，避免模态叠加与阻塞
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // 使用 FilePicker v12+ API 保存文件 (直接传入 bytes)
      Uri? outputPath = await FilePicker.saveFile(
        dialogTitle: localizations.cfgSelectSaveLocation,
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
          localizations.cfgExportedTo(outputPath.path),
          context,
          duration: 3,
          backgroundColor: Colors.green,
        );
        logger.i('配置已导出到：${outputPath.path}');
      }
    } catch (e) {
      logger.e('导出配置失败', error: e, stackTrace: StackTrace.current);
      // 关闭进度对话框
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }
      if (mounted) {
        FlutterToastr.show(
          localizations.cfgExportFailed(e.toString()),
          context,
          duration: 3,
          backgroundColor: Colors.red,
        );
      }
    }
  }

  /// 导入配置
  Future<void> _importConfig(
      BuildContext context, AppLocalizations localizations) async {
    try {
      // 选择文件 (v12+ API)
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.isEmpty) {
        // 用户取消
        return;
      }

      final filePath = result.first.xFile.path;
      if (filePath == null) {
        return;
      }

      // 确认导入
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(localizations.cfgConfirmImport),
          content: Text(localizations.cfgImportConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(localizations.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: Text(localizations.mcpAutoConfirm),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }

      // 导入配置
      final file = File(filePath);
      final jsonStr = await file.readAsString();
      final newConfig = await ConfigImportExport.importConfig(jsonStr);
      _applyImportedConfig(newConfig);

      if (mounted) {
        FlutterToastr.show(
          localizations.cfgImportSuccessRestart,
          context,
          duration: 3,
          backgroundColor: Colors.green,
        );
        logger.i('配置已从 $filePath 导入成功');

        // 刷新页面显示
        setState(() {});
      }
    } catch (e) {
      logger.e('导入配置失败', error: e, stackTrace: StackTrace.current);
      if (mounted) {
        FlutterToastr.show(
          localizations.cfgImportFailed(e.toString()),
          context,
          duration: 3,
          backgroundColor: Colors.red,
        );
      }
    }
  }

  /// 上游 #920：把配置文本复制到剪贴板，方便在设备间直接粘贴传递
  Future<void> _exportToClipboard(BuildContext context) async {
    final localizations = AppLocalizations.of(context)!;
    try {
      final jsonStr = configuration.exportConfig();
      await Clipboard.setData(ClipboardData(text: jsonStr));
      if (mounted) {
        FlutterToastr.show(localizations.cfgCopied, context, duration: 3, backgroundColor: Colors.green);
        logger.i('配置已复制到剪贴板');
      }
    } catch (e) {
      logger.e('复制配置到剪贴板失败', error: e, stackTrace: StackTrace.current);
      if (mounted) {
        FlutterToastr.show(localizations.cfgCopyFailed(e.toString()), context, duration: 3, backgroundColor: Colors.red);
      }
    }
  }

  /// 上游 #920：从剪贴板读取配置文本并导入
  Future<void> _importFromClipboard(BuildContext context) async {
    // 导入会覆盖当前配置，先确认
    final localizations = AppLocalizations.of(context)!;
    showConfirmDialog(context,
        title: localizations.cfgImport,
        content: localizations.cfgImportConfirmBodyShort,
        onConfirm: () => _doImportFromClipboard(context));
  }

  /// 真正执行导入（确认后调用）
  Future<void> _doImportFromClipboard(BuildContext context) async {
    final localizations = AppLocalizations.of(context)!;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty) {
        if (mounted) {
          FlutterToastr.show(localizations.cfgClipboardEmpty, context, duration: 2, backgroundColor: Colors.orange);
        }
        return;
      }
      if (!text.startsWith('{')) {
        if (mounted) {
          FlutterToastr.show(localizations.cfgClipboardNotConfig, context, duration: 3, backgroundColor: Colors.red);
        }
        return;
      }

      final newConfig = await ConfigImportExport.importConfig(text);
      _applyImportedConfig(newConfig);

      if (mounted) {
        FlutterToastr.show(localizations.cfgImportSuccessRestart, context, duration: 3, backgroundColor: Colors.green);
        logger.i('配置已从剪贴板导入');
        setState(() {});
      }
    } catch (e) {
      logger.e('从剪贴板导入配置失败', error: e, stackTrace: StackTrace.current);
      if (mounted) {
        FlutterToastr.show(localizations.cfgImportFailed(e.toString()), context, duration: 3, backgroundColor: Colors.red);
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
    configuration.captureBodyLimitKB = newConfig.captureBodyLimitKB;
    configuration.mcpPort = newConfig.mcpPort;
    configuration.mcpEnabled = newConfig.mcpEnabled;
    configuration.mcpAutoStart = newConfig.mcpAutoStart;
    configuration.mcpToolsEnabled = newConfig.mcpToolsEnabled;
    configuration.enabledHttp2 = newConfig.enabledHttp2;
    configuration.flushConfig();
  }
}
