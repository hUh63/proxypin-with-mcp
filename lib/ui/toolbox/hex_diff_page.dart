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

// 二进制 / 十六进制对比：并排显示两个文件的字节，逐行标出不同的字节。
//
// 对标 Beyond Compare 的 Hex Compare、WinMerge 的二进制模式、010 Editor 的对比视图。
// 文本对比页处理的是「行」，这里处理的是「字节」—— 改过的 so / dex / 序列化数据
// 用文本对比看只会是一堆乱码，hex 视图才能看出「第 0x1F40 处差了 4 个字节」。
//
// 设计取舍：
//   · 分块 16 字节一行（和 hexdump 一致，眼睛熟）；
//   · 只读前 [_maxBytes]（16MB），再大就不是在手机上该干的事；
//   · 「只显示差异」默认开 —— 一个 5MB 的 so 通常只有几十行有差异，
//     全显示的话滚动条根本找不到东西；
//   · 差异行按「对齐后的块」标红具体字节，而不是整行标红，否则看不出改了哪一位。

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';

class HexDiffPage extends StatefulWidget {
  const HexDiffPage({super.key});

  @override
  State<HexDiffPage> createState() => _HexDiffPageState();
}

class _HexDiffPageState extends State<HexDiffPage> {
  /// 单文件最多读这么多（再大 UI 也扛不住）。
  static const int _maxBytes = 16 * 1024 * 1024;

  /// 一行显示多少字节。
  static const int _rowBytes = 16;

  String _leftName = '';
  String _rightName = '';
  Uint8List? _left;
  Uint8List? _right;
  bool _onlyDiff = true;
  bool _busy = false;

  /// 差异行（对齐后的行号集合）与逐字节差异标记。
  List<_HexRow> _rows = const [];

  void _toast(String msg) {
    if (!mounted) return;
    FlutterToastr.show(msg, context, duration: 2);
  }

  Future<void> _pick({required bool left}) async {
    final loc = AppLocalizations.of(context)!;
    try {
      final f = await FilePicker.pickFile();
      if (f == null) return;
      final file = File(f.xFile.path);
      final len = await file.length();
      if (len > _maxBytes) {
        _toast(loc.hexTooLarge('${_maxBytes ~/ (1024 * 1024)}'));
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        if (left) {
          _leftName = f.name;
          _left = bytes;
        } else {
          _rightName = f.name;
          _right = bytes;
        }
      });
      _compute();
    } catch (e) {
      _toast('$e');
    }
  }

  /// 按 16 字节分块、逐字节比较，生成对齐后的行列表。
  ///
  /// 两个文件长度不同时，多出来的部分单独成行（另一侧留空）——
  /// 这比强行对齐更容易看出「尾部多了一段」。
  void _compute() {
    final a = _left;
    final b = _right;
    if (a == null || b == null) {
      setState(() => _rows = const []);
      return;
    }
    setState(() => _busy = true);
    final rows = <_HexRow>[];
    final maxLen = a.length > b.length ? a.length : b.length;
    for (var off = 0; off < maxLen; off += _rowBytes) {
      final leftEnd = off + _rowBytes > a.length ? a.length : off + _rowBytes;
      final rightEnd = off + _rowBytes > b.length ? b.length : off + _rowBytes;
      final leftLen = leftEnd - off;
      final rightLen = rightEnd - off;
      var diff = leftLen != rightLen;
      // 差异位置用**位掩码**记（一行只有 16 个位置）：1M 行时比 Set<int> 省几十 MB，
      // 也不再为每一行复制两份 16 字节的小数组（那是 200 万个对象）。
      var mask = 0;
      if (!diff) {
        for (var i = 0; i < leftLen; i++) {
          if (a[off + i] != b[off + i]) {
            mask |= 1 << i;
            diff = true;
          }
        }
      }
      if (diff) {
        rows.add(_HexRow(offset: off, leftLen: leftLen, rightLen: rightLen, marks: mask));
      } else if (!_onlyDiff) {
        rows.add(_HexRow(offset: off, leftLen: leftLen, rightLen: rightLen, marks: 0));
      }
    }
    setState(() {
      _rows = rows;
      _busy = false;
    });
  }

  void _clear() {
    setState(() {
      _left = null;
      _right = null;
      _leftName = '';
      _rightName = '';
      _rows = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final mono = TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: theme.colorScheme.onSurface);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.hexDiffTitle),
        actions: [
          PopupMenuButton<String>(
            tooltip: loc.more,
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (v) {
              if (v == 'onlyDiff') {
                setState(() => _onlyDiff = !_onlyDiff);
                _compute();
              } else if (v == 'clear') {
                _clear();
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                  value: 'onlyDiff', checked: _onlyDiff, child: Text(loc.diffOnlyChanges)),
              PopupMenuItem(value: 'clear', child: Text(loc.clear)),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Row(children: [
            Expanded(child: _pickButton(loc, theme, true)),
            const SizedBox(width: 8),
            Expanded(child: _pickButton(loc, theme, false)),
          ]),
        ),
        if (_left != null && _right != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              Text('${_rows.length} ${loc.hexDiffRows}',
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              Text('${_left!.length} B ↔ ${_right!.length} B',
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        const SizedBox(height: 4),
        Expanded(
          child: (_left == null || _right == null)
              ? Center(
                  child: Text(loc.hexDiffPickTwo,
                      style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant)),
                )
              : _rows.isEmpty
                  ? Center(
                      child: Text(_busy ? '…' : loc.diffIdentical,
                          style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant)),
                    )
                  : ListView.builder(
                      itemCount: _rows.length,
                      itemBuilder: (_, i) {
                        final r = _rows[i];
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            border: Border(
                                bottom: BorderSide(color: theme.dividerColor, width: 0.3)),
                          ),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(
                              width: 66,
                              child: Text(_hexOffset(r.offset),
                                  style: mono.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
                            ),
                            Expanded(child: _hexCells(_left!, r.offset, r.leftLen, r.marks, mono, theme)),
                            const SizedBox(width: 6),
                            Expanded(child: _hexCells(_right!, r.offset, r.rightLen, r.marks, mono, theme)),
                          ]),
                        );
                      },
                    ),
        ),
      ]),
    );
  }

  Widget _pickButton(AppLocalizations loc, ThemeData theme, bool left) {
    final name = left ? _leftName : _rightName;
    return OutlinedButton(
      onPressed: () => _pick(left: left),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(left ? 'A' : 'B', style: const TextStyle(fontSize: 10)),
        Text(
          name.isEmpty ? loc.crcPickFile : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: name.isEmpty ? theme.colorScheme.onSurfaceVariant : null),
        ),
      ]),
    );
  }

  /// 一行 16 个字节格；[mask] 里的位置标红。
  ///
  /// 直接读原始 buffer 的 `[offset, offset + len)` 窗口，不复制切片 —— 大文件
  /// （几 MB 就是几十万行）下每行复制一次会觉得滚动发涩。
  Widget _hexCells(
      Uint8List bytes, int offset, int len, int mask, TextStyle mono, ThemeData theme) {
    return Wrap(spacing: 2, runSpacing: 1, children: [
      for (var i = 0; i < len; i++)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          decoration: (mask >> i) & 1 == 1
              ? BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(2),
                )
              : null,
          child: Text(bytes[offset + i].toRadixString(16).padLeft(2, '0').toUpperCase(),
              style: mono.copyWith(
                color: (mask >> i) & 1 == 1 ? theme.colorScheme.error : null,
                fontWeight: (mask >> i) & 1 == 1 ? FontWeight.w600 : FontWeight.w400,
              )),
        ),
    ]);
  }

  static String _hexOffset(int off) =>
      off.toRadixString(16).toUpperCase().padLeft(8, '0');
}

/// 对齐后的一行（起始偏移 + 两侧长度 + 差异位掩码）。
///
/// 刻意**不持有字节副本**：原始内容在 State 的 `_left` / `_right` 里，
/// 行对象只记位置。一个 16MB 的文件会有 100 万行，每行存两份 16 字节数组
/// 等于凭空造出 200 万个对象 —— 这是之前滚动卡顿与内存压力的主因。
class _HexRow {
  final int offset;
  final int leftLen;
  final int rightLen;

  /// 位掩码：第 i 位为 1 表示第 i 个字节不同（i ∈ 0..15）。
  final int marks;

  const _HexRow({
    required this.offset,
    required this.leftLen,
    required this.rightLen,
    required this.marks,
  });
}
