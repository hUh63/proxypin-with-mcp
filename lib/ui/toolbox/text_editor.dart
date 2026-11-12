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

// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/component/search/finder.dart';
import 'package:proxypin/ui/component/snippet_bar.dart';
import 'package:proxypin/ui/toolbox/text_diff.dart';
// diff 引擎（DiffBlock / diffLines / buildDiffBlocks）：内联改动标记要用。
import 'package:proxypin/utils/text_diff.dart' show DiffBlock, buildDiffBlocks, diffLines;
import 'package:proxypin/utils/code_minifier.dart';
import 'package:proxypin/utils/js_compiler.dart';
import 'package:proxypin/utils/css_formatter.dart';
import 'package:proxypin/network/util/js_deobfuscator.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/code_keywords.dart';
import 'package:proxypin/utils/code_lint.dart';
import 'package:proxypin/utils/code_snippets.dart';
import 'package:proxypin/utils/code_symbols.dart';
import 'package:proxypin/utils/dir_diff.dart';
import 'package:proxypin/utils/local_history.dart';
import 'package:proxypin/utils/editor_config.dart';
import 'package:proxypin/utils/snippet_placeholders.dart';
import 'package:proxypin/ui/toolbox/workspace_tree.dart';
import 'package:proxypin/utils/todo_scanner.dart';
import 'package:proxypin/utils/merge_conflicts.dart';
import 'package:proxypin/utils/paste_indent.dart';
import 'package:proxypin/utils/string_escape.dart';
import 'package:proxypin/utils/text_align.dart';
import 'package:proxypin/utils/text_stats.dart';
import 'package:proxypin/utils/text_file_reader.dart';
import 'package:proxypin/utils/code_lint_prefs.dart';
import 'package:proxypin/ui/component/lint_rules_dialog.dart';
import 'package:proxypin/ui/toolbox/editor_console.dart';
import 'package:proxypin/utils/custom_lang.dart';
import 'package:proxypin/utils/lang_meta.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:proxypin/utils/naming_case.dart';
import 'package:proxypin/utils/text_edit_ops.dart';
import 'package:proxypin/utils/text_editor_prefs.dart';
import 'package:proxypin/ui/toolbox/text_editor_settings.dart';
import 'package:proxypin/ui/toolbox/text_editor_menus.dart';
import 'package:proxypin/utils/smart_completion.dart';
import 'package:proxypin/utils/smart_suggestions.dart';
import 'package:proxypin/utils/suggestion_stats.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:proxypin/utils/text_special_chars.dart';
import 'package:proxypin/utils/tool_snippets.dart';
import 'package:proxypin/ui/toolbox/text_editor_docs.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xml/xml.dart';
import 'package:proxypin/ui/component/lint_issue_bar.dart';
import 'package:proxypin/ui/toolbox/html_preview.dart';
import 'package:proxypin/ui/toolbox/file_preview.dart';
import 'package:proxypin/ui/toolbox/editor_ai_assist.dart';
import 'package:proxypin/ui/toolbox/editor_quick_open.dart';
import 'package:proxypin/ui/toolbox/compiler_log_page.dart';
import 'package:proxypin/ui/toolbox/editor_file_browser.dart';
import 'package:path_provider/path_provider.dart' show getApplicationDocumentsDirectory;

/// 文本编辑工具：CodeForge 编辑器 + 多文档 + 语言高亮 + 正则查找替换。
///
/// 相比早期版本新增：
/// - 多文档（侧拉栏切换 / 长按拖动排序 / 右滑操作 / 置顶 / 关闭 / 保留文件）；
/// - 撤销重做随文档保留；
/// - 不可见字符可视化（ASCII 控制字符 / Unicode 特殊字符）+ 特殊字符检测报告；
/// - 流畅模式（超长文本自动开启，关闭高亮与折叠换流畅）；
/// - 选到第 N 行、替换当前行、切换注释、换行符设置、快捷插入符号（可自定义）。
///
/// @author Hongen Wang
class TextEditorPage extends StatefulWidget {
  final String? windowId;
  final String? initialText;

  const TextEditorPage({super.key, this.windowId, this.initialText});

  @override
  State<TextEditorPage> createState() => _TextEditorPageState();
}

/// 下拉里的语言项：显示名 + re_highlight Mode；Plain Text 用 null mode。
/// [key] 是 re_highlight 的小写语言标识，用于查语言族（注释 / 格式化 / 补全）。
class _LangOption {
  final String label;
  final Mode? mode;
  final String key;

  /// 显式指定的语言族（自定义语法用；内置语言为 null，按 [key] 查表）。
  final LangFamily? family;

  /// 是否是用户自定义语法。
  final bool custom;

  /// 自定义语法里用户填写的关键字 / 内置函数 / 字面量（直接进入补全候选）。
  final List<String> customWords;

  const _LangOption(this.label, this.mode,
      [this.key = '', this.family, this.custom = false, this.customWords = const []]);
}

/// 少数语言的展示名与内核给的 name 不同，这里做覆盖。
const Map<String, String> _kLangLabelOverride = {
  'xml': 'XML / HTML',
  'plaintext': 'Plain Text',
};

/// 全部内置可高亮语言（来自 re_highlight 内置语言表，约 190 种）。
final List<_LangOption> _builtinLangs = _buildLangs();

List<_LangOption> _buildLangs() {
  final out = <_LangOption>[const _LangOption('Plain Text', null)];
  final used = <String>{'Plain Text'};
  final entries = builtinAllLanguages.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  for (final e in entries) {
    if (e.key == 'plaintext') continue;
    final base = _kLangLabelOverride[e.key] ?? e.value.name ?? e.key;
    // 内核语言表里偶有同名条目，label 重复会让「按 label 找语言」永远命中第一条，
    // 表现为切到该语言后高亮 / 补全没变化。这里追加 key 保证唯一。
    var label = base;
    if (!used.add(label)) {
      label = '$base (${e.key})';
      used.add(label);
    }
    out.add(_LangOption(label, e.value, e.key));
  }
  return out;
}

/// 内置语言 + 用户自定义语法。自定义语法存在 [CustomLangStore] 里，内容变化时
/// [CustomLangStore.revision] 自增，据此让缓存失效。
List<_LangOption>? _allLangsCache;
int _allLangsRev = -1;

List<_LangOption> get _langs {
  if (_allLangsCache == null || _allLangsRev != CustomLangStore.revision) {
    _allLangsCache = [..._builtinLangs, ..._buildCustomLangs()];
    _allLangsRev = CustomLangStore.revision;
  }
  return _allLangsCache!;
}

/// 把自定义语法映射成下拉项。
///
/// 高亮 Mode 由 [CustomLang.buildMode] 在运行时构造：
/// 用户填了关键字就自建 Mode（保证一定能高亮 + 补全），否则复用其借用的内置高亮。
List<_LangOption> _buildCustomLangs() {
  final out = <_LangOption>[];
  for (final lang in CustomLangStore.current) {
    final mode = lang.buildMode();
    // 既没有关键字、又借不到内置高亮时跳过，避免留下「点了没反应」的死条目。
    if (mode == null && lang.isEmptyHighlight) continue;
    out.add(_LangOption(lang.name, mode, lang.baseKey ?? '', lang.family, true, lang.allWords));
  }
  return out;
}

/// 新文件的保留偏好。
/// 一个符号（类 / 方法 / 命名空间…）。「转到符号」与顶部面包屑共用。
typedef _SymbolItem = ({String name, String kind, int line, int offset, int indent});

enum _RetainMode { ask, always, never }

/// 换行符写出策略（编辑器内部永远是 \n）。
enum _Newline { lf, crlf, cr }

/// 超过该字符数自动开启流畅模式（与 MT 的 20 万一致）。
const int _kSmoothThreshold = 200000;

/// 不可见字符高亮上限（超出只着色前 N 个，避免超长文本卡顿）。
const int _kMaxHighlights = 3000;

const String _kPrefRetainMode = 'text_editor_retain_mode_v1';
const String _kPrefNewline = 'text_editor_newline_v1';
const String _kPrefSmoothKeepIme = 'text_editor_smooth_keep_ime_v1';

class _TextEditorPageState extends State<TextEditorPage> {
  final EditorDocuments _docs = EditorDocuments.instance;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  EditorDocument? _doc;

  bool _wrap = true;
  bool _smooth = false;

  /// 本会话里已经确认过「就这么打开」的大文件（path）。
  final Set<String> _bigFileConfirmed = <String>{};

  /// 内容变化后重新嗅探语言的防抖定时器。
  Timer? _sniffTimer;

  /// 上一次变化 *之前* 的文本（自动成对要用它判断「是不是只多了一个字符」）。
  String? _lastBeforeChange;

  /// 流畅模式是「因为文件太大自动打开的」——切到小文档时自动关掉，
  /// 免得用户改完大文件之后，所有小文件也跟着一直关着高亮。
  bool _smoothAuto = false;

  /// 没有文档时给 AnimatedBuilder 用的空监听源。
  static final ChangeNotifier _noFind = ChangeNotifier();

  /// 流畅模式是否保留输入法候选建议。默认 true（不牺牲输入法）；
  /// 关掉后流畅模式会同时禁用输入法建议，换取超长文本下的更高流畅度。
  bool _smoothKeepIme = true;
  bool _readOnly = false;
  bool _showAscii = false;
  bool _showUnicode = false;

  // 语法检查 + 控制台。
  /// 检查结果挂在文档上（切回来不用重跑）。
  LintReport? get _lint => _doc?.lint;
  bool _lintChecking = false;
  Timer? _lintTimer;

  /// 长按右侧分布条时显示的「第几行」浮标（1 基）；null = 不显示。
  int? _rulerLine;
  Timer? _rulerTimer;
  bool _lintEnabled = true;
  bool _inLint = false;

  /// 被用户关掉的规则（持久化在 prefs 里）。
  Set<String> _disabledRules = <String>{};

  /// 被用户关掉的严重程度（问题栏与底部「问题」面板共用一份，和 VS 一样是面板级筛选）。
  final Set<LintSeverity> _hiddenSeverities = <LintSeverity>{};

  /// 严重程度筛选会记住（VS 里面板筛选也是全局状态，重开还在）。
  static const String _hiddenSevKey = 'text_editor_hidden_sev_v1';

  /// 已转换好的波浪线诊断，以及它对应的那份检查结果。
  /// 换行高亮也会走 [_refreshDecorations]，有缓存就不用每次都重算一遍全文边界。
  LintReport? _diagReport;
  List<DiagnosticLine> _diagLines = const <DiagnosticLine>[];
  bool _diagRepaintScheduled = false;
  bool _consoleOpen = false;

  /// 上一次「为了弹补全」而记录的光标位置（避免光标每动一下就重算）。
  int _lastSuggestOffset = -1;
  // 底部面板默认就是「控制台」——问题改在文本下方的窄栏里看。
  EditorConsoleTab _consoleTab = EditorConsoleTab.console;

  /// 当前文档有没有未写回磁盘的修改。
  ///
  /// 真正的状态挂在 [EditorDocument] 上：多文档时每份文件各记各的，
  /// 切文档不会把别人的「已修改」标记抹掉（以前就是这么丢的）。
  bool get _dirty => _doc?.dirty ?? false;
  set _dirty(bool value) => _doc?.dirty = value;
  int? _gutterAnchorLine;

  // 光标导航历史（「上一处 / 下一处位置」）。
  /// 导航历史按文档存（见 [EditorDocument.navStack]），这里只是转发。
  /// 切文档后「后退」不会跳到另一份文件的同名偏移上。
  List<int> get _navStack => _doc?.navStack ?? const <int>[];

  int get _navIndex => _doc?.navIndex ?? -1;

  set _navIndex(int value) {
    final doc = _doc;
    if (doc != null) doc.navIndex = value;
  }
  int _lastNavOffset = -1;
  Timer? _navTimer;
  bool _suppressNav = false;

  // 读写磁盘文件时使用的编码：文档自己的优先，否则跟随全局偏好。
  EditorEncoding get _encoding => _encodingOf(_doc);

  EditorEncoding _encodingOf(EditorDocument? doc) {
    final name = doc?.encodingName ?? _prefs.encodingName;
    return kEncodings.firstWhere((e) => e.name == name, orElse: () => defaultEncoding);
  }

  /// 某份文档要写回的换行符（打开时检测到的值）。
  String _newlineCharsOf(EditorDocument? doc) {
    final nl = doc?.newline;
    return (nl == '\r\n' || nl == '\r') ? nl! : '\n';
  }

  /// 把文本统一成目标换行符。
  ///
  /// 先全部折成 `\n` 再展开：混合换行（半 CRLF 半 LF）的文件直接 replaceAll
  /// 会被反复替换，出现 `\r\r\n` 这种脏东西。
  String _applyNewline(String text, String nl) {
    final lf = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return nl == '\n' ? lf : lf.replaceAll('\n', nl);
  }

  // 文件外部改动 / 删除检测。
  Timer? _fileWatchTimer;
  int? _lastFileMtime;
  bool _fileMissing = false;

  // 双指缩放。
  final Map<int, Offset> _pointers = <int, Offset>{};
  double? _pinchBaseDistance;
  double _pinchStartFontSize = 13;
  int _lastPinchSize = 13;

  /// 这次双指手势是否已经「确认」为捏合缩放。
  ///
  /// 双指平移（手机上很自然的滚动方式）时，两指间距本来就有百分之几的抖动，
  /// 没有这道门槛就是「想滚动，结果字号变了」。
  bool _pinching = false;

  _RetainMode _retainMode = _RetainMode.never;
  _Newline _newline = _Newline.lf;

  String _lastText = '';

  /// 自动保存（VS Code 的 files.autoSave = afterDelay），默认关。
  bool _autoSave = false;
  Timer? _autoSaveTimer;
  static const Duration _autoSaveDelay = Duration(seconds: 2);
  static const String _kPrefAutoSave = 'text_editor_autosave_v1';
  bool _confirmingExit = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  CodeForgeController? get _controller => _doc?.controller;

  InvisibleCharsStyle get _invisibleCharsStyle => InvisibleCharsStyle(
        ascii: _showAscii,
        unicode: _showUnicode,
        hideSingleSpace: _prefs.hideSingleSpace,
        softWrapArrow: _prefs.softWrapArrow,
      );

  TextEditorPrefs get _prefs => TextEditorPrefsStore.notifier.value;

  /// 候选副标题的缓存键与结果（`语言|key|词数`）。
  String? _detailCacheKey;
  Map<String, String> _detailCache = const <String, String>{};

  /// 给每个候选配一句小字：「关键字」或「内置」。
  ///
  /// 文档里自己写的名字不在表里，也就没有小字 —— 这正好是想要的区分：
  /// 有标签的是语言自带的名字，没标签的是这个文件自己的名字。
  Map<String, String> _suggestionDetailsOf(String langLabel, String langKey, List<String> words) {
    final key = '$langLabel|$langKey|${words.length}';
    if (_detailCacheKey == key) return _detailCache;
    final loc = localizations;
    final keyword = loc.editorKindKeyword;
    final builtin = loc.editorKindBuiltin;
    final map = <String, String>{};
    for (final word in words) {
      map[word] = CodeKeywords.kindOf(word) == CompletionKind.keyword ? keyword : builtin;
    }
    _detailCacheKey = key;
    _detailCache = map;
    return map;
  }

  _LangOption get _lang =>
      _langs.firstWhere((l) => l.label == (_doc?.langLabel ?? 'Plain Text'), orElse: () => _langs.first);

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    // 自定义语法表是异步加载的，加载完刷新一次语言列表。
    CustomLangStore.instance.then((_) {
      if (mounted) setState(() {});
    });
    SmartCompletion.load();
    unawaited(_loadLintRules());
    unawaited(_loadHiddenSeverities());
    unawaited(SuggestionStats.ensureLoaded());
    unawaited(LintPrefs.ensureLoaded());
    SmartCompletion.enabled.addListener(_onSmartCompletionChanged);
    TextEditorPrefsStore.load();
    TextEditorPrefsStore.notifier.addListener(_onEditorPrefsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
    if (Platforms.isDesktop()) {
      HardwareKeyboard.instance.addHandler(_onKeyEvent);
    }
    // 纵向滚动位置 → minimap 视口框 / 粘性滚动。
    _vScroll.addListener(_onVScroll);
  }

  @override
  void dispose() {
    _vScroll.removeListener(_onVScroll);
    _vScroll.dispose();
    _navTimer?.cancel();
    _autoSaveTimer?.cancel();
    _fileWatchTimer?.cancel();
    _lintTimer?.cancel();
    _rulerTimer?.cancel();
    _sniffTimer?.cancel();
    _diffTimer?.cancel();
    _docScroll.dispose();
    _tabScroll.dispose();
    _scrollTick.dispose();
    _stickyTrail.dispose();
    SmartCompletion.enabled.removeListener(_onSmartCompletionChanged);
    TextEditorPrefsStore.notifier.removeListener(_onEditorPrefsChanged);
    _doc?.controller.removeListener(_onControllerChanged);
    _doc?.undoController.removeListener(_onUndoChanged);
    if (Platforms.isDesktop()) {
      HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    }
    super.dispose();
  }

  void _onSmartCompletionChanged() {
    if (mounted) setState(() {});
  }

  void _onEditorPrefsChanged() {
    if (mounted) setState(() {});
    _restartFileWatch();
  }

  bool _onKeyEvent(KeyEvent event) {
    // Ctrl/Cmd+Shift+P：命令面板（VS Code 的同款快捷键，外接键盘时比找按钮快）。
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyP &&
        HardwareKeyboard.instance.isShiftPressed &&
        (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)) {
      unawaited(_showCommandPalette());
      return true;
    }
    // F8 / Shift+F8：跳到下一处 / 上一处问题（桌面全平台）。
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f8) {
      if ((_lint?.diagnostics.isNotEmpty ?? false)) {
        _jumpIssue(!HardwareKeyboard.instance.isShiftPressed);
        return true;
      }
      return false;
    }
    // 下面这组是 VS 的常用快捷键，外接键盘时全靠它（手机上没有）。
    if (event is KeyDownEvent) {
      final kb = HardwareKeyboard.instance;
      final ctrl = kb.isControlPressed || kb.isMetaPressed;
      final shift = kb.isShiftPressed;
      final alt = kb.isAltPressed;
      final key = event.logicalKey;
      // Tab / Shift+Tab：编辑器里 Tab 只能用来缩进，不能切焦点。
      if (key == LogicalKeyboardKey.tab && !ctrl && !alt) {
        // 片段占位符还没走完时，Tab 是「下一处占位符」（VS Code 行为），不是缩进。
        if (!shift && _snippetStops.isNotEmpty) {
          _nextSnippetStop();
          return true;
        }
        _indentLines(outdent: shift);
        return true;
      }
      // Esc：放弃剩下的占位符跳转（和 VS Code 一致）。
      if (key == LogicalKeyboardKey.escape) {
        if (_snippetStops.isNotEmpty) {
          _snippetStops.clear();
          return true;
        }
        return false;
      }
      if (ctrl && key == LogicalKeyboardKey.keyS) {
        // Ctrl+Alt+S = 保存全部（VS Code 的 Ctrl+K S 在移动/外接键盘上不好按）
        if (alt) {
          unawaited(_saveAllDirty());
        } else {
          unawaited(_download());
        }
        return true;
      }
      // Ctrl+Alt+A：AI 辅助（选中代码 → 解释/注释/审查/测试/改写）
      if (ctrl && alt && key == LogicalKeyboardKey.keyA) {
        unawaited(_showAiAssist());
        return true;
      }
      if (ctrl && key == LogicalKeyboardKey.keyF) {
        _toggleFind();
        return true;
      }
      // Ctrl+P：快速打开同目录文件（VS/VS Code 同款）
      if (ctrl && key == LogicalKeyboardKey.keyP) {
        unawaited(_showQuickOpen());
        return true;
      }
      // Ctrl+`：切到「终端」（VS Code 同款），再按一次关掉。
      if (ctrl && key == LogicalKeyboardKey.backquote) {
        if (_consoleOpen) {
          setState(() => _consoleOpen = false);
        } else {
          _openConsole(EditorConsoleTab.console);
        }
        return true;
      }
      // Ctrl+Shift+`：切到「问题」页签。
      if (ctrl && shift && key == LogicalKeyboardKey.backquote) {
        _openConsole(EditorConsoleTab.problems);
        return true;
      }
      if (ctrl && key == LogicalKeyboardKey.keyG) {
        unawaited(_selectToLine());
        return true;
      }
      if (ctrl && key == LogicalKeyboardKey.slash) {
        _toggleComment();
        return true;
      }
      // Ctrl+L：选中当前行（VS 同款；带选区时选到整行范围）。
      if (ctrl && !shift && !alt && key == LogicalKeyboardKey.keyL) {
        _selectCurrentLine();
        return true;
      }
      // Ctrl+Shift+K：删除当前行。
      if (ctrl && shift && key == LogicalKeyboardKey.keyK) {
        _lineOp('delete');
        return true;
      }
      // Shift+Alt+↑ / ↓：把当前行复制到上/下一行。
      if (shift && alt && (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown)) {
        _duplicateLine(key == LogicalKeyboardKey.arrowUp);
        return true;
      }
      // Ctrl+Alt+↑ / ↓：在上/下一行的同列加一个光标（VS 同款多光标）。
      if (ctrl &&
          alt &&
          (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown)) {
        _addCursorAtLine(key == LogicalKeyboardKey.arrowUp ? -1 : 1);
        return true;
      }
      // Alt+↑ / Alt+↓：上下移动当前行。
      if (alt && (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown)) {
        _lineOp(key == LogicalKeyboardKey.arrowUp ? 'up' : 'down');
        return true;
      }
    }
    if (widget.windowId == null) return false;
    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      HardwareKeyboard.instance.removeHandler(_onKeyEvent);
      WindowController.fromWindowId(widget.windowId!).close();
      return true;
    }
    return false;
  }

  Future<void> _loadPrefs() async {
    final raw = await SharedPreferencesAsync().getInt(_kPrefRetainMode);
    final nl = await SharedPreferencesAsync().getString(_kPrefNewline);
    final keepIme = await SharedPreferencesAsync().getBool(_kPrefSmoothKeepIme);
    final autoSave = await SharedPreferencesAsync().getBool(_kPrefAutoSave);
    final ws = await SharedPreferencesAsync().getString(_workspaceKey);
    final recent = await SharedPreferencesAsync().getStringList(_recentFilesKey);
    if (!mounted) return;
    setState(() {
      if (raw != null && raw >= 0 && raw < _RetainMode.values.length) {
        _retainMode = _RetainMode.values[raw];
      }
      if (nl != null) {
        _newline = _Newline.values.firstWhere((e) => e.name == nl, orElse: () => _Newline.lf);
      }
      if (keepIme != null) _smoothKeepIme = keepIme;
      if (autoSave != null) _autoSave = autoSave;
      if (ws != null && ws.isNotEmpty) _workspace = ws;
      if (recent != null && recent.isNotEmpty) {
        _recentFiles = recent.take(20).toList();
      }
    });
    // 「语法」菜单的显示勾选存的是语言标签。语言表改过名 / 导入了别的版本的配置时，
    // 这些标签可能一个都对不上 —— 那样 `_visibleLangs` 会静默回退成全量，每次 build
    // 白算一遍。这里清掉失效项（清空即「全部启用」，与默认语义一致）。
    final enabled = _prefs.enabledLangs;
    if (enabled.isNotEmpty) {
      final known = _langs.where((l) => !l.custom).map((l) => l.label).toSet();
      // 失效的标签逐个清掉（不只是「全失效才清空」）：语言表改过名之后，
      // 残留项会让「语法文件管理」里出现勾了就再也点不掉的名字。
      final alive = enabled.where(known.contains).toList();
      if (alive.length != enabled.length) {
        unawaited(TextEditorPrefsStore.update(_prefs.copyWith(
          enabledLangs: alive.isEmpty ? const <String>[] : alive,
        )));
      }
    }
  }

  Future<void> _saveRetainMode() async {
    await SharedPreferencesAsync().setInt(_kPrefRetainMode, _retainMode.index);
  }

  /// 自动保存：改动后 [_autoSaveDelay] 内没有新输入就写回原路径。
  ///
  /// 只对「已经落到磁盘上的文档」生效——没路径的文档不能自动弹另存为，
  /// 那会在用户打字时突然跳一个文件选择框。
  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    if (!_autoSave) return;
    _autoSaveTimer = Timer(_autoSaveDelay, () {
      final doc = _doc;
      if (!mounted || doc == null || !doc.dirty) return;
      final path = doc.path;
      if (path == null || path.isEmpty) return;
      unawaited(_saveDoc(doc));
    });
  }

  Future<void> _saveAutoSave() async {
    await SharedPreferencesAsync().setBool(_kPrefAutoSave, _autoSave);
  }

  Future<void> _saveSmoothKeepIme() async {
    await SharedPreferencesAsync().setBool(_kPrefSmoothKeepIme, _smoothKeepIme);
  }

  Future<void> _saveNewline() async {
    await SharedPreferencesAsync().setString(_kPrefNewline, _newline.name);
  }

  // ---------- 文档管理 ----------

  Future<void> _bootstrap() async {
    await _docs.ensureRestored();
    if (!mounted) return;

    if (widget.initialText != null) {
      final doc = _docs.create(name: localizations.editorUntitled, text: widget.initialText!);
      _activate(doc);
      return;
    }

    final existing = _docs.byId(_docs.activeId ?? '') ?? (_docs.isEmpty ? null : _docs.docs.first);
    if (existing != null) {
      _activate(existing);
    } else {
      final doc = _docs.create(name: localizations.editorUntitled);
      doc.newline = _newlineChars(_newline);
      _activate(doc);
    }
  }

  void _activate(EditorDocument doc) {
    if (identical(_doc, doc)) return;
    _doc?.controller.removeListener(_onControllerChanged);
    _doc?.undoController.removeListener(_onUndoChanged);

    setState(() {
      _doc = doc;
      _docs.activeId = doc.id;
      _lastText = doc.text;
      _caretLine = -1;
      _caretOffset = -1;
      // 换文档后「上次触发补全的位置」不再有意义，否则同偏移量会被误判成重复。
      _lastSuggestOffset = -1;
      // 换文档后波浪线要按新文档重算。
      _diagReport = null;
      _diagLines = const <DiagnosticLine>[];
      // 片段占位符是绑定在「刚才插入的那段文本」上的，换文档就没意义了。
      _snippetStops.clear();
      // 多选是「针对某几个位置」的状态，换文档就失效了。
      _multiSel.clear();
      _multiWord = '';
      _sniffTimer?.cancel();
      if (_smoothAuto) {
        final limit = _prefs.autoPageSize > 0 ? _prefs.autoPageSize : _kSmoothThreshold;
        if (doc.text.length <= limit) {
          _smooth = false;
          _smoothAuto = false;
        }
      }
    });

    doc.controller.addListener(_onControllerChanged);
    // 从缓存恢复的文档回到上次的光标位置。只用一次：之后以 controller 自己
    // 的 selection 为准（切标签来回时不该把光标拽回老地方）。
    if (doc.lastCaret >= 0) {
      final offset = doc.lastCaret.clamp(0, doc.text.length);
      doc.lastCaret = -1;
      try {
        doc.controller.selection = TextSelection.collapsed(offset: offset);
        doc.controller.scrollToLine(_lineOfOffset(doc.text, offset));
      } catch (_) {}
    }
    doc.undoController.addListener(_onUndoChanged);
    _restartFileWatch();
    // 切回旧文档：直接恢复上次的诊断标记，避免「重新检查」造成的闪动。
    if (doc.lint != null) {
      _refreshDecorations();
    } else {
      _clearLintDecorations();
      _scheduleLint();
    }
    // 标签条上可能有十几个文档，切过去要保证那个标签在可视区里。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollTabIntoView();
    });
    // 当前行高亮跟着光标走，切文档后要先算一次（缓存刚被清成 -1）。
    _syncCaretLine();
    _refreshExtraHighlights();
    _refreshSymbolCache();
    // 换文档：粘性滚动的「上次顶部行」失效，重算一次（否则条上还挂着上一篇的类名）。
    _stickyLine = -1;
    _syncSticky();
  }

  // ---------- 外部改动 / 删除检测 ----------

  void _restartFileWatch() {
    _fileWatchTimer?.cancel();
    _lastFileMtime = null;
    _fileMissing = false;
    if (!_prefs.checkFileModified) return;
    _fileWatchTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkFileState(),
    );
  }

  Future<void> _checkFileState() async {
    final doc = _doc;
    final path = doc?.path;
    if (doc == null || path == null || path.isEmpty || !mounted) return;
    final file = File(path);
    try {
      if (!await file.exists()) {
        if (!_fileMissing && mounted) {
          _fileMissing = true;
          _toast(localizations.editorFileMissing);
        }
        return;
      }
      final mtime = (await file.stat()).modified.millisecondsSinceEpoch;
      if (_lastFileMtime == null) {
        _lastFileMtime = mtime;
        return;
      }
      if (mtime != _lastFileMtime) {
        _lastFileMtime = mtime;
        if (mounted) _toast(localizations.editorFileChanged);
      }
    } catch (_) {
      // 忽略瞬时错误（文件正在被写入等）。
    }
  }

  /// 一次改写涉及哪一段（公共前缀 + 公共后缀之外的部分）。
  ///
  /// 只用来平移书签，所以不追求精确到「哪几次编辑」，一次净变化就够。
  static ({int start, int removed, int inserted})? _diffSpan(String before, String after) {
    if (before == after) return null;
    final minLen = before.length < after.length ? before.length : after.length;
    var prefix = 0;
    while (prefix < minLen && before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < minLen - prefix &&
        before.codeUnitAt(before.length - 1 - suffix) ==
            after.codeUnitAt(after.length - 1 - suffix)) {
      suffix++;
    }
    return (
      start: prefix,
      removed: before.length - prefix - suffix,
      inserted: after.length - prefix - suffix,
    );
  }

  /// 把「改动前的偏移」映射到「改动后的偏移」。
  static int _mapOffset(int offset, ({int start, int removed, int inserted}) d) {
    if (offset <= d.start) return offset;
    if (offset >= d.start + d.removed) return offset + d.inserted - d.removed;
    // 落在被删掉的那段里：收到改动起点，别丢。
    return d.start;
  }

  /// 书签上下文用 `左20\u0000右20` 存：单看左边，「}`」这种行根本区分不开。
  static ({String left, String right}) _splitHead(String head) {
    final at = head.indexOf('\u0000');
    if (at < 0) return (left: head, right: '');
    return (left: head.substring(0, at), right: head.substring(at + 1));
  }

  /// 按上下文在新文本里找回书签位置：左右两侧都要对得上，多个候选取离 [near] 最近的。
  static int? _locateByHead(String text, String head, int near) {
    final parts = _splitHead(head);
    if (parts.left.isEmpty && parts.right.isEmpty) return null;
    final needle = parts.left.isNotEmpty ? parts.left : parts.right;
    var best = -1;
    var bestDist = 0;
    var at = text.indexOf(needle);
    // 出现次数不可能太多；给个上限防止极端文本（同一字符重复）里白跑。
    var guard = 0;
    while (at >= 0 && guard++ < 200) {
      final cand = parts.left.isNotEmpty ? at + parts.left.length : at;
      final okRight = parts.right.isEmpty || text.startsWith(parts.right, cand);
      if (okRight) {
        final dist = (cand - near).abs();
        if (best < 0 || dist < bestDist) {
          best = cand;
          bestDist = dist;
        }
      }
      at = text.indexOf(needle, at + 1);
    }
    return best < 0 ? null : best;
  }

  /// 记下每个书签前面的 20 个字符（整份替换后靠它找回位置）。
  void _syncBookmarkHeads(EditorDocument doc) {
    final text = doc.text;
    doc.bookmarkHeads.clear();
    for (final o in doc.bookmarks) {
      final mid = o.clamp(0, text.length);
      final start = (mid - 20).clamp(0, mid);
      final end = (mid + 20).clamp(mid, text.length);
      doc.bookmarkHeads[o] = '${text.substring(start, mid)}\u0000${text.substring(mid, end)}';
    }
  }

  /// 整份替换之后（重载 / 换编码）：按上下文重新定位书签，找不到就收到最近的合法偏移。
  void _remapBookmarksByHead(EditorDocument doc) {
    if (doc.bookmarks.isEmpty) return;
    final text = doc.text;
    final heads = Map<int, String>.from(doc.bookmarkHeads);
    final moved = <int>{};
    for (final o in doc.bookmarks) {
      final head = heads[o];
      if (head != null && head.isNotEmpty) {
        final at = _locateByHead(text, head, o);
        if (at != null) {
          moved.add(at);
          continue;
        }
      }
      moved.add(o.clamp(0, text.length));
    }
    doc.bookmarks
      ..clear()
      ..addAll(moved);
    _syncBookmarkHeads(doc);
  }

  void _onUndoChanged() {
    if (mounted) setState(() {});
  }

  /// 自动补全成对符号（VS 的 auto closing）。
  ///
  /// 只在「这次变化正好是敲入一个开符号、光标紧跟其后」时补一次：
  /// 粘贴整段、选中替换、输入法组合都不碰，避免把用户的文本改坏。
  void _maybeAutoPair() {
    if (!_prefs.autoPair) return;
    final controller = _doc?.controller;
    if (controller == null) return;
    final text = controller.text;
    final prev = _lastBeforeChange ?? _lastText;
    if (text.length != prev.length + 1) return;
    final sel = controller.selection;
    if (!sel.isValid || !sel.isCollapsed) return;
    final caret = sel.baseOffset;
    if (caret <= 0 || caret > text.length) return;
    final ch = text.substring(caret - 1, caret);
    const pairs = {'(': ')', '[': ']', '{': '}', '<': '>', '"': '"', "'": "'"};
    final close = pairs[ch];
    if (close == null) return;
    // 光标后面已经有闭合符号（用户自己打的）就不重复插入。
    if (caret < text.length && text.substring(caret, caret + 1) == close) return;
    controller.replaceRange(caret, caret, close);
    controller.selection = TextSelection.collapsed(offset: caret);
  }

  /// 选中当前词/选区在全文的所有出现（VS 的 Select All Occurrences）。
  void _selectAllOccurrences() {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final sel = controller.selection;
    String word;
    if (sel.isValid && sel.start != sel.end) {
      word = text.substring(sel.start.clamp(0, text.length), sel.end.clamp(0, text.length));
    } else {
      final range = _wordRangeAt(text, sel.isValid ? sel.start : 0);
      word = text.substring(range.start, range.end);
    }
    if (!_isSymbolName(word)) {
      _toast(localizations.editorNoAvailableCommand);
      return;
    }
    final ranges = <({int start, int end})>[];
    var at = text.indexOf(word);
    while (at >= 0 && ranges.length < 2000) {
      ranges.add((start: at, end: at + word.length));
      at = text.indexOf(word, at + word.length);
    }
    if (ranges.isEmpty) return;
    _multiSel
      ..clear()
      ..addAll(ranges);
    _multiWord = word;
    controller.selection = TextSelection(baseOffset: ranges.first.start, extentOffset: ranges.first.end);
    _refreshExtraHighlights();
    setState(() {});
    _toast(localizations.editorMultiSelCount('${ranges.length}'));
  }

  /// 语言是嗅探来的：内容首行/结构变了（例如本来空的 .txt 里粘进一段 JSON），
  /// 语言要跟着变。只对 `doc.langSniffed` 生效，用户手动选的语言不动。
  void _maybeResniffLanguage() {
    final doc = _doc;
    if (doc == null || !doc.langSniffed || !mounted) return;
    final next = _sniffLanguage(doc.text) ?? 'Plain Text';
    if (next == doc.langLabel) {
      doc.plainSniffStreak = 0;
      return;
    }
    if (next == 'Plain Text') {
      doc.plainSniffStreak++;
      // 还没到 3 次就先不动：粘进一段话就把高亮掉掉，编辑过程中会一直闪。
      if (doc.plainSniffStreak < 3) return;
      // 连续三次都判不出语言：锁定为纯文本，别再嗅探了 —— 否则
      // 「JSON → 大白话 → JSON」这种反复编辑会让语言一直抖。
      setState(() {
        doc.langLabel = 'Plain Text';
        doc.langSniffed = false;
        doc.plainSniffStreak = 0;
      });
      return;
    } else {
      doc.plainSniffStreak = 0;
    }
    setState(() {
      doc.langLabel = next;
      // 语言变了，补全表与 lint 规则都要跟着换。
      final key = _langs.firstWhere((l) => l.label == next, orElse: () => _langs.first).key;
      doc.controller.extraSuggestions = CodeKeywords.forLanguage(next, key);
    });
  }

  void _onControllerChanged() {
    final text = _doc?.text ?? '';
    final changed = text != _lastText;
    if (changed) {
      final before = _lastText;
      // 书签跟着代码走：按「这次改了哪一段」平移，别让它漂到隔壁行。
      final bookmarks = _doc?.bookmarks;
      if (bookmarks != null && bookmarks.isNotEmpty) {
        final delta = _diffSpan(_lastText, text);
        if (delta != null) {
          final moved = <int>{};
          // 整份替换（粘贴全文、重新加载）：按偏移平移只会全部挤到起点，
          // 改成「按书签前的上下文找」。
          final bigChange = delta.removed > 2000 || delta.inserted > 2000;
          final heads0 = _doc?.bookmarkHeads;
          final movedHeads = <int, String>{};
          for (final offset in bookmarks) {
            final head = heads0?[offset];
            if (bigChange && head != null && head.isNotEmpty) {
              final at = _locateByHead(text, head, offset);
              if (at != null) {
                moved.add(at);
                movedHeads[at] = head;
                continue;
              }
            }
            final dest = _mapOffset(offset, delta);
            moved.add(dest);
            if (head != null) movedHeads[dest] = head;
          }
          bookmarks
            ..clear()
            ..addAll(moved);
          // 只在「大改动」时重新取上下文：每敲一个字都重建一遍是白活，
          // 而旧上下文只要还在新文本里就能用来定位。
          if (heads0 != null) {
            heads0
              ..clear()
              ..addAll(movedHeads);
            if (bigChange) {
              final doc0 = _doc;
              if (doc0 != null) _syncBookmarkHeads(doc0);
            }
          }
        }
      }
      _rememberEdit(_doc?.controller.selection.extentOffset ?? 0);
      _lastText = text;
      _lastBeforeChange = text;
      if (!_dirty) setState(() => _dirty = true);
      // 只有内容变化才重跑检查：光标移动、选区变化不触发。
      _scheduleLint();
      // 内联改动标记（相对磁盘）也要跟着更新：同一行内打字不跨行，
      // 光靠「光标行变化」那条路刷不出来。
      _scheduleDiffRefresh();
      _lastBeforeChange = before;
      _maybeAutoPair();
      _scheduleAutoSave();
      // 语言是嗅探来的话，内容变了可能就该换语言（空 .txt 里粘进 JSON）。
      if (_doc?.langSniffed ?? false) {
        _sniffTimer?.cancel();
        _sniffTimer = Timer(const Duration(milliseconds: 900), _maybeResniffLanguage);
      }
    }

    // 光标移动防抖后记录位置，供「上一处 / 下一处位置」使用。
    final controller = _doc?.controller;
    if (controller != null) {
      final off = controller.selection.baseOffset;
      if (off >= 0 && off != _lastNavOffset) {
        _lastNavOffset = off;
        _navTimer?.cancel();
        _navTimer = Timer(const Duration(milliseconds: 700), () => _pushNav(off));
      }
      // 文本没变、只是光标动了（点别处再点回来）：光标前是个词就重新弹补全。
      // 不这么做的话，弹窗一旦被点掉就再也不回来，用户得重新打一个字才看得见。
      if (!changed &&
          off > 0 &&
          off != _lastSuggestOffset &&
          off <= text.length &&
          SmartCompletion.enabled.value &&
          !_smooth) {
        _lastSuggestOffset = off;
        final before = text.substring(off - 1, off);
        if (RegExp(r'[\w\$]').hasMatch(before)) {
          controller.requestSuggestions();
        }
      }
      if (_prefs.magnifier && mounted) setState(() {});
      // 当前行高亮（VS Code 的 current line）：只在跨行时重绘。
      _syncCaretLine();
      // 括号配对 / 当前词出现处（内核的 extraHighlights 通道）。
      _refreshExtraHighlights();
    }
  }

  // ---------- 语法检查 / 控制台 ----------

  /// 当前语言是不是编程语言（决定「控制台」入不出现）。
  bool get _programming {
    final doc = _doc;
    if (doc == null) return false;
    return CodeLint.profileOf(doc.langLabel, _lang.key).programming;
  }

  /// 当前语言是否能真跑代码（手机端只有内置 JS 引擎）。
  bool get _jsBackend {
    final key = _lang.key;
    return key == 'javascript' || key == 'typescript' || key == 'coffeescript';
  }

  void _scheduleLint() {
    if (!_lintEnabled || !_programming) return;
    // 流畅模式刻意关掉了高亮/折叠，再挂一层全量扫描等于白费力气；
    // 这种情况下只在打开「问题」面板时按需检查。
    if (_smooth && !_consoleOpen) return;
    _lintTimer?.cancel();
    _lintTimer = Timer(const Duration(milliseconds: 650), _runLint);
  }

  /// 规则开关的存储键：优先用 re_highlight 的 key（csharp / dart / python…），
  /// 自定义语言没有 key 时用规范化后的 label。
  String get _langRuleKey {
    final key = _lang.key.trim().toLowerCase();
    if (key.isNotEmpty) return key;
    final label = _lang.label.trim().toLowerCase();
    if (label.isEmpty) return LintPrefs.globalKey;
    final slug = label.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return slug.isEmpty ? label : slug;
  }

  Future<void> _loadLintRules() async {
    try {
      await LintPrefs.ensureLoaded();
      if (!mounted) return;
      final next = LintPrefs.disabledFor(_langRuleKey);
      if (next.length == _disabledRules.length && next.containsAll(_disabledRules)) return;
      setState(() => _disabledRules = next);
      _doc?.lint = null;
      _scheduleLint();
    } catch (_) {
      // 偏好读取失败就按「全部规则开启」跑
    }
  }

  Future<void> _loadHiddenSeverities() async {
    try {
      final raw = await SharedPreferencesAsync().getStringList(_hiddenSevKey);
      if (raw == null || raw.isEmpty || !mounted) return;
      final next = <LintSeverity>{};
      for (final name in raw) {
        for (final sev in LintSeverity.values) {
          if (sev.name == name) next.add(sev);
        }
      }
      if (next.isEmpty) return;
      setState(() {
        _hiddenSeverities
          ..clear()
          ..addAll(next);
      });
    } catch (_) {
      // 读不到就按「全部显示」处理
    }
  }

  Future<void> _saveHiddenSeverities() async {
    try {
      await SharedPreferencesAsync().setStringList(
        _hiddenSevKey,
        _hiddenSeverities.map((e) => e.name).toList(),
      );
    } catch (_) {
      // 存不上不影响使用
    }
  }

  Future<void> _openLintRules() async {
    final result = await showLintRulesDialog(
      context,
      disabled: _disabledRules,
      languageLabel: _doc?.langLabel ?? '',
      hasOverride: LintPrefs.hasOverride(_langRuleKey),
    );
    if (result == null || !mounted) return;
    if (result.applyToAll) {
      await LintPrefs.applyToAll(result.disabled);
    } else {
      await LintPrefs.setFor(_langRuleKey, result.disabled);
    }
    if (!mounted) return;
    setState(() => _disabledRules = LintPrefs.disabledFor(_langRuleKey));
    _doc?.lint = null;
    _runLint();
  }

  /// 把控制台的结果插到光标处（替换选区）。
  void _insertText(String text) {
    if (text.isEmpty) return;
    final controller = _doc?.controller;
    if (controller == null) return;
    final selection = controller.selection;
    final length = controller.text.length;
    final start = selection.start < 0 ? length : selection.start.clamp(0, length);
    final end = selection.end < 0 ? start : selection.end.clamp(start, length);
    controller.replaceRange(start, end, text);
    controller.selection = TextSelection.collapsed(offset: start + text.length);
  }

  void _runLint() {
    final doc = _doc;
    if (doc == null || !mounted || _inLint || !_programming) return;
    final text = doc.text;
    if (text.length > CodeLint.maxCheckLength) {
      doc.lint = null;
      setState(() => _lintChecking = false);
      _clearLintDecorations();
      return;
    }
    _inLint = true;
    // 纯 CPU 线性扫描，2MB 以内几十毫秒，同步跑即可（省掉跨 isolate 拷贝整份文本）。
    final chinese = Localizations.localeOf(context).languageCode.startsWith('zh');
    final previousText = doc.lintText;
    final previousReport = doc.lint;
    // 光标所在行不报「还没写完」类问题（刚打到 `cons` 就说缺分号太吵）。
    final caret = doc.controller.selection.baseOffset;
    final editingLine = caret < 0 ? null : _lineOfOffset(text, caret) + 1;
    final LintReport report;
    if (previousText != null && previousReport != null) {
      // 大文件里「在末尾继续打字」是最常见的改动，只对新增部分做检查。
      report = CodeLint.checkIncremental(
        previous: previousText,
        previousReport: previousReport,
        current: text,
        langLabel: doc.langLabel,
        langKey: _lang.key,
        chinese: chinese,
        disabledRules: _disabledRules,
        editingLine: editingLine,
        styleRules: _prefs.styleLint,
      );
    } else {
      report = CodeLint.check(
        text,
        langLabel: doc.langLabel,
        langKey: _lang.key,
        chinese: chinese,
        disabledRules: _disabledRules,
        editingLine: editingLine,
        styleRules: _prefs.styleLint,
      );
    }
    _inLint = false;
    if (!mounted) return;
    doc.lint = report;
    doc.lintText = text;
    _lastIssueOffset = -1;
    _refreshSymbolCache();
    setState(() => _lintChecking = false);
    // 换完装饰会 notifyListeners，必须放在 setState 之后、且不能再次触发检查。
    _refreshDecorations();
  }

  void _openConsole(EditorConsoleTab tab) {
    // 非编程语言只能看问题，不能进控制台。
    var target = _programming ? tab : EditorConsoleTab.problems;
    // 调试页只对 JS 有效（内置引擎）：别的语言点进来只会看到一个没有页签的面板。
    if (target == EditorConsoleTab.debug && !_jsBackend) {
      target = EditorConsoleTab.console;
    }
    setState(() {
      _consoleOpen = true;
      _consoleTab = target;
    });
    if (_lintEnabled && _lint == null) _runLint();
  }

  void _clearLintDecorations() {
    _refreshDecorations();
  }

  /// 当前光标行（0 基），用于高亮当前行。由 [_syncCaretLine] 增量维护。
  int _caretLine = -1;
  int _caretOffset = -1;

  /// 光标位置变了就更新「当前行高亮」。
  ///
  /// 只把「行号是否变化」当作重绘条件：光标在行内移动不重绘。
  /// 行号用增量推断（数新旧偏移之间有几个换行），大文件里也不会每点一下都扫全篇。
  void _syncCaretLine() {
    final controller = _doc?.controller;
    if (controller == null) return;
    final text = controller.text;
    final off = controller.selection.extentOffset.clamp(0, text.length);
    var line = _caretLine;
    if (line < 0) {
      // 只有切文档 / 首次进来才整篇扫一次。
      line = _lineOfOffset(text, off);
    } else if (off > _caretOffset) {
      for (var i = _caretOffset; i < off && i < text.length; i++) {
        if (text.codeUnitAt(i) == 10) line++;
      }
    } else if (off < _caretOffset) {
      // 退格 / 删除：同样只数中间那段换行，不整篇重扫。
      for (var i = off; i < _caretOffset && i < text.length; i++) {
        if (text.codeUnitAt(i) == 10) line--;
      }
      if (line < 0) line = _lineOfOffset(text, off);
    }
    final changed = line != _caretLine;
    _caretLine = line;
    _caretOffset = off;
    if (changed && mounted) {
      _refreshDecorations();
      // 面包屑跟着光标走，需要重建（_refreshDecorations 只重画装饰，不重建 widget）。
      setState(() {});
    }
  }

  /// 重画「当前行」与「语法问题」这两类行装饰。
  ///
  /// 两者共用 controller 的 lineDecoration 通道，只能一起重建——谁单独 clear 一次
  /// 都会把对方抹掉（以前就是这么丢的）。
  // 内联 diff 缓存：装饰刷新很频繁（每次编辑 + 光标移动），基线/文本没变就别重算。
  String? _diffCacheBase;
  int _diffCacheHash = 0;
  Map<int, int> _diffMarks = const <int, int>{};
  Timer? _diffTimer;

  /// 打字时重算全篇 diff 太贵，攒 700ms 再刷一次行号栏标记。
  void _scheduleDiffRefresh() {
    if (!_prefs.inlineDiff) return;
    if (_doc?.diskBaseline == null) return;
    _diffTimer?.cancel();
    _diffTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      _refreshDecorations();
    });
  }

  /// 相对磁盘基线的改动标记：0-based 行 → 0 新增 / 1 修改 / 2 删除。
  ///
  /// 只在「开关开着 + 有基线 + 文本不太大」时算：这是整篇比较，
  /// 十万行的文件每敲一个字都重算会明显卡。8 万字符（约两千行）是舒适区。
  Map<int, int> _inlineDiffMarks(String text, {bool force = false}) {
    if (!_prefs.inlineDiff && !force) {
      if (_diffMarks.isNotEmpty) {
        _diffMarks = const <int, int>{};
        _diffCacheBase = null;
      }
      return _diffMarks;
    }
    final base = _doc?.diskBaseline;
    if (base == null || base.isEmpty) return const <int, int>{};
    if (text.length > 80000 || base.length > 80000) return const <int, int>{};
    final h = text.hashCode * 31 + base.hashCode;
    if (h == _diffCacheHash && identical(_diffCacheBase, base)) return _diffMarks;
    _diffCacheHash = h;
    _diffCacheBase = base;

    final diffs = diffLines(base, text);
    final marks = <int, int>{};
    if (diffs.isNotEmpty) {
      for (final b in buildDiffBlocks(diffs)) {
        if (b.rightLines.isEmpty && b.leftLines.isEmpty) continue;
        for (var j = 0; j < b.rightLines.length; j++) {
          // 配对上的算「改写」，没配上的算「纯新增」。
          marks[b.rightLines[j]] = b.leftLocalOfRight(j) == null ? 0 : 1;
        }
        // 纯删除：标在删除发生处的上一行（和 VS Code 一样表示「这里少了几行」）。
        if (b.leftLines.length > b.pairs.length) {
          final at = b.rightStart > 0 ? b.rightStart - 1 : 0;
          marks.putIfAbsent(at, () => 2);
        }
      }
    }
    _diffMarks = marks;
    return marks;
  }

  int _todoTextHash = 0;
  List<TodoHit> _todoHits = const <TodoHit>[];

  /// 当前文档里的 TODO / FIXME 等标记（按文本指纹缓存）。
  ///
  /// 二十万字符以上的文件直接跳过：整篇正则扫一遍在主线程上会明显掉帧，
  /// 而那种体量的文件本来也不适合在手机上读。
  List<TodoHit> _todoHitsOf(String text) {
    if (!_prefs.highlightTodos || text.isEmpty) return const <TodoHit>[];
    if (text.length > 200000) return const <TodoHit>[];
    final h = text.hashCode;
    if (h == _todoTextHash) return _todoHits;
    _todoTextHash = h;
    _todoHits = TodoScanner.scan(text, limit: 200)..sort((a, b) => a.line.compareTo(b.line));
    return _todoHits;
  }

  /// 跳到下一处 / 上一处 TODO（VS 任务列表的等价快捷键）。
  void _gotoTodo(int delta) {
    final controller = _controller;
    if (controller == null) return;
    final hits = _todoHitsOf(controller.text);
    if (hits.isEmpty) {
      _toast(localizations.editorNoTodo);
      return;
    }
    final cur = _caretLine + 1; // hits 里的行号是 1-based
    TodoHit? target;
    if (delta > 0) {
      for (final h in hits) {
        if (h.line > cur) {
          target = h;
          break;
        }
      }
      target ??= hits.first;
    } else {
      for (final h in hits.reversed) {
        if (h.line < cur) {
          target = h;
          break;
        }
      }
      target ??= hits.last;
    }
    _gotoLineNumber(target.line);
    _toast(target.text.isEmpty ? target.tag : '${target.tag}: ${target.text}');
  }

  /// 在光标行加/删断点。
  ///
  /// 只对 JavaScript 有意义：内置引擎没有调试协议，这里做的是「行级插桩 +
  /// 命中抛异常停下来」（见 utils/js_debug.dart）。
  void _toggleBreakpointAtCaret() {
    final line = _caretLine < 0 ? 0 : _caretLine;
    final added = !_breakpoints.contains(line);
    setState(() {
      if (added) {
        _breakpoints.add(line);
      } else {
        _breakpoints.remove(line);
      }
    });
    _refreshDecorations();
    _toast(added
        ? localizations.editorBreakpointAdded(line + 1)
        : localizations.editorBreakpointRemoved(line + 1));
  }

  /// 看「光标这一行相对磁盘上原来是什么」。
  ///
  /// 手机上没有 hover，VS 的 Peek Changes 只能换个入口：光标定位 + 菜单。
  Future<void> _showDiskChangeAtCaret() async {
    final doc = _doc;
    final base = doc?.diskBaseline;
    if (doc == null || base == null || base.isEmpty) {
      _toast(localizations.editorNoDiskBaseline);
      return;
    }
    final text = doc.text;
    if (text.length > 80000 || base.length > 80000) {
      _toast(localizations.editorTooLargeToProcess);
      return;
    }
    final line = _caretLine < 0 ? 0 : _caretLine;
    final blocks = buildDiffBlocks(diffLines(base, text));
    DiffBlock? hit;
    for (final b in blocks) {
      if (b.rightLines.contains(line)) {
        hit = b;
        break;
      }
      // 纯删除块标在「少了几行」的位置（右起点上一行）。
      if (b.leftLines.length > b.pairs.length && b.rightStart - 1 == line) {
        hit = b;
        break;
      }
    }
    if (hit == null) {
      _toast(localizations.editorNoChangeHere);
      return;
    }
    final baseLines = base.split('\n');
    final nowLines = text.split('\n');
    final oldText = hit.leftLines.map((i) => i < baseLines.length ? baseLines[i] : '').join('\n');
    final newText = hit.rightLines.map((i) => i < nowLines.length ? nowLines[i] : '').join('\n');
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(localizations.editorDiskChange, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              _diskChangeBlock(
                ctx,
                localizations.editorDiskChangeOld,
                oldText.isEmpty ? localizations.editorDiskChangeAdded : oldText,
                const Color(0xFFC62828),
              ),
              const SizedBox(height: 10),
              _diskChangeBlock(
                ctx,
                localizations.editorDiskChangeNew,
                newText.isEmpty ? localizations.editorDiskChangeDeleted : newText,
                const Color(0xFF2E7D32),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _diskChangeBlock(BuildContext ctx, String title, String body, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(width: 3, height: 12, color: color),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
        ]),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            body,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35),
          ),
        ),
      ],
    );
  }

  void _refreshDecorations() {
    final controller = _doc?.controller;
    if (controller == null || !mounted) return;
    controller.clearLineDecorations();
    controller.clearGutterDecorations();
    final decos = <LineDecoration>[];
    final gutters = <GutterDecoration>[];

    // VS Code 的当前行高亮：手机屏幕上尤其容易「找不到光标在哪一行」。
    if (_prefs.highlightCurrentLine && _caretLine >= 0) {
      decos.add(LineDecoration(
        id: 'caret-line',
        startLine: _caretLine,
        endLine: _caretLine,
        type: LineDecorationType.background,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.07),
      ));
    }

    // 书签：淡琥珀底色 + 行号栏竖条（和错误标记用不同颜色，不会看混）。
    final doc = _doc;
    if (doc != null && doc.bookmarks.isNotEmpty) {
      final marks = doc.text;
      final lines = doc.bookmarks.map((o) => _lineOfOffset(marks, o)).toSet().toList()..sort();
      for (final line in lines) {
        decos.add(LineDecoration(
          id: 'bm-$line',
          startLine: line,
          endLine: line,
          type: LineDecorationType.background,
          color: Colors.amber.withValues(alpha: 0.10),
        ));
        gutters.add(GutterDecoration(
          id: 'bm-gutter-$line',
          startLine: line,
          endLine: line,
          type: GutterDecorationType.colorBar,
          color: Colors.amber,
        ));
      }
    }

    // 断点：行号栏一个红点（VS 是左侧的实心圆）。
    for (final line in _breakpoints) {
      gutters.add(GutterDecoration(
        id: 'bp-$line',
        startLine: line,
        endLine: line,
        type: GutterDecorationType.dot,
        color: const Color(0xFFD32F2F),
      ));
    }

    // 内联 diff：行号栏标出相对磁盘改了哪几行（VS 源代码管理的差异条）。
    // 画在 lint 之前：同一行既有改动又有错误时，错误那条（更宽/更亮的红）盖住它更合理。
    final marks = _inlineDiffMarks(_doc?.text ?? '');
    if (marks.isNotEmpty) {
      marks.forEach((line, kind) {
        gutters.add(GutterDecoration(
          id: 'diff-$line',
          startLine: line,
          endLine: line,
          type: GutterDecorationType.colorBar,
          color: switch (kind) {
            0 => const Color(0xFF2E7D32), // 新增
            1 => const Color(0xFF1565C0), // 修改
            _ => const Color(0xFFC62828), // 删除（标在「少了几行」的位置）
          },
          width: 2.6,
        ));
      });
    }

    // 注释里的 TODO / FIXME：行号栏一条细橙条（VS 的 TODO Highlight 插件）。
    // 整篇扫描要按文本指纹缓存，否则每次光标移动都会重扫一遍。
    final todos = _todoHitsOf(_doc?.text ?? '');
    for (final t in todos) {
      final line = t.line - 1;
      if (line < 0) continue;
      gutters.add(GutterDecoration(
        id: 'todo-$line',
        startLine: line,
        endLine: line,
        type: GutterDecorationType.colorBar,
        color: const Color(0xFFFFB300),
        width: 1.6,
      ));
    }

    final report = _doc?.lint;
    // VS 的做法：出错的那几个字符下面画波浪线，行号栏左侧加一条竖色条。
    // 不再把整行铺底色——整行染色会把正常代码读成一片彩色，长文件里尤其吵。
    var diagChanged = false;
    if (!identical(report, _diagReport)) {
      _diagReport = report;
      _diagLines = _toDiagnosticLines(report, _doc?.text ?? '');
      diagChanged = true;
    }
    // 内核也可能自己清这个通道（切文档 / LSP 断开），不一致时补回来。
    if (!identical(controller.diagnosticsNotifier.value, _diagLines)) {
      controller.diagnosticsNotifier.value = _diagLines;
      diagChanged = true;
    }
    if (report != null && report.diagnostics.isNotEmpty) {
      // 同一行有多条诊断时只按最严重的那条上色。
      final worstByLine = <int, LintSeverity>{};
      for (final d in report.diagnostics) {
        final line = d.line - 1;
        if (line < 0) continue;
        final current = worstByLine[line];
        if (current == null || d.severity.index < current.index) worstByLine[line] = d.severity;
      }
      worstByLine.forEach((line, severity) {
        final color = severity == LintSeverity.error
            ? Colors.red
            : severity == LintSeverity.warning
                ? Colors.orange
                : Colors.blueGrey;
        gutters.add(GutterDecoration(
          id: 'lint-gutter-$line',
          startLine: line,
          endLine: line,
          type: GutterDecorationType.colorBar,
          color: color,
        ));
      });
    }

    controller.addLineDecorations(decos);
    controller.addGutterDecorations(gutters);
    controller.notifyListeners();
    if (diagChanged) _scheduleDiagRepaint();
  }

  /// 把 lint 诊断翻译成内核的「波浪线」。
  ///
  /// 内核按**字符范围**画波浪线（红色 error / 黄色 warning / 蓝色 info），
  /// 所以要把「偏移 + 长度」换算成 (行, 列)。所有边界点一次扫完，别每条诊断各扫全文。
  static List<DiagnosticLine> _toDiagnosticLines(LintReport? report, String text) {
    final list = report?.diagnostics;
    if (list == null || list.isEmpty) return const <DiagnosticLine>[];
    // 波浪线太多会拖慢绘制（每行都要重建段落），取最前面的 400 条够了。
    final items = list.length > 400 ? list.sublist(0, 400) : list;
    final starts = <int>[];
    final ends = <int>[];
    for (final d in items) {
      final start = d.start.clamp(0, text.length);
      starts.add(start);
      final len = d.length < 0 ? 0 : d.length;
      ends.add((start + len).clamp(start, text.length));
    }
    final targets = <int>{...starts, ...ends}.toList()..sort();
    final positions = <int, (int, int)>{};
    var line = 0;
    var lineStart = 0;
    var cursor = 0;
    for (final target in targets) {
      while (cursor < target) {
        if (text.codeUnitAt(cursor) == 10) {
          line++;
          lineStart = cursor + 1;
        }
        cursor++;
      }
      positions[target] = (line, cursor - lineStart);
    }
    final out = <DiagnosticLine>[];
    for (var i = 0; i < items.length; i++) {
      final d = items[i];
      final from = positions[starts[i]] ?? (0, 0);
      final to = positions[ends[i]] ?? from;
      out.add(DiagnosticLine(
        severity: switch (d.severity) {
          LintSeverity.error => 1,
          LintSeverity.warning => 2,
          LintSeverity.info => 3,
        },
        range: <String, dynamic>{
          'start': <String, dynamic>{'line': from.$1, 'character': from.$2},
          'end': <String, dynamic>{'line': to.$1, 'character': to.$2},
        },
        message: d.message,
      ));
    }
    return out;
  }

  /// 波浪线是 RenderObject 的构造参数，改完得让编辑器重建一次才会画出来；
  /// 而 [_refreshDecorations] 有时会在 build 期间被间接调到，所以推迟到帧末做。
  void _scheduleDiagRepaint() {
    if (_diagRepaintScheduled) return;
    _diagRepaintScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _diagRepaintScheduled = false;
      if (mounted) setState(() {});
    });
  }

  /// 当前选区文本（控制台里的 `$0`）。
  /// 打开文件夹：一层一跳地浏览目录，点文件直接打开（VS 的解决方案资源管理器
  /// 在手机上的可用形态）。
  Future<void> _showFileBrowser() async {
    final path = _doc?.path;
    Directory root;
    if (path != null && path.isNotEmpty) {
      root = File(path).parent;
    } else {
      try {
        final dir = await getApplicationDocumentsDirectory();
        root = dir;
      } catch (_) {
        _toast(localizations.editorBrowserNoRoot);
        return;
      }
    }
    final picked = await showEditorFileBrowser(context, root: root);
    if (picked == null || !mounted) return;
    await _openPath(picked);
  }

  /// 编译日志中文化：粘贴 gcc/clang 输出，翻成中文并能定位回本文件。
  Future<void> _showCompilerLog() async {
    final entry = await CompilerLogPage.show(context, currentPath: _doc?.path ?? '');
    if (entry == null || !mounted) return;
    final line = entry.line;
    if (line == null) return;
    final controller = _controller;
    if (controller == null) return;
    final target = (line - 1).clamp(0, controller.lineCount - 1);
    try {
      final start = controller.getLineStartOffset(target);
      final offset = (start + (entry.column ?? 1) - 1).clamp(0, controller.text.length);
      controller.selection = TextSelection.collapsed(offset: offset);
      controller.scrollToLine(target);
    } catch (_) {
      // 行号越界：忽略
    }
  }

  /// 快速打开：列当前文件所在目录的文本文件，打字即时过滤（VS 的 Ctrl+P）。
  /// 记一次「最近打开」。同一个文件重复打开只把它提到最前，不重复占位。
  void _rememberRecentFile(String path) {
    if (path.isEmpty) return;
    if (_recentFiles.isNotEmpty && _recentFiles.first == path) return;
    _recentFiles.remove(path);
    _recentFiles.insert(0, path);
    if (_recentFiles.length > 20) {
      _recentFiles.removeRange(20, _recentFiles.length);
    }
    unawaited(
        SharedPreferencesAsync().setStringList(_recentFilesKey, _recentFiles));
  }

  /// 最近打开的文件列表。失效的条目会标灰，点一下可以确认移除。
  Future<void> _showRecentFiles() async {
    if (_recentFiles.isEmpty) {
      _toast(localizations.editorNoRecentFiles);
      return;
    }
    // 先一次性探一下存在性（最多 20 次 stat，很快），避免用户点到已被删的文件。
    final exists = <String, bool>{};
    for (final p in _recentFiles) {
      try {
        exists[p] = await File(p).exists();
      } catch (_) {
        exists[p] = false;
      }
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(children: [
              Expanded(
                child: Text(localizations.editorRecentFiles,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: () {
                  setState(() => _recentFiles = <String>[]);
                  unawaited(SharedPreferencesAsync()
                      .remove(_recentFilesKey)
                      .catchError((Object _) {}));
                  Navigator.pop(ctx);
                },
                child: Text(localizations.clear),
              ),
            ]),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _recentFiles.length,
              itemBuilder: (_, i) {
                final path = _recentFiles[i];
                final alive = exists[path] ?? false;
                final name = path.split(RegExp(r'[/\\]')).last;
                final dir = path.length > name.length
                    ? path.substring(0, path.length - name.length - 1)
                    : '';
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  enabled: alive,
                  leading: Icon(
                    alive ? Icons.description_outlined : Icons.error_outline,
                    size: 18,
                  ),
                  title: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(alive ? dir : localizations.editorRecentMissing,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11)),
                  trailing: IconButton(
                    tooltip: localizations.delete,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      setState(() => _recentFiles.remove(path));
                      unawaited(SharedPreferencesAsync()
                          .setStringList(_recentFilesKey, _recentFiles));
                      Navigator.pop(ctx);
                    },
                  ),
                  onTap: () => Navigator.pop(ctx, path),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    await _openPath(picked);
  }

  Future<void> _showQuickOpen() async {
    final path = _doc?.path;
    if (path == null || path.isEmpty) {
      _toast(localizations.editorQuickOpenNeedFile);
      return;
    }
    final picked = await showEditorQuickOpen(context, dir: File(path).parent);
    if (picked == null || !mounted) return;
    await _openPath(picked);
  }

  // 剪贴板历史：只在内存里留最近 20 条（剪贴板内容可能含密钥，不落盘）。
  static const int _clipMax = 20;
  static const int _clipMaxChars = 200000;
  final List<String> _clipHistory = <String>[];

  void _rememberClip(String text) {
    if (text.isEmpty || text.length > _clipMaxChars) return;
    _clipHistory.remove(text);
    _clipHistory.insert(0, text);
    if (_clipHistory.length > _clipMax) {
      _clipHistory.removeRange(_clipMax, _clipHistory.length);
    }
  }

  Future<void> _showClipHistory() async {
    final loc = localizations;
    if (_clipHistory.isEmpty) {
      _toast(loc.editorClipHistoryEmpty);
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
              child: Row(children: [
                const Icon(Icons.content_paste, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(loc.editorClipHistory,
                    style: Theme.of(ctx).textTheme.titleSmall)),
                IconButton(
                  tooltip: loc.close,
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(ctx).maybePop(),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: _clipHistory.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (c, i) {
                  final text = _clipHistory[i];
                  final first = text.split('\n').first.trim();
                  return ListTile(
                    dense: true,
                    title: Text(first.isEmpty ? '…' : first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace')),
                    subtitle: Text('${text.length}',
                        style: const TextStyle(fontSize: 11)),
                    onTap: () => Navigator.of(c).pop(text),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _insertAtCursor(picked);
  }

  /// AI 辅助：选中就处理选中，没选中就整篇（弹层里会截断到 12000 字符）。
  ///
  /// 用的是 App「设置 → AI 分析」那套接口，不额外配置。
  Future<void> _showAiAssist() async {
    final controller = _doc?.controller;
    if (controller == null) return;
    final selected = _selectedText();
    final hasSel = selected.isNotEmpty;
    final text = hasSel ? selected : controller.text;
    if (text.trim().isEmpty) {
      _toast(localizations.editorAiIdle);
      return;
    }
    final selStart = controller.selection.start;
    final selEnd = controller.selection.end;
    await showEditorAiAssist(
      context,
      text: text,
      language: _doc?.langLabel ?? '',
      onInsert: (result) {
        final c = _doc?.controller;
        if (c == null || result.isEmpty) return;
        final offset = c.selection.isValid ? c.selection.start : c.text.length;
        c.replaceRange(offset, offset, result);
      },
      onReplace: hasSel
          ? (result) {
              final c = _doc?.controller;
              if (c == null || result.isEmpty) return;
              final s = selStart.clamp(0, c.text.length);
              final e = selEnd.clamp(s, c.text.length);
              c.replaceRange(s, e, result);
            }
          : null,
    );
  }

  String _selectedText() {
    final controller = _doc?.controller;
    if (controller == null) return '';
    final selection = controller.selection;
    final text = controller.text;
    if (selection.start < 0 || selection.end > text.length || selection.start == selection.end) {
      return '';
    }
    return text.substring(selection.start, selection.end);
  }

  /// 行数缓存（右侧「问题分布条」按行号比例定位，需要总行数）。
  String? _lineCountText;
  int _lineCount = 0;

  int _totalLinesOf(String text) {
    if (!identical(_lineCountText, text)) {
      _lineCountText = text;
      var n = 1;
      for (var i = 0; i < text.length; i++) {
        if (text.codeUnitAt(i) == 10) n++;
      }
      _lineCount = n;
    }
    return _lineCount;
  }

  /// 当前可见（没被筛选关掉）的问题。
  ///
  /// 带缓存：build 里要拿它两次（判断显示 + 画分布条），每次现算会白分配一堆 List，
  /// 还会让分布条每帧都重绘。
  LintReport? _visibleFor;
  List<LintDiagnostic> _visibleCache = const <LintDiagnostic>[];

  List<LintDiagnostic> _visibleIssues() {
    final report = _lint;
    if (identical(report, _visibleFor) && _visibleHiddenSig == _severitySignature(_hiddenSeverities)) {
      return _visibleCache;
    }
    final all = report?.diagnostics;
    _visibleFor = report;
    _visibleHiddenSig = _severitySignature(_hiddenSeverities);
    if (all == null || all.isEmpty) {
      _visibleCache = const <LintDiagnostic>[];
    } else if (_hiddenSeverities.isEmpty) {
      _visibleCache = all;
    } else {
      _visibleCache = all
          .where((d) => !_hiddenSeverities.contains(d.severity))
          .toList(growable: false);
    }
    return _visibleCache;
  }

  /// 筛选状态的「键」（用于判断缓存是否失效）。
  String _visibleHiddenSig = '';

  static String _severitySignature(Set<LintSeverity> muted) {
    if (muted.isEmpty) return '';
    final names = muted.map((e) => e.name).toList()..sort();
    return names.join(',');
  }

  /// 上一次跳到的位置（偏移）。用偏移而不是列表下标：
  /// 列表会因为「筛选掉了某个级别」「检查结果刷新」而变短，下标就指到别处去了。
  int _lastIssueOffset = -1;

  /// F8 / Shift+F8：在问题之间跳。
  ///
  /// 被筛选关掉的级别不参与导航——VS 里隐藏的问题也不会被 F8 跳过去。
  void _jumpIssue(bool forward) {
    final all = _lint?.diagnostics;
    if (all == null || all.isEmpty) return;
    final list = _hiddenSeverities.isEmpty
        ? all
        : all.where((d) => !_hiddenSeverities.contains(d.severity)).toList(growable: false);
    if (list.isEmpty) return;
    LintDiagnostic? pick;
    if (forward) {
      for (final d in list) {
        if (d.start > _lastIssueOffset) {
          pick = d;
          break;
        }
      }
      pick ??= list.first;
    } else {
      for (final d in list.reversed) {
        if (d.start < _lastIssueOffset) {
          pick = d;
          break;
        }
      }
      pick ??= list.last;
    }
    _lastIssueOffset = pick.start;
    // 只有一处问题时以前点了毫无反馈（跳来跳回原地）；现在给序号。
    final index = list.indexOf(pick);
    _toast('${index < 0 ? 1 : index + 1} / ${list.length}');
    _jumpToDiagnostic(pick);
  }

  void _jumpToDiagnostic(LintDiagnostic d) {
    final controller = _doc?.controller;
    if (controller == null) return;
    final text = controller.text;
    final start = d.start.clamp(0, text.length);
    final end = (d.start + d.length).clamp(start, text.length);
    controller.selection = TextSelection(baseOffset: start, extentOffset: end);
    controller.scrollToLine(d.line - 1);
  }

  void _fixDiagnostic(LintDiagnostic d) {
    final controller = _doc?.controller;
    final replacement = d.replacement;
    if (controller == null || replacement == null) return;
    final text = controller.text;
    if (d.start < 0 || d.start + d.length > text.length) return;
    controller.replaceRange(d.start, d.start + d.length, replacement);
    _runLint();
  }

  void _fixAllDiagnostics() {
    final controller = _doc?.controller;
    final report = _lint;
    if (controller == null || report == null) return;
    final before = controller.text;
    // 一键修复后光标不能跳回行首/文末：按「光标之前被替换掉的字符数」平移。
    final caret = controller.selection.extentOffset.clamp(0, before.length);
    var adjusted = caret;
    for (final d in report.diagnostics) {
      final replacement = d.replacement;
      if (replacement == null) continue;
      if (d.start + d.length <= caret) adjusted += replacement.length - d.length;
    }
    final fixed = CodeLint.applyFixes(before, report.diagnostics);
    if (fixed == before) return;
    controller.text = fixed;
    controller.selection =
        TextSelection.collapsed(offset: adjusted.clamp(0, controller.text.length));
    _runLint();
  }

  void _setLintEnabled(bool value) {
    setState(() => _lintEnabled = value);
    if (!value) {
      _lintTimer?.cancel();
      _doc?.lint = null;
      _clearLintDecorations();
    } else {
      // 手动打开开关时立刻检查一次（流畅模式下自动检查是关掉的，
      // 只排定时器会看起来「点了没反应」）。
      _runLint();
    }
  }

  // ---------- 光标导航历史 ----------

  void _pushNav(int offset) {
    if (_suppressNav) return;
    final doc = _doc;
    if (doc == null) return;
    final stack = doc.navStack;
    final index = doc.navIndex;
    if (index >= 0 && index < stack.length && stack[index] == offset) return;
    if (index + 1 < stack.length) {
      stack.removeRange(index + 1, stack.length);
    }
    stack.add(offset);
    if (stack.length > 100) stack.removeAt(0);
    doc.navIndex = stack.length - 1;
    if (mounted) setState(() {});
  }

  void _navBack() {
    if (_navIndex <= 0) return;
    _navIndex--;
    _jumpNav();
  }

  void _navForward() {
    if (_navIndex >= _navStack.length - 1) return;
    _navIndex++;
    _jumpNav();
  }

  void _jumpNav() {
    final controller = _controller;
    if (controller == null || _navIndex < 0 || _navIndex >= _navStack.length) return;
    final offset = _navStack[_navIndex];
    _suppressNav = true;
    _jumpToOffset(offset);
    _suppressNav = false;
    setState(() {});
  }

  // ---------- 剪贴板（供长按浮动菜单用） ----------

  void _cut() {
    final controller = _controller;
    if (controller == null) return;
    final sel = controller.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final text = controller.text;
    final selected = text.substring(sel.start, sel.end);
    Clipboard.setData(ClipboardData(text: selected));
    controller.text = text.replaceRange(sel.start, sel.end, '');
    controller.selection = TextSelection.collapsed(offset: sel.start);
  }

  /// 取 [offset] 所在行的前导空白（用于粘贴对齐缩进）。
  ///
  /// 只取「行首 → 第一个非空白字符」这一段；光标在缩进之前时按光标位置截断，
  /// 这样「行首按粘贴」不会凭空多出缩进。
  String _lineIndentAt(String text, int offset) {
    final at = offset.clamp(0, text.length);
    final lineStart = at == 0 ? 0 : text.lastIndexOf('\n', at - 1) + 1;
    var end = lineStart;
    while (end < text.length) {
      final c = text.codeUnitAt(end);
      if (c != 0x20 && c != 0x09) break;
      end++;
    }
    final indentEnd = end < at ? end : at;
    return text.substring(lineStart, indentEnd);
  }

  Future<void> _paste() async {
    final controller = _controller;
    if (controller == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final clip = data?.text ?? '';
    if (clip.isEmpty) return;
    // 剪贴板里有几十 MB（比如整个日志文件）时，插进去等于让编辑器卡死。
    if (clip.length > 5000000) {
      _toast(localizations.editorPasteTooLarge);
      return;
    }
    final text = controller.text;
    final sel = controller.selection;
    final start = sel.isValid && !sel.isCollapsed ? sel.start : (sel.isValid ? sel.start : text.length);
    final end = sel.isValid && !sel.isCollapsed ? sel.end : start;
    // 对齐缩进：整段代码粘到 if/for 里面时，后续行自动补齐当前行的缩进
    // （VS / VS Code 的 Reindent on paste）。粘贴单行时不做任何改动。
    var payload = clip;
    if (_prefs.pasteStripLineNumbers) {
      payload = stripLineNumbers(payload);
    }
    if (_prefs.pasteReindent) {
      payload = reindentPasted(payload, _lineIndentAt(text, start));
    }
    controller.replaceRange(start, end, payload);
    controller.selection = TextSelection.collapsed(offset: start + payload.length);
  }

  void _selectAll() {
    final controller = _controller;
    if (controller == null) return;
    controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
  }

  // ---------- 双指缩放 ----------

  bool _zoomEnabled = false;

  /// 专注模式：只剩代码，工具栏/标签条/面包屑/状态栏全部收起。
  /// 手机上横屏或小屏时，这些条加起来能吃掉三分之一屏幕。
  bool _zen = false;

  void _onPointerDown(PointerDownEvent e) {
    _zoomEnabled = _prefs.pinchZoom;
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _pinchBaseDistance = _pointerDistance();
      _pinchStartFontSize = _prefs.fontSize;
      _lastPinchSize = _prefs.fontSize.round();
      _pinching = false;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (!_zoomEnabled || _pointers.length != 2 || _pinchBaseDistance == null) return;
    final base = _pinchBaseDistance!;
    if (base <= 0) return;
    final distance = _pointerDistance();
    final ratio = distance / base;
    if (!_pinching) {
      // 两指间距变化超过 12% 才认定为「捏合」。滚动时到不了这个幅度。
      if ((ratio - 1).abs() < 0.12) return;
      _pinching = true;
      // 以此刻为新的基准重新开始，避免确认的瞬间字号跳一大截。
      _pinchBaseDistance = distance;
      _pinchStartFontSize = _prefs.fontSize;
      _lastPinchSize = _prefs.fontSize.round();
      return;
    }
    final next = (_pinchStartFontSize * ratio).clamp(10.0, 40.0);
    final rounded = next.round();
    if (rounded != _lastPinchSize) {
      _lastPinchSize = rounded;
      // 缩放过程只改内存里的字号（不落盘），松手时统一保存。
      TextEditorPrefsStore.notifier.value =
          TextEditorPrefsStore.notifier.value.copyWith(fontSize: rounded.toDouble());
    }
  }

  void _onPointerUp(PointerEvent e) {
    // 双指手势结束，下次重新判定是滚动还是捏合。
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) {
      // 只有真的缩放过的才落盘：双指滚动（没缩放）不该写偏好。
      if (_pinching) {
        TextEditorPrefsStore.update(TextEditorPrefsStore.notifier.value).ignore();
      }
      _pinchBaseDistance = null;
      _pinching = false;
    }
  }

  double _pointerDistance() {
    final list = _pointers.values.toList();
    if (list.length < 2) return 0;
    return (list[0] - list[1]).distance;
  }

  // ---------- 放大镜 ----------

  /// 底部显示当前行的放大视图（跟随光标）。
  Widget _magnifierBar(EditorDocument doc) {
    final text = doc.text;
    final controller = doc.controller;
    final raw = controller.selection.isValid ? controller.selection.baseOffset : 0;
    final safe = raw.clamp(0, text.length);
    final start = safe > 0 ? text.lastIndexOf('\n', safe - 1) + 1 : 0;
    var end = text.indexOf('\n', safe);
    if (end < 0) end = text.length;
    final line = text.substring(start, end);
    final size = _prefs.fontSize;
    return Container(
      height: size * 3.4,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: Colors.black12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            line.isEmpty ? ' ' : line,
            maxLines: 1,
            style: TextStyle(
              fontSize: size * 1.8,
              height: 1.1,
              fontFamily: 'monospace',
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  // ---------- 编码 ----------

  /// 用指定编码重新读一遍当前文件。
  /// 状态栏点编码：选一个编码后按它重新解码当前文件（最常用的语义）。
  Future<void> _pickEncodingFromStatus() async {
    final picked = await showEncodingPicker(context, _encoding,
        title: localizations.editorEncoding);
    if (picked == null) return;
    await _reloadWithEncoding(picked);
  }

  Future<void> _reloadWithEncoding(EditorEncoding encoding) async {
    final doc = _doc;
    final path = doc?.path;
    if (doc == null) return;
    if (path == null || path.isEmpty) {
      _toast(localizations.editorNoFilePath);
      return;
    }
    if (doc.dirty) {
      // 重新加载会丢掉未保存的修改，先问一句。
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(localizations.editorReloadDiscard),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(localizations.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(localizations.confirm)),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    try {
      final bytes = await File(path).readAsBytes();
      final text = await encoding.decode(bytes);
      if (!mounted) return;
      doc.encodingName = encoding.name;
      unawaited(TextEditorPrefsStore.update(
          TextEditorPrefsStore.notifier.value.copyWith(encodingName: encoding.name)));
      setState(() {
        doc.text = text;
        _lastText = text;
        _dirty = false;
      });
      // 换编码后旧的撤销栈指向的是被丢弃的内容，撤销回去等于「变回乱码」。
      doc.undoController.clear();
      _remapBookmarksByHead(doc);
      _toast(localizations.editorReloadSuccess);
    } catch (e) {
      _toast('$e');
    }
  }

  /// 用指定编码把当前文本写回磁盘（有路径直接覆盖，否则另存）。
  Future<void> _saveWithEncoding(EditorEncoding encoding) async {
    final controller = _controller;
    final doc = _doc;
    if (controller == null || doc == null) return;

    // VS 的 format on save：先按语言重排，再落盘（失败/无变化都不打扰用户）。
    if (_prefs.formatOnSave && _canFormat) {
      await _applyFormat(quiet: true);
      if (!mounted) return;
    }
    // VS Code 的 files.trimTrailingWhitespace：落盘前把行尾空白去掉。
    if (_prefs.trimOnSave) _trimOnSaveQuiet();

    final text = _applyNewline(controller.text, _newlineCharsOf(doc));
    final bytes = await encoding.encode(text);
    // 编码记在文档上：改一份文件的编码不该影响下一份。
    doc.encodingName = encoding.name;
    unawaited(TextEditorPrefsStore.update(
        TextEditorPrefsStore.notifier.value.copyWith(encodingName: encoding.name)));

    final path = doc.path;
    if (path != null && path.isNotEmpty) {
      try {
        await File(path).writeAsBytes(bytes);
        if (!mounted) return;
        setState(() => _dirty = false);
        _toast(localizations.saveSuccess);
        return;
      } catch (e) {
        _toast('$e');
        return;
      }
    }

    // 没有路径：走「另存为」。
    if (Platforms.isMobile()) {
      final file = XFile.fromData(bytes, mimeType: 'text/plain');
      RenderBox? box;
      if (await Platforms.isIpad() && mounted) {
        box = context.findRenderObject() as RenderBox?;
      }
      await SharePlus.instance.share(ShareParams(
          files: [file], fileNameOverrides: [doc.name], sharePositionOrigin: box?.paintBounds));
      if (mounted) setState(() => _dirty = false);
      return;
    }
    final saved = await FilePicker.saveFile(fileName: doc.name, bytes: bytes);
    if (saved == null) return;
    if (mounted) {
      setState(() => _dirty = false);
      _toast(localizations.saveSuccess);
    }
  }

  // ---------- 长按浮动菜单 ----------

  List<CustomContextMenu> _floatMenuItems() {
    final show = _prefs.floatMenu.toSet();
    // 注意：这里返回空列表时内核会用它自己的菜单（复制/粘贴/全选）。
    if (show.isEmpty) return const <CustomContextMenu>[];
    final loc = localizations;
    final items = <CustomContextMenu>[];
    for (final item in kFloatMenuItems) {
      if (!show.contains(item.id)) continue;
      items.add(CustomContextMenu(
        label: item.label(loc),
        description: '',
        onPress: () => _runFloatAction(item.id),
      ));
    }
    return items;
  }

  void _runFloatAction(String id) {
    switch (id) {
      case 'copy':
        _copy();
      case 'cut':
        _cut();
      case 'paste':
        _paste();
      case 'selectAll':
        _selectAll();
      case 'comment':
        _toggleComment();
      case 'format':
        _format();
      case 'minify':
        unawaited(_minify());
      case 'find':
        _toggleFind();
      case 'special':
        _showSpecialReport();
      case 'replaceLine':
        _replaceCurrentLine();
      case 'selectNext':
        _addNextOccurrence();
      case 'gotoDef':
        unawaited(_gotoDefinition());
      case 'upper':
        _editSelections((v) => v.toUpperCase());
      case 'lower':
        _editSelections((v) => v.toLowerCase());
      case 'formatSel':
        unawaited(_applyFormat(selectionOnly: true));
      case 'rename':
        unawaited(_renameSymbol());
      case 'renamePair':
        unawaited(_renamePairedTag());
      case 'boxSelect':
        _boxSelect();
    }
  }

  void _newFile() {
    final current = _doc;
    final keep = _prefs.newFileKeepPrefs && current != null;
    final doc = _docs.create(
      name: localizations.editorUntitled,
      langLabel: keep ? current.langLabel : 'Plain Text',
    );
    // 新建文件沿用全局换行符偏好（从 Windows 文件里复制内容过来时更顺）。
    doc.newline = _newlineChars(_newline);
    _activate(doc);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  /// 打开「工作区文件树」：在目录里点着走，不用每次都从系统选择器根目录翻起。
  void _showWorkspaceTree() {
    final ws = _workspace;
    if (ws == null || ws.isEmpty) {
      _toast(localizations.editorWorkspaceNotSet);
      return;
    }
    unawaited(WorkspaceTreeSheet.show(context, root: ws,
        onOpenFile: (p) => unawaited(_openPath(p))));
  }

  /// 记下刚关掉的文档（供「重新打开已关闭」用）。
  void _rememberClosed(EditorDocument doc) {
    final path = doc.path;
    if (path == null || path.isEmpty) return;
    final caret = identical(doc, _doc) ? (_controller?.selection.extentOffset ?? -1) : doc.lastCaret;
    _recentClosed.removeWhere((e) => e.path == path);
    _recentClosed.insert(0, (path: path, name: doc.name, caret: caret));
    if (_recentClosed.length > 10) _recentClosed.removeLast();
  }

  /// 重新打开最近关掉的那份文件，并回到关闭时的光标位置。
  Future<void> _reopenClosed() async {
    if (_recentClosed.isEmpty) {
      _toast(localizations.editorReopenEmpty);
      return;
    }
    final item = _recentClosed.removeAt(0);
    await _openPath(item.path);
    if (!mounted || _doc?.path != item.path) return;
    final c = _controller;
    if (c == null || item.caret < 0) return;
    final off = item.caret.clamp(0, c.text.length);
    c.selection = TextSelection.collapsed(offset: off);
    c.scrollToLine(_lineOfOffset(c.text, off));
  }

  Future<void> _closeDoc(EditorDocument doc) async {
    // 关掉一份「改了但没存」的文档，跟按返回键退出是一回事，都得先问。
    if (doc.dirty && (doc.path?.isNotEmpty ?? false)) {
      final keep = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(localizations.editorUnsavedExitTitle),
          content: Text(localizations.editorUnsavedExitBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localizations.cancel)),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(localizations.editorExitWithoutSaving)),
            FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx, true);
                  await _saveDoc(doc);
                },
                child: Text(localizations.save)),
          ],
        ),
      );
      if (!mounted) return;
      // 取消 → 什么都不做；选「保存」的话上面已经把内容写回去了。
      if (keep == null) return;
      if (doc.dirty) return; // 保存失败则别关，避免「以为存了」
    }
    _rememberClosed(doc);
    final wasActive = identical(doc, _doc);
    if (wasActive) {
      // 先解绑，避免随后对已 dispose 的 controller 做 removeListener
      _doc = null;
    }
    _docs.remove(doc.id);
    if (wasActive) {
      final next = _docs.docs.isEmpty ? null : _docs.docs.first;
      _activate(next ?? _docs.create(name: localizations.editorUntitled));
    }
    setState(() {});
    _docs.persist();
  }

  void _togglePin(EditorDocument doc) {
    doc.pinned = !doc.pinned;
    if (doc.pinned) _docs.moveToTop(doc.id);
    setState(() {});
    _docs.persist();
  }

  void _toggleRetain(EditorDocument doc) {
    doc.retained = !doc.retained;
    setState(() {});
    _docs.persist();
  }

  // ---------- 退出 ----------

  bool get _hasUnretained => _docs.docs.any((d) => !d.retained);

  /// 退出后的收尾：按保留策略处理未保留的文档并落盘。
  ///
  /// 延迟执行是为了避开路由退场动画——动画期间 CodeForge 仍在渲染，
  /// 此时 dispose 掉 controller 会引发异常。
  void _scheduleExitCleanup(bool? keep) {
    Future.delayed(const Duration(milliseconds: 500), () {
      _unbindActiveDoc();
      for (final d in _docs.docs.where((d) => !d.retained).toList()) {
        if (keep == true || _retainMode == _RetainMode.always) {
          d.retained = true;
        } else {
          _docs.remove(d.id);
        }
      }
      unawaited(_docs.persist());
    });
  }

  Future<void> _confirmExit() async {
    if (_confirmingExit) return;
    _confirmingExit = true;

    // 一、「改了但没写回文件」先问一句。默认 retained 文档的正文是存在草稿里的，
    //     下次打开还在，但**文件本身没变**——用户以为存了，其实没存。
    final doc = _doc;
    final path = doc?.path;
    if (_dirty && path != null && path.isNotEmpty) {
      final choice = await showDialog<int>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(localizations.editorUnsavedExitTitle),
          content: Text(localizations.editorUnsavedExitBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(localizations.cancel)),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 0),
                child: Text(localizations.editorExitWithoutSaving)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 1),
                child: Text(localizations.editorSaveAndExit)),
          ],
        ),
      );
      if (!mounted) {
        _confirmingExit = false;
        return;
      }
      // 取消 = 留在编辑器里。
      if (choice == null) {
        _confirmingExit = false;
        return;
      }
      if (choice == 1) {
        await _saveWithEncoding(_encoding);
        if (!mounted || _dirty) {
          // 保存失败（或用户中途取消了另存为）就别退，避免「以为存了」。
          _confirmingExit = false;
          return;
        }
      }
    }

    // 二、未保留文档的取舍（原有逻辑）。
    final keep = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.editorExitRetainTitle),
        content: Text(localizations.editorExitRetainBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(localizations.editorDiscard)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(localizations.editorRetain)),
        ],
      ),
    );
    // 二次确认（可关）。
    if (keep != null && _prefs.confirmExitTwice && mounted) {
      final again = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(localizations.editorExitConfirmAgainTitle),
          content: Text(localizations.editorExitConfirmAgainBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(localizations.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(localizations.confirm)),
          ],
        ),
      );
      if (again != true) {
        _confirmingExit = false;
        return;
      }
    }
    _confirmingExit = false;
    if (!mounted) return;
    // Navigator.pop 不会再次触发 PopScope（只有 maybePop / 系统返回会），无递归风险。
    Navigator.of(context).pop();
    _scheduleExitCleanup(keep);
  }

  // ---------- 不可见字符 ----------

  void _setShowAscii(bool value) {
    setState(() => _showAscii = value);
  }

  void _setShowUnicode(bool value) {
    setState(() => _showUnicode = value);
  }

  Future<void> _showSpecialReport() async {
    final controller = _controller;
    if (controller == null) return;
    if (_tooLargeForSync(controller.text, limit: 2000000)) return;
    final hits = SpecialCharScanner.scan(controller.text);
    final counts = <int, int>{};
    for (final h in hits) {
      counts[h.code] = (counts[h.code] ?? 0) + 1;
    }
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.editorSpecialReport),
        content: SizedBox(
          width: 380,
          height: 360,
          child: entries.isEmpty
              ? Center(child: Text(localizations.editorSpecialNone, style: const TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return ListTile(
                      dense: true,
                      title: Text(SpecialCharScanner.describe(e.key),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('×${e.value}', style: const TextStyle(fontSize: 12)),
                        IconButton(
                          icon: const Icon(Icons.my_location, size: 18),
                          tooltip: localizations.editorJumpTo,
                          onPressed: () {
                            Navigator.pop(ctx);
                            // 列表打开后若又跑过一次检查，这个 code 可能已经不在
                            // hits 里了：firstWhere 会抛 StateError（点一下就红屏），
                            // 所以这里按 indexWhere 取，找不到就什么都不做。
                            final idx = hits.indexWhere((h) => h.code == e.key);
                            if (idx >= 0) _jumpToOffset(hits[idx].index);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          tooltip: localizations.editorRemoveAll,
                          onPressed: () {
                            _removeAllOfCode(e.key);
                            Navigator.pop(ctx);
                          },
                        ),
                      ]),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localizations.close))],
      ),
    );
  }

  void _jumpToOffset(int offset) {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final line = '\n'.allMatches(text.substring(0, offset.clamp(0, text.length))).length;
    controller.selection =
        TextSelection.collapsed(offset: offset.clamp(0, text.length));
    controller.scrollToLine(line);
  }

  void _removeAllOfCode(int code) {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final buffer = StringBuffer();
    var removed = 0;
    for (var i = 0; i < text.length; i++) {
      final cu = text.codeUnitAt(i);
      if (cu >= 0xD800 && cu <= 0xDBFF) {
        buffer.writeCharCode(cu);
        if (i + 1 < text.length) {
          buffer.writeCharCode(text.codeUnitAt(i + 1));
          i++;
        }
        continue;
      }
      if (cu == code) {
        removed++;
        continue;
      }
      buffer.writeCharCode(cu);
    }
    controller.text = buffer.toString();
    _toast(localizations.editorRemoved(removed));
  }

  // ---------- 编辑操作 ----------

  /// [placeholders] 为 true 时按片段语法解析 `$1` / `${1:默认}` / `$0`
  /// （只有「从片段栏插入」走这条路，普通插入/粘贴不解析 —— 否则 shell 的 `$1`
  /// 和正则反向引用会被改坏）。
  void _insertAtCursor(String insert, {bool placeholders = false}) {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final sel = controller.selection;
    // 用 replaceRange 而不是「整份 text 赋值」：撤销粒度是一段，不是整篇。
    final start = sel.isValid && !sel.isCollapsed ? sel.start : (sel.isValid ? sel.start : text.length);
    final end = sel.isValid && !sel.isCollapsed ? sel.end : start;
    if (!placeholders) {
      _snippetStops.clear();
      controller.replaceRange(start, end, insert);
      controller.selection = TextSelection.collapsed(offset: start + insert.length);
      return;
    }
    final parsed = parseSnippetPlaceholders(insert);
    _snippetStops
      ..clear()
      ..addAll(parsed.stops.map((s) => SnippetStop(start + s.start, start + s.end)));
    controller.replaceRange(start, end, parsed.text);
    if (_snippetStops.isEmpty) {
      controller.selection = TextSelection.collapsed(offset: start + parsed.text.length);
      return;
    }
    // 第一处直接选中（`${1:默认}` 时打字即替换，和 VS Code 一样）。
    final first = _snippetStops.removeAt(0);
    controller.selection = TextSelection(baseOffset: first.start, extentOffset: first.end);
  }

  /// 跳到片段的下一处占位符。
  void _nextSnippetStop() {
    final c = _controller;
    if (c == null || _snippetStops.isEmpty) return;
    final len = c.text.length;
    // 中途编辑过的话偏移会漂，越界的停靠点直接丢掉，不要跳到一个乱位置上。
    while (_snippetStops.isNotEmpty && _snippetStops.first.start > len) {
      _snippetStops.removeAt(0);
    }
    if (_snippetStops.isEmpty) return;
    final s = _snippetStops.removeAt(0);
    final start = s.start.clamp(0, len);
    final end = s.end.clamp(start, len);
    c.selection = TextSelection(baseOffset: start, extentOffset: end);
    c.scrollToLine(_lineOfOffset(c.text, start));
    if (_snippetStops.isEmpty) _toast(localizations.editorSnippetDone);
  }

  /// 打开搜索时默认收起（不展开替换行）。
  void _toggleFind() {
    final find = _doc?.findController;
    if (find == null) return;
    if (!find.isActive) find.isReplaceMode = false;
    find.toggleActive();
  }

  /// 可滑动 / 可展开的快捷输入行；随当前文档的语言切换常用符号。
  Widget _snippetBar() {
    final label = _doc?.langLabel ?? 'Plain Text';
    return SnippetBar(
      scope: editorSnippetScope(label),
      defaults: ToolSnippetDefaults.forLanguage(label, _lang.key),
      // 片段栏是「刻意插入模板」，这里才解析 $1/${1:默认}/$0。
      onInsert: (text) => _insertAtCursor(text, placeholders: true),
    );
  }


  /// 行号栏长按选行：第一次长按记录起始行，第二次长按选中两行之间的文本。
  void _onGutterLineLongPress(int line) {
    final controller = _controller;
    if (controller == null) return;

    final anchor = _gutterAnchorLine;
    if (anchor == null) {
      setState(() => _gutterAnchorLine = line);
      _toast(localizations.editorGutterAnchorSet(line + 1));
      return;
    }

    setState(() => _gutterAnchorLine = null);
    final a = anchor <= line ? anchor : line;
    final b = anchor <= line ? line : anchor;
    final offsets = _lineStartOffsets(controller.text);
    final start = a < offsets.length ? offsets[a] : controller.text.length;
    final end = (b + 1) < offsets.length ? offsets[b + 1] - 1 : controller.text.length;
    controller.selection = TextSelection(baseOffset: start, extentOffset: end);
    controller.scrollToLine(a);
    _toast(localizations.editorGutterRangeSelected(a + 1, b + 1));
  }

  /// 传给编辑器内核的行号长按回调。
  void _handleGutterLongPress(int line) => _onGutterLineLongPress(line);

  Future<void> _selectToLine() async {
    final controller = _controller;
    if (controller == null) return;
    final total = '\n'.allMatches(controller.text).length + 1;
    final startCtl = TextEditingController(text: '1');
    final endCtl = TextEditingController(text: '$total');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.editorSelectToLine),
        content: Row(children: [
          Expanded(
            child: TextField(
              controller: startCtl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: localizations.editorStartLine),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: endCtl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: localizations.editorEndLine),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(localizations.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(localizations.confirm)),
        ],
      ),
    );
    // 先把两个输入框的值取出来再 dispose：dispose 之后再读 .text 会抛
    // 「A TextEditingController was used after being disposed」。
    final startText = startCtl.text.trim();
    final endText = endCtl.text.trim();
    startCtl.dispose();
    endCtl.dispose();
    if (ok != true) return;

    final start = (int.tryParse(startText) ?? 1).clamp(1, total);
    final end = (int.tryParse(endText) ?? total).clamp(1, total);
    final a = start <= end ? start : end;
    final b = start <= end ? end : start;

    final offsets = _lineStartOffsets(controller.text);
    final base = offsets[a - 1];
    final extent = b < offsets.length ? offsets[b] - 1 : controller.text.length;
    controller.selection = TextSelection(baseOffset: base, extentOffset: extent);
    controller.scrollToLine(a - 1);
  }

  /// 每行起始处的 utf16 offset（下标 0-based）。
  static List<int> _lineStartOffsets(String text) {
    final offsets = <int>[0];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) offsets.add(i + 1);
    }
    return offsets;
  }

  Future<void> _replaceCurrentLine() async {
    final controller = _controller;
    if (controller == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final clip = data?.text ?? '';
    if (clip.isEmpty) {
      _toast(localizations.editorClipboardEmpty);
      return;
    }
    final text = controller.text;
    final sel = controller.selection;
    final offset = sel.isValid ? sel.start : 0;
    final lineStart = offset == 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;
    final nlIndex = text.indexOf('\n', offset);
    final hasTrailingNewline = nlIndex >= 0;
    final lineEnd = hasTrailingNewline ? nlIndex : text.length;
    final removeEnd = hasTrailingNewline ? lineEnd + 1 : lineEnd;
    final insert = (hasTrailingNewline && !clip.endsWith('\n')) ? '$clip\n' : clip;
    controller.text = text.replaceRange(lineStart, removeEnd, insert);
    controller.selection = TextSelection.collapsed(offset: lineStart + insert.length);
    _toast(localizations.editorReplacedLine);
  }

  // ---------- 行操作 / 大小写（VS Code 的「编辑」菜单） ----------

  /// 光标所在行范围。光标停在换行符之后时算下一行开头。
  ({int start, int end, bool hasNewline})? _currentLineSpan() {
    final controller = _controller;
    if (controller == null) return null;
    final text = controller.text;
    final sel = controller.selection;
    final raw = sel.isValid ? sel.extentOffset : 0;
    final off = raw.clamp(0, text.length);
    final start = off == 0 ? 0 : text.lastIndexOf('\n', off - 1) + 1;
    var nl = text.indexOf('\n', off);
    final hasNewline = nl >= 0;
    if (!hasNewline) nl = text.length;
    return (start: start, end: nl, hasNewline: hasNewline);
  }

  /// 「转到符号」：把当前文件的类 / 接口 / 枚举 / 命名空间 / 方法列出来，点一下跳过去。
  ///
  /// VS 里是 Ctrl+Shift+O。手机上没有快捷键，但这个列表在长文件里确实好用——
  /// 比来回滚动、或者用查找猜名字快得多。
  static final RegExp _symbolRe = RegExp(
    r'^[ \t]*(?:(?:public|private|protected|internal|static|async|override|virtual|abstract|sealed|partial|readonly|const|final|export|default)\s+)*'
    r'(?:(class|struct|interface|enum|record|namespace|func|function|def)\s+([A-Za-z_$][\w$]*)'
    r'|(?!(?:return|throw|new|await|yield|using|var|let|const|if|while|for|foreach|switch|case|else|do|try|catch|assert|print)\b)'
    r'([A-Za-z_$][\w$<>\[\],.?]*)\s+([A-Za-z_$][\w$]*)\s*\()',
    multiLine: true,
  );

  /// 状态栏点「语言」时弹的语言列表（手机上没有下拉框那么小的点击区，弹层更好点）。
  static const String _recentLangKey = 'text_editor_recent_langs_v1';

  Future<List<String>> _loadRecentLangs() async {
    try {
      return await SharedPreferencesAsync().getStringList(_recentLangKey) ?? const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _rememberLang(String label) async {
    if (label.isEmpty) return;
    try {
      final prefs = SharedPreferencesAsync();
      final list = (await prefs.getStringList(_recentLangKey)) ?? <String>[];
      list.remove(label);
      list.insert(0, label);
      if (list.length > 6) list.removeRange(6, list.length);
      await prefs.setStringList(_recentLangKey, list);
    } catch (_) {
      // 记不上不影响切语言
    }
  }

  Future<void> _showLanguagePicker() async {
    if (_langPickerOpen) return;
    _langPickerOpen = true;
    try {
      await _showLanguagePickerBody();
    } finally {
      _langPickerOpen = false;
    }
  }

  Future<void> _showLanguagePickerBody() async {
    final recent = await _loadRecentLangs();
    if (!mounted) return;
    final chosen = await showModalBottomSheet<_LangOption>(
      context: context,
      showDragHandle: true,
      // 带键盘搜索，必须让弹层跟着键盘让位。
      isScrollControlled: true,
      builder: (ctx) => _LanguagePickerSheet(
        langs: _langs,
        current: _lang.label,
        recent: recent,
      ),
    );
    if (chosen == null || !mounted || _doc == null) return;
    if (chosen.key == _lang.key && chosen.label == _lang.label) return;
    unawaited(_rememberLang(chosen.label));
    _applyLanguage(chosen);
  }

  /// 切换文档语言：清旧诊断、换规则集、重跑检查，并**重建编辑区**。
  ///
  /// 重建（换 widget key）是刻意的：内核的高亮器、段落缓存、折叠状态都是按语言
  /// 构建的，光换 Mode 对象在个别语言上会留下错乱的绘制状态（表现出来就是
  /// 布局/光标全乱）。重建一次的成本远小于「切过去就没法编辑」。
  void _applyLanguage(_LangOption chosen) {
    final doc = _doc;
    if (doc == null) return;
    setState(() => doc.langLabel = chosen.label);
    doc.lint = null;
    // 规则开关是按语言记的：切语言要换一份，并立刻重查。
    unawaited(_loadLintRules());
    _scheduleLint();
  }

  // ------------------------------ 转到定义（同文件） ------------------------------

  /// 同文件「转到定义」：光标在某个名字上时，去找它的声明并跳过去。
  ///
  /// 没有工程索引，只在当前文件里找——多数时候够用（改自己写的函数最常干的就是这个）。
  Future<void> _gotoDefinition() async {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final caret = controller.selection.extentOffset;
    if (caret < 0 || caret > text.length) return;
    final range = _wordRangeAt(text, caret);
    final name = text.substring(range.start, range.end);
    if (!_isSymbolName(name)) {
      _toast(localizations.editorNoDefinition);
      return;
    }
    final at = _findDeclaration(text, name, range.start);
    if (at == null) {
      // 同文件里没有声明 → 去其它已打开文档 / 同目录文件里找（跨文件「转到实现」）。
      // 只有一处定义时直接跳过去，不会多弹一层列表。
      await _showReferences(declarationsOnly: true);
      return;
    }
    controller.selection = TextSelection.collapsed(offset: at);
    controller.scrollToLine(_lineOfOffset(text, at));
  }


  /// 在文档里找 [name] 的声明位置（返回名字所在的偏移）。
  ///
  /// [skipOffset] 是当前光标所在的词，找不到别的声明时不要「跳到自己」。
  static int? _findDeclaration(String text, String name, int skipOffset) {
    for (final at in _declarationOffsets(text, name)) {
      // 光标所在的这一处多半就是「当前这个名字」本身，别跳到自己。
      if ((at - skipOffset).abs() < 1) continue;
      return at;
    }
    return null;
  }

  /// [name] 在文档里的**所有**声明位置（下标）。
  ///
  /// 与 [_findDeclaration] 同一套形态正则，区别是全量返回 —— 「工作区查找引用」
  /// 要靠它给每条命中打「定义 / 引用」标记。
  static List<int> _declarationOffsets(String text, String name) {
    final escaped = RegExp.escape(name);
    final patterns = <RegExp>[
      RegExp(r'\b(?:class|struct|interface|enum|record|namespace)\s+' + escaped + r'\b'),
      RegExp(r'\b' + escaped + r'\s*\([^()]*\)\s*(?:\{|=>|;|:(?=\s*(?:\n|$)))'),
      RegExp(r'\b(?:var|let|const|val|final|int|long|double|float|bool|string|char|byte|decimal|object|dynamic|auto|[A-Z][\w<>\[\],.?]*)\s+'
          + escaped +
          r'\b\s*(?:=|;|,)'),
    ];
    final out = <int>[];
    for (final re in patterns) {
      for (final m in re.allMatches(text)) {
        final at = m.start + m.group(0)!.indexOf(name);
        if (out.contains(at)) continue;
        // 函数形态要确认前面确实是「声明」（`Foo();` 是调用，不是定义）。
        if (re.pattern.contains(r'\(') && !_looksLikeDeclHead(text, m.start)) continue;
        out.add(at);
      }
    }
    return out;
  }

  /// 「工作区扫描」按扩展名跳过的二进制 / 归档文件。
  static const List<String> _skipScanExts = [
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.ico', '.svgz',
    '.pdf', '.zip', '.apk', '.aab', '.jar', '.aar', '.so', '.dll', '.dylib',
    '.class', '.dex', '.mp3', '.mp4', '.mov', '.avi', '.mkv', '.m4a', '.wav',
    '.ttf', '.otf', '.woff', '.woff2', '.exe', '.bin', '.dat', '.db', '.sqlite',
    '.xlsx', '.docx', '.pptx', '.doc', '.xls', '.ppt', '.7z', '.rar', '.gz', '.bz2',
    '.a', '.o', '.obj', '.keystore', '.jks', '.p12', '.pfx', '.crx', '.pak',
  ];

  // ------------------------------ 参考高亮（括号配对 / 当前词） ------------------------------

  /// VS 的两个「参考高亮」：光标贴在括号上时把配对的那一对点亮；光标在某个词上时
  /// 把这个词在本文件里的所有出现处淡淡标出来。
  ///
  /// 走内核的 `extraHighlights` 通道（和查找高亮分开），所以开查找不会把它冲掉。
  void _refreshExtraHighlights() {
    final controller = _doc?.controller;
    if (controller == null) return;
    final text = controller.text;
    final sel = controller.selection;
    final caret = sel.isValid ? sel.extentOffset.clamp(0, text.length) : 0;
    final list = <SearchHighlight>[];

    // 1) 全篇括号着色（可关）：整篇按嵌套深度上淡色，扫一眼就能看出块结构。
    list.addAll(_allBracketHighlights(text));

    // 1b) 包住光标的括号链：颜色更深，画在全篇之上（后加的会覆盖先画的）。
    //     全篇那些是「淡底」，这里才是「你现在在哪一层」。
    final chain = _enclosingBracketChain(text, caret);
    for (var i = 0; i < chain.length; i++) {
      final pair = chain[i];
      final color = _bracketColors[i % _bracketColors.length];
      list.add(SearchHighlight(
          start: pair.$1, end: pair.$1 + 1, isCurrentMatch: i == 0, color: color));
      list.add(SearchHighlight(
          start: pair.$2, end: pair.$2 + 1, isCurrentMatch: i == 0, color: color));
    }

    // 2) 多选编辑进行中：只标「已圈中的那几处」。
    //    这时再按整篇同词高亮会看混——用户关心的是「我选了哪几个」。
    if (_multiSel.isNotEmpty) {
      if (sel.isValid && sel.start != sel.end) {
        list.add(SearchHighlight(start: sel.start, end: sel.end, isCurrentMatch: true));
      }
      for (final r in _multiSel) {
        list.add(SearchHighlight(start: r.start, end: r.end));
      }
      if (_sameHighlights(controller.extraHighlights, list)) return;
      controller.extraHighlights = list;
      controller.extraHighlightsChanged = true;
      controller.notifyListeners();
      return;
    }

    // 3) 当前词的所有出现
    //    大文件（>50 万字符）里这一步每次光标移动都要全文扫一遍，直接把开关忽略掉；
    //    括号配对仍然保留（那只扫光标附近）。
    if (_prefs.highlightOccurrences && text.length <= 500000) {
      var start = sel.isValid ? sel.start : caret;
      var end = sel.isValid ? sel.end : caret;
      if (start == end) {
        final range = _wordRangeAt(text, caret);
        start = range.start;
        end = range.end;
      }
      if (end > start) {
        final word = text.substring(start, end);
        if (word.length >= 2 && word.length <= 60 && !word.contains('\n')) {
          // 先数一遍（上限 201）：`return`、`}` 这种满屏都是的词全部上色反而看不清重点。
          var total = 0;
          for (var i = text.indexOf(word); i >= 0 && total <= 200; i = text.indexOf(word, i + word.length)) {
            total++;
          }
          if (total <= 200) {
            for (var i = text.indexOf(word); i >= 0; i = text.indexOf(word, i + word.length)) {
              list.add(SearchHighlight(start: i, end: i + word.length));
            }
          }
        }
      }
    }

    if (_sameHighlights(controller.extraHighlights, list)) return;
    controller.extraHighlights = list;
    controller.extraHighlightsChanged = true;
    controller.notifyListeners();
  }

  static bool _sameHighlights(List<SearchHighlight> a, List<SearchHighlight> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].start != b[i].start ||
          a[i].end != b[i].end ||
          a[i].isCurrentMatch != b[i].isCurrentMatch ||
          a[i].color != b[i].color) {
        return false;
      }
    }
    return true;
  }

  /// 括号嵌套的配色（由内到外）。半透明，深浅主题下都能看见。
  static const List<Color> _bracketColors = <Color>[
    Color(0x44FFB300),
    Color(0x4481C784),
    Color(0x4464B5F6),
    Color(0x44BA68C8),
    Color(0x44F06292),
    Color(0x444DD0E1),
  ];

  /// 全篇括号着色用的更淡一档：整篇都有底色时，太重会盖住语法高亮。
  static const List<Color> _bracketColorsSoft = <Color>[
    Color(0x26FFB300),
    Color(0x2681C784),
    Color(0x2664B5F6),
    Color(0x26BA68C8),
    Color(0x26F06292),
    Color(0x264DD0E1),
  ];

  // 全篇括号扫描的缓存：光标移动时文本没变就不重扫。
  String _bracketScanKey = '';
  List<SearchHighlight> _bracketScanCache = const <SearchHighlight>[];

  // ── minimap / 粘性滚动 ──────────────────────────────────────────────
  // 纵向滚动的像素偏移与视口像素高：minimap 的视口框、粘性滚动的「顶部行」都靠它。
  double _vOffset = 0;
  double _vViewportH = 0;
  // 每滚一点就递增，驱动 minimap 局部重绘（不走 setState，否则整页重建会卡）。
  final ValueNotifier<int> _scrollTick = ValueNotifier<int>(0);
  // 粘性滚动当前钉住的那条符号链。只在「顶部行变了」时更新。
  final ValueNotifier<List<_SymbolItem>> _stickyTrail = ValueNotifier<List<_SymbolItem>>(const []);
  int _stickyLine = -1;
  // 交给 CodeForge 用的纵向 ScrollController（内核支持外部注入）。
  // 用 controller 而不是拦 ScrollNotification：内核内部如果 return true 就把通知吞了。
  final ScrollController _vScroll = ScrollController();

  /// 断点行（0-based）。只对 JS 有意义（内置引擎），其它语言点了会提示没有运行时。
  final Set<int> _breakpoints = <int>{};

  bool get _minimapOn => _prefs.minimap && !_smooth;
  bool get _stickyOn => _prefs.stickyScroll && !_smooth;

  /// 单行像素高：CodeForge 的 _lineHeight = fontSize × textStyle.height。
  double get _linePixelHeight {
    final h = _prefs.fontSize * _prefs.lineHeight;
    return h <= 0 ? 16 : h;
  }

  /// 全篇括号按嵌套深度着色（VS 的 bracket pair colorization）。
  ///
  /// 单遍扫描，跳过字符串 / 行注释 / 块注释。两处限制：
  ///   * 文本 > 20 万字符不扫（每次移动光标都全文扫一遍会明显卡）；
  ///   * 最多 3000 个括号（再多的文件本来也看不清颜色）。
  List<SearchHighlight> _allBracketHighlights(String text) {
    if (!_prefs.rainbowBrackets || text.length > 200000) {
      return const <SearchHighlight>[];
    }
    final key = '${text.length}|${text.hashCode}';
    if (key == _bracketScanKey) return _bracketScanCache;

    final out = <SearchHighlight>[];
    var depth = 0;
    var i = 0;
    String? quote;
    var lineComment = false;
    var blockComment = false;
    while (i < text.length && out.length < 3000) {
      final c = text[i];
      final next = i + 1 < text.length ? text[i + 1] : '';
      if (lineComment) {
        if (c == '\n') lineComment = false;
        i++;
        continue;
      }
      if (blockComment) {
        if (c == '*' && next == '/') {
          blockComment = false;
          i += 2;
          continue;
        }
        i++;
        continue;
      }
      if (quote != null) {
        if (c == '\\') {
          i += 2;
          continue;
        }
        if (c == quote) quote = null;
        i++;
        continue;
      }
      if (c == '/' && next == '/') {
        lineComment = true;
        i += 2;
        continue;
      }
      if (c == '/' && next == '*') {
        blockComment = true;
        i += 2;
        continue;
      }
      if (c == '"' || c == "'" || c == '`') {
        quote = c;
        i++;
        continue;
      }
      if (c == '(' || c == '[' || c == '{') {
        out.add(SearchHighlight(
            start: i, end: i + 1, color: _bracketColorsSoft[depth % _bracketColorsSoft.length]));
        depth++;
        i++;
        continue;
      }
      if (c == ')' || c == ']' || c == '}') {
        if (depth > 0) depth--;
        out.add(SearchHighlight(
            start: i, end: i + 1, color: _bracketColorsSoft[depth % _bracketColorsSoft.length]));
        i++;
        continue;
      }
      i++;
    }
    _bracketScanKey = key;
    _bracketScanCache = out;
    return out;
  }

  /// 包住光标的括号链，由内到外，最多 [maxDepth] 层。
  ///
  /// 每层返回一对位置。用来做「括号对着色」：同一层的一对括号同色，越外层颜色越不同。
  static List<(int, int)> _enclosingBracketChain(String text, int caret, {int maxDepth = 4}) {
    final out = <(int, int)>[];
    if (text.isEmpty) return out;
    var pos = caret.clamp(0, text.length);
    while (out.length < maxDepth) {
      int? open;
      var depth = 0;
      // 往前找最近的、在 pos 之前还没闭合的开括号。扫太远就放弃（别把光标移动做成 O(n²)）。
      final limit = (pos - 20000).clamp(0, text.length);
      for (var i = pos - 1; i >= limit; i--) {
        final c = text[i];
        if (c == ')' || c == ']' || c == '}') {
          depth++;
        } else if (c == '(' || c == '[' || c == '{') {
          if (depth == 0) {
            open = i;
            break;
          }
          depth--;
        }
      }
      if (open == null) break;
      final close = _findClosing(text, open, text[open]);
      if (close == null) break;
      if (close < pos) {
        // 这一对在光标之前就闭合了，不是「包住光标的」，继续往外看。
        pos = open;
        continue;
      }
      out.add((open, close));
      pos = open;
    }
    return out;
  }

  // ------------------------------ minimap / 粘性滚动 ------------------------------

  /// 纵向滚动回调：只记数值，滚动时绝不 setState（滚一帧重建整页会明显卡）。
  void _onVScroll() {
    final ps = _vScroll.positions;
    if (ps.isEmpty) return;
    // 用 positions.last 而不是 position：Key 变化重建的瞬间可能挂着两个 position。
    final p = ps.last;
    final off = p.pixels;
    final vh = p.viewportDimension;
    if ((off - _vOffset).abs() < 0.5 && (vh - _vViewportH).abs() < 0.5) return;
    _vOffset = off;
    _vViewportH = vh;
    if (_minimapOn) _scrollTick.value++;
    _syncSticky();
  }

  /// 粘性滚动：视口顶部那行属于哪条符号链（`Class › Method`），变了才更新。
  ///
  /// 用 ValueNotifier 而不是 setState：滚动过程中这里会被调用几十次，
  /// 每次重建整个编辑器页面的话滚动手感就废了。
  void _syncSticky() {
    if (!_stickyOn) {
      if (_stickyTrail.value.isNotEmpty) _stickyTrail.value = const <_SymbolItem>[];
      return;
    }
    final doc = _doc;
    if (doc == null) return;
    final topLine = (_vOffset / _linePixelHeight).floor() + 1;
    if (topLine == _stickyLine) return;
    _stickyLine = topLine;
    final items = _collectSymbols(doc.text);
    _stickyTrail.value = items.isEmpty ? const <_SymbolItem>[] : _symbolTrail(items, topLine);
  }

  /// 顶部钉住的那条面包屑（VS Code 的 sticky scroll）。
  Widget _stickyBar() {
    return ValueListenableBuilder<List<_SymbolItem>>(
      valueListenable: _stickyTrail,
      builder: (ctx, trail, __) {
        if (trail.isEmpty) return const SizedBox.shrink();
        final color = Theme.of(ctx).colorScheme;
        // 只显示最后两层：手机宽度有限，再往上挤就全是省略号了。
        final shown = trail.length > 2 ? trail.sublist(trail.length - 2) : trail;
        return Container(
          height: 22,
          padding: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            color: color.surface.withValues(alpha: 0.94),
            border: Border(bottom: BorderSide(color: Theme.of(ctx).dividerColor, width: 0.4)),
          ),
          child: Row(children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) Icon(Icons.chevron_right, size: 12, color: color.onSurfaceVariant),
              Flexible(
                child: InkWell(
                  onTap: () => _controller?.scrollToLine(shown[i].line),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                    child: Text(
                      shown[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: color.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            ],
          ]),
        );
      },
    );
  }

  /// 右侧代码缩略图：整篇压成一条，点哪滚哪，拖动也能滚。
  Widget _minimap(String text) {
    final color = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (ctx, c) {
      final h = c.maxHeight;
      void jumpTo(double dy) {
        if (h <= 0 || text.isEmpty) return;
        final total = _lineCountOf(text);
        if (total <= 1) return;
        final line = (dy / h * total).floor().clamp(0, total - 1).toInt();
        _controller?.scrollToLine(line);
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => jumpTo(d.localPosition.dy),
        onVerticalDragUpdate: (d) => jumpTo(d.localPosition.dy),
        child: Container(
          decoration: BoxDecoration(
            color: color.surfaceContainerHighest.withValues(alpha: 0.45),
            border: Border(left: BorderSide(color: Theme.of(ctx).dividerColor, width: 0.5)),
          ),
          child: ValueListenableBuilder<int>(
            valueListenable: _scrollTick,
            builder: (ctx2, _, __) => CustomPaint(
              painter: _MiniMapPainter(
                text: text,
                lineH: _linePixelHeight,
                offset: _vOffset,
                viewportH: _vViewportH,
                fg: color.onSurface,
                accent: color.primary,
              ),
            ),
          ),
        ),
      );
    });
  }

  static int _lineCountOf(String text) {
    var n = 1;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) n++;
    }
    return n;
  }

  // ------------------------------ 参数签名提示 ------------------------------

  /// 从 [close] 处的闭括号往前找配对的开括号（同样带 2 万字符上限）。
  static int? _findOpening(String text, int close, String ch) {
    const pairs = <String, String>{')': '(', ']': '[', '}': '{'};
    final open = pairs[ch];
    if (open == null) return null;
    var depth = 0;
    final limit = (close - 20000).clamp(0, text.length);
    for (var i = close; i >= limit; i--) {
      final c = text[i];
      if (c == ch) {
        depth++;
      } else if (c == open) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return null;
  }

  /// 从 [open] 处的开括号往后找配对的闭括号（同样带 2 万字符上限）。
  static int? _findClosing(String text, int open, String ch) {
    const pairs = <String, String>{'(': ')', '[': ']', '{': '}'};
    final close = pairs[ch];
    if (close == null) return null;
    var depth = 0;
    final limit = (open + 20000).clamp(0, text.length);
    for (var i = open; i < limit; i++) {
      final c = text[i];
      if (c == ch) {
        depth++;
      } else if (c == close) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return null;
  }

  /// 光标在某个调用的括号里时，给出「这个函数的签名 + 现在在第几个参数」。
  ///
  /// 没有语义分析，签名只能从**当前文档里**找声明（参数长得像「类型 名字」才算）。
  /// 找不到就不显示——宁可没有，也不要瞎猜一个错签名给用户看。
  /// 签名缓存：`函数名 → 参数列表`（找不到时存 null）。
  ///
  /// 这个函数在**每次光标移动**时都会被调用（签名条自己监听 controller 重建），
  /// 如果每次都全文正则扫一遍，大文件里光标走一步卡一下。所以按「文本是否同一个对象」
  /// 缓存——文本一变（String 不可变）缓存整体作废。
  String? _sigCacheText;
  final Map<String, List<String>?> _sigCache = <String, List<String>?>{};

  ({String name, List<String> params, int active})? _resolveSignature() {
    final doc = _doc;
    final controller = doc?.controller;
    if (doc == null || controller == null) return null;
    if (!_programming) return null;
    final text = controller.text;
    final caret = controller.selection.extentOffset;
    if (caret <= 0 || caret > text.length) return null;

    // 1) 向上找未闭合的 `(`；碰到语句边界就放弃（别跨语句猜）。
    var i = caret - 1;
    var depth = 0;
    var open = -1;
    while (i >= 0) {
      final c = text[i];
      if (c == ')') {
        depth++;
      } else if (c == '(') {
        if (depth == 0) {
          open = i;
          break;
        }
        depth--;
      } else if (c == ';' || c == '{' || c == '}') {
        return null;
      }
      i--;
    }
    if (open < 0) return null;

    // 2) 取函数名（允许 a.b.c）
    var j = open - 1;
    while (j >= 0 && (text[j] == ' ' || text[j] == '\t')) {
      j--;
    }
    final nameEnd = j + 1;
    while (j >= 0) {
      final c = text[j];
      if (RegExp(r'[\w$]').hasMatch(c) || c == '.') {
        j--;
      } else {
        break;
      }
    }
    final full = text.substring(j + 1, nameEnd);
    if (full.isEmpty) return null;
    final simple = full.contains('.') ? full.substring(full.lastIndexOf('.') + 1) : full;
    if (!RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(simple)) return null;
    // `if (` / `for (` / `new Foo(` 之类不是「函数调用」，别硬找签名。
    if (_sigKeywordBlacklist.contains(simple)) return null;

    // 3) 当前在第几个参数：数光标前的顶层逗号。
    var active = 0;
    var d = 0;
    for (var k = open + 1; k < caret; k++) {
      final c = text[k];
      if (c == '(' || c == '[' || c == '{') {
        d++;
      } else if (c == ')' || c == ']' || c == '}') {
        d--;
      } else if (c == ',' && d == 0) {
        active++;
      }
    }

    // 4) 在文档里找声明
    if (!identical(_sigCacheText, text)) {
      _sigCache.clear();
      _sigCacheText = text;
    }
    List<String>? parts;
    if (_sigCache.containsKey(simple)) {
      parts = _sigCache[simple];
    } else {
      final declRe = RegExp(
          r'\b' + RegExp.escape(simple) + r'\s*\(([^()]*)\)\s*(?:\{|=>|;|:(?=\s*(?:\n|$)))');
      for (final m in declRe.allMatches(text)) {
        if (m.start < caret && m.end > open) continue; // 跳过光标这次调用本身
        if (!_looksLikeDeclHead(text, m.start)) continue;
        final raw = m.group(1)!;
        if (!_looksLikeParams(raw)) continue;
        parts = _splitParams(raw);
        break;
      }
      _sigCache[simple] = parts;
    }
    if (parts == null) return null;
    // 无参函数（`Foo()`）：parts 为空，clamp 的上下界会反过来，必须单独处理。
    return (
      name: simple,
      params: parts,
      active: parts.isEmpty ? 0 : active.clamp(0, parts.length - 1),
    );
  }

  static List<String> _splitParams(String raw) {
    final parts = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < raw.length; i++) {
      final c = raw[i];
      if (c == '(' || c == '[' || c == '{' || c == '<') {
        depth++;
      } else if (c == ')' || c == ']' || c == '}' || c == '>') {
        depth--;
      } else if (c == ',' && depth == 0) {
        parts.add(raw.substring(start, i).trim());
        start = i + 1;
      }
    }
    final tail = raw.substring(start).trim();
    if (tail.isNotEmpty || parts.isNotEmpty) parts.add(tail);
    return parts;
  }

  static const Set<String> _sigKeywordBlacklist = <String>{
    'if', 'for', 'foreach', 'while', 'switch', 'catch', 'using', 'lock', 'fixed', //
    'return', 'new', 'throw', 'sizeof', 'typeof', 'nameof', 'default', 'assert',
  };

  /// 声明前面应该有「修饰符 + 返回类型」，否则就是一次调用语句（`Foo();`）。
  static bool _looksLikeDeclHead(String text, int at) {
    final lineStart = at <= 0 ? 0 : text.lastIndexOf('\n', at - 1) + 1;
    final head = text.substring(lineStart, at);
    if (head.trim().isEmpty) return false;
    // 行内已经出现赋值/括号/逗号，说明我们在一个表达式里（`var x = Foo(`），不是声明。
    if (head.contains('=') || head.contains('(') || head.contains(',')) return false;
    // Python / JS 的函数声明没有返回类型：`def foo(` / `function foo(` / `fn foo(`。
    if (RegExp(r'^\s*(?:def|fn|fun|function|func)\s+$').hasMatch(head)) return true;
    return RegExp(
            r'^(?:\s*)(?:(?:public|private|protected|internal|static|async|override|virtual|abstract|sealed|extern|unsafe|partial|synchronized|export|function|fun|def|fn)\s+)*'
            r'[\w<>\[\],.?:]+\s+$')
        .hasMatch(head);
  }

  static final RegExp _paramRe = RegExp(
      r'^(?:\[[^\]]*\]\s*)*(?:(?:this|ref|out|in|params|scoped)\s+)*'
      r'[A-Za-z_$][\w$]*(?:<[^>]*>)?(?:\[\])?\??\s+[A-Za-z_$][\w$]*\s*(?:=.*)?$');

  /// 参数段是否像「类型 名字」（用来区分声明和调用）。
  static bool _looksLikeParams(String raw) {
    final parts = _splitParams(raw);
    for (final p in parts) {
      if (p.isEmpty) continue;
      if (!_paramRe.hasMatch(p)) return false;
    }
    return true;
  }

  // ---------- 多选编辑（VS 的 Ctrl+D 累加，移动端做成「先圈出来，再一次性改」）----------

  /// 除主选区之外的其它选区（按位置升序、互不重叠）。
  ///
  /// 内核只有「单个选区 + 多个插入点」，画不出 VS 那种多个光标同时打字的效果；
  /// 手机上边打字边盯几处光标本来也不好使。所以这里换了交互：
  /// **先把要改的地方一个个圈出来（加入下一个出现处），再一次性替换 / 删除 / 改大小写。**
  final List<({int start, int end})> _multiSel = <({int start, int end})>[];

  /// 多选时共享的那个词（只用来提示与预填输入框）。
  String _multiWord = '';

  /// 主选区 + 多选区，排好序并合并重叠。
  List<({int start, int end})> _allSelectionRanges() {
    final controller = _controller;
    if (controller == null) return const <({int start, int end})>[];
    final text = controller.text;
    final sel = controller.selection;
    final out = <({int start, int end})>[..._multiSel];
    if (sel.isValid && sel.start != sel.end) {
      out.add((
        start: sel.start.clamp(0, text.length),
        end: sel.end.clamp(0, text.length),
      ));
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    final merged = <({int start, int end})>[];
    for (final r in out) {
      if (merged.isNotEmpty && r.start <= merged.last.end) {
        final last = merged.removeLast();
        merged.add((start: last.start, end: r.end > last.end ? r.end : last.end));
      } else {
        merged.add(r);
      }
    }
    return merged;
  }

  /// 「加入下一个出现处」：第一次先把光标下的词选起来，之后每按一次多收一处。
  void _addNextOccurrence() {
    final controller = _controller;
    if (controller == null) return;
    // 反过来：用多选区取代多光标时，先清掉多光标（否则打字仍走 insertAtAllCursors）。
    if (controller.hasMultiCursors) controller.clearMultiCursors();
    final text = controller.text;
    final sel = controller.selection;
    if (!sel.isValid) return;
    var start = sel.start.clamp(0, text.length);
    var end = sel.end.clamp(0, text.length);

    // 空选区（或跨行选区）：先选中光标下的词，进入多选模式的第一步。
    if (start == end || text.substring(start, end).contains('\n')) {
      final range = _wordRangeAt(text, start == end ? start : sel.extentOffset);
      if (range.end <= range.start) return;
      _multiSel.clear();
      _multiWord = text.substring(range.start, range.end);
      controller.selection = TextSelection(baseOffset: range.start, extentOffset: range.end);
      _toast(localizations.editorMultiSelCount('1'));
      setState(() {});
      _refreshExtraHighlights();
      return;
    }

    final word = _multiSel.isEmpty ? text.substring(start, end) : _multiWord;
    if (word.isEmpty) return;
    if (_multiSel.isEmpty) _multiWord = word;

    if (!_multiSel.any((r) => r.start == start && r.end == end)) {
      _multiSel.add((start: start, end: end));
    }
    // 已经收进来的位置不能重复收，否则会「加了两次同一处」。
    final taken = <int>{for (final r in _multiSel) r.start};

    var next = -1;
    for (var i = text.indexOf(word, end); i >= 0; i = text.indexOf(word, i + word.length)) {
      if (!taken.contains(i)) {
        next = i;
        break;
      }
    }
    if (next < 0) {
      for (var i = text.indexOf(word); i >= 0 && i < end; i = text.indexOf(word, i + word.length)) {
        if (!taken.contains(i)) {
          next = i;
          break;
        }
      }
    }
    if (next < 0) {
      // 全都收完了：保持现状，只提示一声。
      setState(() {});
      _refreshExtraHighlights();
      _toast(localizations.editorMultiSelNoMore);
      return;
    }
    controller.selection = TextSelection(baseOffset: next, extentOffset: next + word.length);
    controller.scrollToLine(_lineOfOffset(text, next));
    setState(() {});
    _refreshExtraHighlights();
    _toast(localizations.editorMultiSelCount('${_multiSel.length + 1}'));
  }

  /// 清空多选，回到普通单选状态。
  void _clearMultiSel() {
    if (_multiSel.isEmpty && _multiWord.isEmpty) return;
    setState(() {
      _multiSel.clear();
      _multiWord = '';
    });
    _refreshExtraHighlights();
  }

  /// 对所有选区做一次性批量编辑。
  ///
  /// 直接重建整篇文本，而不是循环 `replaceRange`：一次赋值只产生**一条**撤销记录，
  /// 也不会因为逐个替换让后面的偏移整体漂移。
  void _editSelections(String Function(String selected) transform) {
    final controller = _controller;
    if (controller == null) return;
    final ranges = _allSelectionRanges();
    if (ranges.isEmpty) return;
    final text = controller.text;
    final after = <({int start, int end})>[];
    // 从后往前替换：前面的偏移不受影响，而且每段是一次 replaceRange，
    // 撤销的时候是「一段」而不是「整篇回到打开时」。
    for (var i = ranges.length - 1; i >= 0; i--) {
      final r = ranges[i];
      final replaced = transform(text.substring(r.start, r.end));
      controller.replaceRange(r.start, r.end, replaced);
      after.insert(0, (start: r.start, end: r.start + replaced.length));
    }
    _multiSel.clear();
    _multiWord = '';
    final result = controller.text;
    if (after.isNotEmpty) {
      // 光标落在最后一处（VS 里改完焦点也留在最后一个光标上）。
      final last = after.last;
      controller.selection = TextSelection(baseOffset: last.start, extentOffset: last.end);
      controller.scrollToLine(_lineOfOffset(result, last.start));
    }
    setState(() {});
    _refreshExtraHighlights();
  }

  /// 批量替换：问一次新文本，然后所有选区都换成它。
  Future<void> _promptReplaceSelections() async {
    final ranges = _allSelectionRanges();
    if (ranges.isEmpty) return;
    final input = TextEditingController(text: _multiWord);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.editorMultiSelReplace('${ranges.length}')),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: InputDecoration(labelText: localizations.editorReplaceWith),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localizations.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, input.text), child: Text(localizations.confirm)),
        ],
      ),
    );
    input.dispose();
    if (!mounted || value == null) return;
    _editSelections((_) => value);
  }

  /// 重命名符号（VS 的 F2 简化版）：只改**同文件内整词出现处**，且要求这里确实是声明。
  ///
  /// 不弹「重命名」面板是因为手机上多一步操作收益很低；
  /// 关键是把「找不到声明就别乱改」这条守住——否则一次误触能把整篇的通用词改掉。
  /// 扫描全文的标签（HTML/XML/Vue…），返回每个标签名在文本里的区间。
  ///
  /// 只处理标签名，不解析属性——重命名只需要知道「哪些地方是同名的开/闭标签」。
  /// 注释、`<!DOCTYPE>`、`<?xml?>` 直接跳过，否则里面的 `<` 会被当成标签。
  static List<_TagRef> _scanTags(String text) {
    final out = <_TagRef>[];
    if (text.isEmpty || text.length > 2000000) return out;
    var i = 0;
    final n = text.length;
    while (i < n) {
      final lt = text.indexOf('<', i);
      if (lt < 0 || lt + 1 >= n) break;
      if (text.startsWith('<!--', lt)) {
        final end = text.indexOf('-->', lt + 4);
        i = end < 0 ? n : end + 3;
        continue;
      }
      if (text.startsWith('<!', lt) || text.startsWith('<?', lt)) {
        final end = text.indexOf('>', lt);
        i = end < 0 ? n : end + 1;
        continue;
      }
      var p = lt + 1;
      final closing = text[p] == '/';
      if (closing) p++;
      final nameStart = p;
      if (p >= n || !_isTagNameStart(text.codeUnitAt(p))) {
        i = lt + 1;
        continue;
      }
      while (p < n && _isTagNameChar(text.codeUnitAt(p))) {
        p++;
      }
      final gt = text.indexOf('>', p);
      final tagEnd = gt < 0 ? n : gt;
      // 自闭合：'>' 前（跳过空白）是 '/'。
      var q = tagEnd - 1;
      while (q > p && (text.codeUnitAt(q) == 32 || text.codeUnitAt(q) == 9 || text.codeUnitAt(q) == 10 || text.codeUnitAt(q) == 13)) {
        q--;
      }
      final selfClosing = !closing && q >= p && text.codeUnitAt(q) == 47;
      out.add(_TagRef(
        name: text.substring(nameStart, p),
        nameStart: nameStart,
        nameEnd: p,
        closing: closing,
        selfClosing: selfClosing,
      ));
      i = gt < 0 ? n : gt + 1;
    }
    return out;
  }

  static bool _isTagNameStart(int c) =>
      (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 58;

  static bool _isTagNameChar(int c) =>
      _isTagNameStart(c) || (c >= 48 && c <= 57) || c == 45 || c == 46;

  /// 重命名光标所在的标签，开标签与闭标签一起改。
  ///
  /// 文本编辑器里改 `<div>` 却忘了下面的 `</div>`，是结构化文本最常见的低级错误；
  /// 而且要改的地方常隔着几十行，靠肉眼找配对很容易漏。
  Future<void> _renamePairedTag() async {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final caret = controller.selection.baseOffset;
    if (caret < 0) return;
    final tags = _scanTags(text);
    if (tags.isEmpty) {
      _toast(localizations.editorNoTagHere);
      return;
    }
    // 光标落在哪个标签上：优先取「包含光标」的名字区间，
    // 其次取光标前最近的那个标签（光标常停在标签右边一格）。
    int index = -1;
    for (var k = 0; k < tags.length; k++) {
      if (caret >= tags[k].nameStart && caret <= tags[k].nameEnd) {
        index = k;
        break;
      }
    }
    if (index < 0) {
      for (var k = tags.length - 1; k >= 0; k--) {
        if (tags[k].nameEnd <= caret) {
          index = k;
          break;
        }
      }
    }
    if (index < 0) {
      _toast(localizations.editorNoTagHere);
      return;
    }
    final hit = tags[index];
    if (hit.selfClosing) {
      _toast(localizations.editorTagSelfClosing);
      return;
    }
    // 找配对：开标签往后数深度，闭标签往前数。
    _TagRef? pair;
    if (!hit.closing) {
      var depth = 0;
      for (var k = index + 1; k < tags.length; k++) {
        final t = tags[k];
        if (t.name != hit.name) continue;
        if (t.closing) {
          depth--;
          if (depth == 0) {
            pair = t;
            break;
          }
        } else if (!t.selfClosing) {
          depth++;
        }
      }
    } else {
      var depth = 0;
      for (var k = index - 1; k >= 0; k--) {
        final t = tags[k];
        if (t.name != hit.name) continue;
        if (!t.closing) {
          if (!t.selfClosing) {
            depth--;
            if (depth == 0) {
              pair = t;
              break;
            }
          }
        } else {
          depth++;
        }
      }
    }
    if (pair == null) {
      _toast(localizations.editorTagNoPair);
      return;
    }

    final input = TextEditingController(text: hit.name);
    input.selection = TextSelection(baseOffset: 0, extentOffset: hit.name.length);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.editorRenamePair),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: InputDecoration(labelText: localizations.editorRenamePairHint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localizations.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, input.text), child: Text(localizations.confirm)),
        ],
      ),
    );
    input.dispose();
    if (!mounted || next == null) return;
    final newName = next.trim();
    if (newName.isEmpty || newName == hit.name) return;
    if (!RegExp(r'^[A-Za-z_:][A-Za-z0-9_:.\-]*$').hasMatch(newName)) {
      _toast(localizations.editorRenameInvalid);
      return;
    }
    // 从后往前替换，前面那处的偏移才不会被后面那次替换改写。
    final ranges = <_TagRef>[hit, pair]..sort((a, b) => b.nameStart.compareTo(a.nameStart));
    for (final r in ranges) {
      controller.replaceRange(r.nameStart, r.nameEnd, newName);
    }
    _toast('${localizations.editorRenamePair}: $newName');
  }

  /// 块选择：把当前选区理解成一个矩形，按列复制并给每行同一列加光标。
  ///
  /// 内核只支持「插入点」不支持「多选区」，所以这里做的是它在那套模型下
  /// 能达到的等价效果：矩形内容进剪贴板（按列），每行右边界立一个光标，
  /// 接着打字就是各行的同列同时插入。
  void _boxSelect() {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final sel = controller.selection;
    if (!sel.isValid) return;
    var a = sel.start.clamp(0, text.length);
    var b = sel.end.clamp(0, text.length);
    if (a > b) {
      final t = a;
      a = b;
      b = t;
    }
    if (a == b) {
      _toast(localizations.diffSelectFirst);
      return;
    }
    final lineA = _lineOfOffset(text, a);
    final lineB = _lineOfOffset(text, b);
    if (lineA == lineB) {
      _toast(localizations.editorRectSingleLine);
      return;
    }
    final offA = _offsetOfLine(text, lineA);
    final offB = _offsetOfLine(text, lineB);
    final colA = a - offA;
    final colB = b - offB;
    final c1 = colA < colB ? colA : colB;
    final c2 = colA < colB ? colB : colA;

    final picked = <String>[];
    controller.clearMultiCursors();
    for (var line = lineA; line <= lineB; line++) {
      final start = _offsetOfLine(text, line);
      final nextStart = _offsetOfLine(text, line + 1);
      // 行末不含换行符：下一行的起点前一位（\n）要去掉。
      var end = nextStart;
      if (end > start && end <= text.length && text.codeUnitAt(end - 1) == 10) end--;
      final len = end - start;
      final from = c1 < len ? c1 : len;
      final to = c2 < len ? c2 : len;
      picked.add(from < to ? text.substring(start + from, start + to) : '');
      // 光标立在矩形右边界（超出实际行长时退到行末）。
      controller.addMultiCursor(line, to);
    }
    controller.selection = TextSelection.collapsed(offset: a);
    unawaited(Clipboard.setData(ClipboardData(text: picked.join('\n'))));
    _toast(localizations.editorRectCopied(picked.length));
  }

  Future<void> _renameSymbol() async {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final caret = controller.selection.baseOffset;
    final range = _wordRangeAt(text, caret < 0 ? 0 : caret);
    final name = text.substring(range.start, range.end);
    // 光标停在空白/标点上时，`_wordRangeAt` 会返回那一个字符：
    // 不拦住的话「重命名」会预填一个空格，确认后全文件的空格全被替换。
    if (!_isSymbolName(name)) return;
    if (_findDeclaration(text, name, range.start) == null) {
      _toast(localizations.editorRenameNoDecl);
      return;
    }
    final input = TextEditingController(text: name);
    input.selection = TextSelection(baseOffset: 0, extentOffset: name.length);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.editorRename),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: InputDecoration(labelText: localizations.editorRenameHint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localizations.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, input.text), child: Text(localizations.confirm)),
        ],
      ),
    );
    input.dispose();
    if (!mounted || next == null || next.isEmpty || next == name) return;
    // 整词替换：`Count` 不能命中 `Counter`。
    final re = RegExp(r'\b' + RegExp.escape(name) + r'\b');
    var count = 0;
    final rebuilt = text.replaceAllMapped(re, (m) {
      count++;
      return next;
    });
    if (count == 0) return;
    controller.text = rebuilt;
    controller.selection = TextSelection.collapsed(offset: range.start.clamp(0, rebuilt.length));
    controller.scrollToLine(_lineOfOffset(rebuilt, range.start.clamp(0, rebuilt.length)));
    _toast(localizations.editorRenameDone('$count'));
    _runLint();
  }

  /// 插入代码片段（对标 VS 的 IntelliSense snippet）。
  ///
  /// 模板按当前语言取，插入时整体按光标行的缩进右移；`$0` 是插入后的光标落点，
  /// `${1:默认值}` 会被选中（Shell 的 `${1:-x}` 这类参数扩展不处理）。
  Future<void> _showSnippets() async {
    final controller = _controller;
    if (controller == null) return;
    final snippets = CodeSnippets.forLanguage(_lang.label, _lang.key);
    if (snippets.isEmpty) {
      _toast(localizations.editorSnippetsEmpty);
      return;
    }
    final filter = TextEditingController();
    final picked = await showModalBottomSheet<CodeSnippet>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final theme = Theme.of(ctx);
          final q = filter.text.trim().toLowerCase();
          final list = q.isEmpty
              ? snippets
              : snippets
                  .where((e) =>
                      e.label.toLowerCase().contains(q) ||
                      e.body.toLowerCase().contains(q))
                  .toList();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: filter,
                          decoration: InputDecoration(
                            isDense: true,
                            border: const OutlineInputBorder(),
                            hintText: localizations.editorSnippetsHint,
                            prefixIcon: const Icon(Icons.search, size: 18),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 10),
                          ),
                          style: const TextStyle(fontSize: 13),
                          onChanged: (_) => setSheet(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_lang.label,
                          style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: list.isEmpty
                      ? Center(
                          child: Text(localizations.editorSnippetsEmpty,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant)),
                        )
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final sn = list[i];
                            final preview = sn.body
                                .split('\n')
                                .where((l) => l.trim().isNotEmpty)
                                .take(3)
                                .map((l) => l.trim())
                                .join('  ');
                            return ListTile(
                              dense: true,
                              title: Text(sn.label,
                                  style: const TextStyle(fontSize: 13)),
                              subtitle: Text(preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11, fontFamily: 'monospace')),
                              onTap: () => Navigator.pop(ctx, sn),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
    filter.dispose();
    if (picked == null || !mounted) return;
    _insertSnippet(picked.body);
  }

  /// 插入一段模板：按当前行缩进整体右移，`$0` 决定光标落点，`${1:x}` 会被选中。
  void _insertSnippet(String raw) {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final sel = controller.selection;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? start : sel.end;

    // 当前行的缩进（Tab 也算），模板的每一行都对齐到它下面
    final lineStart = text.lastIndexOf('\n', (start - 1).clamp(0, text.length)) + 1;
    final head = text.substring(lineStart, start);
    final m = RegExp(r'^[ \t]*').firstMatch(head);
    final indent = m?.group(0) ?? '';

    final lines = raw.split('\n');
    final buf = StringBuffer(lines.first);
    for (var i = 1; i < lines.length; i++) {
      buf.write('\n');
      // 空行不补缩进，免得存一堆尾随空格
      if (lines[i].trim().isNotEmpty) buf.write(indent);
      buf.write(lines[i]);
    }
    var body = buf.toString();

    // ① 先摘掉 `$0`（VS 里表示「最终光标位置」）：它可能落在占位符前面，
    //    先删掉再算偏移才不会错位。
    var caretAt = -1;
    final zero = body.indexOf(r'$0');
    if (zero >= 0) {
      body = body.replaceFirst(r'$0', '');
      caretAt = zero;
    }

    // ② VS 风格的占位符：`${1:名字}` 变成「名字」，并把**序号最小的那一处**选中。
    //
    // 只认带冒号 + 内容的写法，**不认裸 `$1`**：Shell 片段里 `$1` 是位置参数、
    // `${1:-默认}` 是参数扩展，无脑替换会把片段改坏，所以这类前缀直接跳过。
    var selStart = -1;
    var selEnd = -1;
    final ph = RegExp(r'\$\{(\d+):([^}]*)\}');
    final rebuilt = StringBuffer();
    var lastAt = 0;
    var bestIndex = 1 << 30;
    for (final m in ph.allMatches(body)) {
      final value = m.group(2) ?? '';
      if (value.startsWith('-') ||
          value.startsWith('=') ||
          value.startsWith('?') ||
          value.startsWith('+')) {
        continue;
      }
      rebuilt.write(body.substring(lastAt, m.start));
      final at = rebuilt.length;
      rebuilt.write(value);
      lastAt = m.end;
      final idx = int.tryParse(m.group(1) ?? '') ?? 999;
      if (idx < bestIndex) {
        bestIndex = idx;
        selStart = at;
        selEnd = at + value.length;
      }
    }
    if (lastAt > 0) {
      rebuilt.write(body.substring(lastAt));
      body = rebuilt.toString();
    }

    controller.replaceRange(start, end, body);
    final total = controller.text.length;
    if (selStart >= 0) {
      final a = (start + selStart).clamp(0, total);
      final b = (start + selEnd).clamp(a, total);
      controller.selection = TextSelection(baseOffset: a, extentOffset: b);
      controller.scrollToLine(_lineOfOffset(controller.text, a));
    } else {
      final caret = (caretAt >= 0 ? start + caretAt : start + body.length)
          .clamp(0, total);
      controller.selection = TextSelection.collapsed(offset: caret);
      controller.scrollToLine(_lineOfOffset(controller.text, caret));
    }
    _scheduleLint();
  }

  /// 跨文件操作（重命名 / 多文件查找）的候选范围：
  /// 已打开的所有文档 + 当前文件同目录下的文本文件（不递归、≤1MB、最多 300 个）。
  ///
  /// 这两件事范围必须一致，否则「重命名把 A 文件改了、查找却说 B 文件没提到它」。
  Future<List<_ScopeFile>> _collectScopeFiles(EditorDocument doc) async {
    final targets = <_ScopeFile>[];
    final scanned = <String>{};
    for (final d in _docs.docs) {
      final key = d.path ?? 'mem:${d.id}';
      if (!scanned.add(key)) continue;
      targets.add(_ScopeFile(label: d.name, path: d.path, doc: d, content: d.text));
    }
    // ① 工作区：递归整个目录（上限见 _wsMax*）
    final ws = _workspace;
    if (ws != null && ws.isNotEmpty) {
      final got = await _scanWorkspace(ws, scanned);
      if (got.isNotEmpty) return targets..addAll(got);
      // 工作区不可用（被删 / 没权限）时退回下面的「当前目录」
    }
    final basePath = doc.path;
    if (basePath != null) {
      try {
        final dir = File(basePath).parent;
        if (await dir.exists()) {
          var files = 0;
          await for (final e in dir.list(followLinks: false)) {
            if (files >= 300) break;
            if (e is! File) continue;
            if (!scanned.add(e.path)) continue;
            final lower = e.path.toLowerCase();
            if (_skipScanExts.any(lower.endsWith)) continue;
            try {
              if (await e.length() > 1024 * 1024) continue;
              files++;
              final content = await e.readAsString();
              targets.add(_ScopeFile(
                  label: e.path.split(Platform.pathSeparator).last,
                  path: e.path,
                  content: content));
            } catch (_) {
              // 非 UTF-8 / 刚好被删：跳过这一个
            }
          }
        }
      } catch (e) {
        logger.w('scope scan failed', error: e);
      }
    }
    return targets;
  }

  /// 递归扫工作区里的文本文件。有上限（文件数 / 单文件大小 / 总字节 / 深度），
  /// 到限就停 —— 宁可少扫几个，也不要把 UI 卡住几十秒。
  Future<List<_ScopeFile>> _scanWorkspace(
      String root, Set<String> scanned) async {
    final out = <_ScopeFile>[];
    final dir = Directory(root);
    if (!await dir.exists()) return out;
    List<FileSystemEntity> all;
    try {
      // listSync 在 C 层递归，比逐层 await for 快一个量级
      all = dir.listSync(recursive: true, followLinks: false);
    } catch (e) {
      logger.w('workspace list failed', error: e);
      return out;
    }
    var totalBytes = 0;
    final sep = Platform.pathSeparator;
    for (final e in all) {
      if (out.length >= _wsMaxFiles) break;
      if (totalBytes >= _wsMaxTotalBytes) break;
      if (e is! File) continue;
      if (!scanned.add(e.path)) continue;
      final rel = e.path.startsWith(root) ? e.path.substring(root.length) : e.path;
      // 深度：按分隔符个数算（相对路径的第一段是分隔符）
      if (sep.allMatches(rel).length > _wsMaxDepth) continue;
      final lower = e.path.toLowerCase();
      if (_skipScanExts.any(lower.endsWith)) continue;
      // 跳过依赖 / 构建产物目录
      if (DirDiff.defaultSkipDirs.any((d) => rel.contains('$sep$d$sep'))) continue;
      try {
        final len = await e.length();
        if (len == 0 || len > _wsMaxFileBytes) continue;
        totalBytes += len;
        final content = await e.readAsString();
        out.add(_ScopeFile(
            label: e.path.split(sep).last, path: e.path, content: content));
      } catch (_) {
        // 非 UTF-8 / 刚好被删：跳过这一个
      }
    }
    return out;
  }

  /// 设置 / 更换 / 清除工作区。
  Future<void> _pickWorkspace() async {
    final current = _workspace;
    if (current != null && current.isNotEmpty) {
      final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                child: Text(localizations.editorWorkspaceHint,
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(ctx).hintColor)),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.folder_open, size: 20),
                title: Text(localizations.editorWorkspaceCurrent(current),
                    style: const TextStyle(fontSize: 12)),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: Text(localizations.editorWorkspaceSet),
                onTap: () => Navigator.pop(ctx, 'set'),
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: Text(localizations.editorWorkspaceClear),
                onTap: () => Navigator.pop(ctx, 'clear'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || action == null) return;
      if (action == 'clear') {
        setState(() => _workspace = null);
        unawaited(SharedPreferencesAsync().remove(_workspaceKey));
        _toast(localizations.editorWorkspaceClear);
        return;
      }
    }
    try {
      final path = await FilePicker.getDirectoryPath();
      if (path == null || path.isEmpty) return;
      // SAF 可能给出 File API 读不到的路径：先说清楚，别等「查找引用」扫出 0 个才懵。
      if (!await isDirectoryReadable(path)) {
        if (!mounted) return;
        _toast(localizations.editorDirUnreadable);
        return;
      }
      if (!mounted) return;
      setState(() => _workspace = path);
      unawaited(SharedPreferencesAsync().setString(_workspaceKey, path));
      _toast(localizations.editorWorkspaceCurrent(path));
    } catch (e) {
      _toast('$e');
    }
  }

  /// 多文件查找（VS 的 Ctrl+Shift+F，这里范围是「已打开的文件 + 当前目录」）。
  ///
  /// 为什么不在每个文件里单独按 Ctrl+F：改个变量名要确认「别处还有没有」时，
  /// 一个个文件翻是最费事的；这里一次列全，点一条直接跳过去。
  Future<void> _findInFiles() async {
    final doc = _doc;
    if (doc == null) return;
    final scope = await _collectScopeFiles(doc);
    if (!mounted) return;

    final input = TextEditingController(text: _fileSearchQuery);
    input.selection =
        TextSelection(baseOffset: 0, extentOffset: input.text.length);
    var caseSensitive = _fileSearchCase;
    var asRegex = _fileSearchRegex;
    var hits = <_FileSearchHit>[];
    var truncated = false;
    var searched = false;

    String? error;

    void run() {
      hits = [];
      truncated = false;
      searched = true;
      error = null;
      final q = input.text;
      if (q.isEmpty) return;
      RegExp re;
      try {
        re = asRegex
            ? RegExp(q, caseSensitive: caseSensitive, multiLine: true)
            : RegExp(RegExp.escape(q), caseSensitive: caseSensitive);
      } catch (e) {
        error = '$e';
        return;
      }
      final currentKey = doc.path ?? 'mem:${doc.id}';
      for (final f in scope) {
        if (f.content.length > 2000000) continue;      // 2MB 以上的不搜
        var perFile = 0;
        var line = 1;
        var last = 0;
        for (final m in re.allMatches(f.content)) {
          if (perFile >= 200 || hits.length >= 2000) {
            truncated = true;
            break;
          }
          for (var i = last; i < m.start; i++) {
            if (f.content.codeUnitAt(i) == 10) line++;
          }
          last = m.start;
          var lineEnd = f.content.indexOf('\n', m.start);
          if (lineEnd < 0) lineEnd = f.content.length;
          var lineStart = f.content.lastIndexOf('\n', m.start) + 1;
          if (lineStart < 0) lineStart = 0;
          hits.add(_FileSearchHit(
            label: f.label,
            path: f.path,
            line: line,
            offset: m.start,
            matchLength: m.end - m.start,
            text: f.content.substring(lineStart, lineEnd).trim(),
            isCurrent: (f.path ?? 'mem:${f.doc?.id ?? ''}') == currentKey,
          ));
          perFile++;
        }
        if (hits.length >= 2000) break;
      }
      // 当前文件优先，然后按文件名、行号
      hits.sort((a, b) {
        if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
        final byLabel = a.label.compareTo(b.label);
        return byLabel != 0 ? byLabel : a.line.compareTo(b.line);
      });
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final theme = Theme.of(ctx);
          final files = hits.map((h) => h.label).toSet().length;
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.85,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 10, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: input,
                          autofocus: true,
                          decoration: InputDecoration(
                            isDense: true,
                            border: const OutlineInputBorder(),
                            hintText: localizations.editorFindInFilesHint,
                            prefixIcon: const Icon(Icons.search, size: 18),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 10),
                          ),
                          style: const TextStyle(fontSize: 13),
                          onSubmitted: (_) => setSheet(run),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: localizations.editorFindCaseSensitive,
                        isSelected: caseSensitive,
                        icon: const Icon(Icons.text_fields, size: 18),
                        onPressed: () {
                          setSheet(() {
                            caseSensitive = !caseSensitive;
                            run();
                          });
                        },
                      ),
                      IconButton(
                        tooltip: localizations.editorFindRegex,
                        isSelected: asRegex,
                        icon: const Icon(Icons.code, size: 18),
                        onPressed: () {
                          setSheet(() {
                            asRegex = !asRegex;
                            run();
                          });
                        },
                      ),
                      IconButton(
                        tooltip: localizations.editorReplaceInFiles,
                        icon: const Icon(Icons.find_replace, size: 18),
                        onPressed: () {
                          final q = input.text;
                          if (q.isEmpty) return;
                          Navigator.pop(ctx);
                          unawaited(_replaceInFiles(q,
                              asRegex: asRegex, caseSensitive: caseSensitive));
                        },
                      ),
                      FilledButton(
                        onPressed: () => setSheet(run),
                        child: Text(localizations.editorFindInFilesButton),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          error ??
                              (searched
                                  ? localizations.editorFindInFilesResult(
                                      '$files', '${hits.length}')
                                  : localizations.editorFindInFilesScope),
                          style: TextStyle(
                            fontSize: 11,
                            color: error != null
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (truncated)
                        Text(localizations.editorFindTruncated('2000'),
                            style: TextStyle(
                                fontSize: 11, color: theme.colorScheme.error)),
                    ],
                  ),
                ),
                const Divider(height: 12),
                Expanded(
                  child: hits.isEmpty
                      ? Center(
                          child: Text(
                            searched
                                ? localizations.editorFindInFilesEmpty
                                : localizations.editorFindInFilesScope,
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          itemCount: hits.length,
                          itemBuilder: (_, i) {
                            final h = hits[i];
                            final showLabel = i == 0 || hits[i - 1].label != h.label;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (showLabel)
                                  Container(
                                    width: double.infinity,
                                    color: theme.colorScheme.surfaceContainerHighest
                                        .withValues(alpha: 0.5),
                                    padding: const EdgeInsets.fromLTRB(
                                        14, 4, 14, 4),
                                    child: Text(
                                      h.label,
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: h.isCurrent
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme.onSurfaceVariant),
                                    ),
                                  ),
                                InkWell(
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    unawaited(_openSearchHit(h));
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        22, 5, 12, 5),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 44,
                                          child: Text('L${h.line}',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: theme.colorScheme
                                                      .onSurfaceVariant)),
                                        ),
                                        Expanded(
                                          child: Text(
                                            h.text,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontFamily: 'monospace'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
    // 记住这次的查询与开关，下次打开还是它
    _fileSearchQuery = input.text;
    _fileSearchCase = caseSensitive;
    _fileSearchRegex = asRegex;
    input.dispose();
  }

  /// 调用层次（VS 的 Call Hierarchy）。
  ///
  /// 以光标处的名字为根，扫「已打开的文件 + 当前目录」，对每处命中往上找它所在的
  /// 函数，按「调用者」分组。只做两层（符号 → 调用者 → 调用位置），
  /// 够回答「谁在用这个东西」，也不需要跨文件语义解析。
  Future<void> _showCallHierarchy() async {
    final controller = _controller;
    final doc = _doc;
    if (controller == null || doc == null) return;
    final text = controller.text;
    final caret = controller.selection.baseOffset;
    final range = _wordRangeAt(text, caret < 0 ? 0 : caret);
    final name = text.substring(range.start, range.end);
    if (!_isSymbolName(name)) {
      _toast(localizations.editorRenameNeedSymbol);
      return;
    }
    final re = RegExp(r'\b' + RegExp.escape(name) + r'\b');
    final scope = await _collectScopeFiles(doc);
    if (!mounted) return;

    final byCaller = <String, List<_FileSearchHit>>{};
    var siteCount = 0;
    for (final f in scope) {
      if (f.content.length > 2000000) continue;
      final matches = re.allMatches(f.content);
      if (matches.isEmpty) continue;
      final lines = f.content.split('\n');
      var line = 1;
      var last = 0;
      for (final m in matches) {
        if (siteCount >= 1000) break;
        for (var i = last; i < m.start; i++) {
          if (f.content.codeUnitAt(i) == 10) line++;
        }
        last = m.start;
        final caller = CodeSymbols.enclosingCaller(lines, line - 1) ??
            localizations.editorTopLevel;
        var lineEnd = f.content.indexOf('\n', m.start);
        if (lineEnd < 0) lineEnd = f.content.length;
        var lineStart = f.content.lastIndexOf('\n', m.start) + 1;
        if (lineStart < 0) lineStart = 0;
        byCaller.putIfAbsent(caller, () => []).add(_FileSearchHit(
          label: f.label,
          path: f.path,
          line: line,
          offset: m.start,
          matchLength: m.end - m.start,
          text: f.content.substring(lineStart, lineEnd).trim(),
          isCurrent: (f.path ?? 'mem:${f.doc?.id ?? ''}') ==
              (doc.path ?? 'mem:${doc.id}'),
        ));
        siteCount++;
      }
    }

    if (!mounted) return;
    if (siteCount == 0) {
      _toast(localizations.editorCallHierarchyEmpty);
      return;
    }

    // 调用者多的排前面，同数量按名字
    final callers = byCaller.keys.toList()
      ..sort((a, b) {
        final byLen = byCaller[b]!.length.compareTo(byCaller[a]!.length);
        return byLen != 0 ? byLen : a.compareTo(b);
      });

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${localizations.editorCallHierarchy}: $name',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      localizations.editorCallHierarchySummary(
                          '${callers.length}', '$siteCount'),
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: callers.length,
                  itemBuilder: (_, i) {
                    final caller = callers[i];
                    final sites = byCaller[caller]!;
                    return ExpansionTile(
                      dense: true,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                      childrenPadding: EdgeInsets.zero,
                      initiallyExpanded: i == 0,
                      leading: const Icon(Icons.functions, size: 16),
                      title: Text(caller,
                          style: const TextStyle(
                              fontSize: 12.5, fontFamily: 'monospace')),
                      subtitle: Text(
                        '${sites.length} · ${sites.first.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10.5,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                      children: [
                        for (final h in sites)
                          InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              unawaited(_openSearchHit(h));
                            },
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(40, 5, 12, 5),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 42,
                                    child: Text('L${h.line}',
                                        style: TextStyle(
                                            fontSize: 10.5,
                                            color: theme.colorScheme
                                                .onSurfaceVariant)),
                                  ),
                                  Expanded(
                                    child: Text(h.text,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 11.5,
                                            fontFamily: 'monospace')),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 在文件中替换（多文件查找的姊妹功能）。
  ///
  /// 已打开的文档走 controller（能 Ctrl+Z），没打开的写盘并记进 [_renameBackup]，
  /// 所以「撤销上次跨文件重命名」也能把这些写盘还原回去。
  Future<void> _replaceInFiles(String pattern,
      {required bool asRegex, required bool caseSensitive}) async {
    final doc = _doc;
    if (doc == null) return;
    RegExp re;
    try {
      re = asRegex
          ? RegExp(pattern, caseSensitive: caseSensitive, multiLine: true)
          : RegExp(RegExp.escape(pattern), caseSensitive: caseSensitive);
    } catch (e) {
      _toast('$e');
      return;
    }
    final scope = await _collectScopeFiles(doc);
    if (!mounted) return;

    // 先数一下会动多少地方：替换是不可逆的（除了已打开的文件），得让人看清代价
    var hitCount = 0;
    var fileCount = 0;
    for (final f in scope) {
      if (f.content.length > 2000000) continue;
      final n = re.allMatches(f.content).length;
      if (n > 0) {
        hitCount += n;
        fileCount++;
      }
    }
    if (hitCount == 0) {
      _toast(localizations.editorFindInFilesEmpty);
      return;
    }

    final input = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.editorReplaceInFiles),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: input,
              autofocus: true,
              decoration:
                  InputDecoration(labelText: localizations.editorReplaceHint),
              onSubmitted: (v) => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 10),
            Text(
              localizations.editorReplaceConfirmBody('$fileCount', '$hitCount'),
              style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
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
    // 必须在 dispose 之前取值
    final replacement = input.text;
    input.dispose();
    if (!mounted || ok != true) return;

    var changedFiles = 0;
    var changedHits = 0;
    for (final f in scope) {
      if (f.content.length > 2000000) continue;
      final matches = re.allMatches(f.content).length;
      if (matches == 0) continue;
      // 用 replaceAllMapped 返回字面量：非正则模式下 replaceAll 会把 `$1`
      // 当成组引用，用户输入的钱符号会凭空消失。
      final replaced =
          f.content.replaceAllMapped(re, (_) => replacement);
      if (replaced == f.content) continue;
      changedFiles++;
      changedHits += matches;
      final d = f.doc;
      if (d != null) {
        d.controller.text = replaced;
      } else if (f.path != null) {
        try {
          _renameBackup[f.path!] = f.content;
          await File(f.path!).writeAsString(replaced);
        } catch (e) {
          logger.w('replace write failed', error: e);
        }
      }
    }
    if (!mounted) return;
    _toast(localizations.editorReplaceDone('$changedFiles', '$changedHits'));
    _runLint();
    _refreshDecorations();
  }

  /// 跳到一条「多文件查找」结果：必要时切文档，再定位到具体偏移。
  Future<void> _openSearchHit(_FileSearchHit h) async {
    if (h.path != null && _doc?.path != h.path) {
      await _openPath(h.path!);
      // 切文档后 CodeForge 要重排一次，等一帧再定位
      await Future.delayed(const Duration(milliseconds: 60));
    }
    if (!mounted) return;
    if (_doc?.path != null && h.path != null && _doc?.path != h.path) return;
    _jumpToOffset(h.offset);
    // 把命中的那一段选中（只是光标落过去的话，长行里还要自己找）
    final controller = _controller;
    if (controller != null && h.matchLength > 0) {
      final text = controller.text;
      final end = (h.offset + h.matchLength).clamp(0, text.length);
      final start = h.offset.clamp(0, end);
      controller.selection =
          TextSelection(baseOffset: start, extentOffset: end);
    }
  }

  /// 工作区根目录（可选）。设了之后「查找引用 / 多文件查找 / 跨文件重命名 /
  /// 调用层次 / 在文件中替换」都扫整个目录，而不是只有已打开的文件 + 当前目录。
  static const String _workspaceKey = kTextEditorWorkspaceKey;

  /// 最近打开过的文件（跨会话），最多 20 个。
  ///
  /// 编辑器每次都要从「打开文件」一路点目录，来回改同几个文件时特别费事；
  /// 这里单独记一份，比把整个目录列出来（快速打开）更贴近「我刚才在弄哪个」。
  static const String _recentFilesKey = 'text_editor_recent_files_v1';
  List<String> _recentFiles = <String>[];

  /// 最近关闭的文档（VS 的「重新打开关闭的窗口」，Ctrl+Shift+T）。
  ///
  /// 手滑关掉一个还没看完的文件、或者对比完顺手关了又想起来要改一个字，
  /// 手机上重新从目录里翻过去成本很高。只记路径和光标位置，最多 10 条。
  final List<({String path, String name, int caret})> _recentClosed = [];
  String? _workspace;

  /// 工作区递归扫描的上限：仓库动辄几万个文件，不设限就是卡死。
  static const int _wsMaxFiles = 800;
  static const int _wsMaxFileBytes = 512 * 1024;
  static const int _wsMaxTotalBytes = 6 * 1024 * 1024;
  static const int _wsMaxDepth = 8;

  /// 「多文件查找」上次的查询与开关：改一次名字往往要连着查好几次。
  String _fileSearchQuery = '';
  bool _fileSearchCase = false;
  bool _fileSearchRegex = false;

  /// 上一次「跨文件重命名」写盘前的备份（path -> 原内容），供撤销用。
  static final Map<String, String> _renameBackup = {};

  /// 标识符字符判定。Dart 的 `\b` 只认 ASCII 词字符，这里连同 `$` 与中文一起认，
  /// 这样「重命名 `名字` 不能命中 `名字2`」也能成立。
  static bool _isIdentChar(int c) =>
      (c >= 97 && c <= 122) ||
      (c >= 65 && c <= 90) ||
      (c >= 48 && c <= 57) ||
      c == 95 ||
      c == 36 ||
      c > 127;

  static int _countWord(String src, String name) {
    if (name.isEmpty) return 0;
    var n = 0;
    var i = 0;
    while (true) {
      final j = src.indexOf(name, i);
      if (j < 0) break;
      final before = j > 0 ? src.codeUnitAt(j - 1) : 0;
      final after =
          j + name.length < src.length ? src.codeUnitAt(j + name.length) : 0;
      if (!_isIdentChar(before) && !_isIdentChar(after)) n++;
      i = j + name.length;
    }
    return n;
  }

  /// 整词替换（不碰 `name2` / `myName` 这类包含关系）。
  static String _replaceWord(String src, String name, String repl) {
    if (name.isEmpty || name == repl) return src;
    final out = StringBuffer();
    var i = 0;
    while (true) {
      final j = src.indexOf(name, i);
      if (j < 0) {
        out.write(src.substring(i));
        break;
      }
      final end = j + name.length;
      final before = j > 0 ? src.codeUnitAt(j - 1) : 0;
      final after = end < src.length ? src.codeUnitAt(end) : 0;
      out.write(src.substring(i, j));
      if (!_isIdentChar(before) && !_isIdentChar(after)) {
        out.write(repl);
      } else {
        out.write(src.substring(j, end));
      }
      i = end;
    }
    return out.toString();
  }

  /// 跨文件重命名（桌面 VS 的 Ctrl+R,R）。
  ///
  /// 范围与「查找引用」一致：已打开的所有文档 + 当前文件同目录下的文本文件
  /// （不递归、单文件 ≤1MB、最多 300 个）。
  ///
  /// 已打开的文档只改内存（可以 Ctrl+Z 撤销，按 Ctrl+S 才落盘）；
  /// 没打开的文件直接写盘，并把原内容记进 [_renameBackup] 供「撤销上次重命名」。
  Future<void> _renameSymbolEverywhere() async {
    final controller = _controller;
    final doc = _doc;
    if (controller == null || doc == null) return;
    final text = controller.text;
    final caret = controller.selection.baseOffset;
    final range = _wordRangeAt(text, caret < 0 ? 0 : caret);
    final name = text.substring(range.start, range.end);
    if (!_isSymbolName(name)) {
      _toast(localizations.editorRenameNeedSymbol);
      return;
    }

    final input = TextEditingController(text: name);
    input.selection = TextSelection(baseOffset: 0, extentOffset: name.length);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.editorRenameEverywhere),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: input,
              autofocus: true,
              decoration:
                  InputDecoration(labelText: localizations.editorRenameHint),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: 10),
            Text(localizations.editorRenameScope,
                style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(localizations.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, input.text),
              child: Text(localizations.confirm)),
        ],
      ),
    );
    input.dispose();
    if (!mounted) return;
    if (next == null || next.isEmpty || next == name) return;
    if (!_isSymbolName(next)) {
      _toast(localizations.editorRenameNeedSymbol);
      return;
    }

    // ---- 收集范围 ----
    final targets = await _collectScopeFiles(doc);

    var totalHits = 0;
    final planned = <_ScopeFile>[];
    for (final t in targets) {
      t.hits = _countWord(t.content, name);
      if (t.hits == 0) continue;
      totalHits += t.hits;
      planned.add(t);
    }
    if (totalHits == 0) {
      _toast(localizations.editorReferencesEmpty);
      return;
    }

    final diskCount = planned.where((t) => t.doc == null).length;
    if (!mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        localizations.editorRenamePreview(
                            '$name', '$next', '${planned.length}', '$totalHits'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final t in planned)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          t.doc == null
                              ? Icons.save_outlined
                              : Icons.edit_note_outlined,
                          size: 18,
                        ),
                        title: Text(t.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5)),
                        trailing: Text('${t.hits}',
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.primary)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Row(
                  children: [
                    if (diskCount > 0)
                      Expanded(
                        child: Text(
                          localizations.editorRenameDiskNote('$diskCount'),
                          style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      )
                    else
                      const Spacer(),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(localizations.cancel)),
                    const SizedBox(width: 6),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(localizations.editorRenameApply)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true || !mounted) return;

    // ---- 执行 ----
    var changedFiles = 0;
    var changedHits = 0;
    for (final t in planned) {
      final replaced = _replaceWord(t.content, name, next);
      if (replaced == t.content) continue;
      changedFiles++;
      changedHits += t.hits;
      final d = t.doc;
      if (d != null) {
        // 走内核 controller：一次编辑进撤销栈，用户 Ctrl+Z 就回去了。
        d.controller.text = replaced;
      } else if (t.path != null) {
        try {
          _renameBackup[t.path!] = t.content;
          await File(t.path!).writeAsString(replaced);
        } catch (e) {
          logger.w('rename write failed', error: e);
        }
      }
    }
    if (!mounted) return;
    final fs = '$changedFiles';
    final hs = '$changedHits';
    _toast(localizations.editorRenameDoneMulti(fs, hs));
    _runLint();
    _refreshDecorations();
  }

  /// 撤销上一次跨文件重命名里「已写盘」的那些文件。
  Future<void> _undoRenameEverywhere() async {
    if (_renameBackup.isEmpty) {
      _toast(localizations.editorRenameNothingToUndo);
      return;
    }
    var n = 0;
    final entries = Map<String, String>.from(_renameBackup);
    _renameBackup.clear();
    for (final e in entries.entries) {
      try {
        await File(e.key).writeAsString(e.value);
        n++;
        // 如果这个文件正开着，内存里也一起还原（否则下次保存会把改名写回去）
        for (final d in _docs.docs) {
          if (d.path == e.key) d.controller.text = e.value;
        }
      } catch (err) {
        logger.w('rename undo failed', error: err);
      }
    }
    if (!mounted) return;
    _toast(localizations.editorRenameUndone('$n'));
    _refreshDecorations();
  }

  /// 多选状态下的一条操作栏：已选几处 + 替换 / 删除 / 大小写 / 取消。
  Widget _multiSelBar() {
    if (_multiSel.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final count = _multiSel.length + 1;
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        Icon(Icons.select_all, size: 15, color: theme.colorScheme.primary),
        const SizedBox(width: 5),
        Text(localizations.editorMultiSelCount('$count'),
            style: TextStyle(fontSize: 11, color: theme.colorScheme.primary)),
        const SizedBox(width: 6),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _multiAction(localizations.editorMultiSelReplace('$count'), _promptReplaceSelections),
              _multiAction(localizations.delete, () => _editSelections((_) => '')),
              _multiAction(localizations.editorUpperCase, () => _editSelections((v) => v.toUpperCase())),
              _multiAction(localizations.editorLowerCase, () => _editSelections((v) => v.toLowerCase())),
              _multiAction(localizations.editorMultiSelNewline, () => _editSelections((v) => '$v\n')),
              _multiAction(localizations.editorMultiSelCopy, _copySelections),
            ]),
          ),
        ),
        IconButton(
          onPressed: _clearMultiSel,
          tooltip: localizations.cancel,
          icon: const Icon(Icons.close, size: 15),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        ),
      ]),
    );
  }

  /// 把每一处选中的内容按顺序复制出来（一处一行）。
  void _copySelections() {
    final ranges = _allSelectionRanges();
    if (ranges.isEmpty) return;
    final text = _controller?.text ?? '';
    final buffer = StringBuffer();
    for (final r in ranges) {
      if (r.start < 0 || r.end > text.length) continue;
      buffer.writeln(text.substring(r.start, r.end));
    }
    final out = buffer.toString().trimRight();
    if (out.isEmpty) return;
    Clipboard.setData(ClipboardData(text: out));
    _toast(localizations.copied);
  }

  Widget _multiAction(String label, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  // ---------- 定义速览 / 括号跳转 / 逐级扩大选区（VS 的 Alt+F12、Ctrl+]、Shift+Alt+→）----------

  /// 「速览定义」：不跳走，先在下面弹一张小卡片看声明长什么样。
  ///
  /// VS 里是 Alt+F12。手机上「跳过去看一眼再跳回来」这个来回成本很高
  /// （滚动位置、选中都丢了），所以这里先给上下文，看完再决定要不要真跳。
  Future<void> _peekDefinition() async {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final caret = controller.selection.baseOffset;
    final range = _wordRangeAt(text, caret < 0 ? 0 : caret);
    final name = text.substring(range.start, range.end);
    // 空白 / 标点上 `_wordRangeAt` 会返回那一个字符，拿去搜会「定义一个空格」。
    if (!_isSymbolName(name)) {
      _toast(localizations.editorNoDefinition);
      return;
    }
    final at = _findDeclaration(text, name, range.start);
    if (at != null) {
      await _showPeekAt(at: at, title: name);
      return;
    }
    // 同文件没有 → 在其它已打开文档里找（跨文件速览）。
    // 「转到定义」本来就支持跨文件；速览要是不支持，就会变成「能跳不能看」。
    for (final d in _docs.docs) {
      if (d.id == _doc?.id) continue;
      final o = _findDeclaration(d.controller.text, name, -1);
      if (o != null) {
        await _showPeekAt(at: o, title: name, sourceDoc: d);
        return;
      }
    }
    _toast(localizations.editorNoDefinition);
  }

  /// 在下面弹一张卡片「速览」某个位置（声明和引用都走这里）。
  ///
  /// [at] 是名字所在的偏移。卡片里给两个出口：真的跳过去，或者看它的所有引用——
  /// 这样「这里是什么 → 还有谁用我」不用来回关面板再点菜单。
  /// [sourceDoc] 为其它已打开的文档时，卡片里的内容取自它，
  /// 两个出口（看引用 / 跳过去）也都切到那边去。
  Future<void> _showPeekAt(
      {required int at, required String title, EditorDocument? sourceDoc}) async {
    final controller = sourceDoc?.controller ?? _controller;
    if (controller == null) return;
    final text = controller.text;
    final targetLine = _lineOfOffset(text, at);
    final total = _totalLinesOf(text);
    final from = (targetLine - 3).clamp(0, total - 1);
    final to = (targetLine + 4).clamp(0, total - 1);
    final lines = <({int no, String text})>[];
    var offset = _offsetOfLine(text, from);
    for (var line = from; line <= to; line++) {
      var next = text.indexOf('\n', offset);
      if (next < 0) next = text.length;
      lines.add((no: line, text: text.substring(offset, next)));
      offset = next + 1;
      if (offset > text.length) break;
    }
    if (!mounted) return;
    // 速览的是别的文档时，「看引用 / 跳过去」都得先把那个文档切回来。
    Future<bool> switchToSource() async {
      final d = sourceDoc;
      if (d == null) return true;
      if (!identical(d, _doc)) _activate(d);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      return mounted;
    }
    final theme = Theme.of(context);
    final mono = TextStyle(
        fontSize: 12, fontFamily: 'monospace', color: theme.textTheme.bodyMedium?.color);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text('$title  ·  L${targetLine + 1}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final line in lines)
                      Container(
                        color: line.no == targetLine
                            ? theme.colorScheme.primary.withValues(alpha: 0.12)
                            : null,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(
                            width: 34,
                            child: Text('${line.no + 1}',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: theme.disabledColor,
                                    fontFamily: 'monospace')),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(line.text,
                                  style: mono, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ]),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(children: [
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      if (!await switchToSource()) return;
                      final c = _controller;
                      if (c == null) return;
                      c.selection = TextSelection.collapsed(offset: at.clamp(0, c.text.length));
                      unawaited(_showReferences());
                    },
                    child: Text(localizations.editorReferences),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      if (!await switchToSource()) return;
                      final c = _controller;
                      if (c == null) return;
                      c.selection = TextSelection.collapsed(offset: at.clamp(0, c.text.length));
                      c.scrollToLine(targetLine);
                    },
                    child: Text(localizations.editorGotoDefinition),
                  ),
                ]),
              ),
            ]),
      ),
    );
  }

  /// 「跳到配对括号」（VS 的 Ctrl+]）。
  ///
  /// 光标处的括号（或它前面那个）跳到另一半；不在括号上就提示一声——
  /// 不做「找当前行第一个括号」这种猜测，猜错了更让人困惑。
  void _jumpToMatchingBracket() {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    if (text.isEmpty) return;
    final caret = controller.selection.extentOffset.clamp(0, text.length);

    void moveTo(int offset) {
      controller.selection = TextSelection.collapsed(offset: offset.clamp(0, text.length));
      controller.scrollToLine(_lineOfOffset(text, offset));
    }

    for (final offset in <int>[caret, caret - 1]) {
      if (offset < 0 || offset >= text.length) continue;
      final c = text[offset];
      if ('([{'.contains(c)) {
        final close = _findClosing(text, offset, c);
        if (close != null) {
          moveTo(close);
          return;
        }
      } else if (')]}'.contains(c)) {
        final open = _findOpening(text, offset, c);
        if (open != null) {
          moveTo(open);
          return;
        }
      }
    }
    _toast(localizations.editorNoDefinition);
  }

  /// 「逐级扩大选区」（VS 的 Shift+Alt+→）。
  ///
  /// 顺序：光标处的词 → 所在括号的内容 → 含括号 → 整行 → 外层括号整块 → 全文。
  /// 手机上没有这种组合键，而「恰好选中这一段」在触屏上更难，所以给一个可以连点的入口。
  /// 这个位置是否在字符串或行注释里。
  ///
  /// 只扫当前行：括号扩级在注释/字符串里数层级一定会数错（`"("` 这种），
  /// 与其猜，不如判定「这行是注释/字符串」后直接退化成「扩到整行」。
  static bool _insideStringOrComment(String text, int offset) {
    final lineStart = offset == 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;
    var inSingle = false;
    var inDouble = false;
    var escaped = false;
    for (var i = lineStart; i < offset && i < text.length; i++) {
      final c = text[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c.codeUnitAt(0) == 92) {
        // 反斜杠
        escaped = true;
        continue;
      }
      if (!inDouble && c == "'") {
        inSingle = !inSingle;
      } else if (!inSingle && c == '"') {
        inDouble = !inDouble;
      } else if (!inSingle && !inDouble) {
        if (c == '#' ) return true;
        if (c == '/' && i + 1 < text.length && text[i + 1] == '/') return true;
      }
    }
    return inSingle || inDouble;
  }

  /// 在上一行 / 下一行的**同列**位置再加一个光标（VS 的 Ctrl+Alt+↑↓）。
  ///
  /// 内核 controller 本身就支持多光标（打字走 insertAtAllCursors、退格走
  /// backspaceAtAllCursors、code_area 里也逐个画光标），这里只补 UI 入口。
  void _addCursorAtLine(int delta) {
    final controller = _controller;
    if (controller == null) return;
    // 多选区（Ctrl+D 那条线）和多光标是两套独立状态：同时在的时候打字会
    // 只写进多光标那几处、选区那一堆不动，看着像丢字。加光标就先收起多选区。
    if (_multiSel.isNotEmpty) _clearMultiSel();
    final text = controller.text;
    if (text.isEmpty) return;
    final caret = controller.selection.extentOffset.clamp(0, text.length);
    final lineCount = '\n'.allMatches(text).length + 1;
    final curLine = _lineOfOffset(text, caret);
    final target = curLine + delta;
    if (target < 0 || target >= lineCount) return;
    final curStart = _offsetOfLine(text, curLine);
    final targetStart = _offsetOfLine(text, target);
    // 目标行长度（不含换行符；末行没有换行符）。
    final targetEnd =
        target + 1 >= lineCount ? text.length : _offsetOfLine(text, target + 1) - 1;
    final col = (caret - curStart).clamp(0, targetEnd - targetStart);
    controller.addMultiCursor(target, col);
    _toast(localizations.editorMultiCursorCount('${controller.multiCursors.length + 1}'));
    setState(() {});
  }

  void _clearMultiCursors() {
    final controller = _controller;
    if (controller == null || !controller.hasMultiCursors) return;
    controller.clearMultiCursors();
    setState(() {});
  }

  /// 与剪贴板比较（VS Code 的 Compare with Clipboard）：不用先存成文件。
  Future<void> _compareWithClipboard() async {
    final controller = _controller;
    if (controller == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final clip = data?.text ?? '';
    if (!mounted) return;
    if (clip.isEmpty) {
      _toast(localizations.editorClipboardEmpty);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TextDiffPage(
              initialLeft: clip,
              initialRight: _applyNewline(controller.text, _newlineCharsOf(_doc)),
            )));
  }

  /// 与磁盘上的文件比较（VS 的 Compare with Saved）——有未保存修改时最常用。
  Future<void> _compareWithDisk() async {
    final doc = _doc;
    final controller = _controller;
    if (doc == null || controller == null) return;
    final path = doc.path;
    if (path == null || path.isEmpty) {
      _toast(localizations.editorCompareDiskNoFile);
      return;
    }
    try {
      final file = File(path);
      if (!await file.exists()) {
        if (!mounted) return;
        _toast(localizations.editorCompareDiskMissing);
        return;
      }
      final bytes = await file.readAsBytes();
      final (diskText, _) = await _decodeForOpen(bytes, prefer: doc.encodingName);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TextDiffPage(
                initialLeft: diskText,
                initialRight:
                    _applyNewline(controller.text, _newlineCharsOf(doc)),
              )));
    } catch (e) {
      if (!mounted) return;
      _toast('${localizations.fail}: $e');
    }
  }

  /// 与另一个已打开的标签页比较（VS 的 Compare with Selected / 比较标签页）。
  Future<void> _compareWithTab() async {
    final current = _doc;
    if (current == null) return;
    final others =
        EditorDocuments.instance.docs.where((d) => d.id != current.id).toList();
    if (others.isEmpty) {
      _toast(localizations.editorDiffNoOtherTab);
      return;
    }
    final picked = await showDialog<EditorDocument>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(localizations.editorDiffWithTab),
        children: others
            .map<Widget>((d) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, d),
                  child: Row(children: [
                    const Icon(Icons.description_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(d.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (d.dirty)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Text('•'),
                      ),
                  ]),
                ))
            .toList(),
      ),
    );
    if (picked == null || !mounted) return;
    // 两侧都是内存里的缓冲区，不做换行符归一（对齐才准）。
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TextDiffPage(
              initialLeft: current.text,
              initialRight: picked.text,
              initialLeftName: current.name,
              initialRightName: picked.name,
            )));
  }

  /// 本地历史（VS Code 的 Timeline / IDEA 的 Local History 的等价物）。
  ///
  /// 每次保存前留一份「磁盘上原来那一份」的快照，不依赖任何版本控制。
  /// 份数、单份体积都有上限，详见 [LocalHistory]。
  Future<void> _showLocalHistory() async {
    final doc = _doc;
    final controller = _controller;
    if (doc == null || controller == null) return;
    final path = doc.path;
    if (path == null || path.isEmpty) {
      _toast(localizations.editorLocalHistoryNoFile);
      return;
    }
    // 拿一份可变副本：`LocalHistory.list` 在「没有历史」时返回的是 const 空列表，
    // 直接对它 clear() 会抛 UnsupportedError。
    final entries = List<LocalSnapshot>.of(await LocalHistory.list(path));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return StatefulBuilder(builder: (ctx2, setSheet) {
          return SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
                child: Row(children: [
                  Expanded(
                    child: Text(
                        '${localizations.editorLocalHistory} · ${doc.name} · ${entries.length}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  if (entries.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        await LocalHistory.clear(path);
                        if (!ctx2.mounted) return;
                        setSheet(() => entries.clear());
                      },
                      child: Text(localizations.clear),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(localizations.editorLocalHistoryHint,
                      style:
                          TextStyle(fontSize: 11, color: theme.hintColor)),
                ),
              ),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  child: Text(localizations.editorLocalHistoryEmpty,
                      style: TextStyle(color: theme.hintColor)),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      // 倒序：最新的在最上面。
                      final e = entries[entries.length - 1 - i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.history, size: 18),
                        title: Text(
                            '${LocalHistory.formatTime(e.time)} · ${LocalHistory.formatBytes(e.bytes)}',
                            style: const TextStyle(fontSize: 13)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            tooltip: localizations.editorHistoryCompare,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.compare_arrows, size: 18),
                            onPressed: () async {
                              final text =
                                  await LocalHistory.read(path, e.epoch);
                              if (!mounted || !ctx.mounted) return;
                              if (text == null) {
                                _toast(localizations.editorLocalHistoryMissing);
                                return;
                              }
                              Navigator.pop(ctx);
                              await Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => TextDiffPage(
                                            initialLeft: text,
                                            initialRight: _applyNewline(
                                                controller.text,
                                                _newlineCharsOf(doc)),
                                            initialLeftName:
                                                '${doc.name} @ ${LocalHistory.formatTime(e.time)}',
                                            initialRightName: doc.name,
                                          )));
                            },
                          ),
                          IconButton(
                            tooltip: localizations.editorLocalHistoryRestore,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.restore, size: 18),
                            onPressed: () async {
                              final text =
                                  await LocalHistory.read(path, e.epoch);
                              if (!mounted || !ctx.mounted) return;
                              if (text == null) {
                                _toast(localizations.editorLocalHistoryMissing);
                                return;
                              }
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (d) => AlertDialog(
                                  title: Text(
                                      localizations.editorLocalHistoryRestore),
                                  content: Text(localizations
                                      .editorLocalHistoryRestoreAsk),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(d, false),
                                        child: Text(localizations.cancel)),
                                    TextButton(
                                        onPressed: () => Navigator.pop(d, true),
                                        child: Text(localizations.confirm)),
                                  ],
                                ),
                              );
                              if (ok != true || !mounted || !ctx.mounted) return;
                              Navigator.pop(ctx);
                              controller.text = text;
                              controller.selection =
                                  const TextSelection.collapsed(offset: 0);
                              _toast(localizations.editorLocalHistoryRestored);
                            },
                          ),
                        ]),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ]),
          );
        });
      },
    );
  }

  /// 任务列表：把散落在注释里的 TODO / FIXME 之类集中列出来（VS 的 Task List）。
  Future<void> _showTasks() async {
    final controller = _controller;
    if (controller == null) return;
    // path / 文件名 / 命中项；当前文件与工作区扫描共用同一种结构。
    var hits = <({String path, String name, TodoHit hit})>[];
    var loading = false;
    String? tagFilter;

    void scanCurrent() {
      final doc = _doc;
      if (doc == null) return;
      hits = TodoScanner.scan(controller.text, limit: 500)
          .map((h) =>
              (path: doc.path ?? '', name: doc.name, hit: h))
          .toList();
    }

    scanCurrent();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return StatefulBuilder(builder: (ctx2, setSheet) {
          final filtered = tagFilter == null
              ? hits
              : hits.where((e) => e.hit.tag == tagFilter).toList();
          final counts = TodoScanner.countByTag(
              hits.map((e) => e.hit).toList());
          return SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                child: Row(children: [
                  Expanded(
                    child: Text(
                        '${localizations.editorTasks} · ${filtered.length}/${hits.length}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  if (loading)
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    TextButton.icon(
                      onPressed: () async {
                        setSheet(() => loading = true);
                        final doc0 = _doc;
                        final result = <({String path, String name, TodoHit hit})>[];
                        if (doc0 != null) {
                          // `_collectScopeFiles` 已经把内容读好了（工作区 / 同目录 / 已打开），
                          // 这里直接扫内存，不再逐个文件做主线程 IO。
                          final scope = await _collectScopeFiles(doc0);
                          for (final sf in scope) {
                            if (result.length > 2000) break;
                            if (TodoScanner.tooLarge(sf.content,
                                maxBytes: 512 * 1024)) {
                              continue;
                            }
                            for (final h in TodoScanner.scan(sf.content,
                                limit: 200)) {
                              result.add((
                                path: sf.path ?? '',
                                name: sf.label,
                                hit: h
                              ));
                            }
                          }
                        }
                        if (!ctx2.mounted) return;
                        setSheet(() {
                          hits = result;
                          loading = false;
                          tagFilter = null;
                        });
                      },
                      icon: const Icon(Icons.travel_explore, size: 16),
                      label: Text(localizations.editorTasksScanWorkspace,
                          style: const TextStyle(fontSize: 12)),
                    ),
                ]),
              ),
              if (counts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: Wrap(spacing: 6, runSpacing: 4, children: [
                      ChoiceChip(
                        label: Text('${localizations.all} (${hits.length})',
                            style: const TextStyle(fontSize: 11)),
                        selected: tagFilter == null,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setSheet(() => tagFilter = null),
                      ),
                      for (final entry in counts.entries)
                        ChoiceChip(
                          label: Text('${entry.key} (${entry.value})',
                              style: const TextStyle(fontSize: 11)),
                          selected: tagFilter == entry.key,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) =>
                              setSheet(() => tagFilter = entry.key),
                        ),
                    ]),
                  ),
                ),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  child: Text(localizations.editorTasksEmpty,
                      style: TextStyle(color: theme.hintColor)),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final e = filtered[i];
                      return ListTile(
                        dense: true,
                        leading: _taskTagBadge(e.hit.tag),
                        title: Text(e.hit.text.isEmpty ? e.hit.tag : e.hit.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text('${e.name}:${e.hit.line}',
                            style: const TextStyle(fontSize: 11)),
                        onTap: () {
                          Navigator.pop(ctx);
                          unawaited(
                              _jumpToTask(e.path, e.hit.line));
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ]),
          );
        });
      },
    );
  }

  /// 文档统计（Notepad++ 的「摘要」、VS Code 的 Word Count）。
  ///
  /// 有选区时默认看选区的数据 —— 想数「这段多少字」是最常见的用法。
  Future<void> _showDocStats() async {
    final controller = _controller;
    final doc = _doc;
    if (controller == null || doc == null) return;
    final text = controller.text;
    if (text.isEmpty) {
      _toast(localizations.cannotBeEmpty);
      return;
    }
    final sel = controller.selection;
    final hasSelection =
        sel.isValid && !sel.isCollapsed && sel.start != sel.end;
    final whole = TextStats.of(text);
    final part =
        hasSelection ? TextStats.ofRange(text, sel.start, sel.end) : null;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        var useSelection = hasSelection;
        return StatefulBuilder(builder: (ctx2, setSheet) {
          final st = useSelection && part != null ? part : whole;
          Widget row(IconData icon, String label, String value) => ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(icon, size: 18),
                title: Text(label, style: const TextStyle(fontSize: 12.5)),
                trailing: Text(value,
                    style:
                        const TextStyle(fontSize: 13, fontFamily: 'monospace')),
              );
          return SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Row(children: [
                  Expanded(
                    child: Text(
                        '${localizations.editorDocStats} · ${doc.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
              if (hasSelection)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Row(children: [
                    ChoiceChip(
                      label: Text(
                          '${localizations.statsScopeSelection} (${TextStats.formatCount(part?.chars ?? 0)})',
                          style: const TextStyle(fontSize: 11)),
                      selected: useSelection,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setSheet(() => useSelection = true),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text(localizations.statsScopeAll,
                          style: const TextStyle(fontSize: 11)),
                      selected: !useSelection,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setSheet(() => useSelection = false),
                    ),
                  ]),
                ),
              row(Icons.format_list_numbered, localizations.statsLines,
                  TextStats.formatCount(st.lines)),
              row(Icons.short_text, localizations.statsWords,
                  TextStats.formatCount(st.words)),
              row(Icons.text_fields, localizations.statsChars,
                  TextStats.formatCount(st.chars)),
              row(Icons.space_bar, localizations.statsCharsNoSpace,
                  TextStats.formatCount(st.charsNoSpace)),
              row(Icons.data_object, localizations.statsBytes,
                  TextStats.formatBytes(st.bytes)),
              row(
                  Icons.straighten,
                  localizations.statsLongestLine,
                  st.maxLineLength == 0
                      ? '-'
                      : localizations.statsLongestLineValue(
                          '${st.longestLine}', '${st.maxLineLength}')),
              row(Icons.notes, localizations.statsParagraphs,
                  TextStats.formatCount(st.paragraphs)),
              const SizedBox(height: 8),
            ]),
          );
        });
      },
    );
  }

  /// 任务标签的小色块：不同类型给不同颜色，扫一眼能分出轻重。
  Widget _taskTagBadge(String tag) {
    Color color;
    switch (tag) {
      case 'FIXME':
      case 'BUG':
        color = const Color(0xFFE53935);
      case 'HACK':
      case 'XXX':
        color = const Color(0xFFFB8C00);
      case 'TODO':
        color = const Color(0xFF1E88E5);
      case 'REVIEW':
        color = const Color(0xFF8E24AA);
      default:
        color = const Color(0xFF43A047);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(tag,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  /// 跳到某个文件里的某一行（跨文件时先打开再跳）。
  Future<void> _jumpToTask(String path, int line) async {
    if (path.isNotEmpty && path != _doc?.path) {
      await _openPath(path);
      if (!mounted) return;
      // 打开文档后布局要一帧才完成，等一小会儿再定位。
      await Future.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
    }
    _gotoLineNumber(line);
  }

  /// 跳到第 [line] 行（1 开始）。没走内核的 `scrollToLine`，因为要先算偏移。
  void _gotoLineNumber(int line) {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    var offset = 0;
    var seen = 1;
    while (seen < line) {
      final i = text.indexOf('\n', offset);
      if (i < 0) break;
      offset = i + 1;
      seen++;
    }
    _jumpToOffset(offset);
  }

  /// 跳到上一处 / 下一处「相对磁盘的改动」（VS 的 F8 / Shift+F8）。
  ///
  /// 手机上没有 F8，而「我刚才改到哪了、下一处改的是哪」在长文件里靠肉眼翻很痛苦。
  /// 这里复用行号栏那套 diff 标记（[InlineDiff]），即使设置里关着标记也能用。
  void _gotoChange(int delta) {
    final controller = _controller;
    if (controller == null) return;
    final base = _doc?.diskBaseline;
    if (base == null || base.isEmpty) {
      _toast(localizations.editorNoChanges);
      return;
    }
    final marks = _inlineDiffMarks(controller.text, force: true);
    if (marks.isEmpty) {
      _toast(localizations.editorNoChanges);
      return;
    }
    final lines = marks.keys.toList()..sort();
    final cur = _caretLine;
    int target;
    if (delta > 0) {
      target = lines.firstWhere((l) => l > cur, orElse: () => lines.first);
    } else {
      int? prev;
      for (final l in lines.reversed) {
        if (l < cur) {
          prev = l;
          break;
        }
      }
      target = prev ?? lines.last;
    }
    _gotoLineNumber(target + 1);
    final kind = marks[target] ?? 0;
    _toast(kind == 0
        ? localizations.editorChangeAdded
        : (kind == 1
            ? localizations.editorChangeModified
            : localizations.editorChangeDeleted));
  }

  /// 解决 Git 合并冲突（VS 的 Merge Conflict 面板的等价物）。
  ///
  /// 手机上不敢让人手删 `<<<<<<<` 这种标记行——删错一行就吃掉相邻代码。
  /// 这里把每个冲突块找出来，三选一（当前 / 传入 / 两者）后整篇一次替换，
  /// 走 controller 替换所以还能撤销。
  Future<void> _showConflicts() async {
    final controller = _controller;
    if (controller == null) return;
    final blocks = findConflicts(controller.text);
    if (blocks.isEmpty) {
      _toast(localizations.editorNoConflicts);
      return;
    }
    final choices = <int, ConflictChoice>{};
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final color = Theme.of(ctx).colorScheme;
          Widget side(String title, List<String> lines, Color c) {
            final preview = lines.take(4).join('\n');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$title · ${lines.length}',
                    style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    preview.isEmpty ? '—' : preview,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.25),
                  ),
                ),
              ],
            );
          }

          Widget chip(int idx, ConflictChoice c, String label) {
            final on = choices[idx] == c;
            return Padding(
              padding: const EdgeInsets.only(right: 6, top: 6),
              child: ChoiceChip(
                label: Text(label, style: const TextStyle(fontSize: 11.5)),
                selected: on,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setSheet(() {
                  if (on) {
                    choices.remove(idx);
                  } else {
                    choices[idx] = c;
                  }
                }),
              ),
            );
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(
                      localizations.editorConflictCount(blocks.length),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      itemCount: blocks.length,
                      itemBuilder: (_, i) {
                        final b = blocks[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Text('#${i + 1}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: color.primary)),
                                  const SizedBox(width: 6),
                                  if (b.label.isNotEmpty)
                                    Expanded(
                                      child: Text(b.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11)),
                                    )
                                  else
                                    const Spacer(),
                                  Text('L${b.startLine + 1}-${b.endLine + 1}',
                                      style: TextStyle(
                                          fontSize: 10.5, fontFamily: 'monospace',
                                          color: color.onSurfaceVariant)),
                                ]),
                                const SizedBox(height: 4),
                                side(localizations.editorConflictOurs, b.ours, Colors.blue),
                                const SizedBox(height: 4),
                                side(localizations.editorConflictTheirs, b.theirs, Colors.green),
                                Wrap(children: [
                                  chip(i, ConflictChoice.ours, localizations.editorTakeOurs),
                                  chip(i, ConflictChoice.theirs, localizations.editorTakeTheirs),
                                  chip(i, ConflictChoice.both, localizations.editorTakeBoth),
                                  if (b.base.isNotEmpty)
                                    chip(i, ConflictChoice.base, localizations.editorTakeBase),
                                ]),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setSheet(() {
                            for (var i = 0; i < blocks.length; i++) {
                              choices[i] = ConflictChoice.ours;
                            }
                          }),
                          child: Text(localizations.editorConflictAllOurs,
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setSheet(() {
                            for (var i = 0; i < blocks.length; i++) {
                              choices[i] = ConflictChoice.theirs;
                            }
                          }),
                          child: Text(localizations.editorConflictAllTheirs,
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: choices.isEmpty
                            ? null
                            : () {
                                final text = applyConflicts(
                                    controller.text, blocks, Map.of(choices));
                                final left = conflictCount(text);
                                controller.replaceRange(
                                    0, controller.text.length, text);
                                Navigator.of(ctx).pop();
                                _toast(left == 0
                                    ? localizations.editorConflictsResolved(
                                        choices.length)
                                    : localizations.editorConflictLeft(left));
                              },
                        child: Text(
                            '${localizations.editorConflictApply} ${choices.length}/${blocks.length}',
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _expandSelection() {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    if (text.isEmpty) return;
    final sel = controller.selection;
    if (!sel.isValid) return;
    final start = sel.start.clamp(0, text.length);
    final end = sel.end.clamp(0, text.length);

    final lineStart = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
    var lineEnd = text.indexOf('\n', end);
    if (lineEnd < 0) lineEnd = text.length;

    void select(int a, int b) {
      controller.selection = TextSelection(
          baseOffset: a.clamp(0, text.length), extentOffset: b.clamp(0, text.length));
    }

    // 1) 光标 → 词 → 整行
    if (start == end) {
      final word = _wordRangeAt(text, start);
      if (word.end > word.start) {
        select(word.start, word.end);
        return;
      }
      select(lineStart, lineEnd);
      return;
    }

    // 2) 在字符串 / 注释里：不做括号扩级，直接给整行。
    if (_insideStringOrComment(text, start)) {
      select(lineStart, lineEnd);
      return;
    }

    // 3) 已经是整行 → 外层括号整块 / 全文
    if (start <= lineStart && end >= lineEnd) {
      final outer = _enclosingBracketChain(text, start, maxDepth: 16)
          .where((p) => p.$2 >= end)
          .toList(growable: false);
      if (outer.isNotEmpty) {
        final p = outer.last;
        select(p.$1, p.$2 + 1);
        return;
      }
      if (start > 0 || end < text.length) select(0, text.length);
      return;
    }

    // 4) 括号内 → 含括号 → 整行
    final chain = _enclosingBracketChain(text, start, maxDepth: 16);
    ({int a, int b})? pair;
    for (final p in chain) {
      if (p.$2 >= end) {
        pair = (a: p.$1, b: p.$2);
        break;
      }
    }
    if (pair != null) {
      if (start == pair.a + 1 && end == pair.b) {
        select(pair.a, pair.b + 1);
      } else {
        select(pair.a + 1, pair.b);
      }
      return;
    }
    select(lineStart, lineEnd);
  }

  /// 扫一遍文档里的符号。
  ///
  /// 「转到符号」和顶部面包屑都用它；结果按文本对象缓存，
  /// 否则光标每动一下就要重扫一遍全文。
  /// 一次扫描统计全文每个标识符的出现次数。
  ///
  /// 符号大纲里的「N 处引用」（VS Code 的 CodeLens 在手机上的等价物）用它：
  /// 逐个符号去全文 indexOf 是 O(符号数 × 文本长)，几百个符号的大文件会卡住；
  /// 正扫一遍再查表是 O(文本长)。
  static Map<String, int> _identifierCounts(String text) {
    final out = <String, int>{};
    for (final m in _identRe.allMatches(text)) {
      final w = m.group(0)!;
      out[w] = (out[w] ?? 0) + 1;
    }
    return out;
  }

  static final RegExp _identRe = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');

  /// 片段插入后还没走过的占位符（绝对偏移，按跳转顺序）。
  final List<SnippetStop> _snippetStops = [];

  List<_SymbolItem> _collectSymbols(String text) {
    final cached = _symbolCacheText;
    if (cached != null && identical(cached, text)) return _symbolCacheItems;
    final items = <_SymbolItem>[];
    // 匹配位置是递增的，行号就用「游标 + 数换行」增量算：300 个符号也只扫一遍全文，
    // 每个都调一次 _lineOfOffset 的话，大文件里打开这个列表会明显卡一下。
    var scanFrom = 0;
    var line = 0;
    for (final m in _symbolRe.allMatches(text)) {
      final kindWord = m.group(1);
      final name = kindWord != null ? m.group(2)! : m.group(4)!;
      final kind = kindWord ?? '';
      // Match 没有「取某一组起点」的方法，从整段匹配里找名字的位置（名字在行内唯一）。
      final offset = m.start + m.group(0)!.lastIndexOf(name);
      for (var i = scanFrom; i < offset && i < text.length; i++) {
        if (text.codeUnitAt(i) == 10) line++;
      }
      scanFrom = offset;
      // 缩进层级：VS 的符号大纲就是按层级缩进的，一眼能看出谁在谁里面。
      final raw = m.group(0)!;
      items.add((
        name: name,
        kind: kind,
        line: line,
        offset: offset,
        indent: raw.length - raw.trimLeft().length,
      ));
      if (items.length >= 300) break;
    }
    _symbolCacheText = text;
    _symbolCacheItems = items;
    return items;
  }

  /// 缓存：文本对象没换就直接复用（TextEditingController.text 未编辑时是同一实例）。
  String? _symbolCacheText;
  List<_SymbolItem> _symbolCacheItems = const <_SymbolItem>[];

  /// 重扫符号（供顶部面包屑用）。检查跑完后调一次，别放在 build 里。
  ///
  /// 超大文件直接放弃面包屑：那是给自己找卡顿，而且那种文件本来就该用「转到符号」。
  void _refreshSymbolCache() {
    final doc = _doc;
    if (doc == null) return;
    final text = doc.text;
    if (text.length > 262144) {
      _symbolCacheText = text;
      _symbolCacheItems = const <_SymbolItem>[];
      return;
    }
    _symbolCacheText = null;
    _collectSymbols(text);
  }

  /// 光标所在行属于哪条符号链（VS 顶部面包屑的 `Namespace › Class › Method`）。
  ///
  /// 按缩进做栈：遇到缩进不比栈顶深的符号就弹出，压入自己——
  /// 于是「行号 ≤ 当前行」跑完之后，栈里剩下的正好是层层包含的那几个。
  static List<_SymbolItem> _symbolTrail(List<_SymbolItem> symbols, int line) {
    final stack = <_SymbolItem>[];
    for (final item in symbols) {
      if (item.line > line) break;
      while (stack.isNotEmpty && stack.last.indent >= item.indent) {
        stack.removeLast();
      }
      stack.add(item);
    }
    return stack;
  }

  Future<void> _showSymbols() async {
    final controller = _controller;
    if (controller == null) return;
    if (_tooLargeForSync(controller.text, limit: 2000000)) return;
    final items = _collectSymbols(controller.text);
    if (!mounted) return;
    if (items.isEmpty) {
      _toast(localizations.editorSymbolsEmpty);
      return;
    }
    // 引用数只在能承受的文件上算（超大文本扫一遍要几百毫秒）。
    final counts = controller.text.length <= 200000
        ? _identifierCounts(controller.text)
        : const <String, int>{};
    // 加一个过滤框：几千行的文件里符号列表能有上百条，翻着找不如打两个字。
    var query = '';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final q = query.toLowerCase();
          final filtered = q.isEmpty
              ? items
              : items.where((it) => it.name.toLowerCase().contains(q)).toList(growable: false);
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: TextField(
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: localizations.editorSymbolsFilter,
                    border: const OutlineInputBorder(),
                    suffixText: '${filtered.length}/${items.length}',
                    suffixStyle: const TextStyle(fontSize: 11),
                  ),
                  onChanged: (v) => setSheet(() => query = v.trim()),
                ),
              ),
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(localizations.editorSymbolsEmpty,
                            style: const TextStyle(fontSize: 12.5)),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final it = filtered[i];
                          final indent = ((it.indent ~/ 4).clamp(0, 6)) * 10.0;
                          return Padding(
                            padding: EdgeInsets.only(left: indent),
                            child: ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: Icon(_symbolIcon(it.kind), size: 18),
                              title: Row(mainAxisSize: MainAxisSize.min, children: [
                                Flexible(
                                    child: Text(it.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13))),
                                if ((counts[it.name] ?? 0) > 1) ...[
                                  const SizedBox(width: 6),
                                  // 点引用数直接看「都谁用了它」，不用先跳过去再点菜单。
                                  InkWell(
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      final len = controller.text.length;
                                      controller.selection = TextSelection.collapsed(
                                          offset: it.offset.clamp(0, len));
                                      unawaited(_showReferences());
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 3),
                                      child: Text(
                                          localizations.editorRefTimes(counts[it.name]! - 1),
                                          style: TextStyle(
                                              fontSize: 10.5,
                                              color: Theme.of(ctx).colorScheme.primary)),
                                    ),
                                  ),
                                ],
                              ]),
                              trailing: Text('L${it.line + 1}',
                                  style: const TextStyle(fontSize: 11)),
                              onTap: () {
                                Navigator.pop(ctx);
                                final len = controller.text.length;
                                controller.selection =
                                    TextSelection.collapsed(offset: it.offset.clamp(0, len));
                                controller.scrollToLine(it.line);
                              },
                            ),
                          );
                        },
                      ),
              ),
            ]),
          );
        },
      ),
    );
  }

  /// 右侧问题分布条。
  ///
  /// 位置让开右侧滚动条（宽度按常见值估 10px），否则拖滚动条时会被这条细带挡一下。
  List<Widget> _issueRuler(EditorDocument doc) {
    final issues = _visibleIssues();
    if (issues.isEmpty && doc.bookmarks.isEmpty) return const <Widget>[];
    final total = _totalLinesOf(doc.text);
    final bookmarks = doc.bookmarks.map((o) => _lineOfOffset(doc.text, o)).toList(growable: false);
    final theme = Theme.of(context);

    int lineAt(double dy, double h) {
      if (total <= 0 || h <= 0) return 0;
      return (dy / h * total).floor().clamp(0, total - 1);
    }

    void jumpTo(int line) {
      doc.controller.selection = TextSelection.collapsed(offset: _offsetOfLine(doc.text, line));
      doc.controller.scrollToLine(line);
    }

    return <Widget>[
      // 触摸区 14dp、实际只画右侧 3px：3dp 宽点不准，14dp 又会让开滚动条。
      Positioned(
        right: 8,
        top: 0,
        bottom: 0,
        width: 14,
        child: LayoutBuilder(
          builder: (context, box) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 点一下直接跳（VS 的 overview ruler 行为）。
            onTapDown: (d) => jumpTo(lineAt(d.localPosition.dy, box.maxHeight)),
            // 长按先只报行号，松手再跳 —— 几千行的文件里 1px 就是几十行，
            // 盲点必然跳偏，得有个浮标能对。
            onLongPressStart: (d) => _previewRulerLine(lineAt(d.localPosition.dy, box.maxHeight)),
            onLongPressMoveUpdate: (d) =>
                _previewRulerLine(lineAt(d.localPosition.dy, box.maxHeight)),
            onLongPressEnd: (d) {
              jumpTo(lineAt(d.localPosition.dy, box.maxHeight));
              _clearRulerLine();
            },
            child: CustomPaint(
              painter: _RulerPainter(issues: issues, totalLines: total, bookmarks: bookmarks),
            ),
          ),
        ),
      ),
      if (_rulerLine != null)
        Positioned(
          right: 26,
          top: 6,
          child: IgnorePointer(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.inverseSurface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(4),
              ),
              // 顺带把这行的首个问题报出来：只报行号还得自己滑过去看。
              child: Text(
                _rulerHintOf(issues, _rulerLine!),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onInverseSurface),
              ),
            ),
          ),
        ),
    ];
  }

  /// 浮标文案：`L12 · 未闭合的括号`。该行没有问题时只显示行号。
  String _rulerHintOf(List<LintDiagnostic> issues, int line) {
    LintDiagnostic? first;
    for (final d in issues) {
      if (d.line != line) continue;
      if (first == null || d.severity.index < first.severity.index) first = d;
    }
    if (first == null) return 'L$line';
    return 'L$line · ${first.message}';
  }

  /// 长按分布条时的行号浮标：1.4 秒后自动消失（防止手指抬起事件丢了留个残影）。
  void _previewRulerLine(int line) {
    _rulerTimer?.cancel();
    setState(() => _rulerLine = line + 1);
    _rulerTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _rulerLine = null);
    });
  }

  void _clearRulerLine() {
    _rulerTimer?.cancel();
    if (_rulerLine != null) setState(() => _rulerLine = null);
  }

  /// 顶部面包屑（VS 的编辑器导航栏）：当前光标在哪条 `命名空间 › 类 › 方法` 里。
  ///
  /// 手机上没有横向空间放整串，所以只显示路径本身，点一下弹完整的符号大纲。
  /// 跳到某个符号（面包屑点击用）。
  void _jumpToSymbol(_SymbolItem item) {
    final controller = _controller;
    if (controller == null) return;
    final len = controller.text.length;
    controller.selection = TextSelection.collapsed(offset: item.offset.clamp(0, len));
    controller.scrollToLine(item.line);
  }

  Widget _breadcrumb() {
    final doc = _doc;
    if (doc == null || !_programming) return const SizedBox.shrink();
    // 多选操作栏和面包屑在手机上抢同一块地方：正在批量改的时候，路径没人在看。
    if (_multiSel.isNotEmpty) return const SizedBox.shrink();
    // 只读缓存：build 里绝不重扫全文（打字时每个字符都会 build 一次）。
    // 缓存由 [_refreshSymbolCache] 在检查跑完后刷新。
    if (!identical(_symbolCacheText, doc.text)) return const SizedBox.shrink();
    final trail = _symbolTrail(_symbolCacheItems, _caretLine < 0 ? 0 : _caretLine);
    if (trail.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7);
    final children = <Widget>[];
    for (var i = 0; i < trail.length; i++) {
      if (i > 0) {
        children.add(Icon(Icons.chevron_right, size: 13, color: muted));
      }
      children.add(Flexible(
        child: InkWell(
          // 点某一段直接跳到那个符号（VS 的面包屑也是这么用的）。
          onTap: i == trail.length - 1 ? _showSymbols : () => _jumpToSymbol(trail[i]),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Text(
              trail[i].name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: i == trail.length - 1 ? theme.colorScheme.primary : muted,
              ),
            ),
          ),
        ),
      ));
    }
    return InkWell(
      onTap: _showSymbols,
      child: Container(
        height: 22,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  /// 「查找所有引用」（VS 的 Shift+F12）：把这个词在全文出现的位置列出来。
  ///
  /// 和查找面板的区别是它**只找整词**、且直接从当前位置出发，不用先输入。
  Future<void> _showReferences({bool declarationsOnly = false}) async {
    final controller = _controller;
    final doc = _doc;
    if (controller == null || doc == null) return;
    final text = controller.text;
    final caret = controller.selection.baseOffset;
    final range = _wordRangeAt(text, caret < 0 ? 0 : caret);
    final name = text.substring(range.start, range.end);
    if (!_isSymbolName(name)) {
      _toast(declarationsOnly ? localizations.editorNoDefinition : localizations.editorReferencesEmpty);
      return;
    }

    final wordRe = RegExp(r'\b' + RegExp.escape(name) + r'\b');
    final hits = <_RefHit>[];
    final scanned = <String>{};

    void scan(String content, String label, String? path, bool current) {
      // 超大文本跳过：几 MB 的日志里做整词扫描既慢又没有意义。
      if (content.length > 2000000) return;
      // 「是不是声明」要跑 3 套正则全文扫描，只对中等大小的文件做（大文件只当引用）。
      final defOffsets =
          content.length <= 500000 ? _declarationOffsets(content, name).toSet() : <int>{};
      var count = 0;
      var lastLineStart = 0;
      var lastLine = 0;
      for (final m in wordRe.allMatches(content)) {
        if (count++ > 500) break;
        final at = m.start;
        final isDef = defOffsets.contains(at);
        if (declarationsOnly && !isDef) continue;
        // 行号用「上一个命中 → 本次命中」增量数换行，避免每处都从头扫。
        for (var i = lastLineStart; i < at; i++) {
          if (content.codeUnitAt(i) == 10) lastLine++;
        }
        lastLineStart = at;
        var lineEnd = content.indexOf('\n', at);
        if (lineEnd < 0) lineEnd = content.length;
        var lineStart = content.lastIndexOf('\n', at) + 1;
        if (lineStart < 0) lineStart = 0;
        hits.add(_RefHit(
          path: path,
          label: label,
          line: lastLine + 1,
          text: content.substring(lineStart, lineEnd).trim(),
          offset: at,
          isDefinition: isDef,
          isCurrent: current,
        ));
      }
    }

    // ① 已打开的文档：内存里就有，也包含当前文档本身。
    for (final d in _docs.docs) {
      final key = d.path ?? 'mem:${d.id}';
      if (!scanned.add(key)) continue;
      scan(d.text, d.name, d.path, identical(d, doc));
    }

    // ② 当前文件所在目录（不递归）：单文件 ≤1MB、最多 300 个，二进制按扩展名跳过。
    final basePath = doc.path;
    if (basePath != null) {
      try {
        final dir = File(basePath).parent;
        if (await dir.exists()) {
          var files = 0;
          await for (final e in dir.list(followLinks: false)) {
            if (files >= 300) break;
            if (e is! File) continue;
            if (!scanned.add(e.path)) continue;
            final lower = e.path.toLowerCase();
            if (_skipScanExts.any(lower.endsWith)) continue;
            try {
              if (await e.length() > 1024 * 1024) continue;
              files++;
              final content = await e.readAsString();
              scan(content, e.path.split(Platform.pathSeparator).last, e.path, false);
            } catch (_) {
              // 编码不是 UTF-8 / 文件恰好被删：跳过即可，不影响其它文件。
            }
          }
        }
      } catch (e) {
        logger.w('workspace scan failed', error: e);
      }
    }

    if (!mounted) return;
    if (hits.isEmpty) {
      _toast(declarationsOnly
          ? localizations.editorNoDefinition
          : localizations.editorReferencesEmpty);
      return;
    }

    // 定义优先、当前文件优先、行号升序 —— 第一条就是最可能要去的那个。
    hits.sort((a, b) {
      if (a.isDefinition != b.isDefinition) return a.isDefinition ? -1 : 1;
      if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
      final byLabel = a.label.compareTo(b.label);
      return byLabel != 0 ? byLabel : a.line.compareTo(b.line);
    });

    // 「转到实现」且只有唯一一处定义：直接跳过去，不弹列表。
    if (declarationsOnly && hits.length == 1) {
      await _openRefHit(hits.first);
      return;
    }

    final multiFile = hits.map((h) => h.label).toSet().length > 1;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(children: [
              Expanded(
                child: Text(
                  declarationsOnly
                      ? localizations.editorDefinitionsOf(name)
                      : localizations.editorReferencesOf(hits.length, name),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${hits.length}',
                  style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.outline)),
            ]),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: hits.length,
              itemBuilder: (ctx, i) {
                final h = hits[i];
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    h.isDefinition ? Icons.my_location_outlined : Icons.format_list_bulleted,
                    size: 16,
                    color: h.isDefinition ? Theme.of(ctx).colorScheme.primary : null,
                  ),
                  title: Text(h.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                  subtitle: Text(
                    multiFile ? '${h.label} · L${h.line}' : 'L${h.line}',
                    style: const TextStyle(fontSize: 10.5),
                  ),
                  trailing: h.isCurrent
                      ? IconButton(
                          icon: const Icon(Icons.visibility_outlined, size: 16),
                          tooltip: localizations.editorPeekDefinition,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () {
                            Navigator.pop(ctx);
                            unawaited(_showPeekAt(at: h.offset, title: name));
                          },
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_openRefHit(h, selectLength: name.length));
                  },
                );
              },
            ),
          ),
        ],
        ),
      ),
    );
  }

  /// 跳到一条跨文件命中：文件已打开就直接切过去，否则先按路径打开，再定位。
  Future<void> _openRefHit(_RefHit hit, {int selectLength = 0}) async {
    final path = hit.path;
    if (path != null) {
      EditorDocument? target;
      for (final d in _docs.docs) {
        if (d.path == path) {
          target = d;
          break;
        }
      }
      if (target != null) {
        if (!identical(target, _doc)) _activate(target);
      } else {
        await _openPath(path);
        if (!mounted) return;
        // 点中的可能是二进制 / 压缩包，`_openPath` 会转去预览页而不切文档；
        // 这种情况下再「定位」就会跳到当前文档的错误位置，直接收手。
        if (_doc?.path != path) return;
      }
    }
    // 切换 / 打开文档是异步的（还会重建 controller），等一帧再定位。
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;
    final c = _controller;
    if (c == null) return;
    final len = c.text.length;
    if (hit.offset > len) return;
    final end = (hit.offset + selectLength).clamp(hit.offset, len);
    c.selection = TextSelection(baseOffset: hit.offset, extentOffset: end);
    c.scrollToLine(_lineOfOffset(c.text, hit.offset));
  }

  static String _lineTextAt(String text, int line) {
    final start = _offsetOfLine(text, line);
    var end = text.indexOf('\n', start);
    if (end < 0) end = text.length;
    return text.substring(start, end);
  }

  static IconData _symbolIcon(String kind) {
    switch (kind) {
      case 'class':
      case 'record':
        return Icons.class_outlined;
      case 'struct':
        return Icons.view_in_ar_outlined;
      case 'interface':
        return Icons.offline_bolt_outlined;
      case 'enum':
        return Icons.list_alt;
      case 'namespace':
        return Icons.folder_outlined;
      default:
        return Icons.functions;
    }
  }

  Future<void> _showLineOpsMenu() async {
    final size = MediaQuery.of(context).size;
    final chosen = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(size.width - 190, kToolbarHeight + 40, 20, 0),
      items: [
        PopupMenuItem(value: 'delete', child: Text(localizations.editorDeleteLine)),
        PopupMenuItem(value: 'duplicate', child: Text(localizations.editorDuplicateLine)),
        PopupMenuItem(value: 'up', child: Text(localizations.editorMoveLineUp)),
        PopupMenuItem(value: 'down', child: Text(localizations.editorMoveLineDown)),
        PopupMenuItem(value: 'join', child: Text(localizations.editorJoinLine)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'indent', child: Text(localizations.editorIndent)),
        PopupMenuItem(value: 'outdent', child: Text(localizations.editorOutdent)),
        PopupMenuItem(value: 'sortAsc', child: Text(localizations.editorSortAsc)),
        PopupMenuItem(value: 'sortDesc', child: Text(localizations.editorSortDesc)),
        PopupMenuItem(value: 'dedupe', child: Text(localizations.editorDedupeLines)),
        PopupMenuItem(value: 'insertAbove', child: Text(localizations.editorInsertLineAbove)),
        PopupMenuItem(value: 'insertBelow', child: Text(localizations.editorInsertLineBelow)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'indentToSpaces', child: Text(localizations.editorIndentToSpaces)),
        PopupMenuItem(value: 'indentToTabs', child: Text(localizations.editorIndentToTabs)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'align', child: Text(localizations.editorAlignBy)),
        PopupMenuItem(value: 'sortLenAsc', child: Text(localizations.editorSortByLengthAsc)),
        PopupMenuItem(value: 'sortLenDesc', child: Text(localizations.editorSortByLengthDesc)),
        PopupMenuItem(value: 'appendComma', child: Text(localizations.editorAppendComma)),
        PopupMenuItem(value: 'stripComma', child: Text(localizations.editorStripComma)),
        PopupMenuItem(value: 'removeBlank', child: Text(localizations.editorRemoveBlankLines)),
        PopupMenuItem(value: 'collapseBlank', child: Text(localizations.editorCollapseBlankLines)),
      ],
    );
    if (chosen == null) return;
    switch (chosen) {
      case 'indent':
        _indentLines(outdent: false);
      case 'outdent':
        _indentLines(outdent: true);
      case 'sortAsc':
        _sortLines(ascending: true);
      case 'sortDesc':
        _sortLines(ascending: false);
      case 'dedupe':
        _dedupeLines();
      case 'insertAbove':
        _insertBlankLine(above: true);
      case 'insertBelow':
        _insertBlankLine(above: false);
      case 'indentToSpaces':
        _convertIndent(toSpaces: true);
      case 'indentToTabs':
        _convertIndent(toSpaces: false);
      case 'align':
        _applyLineTransform(alignByDelimiter);
      case 'sortLenAsc':
        _sortLinesByLength(ascending: true);
      case 'sortLenDesc':
        _sortLinesByLength(ascending: false);
      case 'appendComma':
        _toggleTrailingComma(add: true);
      case 'stripComma':
        _toggleTrailingComma(add: false);
      case 'removeBlank':
        _applyLineTransform(removeBlankLines);
      case 'collapseBlank':
        _applyLineTransform(collapseBlankLines);
      default:
        _lineOp(chosen);
    }
  }

  /// 按行长度排序（字典序排序的补充）。
  ///
  /// 对齐日志/哈希/URL 列表时，先按长度排一遍，同类长度的会聚在一起，
  /// 一眼就能看出哪几行是异常项。
  void _sortLinesByLength({required bool ascending}) {
    _applyLineTransform((text) {
      final lines = text.split('\n');
      final order = List<int>.generate(lines.length, (i) => i);
      order.sort((a, b) {
        final d = lines[a].trim().length.compareTo(lines[b].trim().length);
        if (d != 0) return ascending ? d : -d;
        // 长度相同保持原顺序（稳定排序），否则排序结果每次都不一样
        return a.compareTo(b);
      });
      return order.map((i) => lines[i]).join('\n');
    });
  }

  /// 每行末尾加/去逗号。
  ///
  /// 把一列值塞进 JSON 数组或 SQL 的 IN 列表时，最后一步就是给每行补逗号；
  /// 空行不动，已经有逗号的不重复加。
  void _toggleTrailingComma({required bool add}) {
    _applyLineTransform((text) {
      final out = <String>[];
      for (final line in text.split('\n')) {
        final t = line.trimRight();
        if (t.isEmpty) {
          out.add(line);
          continue;
        }
        if (add) {
          out.add(t.endsWith(',') ? line : '$t,');
        } else {
          out.add(t.endsWith(',') ? t.substring(0, t.length - 1) : line);
        }
      }
      return out.join('\n');
    });
  }

  /// 行操作：VS Code 里是 Ctrl+Shift+K（删除行）、Alt+Shift+↑/↓（移动行）这一组。
  /// 把整篇（或选区覆盖的行）交给一个纯文本变换函数，并保留撤销。
  ///
  /// 「对齐 / 删空行 / 合并空行」都是整段处理：手机上没法先精确选中再操作，
  /// 所以有选区就用选区，没有就全文。
  void _applyLineTransform(String Function(String) transform) {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    if (text.isEmpty) return;
    final sel = controller.selection;
    final hasSel = sel.isValid && !sel.isCollapsed;
    final result = hasSel
        ? text.replaceRange(sel.start, sel.end, transform(text.substring(sel.start, sel.end)))
        : transform(text);
    if (result == text) {
      _toast(localizations.editorTransformNoChange);
      return;
    }
    // 整篇替换走 replaceRange：撤销粒度是一次操作，不会把用户之前的编辑挤掉
    controller.replaceRange(0, text.length, result);
    controller.selection = TextSelection.collapsed(offset: result.length);
  }

  /// 手机上不给快捷键，全部收进菜单——但语义保持一致。
  /// 行操作（删除 / 复制 / 上移 / 下移 / 合并行）。
  ///
  /// 有多光标时对每个光标所在行各做一次（VS 里也是这个行为）。
  void _lineOp(String op) {
    final controller = _controller;
    if (controller == null) return;
    if (controller.hasMultiCursors) {
      _lineOpAtCursors(op);
      return;
    }
    _lineOpSingle(op);
  }

  /// 多光标下的行操作：**从下往上**逐行执行，这样上面几行的行号不会被
  /// 下面的插入/删除挤偏；执行完光标按原列落到最上面那一行。
  void _lineOpAtCursors(String op) {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final lineCount = '\n'.allMatches(text).length + 1;
    final mainOffset = controller.selection.extentOffset.clamp(0, text.length);
    final mainLine = _lineOfOffset(text, mainOffset);
    final cols = <int, int>{};
    for (final c in controller.multiCursors) {
      cols[c.line.clamp(0, lineCount - 1)] = c.character;
    }
    cols[mainLine] = mainOffset - _offsetOfLine(text, mainLine);
    final ordered = cols.keys.toList()..sort((a, b) => b.compareTo(a));
    controller.clearMultiCursors();
    for (final line in ordered) {
      final t = controller.text;
      final lc = '\n'.allMatches(t).length + 1;
      if (line >= lc) continue;
      final start = _offsetOfLine(t, line);
      final end = line + 1 < lc ? _offsetOfLine(t, line + 1) - 1 : t.length;
      final room = end > start ? end - start : 0;
      final col = (cols[line] ?? 0).clamp(0, room);
      controller.selection = TextSelection.collapsed(offset: start + col);
      _lineOpSingle(op);
    }
    if (mounted) setState(() {});
  }

  /// 折叠到第 N 层（VS 的 Ctrl+K Ctrl+2）：
  /// 先全展开，再把「缩进层级正好等于 N」的块折起来 —— 更深的块跟着父块一起隐藏，
  /// 视觉上就是「只显示到第 N 层」，和 VS 的语义一致。
  Future<void> _showFoldLevelPicker() async {
    final controller = _controller;
    if (controller == null) return;
    final loc = localizations;
    final level = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(loc.editorFoldToLevel, style: const TextStyle(fontSize: 15)),
        children: [
          for (var i = 1; i <= 5; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, i),
              child: Text('${loc.editorFoldLevelN('$i')}'),
            ),
        ],
      ),
    );
    if (level == null || !mounted) return;
    _foldToLevel(level);
  }

  void _foldToLevel(int level) {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    if (text.isEmpty) return;
    try {
      controller.unfoldAll();
    } catch (_) {}
    // 一次扫完算出每行的缩进层级（逐行 _offsetOfLine 会是 O(n²)）。
    final tab = _prefs.tabSize.clamp(1, 16).toInt();
    final levels = <int, int>{};
    var line = 0;
    var width = 0;
    var inIndent = true;
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c == 10) {
        levels[line] = width ~/ tab;
        line++;
        width = 0;
        inIndent = true;
        continue;
      }
      if (!inIndent) continue;
      if (c == 9) {
        width += tab;
      } else if (c == 32) {
        width += 1;
      } else {
        levels[line] = width ~/ tab;
        inIndent = false;
      }
    }
    levels[line] = width ~/ tab;

    final keys = controller.foldings.keys.toList()..sort();
    var folded = 0;
    for (final l in keys) {
      if ((levels[l] ?? -1) != level) continue;
      try {
        controller.toggleFold(l);
        folded++;
      } catch (_) {
        // 该行没有可折叠区域（或折叠没启用），跳过即可。
      }
    }
    setState(() {});
    _toast(localizations.editorFoldLevelDone('$level', '$folded'));
  }

  /// 选中当前行（Ctrl+L）：光标在哪行就整行选中，含行尾换行。
  void _selectCurrentLine() {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final caret = controller.selection.extentOffset.clamp(0, text.length);
    final line = _lineOfOffset(text, caret);
    final start = _offsetOfLine(text, line);
    final lineCount = '\n'.allMatches(text).length + 1;
    final end = line + 1 < lineCount ? _offsetOfLine(text, line + 1) : text.length;
    controller.selection = TextSelection(baseOffset: start, extentOffset: end);
    setState(() {});
  }

  /// 把当前行复制到上/下一行（Shift+Alt+↑↓）。
  void _duplicateLine(bool above) {
    final controller = _controller;
    final span = _currentLineSpan();
    if (controller == null || span == null) return;
    final text = controller.text;
    final line = text.substring(span.start, span.end);
    if (above) {
      controller.replaceRange(span.start, span.start, '$line\n');
      controller.selection = TextSelection.collapsed(offset: span.start);
    } else {
      final tail = span.hasNewline ? span.end + 1 : text.length;
      final insert = span.hasNewline ? '$line\n' : '\n$line';
      controller.replaceRange(tail, tail, insert);
      controller.selection = TextSelection.collapsed(offset: tail);
    }
    setState(() {});
  }

  void _lineOpSingle(String op) {
    final controller = _controller;
    final span = _currentLineSpan();
    if (controller == null || span == null) return;
    final text = controller.text;
    switch (op) {
      case 'delete':
        final cutEnd = span.hasNewline ? span.end + 1 : span.end;
        controller.replaceRange(span.start, cutEnd, '');
        controller.selection =
            TextSelection.collapsed(offset: span.start.clamp(0, controller.text.length));
      case 'duplicate':
        final line = text.substring(span.start, span.end);
        if (span.hasNewline) {
          controller.replaceRange(span.end + 1, span.end + 1, '$line\n');
          controller.selection = TextSelection.collapsed(offset: span.end + 1 + line.length + 1);
        } else {
          controller.replaceRange(text.length, text.length, '\n$line');
          controller.selection = TextSelection.collapsed(offset: text.length + 1 + line.length);
        }
      case 'up':
        if (span.start == 0) return;
        final prevEnd = span.start - 1; // 上一行末尾，也就是换行符的位置
        final prevStart = prevEnd == 0 ? 0 : text.lastIndexOf('\n', prevEnd - 1) + 1;
        final prev = text.substring(prevStart, prevEnd);
        final cur = text.substring(span.start, span.end);
        controller.replaceRange(prevStart, span.end, '$cur\n$prev');
        controller.selection = TextSelection.collapsed(offset: prevStart + cur.length + 1);
      case 'down':
        if (!span.hasNewline) return;
        final nextStart = span.end + 1;
        if (nextStart >= text.length) return;
        var nextEnd = text.indexOf('\n', nextStart);
        if (nextEnd < 0) nextEnd = text.length;
        final cur = text.substring(span.start, span.end);
        final next = text.substring(nextStart, nextEnd);
        controller.replaceRange(span.start, nextEnd, '$next\n$cur');
        controller.selection = TextSelection.collapsed(offset: span.start + next.length + 1);
      case 'join':
        if (!span.hasNewline) return;
        final nextStart = span.end + 1;
        var nextEnd = text.indexOf('\n', nextStart);
        if (nextEnd < 0) nextEnd = text.length;
        // 合并时去掉下一行的前导缩进（VS 也这么做），否则接出来一长串空格。
        final next = text.substring(nextStart, nextEnd).trimLeft();
        controller.replaceRange(span.end, nextEnd, next);
    }
  }

  /// 缩进 / 反缩进：有选区就作用于选中的全部行，否则当前行。
  void _indentLines({required bool outdent}) {
    final controller = _controller;
    final span = _currentLineSpan();
    if (controller == null || span == null) return;
    final text = controller.text;
    final sel = controller.selection;
    var start = span.start;
    var end = span.end;
    if (sel.isValid && sel.start != sel.end) {
      final a = sel.start.clamp(0, text.length);
      final b = sel.end.clamp(0, text.length);
      start = a == 0 ? 0 : text.lastIndexOf('\n', a - 1) + 1;
      final nl = text.indexOf('\n', b);
      end = nl < 0 ? text.length : nl;
    }
    final block = text.substring(start, end);
    final unit = _prefs.useTabs ? '\t' : ' ' * _prefs.tabSize;
    final out = block.split('\n').map((l) {
      if (!outdent) return '$unit$l';
      if (l.startsWith(unit)) return l.substring(unit.length);
      // 不足一个单位的（混用空格 / Tab 的文件）能去多少去多少。
      var i = 0;
      while (i < l.length && i < _prefs.tabSize && l[i] == ' ') {
        i++;
      }
      return l.substring(i);
    }).join('\n');
    if (out == block) return;
    controller.replaceRange(start, end, out);
    controller.selection = TextSelection(baseOffset: start, extentOffset: start + out.length);
  }

  /// 行排序（VS 的 Sort Lines）：有选区排选中行，否则整篇。
  void _sortLines({required bool ascending}) {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final sel = controller.selection;
    var start = 0;
    var end = text.length;
    if (sel.isValid && sel.start != sel.end) {
      final a = sel.start.clamp(0, text.length);
      final b = sel.end.clamp(0, text.length);
      start = a == 0 ? 0 : text.lastIndexOf('\n', a - 1) + 1;
      final nl = text.indexOf('\n', b);
      end = nl < 0 ? text.length : nl;
    }
    if (end <= start) return;
    final lines = text.substring(start, end).split('\n');
    if (lines.length < 2) return;
    final sorted = List<String>.from(lines);
    ascending ? sorted.sort() : sorted.sort((x, y) => y.compareTo(x));
    final out = sorted.join('\n');
    if (out == lines.join('\n')) return;
    controller.replaceRange(start, end, out);
    controller.selection = TextSelection(baseOffset: start, extentOffset: start + out.length);
  }

  /// 删除重复行（保留首次出现）；有选区时只处理选中部分。
  void _dedupeLines() {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final sel = controller.selection;
    var start = 0;
    var end = text.length;
    if (sel.isValid && sel.start != sel.end) {
      final a = sel.start.clamp(0, text.length);
      final b = sel.end.clamp(0, text.length);
      start = a == 0 ? 0 : text.lastIndexOf('\n', a - 1) + 1;
      final nl = text.indexOf('\n', b);
      end = nl < 0 ? text.length : nl;
    }
    if (end <= start) return;
    final lines = text.substring(start, end).split('\n');
    final seen = <String>{};
    final kept = <String>[];
    for (final l in lines) {
      // 空行不参与去重（否则整篇的空行全没了，观感很差）。
      if (l.trim().isEmpty) {
        kept.add(l);
        continue;
      }
      if (seen.add(l)) kept.add(l);
    }
    if (kept.length == lines.length) {
      _toast(localizations.editorDedupeNone);
      return;
    }
    final out = kept.join('\n');
    controller.replaceRange(start, end, out);
    controller.selection = TextSelection(baseOffset: start, extentOffset: start + out.length);
    _toast(localizations.editorDedupeDone('${lines.length - kept.length}'));
  }

  /// 在当前行上方 / 下方插入一个空行（VS 的 Ctrl+Enter / Ctrl+Shift+Enter）。
  /// 全文缩进转换（VS 的 Convert Indentation to Spaces / Tabs）。
  ///
  /// 逐行只看**行首**空白：行中间的 Tab 不动（那些是内容，不是缩进）。
  /// 空格数不是 Tab 大小的整数倍时保留余数，避免把对齐的表格打散。
  void _convertIndent({required bool toSpaces}) {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    if (text.isEmpty) return;
    final tab = _prefs.tabSize.clamp(1, 16).toInt();
    final buf = StringBuffer();
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (toSpaces) {
        buf.write(line.replaceFirstMapped(RegExp(r'^\t+'), (m) => ' ' * (m.group(0)!.length * tab)));
      } else {
        final m = RegExp(r'^ +').firstMatch(line);
        if (m == null) {
          buf.write(line);
        } else {
          final n = m.group(0)!.length;
          buf.write('${'\t' * (n ~/ tab)}${' ' * (n % tab)}${line.substring(n)}');
        }
      }
      if (i != lines.length - 1) buf.write('\n');
    }
    controller.text = buf.toString();
    setState(() {});
    _toast(localizations.editorIndentConverted);
  }

  void _insertBlankLine({required bool above}) {
    final controller = _controller;
    final span = _currentLineSpan();
    if (controller == null || span == null) return;
    if (above) {
      controller.replaceRange(span.start, span.start, '\n');
      controller.selection = TextSelection.collapsed(offset: span.start);
    } else {
      // 行尾（有换行时就是换行符的位置，末行则是文本末尾）插一个换行 → 下方多一个空行。
      final at = span.end;
      controller.replaceRange(at, at, '\n');
      controller.selection = TextSelection.collapsed(offset: at + 1);
    }
  }

  Future<void> _showCaseOpsMenu() async {
    final size = MediaQuery.of(context).size;
    final chosen = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(size.width - 190, kToolbarHeight + 40, 20, 0),
      items: [
        PopupMenuItem(value: 'upper', child: Text(localizations.editorUpperCase)),
        PopupMenuItem(value: 'lower', child: Text(localizations.editorLowerCase)),
        PopupMenuItem(value: 'title', child: Text(localizations.editorTitleCase)),
        const PopupMenuDivider(),
        // 命名风格（VS Code 的 Transform to Camel/Pascal/Snake/Kebab/Constant Case）
        PopupMenuItem(value: 'camel', child: Text(localizations.editorCamelCase)),
        PopupMenuItem(value: 'pascal', child: Text(localizations.editorPascalCase)),
        PopupMenuItem(value: 'snake', child: Text(localizations.editorSnakeCase)),
        PopupMenuItem(value: 'kebab', child: Text(localizations.editorKebabCase)),
        PopupMenuItem(value: 'constant', child: Text(localizations.editorConstantCase)),
      ],
    );
    if (chosen != null) _changeCase(chosen);
  }

  /// 大小写转换：有选区转选区，没选区转光标所在的词。
  void _changeCase(String mode) {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final sel = controller.selection;
    if (!sel.isValid) return;
    var start = sel.start;
    var end = sel.end;
    if (start == end) {
      final range = _wordRangeAt(text, start);
      start = range.start;
      end = range.end;
    }
    start = start.clamp(0, text.length);
    end = end.clamp(start, text.length);
    if (end <= start) return;
    final chunk = text.substring(start, end);
    final converted = switch (mode) {
      'upper' => chunk.toUpperCase(),
      'lower' => chunk.toLowerCase(),
      'camel' || 'pascal' || 'snake' || 'kebab' || 'constant' =>
        convertNamingCase(chunk, namingCaseOf(mode)!),
      _ => _titleCase(chunk),
    };
    if (converted == chunk) return;
    controller.replaceRange(start, end, converted);
    controller.selection = TextSelection(baseOffset: start, extentOffset: start + converted.length);
  }

  // ------------------------------ VS 的编辑动作补充 ------------------------------

  /// 保存时补一个末尾换行（`.editorconfig` 的 `insert_final_newline = true`）。
  void _ensureFinalNewline(EditorDocument doc) {
    final controller = doc.controller;
    final text = controller.text;
    if (text.isEmpty || text.endsWith('\n') || text.endsWith('\r')) return;
    controller.replaceRange(text.length, text.length, '\n');
  }

  /// 状态栏的缩进段：文件所在项目写了 `.editorconfig` 就按它的缩进来显示。
  String _indentLabelFor(EditorDocument doc) {
    final cfg = doc.editorConfig;
    var useTabs = _prefs.useTabs;
    if (cfg?.indentStyle == 'tab') useTabs = true;
    if (cfg?.indentStyle == 'space') useTabs = false;
    final size = cfg?.indentSize ?? cfg?.tabWidth ?? _prefs.tabSize;
    return useTabs ? 'Tab:$size' : 'Space:$size';
  }

  /// 对任意文档做「保存时修剪行尾空白」：同步改缓冲区（保住光标），不提示。
  void _trimDocTrailingWhitespace(EditorDocument doc) {
    final controller = doc.controller;
    final before = controller.text;
    if (before.isEmpty) return;
    final after = stripTrailingWhitespace(before);
    if (after == before) return;
    final sel = controller.selection;
    final start = sel.isValid ? sel.start.clamp(0, after.length) : null;
    final end = sel.isValid ? sel.end.clamp(0, after.length) : null;
    controller.replaceRange(0, before.length, after);
    if (start != null && end != null) {
      controller.selection = TextSelection(baseOffset: start, extentOffset: end);
    }
  }

  /// 保存时静默修剪行尾空白（当前文档）。
  void _trimOnSaveQuiet() {
    final doc = _doc;
    if (doc == null) return;
    _trimDocTrailingWhitespace(doc);
  }

  /// 修剪行尾空白（VS 的 Trim Trailing Whitespace）。
  ///
  /// 有选区只处理选区覆盖到的行，没选区处理全文 —— 和 VS 一致，
  /// 免得「想清理这三行」把整篇都改了。
  void _trimTrailingWhitespace() {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final sel = controller.selection;
    var from = 0;
    var to = text.length;
    if (sel.isValid && !sel.isCollapsed) {
      final s0 = sel.start.clamp(0, text.length);
      final e0 = sel.end.clamp(s0, text.length);
      from = text.lastIndexOf('\n', s0) + 1;
      final nl = text.indexOf('\n', e0);
      to = nl < 0 ? text.length : nl;
    }
    final lines = text.substring(from, to).split('\n');
    var changed = 0;
    final trailing = RegExp(r'[ \t]+$');
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].replaceFirst(trailing, '');
      if (trimmed != lines[i]) {
        lines[i] = trimmed;
        changed++;
      }
    }
    if (changed == 0) {
      _toast(localizations.editorNothingToTrim);
      return;
    }
    final replaced = lines.join('\n');
    controller.replaceRange(from, to, replaced);
    final end = (from + replaced.length).clamp(0, controller.text.length);
    controller.selection = TextSelection.collapsed(offset: end);
    _toast(localizations.editorTrimmed(changed));
  }

  /// 选中从光标处括号到它配对括号之间的内容（VS 的 Ctrl+Shift+\ 的「选择到括号」）。
  void _selectToBracket() {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final caret = controller.selection.extentOffset;
    if (caret < 0 || caret > text.length) return;
    const opens = '([{';
    const closes = ')]}';
    int? pos;
    if (caret < text.length && (opens.contains(text[caret]) || closes.contains(text[caret]))) {
      pos = caret;
    } else if (caret > 0 && (opens.contains(text[caret - 1]) || closes.contains(text[caret - 1]))) {
      pos = caret - 1;
    }
    if (pos == null) {
      _toast(localizations.editorNoBracket);
      return;
    }
    final ch = text[pos];
    final other = opens.contains(ch)
        ? _findClosing(text, pos, ch)
        : _findOpening(text, pos, ch);
    if (other == null) {
      _toast(localizations.editorNoBracket);
      return;
    }
    final start = pos < other ? pos : other;
    final end = (pos < other ? other : pos) + 1;
    controller.selection = TextSelection(baseOffset: start, extentOffset: end);
    controller.scrollToLine(_lineOfOffset(text, start));
  }

  /// 把选区（或全文）转义成字符串字面量 / 反解回来的对话框。
  ///
  /// 手机上手工改 `\n` `\"` 这类转义几乎做不到，而这个动作在日常里很频繁
  /// （SQL 塞进一行日志、日志里的转义还原、粘进 JSON 配置）。
  Future<void> _showEscapeDialog() async {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final sel = controller.selection;
    final hasSel = sel.isValid && !sel.isCollapsed;
    final start = hasSel ? sel.start.clamp(0, text.length) : 0;
    final end = hasSel ? sel.end.clamp(0, text.length) : text.length;
    final source = text.substring(start, end);
    if (source.isEmpty) {
      _toast(localizations.cannotBeEmpty);
      return;
    }
    var dialect = EscapeDialect.cLike;
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final color = Theme.of(ctx).colorScheme;
          String preview(bool escape) {
            final r = escape ? escapeText(source, dialect: dialect) : unescapeText(source);
            return r.length > 2000 ? '${r.substring(0, 2000)}…' : r;
          }

          const names = ['C / JSON', 'SQL', '正则'];
          const kinds = [EscapeDialect.cLike, EscapeDialect.sql, EscapeDialect.regex];
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(localizations.editorEscape,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    localizations.editorEscapeHint(hasSel ? source.length : 0),
                    style: TextStyle(fontSize: 11.5, color: color.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, children: [
                    for (var i = 0; i < kinds.length; i++)
                      ChoiceChip(
                        label: Text(names[i], style: const TextStyle(fontSize: 11.5)),
                        selected: dialect == kinds[i],
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setSheet(() => dialect = kinds[i]),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 160),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        preview(true),
                        style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', height: 1.3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(unescapeText(source)),
                        child: Text(localizations.editorUnescapeDo,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.of(ctx).pop(escapeText(source, dialect: dialect)),
                        child: Text(localizations.editorEscapeDo,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (!mounted || result == null) return;
    if (hasSel) {
      controller.replaceRange(start, end, result);
      controller.selection = TextSelection.collapsed(offset: start + result.length);
    } else {
      controller.replaceRange(0, controller.text.length, result);
      controller.selection = TextSelection.collapsed(offset: result.length);
    }
    _toast(localizations.editorEscapeDone);
  }

  /// 在光标处插入当前日期时间（VS Code 的 Insert Date Time）。
  ///
  /// 写日志、写 TODO、写变更说明时最常用；手机上每次手打这串数字很烦。
  void _insertDateTime() {
    final now = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    _insertAtCursor('${now.year}-${p(now.month)}-${p(now.day)} '
        '${p(now.hour)}:${p(now.minute)}:${p(now.second)}');
  }

  /// 列选择：在选区覆盖的每一行的「选区起始列」各加一个光标。
  ///
  /// 手机上没法按住 Alt 拖框，但「先选一段、再按列加光标」效果一样 ——
  /// 对齐的配置表、日志、CSV 批量改同一列时很省事（VS Code 的 Add Cursors to Line Ends
  /// / 列选择）。
  void _addColumnCursors() {
    final c = _controller;
    if (c == null) return;
    final text = c.text;
    final sel = c.selection;
    if (!sel.isValid || sel.isCollapsed) {
      _toast(localizations.editorColumnNeedSelection);
      return;
    }
    final start = sel.start.clamp(0, text.length);
    final end = sel.end.clamp(start, text.length);
    final firstLineStart = text.lastIndexOf('\n', start) + 1;
    final column = start - firstLineStart;
    var line = _lineOfOffset(text, start);
    var offset = start;
    var added = 0;
    try {
      c.clearMultiCursors();
      while (true) {
        // 第一行就是光标本身，只给后面的行补光标。
        if (added > 0) c.addMultiCursor(line, column);
        added++;
        if (added > 5000) break; // 兜底：别让一次误操作造出上万个光标
        final nl = text.indexOf('\n', offset);
        if (nl < 0 || nl >= end) break;
        offset = nl + 1;
        line++;
      }
    } catch (e) {
      logger.w('column cursors failed', error: e);
    }
    if (added <= 1) {
      _toast(localizations.editorColumnNeedMultiLine);
      return;
    }
    _toast(localizations.editorColumnCursors(added));
  }

  /// 打开光标处（或选中内容）的 http(s) 链接。
  Future<void> _openLinkAtCursor() async {
    final c = _controller;
    if (c == null) return;
    final text = c.text;
    final sel = c.selection;
    String candidate;
    if (sel.isValid && !sel.isCollapsed) {
      candidate = text.substring(sel.start.clamp(0, text.length), sel.end.clamp(0, text.length));
    } else {
      var s0 = sel.extentOffset.clamp(0, text.length);
      var e0 = s0;
      while (s0 > 0 && !_isUrlBoundary(text.codeUnitAt(s0 - 1))) {
        s0--;
      }
      while (e0 < text.length && !_isUrlBoundary(text.codeUnitAt(e0))) {
        e0++;
      }
      candidate = text.substring(s0, e0);
    }
    // 句尾标点不该算进链接（"见 https://a.com/x." 这类）。
    candidate = candidate.trim().replaceAll(RegExp(r'[。，、；：）」』】>]+$'), '');
    final uri = Uri.tryParse(candidate);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      _toast(localizations.editorNoLink);
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _toast('${e}');
    }
  }

  static bool _isUrlBoundary(int c) =>
      c == 32 || c == 9 || c == 10 || c == 13 || c == 34 || c == 39 ||
      c == 40 || c == 41 || c == 60 || c == 62 || c == 91 || c == 93 ||
      c == 123 || c == 125 || c == 0x3000;

  /// 按文件内容猜缩进（VS 的 Detect Indentation）。
  void _detectIndent() {
    final text = _controller?.text ?? '';
    if (text.isEmpty) return;
    final (useTabs, size) = guessIndent(text);
    // 缩进是全局偏好（跟着 Tab 键走），不是某份文档的属性。
    unawaited(TextEditorPrefsStore.update(
        TextEditorPrefsStore.notifier.value.copyWith(useTabs: useTabs, tabSize: size)));
    if (!mounted) return;
    setState(() {});
    // 生成的参数顺序 = arb 里占位符出现顺序（{kind} 在前），别调反。
    _toast(localizations.editorIndentDetected(useTabs ? 'Tab' : 'Space', size));
  }

  /// 光标处的「词」范围；不在词上时退化成光标所在的一个字符。
  /// 名称是否像个标识符。
  ///
  /// `_wordRangeAt` 在空白/标点上会返回那一个字符，直接拿去用会出两种事：
  /// 「转到定义」去搜一个空格；「重命名」预填一个空格，确认后全文件的空格都被换成新名字。
  static bool _isSymbolName(String name) {
    if (name.isEmpty) return false;
    final first = name.codeUnitAt(0);
    final okFirst = (first >= 0x41 && first <= 0x5a) ||
        (first >= 0x61 && first <= 0x7a) ||
        first == 0x5f ||
        first == 0x24 ||
        first > 0x7f;
    if (!okFirst) return false;
    for (var i = 1; i < name.length; i++) {
      final c = name.codeUnitAt(i);
      final ok = (c >= 0x30 && c <= 0x39) ||
          (c >= 0x41 && c <= 0x5a) ||
          (c >= 0x61 && c <= 0x7a) ||
          c == 0x5f ||
          c == 0x24 ||
          c > 0x7f;
      if (!ok) return false;
    }
    return true;
  }

  static ({int start, int end}) _wordRangeAt(String text, int offset) {
    bool isWord(int c) =>
        (c >= 0x30 && c <= 0x39) ||
        (c >= 0x41 && c <= 0x5a) ||
        (c >= 0x61 && c <= 0x7a) ||
        c == 0x5f ||
        c == 0x24 ||
        c > 0x7f;
    var s = offset.clamp(0, text.length);
    var e = s;
    while (s > 0 && isWord(text.codeUnitAt(s - 1))) {
      s--;
    }
    while (e < text.length && isWord(text.codeUnitAt(e))) {
      e++;
    }
    if (s == e && e < text.length) e++;
    return (start: s, end: e);
  }

  static String _titleCase(String s) {
    final buf = StringBuffer();
    var inWord = false;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      final lower = ch.toLowerCase();
      final upper = ch.toUpperCase();
      final isLetter = upper != lower;
      buf.write(isLetter && !inWord ? upper : lower);
      inWord = isLetter || RegExp(r'\d').hasMatch(ch);
    }
    return buf.toString();
  }

  /// 行注释前缀（自定义语法用显式族；其余按语言族查表）。
  String? _lineCommentToken() {
    final f = _lang.family;
    if (f != null) return familyLineComment(f);
    return lineCommentOf(key: _lang.key, label: _lang.label);
  }

  /// 块注释定界符（自定义语法用显式族；其余按语言族查表）。
  (String, String)? get _blockComment {
    final f = _lang.family;
    if (f != null) return familyBlockComment(f);
    return blockCommentOf(key: _lang.key, label: _lang.label);
  }

  void _toggleComment() {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final sel = controller.selection;
    final start = sel.isValid ? sel.start : 0;
    final end = sel.isValid ? sel.end : 0;
    final lineStart = text.lastIndexOf('\n', start - 1) + 1;
    final nlAfterEnd = text.indexOf('\n', end);
    final lineEnd = nlAfterEnd < 0 ? text.length : nlAfterEnd;
    final block = text.substring(lineStart, lineEnd);
    final lines = block.split('\n');

    final token = _lineCommentToken();
    final blockMark = _blockComment;
    if (token == null && blockMark == null) {
      _toast(localizations.editorCommentUnsupported);
      return;
    }

    String result;
    if (blockMark != null && token == null) {
      final open = blockMark.$1;
      final close = blockMark.$2;
      final allWrapped = lines.every((l) =>
          l.trim().isEmpty ||
          (l.trimLeft().startsWith(open) && l.trimRight().endsWith(close)));
      result = lines
          .map((l) {
            if (l.trim().isEmpty) return l;
            final indent = l.substring(0, l.length - l.trimLeft().length);
            final body = l.trim();
            if (allWrapped) {
              return indent +
                  body.replaceFirst(open, '').replaceFirst(RegExp(r'\s*' + RegExp.escape(close) + r'$'), '');
            }
            return '$indent$open $body $close';
          })
          .join('\n');
    } else {
      final prefix = '$token ';
      final nonEmpty = lines.where((l) => l.trim().isNotEmpty).toList();
      final allCommented = nonEmpty.isNotEmpty && nonEmpty.every((l) => l.trimLeft().startsWith(token!));
      result = lines
          .map((l) {
            if (l.trim().isEmpty) return l;
            if (allCommented) {
              // 只在行首缩进之后找 token：`var url = "http://x";` 里也有 `//`，
              // 直接 indexOf 会把字符串里的那段当成注释删掉。
              final indentLen = l.length - l.trimLeft().length;
              var idx = l.indexOf(token!, indentLen);
              if (idx < 0) idx = l.indexOf(token!);
              var rest = l.substring(idx + token.length);
              if (rest.startsWith(' ')) rest = rest.substring(1);
              return l.substring(0, idx) + rest;
            }
            final indent = l.substring(0, l.length - l.trimLeft().length);
            return '$indent$prefix${l.trimLeft()}';
          })
          .join('\n');
    }

    controller.text = text.replaceRange(lineStart, lineEnd, result);
    controller.selection = TextSelection(baseOffset: lineStart, extentOffset: lineStart + result.length);
  }

  // ---------- 打开 / 保存 ----------

  Future<void> _openFile() async {
    String? path;
    try {
      final picked = await FilePicker.pickFile(type: FileType.any);
      path = picked?.path;
    } catch (_) {
      final picked = await FilePicker.pickFile();
      path = picked?.path;
    }
    if (path == null) return;
    await _openPath(path);
  }

  /// 按路径打开文件（「打开文件」与「工作区跳转」共用这一条路径）：
  /// 媒体 / 压缩包 / 二进制走预览，文本走带容错解码，超大文件先问一句。
  Future<void> _openPath(String path) async {
    // 媒体 / 压缩包 / 未知二进制：当文本读只会得到乱码（甚至卡死），直接进预览。
    // HTML 与文本类仍然进编辑器——那些是要改的。
    final kind = filePreviewKindOf(path);
    if (kind == FilePreviewKind.media ||
        kind == FilePreviewKind.archive ||
        kind == FilePreviewKind.binary) {
      if (!mounted) return;
      await FilePreviewPage.show(context, File(path));
      return;
    }

    // 同一路径已经开着就切过去。再开一份的话，两个标签各自编辑同一个文件，
    // 谁后保存谁生效，很容易把另一边的改动覆盖掉。
    for (final d in _docs.docs) {
      if (d.path == path) {
        _activate(d);
        return;
      }
    }

    try {
      // 不能直接用 readAsString：它按 UTF-8 **严格**解码，国内很常见的 GBK 文本
      // （.txt / .properties / 老项目源码）会直接抛异常，文件根本打不开 ——
      // 用户连「重新以某编码加载」的机会都没有。
      // 这里走带容错 + GBK 探测的解码，UTF-16/32 按 BOM 认。
      final file = File(path);
      // 超大文件先问一句：整份读进 controller 很卡（流畅模式只是关掉高亮与折叠，
      // 文本仍然全量载入、全量做行索引）。
      const bigFileBytes = 8 * 1024 * 1024;
      final size = await file.length();
      if (size > bigFileBytes && !_bigFileConfirmed.contains(path)) {
        if (!mounted) return;
        final mb = (size / (1024 * 1024)).toStringAsFixed(1);
        // 除了「照样打开」，还给一个「只读预览」：几 MB 的日志/导出文件多半只是看一眼，
        // 走查看器（截断 + 搜索）比整份塞进编辑器快得多，也不会误改。
        final pick = await showDialog<int>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: Text(localizations.editorBigFileWarn(mb)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 0), child: Text(localizations.cancel)),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 2),
                  child: Text(localizations.editorOpenReadOnly)),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, 1), child: Text(localizations.confirm)),
            ],
          ),
        );
        if (!mounted) return;
        if (pick == 2) {
          final name = path.split(Platform.pathSeparator).last;
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TextViewerPage(file: file, title: name)),
          );
          return;
        }
        if (pick != 1) return;
        // 同一个文件在同一会话里问过一次就够了（从查看器「丢进编辑器」也会回到这里）。
        _bigFileConfirmed.add(path);
      }
      final bytes = await file.readAsBytes();
      final (content, detected) = await _decodeForOpen(bytes);
      // 编码记到这份文档上（同时也更新全局偏好，作为下次新建的默认）——
      // 否则「打开 GBK 文件 → 改一个字 → 保存」会把它悄悄写成 UTF-8。
      final name = path.split(Platform.pathSeparator).last;
      final sniffed = _detectLanguage(path) == null ? _sniffLanguage(content) : null;
      final doc = _docs.create(
        name: name,
        text: content,
        path: path,
        // 扩展名给不出语言时按内容嗅探（.txt 里装 JSON 这类）。
        langLabel: _detectLanguage(path) ?? sniffed ?? 'Plain Text',
      );
      doc.langSniffed = sniffed != null;
      doc.newline = content.contains('\r\n') ? '\r\n' : (content.contains('\r') ? '\r' : '\n');
      if (detected != null) {
        doc.encodingName = detected.name;
        unawaited(TextEditorPrefsStore.update(_prefs.copyWith(encodingName: detected.name)));
      }
      doc.diskBaseline = content;
      // 项目里的 .editorconfig 优先于编辑器的全局偏好（VS / IDEA 同款行为）。
      final cfg = await EditorConfig.loadFor(path);
      if (!mounted) return;
      if (cfg != null && !cfg.isEmpty) {
        doc.editorConfig = cfg;
        final nl = cfg.newlineChars;
        if (nl != null) doc.newline = nl;
      }
      _activate(doc);
      _rememberRecentFile(path);
      final pageLimit =
          _prefs.autoPageSize > 0 ? _prefs.autoPageSize : _kSmoothThreshold;
      if (content.length > pageLimit && !_smooth) {
        setState(() => _smooth = true);
        _smoothAuto = true;
        _toast(localizations.editorSmoothAutoEnabled);
      }
    } catch (e) {
      logger.w('Failed to open file: ', error: e);
      _toast('${localizations.fail}: $e');
    }
  }

  /// 按文件后缀粗略命中语言；命中失败返回 null。
  /// 扩展名 → re_highlight 的语言 key。
  ///
  /// 原来只映射了 22 种扩展名，`.kt` / `.cs` / `.cpp` / `.rs` / `.php` / `.rb` / `.swift`
  /// 这些常见源码打开后全是纯文本（无高亮、无补全）—— 而编辑器本身支持 190 多种语言。
  /// 这里按内核的语言 key 建表，找不到就退回纯文本（不会比原来更差）。
  /// INI：第一段非空内容就是 `[section]`。普通代码不会长这样，误判风险很低。
  static bool _looksLikeIni(String head) {
    for (final line in head.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith(';') || t.startsWith('#')) continue;
      return RegExp(r'^\[[^\]\s]+\]$').hasMatch(t);
    }
    return false;
  }

  /// YAML：连续多行 `key: value`，且没有别的东西掺杂。
  /// 判据取保守一侧 —— 宁可认不出，也不要把 shell / 代码认成 YAML。
  static final RegExp _yamlKvRe = RegExp(r'^[A-Za-z_][\w.\-]*\s*:\s*(\S.*)?$');
  static bool _looksLikeYaml(String head) {
    var kv = 0;
    var others = 0;
    for (final line in head.split('\n')) {
      var t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      // 列表项算「中性」：YAML 里常见，Markdown 里也常见，不足以单独判成 YAML。
      if (t == '-' || t.startsWith('- ')) continue;
      if (_yamlKvRe.hasMatch(t)) {
        kv++;
        continue;
      }
      others++;
    }
    // 至少两行 key: value、且没有一行是别的东西（代码/命令/散文）。
    return kv >= 2 && others == 0;
  }

  static const Map<String, String> _extToLangKey = {
    'c': 'c',
    'h': 'c',
    'cpp': 'cpp',
    'cc': 'cpp',
    'cxx': 'cpp',
    'hpp': 'cpp',
    'hxx': 'cpp',
    'cs': 'csharp',
    'java': 'java',
    'kt': 'kotlin',
    'kts': 'kotlin',
    'scala': 'scala',
    'groovy': 'groovy',
    'gradle': 'groovy',
    'go': 'go',
    'rs': 'rust',
    'rb': 'ruby',
    'php': 'php',
    'swift': 'swift',
    'm': 'objectivec',
    'mm': 'objectivec',
    'pl': 'perl',
    'pm': 'perl',
    'lua': 'lua',
    'r': 'r',
    'py': 'python',
    'pyw': 'python',
    'js': 'javascript',
    'mjs': 'javascript',
    'cjs': 'javascript',
    'jsx': 'javascript',
    'ts': 'typescript',
    'tsx': 'typescript',
    'dart': 'dart',
    'html': 'xml',
    'htm': 'xml',
    'xml': 'xml',
    'svg': 'xml',
    'vue': 'xml',
    'xaml': 'xml',
    'css': 'css',
    'scss': 'scss',
    'less': 'less',
    'json': 'json',
    'jsonc': 'json',
    'yaml': 'yaml',
    'yml': 'yaml',
    'toml': 'ini',
    'ini': 'ini',
    'cfg': 'ini',
    'properties': 'properties',
    'md': 'markdown',
    'markdown': 'markdown',
    'sql': 'sql',
    'sh': 'bash',
    'bash': 'bash',
    'zsh': 'bash',
    'ps1': 'powershell',
    'bat': 'dos',
    'cmd': 'dos',
    'asm': 'x86asm',
    's': 'x86asm',
    'proto': 'protobuf',
    'graphql': 'graphql',
    'gql': 'graphql',
    'tex': 'latex',
    'v': 'verilog',
    'vhd': 'vhdl',
    'vhdl': 'vhdl',
    'dockerfile': 'dockerfile',
    'makefile': 'makefile',
    'cmake': 'cmake',
    'nginx': 'nginx',
    'conf': 'nginx',
    'diff': 'diff',
    'patch': 'diff',
    // 第二批：hljs 里有的其它常用语言（内核没有对应 key 时会退回纯文本，不会更差）。
    'clj': 'clojure',
    'cljs': 'clojure',
    'cljc': 'clojure',
    'edn': 'clojure',
    'ex': 'elixir',
    'exs': 'elixir',
    'erl': 'erlang',
    'hrl': 'erlang',
    'hs': 'haskell',
    'lhs': 'haskell',
    'jl': 'julia',
    'nim': 'nim',
    'nix': 'nix',
    'ml': 'ocaml',
    'mli': 'ocaml',
    'purs': 'purescript',
    'tcl': 'tcl',
    'awk': 'awk',
    'coffee': 'coffeescript',
    'sass': 'sass',
    'styl': 'stylus',
    'hbs': 'handlebars',
    'mustache': 'handlebars',
    'pug': 'pug',
    'jade': 'pug',
    'fs': 'fsharp',
    'fsx': 'fsharp',
    'fsi': 'fsharp',
    'vb': 'vbnet',
    'vbs': 'vbscript',
    'cshtml': 'cshtml',
    'razor': 'cshtml',
    'elm': 'elm',
    'hx': 'haxe',
    'cr': 'crystal',
    'tf': 'hcl',
    'tfvars': 'hcl',
    'matlab': 'matlab',
    'mdx': 'markdown',
    'svelte': 'xml',
    'astro': 'xml',
    'http': '',
    'rest': '',
    // 第三批：数据/配置类与少数语言。内核没有对应 key 时照样退回纯文本，不会更差。
    'json5': 'json',
    'jsonl': 'json',
    'ndjson': 'json',
    'mk': 'makefile',
    'qml': 'xml',
    'prisma': 'prisma',
    'zig': 'zig',
    'sol': 'solidity',
    'pas': 'delphi',
    'dpr': 'delphi',
    'd': 'd',
    'raku': 'perl',
    'p6': 'perl',
    'lisp': 'lisp',
    'el': 'lisp',
    'scm': 'scheme',
    'ss': 'scheme',
    'editorconfig': 'ini',
    'reg': 'ini',
    'desktop': 'ini',
    'service': 'ini',
    'srt': 'plaintext',
    'vtt': 'plaintext',
  };

  String? _detectLanguage(String path) {
    final fileName = path.split(Platform.pathSeparator).last.toLowerCase();
    // 这几类文件名本身没有扩展名。
    if (fileName == 'dockerfile' || fileName.startsWith('dockerfile.')) {
      return _labelOfLangKey('dockerfile');
    }
    if (fileName == 'makefile' || fileName.startsWith('makefile.')) {
      return _labelOfLangKey('makefile');
    }
    if (fileName == 'cmakelists.txt') return _labelOfLangKey('cmake');
    // .env / .env.local / .env.production：key=value，按 ini 给个高亮。
    if (fileName == '.env' || fileName.startsWith('.env.')) return _labelOfLangKey('ini');
    if (fileName == '.editorconfig') return _labelOfLangKey('ini');
    final dot = fileName.lastIndexOf('.');
    final ext = dot < 0 ? '' : fileName.substring(dot + 1);
    // http / rest 是编辑器自己的「HTTP」类（不是 re_highlight 语言）。
    if (ext == 'http' || ext == 'rest') return 'HTTP';
    final key = _extToLangKey[ext];
    if (key == null || key.isEmpty) return null;
    return _labelOfLangKey(key);
  }

  /// 把文件字节解成文本：BOM 认 UTF-16/32，否则 UTF-8 容错解 + 中文样本 GBK 兜底。
  /// 打开文件与「从磁盘重新读取」共用这一套 —— 后者原来直接 readAsString()
  /// （严格 UTF-8），GBK 文件点「重新读取」永远失败。
  Future<(String, EditorEncoding?)> _decodeForOpen(List<int> bytes, {String? prefer}) async {
    var detected = _bomEncodingOf(bytes);
    final String content;
    // 无 BOM 时先试「这份文档记住的编码」（重新读取时用），解出来没有替换字符才认。
    if (detected == null && prefer != null && prefer.isNotEmpty && prefer != 'UTF-8') {
      final preferred = kEncodings.where((e) => e.name == prefer).toList();
      if (preferred.isNotEmpty) {
        try {
          final decoded = await preferred.first.decode(bytes);
          if (!decoded.contains('\uFFFD')) detected = preferred.first;
        } catch (_) {
          // 解不出就按 UTF-8 处理
        }
      }
    }
    if (detected != null) {
      content = await detected.decode(bytes);
    } else {
      // 无 BOM：先按 UTF-8 容错解；出现大量 U+FFFD 再试 GBK
      // （与抓包侧 decodeBytesToText 同一套判据）。
      final utf8Text = utf8.decode(bytes, allowMalformed: true);
      // 只拿前 64KB 做「是不是 GBK」的判断：大文件整份解两次太贵，
      // 而判定只需要一段有中文的样本。
      const probeLimit = 64 * 1024;
      final sample = bytes.length > probeLimit
          ? utf8.decode(bytes.sublist(0, probeLimit), allowMalformed: true)
          : utf8Text;
      final bad = '\uFFFD'.allMatches(sample).length;
      String? gbkText;
      if (bad >= 3 && bad * 100 > sample.length) {
        for (final e in kEncodings) {
          if (e.name != 'GBK') continue;
          try {
            final decoded = await e.decode(bytes);
            if ('\uFFFD'.allMatches(decoded).length * 2 < bad) {
              gbkText = decoded;
              detected = e;
            }
          } catch (_) {
            // 解不出就按 UTF-8 处理
          }
          break;
        }
      }
      content = gbkText ?? utf8Text;
    }
    return (content, detected);
  }

  /// 扩展名不可靠时的兜底：按内容开头判断（`xxx.txt` 里装的其实是 JSON 很常见）。
  ///
  /// 只做「高置信度」的几种，拿不准就返回 null（退回纯文本，宁可不高亮也不乱高亮）。
  String? _sniffLanguage(String content) {
    final head = content.length > 400 ? content.substring(0, 400) : content;
    final t = head.trimLeft();
    if (t.isEmpty) return null;
    // Markdown 的几个高置信度特征：`# 标题`、`- [ ]` 任务列表、`| a | b |` 表格。
    // 命中任何一个就不该被判成 XML —— 文档里夹 `<div>` 很常见。
    final lines = head.split('\n');
    final firstLine = lines.isEmpty ? '' : lines.first.trim();
    final mdHeading = firstLine.startsWith('# ') || firstLine.startsWith('## ');
    final mdTask = firstLine.startsWith('- [ ]') || firstLine.startsWith('- [x]');
    final mdTable = lines.length >= 2 &&
        firstLine.startsWith('|') &&
        RegExp(r'^\|[\s:|-]+\|?$').hasMatch(lines[1].trim());
    if ((mdHeading || mdTask || mdTable) && content.contains('\n')) {
      return _labelOfLangKey('markdown');
    }
    if (t.startsWith('<!DOCTYPE') || t.startsWith('<!doctype') || t.startsWith('<html')) {
      return _labelOfLangKey('xml');
    }
    if (t.startsWith('<?xml')) return _labelOfLangKey('xml');
    if (t.startsWith('<?php')) return _labelOfLangKey('php');
    if (t.startsWith('<svg')) return _labelOfLangKey('xml');
    if (t.startsWith('{') || t.startsWith('[')) {
      // 大文件不嗅探：整份 jsonDecode 太贵，只解析开头又必然失败（不完整）。
      if (content.length > 200000) return null;
      // 必须是能解析的 JSON，避免把普通大括号块认成 JSON。
      try {
        jsonDecode(content);
        return _labelOfLangKey('json');
      } catch (_) {
        return null;
      }
    }
    if (_looksLikeIni(head)) return _labelOfLangKey('ini');
    if (_looksLikeYaml(head)) return _labelOfLangKey('yaml');
    if (t.startsWith('---')) return _labelOfLangKey('yaml');
    if (t.startsWith('#!')) {
      // 解析 `#!/usr/bin/env node` / `#!/usr/bin/python3` 这类，只认解释器本身。
      // 原来用 contains('node')，路径里带 node_modules 的脚本会被误判。
      final firstLine = t.split('\n').first;
      final m = RegExp(r'^#!\s*(\S+)(?:\s+(.*))?$').firstMatch(firstLine);
      var cmd = (m?.group(1) ?? '').split('/').last;
      final arg = (m?.group(2) ?? '').trim();
      if (cmd == 'env' && arg.isNotEmpty) {
        cmd = arg.split(RegExp(r'\s+')).firstWhere((e) => !e.startsWith('-'), orElse: () => '');
      }
      if (cmd.startsWith('python') || cmd.startsWith('pypy')) return _labelOfLangKey('python');
      if (cmd == 'node' || cmd == 'nodejs' || cmd == 'deno' || cmd == 'bun') {
        return _labelOfLangKey('javascript');
      }
      if (cmd == 'ruby') return _labelOfLangKey('ruby');
      if (cmd == 'perl') return _labelOfLangKey('perl');
      if (cmd == 'php') return _labelOfLangKey('php');
      if (cmd == 'lua') return _labelOfLangKey('lua');
      return _labelOfLangKey('bash');
    }
    return null;
  }

  /// 按 re_highlight 的 key 找语言 label；内核没有这门语言时返回 null（退回纯文本）。
  String? _labelOfLangKey(String key) {
    for (final l in _langs) {
      if (l.key == key) return l.label;
    }
    return null;
  }

  Future<void> _download() async {
    final controller = _controller;
    if (controller == null) return;
    var text = controller.text;
    if (text.isEmpty) return;

    // 编辑器内部永远是 \n，写出时按设置替换
    text = _applyNewline(text, _newlineCharsOf(_doc));

    final fileName = _doc?.name ?? 'text.txt';

    if (Platforms.isMobile()) {
      final file = XFile.fromData(utf8.encode(text), mimeType: 'text/plain');
      RenderBox? box;
      if (await Platforms.isIpad() && mounted) {
        box = context.findRenderObject() as RenderBox?;
      }
      await SharePlus.instance.share(
          ShareParams(files: [file], fileNameOverrides: [fileName], sharePositionOrigin: box?.paintBounds));
      if (mounted) setState(() => _dirty = false);
      return;
    }

    final saved = await FilePicker.saveFile(fileName: fileName, bytes: utf8.encode(text));
    if (saved == null) return;
    if (mounted) {
      setState(() => _dirty = false);
      _toast(localizations.saveSuccess);
    }
  }

  /// 重命名当前文件（改的是磁盘上的文件名，不只是标签）。
  ///
  /// 编辑器里原来只能「另存为」——想给文件改个名字得先退出到文件管理器，
  /// 改完再打开一次，很不顺。
  Future<void> _renameFile() async {
    final doc = _doc;
    final path = doc?.path;
    if (doc == null || path == null || path.isEmpty) {
      _toast(localizations.editorNeedFile);
      return;
    }
    final ctrl = TextEditingController(text: doc.name);
    ctrl.selection =
        TextSelection(baseOffset: 0, extentOffset: doc.name.length);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.editorRenameFile),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: localizations.rename),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(localizations.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(localizations.confirm)),
        ],
      ),
    );
    ctrl.dispose();
    final trimmed = (name ?? '').trim();
    if (!mounted || trimmed.isEmpty || trimmed == doc.name) return;
    if (trimmed.contains('/') || trimmed.contains(Platform.pathSeparator)) {
      _toast(localizations.editorRenameInvalid);
      return;
    }
    final sep = Platform.pathSeparator;
    final target = '${File(path).parent.path}$sep$trimmed';
    if (File(target).existsSync()) {
      _toast(localizations.editorFileExists);
      return;
    }
    try {
      await File(path).rename(target);
      if (!mounted) return;
      doc.path = target;
      doc.name = trimmed;
      // 改名后 mtime/监听都要重新挂到新路径上，否则 3 秒后会弹「文件被外部修改」。
      _lastFileMtime = null;
      _restartFileWatch();
      setState(() {});
      _toast(localizations.editorRenamed);
    } catch (e) {
      if (!mounted) return;
      _toast('$e');
    }
  }

  /// 复制当前文件的完整路径（贴到终端/聊天里最常用的那种）。
  Future<void> _copyFilePath() async {
    final path = _doc?.path;
    if (path == null || path.isEmpty) {
      _toast(localizations.editorNeedFile);
      return;
    }
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    _toast(localizations.copied);
  }

  /// 在系统文件管理器里定位这个文件（桌面端才有）。
  Future<void> _revealInFolder() async {
    final path = _doc?.path;
    if (path == null || path.isEmpty) {
      _toast(localizations.editorNeedFile);
      return;
    }
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', ['/select,$path']);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [File(path).parent.path]);
      } else {
        if (!mounted) return;
        _toast(localizations.editorRevealUnsupported);
      }
    } catch (e) {
      if (!mounted) return;
      _toast('$e');
    }
  }

  /// 复制。有选区就复制选区（VS 的 Edit › Copy 就是这个语义）——
  /// 以前不分区选、永远复制整个文件，选中一段去点「复制」拿到全文，很难理解。
  /// 没有选区时退回「复制全部」，手机上这个更常用。
  /// 取「当前生效的文本」+ 它在全文里的起始偏移（有选区取选区，否则整篇）。
  ({String text, int start}) _activeChunk() {
    final controller = _controller;
    if (controller == null) return (text: '', start: 0);
    final all = controller.text;
    final sel = controller.selection;
    if (sel.isValid && !sel.isCollapsed) {
      final len = all.length;
      final a = sel.start.clamp(0, len);
      final b = sel.end.clamp(0, len);
      return a <= b ? (text: all.substring(a, b), start: a) : (text: all.substring(b, a), start: b);
    }
    return (text: all, start: 0);
  }

  /// 把「当前生效文本」（有选区取选区，否则整篇）替换成 [newText]。
  void _replaceActiveChunk(String newText) {
    final c = _controller;
    if (c == null) return;
    final chunk = _activeChunk();
    final all = c.text;
    final start = chunk.start.clamp(0, all.length);
    final end = (chunk.start + chunk.text.length).clamp(0, all.length);
    c.replaceRange(start, end, newText);
  }

  /// 给每一行加引号/前缀后缀，并用分隔符连接。
  ///
  /// 说是「加引号」，实际是「把一列值变成代码里的字面量列表」：
  /// SQL 的 `IN ('a','b')`、JSON 数组、Java/Python 的列表，都靠这一步。
  /// 以前只能手打，或者扔到 Excel 里拼公式。
  Future<void> _quoteLines() async {
    final chunk = _activeChunk();
    if (chunk.text.isEmpty) {
      _toast(localizations.cannotBeEmpty);
      return;
    }
    final lines = chunk.text
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((e) => e.trim().isNotEmpty)
        .map((e) => e.trim())
        .toList();
    if (lines.isEmpty) {
      _toast(localizations.cannotBeEmpty);
      return;
    }
    // 用 controller 而不是 initialValue：下面有「预设 chip」要回填，
    // initialValue 只在第一次 build 生效，点了 chip 输入框不会变。
    final prefixCtl = TextEditingController(text: "'");
    final suffixCtl = TextEditingController(text: "'");
    final sepCtl = TextEditingController(text: ',');
    var prefix = "'";
    var suffix = "'";
    var separator = ',';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.editorQuoteLines),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: prefixCtl,
                    decoration: InputDecoration(
                        labelText: localizations.editorQuotePrefix, isDense: true),
                    onChanged: (v) => prefix = v,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: suffixCtl,
                    decoration: InputDecoration(
                        labelText: localizations.editorQuoteSuffix, isDense: true),
                    onChanged: (v) => suffix = v,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: sepCtl,
                    decoration: InputDecoration(
                        labelText: localizations.editorQuoteSeparator, isDense: true),
                    onChanged: (v) => separator = v,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 6, children: [
                  ActionChip(
                    label: const Text(r"""'a', 'b'""", style: TextStyle(fontSize: 11)),
                    onPressed: () => setDialogState(() {
                      prefix = "'";
                      suffix = "'";
                      separator = ',';
                      prefixCtl.text = prefix;
                      suffixCtl.text = suffix;
                      sepCtl.text = separator;
                    }),
                  ),
                  ActionChip(
                    label: const Text('"a", "b"', style: TextStyle(fontSize: 11)),
                    onPressed: () => setDialogState(() {
                      prefix = '"';
                      suffix = '"';
                      separator = ',';
                      prefixCtl.text = prefix;
                      suffixCtl.text = suffix;
                      sepCtl.text = separator;
                    }),
                  ),
                  ActionChip(
                    label: const Text('a, b', style: TextStyle(fontSize: 11)),
                    onPressed: () => setDialogState(() {
                      prefix = '';
                      suffix = '';
                      separator = ',';
                      prefixCtl.text = prefix;
                      suffixCtl.text = suffix;
                      sepCtl.text = separator;
                    }),
                  ),
                ]),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  localizations.editorNumberingLines(lines.length),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(localizations.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(localizations.confirm)),
        ],
      ),
    );
    prefixCtl.dispose();
    suffixCtl.dispose();
    sepCtl.dispose();
    if (ok != true) return;
    final out = lines.map((e) => '$prefix$e$suffix').join(separator);
    _replaceActiveChunk(out);
  }

  /// 转置光标处相邻的两个字符（VS 的 Ctrl+T）。
  void _transposeChars() {
    final c = _controller;
    if (c == null) return;
    final text = c.text;
    final sel = c.selection;
    if (!sel.isValid) return;
    var i = sel.start;
    if (i >= text.length) i = text.length - 1;
    if (i <= 0) return;
    final a = text.substring(i - 1, i);
    final b = text.substring(i, i + 1);
    c.replaceRange(i - 1, i + 1, '$b$a');
    c.selection = TextSelection.collapsed(offset: (i + 1).clamp(0, text.length));
  }

  /// 给选中的每一行加递增序号（Sublime / Notepad++ 里那种行号生成）。
  ///
  /// 补零位数按「最后一行的号」自动算，所以 1..12 会输出 01..12；
  /// 需要固定宽度（如生成 SQL 的 IN 列表）时手动填位数。
  Future<void> _insertNumbering() async {
    final chunk = _activeChunk();
    if (chunk.text.isEmpty) {
      _toast(localizations.cannotBeEmpty);
      return;
    }
    final lines = chunk.text.replaceAll('\r\n', '\n').split('\n');
    var start = 1;
    var step = 1;
    var digits = 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.editorNumbering),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              keyboardType: TextInputType.number,
              initialValue: '$start',
              decoration: InputDecoration(
                labelText: localizations.editorNumberingStart,
                isDense: true,
              ),
              onChanged: (v) => start = int.tryParse(v.trim()) ?? 1,
            ),
            const SizedBox(height: 8),
            TextFormField(
              keyboardType: TextInputType.number,
              initialValue: '$step',
              decoration: InputDecoration(
                labelText: localizations.editorNumberingStep,
                isDense: true,
              ),
              onChanged: (v) => step = int.tryParse(v.trim()) ?? 1,
            ),
            const SizedBox(height: 8),
            TextFormField(
              keyboardType: TextInputType.number,
              initialValue: '$digits',
              decoration: InputDecoration(
                labelText: localizations.editorNumberingDigits,
                helperText: localizations.editorNumberingDigitsHint,
                isDense: true,
              ),
              onChanged: (v) => digits = int.tryParse(v.trim()) ?? 0,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                localizations.editorNumberingLines(lines.length),
                style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(localizations.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(localizations.confirm)),
        ],
      ),
    );
    if (ok != true) return;
    final last = start + (lines.length - 1) * step;
    final width = digits > 0 ? digits : '$last'.length;
    final buf = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      final no = '${start + i * step}'.padLeft(width, '0');
      buf.writeln('$no${lines[i].isEmpty ? '' : ' ${lines[i]}'}');
    }
    _replaceActiveChunk(buf.toString().trimRight());
  }

  /// 合并行：把选中的多行压成一行（空行丢弃，行间用一个空格连接）。
  void _joinLines() {
    final chunk = _activeChunk();
    if (chunk.text.isEmpty) {
      _toast(localizations.cannotBeEmpty);
      return;
    }
    final joined = chunk.text
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .join(' ');
    _replaceActiveChunk(joined);
  }

  /// 拆行：把每一行按分隔符拆成多行（默认逗号，生成纵向列表时用）。
  Future<void> _splitLines() async {
    final chunk = _activeChunk();
    if (chunk.text.isEmpty) {
      _toast(localizations.cannotBeEmpty);
      return;
    }
    final ctl = TextEditingController(text: ',');
    String sep = ',';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.editorSplitLines),
        content: TextField(
          controller: ctl,
          decoration: InputDecoration(
            labelText: localizations.editorSplitBy,
            isDense: true,
          ),
          onChanged: (v) => sep = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(localizations.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(localizations.confirm)),
        ],
      ),
    );
    ctl.dispose();
    if (ok != true || sep.isEmpty) return;
    final out = chunk.text
        .replaceAll('\r\n', '\n')
        .split('\n')
        .expand((line) => line.split(sep).map((e) => e.trim()))
        .where((e) => e.isNotEmpty)
        .join('\n');
    _replaceActiveChunk(out);
  }

  /// 选中文本的编解码（Base64 / URL / Hex / HTML 实体）。
  ///
  /// 抓包时最常遇到的四种：Authorization 里的 Base64、查询串里的 %XX、
  /// Hex dump、以及 HTML 响应里被转义的字符。都要切到工具箱去处理太绕。
  Future<void> _showTextCodec() async {
    final chunk = _activeChunk();
    if (chunk.text.isEmpty) {
      _toast(localizations.cannotBeEmpty);
      return;
    }
    final src = chunk.text;
    final ops = <(String, String Function(String))>[
      ('Base64', (v) => base64Encode(utf8.encode(v))),
      ('Base64 →', (v) => _tryDecode(() => utf8.decode(base64.decode(v.trim())))),
      ('URL', (v) => Uri.encodeComponent(v)),
      ('URL →', (v) => _tryDecode(() => Uri.decodeComponent(v))),
      ('Hex', (v) => utf8.encode(v).map((b) => b.toRadixString(16).padLeft(2, '0')).join()),
      ('Hex →', (v) => _tryDecode(() => utf8.decode(_parseHex(v)))),
      ('HTML', (v) => const HtmlEscape().convert(v)),
      ('HTML →', (v) => _htmlUnescape(v)),
    ];
    String result = ops.first.$2(src);
    var current = ops.first.$1;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.62,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
                  child: Row(children: [
                    Expanded(
                      child: Text(localizations.editorTextCodec,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Text(localizations.editorEscapeHint(src.length),
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  ]),
                ),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    children: [
                      for (final op in ops)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(op.$1, style: const TextStyle(fontSize: 12)),
                            selected: current == op.$1,
                            onSelected: (_) => setSheetState(() {
                              current = op.$1;
                              result = op.$2(src);
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 12, thickness: 0.3),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        result,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.35),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: result));
                          if (ctx.mounted) Navigator.pop(ctx, false);
                          _toast(localizations.copied);
                        },
                        child: Text(localizations.copy),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(localizations.editorEscapeDo),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied == true) {
      _replaceActiveChunk(result);
      _toast(localizations.editorEscapeDone);
    }
  }

  /// `dart:convert` 只有 HtmlEscape，没有反向。这里只处理最常见的五个实体
  /// （抓包响应里 99% 就这几个），不做完整 HTML 实体表。
  static String _htmlUnescape(String v) => v
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');

  static String _tryDecode(String Function() fn) {
    try {
      return fn();
    } catch (_) {
      return '[decode failed]';
    }
  }

  static List<int> _parseHex(String v) {
    final clean = v.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final out = <int>[];
    for (var i = 0; i + 1 < clean.length; i += 2) {
      out.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  /// 复制时给每行加行号。
  ///
  /// 贴到工单、聊天、代码评审里说「第 137 行那个判断」时，对方不需要
  /// 自己数——这是移动端编辑器普遍缺、但沟通时最省事的一个小功能。
  Future<void> _copyNumbered() async {
    final chunk = _activeChunk();
    if (chunk.text.isEmpty) {
      _toast(localizations.cannotBeEmpty);
      return;
    }
    final all = _controller?.text ?? '';
    final lineCount = '\n'.allMatches(all.substring(0, chunk.start.clamp(0, all.length))).length;
    final lines = chunk.text.replaceAll('\r\n', '\n').split('\n');
    final width = '${lineCount + lines.length}'.length;
    final buf = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      final no = '${lineCount + i + 1}'.padLeft(width);
      buf.writeln('$no  ${lines[i]}');
    }
    final out = buf.toString();
    await Clipboard.setData(ClipboardData(text: out.trimRight()));
    _rememberClip(out);
    _toast(localizations.copied);
  }

  /// 复制为 Markdown 代码块（带语言标记）：粘到文档/IM 里能直接高亮。
  Future<void> _copyMarkdown() async {
    final chunk = _activeChunk();
    if (chunk.text.isEmpty) {
      _toast(localizations.cannotBeEmpty);
      return;
    }
    final key = _lang.key;
    // 语言标记用 re_highlight 的 key（js/python/...），纯文本留空。
    final fence = (key.isEmpty || key == 'plaintext') ? '' : key;
    final body = chunk.text.replaceAll('\r\n', '\n').trimRight();
    final out = '```$fence\n$body\n```';
    await Clipboard.setData(ClipboardData(text: out));
    _rememberClip(out);
    _toast(localizations.copied);
  }

  /// 把另一个文件的内容插到光标处（VS 的 Insert File As Text）。
  /// 拼接配置片段、把模板搅进当前文件时，比复制粘贴少两次切窗口。
  Future<void> _insertFileText() async {
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
      final content = await readTextFileLenient(File(path));
      if (!mounted) return;
      _insertAtCursor(content.text);
      if (content.truncated) _toast(localizations.diffFileTruncated);
    } catch (e) {
      if (mounted) _toast('${localizations.fail}: $e');
    }
  }

  void _copy() {
    final controller = _controller;
    if (controller == null) return;
    final all = controller.text;
    final selection = controller.selection;
    final String text;
    if (selection.isValid && !selection.isCollapsed) {
      final len = all.length;
      final start = selection.start.clamp(0, len);
      final end = selection.end.clamp(0, len);
      text = start <= end ? all.substring(start, end) : all.substring(end, start);
    } else {
      text = all;
    }
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    _rememberClip(text);
    _toast(localizations.copied);
  }

  void _clear() {
    final controller = _controller;
    if (controller == null || controller.text.isEmpty) return;
    controller.text = '';
  }

  /// 当前语言用哪种格式化器（全部语言都有归属，只是不一定有专属格式化器）。
  /// 当前语法能不能就地预览（HTML / SVG / Markdown 类）。
  bool get _canPreview => canPreviewLanguage(key: _lang.key, label: _lang.label);

  /// 打开预览页（渲染当前文档内容，不执行脚本）。
  void _preview() {
    final doc = _doc;
    if (doc == null) return;
    HtmlPreviewPage.show(
      context,
      content: doc.text,
      language: '${_lang.key} ${doc.langLabel}',
      title: doc.name,
    );
  }

  FormatKind get _formatKind {
    // 没借用任何高亮的自定义语法（纯文本）不做格式化，避免按名字瞎猜。
    if (_lang.custom && _lang.key.isEmpty) return FormatKind.none;
    return formatKindOf(key: _lang.key, label: _lang.label);
  }

  bool get _canFormat => _formatKind != FormatKind.none;

  /// 光标所在行里第一条「能自动修」的问题（VS 的灯泡）。
  ///
  /// 有了它就不用眼睛在下方问题栏里找「我这一行是不是有毛病」——
  /// 光标停在那行，工具栏上就亮一个灯泡，点一下直接修掉。
  LintDiagnostic? get _fixAtCaretLine {
    final report = _lint;
    if (report == null || _caretLine < 0) return null;
    for (final d in report.diagnostics) {
      if (d.line - 1 != _caretLine) continue;
      if (d.replacement == null) continue;
      if (_hiddenSeverities.contains(d.severity)) continue;
      return d;
    }
    return null;
  }

  /// 按当前语言格式化。失败时通过 toast 显示原因，不修改原文。
  ///
  /// 两个体验点：**格式化后光标留在原来那一行**（而不是跳回文件开头），
  /// 以及「内容没变」时明确告知（否则用户会以为是点了没反应）。
  Future<void> _format() => _applyFormat();

  /// [quiet] 为 true 时（保存时格式化）不弹提示：用户要的是「存下去」，
  /// 不是「格式化成功了」这种噪音。
  Future<void> _applyFormat({bool quiet = false, bool selectionOnly = false}) async {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    if (text.trim().isEmpty) return;
    // 全量格式化是同步正则 + 重新拼串，几 MB 会把界面卡住好几秒。
    // 超过这个量级连 isolate 传输都开始肉疼了。
    if (text.length > 5000000) {
      if (!quiet) _toast(localizations.editorTooLargeToFormat);
      return;
    }

    // 只格式化选中部分（VS 的 Format Selection）。
    // 片段单独拿去 JSON/XML 解析必然失败，所以这里只做「按大括号重排缩进」。
    if (selectionOnly) {
      final sel = controller.selection;
      if (!sel.isValid || sel.start == sel.end) {
        // 不能说「当前语言不支持格式化」—— 是没选东西，不是语言的问题。
        if (!quiet) _toast(localizations.editorFormatSelectFirst);
        return;
      }
      final snippet = text.substring(sel.start, sel.end);
      final formatted =
          reindentBraces(snippet, tabSize: _prefs.tabSize, useTabs: _prefs.useTabs);
      if (formatted == snippet) {
        if (!quiet) _toast(localizations.editorFormatNoChange);
        return;
      }
      controller.replaceRange(sel.start, sel.end, formatted);
      if (!quiet) _toast(localizations.editorFormatted);
      return;
    }
    final caret = controller.selection.baseOffset;
    final caretLine = _lineOfOffset(text, caret < 0 ? 0 : caret);

    String? result;
    try {
      if (text.length > 1000000 && _formatKind != FormatKind.js &&
          _formatKind != FormatKind.none) {
        // JSON / XML / CSS / 大括号重排都是纯函数：大文本丢 isolate，界面不卡。
        result = await compute(_formatInIsolate,
            <Object>[_formatKind.index, text, _prefs.tabSize, _prefs.useTabs]);
        if (!mounted) return;
      } else {
      switch (_formatKind) {
        case FormatKind.json:
          result = JSON.pretty(text);
        case FormatKind.xml:
          result = XmlDocument.parse(text).toXmlString(pretty: true, indent: '  ');
        case FormatKind.css:
          result = CSS.pretty(text);
        case FormatKind.js:
          // JS 美化走内置 JS runtime（平台通道），没法丢 isolate：大文件直接劝退。
          if (text.length > 500000) {
            if (!quiet) _toast(localizations.editorTooLargeToFormat);
            return;
          }
          result = await JsDeobfuscator.beautify(text);
        case FormatKind.brace:
          // 通用大括号缩进重排：只改每行前导空白，正文逐字保留。
          result = reindentBraces(text, tabSize: _prefs.tabSize, useTabs: _prefs.useTabs);
        case FormatKind.none:
          if (!quiet) _toast(localizations.editorFormatUnsupported);
          return;
      }
      }
    } catch (e) {
      if (!quiet) _toast('${localizations.fail}: $e');
      return;
    }
    if (!mounted || result == null) return;
    if (result == text) {
      if (!quiet) _toast(localizations.editorFormatNoChange);
      return;
    }
    controller.text = result;
    // 尽量把光标放回原来那一行的行首（行数变少时落到末行）。
    final keepLine = caretLine.clamp(0, '\n'.allMatches(result).length);
    controller.selection = TextSelection.collapsed(offset: _offsetOfLine(result, keepLine));
    if (!quiet) _toast(localizations.editorFormatted);
  }

  /// 偏移量 → 行号（0 基）。
  static int _lineOfOffset(String text, int offset) {
    final limit = offset < 0 ? 0 : (offset > text.length ? text.length : offset);
    var line = 0;
    for (var i = 0; i < limit; i++) {
      if (text.codeUnitAt(i) == 10) line++;
    }
    return line;
  }

  /// 行号（0 基）→ 行首偏移量。
  static int _offsetOfLine(String text, int line) {
    if (line <= 0) return 0;
    var seen = 0;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) {
        seen++;
        if (seen == line) return i + 1;
      }
    }
    return text.length;
  }

  /// 压缩当前文档（保守压缩：删注释 / 去缩进 / 合并多余空白）。
  /// 大文本上的全量同步处理（压缩 / 符号表）会卡住界面，超过阈值直接提示跳过。
  bool _tooLargeForSync(String text, {int limit = 1000000}) {
    if (text.length <= limit) return false;
    _toast(localizations.editorTooLargeToProcess);
    return true;
  }

  Future<void> _minify() async {
    final controller = _controller;
    final doc = _doc;
    if (controller == null || doc == null) return;
    final text = controller.text;
    if (text.trim().isEmpty) return;
    // 压缩是纯函数，超过 100 万字符就丢给 isolate；再大的连 isolate 都搬不动了。
    if (_tooLargeForSync(text, limit: 5000000)) return;
    final String? result = text.length > 1000000
        ? await compute(_minifyInIsolate, <String>[doc.langLabel, text])
        : CodeMinifier.minify(doc.langLabel, text);
    if (!mounted) return;
    // isolate 算的这段时间里文档可能已被关闭（controller 已 dispose，写回会抛异常）。
    if (!_docs.docs.any((d) => identical(d, doc))) return;
    if (result == null) {
      _toast(localizations.editorMinifyUnsupported);
      return;
    }
    if (result == text) {
      // 静默返回会像「按钮坏了」。
      _toast(localizations.editorMinifyNoChange);
      return;
    }
    controller.text = result;
    _toast(localizations.editorMinified('${text.length}', '${result.length}'));
  }

  /// 激进压缩：走内置 JS 编译器前端（DCE + 局部变量重命名）。仅 JS/TS；
  /// 语法超出子集时不给结果，提示用户，绝不猜测。
  Future<void> _minifyAggressive() async {
    final controller = _controller;
    final doc = _doc;
    if (controller == null || doc == null) return;
    final label = doc.langLabel;
    if (label != 'JavaScript' && label != 'TypeScript') {
      _toast(localizations.editorMinifyUnsupported);
      return;
    }
    final text = controller.text;
    if (text.trim().isEmpty) return;
    if (_tooLargeForSync(text, limit: 5000000)) return;
    final String? result = text.length > 1000000
        ? await compute(_compilerMinifyInIsolate, text)
        : JsCompiler.minify(text);
    if (!mounted) return;
    if (!_docs.docs.any((d) => identical(d, doc))) return;
    if (result == null) {
      _toast(localizations.editorMinifyAggressiveUnsupported);
      return;
    }
    if (result == text) {
      _toast(localizations.editorMinifyNoChange);
      return;
    }
    controller.text = result;
    _toast(localizations.editorMinified('${text.length}', '${result.length}'));
  }

  void _toast(String msg) {
    if (!mounted) return;
    FlutterToastr.show(msg, context, duration: 3);
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final isNewWindows = widget.windowId != null && Platform.isWindows;
    final doc = _doc;
    // 手机上键盘一弹就吃掉 290dp：这时固定的横条（文档标签、面包屑、问题列表）
    // 会把代码区压到只剩三四行。打字时只留真正要看的东西。
    final media = MediaQuery.of(context);
    final typing = media.viewInsets.bottom > 0;
    // 横屏手机（高度 400 上下）即使没键盘也很挤：两行工具栏 + 几条横条之后
    // 代码区就没多少了，所以横屏也按「紧凑」处理。
    final shortScreen = media.size.height < 480;
    final compact = typing || shortScreen;
    final title = doc == null ? localizations.textEditor : '${doc.name}${_dirty ? ' •' : ''}';
    // 智能预测：文档词 + 语言关键字 + 按光标上下文 / 代码格式推断的候选。
    // 幂等赋值，不触发重建。
    if (doc != null) {
      final smart = SmartCompletion.enabled.value && !_smooth;
      final builtinWords = CodeKeywords.forLanguage(doc.langLabel, _lang.key);
      doc.controller.extraSuggestions = smart
          ? (_lang.customWords.isEmpty
              ? builtinWords
              : <String>[..._lang.customWords, ...builtinWords])
          : const <String>[];
      doc.controller.contextSuggestionProvider = smart
          ? (ctx) {
              final words = SmartSuggestions.suggest(
                language: doc.langLabel,
                key: _lang.key,
                documentText: ctx.documentText,
                linePrefix: ctx.linePrefix,
                prefix: ctx.prefix,
                cursorOffset: ctx.cursorOffset,
              );
              if (words.isEmpty) return words;
              // 只统计「无输入联想」的曝光——普通前缀补全每次都弹，记它没有意义。
              if (ctx.prefix.isEmpty) SuggestionStats.recordShown(doc.langLabel, words);
              // 按这个人平时真的会用的词重排（稳定排序，没学过的保持原位置）。
              return SuggestionStats.rank(doc.langLabel, words);
            }
          : null;
      // 候选右侧那行小字（关键字 / 内置）。按语言缓存：候选表有两百多个词，
      // 每次 build 都现算分类没有意义。
      doc.controller.suggestionDetails =
          smart ? _suggestionDetailsOf(doc.langLabel, _lang.key, builtinWords) : const <String, String>{};
      doc.controller.onSuggestionAccepted =
          smart ? (accepted, _) => SuggestionStats.recordAccepted(doc.langLabel, accepted) : null;
    }

    return PopScope(
      // 有没写回文件的修改时也拦一下：手机上按返回是最容易误触的退出方式。
      // 任一文档有未保存修改都要拦（原来只看当前这份，切走的那些就被忽略了）。
      canPop: !(_docs.docs.any((d) => d.dirty) ||
          (_retainMode == _RetainMode.ask && _hasUnretained)),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _scheduleExitCleanup(null);
        } else {
          unawaited(_confirmExit());
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        // 抽屉边缘拖拽会抢走编辑区的横向滚动（手机上误触很明显），
        // 文档列表改从工具栏的菜单按钮进。
        drawerEdgeDragWidth: 0,
        drawer: _docDrawer(),
        onDrawerChanged: (open) {
          if (!open) {
            // 抽屉一关，里面的输入框就销毁了；搜索词必须一起清掉，
            // 否则下次打开是「列表被旧查询过滤着、搜索框却是空的」——看着像文档丢了。
            if (_docQuery.isNotEmpty) setState(() => _docQuery = '');
            return;
          }
          // 抽屉刚建出来，等一帧再滚（控制器此时还没 attach）。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scrollToActiveDoc();
          });
        },
        appBar: isNewWindows
            ? null
            : PreferredSize(
                preferredSize: Platforms.isDesktop() ? const Size.fromHeight(23) : const Size.fromHeight(36),
                child: AppBar(
                    title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w300)),
                    centerTitle: true),
              ),
        body: Column(children: [
          if (_zen)
            _zenBar()
          else ...[
            _toolbar(),
            if (!compact) _docTabs(),
            const Divider(height: 1, thickness: 0.3),
            if (!compact) _breadcrumb(),
          ],
          _multiSelBar(),
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                child: Listener(
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerUp,
                  // 按语言换 key：切语法时整块重建，避免内核残留绘制状态。
                  child: KeyedSubtree(
                    key: ValueKey('editor-${doc?.langLabel}'),
                    child: _textView(),
                  ),
                ),
              ),
              // 右侧「问题分布条」：VS 滚动条旁那排小色块，一眼看出错误集中在文件哪一段。
              if (doc != null) ..._issueRuler(doc),
            ]),
          ),
          if (!_zen && doc != null && _prefs.magnifier) _magnifierBar(doc),
          // 参数签名提示（VS 打 `(` 后那行签名）：只在对当前语言、且文档里找得到声明时显示。
          if (!_zen && doc != null && _programming)
            _SignatureBar(controller: doc.controller, resolve: _resolveSignature),
          // 问题栏：贴着代码，按文本顺序一行一条（红=报错，黄=警告）
          if (!_zen && doc != null && _lintEnabled && _programming)
            LintIssueBar(
              report: _lint,
              // 打字时只留表头（点一下能进完整面板），别把代码区挤没了。
              maxRows: compact ? 0 : 3,
              chinese: Localizations.localeOf(context).languageCode.startsWith('zh'),
              onJump: _jumpToDiagnostic,
              onFix: _fixDiagnostic,
              onShowAll: () => _openConsole(EditorConsoleTab.problems),
              onFixAll: (_lint?.fixableCount ?? 0) > 0 ? _fixAllDiagnostics : null,
              onPrevIssue: () => _jumpIssue(false),
              onNextIssue: () => _jumpIssue(true),
              muted: _hiddenSeverities,
              onMutedChanged: (next) {
                setState(() {
                  _hiddenSeverities
                    ..clear()
                    ..addAll(next);
                });
                unawaited(_saveHiddenSeverities());
              },
            ),
          if (!_zen && _prefs.shortcutBar && !shortScreen) _snippetBar(),
          if (!_zen && _consoleOpen && doc != null)
            EditorConsolePanel(
              report: _lint,
              checking: _lintChecking,
              language: doc.langLabel,
              langKey: _lang.key,
              jsBackend: _jsBackend,
              readDocument: () => doc.text,
              readSelection: _selectedText,
              onJump: _jumpToDiagnostic,
              onFix: _fixDiagnostic,
              onFixAll: (_lint?.fixableCount ?? 0) > 0 ? _fixAllDiagnostics : null,
              onClose: () => setState(() => _consoleOpen = false),
              initialTab: _consoleTab,
              programming: _programming,
              disabledRules: _disabledRules,
              onOpenRules: _openLintRules,
              onInsertText: _insertText,
              hiddenSeverities: _hiddenSeverities,
              state: doc.consoleState,
              initialHeight: _prefs.consoleHeight,
              onHeightChanged: (h) => TextEditorPrefsStore.update(
                  TextEditorPrefsStore.notifier.value.copyWith(consoleHeight: h)),
              breakpoints: _breakpoints,
              onBreakpointsChanged: (set) {
                setState(() {
                  _breakpoints
                    ..clear()
                    ..addAll(set);
                });
                _refreshDecorations();
              },
              onJumpToLine: (line) => _controller?.scrollToLine(line),
            ),
          if (doc != null)
            AnimatedBuilder(
              animation: doc.findController,
              builder: (_, __) => FindPanelView(controller: doc.findController),
            ),
          // 状态栏（学 VS Code）：光标行列、选中字符数、缩进、语言
          if (!_zen && doc != null) _statusBar(doc),
        ]),
      ),
    );
  }

  /// 专注模式的顶部薄条：只留退出。其余一切让位给代码。
  Widget _zenBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: 10, right: 4),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: Row(children: [
          Icon(Icons.fullscreen, size: 15, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              localizations.editorZenMode,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => setState(() => _zen = false),
            child: Text(localizations.editorExitZen, style: const TextStyle(fontSize: 12)),
          ),
        ]),
      ),
    );
  }

  /// 底部状态栏：光标位置、选中字符数、缩进、语言。
  ///
  /// 状态栏自己监听 controller（而不是整页 setState）：光标一动就更新，
  /// 但不会重建编辑器本体——移动端每次按键重建整页是很贵的。
  Widget _statusBar(EditorDocument doc) {
    return _EditorStatusBar(
      controller: doc.controller,
      dirtyCount: _docs.docs.where((d) => d.dirty).length,
      language: _lang.label == 'Plain Text' ? localizations.editorPlainText : _lang.label,
      indent: _indentLabelFor(doc),
      // 纯文本没有「问题」这个概念，不显示 ❌0 ⚠0。
      report: _programming && _lintEnabled ? doc.lint : null,
      onTapIssues: () => _openConsole(EditorConsoleTab.problems),
      onTapLanguage: _showLanguagePicker,
      onTapIndent: _openSettings,
      encoding: _encoding.name,
      newline: _newlineLabel().split(' ').first,
      onTapEncoding: _pickEncodingFromStatus,
      onTapNewline: () => unawaited(_pickNewline()),
    );
  }

  /// 顶部文档标签条（VS Code 式）：多文档时直接点切，不用开抽屉。
  Widget _docTabs() {
    final docs = _docs.docs;
    if (docs.length < 2) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      height: 29,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: ListView.builder(
        controller: _tabScroll,
        scrollDirection: Axis.horizontal,
        itemCount: docs.length,
        itemBuilder: (context, i) {
          final doc = docs[i];
          final active = doc.id == _doc?.id;
          return InkWell(
            onTap: () {
              if (!active) _activate(doc);
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 0, 4, 0),
              margin: const EdgeInsets.only(right: 1),
              decoration: BoxDecoration(
                color: active ? theme.colorScheme.surface : null,
                border: Border(
                  top: BorderSide(
                    color: active ? theme.colorScheme.primary : Colors.transparent,
                    width: 1.6,
                  ),
                ),
              ),
              child: Row(children: [
                ConstrainedBox(
                  // 长文件名会把一个标签撑到半屏，横滑都救不回来。
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    '${doc.name}${doc.dirty ? ' •' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                      color: active
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 关闭按钮的点击区做大一点：12px 的图标在手机上又难点、
                // 又容易滑到标签本身（手一抖就成了「不小心关掉文件」）。
                InkWell(
                  onTap: () => _closeDoc(doc),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close,
                        size: 13,
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75)),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  /// 把某份文档写回它自己的路径（不是当前文档也能存）。
  Future<bool> _saveDoc(EditorDocument doc) async {
    final path = doc.path;
    if (path == null || path.isEmpty) return false;
    // 「保存全部 / 自动保存 / 退出前保存」也走这里，必须遵守和单文件保存一样的规则，
    // 否则同一份文件换个入口保存，内容就不一样了。
    if (identical(doc, _doc) && _prefs.formatOnSave && _canFormat) {
      await _applyFormat(quiet: true);
      if (!mounted) return false;
    }
    final editorCfg = doc.editorConfig;
    // 行尾空白 / 末尾换行 / 换行符：项目里写了 .editorconfig 就按它来。
    if (editorCfg?.trimTrailingWhitespace ?? _prefs.trimOnSave) {
      _trimDocTrailingWhitespace(doc);
    }
    if (editorCfg?.insertFinalNewline == true) _ensureFinalNewline(doc);
    // 保存前把「磁盘上原来那一份」留进本地历史（VS Code Timeline 的等价物）。
    // 用 diskBaseline 而不是现在的编辑器内容：历史里要的是「你改之前的版本」。
    final baseline = doc.diskBaseline;
    if (baseline != null && baseline != doc.text) {
      unawaited(LocalHistory.record(path, baseline));
    }
    try {
      final text = _applyNewline(
          doc.text, editorCfg?.newlineChars ?? _newlineCharsOf(doc));
      final file = File(path);
      await file.writeAsBytes(await _encodingOf(doc).encode(text));
      // 自己写盘不算「外部修改」：顺手把基线 mtime 对齐，否则 3 秒后的
      // 文件监视会把这刚写的这一次当成别人改的，弹一条误导性提示。
      try {
        _lastFileMtime = (await file.stat()).modified.millisecondsSinceEpoch;
      } catch (_) {}
      doc.dirty = false;
      // 刚写下去的内容就是新的磁盘基线：改动标记（绿/蓝/红）应当全清。
      doc.diskBaseline = doc.text;
      if (mounted && identical(doc, _doc)) {
        _refreshDecorations();
        setState(() {});
      }
      return true;
    } catch (e) {
      _toast('$e');
      return false;
    }
  }

  /// 最近改动过的位置（偏移，最多 20 条）。
  ///
  /// 用「编辑时的光标位置」记，不需要算 diff：打字时光标就在改动处，
  /// 而且这个列表只用来「回到刚才改的地方」，精度要求没那么高。
  /// 最近编辑位置按文档存（见 [EditorDocument.recentEdits]）。
  List<int> get _recentEdits => _doc?.recentEdits ?? const <int>[];

  void _rememberEdit(int offset) {
    if (offset < 0) return;
    final doc = _doc;
    if (doc == null) return;
    // 相差 200 字符内算同一处，否则连着打一句话会塞满整个列表。
    _recentEdits.removeWhere((o) => (o - offset).abs() < 200);
    _recentEdits.insert(0, offset);
    if (_recentEdits.length > 20) _recentEdits.removeLast();
  }

  /// 最近编辑位置列表。
  Future<void> _showRecentEdits() async {
    final controller = _controller;
    if (controller == null) return;
    if (_recentEdits.isEmpty) {
      _toast(localizations.editorNoRecentEdits);
      return;
    }
    final text = controller.text;
    final list = List<int>.from(_recentEdits);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(children: [
              Expanded(
                child: Text(localizations.editorRecentEdits,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: () {
                  setState(() => _doc?.recentEdits.clear());
                  Navigator.pop(ctx);
                },
                child: Text(localizations.clear),
              ),
            ]),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: list.length,
              itemBuilder: (ctx, i) {
                final offset = list[i].clamp(0, text.length);
                final line = _lineOfOffset(text, offset);
                final snippet = _lineTextAt(text, line).trim();
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.history, size: 16),
                  title: Text(
                    snippet.isEmpty ? ' ' : snippet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                  ),
                  subtitle: Text('L${line + 1}', style: const TextStyle(fontSize: 10.5)),
                  onTap: () {
                    Navigator.pop(ctx);
                    controller.selection = TextSelection.collapsed(offset: offset);
                    controller.scrollToLine(line);
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  // ---------- 书签（VS 的 Ctrl+K Ctrl+K）----------

  /// 在当前行加 / 去掉书签。
  ///
  /// 长文件在手机上翻起来很累，书签是「我待会儿还要回到这里」的最省事表达。
  /// 状态挂在文档上，切走再回来还在。
  void _toggleBookmark() {
    final doc = _doc;
    final controller = doc?.controller;
    if (doc == null || controller == null || _caretLine < 0) return;
    final text = controller.text;
    // 用「行首偏移」当锚点：同一行点两次就是去掉。
    final anchor = _offsetOfLine(text, _caretLine);
    int? existing;
    for (final offset in doc.bookmarks) {
      if (_lineOfOffset(text, offset) == _caretLine) {
        existing = offset;
        break;
      }
    }
    setState(() {
      if (existing != null) {
        doc.bookmarks.remove(existing);
      } else {
        doc.bookmarks.add(anchor);
      }
    });
    _refreshDecorations();
    _toast(existing != null
        ? localizations.editorBookmarkRemoved
        : localizations.editorBookmarkAdded);
  }

  /// 跳到下一个 / 上一个书签（到头会绕回去）。
  void _jumpBookmark(bool forward) {
    final doc = _doc;
    final controller = doc?.controller;
    if (doc == null || controller == null) return;
    if (doc.bookmarks.isEmpty) {
      _toast(localizations.editorNoBookmark);
      return;
    }
    final text = controller.text;
    final list = doc.bookmarks.toList()..sort();
    final current = controller.selection.extentOffset.clamp(0, text.length);
    final int target;
    if (forward) {
      target = list.firstWhere((o) => o > current, orElse: () => list.first);
    } else {
      int? found;
      for (final offset in list.reversed) {
        if (offset < current) {
          found = offset;
          break;
        }
      }
      target = found ?? list.last;
    }
    final targetOffset = target.clamp(0, text.length);
    final targetLine = _lineOfOffset(text, targetOffset);
    controller.selection = TextSelection.collapsed(offset: targetOffset);
    controller.scrollToLine(targetLine);
    // 带上行号：只报「2 / 5」还得自己看跳到哪了。
    _toast('${list.indexOf(target) + 1} / ${list.length} · L${targetLine + 1}');
  }

  /// 书签列表（VS 的「书签窗口」）：可以点、可以删、可以一键清空。
  Future<void> _showBookmarks() async {
    final doc = _doc;
    final controller = doc?.controller;
    if (doc == null || controller == null) return;
    final text = controller.text;
    if (doc.bookmarks.isEmpty) {
      _toast(localizations.editorNoBookmark);
      return;
    }
    final list = doc.bookmarks.toList()..sort();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(children: [
              Expanded(
                child: Text(localizations.editorBookmarks,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _clearBookmarks();
                },
                child: Text(localizations.clear),
              ),
            ]),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: list.length,
              itemBuilder: (ctx, i) {
                final offset = list[i];
                final line = _lineOfOffset(text, offset);
                final snippet = _lineTextAt(text, line).trim();
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.bookmark, size: 16, color: Colors.amber),
                  title: Text(
                    snippet.isEmpty ? ' ' : snippet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                  ),
                  subtitle: Text('L${line + 1}', style: const TextStyle(fontSize: 10.5)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: localizations.delete,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () {
                      setState(() => doc.bookmarks.remove(offset));
                      _refreshDecorations();
                      Navigator.pop(ctx);
                      // 删空了就到此为止，不再弹一个空列表 + 一句「还没有书签」。
                      if (doc.bookmarks.isNotEmpty) unawaited(_showBookmarks());
                    },
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    controller.selection =
                        TextSelection.collapsed(offset: offset.clamp(0, text.length));
                    controller.scrollToLine(line);
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  /// 清空本文档的所有书签。
  void _clearBookmarks() {
    final doc = _doc;
    if (doc == null) return;
    if (doc.bookmarks.isEmpty) {
      // 静默返回会让人以为是点了没反应。
      _toast(localizations.editorNoBookmark);
      return;
    }
    setState(() => doc.bookmarks.clear());
    _refreshDecorations();
  }

  /// 把所有改过且有路径的文档一次写回磁盘。
  ///
  /// 没有路径的那些（新建未保存）跳过——它们只能走「另存为」，一弹一串文件选择框
  /// 比什么都糟糕。当前文档若属于这一类，就老老实实弹一次另存为。
  Future<void> _saveAllDirty() async {
    final targets = _docs.docs.where((d) => d.dirty).toList(growable: false);
    if (targets.isEmpty) return;
    var saved = 0;
    var failed = 0;
    for (final doc in targets) {
      final path = doc.path;
      if (path == null || path.isEmpty) {
        if (identical(doc, _doc)) unawaited(_download());
        continue;
      }
      final ok = await _saveDoc(doc);
      if (ok) {
        saved++;
      } else {
        failed++;
      }
    }
    if (!mounted) return;
    if (saved > 0) _toast(localizations.editorSavedCount('$saved'));
    if (failed > 0) _toast('${localizations.fail}: $failed');
  }

  /// 关掉除当前文档以外的全部文档。
  ///
  /// 其中有改过的只问一次（不逐个弹——手机上弹一串对话框最难忍受）。
  Future<void> _closeOtherDocs() async {
    final others = _docs.docs.where((d) => !identical(d, _doc)).toList(growable: false);
    if (others.isEmpty) return;
    final dirtyCount = others.where((d) => d.dirty).length;
    if (dirtyCount > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(localizations.editorCloseOthers),
          content: Text(localizations.editorCloseOthersDirty('$dirtyCount')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localizations.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(localizations.editorExitWithoutSaving)),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    for (final doc in others) {
      _docs.remove(doc.id);
    }
    setState(() {});
    _docs.persist();
  }

  /// 文档抽屉的滚动控制器（打开时滚到当前文档）。
  final ScrollController _docScroll = ScrollController();

  /// 抽屉里的搜索词（文档多了以后翻列表很痛苦）。
  String _docQuery = '';

  /// 顶部文档标签条的滚动控制器（切文档时把当前标签滚进可视区）。
  final ScrollController _tabScroll = ScrollController();

  void _scrollTabIntoView() {
    if (!_tabScroll.hasClients) return;
    final index = _docs.docs.indexWhere((d) => identical(d, _doc));
    if (index < 0) return;
    // 标签最宽 150、最窄 70，按 130 估（宁可多滚一点，也别让当前标签露不出来）。
    final target = (index * 130.0 - 80).clamp(0.0, _tabScroll.position.maxScrollExtent);
    _tabScroll.animateTo(target,
        duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
  }

  void _scrollToActiveDoc() {
    if (!_docScroll.hasClients) return;
    final index = _docs.docs.indexWhere((d) => identical(d, _doc));
    if (index < 0) return;
    // dense ListTile 一行约 56dp，估算即可——差几像素不影响「看得见」。
    final target = (index * 56.0).clamp(0.0, _docScroll.position.maxScrollExtent);
    _docScroll.animateTo(target,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  Widget _docDrawer() {
    final query = _docQuery.trim().toLowerCase();
    final docs = query.isEmpty
        ? _docs.docs
        : _docs.docs.where((d) => d.name.toLowerCase().contains(query)).toList(growable: false);
    return Drawer(
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
            child: Row(children: [
              Expanded(
                child: Text(localizations.editorDocuments,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: localizations.editorNewFile,
                onPressed: _newFile,
              ),
              // 多开几份之后「一份份点开再存」很烦，批量入口放这儿。
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 19),
                tooltip: localizations.editorMore,
                onSelected: (v) {
                  switch (v) {
                    case 'saveAll':
                      unawaited(_saveAllDirty());
                    case 'closeOthers':
                      unawaited(_closeOtherDocs());
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'saveAll', child: Text(localizations.editorSaveAll)),
                  PopupMenuItem(value: 'closeOthers', child: Text(localizations.editorCloseOthers)),
                ],
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: TextField(
              onChanged: (v) => setState(() => _docQuery = v),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 17),
                hintText: localizations.search,
                hintStyle: const TextStyle(fontSize: 12.5),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const Divider(height: 1, thickness: 0.3),
          Expanded(
            // 搜索时不做重排：过滤后的下标和真实顺序对不上，拖了会错位。
            child: query.isEmpty
                ? ReorderableListView.builder(
                    scrollController: _docScroll,
                    buildDefaultDragHandles: false,
                    itemCount: docs.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() => _docs.reorder(oldIndex, newIndex));
                      _docs.persist();
                    },
                    itemBuilder: (context, i) => _docTile(docs[i], i),
                  )
                : ListView.builder(
                    controller: _docScroll,
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final doc = docs[i];
                      return ListTile(
                        dense: true,
                        selected: identical(doc, _doc),
                        leading: Icon(
                          doc.pinned ? Icons.push_pin : Icons.description_outlined,
                          size: 18,
                          color: doc.pinned ? Theme.of(context).colorScheme.primary : null,
                        ),
                        title: Text(doc.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5)),
                        subtitle: Text(
                            doc.bookmarks.isEmpty
                                ? doc.langLabel
                                : '${doc.langLabel} · ${doc.bookmarks.length}',
                            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                        onTap: () {
                          _activate(doc);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _docTile(EditorDocument doc, int index) {
    final selected = identical(doc, _doc);
    return _SwipeTile(
      key: ValueKey(doc.id),
      onTap: () {
        _activate(doc);
        Navigator.of(context).pop();
      },
      actions: [
        _SwipeAction(
          icon: doc.pinned ? Icons.push_pin_outlined : Icons.push_pin,
          tooltip: doc.pinned ? localizations.editorUnpin : localizations.editorPin,
          color: Theme.of(context).colorScheme.primary,
          onTap: () => _togglePin(doc),
        ),
        _SwipeAction(
          icon: Icons.close,
          tooltip: localizations.editorCloseFile,
          color: Colors.red,
          onTap: () => _closeDoc(doc),
        ),
      ],
      child: ReorderableDelayedDragStartListener(
        index: index,
        child: ListTile(
          dense: true,
          selected: selected,
          leading: Icon(
            doc.pinned ? Icons.push_pin : Icons.description_outlined,
            size: 18,
            color: doc.pinned ? Theme.of(context).colorScheme.primary : null,
          ),
          title: Text(
            '${doc.name}${doc.dirty ? ' •' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5),
          ),
          subtitle: Text(
            doc.langLabel,
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (doc.retained)
              Icon(Icons.lock_outline, size: 15, color: Colors.grey[600]),
            IconButton(
              icon: const Icon(Icons.more_vert, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: () => _showDocActions(doc),
            ),
          ]),
        ),
      ),
    );
  }

  void _showDocActions(EditorDocument doc) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(doc.pinned ? Icons.push_pin_outlined : Icons.push_pin),
            title: Text(doc.pinned ? localizations.editorUnpin : localizations.editorPin),
            onTap: () {
              Navigator.pop(ctx);
              _togglePin(doc);
            },
          ),
          ListTile(
            leading: Icon(doc.retained ? Icons.lock_open_outlined : Icons.lock_outline),
            title: Text(localizations.editorRetain),
            subtitle: Text(localizations.editorRetainHint, style: const TextStyle(fontSize: 11.5)),
            onTap: () {
              Navigator.pop(ctx);
              _toggleRetain(doc);
            },
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: Text(localizations.editorCloseFile),
            onTap: () {
              Navigator.pop(ctx);
              unawaited(_closeDoc(doc));
            },
          ),
        ]),
      ),
    );
  }

  /// 工具栏两行，按「找得到 + 按得准」重新排过。
  ///
  /// 第一行只有五个分类菜单（文件 / 编辑 / 代码 / 视图 / 检查）。
  /// 语言选择挪到右下角状态栏（VS 就在那儿），抽屉入口用标题栏自带的按钮，
  /// 省下来的宽度全给这五个分类——每个约 70dp 宽、36dp 高，手指按得准，
  /// 不像之前那样挤成一排小字。
  ///
  /// 第二行是高频图标；灯泡和「更多」靠右，单手握持时拇指更容易够到。
  Widget _toolbar() {
    final color = Theme.of(context).colorScheme.primary;
    final loc = localizations;
    final canUndo = _doc?.undoController.canUndo == true;
    final canRedo = _doc?.undoController.canRedo == true;
    return Container(
      padding: const EdgeInsets.only(left: 2, right: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 36,
          child: Row(children: [
            Expanded(child: _groupMenu('file', loc.editorMenuFile)),
            Expanded(child: _groupMenu('edit', loc.editorMenuEdit)),
            Expanded(child: _groupMenu('code', loc.editorMenuCode)),
            Expanded(child: _groupMenu('view', loc.editorMenuView)),
            if (_programming) Expanded(child: _groupMenu('inspect', loc.editorMenuInspect)),
          ]),
        ),
        SizedBox(
          height: 40,
          child: LayoutBuilder(builder: (context, box) {
            // 360dp 屏上第二行原本要塞 10 个 38dp 按钮（≈400dp），直接 Row overflow。
            // 窄屏把「新建 / 打开」收进第一行的「文件」菜单（那两项本来就在里面），
            // 「保存」留着 —— 手机上它最常用。
            final narrow = box.maxWidth < 400;
            return Row(children: [
              if (!narrow) ...[
                _iconBtn(Icons.note_add_outlined, loc.editorNewFile, _newFile),
                _iconBtn(Icons.folder_open, loc.selectFile, _openFile),
                _toolbarSep(),
              ],
              _iconBtn(Icons.save_outlined, loc.save, _download),
              _iconBtn(Icons.undo, loc.editorUndo, canUndo ? _undo : null),
              _iconBtn(Icons.redo, loc.editorRedo, canRedo ? _redo : null),
              // 搜索在「工具菜单」里可隐藏，这里跟着一起走：设置里关了却在工具栏
              // 还杵着一个按钮，等于设置没生效。
              if (!_prefs.hiddenMenu.contains('search'))
                AnimatedBuilder(
                  animation: _doc?.findController ?? _noFind,
                  builder: (_, __) => _iconBtn(
                      Icons.search,
                      loc.search,
                      _toggleFind,
                      tint: (_doc?.findController.isActive ?? false) ? color : null),
                ),
              const Spacer(),
              // 未保存小圆点（VS 标签上那个点），一眼知道这份文件还没写回磁盘。
              if (_dirty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.circle, size: 7, color: color),
                ),
              // 命令面板：找功能不用翻菜单（VS 的 Ctrl+Q / VS Code 的 Ctrl+Shift+P）。
              _iconBtn(Icons.manage_search, loc.editorCommandPalette, _showCommandPalette),
              // 光标那行有问题时才出现的灯泡（VS 的 Quick Fix），靠右放。
              if (_fixAtCaretLine != null)
                _iconBtn(Icons.lightbulb, loc.editorQuickFix,
                    () => _fixDiagnostic(_fixAtCaretLine!), tint: Colors.amber),
              _moreMenu(color),
            ]);
          }),
        ),
      ]),
    );
  }

  /// 一个分类菜单（`文件` / `编辑` / `代码` / `视图` / `检查`）。
  ///
  /// 内容按功能归类，和「更多」用的是同一套 value，动作只有 [_menuAction] 一份实现。
  Widget _groupMenu(String group, String label) {
    final hidden = _prefs.hiddenMenu.toSet();
    final entries = _entriesOf(group)
        .where((e) => e is! PopupMenuItem<String> || !hidden.contains(e.value as String))
        .toList(growable: false);
    if (entries.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: label,
      onSelected: _menuAction,
      itemBuilder: (_) => entries.toList(),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              // scaleDown 兜底：个别语言（俄语/泰语）的译名更长，宁可略缩也不截成省略号。
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            // 小箭头：纯文字一排很容易被当成 tab，加上它就明确是「下拉菜单」。
            Icon(Icons.arrow_drop_down, size: 15, color: Theme.of(context).textTheme.bodySmall?.color),
          ]),
        ),
      ),
    );
  }

  /// 分类菜单里的一行（VS 的菜单每项前面都有图标）。
  ///
  /// 长菜单里扫图标比逐行读文字快得多，这也是桌面软件菜单一直保留图标的原因。
  PopupMenuEntry<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    bool enabled = true,
  }) {
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: Row(children: [
        Icon(icon, size: 17,
            color: enabled ? Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.8) : Theme.of(context).disabledColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5)),
        ),
      ]),
    );
  }

  /// 某个分类里有哪些菜单项。
  ///
  /// 这里只负责「放哪些、按什么顺序」，点了之后做什么全在 [_menuAction]。
  List<PopupMenuEntry<String>> _entriesOf(String group) {
    final loc = localizations;
    final canUndo = _doc?.undoController.canUndo == true;
    final canRedo = _doc?.undoController.canRedo == true;
    switch (group) {
      case 'file':
        return [
          _menuItem('newFile', Icons.note_add_outlined, loc.editorNewFile),
          _menuItem('open', Icons.folder_open, loc.selectFile),
          _menuItem('recentFiles', Icons.history_toggle_off,
              loc.editorRecentFiles),
          _menuItem('save', Icons.save_outlined, loc.save),
          _menuItem('saveAll', Icons.save_as_outlined, loc.editorSaveAll),
          _menuItem('reopenClosed', Icons.restore_page_outlined, loc.editorReopenClosed),
          _menuItem('workspaceTree', Icons.account_tree_outlined, loc.editorWorkspaceTree),
          _menuItem('renameFile', Icons.drive_file_rename_outline,
              loc.editorRenameFile),
          _menuItem('copyPath', Icons.link, loc.editorCopyPath),
          _menuItem('insertFile', Icons.file_download_outlined, loc.editorInsertFile),
          if (Platforms.isDesktop())
            _menuItem('revealFile', Icons.folder_special, loc.editorRevealFile),
          _menuItem('quickOpen', Icons.bolt, loc.editorQuickOpen),
          _menuItem('browse', Icons.folder_open_outlined, loc.editorBrowser),
          _menuItem('workspace', Icons.workspaces_outlined, loc.editorWorkspace),
          _menuItem('compareDisk', Icons.compare_arrows, loc.editorCompareDisk),
          _menuItem('compareClipboard', Icons.content_paste_search,
              loc.editorCompareClipboard),
          _menuItem('diffTab', Icons.compare, loc.editorDiffWithTab),
          _menuItem('history', Icons.history, loc.editorLocalHistory),
          CheckedPopupMenuItem(
              value: 'autosave', checked: _autoSave, child: Text(loc.editorAutoSave)),
          PopupMenuItem(value: 'file', child: _menuRow(loc.editorMoreFile, Icons.arrow_right, id: 'file')),
          _menuItem('docs', Icons.description_outlined, loc.editorDocuments),
          const PopupMenuDivider(),
          _menuItem('close', Icons.close, loc.editorCloseFile),
        ];
      case 'edit':
        return [
          PopupMenuItem(
              value: 'undo',
              enabled: canUndo,
              child: Text(loc.editorUndo,
                  style: TextStyle(color: canUndo ? null : Theme.of(context).disabledColor))),
          PopupMenuItem(
              value: 'redo',
              enabled: canRedo,
              child: Text(loc.editorRedo,
                  style: TextStyle(color: canRedo ? null : Theme.of(context).disabledColor))),
          _menuItem('recentEdits', Icons.history, loc.editorRecentEdits),
          PopupMenuItem(
              value: 'navBack',
              enabled: _navIndex > 0,
              child: Text(loc.editorNavBack,
                  style: TextStyle(
                      color: _navIndex > 0 ? null : Theme.of(context).disabledColor))),
          PopupMenuItem(
              value: 'navForward',
              enabled: _navIndex < _navStack.length - 1,
              child: Text(loc.editorNavForward,
                  style: TextStyle(
                      color: _navIndex < _navStack.length - 1
                          ? null
                          : Theme.of(context).disabledColor))),
          const PopupMenuDivider(),
          _menuItem('copy', Icons.content_copy, loc.copy),
          _menuItem('clipHistory', Icons.content_paste, loc.editorClipHistory),
          _menuItem('clear', Icons.backspace_outlined, loc.clear),
          _menuItem('replaceLine', Icons.sync_alt, loc.editorReplaceLine),
          const PopupMenuDivider(),
          _menuItem('comment', Icons.code, loc.editorToggleComment),
          PopupMenuItem(value: 'lineOps', child: _menuRow(loc.editorLineOps, Icons.arrow_right, id: 'lineOps')),
          PopupMenuItem(value: 'caseOps', child: _menuRow(loc.editorCaseOps, Icons.arrow_right, id: 'caseOps')),
          _menuItem('expandSel', Icons.open_in_full, loc.editorExpandSelection),
          _menuItem('insertDateTime', Icons.schedule, loc.editorInsertDateTime),
          _menuItem('nextSnippetStop', Icons.keyboard_tab, loc.editorNextSnippetStop),
          _menuItem('escapeString', Icons.text_fields, loc.editorEscape),
        _menuItem('jumpBracket', Icons.data_object, loc.editorJumpBracket),
        _menuItem('selectToBracket', Icons.select_all, loc.editorSelectToBracket),
        _menuItem('columnCursors', Icons.view_column_outlined, loc.editorColumnSelect),
        _menuItem('boxSelect', Icons.grid_on, loc.editorRectSelect),
        _menuItem('openLink', Icons.link, loc.editorOpenLink),
        _menuItem('trimTrailing', Icons.cleaning_services_outlined, loc.editorTrimTrailing),
        PopupMenuItem(value: 'nextBookmark', child: Text(loc.editorNextBookmark)),
        _menuItem('toggleBookmark', Icons.bookmark_add_outlined, loc.editorToggleBookmark),
        _menuItem('bookmarks', Icons.bookmarks_outlined, loc.editorBookmarks),
        _menuItem('clearBookmarks', Icons.bookmark_remove_outlined, loc.editorClearBookmarks),
        _menuItem('nextOccurrence', Icons.select_all, loc.editorSelectNext),
        _menuItem('selectAllOccurrences', Icons.select_all,
            loc.editorSelectAllOccurrences),
        const PopupMenuDivider(),
        _menuItem('cursorAbove', Icons.keyboard_arrow_up, loc.editorCursorAbove),
        _menuItem('cursorBelow', Icons.keyboard_arrow_down, loc.editorCursorBelow),
        _menuItem('clearCursors', Icons.highlight_remove, loc.editorClearCursors),
        ];
      case 'code':
        return [
          // AI 辅助放最前：这是 VS2026/Cursor 里使用频率最高的一档。
          _menuItem('aiAssist', Icons.auto_awesome, loc.editorAiAssist),
          const PopupMenuDivider(),
          if (_canFormat) _menuItem('format', Icons.auto_fix_high, loc.format),
          _menuItem('formatSel', Icons.auto_fix_normal, loc.editorFormatSelection),
          if (_canPreview) _menuItem('preview', Icons.visibility_outlined, loc.editorPreview),
          const PopupMenuDivider(),
          _menuItem('symbols', Icons.account_tree_outlined, loc.editorSymbols),
          _menuItem('gotoLine', Icons.pin_drop_outlined, loc.editorSelectToLine),
          _menuItem('gotoDef', Icons.my_location_outlined, loc.editorGotoDefinition),
        _menuItem('peekDef', Icons.visibility, loc.editorPeekDefinition),
          _menuItem('references', Icons.format_list_bulleted, loc.editorReferences),
          _menuItem('callHierarchy', Icons.account_tree_outlined, loc.editorCallHierarchy),
          _menuItem('rename', Icons.drive_file_rename_outline, loc.editorRename),
          _menuItem('renamePair', Icons.tag, loc.editorRenamePair),
          _menuItem('prevChange', Icons.keyboard_double_arrow_up, loc.editorPrevChange),
          _menuItem('nextChange', Icons.keyboard_double_arrow_down, loc.editorNextChange),
          _menuItem('conflicts', Icons.call_split, loc.editorConflicts),
          _menuItem('workspace', Icons.workspaces_outlined, loc.editorWorkspace),
          _menuItem('snippets', Icons.auto_awesome_motion, loc.editorSnippets),
          _menuItem('stats', Icons.analytics_outlined, loc.editorDocStats),
          _menuItem('copyNumbered', Icons.format_list_numbered, loc.editorCopyNumbered),
          _menuItem('transpose', Icons.swap_horiz, loc.editorTranspose),
          _menuItem('numbering', Icons.format_list_numbered, loc.editorNumbering),
          _menuItem('quoteLines', Icons.format_quote, loc.editorQuoteLines),
          _menuItem('joinLines', Icons.merge_type, loc.editorJoinLines),
          _menuItem('splitLines', Icons.call_split, loc.editorSplitLines),
          _menuItem('textCodec', Icons.swap_vert, loc.editorTextCodec),
          _menuItem('copyMarkdown', Icons.code, loc.editorCopyMarkdown),
          _menuItem('findInFiles', Icons.manage_search, loc.editorFindInFiles),
          _menuItem('renameEverywhere', Icons.drive_file_move_outline, loc.editorRenameEverywhere),
          _menuItem('undoRename', Icons.undo, loc.editorRenameUndo),
          const PopupMenuDivider(),
          _menuItem('foldAll', Icons.unfold_less, loc.editorFoldAll),
          _menuItem('unfoldAll', Icons.unfold_more, loc.editorUnfoldAll),
          _menuItem('foldLevel', Icons.format_indent_decrease, loc.editorFoldToLevel),
          _menuItem('minify', Icons.compress, loc.editorMinify),
          _menuItem('minifyAggressive', Icons.compress, loc.editorMinifyAggressive),
        ];
      case 'view':
        return [
          CheckedPopupMenuItem(value: 'wrap', checked: _wrap, child: Text(loc.wordWrap)),
          CheckedPopupMenuItem(value: 'readOnly', checked: _readOnly, child: Text(loc.editorReadOnly)),
          CheckedPopupMenuItem(value: 'smooth', checked: _smooth, child: Text(loc.editorSmoothMode)),
          CheckedPopupMenuItem(
              value: 'smart', checked: SmartCompletion.enabled.value, child: Text(loc.smartCompletion)),
          CheckedPopupMenuItem(
              value: 'smoothKeepIme',
              checked: _smoothKeepIme,
              child: Text(loc.editorSmoothKeepIme)),
          CheckedPopupMenuItem(
              value: 'ascii', checked: _showAscii, child: Text(loc.editorShowAsciiControl)),
          CheckedPopupMenuItem(
              value: 'unicode', checked: _showUnicode, child: Text(loc.editorShowUnicodeSpecial)),
          CheckedPopupMenuItem(value: 'zen', checked: _zen, child: Text(loc.editorZenMode)),
          _menuItem('report', Icons.report_outlined, loc.editorSpecialReport),
          _menuItem('detectIndent', Icons.format_indent_increase, loc.editorDetectIndent),
          _menuItem('diskChange', Icons.difference_outlined, loc.editorDiskChange),
          const PopupMenuDivider(),
          _menuItem('syntax', Icons.code, loc.editorMoreSyntax),
          PopupMenuItem(
              value: 'newline',
              child: Text('${loc.editorNewline}: ${_newlineLabel()}')),
          PopupMenuItem(
              value: 'retainMode',
              child: Text('${loc.editorRetainPref}: ${_retainModeLabel()}')),
          _menuItem('settings', Icons.settings, loc.editorSettings),
        ];
      case 'inspect':
        if (!_programming) return const [];
        return [
          CheckedPopupMenuItem(
              value: 'lint', checked: _lintEnabled, child: Text(loc.editorLint)),
          _menuItem('lintIssues', Icons.error_outline, loc.editorLintIssues),
          _menuItem('console', Icons.terminal, loc.editorConsole),
          _menuItem('lintRules', Icons.rule, loc.editorLintAllRules),
          _menuItem('compilerLog', Icons.translate, loc.editorCompilerLog),
          _menuItem('toggleBreakpoint', Icons.radio_button_unchecked, loc.editorToggleBreakpoint),
          _menuItem('debug', Icons.bug_report_outlined, loc.editorDebugTab),
          const PopupMenuDivider(),
          _menuItem('prevTodo', Icons.arrow_upward, loc.editorPrevTodo),
          _menuItem('nextTodo', Icons.arrow_downward, loc.editorNextTodo),
          _menuItem('tasks', Icons.checklist, loc.editorTasks),
        ];
    }
    return const [];
  }

  void _undo() => _doc?.undoController.undo();

  void _redo() => _doc?.undoController.redo();

  /// 工具栏的分类菜单和「更多」菜单共用一个动作入口：
  /// 两个入口只是「同一批功能的不同分组方式」，动作必须只有一份实现。
  void _menuAction(String value) {
    switch (value) {

        case 'file':
          _showFileMenu();
        case 'search':
          _toggleFind();
        case 'syntax':
          _showSyntaxMenu();
        case 'gotoLine':
          _selectToLine();
        case 'symbols':
          _showSymbols();
        case 'nextOccurrence':
          _addNextOccurrence();
        case 'selectAllOccurrences':
          _selectAllOccurrences();
        case 'gotoDef':
          unawaited(_gotoDefinition());
        case 'lineOps':
          _showLineOpsMenu();
        case 'caseOps':
          _showCaseOpsMenu();
        case 'navBack':
          _navBack();
        case 'navForward':
          _navForward();
        case 'wrap':
          setState(() => _wrap = !_wrap);
        case 'readOnly':
          setState(() => _readOnly = !_readOnly);
        case 'smooth':
          // 手动切过就当作「用户的意愿」，不再跟着文件大小自动变。
          _smoothAuto = false;
          setState(() => _smooth = !_smooth);
        case 'smart':
          SmartCompletion.setEnabled(!SmartCompletion.enabled.value).ignore();
        case 'smoothKeepIme':
          _setSmoothKeepIme(!_smoothKeepIme);
        case 'ascii':
          _setShowAscii(!_showAscii);
        case 'unicode':
          _setShowUnicode(!_showUnicode);
        case 'report':
          _showSpecialReport();
        case 'diskChange':
          unawaited(_showDiskChangeAtCaret());
        case 'toggleBreakpoint':
          _toggleBreakpointAtCaret();
        case 'debug':
          _openConsole(EditorConsoleTab.debug);
        case 'replaceLine':
          _replaceCurrentLine();
        case 'lint':
          _setLintEnabled(!_lintEnabled);
        case 'lintIssues':
          _openConsole(EditorConsoleTab.problems);
        case 'console':
          _openConsole(EditorConsoleTab.console);
        case 'minify':
          unawaited(_minify());
        case 'minifyAggressive':
          unawaited(_minifyAggressive());
        case 'newline':
          _pickNewline();
        case 'retainMode':
          _pickRetainMode();
        case 'settings':
          _openSettings();
        case 'rename':
          unawaited(_renameSymbol());
        case 'renamePair':
          unawaited(_renamePairedTag());
        case 'boxSelect':
          _boxSelect();
        case 'workspace':
          unawaited(_pickWorkspace());
        case 'snippets':
          unawaited(_showSnippets());
        case 'findInFiles':
          unawaited(_findInFiles());
        case 'renameEverywhere':
          unawaited(_renameSymbolEverywhere());
        case 'undoRename':
          unawaited(_undoRenameEverywhere());
        case 'formatSel':
          unawaited(_applyFormat(selectionOnly: true));
        case 'foldAll':
          _controller?.foldAll();
        case 'unfoldAll':
          _controller?.unfoldAll();
      case 'foldLevel':
        unawaited(_showFoldLevelPicker());
        case 'references':
          unawaited(_showReferences());
        case 'callHierarchy':
          unawaited(_showCallHierarchy());
        case 'close':
          final doc = _doc;
          if (doc != null) unawaited(_closeDoc(doc));
      
      // 分类菜单里额外暴露出来的高频入口（原来只能从图标或子菜单点）。
      case 'newFile':
        _newFile();
      case 'open':
        unawaited(_openFile());
      case 'save':
        unawaited(_download());
      case 'saveAll':
        unawaited(_saveAllDirty());
      case 'aiAssist':
        unawaited(_showAiAssist());
      case 'quickOpen':
        unawaited(_showQuickOpen());
      case 'clipHistory':
        unawaited(_showClipHistory());
      case 'compilerLog':
        unawaited(_showCompilerLog());
      case 'browse':
        unawaited(_showFileBrowser());
      case 'docs':
        _scaffoldKey.currentState?.openDrawer();
      case 'undo':
        _undo();
      case 'redo':
        _redo();
      case 'copy':
        _copy();
      case 'clear':
        _clear();
      case 'comment':
        _toggleComment();
      case 'format':
        unawaited(_applyFormat());
      case 'preview':
        _preview();
      case 'lintRules':
        unawaited(_openLintRules());
      // 以下这批是「代码」分类里的项，之前误插到了长按菜单的动作里，
      // 结果从菜单点它们毫无反应（静默），这里补回正确位置。
      case 'peekDef':
        unawaited(_peekDefinition());
      case 'expandSel':
        _expandSelection();
      case 'nextSnippetStop':
        _nextSnippetStop();
      case 'cursorAbove':
        _addCursorAtLine(-1);
      case 'cursorBelow':
        _addCursorAtLine(1);
      case 'clearCursors':
        _clearMultiCursors();
      case 'compareDisk':
        unawaited(_compareWithDisk());
      case 'compareClipboard':
        unawaited(_compareWithClipboard());
        case 'reopenClosed':
          unawaited(_reopenClosed());
        case 'workspaceTree':
          _showWorkspaceTree();
        case 'diffTab':
          _compareWithTab();
        case 'history':
          _showLocalHistory();
        case 'tasks':
          _showTasks();
        case 'stats':
          unawaited(_showDocStats());
        case 'recentFiles':
          unawaited(_showRecentFiles());
        case 'renameFile':
          unawaited(_renameFile());
        case 'copyPath':
          unawaited(_copyFilePath());
        case 'revealFile':
          unawaited(_revealInFolder());
        case 'insertFile':
          unawaited(_insertFileText());
        case 'copyNumbered':
          unawaited(_copyNumbered());
        case 'copyMarkdown':
          unawaited(_copyMarkdown());
        case 'zen':
          setState(() => _zen = !_zen);
        case 'transpose':
          _transposeChars();
        case 'numbering':
          unawaited(_insertNumbering());
        case 'quoteLines':
          unawaited(_quoteLines());
        case 'joinLines':
          _joinLines();
        case 'splitLines':
          unawaited(_splitLines());
        case 'textCodec':
          unawaited(_showTextCodec());
      case 'autosave':
        setState(() => _autoSave = !_autoSave);
        unawaited(_saveAutoSave());
        if (_autoSave) _scheduleAutoSave();
      case 'jumpBracket':
        _jumpToMatchingBracket();
      case 'insertDateTime':
        _insertDateTime();
      case 'escapeString':
        unawaited(_showEscapeDialog());
      case 'prevTodo':
        _gotoTodo(-1);
      case 'nextTodo':
        _gotoTodo(1);
      case 'prevChange':
        _gotoChange(-1);
      case 'nextChange':
        _gotoChange(1);
      case 'conflicts':
        unawaited(_showConflicts());
      case 'selectToBracket':
        _selectToBracket();
      case 'columnCursors':
        _addColumnCursors();
      case 'openLink':
        unawaited(_openLinkAtCursor());
      case 'trimTrailing':
        _trimTrailingWhitespace();
      case 'detectIndent':
        _detectIndent();
      case 'recentEdits':
        unawaited(_showRecentEdits());
      case 'toggleBookmark':
        _toggleBookmark();
      case 'nextBookmark':
        _jumpBookmark(true);
      case 'prevBookmark':
        _jumpBookmark(false);
      case 'bookmarks':
        unawaited(_showBookmarks());
      case 'clearBookmarks':
        _clearBookmarks();
    }
  }

  Widget _moreMenu(Color color) {
    // 触摸区收成 38dp 与 _iconBtn 一致：PopupMenuButton 默认 48，第二个行会白占 10dp。
    return SizedBox(
      width: 38,
      height: 38,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.more_vert, size: 18),
        tooltip: localizations.editorMore,
        onSelected: _menuAction,
        itemBuilder: (context) {
          final hidden = _prefs.hiddenMenu.toSet();
          // 「更多」只放快入口：搜索 / 语法 / 设置 / 关闭文件。
          //
          // 之前这里几乎把 54 项全列了一遍，和「文件·编辑·代码·视图·检查」五个分类菜单、
          // 以及命令面板完全重复 —— 三套入口列同一份东西，只会让「更多」越滚越长。
          // 隐藏项设置对这里仍然生效。
          return <PopupMenuEntry<String>>[
            PopupMenuItem(value: 'search', child: Text(localizations.search)),
            PopupMenuItem(
              value: 'syntax',
              child: _menuRow(localizations.editorMoreSyntax, Icons.arrow_right, id: 'syntax'),
            ),
            const PopupMenuDivider(),
            _menuItem('settings', Icons.settings, localizations.editorSettings),
            const PopupMenuDivider(),
            _menuItem('close', Icons.close, localizations.editorCloseFile),
          ].where((e) => e is! PopupMenuItem<String> || !hidden.contains(e.value)).toList();
        },
      ),
    );
  }

  /// 按 BOM 认 UTF-16 / UTF-32（这类文件没有 BOM 基本无法可靠识别）。
  EditorEncoding? _bomEncodingOf(List<int> b) {
    EditorEncoding? find(String name) {
      for (final e in kEncodings) {
        if (e.name == name) return e;
      }
      return null;
    }

    if (b.length >= 4) {
      if (b[0] == 0xFF && b[1] == 0xFE && b[2] == 0x00 && b[3] == 0x00) {
        return find('UTF-32LE');
      }
      if (b[0] == 0x00 && b[1] == 0x00 && b[2] == 0xFE && b[3] == 0xFF) {
        return find('UTF-32BE');
      }
    }
    if (b.length >= 2) {
      if (b[0] == 0xFF && b[1] == 0xFE) return find('UTF-16LE');
      if (b[0] == 0xFE && b[1] == 0xFF) return find('UTF-16BE');
    }
    return null;
  }

  /// 菜单里带右侧箭头的行（表示还有下一级）。
  Widget _menuRow(String text, IconData trailing, {String? id}) {
    return Row(
      children: [
        // 二级菜单行也带图标：和一级项保持一样的扫读节奏。
        if (id != null) ...[
          Icon(menuIconOf(id), size: 17, color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.8)),
          const SizedBox(width: 10),
        ],
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
        Icon(trailing, size: 18),
      ],
    );
  }

  /// 命令面板（VS / VS Code 的 Ctrl+Shift+P，这里也能一键找到任何功能）。
  ///
  /// 五个分类是「浏览」，命令面板是「已经知道要找什么」——
  /// 手机上翻四级菜单找一个功能，远不如打两个字。
  static const String _recentCmdKey = 'text_editor_recent_cmds_v1';

  /// 这些是「开关」，执行完不该把面板关掉——用户往往要连着拨几下面板里的开关。
  /// 依赖语法解析的命令：纯文本下没有意义（点了只能得到「未找到符号」之类）。
  static const Set<String> _programmingOnlyCommands = <String>{
    'comment',
    'expandSel',
    'jumpBracket',
    'nextOccurrence',
    'symbols',
    'gotoDef',
    'peekDef',
    'references',
    'rename',
    'foldAll',
    'unfoldAll',
    'minify',
    'minifyAggressive',
  };

  static const Set<String> _toggleCommands = <String>{
    'wrap',
    'readOnly',
    'smooth',
    'smart',
    'smoothKeepIme',
    'ascii',
    'unicode',
    'lint',
  };

  Future<void> _clearRecentCommands() async {
    final backup = await _loadRecentCommands();
    try {
      await SharedPreferencesAsync().remove(_recentCmdKey);
    } catch (_) {
      // 清不掉不影响使用，下次记录会覆盖
      return;
    }
    if (!mounted || backup.isEmpty) return;
    // 长按清空没有二次确认（面板上再加个对话框太重），给 1.6 秒撤销。
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(localizations.editorRecentCleared),
      duration: const Duration(milliseconds: 1600),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: localizations.editorUndo,
        onPressed: () {
          unawaited(SharedPreferencesAsync().setStringList(_recentCmdKey, backup));
        },
      ),
    ));
  }

  Future<List<String>> _loadRecentCommands() async {
    try {
      return await SharedPreferencesAsync().getStringList(_recentCmdKey) ?? const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _rememberCommand(String id) async {
    try {
      final prefs = SharedPreferencesAsync();
      final list = (await prefs.getStringList(_recentCmdKey)) ?? <String>[];
      list.remove(id);
      list.insert(0, id);
      if (list.length > 8) list.removeRange(8, list.length);
      await prefs.setStringList(_recentCmdKey, list);
    } catch (_) {
      // 记不上不影响执行
    }
  }

  /// 命令面板里那些「开关类」命令的当前状态，用来在右侧显示 ✓。
  Map<String, bool> get _toggleStates => {
        // 查找面板是否开着：读一下就能看出「搜索」这条为什么点了没反应（它本来就在开着的状态）。
        'search': _doc?.findController.isActive ?? false,
        'wrap': _wrap,
        'readOnly': _readOnly,
        'smooth': _smooth,
        'smart': SmartCompletion.enabled.value,
        'smoothKeepIme': _smoothKeepIme,
        'ascii': _showAscii,
        'unicode': _showUnicode,
        'lint': _lintEnabled,
      };

  /// 当前不能执行的命令（置灰用）。做成 getter 而不是面板打开时算一次：
  /// 面板留着拨开关时，撤销/重做的可用性会变，算一次就永远是旧的。
  Set<String> get _disabledCommands {
    final out = <String>{};
    final doc = _doc;
    if (doc != null) {
      if (!doc.undoController.canUndo) out.add('undo');
      if (!doc.undoController.canRedo) out.add('redo');
      if (doc.bookmarks.isEmpty) {
        out.addAll(const ['bookmarks', 'clearBookmarks', 'nextBookmark']);
      }
    } else {
      out.addAll(const ['bookmarks', 'clearBookmarks', 'nextBookmark']);
    }
    if (_navIndex <= 0) out.add('navBack');
    if (_navIndex >= _navStack.length - 1) out.add('navForward');
    return out;
  }

  /// 面板是否已经打开（连点工具栏 ⌕ / 快捷键连按会叠出好几层一样的面板）。
  bool _paletteOpen = false;

  /// 语言选择器同样防连点。
  bool _langPickerOpen = false;

  Future<void> _showCommandPalette() async {
    if (_paletteOpen) return;
    _paletteOpen = true;
    try {
      await _showCommandPaletteBody();
    } finally {
      _paletteOpen = false;
    }
  }

  Future<void> _showCommandPaletteBody() async {
    final loc = localizations;
    final hidden = _prefs.hiddenMenu.toSet();
    final commands = <({String id, String label, String group, String keyword})>[];
    for (final item in kEditorMenuItems) {
      if (hidden.contains(item.id)) continue;
      // 检查类（语法检查/问题/控制台/规则）只对编程语言有意义，
      // 非编程语言下不列出来，免得拨了开关毫无反应。
      if (item.group == 'inspect' && !_programming) continue;
      // 同一类问题：这些命令依赖语法解析 / 可格式化 / 可预览，
      // 条件不满足时列出来就是「点了没反应」。
      if (!_programming && _programmingOnlyCommands.contains(item.id)) continue;
      if ((item.id == 'format' || item.id == 'formatSel') && !_canFormat) continue;
      if (item.id == 'preview' && !_canPreview) continue;
      commands.add((
        id: item.id,
        label: item.label(loc),
        group: item.group,
        keyword: item.aliases,
      ));
    }
    if (!mounted) return;
    if (commands.isEmpty) {
      // 全被隐藏时打开一个空面板只会让人懵。
      _toast(loc.editorNoAvailableCommand);
      return;
    }
    final recent = await _loadRecentCommands();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _CommandPaletteSheet(
        commands: commands,
        recent: recent,
        // 传回调而不是快照：面板留着拨开关时，勾选框要跟着变。
        isOn: (id) => _toggleStates[id],
        isDisabled: (id) => _disabledCommands.contains(id),
        onRun: (id) {
          // 一次性命令是「先关面板、下一帧再执行」，这中间用户可能已经把编辑器关了。
          if (!mounted) return;
          unawaited(_rememberCommand(id));
          _menuAction(id);
        },
        // 开关类命令执行完面板留着，可以连着拨几个；其余执行完就关。
        isKeep: (id) => _toggleCommands.contains(id),
        onClearRecent: _clearRecentCommands,
      ),
    );
  }

  /// 「文件」子菜单：另存为 / 重新加载 / 换行符 / 统计。
  Future<void> _showFileMenu() async {
    final size = MediaQuery.of(context).size;
    final chosen = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(size.width - 150, kToolbarHeight + 40, 20, 0),
      items: [
        PopupMenuItem(value: 'saveAs', child: Text(localizations.editorSaveAs)),
        PopupMenuItem(value: 'reload', child: Text(localizations.editorReloadFile)),
        PopupMenuItem(value: 'encodingReload', child: Text(localizations.editorEncodingReload)),
        PopupMenuItem(value: 'encodingSave', child: Text(localizations.editorEncodingSave)),
        PopupMenuItem(
          value: 'newline',
          child: Text('${localizations.editorNewline}: ${_newlineLabel()}'),
        ),
        PopupMenuItem(value: 'stats', child: Text(localizations.editorStats)),
      ],
    );
    switch (chosen) {
      case 'saveAs':
        await _download();
      case 'reload':
        await _reloadFile();
      case 'encodingReload':
        final enc1 = await showEncodingPicker(context, _encoding, title: localizations.editorEncoding);
        if (enc1 != null) await _reloadWithEncoding(enc1);
      case 'encodingSave':
        final enc2 = await showEncodingPicker(context, _encoding, title: localizations.editorEncoding);
        if (enc2 != null) await _saveWithEncoding(enc2);
      case 'newline':
        await _pickNewline();
      case 'stats':
        unawaited(_showStats());
    }
  }

  /// 「语法」子菜单：直接选当前文档的语言（也就是语法高亮）。
  Future<void> _showSyntaxMenu() async {
    final doc = _doc;
    if (doc == null) return;
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => SyntaxPickerDialog(
        items: _visibleLangs.map((l) => (l.label, l.mode as Object?)).toList(),
        current: doc.langLabel,
      ),
    );
    if (!mounted) return;
    // 「管理」里可能增删了自定义语法，统一刷新一次语言列表。
    setState(() {
      if (chosen != null) doc.langLabel = chosen;
    });
  }

  /// 从磁盘重新读一遍当前文件。
  Future<void> _reloadFile() async {
    final doc = _doc;
    final path = doc?.path;
    if (doc == null) return;
    if (path == null || path.isEmpty) {
      _toast(localizations.editorNoFilePath);
      return;
    }
    try {
      final bytes = await File(path).readAsBytes();
      final (text, detected) = await _decodeForOpen(bytes, prefer: doc.encodingName);
      if (!mounted) return;
      // 编码/换行符跟着磁盘上的实际内容走，否则重载之后一保存又会被改写。
      if (detected != null) doc.encodingName = detected.name;
      setState(() {
        doc.text = text;
        doc.newline = text.contains('\r\n') ? '\r\n' : (text.contains('\r') ? '\r' : '\n');
        _lastText = text;
        _dirty = false;
      });
      // 重载 = 回到磁盘内容，基线同步，改动标记清空。
      doc.diskBaseline = text;
      _refreshDecorations();
      // 重载后旧的撤销栈指向的是被丢弃的内容，撤销回去等于「变回旧版本」。
      doc.undoController.clear();
      // 正文可能整份换了位置，书签按上下文重新找。
      _remapBookmarksByHead(doc);
      _toast(localizations.editorReloadSuccess);
    } catch (e) {
      _toast('$e');
    }
  }

  /// 文本统计。
  Future<void> _showStats() async {
    final doc = _doc;
    if (doc == null) return;
    final text = doc.text;
    // 几 MB 的文本在主线程上扫全文 + utf8.encode 会卡一下，
    // 直接丢给 isolate 算（算完回来再弹窗）。
    final Map<String, int> stats = text.length > 500000
        ? await compute(_computeTextStats, text)
        : _computeTextStats(text);
    if (!mounted) return;
    final lines = stats['lines'] ?? 0;
    final chars = stats['chars'] ?? 0;
    final words = stats['words'] ?? 0;
    final bytes = stats['bytes'] ?? 0;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.editorStats),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statRow(localizations.editorLines, '$lines'),
            _statRow(localizations.editorChars, '$chars'),
            _statRow(localizations.editorWords, '$words'),
            _statRow(localizations.editorBytes, '$bytes'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(localizations.close),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// 打开编辑器设置页。
  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TextEditorSettingsPage(
          allLangs: _langs.map((l) => l.label).toList(),
        ),
      ),
    );
    // 设置页里的「语法文件管理」可能改了自定义语法。
    if (mounted) setState(() {});
  }

  /// 「语法」菜单里可见的语言（受「语法文件管理」的勾选控制）。
  List<_LangOption> get _visibleLangs {
    final enabled = _prefs.enabledLangs;
    if (enabled.isEmpty) return _langs;
    // 自定义语法由用户自己增删，不参与「显示勾选」的过滤。
    final list = _langs.where((l) => l.custom || enabled.contains(l.label)).toList();
    return list.isEmpty ? _langs : list;
  }

  void _setSmoothKeepIme(bool value) {
    setState(() => _smoothKeepIme = value);
    _saveSmoothKeepIme();
  }

  String _newlineLabel() {
    // 显示的是「这份文件」的换行符（保存时按它写回），不是全局偏好。
    final current = _newlineOf(_newlineCharsOf(_doc));
    switch (current) {
      case _Newline.lf:
        return 'LF (\\n)';
      case _Newline.crlf:
        return 'CRLF (\\r\\n)';
      case _Newline.cr:
        return 'CR (\\r)';
    }
  }

  String _retainModeLabel() {
    switch (_retainMode) {
      case _RetainMode.ask:
        return localizations.editorRetainAsk;
      case _RetainMode.always:
        return localizations.editorRetainAlways;
      case _RetainMode.never:
        return localizations.editorRetainNever;
    }
  }

  Future<void> _pickNewline() async {
    // 多文档时允许一次改完（同一个项目里通常是一套换行符）。
    var applyAll = false;
    final multi = _docs.docs.length > 1;
    final value = await showDialog<_Newline>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => SimpleDialog(
          title: Text(localizations.editorNewline),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Text(localizations.editorNewlineHint,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ),
            ..._Newline.values.map((e) => ListTile(
                  dense: true,
                  title: Text(_newlineText(e)),
                  trailing: e == _newlineOf(_newlineCharsOf(_doc))
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () => Navigator.pop(ctx, e),
                )),
            if (multi) ...[
              const Divider(height: 1),
              CheckboxListTile(
                dense: true,
                value: applyAll,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text(localizations.editorApplyToAll,
                    style: const TextStyle(fontSize: 13)),
                onChanged: (v) => setDlg(() => applyAll = v ?? false),
              ),
            ],
          ],
        ),
      ),
    );
    if (value == null || !mounted) return;
    // 改的是文档（保存时按它写回）；同时存成全局偏好，新建文件沿用它。
    final chars = _newlineChars(value);
    setState(() {
      _newline = value;
      if (applyAll) {
        for (final d in _docs.docs) {
          d.newline = chars;
        }
      } else {
        _doc?.newline = chars;
      }
    });
    await _saveNewline();
  }

  /// `_Newline` → 实际字符。
  static String _newlineChars(_Newline n) {
    switch (n) {
      case _Newline.lf:
        return '\n';
      case _Newline.crlf:
        return '\r\n';
      case _Newline.cr:
        return '\r';
    }
  }

  /// 实际字符 → `_Newline`。
  static _Newline _newlineOf(String nl) {
    if (nl == '\r\n') return _Newline.crlf;
    if (nl == '\r') return _Newline.cr;
    return _Newline.lf;
  }

  Future<void> _pickRetainMode() async {
    final value = await showDialog<_RetainMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(localizations.editorRetainPref),
        children: _RetainMode.values
            .map((e) => ListTile(
                  dense: true,
                  title: Text(_retainText(e)),
                  trailing: e == _retainMode ? const Icon(Icons.check, size: 18) : null,
                  onTap: () => Navigator.pop(ctx, e),
                ))
            .toList(),
      ),
    );
    if (value == null || !mounted) return;
    setState(() => _retainMode = value);
    await _saveRetainMode();
  }

  String _newlineText(_Newline e) {
    switch (e) {
      case _Newline.lf:
        return 'LF (\\n)';
      case _Newline.crlf:
        return 'CRLF (\\r\\n)';
      case _Newline.cr:
        return 'CR (\\r)';
    }
  }

  String _retainText(_RetainMode e) {
    switch (e) {
      case _RetainMode.ask:
        return localizations.editorRetainAsk;
      case _RetainMode.always:
        return localizations.editorRetainAlways;
      case _RetainMode.never:
        return localizations.editorRetainNever;
    }
  }

  /// 解绑当前文档的监听（退出 / 关闭前调用，避免对已 dispose 的对象再操作）。
  void _unbindActiveDoc() {
    _doc?.controller.removeListener(_onControllerChanged);
    _doc?.undoController.removeListener(_onUndoChanged);
    _doc = null;
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback? onTap, {Color? tint}) {
    // 固定 38×38：手指按得准，又不像默认 48 那么占地方。
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: onTap == null ? Colors.grey : tint),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
    );
  }

  /// 工具栏分组之间的竖线（VS Code 那套「文件 | 编辑 | 视图」的分隔）。
  Widget _toolbarSep() {
    // Wrap 里没有交叉轴拉伸，竖线必须自己给高度，否则高度 0 看不见。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
      child: Container(width: 1, height: 18, color: Theme.of(context).dividerColor),
    );
  }

  Widget _textView() {
    final controller = _doc?.controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final isDark = Theme.brightnessOf(context) == Brightness.dark;
    final baseTheme = isDark ? atomOneDarkTheme : atomOneLightTheme;
    final pageBg = Theme.of(context).colorScheme.surface;
    final editorTheme = isDark
        ? {
            ...baseTheme,
            'root': const TextStyle(color: Color(0xffabb2bf)).copyWith(backgroundColor: pageBg),
          }
        : baseTheme;

    final editor = CodeForge(
          // CodeForge 的 language / lineWrap 是 late final，切换得新 key 重建；
          // controller / findController / undoController 在文档对象持有，重建不丢数据。
          key: ValueKey('text-editor-${_doc!.id}-${_lang.label}-$_wrap-$_smooth-$_smoothKeepIme-'
              '${SmartCompletion.enabled.value}-${_prefs.fontSize}-${_prefs.lineHeight}-${_prefs.showGutter}-'
              '${_prefs.gutterDivider}-${_prefs.guideLines}-${_prefs.enableFolding}-${_prefs.tabSize}-'
              '${_prefs.useTabs}-$_readOnly'),
          controller: controller,
          findController: _doc!.findController,
          undoController: _doc!.undoController,
          // 流畅模式：关高亮 / 折叠 / 自动换行，换取超长文本下的流畅度。
          // 输入法候选建议是否一并关闭，由「保留输入法」开关决定（默认保留，不牺牲输入法）。
          lineWrap: _wrap && !_smooth,
          readOnly: _readOnly,
          language: _smooth ? null : _lang.mode,
          enableGuideLines: _prefs.guideLines,
          enableGutter: _prefs.showGutter,
          enableGutterDivider: _prefs.gutterDivider,
          tabSize: _prefs.tabSize,
          useSpaceAsTab: !_prefs.useTabs,
          enableFolding: !_smooth && _prefs.enableFolding,
          // 本地代码补全（文档词 + 语言关键字）：光标上方弹出候选，选中才插入。
          // 流畅模式关闭，换取超长文本下的流畅度。
          enableLocalSuggestions: SmartCompletion.enabled.value && !_smooth,
          enableKeyboardSuggestions: !_smooth || _smoothKeepIme,
          editorTheme: editorTheme,
          textStyle: TextStyle(fontSize: _prefs.fontSize, height: _prefs.lineHeight),
          selectionStyle: CodeSelectionStyle(cursorColor: Theme.of(context).colorScheme.primary),
          invisibleChars: _invisibleCharsStyle,
          autoIndent: _prefs.autoIndent,
          enterSuggestion: _prefs.enterSuggestion,
          suggestionMaxHeight: _prefs.suggestionMaxHeight,
          customContextMenuItems: _floatMenuItems(),
          verticalScrollController: _vScroll,
          onGutterLineLongPress: _handleGutterLongPress,
        );

    Widget body = editor;
    if (_minimapOn) {
      body = Row(children: [
        Expanded(child: editor),
        SizedBox(width: 56, child: _minimap(controller.text)),
      ]);
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor)),
        child: Stack(children: [
          Positioned.fill(child: body),
          // 粘性滚动钉在最上层：覆盖式，和 VS Code 一样让正文从下面穿过去。
          if (_stickyOn) Positioned(left: 0, right: _minimapOn ? 56 : 0, top: 0, child: _stickyBar()),
        ]),
      ),
    );
  }
}


/// 右滑露出操作的列表项（用于文档列表的「置顶 / 关闭」）。
/// 编辑器右侧的问题分布条：把每条问题的行号按总行数换算成纵向位置画一小段。
///
/// VS 是在滚动条上画，这里滚动条归内核管，就贴在它左侧自己画一条——
/// 效果一样：扫一眼就知道错误是集中在开头还是尾部。
/// 命令面板：输入两个字就定位到任何菜单项。
///
/// 列表分两段：「最近用过」在前（8 条，跨会话保留），下面才是全部。
/// 47 项平铺时，常用的那三五个每次都得重新读一遍列表。
class _CommandPaletteSheet extends StatefulWidget {
  final List<({String id, String label, String group, String keyword})> commands;
  final List<String> recent;

  /// 命令当前是否处于「开着」的状态；null = 这条不是开关类，不显示状态。
  ///
  /// 现取现用（回调而不是快照），拨完开关立刻能看到勾变化。
  final bool? Function(String id) isOn;

  /// 执行一条命令。
  final void Function(String id) onRun;

  /// 这条命令执行后要不要把面板留着（开关类命令 = true）。
  final bool Function(String id) isKeep;

  /// 当前不能执行的命令（没有撤销历史、没有书签…），显示成灰色。
  final bool Function(String id) isDisabled;

  /// 长按「最近使用」标题 → 清空这份记录。
  final Future<void> Function()? onClearRecent;

  const _CommandPaletteSheet({
    required this.commands,
    required this.onRun,
    required this.isKeep,
    required this.isOn,
    required this.isDisabled,
    this.onClearRecent,
    this.recent = const <String>[],
  });

  @override
  State<_CommandPaletteSheet> createState() => _CommandPaletteSheetState();
}

class _CommandPaletteSheetState extends State<_CommandPaletteSheet> {
  String _query = '';

  /// 刚清空过「最近使用」（不再显示这一段）。
  bool _recentCleared = false;

  void _runCommand(String id) {
    if (widget.isDisabled(id)) return;
    if (widget.isKeep(id)) {
      widget.onRun(id);
      setState(() {});
      return;
    }
    // 先关面板、下一帧再执行：这里有些命令（文件▸/语法▸/行操作▸/大小写▸
    // 以及各种 sheet）自己会 push 一个 route，面板还在栈上时执行，
    // 它们收尾时的 pop 会把刚弹出的子菜单一起弹掉 —— 表现为「点了闪一下就没了」。
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onRun(id));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase();
    final matched = q.isEmpty
        ? widget.commands
        : widget.commands
            .where((c) => c.label.toLowerCase().contains(q) || c.keyword.toLowerCase().contains(q))
            .toList(growable: false);

    // 空查询时：最近用过提到最前，其余按工具栏那五个分类分段。
    // 47 项平铺成一长条时，找一个不常用的命令要滑很久。
    final rows = <Object>[];
    // 已经在「最近使用」里出现过的命令不再在下面分组里重复列一遍。
    final shown = <String>{};
    if (q.isEmpty) {
      if (!_recentCleared && widget.recent.isNotEmpty) {
        final byId = {for (final c in widget.commands) c.id: c};
        final recentCmds = <({String id, String label, String group, String keyword})>[];
        for (final id in widget.recent) {
          final cmd = byId[id];
          if (cmd != null) recentCmds.add(cmd);
        }
        if (recentCmds.isNotEmpty) {
          rows.add(_PaletteHeader(loc.editorRecentCommands,
              onLongPress: widget.onClearRecent == null ? null : () => widget.onClearRecent!()));
          rows.addAll(recentCmds);
          shown.addAll(recentCmds.map((c) => c.id));
        }
      }
      final groupTitles = <String, String>{
        'file': loc.editorMenuFile,
        'edit': loc.editorMenuEdit,
        'code': loc.editorMenuCode,
        'view': loc.editorMenuView,
        'inspect': loc.editorMenuInspect,
      };
      for (final g in const ['file', 'edit', 'code', 'view', 'inspect']) {
        final items = matched.where((c) => c.group == g && !shown.contains(c.id)).toList(growable: false);
        if (items.isEmpty) continue;
        rows.add(_PaletteHeader(groupTitles[g]!));
        rows.addAll(items);
      }
    } else {
      rows.addAll(matched);
    }

    // 横屏 + 键盘时 0.6 屏高可能只剩一百多 dp，再让一次位。
    final media = MediaQuery.of(context);
    final available = media.size.height - media.viewInsets.bottom - 120;
    final maxHeight = (media.size.height * 0.6).clamp(140.0, available < 140 ? 140.0 : available);

    return Padding(
      // 键盘弹起来时要让位，否则列表被压到看不见。
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              // 回车执行第一条匹配（VS Code 的行为）。手机上输入法右下角就是回车，
              // 打字 → 回车比「打字 → 手指移到列表 → 点」快得多。
              onSubmitted: (_) {
                if (matched.isEmpty) return;
                _runCommand(matched.first.id);
              },
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.manage_search, size: 18),
                hintText: loc.editorCommandPaletteHint,
                hintStyle: const TextStyle(fontSize: 12.5),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(loc.emptyData,
                        style: TextStyle(fontSize: 12, color: theme.disabledColor)),
                  )
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final row = rows[i];
                      if (row is _PaletteHeader) {
                        return GestureDetector(
                          // 长按「最近使用」→ 清空记录（VS Code 没有，但手机上没有别的入口）。
                          onLongPress: row.onLongPress == null
                              ? null
                              : () {
                                  row.onLongPress!();
                                  setState(() => _recentCleared = true);
                                },
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                            child: Text(row.text,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600)),
                          ),
                        );
                      }
                      final cmd = row as ({String id, String label, String group, String keyword});
                      // 开关类命令右侧显示当前状态，不然「换行/只读/平滑模式」
                      // 拨了之后看不出是开还是关，只能靠编辑区反推。
                      final state = widget.isOn(cmd.id);
                      final isToggle = widget.isKeep(cmd.id);
                      final usable = !widget.isDisabled(cmd.id);
                      return ListTile(
                        dense: true,
                        enabled: usable,
                        leading: Icon(menuIconOf(cmd.id), size: 17),
                        title: Text(cmd.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5)),
                        trailing: state == null
                            ? null
                            : isToggle
                                ? Icon(
                                    state
                                        ? Icons.check_box_outlined
                                        : Icons.check_box_outline_blank,
                                    size: 17,
                                    color: state
                                        ? theme.colorScheme.primary
                                        : theme.disabledColor,
                                  )
                                // 不是开关类但当前「生效中」（如查找面板正开着）：
                                // 用实心小圆点，不用勾选框 —— 它点了不是切换。
                                : (state
                                    ? Icon(Icons.circle,
                                        size: 7, color: theme.colorScheme.primary)
                                    : null),
                        onTap: () => _runCommand(cmd.id),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

/// 命令面板里的小标题。
class _PaletteHeader {
  final String text;

  /// 长按标题时的动作（目前只有「最近使用」用它清空记录）。
  final VoidCallback? onLongPress;

  const _PaletteHeader(this.text, {this.onLongPress});
}

/// 语言选择的底部弹层：搜索 + 常用语言置顶。
///
/// 内置加自定义语法将近两百个，没有搜索的列表在手机上等于「滑到手指发麻」；
/// 固定高度的居中对话框在小屏上还会顶到状态栏，所以这里用半屏弹层。
class _LanguagePickerSheet extends StatefulWidget {
  final List<_LangOption> langs;
  final String current;

  /// 最近用过的语言（排在最前）。
  final List<String> recent;

  const _LanguagePickerSheet({
    required this.langs,
    required this.current,
    this.recent = const <String>[],
  });

  @override
  State<_LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<_LanguagePickerSheet> {
  /// 常写的那几个排前面（没搜的时候不用滑）。
  static const List<String> _common = <String>[
    'Plain Text',
    'JSON',
    'XML / HTML',
    'Java',
    'C#',
    'C++',
    'Python',
    'JavaScript',
    'TypeScript',
    'Go',
    'Dart',
    'SQL',
    'YAML',
    'Bash',
    'Markdown',
    'HTTP',
    'CSS',
  ];

  String _query = '';

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  String _labelOf(_LangOption option) =>
      option.label == 'Plain Text' ? localizations.editorPlainText : option.label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query.trim().toLowerCase();
    final all = widget.langs;
    final matched = query.isEmpty
        ? all
        : all.where((l) => l.label.toLowerCase().contains(query)).toList(growable: false);
    // 空查询时把常用语言提到最前（保持原顺序）。
    // 分三段并给出标题：只靠排序的话，用户看不出「为什么这两项在最前面」。
    final rows = <Object>[];
    if (query.isEmpty) {
      final recent = <_LangOption>[];
      final common = <_LangOption>[];
      final rest = <_LangOption>[];
      for (final option in matched) {
        if (widget.recent.contains(option.label)) {
          recent.add(option);
        } else if (_common.contains(option.label)) {
          common.add(option);
        } else {
          rest.add(option);
        }
      }
      // 最近用过的按「最近」排序，常用的按固定表排序。
      recent.sort((a, b) =>
          widget.recent.indexOf(a.label).compareTo(widget.recent.indexOf(b.label)));
      common.sort((a, b) => _common.indexOf(a.label).compareTo(_common.indexOf(b.label)));
      if (recent.isNotEmpty) {
        rows.add(_PaletteHeader(localizations.editorLangRecent));
        rows.addAll(recent);
      }
      if (common.isNotEmpty) {
        rows.add(_PaletteHeader(localizations.editorLangCommon));
        rows.addAll(common);
      }
      if (rest.isNotEmpty) {
        rows.add(_PaletteHeader(localizations.editorLangAll));
        rows.addAll(rest);
      }
    } else {
      rows.addAll(matched);
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            autofocus: false,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: localizations.search,
              hintStyle: const TextStyle(fontSize: 12.5),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(localizations.emptyData,
                      style: TextStyle(fontSize: 12, color: theme.disabledColor)),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (ctx, i) {
                    final row = rows[i];
                    if (row is _PaletteHeader) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                        child: Text(row.text,
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600)),
                      );
                    }
                    final option = row as _LangOption;
                    return ListTile(
                      dense: true,
                      selected: option.label == widget.current,
                      title: Text(_labelOf(option), style: const TextStyle(fontSize: 13)),
                      onTap: () => Navigator.pop(ctx, option),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class _RulerPainter extends CustomPainter {
  final List<LintDiagnostic> issues;
  final int totalLines;

  /// 书签所在的行（0 基）。画成琥珀色小段，和错误色区分开。
  final List<int> bookmarks;

  _RulerPainter({required this.issues, required this.totalLines, this.bookmarks = const <int>[]});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0 || totalLines <= 0) return;
    // 控件比色带宽（触摸区 14dp，色带 3dp），统一右对齐，色带贴着滚动条。
    const w = 3.0;
    final left = size.width - w;
    final paint = Paint();
    // 先画书签（窄一点、偏左），错误再盖上去：同一行既有错又有书签时，错的优先。
    for (final line in bookmarks) {
      final ratio = line / totalLines;
      final y = (ratio * size.height).clamp(0.0, size.height - 3);
      paint.color = Colors.amber;
      canvas.drawRect(Rect.fromLTWH(left, y, w * 0.6, 3), paint);
    }
    for (final d in issues) {
      final ratio = (d.line - 1) / totalLines;
      final y = (ratio * size.height).clamp(0.0, size.height - 2);
      paint.color = d.severity == LintSeverity.error
          ? Colors.red
          : d.severity == LintSeverity.warning
              ? Colors.orange
              : Colors.blueGrey;
      canvas.drawRect(Rect.fromLTWH(left, y, w, 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.totalLines != totalLines ||
      old.issues.length != issues.length ||
      !identical(old.issues, issues) ||
      old.bookmarks.length != bookmarks.length ||
      !identical(old.bookmarks, bookmarks);
}

class _SwipeAction {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _SwipeAction({required this.icon, required this.tooltip, required this.color, required this.onTap});
}

class _SwipeTile extends StatefulWidget {
  final Widget child;
  final List<_SwipeAction> actions;
  final VoidCallback onTap;

  const _SwipeTile({super.key, required this.child, required this.actions, required this.onTap});

  @override
  State<_SwipeTile> createState() => _SwipeTileState();
}

class _SwipeTileState extends State<_SwipeTile> with SingleTickerProviderStateMixin {
  static const double _actionWidth = 76;

  late final AnimationController _ctrl;
  bool _open = false;

  double get _maxOffset => widget.actions.length * _actionWidth;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_maxOffset <= 0) return;
    final next = (_ctrl.value * _maxOffset + d.delta.dx).clamp(0.0, _maxOffset);
    _ctrl.value = next / _maxOffset;
    _open = _ctrl.value > 0;
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    final open = _ctrl.value > 0.5 || velocity > 400;
    _open = open;
    _ctrl.animateTo(open ? 1 : 0);
  }

  void _close() {
    if (!_open) return;
    _open = false;
    _ctrl.animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final offset = _ctrl.value * _maxOffset;
        return Stack(children: [
          // 露出的操作区（在左侧）
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: widget.actions.map((a) {
                return SizedBox(
                  width: _actionWidth,
                  child: Material(
                    color: a.color.withValues(alpha: 0.12),
                    child: InkWell(
                      onTap: () {
                        _close();
                        a.onTap();
                      },
                      child: Tooltip(
                        message: a.tooltip,
                        child: Center(child: Icon(a.icon, size: 19, color: a.color)),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Transform.translate(
            offset: Offset(offset, 0),
            child: GestureDetector(
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: InkWell(
                  onTap: _open ? _close : widget.onTap,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

/// 编辑器底部状态栏（行:列 / 选中 / 字符数 / 缩进 / 语言）。
class _EditorStatusBar extends StatefulWidget {
  final CodeForgeController controller;
  final String language;
  final String indent;

  /// 有未保存修改的文档份数（>1 时状态栏显示 `•N`）。
  final int dirtyCount;

  /// 当前诊断（VS 状态栏左侧那组「错误 N / 警告 M」）。
  final LintReport? report;

  /// 点计数 → 打开问题列表。
  final VoidCallback? onTapIssues;

  /// 点语言 / 缩进段（VS 状态栏这两处都能点）。
  final VoidCallback? onTapLanguage;
  final VoidCallback? onTapIndent;

  /// 编码名与换行符（VS 状态栏右半边也有这两段，点一下就能改）。
  final String? encoding;
  final String? newline;
  final VoidCallback? onTapEncoding;
  final VoidCallback? onTapNewline;

  const _EditorStatusBar({
    required this.controller,
    required this.language,
    required this.indent,
    this.dirtyCount = 0,
    this.report,
    this.onTapIssues,
    this.onTapLanguage,
    this.onTapIndent,
    this.encoding,
    this.newline,
    this.onTapEncoding,
    this.onTapNewline,
  });

  @override
  State<_EditorStatusBar> createState() => _EditorStatusBarState();
}

class _EditorStatusBarState extends State<_EditorStatusBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant _EditorStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  // 行列计算：以前每次重建都从头扫两遍全文（1MB 文件里每按一个键就是 2ms），
  // 现在按「上次位置」增量数换行；文本对象变了才从头算一次。
  String? _cacheText;
  int _cacheOffset = -1;
  int _cacheLine = 0;
  int _cacheLineStart = 0;

  ({int line, int column}) _position(String text, int offset) {
    final target = offset < 0 ? 0 : (offset > text.length ? text.length : offset);
    if (!identical(_cacheText, text)) {
      _cacheText = text;
      _cacheOffset = -1;
    }
    if (_cacheOffset >= 0 && target >= _cacheOffset) {
      var line = _cacheLine;
      var lineStart = _cacheLineStart;
      for (var i = _cacheOffset; i < target; i++) {
        if (text.codeUnitAt(i) == 10) {
          line++;
          lineStart = i + 1;
        }
      }
      _cacheOffset = target;
      _cacheLine = line;
      _cacheLineStart = lineStart;
      return (line: line, column: target - lineStart + 1);
    }
    var line = 0;
    var lineStart = 0;
    for (var i = 0; i < target; i++) {
      if (text.codeUnitAt(i) == 10) {
        line++;
        lineStart = i + 1;
      }
    }
    _cacheOffset = target;
    _cacheLine = line;
    _cacheLineStart = lineStart;
    return (line: line, column: target - lineStart + 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.controller.text;
    final offset = widget.controller.selection.baseOffset;
    final safe = offset < 0 ? 0 : (offset > text.length ? text.length : offset);
    final pos = _position(text, safe);
    final line = pos.line;
    final column = pos.column;
    final selection = widget.controller.selection;
    final selected = selection.isValid && !selection.isCollapsed
        ? (selection.end - selection.start).abs()
        : 0;
    final color = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85);
    final style = TextStyle(fontSize: 10.5, color: color);
    // 手机窄屏（360dp）装不下这么多项：行号 + 选中数 + ❌⚠ + 未保存 + 字符数 +
    // 缩进 + 语言名，「Objective-C++」这种长语言名一进来就 Row overflow（黄黑条）。
    // 处理：语言名允许收缩成省略号，窄屏再先把「缩进」收掉。
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 380;
        return Container(
          height: 21,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.06),
            border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
          ),
          child: Row(children: [
            Text('L${line + 1}:$column', style: style),
            if (selected > 0) ...[
              const SizedBox(width: 6),
              Text('($selected)', style: TextStyle(fontSize: 10.5, color: theme.colorScheme.primary)),
            ],
            if (widget.controller.hasMultiCursors) ...[
              const SizedBox(width: 6),
              Text('${widget.controller.multiCursors.length + 1} ⌖',
                  style: TextStyle(fontSize: 10.5, color: theme.colorScheme.tertiary)),
            ],
            const Spacer(),
            if (widget.report != null) ...[
              InkWell(
                onTap: widget.onTapIssues,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.cancel,
                        size: 10.5,
                        color: (widget.report!.errorCount) > 0 ? Colors.red : color),
                    const SizedBox(width: 2),
                    Text('${widget.report!.errorCount}', style: style),
                    const SizedBox(width: 8),
                    Icon(Icons.warning_amber_rounded,
                        size: 11.5,
                        color: (widget.report!.warningCount) > 0 ? Colors.orange : color),
                    const SizedBox(width: 2),
                    Text('${widget.report!.warningCount}', style: style),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
            ],
            // 未保存份数（多文档时才知道「还有几份没写回磁盘」）。
            if (widget.dirtyCount > 0) ...[
              Icon(Icons.circle, size: 6, color: color),
              const SizedBox(width: 3),
              Text('${widget.dirtyCount}', style: style),
              const SizedBox(width: 8),
            ],
            Text('${text.length}', style: style),
            const SizedBox(width: 10),
            // 窄屏不直接收掉，缩成 `S4` / `T4`：值还是看一眼就知道，点进去还能改。
            InkWell(
              onTap: widget.onTapIndent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  compact
                      ? widget.indent.replaceFirst('Space:', 'S').replaceFirst('Tab:', 'T')
                      : widget.indent,
                  style: style,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // 换行符：LF / CRLF / CR，点一下换（VS 状态栏的换行段）。
            if (widget.newline != null)
              InkWell(
                onTap: widget.onTapNewline,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(widget.newline!, style: style),
                ),
              ),
            const SizedBox(width: 6),
            // 编码：窄屏（360dp）放不下，只在宽屏显示，编码入口在「文件」菜单里。
            if (widget.encoding != null && !compact)
              InkWell(
                onTap: widget.onTapEncoding,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(widget.encoding!, style: style),
                ),
              ),
            const SizedBox(width: 6),
            // 语言名最后才收缩：点它换语法，是状态栏上最常点的东西。
            Flexible(
              child: InkWell(
                onTap: widget.onTapLanguage,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    widget.language,
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}


/// 参数签名提示条：显示「函数名(参数列表)」并高亮当前参数。
///
/// 自己监听 controller —— 光标一动就更新，但只重建这一条，不带动整个编辑页。
class _SignatureBar extends StatefulWidget {
  final CodeForgeController controller;
  final ({String name, List<String> params, int active})? Function() resolve;

  const _SignatureBar({required this.controller, required this.resolve});

  @override
  State<_SignatureBar> createState() => _SignatureBarState();
}

class _SignatureBarState extends State<_SignatureBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant _SignatureBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hint = widget.resolve();
    if (hint == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final spans = <InlineSpan>[];
    for (var i = 0; i < hint.params.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: ', '));
      final active = i == hint.active;
      spans.add(TextSpan(
        text: hint.params[i],
        style: TextStyle(
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: active ? theme.colorScheme.primary : theme.textTheme.bodyMedium?.color,
          backgroundColor:
              active ? theme.colorScheme.primary.withValues(alpha: 0.10) : null,
        ),
      ));
    }
    const mono = TextStyle(fontSize: 11.5, fontFamily: 'monospace');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: Row(children: [
        Icon(Icons.functions, size: 13, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text('${hint.name}(', style: mono),
        Expanded(
          child: Text.rich(
            TextSpan(children: spans),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono,
          ),
        ),
        const Text(')', style: mono),
        if (hint.params.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(
            '${hint.active + 1}/${hint.params.length}',
            style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ]),
    );
  }
}

/// 文本统计（行 / 字符 / 词 / 字节）。
///
/// 抽成顶层函数是为了能丢进 isolate：几 MB 的文本在主线程上扫全文 +
/// `utf8.encode` 会明显卡顿。
Map<String, int> _computeTextStats(String text) {
  final lines = text.isEmpty ? 0 : '\n'.allMatches(text).length + 1;
  final words = RegExp(r'\S+').allMatches(text).length;
  final bytes = utf8.encode(text).length;
  return {'lines': lines, 'chars': text.length, 'words': words, 'bytes': bytes};
}

/// 压缩（按语言）的 isolate 入口：参数是 `[语言 label, 正文]`。
String? _minifyInIsolate(List<String> args) => CodeMinifier.minify(args[0], args[1]);

/// 激进压缩（JS 编译器前端）的 isolate 入口。
String? _compilerMinifyInIsolate(String text) => JsCompiler.minify(text);

/// 格式化（JSON / XML / CSS / 大括号重排）的 isolate 入口。
/// 参数：`[FormatKind.index, 正文, tabSize, useTabs]`；JS 美化是 async，不走这里。
String? _formatInIsolate(List<Object> args) {
  final kind = FormatKind.values[args[0] as int];
  final text = args[1] as String;
  final tabSize = args[2] as int;
  final useTabs = args[3] as bool;
  switch (kind) {
    case FormatKind.json:
      return JSON.pretty(text);
    case FormatKind.xml:
      // XML 解析会整棵树建在内存里（比原文大好几倍）：元素特别多时先劝退，
      // 抛出去的异常主线程会转成提示。
      if ('<'.allMatches(text).length > 200000) {
        throw StateError('too many elements to format');
      }
      return XmlDocument.parse(text).toXmlString(pretty: true, indent: '  ');
    case FormatKind.css:
      return CSS.pretty(text);
    case FormatKind.brace:
      return reindentBraces(text, tabSize: tabSize, useTabs: useTabs);
    case FormatKind.js:
    case FormatKind.none:
      return null;
  }
}

/// 「工作区查找引用」的一条命中。
/// 「跨文件操作」（重命名 / 多文件查找）的一个候选文件。
///
/// [doc] 非空表示这个文件正开在编辑器里：改它走 controller（可撤销、不落盘）；
/// 为空表示只有磁盘上的副本，改它就直接写盘并记备份。
/// 「多文件查找」的一条命中。
class _FileSearchHit {
  final String label;
  final String? path;
  final int line;
  final int offset;
  final int matchLength;
  final String text;
  final bool isCurrent;

  const _FileSearchHit({
    required this.label,
    required this.offset,
    required this.line,
    required this.matchLength,
    required this.text,
    this.path,
    this.isCurrent = false,
  });
}

class _ScopeFile {
  final String label;
  final String? path;
  final EditorDocument? doc;
  final String content;
  int hits = 0;

  _ScopeFile({
    required this.label,
    required this.content,
    this.path,
    this.doc,
  });
}

class _RefHit {
  /// 文件路径；仅存在于编辑器内存、尚未落盘的文档为 null。
  final String? path;

  /// 显示用的文件名。
  final String label;

  /// 1-based 行号。
  final int line;

  /// 该行内容（已 trim）。
  final String text;

  /// 命中处的字符偏移（用于跳转与选中）。
  final int offset;

  /// 是否是该符号的声明（否则只是引用）。
  final bool isDefinition;

  /// 是否属于当前正在编辑的文档（决定要不要给「速览」按钮）。
  final bool isCurrent;

  const _RefHit({
    required this.path,
    required this.label,
    required this.line,
    required this.text,
    required this.offset,
    required this.isDefinition,
    required this.isCurrent,
  });
}

/// 右侧缩略图（minimap）的画笔：把整篇按行压成竖条。
///
/// 两个上限：行数 > 5 万或文本 > 20 万字符时只画视口框——那种规模逐行画
/// 不比不画更清楚，还会吃掉滚动帧率。
class _MiniMapPainter extends CustomPainter {
  _MiniMapPainter({
    required this.text,
    required this.lineH,
    required this.offset,
    required this.viewportH,
    required this.fg,
    required this.accent,
  });

  final String text;
  final double lineH;
  final double offset;
  final double viewportH;
  final Color fg;
  final Color accent;

  int get _lines {
    var n = 1;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) n++;
    }
    return n;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0 || size.width <= 0) return;
    final total = _lines;
    final totalPx = lineH * total;
    if (totalPx <= 0) return;

    if (total <= 50000 && text.length <= 200000) {
      // 每个像素行只记「这一格里最长的非空行」，避免逐行画几万个矩形。
      final rows = size.height.ceil() + 1;
      final widths = List<double>.filled(rows, 0);
      var line = 0;
      var start = 0;
      var maxLen = 1.0;
      for (var i = 0; i <= text.length; i++) {
        if (i == text.length || text.codeUnitAt(i) == 10) {
          final len = (i - start).toDouble();
          if (len > 0) {
            var y = (line / total * size.height).floor();
            if (y < 0) y = 0;
            if (y < rows && len > widths[y]) {
              widths[y] = len;
              if (len > maxLen) maxLen = len;
            }
          }
          line++;
          start = i + 1;
        }
      }
      final paint = Paint()..color = fg.withValues(alpha: 0.42);
      final usable = size.width - 4;
      for (var y = 0; y < rows && y < size.height; y++) {
        final w = widths[y];
        if (w <= 0) continue;
        // 长行按比例压缩：一行 300 字符不该把整条涂满。
        final ratio = w <= 40 ? w / 40 : (0.55 + 0.45 * (w / maxLen));
        canvas.drawRect(
          Rect.fromLTWH(2, y.toDouble(), (usable * ratio).clamp(1.0, usable).toDouble(), 1),
          paint,
        );
      }
    }

    // 视口框：不管内容画没画，位置指示都要有。
    final top = (offset / totalPx * size.height).clamp(0.0, size.height).toDouble();
    final room = (size.height - top).clamp(0.0, size.height).toDouble();
    final boxH = (viewportH / totalPx * size.height).clamp(room >= 6 ? 6.0 : room, room).toDouble();
    final box = Rect.fromLTWH(0, top, size.width, boxH);
    canvas.drawRect(box, Paint()..color = accent.withValues(alpha: 0.14));
    canvas.drawRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = accent.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter old) =>
      !identical(old.text, text) ||
      old.lineH != lineH ||
      old.offset != offset ||
      old.viewportH != viewportH ||
      old.fg != fg ||
      old.accent != accent;
}

/// 一个标签名在文本里的位置。只用于「重命名配对标签」，不需要属性解析。
class _TagRef {
  final String name;
  final int nameStart;
  final int nameEnd;
  final bool closing;

  /// `<br/>` 这类没有配对标签。
  final bool selfClosing;

  const _TagRef({
    required this.name,
    required this.nameStart,
    required this.nameEnd,
    required this.closing,
    required this.selfClosing,
  });
}
