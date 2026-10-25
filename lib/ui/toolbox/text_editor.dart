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
import 'package:proxypin/ui/component/lint_rules_dialog.dart';
import 'package:proxypin/ui/toolbox/editor_console.dart';
import 'package:proxypin/utils/custom_lang.dart';
import 'package:proxypin/utils/lang_meta.dart';
import 'package:proxypin/utils/text_editor_prefs.dart';
import 'package:proxypin/ui/toolbox/text_editor_settings.dart';
import 'package:proxypin/ui/toolbox/text_editor_menus.dart';
import 'package:proxypin/utils/smart_completion.dart';
import 'package:proxypin/utils/smart_suggestions.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:proxypin/utils/text_special_chars.dart';
import 'package:proxypin/utils/tool_snippets.dart';
import 'package:proxypin/ui/toolbox/text_editor_docs.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xml/xml.dart';

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
  bool _lintEnabled = true;
  bool _inLint = false;

  /// 被用户关掉的规则（持久化在 prefs 里）。
  Set<String> _disabledRules = <String>{};
  static const String _kLintDisabled = 'code_lint_disabled_v1';
  bool _consoleOpen = false;
  EditorConsoleTab _consoleTab = EditorConsoleTab.problems;
  bool _dirty = false;
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
      _dirty = false;
    });

    doc.controller.addListener(_onControllerChanged);
    doc.undoController.addListener(_onUndoChanged);
    _restartFileWatch();
    // 切回旧文档：直接恢复上次的诊断标记，避免「重新检查」造成的闪动。
    final cached = doc.lint;
    if (cached != null) {
      _applyLintDecorations(cached);
    } else {
      _clearLintDecorations();
      _scheduleLint();
    }
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

  void _onUndoChanged() {
    if (mounted) setState(() {});
  }

  void _onControllerChanged() {
    final text = _doc?.text ?? '';
    if (text != _lastText) {
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
      if (_prefs.magnifier && mounted) setState(() {});
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
    if (!_lintEnabled) return;
    // 流畅模式刻意关掉了高亮/折叠，再挂一层全量扫描等于白费力气；
    // 这种情况下只在打开「问题」面板时按需检查。
    if (_smooth && !_consoleOpen) return;
    _lintTimer?.cancel();
    _lintTimer = Timer(const Duration(milliseconds: 650), _runLint);
  }

  Future<void> _loadLintRules() async {
    try {
      final raw = await SharedPreferencesAsync().getStringList(_kLintDisabled);
      if (!mounted) return;
      if (raw == null) return;
      setState(() => _disabledRules = raw.toSet());
      _doc?.lint = null;
      _scheduleLint();
    } catch (_) {
      // 偏好读取失败就按「全部规则开启」跑
    }
  }

  Future<void> _saveLintRules() async {
    try {
      await SharedPreferencesAsync().setStringList(_kLintDisabled, _disabledRules.toList());
    } catch (_) {
      // 忽略
    }
  }

  Future<void> _openLintRules() async {
    final result = await showLintRulesDialog(context, _disabledRules);
    if (result == null || !mounted) return;
    setState(() => _disabledRules = result);
    unawaited(_saveLintRules());
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
    if (doc == null || !mounted || _inLint) return;
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
      );
    } else {
      report = CodeLint.check(
        text,
        langLabel: doc.langLabel,
        langKey: _lang.key,
        chinese: chinese,
        disabledRules: _disabledRules,
      );
    }
    _inLint = false;
    if (!mounted) return;
    doc.lint = report;
    doc.lintText = text;
    _issueCursor = -1;
    setState(() => _lintChecking = false);
    // 换完装饰会 notifyListeners，必须放在 setState 之后、且不能再次触发检查。
    _applyLintDecorations(report);
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
    final controller = _doc?.controller;
    if (controller == null) return;
    controller.clearLineDecorations();
    controller.clearGutterDecorations();
    controller.notifyListeners();
  }

  void _applyLintDecorations(LintReport report) {
    final controller = _doc?.controller;
    if (controller == null) return;
    controller.clearLineDecorations();
    controller.clearGutterDecorations();
    if (report.diagnostics.isEmpty) {
      controller.notifyListeners();
      return;
    }

    // 同一行有多条诊断时只按最严重的那条染色。
    final worstByLine = <int, LintSeverity>{};
    for (final d in report.diagnostics) {
      final line = d.line - 1;
      if (line < 0) continue;
      final current = worstByLine[line];
      if (current == null || d.severity.index < current.index) worstByLine[line] = d.severity;
    }

    final decos = <LineDecoration>[];
    final gutters = <GutterDecoration>[];
    worstByLine.forEach((line, severity) {
      final color = severity == LintSeverity.error
          ? Colors.red
          : severity == LintSeverity.warning
              ? Colors.orange
              : Colors.blueGrey;
      decos.add(LineDecoration(
        id: 'lint-bg-$line',
        startLine: line,
        endLine: line,
        type: LineDecorationType.background,
        color: color.withValues(alpha: 0.12),
      ));
      gutters.add(GutterDecoration(
        id: 'lint-gutter-$line',
        startLine: line,
        endLine: line,
        type: GutterDecorationType.colorBar,
        color: color,
      ));
    });
    controller.addLineDecorations(decos);
    controller.addGutterDecorations(gutters);
    controller.notifyListeners();
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

  /// F8 / Shift+F8：在问题之间跳。
  void _jumpIssue(bool forward) {
    final list = _lint?.diagnostics;
    if (list == null || list.isEmpty) return;
    var next = _issueCursor + (forward ? 1 : -1);
    if (next < 0) next = list.length - 1;
    if (next >= list.length) next = 0;
    _issueCursor = next;
    _jumpToDiagnostic(list[next]);
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
    final fixed = CodeLint.applyFixes(controller.text, report.diagnostics);
    if (fixed == controller.text) return;
    controller.text = fixed;
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
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (!_zoomEnabled || _pointers.length != 2 || _pinchBaseDistance == null) return;
    final base = _pinchBaseDistance!;
    if (base <= 0) return;
    final ratio = _pointerDistance() / base;
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
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) {
      if (_pinchBaseDistance != null) {
        // 缩放结束，落盘一次。
        TextEditorPrefsStore.update(TextEditorPrefsStore.notifier.value).ignore();
      }
      _pinchBaseDistance = null;
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

  void _closeDoc(EditorDocument doc) {
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
    final lineStart = text.lastIndexOf('\n', offset - 1) + 1;
    final nlIndex = text.indexOf('\n', offset);
    final hasTrailingNewline = nlIndex >= 0;
    final lineEnd = hasTrailingNewline ? nlIndex : text.length;
    final removeEnd = hasTrailingNewline ? lineEnd + 1 : lineEnd;
    final insert = (hasTrailingNewline && !clip.endsWith('\n')) ? '$clip\n' : clip;
    controller.text = text.replaceRange(lineStart, removeEnd, insert);
    controller.selection = TextSelection.collapsed(offset: lineStart + insert.length);
    _toast(localizations.editorReplacedLine);
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
  FormatKind get _formatKind {
    // 没借用任何高亮的自定义语法（纯文本）不做格式化，避免按名字瞎猜。
    if (_lang.custom && _lang.key.isEmpty) return FormatKind.none;
    return formatKindOf(key: _lang.key, label: _lang.label);
  }

  bool get _canFormat => _formatKind != FormatKind.none;

  /// 按当前语言格式化。失败时通过 toast 显示原因，不修改原文。
  Future<void> _format() async {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    if (text.trim().isEmpty) return;
    switch (_formatKind) {
      case FormatKind.json:
        try {
          final pretty = JSON.pretty(text);
          if (pretty != text) controller.text = pretty;
        } catch (e) {
          _toast('${localizations.fail}: $e');
        }
      case FormatKind.xml:
        try {
          final pretty = XmlDocument.parse(text).toXmlString(pretty: true, indent: '  ');
          if (pretty != text) controller.text = pretty;
        } on XmlException catch (e) {
          _toast('${localizations.fail}: ${e.message}');
        }
      case FormatKind.css:
        final pretty = CSS.pretty(text);
        if (pretty != text) controller.text = pretty;
      case FormatKind.js:
        try {
          final pretty = await JsDeobfuscator.beautify(text);
          if (pretty != text) controller.text = pretty;
        } catch (e) {
          _toast('${localizations.fail}: $e');
        }
      case FormatKind.brace:
        // 通用大括号缩进重排：只改每行前导空白，正文逐字保留。
        final pretty = reindentBraces(text, tabSize: _prefs.tabSize, useTabs: _prefs.useTabs);
        if (pretty != text) controller.text = pretty;
      case FormatKind.none:
        _toast(localizations.editorFormatUnsupported);
    }
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
          ? (ctx) => SmartSuggestions.suggest(
                language: doc.langLabel,
                key: _lang.key,
                documentText: ctx.documentText,
                linePrefix: ctx.linePrefix,
                prefix: ctx.prefix,
                cursorOffset: ctx.cursorOffset,
              )
          : null;
    }

    return PopScope(
      canPop: !(_retainMode == _RetainMode.ask && _hasUnretained),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _scheduleExitCleanup(null);
        } else {
          unawaited(_confirmExit());
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _docDrawer(),
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
          const Divider(height: 1, thickness: 0.3),
          Expanded(
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerUp,
              child: _textView(),
            ),
          ),
          if (doc != null && _prefs.magnifier) _magnifierBar(doc),
          if (_prefs.shortcutBar) _snippetBar(),
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
            ),
          if (doc != null)
            AnimatedBuilder(
              animation: doc.findController,
              builder: (_, __) => FindPanelView(controller: doc.findController),
            ),
        ]),
      ),
    );
  }

  Widget _docDrawer() {
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
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(localizations.editorDocsHint,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, thickness: 0.3),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _docs.docs.length,
              onReorder: (oldIndex, newIndex) {
                setState(() => _docs.reorder(oldIndex, newIndex));
                _docs.persist();
              },
              itemBuilder: (context, i) {
                final doc = _docs.docs[i];
                return _docTile(doc, i);
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
            doc.name,
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
              _closeDoc(doc);
            },
          ),
        ]),
      ),
    );
  }

  Widget _toolbar() {
    final color = Theme.of(context).colorScheme.primary;
    final controller = _controller;
    return Container(
      padding: const EdgeInsets.only(top: 2, bottom: 2, left: 4, right: 12),
      // 两行布局：菜单 + 语言行 + 工具行，窄屏（手机）不再溢出
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(
            icon: const Icon(Icons.menu, size: 19),
            tooltip: localizations.editorDocuments,
            visualDensity: VisualDensity.compact,
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          DropdownButton<_LangOption>(
            value: _lang,
            isDense: true,
            underline: const SizedBox.shrink(),
            icon: const Icon(Icons.arrow_drop_down, size: 18),
            items: _langs
                .map((l) => DropdownMenuItem(
                    value: l,
                    child: Text(l.label == 'Plain Text' ? localizations.editorPlainText : l.label,
                        style: const TextStyle(fontSize: 12.5))))
                .toList(),
            onChanged: (v) {
              if (v == null || v == _lang || _doc == null) return;
              setState(() => _doc!.langLabel = v.label);
              _doc!.lint = null;
              _scheduleLint();
            },
          ),
          const Spacer(),
          if (_dirty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(localizations.editorUnsaved, style: TextStyle(fontSize: 11, color: color)),
            ),
        ]),
        Wrap(
          spacing: 0,
          runSpacing: 0,
          children: [
            _iconBtn(Icons.note_add_outlined, localizations.editorNewFile, _newFile),
            _iconBtn(Icons.folder_open, localizations.selectFile, _openFile),
            _iconBtn(Icons.save_outlined, localizations.save, _download),
            _iconBtn(Icons.undo, localizations.editorUndo, _doc?.undoController.canUndo == true ? _undo : null),
            _iconBtn(Icons.redo, localizations.editorRedo, _doc?.undoController.canRedo == true ? _redo : null),
            AnimatedBuilder(
              animation: _doc?.findController ?? _noFind,
              builder: (_, __) => _iconBtn(
                  Icons.search,
                  localizations.search,
                  _toggleFind,
                  tint: (_doc?.findController.isActive ?? false) ? color : null),
            ),
            _iconBtn(Icons.auto_fix_high, localizations.format, _canFormat ? _format : null),
            _iconBtn(Icons.code, localizations.editorToggleComment, _toggleComment),
            _iconBtn(Icons.wrap_text, localizations.wordWrap, () => setState(() => _wrap = !_wrap),
                tint: _wrap ? color : null),
            _iconBtn(Icons.copy, localizations.copy, _copy),
            _iconBtn(Icons.delete_outline, localizations.clear, _clear),
            if (_lintEnabled) _lintButton(color),
            _moreMenu(color),
          ],
        ),
      ]),
    );
  }

  void _undo() => _doc?.undoController.undo();

  void _redo() => _doc?.undoController.redo();

  Widget _moreMenu(Color color) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      tooltip: localizations.editorMore,
      onSelected: (value) {
        switch (value) {
          case 'file':
            _showFileMenu();
          case 'search':
            _toggleFind();
          case 'syntax':
            _showSyntaxMenu();
          case 'gotoLine':
            _selectToLine();
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
          case 'close':
            final doc = _doc;
            if (doc != null) _closeDoc(doc);
        }
      },
      itemBuilder: (context) {
        final hidden = _prefs.hiddenMenu.toSet();
        return <PopupMenuEntry<String>>[
        PopupMenuItem(
          value: 'file',
          child: _menuRow(localizations.editorMoreFile, Icons.arrow_right),
        ),
        PopupMenuItem(value: 'search', child: Text(localizations.search)),
        PopupMenuItem(
          value: 'syntax',
          child: _menuRow(localizations.editorMoreSyntax, Icons.arrow_right),
        ),
        PopupMenuItem(value: 'gotoLine', child: Text(localizations.editorSelectToLine)),
        PopupMenuItem(
          value: 'navBack',
          enabled: _navIndex > 0,
          child: Text(localizations.editorNavBack, style: TextStyle(
              color: _navIndex > 0 ? null : Theme.of(context).disabledColor)),
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
        PopupMenuItem(value: 'report', child: Text(localizations.editorSpecialReport)),
        PopupMenuItem(value: 'replaceLine', child: Text(localizations.editorReplaceLine)),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: 'lint',
          checked: _lintEnabled,
          child: Text(localizations.editorLint),
        ),
        PopupMenuItem(value: 'lintIssues', child: Text(localizations.editorLintIssues)),
        if (_programming)
          PopupMenuItem(value: 'console', child: Text(localizations.editorConsole)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'minify', child: Text(localizations.editorMinify)),
        PopupMenuItem(value: 'minifyAggressive', child: Text(localizations.editorMinifyAggressive)),
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
        PopupMenuItem(value: 'settings', child: Text(localizations.editorSettings)),
        PopupMenuItem(value: 'close', child: Text(localizations.editorCloseFile)),
        ]
            .where((e) => e is! PopupMenuItem<String> || !hidden.contains(e.value))
            .toList();
      },
    );
  }

  /// 菜单里带右侧箭头的行（表示还有下一级）。
  Widget _menuRow(String text, IconData trailing) {
    return Row(
      children: [
        Expanded(child: Text(text)),
        Icon(trailing, size: 18),
      ],
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
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 17, color: onTap == null ? Colors.grey : tint),
      visualDensity: VisualDensity.compact,
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
