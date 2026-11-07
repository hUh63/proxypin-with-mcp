import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/todo_scanner.dart';

void main() {
  group('识别各种注释风格', () {
    test('C 风格行注释', () {
      final hits = TodoScanner.scan('int a = 1;\n// TODO: 改成常量\n');
      expect(hits.length, 1);
      expect(hits.first.line, 2);
      expect(hits.first.tag, 'TODO');
      expect(hits.first.text, '改成常量');
    });

    test('行尾注释', () {
      final hits = TodoScanner.scan('final x = 1; // FIXME 这里会崩');
      expect(hits.length, 1);
      expect(hits.first.tag, 'FIXME');
      expect(hits.first.text, '这里会崩');
    });

    test('Python / Shell 的 #', () {
      final hits = TodoScanner.scan('# HACK 临时绕过\nprint(1)\n  # todo 大小写都认');
      expect(hits.length, 2);
      expect(hits[0].tag, 'HACK');
      expect(hits[1].tag, 'TODO');
      expect(hits[1].line, 3);
    });

    test('块注释的 * 行', () {
      final hits = TodoScanner.scan('/*\n * TODO 重构\n */');
      expect(hits.length, 1);
      expect(hits.first.line, 2);
      expect(hits.first.text, '重构');
    });

    test('HTML 注释且去掉收尾符', () {
      final hits = TodoScanner.scan('<!-- TODO: 补文案 -->');
      expect(hits.length, 1);
      expect(hits.first.text, '补文案');
    });

    test('SQL / Lua 的 --', () {
      final hits = TodoScanner.scan('-- NOTE 索引要重建');
      expect(hits.length, 1);
      expect(hits.first.tag, 'NOTE');
      expect(hits.first.text, '索引要重建');
    });

    test('ini / 汇编的 ;', () {
      final hits = TodoScanner.scan('; TODO 补配置');
      expect(hits.length, 1);
      expect(hits.first.tag, 'TODO');
    });

    test('无说明文字也能识别', () {
      final hits = TodoScanner.scan('// TODO');
      expect(hits.length, 1);
      expect(hits.first.text, '');
    });

    test('标记后面直接跟中文（无分隔符）', () {
      final hits = TodoScanner.scan('// TODO改这里');
      expect(hits.length, 1);
      expect(hits.first.text, '改这里');
    });

    test('行内多个标记只认第一个', () {
      final hits = TodoScanner.scan('// TODO 甲 FIXME 乙');
      expect(hits.length, 1);
      expect(hits.first.tag, 'TODO');
    });
  });

  group('不该命中的', () {
    test('字符串里的 TODO', () {
      expect(TodoScanner.scan('final s = "TODO: 不是任务";'), isEmpty);
      expect(TodoScanner.scan("final s = 'FIXME';"), isEmpty);
    });

    test('标识符里的 TODO', () {
      expect(TodoScanner.scan('final todoList = <int>[];'), isEmpty);
      expect(TodoScanner.scan('void myTodoHelper() {}'), isEmpty);
    });

    test('URL 里的单词', () {
      expect(TodoScanner.scan('// see https://example.com/notodo'), isEmpty);
    });

    test('空文本', () {
      expect(TodoScanner.scan(''), isEmpty);
    });
  });

  group('行号与数量', () {
    test('行号从 1 开始且准确', () {
      final hits = TodoScanner.scan('a\nb\nc\n// TODO x\nd');
      expect(hits.single.line, 4);
    });

    test('limit 生效', () {
      final text = List<String>.generate(50, (i) => '// TODO $i').join('\n');
      expect(TodoScanner.scan(text, limit: 10).length, 10);
    });

    test('只关心指定标签', () {
      const text = '// TODO a\n// FIXME b\n// NOTE c';
      final hits = TodoScanner.scan(text, tags: const ['FIXME']);
      expect(hits.length, 1);
      expect(hits.first.tag, 'FIXME');
    });

    test('\r\n 换行', () {
      final hits = TodoScanner.scan('a\r\n// TODO x\r\nb');
      expect(hits.single.line, 2);
      expect(hits.single.text, 'x');
    });
  });

  group('统计与排序', () {
    test('countByTag', () {
      final hits = TodoScanner.scan('// TODO a\n// TODO b\n// FIXME c');
      final counts = TodoScanner.countByTag(hits);
      expect(counts['TODO'], 2);
      expect(counts['FIXME'], 1);
    });

    test('sortByTag 按默认标签顺序', () {
      final hits = TodoScanner.scan('// NOTE a\n// FIXME b\n// TODO c');
      final sorted = TodoScanner.sortByTag(hits);
      expect(sorted.map((e) => e.tag).toList(), ['TODO', 'FIXME', 'NOTE']);
    });
  });

  test('tooLarge', () {
    expect(TodoScanner.tooLarge('abc', maxBytes: 10), isFalse);
    expect(TodoScanner.tooLarge('a' * 100, maxBytes: 10), isTrue);
  });
}
