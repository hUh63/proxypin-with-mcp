/*
 * WebSocket 流量推送端口编辑对话框（上游 #756）
 *
 * 端口此前只能改配置文件：12080 被占用时开关会启动失败并回滚，用户无路可走。
 * 这里提供图形化修改入口，改完立即生效（服务已开启则自动重启监听）。
 */
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 编辑 WebSocket 流量推送端口；确认返回新端口，取消返回 null。
Future<int?> showWsTrafficPortDialog(BuildContext context, {required int currentPort}) async {
  final controller = TextEditingController(text: currentPort.toString());
  final formKey = GlobalKey<FormState>();

  final result = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('订阅端口'),
      content: Form(
        key: formKey,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('外部工具 / AI 通过 ws://127.0.0.1:<端口> 订阅抓包流量。'
              '端口被占用时请改用其他端口（建议 1024~65535）。', style: TextStyle(fontSize: 12, height: 1.4)),
          const SizedBox(height: 12),
          TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '端口', border: OutlineInputBorder(), isDense: true),
            validator: (v) {
              final port = int.tryParse(v?.trim() ?? '');
              if (port == null) return '请输入数字端口';
              if (port < 1024 || port > 65535) return '端口需在 1024~65535 之间';
              return null;
            },
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() != true) return;
            Navigator.pop(context, int.parse(controller.text.trim()));
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
  return result;
}
