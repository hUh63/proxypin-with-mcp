/*
 * Copyright 2025 Hongen Wang All rights reserved.
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';

/// 内置环境变量速查（上游 #900）。
///
/// 这些变量无需在环境里定义，凡是支持 `{{变量}}` 的地方
/// （重写规则、上报地址、脚本、MCP 等）都能直接引用；点击即可复制。
class BuiltinVariablesDialog extends StatelessWidget {
  const BuiltinVariablesDialog({super.key});

  /// 变量名 + 说明，与 EnvironmentManager._builtinValue 保持一致
  static const List<(String, String)> variables = [
    ('timestamp', '秒级 Unix 时间戳'),
    ('timestamp_ms', '毫秒级 Unix 时间戳'),
    ('datetime', 'ISO 8601 日期时间'),
    ('date', '日期（yyyy-MM-dd）'),
    ('time', '时间（HH:mm:ss）'),
    ('unix_date', '自 1970 年以来的天数'),
    ('uuid', '随机 UUID（每次引用都不同）'),
  ];

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const BuiltinVariablesDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.functions, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          const Text('内置变量', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 420),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '下面这些变量不用定义，在任何支持 {{变量}} 的地方（重写规则、上报地址、脚本等）都能直接引用。点一下复制。',
                style: TextStyle(fontSize: 12, height: 1.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              for (final (name, desc) in variables)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.data_object, size: 18),
                  title: Text('{{$name}}', style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                  subtitle: Text(desc, style: const TextStyle(fontSize: 11.5)),
                  trailing: const Icon(Icons.copy, size: 16),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: '{{$name}}'));
                    if (context.mounted) {
                      FlutterToastr.show('已复制 {{$name}}', context, duration: 2);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了')),
      ],
    );
  }
}
