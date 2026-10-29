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
import 'dart:io';
import 'dart:typed_data';
import 'package:charset/charset.dart' as charset;
import 'package:charset_converter/charset_converter.dart';
import 'package:proxypin/utils/big5_codec.dart';

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/text_editor_prefs.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/utils/custom_lang.dart';
import 'package:proxypin/utils/lang_meta.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:re_highlight/languages/all.dart';

/// 编辑器读写文件时可选的一种编码。
///
/// 解码 / 编码按下面的顺序逐级回退，保证任何平台上都不会「无解」：
/// 1. 内置实现（UTF-8 / UTF-16 / UTF-32 / CESU-8 / ISO-2022-JP·KR）；
/// 2. 纯 Dart codec（`enough_convert` 的 Big5、`charset` 的 GBK / EUC / ShiftJIS /
///    ISO-8859 / Windows-125x 等）；
/// 3. 平台原生 ICU（`charset_converter`）；
/// 4. 最后以 Latin-1 容错解码，至少不抛异常。
class EditorEncoding {
  final String name;

  /// 纯 Dart codec，可能为 null。
  final Encoding? codec;

  /// 交给平台原生转换器时使用的名字；null 表示不走原生。
  final String? nativeName;

  const EditorEncoding(this.name, this.codec, [this.nativeName]);

  bool get isUtf8 => name == 'UTF-8';
  bool get isUtf8Bom => name == 'UTF-8-BOM';
  bool get isUtf16Le => name == 'UTF-16LE';
  bool get isUtf16Be => name == 'UTF-16BE';
  bool get isUtf32Le => name == 'UTF-32LE';
  bool get isUtf32Be => name == 'UTF-32BE';
  bool get isCesu8 => name == 'CESU-8';
  bool get isIso2022Jp => name == 'ISO-2022-JP';
  bool get isIso2022Kr => name == 'ISO-2022-KR';

  /// 该编码在当前平台是否走原生实现（用于界面提示）。
  bool get usesNative => !isUtf8 &&
      !isUtf8Bom &&
      !isUtf16Le &&
      !isUtf16Be &&
      !isUtf32Le &&
      !isUtf32Be &&
      !isCesu8 &&
      !isIso2022Jp &&
      !isIso2022Kr &&
      codec == null;

  Future<String> decode(List<int> bytes) async {
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
    if (isCesu8) return _decodeCesu8(bytes);
    if (isIso2022Jp) return _decodeIso2022(bytes, charset.eucJp);
    if (isIso2022Kr) return _decodeIso2022(bytes, charset.eucKr);

    final c = codec;
    if (c != null) {
      try {
        return c.decode(bytes);
      } catch (_) {
        // 继续尝试原生。
      }
    }
    final n = nativeName;
    if (n != null) {
      try {
        return await CharsetConverter.decode(n, Uint8List.fromList(bytes));
      } catch (_) {
        // 继续兜底。
      }
    }
    return latin1.decode(bytes, allowInvalid: true);
  }

  Future<Uint8List> encode(String text) async {
    if (isUtf8) return utf8.encode(text);
    if (isUtf8Bom) {
      return Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);
    }
    if (isUtf16Le) return _encodeU16(text, true);
    if (isUtf16Be) return _encodeU16(text, false);
    if (isUtf32Le) return _encodeU32(text, true);
    if (isUtf32Be) return _encodeU32(text, false);
    if (isCesu8) return _encodeCesu8(text);
    if (isIso2022Jp) return _encodeIso2022(text, charset.eucJp, kr: false);
    if (isIso2022Kr) return _encodeIso2022(text, charset.eucKr, kr: true);

    final c = codec;
    if (c != null) {
      try {
        return Uint8List.fromList(c.encode(text));
      } catch (_) {
        // 继续尝试原生。
      }
    }
    final n = nativeName;
    if (n != null) {
      try {
        return await CharsetConverter.encode(n, text);
      } catch (_) {
        // 继续兜底。
      }
    }
    return utf8.encode(text);
  }

  // ------------------------------------------------------------ 内置实现

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
      } else if (!little &&
          bytes[0] == 0x00 &&
          bytes[1] == 0x00 &&
          bytes[2] == 0xFE &&
          bytes[3] == 0xFF) {
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

  /// CESU-8：把每个 UTF-16 code unit 单独按 3 字节以内的 UTF-8 形式编码，
  /// 代理对因此会变成两个 3 字节序列（而不是标准 UTF-8 的 4 字节）。
  static String _decodeCesu8(List<int> bytes) {
    final out = <int>[];
    var i = 0;
    while (i < bytes.length) {
      final c = bytes[i];
      if (c < 0x80) {
        out.add(c);
        i += 1;
      } else if (c < 0xE0 && i + 1 < bytes.length) {
        out.add(((c & 0x1F) << 6) | (bytes[i + 1] & 0x3F));
        i += 2;
      } else if (i + 2 < bytes.length) {
        out.add(((c & 0x0F) << 12) |
            ((bytes[i + 1] & 0x3F) << 6) |
            (bytes[i + 2] & 0x3F));
        i += 3;
      } else {
        break;
      }
    }
    return String.fromCharCodes(out);
  }

  static Uint8List _encodeCesu8(String text) {
    final out = BytesBuilder();
    for (final u in text.codeUnits) {
      if (u < 0x80) {
        out.addByte(u);
      } else if (u < 0x800) {
        out.addByte(0xC0 | (u >> 6));
        out.addByte(0x80 | (u & 0x3F));
      } else {
        out.addByte(0xE0 | (u >> 12));
        out.addByte(0x80 | ((u >> 6) & 0x3F));
        out.addByte(0x80 | (u & 0x3F));
      }
    }
    return out.toBytes();
  }

  /// ISO-2022-JP / KR 解码：把转义序列切换出来的双字节区（JIS X 0208 / KS X 1001）
  /// 还原成 EUC 字节（每字节 +0x80），ASCII 区原样保留，最后交给 EUC 解码器。
  /// 这样不依赖任何大表，也就能在全平台工作。
  static String _decodeIso2022(List<int> bytes, Encoding euc) {
    final out = <int>[];
    var i = 0;
    var doubleByte = false;
    while (i < bytes.length) {
      final b = bytes[i];
      if (b == 0x1B && i + 1 < bytes.length) {
        final b1 = bytes[i + 1];
        if (b1 == 0x24) {
          // ESC $ ( ... ) : 进入双字节区
          if (i + 3 < bytes.length && bytes[i + 2] == 0x29) {
            i += 4;
          } else {
            i += 3;
          }
          doubleByte = true;
          continue;
        }
        if (b1 == 0x28) {
          // ESC ( B / J / I : 回到单字节区
          i += 3;
          doubleByte = false;
          continue;
        }
        i += 2;
        continue;
      }
      if (doubleByte && b >= 0x21 && i + 1 < bytes.length && bytes[i + 1] >= 0x21) {
        out.add(b | 0x80);
        out.add(bytes[i + 1] | 0x80);
        i += 2;
        continue;
      }
      out.add(b);
      i += 1;
    }
    try {
      return euc.decode(out);
    } catch (_) {
      return latin1.decode(out, allowInvalid: true);
    }
  }

  static Uint8List _encodeIso2022(String text, Encoding euc, {required bool kr}) {
    final eucBytes = euc.encode(text);
    final out = BytesBuilder();
    if (kr) out.add(<int>[0x1B, 0x24, 0x29, 0x43]);
    var doubleByte = false;
    for (var i = 0; i < eucBytes.length; i++) {
      final b = eucBytes[i];
      if (b < 0x80) {
        if (doubleByte) {
          out.add(<int>[0x1B, 0x28, 0x42]);
          doubleByte = false;
        }
        out.addByte(b);
      } else if (b >= 0xA1) {
        if (!doubleByte) {
          out.add(<int>[0x1B, 0x24, 0x42]);
          doubleByte = true;
        }
        out.addByte(b & 0x7F);
      } else {
        // 0x80-0xA0（半角假名等）在 ISO-2022 里没有直接对应，用空格占位。
        if (doubleByte) {
          out.add(<int>[0x1B, 0x28, 0x42]);
          doubleByte = false;
        }
        out.addByte(0x20);
      }
    }
    if (doubleByte) out.add(<int>[0x1B, 0x28, 0x42]);
    return out.toBytes();
  }
}

/// 编码列表顺序（与常见编辑器一致）。
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

/// 全部可用编码。
final List<EditorEncoding> kEncodings = _buildEncodings();

/// 有内置实现的编码。
bool _isBuiltinEncoding(String n) =>
    n == 'UTF-8' ||
    n == 'UTF-8-BOM' ||
    n == 'CESU-8' ||
    n == 'ISO-2022-JP' ||
    n == 'ISO-2022-KR' ||
    n.startsWith('UTF-16') ||
    n.startsWith('UTF-32');

List<EditorEncoding> _buildEncodings() {
  final out = <EditorEncoding>[];
  for (final n in _kEncodingNames) {
    if (_isBuiltinEncoding(n)) {
      out.add(EditorEncoding(n, null, n));
      continue;
    }
    if (n == 'Big5' || n == 'Big5-HKSCS') {
      // WHATWG 索引表自带 HKSCS 扩展，Big5 与 Big5-HKSCS 共用同一实现，
      // 纯 Dart、全平台一致，不再依赖原生。
      out.add(EditorEncoding(n, Big5HkscsCodec(n)));
      continue;
    }
    out.add(EditorEncoding(n, charset.Charset.getByName(n), n));
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
  // 工具栏分类菜单（文件/编辑/代码/视图/检查）里出现的项，也要能在这里统一隐藏。
  EditorMenuItem('newFile', _newFileLabel),
  EditorMenuItem('open', _openLabel),
  EditorMenuItem('save', _saveLabel),
  EditorMenuItem('docs', _docsLabel),
  EditorMenuItem('undo', _undoLabel),
  EditorMenuItem('redo', _redoLabel),
  EditorMenuItem('copy', _copyLabel),
  EditorMenuItem('clear', _clearLabel),
  EditorMenuItem('comment', _commentLabel),
  EditorMenuItem('format', _formatLabel),
  EditorMenuItem('formatSel', _formatSelLabel),
  EditorMenuItem('preview', _previewLabel),
  EditorMenuItem('symbols', _symbolsLabel),
  EditorMenuItem('gotoDef', _gotoDefLabel),
  EditorMenuItem('references', _referencesLabel),
  EditorMenuItem('rename', _renameLabel),
  EditorMenuItem('foldAll', _foldAllLabel),
  EditorMenuItem('unfoldAll', _unfoldAllLabel),
  EditorMenuItem('nextOccurrence', _nextOccurrenceLabel),
  EditorMenuItem('lineOps', _lineOpsLabel),
  EditorMenuItem('caseOps', _caseOpsLabel),
  EditorMenuItem('lint', _lintLabel),
  EditorMenuItem('lintIssues', _lintIssuesLabel),
  EditorMenuItem('console', _consoleLabel),
  EditorMenuItem('lintRules', _lintRulesLabel),
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
String _newFileLabel(AppLocalizations l) => l.editorNewFile;
String _openLabel(AppLocalizations l) => l.selectFile;
String _saveLabel(AppLocalizations l) => l.save;
String _docsLabel(AppLocalizations l) => l.editorDocuments;
String _undoLabel(AppLocalizations l) => l.editorUndo;
String _redoLabel(AppLocalizations l) => l.editorRedo;
String _copyLabel(AppLocalizations l) => l.copy;
String _clearLabel(AppLocalizations l) => l.clear;
String _commentLabel(AppLocalizations l) => l.editorToggleComment;
String _formatLabel(AppLocalizations l) => l.format;
String _formatSelLabel(AppLocalizations l) => l.editorFormatSelection;
String _previewLabel(AppLocalizations l) => l.editorPreview;
String _symbolsLabel(AppLocalizations l) => l.editorSymbols;
String _gotoDefLabel(AppLocalizations l) => l.editorGotoDefinition;
String _referencesLabel(AppLocalizations l) => l.editorReferences;
String _renameLabel(AppLocalizations l) => l.editorRename;
String _foldAllLabel(AppLocalizations l) => l.editorFoldAll;
String _unfoldAllLabel(AppLocalizations l) => l.editorUnfoldAll;
String _nextOccurrenceLabel(AppLocalizations l) => l.editorSelectNext;
String _lineOpsLabel(AppLocalizations l) => l.editorLineOps;
String _caseOpsLabel(AppLocalizations l) => l.editorCaseOps;
String _lintLabel(AppLocalizations l) => l.editorLint;
String _lintIssuesLabel(AppLocalizations l) => l.editorLintIssues;
String _consoleLabel(AppLocalizations l) => l.editorConsole;
String _lintRulesLabel(AppLocalizations l) => l.editorLintAllRules;

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
  // 把已经做好的能力接到长按菜单上：长按选词是最顺手的入口，
  // 让用户再回头去找工具栏或子菜单反而绕。
  FloatMenuItem('selectNext', _fSelectNext),
  FloatMenuItem('gotoDef', _fGotoDef),
  FloatMenuItem('upper', _fUpper),
  FloatMenuItem('lower', _fLower),
  FloatMenuItem('formatSel', _fFormatSel),
  FloatMenuItem('rename', _fRename),
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
String _fSelectNext(AppLocalizations l) => l.editorSelectNext;
String _fGotoDef(AppLocalizations l) => l.editorGotoDefinition;
String _fUpper(AppLocalizations l) => l.editorUpperCase;
String _fLower(AppLocalizations l) => l.editorLowerCase;
String _fFormatSel(AppLocalizations l) => l.editorFormatSelection;
String _fRename(AppLocalizations l) => l.editorRename;

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

/// 语法文件管理：勾选要出现在「语法」菜单里的语言、维护自定义语法、导入 / 导出配置。
///
/// [allLangs] 是内核支持的全部语言 label（内置语言）。
class LanguageManagerDialog extends StatefulWidget {
  const LanguageManagerDialog({super.key, required this.allLangs});

  final List<String> allLangs;

  @override
  State<LanguageManagerDialog> createState() => _LanguageManagerDialogState();
}

class _LanguageManagerDialogState extends State<LanguageManagerDialog> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  final TextEditingController _search = TextEditingController();
  late Set<String> _enabled;
  List<CustomLang> _custom = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    final saved = TextEditorPrefsStore.notifier.value.enabledLangs;
    _enabled = saved.isEmpty ? widget.allLangs.toSet() : saved.toSet();
    CustomLangStore.instance.then((store) {
      if (mounted) setState(() => _custom = store.langs);
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final size = MediaQuery.of(context).size;
    return AlertDialog(
      title: Text(loc.editorSyntaxManager),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: (size.width * 0.86).clamp(260.0, 400.0),
        height: (size.height * 0.6).clamp(300.0, 440.0),
        child: Column(children: [
          TabBar(
            controller: _tab,
            tabs: [
              Tab(text: loc.syntaxTabBuiltin),
              Tab(text: '${loc.syntaxTabCustom} (${_custom.length})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [_buildBuiltin(loc), _buildCustom(loc)],
            ),
          ),
        ]),
      ),
      actionsOverflowButtonSpacing: 2,
      actions: [
        IconButton(
          onPressed: _import,
          icon: const Icon(Icons.file_open_outlined, size: 20),
          tooltip: loc.syntaxImport,
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          onPressed: _export,
          icon: const Icon(Icons.save_alt, size: 20),
          tooltip: loc.syntaxExport,
          visualDensity: VisualDensity.compact,
        ),
        TextButton(
          onPressed: () => setState(() => _enabled = widget.allLangs.toSet()),
          child: Text(loc.editorReset),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(loc.cancel)),
        FilledButton(onPressed: _save, child: Text(loc.confirm)),
      ],
    );
  }

  /// 内置语言：勾选后才会出现在「语法」菜单里。
  Widget _buildBuiltin(AppLocalizations loc) {
    final q = _query.toLowerCase();
    final list = q.isEmpty
        ? widget.allLangs
        : widget.allLangs.where((l) => l.toLowerCase().contains(q)).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: TextField(
          controller: _search,
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
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(loc.editorLangManagerHint,
              style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
        ),
      ),
      Expanded(
        child: ListView(
          children: list
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
    ]);
  }

  /// 自定义语法：借用内置高亮 + 自定名字 / 注释风格。
  Widget _buildCustom(AppLocalizations loc) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(loc.syntaxCustomHint,
                style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
          ),
          TextButton.icon(
            onPressed: () => _editCustom(null),
            icon: const Icon(Icons.add, size: 18),
            label: Text(loc.syntaxAdd),
          ),
        ]),
      ),
      Expanded(
        child: _custom.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(loc.syntaxCustomEmpty,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ),
              )
            : ListView(
                children: _custom.map((c) {
                  final baseKey = c.baseKey ?? '';
                  final base = baseKey.isEmpty ? loc.custLangBaseNone : langLabelOf(baseKey);
                  final fam = c.family == null ? loc.custLangFamilyAuto : familyLabel(loc, c.family!);
                  final words = c.allWords.length;
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(c.name, style: const TextStyle(fontSize: 13.5)),
                    subtitle: Text(
                        '${loc.custLangBase}: $base · ${loc.custLangFamily}: $fam'
                        '${words > 0 ? ' · ${loc.custLangKeywords} ×$words' : ''}',
                        style: const TextStyle(fontSize: 11)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        onPressed: () => _editCustom(c),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        tooltip: loc.edit,
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        onPressed: () => _removeCustom(c),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        tooltip: loc.delete,
                        visualDensity: VisualDensity.compact,
                      ),
                    ]),
                  );
                }).toList(),
              ),
      ),
    ]);
  }

  Future<void> _save() async {
    // 全部启用时存空列表（等价于默认）。
    final list = _enabled.length == widget.allLangs.length ? <String>[] : _enabled.toList();
    await TextEditorPrefsStore.update(
        TextEditorPrefsStore.notifier.value.copyWith(enabledLangs: list));
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _editCustom(CustomLang? existing) async {
    final taken = <String>{
      ...widget.allLangs,
      ..._custom.map((c) => c.name),
    }..remove(existing?.name);
    final result = await showDialog<CustomLang>(
      context: context,
      builder: (_) => _CustomLangEditorDialog(existing: existing, takenNames: taken),
    );
    if (result == null) return;
    final store = await CustomLangStore.instance;
    if (existing == null) {
      await store.add(result);
    } else {
      await store.update(existing.name, result);
    }
    if (mounted) setState(() => _custom = store.langs);
  }

  Future<void> _removeCustom(CustomLang lang) async {
    final store = await CustomLangStore.instance;
    await store.remove(lang.name);
    if (mounted) setState(() => _custom = store.langs);
  }

  /// 导入语法配置：同名覆盖、新名追加，并同步文件里携带的语言显示勾选。
  Future<void> _import() async {
    final loc = AppLocalizations.of(context)!;
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (picked == null || picked.isEmpty) return;
      final text = await picked.single.xFile.readAsString();
      final (langs, enabled) = CustomLangStore.parseExport(text);
      if (langs.isEmpty && enabled == null) {
        if (mounted) FlutterToastr.show(loc.syntaxImportEmpty, context, duration: 3);
        return;
      }
      final store = await CustomLangStore.instance;
      final (added, updated) = await store.merge(langs);
      if (enabled != null) {
        final list = enabled.length == widget.allLangs.length ? <String>[] : enabled;
        await TextEditorPrefsStore.update(
            TextEditorPrefsStore.notifier.value.copyWith(enabledLangs: list));
      }
      if (!mounted) return;
      setState(() {
        _custom = store.langs;
        if (enabled != null) {
          _enabled = enabled.isEmpty ? widget.allLangs.toSet() : enabled.toSet();
        }
      });
      FlutterToastr.show(loc.syntaxImportDone('$added', '$updated'), context, duration: 3);
    } catch (e, t) {
      logger.e('导入语法配置失败', error: e, stackTrace: t);
      if (mounted) FlutterToastr.show('${loc.syntaxImportFailed}: $e', context, duration: 3);
    }
  }

  /// 导出自定义语法 + 语言显示勾选。
  Future<void> _export() async {
    final loc = AppLocalizations.of(context)!;
    try {
      final store = await CustomLangStore.instance;
      final enabled = _enabled.length == widget.allLangs.length ? <String>[] : _enabled.toList();
      final bytes = Uint8List.fromList(utf8.encode(store.buildExportPayload(enabled)));
      const fileName = 'proxypin-syntax.json';
      if (Platforms.isDesktop()) {
        // 桌面端 file_picker 在部分平台不真正写入 bytes，沿用「只拿路径、自己写盘」的惯例。
        final path = await Platforms.saveFileAdaptive(
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        if (path == null) return;
        await File(path).writeAsBytes(bytes);
      } else {
        final uri = await FilePicker.saveFile(
          fileName: fileName,
          bytes: bytes,
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        if (uri == null) return;
      }
      if (mounted) FlutterToastr.show(loc.syntaxExportDone, context, duration: 3);
    } catch (e, t) {
      logger.e('导出语法配置失败', error: e, stackTrace: t);
      if (mounted) FlutterToastr.show('${loc.syntaxExportFailed}: $e', context, duration: 3);
    }
  }
}

/// 内置语言 key 的展示名（找不到就退回 key 本身）。
String langLabelOf(String key) => builtinAllLanguages[key]?.name ?? key;

/// 语言族的可读描述（技术串，跨语言通用，不做本地化）。
String familyLabel(AppLocalizations loc, LangFamily family) {
  switch (family) {
    case LangFamily.c:
      return '//  /* */  (C / Java / Go)';
    case LangFamily.hash:
      return '#  (Python / Shell / YAML)';
    case LangFamily.sql:
      return '--  (SQL / Haskell / Lua)';
    case LangFamily.xml:
      return '<!-- -->  (HTML / XML)';
    case LangFamily.lisp:
      return ';  (Lisp / asm / ini)';
    case LangFamily.percent:
      return '%  (Erlang / MATLAB / LaTeX)';
    case LangFamily.vb:
      return "'  (Visual Basic)";
    case LangFamily.batch:
      return 'REM  (Batch)';
    case LangFamily.fortran:
      return '!  (Fortran)';
    case LangFamily.none:
      return loc.custLangFamilyNone;
  }
}

/// 新增 / 编辑一条自定义语法。
///
/// 关键是**关键字可以直接填**：填了就由这些词构造高亮与补全，不再受内核内置
/// 语言表限制；只填「高亮基础」时就退化成借用内置高亮。
class _CustomLangEditorDialog extends StatefulWidget {
  const _CustomLangEditorDialog({this.existing, required this.takenNames});

  final CustomLang? existing;

  /// 已被内置语言或其它自定义语法占用的名字（不含正在编辑的这一条）。
  final Set<String> takenNames;

  @override
  State<_CustomLangEditorDialog> createState() => _CustomLangEditorDialogState();
}

class _CustomLangEditorDialogState extends State<_CustomLangEditorDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _keywords =
      TextEditingController(text: (widget.existing?.keywords ?? const []).join(' '));
  late final TextEditingController _builtIns =
      TextEditingController(text: (widget.existing?.builtIns ?? const []).join(' '));
  late final TextEditingController _literals =
      TextEditingController(text: (widget.existing?.literals ?? const []).join(' '));
  late String _base = widget.existing?.baseKey ?? '';
  late String _familyName = widget.existing?.family?.name ?? 'auto';
  late bool _caseInsensitive = widget.existing?.caseInsensitive ?? false;

  @override
  void dispose() {
    _name.dispose();
    _keywords.dispose();
    _builtIns.dispose();
    _literals.dispose();
    super.dispose();
  }

  /// 按空格 / 逗号 / 分号 / 换行切词。
  static List<String> _parseWords(String raw) => raw
      .split(RegExp(r'[\s,;，；、]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final size = MediaQuery.of(context).size;
    final bases = builtinAllLanguages.keys.toList()
      ..sort((a, b) => langLabelOf(a).toLowerCase().compareTo(langLabelOf(b).toLowerCase()));
    return AlertDialog(
      title: Text(widget.existing == null ? loc.syntaxAdd : loc.syntaxEditLang),
      content: SizedBox(
        width: (size.width * 0.86).clamp(260.0, 420.0),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                isDense: true,
                labelText: loc.custLangName,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keywords,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                isDense: true,
                labelText: loc.custLangKeywords,
                helperText: loc.custLangWordsHint,
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _builtIns,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                isDense: true,
                labelText: loc.custLangBuiltIns,
                helperText: loc.custLangWordsHint,
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _literals,
              minLines: 1,
              maxLines: 2,
              decoration: InputDecoration(
                isDense: true,
                labelText: loc.custLangLiterals,
                helperText: loc.custLangWordsHint,
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _base,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                labelText: loc.custLangBase,
                helperText: loc.custLangBaseHint,
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: '', child: Text(loc.custLangBaseNone)),
                ...bases.map((k) => DropdownMenuItem(
                      value: k,
                      child: Text('${langLabelOf(k)}  ·  $k', overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (v) => setState(() => _base = v ?? ''),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _familyName,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                labelText: loc.custLangFamily,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 'auto', child: Text(loc.custLangFamilyAuto)),
                ...LangFamily.values.map((f) => DropdownMenuItem(
                      value: f.name,
                      child: Text(familyLabel(loc, f), overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (v) => setState(() => _familyName = v ?? 'auto'),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              value: _caseInsensitive,
              title: Text(loc.custLangCaseInsensitive, style: const TextStyle(fontSize: 13)),
              onChanged: (v) => setState(() => _caseInsensitive = v),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(loc.cancel)),
        FilledButton(onPressed: _submit, child: Text(loc.confirm)),
      ],
    );
  }

  void _submit() {
    final loc = AppLocalizations.of(context)!;
    final name = _name.text.trim();
    if (name.isEmpty) {
      FlutterToastr.show(loc.custLangNameRequired, context, duration: 2);
      return;
    }
    if (widget.takenNames.contains(name)) {
      FlutterToastr.show('${loc.custLangNameTaken}: $name', context, duration: 2);
      return;
    }
    final keywords = _parseWords(_keywords.text);
    final builtIns = _parseWords(_builtIns.text);
    final literals = _parseWords(_literals.text);
    if (keywords.isEmpty && builtIns.isEmpty && literals.isEmpty && _base.isEmpty) {
      FlutterToastr.show(loc.custLangNeedWords, context, duration: 3);
      return;
    }
    Navigator.pop(
      context,
      CustomLang(
        name: name,
        baseKey: _base.isEmpty ? null : _base,
        keywords: keywords,
        builtIns: builtIns,
        literals: literals,
        family: _familyName == 'auto' ? null : CustomLang.familyFromName(_familyName),
        caseInsensitive: _caseInsensitive,
      ),
    );
  }
}
