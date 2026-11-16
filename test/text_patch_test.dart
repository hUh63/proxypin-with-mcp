// unified diff（.patch）生成器的用例。
//
// 之所以单独测：patch 是**机器可读**的，行号错一位，`git apply` 就会整份拒绝，
// 而界面上「看起来是对的」——这类错误只能靠构造出来的文本逐字比对。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_patch.dart';

void main() {
  group('buildUnifiedPatch', () {
    test('完全相同时返回空串', () {
      expect(buildUnifiedPatch('a\nb\n', 'a\nb\n'), '');
    });

    test('单行修改：上下文各 3 行', () {
      const left = '1\n2\n3\n4\n5\n';
      const right = '1\n2\nX\n4\n5\n';
      final p = buildUnifiedPatch(left, right, leftName: 'a/f.txt', rightName: 'b/f.txt');
      expect(p, contains('--- a/f.txt'));
      expect(p, contains('+++ b/f.txt'));
      expect(p, contains('@@ -1,5 +1,5 @@'));
      expect(p, contains('-3'));
      expect(p, contains('+X'));
      expect(p, contains(' 1'));
      // 文本末尾的换行不是空行：不该多出一条「空格开头、内容为空」的行
      expect(p.split('\n').where((e) => e == ' ').isEmpty, isTrue);
      expect(p.trim().endsWith(' 5'), isTrue);
    });

    test('文件中部纯新增：hunk 头必须是「上一行,0」而不是 1', () {
      // 左 10 行，右在第 6 行后插入一行 —— 这是原实现最容易错的地方：
      // 写成 `-1,0` 会把内容插到文件开头。
      const left = 'a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n';
      const right = 'a\nb\nc\nd\ne\nNEW\nf\ng\nh\ni\nj\n';
      final p = buildUnifiedPatch(left, right);
      // 差异在第 6 行（0 起下标 5），块向两侧各扩 3 行 → 覆盖左第 3~9 行共 6 行；
      // 右侧多出插入的那一行，所以是 7 行。
      expect(p, contains('@@ -3,6 +3,7 @@'));
      expect(p, contains('+NEW'));
      expect(p, isNot(contains('@@ -1,')));
    });

    test('文件开头纯新增：左计数 0', () {
      const left = 'a\nb\n';
      const right = 'NEW\na\nb\n';
      final p = buildUnifiedPatch(left, right);
      // 原文件有 2 行，开头插入 1 行 → 左侧仍有 2 行（不是 0 行）。
      expect(p, contains('@@ -1,2 +1,3 @@'));
      expect(p, contains('+NEW'));
    });

    test('纯新增且只有一行：右计数 1 写成 +1（省略 ,1）', () {
      const left = '';
      const right = 'only\n';
      final p = buildUnifiedPatch(left, right);
      expect(p, contains('@@ -0,0 +1 @@'));
    });

    test('整块删除', () {
      const left = 'a\nb\nc\nd\n';
      const right = 'a\nd\n';
      final p = buildUnifiedPatch(left, right);
      expect(p, contains('-b'));
      expect(p, contains('-c'));
      expect(p, contains(' a'));
      expect(p, contains(' d'));
    });

    test('两处相差很远 → 两个 hunk', () {
      final left = List.generate(40, (i) => 'line$i').join('\n') + '\n';
      final right = left.replaceFirst('line1\n', 'line1x\n').replaceFirst('line38\n', 'line38x\n');
      final p = buildUnifiedPatch(left, right);
      expect('@@'.allMatches(p).length, 4); // 每个 hunk 头里有 2 个 @@
      expect(patchSummary(left, right).hunks, 2);
    });

    test('两处挨得近（间隔 <= 2*context）→ 合并成一个 hunk', () {
      final left = List.generate(20, (i) => 'line$i').join('\n') + '\n';
      final right = left.replaceFirst('line3\n', 'line3x\n').replaceFirst('line6\n', 'line6x\n');
      expect(patchSummary(left, right).hunks, 1);
    });

    test('context: 0 时只含变化行', () {
      const left = 'a\nb\nc\n';
      const right = 'a\nX\nc\n';
      final p = buildUnifiedPatch(left, right, context: 0);
      // 具体的上下文行是「空格 + 内容」，header 里的 '--- a.txt' 不算
      expect(p, isNot(contains('\n a')));
      expect(p, contains('-b'));
      expect(p, contains('+X'));
    });

    test('中文与 CRLF 内容都能原样出现在补丁里', () {
      const left = '第一行\r\n第二行\r\n第三行\r\n';
      const right = '第一行\r\n第二行改\r\n第三行\r\n';
      final p = buildUnifiedPatch(left, right);
      expect(p, contains('-第二行'));
      expect(p, contains('+第二行改'));
      // CRLF 在输出里已经被归一成 \n（patch 以行切分，不保留 \r）
      expect(p, isNot(contains('\r')));
    });

    test('忽略大小写不影响补丁内容（补丁必须是真实差异）', () {
      const left = 'Hello\nWorld\n';
      const right = 'HELLO\nWorld\n';
      // buildUnifiedPatch 本身支持 ignoreCase，但界面上的导出刻意不传 ——
      // 这里验证「不传」时补丁包含这处差异。
      final p = buildUnifiedPatch(left, right);
      expect(p, contains('-Hello'));
      expect(p, contains('+HELLO'));
    });

    test('patchSummary 统计增删行数', () {
      const left = 'a\nb\nc\n';
      const right = 'a\nX\nY\nc\n';
      final s = patchSummary(left, right);
      expect(s.hunks, 1);
      expect(s.added, 2);
      expect(s.removed, 1);
    });

    test('空文本两侧都空 → 空串，不抛异常', () {
      expect(buildUnifiedPatch('', ''), '');
      expect(patchSummary('', '').hunks, 0);
    });

    test('左侧空、右侧有内容', () {
      final p = buildUnifiedPatch('', 'a\nb\n');
      expect(p, contains('--- a.txt'));
      expect(p, contains('+a'));
      expect(p, contains('+b'));
    });

    test('右侧空、左侧有内容', () {
      final p = buildUnifiedPatch('a\nb\n', '');
      expect(p, contains('-a'));
      expect(p, contains('-b'));
    });
  });
}
