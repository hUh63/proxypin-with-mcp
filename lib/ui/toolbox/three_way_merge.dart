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

// 三方合并：基线 / 我的 / 他的 → 合并结果。
//
// 对标 git merge-file、WinMerge 的三栏合并、KDiff3、Meld、Beyond Compare 的 3-way merge。
//
// 手机屏幕横着放不下三栏，所以交互换成「按变更区逐条决策」：
//   · 每个变更区是一张卡片，标题写明基线行号，正文列出 基 / 我 / 他 三段摘要；
//   · 「只有一侧改过」或「两侧改成了同一个结果」的区自动定好，标灰；
//   · 「两侧都改且结果不同」的区标红，默认取「我的」，由用户逐条改 ——
//     这正是 git 里 conflict 的语义；
//   · 底部一次性预览 / 复制 / 保存合并结果，可另存带 <<<<<<< 标记的版本给外部工具。
//
// 引擎在 lib/utils/text_diff.dart 的 mergeThreeWay()（纯函数、可单测）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/text_diff.dart';

class ThreeWayMergePage extends StatefulWidget {
  /// 从对比页进来时可以预填：左侧当基线、右侧当「我的」，用户只需再选「他的」。
  /// 这样「比对出差异 → 想合进来」不用重新挑两个文件。
  final String? initialBase;
  final String? initialMine;

  const ThreeWayMergePage({super.key, this.initialBase, this.initialMine});

  @override
  State<ThreeWayMergePage> createState() => _ThreeWayMergePageState();
}

class _ThreeWayMergePageState extends State<ThreeWayMergePage> {
  /// 单文件上限：再大的文本在手机上做三方比对没有实际意义。
  static const int _maxBytes = 4 * 1024 * 1024;

  String _baseName = '';
  String _mineName = '';
  String _theirsName = '';
  String? _baseText;
  String? _mineText;
  String? _theirsText;

  MergeResult? _result;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final base = widget.initialBase;
    final mine = widget.initialMine;
    if (base != null) {
      _baseText = base;
      _baseName = '#left';
    }
    if (mine != null) {
      _mineText = mine;
      _mineName = '#right';
    }
  }

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  void _toast(String msg) {
    if (!mounted) return;
    FlutterToastr.show(msg, context, duration: 2);
  }

  /// 文件选择器重入保护：ListTile 与「选择」按钮都能触发，连点会弹两个系统面板。
  bool _picking = false;

  Future<void> _pick(int which) async {
    if (_picking) return;
    _picking = true;
    final loc = localizations;
    try {
      final f = await FilePicker.pickFile();
      if (f == null) return;
      final file = File(f.xFile.path);
      if (await file.length() > _maxBytes) {
        _toast(loc.mergeTooLarge);
        return;
      }
      final text = await file.readAsString();
      if (!mounted) return;
      setState(() {
        switch (which) {
          case 0:
            _baseName = f.name;
            _baseText = text;
          case 1:
            _mineName = f.name;
            _mineText = text;
          default:
            _theirsName = f.name;
            _theirsText = text;
        }
        _result = null;
      });
    } catch (e) {
      _toast('$e');
    } finally {
      _picking = false;
    }
  }

  Future<void> _merge() async {
    final b = _baseText;
    final m = _mineText;
    final t = _theirsText;
    if (b == null || m == null || t == null) {
      _toast(localizations.mergeNeedThreeFiles);
      return;
    }
    setState(() => _busy = true);
    // mergeThreeWay 是同步的：先让「合并中」这一帧画出来，否则大文件下用户
    // 只会觉得按钮点下去没反应。
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;
    final result = mergeThreeWay(b, m, t);
    if (!mounted) return;
    setState(() {
      _result = result;
      _composeCache = null;
      _busy = false;
    });
  }

  void _chooseAll(MergeChoice choice) {
    final r = _result;
    if (r == null) return;
    setState(() {
      for (final g in r.regions) {
        g.choice = choice;
      }
      _composeCache = null;
    });
  }

  /// 合并结果缓存：底部栏每帧都要算行数，几 MB 的文本每次重建都拼一遍太亏。
  /// 任何一次「换选择」都要清掉。
  String? _composeCache;

  String _compose({bool markers = false}) {
    final r = _result;
    if (r == null) return '';
    // 带标记的版本只用于导出，不缓存（不常调）。
    if (markers) return r.compose(markers: true);
    return _composeCache ??= r.compose();
  }

  Future<void> _save({bool markers = false}) async {
    final r = _result;
    if (r == null) return;
    try {
      final bytes = utf8.encode(_compose(markers: markers));
      final uri = await FilePicker.saveFile(
          fileName: markers ? 'merged.conflict.txt' : 'merged.txt', bytes: bytes);
      if (uri == null) return;
      _toast(localizations.mergeSaved);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _copy() async {
    final r = _result;
    if (r == null) return;
    await Clipboard.setData(ClipboardData(text: _compose()));
    _toast(localizations.copied);
  }

  void _preview() {
    final r = _result;
    if (r == null) return;
    final text = _compose();
    final clipped = text.length > 200000 ? '${text.substring(0, 200000)}\n…' : text;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.mergePreview),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: SingleChildScrollView(
            child: SelectableText(
              clipped,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(localizations.close)),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              unawaited(_copy());
            },
            child: Text(localizations.copy),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = localizations;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.diffThreeWay),
        actions: [
          IconButton(
            tooltip: loc.mergeApplyToDiff,
            icon: const Icon(Icons.check_circle_outline),
            onPressed: _result == null ? null : () => Navigator.of(context).pop(_compose()),
          ),
          IconButton(
            tooltip: loc.mergeCopy,
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _result == null ? null : () => unawaited(_copy()),
          ),
          PopupMenuButton<String>(
            tooltip: loc.more,
            onSelected: (v) {
              switch (v) {
                case 'save':
                  unawaited(_save());
                case 'saveMarkers':
                  unawaited(_save(markers: true));
                case 'preview':
                  _preview();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'save', child: Text(loc.mergeSave)),
              PopupMenuItem(value: 'preview', child: Text(loc.mergePreview)),
              PopupMenuItem(value: 'saveMarkers', child: Text(loc.mergeConflictMarkers)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          _filePickers(loc, theme),
          if (_result != null) _summaryBar(loc, theme),
          const Divider(height: 1),
          Expanded(child: _result == null ? _hint(loc, theme) : _regionList(loc, theme)),
          if (_result != null) _bottomBar(loc),
        ],
      ),
    );
  }

  Widget _filePickers(AppLocalizations loc, ThemeData theme) {
    Widget row(int which, String title, String name, Color color) {
      final has = name.isNotEmpty;
      return ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: Icon(Icons.insert_drive_file_outlined, size: 18, color: color),
        title: Text(title, style: const TextStyle(fontSize: 13)),
        subtitle: Text(
          has ? name : loc.mergeNotSelected,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 11.5,
              color: has ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.error),
        ),
        trailing: TextButton(
          style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
          onPressed: () => unawaited(_pick(which)),
          child: Text(has ? loc.mergeChangeFile : loc.mergePickFile,
              style: const TextStyle(fontSize: 12)),
        ),
        onTap: () => unawaited(_pick(which)),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          row(0, loc.mergeBase, _baseName, Colors.blueGrey),
          row(1, loc.mergeMine, _mineName, Colors.blue),
          row(2, loc.mergeTheirs, _theirsName, Colors.deepOrange),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : () => unawaited(_merge()),
                icon: const Icon(Icons.merge_type, size: 18),
                label: Text(loc.mergeStart),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryBar(AppLocalizations loc, ThemeData theme) {
    final r = _result!;
    final conflict = r.conflicts;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      color: conflict > 0
          ? Colors.orange.withValues(alpha: 0.12)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(children: [
        Icon(conflict > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            size: 16, color: conflict > 0 ? Colors.orange : Colors.green),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            conflict > 0
                ? loc.mergeConflicts(conflict, r.autoCount)
                : loc.mergeAutoMerged(r.regions.length),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: () => _chooseAll(MergeChoice.mine),
          child: Text(loc.mergeUseAllMine, style: const TextStyle(fontSize: 11.5)),
        ),
        TextButton(
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: () => _chooseAll(MergeChoice.theirs),
          child: Text(loc.mergeUseAllTheirs, style: const TextStyle(fontSize: 11.5)),
        ),
      ]),
    );
  }

  Widget _hint(AppLocalizations loc, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          loc.mergeHint,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, height: 1.6, color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _regionList(AppLocalizations loc, ThemeData theme) {
    final r = _result!;
    if (r.regions.isEmpty) {
      return Center(child: Text(loc.mergeNoChange, style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
      itemCount: r.regions.length,
      itemBuilder: (_, i) => _regionCard(i, r.regions[i], loc, theme),
    );
  }

  Widget _regionCard(int index, MergeRegion r, AppLocalizations loc, ThemeData theme) {
    final conflict = r.conflict;
    final accent = conflict ? Colors.orange : theme.colorScheme.outline;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: conflict ? Colors.orange.withValues(alpha: 0.7) : Colors.transparent),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: conflict ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  conflict ? loc.mergeConflict : loc.mergeAuto,
                  style: TextStyle(fontSize: 10, color: accent, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                r.baseStart == r.baseEnd
                    ? 'L${r.baseStart + 1}'
                    : 'L${r.baseStart + 1}-${r.baseEnd}',
                style: TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 6),
              Text('#${index + 1}', style: TextStyle(fontSize: 10.5, color: theme.colorScheme.outline)),
            ]),
            const SizedBox(height: 5),
            _sideLine(loc.mergeBase, r.baseLines, Colors.blueGrey),
            _sideLine(loc.mergeMine, r.mineLines, Colors.blue),
            _sideLine(loc.mergeTheirs, r.theirsLines, Colors.deepOrange),
            const SizedBox(height: 4),
            Row(children: [
              _choiceChip(loc.mergeUseMine, MergeChoice.mine, r, Colors.blue),
              const SizedBox(width: 6),
              _choiceChip(loc.mergeUseTheirs, MergeChoice.theirs, r, Colors.deepOrange),
              const SizedBox(width: 6),
              _choiceChip(loc.mergeUseBase, MergeChoice.base, r, Colors.blueGrey),
            ]),
          ],
        ),
      ),
    );
  }

  /// 一侧的内容摘要：显示首行 + 「共 N 行」。
  Widget _sideLine(String label, List<String> lines, Color color) {
    final first = lines.isEmpty ? '∅' : lines.first.trimRight();
    final rest = lines.length > 1 ? '  +${lines.length - 1}' : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Text(label,
                style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(
              '$first$rest',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontFamily: 'monospace',
                height: 1.3,
                color: lines.isEmpty ? Theme.of(context).colorScheme.outline : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _choiceChip(String label, MergeChoice value, MergeRegion r, Color color) {
    final selected = r.choice == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (!mounted) return;
          setState(() {
            r.choice = value;
            _composeCache = null;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: selected ? color.withValues(alpha: 0.8) : Colors.grey.withValues(alpha: 0.35)),
          ),
          child: Text(
            label,
            style: TextStyle(
                fontSize: 11.5, color: selected ? color : null, fontWeight: selected ? FontWeight.w600 : null),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(AppLocalizations loc) {
    final r = _result!;
    final text = _compose();
    final lines = text.isEmpty ? 0 : '\n'.allMatches(text).length + 1;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.4))),
        ),
        child: Row(children: [
          Text('$lines ${loc.mergeLinesUnit}',
              style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const Spacer(),
          TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => unawaited(_copy()),
            icon: const Icon(Icons.copy_outlined, size: 16),
            label: Text(loc.mergeCopy, style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 4),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: r.regions.isEmpty ? null : () => Navigator.of(context).pop(_compose()),
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: Text(loc.mergeApplyToDiff, style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: r.regions.isEmpty ? null : () => unawaited(_save()),
            icon: const Icon(Icons.save_outlined, size: 16),
            label: Text(loc.mergeSave, style: const TextStyle(fontSize: 12)),
          ),
        ]),
      ),
    );
  }
}
