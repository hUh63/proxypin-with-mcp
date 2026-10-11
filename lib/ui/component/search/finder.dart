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

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';

/// 编辑器底部的「查找 / 替换」面板。
///
/// 它和「快捷输入行」上下相邻：符号条在上，本面板在符号条**下方**（都贴在页面底部）。
///
/// 两种状态：
/// * **收起**（默认）—— 只有一行「查找 + 输入框 + 展开箭头」以及上一处 / 下一处 / 关闭；
/// * **展开**（点箭头）—— 追加「搜索结果 + 匹配选项」「替换行」和
///   「上一个 / 下一个 / 替换 / 全部替换」按钮行。
class FindPanelView extends StatelessWidget implements PreferredSizeWidget {
  final FindController controller;

  const FindPanelView({super.key, required this.controller});

  /// 给「仍被 CodeForge 当作 slot 使用」的场景（如 JS 运行页、重写页）一个合理高度；
  /// 在我们自己放进页面底部 Column 的用法里，这个值不影响布局。
  @override
  Size get preferredSize => controller.isActive
      ? Size(double.infinity, controller.isReplaceMode ? 120 : 76)
      : const Size(double.infinity, 0);

  AppLocalizations _loc(BuildContext context) => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    if (!controller.isActive) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 0.6),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (node, event) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            controller.isActive = false;
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller.isReplaceMode) _resultRow(context),
            _findRow(context),
            if (controller.isReplaceMode) _replaceRow(context),
            _actionRow(context),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ 行

  /// 搜索结果计数 + 匹配选项开关。
  Widget _resultRow(BuildContext context) {
    final loc = _loc(context);
    final count = controller.matchCount;
    return Row(
      children: [
        Text(
          '${loc.findResults}: $count',
          style: TextStyle(
            fontSize: 12,
            color: count == 0 ? Colors.grey : Colors.orange,
          ),
        ),
        const Spacer(),
        _toggle(context, 'Aa', controller.caseSensitive, controller.toggleCaseSensitive,
            loc.findCaseSensitive),
        _toggle(context, 'W', controller.matchWholeWord, controller.toggleMatchWholeWord,
            loc.findWholeWord),
        _toggle(context, '.*', controller.isRegex, controller.toggleRegex, loc.findRegex),
      ],
    );
  }

  Widget _findRow(BuildContext context) {
    final loc = _loc(context);
    return Row(
      children: [
        Text(loc.search, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 8),
        Expanded(
          child: _input(
            controller.findInputController,
            controller.findInputFocusNode,
          ),
        ),
        IconButton(
          icon: Icon(
            controller.isReplaceMode ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
            size: 20,
          ),
          tooltip: loc.replace,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
          onPressed: controller.toggleReplaceMode,
        ),
      ],
    );
  }

  Widget _replaceRow(BuildContext context) {
    final loc = _loc(context);
    return Row(
      children: [
        Text(loc.replace, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 8),
        Expanded(
          child: _input(
            controller.replaceInputController,
            controller.replaceInputFocusNode,
            onSubmit: (_) {
              controller.replace();
              controller.replaceInputFocusNode.requestFocus();
            },
          ),
        ),
        const SizedBox(width: 32),
      ],
    );
  }

  Widget _actionRow(BuildContext context) {
    final loc = _loc(context);
    final none = controller.matchCount == 0;
    return Row(
      children: [
        _textButton(loc.findPrevious, none ? null : controller.previous),
        _textButton(loc.findNext, none ? null : controller.next),
        if (controller.isReplaceMode) ...[
          _textButton(loc.replace, none ? null : controller.replace),
          _textButton(loc.findReplaceAll, none ? null : controller.replaceAll),
        ],
        const Spacer(),
        _textButton(loc.close, controller.toggleActive),
      ],
    );
  }

  // ------------------------------------------------------------- 小部件

  Widget _input(
    TextEditingController textController,
    FocusNode focusNode, {
    ValueChanged<String>? onSubmit,
  }) {
    return TextField(
      controller: textController,
      focusNode: focusNode,
      maxLines: 1,
      style: const TextStyle(fontSize: 13),
      onSubmitted: onSubmit ?? (_) => controller.next(),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: 6),
        border: UnderlineInputBorder(),
      ),
    );
  }

  Widget _toggle(
    BuildContext context,
    String text,
    bool checked,
    VoidCallback onPressed,
    String tooltip,
  ) {
    final color = checked ? Theme.of(context).colorScheme.primary : Colors.grey;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: checked ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _textButton(String label, VoidCallback? onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}
