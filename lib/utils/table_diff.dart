/// 表格（CSV / TSV / 管道分隔）对比引擎。
///
/// 文本对比是按「行」看的，导出的报表、接口返回的表格数据一旦按行看，
/// 只要有一列宽度变化下面整段都会红。这里把它提升到「单元格」级别：
/// 先解析成行列矩阵，再按列名配对、按主键（或行号）配对行，最后逐格比。
///
/// 纯 Dart，无 Flutter 依赖，可直接单测。
library;

/// 一张解析好的表格。
class TableData {
  /// 表头。取第一行。
  final List<String> headers;

  /// 数据行（不含表头）。每行长度已对齐到 headers.length。
  final List<List<String>> rows;

  /// 实际使用的分隔符，便于界面上回显「这是按逗号切的」。
  final String delimiter;

  const TableData({
    required this.headers,
    required this.rows,
    required this.delimiter,
  });

  int get columnCount => headers.length;
  int get rowCount => rows.length;

  /// 某一列的所有值（不含表头）。
  List<String> column(int index) {
    if (index < 0 || index >= headers.length) return const <String>[];
    return <String>[for (final r in rows) r[index]];
  }
}

/// 猜测分隔符。返回命中最多的那个；一个都没命中时回退逗号。
String guessDelimiter(String text) {
  // 只看前 20 行，避免大文件上白跑。
  final sample = text.split('\n').take(20).join('\n');
  const candidates = <String>[',', '\t', ';', '|'];
  var best = ',';
  var bestScore = -1;
  for (final d in candidates) {
    // 每行都出现的分隔符才算数，取平均出现次数作分数。
    final lines = sample.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) continue;
    var total = 0;
    var hit = 0;
    for (final l in lines) {
      final c = _countOutsideQuotes(l, d);
      if (c > 0) {
        hit++;
        total += c;
      }
    }
    if (hit == 0) continue;
    // 命中行占比优先，其次平均列数。这样 TSV 不会被逗号抢走。
    final score = hit * 1000 + (total ~/ lines.length);
    if (score > bestScore) {
      bestScore = score;
      best = d;
    }
  }
  return best;
}

int _countOutsideQuotes(String line, String d) {
  var inQuote = false;
  var n = 0;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      inQuote = !inQuote;
    } else if (!inQuote && ch == d) {
      n++;
    }
  }
  return n;
}

/// 解析分隔符表格。支持 RFC4180 的核心约定：
/// 引号内可含分隔符与换行，`""` 表示一个字面引号。
///
/// [delimiter] 为空时自动猜测。
TableData parseTable(String text, {String? delimiter, bool firstRowIsHeader = true}) {
  final d = (delimiter == null || delimiter.isEmpty) ? guessDelimiter(text) : delimiter;
  final rawRows = _splitRecords(text, d);
  if (rawRows.isEmpty) {
    return TableData(headers: const <String>[], rows: const <List<String>>[], delimiter: d);
  }

  // 丢掉全空行（尾部换行会产生一行 ['']）。
  final cleaned = <List<String>>[
    for (final r in rawRows)
      if (r.any((c) => c.trim().isNotEmpty)) r,
  ];
  if (cleaned.isEmpty) {
    return TableData(headers: const <String>[], rows: const <List<String>>[], delimiter: d);
  }

  final headerRow = firstRowIsHeader ? cleaned.first : _syntheticHeader(cleaned.first.length);
  final dataRows = firstRowIsHeader ? cleaned.skip(1).toList() : cleaned;

  // 列数按最宽的一行补空格（真实 CSV 常常尾部列是空的）。
  var width = headerRow.length;
  for (final r in dataRows) {
    if (r.length > width) width = r.length;
  }
  final headers = <String>[
    for (var i = 0; i < width; i++)
      i < headerRow.length && headerRow[i].trim().isNotEmpty ? headerRow[i].trim() : '列${i + 1}',
  ];
  final rows = <List<String>>[
    for (final r in dataRows) <String>[for (var i = 0; i < width; i++) i < r.length ? r[i] : ''],
  ];
  return TableData(headers: headers, rows: rows, delimiter: d);
}

List<String> _syntheticHeader(int n) => <String>[for (var i = 0; i < n; i++) '列${i + 1}'];

/// 按分隔符切记录，处理引号包裹与引号内换行。
List<List<String>> _splitRecords(String text, String delim) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuote = false;
  var i = 0;
  final n = text.length;
  while (i < n) {
    final ch = text[i];
    if (inQuote) {
      if (ch == '"') {
        if (i + 1 < n && text[i + 1] == '"') {
          cell.write('"');
          i += 2;
          continue;
        }
        inQuote = false;
        i++;
        continue;
      }
      cell.write(ch);
      i++;
      continue;
    }
    if (ch == '"' && cell.isEmpty) {
      inQuote = true;
      i++;
      continue;
    }
    if (ch == delim) {
      row.add(cell.toString());
      cell.clear();
      i++;
      continue;
    }
    if (ch == '\r') {
      // 统一按 \n 处理换行，跳过 \r。
      i++;
      continue;
    }
    if (ch == '\n') {
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
      i++;
      continue;
    }
    cell.write(ch);
    i++;
  }
  // 收尾：最后一段没有以换行结束时仍要落一行。
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

/// 列的状态。
enum TableColumnState { unchanged, changed, added, removed }

/// 单列的对比结果。
class TableColumnDiff {
  final String name;

  /// 左侧列下标，-1 表示右侧新增的列。
  final int leftIndex;

  /// 右侧列下标，-1 表示左侧被删掉的列。
  final int rightIndex;

  final TableColumnState state;

  /// 该列里值发生变化的行数。
  final int changedCells;

  const TableColumnDiff({
    required this.name,
    required this.leftIndex,
    required this.rightIndex,
    required this.state,
    required this.changedCells,
  });

  bool get isPresentOnLeft => leftIndex >= 0;
  bool get isPresentOnRight => rightIndex >= 0;
}

/// 行的状态。
enum TableRowState { unchanged, changed, added, removed }

/// 单行的对比结果。leftIndex/rightIndex 为 -1 表示该侧没有这一行。
class TableRowDiff {
  final int leftIndex;
  final int rightIndex;
  final TableRowState state;

  /// 内容发生变化的列下标（按对齐后的列位置）。
  final List<int> changedColumns;

  const TableRowDiff({
    required this.leftIndex,
    required this.rightIndex,
    required this.state,
    required this.changedColumns,
  });
}

/// 整张表的对比结果。
class TableDiffResult {
  final TableData left;
  final TableData right;

  /// 按坐标位置（0..n）给出的列结果，长度 = 对齐后的列数。
  final List<TableColumnDiff> columns;

  /// 按对齐后的行顺序给出。
  final List<TableRowDiff> rows;

  /// 行是如何配对的。
  final String rowKey;

  const TableDiffResult({
    required this.left,
    required this.right,
    required this.columns,
    required this.rows,
    required this.rowKey,
  });

  int get changedRowCount => rows.where((r) => r.state != TableRowState.unchanged).length;
  int get changedColumnCount => columns.where((c) => c.state != TableColumnState.unchanged).length;
  int get addedRows => rows.where((r) => r.state == TableRowState.added).length;
  int get removedRows => rows.where((r) => r.state == TableRowState.removed).length;
  int get addedColumns => columns.where((c) => c.state == TableColumnState.added).length;
  int get removedColumns => columns.where((c) => c.state == TableColumnState.removed).length;

  bool get identical => changedRowCount == 0 && changedColumnCount == 0;

  /// 供界面渲染的一行「对齐后的单元格」。左侧没有的格子/右侧没有的格子都给空串。
  List<String> leftCellsAt(int rowPosition) {
    final r = rows[rowPosition];
    if (r.leftIndex < 0) return List<String>.filled(columns.length, '');
    final row = left.rows[r.leftIndex];
    return <String>[
      for (final c in columns) c.leftIndex >= 0 && c.leftIndex < row.length ? row[c.leftIndex] : '',
    ];
  }

  List<String> rightCellsAt(int rowPosition) {
    final r = rows[rowPosition];
    if (r.rightIndex < 0) return List<String>.filled(columns.length, '');
    final row = right.rows[r.rightIndex];
    return <String>[
      for (final c in columns) c.rightIndex >= 0 && c.rightIndex < row.length ? row[c.rightIndex] : '',
    ];
  }
}

/// 对比两张表。
///
/// [keyColumn]：用哪一列作为主键来对齐行（列名或 0 起的列下标）。
/// 传空则按行号对齐。
/// [ignoreCase] / [ignoreWhitespace]：单元格比较时的宽松规则。
TableDiffResult compareTables(
  TableData left,
  TableData right, {
  String? keyColumn,
  bool ignoreCase = false,
  bool ignoreWhitespace = false,
}) {
  final columns = _alignColumns(left.headers, right.headers);
  final leftKeyIndex = _resolveKeyColumn(left.headers, keyColumn);
  final rightKeyIndex = _resolveKeyColumn(right.headers, keyColumn);

  List<TableRowDiff> rows;
  String rowKeyLabel;
  if (leftKeyIndex >= 0 && rightKeyIndex >= 0) {
    rows = _alignRowsByKey(left, right, columns, leftKeyIndex, rightKeyIndex,
        ignoreCase: ignoreCase, ignoreWhitespace: ignoreWhitespace);
    rowKeyLabel = left.headers[leftKeyIndex];
  } else {
    rows = _alignRowsByPosition(left, right, columns,
        ignoreCase: ignoreCase, ignoreWhitespace: ignoreWhitespace);
    rowKeyLabel = '';
  }

  // 逐列统计「有几格变了」，列的状态由「是否存在于两侧 + 是否有格子变化」共同决定。
  final changedPerColumn = List<int>.filled(columns.length, 0);
  for (final r in rows) {
    for (final c in r.changedColumns) {
      if (c >= 0 && c < changedPerColumn.length) changedPerColumn[c]++;
    }
  }
  final colDiffs = <TableColumnDiff>[
    for (var i = 0; i < columns.length; i++)
      TableColumnDiff(
        name: columns[i].name,
        leftIndex: columns[i].leftIndex,
        rightIndex: columns[i].rightIndex,
        state: columns[i].leftIndex < 0
            ? TableColumnState.added
            : columns[i].rightIndex < 0
                ? TableColumnState.removed
                : (changedPerColumn[i] > 0 ? TableColumnState.changed : TableColumnState.unchanged),
        changedCells: changedPerColumn[i],
      ),
  ];

  return TableDiffResult(
    left: left,
    right: right,
    columns: colDiffs,
    rows: rows,
    rowKey: rowKeyLabel,
  );
}

int _resolveKeyColumn(List<String> headers, String? key) {
  if (key == null || key.trim().isEmpty) return -1;
  final k = key.trim();
  final idx = headers.indexWhere((h) => h == k);
  if (idx >= 0) return idx;
  final asInt = int.tryParse(k);
  if (asInt != null && asInt >= 0 && asInt < headers.length) return asInt;
  return -1;
}

class _ColumnPair {
  final String name;
  final int leftIndex;
  final int rightIndex;
  const _ColumnPair(this.name, this.leftIndex, this.rightIndex);
}

/// 按列名配对；左侧没出现的算新增列，右侧没出现的算删除列。
_ColumnPair _named(String name, int l, int r) => _ColumnPair(name, l, r);

List<_ColumnPair> _alignColumns(List<String> leftHeaders, List<String> rightHeaders) {
  final result = <_ColumnPair>[];
  final usedRight = <int>{};
  final usedLeft = <int>{};

  // 第一轮：同名配对（同名多列时按出现顺序依次配）。
  for (var i = 0; i < leftHeaders.length; i++) {
    for (var j = 0; j < rightHeaders.length; j++) {
      if (usedRight.contains(j)) continue;
      if (rightHeaders[j] == leftHeaders[i]) {
        usedRight.add(j);
        usedLeft.add(i);
        result.add(_named(leftHeaders[i], i, j));
        break;
      }
    }
  }
  // 第二轮：剩下的左侧列 = 被删的列，按原顺序插进去。
  // 插入位置取「它左边最近一个已配对列的位置 +1」，这样列的视觉顺序接近原表。
  final leftoversLeft = <int>[
    for (var i = 0; i < leftHeaders.length; i++)
      if (!usedLeft.contains(i)) i,
  ];
  for (final i in leftoversLeft) {
    var pos = 0;
    for (var k = 0; k < result.length; k++) {
      if (result[k].leftIndex >= 0 && result[k].leftIndex < i) pos = k + 1;
    }
    result.insert(pos, _named(leftHeaders[i], i, -1));
  }
  // 第三轮：剩下的右侧列 = 新增的列。
  final leftoversRight = <int>[
    for (var j = 0; j < rightHeaders.length; j++)
      if (!usedRight.contains(j)) j,
  ];
  for (final j in leftoversRight) {
    var pos = result.length;
    for (var k = 0; k < result.length; k++) {
      if (result[k].rightIndex >= 0 && result[k].rightIndex < j) pos = k + 1;
    }
    result.insert(pos, _named(rightHeaders[j], -1, j));
  }
  return result;
}

bool _cellEq(String a, String b, {required bool ignoreCase, required bool ignoreWhitespace}) {
  var x = a;
  var y = b;
  if (ignoreWhitespace) {
    x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
    y = y.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
  if (ignoreCase) return x.toLowerCase() == y.toLowerCase();
  return x == y;
}

List<TableRowDiff> _alignRowsByPosition(
  TableData left,
  TableData right,
  List<_ColumnPair> columns, {
  required bool ignoreCase,
  required bool ignoreWhitespace,
}) {
  final out = <TableRowDiff>[];
  final n = left.rowCount > right.rowCount ? left.rowCount : right.rowCount;
  for (var i = 0; i < n; i++) {
    final hasL = i < left.rowCount;
    final hasR = i < right.rowCount;
    if (!hasL) {
      out.add(TableRowDiff(leftIndex: -1, rightIndex: i, state: TableRowState.added, changedColumns: const <int>[]));
      continue;
    }
    if (!hasR) {
      out.add(TableRowDiff(leftIndex: i, rightIndex: -1, state: TableRowState.removed, changedColumns: const <int>[]));
      continue;
    }
    final lr = left.rows[i];
    final rr = right.rows[i];
    final changed = <int>[];
    for (var c = 0; c < columns.length; c++) {
      final ci = columns[c];
      if (ci.leftIndex < 0 || ci.rightIndex < 0) continue;
      final lv = ci.leftIndex < lr.length ? lr[ci.leftIndex] : '';
      final rv = ci.rightIndex < rr.length ? rr[ci.rightIndex] : '';
      if (!_cellEq(lv, rv, ignoreCase: ignoreCase, ignoreWhitespace: ignoreWhitespace)) changed.add(c);
    }
    out.add(TableRowDiff(
      leftIndex: i,
      rightIndex: i,
      state: changed.isEmpty ? TableRowState.unchanged : TableRowState.changed,
      changedColumns: changed,
    ));
  }
  return out;
}

List<TableRowDiff> _alignRowsByKey(
  TableData left,
  TableData right,
  List<_ColumnPair> columns,
  int leftKey,
  int rightKey, {
  required bool ignoreCase,
  required bool ignoreWhitespace,
}) {
  String keyOf(List<List<String>> rows, int rowIdx, int keyIdx) {
    if (rowIdx >= rows.length) return '';
    final r = rows[rowIdx];
    if (keyIdx >= r.length) return '';
    final v = ignoreWhitespace ? r[keyIdx].replaceAll(RegExp(r'\s+'), ' ').trim() : r[keyIdx];
    return ignoreCase ? v.toLowerCase() : v;
  }

  // 左侧建索引：key → 第一出现行号。重复主键按出现顺序依次消耗。
  final leftByKey = <String, List<int>>{};
  for (var i = 0; i < left.rowCount; i++) {
    leftByKey.putIfAbsent(keyOf(left.rows, i, leftKey), () => <int>[]).add(i);
  }
  final usedLeft = <int>{};
  final out = <TableRowDiff>[];

  for (var j = 0; j < right.rowCount; j++) {
    final k = keyOf(right.rows, j, rightKey);
    final bucket = leftByKey[k];
    int? li;
    if (bucket != null) {
      for (final cand in bucket) {
        if (!usedLeft.contains(cand)) {
          li = cand;
          break;
        }
      }
    }
    if (li == null) {
      out.add(TableRowDiff(leftIndex: -1, rightIndex: j, state: TableRowState.added, changedColumns: const <int>[]));
      continue;
    }
    usedLeft.add(li);
    final lr = left.rows[li];
    final rr = right.rows[j];
    final changed = <int>[];
    for (var c = 0; c < columns.length; c++) {
      final ci = columns[c];
      if (ci.leftIndex < 0 || ci.rightIndex < 0) continue;
      final lv = ci.leftIndex < lr.length ? lr[ci.leftIndex] : '';
      final rv = ci.rightIndex < rr.length ? rr[ci.rightIndex] : '';
      if (!_cellEq(lv, rv, ignoreCase: ignoreCase, ignoreWhitespace: ignoreWhitespace)) changed.add(c);
    }
    out.add(TableRowDiff(
      leftIndex: li,
      rightIndex: j,
      state: changed.isEmpty ? TableRowState.unchanged : TableRowState.changed,
      changedColumns: changed,
    ));
  }

  // 右侧没出现的左侧行 = 被删除的行，插到「它原本前一行」的位置后面。
  for (var i = 0; i < left.rowCount; i++) {
    if (usedLeft.contains(i)) continue;
    var pos = out.length;
    for (var k = 0; k < out.length; k++) {
      final li = out[k].leftIndex;
      if (li >= 0 && li < i) pos = k + 1;
    }
    out.insert(pos, TableRowDiff(leftIndex: i, rightIndex: -1, state: TableRowState.removed, changedColumns: const <int>[]));
  }
  return out;
}
