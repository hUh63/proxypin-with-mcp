/*
 * 分享加密相关对话框（上游 #133）
 *
 * - [showShareModeDialog]：选择「明文分享」或「加密分享」
 * - [showSharePasswordDialog]：输入口令（可要求二次确认）
 */
import 'package:flutter/material.dart';

import 'package:proxypin/utils/secure_share.dart';

/// 选择分享方式：返回 true 表示加密分享，false 表示明文，null 表示取消
Future<bool?> showShareModeDialog(BuildContext context, {String title = '分享方式'}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('明文分享：接收方可直接导入，适合自己备份或可信环境。', style: TextStyle(fontSize: 12, height: 1.4)),
        const SizedBox(height: 8),
        const Text('加密分享：设置口令后接收方需输入相同口令才能导入；口令不同或内容被改动将无法解密。',
            style: TextStyle(fontSize: 12, height: 1.4)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('明文分享')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('加密分享')),
      ],
    ),
  );
}

/// 输入分享口令；[confirm] 为 true 时要求两次输入一致。取消返回 null
Future<String?> showSharePasswordDialog(
  BuildContext context, {
  required String title,
  String? subtitle,
  bool confirm = false,
  String confirmButtonText = '确定',
}) async {
  final controller = TextEditingController();
  final confirmController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  var obscure = true;

  final result = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      return AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
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
                labelText: '口令',
                border: const OutlineInputBorder(),
                isDense: true,
                helperText: '至少 ${SecureShare.minPasswordLength} 位',
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 18),
                  tooltip: obscure ? '显示' : '隐藏',
                  onPressed: () => setState(() => obscure = !obscure),
                ),
              ),
              validator: (v) => (v == null || v.length < SecureShare.minPasswordLength) ? '口令至少 ${SecureShare.minPasswordLength} 位' : null,
            ),
            if (confirm) ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: confirmController,
                obscureText: obscure,
                decoration: const InputDecoration(labelText: '确认口令', border: OutlineInputBorder(), isDense: true),
                validator: (v) => v != controller.text ? '两次输入不一致' : null,
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(context, controller.text);
            },
            child: Text(confirmButtonText),
          ),
        ],
      );
    }),
  );

  // 注意：不在对话框关闭后立即 dispose controller——关闭动画期间控件仍可能引用它
  return result;
}
