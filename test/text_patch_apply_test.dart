// applyUnifiedPatch 的用例：把「导出的补丁」贴回来，能不能真的还原。
//
// 这组用例的重点是 round-trip：buildUnifiedPatch 生成 → applyUnifiedPatch 应用，
// 结果必须逐字符等于目标文本。补丁是机器可读的，差一个空格就整份打不上。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_patch.dart';

const _left = 'one\ntwo\nthree\nfour\nfive\nsix\nseven\n';
const _right = 'one\ntwo\nTHREE\nfour\nfive\nsix\nseven\n';

void main() {
  group('applyUnifiedPatch', () {
    test('正向：把左侧文本改成右侧', () {
      final patch = buildUnifiedPatch(_left, _right);
      final r = applyUnifiedPatch(_left, patch);
      expect(r.ok, isTrue);
      expect(r.text, _right);
      expect(r.applied, 1);
      expect(r.failed, isEmpty);
    });

    test('反向：把右侧文本撤销回左侧', () {
      final patch = buildUnifiedPatch(_left, _right);
      final r = applyUnifiedPatch(_right, patch, reverse: true);
      expect(r.ok, isTrue);
      expect(r.text, _left);
    });

    test('多处差异一次应用完', () {
      const a = 'a\nb\nc\nd\ne\nf\ng\nh\n';
      const b = 'a\nB\nc\nd\ne\nf\nG\nh\n';
      final patch = buildUnifiedPatch(a, b, context: 1);
      final r = applyUnifiedPatch(a, patch);
      expect(r.ok, isTrue);
      expect(r.text, b);
      expect(r.applied, 2);
    });

    test('纯新增（从空文件）也能应用', () {
      final patch = buildUnifiedPatch('', 'x\ny\n');
      final r = applyUnifiedPatch('', patch);
      expect(r.ok, isTrue);
      expect(r.text, 'x\ny\n');
    });

    test('目标文件中间多插了几行 → 靠平移仍然打得进去', () {
      final patch = buildUnifiedPatch(_left, _right);
      // 在开头插两行，行号整体平移
      final shifted = 'added0\nadded1\n$_left';
      final r = applyUnifiedPatch(shifted, patch);
      expect(r.ok, isTrue);
      expect(r.text, 'added0\nadded1\n$_right');
    });

    test('上下文被改坏 → 该块失败，但仍报告其它块的结果', () {
      const a = 'a\nb\nc\nd\ne\nf\ng\nh\n';
      const b = 'a\nB\nc\nd\ne\nf\nG\nh\n';
      final patch = buildUnifiedPatch(a, b, context: 1);
      // 把第一块依赖的上下文 'b' 改掉
      final broken = 'a\nZZZ\nc\nd\ne\nf\ng\nh\n';
      final r = applyUnifiedPatch(broken, patch, fuzz: 0);
      expect(r.ok, isFalse);
      expect(r.failed, isNotEmpty);
      expect(r.applied, lessThan(2));
    });

    test('不是补丁 → 返回明确错误，原文本不变', () {
      final r = applyUnifiedPatch('abc\n', '随便写点什么\n没有 @@ 块\n');
      expect(r.ok, isFalse);
      expect(r.error, isNotNull);
      expect(r.text, 'abc\n');
    });

    test('CRLF 目标：应用后仍按原样输出，不混进 \\r', () {
      const crlfLeft = 'one\r\ntwo\r\nthree\r\n';
      const crlfRight = 'one\r\ntwo\r\nTHREE\r\n';
      final patch = buildUnifiedPatch(crlfLeft, crlfRight);
      final r = applyUnifiedPatch(crlfLeft, patch);
      expect(r.ok, isTrue);
      // patch 里是按行比较，输出统一成 \n
      expect(r.text, 'one\ntwo\nTHREE\n');
    });

    test('目标末尾没有换行时，结果也不多给一个换行', () {
      final patch = buildUnifiedPatch('a\nb', 'a\nX');
      final r = applyUnifiedPatch('a\nb', patch);
      expect(r.ok, isTrue);
      expect(r.text, 'a\nX');
      expect(r.text.endsWith('\n'), isFalse);
    });

    test('中文内容', () {
      const a = '第一行\n第二行\n第三行\n';
      const b = '第一行\n第二行改过\n第三行\n';
      final patch = buildUnifiedPatch(a, b);
      final r = applyUnifiedPatch(a, patch);
      expect(r.text, b);
    });

    test('空文本 + 空补丁不抛异常', () {
      final r = applyUnifiedPatch('', '');
      expect(r.ok, isFalse);
      expect(r.error, isNotNull);
    });
  });
}
