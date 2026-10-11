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
import 'package:proxypin/utils/find_history.dart';

/// 编辑器底部的「查找 / 替换」面板。
///
/// 它和「快捷输入行」上下相邻：符号条在上，本面板在符号条**下方**（都贴在页面底部）。
///
/// 两种状态（点查找框右侧的箭头切换）：
/// * **收起**（默认）—— 查找行 + 匹配开关（`Aa` / `W` / `.*`）+ 操作行
///   （上一个 / 下一个 / 替换 / 全部替换 / 关闭）；
/// * **展开** —— 额外显示「搜索结果计数」和「替换输入框」。
///
/// 查找框右侧的 ▼ 是**历史记录**：随时可以取用历史查找词，也能把常用词收藏起来。
class FindPanelView extends StatefulWidget implements PreferredSizeWidget {
  final FindController controller;

  const FindPanelView({super.key, required this.controller});

  /// 给「仍被 CodeForge 当作 slot 使用」的场景（如 JS 运行页、重写页）一个合理高度；
  /// 在我们自己放进页面底部 Column 的用法里，这个值不影响布局。
  @override
  Size get preferredSize => controller.isActive
      ? Size(double.infinity, controller.isReplaceMode ? 150 : 108)
      : const Size(double.infinity, 0);

  @override
  State<FindPanelView> createState() => _FindPanelViewState();
}

class _FindPanelViewState extends State<FindPanelView> with SingleTickerProviderStateMixin {
  List<String> _favorites = const [];
  List<String> _history = const [];

  /// 面板「长出来 / 收回去」的过渡（约 170ms，够了，不拖沓）。
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 170),
    reverseDuration: const Duration(milliseconds: 130),
  );

  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _anim,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  FindController get controller => widget.controller;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _reload();
    widget.controller.addListener(_syncAnim);
    _syncAnim();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncAnim);
    _curve.dispose();
    _anim.dispose();
    super.dispose();
  }

  /// 跟随 controller 的激活状态驱动展开 / 收起动画。
  void _syncAnim() {
    if (widget.controller.isActive) {
      if (_anim.status == AnimationStatus.dismissed || _anim.status == AnimationStatus.reverse) {
        _anim.forward();
      }
    } else if (_anim.status != AnimationStatus.dismissed) {
      _anim.reverse();
    }
  }

  /// 展开中的内容增长（如点 ▼ 展开替换行）也走同一套缓动。
  Widget _animatedBody(BuildContext context) {
    final body = _panel(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: body,
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncAnim();
    final active = widget.controller.isActive;
    // 收起动画播完就彻底移除，不留空位。
    if (!active && _anim.status == AnimationStatus.dismissed) {
      return const SizedBox(width: double.infinity);
    }
    return SizeTransition(
      sizeFactor: _curve,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: _curve,
        child: active || _anim.status != AnimationStatus.dismissed
            ? _animatedBody(context)
            : const SizedBox(width: double.infinity),
      ),
    );
  }

  Future<void> _reload() async {
    final favorites = await FindHistory.loadFavorites();
    final history = await FindHistory.loadHistory();
    if (!mounted) return;
    setState(() {
      _favorites = favorites;
      _history = history;
    });
  }

  bool get _isCurrentFavorite =>
      _favorites.contains(controller.findInputController.text.trim());

  /// 面板本体（行布局）。显隐 / 高度动画由外面的 [build] 负责。
  Widget _panel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expanded = controller.isReplaceMode;
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
            if (expanded) _resultRow(context),
            _findRow(context),
            if (expanded) _replaceRow(context),
            if (!expanded) _optionRow(context),
            _actionRow(context),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ 行

  /// 展开态：搜索结果计数 + 匹配选项。
  Widget _resultRow(BuildContext context) {
    final count = controller.matchCount;
    return Wrap(
      spacing: 8,
      runSpacing: 0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${localizations.findResults}: $count',
          style: TextStyle(
            fontSize: 12,
            color: count == 0 ? Colors.grey : Colors.orange,
          ),
        ),
        ..._options(context),
      ],
    );
  }

  /// 收起态：匹配选项单独一行（展开态里它在结果行右侧）。
  Widget _optionRow(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: _options(context),
    );
  }

  List<Widget> _options(BuildContext context) => [
        _toggle(context, 'Aa', controller.caseSensitive, controller.toggleCaseSensitive,
            localizations.findCaseSensitive),
        _toggle(context, 'W', controller.matchWholeWord, controller.toggleMatchWholeWord,
            localizations.findWholeWord),
        _toggle(context, '.*', controller.isRegex, controller.toggleRegex, localizations.findRegex),
      ];

  Widget _findRow(BuildContext context) {
    return Row(
      children: [
        Text(localizations.search, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 8),
        Expanded(
          child: _input(
            controller.findInputController,
            controller.findInputFocusNode,
            onSubmit: (value) async {
              await FindHistory.record(value);
              await _reload();
              controller.next();
            },
          ),
        ),
        // 历史记录 / 收藏
        IconButton(
          icon: const Icon(Icons.history, size: 18),
          tooltip: localizations.findHistory,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          onPressed: _showHistory,
        ),
        IconButton(
          icon: Icon(
            controller.isReplaceMode ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
            size: 20,
          ),
          tooltip: localizations.replace,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          onPressed: controller.toggleReplaceMode,
        ),
      ],
    );
  }

  Widget _replaceRow(BuildContext context) {
    return Row(
      children: [
        Text(localizations.replace, style: const TextStyle(fontSize: 12)),
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
        const SizedBox(width: 60),
      ],
    );
  }

  Widget _actionRow(BuildContext context) {
    final none = controller.matchCount == 0;
    // 用 Wrap：窄屏（手机）放不下时自动换行，不会把“关闭”挤出屏幕。
    return Wrap(
      spacing: 2,
      runSpacing: 0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _textButton(localizations.findPrevious, none ? null : controller.previous),
        _textButton(localizations.findNext, none ? null : controller.next),
        _textButton(localizations.replace, none ? null : controller.replace),
        _textButton(localizations.findReplaceAll, none ? null : controller.replaceAll),
        _textButton(localizations.close, controller.toggleActive),
      ],
    );
  }

  // -------------------------------------------------------- 历史记录 / 收藏

  Future<void> _showHistory() async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final anchor = box != null && box.hasSize ? box.localToGlobal(Offset.zero) : Offset.zero;
    final favorites = _favorites;
    final history = _history.where((e) => !favorites.contains(e)).toList();

    final items = <PopupMenuEntry<String>>[];
    if (favorites.isNotEmpty) {
      items.add(_header(localizations.findFavorites));
      for (final f in favorites) {
        items.add(_entry('fav:$f', f, starred: true));
      }
      if (history.isNotEmpty) items.add(const PopupMenuDivider());
    }
    if (history.isNotEmpty) {
      if (favorites.isNotEmpty) items.add(_header(localizations.findHistory));
      for (final h in history) {
        items.add(_entry('his:$h', h, starred: false));
      }
    }
    if (favorites.isEmpty && history.isEmpty) {
      items.add(_header(localizations.findEmptyHistory));
    }
    items.add(const PopupMenuDivider());
    items.add(PopupMenuItem<String>(
      value: 'favorite',
      height: 38,
      child: Text(_isCurrentFavorite ? localizations.findUnfavoriteCurrent : localizations.findFavoriteCurrent),
    ));
    if (history.isNotEmpty) {
      items.add(PopupMenuItem<String>(
        value: 'clear',
        height: 38,
        child: Text(localizations.findClearHistory),
      ));
    }

    final chosen = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(anchor, anchor + const Offset(1, 1)),
        Offset.zero & (overlay?.size ?? MediaQuery.of(context).size),
      ),
      items: items,
    );
    if (chosen == null) return;

    if (chosen.startsWith('fav:') || chosen.startsWith('his:')) {
      final value = chosen.substring(4);
      controller.findInputController.text = value;
      controller.findInputFocusNode.requestFocus();
      return;
    }
    if (chosen == 'favorite') {
      await FindHistory.toggleFavorite(controller.findInputController.text);
      await _reload();
      return;
    }
    if (chosen == 'clear') {
      await FindHistory.clearHistory();
      await _reload();
    }
  }

  PopupMenuEntry<String> _header(String text) {
    return PopupMenuItem<String>(
      enabled: false,
      height: 30,
      child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    );
  }

  PopupMenuEntry<String> _entry(String value, String label, {required bool starred}) {
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      child: Row(
        children: [
          Icon(starred ? Icons.star : Icons.history,
              size: 15, color: starred ? Colors.amber : Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}
