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
import 'package:flutter/services.dart';

/// 一条可执行的命令。
class CommandItem {
  /// 唯一标识，用于去重与排序。
  final String id;

  /// 主标题（会参与模糊匹配）。
  final String label;

  /// 次要说明（也会参与匹配，但权重低于 label）。
  final String? hint;

  /// 分组名，用于在结果里分节显示。
  final String group;

  final IconData icon;

  /// 关键词别名，便于用英文/缩写搜到中文命令。
  final List<String> keywords;

  final VoidCallback? onRun;

  const CommandItem({
    required this.id,
    required this.label,
    required this.group,
    required this.icon,
    this.hint,
    this.keywords = const [],
    this.onRun,
  });

  bool get enabled => onRun != null;

  /// 与查询串的匹配得分；null 表示不匹配。
  ///
  /// 打分规则刻意简单：前缀命中 > 连续子串 > 关键词命中，label 优于 hint。
  int? score(String query) {
    if (query.isEmpty) return 0;
    final l = label.toLowerCase();
    if (l.startsWith(query)) return 100 - (l.length - query.length).clamp(0, 50);
    final idx = l.indexOf(query);
    if (idx >= 0) return 80 - idx.clamp(0, 40);
    for (final k in keywords) {
      final kl = k.toLowerCase();
      if (kl.startsWith(query)) return 70;
      if (kl.contains(query)) return 50;
    }
    final hi = hint?.toLowerCase();
    if (hi != null && hi.contains(query)) return 30;
    return null;
  }
}

/// 命令面板：`Ctrl/Cmd + K` 唤起，输入即筛，回车执行。
///
/// 设计目标是「不用记菜单在哪」——所有可跳转的页面与可切换的开关都收敛到这里。
class CommandPalette extends StatefulWidget {
  final List<CommandItem> items;
  final String title;
  final String hint;

  const CommandPalette({
    super.key,
    required this.items,
    required this.title,
    required this.hint,
  });

  /// 弹出命令面板；返回执行过的命令 id（未执行则 null）。
  static Future<String?> show(
    BuildContext context, {
    required List<CommandItem> items,
    required String title,
    required String hint,
  }) {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => CommandPalette(items: items, title: title, hint: hint),
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  var _query = '';
  var _active = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<CommandItem> get _results {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      return widget.items.where((e) => e.enabled).toList();
    }
    final scored = <MapEntry<CommandItem, int>>[];
    for (final item in widget.items) {
      if (!item.enabled) continue;
      final s = item.score(q);
      if (s != null) scored.add(MapEntry(item, s));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList();
  }

  void _move(int delta) {
    final results = _results;
    if (results.isEmpty) return;
    setState(() => _active = (_active + delta).clamp(0, results.length - 1));
  }

  void _run(CommandItem? item) {
    if (item == null || !item.enabled) return;
    Navigator.pop(context, item.id);
    // 关闭面板后再执行，避免命令里再弹对话框时与当前路由打架
    WidgetsBinding.instance.addPostFrameCallback((_) => item.onRun?.call());
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      final results = _results;
      _run(results.isEmpty ? null : results[_active.clamp(0, results.length - 1)]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    if (_active >= results.length) _active = results.isEmpty ? 0 : results.length - 1;

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 90, left: 24, right: 24, bottom: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Row(children: [
              const Icon(Icons.search, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Focus(
                  onKeyEvent: _onKey,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      border: InputBorder.none,
                      isDense: true,
                      hintStyle: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7)),
                    ),
                    onChanged: (v) => setState(() {
                      _query = v;
                      _active = 0;
                    }),
                  ),
                ),
              ),
              Text(widget.title,
                  style: TextStyle(
                      fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color)),
            ]),
          ),
          const Divider(height: 1),
          Flexible(
            child: results.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Text('—', style: TextStyle(fontSize: 18)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: results.length,
                    itemBuilder: (_, i) {
                      final item = results[i];
                      final selected = i == _active;
                      return InkWell(
                        onTap: () => _run(item),
                        onHover: (hovering) {
                          if (hovering) setState(() => _active = i);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                          color: selected
                              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                              : null,
                          child: Row(children: [
                            Icon(item.icon, size: 18, color: Colors.grey),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.label,
                                      style: const TextStyle(fontSize: 13.5),
                                      overflow: TextOverflow.ellipsis),
                                  if (item.hint != null)
                                    Text(item.hint!,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Theme.of(context).textTheme.bodySmall?.color),
                                        overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(item.group,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color
                                        ?.withValues(alpha: 0.8))),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

/// 全局快捷键包装：`Ctrl/Cmd + K` 唤起命令面板。
class CommandPaletteShortcuts extends StatelessWidget {
  final VoidCallback onOpen;
  final Widget child;

  const CommandPaletteShortcuts({super.key, required this.onOpen, required this.child});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): onOpen,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): onOpen,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
