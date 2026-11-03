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

// 文本编辑器的「AI 辅助」弹层（对标 VS2026 / Cursor 的内联 AI）。
//
// 复用 App「设置 → AI 分析」那一套 OpenAI 兼容配置——不另开一套 key，
// 用户配一次，抓包分析、编辑器辅助、ARTEX 三处都能用。
//
// 五个固定动作（解释/注释/审查/测试/优化）+ 自由提问；结果可复制、
// 插入到光标或替换选区。选中为空时对整篇（截断 12000 字符）处理。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/ai_analyzer.dart';

enum EditorAiAction { explain, comment, review, tests, improve, ask }

/// 打开 AI 辅助弹层。
///
/// [onInsert] 把结果插到光标处；[onReplace] 为 null 表示当前没有选中内容。
Future<void> showEditorAiAssist(
  BuildContext context, {
  required String text,
  required String language,
  required void Function(String) onInsert,
  void Function(String)? onReplace,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => EditorAiAssistDialog(
      text: text,
      language: language,
      onInsert: onInsert,
      onReplace: onReplace,
    ),
  );
}

class EditorAiAssistDialog extends StatefulWidget {
  final String text;
  final String language;
  final void Function(String) onInsert;
  final void Function(String)? onReplace;

  const EditorAiAssistDialog({
    super.key,
    required this.text,
    required this.language,
    required this.onInsert,
    this.onReplace,
  });

  @override
  State<EditorAiAssistDialog> createState() => _EditorAiAssistDialogState();
}

class _EditorAiAssistDialogState extends State<EditorAiAssistDialog> {
  final _ask = TextEditingController();
  EditorAiAction _action = EditorAiAction.explain;
  bool _busy = false;
  String? _result;
  String? _error;

  @override
  void dispose() {
    _ask.dispose();
    super.dispose();
  }

  static const String _system =
      '你是一名资深软件工程师，正在 IDE 里协助用户处理代码。'
      '回答用简体中文，直接给结论和可执行的产物，不要客套。'
      '涉及代码时用 Markdown 代码围栏包裹完整片段。';

  String _prompt(AppLocalizations loc) {
    final lang = widget.language.isEmpty ? '未知语言' : widget.language;
    // 截断：模型上下文有限，整篇几万行会直接 400。
    final body = widget.text.length > 12000
        ? '${widget.text.substring(0, 12000)}\n…（已截断，原文共 ${widget.text.length} 字符）'
        : widget.text;
    const fence = '```';
    final code = '$fence$lang\n$body\n$fence';
    switch (_action) {
      case EditorAiAction.explain:
        return '请解释下面这段 $lang 代码：先用一句话概括用途，再按执行顺序说明关键逻辑，'
            '最后指出可能的坑。不要重复贴大段代码。\n\n$code';
      case EditorAiAction.comment:
        return '给下面这段 $lang 代码加注释：保持代码逻辑与格式不变，只插入必要的注释，'
            '返回**完整代码**（用代码围栏包裹）。注释用中文。\n\n$code';
      case EditorAiAction.review:
        return '以资深工程师视角审查下面这段 $lang 代码：列出问题'
            '（正确性、边界条件、性能、安全、可读性），每条给出具体修改建议，按严重程度排序。'
            '不要整段重写。\n\n$code';
      case EditorAiAction.tests:
        return '为下面这段 $lang 代码生成单元测试：覆盖正常路径、边界和异常，'
            '只输出可直接运行的测试代码（用代码围栏包裹）。\n\n$code';
      case EditorAiAction.improve:
        return '重构下面这段 $lang 代码：保持行为不变，改善可读性与健壮性。'
            '先用三条说明改了什么，再给出完整代码（用代码围栏包裹）。\n\n$code';
      case EditorAiAction.ask:
        final q = _ask.text.trim();
        return '${q.isEmpty ? '请说明这段代码的作用与风险。' : q}\n\n$code';
    }
  }

  Future<void> _run() async {
    if (_busy) return;
    final loc = AppLocalizations.of(context)!;
    if (!AiAnalyzer.isConfigured) {
      setState(() => _error = loc.editorAiNoConfig);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await AiAnalyzer.chat([
        {'role': 'user', 'content': _prompt(loc)}
      ], systemOverride: _system);
      if (!mounted) return;
      setState(() => _result = r);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 去掉最外层代码围栏——插入到编辑器时不需要 ```
  static String _stripFence(String s) {
    final t = s.trim();
    if (!t.startsWith('```')) return t;
    final firstNl = t.indexOf('\n');
    if (firstNl < 0) return t;
    var body = t.substring(firstNl + 1);
    final last = body.lastIndexOf('```');
    if (last >= 0) body = body.substring(0, last);
    return body.trimRight();
  }

  void _insert() {
    final r = _result;
    if (r == null) return;
    widget.onInsert(_stripFence(r));
    Navigator.of(context).maybePop();
  }

  void _replace() {
    final r = _result;
    final cb = widget.onReplace;
    if (r == null || cb == null) return;
    cb(_stripFence(r));
    Navigator.of(context).maybePop();
  }

  Future<void> _copy() async {
    final r = _result;
    if (r == null) return;
    await Clipboard.setData(ClipboardData(text: r));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.copied)));
  }

  String _label(AppLocalizations loc, EditorAiAction a) {
    switch (a) {
      case EditorAiAction.explain:
        return loc.editorAiExplain;
      case EditorAiAction.comment:
        return loc.editorAiComment;
      case EditorAiAction.review:
        return loc.editorAiReview;
      case EditorAiAction.tests:
        return loc.editorAiTests;
      case EditorAiAction.improve:
        return loc.editorAiImprove;
      case EditorAiAction.ask:
        return loc.editorAiAsk;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final height = (MediaQuery.of(context).size.height * 0.6).clamp(280.0, 460.0);
    final width = (MediaQuery.of(context).size.width - 48).clamp(260.0, 560.0);
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
      title: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(loc.editorAiAssist, style: const TextStyle(fontSize: 16))),
          IconButton(
            tooltip: loc.close,
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      content: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in EditorAiAction.values)
                  ChoiceChip(
                    label: Text(_label(loc, a), style: const TextStyle(fontSize: 12)),
                    selected: _action == a,
                    onSelected: (_) => setState(() => _action = a),
                  ),
              ],
            ),
            if (_action == EditorAiAction.ask) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _ask,
                decoration: InputDecoration(
                  hintText: loc.editorAiAskHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _run(),
              ),
            ],
            const SizedBox(height: 10),
            if (_busy) ...[
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 6),
              Text(loc.editorAiThinking,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error, height: 1.5)),
              ),
            if (_result != null)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _result!,
                        style: const TextStyle(fontSize: 12, height: 1.55),
                      ),
                    ),
                  ),
                ),
              )
            else if (!_busy)
              Expanded(
                child: Center(
                  child: Text(
                    AiAnalyzer.isConfigured ? loc.editorAiIdle : loc.editorAiNoConfig,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor, height: 1.6),
                  ),
                ),
              ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      actions: [
        TextButton(
          onPressed: _busy ? null : _run,
          child: Text(_result == null ? loc.editorAiRun : loc.editorAiRegenerate),
        ),
        if (_result != null) TextButton(onPressed: _copy, child: Text(loc.copy)),
        if (_result != null && widget.onReplace != null)
          TextButton(onPressed: _replace, child: Text(loc.editorAiReplace)),
        if (_result != null)
          FilledButton(onPressed: _insert, child: Text(loc.editorAiInsert)),
      ],
    );
  }
}
