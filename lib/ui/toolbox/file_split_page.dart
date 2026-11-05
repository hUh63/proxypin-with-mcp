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

// 文件拆分 / 合并页。分片落在应用文档目录，完成后可直接分享（邮件 / 聊天工具发出去）。

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:path_provider/path_provider.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/file_splitter.dart';
import 'package:share_plus/share_plus.dart';

class FileSplitPage extends StatefulWidget {
  const FileSplitPage({super.key});

  @override
  State<FileSplitPage> createState() => _FileSplitPageState();
}

class _FileSplitPageState extends State<FileSplitPage> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  final _sizeMb = TextEditingController(text: '8');
  final _count = TextEditingController(text: '4');
  bool _byCount = false;

  File? _source;
  List<SplitPart> _parts = [];
  double _progress = 0;
  bool _busy = false;
  bool _cancel = false;
  String? _mergedPath;
  int _mergedBytes = 0;

  @override
  void dispose() {
    _tab.dispose();
    _sizeMb.dispose();
    _count.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    FlutterToastr.show(msg, context, duration: 2);
  }

  Future<void> _pickSource() async {
    try {
      final f = await FilePicker.pickFile();
      if (f == null) return;
      if (!mounted) return;
      setState(() {
        _source = File(f.xFile.path);
        _parts = [];
        _progress = 0;
      });
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _split() async {
    final loc = AppLocalizations.of(context)!;
    final src = _source;
    if (src == null || _busy) return;
    final mb = double.tryParse(_sizeMb.text.trim()) ?? 8;
    final count = int.tryParse(_count.text.trim()) ?? 4;
    setState(() {
      _busy = true;
      _cancel = false;
      _progress = 0;
    });
    try {
      final docs = await getApplicationDocumentsDirectory();
      final base = src.path.split(Platform.pathSeparator).last;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final outDir = Directory('${docs.path}${Platform.pathSeparator}split${Platform.pathSeparator}${base}_$stamp');
      final parts = _byCount
          ? await FileSplitter.splitByCount(src,
              outDir: outDir,
              count: count,
              onProgress: _onProgress,
              isCancelled: () => _cancel)
          : await FileSplitter.splitBySize(src,
              outDir: outDir,
              // 上限 256MB：分片是整块读进内存再写出，再大就是拿内存赌运气。
              chunkSize: (mb * 1024 * 1024).round().clamp(1, 256 * 1024 * 1024),
              onProgress: _onProgress,
              isCancelled: () => _cancel);
      if (!mounted) return;
      setState(() {
        _parts = parts;
        _busy = false;
      });
      _toast(_cancel ? loc.fileSplitStopped : loc.fileSplitDone('${parts.length}'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('${loc.fail}: $e');
    }
  }

  void _onProgress(double p) {
    if (!mounted) return;
    setState(() => _progress = p.clamp(0, 1));
  }

  Future<void> _shareParts() async {
    if (_parts.isEmpty) return;
    try {
      await SharePlus.instance.share(ShareParams(
        files: _parts.map((p) => XFile(p.path)).toList(),
      ));
    } catch (e) {
      _toast('$e');
    }
  }

  /// 选一个 part → 自动找同目录的其他 part → 拼成一个文件。
  Future<void> _merge() async {
    final loc = AppLocalizations.of(context)!;
    if (_busy) return;
    try {
      final picked = await FilePicker.pickFile();
      if (picked == null) return;
      final file = File(picked.xFile.path);
      final dir = file.parent;
      final parts = await FileSplitter.findParts(dir);
      if (parts.isEmpty) {
        _toast(loc.fileMergeNoParts);
        return;
      }
      setState(() {
        _busy = true;
        _progress = 0;
      });
      final docs = await getApplicationDocumentsDirectory();
      final merged = '${docs.path}${Platform.pathSeparator}merged_${DateTime.now().millisecondsSinceEpoch}.bin';
      final size = await FileSplitter.merge(parts, outPath: merged, onProgress: _onProgress);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _mergedPath = merged;
        _mergedBytes = size;
      });
      // 不把合并结果读进内存再「另存为」：几百 MB 会直接把内存打满。
      // 留在应用目录里给路径 + 分享按钮，效果一样。
      _toast(loc.fileMergeDone('${parts.length}', '$size'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.fileSplitTitle),
        bottom: TabBar(controller: _tab, tabs: [
          Tab(text: loc.fileSplit),
          Tab(text: loc.fileMerge),
        ]),
      ),
      body: TabBarView(controller: _tab, children: [
        ListView(padding: const EdgeInsets.all(12), children: [
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _pickSource,
            icon: const Icon(Icons.folder_open, size: 16),
            label: Text(loc.crcPickFile),
          ),
          if (_source != null) ...[
            const SizedBox(height: 8),
            Text(_source!.path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace')),
          ],
          const SizedBox(height: 12),
          Row(children: [
            ChoiceChip(
              label: Text(loc.fileSplitBySize, style: const TextStyle(fontSize: 12)),
              selected: !_byCount,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _byCount = false),
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: Text(loc.fileSplitByCount, style: const TextStyle(fontSize: 12)),
              selected: _byCount,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _byCount = true),
            ),
          ]),
          const SizedBox(height: 8),
          if (_byCount)
            TextField(
              controller: _count,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: loc.fileSplitParts,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            )
          else
            TextField(
              controller: _sizeMb,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: loc.fileSplitChunkMb,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 10),
          if (_busy) ...[
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            const SizedBox(height: 6),
            TextButton(onPressed: () => setState(() => _cancel = true), child: Text(loc.cancel)),
          ] else
            Row(children: [
              FilledButton(onPressed: _split, child: Text(loc.fileSplitDo)),
              const SizedBox(width: 8),
              if (_parts.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _shareParts,
                  icon: const Icon(Icons.ios_share, size: 15),
                  label: Text('${loc.share} (${_parts.length})'),
                ),
            ]),
          if (_parts.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final p in _parts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(
                    child: Text(p.path.split(Platform.pathSeparator).last,
                        style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace')),
                  ),
                  Text('${p.bytes} B',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ),
          ],
        ]),
        ListView(padding: const EdgeInsets.all(12), children: [
          Text(loc.fileMergeHint,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          if (_busy) ...[
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
          ] else
            Row(children: [
              FilledButton.tonalIcon(
                onPressed: _merge,
                icon: const Icon(Icons.call_merge, size: 16),
                label: Text(loc.fileMergeDo),
              ),
              const SizedBox(width: 8),
              if (_mergedPath != null)
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await SharePlus.instance
                          .share(ShareParams(files: [XFile(_mergedPath!)]));
                    } catch (e) {
                      _toast('$e');
                    }
                  },
                  icon: const Icon(Icons.ios_share, size: 15),
                  label: Text(loc.share),
                ),
            ]),
          if (_mergedPath != null) ...[
            const SizedBox(height: 8),
            SelectableText(_mergedPath!,
                style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace')),
            Text('$_mergedBytes B',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ]),
      ]),
    );
  }
}
