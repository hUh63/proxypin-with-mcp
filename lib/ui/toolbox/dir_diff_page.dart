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

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/toolbox/file_preview.dart';
import 'package:proxypin/ui/toolbox/text_diff.dart';
import 'package:proxypin/utils/dir_diff.dart';
import 'package:proxypin/utils/text_file_reader.dart';

/// 目录对比：选两个文件夹，按相对路径配对，列出「相同 / 修改 / 仅左侧 / 仅右侧 /
/// 二进制不同」。点某一条进入文本对比页（或文件预览）看细粒度差异。
///
/// 只读——除了「复制到另一侧」这一个显式动作，不会改动磁盘上的任何文件。
class DirDiffPage extends StatefulWidget {
  final String? windowId;
  final String? initialLeft;
  final String? initialRight;

  const DirDiffPage({
    super.key,
    this.windowId,
    this.initialLeft,
    this.initialRight,
  });

  static Future<void> show(BuildContext context,
      {String? windowId, String? left, String? right}) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DirDiffPage(
          windowId: windowId, initialLeft: left, initialRight: right),
    ));
  }

  @override
  State<DirDiffPage> createState() => _DirDiffPageState();
}

class _DirDiffPageState extends State<DirDiffPage> {
  final TextEditingController _leftCtrl = TextEditingController();
  final TextEditingController _rightCtrl = TextEditingController();
  final TextEditingController _filterCtrl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  DirDiffResult? _result;
  bool _busy = false;
  bool _onlyDiff = true;
  String _filter = '';
  bool _picking = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _leftCtrl.text = widget.initialLeft ?? '';
    _rightCtrl.text = widget.initialRight ?? '';
  }

  @override
  void dispose() {
    _leftCtrl.dispose();
    _rightCtrl.dispose();
    _filterCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    FlutterToastr.show(msg, context, backgroundColor: Colors.black87);
  }

  Future<void> _pick(bool left) async {
    if (_picking) return;
    _picking = true;
    try {
      final path = await FilePicker.getDirectoryPath();
      if (path == null || path.isEmpty) return;
      if (!mounted) return;
      setState(() {
        if (left) {
          _leftCtrl.text = path;
        } else {
          _rightCtrl.text = path;
        }
      });
    } catch (e) {
      _toast('$e');
    } finally {
      _picking = false;
    }
  }

  Future<void> _scan() async {
    final left = _leftCtrl.text.trim();
    final right = _rightCtrl.text.trim();
    if (left.isEmpty || right.isEmpty) {
      _toast(localizations.dirDiffEmptyDir);
      return;
    }
    if (left == right) {
      _toast(localizations.dirDiffSamePath);
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final r = await DirDiff.compare(left, right);
      if (!mounted) return;
      setState(() => _result = r);
      if (r.error != null) {
        _toast(switch (r.error) {
          'left-missing' => localizations.dirDiffLeftMissing,
          'right-missing' => localizations.dirDiffRightMissing,
          _ => localizations.dirDiffEmptyDir,
        });
      } else if (!r.hasDifference) {
        _toast(localizations.dirDiffNoDifference);
      }
    } catch (e) {
      if (!mounted) return;
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<DirDiffEntry> get _visible {
    final all = _result?.entries ?? const <DirDiffEntry>[];
    final f = _filter.trim().toLowerCase();
    return all.where((e) {
      if (_onlyDiff && !e.status.isDifferent) return false;
      if (f.isNotEmpty && !e.relativePath.toLowerCase().contains(f)) {
        return false;
      }
      return true;
    }).toList();
  }

  String _join(String root, String rel) {
    if (root.endsWith('/') || root.endsWith('\\')) return '$root$rel';
    return '$root${Platform.pathSeparator}$rel';
  }

  Future<void> _openEntry(DirDiffEntry e) async {
    final left = _join(_leftCtrl.text.trim(), e.relativePath);
    final right = _join(_rightCtrl.text.trim(), e.relativePath);
    switch (e.status) {
      case DirDiffStatus.modified:
      case DirDiffStatus.same:
        await _openText(left, right, e.relativePath);
      case DirDiffStatus.binaryModified:
        _showBinaryInfo(e, left, right);
      case DirDiffStatus.leftOnly:
        await FilePreviewPage.show(context, File(left));
      case DirDiffStatus.rightOnly:
        await FilePreviewPage.show(context, File(right));
      case DirDiffStatus.error:
        _toast(e.note ?? localizations.dirDiffError);
    }
  }

  Future<void> _openText(String left, String right, String rel) async {
    // 两次读都不抛（读不到返回空串），所以这里不需要 try
    final l = await readTextFileLenient(File(left));
    final r = await readTextFileLenient(File(right));
    if (!mounted) return;
    if (l.truncated || r.truncated) _toast(localizations.diffFileTruncated);
    await Navigator.of(context, rootNavigator: false).push(
      MaterialPageRoute(
        builder: (_) => TextDiffPage(
          windowId: widget.windowId,
          initialLeft: l.text,
          initialRight: r.text,
          initialLeftName: rel,
          initialRightName: rel,
          persist: false,
        ),
      ),
    );
  }

  void _showBinaryInfo(DirDiffEntry e, String left, String right) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.data_object),
              title: Text(e.relativePath),
              subtitle: Text(
                  '${_sizeText(e.leftSize)} → ${_sizeText(e.rightSize)}'),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: Text(localizations.dirDiffOpenLeft),
              onTap: () {
                Navigator.pop(ctx);
                FilePreviewPage.show(context, File(left));
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: Text(localizations.dirDiffOpenRight),
              onTap: () {
                Navigator.pop(ctx);
                FilePreviewPage.show(context, File(right));
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 把一侧的文件覆盖到另一侧。唯一会写盘的动作，所以必须确认。
  Future<void> _copyToOther(DirDiffEntry e, {required bool fromLeft}) async {
    final src = _join(
        (fromLeft ? _leftCtrl : _rightCtrl).text.trim(), e.relativePath);
    final dst = _join(
        (fromLeft ? _rightCtrl : _leftCtrl).text.trim(), e.relativePath);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.dirDiffCopyToOther),
        content: Text('${e.relativePath}\n\n${localizations.dirDiffCopyConfirm}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(localizations.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(localizations.confirm)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final target = File(dst);
      await target.parent.create(recursive: true);
      await File(src).copy(dst);
      if (!mounted) return;
      _toast(localizations.dirDiffCopied);
      await _scan();
    } catch (err) {
      _toast('$err');
    }
  }

  Future<void> _exportReport() async {
    final r = _result;
    if (r == null) return;
    final buf = StringBuffer()
      ..writeln('# ${localizations.dirDiff}')
      ..writeln()
      ..writeln('- ${localizations.dirDiffLeftDir}: `${_leftCtrl.text.trim()}`')
      ..writeln(
          '- ${localizations.dirDiffRightDir}: `${_rightCtrl.text.trim()}`')
      ..writeln()
      ..writeln('| ${localizations.dirDiffColStatus} | '
          '${localizations.dirDiffColPath} | '
          '${localizations.dirDiffColSize} |')
      ..writeln('|---|---|---|');
    for (final e in _visible) {
      buf.writeln('| ${_statusText(e.status)} | ${e.relativePath} | '
          '${_sizeText(e.leftSize)} → ${_sizeText(e.rightSize)} |');
    }
    try {
      final uri = await FilePicker.saveFile(
          fileName: 'dir-diff.md', bytes: utf8.encode(buf.toString()));
      if (uri == null) return;
      if (!mounted) return;
      _toast(localizations.diffReportSaved);
    } catch (e) {
      _toast('$e');
    }
  }

  String _statusText(DirDiffStatus s) => switch (s) {
        DirDiffStatus.same => localizations.dirDiffSame,
        DirDiffStatus.modified => localizations.diffModified,
        DirDiffStatus.binaryModified => localizations.dirDiffBinary,
        DirDiffStatus.leftOnly => localizations.dirDiffLeftOnly,
        DirDiffStatus.rightOnly => localizations.dirDiffRightOnly,
        DirDiffStatus.error => localizations.dirDiffError,
      };

  Color _statusColor(DirDiffStatus s) => switch (s) {
        DirDiffStatus.same => Colors.grey,
        DirDiffStatus.modified => Colors.orange,
        DirDiffStatus.binaryModified => Colors.purple,
        DirDiffStatus.leftOnly => Colors.blue,
        DirDiffStatus.rightOnly => Colors.green,
        DirDiffStatus.error => Colors.red,
      };

  String _sizeText(int n) {
    if (n < 0) return '?';
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    if (n < 1024 * 1024 * 1024) {
      return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(n / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.dirDiff),
        actions: [
          IconButton(
            tooltip: localizations.dirDiffOnlyDiff,
            isSelected: _onlyDiff,
            icon: const Icon(Icons.filter_alt_outlined),
            selectedIcon: const Icon(Icons.filter_alt),
            onPressed: () => setState(() => _onlyDiff = !_onlyDiff),
          ),
          PopupMenuButton<String>(
            tooltip: localizations.more,
            onSelected: (v) {
              switch (v) {
                case 'report':
                  _exportReport();
                case 'skip':
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(localizations.dirDiff),
                      content: Text(localizations.dirDiffSkipHint),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(localizations.confirm)),
                      ],
                    ),
                  );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'report', child: Text(localizations.diffExportReport)),
              PopupMenuItem(
                  value: 'skip', child: Text(localizations.dirDiffSkipHint)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Column(
              children: [
                _dirRow(true, theme),
                const SizedBox(height: 6),
                _dirRow(false, theme),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _scan,
                        icon: _busy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.compare_arrows, size: 18),
                        label: Text(_busy
                            ? localizations.dirDiffScanning
                            : localizations.dirDiffStart),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _statsBar(theme),
          _filterBar(theme),
          const Divider(height: 1),
          Expanded(child: _list(theme)),
        ],
      ),
    );
  }

  Widget _dirRow(bool left, ThemeData theme) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            left ? localizations.dirDiffLeftDir : localizations.dirDiffRightDir,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: TextField(
            controller: left ? _leftCtrl : _rightCtrl,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: '/path/to/dir',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
          ),
        ),
        IconButton(
          tooltip: localizations.dirDiffPickDir,
          icon: const Icon(Icons.folder_open, size: 20),
          onPressed: () => _pick(left),
        ),
      ],
    );
  }

  Widget _statsBar(ThemeData theme) {
    final r = _result;
    if (r == null) return const SizedBox.shrink();
    final items = <(DirDiffStatus, int)>[
      (DirDiffStatus.same, r.countOf(DirDiffStatus.same)),
      (DirDiffStatus.modified, r.countOf(DirDiffStatus.modified)),
      (DirDiffStatus.binaryModified, r.countOf(DirDiffStatus.binaryModified)),
      (DirDiffStatus.leftOnly, r.countOf(DirDiffStatus.leftOnly)),
      (DirDiffStatus.rightOnly, r.countOf(DirDiffStatus.rightOnly)),
      (DirDiffStatus.error, r.countOf(DirDiffStatus.error)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (s, c) in items)
            if (c > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(s).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${_statusText(s)} $c',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: _statusColor(s),
                        fontWeight: FontWeight.w600)),
              ),
          if (r.truncated)
            Text(localizations.dirDiffTruncated,
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.error)),
        ],
      ),
    );
  }

  Widget _filterBar(ThemeData theme) {
    if (_result == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: TextField(
        controller: _filterCtrl,
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.search, size: 18),
          hintText: localizations.dirDiffFilterHint,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          suffixIcon: _filter.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: () {
                    _filterCtrl.clear();
                    setState(() => _filter = '');
                  },
                ),
        ),
        style: const TextStyle(fontSize: 13),
        onChanged: (v) => setState(() => _filter = v),
      ),
    );
  }

  Widget _list(ThemeData theme) {
    if (_result == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _busy ? localizations.dirDiffScanning : localizations.dirDiffEmptyDir,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final items = _visible;
    if (items.isEmpty) {
      return Center(
        child: Text(localizations.dirDiffNoDifference,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      itemCount: items.length,
      itemBuilder: (_, i) => _row(items[i], theme),
    );
  }

  Widget _row(DirDiffEntry e, ThemeData theme) {
    final color = _statusColor(e.status);
    return InkWell(
      onTap: () => _openEntry(e),
      onLongPress: () => _showRowMenu(e),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 30,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  if (e.dir.isNotEmpty)
                    Text(
                      e.dir,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              e.status == DirDiffStatus.leftOnly ||
                      e.status == DirDiffStatus.rightOnly
                  ? _sizeText(e.status == DirDiffStatus.leftOnly
                      ? e.leftSize
                      : e.rightSize)
                  : '${_sizeText(e.leftSize)} → ${_sizeText(e.rightSize)}',
              style: TextStyle(fontSize: 11, color: color),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, size: 18),
              onPressed: () => _showRowMenu(e),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRowMenu(DirDiffEntry e) async {
    final left = _join(_leftCtrl.text.trim(), e.relativePath);
    final right = _join(_rightCtrl.text.trim(), e.relativePath);
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              title: Text(e.relativePath,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              subtitle: Text(_statusText(e.status)),
            ),
            const Divider(height: 1),
            if (e.status != DirDiffStatus.rightOnly)
              ListTile(
                leading: const Icon(Icons.compare_arrows),
                title: Text(localizations.dirDiffCompare),
                onTap: () => Navigator.pop(ctx, 'diff'),
              ),
            if (e.status != DirDiffStatus.rightOnly)
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: Text(localizations.dirDiffOpenLeft),
                onTap: () => Navigator.pop(ctx, 'left'),
              ),
            if (e.status != DirDiffStatus.leftOnly)
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: Text(localizations.dirDiffOpenRight),
                onTap: () => Navigator.pop(ctx, 'right'),
              ),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: Text(localizations.dirDiffCopyPath),
              onTap: () => Navigator.pop(ctx, 'path'),
            ),
            if (e.status == DirDiffStatus.leftOnly ||
                e.status == DirDiffStatus.modified ||
                e.status == DirDiffStatus.binaryModified)
              ListTile(
                leading: const Icon(Icons.arrow_forward),
                title: Text(localizations.dirDiffCopyLeftToRight),
                onTap: () => Navigator.pop(ctx, 'l2r'),
              ),
            if (e.status == DirDiffStatus.rightOnly ||
                e.status == DirDiffStatus.modified ||
                e.status == DirDiffStatus.binaryModified)
              ListTile(
                leading: const Icon(Icons.arrow_back),
                title: Text(localizations.dirDiffCopyRightToLeft),
                onTap: () => Navigator.pop(ctx, 'r2l'),
              ),
          ],
        ),
      ),
    );
    if (v == null || !mounted) return;
    switch (v) {
      case 'diff':
        await _openText(left, right, e.relativePath);
      case 'left':
        await FilePreviewPage.show(context, File(left));
      case 'right':
        await FilePreviewPage.show(context, File(right));
      case 'path':
        await Clipboard.setData(ClipboardData(text: e.relativePath));
        if (!mounted) return;
        _toast(localizations.copied);
      case 'l2r':
        await _copyToOther(e, fromLeft: true);
      case 'r2l':
        await _copyToOther(e, fromLeft: false);
    }
  }
}
