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
import 'package:proxypin/utils/platform.dart';
import 'package:proxypin/utils/text_special_chars.dart';
import 'package:proxypin/utils/tool_snippets.dart';
import 'package:proxypin/ui/toolbox/text_editor_docs.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/http.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
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
class _LangOption {
  final String label;
  final Mode? mode;

  const _LangOption(this.label, this.mode);
}

final List<_LangOption> _langs = [
  _LangOption('Plain Text', null),
  _LangOption('HTTP', langHttp),
  _LangOption('JSON', langJson),
  _LangOption('XML / HTML', langXml),
  _LangOption('JavaScript', langJavascript),
  _LangOption('TypeScript', langTypescript),
  _LangOption('CSS', langCss),
  _LangOption('SQL', langSql),
  _LangOption('YAML', langYaml),
  _LangOption('Markdown', langMarkdown),
  _LangOption('Bash', langBash),
  _LangOption('Python', langPython),
  _LangOption('Java', langJava),
  _LangOption('Go', langGo),
  _LangOption('Dart', langDart),
];

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

  /// 流畅模式是否保留输入法候选建议。默认 true（不牺牲输入法）；
  /// 关掉后流畅模式会同时禁用输入法建议，换取超长文本下的更高流畅度。
  bool _smoothKeepIme = true;
  bool _showAscii = false;
  bool _showUnicode = false;
  bool _dirty = false;
  int? _gutterAnchorLine;

  _RetainMode _retainMode = _RetainMode.never;
  _Newline _newline = _Newline.lf;

  String _lastText = '';
  bool _confirmingExit = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  CodeForgeController? get _controller => _doc?.controller;

  InvisibleCharsStyle get _invisibleCharsStyle =>
      InvisibleCharsStyle(ascii: _showAscii, unicode: _showUnicode);

  _LangOption get _lang =>
      _langs.firstWhere((l) => l.label == (_doc?.langLabel ?? 'Plain Text'), orElse: () => _langs.first);

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
    if (Platforms.isDesktop() && widget.windowId != null) {
      HardwareKeyboard.instance.addHandler(_onKeyEvent);
    }
  }

  @override
  void dispose() {
    _doc?.controller.removeListener(_onControllerChanged);
    _doc?.undoController.removeListener(_onUndoChanged);
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
  }

  void _onUndoChanged() {
    if (mounted) setState(() {});
  }

  void _onControllerChanged() {
    final text = _doc?.text ?? '';
    if (text != _lastText) {
      _lastText = text;
      if (!_dirty) setState(() => _dirty = true);
    }
  }

  void _newFile() {
    final doc = _docs.create(name: localizations.editorUntitled);
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

  /// 可滑动 / 可展开的快捷输入行；随当前文档的语言切换常用符号。
  Widget _snippetBar() {
    final label = _doc?.langLabel ?? 'Plain Text';
    return SnippetBar(
      scope: editorSnippetScope(label),
      defaults: ToolSnippetDefaults.forLanguage(label),
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

  String? _lineCommentToken() {
    switch (_doc?.langLabel) {
      case 'JavaScript':
      case 'TypeScript':
      case 'Java':
      case 'Go':
      case 'Dart':
      case 'CSS':
        return '//';
      case 'Python':
      case 'Bash':
      case 'YAML':
        return '#';
      case 'SQL':
        return '--';
      default:
        return null;
    }
  }

  bool get _isBlockCommentLang =>
      _doc?.langLabel == 'XML / HTML' || _doc?.langLabel == 'Markdown';

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
    if (token == null && !_isBlockCommentLang) {
      _toast(localizations.editorCommentUnsupported);
      return;
    }

    String result;
    if (_isBlockCommentLang && token == null) {
      final allWrapped = lines.every((l) => l.trim().isEmpty || (l.trimLeft().startsWith('<!--') && l.trimRight().endsWith('-->')));
      result = lines
          .map((l) {
            if (l.trim().isEmpty) return l;
            final indent = l.substring(0, l.length - l.trimLeft().length);
            final body = l.trim();
            if (allWrapped) {
              return indent + body.replaceFirst('<!--', '').replaceFirst(RegExp(r'-->\s*$'), '');
            }
            return '$indent<!-- $body -->';
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
      if (content.length > _kSmoothThreshold && !_smooth) {
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

  /// 是否支持格式化：JSON / XML / HTML / CSS / JavaScript。
  bool get _canFormat =>
      _lang.label == 'JSON' ||
      _lang.label == 'XML / HTML' ||
      _lang.label == 'CSS' ||
      _lang.label == 'JavaScript';

  /// 按当前语言格式化。失败时通过 toast 显示原因，不修改原文。
  Future<void> _format() async {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    if (text.trim().isEmpty) return;
    switch (_lang.label) {
      case 'JSON':
        try {
          final pretty = JSON.pretty(text);
          if (pretty != text) controller.text = pretty;
        } catch (e) {
          _toast('${localizations.fail}: $e');
        }
      case 'XML / HTML':
        try {
          final pretty = XmlDocument.parse(text).toXmlString(pretty: true, indent: '  ');
          if (pretty != text) controller.text = pretty;
        } on XmlException catch (e) {
          _toast('${localizations.fail}: ${e.message}');
        }
      case 'CSS':
        final pretty = CSS.pretty(text);
        if (pretty != text) controller.text = pretty;
      case 'JavaScript':
        try {
          final pretty = await JsDeobfuscator.beautify(text);
          if (pretty != text) controller.text = pretty;
        } catch (e) {
          _toast('${localizations.fail}: $e');
        }
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
          Expanded(child: _textView()),
          _snippetBar(),
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
            _iconBtn(Icons.search, localizations.search, _doc?.findController.toggleActive),
            _iconBtn(Icons.auto_fix_high, localizations.format, _canFormat ? _format : null),
            _iconBtn(Icons.code, localizations.editorToggleComment, _toggleComment),
            _iconBtn(Icons.wrap_text, localizations.wordWrap, () => setState(() => _wrap = !_wrap),
                tint: _wrap ? color : null),
            _iconBtn(Icons.copy, localizations.copy, _copy),
            _iconBtn(Icons.delete_outline, localizations.clear, _clear),
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
          case 'ascii':
            _setShowAscii(!_showAscii);
          case 'unicode':
            _setShowUnicode(!_showUnicode);
          case 'report':
            _showSpecialReport();
          case 'smooth':
            setState(() => _smooth = !_smooth);
          case 'smoothKeepIme':
            _setSmoothKeepIme(!_smoothKeepIme);
          case 'selectLine':
            _selectToLine();
          case 'replaceLine':
            _replaceCurrentLine();
          case 'minify':
            _minify();
          case 'minifyAggressive':
            _minifyAggressive();
          case 'retainMode':
            _pickRetainMode();
          case 'newline':
            _pickNewline();
        }
      },
      itemBuilder: (context) => [
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
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: 'smooth',
          checked: _smooth,
          child: Text(localizations.editorSmoothMode),
        ),
        CheckedPopupMenuItem(
          value: 'smoothKeepIme',
          checked: _smoothKeepIme,
          child: Text(localizations.editorSmoothKeepIme),
        ),
        PopupMenuItem(value: 'selectLine', child: Text(localizations.editorSelectToLine)),
        PopupMenuItem(value: 'replaceLine', child: Text(localizations.editorReplaceLine)),
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
      ],
    );
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
        decoration: BoxDecoration(border: Border.all(color: Colors.black12)),
        child: CodeForge(
          // CodeForge 的 language / lineWrap 是 late final，切换得新 key 重建；
          // controller / findController / undoController 在文档对象持有，重建不丢数据。
          key: ValueKey('text-editor-${_doc!.id}-${_lang.label}-$_wrap-$_smooth-$_smoothKeepIme'),
          controller: controller,
          findController: _doc!.findController,
          undoController: _doc!.undoController,
          // 流畅模式：关高亮 / 折叠 / 自动换行，换取超长文本下的流畅度。
          // 输入法候选建议是否一并关闭，由「保留输入法」开关决定（默认保留，不牺牲输入法）。
          lineWrap: _wrap && !_smooth,
          language: _smooth ? null : _lang.mode,
          enableGuideLines: false,
          enableFolding: !_smooth,
          enableLocalSuggestions: false,
          enableKeyboardSuggestions: !_smooth || _smoothKeepIme,
          editorTheme: editorTheme,
          textStyle: const TextStyle(fontSize: 13),
          finderBuilder: (c, controller) => FindPanelView(controller: controller),
          selectionStyle: CodeSelectionStyle(cursorColor: Theme.of(context).colorScheme.primary),
          invisibleChars: _invisibleCharsStyle,
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
