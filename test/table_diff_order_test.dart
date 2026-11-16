// compareTables(ignoreRowOrder:) 的用例。
//
// 场景：两份从不同系统导出的表，内容基本一样、行顺序不同。
// 按行号对齐会把几乎每行都标成「变了」，看不出真正多了哪几行。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/table_diff.dart';

TableDiffResult _cmp(String left, String right,
    {bool ignoreRowOrder = false,
    bool ignoreCase = false,
    String? key,
    Set<String> ignoreColumns = const <String>{}}) {
  return compareTables(
    parseTable(left),
    parseTable(right),
    keyColumn: key,
    ignoreCase: ignoreCase,
    ignoreWhitespace: false,
    ignoreRowOrder: ignoreRowOrder,
    ignoreColumns: ignoreColumns,
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

  group('忽略指定列', () {
    const left = 'id,ts,name\n1,2026-01-01,Tom\n2,2026-01-02,Amy';
    const right = 'id,ts,name\n1,2026-11-15,Tom\n2,2026-11-15,Amy';

    test('不忽略时，只有时间戳不同的行也算变了', () {
      expect(_cmp(left, right).changedRowCount, 2);
    });

    test('忽略 ts 列后，两行都没有变化', () {
      final r = _cmp(left, right, ignoreColumns: {'ts'});
      expect(r.changedRowCount, 0);
    });

    test('忽略列后单元格里的变化仍然被发现', () {
      const r2 = 'id,ts,name\n1,2026-11-15,Tommy\n2,2026-11-15,Amy';
      final r = _cmp(left, r2, ignoreColumns: {'ts'});
      expect(r.changedRowCount, 1, reason: 'Tom 改成了 Tommy');
    });

    test('忽略列 + 忽略行序可以一起用', () {
      const r3 = 'id,ts,name\n2,2026-11-15,Amy\n1,2026-11-15,Tom';
      final r = _cmp(left, r3, ignoreColumns: {'ts'}, ignoreRowOrder: true);
      expect(r.changedRowCount, 0);
    });

    test('忽略主键列不影响按主键对齐（主键仍用于配对）', () {
      const r4 = 'id,ts,name\n2,2026-11-15,Amy\n1,2026-11-15,Tom';
      final r = _cmp(left, r4, key: 'id', ignoreColumns: {'id', 'ts'});
      expect(r.changedRowCount, 0);
    });
  });

  group('忽略列：支持 #列号（两侧表头名字对不上时）', () {
    const left = 'id,time,val\n1,2026-01-01,a\n2,x,b\n';
    // 右表第二列叫 timestamp，与左表的 time 名字对不上
    const right = 'id,timestamp,val\n1,2026-11-11,a\n2,y,b\n';

    test('按名字忽略不掉（表头不同）', () {
      final r = _cmp(left, right, key: 'id', ignoreColumns: {'time'});
      expect(r.changedRowCount, 2);
    });

    test('按 #2 忽略第二列后只剩 val 的差异', () {
      final r = _cmp(left, right, key: 'id', ignoreColumns: {'#2'});
      expect(r.changedRowCount, 1);
    });

    test('#1 是被忽略的自增 id 列（名字还不同），按 name 对齐后无差异', () {
      const l = 'id,name\n1,tom\n2,amy\n';
      const rr = 'index,name\n9,tom\n8,amy\n';
      final r = _cmp(l, rr, key: 'name', ignoreColumns: {'#1'});
      expect(r.changedRowCount, 0);
    });

    test('越界 / 非法的 #N 不抛异常', () {
      final r = _cmp(left, right, key: 'id', ignoreColumns: {'#99', '#x', '#'});
      expect(r, isNotNull);
    });

    test('名字和列号可以混着用', () {
      final r = _cmp(left, right, key: 'id', ignoreColumns: {'time', '#2'});
      expect(r.changedRowCount, 2);
    });
  });
}
