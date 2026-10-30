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
/// 顶部是一条**拖动柄**（小横线）：点一下切换，或者直接上下拖动 ——
/// 拖动过程中面板高度**跟着手指走**，松手后按位置吸附到展开 / 收起并带过渡动画。
///
/// * **收起**（默认）—— 一行符号，横向滑动浏览；
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
  /// 展开面板的最大高度。
  /// 展开态的「理想」高度。
  static const double _prefMaxExtent = 236;

  /// 超过这个比例就吸附成「展开」。
  static const double _snapRatio = 0.35;

  late List<ToolSnippet> _items = widget.defaults;
  List<ToolSnippet> _customLibrary = const [];

  /// 展开面板里的当前分类：false = 本页（当前语言）符号，true = 共用符号库。
  bool _showLibrary = false;

  /// 当前展开高度（0 = 收起）。拖动时实时变化，松手后动画吸附。
  double _extent = 0;

  /// 展开态最大高度：默认 236dp，但横屏 / 分屏 / 键盘弹出时最多占「可用高度」的 45%。
  ///
  /// 固定 236 在 360dp 高的横屏上会把编辑区挤到只剩几十 dp；键盘弹出时同理
  /// （`MediaQuery.size` 不含键盘，得自己扣 `viewInsets`）。
  double get _maxExtent {
    final media = MediaQuery.of(context);
    final usable = media.size.height - media.viewInsets.bottom;
    final limit = usable * 0.45;
    return limit < _prefMaxExtent ? limit.clamp(72.0, _prefMaxExtent) : _prefMaxExtent;
  }
  bool _dragging = false;

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
    final recent = await ToolSnippetStore.loadRecent();
    if (!mounted) return;
    setState(() {
      if (saved != null) _items = saved;
      _customLibrary = lib;
      _items = _sortByRecent(_items, recent);
    });
  }

  /// 最近用过的排前面，其余保持原顺序（稳定）。
  static List<ToolSnippet> _sortByRecent(List<ToolSnippet> items, List<String> recent) {
    if (recent.isEmpty) return items;
    final rank = <String, int>{};
    for (var i = 0; i < recent.length; i++) {
      rank[recent[i]] = i;
    }
    final sorted = List<ToolSnippet>.from(items);
    sorted.sort((a, b) {
      final ra = rank[a.insert];
      final rb = rank[b.insert];
      if (ra == null && rb == null) return 0;
      if (ra == null) return 1;
      if (rb == null) return -1;
      return ra.compareTo(rb);
    });
    return sorted;
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

  void _toggle() {
    setState(() => _extent = _extent > 0 ? 0 : _maxExtent);
  }

  // ---------------------------------------------------------------- 拖动柄

  /// 顶部小横线：点一下切换，上下拖动时面板高度跟手，松手吸附。
  Widget _dragHandle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      onVerticalDragStart: (_) {
        _dragging = true;
      },
      onVerticalDragUpdate: (details) {
        setState(() {
          _extent = (_extent - details.delta.dy).clamp(0, _maxExtent);
        });
      },
      onVerticalDragEnd: (_) {
        _dragging = false;
        final open = _extent > _maxExtent * _snapRatio;
        setState(() => _extent = open ? _maxExtent : 0);
      },
      onVerticalDragCancel: () {
        _dragging = false;
        setState(() => _extent = _extent > _maxExtent * _snapRatio ? _maxExtent : 0);
      },
      child: SizedBox(
        height: 14,
        width: double.infinity,
        child: Center(
          child: Container(
            width: 46,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ 收起

  Widget _collapsedRow() {
    return SizedBox(
      height: 36,
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
            _iconBtn(Icons.tune, localizations.editorManage, _manage),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ 展开

  Widget _expandedView() {
    final list = _showLibrary ? _customLibrary : _items;
    return SizedBox(
      height: _maxExtent - 2,
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 4, bottom: 4),
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
                _iconBtn(Icons.tune, localizations.editorManage, _manage),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: list.isEmpty
                  ? Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        _showLibrary
                            ? localizations.snippetCustomLibraryEmpty
                            : localizations.snippetManagerEmpty,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Wrap(
                        spacing: 2,
                        runSpacing: 2,
                        children: list.map(_cell).toList(),
                      ),
                    ),
            ),
          ],
        ),
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
      onTap: () {
        widget.onInsert(s.insert);
        // 记一笔「最近使用」，下次打开就排到前面。
        ToolSnippetStore.recordUse(s.insert).ignore();
      },
      borderRadius: BorderRadius.circular(4),
      // 宽度跟着文字走（46～110）：固定 46 会把 `#include <iostream>` 这类
      // 直接截成 `#inc...`，等于把信息全砍掉了。
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 46, maxWidth: 110),
        child: Container(
          height: 30,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Text(
            s.label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: widget.labelStyle,
          ),
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 键盘弹出来了（viewInsets 变大）：展开态这时会把编辑区挤没，自动收起。
    // 只在展开态处理，用户收起后不再动。
    if (MediaQuery.of(context).viewInsets.bottom > 0 && _extent > 0 && !_dragging) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _extent > 0 && !_dragging) setState(() => _extent = 0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dragHandle(),
        // 展开的面板：高度带动画（拖动时 0 时长 → 跟手；松手 200ms 吸附）。
        TweenAnimationBuilder<double>(
          tween: Tween<double>(end: _extent.clamp(0.0, _maxExtent)),
          duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          builder: (_, height, __) => SizedBox(
            height: height,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: 0,
                maxHeight: _maxExtent,
                child: _expandedView(),
              ),
            ),
          ),
        ),
        _collapsedRow(),
      ],
    );
  }
}
