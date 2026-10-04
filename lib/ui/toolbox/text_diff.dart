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
import 'package:proxypin/utils/text_diff.dart';

/// 文本对比工具
/// - 左右两个 CodeForge 输入；
/// - 点对比后差异直接在原文 / 新文上染色（删行红、增行绿），无单独结果区；
/// - 用户开始编辑任一侧时清空高亮，避免行号错位误导。
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
  late final CodeForgeController _left;
  late final CodeForgeController _right;

  bool _wrap = true;
  String? _summary;

  /// 差异块（用于上一处 / 下一处导航）。每个块记录左右两侧的起始行（0-based）。
  List<_DiffHunk> _hunks = [];
  int _navIndex = -1;

  /// 上一次对比时左右文本的快照；用来判断 listener 收到的变化是不是真改了文本，
  /// 因为 CodeForgeController 的 listener 选区 / 装饰变化也会触发。
  String _leftSnapshot = '';
  String _rightSnapshot = '';

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _left = CodeForgeController()..text = widget.initialLeft ?? '';
    _right = CodeForgeController()..text = widget.initialRight ?? '';
    _left.addListener(_onLeftChanged);
    _right.addListener(_onRightChanged);

    if (Platforms.isDesktop() && widget.windowId != null) {
      HardwareKeyboard.instance.addHandler(_onKeyEvent);
    }
  }

  @override
  void dispose() {
    _left.removeListener(_onLeftChanged);
    _right.removeListener(_onRightChanged);
    _left.dispose();
    _right.dispose();
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
    Future.delayed(const Duration(milliseconds: 1500), () {
      _compare();
      textChanged = false;
    });
  }

  // ---------- 操作 ----------
  void _compare() {
    if (_left.text.isEmpty && _right.text.isEmpty) return;
    final diffs = diffLines(_left.text, _right.text);

    final addBg = Colors.green.withValues(alpha: 0.18);
    final delBg = Colors.red.withValues(alpha: 0.18);
    final modBg = Colors.orange.withValues(alpha: 0.20);
    const addColor = Colors.green;
    const delColor = Colors.red;
    const modColor = Colors.orange;

    final leftGutterDecos = <GutterDecoration>[];
    final rightGutterDecos = <GutterDecoration>[];

    // 字符级高亮要走 controller.searchHighlights：那是按全文 utf16 offset 标范围。
    // 这里先算每行起始 offset，后面把行号转成 offset。
    final leftLineStarts = _lineStartOffsets(_left.text);
    final rightLineStarts = _lineStartOffsets(_right.text);
    final leftCharHighlights = <SearchHighlight>[];
    final rightCharHighlights = <SearchHighlight>[];

    // 整行底色只给"没参与字符配对"的纯增/纯删行——
    // CodeForge 渲染顺序是 SearchHighlights 先于 LineDecorations，
    // 整行 LineDecoration 会盖掉字符高亮。所以配对行不加整行色，靠
    // gutter 色条 + 字符级 searchHighlights 即可表达差异。
    final pairedDeleteLines = <int>{}; // 0-based 左侧行号
    final pairedInsertLines = <int>{}; // 0-based 右侧行号

    var inserts = 0, deletes = 0;
    for (final d in diffs) {
      switch (d.type) {
        case LineDiffType.equal:
          break;
        case LineDiffType.delete:
          deletes++;
        case LineDiffType.insert:
          inserts++;
      }
    }

    // 第二趟：扫描"紧邻的 delete + insert"做字符级配对。
    // 新版 diffLines 用的是双指针 + 前瞻：发现错位时左 delete / 右 insert
    // 总是紧贴出现（"同行修改"或"局部增删"），所以这里只需识别相邻配对，
    // 不必再做全局匹配。
    for (var k = 0; k + 1 < diffs.length; k++) {
      final a = diffs[k];
      final b = diffs[k + 1];
      LineDiff? dl, dr;
      if (a.type == LineDiffType.delete && b.type == LineDiffType.insert) {
        dl = a;
        dr = b;
      } else if (a.type == LineDiffType.insert && b.type == LineDiffType.delete) {
        dl = b;
        dr = a;
      }
      if (dl == null || dr == null) continue;
      // 已经被前一对消费过的行就跳过
      final lLine = dl.leftLine! - 1;
      final rLine = dr.rightLine! - 1;
      if (pairedDeleteLines.contains(lLine) || pairedInsertLines.contains(rLine)) continue;

      final cd = diffChars(dl.text, dr.text);
      final lOff = leftLineStarts[lLine];
      final rOff = rightLineStarts[rLine];
      for (final r in cd.leftRanges) {
        leftCharHighlights.add(SearchHighlight(start: lOff + r.start, end: lOff + r.end));
      }
      for (final r in cd.rightRanges) {
        rightCharHighlights.add(SearchHighlight(start: rOff + r.start, end: rOff + r.end));
      }
      pairedDeleteLines.add(lLine);
      pairedInsertLines.add(rLine);
    }

    // 第三趟：所有差异行都加整行底色 + 行号色条。
    // 配对过的「删+增」视为**修改**，用橙色与纯新增（绿）/纯删除（红）区分；
    // 整行 alpha 只有 0.18~0.20，字符级 searchHighlights 用 0.85+ 的深色压在上面，
    // 叠加后差异字符仍然明显比整行其他位置深。
    final leftLineDecos = <LineDecoration>[];
    final rightLineDecos = <LineDecoration>[];
    for (final d in diffs) {
      if (d.type == LineDiffType.delete) {
        final ln = d.leftLine! - 1;
        final isMod = pairedDeleteLines.contains(ln);
        leftLineDecos.add(LineDecoration(
          id: 'del-$ln',
          startLine: ln,
          endLine: ln,
          type: LineDecorationType.background,
          color: isMod ? modBg : delBg,
        ));
        leftGutterDecos.add(GutterDecoration(
          id: 'del-g-$ln',
          startLine: ln,
          endLine: ln,
          type: GutterDecorationType.colorBar,
          color: isMod ? modColor : delColor,
        ));
      } else if (d.type == LineDiffType.insert) {
        final ln = d.rightLine! - 1;
        final isMod = pairedInsertLines.contains(ln);
        rightLineDecos.add(LineDecoration(
          id: 'ins-$ln',
          startLine: ln,
          endLine: ln,
          type: LineDecorationType.background,
          color: isMod ? modBg : addBg,
        ));
        rightGutterDecos.add(GutterDecoration(
          id: 'ins-g-$ln',
          startLine: ln,
          endLine: ln,
          type: GutterDecorationType.colorBar,
          color: isMod ? modColor : addColor,
        ));
      }
    }

    _left.clearLineDecorations();
    _left.clearGutterDecorations();
    _right.clearLineDecorations();
    _right.clearGutterDecorations();
    _left.addLineDecorations(leftLineDecos);
    _left.addGutterDecorations(leftGutterDecos);
    _right.addLineDecorations(rightLineDecos);
    _right.addGutterDecorations(rightGutterDecos);

    // searchHighlights 是个普通 List 字段，赋值后要 notify 让编辑器重绘。
    _left.searchHighlights = leftCharHighlights;
    _right.searchHighlights = rightCharHighlights;
    _left.searchHighlightsChanged = true;
    _right.searchHighlightsChanged = true;
    _left.notifyListeners();
    _right.notifyListeners();

    _leftSnapshot = _left.text;
    _rightSnapshot = _right.text;

    final modified = pairedDeleteLines.length;
    final additions = inserts - modified;
    final deletions = deletes - modified;
    final hunks = _buildHunks(diffs);

    setState(() {
      _hunks = hunks;
      _navIndex = -1;
      if (inserts == 0 && deletes == 0) {
        _summary = localizations.diffIdentical;
      } else {
        _summary = localizations.diffSummaryDetail(additions, deletions, modified);
      }
    });
  }

  /// 把连续的差异行归并成一个个"差异块"，供上一处 / 下一处导航使用。
  static List<_DiffHunk> _buildHunks(List<LineDiff> diffs) {
    final hunks = <_DiffHunk>[];
    _DiffHunk? current;
    for (final d in diffs) {
      if (d.type == LineDiffType.equal) {
        current = null;
        continue;
      }
      final l = d.type == LineDiffType.delete ? d.leftLine! - 1 : null;
      final r = d.type == LineDiffType.insert ? d.rightLine! - 1 : null;
      if (current == null) {
        current = _DiffHunk(l, r);
        hunks.add(current);
      } else {
        current.leftLine ??= l;
        current.rightLine ??= r;
      }
    }
    return hunks;
  }

  /// 跳到上一处（[delta] < 0）或下一处（[delta] > 0）差异，两侧一起滚动。
  void _navigate(int delta) {
    if (_hunks.isEmpty) return;
    var index = _navIndex;
    if (index < 0) {
      index = delta > 0 ? 0 : _hunks.length - 1;
    } else {
      index = (index + delta) % _hunks.length;
      if (index < 0) index += _hunks.length;
    }
    setState(() => _navIndex = index);

    final hunk = _hunks[index];
    if (hunk.leftLine != null) _left.scrollToLine(hunk.leftLine!);
    if (hunk.rightLine != null) _right.scrollToLine(hunk.rightLine!);
  }

  /// 用左侧内容整体覆盖右侧。
  void _applyLeftToRight() {
    if (_left.text == _right.text) return;
    _right.text = _left.text;
    _compare();
  }

  /// 用右侧内容整体覆盖左侧。
  void _applyRightToLeft() {
    if (_left.text == _right.text) return;
    _left.text = _right.text;
    _compare();
  }

  /// 累计 \n 偏移得到每行起始处的全文 utf16 offset。下标 0-based。
  static List<int> _lineStartOffsets(String text) {
    final offsets = <int>[0];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) offsets.add(i + 1);
    }
    return offsets;
  }

  /// 清掉两侧高亮，但保留文本内容。
  void _clearHighlights() {
    if (_summary == null) return;
    // 必须先翻成 false：clearLineDecorations / searchHighlights 赋值都会触发
    // controller.notifyListeners → _onLeftChanged/_onRightChanged 重入，

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
      _hunks = [];
      _navIndex = -1;
    });
  }

  void _clearAll() {
    if (_left.text.isEmpty && _right.text.isEmpty) return;
    _left.text = '';
    _right.text = '';
    _clearHighlights();
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

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    bool isNewWindows = widget.windowId != null && Platform.isWindows;

    return Scaffold(
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
        Row(children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _legend(),
            ),
          ),
          _toolbar(),
        ]),
        const Divider(height: 1, thickness: 0.3),
        Expanded(
          child: LayoutBuilder(
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
              if (_hunks.isNotEmpty && _navIndex >= 0)
                Text(
                  localizations.diffPosition(_navIndex + 1, _hunks.length),
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary),
                ),
            ]),
          ),
      ]),
    );
  }

  /// 左上角图例：说明三种差异配色。
  Widget _legend() {
    Widget item(Color c, String label) {
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, color: c.withValues(alpha: 0.55)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(children: [
        item(Colors.green, localizations.diffAdded),
        item(Colors.orange, localizations.diffModified),
        item(Colors.red, localizations.diffDeleted),
      ]),
    );
  }

  Widget _toolbar() {
    final color = Theme.of(context).colorScheme.primary;
    final hasDiff = _hunks.isNotEmpty;
    return Container(
      padding: const EdgeInsets.only(top: 2, bottom: 2, right: 12),
      child: Wrap(
        spacing: 0,
        runSpacing: 0,
        children: [
          _iconBtn(Icons.keyboard_arrow_up, localizations.diffPrev, hasDiff ? () => _navigate(-1) : null),
          _iconBtn(Icons.keyboard_arrow_down, localizations.diffNext, hasDiff ? () => _navigate(1) : null),
          _iconBtn(Icons.arrow_forward, localizations.diffReplaceLeftToRight, _applyLeftToRight),
          _iconBtn(Icons.arrow_back, localizations.diffReplaceRightToLeft, _applyRightToLeft),
          _iconBtn(Icons.compare_arrows, localizations.compare, _onTextChange),
          _iconBtn(Icons.delete_outline, localizations.clear, _clearAll),
          _iconBtn(
            Icons.wrap_text,
            localizations.wordWrap,
            () => setState(() => _wrap = !_wrap),
            tint: _wrap ? color : null,
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

    // 字符级差异：左边删除（深红底），右边新增（深绿底）。
    // 用接近不透明的 alpha：CodeForge 渲染顺序是 SearchHighlight 在 LineDecoration
    // 之前，整行浅底色会盖在它上面（alpha blend），所以这里调到 0xCC 才能在
    // 整行 0x2E 的浅红/浅绿之上保持可辨识对比。
    final charStyle = isLeft
        ? const TextStyle(backgroundColor: Color(0xCCE53935)) // 深红
        : const TextStyle(backgroundColor: Color(0xCC43A047)); // 深绿
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
          child: CodeForge(
            // CodeForge 的 lineWrap 是 late final，切换得新 key 重建；
            // controller 在 State 持有，重建不丢文本与撤销栈。
            key: ValueKey('diff-$title-$_wrap'),
            controller: controller,
            lineWrap: _wrap,
            enableGuideLines: false,
            editorTheme: editorTheme,
            textStyle: const TextStyle(fontSize: 14.5),
            matchHighlightStyle: matchStyle,
            finderBuilder: (c, controller) => FindPanelView(controller: controller),
            selectionStyle: CodeSelectionStyle(cursorColor: Theme.of(context).colorScheme.primary),
          ),
        ),
      ),
    ]);
  }
}

/// 一段连续的差异（可能同时含删除与新增），用于上一处 / 下一处导航。
class _DiffHunk {
  int? leftLine;
  int? rightLine;

  _DiffHunk(this.leftLine, this.rightLine);
}
