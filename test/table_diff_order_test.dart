// compareTables(ignoreRowOrder:) 的用例。
//
// 场景：两份从不同系统导出的表，内容基本一样、行顺序不同。
// 按行号对齐会把几乎每行都标成「变了」，看不出真正多了哪几行。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/table_diff.dart';

TableDiffResult _cmp(String left, String right,
    {bool ignoreRowOrder = false, bool ignoreCase = false, String? key}) {
  return compareTables(
    parseTable(left),
    parseTable(right),
    keyColumn: key,
    ignoreCase: ignoreCase,
    ignoreWhitespace: false,
    ignoreRowOrder: ignoreRowOrder,
  );
}

void main() {
  test('行顺序不同：忽略行序后完全没有变化', () {
    const left = 'name,age\nTom,3\nAmy,4\nBob,5';
    const right = 'name,age\nBob,5\nTom,3\nAmy,4';
    final strict = _cmp(left, right);
    expect(strict.changedRowCount, greaterThan(0), reason: '按行号对齐会整片标红');
    final loose = _cmp(left, right, ignoreRowOrder: true);
    expect(loose.changedRowCount, 0);
    expect(loose.addedRows, 0);
    expect(loose.removedRows, 0);
  });

  test('忽略行序时多出来的行仍算新增', () {
    const left = 'name,age\nTom,3\nAmy,4';
    const right = 'name,age\nAmy,4\nTom,3\nZoe,9';
    final r = _cmp(left, right, ignoreRowOrder: true);
    expect(r.addedRows, 1);
    expect(r.removedRows, 0);
  });

  test('忽略行序时少掉的行仍算删除', () {
    const left = 'name,age\nTom,3\nAmy,4\nBob,5';
    const right = 'name,age\nAmy,4\nTom,3';
    final r = _cmp(left, right, ignoreRowOrder: true);
    expect(r.removedRows, 1);
    expect(r.addedRows, 0);
  });

  test('改了一个格子的行会被配对成「修改」，不是删+增', () {
    const left = 'name,age\nTom,3\nAmy,4';
    const right = 'name,age\nAmy,9\nTom,3';
    final r = _cmp(left, right, ignoreRowOrder: true);
    expect(r.addedRows, 0);
    expect(r.removedRows, 0);
    final changed = r.rows.where((x) => x.state == TableRowState.changed).toList();
    expect(changed.length, 1, reason: 'Amy 那行的 age 变了');
    expect(changed.first.changedColumns.isNotEmpty, true);
  });

  test('ignoreCase 也作用在忽略行序的签名上', () {
    const left = 'name,age\nTom,3';
    const right = 'name,age\ntom,3';
    expect(_cmp(left, right, ignoreRowOrder: true).changedRowCount, greaterThan(0));
    expect(_cmp(left, right, ignoreRowOrder: true, ignoreCase: true).changedRowCount, 0);
  });

  test('选了主键列时按主键对齐，忽略行序不参与', () {
    const left = 'id,name\n1,Tom\n2,Amy';
    const right = 'id,name\n2,Amy\n1,Tom';
    final r = _cmp(left, right, key: 'id', ignoreRowOrder: true);
    expect(r.changedRowCount, 0);
    expect(r.rowKey, 'id');
  });

  test('两边完全一样：忽略行序结果一致', () {
    const same = 'a,b\n1,2\n3,4';
    final r = _cmp(same, same, ignoreRowOrder: true);
    expect(r.identical, true);
  });

  test('列数不同（有一侧多一列）时不崩，只是配对变宽松', () {
    const left = 'a,b\n1,2';
    const right = 'a,b,c\n1,2,9';
    final r = _cmp(left, right, ignoreRowOrder: true);
    expect(r.rows.length, greaterThan(0));
  });
}
