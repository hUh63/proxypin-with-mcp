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

  group('锚点索引：唯一行表 + 较小侧遍历', () {
    test('重复行不当锚点，段内无锚点时仍走 lookahead 兜底', () {
      final blocks = buildDiffBlocks(diffLines('common\nA\ncommon', 'common\nB\ncommon'));
      expect(blocks.length, 1);
      // leftLines / rightLines 存的是 0-based 行号，不是文本
      expect(blocks.first.leftLines.length, 1);
      expect(blocks.first.rightLines.length, 1);
    });

    test('两侧行数悬殊时仍能靠唯一行定位', () {
      final left = 'a\nanchor\nb';
      final right = [
        ...List.generate(2000, (i) => 'x$i'),
        'anchor',
        'b',
      ].join('\n');
      final blocks = buildDiffBlocks(diffLines(left, right));
      expect(blocks.length, 1);
      expect(blocks.first.leftLines.length, 1);
      expect(blocks.first.rightLines.length, 2000);
    });

    test('一侧为空不产生锚点异常', () {
      expect(buildDiffBlocks(diffLines('', 'a\nb')).length, 1);
      expect(buildDiffBlocks(diffLines('a\nb', '')).length, 1);
    });
  });

  group('相似度：长度上界剪枝与 buffer 复用', () {
    test('长度比够不到阈值 → 不配对（与完整 LCS 一致）', () {
      final blocks = buildDiffBlocks(diffLines('a', 'abcdefghijklmnop'));
      expect(blocks.length, 1);
      expect(blocks.first.pairs, isEmpty);
    });

    test('短行是长行前缀但长度差过大 → 同样不配对', () {
      final blocks = buildDiffBlocks(diffLines('abc', 'abcxxxxxxxxxxxx'));
      expect(blocks.first.pairs, isEmpty);
    });

    test('长度相近且共享前缀 → 仍配成修改', () {
      final blocks = buildDiffBlocks(diffLines('abcdefgh', 'abcdefgi'));
      expect(blocks.first.pairs.length, 1);
    });

    test('同一块里右行长度交替变化，scratch 复用不能串味', () {
      final left = ['aaa111', 'bbbb2222', 'cc333', 'dddddd44444'].join('\n');
      final right = ['aaa112', 'bbbb2223', 'cc334', 'dddddd44446'].join('\n');
      final blocks = buildDiffBlocks(diffLines(left, right));
      expect(blocks.length, 1);
      expect(blocks.first.pairs.length, 4);
      for (var k = 0; k < 4; k++) {
        expect(blocks.first.pairs[k].left, k);
        expect(blocks.first.pairs[k].right, k);
      }
    });

    test('混合长短行 + 完全不相似行，配对仍保序不交叉', () {
      final left = ['alpha', 'b', 'cccccc', 'dd'].join('\n');
      final right = ['alphb', 'b', 'zzzzzzzzzzzz', 'de'].join('\n');
      final blocks = buildDiffBlocks(diffLines(left, right));
      expect(blocks.isNotEmpty, isTrue);
      for (final b in blocks) {
        for (var k = 1; k < b.pairs.length; k++) {
          expect(b.pairs[k].left > b.pairs[k - 1].left, isTrue);
          expect(b.pairs[k].right > b.pairs[k - 1].right, isTrue);
        }
      }
    });
  });

  group('规模与稳定性', () {
    test('1000 行里只改一行 → 恰好 1 个差异块', () {
      final left = List.generate(1000, (i) => 'line $i').join('\n');
      final rightLines = List.generate(1000, (i) => 'line $i');
      // 改后的行要与原行足够像（相似度 ≥ 500‰）才配成「修改」；
      // 'line 500' → 'line five hundred' 只有 277‰，会被算成删 + 增。
      rightLines[500] = 'line 5001';
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

    test('整段重写（相似度全低）→ 配对为空，且不建 dp 表也不会错', () {
      final left = List.generate(50, (i) => 'alpha-$i').join('\n');
      final right = List.generate(50, (i) => 'z' * (i % 3 + 1) * 7).join('\n');
      final blocks = buildDiffBlocks(diffLines(left, right));
      expect(blocks.length, 1);
      expect(blocks.first.pairs, isEmpty);
    });

    test('块内行数乘积超过上限 → 退化为按位置配对', () {
      final left = List.generate(200, (i) => 'row $i same').join('\n');
      final right = List.generate(200, (i) => 'row $i same!').join('\n');
      // 200×200 = 40000 > _pairMaxCells(20000)，走「按位置配对」的兜底路径。
      final blocks = buildDiffBlocks(diffLines(left, right));
      expect(blocks.length, 1);
      expect(blocks.first.pairs.length, 200);
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
