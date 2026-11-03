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

// 工具箱里那些「专业工具」的公共外壳。
//
// 用户反馈（v1.67.225 之后）：「字节签名 / CRC32 / 三方合并 / 安全自检 / Fuzz / WAF
// 变异，功能很 AI，不是正常人使用的」。问题不在算法，在**页面没有把话说清楚**：
//   * 进来不知道这个工具要什么输入、会吐什么结果；
//   * 空着表单不知道填什么，也没有示例；
//   * 结果散落在对话框/弹窗里，想复制还得找。
//
// 所以统一三件套：
//   1. [ToolIntro]——一句话说清楚「干什么 / 填什么 / 得到什么」，配「填示例」和
//      「常用场景」按钮，空表单一个点击就能跑通；
//   2. [ToolStepHeader]——多步流程（选目标 → 选策略 → 看结果）显式编号；
//   3. [ToolResultBox]——固定在一块的结果区，等宽字体 + 复制 + 保存，别再用对话框。

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 工具页顶部说明卡（含示例与常用场景）。
class ToolIntro extends StatelessWidget {
  /// 一句话：这个工具干什么。
  final String text;

  /// 输入什么 / 得到什么（两行小字）。
  final String? input;
  final String? output;

  /// 「填示例」回调；为空则不显示按钮。
  final VoidCallback? onExample;

  /// 常用场景（点了直接套预设）。
  final List<ToolPreset> presets;

  /// 可展开的「说明」长文本（选填）。
  final String? help;

  /// 外边距（放在已有 padding 的列表里时传 [EdgeInsets.zero]）。
  final EdgeInsetsGeometry margin;

  const ToolIntro({
    super.key,
    required this.text,
    this.input,
    this.output,
    this.onExample,
    this.presets = const <ToolPreset>[],
    this.help,
    this.margin = const EdgeInsets.fromLTRB(12, 12, 12, 6),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: margin,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(text,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                ),
                if (onExample != null)
                  TextButton.icon(
                    onPressed: onExample,
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    label: const Text('示例', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
            if ((input ?? '').isNotEmpty || (output ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((input ?? '').isNotEmpty)
                      _kv(theme, '输入', input!),
                    if ((output ?? '').isNotEmpty)
                      _kv(theme, '输出', output!),
                  ],
                ),
              ),
            if (presets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in presets)
                      ActionChip(
                        avatar: const Icon(Icons.bolt, size: 14),
                        label: Text(p.label, style: const TextStyle(fontSize: 12)),
                        onPressed: p.onApply,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ),
            if (help != null && help!.trim().isNotEmpty)
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 6),
                  title: Text('说明', style: theme.textTheme.labelMedium),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(help!,
                          style: theme.textTheme.bodySmall?.copyWith(height: 1.55)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Widget _kv(ThemeData theme, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2, right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(k,
                style: TextStyle(fontSize: 10, color: theme.colorScheme.primary)),
          ),
          Expanded(
            child: Text(v,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          ),
        ],
      ),
    );
  }
}

/// 一个「常用场景」预设。
class ToolPreset {
  final String label;
  final VoidCallback onApply;

  const ToolPreset(this.label, this.onApply);
}

/// 多步流程的小标题（1/2/3）。
class ToolStepHeader extends StatelessWidget {
  final int step;
  final String title;
  final Widget? trailing;

  const ToolStepHeader({super.key, required this.step, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Text('$step',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onPrimary)),
          ),
          const SizedBox(width: 8),
          Text(title,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 固定结果区：等宽文本 + 复制 + 保存，替代「弹个对话框给你看」。
class ToolResultBox extends StatelessWidget {
  final String? title;
  final String value;

  /// 为空时的占位说明（"结果会出现在这里"）。
  final String emptyHint;

  /// 保存文件名（不含扩展名）；为空则不显示保存按钮。
  final String? saveName;

  final double minHeight;

  const ToolResultBox({
    super.key,
    this.title,
    required this.value,
    this.emptyHint = '结果会显示在这里',
    this.saveName,
    this.minHeight = 120,
  });

  Future<void> _save(BuildContext context) async {
    try {
      final name = '${(saveName == null || saveName!.isEmpty) ? 'result' : saveName!}.txt';
      final saved = await FilePicker.saveFile(
        fileName: name,
        // 必须用 UTF-8：codeUnits 是 UTF-16 单元，中文会写成乱码
        bytes: Uint8List.fromList(utf8.encode(value)),
      );
      if (saved == null) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存：$saved')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEmpty = value.trim().isEmpty;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title ?? '结果',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (!isEmpty) ...[
                IconButton(
                  tooltip: '复制',
                  visualDensity: VisualDensity.compact,
                  iconSize: 17,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: value));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('已复制'), duration: Duration(milliseconds: 1200)),
                    );
                  },
                  icon: const Icon(Icons.copy_all_outlined),
                ),
                if (saveName != null)
                  IconButton(
                    tooltip: '保存',
                    visualDensity: VisualDensity.compact,
                    iconSize: 17,
                    onPressed: () => _save(context),
                    icon: const Icon(Icons.save_alt),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          SelectableText(
            isEmpty ? emptyHint : value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.5,
              color: isEmpty ? theme.hintColor : theme.textTheme.bodyMedium?.color,
            ),
          ),
        ],
      ),
    );
  }
}
