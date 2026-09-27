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
import 'package:proxypin/l10n/app_localizations.dart';

/// 内置环境变量速查（上游 #900）。
///
/// 这些变量无需在环境里定义，凡是支持 `{{变量}}` 的地方
/// （重写规则、上报地址、脚本、MCP 等）都能直接引用；点击即可复制。
class BuiltinVariablesDialog extends StatelessWidget {
  const BuiltinVariablesDialog({super.key});

  /// 变量名 + 说明，与 EnvironmentManager._builtinValue 保持一致
  static const List<String> variableNames = [
    'timestamp',
    'timestamp_ms',
    'datetime',
    'date',
    'time',
    'unix_date',
    'uuid',
  ];

  static String _desc(AppLocalizations loc, String name) {
    switch (name) {
      case 'timestamp':
        return loc.bvDescTimestamp;
      case 'timestamp_ms':
        return loc.bvDescTimestampMs;
      case 'datetime':
        return loc.bvDescDatetime;
      case 'date':
        return loc.bvDescDate;
      case 'time':
        return loc.bvDescTime;
      case 'unix_date':
        return loc.bvDescUnixDate;
      case 'uuid':
        return loc.bvDescUuid;
      default:
        return name;
    }
  }

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
          Text(AppLocalizations.of(context)!.bvTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 420),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.bvIntro(AppLocalizations.of(context)!.bvSampleVariable('{',
                    AppLocalizations.of(context)!.bvVariableWord, '}')),
                style: TextStyle(fontSize: 12, height: 1.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              for (final name in variableNames)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.data_object, size: 18),
                  title: Text('{{$name}}', style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                  subtitle: Text(_desc(AppLocalizations.of(context)!, name),
                      style: const TextStyle(fontSize: 11.5)),
                  trailing: const Icon(Icons.copy, size: 16),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: '{{$name}}'));
                    if (context.mounted) {
                      FlutterToastr.show(
                          AppLocalizations.of(context)!.bvCopied('{{$name}}'),
                          context,
                          duration: 2);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.bvGotIt)),
      ],
    );
  }
}
