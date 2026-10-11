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
import 'package:charset/charset.dart' as charset;

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/text_editor_prefs.dart';

/// 编辑器读写文件时可选的一种编码。
///
/// 展示名与常见编辑器（如 MT 管理器）保持一致；实际转换优先走内置实现
/// （UTF-8 / UTF-16 / UTF-32），其余交给 `charset` 包。
class EditorEncoding {
  final String name;
  final Encoding? codec;

  const EditorEncoding(this.name, this.codec);

  bool get isUtf8 => name == 'UTF-8';
  bool get isUtf8Bom => name == 'UTF-8-BOM';
  bool get isUtf16Le => name == 'UTF-16LE';
  bool get isUtf16Be => name == 'UTF-16BE';
  bool get isUtf32Le => name == 'UTF-32LE';
  bool get isUtf32Be => name == 'UTF-32BE';

  String decode(List<int> bytes) {
    if (isUtf8) return utf8.decode(bytes, allowMalformed: true);
    if (isUtf8Bom) {
      final b = (bytes.length >= 3 &&
              bytes[0] == 0xEF &&
              bytes[1] == 0xBB &&
              bytes[2] == 0xBF)
          ? bytes.sublist(3)
          : bytes;
      return utf8.decode(b, allowMalformed: true);
    }
    if (isUtf16Le) return _decodeU16(bytes, true);
    if (isUtf16Be) return _decodeU16(bytes, false);
    if (isUtf32Le) return _decodeU32(bytes, true);
    if (isUtf32Be) return _decodeU32(bytes, false);
    try {
      return codec?.decode(bytes) ?? latin1.decode(bytes, allowInvalid: true);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  Uint8List encode(String text) {
    if (isUtf8) return utf8.encode(text);
    if (isUtf8Bom) {
      return Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);
    }
    if (isUtf16Le) return _encodeU16(text, true);
    if (isUtf16Be) return _encodeU16(text, false);
    if (isUtf32Le) return _encodeU32(text, true);
    if (isUtf32Be) return _encodeU32(text, false);
    try {
      return codec?.encode(text) ?? utf8.encode(text);
    } catch (_) {
      return utf8.encode(text);
    }
  }

  static String _decodeU16(List<int> bytes, bool little) {
    var start = 0;
    if (bytes.length >= 2) {
      final a = bytes[0];
      final b = bytes[1];
      if ((a == 0xFF && b == 0xFE) || (a == 0xFE && b == 0xFF)) start = 2;
    }
    final units = <int>[];
    for (var i = start; i + 1 < bytes.length; i += 2) {
      units.add(little
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }

  static Uint8List _encodeU16(String text, bool little) {
    final out = BytesBuilder();
    out.addByte(little ? 0xFF : 0xFE);
    out.addByte(little ? 0xFE : 0xFF);
    for (final u in text.codeUnits) {
      if (little) {
        out.addByte(u & 0xFF);
        out.addByte((u >> 8) & 0xFF);
      } else {
        out.addByte((u >> 8) & 0xFF);
        out.addByte(u & 0xFF);
      }
    }
    return out.toBytes();
  }

  static String _decodeU32(List<int> bytes, bool little) {
    var start = 0;
    if (bytes.length >= 4) {
      if (little && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        start = 4;
      } else if (!little && bytes[0] == 0x00 && bytes[1] == 0x00 &&
          bytes[2] == 0xFE && bytes[3] == 0xFF) {
        start = 4;
      }
    }
    final out = <int>[];
    for (var i = start; i + 3 < bytes.length; i += 4) {
      final cp = little
          ? bytes[i] | (bytes[i + 1] << 8) | (bytes[i + 2] << 16) | (bytes[i + 3] << 24)
          : (bytes[i] << 24) | (bytes[i + 1] << 16) | (bytes[i + 2] << 8) | bytes[i + 3];
      out.add(cp & 0x10FFFF);
    }
    return String.fromCharCodes(out);
  }

  static Uint8List _encodeU32(String text, bool little) {
    final out = BytesBuilder();
    if (little) {
      out.add(<int>[0xFF, 0xFE, 0x00, 0x00]);
    } else {
      out.add(<int>[0x00, 0x00, 0xFE, 0xFF]);
    }
    for (final cp in text.runes) {
      if (little) {
        out.addByte(cp & 0xFF);
        out.addByte((cp >> 8) & 0xFF);
        out.addByte((cp >> 16) & 0xFF);
        out.addByte((cp >> 24) & 0xFF);
      } else {
        out.addByte((cp >> 24) & 0xFF);
        out.addByte((cp >> 16) & 0xFF);
        out.addByte((cp >> 8) & 0xFF);
        out.addByte(cp & 0xFF);
      }
    }
    return out.toBytes();
  }
}

/// 编码列表顺序（与常见编辑器一致）。`charset` 不支持的会自动跳过。
const List<String> _kEncodingNames = <String>[
  'UTF-8', 'UTF-8-BOM', 'UTF-16BE', 'UTF-16LE', 'UTF-32BE', 'UTF-32LE',
  'GB2312', 'GB18030', 'GBK', 'Big5', 'Big5-HKSCS', 'CESU-8',
  'EUC-JP', 'EUC-KR', 'IBM866', 'IBM850', 'ISO-2022-JP', 'ISO-2022-KR',
  'ISO-8859-1', 'ISO-8859-2', 'ISO-8859-3', 'ISO-8859-4', 'ISO-8859-5',
  'ISO-8859-6', 'ISO-8859-7', 'ISO-8859-8', 'ISO-8859-9', 'ISO-8859-10',
  'ISO-8859-11', 'ISO-8859-13', 'ISO-8859-14', 'ISO-8859-15',
  'KOI8-R', 'KOI8-U', 'ShiftJIS',
  'Windows-1250', 'Windows-1251', 'Windows-1252', 'Windows-1253',
  'Windows-1254', 'Windows-1255', 'Windows-1256', 'Windows-1257',
  'Windows-1258',
];

/// 全部可用编码（无法解析的已剔除）。
final List<EditorEncoding> kEncodings = _buildEncodings();

List<EditorEncoding> _buildEncodings() {
  final out = <EditorEncoding>[];
  for (final n in _kEncodingNames) {
    if (n == 'UTF-8' ||
        n == 'UTF-8-BOM' ||
        n.startsWith('UTF-16') ||
        n.startsWith('UTF-32')) {
      out.add(EditorEncoding(n, null));
      continue;
    }
    final c = charset.Charset.getByName(n);
    if (c != null) out.add(EditorEncoding(n, c));
  }
  return out;
}

/// 默认编码（列表第一项）。
EditorEncoding get defaultEncoding =>
    kEncodings.isNotEmpty ? kEncodings.first : const EditorEncoding('UTF-8', null);

/// 弹出编码选择框（长列表 + 关闭按钮，风格与常见编辑器一致）。
Future<EditorEncoding?> showEncodingPicker(
  BuildContext context,
  EditorEncoding current, {
  required String title,
}) {
  return showDialog<EditorEncoding>(
    context: context,
    builder: (ctx) => _EncodingDialog(title: title, current: current),
  );
}

class _EncodingDialog extends StatefulWidget {
  const _EncodingDialog({required this.title, required this.current});

  final String title;
  final EditorEncoding current;

  @override
  State<_EncodingDialog> createState() => _EncodingDialogState();
}

class _EncodingDialogState extends State<_EncodingDialog> {
  final TextEditingController _filter = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final list = _query.isEmpty
        ? kEncodings
        : kEncodings
            .where((e) => e.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 340,
        height: 420,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: _filter,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: loc.search,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final e = list[i];
                final selected = e.name == widget.current.name;
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: selected ? Theme.of(context).colorScheme.primary : null,
                  ),
                  title: Text(e.name, style: const TextStyle(fontSize: 13.5)),
                  onTap: () => Navigator.pop(context, e),
                );
              },
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(loc.close),
        ),
      ],
    );
  }
}

/// 「语法」选择对话框：列出现有语言，可按名称筛选，并提供「管理」入口。
class SyntaxPickerDialog extends StatefulWidget {
  const SyntaxPickerDialog({
    super.key,
    required this.items,
    required this.current,
  });

  /// (label, mode) 列表，label 即实际写入文档的语法名。
  final List<(String, Object?)> items;
  final String current;

  @override
  State<SyntaxPickerDialog> createState() => _SyntaxPickerDialogState();
}

class _SyntaxPickerDialogState extends State<SyntaxPickerDialog> {
  final TextEditingController _filter = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final q = _query.toLowerCase();
    final list = _query.isEmpty
        ? widget.items
        : widget.items.where((e) => e.$1.toLowerCase().contains(q)).toList();
    return AlertDialog(
      title: Text(loc.editorMoreSyntax),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 340,
        height: 440,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: _filter,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: loc.search,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final e = list[i];
                final selected = e.$1 == widget.current;
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: selected ? Theme.of(context).colorScheme.primary : null,
                  ),
                  title: Text(e.$1, style: const TextStyle(fontSize: 13.5)),
                  onTap: () => Navigator.pop(context, e.$1),
                );
              },
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final langs = widget.items.map((e) => e.$1).toList();
            await showDialog<void>(
              context: context,
              builder: (_) => LanguageManagerDialog(allLangs: langs),
            );
          },
          child: Text(loc.editorMenuManage),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(loc.close),
        ),
      ],
    );
  }
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
