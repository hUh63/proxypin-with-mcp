// 对比引擎的「忽略 XXX」开关：这些选项一旦算错，用户会以为自己的文件完全一样
// （或者完全不一样），所以每条都锁一个用例。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_diff.dart';

int changesOf(String a, String b,
    {bool ignoreCase = false,
    bool ignoreWhitespace = false,
    bool ignoreTrailingWhitespace = false,
    bool ignoreBlankLines = false,
    bool ignoreComments = false}) {
  final diffs = diffLines(a, b,
      ignoreCase: ignoreCase,
      ignoreWhitespace: ignoreWhitespace,
      ignoreTrailingWhitespace: ignoreTrailingWhitespace,
      ignoreBlankLines: ignoreBlankLines,
      ignoreComments: ignoreComments);
  final stats = diffStats(buildDiffBlocks(diffs,
      ignoreCase: ignoreCase,
      ignoreWhitespace: ignoreWhitespace,
      ignoreTrailingWhitespace: ignoreTrailingWhitespace,
      ignoreBlankLines: ignoreBlankLines,
      ignoreComments: ignoreComments));
  return stats.added + stats.deleted + stats.modified;
}

void main() {
  group('ignoreComments', () {
    test('整行注释视为空行', () {
      expect(changesOf('a\n// 说明\nb', 'a\n// 换了个说法\nb'), greaterThan(0));
      expect(
        changesOf('a\n// 说明\nb', 'a\n// 换了个说法\nb', ignoreComments: true),
        0,
      );
    });

    test('行尾注释被忽略', () {
      expect(
        changesOf('x = 1; // 旧注释', 'x = 1; // 新注释', ignoreComments: true),
        0,
      );
    });

    test('行尾空格后的 // 才算注释', () {
      expect(
        changesOf('x = 1; // a', 'x = 1; // a', ignoreComments: true),
        0,
      );
    });

    test('URL 里的 // 不会被当成注释', () {
      // 关键点：http:// 前面是冒号不是空格，不能被剥掉。
      expect(
        changesOf('var u = "http://a";', 'var u = "http://b";', ignoreComments: true),
        greaterThan(0),
      );
    });

    test('# 开头的行也算注释', () {
      expect(changesOf('# a\nx', '# b\nx', ignoreComments: true), 0);
    });

    test('代码本身的差异照旧能查出来', () {
      expect(
        changesOf('x = 1; // a', 'x = 2; // a', ignoreComments: true),
        greaterThan(0),
      );
    });
  });

  group('ignoreBlankLines', () {
    // 这个开关的语义是「空行的内容不参与比较」——空行里带了空格 / Tab 时不算差异。
    // 它**不是** Beyond Compare 那种「多几个空行也不算差异」：行数仍然要对得上，
    // 因为对齐视图按行配对，凭空吞行会让左右行号错位。
    test('空行里带空格 / Tab 不算差异', () {
      expect(changesOf('a\nb', 'a\n \nb'), greaterThan(0));
      expect(changesOf('a\nb', 'a\n \nb', ignoreBlankLines: true), 0);
      expect(changesOf('a\n \nb', 'a\n\t\nb', ignoreBlankLines: true), 0);
    });

    test('多出行仍然算差异（按行配对，不能凭空吞行）', () {
      expect(changesOf('a\nb', 'a\n\n\nb', ignoreBlankLines: true), greaterThan(0));
    });

    test('真正的行差异不受影响', () {
      expect(changesOf('a\nb', 'a\n\nc', ignoreBlankLines: true), greaterThan(0));
    });
  });

  group('ignoreTrailingWhitespace', () {
    test('行尾空格不算差异', () {
      expect(changesOf('a  \nb', 'a\nb', ignoreTrailingWhitespace: true), 0);
    });
  });
}
