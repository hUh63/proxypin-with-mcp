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

  const SnippetManagerDialog({
    super.key,
    required this.scope,
    required this.items,
    required this.defaults,
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
  final ScrollController _scroll = ScrollController();

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _rows = widget.items.map((e) => _RowCtl(e.label, e.insert)).toList();
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
            isDense: true,
            decoration: InputDecoration(
              labelText: localizations.snippetManagerLabel,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: row.insert,
            isDense: true,
            decoration: InputDecoration(
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
