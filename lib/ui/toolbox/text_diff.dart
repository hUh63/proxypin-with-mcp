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
import 'dart:typed_data';

import 'package:code_forge/code_forge.dart';
import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/code_lint.dart';
import 'package:proxypin/ui/component/search/finder.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:proxypin/ui/component/snippet_bar.dart';
import 'package:proxypin/utils/text_diff.dart';
import 'package:proxypin/utils/tool_snippets.dart';
import 'package:proxypin/ui/component/search/finder.dart';
import 'package:proxypin/utils/smart_completion.dart';
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

  /// 并排还是上下。默认并排（左右两侧），用户切过就记住。
  static const String _sideKey = 'text_diff_side_by_side_v1';
  static const String _fontKey = 'text_diff_font_size_v1';
  bool _sideBySide = true;

  late final CodeForgeController _left;
  late final CodeForgeController _right;
  late final UndoRedoController _leftUndo;
  late final UndoRedoController _rightUndo;
  late final FindController _findLeft;
  late final FindController _findRight;

  bool _wrap = true;

  /// 忽略大小写 / 忽略空白：比较时归一化，显示仍是原文。
  bool _ignoreCase = false;
  bool _ignoreWhitespace = false;

  /// 对齐并排视图（逐行对齐、差异上底色）：这是主视图，默认开。
  /// 想直接编辑两侧文本时切到「编辑视图」（原码流视图）。
  bool _aligned = true;

  /// 显示字号（底部 +/- 调节）。
  double _fontSize = 13.5;

  /// 对齐视图：左右各一个纵向滚动控制器（互相联动）+ 各一个横向滚动控制器（各自独立）。
  final ScrollController _leftV = ScrollController();
  final ScrollController _rightV = ScrollController();
  final ScrollController _leftH = ScrollController();
  final ScrollController _rightH = ScrollController();

  /// 防止「A 带动 B、B 又带动 A」的回路。
  bool _syncingScroll = false;

  /// 双指缩放状态。
  final Map<int, Offset> _pointers = <int, Offset>{};
  double? _pinchBase;
  double _pinchStartFont = 13.5;

  /// 内容宽度缓存（估算最长行，缩放后要重算）。
  double _leftWidth = 0;
  double _rightWidth = 0;
  String _widthKey = '';

  /// 只显示差异（相同行折叠成一行占位），对应 VS diff 的 hide unchanged。
  bool _onlyDiff = false;

  /// 对齐视图的行缓存：每次 build 重算 diff 太贵（几千行会明显顿）。
  List<DiffRow> _alignedRowsCache = const <DiffRow>[];
  String _alignedRowsKey = '';
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
    SmartCompletion.load();
    SmartCompletion.enabled.addListener(_onSmartChanged);
    super.initState();
    _left = CodeForgeController()..text = widget.initialLeft ?? '';
    _right = CodeForgeController()..text = widget.initialRight ?? '';
    _leftUndo = UndoRedoController();
    _rightUndo = UndoRedoController();
    _left.setUndoController(_leftUndo);
    _right.setUndoController(_rightUndo);
    _findLeft = FindController(_left);
    _findRight = FindController(_right);
    // 读取失败不影响使用（默认左右并排），但 catchError 必须返回同类型值，
    // 否则会逃逸成未捕获异步错误（这个坑踩过）。
    _leftV.addListener(_syncFromLeft);
    _rightV.addListener(_syncFromRight);
    unawaited(SharedPreferencesAsync().getDouble(_fontKey).then((v) {
      if (!mounted || v == null || v == _fontSize) return;
      setState(() => _fontSize = v.clamp(11.0, 22.0));
    }).catchError((_) => null));
    unawaited(SharedPreferencesAsync().getBool(_sideKey).then((v) {
      if (!mounted || v == null || v == _sideBySide) return;
      setState(() => _sideBySide = v);
    }).catchError((_) => null));

    _left.addListener(_onLeftChanged);
    _right.addListener(_onRightChanged);
    _leftUndo.addListener(_onUndoChanged);
    _rightUndo.addListener(_onUndoChanged);

    if (Platforms.isDesktop() && widget.windowId != null) {
      HardwareKeyboard.instance.addHandler(_onKeyEvent);
    }

    _restoreIfNeeded();
  }

  void _onSmartChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SmartCompletion.enabled.removeListener(_onSmartChanged);
    _leftV.dispose();
    _rightV.dispose();
    _leftH.dispose();
    _rightH.dispose();
    _persistTimer?.cancel();
    _longPressTimer?.cancel();
    _left.removeListener(_onLeftChanged);
    _right.removeListener(_onRightChanged);
    _leftUndo.removeListener(_onUndoChanged);
    _rightUndo.removeListener(_onUndoChanged);
    _findLeft.dispose();
    _findRight.dispose();
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
    _scrollToCurrentRow();
  }

  /// 对齐视图里滚到当前差异（留一行上下文）。两侧联动，动左边就会带动右边。
  void _scrollToCurrentRow() {
    if (!_aligned || !_leftV.hasClients) return;
    final i = _currentRowIndex(_visibleRows(_alignedRows()));
    if (i < 0) return;
    final target = (i * _rowHeight - _rowHeight).clamp(0.0, _leftV.position.maxScrollExtent);
    _leftV.animateTo(target, duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
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
    // 必须 setState：搜索面板用的 controller（_findLeft / _findRight）由 _leftActive 决定，
    // 不触发重建的话面板会继续操作**上一侧**的 controller ——
    // 「先点右侧、再点左侧、然后回来点『下一个』」就会把跳转作用在错误的一侧。
    if (_leftActive != isLeft) {
      setState(() => _leftActive = isLeft);
    }
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
          _fileBar(),
          Row(
            children: [
              Expanded(child: _legend()),
              _toolbar(),
            ],
          ),
          const Divider(height: 1, thickness: 0.3),
          Expanded(
            child: _aligned
                ? _alignedView()
                // 默认对齐视图（逐行对齐 + 行号列）；两侧都还空着时退回编辑视图，
                // 否则用户进来连输入框都看不到，得先去点 ✏️。
                : (!_aligned || (_left.text.isEmpty && _right.text.isEmpty))
                    ? (_sideBySide ? _wideLayout() : _narrowLayout())
                    : _alignedView(),
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
          // 快捷插入只在编辑视图有意义（对齐视图是只读渲染）。
          if (!_aligned) _snippetBar(),
          _bottomBar(),
          AnimatedBuilder(
            animation: Listenable.merge([_findLeft, _findRight]),
            builder: (_, __) => FindPanelView(
                controller: _leftActive ? _findLeft : _findRight),
          ),
        ]),
      ),
    );
  }

  void _changeFontSize(double delta) {
    final next = (_fontSize + delta).clamp(11.0, 22.0);
    if (next == _fontSize) return;
    setState(() => _fontSize = next);
    unawaited(SharedPreferencesAsync().setDouble(_fontKey, next));
  }

  /// 交换左右（工具栏的 ↔）。文本、快照、标注一起换。
  void _swapSides() {
    final l = _left.text;
    final r = _right.text;
    _left.text = r;
    _right.text = l;
    _leftSnapshot = _right.text;
    _rightSnapshot = _left.text;
    _navIndex = -1;
    _compare();
    // 交换后两栏内容宽度可能完全变了，横向偏移要归零，否则可能停在空白处。
    for (final c in [_leftH, _rightH]) {
      if (c.hasClients) c.jumpTo(0);
    }
    setState(() {});
    _toastText(localizations.diffSwapped);
  }

  void _toastText(String msg) {
    if (!mounted) return;
    FlutterToastr.show(msg, context, duration: 2);
  }

  /// 顶部「更多」菜单：把不常用的开关收进来，主栏只留最常用的几个。
  Widget _moreMenu() {
    final color = Theme.of(context).colorScheme.primary;
    return PopupMenuButton<String>(
      tooltip: localizations.more,
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (v) {
        switch (v) {
          case 'ignoreCase':
            setState(() => _ignoreCase = !_ignoreCase);
            _compare();
          case 'ignoreSpace':
            setState(() => _ignoreWhitespace = !_ignoreWhitespace);
            _compare();
          case 'wrap':
            setState(() => _wrap = !_wrap);
          case 'onlyDiff':
            setState(() => _onlyDiff = !_onlyDiff);
          case 'syntax':
            unawaited(_checkSyntax());
          case 'swapLayout':
            final next = !_sideBySide;
            setState(() => _sideBySide = next);
            unawaited(SharedPreferencesAsync().setBool(_sideKey, next));
          case 'clear':
            _clearAll();
        }
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(value: 'ignoreCase', checked: _ignoreCase, child: Text(localizations.diffIgnoreCase)),
        CheckedPopupMenuItem(
            value: 'ignoreSpace', checked: _ignoreWhitespace, child: Text(localizations.diffIgnoreWhitespace)),
        CheckedPopupMenuItem(value: 'wrap', checked: _wrap, child: Text(localizations.wordWrap)),
        CheckedPopupMenuItem(
            value: 'onlyDiff', checked: _onlyDiff, child: Text(localizations.diffOnlyChanges)),
        PopupMenuItem(value: 'swapLayout', child: Text(
            _sideBySide ? localizations.diffStacked : localizations.diffSideBySide)),
        PopupMenuItem(value: 'syntax', child: Text(localizations.diffSyntaxCheck)),
        PopupMenuItem(value: 'clear', child: Text(localizations.clear)),
      ],
    );
  }

  /// 底部操作栏：`<` 上一处、`→` 下一处、`+/-` 字号、`*` 切编辑、`=` 统计、`/` 查找。
  Widget _bottomBar() {
    Widget btn(String label, String tip, VoidCallback? onTap, {bool active = false}) {
      final color = active ? Theme.of(context).colorScheme.primary : null;
      return Expanded(
        child: Tooltip(
          message: tip,
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 34,
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontFamily: 'monospace',
                  color: onTap == null ? Colors.grey : color,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final hasDiff = _blocks.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.4))),
      ),
      child: Row(children: [
        btn('<', localizations.diffPrev, hasDiff ? () => _navigate(-1) : null),
        btn('→', localizations.diffNext, hasDiff ? () => _navigate(1) : null),
        btn('+', localizations.editorZoomIn, () => _changeFontSize(1)),
        btn('-', localizations.editorZoomOut, () => _changeFontSize(-1)),
        btn('*', localizations.compare, () => setState(() => _aligned = !_aligned), active: _aligned),
        btn('=', localizations.editorStats, _showDiffStats),
        btn('/', localizations.search, () => _toggleFind(_leftActive ? _findLeft : _findRight)),
      ]),
    );
  }

  void _showDiffStats() {
    final stats = diffStats(_blocks);
    _toastText(localizations.diffStatsSummary(
        '${stats.added}', '${stats.deleted}', '${stats.modified}'));
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
      padding: const EdgeInsets.only(right: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _iconBtn(Icons.swap_horiz, localizations.diffSwapSides, _swapSides),
        _iconBtn(Icons.keyboard_arrow_up, localizations.diffPrev, hasDiff ? () => _navigate(-1) : null),
        _iconBtn(Icons.keyboard_arrow_down, localizations.diffNext, hasDiff ? () => _navigate(1) : null),
        _iconBtn(Icons.save_outlined, localizations.diffSaveRight, _saveResult),
        _iconBtn(Icons.edit_outlined, localizations.diffEditMode,
            () => setState(() => _aligned = !_aligned), tint: _aligned ? null : color),
        _moreMenu(),
      ]),
    );
  }

  /// 保存「修改后」那一侧的文本到文件（图片里的 💾）。
  Future<void> _saveResult() async {
    final text = _right.text;
    if (text.isEmpty) {
      _toastText(localizations.cannotBeEmpty);
      return;
    }
    try {
      await FilePicker.saveFile(
          fileName: 'diff-right.txt', bytes: Uint8List.fromList(utf8.encode(text)));
      if (mounted) _toastText(localizations.copied);
    } catch (e) {
      _toastText('${localizations.fail}: $e');
    }
  }

  /// 文件名行：左「原文」、中间差异计数、右「修改后」（对应图片里的布局）。
  Widget _fileBar() {
    final total = _blocks.length;
    final pos = total == 0 ? 0 : (_navIndex < 0 ? 1 : _navIndex + 1);
    final color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
      color: color.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Row(children: [
        Expanded(
          child: Text(localizations.diffOriginal,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: color.onSurfaceVariant)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(
            color: color.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text('$pos/$total',
              style: TextStyle(
                  fontSize: 11, fontFamily: 'monospace', color: color.primary, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Text(localizations.diffChanged,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: color.onSurfaceVariant)),
        ),
      ]),
    );
  }

  /// 对两侧文本做静态语法检查。
  ///
  /// 为什么不做行染色：diff 自己已经用 LineDecoration 标了增删改，
  /// 再往上叠一层会互相盖掉。所以结果是列成清单弹出来，点一条跳到原位置。
  Future<void> _checkSyntax() async {
    final chinese = Localizations.localeOf(context).languageCode.startsWith('zh');
    final left = _lintFor(_left.text, chinese);
    final right = _lintFor(_right.text, chinese);
    if (left == null && right == null) {
      FlutterToastr.show(localizations.diffSyntaxUnsupported, context, duration: 2);
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => DefaultTabController(
        length: 2,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TabBar(
            labelStyle: const TextStyle(fontSize: 13),
            tabs: [
              Tab(text: '${localizations.diffOriginal} ${left?.diagnostics.length ?? 0}'),
              Tab(text: '${localizations.diffChanged} ${right?.diagnostics.length ?? 0}'),
            ],
          ),
          SizedBox(
            height: 320,
            child: TabBarView(children: [
              _lintList(ctx, left, (d) => _jumpSide(true, d)),
              _lintList(ctx, right, (d) => _jumpSide(false, d)),
            ]),
          ),
        ]),
      ),
    );
  }

  LintReport? _lintFor(String text, bool chinese) {
    final trimmed = text.trimLeft();
    String? key;
    String label = 'Plain Text';
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      key = 'json';
      label = 'JSON';
    } else if (trimmed.startsWith('<')) {
      key = 'xml';
      label = 'XML';
    }
    if (key == null) return null;
    return CodeLint.check(text, langLabel: label, langKey: key, chinese: chinese);
  }

  void _jumpSide(bool isLeft, LintDiagnostic d) {
    final controller = isLeft ? _left : _right;
    final length = controller.text.length;
    final start = d.start.clamp(0, length);
    final end = (d.start + d.length).clamp(start, length);
    controller.selection = TextSelection(baseOffset: start, extentOffset: end);
    controller.scrollToLine(d.line - 1);
    Navigator.pop(context);
  }

  Widget _lintList(BuildContext ctx, LintReport? report, void Function(LintDiagnostic) onTap) {
    if (report == null) {
      return Center(child: Text(localizations.diffSyntaxUnsupported, style: const TextStyle(fontSize: 12)));
    }
    if (report.diagnostics.isEmpty) {
      return Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_outline, size: 15, color: Colors.green),
          const SizedBox(width: 6),
          Text(localizations.editorLintClean, style: const TextStyle(fontSize: 12)),
        ]),
      );
    }
    return ListView.builder(
      itemCount: report.diagnostics.length,
      itemBuilder: (context, i) {
        final d = report.diagnostics[i];
        final color = switch (d.severity) {
          LintSeverity.error => Colors.red,
          LintSeverity.warning => Colors.orange,
          LintSeverity.info => Colors.blueGrey,
        };
        return ListTile(
          dense: true,
          leading: Icon(Icons.circle, size: 10, color: color),
          title: Text('${d.line}:${d.column}  ${d.message}', style: const TextStyle(fontSize: 12)),
          subtitle: d.suggestion == null ? null : Text(d.suggestion!, style: const TextStyle(fontSize: 11)),
          onTap: () => onTap(d),
        );
      },
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
  /// 打开搜索时默认收起（不展开替换行）。
  void _toggleFind(FindController f) {
    if (!f.isActive) f.isReplaceMode = false;
    f.toggleActive();
  }

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
              key: ValueKey('diff-$title-$_wrap-${SmartCompletion.enabled.value}'),
              controller: controller,
              undoController: isLeft ? _leftUndo : _rightUndo,
              lineWrap: _wrap,
              enableGuideLines: false,
              enableLocalSuggestions: SmartCompletion.enabled.value,
              editorTheme: editorTheme,
              textStyle: const TextStyle(fontSize: 14.5),
              matchHighlightStyle: matchStyle,
              findController: isLeft ? _findLeft : _findRight,
              selectionStyle: CodeSelectionStyle(cursorColor: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
      ),
    ]);
  }

  /// 对齐视图的行（带缓存）：文本或忽略选项变了才重算。
  List<DiffRow> _alignedRows() {
    final key = '${_left.text.hashCode}|${_right.text.hashCode}|$_ignoreCase|$_ignoreWhitespace';
    if (key == _alignedRowsKey) return _alignedRowsCache;
    _alignedRowsKey = key;
    _alignedRowsCache = alignedDiffRows(_left.text, _right.text,
        ignoreCase: _ignoreCase, ignoreWhitespace: _ignoreWhitespace);
    return _alignedRowsCache;
  }

  /// 当前差异块在「对齐行列表」里的行号（找不到返回 -1）。
  int _currentRowIndex(List<DiffRow> rows) {
    if (_navIndex < 0 || _navIndex >= _blocks.length) return -1;
    final b = _blocks[_navIndex];
    final wantLeft = b.leftStart + 1;
    final wantRight = b.rightStart + 1;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].leftLine == wantLeft || rows[i].rightLine == wantRight) return i;
    }
    return -1;
  }

  double get _rowHeight => (_fontSize * 1.65).clamp(19.0, 40.0);

  /// 对齐并排视图：左右各一栏（行号 + 文本），两栏纵向滚动联动、
  /// 横向各自滚动、双指缩放统一字号。
  Widget _alignedView() {
    final rows = _visibleRows(_alignedRows());
    if (rows.isEmpty) {
      return Center(
        child: Text(localizations.diffNoDifference, style: TextStyle(color: Colors.grey[600])),
      );
    }
    _ensureWidths(rows);
    final current = _currentRowIndex(rows);
    final divider = Theme.of(context).dividerColor.withValues(alpha: 0.35);
    return Row(children: [
      Expanded(child: _alignedPane(rows, current, left: true)),
      Container(width: 1, color: divider),
      Expanded(child: _alignedPane(rows, current, left: false)),
      _densityBar(rows),
    ]);
  }

  /// 只显示差异时：保留每个差异块前后各一行上下文，其余折成一行占位。
  List<DiffRow> _visibleRows(List<DiffRow> rows) {
    if (!_onlyDiff) return rows;
    final keep = <int>{};
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].type == DiffRowType.equal) continue;
      for (var d = -1; d <= 1; d++) {
        final j = i + d;
        if (j >= 0 && j < rows.length) keep.add(j);
      }
    }
    if (keep.isEmpty) return const <DiffRow>[];
    final out = <DiffRow>[];
    var i = 0;
    while (i < rows.length) {
      if (keep.contains(i)) {
        out.add(rows[i]);
        i++;
      } else {
        final start = i;
        while (i < rows.length && !keep.contains(i)) {
          i++;
        }
        out.add(DiffRow(DiffRowType.equal, null,
            '⋯  ${i - start} ${localizations.diffUnchangedLines}', null, null));
      }
    }
    return out;
  }

  /// 右侧「差异密度条」：把每一行的类型按比例画成色块，点哪里滚到哪里（VS 的 overview ruler）。
  Widget _densityBar(List<DiffRow> rows) {
    final isDark = Theme.brightnessOf(context) == Brightness.dark;
    return LayoutBuilder(builder: (context, c) {
      // 监听滚动控制器画「当前视口」的滑块（滚动时不需要整页 setState）。
      return ListenableBuilder(
        listenable: _leftV,
        builder: (context, _) {
          var vpStart = 0.0;
          var vpEnd = 1.0;
          if (_leftV.hasClients) {
            final pos = _leftV.position;
            final total = pos.maxScrollExtent + pos.viewportDimension;
            if (total > 0) {
              vpStart = (pos.pixels / total).clamp(0.0, 1.0);
              vpEnd = ((pos.pixels + pos.viewportDimension) / total).clamp(vpStart, 1.0);
            }
          }
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              if (c.maxHeight <= 0) return;
              final i = (d.localPosition.dy / c.maxHeight * rows.length)
                  .floor()
                  .clamp(0, rows.length - 1);
              _scrollToRowIndex(i);
            },
            child: SizedBox(
              width: 9,
              height: double.infinity,
              child: CustomPaint(
                painter: _DensityPainter(rows, isDark, vpStart, vpEnd),
              ),
            ),
          );
        },
      );
    });
  }

  void _scrollToRowIndex(int i) {
    if (!_leftV.hasClients) return;
    final target = (i * _rowHeight).clamp(0.0, _leftV.position.maxScrollExtent);
    _leftV.animateTo(target,
        duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
  }

  /// 一栏：横向可滚（看长行），纵向 ListView（行高固定，便于精确跳转）。
  Widget _alignedPane(List<DiffRow> rows, int current, {required bool left}) {
    final vCtrl = left ? _leftV : _rightV;
    final hCtrl = left ? _leftH : _rightH;
    final width = left ? _leftWidth : _rightWidth;
    return Listener(
      // 用 Listener 而不是 GestureDetector：后者会和滚动手势抢竞技场，
      // 单指拖动会被当成 scale（pointerCount==1）而滚不动。
      onPointerDown: _onPinchDown,
      onPointerMove: _onPinchMove,
      onPointerUp: _onPinchUp,
      onPointerCancel: _onPinchUp,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = width > constraints.maxWidth ? width : constraints.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: hCtrl,
            child: SizedBox(
              width: w,
              child: ListView.builder(
                controller: vCtrl,
                itemExtent: _rowHeight,
                itemCount: rows.length,
                itemBuilder: (_, i) =>
                    _alignedRow(rows[i], left: left, isCurrent: i == current),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _alignedRow(DiffRow r, {required bool left, required bool isCurrent}) {
    final isDark = Theme.brightnessOf(context) == Brightness.dark;
    Color? bg;
    switch (r.type) {
      case DiffRowType.added:
        bg = Colors.green.withValues(alpha: isDark ? 0.20 : 0.16);
      case DiffRowType.deleted:
        bg = Colors.red.withValues(alpha: isDark ? 0.22 : 0.14);
      case DiffRowType.modified:
        bg = Colors.orange.withValues(alpha: isDark ? 0.18 : 0.12);
      case DiffRowType.equal:
        bg = null;
    }
    final line = left ? r.leftLine : r.rightLine;
    final text = left ? r.leftText : r.rightText;
    final numStyle = TextStyle(fontSize: _fontSize - 2, color: Colors.grey[600], height: 1.0);
    final textStyle = TextStyle(fontSize: _fontSize, fontFamily: 'monospace', height: 1.0);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          left: BorderSide(
              color: isCurrent ? Theme.of(context).colorScheme.primary : Colors.transparent,
              width: 2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(line?.toString() ?? '',
                textAlign: TextAlign.right, maxLines: 1, style: numStyle),
          ),
          const SizedBox(width: 5),
          // 不裁剪：横向滚动由外层负责，长行能一直往右看。
          Text(text ?? '', maxLines: 1, softWrap: false, overflow: TextOverflow.visible,
              style: textStyle),
        ],
      ),
    );
  }

  /// 估算两栏的内容宽度（等宽字体按 0.62 字宽，CJK 记 2 个字宽）。
  void _ensureWidths(List<DiffRow> rows) {
    final key = '$_alignedRowsKey|${_fontSize.toStringAsFixed(2)}';
    if (key == _widthKey) return;
    _widthKey = key;
    var maxLeft = 0;
    var maxRight = 0;
    for (final r in rows) {
      final l = _displayUnits(r.leftText);
      final rt = _displayUnits(r.rightText);
      if (l > maxLeft) maxLeft = l;
      if (rt > maxRight) maxRight = rt;
    }
    _leftWidth = 39 + maxLeft * _fontSize * 0.62 + 16;
    _rightWidth = 39 + maxRight * _fontSize * 0.62 + 16;
  }

  static int _displayUnits(String? text) {
    if (text == null || text.isEmpty) return 0;
    var units = 0;
    for (final c in text.codeUnits) {
      units += c > 0x1100 && (c <= 0x115f || (c >= 0x2e80 && c <= 0xa4cf) || c >= 0xac00) ? 2 : 1;
    }
    return units;
  }

  // ---------- 纵向联动 ----------

  void _syncFromLeft() => _syncVertical(_leftV, _rightV);
  void _syncFromRight() => _syncVertical(_rightV, _leftV);

  /// 两侧行数、行高完全一致，所以「同一像素位置」就是「同一对齐行」。
  void _syncVertical(ScrollController from, ScrollController to) {
    if (_syncingScroll || !from.hasClients || !to.hasClients) return;
    final max = to.position.maxScrollExtent;
    if (max <= 0) return;
    final target = from.offset.clamp(0.0, max);
    if ((to.offset - target).abs() < 0.5) return;
    _syncingScroll = true;
    to.jumpTo(target);
    _syncingScroll = false;
  }

  // ---------- 双指缩放（左右统一字号） ----------

  void _onPinchDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      final pts = _pointers.values.toList();
      _pinchBase = (pts[0] - pts[1]).distance;
      _pinchStartFont = _fontSize;
    }
  }

  void _onPinchMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length < 2) return;
    final base = _pinchBase;
    if (base == null || base < 1) return;
    final pts = _pointers.values.toList();
    final dist = (pts[0] - pts[1]).distance;
    final next = (_pinchStartFont * dist / base).clamp(9.0, 26.0);
    if ((next - _fontSize).abs() < 0.25) return;
    // 缩放时保持「顶部那一行」不动（行高变了，像素位置要跟着换算）。
    final anchorRow = _leftV.hasClients ? _leftV.offset / _rowHeight : 0.0;
    final anchorRightRow = _rightV.hasClients ? _rightV.offset / _rowHeight : 0.0;
    setState(() => _fontSize = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final h = _rowHeight;
      if (_leftV.hasClients) {
        _leftV.jumpTo((anchorRow * h).clamp(0.0, _leftV.position.maxScrollExtent));
      }
      if (_rightV.hasClients) {
        _rightV.jumpTo((anchorRightRow * h).clamp(0.0, _rightV.position.maxScrollExtent));
      }
    });
  }

  void _onPinchUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _pinchBase = null;
    if (_pointers.isEmpty) {
      unawaited(SharedPreferencesAsync().setDouble(_fontKey, _fontSize));
    }
  }


}

/// 差异密度条的绘制：行太多时按固定桶数聚合，避免每帧画几万个小矩形。
class _DensityPainter extends CustomPainter {
  _DensityPainter(this.rows, this.isDark, this.vpStart, this.vpEnd);

  final List<DiffRow> rows;
  final bool isDark;
  final double vpStart;
  final double vpEnd;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = (isDark ? Colors.white10 : Colors.black12));
    if (rows.isEmpty || size.height <= 0) return;

    final buckets = rows.length > 400 ? 400 : rows.length;
    final bucketHeight = size.height / buckets;
    final paint = Paint();
    for (var b = 0; b < buckets; b++) {
      final start = (b * rows.length / buckets).floor();
      final end = (((b + 1) * rows.length / buckets).ceil()).clamp(start + 1, rows.length);
      DiffRowType? type;
      for (var i = start; i < end; i++) {
        final t = rows[i].type;
        if (t == DiffRowType.equal) continue;
        // 一个桶里混了多种时优先显示「新增」—— 绿最能引起注意。
        if (type == null || t == DiffRowType.added) type = t;
      }
      if (type == null) continue;
      paint.color = switch (type) {
        DiffRowType.added => Colors.green.withValues(alpha: 0.9),
        DiffRowType.deleted => Colors.red.withValues(alpha: 0.9),
        DiffRowType.modified => Colors.orange.withValues(alpha: 0.9),
        DiffRowType.equal => Colors.transparent,
      };
      canvas.drawRect(
          Rect.fromLTWH(0, b * bucketHeight, size.width, bucketHeight < 1 ? 1 : bucketHeight), paint);
    }

    // 当前视口的位置（拖动滚动时跟着走，方便知道自己在文件的哪一段）。
    if (vpEnd > vpStart) {
      final top = vpStart * size.height;
      final h = ((vpEnd - vpStart) * size.height).clamp(2.0, size.height);
      final rect = Rect.fromLTWH(0, top, size.width, h);
      canvas.drawRect(rect, Paint()..color = Colors.white.withValues(alpha: 0.16));
      canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.38));
    }
  }

  @override
  bool shouldRepaint(covariant _DensityPainter oldDelegate) =>
      oldDelegate.rows != rows ||
      oldDelegate.isDark != isDark ||
      oldDelegate.vpStart != vpStart ||
      oldDelegate.vpEnd != vpEnd;
}
