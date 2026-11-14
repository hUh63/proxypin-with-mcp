// Emmet 展开：一层写错（缩进、闭合、$ 序号）人工很难在生成的一屏 HTML 里看出来，
// 所以每条用例都断言完整字符串。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/emmet.dart';

void main() {
  group('expandEmmet', () {
    test('单个标签', () {
      expect(expandEmmet('div')!.text, '<div></div>');
    });

    test('子级 > 与重复 *n', () {
      expect(
        expandEmmet('ul>li*3')!.text,
        '<ul>\n  <li></li>\n  <li></li>\n  <li></li>\n</ul>',
      );
    });

    test('id / class', () {
      expect(expandEmmet('div.card#main')!.text, '<div id="main" class="card"></div>');
    });

    test('多个 class', () {
      expect(expandEmmet('span.a.b')!.text, '<span class="a b"></span>');
    });

    test('属性与文本', () {
      expect(expandEmmet('a[href=x]{link}')!.text, '<a href="x">link</a>');
    });

    test('布尔属性（无值）', () {
      expect(expandEmmet('input[disabled]')!.text, '<input disabled />');
    });

    test('自闭合标签', () {
      expect(expandEmmet('img')!.text, '<img />');
      expect(expandEmmet('br')!.text, '<br />');
    });

    test(r'$ 序号替换', () {
      expect(
        expandEmmet(r'ul>li.item$*2')!.text,
        '<ul>\n  <li class="item1"></li>\n  <li class="item2"></li>\n</ul>',
      );
    });

    test('兄弟 +', () {
      expect(expandEmmet('p+p')!.text, '<p></p>\n<p></p>');
    });

    test('多层嵌套缩进跟随 indentUnit', () {
      expect(
        expandEmmet('div>div>span', indentUnit: '\t')!.text,
        '<div>\n\t<div>\n\t\t<span></span>\n\t</div>\n</div>',
      );
    });

    test('没有标签只有 class 时补 div', () {
      expect(expandEmmet('.box')!.text, '<div class="box"></div>');
    });

    test('空 / 含换行的输入不做展开', () {
      expect(expandEmmet(''), isNull);
      expect(expandEmmet('   '), isNull);
      expect(expandEmmet('div\nspan'), isNull);
    });

    test('光标位置落在末尾', () {
      final r = expandEmmet('p')!;
      expect(r.caretOffset, r.text.length);
    });

    test('重复次数上限兜底（不会展开出上千行）', () {
      final r = expandEmmet('li*999')!;
      expect(r.text.split('\n').length, 200);
    });
  });
}
