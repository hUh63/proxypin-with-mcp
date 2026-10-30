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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/component/search/finder.dart';
import 'package:proxypin/ui/component/snippet_bar.dart';
import 'package:proxypin/utils/code_minifier.dart';
import 'package:proxypin/utils/js_compiler.dart';
import 'package:proxypin/utils/css_formatter.dart';
import 'package:proxypin/network/util/js_deobfuscator.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/code_keywords.dart';
import 'package:proxypin/utils/code_lint.dart';
import 'package:proxypin/utils/code_lint_prefs.dart';
import 'package:proxypin/ui/component/lint_rules_dialog.dart';
import 'package:proxypin/ui/toolbox/editor_console.dart';
import 'package:proxypin/utils/custom_lang.dart';
import 'package:proxypin/utils/lang_meta.dart';
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
import 'package:proxypin/ui/toolbox/media_preview.dart';
import 'package:proxypin/ui/toolbox/file_preview.dart';

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
  int _issueCursor = -1;
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
  final List<int> _navStack = <int>[];
  int _navIndex = -1;
  int _lastNavOffset = -1;
  Timer? _navTimer;
  bool _suppressNav = false;

  // 读写磁盘文件时使用的编码（跟随全局偏好）。
  EditorEncoding get _encoding => kEncodings.firstWhere(
        (e) => e.name == _prefs.encodingName,
        orElse: () => defaultEncoding,
      );

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
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _fileWatchTimer?.cancel();
    _lintTimer?.cancel();
    _rulerTimer?.cancel();
    _docScroll.dispose();
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
    // F8 / Shift+F8：跳到下一处 / 上一处问题（桌面全平台）。
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f8) {
      if ((_lint?.diagnostics.isNotEmpty ?? false)) {
        _jumpIssue(!HardwareKeyboard.instance.isShiftPressed);
        return true;
      }
      return false;
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
    if (!mounted) return;
    setState(() {
      if (raw != null && raw >= 0 && raw < _RetainMode.values.length) {
        _retainMode = _RetainMode.values[raw];
      }
      if (nl != null) {
        _newline = _Newline.values.firstWhere((e) => e.name == nl, orElse: () => _Newline.lf);
      }
      if (keepIme != null) _smoothKeepIme = keepIme;
    });
  }

  Future<void> _saveRetainMode() async {
    await SharedPreferencesAsync().setInt(_kPrefRetainMode, _retainMode.index);
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
      _activate(_docs.create(name: localizations.editorUntitled));
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
      _issueCursor = -1;
      // 换文档后波浪线要按新文档重算。
      _diagReport = null;
      _diagLines = const <DiagnosticLine>[];
      // 多选是「针对某几个位置」的状态，换文档就失效了。
      _multiSel.clear();
      _multiWord = '';
    });

    doc.controller.addListener(_onControllerChanged);
    doc.undoController.addListener(_onUndoChanged);
    _restartFileWatch();
    // 切回旧文档：直接恢复上次的诊断标记，避免「重新检查」造成的闪动。
    if (doc.lint != null) {
      _refreshDecorations();
    } else {
      _clearLintDecorations();
      _scheduleLint();
    }
    // 当前行高亮跟着光标走，切文档后要先算一次（缓存刚被清成 -1）。
    _syncCaretLine();
    _refreshExtraHighlights();
    _refreshSymbolCache();
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

  void _onUndoChanged() {
    if (mounted) setState(() {});
  }

  void _onControllerChanged() {
    final text = _doc?.text ?? '';
    final changed = text != _lastText;
    if (changed) {
      // 书签跟着代码走：按「这次改了哪一段」平移，别让它漂到隔壁行。
      final bookmarks = _doc?.bookmarks;
      if (bookmarks != null && bookmarks.isNotEmpty) {
        final delta = _diffSpan(_lastText, text);
        if (delta != null) {
          final moved = <int>{};
          for (final offset in bookmarks) {
            if (offset <= delta.start) {
              moved.add(offset);
            } else if (offset >= delta.start + delta.removed) {
              moved.add(offset + delta.inserted - delta.removed);
            } else {
              // 落在被删掉的那段里：收到改动起点，别丢。
              moved.add(delta.start);
            }
          }
          bookmarks
            ..clear()
            ..addAll(moved);
        }
      }
      _rememberEdit(_doc?.controller.selection.extentOffset ?? 0);
      _lastText = text;
      if (!_dirty) setState(() => _dirty = true);
      // 只有内容变化才重跑检查：光标移动、选区变化不触发。
      _scheduleLint();
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
    _issueCursor = -1;
    _lastIssueOffset = -1;
    _refreshSymbolCache();
    setState(() => _lintChecking = false);
    // 换完装饰会 notifyListeners，必须放在 setState 之后、且不能再次触发检查。
    _refreshDecorations();
  }

  void _openConsole(EditorConsoleTab tab) {
    // 非编程语言只能看问题，不能进控制台。
    final target = _programming ? tab : EditorConsoleTab.problems;
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
    _issueCursor = list.indexOf(pick);
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

  Widget _lintButton(Color color) {
    final report = _lint;
    final count = report?.diagnostics.length ?? 0;
    final worst = report?.worst;
    final tint = worst == LintSeverity.error
        ? Colors.red
        : worst == LintSeverity.warning
            ? Colors.orange
            : worst == LintSeverity.info
                ? Colors.blueGrey
                : null;
    return InkWell(
      onTap: () => _openConsole(EditorConsoleTab.problems),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(count > 0 ? Icons.report_problem_outlined : Icons.check_circle_outline,
              size: 16, color: tint ?? color),
          if (count > 0) ...[
            const SizedBox(width: 2),
            Text('$count', style: TextStyle(fontSize: 10.5, color: tint ?? color)),
          ],
        ]),
      ),
    );
  }

  // ---------- 光标导航历史 ----------

  void _pushNav(int offset) {
    if (_suppressNav) return;
    if (_navIndex >= 0 && _navIndex < _navStack.length && _navStack[_navIndex] == offset) return;
    if (_navIndex + 1 < _navStack.length) {
      _navStack.removeRange(_navIndex + 1, _navStack.length);
    }
    _navStack.add(offset);
    if (_navStack.length > 100) _navStack.removeAt(0);
    _navIndex = _navStack.length - 1;
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

  Future<void> _paste() async {
    final controller = _controller;
    if (controller == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final clip = data?.text ?? '';
    if (clip.isEmpty) return;
    final text = controller.text;
    final sel = controller.selection;
    if (sel.isValid && !sel.isCollapsed) {
      controller.text = text.replaceRange(sel.start, sel.end, clip);
      controller.selection = TextSelection.collapsed(offset: sel.start + clip.length);
    } else {
      final offset = sel.isValid ? sel.start : text.length;
      controller.text = text.replaceRange(offset, offset, clip);
      controller.selection = TextSelection.collapsed(offset: offset + clip.length);
    }
  }

  void _selectAll() {
    final controller = _controller;
    if (controller == null) return;
    controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
  }

  // ---------- 双指缩放 ----------

  bool _zoomEnabled = false;

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
  Future<void> _reloadWithEncoding(EditorEncoding encoding) async {
    final doc = _doc;
    final path = doc?.path;
    if (doc == null) return;
    if (path == null || path.isEmpty) {
      _toast(localizations.editorNoFilePath);
      return;
    }
    try {
      final bytes = await File(path).readAsBytes();
      final text = await encoding.decode(bytes);
      if (!mounted) return;
      TextEditorPrefsStore.update(
          TextEditorPrefsStore.notifier.value.copyWith(encodingName: encoding.name));
      setState(() {
        doc.text = text;
        _lastText = text;
        _dirty = false;
      });
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

    var text = controller.text;
    switch (_newline) {
      case _Newline.crlf:
        text = text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
      case _Newline.cr:
        text = text.replaceAll('\r\n', '\n').replaceAll('\n', '\r');
      case _Newline.lf:
        text = text.replaceAll('\r\n', '\n');
    }
    final bytes = await encoding.encode(text);
    TextEditorPrefsStore.update(
        TextEditorPrefsStore.notifier.value.copyWith(encodingName: encoding.name));

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
        _minify();
      case 'find':
        _toggleFind();
      case 'special':
        _showSpecialReport();
      case 'replaceLine':
        _replaceCurrentLine();
      case 'selectNext':
        _addNextOccurrence();
      case 'gotoDef':
        _gotoDefinition();
      case 'upper':
        _editSelections((v) => v.toUpperCase());
      case 'lower':
        _editSelections((v) => v.toLowerCase());
      case 'formatSel':
        unawaited(_applyFormat(selectionOnly: true));
      case 'rename':
        unawaited(_renameSymbol());
    }
  }

  void _newFile() {
    final current = _doc;
    final keep = _prefs.newFileKeepPrefs && current != null;
    final doc = _docs.create(
      name: localizations.editorUntitled,
      langLabel: keep ? current.langLabel : 'Plain Text',
    );
    _activate(doc);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
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
                            _jumpToOffset(hits.firstWhere((h) => h.code == e.key).index);
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

  void _insertAtCursor(String insert) {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final sel = controller.selection;
    if (sel.isValid && !sel.isCollapsed) {
      controller.text = text.replaceRange(sel.start, sel.end, insert);
      controller.selection = TextSelection.collapsed(offset: sel.start + insert.length);
    } else {
      final offset = sel.isValid ? sel.start : text.length;
      controller.text = text.replaceRange(offset, offset, insert);
      controller.selection = TextSelection.collapsed(offset: offset + insert.length);
    }
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
      onInsert: (text) => _insertAtCursor(text),
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
    if (ok != true) return;

    final start = (int.tryParse(startCtl.text.trim()) ?? 1).clamp(1, total);
    final end = (int.tryParse(endCtl.text.trim()) ?? total).clamp(1, total);
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
    if (chosen == null || _doc == null) return;
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
  void _gotoDefinition() {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final caret = controller.selection.extentOffset;
    if (caret < 0 || caret > text.length) return;
    final range = _wordRangeAt(text, caret);
    final name = text.substring(range.start, range.end);
    if (name.isEmpty) {
      _toast(localizations.editorNoDefinition);
      return;
    }
    final at = _findDeclaration(text, name, range.start);
    if (at == null) {
      _toast(localizations.editorNoDefinition);
      return;
    }
    controller.selection = TextSelection.collapsed(offset: at);
    controller.scrollToLine(_lineOfOffset(text, at));
  }

  /// 在文档里找 [name] 的声明位置（返回名字所在的偏移）。
  ///
  /// [skipOffset] 是当前光标所在的词，找不到别的声明时不要「跳到自己」。
  static int? _findDeclaration(String text, String name, int skipOffset) {
    final escaped = RegExp.escape(name);
    final patterns = <RegExp>[
      RegExp(r'\b(?:class|struct|interface|enum|record|namespace)\s+' + escaped + r'\b'),
      RegExp(r'\b' + escaped + r'\s*\([^()]*\)\s*(?:\{|=>|;|:(?=\s*(?:\n|$)))'),
      RegExp(r'\b(?:var|let|const|val|final|int|long|double|float|bool|string|char|byte|decimal|object|dynamic|auto|[A-Z][\w<>\[\],.?]*)\s+'
          + escaped +
          r'\b\s*(?:=|;|,)'),
    ];
    for (final re in patterns) {
      for (final m in re.allMatches(text)) {
        final at = m.start + m.group(0)!.indexOf(name);
        if ((at - skipOffset).abs() < 1) continue;
        // 函数形态要确认前面确实是「声明」（`Foo();` 是调用，不是定义）。
        if (re.pattern.contains(r'\(') && !_looksLikeDeclHead(text, m.start)) continue;
        return at;
      }
    }
    return null;
  }

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

    // 1) 括号配对
    // 括号嵌套链上色（VS 的 bracket pair colorization）：由内到外各一层颜色。
    // 只给「包住光标的这几层」上色，不给整篇所有括号铺底色——那只会更花。
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
    if (_prefs.highlightOccurrences) {
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
          var count = 0;
          for (var i = text.indexOf(word); i >= 0; i = text.indexOf(word, i + word.length)) {
            list.add(SearchHighlight(start: i, end: i + word.length));
            if (++count >= 200) break;
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
          a[i].isCurrentMatch != b[i].isCurrentMatch) {
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
  ];

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
    final buffer = StringBuffer();
    var cursor = 0;
    final after = <({int start, int end})>[];
    for (final r in ranges) {
      buffer.write(text.substring(cursor, r.start));
      final replaced = transform(text.substring(r.start, r.end));
      final at = buffer.length;
      buffer.write(replaced);
      after.add((start: at, end: at + replaced.length));
      cursor = r.end;
    }
    buffer.write(text.substring(cursor));
    final result = buffer.toString();
    _multiSel.clear();
    _multiWord = '';
    controller.text = result;
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
  Future<void> _renameSymbol() async {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    final caret = controller.selection.baseOffset;
    final range = _wordRangeAt(text, caret < 0 ? 0 : caret);
    final name = text.substring(range.start, range.end);
    if (name.isEmpty) return;
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
    if (name.isEmpty) {
      _toast(localizations.editorNoDefinition);
      return;
    }
    final at = _findDeclaration(text, name, range.start);
    if (at == null) {
      _toast(localizations.editorNoDefinition);
      return;
    }
    await _showPeekAt(at: at, title: name);
  }

  /// 在下面弹一张卡片「速览」某个位置（声明和引用都走这里）。
  ///
  /// [at] 是名字所在的偏移。卡片里给两个出口：真的跳过去，或者看它的所有引用——
  /// 这样「这里是什么 → 还有谁用我」不用来回关面板再点菜单。
  Future<void> _showPeekAt({required int at, required String title}) async {
    final controller = _controller;
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
                    onPressed: () {
                      Navigator.pop(ctx);
                      controller.selection =
                          TextSelection.collapsed(offset: at.clamp(0, text.length));
                      unawaited(_showReferences());
                    },
                    child: Text(localizations.editorReferences),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      controller.selection =
                          TextSelection.collapsed(offset: at.clamp(0, text.length));
                      controller.scrollToLine(targetLine);
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
    final items = _collectSymbols(controller.text);
    if (!mounted) return;
    if (items.isEmpty) {
      _toast(localizations.editorSymbolsEmpty);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView.builder(
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final it = items[i];
          final indent = ((it.indent ~/ 4).clamp(0, 6)) * 10.0;
          return Padding(
            padding: EdgeInsets.only(left: indent),
            child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(_symbolIcon(it.kind), size: 18),
              title: Text(it.name, style: const TextStyle(fontSize: 13)),
              trailing: Text('L${it.line + 1}', style: const TextStyle(fontSize: 11)),
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.inverseSurface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$_rulerLine',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onInverseSurface),
              ),
            ),
          ),
        ),
    ];
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
        child: Text(
          trail[i].name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: i == trail.length - 1 ? theme.colorScheme.primary : muted,
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
  Future<void> _showReferences() async {
    final controller = _controller;
    final doc = _doc;
    if (controller == null || doc == null) return;
    final text = controller.text;
    final caret = controller.selection.baseOffset;
    final range = _wordRangeAt(text, caret < 0 ? 0 : caret);
    final name = text.substring(range.start, range.end);
    if (name.isEmpty) {
      _toast(localizations.editorReferencesEmpty);
      return;
    }
    final hits = <int>[];
    final wordChar = RegExp(r'[\w$]');
    var from = 0;
    while (hits.length < 200) {
      final at = text.indexOf(name, from);
      if (at < 0) break;
      // 只认整词：`Count` 不该命中 `Counter`。
      final before = at == 0 ? '' : text[at - 1];
      final afterAt = at + name.length;
      final after = afterAt >= text.length ? '' : text[afterAt];
      final ok = (before.isEmpty || !wordChar.hasMatch(before)) &&
          (after.isEmpty || !wordChar.hasMatch(after));
      if (ok) hits.add(at);
      from = at + name.length;
    }
    if (hits.isEmpty) {
      _toast(localizations.editorReferencesEmpty);
      return;
    }
    if (!mounted) return;
    final lines = <int>[];
    var scan = 0;
    var line = 0;
    for (final at in hits) {
      for (var i = scan; i < at && i < text.length; i++) {
        if (text.codeUnitAt(i) == 10) line++;
      }
      scan = at;
      lines.add(line);
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView.builder(
        itemCount: hits.length,
        itemBuilder: (ctx, i) {
          final at = hits[i];
          final snippet = _lineTextAt(text, lines[i]).trim();
          return ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.format_list_bulleted, size: 16),
            title: Text(snippet, maxLines: 1,
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('L${lines[i] + 1}', style: const TextStyle(fontSize: 11)),
              IconButton(
                icon: const Icon(Icons.visibility_outlined, size: 16),
                tooltip: localizations.editorPeekDefinition,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () {
                  Navigator.pop(ctx);
                  unawaited(_showPeekAt(at: at, title: name));
                },
              ),
            ]),
            onTap: () {
              Navigator.pop(ctx);
              final len = controller.text.length;
              controller.selection =
                  TextSelection(baseOffset: at.clamp(0, len), extentOffset: (at + name.length).clamp(0, len));
              controller.scrollToLine(lines[i]);
            },
          );
        },
      ),
    );
  }

  /// 取某一行的原文（引用列表的摘要用）。
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
      ],
    );
    if (chosen != null) _lineOp(chosen);
  }

  /// 行操作：VS Code 里是 Ctrl+Shift+K（删除行）、Alt+Shift+↑/↓（移动行）这一组。
  /// 手机上不给快捷键，全部收进菜单——但语义保持一致。
  void _lineOp(String op) {
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

  Future<void> _showCaseOpsMenu() async {
    final size = MediaQuery.of(context).size;
    final chosen = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(size.width - 190, kToolbarHeight + 40, 20, 0),
      items: [
        PopupMenuItem(value: 'upper', child: Text(localizations.editorUpperCase)),
        PopupMenuItem(value: 'lower', child: Text(localizations.editorLowerCase)),
        PopupMenuItem(value: 'title', child: Text(localizations.editorTitleCase)),
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
      _ => _titleCase(chunk),
    };
    if (converted == chunk) return;
    controller.replaceRange(start, end, converted);
    controller.selection = TextSelection(baseOffset: start, extentOffset: start + converted.length);
  }

  /// 光标处的「词」范围；不在词上时退化成光标所在的一个字符。
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
              final idx = l.indexOf(token!);
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

    try {
      final content = await File(path).readAsString();
      final name = path.split(Platform.pathSeparator).last;
      final doc = _docs.create(name: name, text: content, path: path, langLabel: _detectLanguage(path) ?? 'Plain Text');
      doc.newline = content.contains('\r\n') ? '\r\n' : (content.contains('\r') ? '\r' : '\n');
      _activate(doc);
      final pageLimit =
          _prefs.autoPageSize > 0 ? _prefs.autoPageSize : _kSmoothThreshold;
      if (content.length > pageLimit && !_smooth) {
        setState(() => _smooth = true);
        _toast(localizations.editorSmoothAutoEnabled);
      }
    } catch (e) {
      logger.w('Failed to open file: ', error: e);
      _toast('${localizations.fail}: $e');
    }
  }

  /// 按文件后缀粗略命中语言；命中失败返回 null。
  String? _detectLanguage(String path) {
    final ext = path.split('.').last.toLowerCase();
    const map = {
      'http': 'HTTP',
      'rest': 'HTTP',
      'json': 'JSON',
      'xml': 'XML / HTML',
      'html': 'XML / HTML',
      'htm': 'XML / HTML',
      'js': 'JavaScript',
      'mjs': 'JavaScript',
      'ts': 'TypeScript',
      'tsx': 'TypeScript',
      'css': 'CSS',
      'sql': 'SQL',
      'yaml': 'YAML',
      'yml': 'YAML',
      'md': 'Markdown',
      'markdown': 'Markdown',
      'sh': 'Bash',
      'bash': 'Bash',
      'py': 'Python',
      'java': 'Java',
      'go': 'Go',
      'dart': 'Dart',
    };
    return map[ext];
  }

  Future<void> _download() async {
    final controller = _controller;
    if (controller == null) return;
    var text = controller.text;
    if (text.isEmpty) return;

    // 编辑器内部永远是 \n，写出时按设置替换
    switch (_newline) {
      case _Newline.crlf:
        text = text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
      case _Newline.cr:
        text = text.replaceAll('\r\n', '\n').replaceAll('\n', '\r');
      case _Newline.lf:
        text = text.replaceAll('\r\n', '\n');
    }

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

  void _copy() {
    final text = _controller?.text ?? '';
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
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

    // 只格式化选中部分（VS 的 Format Selection）。
    // 片段单独拿去 JSON/XML 解析必然失败，所以这里只做「按大括号重排缩进」。
    if (selectionOnly) {
      final sel = controller.selection;
      if (!sel.isValid || sel.start == sel.end) {
        if (!quiet) _toast(localizations.editorFormatUnsupported);
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
      switch (_formatKind) {
        case FormatKind.json:
          result = JSON.pretty(text);
        case FormatKind.xml:
          result = XmlDocument.parse(text).toXmlString(pretty: true, indent: '  ');
        case FormatKind.css:
          result = CSS.pretty(text);
        case FormatKind.js:
          result = await JsDeobfuscator.beautify(text);
        case FormatKind.brace:
          // 通用大括号缩进重排：只改每行前导空白，正文逐字保留。
          result = reindentBraces(text, tabSize: _prefs.tabSize, useTabs: _prefs.useTabs);
        case FormatKind.none:
          if (!quiet) _toast(localizations.editorFormatUnsupported);
          return;
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
  void _minify() {
    final controller = _controller;
    final doc = _doc;
    if (controller == null || doc == null) return;
    final text = controller.text;
    if (text.trim().isEmpty) return;
    final result = CodeMinifier.minify(doc.langLabel, text);
    if (result == null) {
      _toast(localizations.editorMinifyUnsupported);
      return;
    }
    if (result == text) return;
    controller.text = result;
    _toast(localizations.editorMinified('${text.length}', '${result.length}'));
  }

  /// 激进压缩：走内置 JS 编译器前端（DCE + 局部变量重命名）。仅 JS/TS；
  /// 语法超出子集时不给结果，提示用户，绝不猜测。
  void _minifyAggressive() {
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
    final result = JsCompiler.minify(text);
    if (result == null) {
      _toast(localizations.editorMinifyAggressiveUnsupported);
      return;
    }
    if (result == text) return;
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
          _toolbar(),
          if (!compact) _docTabs(),
          const Divider(height: 1, thickness: 0.3),
          if (!compact) _breadcrumb(),
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
          if (doc != null && _prefs.magnifier) _magnifierBar(doc),
          // 参数签名提示（VS 打 `(` 后那行签名）：只在对当前语言、且文档里找得到声明时显示。
          if (doc != null && _programming)
            _SignatureBar(controller: doc.controller, resolve: _resolveSignature),
          // 问题栏：贴着代码，按文本顺序一行一条（红=报错，黄=警告）
          if (doc != null && _lintEnabled && _programming)
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
          if (_prefs.shortcutBar && !shortScreen) _snippetBar(),
          if (_consoleOpen && doc != null)
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
            ),
          if (doc != null)
            AnimatedBuilder(
              animation: doc.findController,
              builder: (_, __) => FindPanelView(controller: doc.findController),
            ),
          // 状态栏（学 VS Code）：光标行列、选中字符数、缩进、语言
          if (doc != null) _statusBar(doc),
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
      indent: _prefs.useTabs ? 'Tab:${_prefs.tabSize}' : 'Space:${_prefs.tabSize}',
      // 纯文本没有「问题」这个概念，不显示 ❌0 ⚠0。
      report: _programming && _lintEnabled ? doc.lint : null,
      onTapIssues: () => _openConsole(EditorConsoleTab.problems),
      onTapLanguage: _showLanguagePicker,
      onTapIndent: _openSettings,
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
    try {
      var text = doc.text;
      switch (_newline) {
        case _Newline.crlf:
          text = text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
        case _Newline.cr:
          text = text.replaceAll('\r\n', '\n').replaceAll('\n', '\r');
        case _Newline.lf:
          text = text.replaceAll('\r\n', '\n');
      }
      await File(path).writeAsBytes(await _encoding.encode(text));
      doc.dirty = false;
      if (mounted && identical(doc, _doc)) setState(() {});
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
  final List<int> _recentEdits = <int>[];

  void _rememberEdit(int offset) {
    if (offset < 0) return;
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
                  setState(() => _recentEdits.clear());
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
    controller.selection = TextSelection.collapsed(offset: target.clamp(0, text.length));
    controller.scrollToLine(_lineOfOffset(text, target));
    _toast('${list.indexOf(target) + 1} / ${list.length}');
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
          child: Row(children: [
            _iconBtn(Icons.note_add_outlined, loc.editorNewFile, _newFile),
            _iconBtn(Icons.folder_open, loc.selectFile, _openFile),
            _iconBtn(Icons.save_outlined, loc.save, _download),
            _toolbarSep(),
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
          ]),
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
          _menuItem('save', Icons.save_outlined, loc.save),
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
          _menuItem('copy', Icons.copy_all, loc.copy),
          _menuItem('clear', Icons.backspace_outlined, loc.clear),
          _menuItem('replaceLine', Icons.sync_alt, loc.editorReplaceLine),
          const PopupMenuDivider(),
          _menuItem('comment', Icons.code, loc.editorToggleComment),
          PopupMenuItem(value: 'lineOps', child: _menuRow(loc.editorLineOps, Icons.arrow_right, id: 'lineOps')),
          PopupMenuItem(value: 'caseOps', child: _menuRow(loc.editorCaseOps, Icons.arrow_right, id: 'caseOps')),
          _menuItem('expandSel', Icons.open_in_full, loc.editorExpandSelection),
        _menuItem('jumpBracket', Icons.data_object, loc.editorJumpBracket),
        PopupMenuItem(value: 'nextBookmark', child: Text(loc.editorNextBookmark)),
        _menuItem('toggleBookmark', Icons.bookmark_add_outlined, loc.editorToggleBookmark),
        _menuItem('bookmarks', Icons.bookmarks_outlined, loc.editorBookmarks),
        _menuItem('clearBookmarks', Icons.bookmark_remove_outlined, loc.editorClearBookmarks),
        _menuItem('nextOccurrence', Icons.select_all, loc.editorSelectNext),
        ];
      case 'code':
        return [
          if (_canFormat) _menuItem('format', Icons.auto_fix_high, loc.format),
          _menuItem('formatSel', Icons.auto_fix_normal, loc.editorFormatSelection),
          if (_canPreview) _menuItem('preview', Icons.visibility_outlined, loc.editorPreview),
          const PopupMenuDivider(),
          _menuItem('symbols', Icons.account_tree_outlined, loc.editorSymbols),
          _menuItem('gotoLine', Icons.pin_drop_outlined, loc.editorSelectToLine),
          _menuItem('gotoDef', Icons.my_location_outlined, loc.editorGotoDefinition),
        _menuItem('peekDef', Icons.visibility, loc.editorPeekDefinition),
          _menuItem('references', Icons.format_list_bulleted, loc.editorReferences),
          _menuItem('rename', Icons.drive_file_rename_outline, loc.editorRename),
          const PopupMenuDivider(),
          _menuItem('foldAll', Icons.unfold_less, loc.editorFoldAll),
          _menuItem('unfoldAll', Icons.unfold_more, loc.editorUnfoldAll),
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
          _menuItem('report', Icons.report_outlined, loc.editorSpecialReport),
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
        case 'gotoDef':
          _gotoDefinition();
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
        case 'replaceLine':
          _replaceCurrentLine();
        case 'lint':
          _setLintEnabled(!_lintEnabled);
        case 'lintIssues':
          _openConsole(EditorConsoleTab.problems);
        case 'console':
          _openConsole(EditorConsoleTab.console);
        case 'minify':
          _minify();
        case 'minifyAggressive':
          _minifyAggressive();
        case 'newline':
          _pickNewline();
        case 'retainMode':
          _pickRetainMode();
        case 'settings':
          _openSettings();
        case 'rename':
          unawaited(_renameSymbol());
        case 'formatSel':
          unawaited(_applyFormat(selectionOnly: true));
        case 'foldAll':
          _controller?.foldAll();
        case 'unfoldAll':
          _controller?.unfoldAll();
        case 'references':
          unawaited(_showReferences());
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
      case 'jumpBracket':
        _jumpToMatchingBracket();
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
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      tooltip: localizations.editorMore,
      onSelected: _menuAction,
      itemBuilder: (context) {
        final hidden = _prefs.hiddenMenu.toSet();
        return <PopupMenuEntry<String>>[
        PopupMenuItem(
          value: 'file',
          child: _menuRow(localizations.editorMoreFile, Icons.arrow_right, id: 'file'),
        ),
        PopupMenuItem(value: 'search', child: Text(localizations.search)),
        PopupMenuItem(
          value: 'syntax',
          child: _menuRow(localizations.editorMoreSyntax, Icons.arrow_right, id: 'syntax'),
        ),
        _menuItem('gotoLine', Icons.pin_drop_outlined, localizations.editorSelectToLine),
        _menuItem('symbols', Icons.account_tree_outlined, localizations.editorSymbols),
        _menuItem('nextOccurrence', Icons.select_all, localizations.editorSelectNext),
        _menuItem('rename', Icons.drive_file_rename_outline, localizations.editorRename),
        PopupMenuItem(
          value: 'formatSel',
          child: Text(localizations.editorFormatSelection),
        ),
        _menuItem('foldAll', Icons.unfold_less, localizations.editorFoldAll),
        _menuItem('unfoldAll', Icons.unfold_more, localizations.editorUnfoldAll),
        _menuItem('gotoDef', Icons.my_location_outlined, localizations.editorGotoDefinition),
        _menuItem('references', Icons.format_list_bulleted, localizations.editorReferences),
        PopupMenuItem(
          value: 'lineOps',
          child: _menuRow(localizations.editorLineOps, Icons.arrow_right, id: 'lineOps'),
        ),
        PopupMenuItem(
          value: 'caseOps',
          child: _menuRow(localizations.editorCaseOps, Icons.arrow_right, id: 'caseOps'),
        ),
        PopupMenuItem(
          value: 'navBack',
          enabled: _navIndex > 0,
          child: Text(localizations.editorNavBack, style: TextStyle(
              color: _navIndex > 0 ? null : Theme.of(context).disabledColor)),
        ),
        PopupMenuItem(
          value: 'recentEdits',
          child: Text(localizations.editorRecentEdits, style: const TextStyle(fontSize: 13.5)),
        ),
        PopupMenuItem(
          value: 'navForward',
          enabled: _navIndex < _navStack.length - 1,
          child: Text(localizations.editorNavForward, style: TextStyle(
              color: _navIndex < _navStack.length - 1 ? null : Theme.of(context).disabledColor)),
        ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: 'wrap',
          checked: _wrap,
          child: Text(localizations.wordWrap),
        ),
        CheckedPopupMenuItem(
          value: 'readOnly',
          checked: _readOnly,
          child: Text(localizations.editorReadOnly),
        ),
        CheckedPopupMenuItem(
          value: 'smooth',
          checked: _smooth,
          child: Text(localizations.editorSmoothMode),
        ),
        CheckedPopupMenuItem(
          value: 'smart',
          checked: SmartCompletion.enabled.value,
          child: Text(localizations.smartCompletion),
        ),
        CheckedPopupMenuItem(
          value: 'smoothKeepIme',
          checked: _smoothKeepIme,
          child: Text(localizations.editorSmoothKeepIme),
        ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: 'ascii',
          checked: _showAscii,
          child: Text(localizations.editorShowAsciiControl),
        ),
        CheckedPopupMenuItem(
          value: 'unicode',
          checked: _showUnicode,
          child: Text(localizations.editorShowUnicodeSpecial),
        ),
        _menuItem('report', Icons.report_outlined, localizations.editorSpecialReport),
        _menuItem('replaceLine', Icons.sync_alt, localizations.editorReplaceLine),
        const PopupMenuDivider(),
        // 「检查」只对编程语言有意义：JSON/YAML/纯文本没有「编译」这回事，
        // 把它藏在非编程语法下，菜单里就不会出现点了也没用的项。
        if (_programming) ...[
          CheckedPopupMenuItem(
            value: 'lint',
            checked: _lintEnabled,
            child: Text(localizations.editorLint),
          ),
          _menuItem('lintIssues', Icons.error_outline, localizations.editorLintIssues),
          _menuItem('console', Icons.terminal, localizations.editorConsole),
        ],
        const PopupMenuDivider(),
        _menuItem('minify', Icons.compress, localizations.editorMinify),
        _menuItem('minifyAggressive', Icons.compress, localizations.editorMinifyAggressive),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'newline',
          child: Text('${localizations.editorNewline}: ${_newlineLabel()}'),
        ),
        PopupMenuItem(
          value: 'retainMode',
          child: Text('${localizations.editorRetainPref}: ${_retainModeLabel()}'),
        ),
        const PopupMenuDivider(),
        _menuItem('settings', Icons.settings, localizations.editorSettings),
        _menuItem('close', Icons.close, localizations.editorCloseFile),
        ]
            .where((e) => e is! PopupMenuItem<String> || !hidden.contains(e.value))
            .toList();
      },
    );
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
        'wrap': _wrap,
        'readOnly': _readOnly,
        'smooth': _smooth,
        'smart': SmartCompletion.enabled.value,
        'smoothKeepIme': _smoothKeepIme,
        'ascii': _showAscii,
        'unicode': _showUnicode,
        'lint': _lintEnabled,
      };

  Future<void> _showCommandPalette() async {
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
        toggles: _toggleStates,
        onRun: (id) {
          // 一次性命令是「先关面板、下一帧再执行」，这中间用户可能已经把编辑器关了。
          if (!mounted) return;
          unawaited(_rememberCommand(id));
          _menuAction(id);
        },
        // 开关类命令执行完面板留着，可以连着拨几个；其余执行完就关。
        isKeep: (id) => _toggleCommands.contains(id),
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
        _showStats();
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
      final text = await File(path).readAsString();
      if (!mounted) return;
      setState(() {
        doc.text = text;
        _lastText = text;
        _dirty = false;
      });
      _toast(localizations.editorReloadSuccess);
    } catch (e) {
      _toast('$e');
    }
  }

  /// 文本统计。
  void _showStats() {
    final doc = _doc;
    if (doc == null) return;
    final text = doc.text;
    final lines = text.isEmpty ? 0 : '\n'.allMatches(text).length + 1;
    final chars = text.length;
    final words = RegExp(r'\S+').allMatches(text).length;
    final bytes = utf8.encode(text).length;

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
    switch (_newline) {
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
    final value = await showDialog<_Newline>(
      context: context,
      builder: (ctx) => SimpleDialog(
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
                trailing: e == _newline ? const Icon(Icons.check, size: 18) : null,
                onTap: () => Navigator.pop(ctx, e),
              )),
        ],
      ),
    );
    if (value == null) return;
    setState(() => _newline = value);
    await _saveNewline();
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
    if (value == null) return;
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

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor)),
        child: CodeForge(
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
          onGutterLineLongPress: _handleGutterLongPress,
        ),
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

  /// 开关类命令的当前状态（id → 是否开启），用来显示右侧的 ✓。
  final Map<String, bool> toggles;

  /// 执行一条命令。
  final void Function(String id) onRun;

  /// 这条命令执行后要不要把面板留着（开关类命令 = true）。
  final bool Function(String id) isKeep;

  const _CommandPaletteSheet({
    required this.commands,
    required this.onRun,
    required this.isKeep,
    required this.toggles,
    this.recent = const <String>[],
  });

  @override
  State<_CommandPaletteSheet> createState() => _CommandPaletteSheetState();
}

class _CommandPaletteSheetState extends State<_CommandPaletteSheet> {
  String _query = '';

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
      if (widget.recent.isNotEmpty) {
        final byId = {for (final c in widget.commands) c.id: c};
        final recentCmds = <({String id, String label, String group, String keyword})>[];
        for (final id in widget.recent) {
          final cmd = byId[id];
          if (cmd != null) recentCmds.add(cmd);
        }
        if (recentCmds.isNotEmpty) {
          rows.add(_PaletteHeader(loc.editorRecentCommands));
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
                      final cmd = row as ({String id, String label, String group, String keyword});
                      // 开关类命令右侧显示当前状态，不然「换行/只读/平滑模式」
                      // 拨了之后看不出是开还是关，只能靠编辑区反推。
                      final toggle = widget.toggles[cmd.id];
                      return ListTile(
                        dense: true,
                        leading: Icon(menuIconOf(cmd.id), size: 17),
                        title: Text(cmd.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5)),
                        trailing: toggle == null
                            ? null
                            : Icon(
                                toggle ? Icons.check_box_outlined : Icons.check_box_outline_blank,
                                size: 17,
                                color: toggle ? theme.colorScheme.primary : theme.disabledColor,
                              ),
                        onTap: () {
                          if (widget.isKeep(cmd.id)) {
                            widget.onRun(cmd.id);
                            setState(() {});
                            return;
                          }
                          // 先关面板、下一帧再执行：这里有些命令（文件▸/语法▸/
                          // 行操作▸/大小写▸ 以及各种 sheet）自己会 push 一个 route，
                          // 面板还在栈上时执行，它们收尾时的 pop 会把刚弹出的子菜单
                          // 一起弹掉 —— 表现为「点了闪一下就没了」。
                          Navigator.pop(ctx);
                          WidgetsBinding.instance.addPostFrameCallback((_) => widget.onRun(cmd.id));
                        },
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
  const _PaletteHeader(this.text);
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

  const _EditorStatusBar({
    required this.controller,
    required this.language,
    required this.indent,
    this.dirtyCount = 0,
    this.report,
    this.onTapIssues,
    this.onTapLanguage,
    this.onTapIndent,
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
            if (!compact) ...[
              const SizedBox(width: 10),
              InkWell(
                onTap: widget.onTapIndent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(widget.indent, style: style),
                ),
              ),
            ],
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
