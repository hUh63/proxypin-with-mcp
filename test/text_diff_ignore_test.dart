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
    // 对齐语义按 Beyond Compare 来：空行（不管里面有没有空格 / Tab）只要在差异段里
    // 就整段忽略，所以「右边多两行空行」不显示差异。真正的内容变化照旧能查出来。
    test('多出来的空行不算差异', () {
      expect(changesOf('a\nb', 'a\n\n\nb', ignoreBlankLines: true), 0);
      expect(changesOf('a\nb', 'a\n \nb', ignoreBlankLines: true), 0);
      expect(changesOf('a\n \nb', 'a\n\t\nb', ignoreBlankLines: true), 0);
    });

    test('不打开开关时照旧算差异', () {
      expect(changesOf('a\nb', 'a\n\n\nb'), greaterThan(0));
    });

    test('真正的内容变化不受影响', () {
      expect(changesOf('a\nb', 'a\n\nc', ignoreBlankLines: true), greaterThan(0));
      expect(changesOf('a\nb', 'a\nc', ignoreBlankLines: true), greaterThan(0));
    });
  });

  group('ignoreTrailingWhitespace', () {
    test('行尾空格不算差异', () {
      expect(changesOf('a  \nb', 'a\nb', ignoreTrailingWhitespace: true), 0);
    });
  });
}
