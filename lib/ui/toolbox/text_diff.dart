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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/component/search/finder.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:proxypin/ui/component/snippet_bar.dart';
import 'package:proxypin/utils/text_diff.dart';
import 'package:proxypin/utils/tool_snippets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 文本对比工具
/// - 左右两个 CodeForge 输入；
/// - 差异按块（连续 delete/insert）分类为新增 / 修改 / 删除并染色；
/// - 上一处 / 下一处会同时滚动两侧并把光标定位到差异处；
/// - 长按某处差异可把它「应用到另一侧」对应位置；
/// - 退出时询问是否保留内容，保留后下次进入自动恢复。
///
/// @author Hongen Wang
class TextDiffPage extends StatefulWidget {
  final String? windowId;
  final String? initialLeft;
  final String? initialRight;

  const TextDiffPage({super.key, this.windowId, this.initialLeft, this.initialRight});

  @override
  State<TextDiffPage> createState() => _TextDiffPageState();
}

class _TextDiffPageState extends State<TextDiffPage> {
  static const String _storeKey = 'text_diff_content_v1';

  late final CodeForgeController _left;
  late final CodeForgeController _right;
  late final UndoRedoController _leftUndo;
  late final UndoRedoController _rightUndo;

  bool _wrap = true;

  /// 忽略大小写 / 忽略空白：比较时归一化，显示仍是原文。
  bool _ignoreCase = false;
  bool _ignoreWhitespace = false;

  /// 对齐并排视图（逐行对齐、差异上底色），用于快速看清多段差异的对应关系。
  bool _aligned = false;
  String? _summary;

  /// 差异块（用于导航、分类与整块替换）。
  List<DiffBlock> _blocks = [];
  int _navIndex = -1;

  /// 撤销 / 重做作用的对象：最近一次触摸的编辑器。
  bool _leftActive = true;

  /// 上一次对比时左右文本的快照；用来判断 listener 收到的变化是不是真改了文本。
  String _leftSnapshot = '';
  String _rightSnapshot = '';

  /// 退出确认已在处理中，避免重入。
  bool _leaving = false;

  Timer? _persistTimer;

  // 长按检测（Listener 只观察、不吃事件，故不影响选中与输入法）。
  Timer? _longPressTimer;
  Offset? _pressDown;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _left = CodeForgeController()..text = widget.initialLeft ?? '';
    _right = CodeForgeController()..text = widget.initialRight ?? '';
    _leftUndo = UndoRedoController();
    _rightUndo = UndoRedoController();
    _left.setUndoController(_leftUndo);
    _right.setUndoController(_rightUndo);

    _left.addListener(_onLeftChanged);
    _right.addListener(_onRightChanged);
    _leftUndo.addListener(_onUndoChanged);
    _rightUndo.addListener(_onUndoChanged);

    if (Platforms.isDesktop() && widget.windowId != null) {
      HardwareKeyboard.instance.addHandler(_onKeyEvent);
    }

    _restoreIfNeeded();
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _longPressTimer?.cancel();
    _left.removeListener(_onLeftChanged);
    _right.removeListener(_onRightChanged);
    _leftUndo.removeListener(_onUndoChanged);
    _rightUndo.removeListener(_onUndoChanged);
    _left.dispose();
    _right.dispose();
    _leftUndo.dispose();
    _rightUndo.dispose();
    if (Platforms.isDesktop() && widget.windowId != null) {
      HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    }
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    if (widget.windowId == null) return false;
    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      HardwareKeyboard.instance.removeHandler(_onKeyEvent);
      WindowController.fromWindowId(widget.windowId!).close();
      return true;
    }
    return false;
  }

  void _onUndoChanged() {
    if (mounted) setState(() {});
  }

  void _onLeftChanged() {
    if (_left.text == _leftSnapshot) return; // 选区 / 滚动等非文本变化忽略
    _onTextChange();
  }

  void _onRightChanged() {
    if (_right.text == _rightSnapshot) return;
    _onTextChange();
  }

  bool textChanged = false;

  void _onTextChange() {
    if (textChanged) return;
    textChanged = true;
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      _compare();
      textChanged = false;
    });
  }

  // ---------- 持久化 ----------

  Future<void> _restoreIfNeeded() async {
    if (widget.initialLeft != null || widget.initialRight != null) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_storeKey);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final l = (m['left'] as String?) ?? '';
      final r = (m['right'] as String?) ?? '';
      if (l.isEmpty && r.isEmpty) return;
      if (!mounted) return;
      _left.text = l;
      _right.text = r;
      _compare();
    } catch (_) {
      // 忽略损坏的存档
    }
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 700), _persistNow);
  }

  Future<void> _persistNow() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_storeKey, jsonEncode({'left': _left.text, 'right': _right.text}));
    } catch (_) {}
  }

  Future<void> _clearPersist() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_storeKey);
    } catch (_) {}
  }

  // ---------- 对比 ----------

  void _compare() {
    if (_left.text.isEmpty && _right.text.isEmpty) {
      if (_summary != null || _blocks.isNotEmpty) {
        setState(() {
          _summary = null;
          _blocks = [];
          _navIndex = -1;
        });
      }
      return;
    }

    // 先同步快照：随后 clearDecoration / notifyListeners 都会触发 listener，
    // 快照一致可让 _onLeftChanged 直接早退，避免多余的 1.2s 兜底重排。
    _leftSnapshot = _left.text;
    _rightSnapshot = _right.text;

    final diffs = diffLines(_left.text, _right.text,
        ignoreCase: _ignoreCase, ignoreWhitespace: _ignoreWhitespace);
    final blocks = buildDiffBlocks(diffs, ignoreCase: _ignoreCase, ignoreWhitespace: _ignoreWhitespace);
    final stats = diffStats(blocks);

    final addBg = Colors.green.withValues(alpha: 0.16);
    final delBg = Colors.red.withValues(alpha: 0.16);
    final modBg = Colors.orange.withValues(alpha: 0.16);

    final leftDecos = <LineDecoration>[];
    final rightDecos = <LineDecoration>[];
    final leftGutter = <GutterDecoration>[];
    final rightGutter = <GutterDecoration>[];
    final leftHL = <SearchHighlight>[];
    final rightHL = <SearchHighlight>[];

    for (final b in blocks) {
      for (var i = 0; i < b.leftLines.length; i++) {
        final ln = b.leftLines[i];
        final isMod = b.rightLocalOfLeft(i) != null;
        leftDecos.add(LineDecoration(
          id: 'ld-$ln',
          startLine: ln,
          endLine: ln,
          type: LineDecorationType.background,
          color: isMod ? modBg : delBg,
        ));
        leftGutter.add(GutterDecoration(
          id: 'lg-$ln',
          startLine: ln,
          endLine: ln,
          type: GutterDecorationType.colorBar,
          color: isMod ? Colors.orange : Colors.red,
        ));
      }
      for (var j = 0; j < b.rightLines.length; j++) {
        final ln = b.rightLines[j];
        final isMod = b.leftLocalOfRight(j) != null;
        rightDecos.add(LineDecoration(
          id: 'rd-$ln',
          startLine: ln,
          endLine: ln,
          type: LineDecorationType.background,
          color: isMod ? modBg : addBg,
        ));
        rightGutter.add(GutterDecoration(
          id: 'rg-$ln',
          startLine: ln,
          endLine: ln,
          type: GutterDecorationType.colorBar,
          color: isMod ? Colors.orange : Colors.green,
        ));
      }

      // 配对行做字符级高亮。
      for (final pair in b.pairs) {
        final ll = b.leftLines[pair.left];
        final rl = b.rightLines[pair.right];
        final cd = diffChars(_left.getLineText(ll), _right.getLineText(rl));
        final lo = _left.getLineStartOffset(ll);
        final ro = _right.getLineStartOffset(rl);
        for (final r in cd.leftRanges) {
          leftHL.add(SearchHighlight(start: lo + r.start, end: lo + r.end));
        }
        for (final r in cd.rightRanges) {
          rightHL.add(SearchHighlight(start: ro + r.start, end: ro + r.end));
        }
      }
    }

    _left.clearLineDecorations();
    _left.clearGutterDecorations();
    _right.clearLineDecorations();
    _right.clearGutterDecorations();
    _left.addLineDecorations(leftDecos);
    _left.addGutterDecorations(leftGutter);
    _right.addLineDecorations(rightDecos);
    _right.addGutterDecorations(rightGutter);

    _left.searchHighlights = leftHL;
    _left.searchHighlightsChanged = true;
    _right.searchHighlights = rightHL;
    _right.searchHighlightsChanged = true;
    _left.notifyListeners();
    _right.notifyListeners();

    if (mounted) {
      setState(() {
        _blocks = blocks;
        _navIndex = -1;
        _summary = stats.identical
            ? localizations.diffIdentical
            : localizations.diffSummaryDetail(stats.added, stats.deleted, stats.modified);
      });
    }
    _schedulePersist();
  }

  /// 跳到上一处（[delta] < 0）或下一处（[delta] > 0）差异，两侧一起滚动并把光标定位过去。
  void _navigate(int delta) {
    if (_blocks.isEmpty) return;
    var index = _navIndex;
    if (index < 0) {
      index = delta > 0 ? 0 : _blocks.length - 1;
    } else {
      index = (index + delta) % _blocks.length;
      if (index < 0) index += _blocks.length;
    }
    setState(() => _navIndex = index);

    final b = _blocks[index];
    _gotoLine(_left, b.leftStart);
    _gotoLine(_right, b.rightStart);
  }

  /// 把编辑器滚动到 [line]（0-based），并在该行行首放置光标。两侧都会执行，
  /// 因此「上一处 / 下一处」会同时定位两个窗口。
  void _gotoLine(CodeForgeController controller, int line) {
    if (controller.lineCount == 0) return;
    final target = line.clamp(0, controller.lineCount - 1);
    try {
      controller.selection = TextSelection.collapsed(offset: controller.getLineStartOffset(target));
    } catch (_) {}
    try {
      controller.scrollToLine(target);
    } catch (_) {}
  }

  void _undo() => (_leftActive ? _leftUndo : _rightUndo).undo();

  void _redo() => (_leftActive ? _leftUndo : _rightUndo).redo();

  // ---------- 长按：把此处差异应用到另一侧 ----------

  void _onPointerDown(bool isLeft, PointerDownEvent e) {
    _leftActive = isLeft;
    _pressDown = e.position;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(const Duration(milliseconds: 560), () {
      if (!mounted) return;
      _onLongPress(isLeft, e.position);
    });
  }

  void _onPointerMove(PointerMoveEvent e) {
    final start = _pressDown;
    if (start == null) return;
    if ((e.position - start).distance > 14) _cancelLongPress();
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _pressDown = null;
  }

  void _onLongPress(bool isLeft, Offset globalPos) {
    if (!mounted) return;
    final controller = isLeft ? _left : _right;
    int line;
    try {
      final sel = controller.selection.start.clamp(0, controller.text.length);
      line = controller.getLineAtOffset(sel);
    } catch (_) {
      return;
    }
    final block = _blockAtLine(isLeft, line);
    if (block == null) {
      _toast(localizations.diffNoChangeHere);
      return;
    }

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final size = overlay?.size ?? MediaQuery.of(context).size;
    final pos = RelativeRect.fromLTRB(
      globalPos.dx,
      globalPos.dy,
      (size.width - globalPos.dx).clamp(0.0, size.width),
      (size.height - globalPos.dy).clamp(0.0, size.height),
    );

    showMenu<String>(
      context: context,
      position: pos,
      items: [
        PopupMenuItem<String>(
          value: 'apply',
          child: Row(children: [
            const Icon(Icons.input, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(isLeft ? localizations.diffReplaceBlockLeft : localizations.diffReplaceBlockRight),
            ),
          ]),
        ),
      ],
    ).then((v) {
      if (v == 'apply') _applyBlock(block, fromLeft: isLeft);
    });
  }

  DiffBlock? _blockAtLine(bool isLeft, int line) {
    for (final b in _blocks) {
      final lines = isLeft ? b.leftLines : b.rightLines;
      if (lines.contains(line)) return b;
    }
    // 空块（纯增 / 纯删）里光标可能落在块起止行上，做一次范围兜底匹配。
    for (final b in _blocks) {
      final lines = isLeft ? b.leftLines : b.rightLines;
      final start = isLeft ? b.leftStart : b.rightStart;
      if (lines.isEmpty && (line == start || line == start - 1)) return b;
    }
    return null;
  }

  /// 把 [b] 这一整块文本从 [fromLeft] 侧复制到另一侧对应位置。
  void _applyBlock(DiffBlock b, {required bool fromLeft}) {
    if (!mounted) return;
    final src = fromLeft ? _left : _right;
    final dst = fromLeft ? _right : _left;
    final srcStart = fromLeft ? b.leftStart : b.rightStart;
    final srcCount = fromLeft ? b.leftLines.length : b.rightLines.length;
    final dstStart = fromLeft ? b.rightStart : b.leftStart;
    final dstCount = fromLeft ? b.rightLines.length : b.leftLines.length;

    try {
      final srcStartOff = src.getLineStartOffset(srcStart.clamp(0, src.lineCount - 1));
      final srcEndOff = srcStart + srcCount < src.lineCount
          ? src.getLineStartOffset(srcStart + srcCount)
          : src.text.length;
      final srcText = src.text.substring(srcStartOff, srcEndOff);

      final dstStartOff = dst.getLineStartOffset(dstStart.clamp(0, dst.lineCount - 1));
      final dstEndOff =
          dstStart + dstCount < dst.lineCount ? dst.getLineStartOffset(dstStart + dstCount) : dst.text.length;

      dst.replaceRange(dstStartOff, dstEndOff, srcText);
      _compare();
      _toast(localizations.diffApplied);
    } catch (e) {
      _toast('${localizations.fail}: $e');
    }
  }

  // ---------- 其它操作 ----------

  /// 清掉两侧高亮，但保留文本内容。
  void _clearHighlights() {
    _left.clearLineDecorations();
    _left.clearGutterDecorations();
    _right.clearLineDecorations();
    _right.clearGutterDecorations();
    if (_left.searchHighlights.isNotEmpty) {
      _left.searchHighlights = [];
      _left.searchHighlightsChanged = true;
      _left.notifyListeners();
    }
    if (_right.searchHighlights.isNotEmpty) {
      _right.searchHighlights = [];
      _right.searchHighlightsChanged = true;
      _right.notifyListeners();
    }
    setState(() {
      _summary = null;
      _blocks = [];
      _navIndex = -1;
    });
  }

  void _clearAll() {
    if (_left.text.isEmpty && _right.text.isEmpty) return;
    _left.text = '';
    _right.text = '';
    _leftUndo.clear();
    _rightUndo.clear();
    _clearHighlights();
    _schedulePersist();
  }

  Future<void> _openFileInto(CodeForgeController target) async {
    String? path;
    try {
      final picked = await FilePicker.pickFile(type: FileType.any);
      path = picked?.path;
    } catch (_) {
      final picked = await FilePicker.pickFile();
      path = picked?.path;
    }

    if (path == null) return;
    try {
      final content = await File(path).readAsString();
      target.text = content;
    } catch (e) {
      _toast('${localizations.fail}: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    FlutterToastr.show(msg, context, duration: 3);
  }

  /// 退出确认：内容非空时询问是否保留，保留会写入存档供下次恢复。
  /// 返回 true=保留退出，false=不保留退出，null=取消。
  Future<bool?> _confirmExit() async {
    if (_left.text.isEmpty && _right.text.isEmpty) return false;
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(localizations.diffExitKeepTitle),
        content: Text(localizations.diffExitKeepBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(null), child: Text(localizations.cancel)),
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: Text(localizations.editorDiscard),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: Text(localizations.diffKeep),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePop() async {
    if (_leaving) return;
    _leaving = true;
    final keep = await _confirmExit();
    if (!mounted) return;
    if (keep == null) {
      _leaving = false;
      return; // 取消，留在页面
    }
    _persistTimer?.cancel();
    if (keep) {
      await _persistNow();
    } else {
      await _clearPersist();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    bool isNewWindows = widget.windowId != null && Platform.isWindows;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handlePop();
      },
      child: Scaffold(
        appBar: isNewWindows
            ? null
            : PreferredSize(
                preferredSize: Platforms.isDesktop() ? const Size.fromHeight(23) : const Size.fromHeight(36),
                child: AppBar(
                  title: Text(localizations.textDiff, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w300)),
                  centerTitle: true,
                ),
              ),
        body: Column(children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _legend(),
              const SizedBox(width: 4),
              Expanded(child: Align(alignment: Alignment.topRight, child: _toolbar())),
            ],
          ),
          const Divider(height: 1, thickness: 0.3),
          Expanded(
            child: _aligned
                ? _alignedView()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // 800 是经验阈值：再窄左右两个编辑器单独宽度不够，堆叠更舒服。
                      final wide = constraints.maxWidth >= 800;
                      return wide ? _wideLayout() : _narrowLayout();
                    },
                  ),
          ),
          if (_summary != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(children: [
                Expanded(child: Text(_summary!, style: const TextStyle(fontSize: 14))),
                if (_blocks.isNotEmpty && _navIndex >= 0)
                  Text(
                    localizations.diffPosition(_navIndex + 1, _blocks.length),
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary),
                  ),
              ]),
            ),
          _snippetBar(),
        ]),
      ),
    );
  }

  /// 左上角图例：三行「颜色 + 文本」的小号示例，固定显示（不横向滑动）。
  Widget _legend() {
    Widget item(Color c, String label) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 1),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(1.5)),
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 9.5, height: 1.05)),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 3, bottom: 3),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        item(Colors.green, localizations.diffAdded),
        item(Colors.orange, localizations.diffModified),
        item(Colors.red, localizations.diffDeleted),
      ]),
    );
  }

  Widget _toolbar() {
    final color = Theme.of(context).colorScheme.primary;
    final hasDiff = _blocks.isNotEmpty;
    final activeUndo = _leftActive ? _leftUndo : _rightUndo;
    return Container(
      padding: const EdgeInsets.only(top: 2, bottom: 2, right: 12),
      child: Wrap(
        spacing: 0,
        runSpacing: 0,
        children: [
          _iconBtn(Icons.undo, localizations.editorUndo, activeUndo.canUndo ? _undo : null),
          _iconBtn(Icons.redo, localizations.editorRedo, activeUndo.canRedo ? _redo : null),
          _iconBtn(Icons.keyboard_arrow_up, localizations.diffPrev, hasDiff ? () => _navigate(-1) : null),
          _iconBtn(Icons.keyboard_arrow_down, localizations.diffNext, hasDiff ? () => _navigate(1) : null),
          _iconBtn(Icons.compare_arrows, localizations.compare, _onTextChange),
          _iconBtn(
            Icons.text_format,
            localizations.diffIgnoreCase,
            () {
              setState(() => _ignoreCase = !_ignoreCase);
              _compare();
            },
            tint: _ignoreCase ? color : null,
          ),
          _iconBtn(
            Icons.space_bar,
            localizations.diffIgnoreWhitespace,
            () {
              setState(() => _ignoreWhitespace = !_ignoreWhitespace);
              _compare();
            },
            tint: _ignoreWhitespace ? color : null,
          ),
          _iconBtn(Icons.delete_outline, localizations.clear, _clearAll),
          _iconBtn(
            Icons.wrap_text,
            localizations.wordWrap,
            () => setState(() => _wrap = !_wrap),
            tint: _wrap ? color : null,
          ),
          _iconBtn(
            Icons.view_column_outlined,
            localizations.diffAlignedView,
            () => setState(() => _aligned = !_aligned),
            tint: _aligned ? color : null,
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback? onTap, {Color? tint}) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 17, color: onTap == null ? Colors.grey : tint),
      visualDensity: VisualDensity.compact,
    );
  }

  /// 可滑动 / 可展开的快捷输入行（插入到最近触摸的一侧）。
  Widget _snippetBar() {
    return SnippetBar(
      scope: 'diff',
      defaults: ToolSnippetDefaults.editor,
      onInsert: _insertSnippet,
    );
  }

  void _insertSnippet(String insert) {
    final c = _leftActive ? _left : _right;
    final text = c.text;
    final sel = c.selection;
    if (sel.isValid && !sel.isCollapsed) {
      c.text = text.replaceRange(sel.start, sel.end, insert);
      c.selection = TextSelection.collapsed(offset: sel.start + insert.length);
    } else {
      final offset = sel.isValid ? sel.start : text.length;
      c.text = text.replaceRange(offset, offset, insert);
      c.selection = TextSelection.collapsed(offset: offset + insert.length);
    }
    _onTextChange();
  }

  Widget _wideLayout() {
    return Row(children: [
      Expanded(child: _editor(_left, localizations.diffOriginal, isLeft: true)),
      const VerticalDivider(width: 1, thickness: 0.3),
      Expanded(child: _editor(_right, localizations.diffChanged, isLeft: false)),
    ]);
  }

  Widget _narrowLayout() {
    return Column(children: [
      Expanded(child: _editor(_left, localizations.diffOriginal, isLeft: true)),
      const Divider(height: 1, thickness: 0.3),
      Expanded(child: _editor(_right, localizations.diffChanged, isLeft: false)),
    ]);
  }

  Widget _editor(CodeForgeController controller, String title, {required bool isLeft}) {
    final isDark = Theme.brightnessOf(context) == Brightness.dark;
    final baseTheme = isDark ? atomOneDarkTheme : atomOneLightTheme;
    final pageBg = Theme.of(context).colorScheme.surface;
    final editorTheme = isDark
        ? {
            ...baseTheme,
            'root': const TextStyle(color: Color(0xffabb2bf)).copyWith(backgroundColor: pageBg),
          }
        : baseTheme;

    // 字符级差异：左边删除（红底白字加粗），右边新增（绿底白字加粗），更醒目。
    final charStyle = isLeft
        ? const TextStyle(backgroundColor: Color(0xF2C62828), color: Colors.white, fontWeight: FontWeight.w600)
        : const TextStyle(backgroundColor: Color(0xF22E7D32), color: Colors.white, fontWeight: FontWeight.w600);
    final matchStyle = MatchHighlightStyle(currentMatchStyle: charStyle, otherMatchStyle: charStyle);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(children: [
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const Spacer(),
          IconButton(
            tooltip: localizations.selectFile,
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.folder_open),
            onPressed: () => _openFileInto(controller),
          ),
        ]),
      ),
      Expanded(
        child: Container(
          margin: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          decoration: BoxDecoration(border: Border.all(color: Colors.black12)),
          child: Listener(
            onPointerDown: (e) => _onPointerDown(isLeft, e),
            onPointerMove: _onPointerMove,
            onPointerUp: (_) => _cancelLongPress(),
            onPointerCancel: (_) => _cancelLongPress(),
            child: CodeForge(
              // CodeForge 的 lineWrap 是 late final，切换得新 key 重建；
              // controller / undoController 在 State 持有，重建不丢文本与撤销栈。
              key: ValueKey('diff-$title-$_wrap'),
              controller: controller,
              undoController: isLeft ? _leftUndo : _rightUndo,
              lineWrap: _wrap,
              enableGuideLines: false,
              enableLocalSuggestions: true,
              editorTheme: editorTheme,
              textStyle: const TextStyle(fontSize: 14.5),
              matchHighlightStyle: matchStyle,
              finderBuilder: (c, controller) => FindPanelView(controller: controller),
              selectionStyle: CodeSelectionStyle(cursorColor: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
      ),
    ]);
  }

  /// 对齐并排视图：逐行对齐左右（缺失侧留空），差异行上底色。
  /// 解决窄屏 / 行数不等时「各显示自己行号、多段差异看不出对应关系」的问题。
  Widget _alignedView() {
    final rows = alignedDiffRows(_left.text, _right.text,
        ignoreCase: _ignoreCase, ignoreWhitespace: _ignoreWhitespace);
    if (rows.isEmpty) {
      return Center(
        child: Text(localizations.diffNoDifference, style: TextStyle(color: Colors.grey[600])),
      );
    }
    final isDark = Theme.brightnessOf(context) == Brightness.dark;
    Color? bgOf(DiffRowType t) {
      switch (t) {
        case DiffRowType.added:
          return Colors.green.withValues(alpha: isDark ? 0.22 : 0.15);
        case DiffRowType.deleted:
          return Colors.red.withValues(alpha: isDark ? 0.22 : 0.15);
        case DiffRowType.modified:
          return Colors.orange.withValues(alpha: isDark ? 0.22 : 0.15);
        case DiffRowType.equal:
          return null;
      }
    }

    return Scrollbar(
      child: ListView.builder(
        itemCount: rows.length,
        itemBuilder: (_, i) {
          final r = rows[i];
          final bg = bgOf(r.type);
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _alignedCell(r.leftLine, r.leftText, bg)),
                const VerticalDivider(width: 1, thickness: 0.2),
                Expanded(child: _alignedCell(r.rightLine, r.rightText, bg)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _alignedCell(int? line, String? text, Color? bg) {
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 38,
            child: Text(line?.toString() ?? '',
                textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text ?? '',
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace', height: 1.25),
            ),
          ),
        ],
      ),
    );
  }
}
