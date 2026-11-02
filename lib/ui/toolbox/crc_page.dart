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

// CRC 工具：算 CRC32、看 zip/apk 每个条目的 CRC、按需改写条目 CRC。
//
// 用途是对「只校验目录 CRC 不看实际数据」的检查做一致性验证（自测 / 兼容性排查），
// 改完不重打包、只动 4 个字节，所以很快。

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/component/tool_kit.dart';
import 'package:proxypin/utils/smali_tool.dart';

class CrcPage extends StatefulWidget {
  const CrcPage({super.key});

  @override
  State<CrcPage> createState() => _CrcPageState();
}

class _CrcPageState extends State<CrcPage> {
  String _path = '';
  Uint8List? _bytes;
  int _fileCrc = 0;
  List<ZipEntryInfo>? _entries;
  int? _selected;
  final _newCrc = TextEditingController();
  bool _dirty = false;

  @override
  void dispose() {
    _newCrc.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    FlutterToastr.show(msg, context, duration: 2);
  }

  Future<void> _pick() async {
    final loc = AppLocalizations.of(context)!;
    try {
      final file = await FilePicker.pickFile();
      if (file == null) return;
      final bytes = await File(file.xFile.path).readAsBytes();
      if (!mounted) return;
      setState(() {
        _path = file.name;
        _bytes = bytes;
        _fileCrc = Crc32Tool.compute(bytes);
        _entries = ZipCrcEditor.readEntries(bytes);
        _selected = null;
        _dirty = false;
        _newCrc.text = '';
      });
      if (_entries == null) _toast(loc.crcNotZip);
    } catch (e) {
      _toast('${AppLocalizations.of(context)!.fail}: $e');
    }
  }

  /// 只改内存里的字节；真正落盘走「另存为」，不动原文件。
  void _applyToSelected() {
    final loc = AppLocalizations.of(context)!;
    final bytes = _bytes;
    final idx = _selected;
    if (bytes == null || idx == null) {
      _toast(loc.crcPickEntryFirst);
      return;
    }
    final parsed = int.tryParse(_newCrc.text.trim().replaceFirst('0x', ''), radix: 16);
    if (parsed == null) {
      _toast(loc.crcInvalidValue);
      return;
    }
    final patched = ZipCrcEditor.patchEntryCrc(bytes, idx, parsed & 0xFFFFFFFF);
    setState(() {
      _bytes = patched;
      _fileCrc = Crc32Tool.compute(patched);
      _entries = ZipCrcEditor.readEntries(patched);
      _dirty = true;
    });
    _toast(loc.crcPatched);
  }

  /// 把选中条目的 CRC 改成「随便一个别的值」（测试用）。
  void _randomize() {
    final entries = _entries;
    final idx = _selected;
    if (entries == null || idx == null) return;
    final v = (entries[idx].crc ^ 0x00000001) & 0xFFFFFFFF;
    _newCrc.text = Crc32Tool.hex(v);
    setState(() {});
  }

  Future<void> _saveAs() async {
    final loc = AppLocalizations.of(context)!;
    final bytes = _bytes;
    if (bytes == null) return;
    try {
      final name = _path.isEmpty ? 'patched.bin' : _path;
      await FilePicker.saveFile(fileName: name, bytes: bytes);
      if (!mounted) return;
      setState(() => _dirty = false);
      _toast(loc.saveSuccess);
    } catch (e) {
      _toast('${loc.fail}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final entries = _entries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRC32'),
        actions: [
          if (_bytes != null)
            IconButton(
              tooltip: loc.saveAs,
              icon: Icon(Icons.save_alt, color: _dirty ? theme.colorScheme.primary : null),
              onPressed: _saveAs,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
        children: [
          ToolIntro(
            margin: EdgeInsets.zero,
            text: '算文件 CRC32、看 zip/apk 里每个条目的 CRC，必要时只改那 4 个字节（不重新打包）。',
            input: '选一个文件（任意文件算整体 CRC；zip/apk 额外列出条目）',
            output: '整体 CRC32 + 条目表；选中条目可改成指定值并另存',
            help: '常见用法：服务端/校验工具只比对条目 CRC 时，验证「改内容不改 CRC」是否被放行。'
                '改写只动中央目录里的 4 字节，文件其余部分完全不变；改完用右上角另存，不覆盖原文件。',
          ),
          const SizedBox(height: 6),
          Row(children: [
            FilledButton.tonalIcon(
              onPressed: _pick,
              icon: const Icon(Icons.folder_open, size: 16),
              label: Text(loc.crcPickFile, style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 8),
            if (_path.isNotEmpty)
              Expanded(
                child: Text(_path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
              ),
          ]),
          if (_bytes != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(8),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
              child: Row(children: [
                Text('${loc.crcWholeFile}: ', style: const TextStyle(fontSize: 12)),
                SelectableText(Crc32Tool.hex(_fileCrc),
                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                const SizedBox(width: 12),
                Text('${_bytes!.length} B',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                const Spacer(),
                IconButton(
                  tooltip: loc.copy,
                  iconSize: 15,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.copy_all_outlined),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: Crc32Tool.hex(_fileCrc)));
                    _toast(loc.copied);
                  },
                ),
              ]),
            ),
            if (entries != null) ...[
              const SizedBox(height: 12),
              Text('${loc.crcEntries} (${entries.length})',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(border: Border.all(color: theme.dividerColor)),
                child: Column(children: [
                  for (var i = 0; i < entries.length; i++)
                    InkWell(
                      onTap: () => setState(() {
                        _selected = i;
                        _newCrc.text = Crc32Tool.hex(entries[i].crc);
                      }),
                      child: Container(
                        color: _selected == i
                            ? theme.colorScheme.primary.withValues(alpha: 0.12)
                            : null,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        child: Row(children: [
                          Expanded(
                            child: Text(entries[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                          ),
                          const SizedBox(width: 8),
                          Text(Crc32Tool.hex(entries[i].crc),
                              style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace')),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 62,
                            child: Text('${entries[i].uncompressedSize}',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                          ),
                        ]),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _newCrc,
                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText: loc.crcNewValue,
                      hintText: 'DEADBEEF',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton(onPressed: _randomize, child: Text(loc.crcRandom)),
                const SizedBox(width: 6),
                FilledButton(onPressed: _applyToSelected, child: Text(loc.crcApply)),
              ]),
              const SizedBox(height: 6),
              Text(loc.crcWarn,
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.error)),
            ],
          ],
        ],
      ),
    );
  }
}
