import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/table_diff.dart';

void main() {
  group('guessDelimiter', () {
    test('逗号', () {
      expect(guessDelimiter('a,b,c\n1,2,3'), ',');
    });
    test('制表符', () {
      expect(guessDelimiter('a\tb\tc\n1\t2\t3'), '\t');
    });
    test('分号', () {
      expect(guessDelimiter('a;b;c\n1;2;3'), ';');
    });
    test('管道', () {
      expect(guessDelimiter('| a | b |\n| 1 | 2 |'), '|');
    });
    test('没有分隔符时回退逗号', () {
      expect(guessDelimiter('hello\nworld'), ',');
    });
    test('引号内的逗号不算数', () {
      // 整行只有一个真分隔符，引号里那个不参与统计。
      expect(guessDelimiter('"x,y",z'), ',');
    });
  });

  group('parseTable', () {
    test('基本解析', () {
      final t = parseTable('name,age\nTom,3\nAmy,4');
      expect(t.headers, ['name', 'age']);
      expect(t.rowCount, 2);
      expect(t.rows[0], ['Tom', '3']);
      expect(t.delimiter, ',');
    });

    test('引号包裹的单元格里的分隔符', () {
      final t = parseTable('a,b\n"1,2",3');
      expect(t.rows[0], ['1,2', '3']);
    });

    test('引号内的换行不断行', () {
      final t = parseTable('a,b\n"line1\nline2",3');
      expect(t.rowCount, 1);
      expect(t.rows[0][0], 'line1\nline2');
    });

    test('双引号转义', () {
      final t = parseTable('a\n"say ""hi"""');
      expect(t.rows[0][0], 'say "hi"');
    });

    test('CRLF 不残留回车', () {
      final t = parseTable('a,b\r\n1,2\r\n');
      expect(t.rowCount, 1);
      expect(t.rows[0][1], '2');
    });

    test('列数不齐时补齐', () {
      final t = parseTable('a,b,c\n1,2');
      expect(t.rowCount, 1);
      expect(t.rows[0].length, 3);
      expect(t.rows[0][2], '');
    });

    test('表头有空名字时给占位', () {
      final t = parseTable('a,,c\n1,2,3');
      expect(t.headers[1], '列2');
    });

    test('空文本', () {
      final t = parseTable('');
      expect(t.rowCount, 0);
      expect(t.headers, isEmpty);
    });

    test('尾部空行被丢掉', () {
      final t = parseTable('a,b\n1,2\n\n\n');
      expect(t.rowCount, 1);
    });

    test('指定分隔符优先于猜测', () {
      final t = parseTable('a;b\n1;2', delimiter: ';');
      expect(t.headers, ['a', 'b']);
    });
  });

  group('compareTables 按行号对齐', () {
    test('完全相同时没有差异', () {
      final t = parseTable('a,b\n1,2');
      final r = compareTables(t, t);
      expect(r.identical, isTrue);
      expect(r.changedRowCount, 0);
    });

    test('单元格变化被定位到列', () {
      final l = parseTable('a,b\n1,2');
      final r = compareTables(l, parseTable('a,b\n1,9'));
      expect(r.changedRowCount, 1);
      expect(r.rows[0].changedColumns, [1]);
      expect(r.columns[1].state, TableColumnState.changed);
      expect(r.columns[1].changedCells, 1);
      expect(r.columns[0].state, TableColumnState.unchanged);
    });

    test('右侧多行算新增', () {
      final l = parseTable('a\n1');
      final r = compareTables(l, parseTable('a\n1\n2'));
      expect(r.addedRows, 1);
      expect(r.rows.last.state, TableRowState.added);
      expect(r.rows.last.leftIndex, -1);
    });

    test('右侧少行算删除', () {
      final r = compareTables(parseTable('a\n1\n2'), parseTable('a\n1'));
      expect(r.removedRows, 1);
      expect(r.rows.last.state, TableRowState.removed);
      expect(r.rows.last.rightIndex, -1);
    });

    test('ignoreCase 生效', () {
      final l = parseTable('a\nTom');
      final rr = parseTable('a\ntom');
      expect(compareTables(l, rr).changedRowCount, 1);
      expect(compareTables(l, rr, ignoreCase: true).changedRowCount, 0);
    });

    test('ignoreWhitespace 生效', () {
      final l = parseTable('a\n"  x  y  "');
      final rr = parseTable('a\n"x y"');
      expect(compareTables(l, rr).changedRowCount, 1);
      expect(compareTables(l, rr, ignoreWhitespace: true).changedRowCount, 0);
    });
  });

  group('compareTables 按主键对齐', () {
    test('顺序不同但内容相同不算差异', () {
      final l = parseTable('id,v\n1,a\n2,b');
      final r = compareTables(l, parseTable('id,v\n2,b\n1,a'), keyColumn: 'id');
      expect(r.identical, isTrue);
      expect(r.rowKey, 'id');
    });

    test('乱序下仍能定位到变化的行', () {
      final l = parseTable('id,v\n1,a\n2,b');
      final r = compareTables(l, parseTable('id,v\n2,B\n1,a'), keyColumn: 'id');
      expect(r.changedRowCount, 1);
      final row = r.rows.firstWhere((x) => x.state == TableRowState.changed);
      expect(row.leftIndex, 1);
      expect(row.rightIndex, 0);
    });

    test('主键新增的行', () {
      final l = parseTable('id,v\n1,a');
      final r = compareTables(l, parseTable('id,v\n1,a\n9,z'), keyColumn: 'id');
      expect(r.addedRows, 1);
      expect(r.removedRows, 0);
    });

    test('主键消失的行', () {
      final l = parseTable('id,v\n1,a\n9,z');
      final r = compareTables(l, parseTable('id,v\n1,a'), keyColumn: 'id');
      expect(r.removedRows, 1);
      expect(r.addedRows, 0);
    });

    test('主键列不存在时回退按行号', () {
      final l = parseTable('id,v\n1,a');
      final r = compareTables(l, parseTable('id,v\n1,a'), keyColumn: 'nope');
      expect(r.rowKey, '');
      expect(r.identical, isTrue);
    });

    test('主键可用列下标指定', () {
      final l = parseTable('id,v\n1,a\n2,b');
      final r = compareTables(l, parseTable('id,v\n2,b\n1,a'), keyColumn: '0');
      expect(r.identical, isTrue);
    });

    test('重复主键按出现顺序依次消耗，不误报', () {
      final l = parseTable('id,v\n1,a\n1,b');
      final r = compareTables(l, parseTable('id,v\n1,a\n1,b'), keyColumn: 'id');
      expect(r.identical, isTrue);
    });
  });

  group('列增删', () {
    test('右侧多一列', () {
      final r = compareTables(parseTable('a,b\n1,2'), parseTable('a,b,c\n1,2,3'));
      expect(r.addedColumns, 1);
      expect(r.columns.last.name, 'c');
      expect(r.columns.last.leftIndex, -1);
      expect(r.columns.last.state, TableColumnState.added);
    });

    test('右侧少一列', () {
      final r = compareTables(parseTable('a,b,c\n1,2,3'), parseTable('a,b\n1,2'));
      expect(r.removedColumns, 1);
      expect(r.columns.last.name, 'c');
      expect(r.columns.last.rightIndex, -1);
    });

    test('列顺序调换不算列增删', () {
      final r = compareTables(parseTable('a,b\n1,2'), parseTable('b,a\n2,1'));
      expect(r.addedColumns, 0);
      expect(r.removedColumns, 0);
      expect(r.identical, isTrue);
    });

    test('列改名 = 删一列 + 增一列', () {
      final r = compareTables(parseTable('a,b\n1,2'), parseTable('a,c\n1,2'));
      expect(r.addedColumns, 1);
      expect(r.removedColumns, 1);
    });
  });

  group('渲染辅助', () {
    test('leftCellsAt / rightCellsAt 对齐到列宽', () {
      final diff = compareTables(parseTable('a,b\n1,2'), parseTable('a,b,c\n1,2,3'));
      expect(diff.leftCellsAt(0).length, diff.columns.length);
      expect(diff.rightCellsAt(0)[2], '3');
      // 左侧没有 c 列，对应格子给空串。
      expect(diff.leftCellsAt(0)[2], '');
    });

    test('只有右侧有的行，左侧格子全空', () {
      final diff = compareTables(parseTable('a\n1'), parseTable('a\n1\n2'));
      final pos = diff.rows.length - 1;
      expect(diff.leftCellsAt(pos).every((e) => e.isEmpty), isTrue);
      expect(diff.rightCellsAt(pos), ['2']);
    });
  });
}
