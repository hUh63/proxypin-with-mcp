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

/// 页面底部的「快捷输入行」。
///
/// 两态：
/// * **收起**（默认）—— 一行符号，横向滑动浏览；**向上拖动**或点右侧箭头即可展开；
/// * **展开** —— 顶部是分类标签（当前语言符号 / 共用符号库），下面是成排的符号网格。
///
/// 条目数据沿用 [ToolSnippetStore]：本页列表按 [scope] 持久化，其它页面保存过的
/// 自定义条目都会进「共用符号库」，这里可以直接取用。
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

  /// 展开面板里的当前分类：false = 本页（当前语言）符号，true = 共用符号库。
  bool _showLibrary = false;

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
      setState(() {
        _items = widget.defaults;
        _showLibrary = false;
      });
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

  // ------------------------------------------------------------------ 收起

  Widget _collapsed() {
    return SizedBox(
      height: 38,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 往上拖 = 展开符号面板。
        onVerticalDragUpdate: (details) {
          if (details.delta.dy < -6) setState(() => _expanded = true);
        },
        child: Padding(
          padding: const EdgeInsets.only(left: 8, right: 4),
          child: Row(
            children: [
              Expanded(
                child: _items.isEmpty
                    ? const SizedBox.shrink()
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 2),
                        itemBuilder: (_, i) => Center(child: _cell(_items[i])),
                      ),
              ),
              _iconBtn(Icons.unfold_more, localizations.snippetExpand, () {
                setState(() => _expanded = true);
              }),
              _iconBtn(Icons.tune, localizations.editorManage, _manage),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ 展开

  Widget _expandedView() {
    final list = _showLibrary ? _customLibrary : _items;
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 4, top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _tab(localizations.editorInsertSymbol, !_showLibrary, () {
                setState(() => _showLibrary = false);
              }),
              const SizedBox(width: 4),
              _tab(localizations.snippetCustomLibrary, _showLibrary, () {
                setState(() => _showLibrary = true);
              }),
              const Spacer(),
              _iconBtn(Icons.unfold_less, localizations.snippetCollapse, () {
                setState(() => _expanded = false);
              }),
              _iconBtn(Icons.tune, localizations.editorManage, _manage),
            ],
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 210),
            child: SingleChildScrollView(
              child: list.isEmpty
                  ? SizedBox(
                      height: 34,
                      width: double.infinity,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _showLibrary
                              ? localizations.snippetCustomLibraryEmpty
                              : localizations.snippetManagerEmpty,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ),
                    )
                  : Wrap(
                      spacing: 2,
                      runSpacing: 2,
                      children: list.map(_cell).toList(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 部件

  /// 分类标签（选中态用主题色 + 下划线）。
  Widget _tab(String label, bool selected, VoidCallback onTap) {
    final color = selected ? Theme.of(context).colorScheme.primary : Colors.grey;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: color, width: selected ? 2 : 0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// 一个符号格：纯文字、无边框，方便成排排列。
  Widget _cell(ToolSnippet s) {
    return InkWell(
      onTap: () => widget.onInsert(s.insert),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 46,
        height: 32,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          s.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: widget.labelStyle,
        ),
      ),
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
    return _expanded ? _expandedView() : _collapsed();
  }
}
