// 「忽略匹配某正则的行」：日志/抓包对比里最常用（时间戳、请求 id 每行都不同）。
// 一旦这段逻辑把「真差异」也一并忽略掉，用户会以为文件完全一样 —— 所以每条都锁用例。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_diff.dart';

int changesOf(String a, String b, {RegExp? pattern}) {
  final diffs = diffLines(a, b, ignoreLinePattern: pattern);
  final stats = diffStats(buildDiffBlocks(diffs));
  return stats.added + stats.deleted + stats.modified;
}

void main() {
  group('ignoreLinePattern', () {
    test('两侧都有的时间戳行不算差异', () {
      const a = 'id=1 time=10:00\nbody=A\n';
      const b = 'id=1 time=10:05\nbody=A\n';
      final re = RegExp(r'time=');
      expect(changesOf(a, b), 1);
      expect(changesOf(a, b, pattern: re), 0);
    });

    test('只在一侧出现的被忽略行也不算差异', () {
      const a = 'x\ntime=1\ny\n';
      const b = 'x\ny\n';
      final stats = diffStats(buildDiffBlocks(
          diffLines(a, b, ignoreLinePattern: RegExp(r'^time='))));
      expect(stats.added + stats.deleted + stats.modified, 0);
      expect(stats.identical, isTrue);
    });

    test('真差异仍然能识别', () {
      const a = 'foo\nbar\ntime=1';
      const b = 'foo\nbaz\ntime=2';
      expect(changesOf(a, b, pattern: RegExp(r'^time=')), 1);
    });

    test('模式不匹配任何行时与不传等价', () {
      const a = 'a\nb\n';
      const b = 'a\nc\n';
      expect(changesOf(a, b, pattern: RegExp(r'^zzz')),
          changesOf(a, b));
    });

    test('全篇都被忽略时判定为完全一致', () {
      const a = 'ts=1\nts=2\n';
      const b = 'ts=9\nts=8\n';
      expect(changesOf(a, b, pattern: RegExp(r'^ts=')), 0);
    });

    test('行号仍然保留（只是内容被忽略）', () {
      const a = 'x\nts=1\ny\n';
      const b = 'x\ny\n';
      final rows = alignedDiffRows(a, b, ignoreLinePattern: RegExp(r'^ts='));
      expect(rows.every((r) => r.type == DiffRowType.equal), isTrue);
    });
  });
}
