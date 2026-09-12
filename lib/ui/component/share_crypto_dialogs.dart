/*
 * 分享加密相关对话框（上游 #133）
 *
 * - [showShareModeDialog]：选择「明文分享」或「加密分享」
 * - [showSharePasswordDialog]：输入口令（可要求二次确认）
 */
import 'package:flutter/material.dart';

import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/secure_share.dart';

/// 选择分享方式：返回 true 表示加密分享，false 表示明文，null 表示取消
Future<bool?> showShareModeDialog(BuildContext context, {String? title}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      final localizations = AppLocalizations.of(context)!;
      return AlertDialog(
        title: Text(title ?? localizations.share),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(localizations.shareModePlainDesc, style: const TextStyle(fontSize: 12, height: 1.4)),
            const SizedBox(height: 8),
            Text(localizations.shareModeEncryptedDesc, style: const TextStyle(fontSize: 12, height: 1.4)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(localizations.shareModePlain)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(localizations.shareModeEncrypted)),
        ],
      );
    },
  );
}

/// 输入分享口令；[confirm] 为 true 时要求两次输入一致。取消返回 null
Future<String?> showSharePasswordDialog(
  BuildContext context, {
  String? title,
  String? subtitle,
  bool confirm = false,
  String? confirmButtonText,
}) async {
  final controller = TextEditingController();
  final confirmController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  var obscure = true;

  final result = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      final localizations = AppLocalizations.of(context)!;
      return AlertDialog(
        title: Text(title ?? localizations.password),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (subtitle != null) ...[
                Text(subtitle, style: const TextStyle(fontSize: 12, height: 1.4)),
                const SizedBox(height: 10),
              ],
              TextFormField(
                controller: controller,
                obscureText: obscure,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: localizations.password,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  helperText: localizations.sharePasswordMinLength('${SecureShare.minPasswordLength}'),
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 18),
                    tooltip: obscure ? localizations.sharePasswordShow : localizations.sharePasswordHide,
                    onPressed: () => setState(() => obscure = !obscure),
                  ),
                ),
                validator: (v) => (v == null || v.length < SecureShare.minPasswordLength)
                    ? localizations.sharePasswordMinLength('${SecureShare.minPasswordLength}')
                    : null,
              ),
              if (confirm) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: confirmController,
                  obscureText: obscure,
                  decoration: InputDecoration(
                      labelText: localizations.sharePasswordConfirm,
                      border: const OutlineInputBorder(),
                      isDense: true),
                  validator: (v) => v != controller.text ? localizations.sharePasswordMismatch : null,
                ),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(localizations.cancel)),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(context, controller.text);
            },
            child: Text(confirmButtonText ?? localizations.confirm),
          ),
        ],
      );
    }),
  );

  // 注意：不在对话框关闭后立即 dispose controller——关闭动画期间控件仍可能引用它
  return result;
}
