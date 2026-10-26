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

// 编辑器底部的「问题栏」。
//
// 与底部大面板（控制台）分开：语法问题要**贴着代码**看，所以它是一个扁条，
// 贴在文本区正下方、快捷插入行之上，按文本里的先后顺序一行一条：
//
//   红点  缺少分号  第 12 行 第 14 个  [修复]
//   黄点  缩进混用  第 30 行 第 1 个
//
// 点整行 → 跳到那个位置；点「修复」→ 直接应用该条的建议（不是全量修复）。
// 行数和条数都有上限，超出的折叠成一行「还有 N 条」，点开进完整面板。
import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/code_lint.dart';

/// 问题栏：红色报错 + 黄色警告，一行一条。
class LintIssueBar extends StatefulWidget {
  final LintReport? report;

  /// 消息语言（中文用户看中文）。
  final bool chinese;

  /// 点某一条 → 跳到文本里对应位置。
  final void Function(LintDiagnostic) onJump;

  /// 点「修复」→ 只应用这一条建议。
  final void Function(LintDiagnostic) onFix;

  /// 点「还有 N 条」→ 打开完整面板。
  final VoidCallback? onShowAll;

  /// 同时最多显示几行（超出的折叠）。
  final int maxRows;

  const LintIssueBar({
    super.key,
    required this.report,
    required this.onJump,
    required this.onFix,
    this.onShowAll,
    this.chinese = true,
    this.maxRows = 3,
  });

  @override
  State<LintIssueBar> createState() => _LintIssueBarState();
}

class _LintIssueBarState extends State<LintIssueBar> {
  /// 用户主动收起。
  bool _collapsed = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    final all = widget.report?.diagnostics ?? const <LintDiagnostic>[];
    // 没有问题就不占位置（保持编辑区干净）。
    if (all.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final errors = all.where((e) => e.severity == LintSeverity.error).length;
    final warnings = all.where((e) => e.severity == LintSeverity.warning).length;
    final infos = all.length - errors - warnings;
    final rows = _collapsed ? const <LintDiagnostic>[] : all.take(widget.maxRows).toList();
    final hidden = all.length - rows.length;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.6)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // 表头：数量 + 收起/展开
        InkWell(
          onTap: () => setState(() => _collapsed = !_collapsed),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 3, 6, 3),
            child: Row(children: [
              if (errors > 0) _countBadge(Colors.red, errors),
              if (warnings > 0) ...[
                if (errors > 0) const SizedBox(width: 6),
                _countBadge(Colors.orange, warnings),
              ],
              if (infos > 0) ...[
                if (errors > 0 || warnings > 0) const SizedBox(width: 6),
                _countBadge(Colors.blueGrey, infos),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.onShowAll == null ? '' : localizations.editorIssueHint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: theme.textTheme.bodySmall?.color),
                ),
              ),
              Icon(_collapsed ? Icons.expand_less : Icons.expand_more,
                  size: 16, color: theme.textTheme.bodySmall?.color),
            ]),
          ),
        ),
        if (rows.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 132),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: rows.length,
              itemBuilder: (context, i) => _row(theme, rows[i]),
            ),
          ),
        if (hidden > 0)
          InkWell(
            onTap: widget.onShowAll,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
              child: Row(children: [
                Icon(Icons.unfold_more, size: 13, color: theme.colorScheme.primary),
                const SizedBox(width: 5),
                Text(localizations.editorIssueMore('$hidden'),
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.primary)),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _countBadge(Color color, int count) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.circle, size: 8, color: color),
      const SizedBox(width: 3),
      Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    ]);
  }

  Widget _row(ThemeData theme, LintDiagnostic d) {
    final color = switch (d.severity) {
      LintSeverity.error => Colors.red,
      LintSeverity.warning => Colors.orange,
      LintSeverity.info => Colors.blueGrey,
    };
    final fixable = d.replacement != null;
    return InkWell(
      onTap: () => widget.onJump(d),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 6, 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Icon(Icons.circle, size: 7, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              d.message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: theme.textTheme.bodyMedium?.color),
            ),
          ),
          const SizedBox(width: 6),
          // 位置：用主题色高亮，点它也是跳转
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              localizations.editorIssuePosition('${d.line}', '${d.column}'),
              style: TextStyle(fontSize: 10, color: theme.colorScheme.primary),
            ),
          ),
          if (fixable)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: TextButton(
                onPressed: () => widget.onFix(d),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 24),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  visualDensity: VisualDensity.compact,
                  foregroundColor: theme.colorScheme.primary,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(localizations.editorIssueFix, style: const TextStyle(fontSize: 11)),
              ),
            ),
        ]),
      ),
    );
  }
}
