/*
 * Copyright 2023 Hongen Wang
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
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/fuzz_dictionary.dart';
import 'package:proxypin/network/util/request_fuzzer.dart';
import 'package:proxypin/ui/component/utils.dart';

/// Fuzz 字典管理：查看 / 新建 / 编辑 / 删除 / 从文件导入 / 试跑脚本。
///
/// 选中一个字典后关闭并把它返回给调用方（由调用方展开成取值填入注入项）。
class FuzzDictionaryDialog extends StatefulWidget {
  const FuzzDictionaryDialog({super.key});

  static Future<FuzzDictionary?> show(BuildContext context) => showDialog<FuzzDictionary>(
        context: context,
        builder: (_) => const FuzzDictionaryDialog(),
      );

  @override
  State<FuzzDictionaryDialog> createState() => _FuzzDictionaryDialogState();
}

class _FuzzDictionaryDialogState extends State<FuzzDictionaryDialog> {
  List<FuzzDictionary> _custom = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await FuzzDictionaryStore.load();
    if (!mounted) return;
    setState(() {
      _custom = list;
      _loaded = true;
    });
  }

  Future<void> _persist() => FuzzDictionaryStore.save(_custom);

  Future<void> _import() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'csv', 'json', 'js'],
    );
    if (files == null || files.isEmpty) return;
    final file = files.first;
    final bytes = await file.readAsBytes();
    final text = utf8.decode(bytes, allowMalformed: true);
    final name = file.name.replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '');

    final isScript = file.name.toLowerCase().endsWith('.js');
    final dictionary = FuzzDictionary(
      name: name.isEmpty ? AppLocalizations.of(context)!.fuzzDictDefaultName : name,
      entries: isScript ? const [] : RequestFuzzer.parsePayloads(text),
      script: isScript ? text : null,
    );
    if (!mounted) return;
    setState(() => _custom.add(dictionary));
    await _persist();
    if (!mounted) return;
    FlutterToastr.show(
        AppLocalizations.of(context)!.fuzzDictImported(dictionary.name),
        context,
        duration: 2);
  }

  Future<void> _edit({FuzzDictionary? dictionary}) async {
    final result = await showDialog<FuzzDictionary>(
      context: context,
      builder: (_) => _DictionaryEditorDialog(dictionary: dictionary),
    );
    if (result == null) return;
    setState(() {
      final index = _custom.indexWhere((e) => e.name == dictionary?.name);
      if (index >= 0) {
        _custom[index] = result;
      } else {
        _custom.add(result);
      }
    });
    await _persist();
  }

  Future<void> _delete(FuzzDictionary dictionary) async {
    // showConfirmDialog 是回调式（无返回值），走 onConfirm
    final loc = AppLocalizations.of(context)!;
    showConfirmDialog(context,
        title: loc.fuzzDictDeleteTitle,
        content: loc.fuzzDictDeleteConfirm(dictionary.name),
        onConfirm: () async {
          setState(() => _custom.removeWhere((e) => e.name == dictionary.name));
          await _persist();
        });
  }

  @override
  Widget build(BuildContext context) {
    final builtins = FuzzDictionaryStore.builtins();
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.fuzzDictTitle,
          style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: !_loaded
            ? const SizedBox(
                height: 80, child: Center(child: CircularProgressIndicator()))
            : ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    AppLocalizations.of(context)!.fuzzDictTips,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Text(AppLocalizations.of(context)!.capturePlanBuiltin,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  for (final d in builtins) _tile(d, builtin: true),
                  const SizedBox(height: 8),
                  Text(AppLocalizations.of(context)!.custom,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  if (_custom.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(AppLocalizations.of(context)!.fuzzDictNoCustom,
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                  for (final d in _custom) _tile(d),
                ],
              ),
      ),
      actions: [
        TextButton(
            onPressed: _import,
            child: Text(AppLocalizations.of(context)!.fuzzDictImportFile)),
        TextButton(
            onPressed: () => _edit(),
            child: Text(AppLocalizations.of(context)!.newBuilt)),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.close)),
      ],
    );
  }

  Widget _tile(FuzzDictionary d, {bool builtin = false}) {
    final parts = <String>[
      AppLocalizations.of(context)!.fuzzDictNEntries(d.entries.length)
    ];
    if (d.hasScript) parts.add(AppLocalizations.of(context)!.script);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(d.name, style: const TextStyle(fontSize: 13)),
      subtitle: Text(parts.join(' · '), style: const TextStyle(fontSize: 11)),
      onTap: () => Navigator.pop(context, d),
      trailing: builtin
          ? const Icon(Icons.lock_outline, size: 16, color: Colors.grey)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                    icon: const Icon(Icons.edit, size: 16),
                    tooltip: AppLocalizations.of(context)!.edit,
                    onPressed: () => _edit(dictionary: d)),
                IconButton(
                    icon: const Icon(Icons.delete, size: 16),
                    tooltip: AppLocalizations.of(context)!.delete,
                    onPressed: () => _delete(d)),
              ],
            ),
    );
  }
}

/// 新建 / 编辑一个字典
class _DictionaryEditorDialog extends StatefulWidget {
  final FuzzDictionary? dictionary;

  const _DictionaryEditorDialog({this.dictionary});

  @override
  State<_DictionaryEditorDialog> createState() => _DictionaryEditorDialogState();
}

class _DictionaryEditorDialogState extends State<_DictionaryEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _entries;
  late final TextEditingController _script;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.dictionary?.name ?? '');
    _entries = TextEditingController(text: (widget.dictionary?.entries ?? const []).join('\n'));
    _script = TextEditingController(text: widget.dictionary?.script ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _entries.dispose();
    _script.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      final values = await FuzzDictionaryStore.resolve(FuzzDictionary(
        name: 'test',
        entries: RequestFuzzer.parsePayloads(_entries.text),
        script: _script.text,
      ));
      if (!mounted) return;
      final preview =
          '${values.take(3).join(' / ')}${values.length > 3 ? ' …' : ''}';
      FlutterToastr.show(
          AppLocalizations.of(context)!.fuzzDictExpanded(values.length, preview),
          context,
          duration: 3);
    } catch (e) {
      if (!mounted) return;
      FlutterToastr.show(
          AppLocalizations.of(context)!.fuzzDictScriptFailed('$e'),
          context,
          duration: 3,
          backgroundColor: Colors.red);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      FlutterToastr.show(
          AppLocalizations.of(context)!.fuzzDictNameRequired, context);
      return;
    }
    Navigator.pop(
      context,
      FuzzDictionary(
        name: name,
        entries: RequestFuzzer.parsePayloads(_entries.text),
        script: _script.text.trim().isEmpty ? null : _script.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
          widget.dictionary == null
              ? AppLocalizations.of(context)!.fuzzDictCreate
              : AppLocalizations.of(context)!.fuzzDictEditTitle,
          style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.name,
                    isDense: true,
                    border: const OutlineInputBorder()),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _entries,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.fuzzerPayloads,
                  hintText: AppLocalizations.of(context)!.fuzzerPayloadsHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _script,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.fuzzDictScriptLabel,
                  hintText: "result = Array.from({length: 8}, (_, i) => 'x'.repeat(i + 1));",
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 6),
              Row(children: [
                TextButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: Text(AppLocalizations.of(context)!.fuzzDictTestRun,
                      style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(AppLocalizations.of(context)!.fuzzDictScriptNote,
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel)),
        FilledButton(
            onPressed: _submit, child: Text(AppLocalizations.of(context)!.save)),
      ],
    );
  }
}
