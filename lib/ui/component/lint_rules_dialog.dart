/*
 * Copyright 2026 Hongen Wang All rights reserved.
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

// 「语法检查规则」开关面板。
//
// 有些项目的规范就是和默认规则不一样（比如坚持用 tab 缩进、或者就是不用分号），
// 与其让用户忍着误报，不如让他把那条规则关掉——关掉的规则不再产出诊断。
import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/code_lint.dart';

/// 打开规则开关面板，返回新的「已关闭规则」集合；返回 null 表示取消。
Future<Set<String>?> showLintRulesDialog(BuildContext context, Set<String> disabled) {
  final localizations = AppLocalizations.of(context)!;
  final working = Set<String>.from(disabled);
  final chinese = Localizations.localeOf(context).languageCode.startsWith('zh');
  return showDialog<Set<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(localizations.editorLintRules, style: const TextStyle(fontSize: 15)),
        contentPadding: const EdgeInsets.only(top: 8, bottom: 0),
        content: SizedBox(
          width: 420,
          height: 420,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(localizations.editorLintRulesHint,
                  style: TextStyle(fontSize: 11.5, color: Theme.of(ctx).textTheme.bodySmall?.color)),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView.builder(
                itemCount: LintRules.all.length,
                itemBuilder: (context, i) {
                  final rule = LintRules.all[i];
                  return SwitchListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(chinese ? rule.nameZh : rule.nameEn, style: const TextStyle(fontSize: 12.5)),
                    subtitle: Text(rule.code, style: const TextStyle(fontSize: 10)),
                    value: !working.contains(rule.code),
                    onChanged: (enabled) {
                      setDialogState(() {
                        if (enabled) {
                          working.remove(rule.code);
                        } else {
                          working.add(rule.code);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => setDialogState(working.clear),
            child: Text(localizations.editorLintRulesAll),
          ),
          TextButton(
            onPressed: () => setDialogState(() => working.addAll(LintRules.all.map((e) => e.code))),
            child: Text(localizations.editorLintRulesNone),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localizations.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, working),
            child: Text(localizations.save),
          ),
        ],
      ),
    ),
  );
}
