/*
 * Copyright 2024 Hongen Wang All rights reserved.
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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/ui/component/multi_window.dart';
import 'package:proxypin/ui/component/utils.dart';

/// Mock 场景合集
///
/// 把重写规则按「场景」分组后，可在此一键批量启用 / 停用 / 仅启用某个场景，
/// 便于在不同调试场景（正常 / 异常 / 边界）之间快速切换。
/// 借鉴 proxypin-mcp-workbench 的 mock_scenarios 场景合集思路。
void showRewriteScenarioDialog(BuildContext context, RequestRewriteManager manager, {VoidCallback? onChanged}) {
  showDialog(context: context, builder: (_) => RewriteScenarioDialog(manager: manager, onChanged: onChanged));
}

class RewriteScenarioDialog extends StatefulWidget {
  final RequestRewriteManager manager;
  final VoidCallback? onChanged;

  const RewriteScenarioDialog({super.key, required this.manager, this.onChanged});

  @override
  State<RewriteScenarioDialog> createState() => _RewriteScenarioDialogState();
}

class _RewriteScenarioDialogState extends State<RewriteScenarioDialog> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  /// 执行改动，并把规则状态同步到其它窗口后刷新自身
  void _apply(void Function() action) {
    action();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      var rules = widget.manager.rules;
      for (var i = 0; i < rules.length; i++) {
        MultiWindow.invokeRefreshRewrite(Operation.update, index: i, rule: rules[i]);
      }
    }
    widget.onChanged?.call();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    var scenarios = widget.manager.scenarios;
    var hintColor = Theme.of(context).hintColor;
    return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        titlePadding: const EdgeInsets.only(top: 14, left: 20, right: 20),
        contentPadding: const EdgeInsets.only(left: 20, right: 20, top: 6, bottom: 4),
        actionsPadding: const EdgeInsets.only(right: 16, bottom: 12),
        title: Row(children: [
          const Icon(Icons.movie_filter_outlined, size: 20),
          const SizedBox(width: 8),
          Text(localizations.mockScenario, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ]),
        content: SizedBox(
            width: 540,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(localizations.mockScenarioTips, style: TextStyle(fontSize: 12, color: hintColor)),
              const SizedBox(height: 12),
              if (scenarios.isEmpty)
                Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
                    child: Column(children: [
                      Icon(Icons.inbox_outlined, size: 34, color: hintColor),
                      const SizedBox(height: 8),
                      Text(localizations.mockScenarioEmpty,
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: hintColor)),
                    ]))
              else
                ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 380),
                    child: SingleChildScrollView(child: Column(children: [for (var s in scenarios) _tile(s)]))),
              if (widget.manager.unassignedCount > 0)
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${localizations.mockScenarioUnassigned}: ${widget.manager.unassignedCount}',
                        style: TextStyle(fontSize: 12, color: hintColor))),
            ])),
        actions: [
          ElevatedButton(child: Text(localizations.close), onPressed: () => Navigator.of(context).pop()),
        ]);
  }

  Widget _tile(String scenario) {
    var total = widget.manager.scenarioTotal(scenario);
    var on = widget.manager.scenarioEnabledCount(scenario);
    var allOn = total > 0 && on == total;
    var hintColor = Theme.of(context).hintColor;
    return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.6))),
        child: Row(children: [
          Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(scenario,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text('${localizations.mockScenarioEnabled} $on / $total', style: TextStyle(fontSize: 12, color: hintColor)),
          ])),
          Tooltip(
              message: localizations.mockScenarioSoloTip,
              child: TextButton(
                  onPressed: () => _apply(() => widget.manager.soloScenario(scenario)),
                  child: Text(localizations.mockScenarioSolo, style: const TextStyle(fontSize: 13)))),
          IconButton(
              tooltip: localizations.rename,
              visualDensity: VisualDensity.compact,
              onPressed: () => _rename(scenario),
              icon: const Icon(Icons.edit_outlined, size: 18)),
          IconButton(
              tooltip: localizations.mockScenarioClear,
              visualDensity: VisualDensity.compact,
              onPressed: () => _clear(scenario),
              icon: const Icon(Icons.link_off, size: 18)),
          Transform.scale(
              scale: 0.8,
              child: Switch(
                  value: allOn, onChanged: (val) => _apply(() => widget.manager.setScenarioEnabled(scenario, val)))),
        ]));
  }

  Future<void> _rename(String scenario) async {
    var controller = TextEditingController(text: scenario);
    var result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              title: Text(localizations.mockScenarioRename, style: const TextStyle(fontSize: 16)),
              content: TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                      hintText: localizations.mockScenarioRenameHint, border: const OutlineInputBorder())),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(localizations.cancel)),
                FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(controller.text), child: Text(localizations.save)),
              ],
            ));
    var name = result?.trim();
    if (name == null || name.isEmpty || name == scenario) {
      return;
    }
    _apply(() => widget.manager.renameScenario(scenario, name));
    if (mounted) {
      FlutterToastr.show(localizations.saveSuccess, context);
    }
  }

  void _clear(String scenario) {
    showConfirmDialog(context, content: localizations.mockScenarioClearConfirm, onConfirm: () {
      _apply(() => widget.manager.clearScenario(scenario));
      if (mounted) {
        FlutterToastr.show(localizations.saveSuccess, context);
      }
    });
  }
}
