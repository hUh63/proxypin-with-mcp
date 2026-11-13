import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/toolbox/text_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:proxypin/utils/excel_export.dart';
import 'package:proxypin/utils/table_diff.dart';
import 'package:proxypin/utils/text_file_reader.dart';

/// 表格（CSV / TSV）对比。
///
/// 为什么要有这一页：文本对比是按行看的，一张导出的报表只要有一列宽度变化，
/// 从那一行开始下面整段都会标红，看不出「到底哪一格变了」。表格对比把数据
/// 解析成行列，按列名配对、按主键（或行号）配对行，最后逐格比较，
/// 变化只会落在真正变了的那个单元格上。
class TableDiffPage extends StatefulWidget {
  final String? initialLeft;
  final String? initialRight;
  final String? initialLeftName;
  final String? initialRightName;

  const TableDiffPage({
    super.key,
    this.initialLeft,
    this.initialRight,
    this.initialLeftName,
    this.initialRightName,
  });

  static Future<void> show(
    BuildContext context, {
    String? left,
    String? right,
    String? leftName,
    String? rightName,
  }) {
    return Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => TableDiffPage(
        initialLeft: left,
        initialRight: right,
        initialLeftName: leftName,
        initialRightName: rightName,
      ),
    ));
  }

  @override
  State<TableDiffPage> createState() => _TableDiffPageState();
}

class _TableDiffPageState extends State<TableDiffPage> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  String _leftText = '';
  String _rightText = '';
  String _leftName = '';
  String _rightName = '';

  /// 空串 = 自动识别。
  String _delimiter = '';

  /// 空串 = 按行号对齐。
  String _key = '';
  bool _ignoreCase = false;
  bool _ignoreWhitespace = false;
  bool _onlyDiff = false;

  double _fontSize = 12;

  TableData? _leftTable;
  TableData? _rightTable;
  TableDiffResult? _result;

  @override
  void initState() {
    super.initState();
    _leftText = widget.initialLeft ?? '';
    _rightText = widget.initialRight ?? '';
    _leftName = widget.initialLeftName ?? '';
    _rightName = widget.initialRightName ?? '';
    _recompute();
  }

  void _recompute() {
    _leftTable = parseTable(_leftText, delimiter: _delimiter);
    _rightTable = parseTable(_rightText, delimiter: _delimiter);
    if (_leftTable!.headers.isEmpty || _rightTable!.headers.isEmpty) {
      _result = null;
      // 表换了（或清空了），原来选的主键列可能已经不存在。
      // 不重置的话 DropdownButton 会因为 value 不在 items 里直接 assert 崩。
      _key = '';
      return;
    }
    if (_key.isNotEmpty && !_leftTable!.headers.contains(_key)) _key = '';
    _result = compareTables(
      _leftTable!,
      _rightTable!,
      keyColumn: _key,
      ignoreCase: _ignoreCase,
      ignoreWhitespace: _ignoreWhitespace,
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _pickSide({required bool left}) async {
    try {
      final picked = Platform.isAndroid || Platform.isIOS
          ? await FilePicker.pickFile()
          : await FilePicker.pickFile(type: FileType.any);
      if (picked == null) return;
      final path = picked.xFile.path;
      final content = await readTextFileLenient(File(path));
      if (!mounted) return;
      final name = path.split(Platform.pathSeparator).last;
      setState(() {
        if (left) {
          _leftText = content.text;
          _leftName = name;
        } else {
          _rightText = content.text;
          _rightName = name;
        }
        _recompute();
      });
      if (content.truncated) _toast(localizations.diffFileTruncated);
    } catch (e) {
      _toast('${localizations.fail}: $e');
    }
  }

  Future<void> _pasteSide({required bool left}) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final loc = AppLocalizations.of(ctx)!;
        return AlertDialog(
          title: Text(loc.paste),
          content: SizedBox(
            width: 520,
            height: 320,
            child: TextField(
              controller: controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(loc.cancel)),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(loc.confirm),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (text == null || !mounted) return;
    setState(() {
      if (left) {
        _leftText = text;
        _leftName = '';
      } else {
        _rightText = text;
        _rightName = '';
      }
      _recompute();
    });
  }

  /// 把某一侧送进文本编辑器继续改。
  void _editSide({required bool left}) {
    final text = left ? _leftText : _rightText;
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => TextEditorPage(initialText: text),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final loc = localizations;
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.tableDiffTitle),
        actions: <Widget>[
          IconButton(
            tooltip: loc.diffOriginal,
            icon: const Icon(Icons.crop_square, size: 20),
            onPressed: () => _pickSide(left: true),
          ),
          IconButton(
            tooltip: loc.diffChanged,
            icon: const Icon(Icons.crop_din, size: 20),
            onPressed: () => _pickSide(left: false),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'pasteLeft':
                  _pasteSide(left: true);
                  break;
                case 'pasteRight':
                  _pasteSide(left: false);
                  break;
                case 'editLeft':
                  _editSide(left: true);
                  break;
                case 'editRight':
                  _editSide(left: false);
                  break;
                case 'zoomIn':
                  setState(() => _fontSize = (_fontSize + 1).clamp(9, 22));
                  break;
                case 'zoomOut':
                  setState(() => _fontSize = (_fontSize - 1).clamp(9, 22));
                  break;
                case 'exportCsv':
                  unawaited(_exportDiff(asCsv: true));
                  break;
                case 'exportMd':
                  unawaited(_exportDiff(asCsv: false));
                  break;
                case 'exportXlsx':
                  unawaited(_exportXlsx());
                  break;
                case 'clear':
                  setState(() {
                    _leftText = '';
                    _rightText = '';
                    _leftName = '';
                    _rightName = '';
                    _recompute();
                  });
                  break;
              }
            },
            itemBuilder: (ctx) => <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'pasteLeft', child: Text('${loc.paste} · ${loc.diffOriginal}')),
              PopupMenuItem(value: 'pasteRight', child: Text('${loc.paste} · ${loc.diffChanged}')),
              PopupMenuItem(value: 'editLeft', child: Text('${loc.edit} · ${loc.diffOriginal}')),
              PopupMenuItem(value: 'editRight', child: Text('${loc.edit} · ${loc.diffChanged}')),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'zoomIn', child: Text('${loc.editorZoomIn}  +')),
              PopupMenuItem(value: 'zoomOut', child: Text('${loc.editorZoomOut}  −')),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'exportCsv', child: Text(loc.diffExportCsv)),
              PopupMenuItem(value: 'exportMd', child: Text(loc.diffExportMarkdown)),
              PopupMenuItem(value: 'exportXlsx', child: Text(loc.exportExcel)),
              PopupMenuItem(value: 'clear', child: Text(loc.clear)),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _controls(loc),
          Expanded(
            child: result == null ? _empty(loc) : _table(result, loc),
          ),
          if (result != null) _statBar(result, loc),
        ],
      ),
    );
  }

  Widget _controls(AppLocalizations loc) {
    final detected = _leftTable?.delimiter ?? ',';
    final headers = _leftTable?.headers ?? const <String>[];
    // 分隔符下拉的选项：自动 + 四个常见符号。标签用符号本身，
    // 「制表符」这种看不见的用 Tab 字样，否则选完啥也看不出来。
    final delimiterItems = <String, String>{
      '': loc.tableDiffAuto,
      ',': ',',
      '\t': 'Tab',
      ';': ';',
      '|': '|',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          _labeledDrop<String>(
            label: loc.tableDiffDelimiter,
            value: _delimiter,
            items: delimiterItems,
            onChanged: (v) => setState(() {
              _delimiter = v ?? '';
              _recompute();
            }),
          ),
          if (_delimiter.isEmpty)
            Text(
              detected == '\t' ? 'Tab' : detected,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          _labeledDrop<String>(
            label: loc.tableDiffKeyColumn,
            value: _key,
            items: <String, String>{
              '': loc.tableDiffKeyByPosition,
              for (final h in headers) h: h,
            },
            onChanged: (v) => setState(() {
              _key = v ?? '';
              _recompute();
            }),
          ),
          FilterChip(
            label: Text(loc.diffIgnoreCase, style: const TextStyle(fontSize: 11)),
            selected: _ignoreCase,
            visualDensity: VisualDensity.compact,
            onSelected: (v) => setState(() {
              _ignoreCase = v;
              _recompute();
            }),
          ),
          FilterChip(
            label: Text(loc.diffIgnoreWhitespace, style: const TextStyle(fontSize: 11)),
            selected: _ignoreWhitespace,
            visualDensity: VisualDensity.compact,
            onSelected: (v) => setState(() {
              _ignoreWhitespace = v;
              _recompute();
            }),
          ),
          FilterChip(
            label: Text(loc.tableDiffOnlyDiff, style: const TextStyle(fontSize: 11)),
            selected: _onlyDiff,
            visualDensity: VisualDensity.compact,
            onSelected: (v) => setState(() => _onlyDiff = v),
          ),
        ],
      ),
    );
  }

  /// 带前置文字的下拉。值-标签分开是因为分隔符可能看不见。
  Widget _labeledDrop<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 4),
        DropdownButton<T>(
          value: value,
          underline: const SizedBox.shrink(),
          isDense: true,
          style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12),
          items: <DropdownMenuItem<T>>[
            for (final e in items.entries)
              DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _empty(AppLocalizations loc) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.table_chart_outlined, size: 46, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(loc.tableDiffEmpty, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              OutlinedButton(
                onPressed: () => _pickSide(left: true),
                child: Text(loc.diffOriginal),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => _pickSide(left: false),
                child: Text(loc.diffChanged),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _rowColor(TableRowState state) {
    switch (state) {
      case TableRowState.added:
        return const Color(0xFF2E7D32);
      case TableRowState.removed:
        return const Color(0xFFC62828);
      case TableRowState.changed:
        return const Color(0xFFEF6C00);
      case TableRowState.unchanged:
        return Colors.transparent;
    }
  }

  Widget _table(TableDiffResult result, AppLocalizations loc) {
    final columns = result.columns;
    final cellWidth = (_fontSize * 9).clamp(72.0, 260.0);
    const numWidth = 42.0;
    final totalWidth = numWidth * 2 + cellWidth * columns.length + 8;

    // 只显示差异时，保留「两侧都完全一致」之外的所有行。
    final positions = <int>[];
    for (var i = 0; i < result.rows.length; i++) {
      if (_onlyDiff && result.rows[i].state == TableRowState.unchanged) continue;
      positions.add(i);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: totalWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _headerRow(result, loc, cellWidth, numWidth),
            const Divider(height: 1),
            Expanded(
              child: positions.isEmpty
                  ? Center(
                      child: Text(loc.diffIdentical,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    )
                  : ListView.builder(
                      itemCount: positions.length,
                      itemExtent: null,
                      itemBuilder: (ctx, i) {
                        final pos = positions[i];
                        return _dataRow(result, pos, cellWidth, numWidth);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerRow(TableDiffResult result, AppLocalizations loc, double cellWidth, double numWidth) {
    final style = TextStyle(
      fontSize: _fontSize - 1,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Container(
      height: 30,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Row(
        children: <Widget>[
          SizedBox(width: numWidth, child: Text('L', style: style, textAlign: TextAlign.center)),
          SizedBox(width: numWidth, child: Text('R', style: style, textAlign: TextAlign.center)),
          for (final c in result.columns)
            SizedBox(
              width: cellWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: <Widget>[
                    if (c.state == TableColumnState.added)
                      const Icon(Icons.add, size: 11, color: Color(0xFF2E7D32))
                    else if (c.state == TableColumnState.removed)
                      const Icon(Icons.remove, size: 11, color: Color(0xFFC62828))
                    else if (c.state == TableColumnState.changed)
                      const Icon(Icons.edit, size: 11, color: Color(0xFFEF6C00)),
                    Expanded(
                      child: Text(
                        c.name,
                        style: style,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (c.changedCells > 0)
                      Text(
                        '${c.changedCells}',
                        style: style.copyWith(fontSize: _fontSize - 3, color: const Color(0xFFEF6C00)),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dataRow(TableDiffResult result, int pos, double cellWidth, double numWidth) {
    final row = result.rows[pos];
    final leftCells = result.leftCellsAt(pos);
    final rightCells = result.rightCellsAt(pos);
    final base = _rowColor(row.state);
    final changedSet = row.changedColumns.toSet();
    final hasCellDiff = row.changedColumns.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: base, width: base == Colors.transparent ? 0 : 3),
          bottom: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.25), width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _numCell(row.leftIndex, numWidth),
          _numCell(row.rightIndex, numWidth),
          for (var c = 0; c < result.columns.length; c++)
            _cell(
              leftText: leftCells[c],
              rightText: rightCells[c],
              width: cellWidth,
              changed: changedSet.contains(c),
              addedCol: result.columns[c].state == TableColumnState.added,
              removedCol: result.columns[c].state == TableColumnState.removed,
              rowAdded: row.state == TableRowState.added,
              rowRemoved: row.state == TableRowState.removed,
              tall: hasCellDiff,
            ),
        ],
      ),
    );
  }

  Widget _numCell(int index, double width) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Text(
          index < 0 ? '' : '${index + 1}',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: _fontSize - 2,
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _cell({
    required String leftText,
    required String rightText,
    required double width,
    required bool changed,
    required bool addedCol,
    required bool removedCol,
    required bool rowAdded,
    required bool rowRemoved,
    required bool tall,
  }) {
    // 变化的格子上下两行显示「原值 / 新值」，不变的只显示一行，行高因此不同。
    Color? bg;
    if (changed) {
      bg = const Color(0xFFEF6C00).withValues(alpha: 0.16);
    } else if (addedCol || rowAdded) {
      bg = const Color(0xFF2E7D32).withValues(alpha: 0.12);
    } else if (removedCol || rowRemoved) {
      bg = const Color(0xFFC62828).withValues(alpha: 0.12);
    }

    final commonStyle = TextStyle(fontSize: _fontSize, fontFamily: 'monospace', height: 1.25);

    Widget content;
    if (changed) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            leftText.isEmpty ? '∅' : leftText,
            style: commonStyle.copyWith(color: const Color(0xFFC62828)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            rightText.isEmpty ? '∅' : rightText,
            style: commonStyle.copyWith(color: const Color(0xFF2E7D32)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    } else {
      final text = rowAdded ? rightText : leftText;
      content = Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: commonStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final cell = Container(
      width: width,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: content,
    );

    if (!changed && !rowAdded && !rowRemoved) return cell;
    // 差异格给个「点开看全文」，长文本被省略号截掉时至少能读到完整值。
    return Tooltip(
      message: changed ? '$leftText  →  $rightText' : (rowAdded ? rightText : leftText),
      waitDuration: const Duration(milliseconds: 500),
      child: cell,
    );
  }

  /// 单元格里可能有逗号/换行/引号，CSV 必须按 RFC4180 包起来。
  static String _csvCell(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  /// 导出差异清单：一行一个「变化/新增/删除的行」，
  /// 变化行拆到单元格级别，方便贴到工单或表单里逐条核对。
  Future<void> _exportDiff({required bool asCsv}) async {
    final result = _result;
    if (result == null) {
      _toast(localizations.tableDiffEmpty);
      return;
    }
    final buf = StringBuffer();
    if (asCsv) {
      // 带 BOM，Windows Excel 才不会把 UTF-8 当 GBK 解成乱码。
      buf.writeCharCode(0xFEFF);
      buf.writeln('row,column,left,right');
    } else {
      buf.writeln('| ${localizations.tableDiffStat(0, 0, 0).split(' ').first} | column | left | right |');
      buf.writeln('| --- | --- | --- | --- |');
    }
    var exported = 0;
    for (var pos = 0; pos < result.rows.length; pos++) {
      final row = result.rows[pos];
      if (row.state == TableRowState.unchanged) continue;
      final l = result.leftCellsAt(pos);
      final r = result.rightCellsAt(pos);
      if (row.state == TableRowState.added || row.state == TableRowState.removed) {
        final added = row.state == TableRowState.added;
        final cells = added ? r : l;
        for (var c = 0; c < result.columns.length; c++) {
          final left = added ? '' : cells[c];
          final right = added ? cells[c] : '';
          final rowNo = added ? row.rightIndex + 1 : row.leftIndex + 1;
          buf.writeln(asCsv
              ? '$rowNo,${_csvCell(result.columns[c].name)},${_csvCell(left)},${_csvCell(right)}'
              : '| $rowNo | ${result.columns[c].name} | $left | $right |');
          exported++;
        }
      } else {
        for (final c in row.changedColumns) {
          buf.writeln(asCsv
              ? '${row.leftIndex + 1},${_csvCell(result.columns[c].name)},${_csvCell(l[c])},${_csvCell(r[c])}'
              : '| ${row.leftIndex + 1} | ${result.columns[c].name} | ${l[c]} | ${r[c]} |');
          exported++;
        }
      }
    }
    if (exported == 0) {
      _toast(localizations.diffIdentical);
      return;
    }
    try {
      final bytes = utf8.encode(buf.toString());
      await FilePicker.saveFile(
        fileName: asCsv ? 'table-diff.csv' : 'table-diff.md',
        bytes: Uint8List.fromList(bytes),
      );
      if (!mounted) return;
      _toast('${localizations.exportSuccess} · $exported');
    } catch (e) {
      _toast('${localizations.fail}: $e');
    }
  }

  /// 导出 xlsx：和 CSV 同一份差异清单，只是 Excel 打开即分好列。
  /// CSV 在中文 Windows 上常被当 GBK 解开（已加 BOM 兜底），单元格里带逗号还得手动分列；
  /// 工单/验收表直接收 xlsx 少一步。
  Future<void> _exportXlsx() async {
    final result = _result;
    if (result == null) {
      _toast(localizations.tableDiffEmpty);
      return;
    }
    final rows = <List<Object?>>[
      <Object?>['row', 'column', 'left', 'right'],
    ];
    var exported = 0;
    for (var pos = 0; pos < result.rows.length; pos++) {
      final row = result.rows[pos];
      if (row.state == TableRowState.unchanged) continue;
      final l = result.leftCellsAt(pos);
      final r = result.rightCellsAt(pos);
      if (row.state == TableRowState.added || row.state == TableRowState.removed) {
        final added = row.state == TableRowState.added;
        final cells = added ? r : l;
        for (var c = 0; c < result.columns.length; c++) {
          rows.add(<Object?>[
            added ? row.rightIndex + 1 : row.leftIndex + 1,
            result.columns[c].name,
            added ? '' : cells[c],
            added ? cells[c] : '',
          ]);
          exported++;
        }
      } else {
        for (final c in row.changedColumns) {
          rows.add(<Object?>[row.leftIndex + 1, result.columns[c].name, l[c], r[c]]);
          exported++;
        }
      }
    }
    if (exported == 0) {
      _toast(localizations.diffIdentical);
      return;
    }
    try {
      final bytes = ExcelExport.buildWorkbook(rows, sheetName: 'TableDiff');
      await FilePicker.saveFile(fileName: 'table-diff.xlsx', bytes: bytes);
      if (!mounted) return;
      _toast('${localizations.exportSuccess} · $exported');
    } catch (e) {
      _toast('${localizations.fail}: $e');
    }
  }

  Widget _statBar(TableDiffResult result, AppLocalizations loc) {
    final style = TextStyle(
      fontSize: 11,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 0.6)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              loc.tableDiffStat(result.rows.length, result.columns.length, result.changedRowCount + result.changedColumnCount),
              style: style,
            ),
          ),
          if (result.addedRows > 0) ...<Widget>[
            Text('+${result.addedRows}', style: style.copyWith(color: const Color(0xFF2E7D32))),
            const SizedBox(width: 8),
          ],
          if (result.removedRows > 0) ...<Widget>[
            Text('−${result.removedRows}', style: style.copyWith(color: const Color(0xFFC62828))),
            const SizedBox(width: 8),
          ],
          if (_leftName.isNotEmpty || _rightName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '${_leftName.isEmpty ? loc.diffOriginal : _leftName} ↔ '
                '${_rightName.isEmpty ? loc.diffChanged : _rightName}',
                style: style,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (result.rowKey.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text('${loc.tableDiffKeyColumn}: ${result.rowKey}', style: style),
            ),
        ],
      ),
    );
  }
}
