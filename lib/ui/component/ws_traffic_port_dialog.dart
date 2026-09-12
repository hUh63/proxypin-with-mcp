/*
 * WebSocket 流量推送端口编辑对话框（上游 #756）
 *
 * 端口此前只能改配置文件：12080 被占用时开关会启动失败并回滚，用户无路可走。
 * 这里提供图形化修改入口，改完立即生效（服务已开启则自动重启监听）。
 */
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';

/// 编辑 WebSocket 流量推送端口；确认返回新端口，取消返回 null。
Future<int?> showWsTrafficPortDialog(BuildContext context, {required int currentPort}) async {
  final controller = TextEditingController(text: currentPort.toString());
  final formKey = GlobalKey<FormState>();

  final result = await showDialog<int>(
    context: context,
    builder: (context) {
      final localizations = AppLocalizations.of(context)!;
      return AlertDialog(
        title: Text(localizations.wsTrafficPort),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(localizations.wsTrafficPortDialogDesc, style: const TextStyle(fontSize: 12, height: 1.4)),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                    labelText: localizations.wsTrafficPortLabel,
                    border: const OutlineInputBorder(),
                    isDense: true),
                validator: (v) {
                  final port = int.tryParse(v?.trim() ?? '');
                  if (port == null) return localizations.wsTrafficPortInvalidNumber;
                  if (port < 1024 || port > 65535) return localizations.wsTrafficPortOutOfRange;
                  return null;
                },
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(localizations.cancel)),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(context, int.parse(controller.text.trim()));
            },
            child: Text(localizations.save),
          ),
        ],
      );
    },
  );
  return result;
}
