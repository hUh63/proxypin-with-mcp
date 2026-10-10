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
import 'package:proxypin/utils/tool_snippets.dart';

/// 快捷插入条目管理对话框（增删改 + 恢复默认）。
///
/// 确认时通过 `Navigator.pop` 返回新的完整列表；取消返回 null。
class SnippetManagerDialog extends StatefulWidget {
  final String scope;
  final List<ToolSnippet> items;
  final List<ToolSnippet> defaults;

  /// 全局「共用符号库」：其他页面新增过的自定义条目，点一下即可加到本页。
  final List<ToolSnippet> customLibrary;

  const SnippetManagerDialog({
    super.key,
    required this.scope,
    required this.items,
    required this.defaults,
    this.customLibrary = const [],
  });

  @override
  State<SnippetManagerDialog> createState() => _SnippetManagerDialogState();
}

class _RowCtl {
  final TextEditingController label;
  final TextEditingController insert;

  _RowCtl(String l, String i)
      : label = TextEditingController(text: l),
        insert = TextEditingController(text: i);

  void dispose() {
    label.dispose();
    insert.dispose();
  }
}

class _SnippetManagerDialogState extends State<SnippetManagerDialog> {
  late List<_RowCtl> _rows;
  late List<ToolSnippet> _library;
  final ScrollController _scroll = ScrollController();

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _rows = widget.items.map((e) => _RowCtl(e.label, e.insert)).toList();
    _library = [...widget.customLibrary];
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _addRow() {
    _rows.add(_RowCtl('', ''));
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  /// 把共用库里的条目加进本页（按插入文本去重）。
  void _addFromLibrary(ToolSnippet s) {
    if (_rows.any((r) => r.insert.text == s.insert)) return;
    _rows.add(_RowCtl(s.label, s.insert));
    setState(() {});
  }

  Future<void> _removeFromLibrary(ToolSnippet s) async {
    final lib = await ToolSnippetStore.removeCustom(s.insert);
    if (!mounted) return;
    setState(() => _library = lib);
  }

  Future<void> _clearLibrary() async {
    await ToolSnippetStore.clearCustom();
    if (!mounted) return;
    setState(() => _library = const []);
  }

  /// 长按共用库条目 → 编辑（标题 + 内容都能改）。
  Future<void> _editLibraryItem(ToolSnippet s) async {
    final labelCtl = TextEditingController(text: s.label);
    final insertCtl = TextEditingController(text: s.insert);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.edit),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: labelCtl,
            decoration: InputDecoration(
              isDense: true,
              labelText: localizations.snippetManagerLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: insertCtl,
            decoration: InputDecoration(
              isDense: true,
              labelText: localizations.snippetManagerInsert,
              border: const OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(localizations.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(localizations.confirm)),
        ],
      ),
    );
    if (ok != true) {
      labelCtl.dispose();
      insertCtl.dispose();
      return;
    }
    final insert = insertCtl.text;
    final label = labelCtl.text.trim();
    labelCtl.dispose();
    insertCtl.dispose();
    if (!mounted || insert.isEmpty) return;
    final lib = await ToolSnippetStore.updateCustom(
        s.insert, ToolSnippet(label.isEmpty ? insert : label, insert));
    if (!mounted) return;
    // 本页列表里若也有这条，一并改掉，免得再点一次又回到旧值。
    for (final r in _rows) {
      if (r.insert.text == s.insert) {
        r.label.text = label.isEmpty ? insert : label;
        r.insert.text = insert;
      }
    }
    setState(() => _library = lib);
  }

  void _resetToDefaults() {
    for (final r in _rows) {
      r.dispose();
    }
    _rows = widget.defaults.map((e) => _RowCtl(e.label, e.insert)).toList();
    setState(() {});
  }

  List<ToolSnippet> _collect() {
    final out = <ToolSnippet>[];
    for (final r in _rows) {
      final insert = r.insert.text;
      if (insert.isEmpty) continue;
      final label = r.label.text.trim();
      out.add(ToolSnippet(label.isEmpty ? insert : label, insert));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(localizations.snippetManagerTitle),
      content: SizedBox(
        width: 420,
        height: 400,
        child: Column(children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              localizations.snippetManagerHint,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _rows.isEmpty
                ? Center(
                    child: Text(localizations.snippetManagerEmpty,
                        style: const TextStyle(color: Colors.grey)))
                : ListView.builder(
                    controller: _scroll,
                    itemCount: _rows.length,
                    itemBuilder: (context, i) => _row(i),
                  ),
          ),
          const SizedBox(height: 4),
          Row(children: [
            TextButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add, size: 18),
              label: Text(localizations.add),
            ),
            TextButton.icon(
              onPressed: _resetToDefaults,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: Text(localizations.snippetManagerReset),
            ),
          ]),
          if (_library.isNotEmpty) ...[
            const Divider(height: 18),
            Row(children: [
              Expanded(
                child: Text(localizations.snippetCustomLibrary,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ),
              // 清空整个共用库。
              InkWell(
                onTap: _clearLibrary,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(localizations.clear,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 110),
              child: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _library
                        .map((s) => GestureDetector(
                              // 长按 → 编辑这条共用符号。
                              onLongPress: () => _editLibraryItem(s),
                              child: InputChip(
                                label: Text(s.label,
                                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                onPressed: () => _addFromLibrary(s),
                                // 右侧 × → 从共用库里删掉。
                                onDeleted: () => _removeFromLibrary(s),
                                deleteIcon: const Icon(Icons.close, size: 14),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(localizations.cancel)),
        FilledButton(
          onPressed: () => Navigator.pop(context, _collect()),
          child: Text(localizations.confirm),
        ),
      ],
    );
  }

  Widget _row(int i) {
    final row = _rows[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(
          width: 110,
          child: TextField(
            controller: row.label,
            decoration: InputDecoration(
              isDense: true,
              labelText: localizations.snippetManagerLabel,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: row.insert,
            decoration: InputDecoration(
              isDense: true,
              labelText: localizations.snippetManagerInsert,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 18),
          tooltip: localizations.delete,
          onPressed: () {
            final removed = _rows.removeAt(i);
            removed.dispose();
            setState(() {});
          },
        ),
      ]),
    );
  }
}
