import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/region_folds.dart';

String _sig(List<RegionFold> r) =>
    r.map((e) => '${e.startLine}-${e.endLine}').join(',');

void main() {
  group('#region 扫描', () {
    test('基本的一对', () {
      const src = '#region A\nx\ny\n#endregion\nz';
      expect(_sig(scanRegionFolds(src)), '0-3');
    });

    test('嵌套：内外都能折', () {
      const src = '#region 外\n#region 内\na\n#endregion\nb\n#endregion';
      expect(_sig(scanRegionFolds(src)), '0-5,1-3');
    });

    test('认 // 与 //region 与块注释与 HTML 注释', () {
      const src = '// #region a\nx\n// #endregion\n'
          '//region b\ny\n//endregion\n'
          '/* #region c */\nz\n/* #endregion */\n'
          '<!-- #region d -->\nw\n<!-- #endregion -->';
      expect(scanRegionFolds(src).length, 4);
    });

    test('大小写不敏感', () {
      const src = '#Region A\nx\n#EndRegion';
      expect(scanRegionFolds(src).length, 1);
    });

    test('没闭合的延续到文件末尾，尾部空行不算', () {
      const src = '#region A\nx\ny\n\n\n';
      final r = scanRegionFolds(src).single;
      expect(r.startLine, 0);
      expect(r.endLine, 2);
    });

    test('多余的 #endregion 被忽略', () {
      const src = '#endregion\n#region A\nx\n#endregion';
      expect(_sig(scanRegionFolds(src)), '1-3');
    });

    test('普通单词 region 不误判', () {
      const src = 'var region = 1;\n// this region is fine\nfinal regions = [];';
      expect(scanRegionFolds(src), isEmpty);
    });

    test('相邻的一对也能折叠（折起来只剩 #region 那行）', () {
      const src = '#region A\n#endregion';
      expect(_sig(scanRegionFolds(src)), '0-1');
    });

    test('上限生效', () {
      final sb = StringBuffer();
      for (var i = 0; i < 20; i++) {
        sb.writeln('#region r$i');
        sb.writeln('x');
        sb.writeln('#endregion');
      }
      expect(scanRegionFolds(sb.toString(), maxFolds: 5), hasLength(5));
    });
  });
}
