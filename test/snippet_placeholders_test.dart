// 片段占位符：`$1` / `${1:默认值}` / `$0`。
// 这套语法只要有一处把「普通文本里的 $1」也吞掉，就会把 shell 脚本、正则替换改坏，
// 所以每条边界都锁用例。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/snippet_placeholders.dart';

void main() {
  group('parseSnippetPlaceholders', () {
    test('没有占位符时原样返回', () {
      final r = parseSnippetPlaceholders('console.log("hi")');
      expect(r.text, 'console.log("hi")');
      expect(r.hasStops, isFalse);
    });

    test('\${1:默认值} 插入默认文本并选中整段', () {
      final r = parseSnippetPlaceholders('for (var \${1:i} = 0; \${2:cond}; \${3:i++}) {}\n\$0');
      expect(r.text, 'for (var i = 0; cond; i++) {}\n');
      expect(r.stops.length, 4);
      // 第一个停靠点正好圈住 i
      expect(r.stops[0].start, 10);
      expect(r.stops[0].end, 11);
      expect(r.text.substring(r.stops[0].start, r.stops[0].end), 'i');
      // $0 永远排最后，且是零宽
      expect(r.stops.last.isCaret, isTrue);
      expect(r.stops.last.start, r.text.length);
    });

    test('\$1 这种零宽停靠点按编号顺序', () {
      final r = parseSnippetPlaceholders('a\$2 b\$1 c');
      expect(r.text, 'a b c');
      expect(r.stops.length, 2);
      // $1 在前（编号顺序），$2 在后
      expect(r.stops[0].start, 3);
      expect(r.stops[1].start, 1);
    });

    test(r'\$1 是字面美元符，不产生停靠点', () {
      final r = parseSnippetPlaceholders(r'echo \$1');
      expect(r.text, 'echo \$1');
      expect(r.hasStops, isFalse);
    });

    test('\$foo 不是占位符（后面跟标识符字符）', () {
      final r = parseSnippetPlaceholders('echo \$HOME and \$1x');
      expect(r.text, 'echo \$HOME and \$1x');
      expect(r.hasStops, isFalse);
    });

    test('重复编号以最后一次为准', () {
      final r = parseSnippetPlaceholders('\$1 vs \$1');
      expect(r.text, ' vs ');
      expect(r.stops.length, 1);
      expect(r.stops[0].start, 4);
    });

    test('只有 \$0 时也能正确收尾', () {
      final r = parseSnippetPlaceholders('if () {\$0}');
      expect(r.text, 'if () {}');
      expect(r.stops.single.start, 7);
    });

    test('缺右花括号的片段不崩，按原样保留', () {
      final r = parseSnippetPlaceholders('x \${1:abc');
      expect(r.hasStops, isFalse);
      expect(r.text, 'x \${1:abc');
    });
  });
}
