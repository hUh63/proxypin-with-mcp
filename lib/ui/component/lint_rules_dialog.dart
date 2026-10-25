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
//
// 开关**按语言分开记**：在 C# 里关掉「缺少分号」不该影响 Python。默认只改当前
// 语言，想一次改完所有语言就点「应用到全部语言」。
import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/code_lint.dart';

/// 规则面板的返回值。
class LintRulesResult {
  /// 勾选后仍然开启的规则（即「未关闭」集合的补集已算好，这里直接给「关闭」集合）。
  final Set<String> disabled;

  /// 是否应用到全部语言（否则只对打开面板时的那个语言生效）。
  final bool applyToAll;

  const LintRulesResult(this.disabled, {this.applyToAll = false});
}

/// 打开规则开关面板，返回新的「已关闭规则」集合；返回 null 表示取消。
Future<LintRulesResult?> showLintRulesDialog(
  BuildContext context, {
  required Set<String> disabled,
  String languageLabel = '',
  bool hasOverride = false,
}) {
  final localizations = AppLocalizations.of(context)!;
  final working = Set<String>.from(disabled);
  final chinese = Localizations.localeOf(context).languageCode.startsWith('zh');
  return showDialog<LintRulesResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(localizations.editorLintRules, style: const TextStyle(fontSize: 15)),
        contentPadding: const EdgeInsets.only(top: 8, bottom: 0),
        content: SizedBox(
          width: 440,
          height: 440,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(localizations.editorLintRulesHint,
                    style: TextStyle(fontSize: 11.5, color: Theme.of(ctx).textTheme.bodySmall?.color)),
                if (languageLabel.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(children: [
                    Icon(Icons.language, size: 12, color: Theme.of(ctx).colorScheme.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        chinese
                            ? '这些开关只对『$languageLabel』生效'
                                '${hasOverride ? '（已有单独设置）' : '（当前继承通用设置）'}'
                            : 'These switches apply to "$languageLabel" only'
                                '${hasOverride ? ' (already customized)' : ' (inherited)'}',
                        style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.primary),
                      ),
                    ),
                  ]),
                ],
              ]),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, LintRulesResult(Set<String>.from(working), applyToAll: true)),
            child: Text(localizations.editorLintRulesApplyAll, style: const TextStyle(fontSize: 12)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localizations.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, LintRulesResult(Set<String>.from(working))),
            child: Text(localizations.save),
          ),
        ],
      ),
    ),
  );
}
