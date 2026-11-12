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

import 'package:xml/xml.dart' as xml;
import 'dart:io';
import 'dart:typed_data';

import 'package:code_forge/code_forge.dart';
import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:proxypin/ui/component/search/highlight_text_document.dart'
    show
        HighlightStyledSegment,
        buildHighlightBaseSegments,
        buildHighlightDocumentLines;
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
import 'package:proxypin/ui/toolbox/text_editor.dart' show TextEditorPage;
import 'package:proxypin/ui/component/snippet_bar.dart';
import 'package:proxypin/ui/toolbox/dir_diff_page.dart';
import 'package:proxypin/ui/toolbox/hex_diff_page.dart';
import 'package:proxypin/ui/toolbox/image_diff_page.dart';
import 'package:proxypin/ui/toolbox/table_diff_page.dart';
import 'package:proxypin/ui/toolbox/three_way_merge.dart';
import 'package:proxypin/ui/toolbox/workspace_tree.dart';
import 'package:proxypin/utils/text_diff.dart';
import 'package:proxypin/utils/text_editor_prefs.dart' show kTextEditorWorkspaceKey;
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

  /// 是否把内容写进「上次对比」（默认是）。从别处临时比较一段选区时传 false，
  /// 否则退出后用户原来的对比内容会被这段选区顶掉。
  final bool persist;

  /// 两侧的名字（显示在标题栏「原文件 · xxx」处）。目录对比点开某一条时传相对路径，
  /// 否则两边都只显示「原文件 / 新文件」，看不出在比哪个文件。
  final String? initialLeftName;
  final String? initialRightName;

  const TextDiffPage({
    super.key,
    this.windowId,
    this.initialLeft,
    this.initialRight,
    this.persist = true,
    this.initialLeftName,
    this.initialRightName,
  });

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

  /// 自动换行：手机上长行不换行就只能一直往右滑，很费劲。
  static const String _wrapKey = 'text_diff_wrap_v1';
  bool _sideBySide = true;

  late final CodeForgeController _left;
  late final CodeForgeController _right;
  late final UndoRedoController _leftUndo;
  late final UndoRedoController _rightUndo;
  late final FindController _findLeft;
  late final FindController _findRight;

  /// 自动换行：手机上长行不换行就只能一直往右滑，很费劲。
  /// 编辑视图（CodeForge 的 lineWrap）和对比视图共用这一个开关。
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

  /// 「差异列表」里已看过的块下标（只为 review 进度，不持久化）。
  final Set<int> _reviewed = {};
  static const String _alignedKey = 'text_diff_aligned_v1';

  /// 并排视图里左右两栏的宽度比例（0.15 ~ 0.85）：拖中间那条分隔线改。
  /// 手机上两栏等宽时，一边长行一边短行很常见，能拖一下就好读多了。
  double _splitRatio = 0.5;
  static const String _splitKey = 'text_diff_split_v1';

  /// 忽略空白行：一边多几个空行不算差异（Beyond Compare 的同名选项）。
  bool _ignoreBlank = false;

  /// 忽略注释：`//` `*` `#` 开头的行当作空行，行尾 ` //` 之后丢掉。
  bool _ignoreComments = false;

  /// 按行号对齐（Beyond Compare 的 Alignment → 按位置）：
  /// 不做内容匹配，左边第 i 行直接对右边第 i 行。改配置、改一列数值这类
  /// 「结构没动」的对比用它更好读 —— 内容对齐会因为插了一行而把下面整段挪位。
  bool _alignByLine = false;

  /// 手动标记的差异块下标（WinMerge / Beyond Compare 的「书签」）：
  /// 一次对比几十处差异时，先把要处理的几处标上，之后只在它们之间跳，
  /// 不用一路「下一处」翻过去。
  final Set<int> _marks = <int>{};

  /// 「忽略匹配某正则的行」——日志/抓包对比时最常见（时间戳、请求 id 每行都不同）。
  String _ignoreLineText = '';
  RegExp? _ignoreLineRe;

  /// 两栏的文件名（打开文件后显示在顶部标签里：「原文件 · xxx.txt」）。
  String _leftName = '';
  String _rightName = '';

  /// 两侧文件的完整路径（只有「从文件打开」的那侧有）。重新加载要用。
  String _leftPath = '';
  String _rightPath = '';

  /// 显示字号（底部 +/- 调节）。
  double _fontSize = 13.5;

  /// 对齐视图里的查找（vs 编辑视图的 FindPanelView：那个只能搜编辑器里的文本，
  /// 对齐视图是只读渲染，得自己实现一份）。
  bool _findOpen = false;
  final TextEditingController _findInput = TextEditingController();
  String _findQuery = '';
  bool _findCase = false;

  /// 当前命中在 [_findHitsCache] 里的下标。
  int _findCursor = 0;
  List<({bool left, int row})> _findHitsCache = const <({bool left, int row})>[];
  int? _findCurrentRow;
  String _findHitsKey = '';

  /// Tab 展开成几个空格（0 = 不展开，按原样显示）。
  ///
  /// 对比两份缩进风格不同的文件时，`\t` 和空格混用会让两边怎么都对不齐；
  /// 展开之后至少视觉上能对齐，也顺便看出「Tab 占了几列」。
  int _tabWidth = 0;
  static const String _tabWidthKey = 'text_diff_tab_width_v1';

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

  /// 「合并结果」的策略：0=全部用右侧，1=全部用左侧，2=逐块选择。
  int _mergeStrategy = 0;

  /// 逐块选择：块下标 → true 用右侧 / false 用左侧（缺省用右侧）。
  final Map<int, bool> _mergeChoice = {};

  /// 同步横向滚动：一栏往右看长行时另一栏跟着走（默认关，两栏独立更常用）。
  bool _syncH = false;
  bool _syncingH = false;

  /// 同步纵向滚动：并排看代码时一栏滚动另一栏跟着走（默认开）。
  /// 关掉后两栏各自独立——只想翻左边、右边停住对照时用。
  bool _syncV = true;

  /// 磁盘上的文件在别处被改过（mtime 变了）→ 顶部提示条。
  /// 不做的话，用户在编辑器里改完切回来，看到的还是打开那一刻的旧内容，
  /// 却以为是「现在磁盘上的样子」，据此下结论。
  bool _staleDisk = false;
  int _leftMtime = 0;
  int _rightMtime = 0;
  Timer? _staleTimer;

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

  /// 把空格显示成 `·`、Tab 显示成 `→`（仅对齐视图/只读预览）。
  /// 「看起来一模一样却标了修改」基本都是尾随空格或 Tab/空格混用，肉眼看不出来。
  bool _showSpace = false;

  /// 对齐视图的语法高亮：代码 diff 全是黑字时，几乎看不出结构（Beyond Compare /
  /// VS Code 的 diff 都带高亮）。按行缓存 token 样式，只在文本/语言/主题变化时重算。
  bool _syntax = true;
  List<List<HighlightStyledSegment>>? _leftTokens;
  List<List<HighlightStyledSegment>>? _rightTokens;
  String _tokenKey = '';

  /// 词级（字符级）高亮：关掉只看整行，几万行的超大文件更顺。
  bool _wordDiff = true;

  /// 统一视图（单栏）：像 git / GitHub 的 unified diff，窄屏上比两栏好读。
  bool _unified = false;

  /// 忽略行尾空白：只抹掉每行末尾的空格/Tab，行内差异仍然比。
  /// （「忽略空白」是全量抹空白，适合格式化后的对比；这个是更精准的那一档。）
  bool _ignoreTrailing = false;

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
    _leftName = widget.initialLeftName ?? '';
    _rightName = widget.initialRightName ?? '';
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
    // 每 3 秒看一眼两侧文件的修改时间（纯 stat，代价可忽略）。
    _staleTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkDiskChanged());
    // 横向同步：常驻监听，开关关闭时 `_syncHorizontal` 第一行就返回。
    _leftH.addListener(() => _syncHorizontal(_leftH, _rightH));
    _rightH.addListener(() => _syncHorizontal(_rightH, _leftH));
    unawaited(SharedPreferencesAsync().getBool(_wrapKey).then((v) {
      if (!mounted || v == null || v == _wrap) return;
      setState(() => _wrap = v);
    }).catchError((_) => null));
    unawaited(SharedPreferencesAsync().getDouble(_fontKey).then((v) {
      if (!mounted || v == null || v == _fontSize) return;
      setState(() => _fontSize = v.clamp(11.0, 22.0));
    }).catchError((_) => null));
    unawaited(SharedPreferencesAsync().getInt(_tabWidthKey).then((v) {
      if (!mounted || v == null || v == _tabWidth) return;
      setState(() {
        _tabWidth = v.clamp(0, 8);
        _findHitsKey = '';
      });
    }).catchError((_) => null));
    unawaited(SharedPreferencesAsync().getBool(_sideKey).then((v) {
      if (!mounted || v == null || v == _sideBySide) return;
      setState(() => _sideBySide = v);
    }).catchError((_) => null));
    unawaited(SharedPreferencesAsync().getBool(_alignedKey).then((v) {
      if (!mounted || v == null || v == _aligned) return;
      setState(() => _aligned = v);
    }).catchError((_) => null));
    unawaited(SharedPreferencesAsync().getDouble(_splitKey).then((v) {
      if (!mounted || v == null || v == _splitRatio) return;
      setState(() => _splitRatio = v.clamp(0.15, 0.85));
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
    _staleTimer?.cancel();
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
    _findInput.dispose();
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
    if (!widget.persist) return;
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
      // 路径也一起恢复：不恢复的话，下次进来「保存右侧 / 写回右侧文件 / 从磁盘重读」
      // 全部失效（路径是空的），只能重新选一遍文件。
      _leftPath = (m['leftPath'] as String?) ?? '';
      _rightPath = (m['rightPath'] as String?) ?? '';
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
    if (!widget.persist) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
          _storeKey,
          jsonEncode({
            'left': _left.text,
            'right': _right.text,
            'leftName': _leftName,
            'rightName': _rightName,
            'leftPath': _leftPath,
            'rightPath': _rightPath,
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
    // 比较内容变了，上一轮的「已看」标记就不再有意义
    _reviewed.clear();
    // 块下标是按上一版内容算的，内容一变就会指到别的块上，一起清掉。
    _marks.clear();
    _charDiffCache.clear();
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

    final diffs = _alignByLine
        ? diffLinesByPosition(_left.text, _right.text,
            ignoreCase: _ignoreCase,
            ignoreWhitespace: _ignoreWhitespace,
            ignoreTrailingWhitespace: _ignoreTrailing,
            ignoreBlankLines: _ignoreBlank,
            ignoreComments: _ignoreComments,
            ignoreLinePattern: _ignoreLineRe)
        : diffLines(_left.text, _right.text,
            ignoreCase: _ignoreCase,
            ignoreWhitespace: _ignoreWhitespace,
            ignoreTrailingWhitespace: _ignoreTrailing,
            ignoreBlankLines: _ignoreBlank,
            ignoreComments: _ignoreComments,
            ignoreLinePattern: _ignoreLineRe);
    final blocks = buildDiffBlocks(diffs,
        ignoreCase: _ignoreCase,
        ignoreWhitespace: _ignoreWhitespace,
        ignoreTrailingWhitespace: _ignoreTrailing,
        ignoreBlankLines: _ignoreBlank,
        ignoreComments: _ignoreComments);
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

      // 配对行做字符级高亮（词级开关关掉时只保留整行底色）。
      if (!_wordDiff) continue;
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
    // 聚焦模式下「上一处/下一处」直接切到那一块（_jumpToBlock 里统一处理）。
    _jumpToBlock(index);
  }

  /// 跳到第 [i] 块：两侧编辑器定位 + 对齐视图滚动。
  ///
  /// 「上一处/下一处」「差异列表点击」「跳到下一处未看」三处共用一份实现，
  /// 免得改了一处忘另一处（之前就有过只改了导航、忘了列表点击）。
  /// 标记 / 取消标记当前差异块。
  void _toggleMark() {
    final i = _navIndex;
    if (i < 0 || i >= _blocks.length) {
      _toastText(localizations.diffMarkNeedBlock);
      return;
    }
    setState(() {
      if (!_marks.add(i)) _marks.remove(i);
    });
  }

  /// 在已标记的块之间跳转（[delta] > 0 向后，< 0 向前，两端环绕）。
  void _gotoMark(int delta) {
    if (_marks.isEmpty) {
      _toastText(localizations.diffMarkEmpty);
      return;
    }
    final sorted = _marks.toList()..sort();
    int target;
    if (_navIndex < 0) {
      target = delta > 0 ? sorted.first : sorted.last;
    } else if (delta > 0) {
      target = sorted.firstWhere((e) => e > _navIndex, orElse: () => sorted.first);
    } else {
      target = sorted.lastWhere((e) => e < _navIndex, orElse: () => sorted.last);
    }
    _jumpToBlock(target);
  }

  void _jumpToBlock(int i) {
    if (i < 0 || i >= _blocks.length) return;
    final b = _blocks[i];
    setState(() {
      _navIndex = i;
      if (_focusBlock != null) _focusBlock = i;
    });
    _gotoLine(_left, b.leftStart);
    _gotoLine(_right, b.rightStart);
    _scrollToCurrentRow();
  }

  /// 从当前位置往后找第一块「还没勾已看」的，找不到返回 -1。
  int _firstUnreviewed() {
    if (_blocks.isEmpty) return -1;
    for (var k = 1; k <= _blocks.length; k++) {
      final i = (_navIndex + k) % _blocks.length;
      if (!_reviewed.contains(i)) return i;
    }
    return -1;
  }

  /// 对齐视图里滚到当前差异（留一行上下文）。两侧联动，动左边就会带动右边。
  void _scrollToCurrentRow() {
    if (!_aligned || !_leftV.hasClients) return;
    var rows = _visibleRows(_alignedRows());
    var i = _currentRowIndex(rows);
    if (i < 0 && _navIndex >= 0 && _navIndex < _blocks.length) {
      // 目标行落在「折叠未变区域」里：摘要行吃掉了那几行，于是按行号找不到，
      // 表现为「上一处/下一处按下去了但屏幕没动」。把覆盖它的那一段展开再定位。
      final b = _blocks[_navIndex];
      final fold =
          _foldStartCovering(_alignedRows(), b.leftStart + 1, b.rightStart + 1);
      if (fold != null && !_expandedFolds.contains(fold)) {
        setState(() => _expandedFolds.add(fold));
        rows = _visibleRows(_alignedRows());
        i = _currentRowIndex(rows);
      }
    }
    if (i < 0) return;
    final target = (i * _rowHeight - _rowHeight).clamp(0.0, _leftV.position.maxScrollExtent);
    _leftV.animateTo(target, duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
  }

  /// [rows] 是**未折叠**的对齐行表。返回「覆盖这一行、且确实会被折叠成摘要」的那一段
  /// 的起点下标（`_expandedFolds` 里的值），找不到返回 null。
  ///
  /// `foldUnchangedRuns` 只折叠**连续 equal 且长度 > 6** 的段落，这里保持同一判据，
  /// 否则会去展开一个本来就没折叠的位置（白 setState 一次）。
  int? _foldStartCovering(List<DiffRow> rows, int wantLeft, int wantRight) {
    var i = 0;
    while (i < rows.length) {
      if (rows[i].type != DiffRowType.equal) {
        i++;
        continue;
      }
      var j = i;
      while (j < rows.length && rows[j].type == DiffRowType.equal) {
        j++;
      }
      if (j - i > 6) {
        for (var k = i; k < j; k++) {
          if (rows[k].leftLine == wantLeft || rows[k].rightLine == wantRight) {
            return i;
          }
        }
      }
      i = j;
    }
    return null;
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
    _leftPath = '';
    _rightPath = '';
    _leftMtime = 0;
    _rightMtime = 0;
    _staleDisk = false;
    _leftUndo.clear();
    _rightUndo.clear();
    _clearHighlights();
    _schedulePersist();
  }

  /// 读 [path] 到 [target] 那一侧（系统选择器和工作区文件树都走这里）。
  Future<void> _loadPathInto(String path, CodeForgeController target) async {
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
          _leftPath = path;
        } else {
          _rightName = name;
          _rightPath = path;
        }
      });
      _markDiskBaseline();
      // 超过 8MB 只读了前 8MB：不提示的话，用户会拿着「后半段都一样」的结论做决定。
      if (content.truncated) _toast(localizations.diffFileTruncated);
    } catch (e) {
      _toast('${localizations.fail}: $e');
    }
  }

  /// 设过工作区时先问「从工作区点还是用系统选择器」。
  ///
  /// 对比的两份文件常常都在同一个项目里（改前/改后、两个模块的同名文件），
  /// 这时从目录树点两下就到位；而系统选择器每次都要从根目录重新翻。
  Future<String?> _workspaceRoot() async {
    try {
      final v = await SharedPreferencesAsync().getString(kTextEditorWorkspaceKey);
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openFileInto(CodeForgeController target) async {
    final ws = await _workspaceRoot();
    if (ws != null && mounted) {
      final how = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: Text(localizations.editorWorkspaceTree),
              subtitle: Text(ws, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(ctx, 'ws'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: Text(localizations.selectFile),
              onTap: () => Navigator.pop(ctx, 'picker'),
            ),
          ]),
        ),
      );
      if (!mounted || how == null) return;
      if (how == 'ws') {
        await WorkspaceTreeSheet.show(context,
            root: ws, onOpenFile: (p) => unawaited(_loadPathInto(p, target)));
        return;
      }
    }

    String? path;
    try {
      final picked = await FilePicker.pickFile(type: FileType.any);
      path = picked?.path;
    } catch (_) {
      final picked = await FilePicker.pickFile();
      path = picked?.path;
    }
    if (path == null) return;
    await _loadPathInto(path, target);
  }

  /// 从磁盘重新读两侧（文件在编辑器/别的工具里改过之后，回到这里刷新）。
  Future<void> _reloadFromDisk() async {
    if (_leftPath.isEmpty && _rightPath.isEmpty) {
      _toastText(localizations.diffNoFileToReload);
      return;
    }
    var n = 0;
    for (final isLeft in [true, false]) {
      final path = isLeft ? _leftPath : _rightPath;
      if (path.isEmpty) continue;
      try {
        final content = await readTextFileLenient(File(path));
        if (!mounted) return;
        (isLeft ? _left : _right).text = content.text;
        n++;
      } catch (e) {
        if (!mounted) return;
        _toast('${localizations.fail}: $e');
      }
    }
    if (!mounted) return;
    setState(() => _navIndex = -1);
    _markDiskBaseline();
    _compare();
    _toastText(localizations.diffReloaded(n));
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
    // 命中的行要跟着「忽略开关 / 只显示差异 / 聚焦块」一起变，统一在 build
    // 开头刷一次（带 key，没变就不重算）。
    _refreshFindHits();
    _ensureTokens();

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
          if (_staleDisk) _staleBar(),
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
          if (_findOpen) _findBar(),
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

  /// 让两侧的 token 样式与当前内容对齐（文本/语言/主题/开关变了才重算）。
  void _ensureTokens() {
    final lang = _diffLang;
    final key = '${lang ?? ''}|${_left.text.length}|${_left.text.hashCode}'
        '|${_right.text.length}|${_right.text.hashCode}'
        '|${Theme.brightnessOf(context).name}|$_syntax';
    if (key == _tokenKey) return;
    _tokenKey = key;
    if (!_syntax || lang == null) {
      _leftTokens = null;
      _rightTokens = null;
      return;
    }
    _leftTokens = _tokenizeFor(_left.text, lang);
    _rightTokens = _tokenizeFor(_right.text, lang);
  }

  List<List<HighlightStyledSegment>>? _tokenizeFor(String text, String lang) {
    if (text.isEmpty) return const <List<HighlightStyledSegment>>[];
    // 解析是同步的，几百 KB 上会明显卡一帧；几万行的 diff 本来就该关高亮看。
    if (text.length > 300000) return null;
    try {
      final segments =
          buildHighlightBaseSegments(context, text, language: lang);
      return buildHighlightDocumentLines(segments)
          .map((line) => line.segments)
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  /// 语法高亮实际是否生效。
  ///
  /// Tab 展开与空白可视化会改写"显示用的文本"，token 就对不上了，所以那时让位；
  /// 查找高亮同理（同一段文本只能有一种底色）。
  bool get _syntaxActive {
    if (!_syntax || _tabWidth > 0 || _showSpace || _findQuery.isNotEmpty) {
      return false;
    }
    final left = _leftTokens;
    final right = _rightTokens;
    return (left != null && left.isNotEmpty) ||
        (right != null && right.isNotEmpty);
  }

  /// 对比的语言：按文件名后缀推（两侧都没有文件名时不高亮）。
  String? get _diffLang {
    final name = _leftName.isNotEmpty ? _leftName : _rightName;
    if (name.isEmpty) return null;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return null;
    return _langOfExt(name.substring(dot + 1).toLowerCase());
  }

  static String? _langOfExt(String ext) => switch (ext) {
        'dart' => 'dart',
        'js' || 'mjs' || 'cjs' || 'jsx' => 'javascript',
        'ts' || 'tsx' => 'typescript',
        'json' => 'json',
        'xml' || 'svg' || 'html' || 'htm' || 'vue' => 'xml',
        'css' => 'css',
        'scss' => 'scss',
        'less' => 'less',
        'yaml' || 'yml' => 'yaml',
        'md' || 'markdown' => 'markdown',
        'sql' => 'sql',
        'py' => 'python',
        'java' => 'java',
        'kt' || 'kts' => 'kotlin',
        'go' => 'go',
        'rs' => 'rust',
        'c' || 'h' => 'c',
        'cpp' || 'cc' || 'cxx' || 'hpp' => 'cpp',
        'cs' => 'csharp',
        'php' => 'php',
        'rb' => 'ruby',
        'swift' => 'swift',
        'sh' || 'bash' || 'zsh' => 'bash',
        'ini' || 'conf' || 'toml' || 'properties' => 'ini',
        'lua' => 'lua',
        'gradle' || 'groovy' => 'groovy',
        _ => null,
      };

  /// 把一行的 token 段拼成 span（底色已经剥掉了，不会盖住 diff 的绿/红）。
  TextSpan _tokenSpan(List<HighlightStyledSegment> segments, TextStyle base) {
    if (segments.isEmpty) return TextSpan(text: '', style: base);
    return TextSpan(style: base, children: [
      for (final seg in segments)
        TextSpan(
          text: seg.text,
          style: seg.style == null
              ? null
              : base.merge(seg.style).copyWith(backgroundColor: null),
        ),
    ]);
  }

  /// 配对行的字符级差异（相对**原始行文本**的偏移）。
  ///
  /// 并排视图以前只有整行底色：一眼看得出「这行改了」，但看不出「改的是哪几个词」。
  /// WinMerge / Beyond Compare / VS Code 都会在配对行里标出具体改动，这里补上。
  /// 单行 LCS 是 O(m·n)，超过 3000 字符直接放弃（整行底色仍在）。
  final Map<String, CharDiff> _charDiffCache = {};

  CharDiff? _charDiffOf(String l, String r) {
    if (l == r) return null;
    if (l.length > 3000 || r.length > 3000) return null;
    final key = '${l.hashCode}:${r.hashCode}:${l.length}:${r.length}';
    final hit = _charDiffCache[key];
    if (hit != null) return hit;
    final cd = diffChars(l, r);
    if (_charDiffCache.length > 800) _charDiffCache.clear();
    _charDiffCache[key] = cd;
    return cd;
  }

  /// 纯文本行：把差异区间涂上底色。
  TextSpan _spansWithBg(String text, TextStyle style,
      List<({int start, int end})> ranges, Color? bg) {
    if (ranges.isEmpty || bg == null) return TextSpan(text: text, style: style);
    final children = <TextSpan>[];
    var cursor = 0;
    for (final r in ranges) {
      final s = r.start.clamp(0, text.length);
      final e = r.end.clamp(0, text.length);
      if (e <= s) continue;
      if (s > cursor) {
        children.add(TextSpan(text: text.substring(cursor, s), style: style));
      }
      children.add(TextSpan(
          text: text.substring(s, e),
          style: style.copyWith(backgroundColor: bg)));
      cursor = e;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor), style: style));
    }
    return TextSpan(style: style, children: children);
  }

  /// 语法高亮行：在 token 前景色之上再叠字符差异底色。
  ///
  /// 实现是把每个 token 按差异区间切开——差异通常是「几个词」，切开后段数很少；
  /// 没有差异时直接走原来的 [_tokenSpan]，不产生额外开销。
  TextSpan _tokenSpanWithDiff(List<HighlightStyledSegment> segments, TextStyle base,
      List<({int start, int end})> ranges, Color? bg) {
    if (ranges.isEmpty || bg == null) return _tokenSpan(segments, base);
    if (segments.isEmpty) return TextSpan(text: '', style: base);
    final children = <TextSpan>[];
    var pos = 0;
    for (final seg in segments) {
      final len = seg.text.length;
      if (len == 0) continue;
      final segStart = pos;
      final segEnd = pos + len;
      pos = segEnd;
      final style = seg.style == null
          ? null
          : base.merge(seg.style).copyWith(backgroundColor: null);
      var cursor = segStart;
      for (final r in ranges) {
        if (r.end <= segStart) continue;
        if (r.start >= segEnd) break;
        final a = r.start.clamp(segStart, segEnd);
        final b = r.end.clamp(segStart, segEnd);
        if (a > cursor) {
          children.add(TextSpan(
              text: seg.text.substring(cursor - segStart, a - segStart), style: style));
        }
        if (b > a) {
          children.add(TextSpan(
              text: seg.text.substring(a - segStart, b - segStart),
              style: (style ?? base).copyWith(backgroundColor: bg)));
        }
        cursor = b;
      }
      if (cursor < segEnd) {
        children.add(TextSpan(text: seg.text.substring(cursor - segStart), style: style));
      }
    }
    return TextSpan(style: base, children: children);
  }

  /// 命中缓存：文本 / 开关 / 显示范围任何一项变了才重算。
  void _refreshFindHits() {
    // 没在查找时直接返回：`_visibleRows` 每次都会新建一张列表，放在 build 里
    // 无脑调用的话，几万行的对比每帧都要多走一遍（滚动也跟着变卡）。
    if (_findQuery.isEmpty) {
      if (_findHitsKey.isNotEmpty) {
        _findHitsKey = '';
        _findHitsCache = const <({bool left, int row})>[];
        _findCurrentRow = null;
        _findCursor = 0;
      }
      return;
    }
    final rows = _visibleRows(_alignedRows());
    final key = '$_findQuery|$_findCase|$_alignedRowsKey|${rows.length}'
        '|$_onlyDiff|$_focusBlock|$_typeFilter|$_wrap';
    if (key == _findHitsKey) return;
    _findHitsKey = key;
    final hits = <({bool left, int row})>[];
    final needle = _findCase ? _findQuery : _findQuery.toLowerCase();
    for (var i = 0; i < rows.length; i++) {
      final l = rows[i].leftText;
      if (l != null && l.isNotEmpty) {
        final hay = _findCase ? l : l.toLowerCase();
        if (hay.contains(needle)) {
          hits.add((left: true, row: i));
        }
      }
      final r = rows[i].rightText;
      if (r != null && r.isNotEmpty) {
        final hay = _findCase ? r : r.toLowerCase();
        if (hay.contains(needle)) {
          hits.add((left: false, row: i));
        }
      }
    }
    _findHitsCache = hits;
    if (_findCursor >= hits.length) _findCursor = hits.isEmpty ? 0 : hits.length - 1;
    _findCurrentRow = hits.isEmpty ? null : hits[_findCursor].row;
  }

  /// 上一处 / 下一处。
  void _findGo(int delta) {
    final hits = _findHitsCache;
    if (hits.isEmpty) {
      _toastText(localizations.diffFindNoMatch);
      return;
    }
    var next = _findCursor + delta;
    if (next < 0) next = hits.length - 1;
    if (next >= hits.length) next = 0;
    setState(() {
      _findCursor = next;
      _findCurrentRow = hits[next].row;
    });
    _scrollToRowIndex(hits[next].row);
  }

  void _closeFind() {
    setState(() {
      _findOpen = false;
      _findQuery = '';
      _findInput.clear();
      _findCurrentRow = null;
      _findHitsCache = const <({bool left, int row})>[];
      _findHitsKey = '';
    });
  }

  /// 对齐视图的查找条（编辑视图仍然用内核的 FindPanelView）。
  Widget _findBar() {
    final theme = Theme.of(context);
    final total = _findHitsCache.length;
    final pos = total == 0 ? 0 : _findCursor.clamp(0, total - 1) + 1;
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
            top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4))),
      ),
      child: Row(children: [
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _findInput,
            autofocus: true,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: localizations.diffFindInDiff,
              hintStyle: const TextStyle(fontSize: 13),
            ),
            onChanged: (v) {
              setState(() {
                _findQuery = v;
                _findCursor = 0;
                _findHitsKey = '';
              });
              _refreshFindHits();
              if (_findHitsCache.isNotEmpty) {
                _scrollToRowIndex(_findHitsCache.first.row);
              }
            },
            onSubmitted: (_) => _findGo(1),
          ),
        ),
        Text(total == 0 ? (localizations.diffFindNoMatch) : '$pos/$total',
            style: TextStyle(
                fontSize: 11,
                color: total == 0
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary)),
        IconButton(
          tooltip: localizations.diffMatchCase,
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.text_fields,
              size: 16,
              color: _findCase ? theme.colorScheme.primary : null),
          onPressed: () {
            setState(() {
              _findCase = !_findCase;
              _findCursor = 0;
              _findHitsKey = '';
            });
            _refreshFindHits();
          },
        ),
        IconButton(
          tooltip: localizations.diffPrev,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.keyboard_arrow_up, size: 18),
          onPressed: total == 0 ? null : () => _findGo(-1),
        ),
        IconButton(
          tooltip: localizations.diffNext,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.keyboard_arrow_down, size: 18),
          onPressed: total == 0 ? null : () => _findGo(1),
        ),
        IconButton(
          tooltip: localizations.cancel,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, size: 17),
          onPressed: _closeFind,
        ),
      ]),
    );
  }

  /// 工具栏的搜索按钮：对齐视图走自建查找条，编辑视图走内核的查找面板。
  void _onSearchButton() {
    final showingAligned =
        _aligned || !(_left.text.isEmpty && _right.text.isEmpty);
    if (!showingAligned) {
      _toggleFind(_leftActive ? _findLeft : _findRight);
      return;
    }
    setState(() => _findOpen = !_findOpen);
    if (!_findOpen) _closeFind();
  }

  /// 对齐视图 ↔ 编辑视图，并把选择记住。
  void _toggleAligned() {
    final next = !_aligned;
    setState(() => _aligned = next);
    unawaited(SharedPreferencesAsync().setBool(_alignedKey, next));
  }

  void _setTabWidth(int width) {
    setState(() {
      _tabWidth = width;
      _findHitsKey = '';
    });
    unawaited(SharedPreferencesAsync().setInt(_tabWidthKey, width));
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
    final lp = _leftPath;
    _leftPath = _rightPath;
    _rightPath = lp;
    final lm = _leftMtime;
    _leftMtime = _rightMtime;
    _rightMtime = lm;
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
          case 'ignoreTrailing':
            setState(() => _ignoreTrailing = !_ignoreTrailing);
            _compare();
          case 'ignoreBlank':
            setState(() => _ignoreBlank = !_ignoreBlank);
            _compare();
          case 'tabKeep':
            _setTabWidth(0);
          case 'tab2':
            _setTabWidth(2);
          case 'tab4':
            _setTabWidth(4);
          case 'tab8':
            _setTabWidth(8);
          case 'ignoreComment':
            setState(() => _ignoreComments = !_ignoreComments);
            _compare();
          case 'ignoreLines':
            unawaited(_showIgnoreLineDialog());
          case 'syntax':
            setState(() => _syntax = !_syntax);
          case 'wrap':
            final next = !_wrap;
            setState(() => _wrap = next);
            unawaited(SharedPreferencesAsync().setBool(_wrapKey, next));
          case 'onlyDiff':
            setState(() => _onlyDiff = !_onlyDiff);
          case 'syncV':
            setState(() => _syncV = !_syncV);
            if (_syncV) _syncVertical(_leftV, _rightV);
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
            unawaited(_showDiffStats());
          case 'filterAdd':
            setState(() => _typeFilter = _typeFilter == 'added' ? null : 'added');
          case 'filterDel':
            setState(() => _typeFilter = _typeFilter == 'deleted' ? null : 'deleted');
          case 'filterMod':
            setState(() => _typeFilter = _typeFilter == 'modified' ? null : 'modified');
          case 'exportHtml':
            unawaited(_exportHtmlReport());
          case 'exportPatch':
            unawaited(_exportPatch());
          case 'copyPatch':
            unawaited(_copyUnifiedDiff());
          case 'normalize':
            unawaited(_normalizeBoth());
          case 'editInEditorLeft':
            _openInEditor(true);
          case 'editInEditorRight':
            _openInEditor(false);
          case 'shareDiff':
            unawaited(_shareDiff());
          case 'reloadFiles':
            unawaited(_reloadFromDisk());
          case 'exportCsv':
            unawaited(_exportCsv());
          case 'history':
            unawaited(_showDiffHistory());
          case 'diffList':
            _showDiffList();
          case 'hexDiff':
            unawaited(Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HexDiffPage())));
          case 'imageDiff':
            unawaited(ImageDiffPage.show(context));
          case 'baselineSave':
            unawaited(_saveBaseline());
          case 'baselineCompare':
            unawaited(_compareWithBaseline());
          case 'baselineClear':
            unawaited(_clearBaseline());
          case 'tableCompare':
            unawaited(TableDiffPage.show(
              context,
              left: _left.text,
              right: _right.text,
              leftName: _leftName,
              rightName: _rightName,
            ));
          case 'alignByLine':
            setState(() {
              _alignByLine = !_alignByLine;
              _expandedFolds.clear();
            });
            _compare();
          case 'foldUnchanged':
            setState(() {
              _foldUnchanged = !_foldUnchanged;
              _expandedFolds.clear();
            });
          case 'expandAll':
            _expandAllFolds();
          case 'saveLeft':
            unawaited(_saveSide(left: true));
          case 'merge':
            unawaited(_showMergeResult());
          case 'dirDiff':
            unawaited(DirDiffPage.show(context, windowId: widget.windowId));
          case 'threeWay':
            unawaited(_openThreeWayMerge());
          // 注意：上面已经有一个 'syntax'（语法高亮开关），同一个 value 只能命中第一个 case，
          // 所以「检查两侧语法」以前永远走不到，点它只是把高亮开关切了一下。
          case 'checkSyntax':
            unawaited(_checkSyntax());
          case 'swapLayout':
            final next = !_sideBySide;
            setState(() => _sideBySide = next);
            unawaited(SharedPreferencesAsync().setBool(_sideKey, next));
          case 'clear':
            _clearAll();
          case 'showSpace':
            setState(() => _showSpace = !_showSpace);
          case 'wordDiff':
            setState(() => _wordDiff = !_wordDiff);
            _compare();
          case 'gotoLine':
            unawaited(_gotoLineDialog());
          case 'gotoBlock':
            unawaited(_gotoBlockDialog());
          case 'markBlock':
            _toggleMark();
          case 'prevMark':
            _gotoMark(-1);
          case 'nextMark':
            _gotoMark(1);
          case 'clearMarks':
            setState(_marks.clear);
          case 'exportMarkdown':
            unawaited(_exportMarkdown());
          case 'compareSelection':
            unawaited(_compareSelection());
          case 'unifiedView':
            setState(() => _unified = !_unified);
        }
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(value: 'ignoreCase', checked: _ignoreCase, child: Text(localizations.diffIgnoreCase)),
        CheckedPopupMenuItem(
            value: 'ignoreSpace', checked: _ignoreWhitespace, child: Text(localizations.diffIgnoreWhitespace)),
        CheckedPopupMenuItem(
            value: 'ignoreTrailing',
            checked: _ignoreTrailing,
            child: Text(localizations.diffIgnoreTrailing)),
        CheckedPopupMenuItem(
            value: 'ignoreBlank',
            checked: _ignoreBlank,
            child: Text(localizations.diffIgnoreBlankLines)),
        CheckedPopupMenuItem(
            value: 'ignoreComment',
            checked: _ignoreComments,
            child: Text(localizations.diffIgnoreComments)),
        CheckedPopupMenuItem(
            value: 'alignByLine',
            checked: _alignByLine,
            child: Text(localizations.diffAlignByLine)),
        PopupMenuItem(
            value: 'ignoreLines',
            child: Text(_ignoreLineText.isEmpty
                ? localizations.diffIgnoreLines
                : localizations.diffIgnoreLinePattern(_ignoreLineText))),
        CheckedPopupMenuItem(value: 'wrap', checked: _wrap, child: Text(localizations.wordWrap)),
        CheckedPopupMenuItem(
            value: 'onlyDiff', checked: _onlyDiff, child: Text(localizations.diffOnlyChanges)),
        CheckedPopupMenuItem(
            value: 'syncH', checked: _syncH, child: Text(localizations.diffSyncHScroll)),
        CheckedPopupMenuItem(
            value: 'syncV', checked: _syncV, child: Text(localizations.diffSyncVScroll)),
        CheckedPopupMenuItem(
            value: 'foldUnchanged',
            checked: _foldUnchanged,
            child: Text(localizations.diffFoldUnchanged)),
        if (_foldUnchanged)
          PopupMenuItem(value: 'expandAll', child: Text(localizations.diffExpandAllFolds)),
        CheckedPopupMenuItem(
            value: 'showSpace',
            checked: _showSpace,
            child: Text(localizations.diffShowWhitespace)),
        CheckedPopupMenuItem(
            value: 'syntax',
            checked: _syntax,
            child: Text(localizations.diffSyntaxHighlight)),
        CheckedPopupMenuItem(
            value: 'wordDiff',
            checked: _wordDiff,
            child: Text(localizations.diffWordDiff)),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
            enabled: false,
            height: 28,
            child: Text(localizations.diffTabWidth,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.primary))),
        CheckedPopupMenuItem(
            value: 'tabKeep',
            checked: _tabWidth == 0,
            child: Text(localizations.diffTabWidthNone)),
        CheckedPopupMenuItem(
            value: 'tab2', checked: _tabWidth == 2, child: const Text('Tab = 2')),
        CheckedPopupMenuItem(
            value: 'tab4', checked: _tabWidth == 4, child: const Text('Tab = 4')),
        CheckedPopupMenuItem(
            value: 'tab8', checked: _tabWidth == 8, child: const Text('Tab = 8')),
        PopupMenuItem(value: 'gotoLine', child: Text(localizations.diffGotoLine)),
        PopupMenuItem(
            value: 'gotoBlock', child: Text(localizations.diffGotoBlock)),
        PopupMenuItem(
            value: 'compareSelection',
            child: Text(localizations.diffCompareSelection)),
        CheckedPopupMenuItem(
            value: 'markBlock',
            checked: _navIndex >= 0 && _marks.contains(_navIndex),
            child: Text(_marks.isEmpty
                ? localizations.diffMarkBlock
                : localizations.diffMarkBlockCount(_marks.length))),
        PopupMenuItem(value: 'prevMark', child: Text(localizations.diffPrevMark)),
        if (_marks.isNotEmpty) ...[
          PopupMenuItem(value: 'nextMark', child: Text(localizations.diffNextMark)),
          PopupMenuItem(value: 'clearMarks', child: Text(localizations.diffClearMarks)),
        ],
        CheckedPopupMenuItem(
            value: 'unifiedView',
            checked: _unified,
            child: Text(localizations.diffUnifiedView)),
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
        PopupMenuItem(value: 'exportMarkdown', child: Text(localizations.diffExportMarkdown)),
        PopupMenuItem(value: 'exportReport', child: Text(localizations.diffExportReport)),
        PopupMenuItem(value: 'exportHtml', child: Text(localizations.diffExportHtmlReport)),
        PopupMenuItem(value: 'exportPatch', child: Text(localizations.diffExportPatch)),
        PopupMenuItem(value: 'copyPatch', child: Text(localizations.diffCopyPatch)),
        PopupMenuItem(value: 'normalize', child: Text(localizations.diffNormalize)),
        PopupMenuItem(value: 'editInEditorLeft', child: Text(localizations.diffOpenInEditorLeft)),
        PopupMenuItem(value: 'editInEditorRight', child: Text(localizations.diffOpenInEditorRight)),
        PopupMenuItem(value: 'shareDiff', child: Text(localizations.diffShare)),
        PopupMenuItem(value: 'reloadFiles', child: Text(localizations.diffReloadFiles)),
        PopupMenuItem(value: 'exportCsv', child: Text(localizations.diffExportCsv)),
        PopupMenuItem(value: 'diffList', child: Text(localizations.diffList)),
        PopupMenuItem(value: 'hexDiff', child: Text(localizations.hexDiffTitle)),
        PopupMenuItem(value: 'imageDiff', child: Text(localizations.imageDiffTitle)),
        PopupMenuItem(value: 'tableCompare', child: Text(localizations.tableDiffOpen)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'baselineSave', child: Text(localizations.diffBaselineSave)),
        PopupMenuItem(value: 'baselineCompare', child: Text(localizations.diffBaselineCompare)),
        PopupMenuItem(value: 'baselineClear', child: Text(localizations.diffBaselineClear)),
        PopupMenuItem(value: 'saveLeft', child: Text(localizations.diffSaveLeft)),
        PopupMenuItem(value: 'merge', child: Text(localizations.diffMerge)),
        PopupMenuItem(value: 'dirDiff', child: Text(localizations.dirDiff)),
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
        PopupMenuItem(value: 'checkSyntax', child: Text(localizations.diffSyntaxCheck)),
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
    // 导航到某处差异时也给一条「就地应用」的快捷条：
    // 以前「用左侧 / 用右侧」只藏在差异列表和聚焦模式里，逐块合并要反复开关面板。
    final i = _navIndex;
    if (i >= 0 && i < _blocks.length) return _navApplyBar(i);
    return const SizedBox.shrink();
  }

  /// 当前差异块的「上一个 / 下一个 / 用左侧 / 用右侧」快捷条。
  Widget _navApplyBar(int idx) {
    final theme = Theme.of(context);
    return Container(
      height: 38,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4))),
        color: theme.colorScheme.primary.withValues(alpha: 0.04),
      ),
      child: Row(children: <Widget>[
        IconButton(
          tooltip: localizations.diffPrev,
          icon: const Icon(Icons.keyboard_arrow_up, size: 19),
          onPressed: () => _navigate(-1),
        ),
        Text('${idx + 1}/${_blocks.length}',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.primary)),
        IconButton(
          tooltip: localizations.diffNext,
          icon: const Icon(Icons.keyboard_arrow_down, size: 19),
          onPressed: () => _navigate(1),
        ),
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
          icon: const Icon(Icons.close, size: 16),
          onPressed: () => setState(() => _navIndex = -1),
        ),
      ]),
    );
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

  /// 只比较两侧各自选中的段落：单独开一个临时对比页（不覆盖「上次对比」）。
  static const _baselineKey = 'text_diff_baseline_v1';

  /// 把左栏存成基线。
  ///
  /// 用途：改配置、改模板这类工作，「上次提交时的样子」比「上一次保存的样子」
  /// 更有意义（后者每一版都在变，看不出累计漂移）。存一次基线，之后每次都是
  /// 基线 vs 现在，看的就是相对起点的总变化。
  Future<void> _saveBaseline() async {
    final text = _left.text;
    if (text.trim().isEmpty) {
      _toastText(localizations.diffSelectFirst);
      return;
    }
    try {
      final sp = await SharedPreferencesAsync();
      final name = _leftName.isNotEmpty ? _leftName : localizations.diffBaseline;
      await sp.setString(
        _baselineKey,
        jsonEncode(<String, dynamic>{
          'name': name,
          'time': DateTime.now().toIso8601String(),
          'text': text,
        }),
      );
      if (!mounted) return;
      _toastText(localizations.diffBaselineSaved);
    } catch (e) {
      if (!mounted) return;
      _toastText('${localizations.fail}: $e');
    }
  }

  /// 基线塞进左栏，「现在」留在右栏。
  Future<void> _compareWithBaseline() async {
    String? raw;
    try {
      raw = await SharedPreferencesAsync().getString(_baselineKey);
    } catch (_) {
      raw = null;
    }
    if (raw == null || raw.isEmpty) {
      if (!mounted) return;
      _toastText(localizations.diffBaselineNone);
      return;
    }
    var text = '';
    var name = '';
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      text = (m['text'] as String?) ?? '';
      name = (m['name'] as String?) ?? '';
    } catch (_) {
      if (!mounted) return;
      _toastText(localizations.diffBaselineNone);
      return;
    }
    if (text.isEmpty) {
      if (!mounted) return;
      _toastText(localizations.diffBaselineNone);
      return;
    }
    if (!mounted) return;
    setState(() {
      _left.text = text;
      _leftName = name.isEmpty ? localizations.diffBaseline : name;
      // 基线不是磁盘上的文件，别让它参与「文件被外部修改」的提示。
      _leftPath = '';
    });
    _markDiskBaseline();
    _compare();
    if (!mounted) return;
    _toastText('${localizations.diffBaseline}: $_leftName');
  }

  Future<void> _clearBaseline() async {
    try {
      await SharedPreferencesAsync().remove(_baselineKey);
      if (!mounted) return;
      _toastText(localizations.clear);
    } catch (e) {
      if (!mounted) return;
      _toastText('${localizations.fail}: $e');
    }
  }

  Future<void> _compareSelection() async {
    String selOf(CodeForgeController c) {
      final sel = c.selection;
      if (!sel.isValid || sel.isCollapsed) return '';
      final len = c.text.length;
      final a = sel.start.clamp(0, len);
      final b = sel.end.clamp(0, len);
      return a <= b ? c.text.substring(a, b) : c.text.substring(b, a);
    }

    final l = selOf(_left);
    final r = selOf(_right);
    if (l.isEmpty && r.isEmpty) {
      _toastText(localizations.diffSelectFirst);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TextDiffPage(initialLeft: l, initialRight: r, persist: false),
    ));
  }

  /// 跳到第 N 处差异：几十处差异时，一直点「下一处」翻到手酸。
  Future<void> _gotoBlockDialog() async {
    if (_blocks.isEmpty) {
      _toastText(localizations.diffNoDifference);
      return;
    }
    final ctrl = TextEditingController(
        text: '${(_navIndex >= 0 ? _navIndex : 0) + 1}');
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.diffGotoBlock),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1 - ${_blocks.length}'),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v.trim())),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(localizations.cancel)),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
              child: Text(localizations.confirm)),
        ],
      ),
    );
    ctrl.dispose();
    if (!mounted || n == null) return;
    if (n < 1 || n > _blocks.length) {
      _toastText(localizations.diffGotoBlockInvalid('${_blocks.length}'));
      return;
    }
    _jumpToBlock(n - 1);
  }

  /// 跳转到指定行（两侧同步，按各自行数 clamp）。
  Future<void> _gotoLineDialog() async {
    final loc = localizations;
    final c = TextEditingController();
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.diffGotoLine),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: loc.diffGotoLineHint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(int.tryParse(v.trim())),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(loc.cancel)),
          FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(int.tryParse(c.text.trim())),
              child: Text(loc.confirm)),
        ],
      ),
    );
    c.dispose();
    if (n == null || n <= 0) return;
    _gotoLine(_left, n - 1);
    _gotoLine(_right, n - 1);
  }

  /// 差异统计 + 两侧文件信息（对标 WinMerge 的「比较结果」页）。
  ///
  /// 以前只弹一句 toast，看不到「左边多少个字符、右边多大、改的是哪个时间点的文件」——
  /// 而这些恰恰是「我改的到底是不是这一版」的判断依据。
  Future<void> _showDiffStats() async {
    final stats = diffStats(_blocks);
    final summary = localizations.diffStatsSummary(
        '${stats.added}', '${stats.deleted}', '${stats.modified}');
    final li = _sideInfo(_leftPath, _left.text);
    final ri = _sideInfo(_rightPath, _right.text);
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final color = Theme.of(ctx).colorScheme;
        Widget row(String k, String v) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 62,
                  child: Text(k,
                      style: TextStyle(fontSize: 11.5, color: color.onSurfaceVariant)),
                ),
                Expanded(
                  child: Text(v,
                      style: const TextStyle(fontSize: 11.5, height: 1.3)),
                ),
              ]),
            );
        Widget card(String title, ({_SideInfo info, String name, String path}) side) {
          final i = side.info;
          return Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: color.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  side.name.isEmpty ? title : side.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                row(localizations.diffStatLines, '${i.lines}'),
                row(localizations.diffStatChars, '${i.chars}'),
                row(localizations.diffStatSize, i.sizeText),
                row(localizations.diffStatNewline, i.newline),
                if (i.modified != null)
                  row(localizations.diffStatModified, i.modified!),
                if (side.path.isNotEmpty)
                  row(localizations.diffStatPath, side.path),
              ]),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(localizations.diffStatsTitle,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(summary,
                    style: TextStyle(
                        fontSize: 12.5, fontFamily: 'monospace', color: color.primary)),
                if (_newlineHint().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(_newlineHint().trim(),
                      style: TextStyle(fontSize: 11, color: Colors.orange.shade800)),
                ],
                if (_ignoreSummary().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(localizations.diffIgnoredList(_ignoreSummary()),
                      style: TextStyle(fontSize: 11, color: color.onSurfaceVariant)),
                ],
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  card(localizations.diffOriginal,
                      (info: li, name: _leftName, path: _leftPath)),
                  const SizedBox(width: 8),
                  card(localizations.diffChanged,
                      (info: ri, name: _rightName, path: _rightPath)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final text = [
                          summary,
                          if (_newlineHint().isNotEmpty) _newlineHint().trim(),
                          '${localizations.diffOriginal}: '
                              '${_leftName.isEmpty ? '-' : _leftName} · '
                              '${li.lines}L / ${li.sizeText} / ${li.newline}',
                          '${localizations.diffChanged}: '
                              '${_rightName.isEmpty ? '-' : _rightName} · '
                              '${ri.lines}L / ${ri.sizeText} / ${ri.newline}',
                        ].join('\n');
                        await Clipboard.setData(ClipboardData(text: text));
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                        _toastText(localizations.copied);
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: Text(localizations.diffCopyStats,
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(localizations.guideGotIt),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 一侧的字符/行/体积/换行符信息。文件存在时用磁盘上的真实大小与修改时间。
  _SideInfo _sideInfo(String path, String text) {
    final lines = text.isEmpty ? 0 : text.split('\n').length;
    final crlf = RegExp('\\r\\n').allMatches(text).length;
    final lfOnly = '\n'.allMatches(text).length - crlf;
    final newline = crlf > 0 && lfOnly > 0
        ? localizations.diffNewlineMixed
        : (crlf > 0 ? 'CRLF' : 'LF');
    int bytes = utf8.encode(text).length;
    String? modified;
    if (path.isNotEmpty) {
      try {
        final f = File(path);
        if (f.existsSync()) {
          bytes = f.lengthSync();
          final t = f.statSync().modified;
          String p2(int n) => n.toString().padLeft(2, '0');
          modified = '${t.year}-${p2(t.month)}-${p2(t.day)} ${p2(t.hour)}:${p2(t.minute)}';
        }
      } catch (_) {
        // 盘上读不到（SAF 路径 / 权限）就用内存里的估算值，不拦着看统计
      }
    }
    return _SideInfo(
      lines: lines,
      chars: text.length,
      bytes: bytes,
      newline: newline,
      modified: modified,
    );
  }

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  /// 「忽略匹配某正则的行」的输入框。
  ///
  /// 日志、抓包、时间戳这类对比里，真正要看的内容一样，但每行都夹着不同的
  /// 时间/请求 id —— 不忽略就满屏红。正则在这里比「忽略空白」实用得多。
  Future<void> _showIgnoreLineDialog() async {
    final ctl = TextEditingController(text: _ignoreLineText);
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(localizations.diffIgnoreLineTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctl,
                autofocus: true,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  hintText: localizations.diffIgnoreLineHintText,
                  errorText: error,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Text(localizations.diffIgnoreLineHint,
                  style: TextStyle(
                      fontSize: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ],
          ),
          actions: [
            if (_ignoreLineText.isNotEmpty)
              TextButton(
                onPressed: () {
                  ctl.text = '';
                  setDlg(() => error = null);
                },
                child: Text(localizations.clear),
              ),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(localizations.cancel)),
            FilledButton(
              onPressed: () {
                final t = ctl.text.trim();
                if (t.isNotEmpty) {
                  try {
                    RegExp(t);
                  } catch (e) {
                    setDlg(() => error = '$e');
                    return;
                  }
                }
                Navigator.of(ctx).pop(true);
              },
              child: Text(localizations.confirm),
            ),
          ],
        ),
      ),
    );
    final value = ctl.text.trim();
    ctl.dispose();
    if (ok != true || !mounted) return;
    _ignoreLineText = value;
    _ignoreLineRe = value.isEmpty ? null : RegExp(value);
    _compare();
  }

  /// 当前生效的「忽略」项（统计面板里显示）。
  ///
  /// 用户开了「忽略大小写」之后再看结果，很可能忘了自己开过 —— 结果是
  /// 「明明有差别却说完全一致」，很容易怀疑工具坏了。
  String _ignoreSummary() {
    final parts = <String>[
      if (_ignoreCase) localizations.diffIgnoreCase,
      if (_ignoreWhitespace) localizations.diffIgnoreWhitespace,
      if (_ignoreTrailing) localizations.diffIgnoreTrailing,
      if (_ignoreBlank) localizations.diffIgnoreBlankLines,
      if (_ignoreComments) localizations.diffIgnoreComments,
      if (_ignoreLineText.isNotEmpty) localizations.diffIgnoreLinePattern(_ignoreLineText),
    ];
    return parts.join('、');
  }

  /// 两侧换行符风格不同时补一句提示：这是「看着一样却全标红」的第二大原因
  /// （第一大是行尾空格）。比较本身已经忽略行尾 \r，这里只是解释现象。
  String _newlineHint() {
    final l = _left.text.contains('\r\n');
    final r = _right.text.contains('\r\n');
    if (l == r) return '';
    return '\n${localizations.diffNewlineMismatch(l ? 'CRLF' : 'LF', r ? 'CRLF' : 'LF')}';
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
    return Container(
      padding: const EdgeInsets.only(right: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _iconBtn(Icons.swap_horiz, localizations.diffSwapSides, _swapSides),
        _iconBtn(Icons.keyboard_arrow_up, localizations.diffPrev, hasDiff ? () => _navigate(-1) : null),
        _iconBtn(Icons.keyboard_arrow_down, localizations.diffNext, hasDiff ? () => _navigate(1) : null),
        _iconBtn(Icons.search, localizations.search, _onSearchButton),
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

  /// 保存某一侧的文本到文件（工具栏 💾 存右侧，菜单里可以存左侧）。
  Future<void> _saveSide({required bool left}) async {
    final text = left ? _left.text : _right.text;
    if (text.isEmpty) {
      _toastText(localizations.cannotBeEmpty);
      return;
    }
    try {
      await FilePicker.saveFile(
          fileName: left ? 'diff-left.txt' : 'diff-right.txt',
          bytes: Uint8List.fromList(utf8.encode(text)));
      if (mounted) _toastText(localizations.copied);
    } catch (e) {
      _toastText('${localizations.fail}: $e');
    }
  }

  Future<void> _saveResult() => _saveSide(left: false);

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
          if (_blocks.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              _statsText(),
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: color.onSurfaceVariant,
              ),
            ),
          ],
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
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth;
      // flex 用整数：0.5 → 500/500。夹住是为了不让某一侧被拖到看不见。
      final leftFlex = (_splitRatio * 1000).round().clamp(150, 850);
      return Row(children: [
        Expanded(flex: leftFlex, child: _editor(_left, localizations.diffOriginal, isLeft: true)),
        // 拖动条：视觉 1px，触摸区 9px（手指能按到，又不像分栏手柄那么笨重）。
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) {
            if (w <= 0) return;
            setState(() => _splitRatio = (_splitRatio + d.delta.dx / w).clamp(0.15, 0.85));
          },
          // setDouble 返回 Future<void>，catchError 的 handler 不能返回 null
          // （那样会抛「error handler must return a value of the future's type」）。
          onHorizontalDragEnd: (_) => unawaited(
              SharedPreferencesAsync().setDouble(_splitKey, _splitRatio).catchError((Object _) {})),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: SizedBox(
              width: 9,
              child: Center(
                child: Container(
                  width: 1,
                  color: Theme.of(ctx).dividerColor.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ),
        Expanded(flex: 1000 - leftFlex, child: _editor(_right, localizations.diffChanged, isLeft: false)),
      ]);
    });
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
          IconButton(
            tooltip: localizations.paste,
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.content_paste),
            onPressed: () => _pasteInto(controller),
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
    final key =
        '${_left.text.hashCode}|${_right.text.hashCode}|$_ignoreCase|$_ignoreWhitespace|'
        '$_ignoreTrailing|$_ignoreBlank|$_ignoreComments|$_ignoreLineText|$_alignByLine';
    if (key == _alignedRowsKey) return _alignedRowsCache;
    _alignedRowsKey = key;
    _alignedRowsCache = alignedDiffRows(_left.text, _right.text,
        ignoreCase: _ignoreCase,
        ignoreWhitespace: _ignoreWhitespace,
        ignoreTrailingWhitespace: _ignoreTrailing,
        ignoreBlankLines: _ignoreBlank,
        ignoreComments: _ignoreComments,
        ignoreLinePattern: _ignoreLineRe,
        alignByLine: _alignByLine);
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
    if (_unified) return _unifiedView(rows);
    _ensureWidths(rows);
    final current = _currentRowIndex(rows);
    final divider = Theme.of(context).dividerColor.withValues(alpha: 0.35);
    // 左右两栏宽度可拖（对标 WinMerge / Beyond Compare 的中缝拖动）：
    // 手机竖屏各占一半最省地方，但横屏、平板上常常是「一边只看行号、另一边看长行」，
    // 固定 50/50 会浪费；中缝双击复位。
    // 对齐视图也支持拖中缝：和源码视图共用同一个比例（都是「左栏占多少」），
    // 用户拖过一次，两个视图都记住。
    final leftFlex = (_splitRatio * 1000).round().clamp(150, 850);
    final body = Row(children: [
      Expanded(flex: leftFlex, child: _alignedPane(rows, current, left: true)),
      _splitHandle(divider),
      Expanded(
          flex: 1000 - leftFlex, child: _alignedPane(rows, current, left: false)),
      _densityBar(rows),
    ]);
    // 悬浮的「上一处 / 下一处」：滚下去之后顶部工具栏看不见了，
    // 手机上想跳到下一处还得先滚回顶部，很别扭（对标 VS Code diff 的右上角那对箭头）。
    if (_blocks.length < 2) return body;
    return Stack(children: [
      Positioned.fill(child: body),
      Positioned(
        right: 10,
        bottom: 10,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _navFab(Icons.keyboard_arrow_up, () => _navigate(-1), localizations.editorLintPrev),
          const SizedBox(height: 6),
          _navFab(Icons.keyboard_arrow_down, () => _navigate(1), localizations.editorLintNext),
        ]),
      ),
    ]);
  }

  /// 对齐视图两栏之间的可拖动中缝（视觉 1px、触摸区 9px，和源码视图手感一致）。
  Widget _splitHandle(Color divider) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) {
        final w = MediaQuery.sizeOf(context).width;
        if (w <= 0) return;
        setState(() =>
            _splitRatio = (_splitRatio + d.delta.dx / w).clamp(0.15, 0.85));
      },
      onHorizontalDragEnd: (_) => unawaited(
          SharedPreferencesAsync().setDouble(_splitKey, _splitRatio).catchError((Object _) {})),
      // 双击复位：拖歪了不用一点点拖回来。
      onDoubleTap: () {
        setState(() => _splitRatio = 0.5);
        unawaited(SharedPreferencesAsync()
            .setDouble(_splitKey, 0.5)
            .catchError((Object _) {}));
      },
      child: Container(
        width: 9,
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Container(width: 1, color: divider),
      ),
    );
  }

  Widget _navFab(IconData icon, VoidCallback onTap, String tooltip) {
    final color = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.primary.withValues(alpha: 0.9),
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 20, color: color.onPrimary),
          ),
        ),
      ),
    );
  }

  /// 把剪贴板内容贴进某一侧（手机上「复制一段 → 直接比」比选文件快得多）。
  Future<void> _pasteInto(CodeForgeController target) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.isEmpty) {
        _toastText(localizations.editorClipboardEmpty);
        return;
      }
      target.text = text;
      if (!mounted) return;
      setState(() {
        // 粘贴进来的内容不再对应原来那个文件名。
        if (identical(target, _left)) {
          _leftName = '';
          _leftPath = '';
        } else {
          _rightName = '';
          _rightPath = '';
        }
        _navIndex = -1;
      });
      _compare();
    } catch (e) {
      _toastText('${localizations.fail}: $e');
    }
  }

  /// 统一视图：单栏上下排，删除行标 -、新增行标 +，修改拆成「- 旧 / + 新」两行。
  ///
  /// 手机竖屏上两栏各占一半宽度，长行基本读不了；git 那种单栏反而更清楚。
  Widget _unifiedView(List<DiffRow> rows) {
    final lines = <_UnifiedLine>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      switch (r.type) {
        case DiffRowType.equal:
          lines.add(_UnifiedLine(
              '  ', r.leftLine ?? r.rightLine, r.leftText ?? '', r.type, i));
        case DiffRowType.deleted:
          lines.add(_UnifiedLine('- ', r.leftLine, r.leftText ?? '', r.type, i));
        case DiffRowType.added:
          lines.add(
              _UnifiedLine('+ ', r.rightLine, r.rightText ?? '', r.type, i));
        case DiffRowType.modified:
          final cd = _wordDiff ? _charDiffOf(r.leftText ?? '', r.rightText ?? '') : null;
          lines.add(_UnifiedLine(
              '- ', r.leftLine, r.leftText ?? '', DiffRowType.deleted, i,
              ranges: cd?.leftRanges));
          lines.add(_UnifiedLine(
              '+ ', r.rightLine, r.rightText ?? '', DiffRowType.added, i,
              ranges: cd?.rightRanges));
      }
    }
    // 单栏不横向滚动：超长行用省略号截断（统一视图是「快速扫改动」，
    // 逐字读长行请切回并排视图或直接看编辑器）。
    return ListView.builder(
      // 复用左栏的滚动控制器：两种视图互斥，同一时刻只有一个挂在树上，
      // 这样「跳到某处差异 / 跳到命中」在统一视图里也能滚到位。
      controller: _leftV,
      itemExtent: _wrap ? null : _rowHeight,
      itemCount: lines.length,
      itemBuilder: (context, i) => _unifiedLine(lines[i]),
      padding: EdgeInsets.zero,
    );
  }

  Widget _unifiedLine(_UnifiedLine l) {
    final isDark = Theme.brightnessOf(context) == Brightness.dark;
    Color? bg;
    switch (l.type) {
      case DiffRowType.added:
        bg = Colors.green.withValues(alpha: isDark ? 0.20 : 0.14);
      case DiffRowType.deleted:
        bg = Colors.red.withValues(alpha: isDark ? 0.22 : 0.13);
      case DiffRowType.modified:
      case DiffRowType.equal:
        bg = null;
    }
    final signColor = switch (l.type) {
      DiffRowType.added => Colors.green.shade600,
      DiffRowType.deleted => Colors.red.shade600,
      _ => Colors.grey,
    };
    final raw = l.text;
    final text = _renderText(raw);
    return Container(
      color: bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 34,
            child: Text(l.num?.toString() ?? '',
                textAlign: TextAlign.right,
                maxLines: 1,
                style: TextStyle(fontSize: _fontSize - 2, color: Colors.grey[600], height: 1.0)),
          ),
          SizedBox(
            width: 16,
            child: Text(l.sign,
                maxLines: 1,
                style: TextStyle(
                    fontSize: _fontSize, color: signColor, fontFamily: 'monospace', height: 1.0)),
          ),
          Expanded(
            child: _findQuery.isEmpty
                ? (l.ranges != null && l.ranges!.isNotEmpty && _tabWidth == 0
                    ? Text.rich(
                        _spansWithBg(
                            text,
                            TextStyle(
                                fontSize: _fontSize,
                                fontFamily: 'monospace',
                                height: 1.0),
                            l.ranges!,
                            l.type == DiffRowType.added
                                ? Colors.green.withValues(alpha: isDark ? 0.30 : 0.22)
                                : Colors.red.withValues(alpha: isDark ? 0.34 : 0.26)),
                        maxLines: _wrap ? null : 1,
                        softWrap: _wrap,
                        overflow:
                            _wrap ? TextOverflow.clip : TextOverflow.ellipsis)
                    : Text(text,
                        maxLines: _wrap ? null : 1,
                        softWrap: _wrap,
                        overflow:
                            _wrap ? TextOverflow.clip : TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: _fontSize,
                            fontFamily: 'monospace',
                            height: 1.0)))
                : Text.rich(
                    _highlightSpan(text,
                        TextStyle(
                            fontSize: _fontSize,
                            fontFamily: 'monospace',
                            height: 1.0),
                        l.srcRow),
                    maxLines: _wrap ? null : 1,
                    softWrap: _wrap,
                    overflow:
                        _wrap ? TextOverflow.clip : TextOverflow.ellipsis),
          ),
        ],
      ),
    );
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
  /// 合并结果（2-way merge）：逐块决定用左还是用右，拼出**第三份**文本。
  ///
  /// 之前只有「全部接受」「单块应用」，那是把一侧改写成另一侧；这里给一个输出口：
  /// 生成后可以写回右栏、复制、或导出成文件——改代码时通常要的就是「合并后的那份」。
  String _buildMergedText(Map<int, bool> choice, int strategy) {
    // 空文本拆出来是 ['']（一个空行），会让合并结果凭空多一个换行
    List<String> lines(String t) =>
        t.isEmpty ? const <String>[] : t.split('\n');
    return mergeTwoWay(
      leftLines: lines(_left.text),
      rightLines: lines(_right.text),
      blocks: _blocks,
      useRight: (bi) =>
          strategy == 0 ? true : (strategy == 1 ? false : (choice[bi] ?? true)),
    );
  }

  /// 把合并结果直接写回**右侧那个文件的路径**（不是编辑器缓冲区）。
  ///
  /// 「另存为」是给新文件用的；这里省掉选路径那一步 —— 三个版本合并完，
  /// 想让磁盘上那份也跟上，是最自然的收尾动作。
  Future<void> _writeToRightFile(String text) async {
    final path = _rightPath;
    if (path.isEmpty) return;
    final name = _rightName.isEmpty
        ? path.split(RegExp(r'[/\\]')).last
        : _rightName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(localizations.diffMergeSaveToFile),
        content: Text(localizations.diffMergeSaveToFileAsk(name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: Text(localizations.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: Text(localizations.confirm)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await File(path).writeAsString(text);
      if (!mounted) return;
      _toastText(localizations.diffMergedSaved(name));
    } catch (e) {
      if (!mounted) return;
      _toastText('${localizations.fail}: $e');
    }
  }

  Future<void> _showMergeResult() async {
    if (_blocks.isEmpty) {
      _toastText(localizations.diffNoDifference);
      return;
    }
    if (_left.text.length + _right.text.length > 4000000) {
      _toastText(localizations.diffMergeTooLarge);
      return;
    }
    if (_mergeChoice.length != _blocks.length) {
      // 块数量变了（重新比较过）：旧的选择已经没有对应关系
      _mergeChoice.clear();
    }
    var strategy = _mergeStrategy;
    var merged = _buildMergedText(_mergeChoice, strategy);

    String rebuild(int s) {
      strategy = s;
      return _buildMergedText(_mergeChoice, s);
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final theme = Theme.of(ctx);
          Widget chip(String label, int value) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  selected: strategy == value,
                  onSelected: (_) => setSheet(() => merged = rebuild(value)),
                ),
              );
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.88,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(localizations.diffMerge,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface)),
                      ),
                      Text('${_blocks.length}',
                          style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant)),
                      // 右侧是从文件打开的：给一个「直接覆盖那个文件」的快捷入口。
                      if (_rightPath.isNotEmpty)
                        IconButton(
                          tooltip: localizations.diffMergeSaveToFile,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.save, size: 18),
                          onPressed: () => _writeToRightFile(merged),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      chip(localizations.diffMergeAllRight, 0),
                      chip(localizations.diffMergeAllLeft, 1),
                      chip(localizations.diffMergeCustom, 2),
                    ],
                  ),
                ),
                if (strategy == 2)
                  SizedBox(
                    height: 132,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: _blocks.length,
                      itemBuilder: (_, i) {
                        final b = _blocks[i];
                        final useRight = _mergeChoice[i] ?? true;
                        return InkWell(
                          onTap: () => setSheet(() {
                            _mergeChoice[i] = !useRight;
                            merged = rebuild(2);
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                Text('#${i + 1}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurfaceVariant)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'L${b.leftStart + 1} ↔ R${b.rightStart + 1}',
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        fontFamily: 'monospace'),
                                  ),
                                ),
                                _sidePill(
                                    theme,
                                    localizations.diffMergeUseLeftShort,
                                    !useRight),
                                const SizedBox(width: 4),
                                _sidePill(
                                    theme,
                                    localizations.diffMergeUseRightShort,
                                    useRight),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const Divider(height: 8),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        merged.length > 20000
                            ? '${merged.substring(0, 20000)}\n…'
                            : merged,
                        style: TextStyle(
                            fontSize: _fontSize - 1, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: merged));
                              if (!mounted) return;
                              _toastText(localizations.copied);
                            },
                            icon: const Icon(Icons.copy, size: 16),
                            label: Text(localizations.copy,
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                await FilePicker.saveFile(
                                    fileName: 'merged.txt',
                                    bytes: utf8.encode(merged));
                                if (!mounted) return;
                                _toastText(localizations.diffReportSaved);
                              } catch (e) {
                                _toastText('$e');
                              }
                            },
                            icon: const Icon(Icons.save_alt, size: 16),
                            label: Text(localizations.save,
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              _right.text = merged;
                              _mergeStrategy = strategy;
                              Navigator.pop(ctx);
                              _compare();
                              _toastText(localizations.diffMergeApplied);
                            },
                            icon: const Icon(Icons.arrow_forward, size: 16),
                            label: Text(localizations.diffMergeToRight,
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    _mergeStrategy = strategy;
  }

  Widget _sidePill(ThemeData theme, String label, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: active
            ? theme.colorScheme.primary.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: active ? theme.colorScheme.primary : theme.dividerColor,
            width: 0.8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5,
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant)),
    );
  }

  void _showDiffList() {
    if (_blocks.isEmpty) {
      _toastText(localizations.diffNoDifference);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
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
                const SizedBox(width: 8),
                // 两侧各多少行：一路翻差异时，能顺便看出「这份文件到底改了多大的量」。
                Text(
                    localizations.diffLineCounts(
                        '${_left.lineCount}', '${_right.lineCount}'),
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant)),
                if (_reviewed.isNotEmpty)
                  Text(
                      localizations.diffReviewedCount(
                          '${_reviewed.length}', '${_blocks.length}'),
                      style: TextStyle(
                          fontSize: 11, color: theme.colorScheme.primary)),
                const Spacer(),
                IconButton(
                  tooltip: localizations.diffNextUnreviewed,
                  icon: const Icon(Icons.skip_next, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    final next = _firstUnreviewed();
                    if (next < 0) {
                      _toastText(localizations.diffAllReviewed);
                      return;
                    }
                    Navigator.of(ctx).pop();
                    _jumpToBlock(next);
                  },
                ),
                if (_reviewed.isNotEmpty)
                  IconButton(
                    tooltip: localizations.diffReviewedReset,
                    icon: const Icon(Icons.restart_alt, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setSheet(() => _reviewed.clear()),
                  ),
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
                  final seen = _reviewed.contains(i);
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    minLeadingWidth: 52,
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${i + 1}',
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(width: 6),
                        // 勾一下表示「这块看过了」：大 diff 分几次看的时候，
                        // 回来能知道看到哪儿了。只存内存，换内容就清空。
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setSheet(() {
                            if (!_reviewed.remove(i)) _reviewed.add(i);
                          }),
                          child: Icon(
                            seen
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 17,
                            color: seen
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    title: Text(
                      'L${b.leftStart + 1} ↔ R${b.rightStart + 1}   ${parts.join(' · ')}'
                      '${_blockCharDelta(b)}',
                      style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                    ),
                    subtitle: _blockPreview(b),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _jumpToBlock(i);
                    },
                  );
                },
              ),
            ),
          ]),
        );
        });
      },
    );
  }

  /// 这块大概改了多少字符（`+12/-8`）。
  ///
  /// 行数一样的块（比如改了一个词）在列表里只显示「修改 1」，看不出改动规模；
  /// 加个字符数量级，扫列表时能一眼分出「改了个变量名」和「重写了一个函数」。
  String _blockCharDelta(DiffBlock b) {
    if (b.leftLines.isEmpty && b.rightLines.isEmpty) return '';
    if (b.leftLines.length + b.rightLines.length > 200) return '';
    final l = b.leftLines
        .map((i) => (i >= 0 && i < _left.lineCount) ? _lineText(_left, i) : '')
        .join('\n');
    final r = b.rightLines
        .map((i) => (i >= 0 && i < _right.lineCount) ? _lineText(_right, i) : '')
        .join('\n');
    if (l.length + r.length > 40000) return '';
    final cd = diffChars(l, r);
    var add = 0;
    var del = 0;
    for (final p in cd.rightRanges) {
      add += p.end - p.start;
    }
    for (final p in cd.leftRanges) {
      del += p.end - p.start;
    }
    if (add == 0 && del == 0) return '';
    return '   +$add/−$del';
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
      var raw = controller.text.substring(
          start.clamp(0, controller.text.length), end.clamp(0, controller.text.length));
      if (raw.endsWith('\n')) raw = raw.substring(0, raw.length - 1);
      // 行尾 \r 在并排视图里不可见，但会让复制出来的文本带脏字符。
      return raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    } catch (_) {
      return '';
    }
  }

  /// 导出差异报告（Markdown，unified diff 风格）：存档 / 贴 issue 都能用。
  /// 导出标准 unified diff（`--- a/x +++ b/x @@ ... @@`），可直接 `git apply` /
  /// `patch -p1`。桌面工具（Beyond Compare / Meld）都有这个出口，用来把差异交给
  /// CI 或同事的机器。
  /// 导出差异清单 CSV：给「要贴到工单/Excel 里逐条确认」的场景。
  ///
  /// 只导差异行（含上下文？不带 —— 清单只列改动本身最有用）。
  /// 带 UTF-8 BOM + 防公式注入，Excel 直接双击打开不乱码。
  /// 导出差异为 Markdown 表格。
  ///
  /// CSV 适合再加工，但「发给同事看一眼」「贴进 issue / 周报」时还得再排版一次；
  /// Markdown 表格是这些地方都能直接渲染的最小公约数。
  Future<void> _exportMarkdown() async {
    final rows = _alignedRows();
    final changed = rows.where((r) => r.type != DiffRowType.equal).toList();
    if (changed.isEmpty) {
      _toastText(localizations.diffNoChange);
      return;
    }
    final loc = localizations;
    // 表格里 `|` 必须转义，换行在单元格里不合法，压成空格。
    String cell(String? v) =>
        (v ?? '').replaceAll('|', '\\|').replaceAll('\r', '').replaceAll('\n', ' ');
    final buf = StringBuffer()
      ..writeln('| ${loc.diffCsvType} | L | R | ${loc.diffCsvLeftText} | ${loc.diffCsvRightText} |')
      ..writeln('| --- | --- | --- | --- | --- |');
    for (final r in changed) {
      final kind = switch (r.type) {
        DiffRowType.added => loc.diffOnlyAdded,
        DiffRowType.deleted => loc.diffOnlyDeleted,
        DiffRowType.modified => loc.diffOnlyModified,
        DiffRowType.equal => '',
      };
      buf.writeln('| $kind | ${r.leftLine ?? ''} | ${r.rightLine ?? ''} | '
          '${cell(r.leftText)} | ${cell(r.rightText)} |');
    }
    try {
      final bytes = Uint8List.fromList(utf8.encode(buf.toString()));
      final saved = await FilePicker.saveFile(fileName: 'diff-changes.md', bytes: bytes);
      if (!mounted) return;
      if (saved != null) _toastText(localizations.diffReportSaved);
    } catch (e) {
      _toastText('${localizations.fail}: $e');
    }
  }

  Future<void> _exportCsv() async {
    final rows = _alignedRows();
    final changed = rows.where((r) => r.type != DiffRowType.equal).toList();
    if (changed.isEmpty) {
      _toastText(localizations.diffNoChange);
      return;
    }
    final loc = localizations;
    final buf = StringBuffer()
      ..writeln('${_csv(loc.diffCsvType)},${_csv(loc.diffCsvLeft)},'
          '${_csv(loc.diffCsvRight)},${_csv(loc.diffCsvLeftText)},'
          '${_csv(loc.diffCsvRightText)}');
    for (final r in changed) {
      buf.writeln([
        _csv(switch (r.type) {
          DiffRowType.added => loc.diffOnlyAdded,
          DiffRowType.deleted => loc.diffOnlyDeleted,
          DiffRowType.modified => loc.diffOnlyModified,
          DiffRowType.equal => '',
        }),
        _csv(r.leftLine?.toString() ?? ''),
        _csv(r.rightLine?.toString() ?? ''),
        _csv(r.leftText ?? ''),
        _csv(r.rightText ?? ''),
      ].join(','));
    }
    try {
      // BOM：Windows Excel 打开无 BOM 的 UTF-8 CSV 会按 GBK 解码，中文全乱。
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(buf.toString())]);
      final saved = await FilePicker.saveFile(fileName: 'diff-changes.csv', bytes: bytes);
      if (!mounted) return;
      if (saved != null) _toastText(localizations.diffReportSaved);
    } catch (e) {
      _toastText('${localizations.fail}: $e');
    }
  }

  /// CSV 单元格：转义引号 + 以 = + - @ 开头的加单引号（防 Excel 公式注入）。
  static String _csv(String s) {
    var v = s.replaceAll('\r', '').replaceAll('\n', ' ');
    if (v.startsWith('=') || v.startsWith('+') || v.startsWith('-') || v.startsWith('@')) {
      v = "'$v";
    }
    if (v.contains(',') || v.contains('"') || v.contains(' ')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  /// 增 / 删 / 改的行数，常显在顶部（`+3 −2 ~1`）。按 blocks 缓存，别每次 build 重算。
  List<DiffBlock>? _statsFor;
  String _statsLabel = '';

  String _statsText() {
    if (!identical(_statsFor, _blocks)) {
      _statsFor = _blocks;
      final st = diffStats(_blocks);
      var label = '+${st.added} −${st.deleted} ~${st.modified}';
      // 相似度 = 相同行 / 较多一侧的行数。两段文本是同一份文件的两个版本时，
      // 这个数字比「+3 −2 ~1」更直观（Beyond Compare 也把它放在摘要里）。
      final total = _left.lineCount > _right.lineCount
          ? _left.lineCount
          : _right.lineCount;
      if (total > 0) {
        final same = total - st.added - st.deleted - st.modified;
        final pct = (same * 100 / total).clamp(0, 100).round();
        label = '$label · $pct%';
      }
      _statsLabel = label;
    }
    return _statsLabel;
  }

  /// 把两侧都按格式规整一遍（JSON 缩进 2 / XML pretty）。
  ///
  /// 抓到的两个响应经常一个压成一行、一个带缩进，直接对比就是「全行都变了」，
  /// 真正改了哪几处根本看不出来。规整之后差异只剩语义层面的。
  /// 只对**两侧都是同一格式**的文本动手，格式不同就提示不做。
  Future<void> _normalizeBoth() async {
    final kinds = <String>[];
    final results = <String>[];
    for (final side in [_left, _right]) {
      final t = side.text;
      if (t.trim().isEmpty) {
        results.add(t);
        kinds.add('');
        continue;
      }
      final pretty = _prettyOf(t);
      if (pretty == null) {
        results.add(t);
        kinds.add('');
      } else {
        results.add(pretty.text);
        kinds.add(pretty.kind);
      }
    }
    final usable = kinds.where((k) => k.isNotEmpty).toList();
    if (usable.isEmpty) {
      _toastText(localizations.diffNormalizeFailed);
      return;
    }
    if (usable.length == 2 && usable[0] != usable[1]) {
      _toastText(localizations.diffNormalizeMismatch(usable[0], usable[1]));
      return;
    }
    setState(() {
      if (results[0] != _left.text) _left.text = results[0];
      if (results[1] != _right.text) _right.text = results[1];
    });
    _compare();
    _toastText(localizations.diffNormalized(usable.first));
  }

  /// 能规整就返回格式化后的文本与格式名（json/xml），否则 null。
  static ({String text, String kind})? _prettyOf(String src) {
    final t = src.trim();
    if (t.length > 4000000) return null;
    if (t.startsWith('{') || t.startsWith('[')) {
      try {
        final obj = jsonDecode(t);
        return (text: const JsonEncoder.withIndent('  ').convert(obj), kind: 'JSON');
      } catch (_) {}
    }
    if (t.startsWith('<')) {
      try {
        final doc = xml.XmlDocument.parse(t);
        return (text: doc.toXmlString(pretty: true, indent: '  '), kind: 'XML');
      } catch (_) {}
    }
    return null;
  }

  /// 把某一侧的内容送进文本编辑器改。
  ///
  /// 对比完发现要改，以前只能记住文件名再自己开编辑器找一遍；
  /// 差一块就能直接接着改（内容进新文档，不覆盖磁盘文件）。
  void _openInEditor(bool isLeft) {
    final text = isLeft ? _left.text : _right.text;
    if (text.isEmpty) {
      _toastText(localizations.cannotBeEmpty);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TextEditorPage(initialText: text),
    ));
  }

  /// 分享 unified diff（走系统分享面板：微信/邮件/文件传输）。
  ///
  /// 复制到剪贴板再手动粘到聊天窗口那两步，手机上经常被别的 App 挤掉。
  Future<void> _shareDiff() async {
    final text = _unifiedDiff(_alignedRows());
    if (text.trim().isEmpty) {
      _toastText(localizations.cannotBeEmpty);
      return;
    }
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (e) {
      if (!mounted) return;
      _toastText('${localizations.fail}: $e');
    }
  }

  /// 把 unified diff 复制到剪贴板：手机上「发给别人看我改了什么」最常用的路径。
  Future<void> _copyUnifiedDiff() async {
    final text = _unifiedDiff(_alignedRows());
    if (text.trim().isEmpty) {
      _toastText(localizations.cannotBeEmpty);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _toastText(localizations.copied);
  }

  Future<void> _exportPatch() async {
    final rows = _alignedRows();
    if (rows.isEmpty) {
      _toastText(localizations.cannotBeEmpty);
      return;
    }
    final text = _unifiedDiff(rows);
    try {
      final saved = await FilePicker.saveFile(
          fileName: 'changes.patch', bytes: Uint8List.fromList(utf8.encode(text)));
      if (!mounted) return;
      if (saved != null) _toastText(localizations.diffReportSaved);
    } catch (e) {
      _toastText('${localizations.fail}: $e');
    }
  }

  String _unifiedDiff(List<DiffRow> rows) {
    final lName = _leftName.isEmpty ? 'original' : _leftName;
    final rName = _rightName.isEmpty ? 'modified' : _rightName;
    final out = StringBuffer()
      ..writeln('--- a/$lName')
      ..writeln('+++ b/$rName');
    final changed = <int>[];
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].type != DiffRowType.equal) changed.add(i);
    }
    if (changed.isEmpty) return out.toString();
    // 相邻变更（间隔 <= 2*context+1）合成一个 hunk
    const context = 3;
    var start = changed.first;
    var end = changed.first;
    for (final i in changed.skip(1)) {
      if (i - end <= context * 2 + 1) {
        end = i;
      } else {
        _writeHunk(out, rows, start, end, context);
        start = i;
        end = i;
      }
    }
    _writeHunk(out, rows, start, end, context);
    return out.toString();
  }

  void _writeHunk(StringBuffer out, List<DiffRow> rows, int from, int to, int context) {
    final first = from - context < 0 ? 0 : from - context;
    final last = to + context >= rows.length ? rows.length - 1 : to + context;
    int? lStart;
    int? rStart;
    var lCount = 0;
    var rCount = 0;
    for (var i = first; i <= last; i++) {
      final r = rows[i];
      if (lStart == null && r.leftLine != null) lStart = r.leftLine;
      if (rStart == null && r.rightLine != null) rStart = r.rightLine;
      if (r.type != DiffRowType.added && r.leftLine != null) lCount++;
      if (r.type != DiffRowType.deleted && r.rightLine != null) rCount++;
    }
    out.writeln('@@ -${lStart ?? 1},$lCount +${rStart ?? 1},$rCount @@');
    for (var i = first; i <= last; i++) {
      final r = rows[i];
      switch (r.type) {
        case DiffRowType.deleted:
          out.writeln('-${r.leftText ?? ''}');
        case DiffRowType.added:
          out.writeln('+${r.rightText ?? ''}');
        case DiffRowType.modified:
          out.writeln('-${r.leftText ?? ''}');
          out.writeln('+${r.rightText ?? ''}');
        case DiffRowType.equal:
          out.writeln(' ${r.leftText ?? r.rightText ?? ''}');
      }
    }
  }

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
  /// 一次性展开所有折叠段。
  ///
  /// 逐段点开太麻烦：几十处未变区就是几十次点击，而且点完还得重新找位置。
  void _expandAllFolds() {
    if (!_foldUnchanged) return;
    final rows = _visibleRows(_alignedRows());
    final starts = <int>{};
    for (final row in rows) {
      final from = row.foldFrom;
      if (from != null) starts.add(from);
    }
    if (starts.isEmpty) {
      _toastText(localizations.diffNoFolds);
      return;
    }
    setState(() => _expandedFolds.addAll(starts));
  }

  void _toggleFold(int from) {
    if (!mounted) return;
    setState(() {
      if (!_expandedFolds.add(from)) _expandedFolds.remove(from);
    });
  }

  /// 右侧「差异密度条」：把每一行的类型按比例画成色块，点哪里滚到哪里（VS 的 overview ruler）。
  Widget _densityBar(List<DiffRow> rows) {
    final isDark = Theme.brightnessOf(context) == Brightness.dark;
    // 已标记的块在密度条上的位置：块 → 它在当前（可能已折叠/已过滤）行列表里的下标。
    final marks = <double>[];
    if (_marks.isNotEmpty && rows.isNotEmpty) {
      for (final i in _marks) {
        if (i < 0 || i >= _blocks.length) continue;
        final wantLeft = _blocks[i].leftStart + 1;
        final wantRight = _blocks[i].rightStart + 1;
        for (var k = 0; k < rows.length; k++) {
          if (rows[k].leftLine == wantLeft || rows[k].rightLine == wantRight) {
            marks.add(k / rows.length);
            break;
          }
        }
      }
    }
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
                painter: _DensityPainter(rows, isDark, vpStart, vpEnd, marks),
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
    // 统一视图把 modified 拆成「-」「+」两行，行号要跟着重算。
    var index = i;
    if (_unified && i > 0) {
      index = 0;
      for (var k = 0; k < i && k < rows.length; k++) {
        index += rows[k].type == DiffRowType.modified ? 2 : 1;
      }
    }
    final target =
        (index * _rowHeight).clamp(0.0, _leftV.position.maxScrollExtent);
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
                itemExtent: _wrap ? null : _rowHeight,
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final row = rows[i];
                  final cell = _alignedRow(row,
                      left: left, isCurrent: i == current, rowIndex: i);
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

  Widget _alignedRow(DiffRow r,
      {required bool left, required bool isCurrent, int rowIndex = -1}) {
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
    final raw = (left ? r.leftText : r.rightText) ?? '';
    final text = _renderText(raw);
    // 语法高亮：按行号取 token（tokens 是 0-based 行数组）。
    final tokens = _syntaxActive ? (left ? _leftTokens : _rightTokens) : null;
    final tokenLine =
        (tokens != null && line != null && line >= 1 && line <= tokens.length)
            ? tokens[line - 1]
            : null;
    final numStyle = TextStyle(fontSize: _fontSize - 2, color: Colors.grey[600], height: 1.0);
    final textStyle = TextStyle(fontSize: _fontSize, fontFamily: 'monospace', height: 1.0);

    // 配对行里「具体改了哪几个词」：只有 modified 行有意义；且显示文本必须仍与原始行
    // 逐字符对齐（Tab 展开会改变长度，那时放弃逐字高亮，整行底色仍在）。
    List<({int start, int end})>? diffRanges;
    if (_wordDiff && r.type == DiffRowType.modified) {
      final canMap = tokenLine != null || _tabWidth == 0;
      if (canMap) {
        final cd = _charDiffOf(r.leftText ?? '', r.rightText ?? '');
        diffRanges = left ? cd?.leftRanges : cd?.rightRanges;
      }
    }
    final diffBg = left
        ? Colors.red.withValues(alpha: isDark ? 0.34 : 0.26)
        : Colors.green.withValues(alpha: isDark ? 0.30 : 0.22);
    final hasDiff = diffRanges != null && diffRanges.isNotEmpty;
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
          Expanded(
            child: tokenLine != null
                ? Text.rich(
                    hasDiff
                        ? _tokenSpanWithDiff(tokenLine, textStyle, diffRanges, diffBg)
                        : _tokenSpan(tokenLine, textStyle),
                    maxLines: _wrap ? null : 1,
                    softWrap: _wrap,
                    overflow: TextOverflow.visible)
                : (_findQuery.isEmpty
                    ? (hasDiff
                        ? Text.rich(
                            _spansWithBg(text, textStyle, diffRanges, diffBg),
                            maxLines: _wrap ? null : 1,
                            softWrap: _wrap,
                            overflow: TextOverflow.visible)
                        : Text(text,
                            maxLines: _wrap ? null : 1,
                            softWrap: _wrap,
                            overflow: TextOverflow.visible,
                            style: textStyle))
                    : Text.rich(
                        _highlightSpan(text, textStyle, rowIndex),
                        maxLines: _wrap ? null : 1,
                        softWrap: _wrap,
                        overflow: TextOverflow.visible)),
          ),
        ],
      ),
    );
  }

  /// 把一行文本按查找词切成多段（命中处加底色）。
  TextSpan _highlightSpan(String text, TextStyle style, int rowIndex) {
    final q = _findQuery;
    if (q.isEmpty || text.isEmpty) return TextSpan(text: text, style: style);
    final base = _findCase ? text : text.toLowerCase();
    final needle = _findCase ? q : q.toLowerCase();
    if (needle.isEmpty) return TextSpan(text: text, style: style);
    final isCurrent = rowIndex >= 0 && rowIndex == _findCurrentRow;
    final bg = isCurrent
        ? const Color(0xFFFFA726).withValues(alpha: 0.65)
        : const Color(0xFFFFEB3B).withValues(alpha: 0.45);
    final spans = <TextSpan>[];
    var start = 0;
    var guard = 0;
    while (guard++ < 4000) {
      final i = base.indexOf(needle, start);
      if (i < 0) break;
      if (i > start) {
        spans.add(TextSpan(text: text.substring(start, i), style: style));
      }
      spans.add(TextSpan(
          text: text.substring(i, i + needle.length),
          style: style.copyWith(backgroundColor: bg)));
      start = i + needle.length;
    }
    if (spans.isEmpty) return TextSpan(text: text, style: style);
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: style));
    }
    return TextSpan(children: spans, style: style);
  }

  /// 这一行最终显示成什么文本（Tab 展开 + 空白可视化）。
  ///
  /// 渲染和「算宽度」必须用同一份结果，否则展开 Tab 之后两栏会一栏对齐一栏不对齐。
  String _renderText(String raw) {
    var t = raw;
    if (_tabWidth > 0 && t.contains('\t')) {
      t = t.replaceAll('\t', ' ' * _tabWidth);
    }
    if (_showSpace) t = _visualizeSpace(t);
    return t;
  }

  /// 估算两栏的内容宽度（等宽字体按 0.62 字宽，CJK 记 2 个字宽）。
  void _ensureWidths(List<DiffRow> rows) {
    final key = '$_alignedRowsKey|${_fontSize.toStringAsFixed(2)}|$_tabWidth'
        '|$_showSpace|$_syntax|${_diffLang ?? ''}';
    if (key == _widthKey) return;
    _widthKey = key;
    // 语法高亮生效时显示的是原文（Tab 不展开），宽度也要按同一份文本来算，
    // 否则两栏会一栏对齐、一栏差几列。
    final syntax = _syntaxActive;
    var maxLeft = 0;
    var maxRight = 0;
    for (final r in rows) {
      final l = _displayUnits(
          syntax ? (r.leftText ?? '') : _renderText(r.leftText ?? ''));
      final rt = _displayUnits(
          syntax ? (r.rightText ?? '') : _renderText(r.rightText ?? ''));
      if (l > maxLeft) maxLeft = l;
      if (rt > maxRight) maxRight = rt;
    }
    _leftWidth = 39 + maxLeft * _fontSize * 0.62 + 16;
    _rightWidth = 39 + maxRight * _fontSize * 0.62 + 16;
  }

  /// 空格的两种「看不见的差别」：尾随空格、Tab 与空格混用。
  /// 显示成 · 与 → 之后一眼能看出来，且不改变字符宽度（便于对齐）。
  static String _visualizeSpace(String text) {
    if (text.isEmpty) return text;
    final buf = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c == 0x20) {
        buf.write('\u00b7'); // ·
      } else if (c == 0x09) {
        buf.write('\u2192'); // →
      } else if (c == 0x00a0) {
        buf.write('\u00b7'); // 不换行空格同样是「看不见的空白」
      } else {
        buf.writeCharCode(c);
      }
    }
    return buf.toString();
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

  static int _mtimeOf(String path) {
    if (path.isEmpty) return 0;
    try {
      return File(path).statSync().modified.millisecondsSinceEpoch;
    } catch (_) {
      return 0;
    }
  }

  void _markDiskBaseline() {
    _leftMtime = _mtimeOf(_leftPath);
    _rightMtime = _mtimeOf(_rightPath);
    if (_staleDisk) setState(() => _staleDisk = false);
  }

  void _checkDiskChanged() {
    if (!mounted) return;
    if (_leftPath.isEmpty && _rightPath.isEmpty) return;
    var changed = false;
    if (_leftMtime != 0 && _mtimeOf(_leftPath) != _leftMtime) changed = true;
    if (_rightMtime != 0 && _mtimeOf(_rightPath) != _rightMtime) changed = true;
    if (changed && !_staleDisk) setState(() => _staleDisk = true);
  }

  /// 顶部「文件已在磁盘上变化」提示条：不打断操作，只给一个按钮重读。
  Widget _staleBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 2, 6, 2),
      color: cs.tertiaryContainer.withValues(alpha: 0.55),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: Row(children: [
          Icon(Icons.sync_problem, size: 15, color: cs.onTertiaryContainer),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              localizations.diffStaleDisk,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: cs.onTertiaryContainer),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => unawaited(_reloadFromDisk()),
            child: Text(localizations.diffStaleReload, style: const TextStyle(fontSize: 12)),
          ),
          IconButton(
            tooltip: localizations.diffStaleIgnore,
            icon: const Icon(Icons.close, size: 15),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => _markDiskBaseline(),
          ),
        ]),
      ),
    );
  }

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
    if (!_syncV) return;
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
  _DensityPainter(this.rows, this.isDark, this.vpStart, this.vpEnd,
      [this.marks = const <double>[]]);

  final List<DiffRow> rows;
  final bool isDark;
  final double vpStart;
  final double vpEnd;

  /// 已标记（书签）的差异块在整篇里的相对位置（0~1），画成黄色小刻度。
  final List<double> marks;

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

    // 书签刻度：不在视口里也要看得见，所以最后画、用不透明色。
    if (marks.isNotEmpty) {
      final mp = Paint()..color = Colors.amber;
      for (final m in marks) {
        final y = (m * size.height).clamp(0.0, size.height - 3);
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, 3), mp);
      }
    }
  }

  /// 手写比较：这个文件没有（也不值得为它）引入 foundation 的 listEquals。
  static bool _sameMarks(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool shouldRepaint(covariant _DensityPainter oldDelegate) =>
      oldDelegate.rows != rows ||
      oldDelegate.isDark != isDark ||
      oldDelegate.vpStart != vpStart ||
      oldDelegate.vpEnd != vpEnd ||
      !_sameMarks(oldDelegate.marks, marks);
}

/// 统一视图里的一行：符号（'  ' / '- ' / '+ '）+ 行号 + 文本。
/// 一侧的字符 / 行 / 体积 / 换行符信息，供「统计」面板展示。
class _SideInfo {
  final int lines;
  final int chars;
  final int bytes;
  final String newline;
  final String? modified;

  const _SideInfo({
    required this.lines,
    required this.chars,
    required this.bytes,
    required this.newline,
    this.modified,
  });

  String get sizeText => _TextDiffPageState._fmtSize(bytes);
}

class _UnifiedLine {
  final String sign;
  final int? num;
  final String text;
  final DiffRowType type;

  /// 对应「对齐行表」里的下标 —— 统一视图是展平的（modified 拆成两行），
  /// 但查找高亮要知道它属于哪一行，所以把来源记下来。
  final int srcRow;

  /// 字符级差异区间（相对 [text]）。统一视图里 modified 被拆成 `-`/`+` 两行，
  /// 两边的差异区间分别来自左/右原文。
  final List<({int start, int end})>? ranges;

  const _UnifiedLine(this.sign, this.num, this.text, this.type, this.srcRow,
      {this.ranges});
}

