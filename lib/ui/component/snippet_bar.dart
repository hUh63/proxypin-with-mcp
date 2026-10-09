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

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/component/snippet_manager.dart';
import 'package:proxypin/utils/tool_snippets.dart';

/// 可滑动 + 可展开的「快捷输入行」。
///
/// - 收起：单行，横向滑动浏览；点「展开」变为多行铺开（限高可滚）。
/// - 右侧「管理」打开 [SnippetManagerDialog]，增删改后按 [scope] 持久化。
/// - 条目数据沿用 [ToolSnippetStore]，与旧版单页插入完全兼容。
class SnippetBar extends StatefulWidget {
  /// 持久化作用域（如 'editor' / 'json' / 'xml' / 'diff' / 'regexp'）。
  final String scope;

  /// 内置默认条目（用户未自定义时使用）。
  final List<ToolSnippet> defaults;

  /// 点击条目时把插入文本回调给页面。
  final void Function(String insert) onInsert;

  /// 条目文字样式。
  final TextStyle labelStyle;

  const SnippetBar({
    super.key,
    required this.scope,
    required this.defaults,
    required this.onInsert,
    this.labelStyle = const TextStyle(fontSize: 12, fontFamily: 'monospace'),
  });

  @override
  State<SnippetBar> createState() => _SnippetBarState();
}

class _SnippetBarState extends State<SnippetBar> {
  late List<ToolSnippet> _items = widget.defaults;
  bool _expanded = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await ToolSnippetStore.load(widget.scope);
    if (!mounted || saved == null) return;
    setState(() => _items = saved);
  }

  Future<void> _manage() async {
    final result = await showDialog<List<ToolSnippet>>(
      context: context,
      builder: (_) => SnippetManagerDialog(
        scope: widget.scope,
        items: _items,
        defaults: widget.defaults,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _items = result);
    await ToolSnippetStore.save(widget.scope, result);
  }

  Widget _chip(ToolSnippet s) {
    return ActionChip(
      label: Text(s.label, style: widget.labelStyle),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onPressed: () => widget.onInsert(s.insert),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(padding: const EdgeInsets.all(5), child: Icon(icon, size: 18)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.only(left: 8, right: 6, top: 2, bottom: 2),
          child: Row(children: [
            Expanded(
              child: _items.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, i) => Center(child: _chip(_items[i])),
                    ),
            ),
            _iconBtn(Icons.unfold_more, localizations.snippetExpand, () => setState(() => _expanded = true)),
            _iconBtn(Icons.tune, localizations.editorManage, _manage),
          ]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 6, top: 2, bottom: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(localizations.editorInsertSymbol, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const Spacer(),
          _iconBtn(Icons.unfold_less, localizations.snippetCollapse, () => setState(() => _expanded = false)),
          _iconBtn(Icons.tune, localizations.editorManage, _manage),
        ]),
        const SizedBox(height: 2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 170),
          child: SingleChildScrollView(
            child: _items.isEmpty
                ? const SizedBox(height: 4, width: double.infinity)
                : Wrap(spacing: 6, runSpacing: 6, children: _items.map(_chip).toList()),
          ),
        ),
      ]),
    );
  }
}
