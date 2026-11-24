import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_diff.dart';

/// 对比引擎的性能优化不能改变结果。
///
/// 这一批用例盯的是本轮加的三处加速：
/// 1. `diffLines` 的「归一化后逐行相同 → 全 equal」快速路径
/// 2. `_normKey` 的「所有忽略开关都关着」快速路径
/// 3. `_similarityScore` 的公共前后缀剥离 + buffer 复用
///
/// 前两条是纯等价变换，第三条靠 LCS 的标准性质（首字符相同则必可纳入某个 LCS），
/// 但性质用错了就会悄悄把「修改」算成「删除 + 新增」，所以这里逐条钉住。
void main() {
  group('全等快速路径', () {
    test('相同文本 → 全部 equal，行号连续', () {
      final d = diffLines('a\nb\nc', 'a\nb\nc');
      expect(d.length, 3);
      expect(d.every((e) => e.type == LineDiffType.equal), isTrue);
      expect(d.map((e) => e.leftLine).toList(), [1, 2, 3]);
      expect(d.map((e) => e.rightLine).toList(), [1, 2, 3]);
    });

    test('只差大小写、开 ignoreCase → 全 equal', () {
      final d = diffLines('Hello\nWorld', 'hello\nworld', ignoreCase: true);
      expect(d.every((e) => e.type == LineDiffType.equal), isTrue);
      // 显示文本仍是原文（归一化只用于比较）
      expect(d.first.text, 'Hello');
    });

    test('只差行尾空白、开 ignoreTrailingWhitespace → 全 equal', () {
      final d = diffLines('a  \nb\t', 'a\nb', ignoreTrailingWhitespace: true);
      expect(d.every((e) => e.type == LineDiffType.equal), isTrue);
    });

    test('只差空行、开 ignoreBlankLines → 行数不同但无差异块', () {
      final blocks = buildDiffBlocks(diffLines('a\n\nb', 'a\nb', ignoreBlankLines: true));
      expect(blocks, isEmpty);
    });

    test('行数不同时快速路径不生效，仍走完整算法', () {
      final blocks = buildDiffBlocks(diffLines('a\nb', 'a\nb\nc'));
      expect(blocks.length, 1);
      expect(blocks.first.rightLines.length, 1);
    });

    test('空文本边界', () {
      expect(diffLines('', '').every((e) => e.type == LineDiffType.equal), isTrue);
      expect(buildDiffBlocks(diffLines('', 'a')).length, 1);
      expect(buildDiffBlocks(diffLines('a', '')).length, 1);
    });
  });

  group('相似度配对：前后缀剥离不改变结果', () {
    test('只差中间一个字符 → 配成「修改」而不是删 + 增', () {
      final blocks = buildDiffBlocks(diffLines('abc', 'axc'));
      expect(blocks.length, 1);
      expect(blocks.first.pairs.length, 1);
    });

    test('缩进 + 标识符都变了，但主体相同 → 仍配对', () {
      final blocks = buildDiffBlocks(
          diffLines('    final value = compute(1);', '  final result = compute(2);'));
      expect(blocks.first.pairs.length, 1);
    });

    test('完全不同的两行 → 不配对（删 + 增）', () {
      final blocks = buildDiffBlocks(diffLines('aaaa', 'zzzz'));
      expect(blocks.first.pairs, isEmpty);
      expect(blocks.first.leftLines.length, 1);
      expect(blocks.first.rightLines.length, 1);
    });

    test('一行是另一行的前缀 → 仍能配对', () {
      final blocks = buildDiffBlocks(diffLines('abcdef', 'abc'));
      expect(blocks.first.pairs.length, 1);
    });

    test('长行共享长前缀：只差尾部时配对', () {
      final pad = 'x' * 500;
      final blocks = buildDiffBlocks(diffLines('${pad}one', '${pad}two'));
      expect(blocks.first.pairs.length, 1);
    });
  });

  group('规模与稳定性', () {
    test('1000 行里只改一行 → 恰好 1 个差异块', () {
      final left = List.generate(1000, (i) => 'line $i').join('\n');
      final rightLines = List.generate(1000, (i) => 'line $i');
      rightLines[500] = 'line five hundred';
      final blocks = buildDiffBlocks(diffLines(left, rightLines.join('\n')));
      expect(blocks.length, 1);
      expect(blocks.first.leftStart, 500);
      expect(blocks.first.pairs.length, 1);
    });

    test('大块删除 + 新增多行，配对结果保序不交叉', () {
      final left = List.generate(30, (i) => 'a$i').join('\n');
      final right = List.generate(30, (i) => 'a${i + 100}').join('\n');
      final blocks = buildDiffBlocks(diffLines(left, right));
      expect(blocks.length, 1);
      final pairs = blocks.first.pairs;
      for (var k = 1; k < pairs.length; k++) {
        expect(pairs[k].left > pairs[k - 1].left, isTrue);
        expect(pairs[k].right > pairs[k - 1].right, isTrue);
      }
    });

    test('CRLF 与 LF 的同内容 → 无差异块', () {
      final blocks = buildDiffBlocks(diffLines('a\r\nb\r\n', 'a\nb\n'));
      expect(blocks, isEmpty);
    });

    test('行首 BOM 不影响比较', () {
      final blocks = buildDiffBlocks(diffLines('\uFEFFabc', 'abc'));
      expect(blocks, isEmpty);
    });
  });
}
