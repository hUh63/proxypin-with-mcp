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
import 'package:proxypin/ui/toolbox/hex_diff_page.dart';
import 'package:proxypin/ui/toolbox/three_way_merge.dart';
import 'package:proxypin/utils/text_diff.dart';
import 'package:proxypin/utils/text_file_reader.dart';
import 'package:proxypin/utils/tool_snippets.dart';
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

  /// 最近几次对比的快照（最多 5 组）：「刚才那两段怎么改的」可以回看。
  static const String _historyKey = 'text_diff_history_v1';
  static const int _historyLimit = 5;
  bool _historyWriting = false;

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

  /// 对齐并排视图（逐行对齐、差异上底色）。
  ///
  /// 默认**关**（进页面就落在编辑态）：对比页最常见的动作是「贴/改两段文本」，
  /// 一进来是只读的对齐视图，很容易让人以为这里不能输入。想并排看差异时点
  /// 工具栏的对比按钮切过去，选择会记住。
  bool _aligned = false;
  static const String _alignedKey = 'text_diff_aligned_v1';

  /// 两栏的文件名（打开文件后显示在顶部标签里：「原文件 · xxx.txt」）。
  String _leftName = '';
  String _rightName = '';

  /// 显示字号（底部 +/- 调节）。
  double _fontSize = 13.5;

  /// 对齐视图：左右各一个纵向滚动控制器（互相联动）+ 各一个横向滚动控制器（各自独立）。
  final ScrollController _leftV = ScrollController();
  final ScrollController _rightV = ScrollController();
  final ScrollController _leftH = ScrollController();
  final ScrollController _rightH = ScrollController();

  /// 防止「A 带动 B、B 又带动 A」的回路。
  bool _syncingScroll = false;

  /// 右侧「差异密度条」只在滚动时出现，停止 1.1 秒后淡出。
  ///
  /// 用户反馈：它常驻在右边，看起来像一条滚动条，还占横向空间。功能（点哪跳哪）
  /// 保留，只是平时不挡视线。
  final ValueNotifier<bool> _densityVisible = ValueNotifier<bool>(false);
  Timer? _densityTimer;

  void _bumpDensity() {
    _densityVisible.value = true;
    _densityTimer?.cancel();
    _densityTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) _densityVisible.value = false;
    });
  }

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

  /// 同步横向滚动：一栏往右看长行时另一栏跟着走（默认关，两栏独立更常用）。
  bool _syncH = false;
  bool _syncingH = false;

  /// 聚焦模式：只显示某一处差异（±[_focusContext] 行上下文），
  /// 配合底部「← 用右侧 / 用左侧 →」逐个块过一遍——多轮改动后逐块确认最省心。
  int? _focusBlock;

  /// 折叠「连续未变」的段落（VS Code 的 Fold Unchanged Regions）。
  bool _foldUnchanged = false;

  /// 已被用户手动展开的折叠段（值是折叠段在未折叠列表里的起始下标）。
  final Set<int> _expandedFolds = <int>{};

  /// 只看某一类差异（`added` / `deleted` / `modified`）；null = 全部。
  /// 对标 Beyond Compare 的「只显示新增/删除/修改」过滤。
  String? _typeFilter;

  /// 聚焦模式保留的上下文行数。
  static const int _focusContext = 3;

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
    // 横向同步：常驻监听，开关关闭时 `_syncHorizontal` 第一行就返回。
    _leftH.addListener(() => _syncHorizontal(_leftH, _rightH));
    _rightH.addListener(() => _syncHorizontal(_rightH, _leftH));
    unawaited(SharedPreferencesAsync().getDouble(_fontKey).then((v) {
      if (!mounted || v == null || v == _fontSize) return;
      setState(() => _fontSize = v.clamp(11.0, 22.0));
    }).catchError((_) => null));
    unawaited(SharedPreferencesAsync().getBool(_sideKey).then((v) {
      if (!mounted || v == null || v == _sideBySide) return;
      setState(() => _sideBySide = v);
    }).catchError((_) => null));
    unawaited(SharedPreferencesAsync().getBool(_alignedKey).then((v) {
      if (!mounted || v == null || v == _aligned) return;
      setState(() => _aligned = v);
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
    _densityTimer?.cancel();
    _densityVisible.dispose();
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
      // 文件名也要一起恢复：「原文件 · a.txt / 新文件 · b.txt」是这一页的主要
      // 信息之一，只存正文的话下次进来标签就退回「原文件/新文件」。
      _leftName = (m['leftName'] as String?) ?? '';
      _rightName = (m['rightName'] as String?) ?? '';
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
      await sp.setString(
          _storeKey,
          jsonEncode({
            'left': _left.text,
            'right': _right.text,
            'leftName': _leftName,
            'rightName': _rightName,
          }));
    } catch (_) {}
    unawaited(_pushHistory());
  }

  /// 把当前这对文本压进「最近对比」历史（同内容不重复，最多 5 组）。
  Future<void> _pushHistory() async {
    final left = _left.text;
    final right = _right.text;
    if (left.isEmpty && right.isEmpty) return;
    // 太大的不存：SharedPreferences 不是给几 MB 文本用的。
    if (left.length + right.length > 400000) return;
    if (_historyWriting) return;
    _historyWriting = true;
    try {
      final sp = await SharedPreferencesAsync();
      final raw = await sp.getString(_historyKey);
      final list = <Map<String, dynamic>>[];
      if (raw != null && raw.isNotEmpty) {
        try {
          for (final e in jsonDecode(raw) as List) {
            if (e is Map) list.add(Map<String, dynamic>.from(e));
          }
        } catch (_) {
          // 历史坏了就当没有，别影响主流程
        }
      }
      if (list.isNotEmpty && list.first['left'] == left && list.first['right'] == right) return;
      list.insert(0, {
        'left': left,
        'right': right,
        'time': DateTime.now().millisecondsSinceEpoch,
      });
      while (list.length > _historyLimit) {
        list.removeLast();
      }
      await sp.setString(_historyKey, jsonEncode(list));
    } catch (_) {
      // 历史只是便利功能，失败静默
    } finally {
      _historyWriting = false;
    }
  }

  /// 最近对比记录：点一条把左右两侧恢复成当时的内容。
  Future<void> _showDiffHistory() async {
    List<Map<String, dynamic>> list = const [];
    try {
      final sp = await SharedPreferencesAsync();
      final raw = await sp.getString(_historyKey);
      if (raw != null && raw.isNotEmpty) {
        list = [
          for (final e in jsonDecode(raw) as List)
            if (e is Map) Map<String, dynamic>.from(e),
        ];
      }
    } catch (_) {
      list = const [];
    }
    if (!mounted) return;
    if (list.isEmpty) {
      _toastText(localizations.diffHistoryEmpty);
      return;
    }
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView.builder(
        shrinkWrap: true,
        itemCount: list.length,
        itemBuilder: (ctx, i) {
          final item = list[i];
          final l = (item['left'] as String?) ?? '';
          final r = (item['right'] as String?) ?? '';
          final time = item['time'] is int
              ? DateTime.fromMillisecondsSinceEpoch(item['time'] as int)
              : null;
          final firstLine = (r.isEmpty ? l : r).split('\n').first.trim();
          return ListTile(
            dense: true,
            leading: Text('${i + 1}', style: const TextStyle(fontSize: 11)),
            title: Text(
              firstLine.isEmpty ? localizations.diffHistoryEmpty : firstLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
            ),
            subtitle: Text(
              '${time == null ? '' : _historyTime(time)}  '
              'L${l.isEmpty ? 0 : '\n'.allMatches(l).length + 1} / '
              'R${r.isEmpty ? 0 : '\n'.allMatches(r).length + 1}',
              style: const TextStyle(fontSize: 10.5),
            ),
            onTap: () => Navigator.pop(ctx, i),
          );
        },
      ),
    );
    if (!mounted || picked == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(localizations.diffHistoryRestore),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(localizations.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(localizations.confirm)),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    final item = list[picked];
    _left.text = (item['left'] as String?) ?? '';
    _right.text = (item['right'] as String?) ?? '';
    _leftUndo.clear();
    _rightUndo.clear();
    _leftName = '';
    _rightName = '';
    _navIndex = -1;
    _compare();
    setState(() {});
  }

  static String _historyTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
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
        final lt = _left.getLineText(ll);
        final rt = _right.getLineText(rl);
        // 字符级 LCS 也是 O(m·n)：压缩过的单行文件（几十万字符）必须跳过，
        // 否则一按「对比」就卡死。整行底色仍然会画，只是没有逐字高亮。
        if (lt.length > 3000 || rt.length > 3000) continue;
        final cd = diffChars(lt, rt);
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
        _expandedFolds.clear();
        // 块数变了：聚焦下标越界就退出聚焦，否则保持在原块上。
        if (_focusBlock != null && _focusBlock! >= blocks.length) _focusBlock = null;
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
    setState(() {
      _navIndex = index;
      // 聚焦模式下「上一处/下一处」直接切到那一块。
      if (_focusBlock != null) _focusBlock = index;
    });

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
    _leftName = '';
    _rightName = '';
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
      // 不能直接 readAsString（严格 UTF-8）：GBK 的 .txt/.properties 会直接抛，
      // 用户看到的就是「文件打不开」。走带容错解码的公共入口。
      final content = await readTextFileLenient(File(path));
      target.text = content.text;
      if (!mounted) return;
      final name = path.split(Platform.pathSeparator).last;
      setState(() {
        if (identical(target, _left)) {
          _leftName = name;
        } else {
          _rightName = name;
        }
      });
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
        // 桌面快捷键（对齐 Beyond Compare / Meld 的习惯）：
        //   F7 / Alt+↓ 下一处差异，Shift+F7 / Alt+↑ 上一处。
        // 只包 body，不动输入框自己的按键行为。
        body: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.f7): () => _navigate(1),
            const SingleActivator(LogicalKeyboardKey.f7, shift: true): () => _navigate(-1),
            const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () => _navigate(1),
            const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () => _navigate(-1),
          },
          child: Focus(
            autofocus: true,
            child: Column(children: [
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
        ),
      ),
    );
  }

  /// 对齐视图 ↔ 编辑视图，并把选择记住。
  void _toggleAligned() {
    final next = !_aligned;
    setState(() => _aligned = next);
    unawaited(SharedPreferencesAsync().setBool(_alignedKey, next));
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
    // 文件名跟着内容走，否则「原文件 · a.txt」会指向交换后的另一份内容。
    final ln = _leftName;
    _leftName = _rightName;
    _rightName = ln;
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
          case 'syncH':
            setState(() => _syncH = !_syncH);
            if (_syncH) _syncHorizontal(_leftH, _rightH);
          case 'focus':
            setState(() {
              if (_focusBlock != null) {
                _focusBlock = null;
              } else if (_blocks.isNotEmpty) {
                _focusBlock = _navIndex >= 0 ? _navIndex : 0;
              }
            });
          case 'allFromLeft':
            _applyAll(fromLeft: true);
          case 'allFromRight':
            _applyAll(fromLeft: false);
          case 'exportReport':
            unawaited(_exportReport());
          case 'zoomIn':
            _changeFontSize(1);
          case 'zoomOut':
            _changeFontSize(-1);
          case 'stats':
            _showDiffStats();
          case 'filterAdd':
            setState(() => _typeFilter = _typeFilter == 'added' ? null : 'added');
          case 'filterDel':
            setState(() => _typeFilter = _typeFilter == 'deleted' ? null : 'deleted');
          case 'filterMod':
            setState(() => _typeFilter = _typeFilter == 'modified' ? null : 'modified');
          case 'exportHtml':
            unawaited(_exportHtmlReport());
          case 'history':
            unawaited(_showDiffHistory());
          case 'diffList':
            _showDiffList();
          case 'hexDiff':
            unawaited(Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HexDiffPage())));
          case 'foldUnchanged':
            setState(() {
              _foldUnchanged = !_foldUnchanged;
              _expandedFolds.clear();
            });
          case 'threeWay':
            unawaited(_openThreeWayMerge());
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
        CheckedPopupMenuItem(
            value: 'syncH', checked: _syncH, child: Text(localizations.diffSyncHScroll)),
        CheckedPopupMenuItem(
            value: 'foldUnchanged',
            checked: _foldUnchanged,
            child: Text(localizations.diffFoldUnchanged)),
        PopupMenuItem(value: 'zoomIn', child: Text(localizations.editorZoomIn)),
        PopupMenuItem(value: 'zoomOut', child: Text(localizations.editorZoomOut)),
        PopupMenuItem(value: 'stats', child: Text(localizations.editorStats)),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
            value: 'filterAdd',
            checked: _typeFilter == 'added',
            child: Text(localizations.diffOnlyAdded)),
        CheckedPopupMenuItem(
            value: 'filterDel',
            checked: _typeFilter == 'deleted',
            child: Text(localizations.diffOnlyDeleted)),
        CheckedPopupMenuItem(
            value: 'filterMod',
            checked: _typeFilter == 'modified',
            child: Text(localizations.diffOnlyModified)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'exportReport', child: Text(localizations.diffExportReport)),
        PopupMenuItem(value: 'exportHtml', child: Text(localizations.diffExportHtmlReport)),
        PopupMenuItem(value: 'diffList', child: Text(localizations.diffList)),
        PopupMenuItem(value: 'hexDiff', child: Text(localizations.hexDiffTitle)),
        PopupMenuItem(value: 'threeWay', child: Text(localizations.diffThreeWay)),
        PopupMenuItem(value: 'history', child: Text(localizations.diffHistory)),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
            value: 'focus', checked: _focusBlock != null, child: Text(localizations.diffFocus)),
        PopupMenuItem(
          value: 'allFromLeft',
          enabled: _blocks.isNotEmpty,
          child: Text(localizations.diffApplyAllLeft),
        ),
        PopupMenuItem(
          value: 'allFromRight',
          enabled: _blocks.isNotEmpty,
          child: Text(localizations.diffApplyAllRight),
        ),
        PopupMenuItem(value: 'swapLayout', child: Text(
            _sideBySide ? localizations.diffStacked : localizations.diffSideBySide)),
        PopupMenuItem(value: 'syntax', child: Text(localizations.diffSyntaxCheck)),
        PopupMenuItem(value: 'clear', child: Text(localizations.clear)),
      ],
    );
  }

  /// 底部只剩「聚焦单块」时的操作条。
  ///
  /// 原来这里还有一行 `<` `→` `+` `-` `*` `=` `/` 的符号按钮，除了字号 / 统计 /
  /// 查找之外全部与工具栏重复，和上面的快捷输入行叠在一起像「两个符号栏」。这些
  /// 动作已分别挪到工具栏（查找）与「更多」菜单（放大 / 缩小 / 统计）。
  Widget _bottomBar() {
    if (_focusBlock != null && _focusBlock! < _blocks.length) return _focusBar();
    return const SizedBox.shrink();
  }

  /// 聚焦模式的底部条：当前第几处 + 「用右侧 / 用左侧」+ 退出。
  Widget _focusBar() {
    final idx = _focusBlock ?? 0;
    final theme = Theme.of(context);
    return Container(
      height: 40,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4))),
        color: theme.colorScheme.primary.withValues(alpha: 0.04),
      ),
      child: Row(children: [
        const SizedBox(width: 10),
        Text('${localizations.diffFocus} ${idx + 1}/${_blocks.length}',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.primary)),
        const Spacer(),
        TextButton(
          onPressed: () => _applyBlock(_blocks[idx], fromLeft: false),
          child: Text('← ${localizations.diffUseRight}',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
        ),
        TextButton(
          onPressed: () => _applyBlock(_blocks[idx], fromLeft: true),
          child: Text('${localizations.diffUseLeft} →',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
        ),
        IconButton(
          tooltip: localizations.cancel,
          icon: const Icon(Icons.close, size: 17),
          onPressed: () => setState(() => _focusBlock = null),
        ),
        const SizedBox(width: 2),
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
        _iconBtn(Icons.search, localizations.search,
            () => _toggleFind(_leftActive ? _findLeft : _findRight)),
        _iconBtn(Icons.save_outlined, localizations.diffSaveRight, _saveResult),
        // 对齐（并排对比）↔ 编辑：图标跟着当前状态换，点一下切过去。
        _iconBtn(
            _aligned ? Icons.edit_outlined : Icons.compare_arrows,
            _aligned ? localizations.diffEditMode : localizations.compare,
            _toggleAligned,
            tint: _aligned ? color : null),
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

  /// 文件名行：左「原文件」、中间差异计数、右「新文件」。
  ///
  /// 打开过文件时标签后面带上文件名（「原文件 · a.txt」），不用猜哪边是哪份。
  /// 整行限制字体放大倍数：系统字体调到 1.3 倍以上时，这一行会被挤到只剩半个
  /// 字（用户反馈过「新文件」显示不全）。
  Widget _fileBar() {
    final total = _blocks.length;
    final pos = total == 0 ? 0 : (_navIndex < 0 ? 1 : _navIndex + 1);
    final color = Theme.of(context).colorScheme;

    Widget label(String base, String name, {TextAlign align = TextAlign.left}) {
      return Expanded(
        child: Text(
          name.isEmpty ? base : '$base · $name',
          textAlign: align,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: color.onSurfaceVariant),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
      color: color.surfaceContainerHighest.withValues(alpha: 0.4),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: Row(children: [
          label(localizations.diffOriginal, _leftName),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: color.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text('$pos/$total',
                style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: color.primary,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          label(localizations.diffChanged, _rightName, align: TextAlign.right),
        ]),
      ),
    );
  }

  /// 导出 HTML 报告（对标 Beyond Compare / WinMerge 的 HTML 报告）。
  ///
  /// 并排表格 + 底色 + 行号，双击就能在浏览器里看，也能直接发给别人 ——
  /// Markdown 报告适合贴 issue，HTML 适合「让人一眼看出改了哪」。
  Future<void> _exportHtmlReport() async {
    final rows = _alignedRows();
    if (rows.isEmpty) {
      _toastText(localizations.cannotBeEmpty);
      return;
    }
    const maxRows = 8000;
    final shown = rows.length > maxRows ? rows.sublist(0, maxRows) : rows;
    final changed = rows.where((r) => r.type != DiffRowType.equal).length;
    final esc = const HtmlEscape().convert;

    final sb = StringBuffer()
      ..writeln('<!DOCTYPE html>')
      ..writeln('<html lang="en"><head><meta charset="utf-8">')
      ..writeln('<meta name="viewport" content="width=device-width, initial-scale=1">')
      ..writeln('<title>Diff report</title>')
      ..writeln([
        '<style>',
        'body{margin:0;padding:16px;font:13px/1.5 -apple-system,Segoe UI,Helvetica,Arial,sans-serif;color:#1b1b1b;background:#fff}',
        'h1{font-size:17px;margin:0 0 2px}',
        '.meta{color:#6b6b6b;font-size:12px;margin-bottom:12px}',
        'table{border-collapse:collapse;width:100%;table-layout:fixed}',
        'td{font:12px/1.45 ui-monospace,Menlo,Consolas,monospace;white-space:pre-wrap;word-break:break-word;vertical-align:top;padding:1px 6px;border-bottom:1px solid #f0f0f0}',
        'td.ln{width:54px;text-align:right;color:#9a9a9a;background:#fafafa}',
        'tr.eq td{background:#fff}',
        'tr.del td{background:#ffecec}',
        'tr.add td{background:#eaffea}',
        'tr.mod td{background:#fff8e1}',
        '.hint{color:#9a9a9a;font-size:11px;margin-top:10px}',
        '</style></head><body>'
      ].join('\n'))
      ..writeln('<h1>Diff report</h1>')
      ..writeln('<div class="meta">${rows.length} rows &middot; $changed changed'
          '${_ignoreCase ? ' &middot; ignore case' : ''}'
          '${_ignoreWhitespace ? ' &middot; ignore whitespace' : ''}</div>')
      ..writeln('<table>');

    for (final r in shown) {
      final cls = switch (r.type) {
        DiffRowType.equal => 'eq',
        DiffRowType.added => 'add',
        DiffRowType.deleted => 'del',
        DiffRowType.modified => 'mod',
      };
      final left = r.leftText == null ? '' : esc(r.leftText!);
      final right = r.rightText == null ? '' : esc(r.rightText!);
      sb.writeln('<tr class="$cls">'
          '<td class="ln">${r.leftLine ?? ''}</td><td>${left.isEmpty ? '&nbsp;' : left}</td>'
          '<td class="ln">${r.rightLine ?? ''}</td><td>${right.isEmpty ? '&nbsp;' : right}</td>'
          '</tr>');
    }
    sb.writeln('</table>');
    if (rows.length > maxRows) {
      sb.writeln('<div class="hint">Only the first $maxRows rows are included '
          '(${rows.length} total).</div>');
    }
    sb.writeln('</body></html>');

    try {
      await FilePicker.saveFile(
          fileName: 'diff-report.html',
          bytes: Uint8List.fromList(utf8.encode(sb.toString())));
      if (mounted) _toast(localizations.copied);
    } catch (e) {
      _toast('${localizations.fail}: $e');
    }
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

  /// 同步横向滚动：把 src 的偏移镜像到 dst（`_syncingH` 防回路）。
  void _syncHorizontal(ScrollController src, ScrollController dst) {
    if (!_syncH || _syncingH || !src.hasClients || !dst.hasClients) return;
    final max = dst.position.maxScrollExtent;
    if (max <= 0) return;
    final target = src.offset.clamp(0.0, max);
    if ((dst.offset - target).abs() < 0.5) return;
    _syncingH = true;
    try {
      dst.jumpTo(target);
    } catch (_) {
      // 目标栏正在重新布局（maxScrollExtent 还在变），跳过这一帧即可。
    } finally {
      _syncingH = false;
    }
  }

  /// 打开三方合并：预填当前左右内容（左=基线、右=我的），返回的合并结果
  /// 可以选择直接替换右栏，省掉「保存到文件再打开」。
  Future<void> _openThreeWayMerge() async {
    final merged = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => ThreeWayMergePage(
        initialBase: _left.text,
        initialMine: _right.text,
      ),
    ));
    if (!mounted || merged == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(localizations.mergeReplaceRight),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(localizations.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(localizations.confirm)),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    _right.text = merged;
    _compare();
    _toast(localizations.diffApplied);
  }

  /// 差异列表（WinMerge 的 diff 列表 / Meld 的侧栏）：全部差异一次列出来，
  /// 点一条就直接跳到那块并把光标放过去。
  void _showDiffList() {
    if (_blocks.isEmpty) {
      _toastText(localizations.diffNoDifference);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.25,
          maxChildSize: 0.9,
          builder: (ctx, scroll) => Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
              child: Row(children: [
                Text('${localizations.diffList}  (${_blocks.length})',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scroll,
                itemCount: _blocks.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final b = _blocks[i];
                  final added = b.rightLines.length - b.pairs.length;
                  final deleted = b.leftLines.length - b.pairs.length;
                  final parts = <String>[];
                  if (b.pairs.isNotEmpty) parts.add('${localizations.diffModified} ${b.pairs.length}');
                  if (added > 0) parts.add('${localizations.diffAdded} $added');
                  if (deleted > 0) parts.add('${localizations.diffDeleted} $deleted');
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Text('${i + 1}',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                    title: Text(
                      'L${b.leftStart + 1} ↔ R${b.rightStart + 1}   ${parts.join(' · ')}',
                      style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                    ),
                    subtitle: _blockPreview(b),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      setState(() {
                        _navIndex = i;
                        if (_focusBlock != null) _focusBlock = i;
                      });
                      _gotoLine(_left, b.leftStart);
                      _gotoLine(_right, b.rightStart);
                      _scrollToCurrentRow();
                    },
                  );
                },
              ),
            ),
          ]),
        );
      },
    );
  }

  /// 差异列表里每条的一行摘要：优先显示「右侧新内容」，没有就显示左侧被删内容。
  Widget? _blockPreview(DiffBlock b) {
    String? text;
    if (b.rightLines.isNotEmpty) {
      final idx = b.rightLines.first;
      if (idx >= 0 && idx < _right.lineCount) text = _lineText(_right, idx);
    }
    if (text == null && b.leftLines.isNotEmpty) {
      final idx = b.leftLines.first;
      if (idx >= 0 && idx < _left.lineCount) text = _lineText(_left, idx);
    }
    if (text == null) return null;
    return Text(text.trim(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'));
  }

  /// 取某行的文本（不带换行符）。
  String _lineText(CodeForgeController controller, int line) {
    try {
      final start = controller.getLineStartOffset(line);
      final end = line + 1 < controller.lineCount ? controller.getLineStartOffset(line + 1) : controller.text.length;
      final raw = controller.text.substring(start.clamp(0, controller.text.length), end.clamp(0, controller.text.length));
      return raw.endsWith('\n') ? raw.substring(0, raw.length - 1) : raw;
    } catch (_) {
      return '';
    }
  }

  /// 导出差异报告（Markdown，unified diff 风格）：存档 / 贴 issue 都能用。
  Future<void> _exportReport() async {
    final rows = _alignedRows();
    if (rows.isEmpty) {
      _toastText(localizations.cannotBeEmpty);
      return;
    }
    final buf = StringBuffer();
    final changed = rows.where((r) => r.type != DiffRowType.equal).length;
    buf.writeln('# ${localizations.diffReport}');
    buf.writeln('# ${DateTime.now()} · ${rows.length} rows · $changed changed');
    if (_ignoreCase || _ignoreWhitespace) {
      buf.writeln('# ignore: '
          '${_ignoreCase ? 'case ' : ''}${_ignoreWhitespace ? 'whitespace' : ''}');
    }
    buf.writeln();
    var inBlock = false;
    for (final r in rows) {
      if (r.type == DiffRowType.equal) {
        inBlock = false;
        continue;
      }
      if (!inBlock) {
        inBlock = true;
        buf.writeln('@@ L${r.leftLine ?? '-'} / R${r.rightLine ?? '-'} @@');
      }
      switch (r.type) {
        case DiffRowType.deleted:
          buf.writeln('- ${r.leftText ?? ''}');
        case DiffRowType.added:
          buf.writeln('+ ${r.rightText ?? ''}');
        case DiffRowType.modified:
          buf.writeln('- ${r.leftText ?? ''}');
          buf.writeln('+ ${r.rightText ?? ''}');
        case DiffRowType.equal:
          break;
      }
    }
    try {
      final saved = await FilePicker.saveFile(
          fileName: 'diff-report.md',
          bytes: Uint8List.fromList(utf8.encode(buf.toString())));
      if (!mounted) return;
      if (saved != null) _toastText(localizations.diffReportSaved);
    } catch (e) {
      _toastText('${localizations.fail}: $e');
    }
  }

  /// 聚焦模式下的一屏：这一处差异 + 前后各 [_focusContext] 行上下文。
  List<DiffRow> _focusRows(List<DiffRow> rows, DiffBlock b) {
    final wantLeft = b.leftStart + 1;
    final wantRight = b.rightStart + 1;
    var start = -1;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].leftLine == wantLeft || rows[i].rightLine == wantRight) {
        start = i;
        break;
      }
    }
    if (start < 0) return rows;
    var count = b.leftLines.length + b.rightLines.length;
    if (count < 1) count = 1;
    final from = (start - _focusContext).clamp(0, rows.length);
    final to = (start + count + _focusContext).clamp(0, rows.length);
    if (to <= from) return rows;
    return rows.sublist(from, to);
  }

  /// 全部接受：把一侧的每一处差异一次性搬到另一侧（Beyond Compare 的 All Left / All Right）。
  ///
  /// 逐块改写会因为 `_compare()` 重建块表而错位，所以这里先按**目标侧偏移**
  /// 算出所有替换，再从后往前一次性拼出新文本。
  void _applyAll({required bool fromLeft}) {
    if (_blocks.isEmpty) return;
    if (!mounted) return;
    final src = fromLeft ? _left : _right;
    final dst = fromLeft ? _right : _left;
    final ops = <({int start, int end, String text})>[];
    for (final b in _blocks) {
      final srcStart = fromLeft ? b.leftStart : b.rightStart;
      final srcCount = fromLeft ? b.leftLines.length : b.rightLines.length;
      final dstStart = fromLeft ? b.rightStart : b.leftStart;
      final dstCount = fromLeft ? b.rightLines.length : b.leftLines.length;
      try {
        final sOff = src.getLineStartOffset(srcStart.clamp(0, src.lineCount - 1));
        final sEnd = srcStart + srcCount < src.lineCount
            ? src.getLineStartOffset(srcStart + srcCount)
            : src.text.length;
        final dOff = dst.getLineStartOffset(dstStart.clamp(0, dst.lineCount - 1));
        final dEnd = dstStart + dstCount < dst.lineCount
            ? dst.getLineStartOffset(dstStart + dstCount)
            : dst.text.length;
        ops.add((start: dOff, end: dEnd, text: src.text.substring(sOff, sEnd)));
      } catch (_) {
        continue;
      }
    }
    if (ops.isEmpty) return;
    ops.sort((a, b) => b.start.compareTo(a.start));
    var text = dst.text;
    var lastStart = text.length + 1;
    var applied = 0;
    for (final op in ops) {
      // 与前一个已应用区间重叠就跳过（正常不会发生，纯防御）。
      if (op.end > lastStart || op.start > op.end) continue;
      text = text.replaceRange(op.start, op.end, op.text);
      lastStart = op.start;
      applied++;
    }
    if (applied == 0) return;
    dst.text = text;
    setState(() => _focusBlock = null);
    _compare();
    _toast(localizations.diffApplied);
  }

  /// 只显示差异时：保留每个差异块前后各一行上下文，其余折成一行占位。
  List<DiffRow> _visibleRows(List<DiffRow> rows) {
    final fb = _focusBlock;
    if (fb != null && fb >= 0 && fb < _blocks.length) {
      return _focusRows(rows, _blocks[fb]);
    }
    if (!_onlyDiff && _typeFilter == null) {
      return _foldUnchanged ? _foldRuns(rows) : rows;
    }
    final keep = <int>{};
    for (var i = 0; i < rows.length; i++) {
      final type = rows[i].type;
      if (type == DiffRowType.equal) continue;
      if (_typeFilter != null && type.name != _typeFilter) continue;
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

  /// 折叠连续未变的段落（引擎侧 [foldUnchangedRuns]，这里只提供文案）。
  List<DiffRow> _foldRuns(List<DiffRow> rows) => foldUnchangedRuns(
        rows,
        expanded: _expandedFolds,
        label: (n) => '⋯  $n ${localizations.diffUnchangedLines}',
      );

  /// 双击对齐视图的某一行 → 切到编辑视图并把光标放到对应行。
  void _editAtRow(DiffRow row, {required bool left}) {
    final line = left ? row.leftLine : row.rightLine;
    if (line == null || line <= 0) return;
    if (_aligned) {
      setState(() => _aligned = false);
      unawaited(SharedPreferencesAsync().setBool(_alignedKey, false));
    }
    // 编辑视图是另一套 widget 树（CodeForge 重建），等这一帧画完再定位。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _gotoLine(left ? _left : _right, line - 1);
    });
  }

  /// 展开 / 收起一个折叠段。
  void _toggleFold(int from) {
    if (!mounted) return;
    setState(() {
      if (!_expandedFolds.add(from)) _expandedFolds.remove(from);
    });
  }

  /// 右侧「差异密度条」：把每一行的类型按比例画成色块，点哪里滚到哪里（VS 的 overview ruler）。
  Widget _densityBar(List<DiffRow> rows) {
    final isDark = Theme.brightnessOf(context) == Brightness.dark;
    // 平时隐藏（用户反馈它常驻在右边像条滚动条），滚动时淡入、停 1.1 秒淡出。
    // 占位宽度保留 9dp，避免显隐时整页横向跳动。
    final bar = LayoutBuilder(builder: (context, c) {
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
    return ValueListenableBuilder<bool>(
      valueListenable: _densityVisible,
      builder: (context, visible, child) => AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: IgnorePointer(ignoring: !visible, child: child),
      ),
      child: bar,
    );
  }

  void _scrollToRowIndex(int i) {
    if (!_leftV.hasClients) return;
    // 点密度条 = 跳到这一行：顺手把「当前第几处差异」也切过去，
    // 否则点完不知道自己在第几块，接着按「下一处」会从旧位置重新算。
    final rows = _visibleRows(_alignedRows());
    if (i >= 0 && i < rows.length && rows[i].type != DiffRowType.equal) {
      final line = rows[i].leftLine ?? rows[i].rightLine;
      if (line != null) {
        final b = _blockAtLine(rows[i].leftLine != null, line - 1);
        final idx = b == null ? -1 : _blocks.indexOf(b);
        if (idx >= 0) {
          setState(() {
            _navIndex = idx;
            if (_focusBlock != null) _focusBlock = idx;
          });
        }
      }
    }
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
                itemBuilder: (_, i) {
                  final row = rows[i];
                  final cell = _alignedRow(row, left: left, isCurrent: i == current);
                  if (!row.isFold) {
                    // 双击任意一行 → 切回编辑视图并跳到这一行（对齐视图是只读的，
                    // 看到差异想改的时候不用先切模式再自己找位置）。
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: () => _editAtRow(row, left: left),
                      child: cell,
                    );
                  }
                  // 折叠摘要行：点一下就展开这一段（两侧都能点）。
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _toggleFold(row.foldFrom!),
                    child: Tooltip(
                      message: localizations.diffFoldExpandHint,
                      child: cell,
                    ),
                  );
                },
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

  void _syncFromLeft() {
    _bumpDensity();
    _syncVertical(_leftV, _rightV);
  }

  void _syncFromRight() {
    _bumpDensity();
    _syncVertical(_rightV, _leftV);
  }

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
