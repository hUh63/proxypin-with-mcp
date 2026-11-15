// detectMovedBlocks 的用例：搬家 vs 真改动必须区分开。
//
// 判据刻意保守（只配纯删除块 ↔ 纯新增块、块至少 2 行、内容完全一致），
// 所以这里重点验证「不该配的别配」——误报比漏报讨厌得多。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_diff.dart';

List<String> _lines(String t) => t.isEmpty ? const <String>[] : t.split('\n');

/// 用真实引擎跑一遍，得到 blocks（比手搓 DiffBlock 更接近线上行为）。
List<DiffBlock> _blocks(String left, String right) {
  final ll = _lines(left);
  final rl = _lines(right);
  final diffs = diffLines(ll, rl);
  return buildDiffBlocks(diffs);
}

void main() {
  test('整段搬家：标成移动，不再是「删+增」', () {
    const left = 'a\n1\n2\n3\nb';
    const right = '1\n2\n3\na\nb';
    final blocks = _blocks(left, right);
    final moved = detectMovedBlocks(
      blocks,
      leftSource: _lines(left),
      rightSource: _lines(right),
    );
    expect(moved, isNotEmpty, reason: '1/2/3 整段换了位置应被识别为移动');
    expect(moved.first.lines, 3);
    // 每个删除块最多配一个新增块
    expect(moved.map((m) => m.fromBlock).toSet().length, moved.length);
    expect(moved.map((m) => m.toBlock).toSet().length, moved.length);
  });

  test('真改了内容：不配对', () {
    const left = 'x\nfoo\nbar\ny';
    const right = 'x\ny\nfoo\nbaz';
    final moved = detectMovedBlocks(
      _blocks(left, right),
      leftSource: _lines(left),
      rightSource: _lines(right),
    );
    // bar 变 baz，没有整段一致的内容可以配对
    expect(moved, isEmpty);
  });

  test('单行移动不算（minLines 默认 2）', () {
    const left = 'a\nimport x;\nb';
    const right = 'import x;\na\nb';
    final moved = detectMovedBlocks(
      _blocks(left, right),
      leftSource: _lines(left),
      rightSource: _lines(right),
    );
    expect(moved, isEmpty);
  });

  test('minLines=1 时单行也能识别', () {
    const left = 'a\nimport x;\nb';
    const right = 'import x;\na\nb';
    final moved = detectMovedBlocks(
      _blocks(left, right),
      leftSource: _lines(left),
      rightSource: _lines(right),
      minLines: 1,
    );
    expect(moved, isNotEmpty);
  });

  test('ignoreWhitespace 让缩进不同的搬家也算移动', () {
    const left = 'fn() {\n  a();\n  b();\n}';
    const right = 'a();\nb();\nfn() {}';
    final strict = detectMovedBlocks(
      _blocks(left, right),
      leftSource: _lines(left),
      rightSource: _lines(right),
    );
    expect(strict, isEmpty, reason: '缩进不同，严格比对配不上');
    final loose = detectMovedBlocks(
      _blocks(left, right),
      leftSource: _lines(left),
      rightSource: _lines(right),
      ignoreWhitespace: true,
    );
    expect(loose, isNotEmpty);
  });

  test('同一段被复制到两处：按顺序各配一次，不重复消费', () {
    const left = 'p\nq';
    const right = 'p\nq\np\nq';
    final moved = detectMovedBlocks(
      _blocks(left, right),
      leftSource: _lines(left),
      rightSource: _lines(right),
    );
    // 左只有一份，右侧有两份 -> 最多配一次
    expect(moved.length, lessThanOrEqualTo(1));
  });

  test('完全没有差异：空列表', () {
    const same = 'a\nb\nc';
    final moved = detectMovedBlocks(
      _blocks(same, same),
      leftSource: _lines(same),
      rightSource: _lines(same),
    );
    expect(moved, isEmpty);
  });

  test('越界行号不抛异常', () {
    // 手工构造一个行号超出原文的块，确认不会崩（防御性）
    const blocks = <DiffBlock>[
      DiffBlock(leftStart: 0, rightStart: 0, leftLines: [99, 100], rightLines: []),
      DiffBlock(leftStart: 0, rightStart: 0, leftLines: [], rightLines: [99, 100]),
    ];
    final moved = detectMovedBlocks(
      blocks,
      leftSource: const ['a'],
      rightSource: const ['b'],
    );
    // 取不到文本的块直接不参与配对
    expect(moved, isEmpty);
  });
}
