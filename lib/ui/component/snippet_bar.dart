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
  List<ToolSnippet> _customLibrary = const [];
  bool _expanded = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SnippetBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 文本编辑页切换语言时 scope 会变，需重新载入该格式的条目与默认。
    if (oldWidget.scope != widget.scope) {
      setState(() => _items = widget.defaults);
      _load();
    }
  }

  Future<void> _load() async {
    final saved = await ToolSnippetStore.load(widget.scope);
    final lib = await ToolSnippetStore.loadCustom();
    if (!mounted) return;
    setState(() {
      if (saved != null) _items = saved;
      _customLibrary = lib;
    });
  }

  Future<void> _manage() async {
    final before = _items;
    final result = await showDialog<List<ToolSnippet>>(
      context: context,
      builder: (_) => SnippetManagerDialog(
        scope: widget.scope,
        items: _items,
        defaults: widget.defaults,
        customLibrary: _customLibrary,
      ),
    );
    if (!mounted) return;
    // 对话框里可能增删改过共用库，统一重载一次。
    final lib = await ToolSnippetStore.loadCustom();
    if (!mounted) return;
    setState(() => _customLibrary = lib);
    if (result == null) return;
    setState(() => _items = result);
    await ToolSnippetStore.save(widget.scope, result);
    // 本次新增的条目 → 追加进全局共用库，其他页面即可一键取用。
    final known = <String>{for (final e in before) e.insert};
    final added = result.where((e) => !known.contains(e.insert)).toList();
    if (added.isNotEmpty) {
      final updated = await ToolSnippetStore.appendCustom(added);
      if (mounted) setState(() => _customLibrary = updated);
    }
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

    // 展开态：条目在上、操作行在下 —— 因为输入行位于页面底部，这样展开时是往上生长。
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 6, top: 2, bottom: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 170),
          child: SingleChildScrollView(
            child: _items.isEmpty
                ? const SizedBox(height: 4, width: double.infinity)
                : Wrap(spacing: 6, runSpacing: 6, children: _items.map(_chip).toList()),
          ),
        ),
        const SizedBox(height: 2),
        Row(children: [
          Text(localizations.editorInsertSymbol, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const Spacer(),
          _iconBtn(Icons.unfold_less, localizations.snippetCollapse, () => setState(() => _expanded = false)),
          _iconBtn(Icons.tune, localizations.editorManage, _manage),
        ]),
      ]),
    );
  }
}
