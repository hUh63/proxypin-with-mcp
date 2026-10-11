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

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/text_editor_prefs.dart';

/// 以字节形式读写文件时支持的编码。
enum EditorEncoding { utf8, utf8Bom, latin1, utf16le, utf16be }

extension EditorEncodingX on EditorEncoding {
  String get label {
    switch (this) {
      case EditorEncoding.utf8:
        return 'UTF-8';
      case EditorEncoding.utf8Bom:
        return 'UTF-8 (BOM)';
      case EditorEncoding.latin1:
        return 'ISO-8859-1 (Latin-1)';
      case EditorEncoding.utf16le:
        return 'UTF-16 LE';
      case EditorEncoding.utf16be:
        return 'UTF-16 BE';
    }
  }

  /// 字节 -> 文本。
  String decode(List<int> bytes) {
    switch (this) {
      case EditorEncoding.utf8:
      case EditorEncoding.utf8Bom:
        return utf8.decode(bytes, allowMalformed: true);
      case EditorEncoding.latin1:
        return latin1.decode(bytes, allowInvalid: true);
      case EditorEncoding.utf16le:
        return _decodeUtf16(bytes, true);
      case EditorEncoding.utf16be:
        return _decodeUtf16(bytes, false);
    }
  }

  /// 文本 -> 字节。
  Uint8List encode(String text) {
    switch (this) {
      case EditorEncoding.utf8:
        return utf8.encode(text);
      case EditorEncoding.utf8Bom:
        return Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);
      case EditorEncoding.latin1:
        // 宽容处理：超出 Latin-1 的码位按低 8 位截断，避免抛错。
        return Uint8List.fromList(text.codeUnits.map((c) => c & 0xFF).toList());
      case EditorEncoding.utf16le:
        return _encodeUtf16(text, true);
      case EditorEncoding.utf16be:
        return _encodeUtf16(text, false);
    }
  }

  static String _decodeUtf16(List<int> bytes, bool littleEndian) {
    var start = 0;
    if (bytes.length >= 2) {
      final a = bytes[0];
      final b = bytes[1];
      if ((a == 0xFF && b == 0xFE) || (a == 0xFE && b == 0xFF)) start = 2;
    }
    final units = <int>[];
    for (var i = start; i + 1 < bytes.length; i += 2) {
      units.add(littleEndian ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }

  static Uint8List _encodeUtf16(String text, bool littleEndian) {
    final out = BytesBuilder();
    if (littleEndian) {
      out.addByte(0xFF);
      out.addByte(0xFE);
    } else {
      out.addByte(0xFE);
      out.addByte(0xFF);
    }
    for (final u in text.codeUnits) {
      if (littleEndian) {
        out.addByte(u & 0xFF);
        out.addByte((u >> 8) & 0xFF);
      } else {
        out.addByte((u >> 8) & 0xFF);
        out.addByte(u & 0xFF);
      }
    }
    return out.toBytes();
  }
}

/// 弹出编码选择框。[current] 是当前编码，用于打勾。
Future<EditorEncoding?> showEncodingPicker(BuildContext context, EditorEncoding current,
    {required String title}) {
  final loc = AppLocalizations.of(context)!;
  return showDialog<EditorEncoding>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: EditorEncoding.values
          .map<Widget>((e) => ListTile(
                dense: true,
                title: Text(e.label),
                trailing: e == current ? const Icon(Icons.check, size: 18) : null,
                onTap: () => Navigator.pop(ctx, e),
              ))
          .toList()
        ..add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
            child: Text(loc.editorEncodingHint,
                style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
          ),
        ),
    ),
  );
}

/// 一个可在「工具菜单」里显隐的菜单项。
class EditorMenuItem {
  final String id;
  final String Function(AppLocalizations) label;

  const EditorMenuItem(this.id, this.label);
}

/// 「文字编辑器」更多菜单里所有可配置的项（顺序即菜单顺序）。
const List<EditorMenuItem> kEditorMenuItems = [
  EditorMenuItem('file', _fileLabel),
  EditorMenuItem('search', _searchLabel),
  EditorMenuItem('syntax', _syntaxLabel),
  EditorMenuItem('gotoLine', _gotoLabel),
  EditorMenuItem('navBack', _navBackLabel),
  EditorMenuItem('navForward', _navForwardLabel),
  EditorMenuItem('wrap', _wrapLabel),
  EditorMenuItem('readOnly', _readOnlyLabel),
  EditorMenuItem('smooth', _smoothLabel),
  EditorMenuItem('smart', _smartLabel),
  EditorMenuItem('smoothKeepIme', _keepImeLabel),
  EditorMenuItem('ascii', _asciiLabel),
  EditorMenuItem('unicode', _unicodeLabel),
  EditorMenuItem('report', _reportLabel),
  EditorMenuItem('replaceLine', _replaceLineLabel),
  EditorMenuItem('minify', _minifyLabel),
  EditorMenuItem('minifyAggressive', _minifyAggressiveLabel),
  EditorMenuItem('newline', _newlineLabel),
  EditorMenuItem('retainMode', _retainLabel),
  EditorMenuItem('settings', _settingsLabel),
  EditorMenuItem('close', _closeLabel),
];

String _fileLabel(AppLocalizations l) => l.editorMoreFile;
String _searchLabel(AppLocalizations l) => l.search;
String _syntaxLabel(AppLocalizations l) => l.editorMoreSyntax;
String _gotoLabel(AppLocalizations l) => l.editorSelectToLine;
String _navBackLabel(AppLocalizations l) => l.editorNavBack;
String _navForwardLabel(AppLocalizations l) => l.editorNavForward;
String _wrapLabel(AppLocalizations l) => l.wordWrap;
String _readOnlyLabel(AppLocalizations l) => l.editorReadOnly;
String _smoothLabel(AppLocalizations l) => l.editorSmoothMode;
String _smartLabel(AppLocalizations l) => l.smartCompletion;
String _keepImeLabel(AppLocalizations l) => l.editorSmoothKeepIme;
String _asciiLabel(AppLocalizations l) => l.editorShowAsciiControl;
String _unicodeLabel(AppLocalizations l) => l.editorShowUnicodeSpecial;
String _reportLabel(AppLocalizations l) => l.editorSpecialReport;
String _replaceLineLabel(AppLocalizations l) => l.editorReplaceLine;
String _minifyLabel(AppLocalizations l) => l.editorMinify;
String _minifyAggressiveLabel(AppLocalizations l) => l.editorMinifyAggressive;
String _newlineLabel(AppLocalizations l) => l.editorNewline;
String _retainLabel(AppLocalizations l) => l.editorRetainPref;
String _settingsLabel(AppLocalizations l) => l.editorSettings;
String _closeLabel(AppLocalizations l) => l.editorCloseFile;

/// 可加入长按浮动菜单的项。id 与 [EditorDocument] 侧的处理器对应。
class FloatMenuItem {
  final String id;
  final String Function(AppLocalizations) label;

  const FloatMenuItem(this.id, this.label);
}

const List<FloatMenuItem> kFloatMenuItems = [
  FloatMenuItem('copy', _fCopy),
  FloatMenuItem('cut', _fCut),
  FloatMenuItem('paste', _fPaste),
  FloatMenuItem('selectAll', _fSelectAll),
  FloatMenuItem('comment', _fComment),
  FloatMenuItem('format', _fFormat),
  FloatMenuItem('minify', _fMinify),
  FloatMenuItem('find', _fFind),
  FloatMenuItem('special', _fSpecial),
  FloatMenuItem('replaceLine', _fReplaceLine),
];

String _fCopy(AppLocalizations l) => l.copy;
String _fCut(AppLocalizations l) => l.cut;
String _fPaste(AppLocalizations l) => l.paste;
String _fSelectAll(AppLocalizations l) => l.selectAll;
String _fComment(AppLocalizations l) => l.editorToggleComment;
String _fFormat(AppLocalizations l) => l.format;
String _fMinify(AppLocalizations l) => l.editorMinify;
String _fFind(AppLocalizations l) => l.search;
String _fSpecial(AppLocalizations l) => l.editorSpecialReport;
String _fReplaceLine(AppLocalizations l) => l.editorReplaceLine;

/// 勾选要在「更多」菜单里显示 / 隐藏的项。
class EditorMenuManagerDialog extends StatefulWidget {
  const EditorMenuManagerDialog({super.key});

  @override
  State<EditorMenuManagerDialog> createState() => _EditorMenuManagerDialogState();
}

class _EditorMenuManagerDialogState extends State<EditorMenuManagerDialog> {
  late Set<String> _hidden;

  @override
  void initState() {
    super.initState();
    _hidden = TextEditorPrefsStore.notifier.value.hiddenMenu.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(loc.editorEditToolMenu),
      content: SizedBox(
        width: 380,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.editorMenuHint, style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
            const SizedBox(height: 6),
            Expanded(
              child: ListView(
                children: kEditorMenuItems
                    .map((item) => CheckboxListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          value: !_hidden.contains(item.id),
                          title: Text(item.label(loc), style: const TextStyle(fontSize: 13.5)),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _hidden.remove(item.id);
                              } else {
                                _hidden.add(item.id);
                              }
                            });
                          },
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _hidden = <String>{}),
          child: Text(loc.editorReset),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(loc.cancel)),
        FilledButton(
          onPressed: () async {
            await TextEditorPrefsStore.update(
                TextEditorPrefsStore.notifier.value.copyWith(hiddenMenu: _hidden.toList()));
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(loc.confirm),
        ),
      ],
    );
  }
}

/// 勾选长按浮动菜单里要显示的自定义项。
class FloatMenuManagerDialog extends StatefulWidget {
  const FloatMenuManagerDialog({super.key});

  @override
  State<FloatMenuManagerDialog> createState() => _FloatMenuManagerDialogState();
}

class _FloatMenuManagerDialogState extends State<FloatMenuManagerDialog> {
  late Set<String> _shown;

  @override
  void initState() {
    super.initState();
    _shown = TextEditorPrefsStore.notifier.value.floatMenu.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(loc.editorEditFloatMenu),
      content: SizedBox(
        width: 380,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.editorFloatMenuHint, style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
            const SizedBox(height: 6),
            Expanded(
              child: ListView(
                children: kFloatMenuItems
                    .map((item) => CheckboxListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          value: _shown.contains(item.id),
                          title: Text(item.label(loc), style: const TextStyle(fontSize: 13.5)),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _shown.add(item.id);
                              } else {
                                _shown.remove(item.id);
                              }
                            });
                          },
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => setState(() => _shown = <String>{}), child: Text(loc.editorReset)),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(loc.cancel)),
        FilledButton(
          onPressed: () async {
            await TextEditorPrefsStore.update(
                TextEditorPrefsStore.notifier.value.copyWith(floatMenu: _shown.toList()));
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(loc.confirm),
        ),
      ],
    );
  }
}

/// 勾选要出现在「语法」菜单里的语言。[allLangs] 是内核支持的全部语言 label。
class LanguageManagerDialog extends StatefulWidget {
  const LanguageManagerDialog({super.key, required this.allLangs});

  final List<String> allLangs;

  @override
  State<LanguageManagerDialog> createState() => _LanguageManagerDialogState();
}

class _LanguageManagerDialogState extends State<LanguageManagerDialog> {
  late Set<String> _enabled;

  @override
  void initState() {
    super.initState();
    final saved = TextEditorPrefsStore.notifier.value.enabledLangs;
    _enabled = saved.isEmpty ? widget.allLangs.toSet() : saved.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(loc.editorSyntaxManager),
      content: SizedBox(
        width: 380,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.editorLangManagerHint, style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
            const SizedBox(height: 6),
            Expanded(
              child: ListView(
                children: widget.allLangs
                    .map((l) => CheckboxListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          value: _enabled.contains(l),
                          title: Text(l, style: const TextStyle(fontSize: 13.5)),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _enabled.add(l);
                              } else {
                                _enabled.remove(l);
                              }
                            });
                          },
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => setState(() => _enabled = widget.allLangs.toSet()), child: Text(loc.editorReset)),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(loc.cancel)),
        FilledButton(
          onPressed: () async {
            // 全部启用时存空列表（等价于默认）。
            final list = _enabled.length == widget.allLangs.length ? <String>[] : _enabled.toList();
            await TextEditorPrefsStore.update(
                TextEditorPrefsStore.notifier.value.copyWith(enabledLangs: list));
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(loc.confirm),
        ),
      ],
    );
  }
}
