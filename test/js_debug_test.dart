// JS 行级调试插桩的单元测试。
//
// 这块最容易出的事故是「插出来的代码不合法」——用户按下调试，看到的是自己脚本的
// SyntaxError，完全没法判断是不是工具的锅。所以这里逐条锁住边界：对象字面量、
// 参数列表、注释、else 分支都不能被插。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/js_debug.dart';

void main() {
  group('instrument', () {
    test('顶层语句逐行插桩', () {
      final src = 'var a = 1;\nvar b = 2;\nconsole.log(a + b);';
      final out = JsDebug.instrument(src);
      expect(JsDebug.probe.allMatches(out).length, 3);
      expect(out, contains('${JsDebug.probe}(1);'));
      expect(out, contains('${JsDebug.probe}(3);'));
      // 行号不能被插桩改掉：插进去的行都是独立行，原行内容原样保留。
      expect(out, contains('var b = 2;'));
    });

    test('对象字面量内部不插（否则会变成语法错）', () {
      const src = 'const o = {\n  a: 1,\n  b: 2,\n};';
      final out = JsDebug.instrument(src);
      expect(JsDebug.probe.allMatches(out).length, 1);
      expect(out, contains('${JsDebug.probe}(1);'));
      expect(out, isNot(contains('${JsDebug.probe}(2);')));
    });

    test('花括号块内部照常插桩', () {
      const src = 'function f(x) {\n  if (x) {\n    return 1;\n  }\n  return 2;\n}';
      final out = JsDebug.instrument(src);
      expect(out, contains('${JsDebug.probe}(2);'));
      expect(out, contains('${JsDebug.probe}(3);'));
      expect(out, contains('${JsDebug.probe}(5);'));
    });

    test('else / catch / case 行不插', () {
      const src = 'if (a) {\n  x();\n} else {\n  y();\n}\ntry {\n  z();\n} catch (e) {\n  w();\n}';
      final out = JsDebug.instrument(src);
      expect(out, isNot(contains('${JsDebug.probe}(3);')));
      expect(out, isNot(contains('${JsDebug.probe}(8);')));
      // 块内的真正语句还是要插。
      expect(out, contains('${JsDebug.probe}(4);'));
      expect(out, contains('${JsDebug.probe}(9);'));
    });

    test('注释行不插', () {
      const src = '// 说明\nvar a = 1;\n/* 块注释 */\nvar b = 2;';
      final out = JsDebug.instrument(src);
      expect(out, isNot(contains('${JsDebug.probe}(1);')));
      expect(out, isNot(contains('${JsDebug.probe}(3);')));
      expect(out, contains('${JsDebug.probe}(2);'));
    });

    test('参数列表里的续行不插', () {
      const src = 'foo(\n  1,\n  2\n);';
      final out = JsDebug.instrument(src);
      // 第 1 行可以插（文件开头），后面的参数行不能。
      expect(out, contains('${JsDebug.probe}(1);'));
      expect(out, isNot(contains('${JsDebug.probe}(2);')));
      expect(out, isNot(contains('${JsDebug.probe}(3);')));
    });

    test('类体里不插，方法体里插', () {
      const src = 'class A {\n  constructor() {\n    this.x = 1;\n  }\n  static z() {\n    return 2;\n  }\n}';
      final out = JsDebug.instrument(src);
      // 类体起始行本身可以插（它在类外面），但类体直接子层不能。
      expect(out, isNot(contains('${JsDebug.probe}(2);')));
      expect(out, isNot(contains('${JsDebug.probe}(5);')));
      expect(out, contains('${JsDebug.probe}(3);'));
      expect(out, contains('${JsDebug.probe}(6);'));
    });

    test('标签行之后不插（否则 break label 找不到标签）', () {
      const src = 'outer:\nfor (var i = 0; i < 2; i++) {\n  if (i === 1) break outer;\n}';
      final out = JsDebug.instrument(src);
      expect(out, isNot(contains('${JsDebug.probe}(2);')));
    });

    test('一行都插不进去时原样返回', () {
      const src = '}';
      expect(JsDebug.instrument(src), src);
    });

    test('数组字面量内部不插', () {
      const src = 'const arr = [\n  1,\n  2,\n];';
      final out = JsDebug.instrument(src);
      expect(JsDebug.probe.allMatches(out).length, 1);
    });
  });

  group('breakLineFrom', () {
    test('取出命中的行号', () {
      expect(JsDebug.breakLineFrom('__PP_BREAK__:12'), 12);
      expect(JsDebug.breakLineFrom('Error: __PP_BREAK__:7 at foo'), 7);
    });

    test('不是断点错误时返回 null', () {
      expect(JsDebug.breakLineFrom('TypeError: x is not a function'), isNull);
      expect(JsDebug.breakLineFrom(null), isNull);
    });
  });

  group('collectTests', () {
    test('抓 test / it 用例名与行号', () {
      const src = "test('加法', () => {\n  expect(1 + 1).toBe(2);\n});\n"
          'it("减法", function () {\n  1;\n});';
      final list = JsDebug.collectTests(src);
      expect(list.length, 2);
      expect(list[0].name, '加法');
      expect(list[0].line, 1);
      expect(list[1].name, '减法');
      expect(list[1].line, 4);
    });

    test('方法调用 obj.test 不算用例', () {
      const src = 'obj.test("不是用例");';
      expect(JsDebug.collectTests(src), isEmpty);
    });
  });

  group('prelude', () {
    test('断点表写进预置，命中计数与跳过次数可续跑', () {
      final src = JsDebug.prelude({3, 9});
      expect(src, contains('__ppHits'));
      expect(src, contains('__ppSkip'));
      expect(src, contains('"3"'));
      expect(src, contains('"9"'));
    });
  });
}
