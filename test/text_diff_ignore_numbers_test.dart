import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_diff.dart';
import 'package:proxypin/utils/text_diff_job.dart';

void main() {
  group('忽略数字差异', () {
    test('只差数字的行算相同', () {
      final on = diffLines('id=1 ts=100', 'id=2 ts=250', ignoreNumbers: true);
      expect(on.every((d) => d.type == LineDiffType.equal), isTrue,
          reason: '数字归一后应完全相同');

      final off = diffLines('id=1 ts=100', 'id=2 ts=250');
      expect(off.any((d) => d.type != LineDiffType.equal), isTrue);
    });

    test('数字位置不同也算相同（只要结构一致）', () {
      final d = diffLines('GET /a/1 200', 'GET /a/22 200', ignoreNumbers: true);
      expect(d.every((x) => x.type == LineDiffType.equal), isTrue);
    });

    test('非数字差异不会被吞掉', () {
      final d = diffLines('GET /a/1 200', 'POST /a/1 404', ignoreNumbers: true);
      expect(d.any((x) => x.type != LineDiffType.equal), isTrue);
    });

    test('整篇 + 忽略数字 + 相似度配对三者叠加', () {
      const a = 'time=1 aaa\nkeep\ntime=2 bbb';
      const b = 'time=9 aaa\nkeep\ntime=8 bbb';
      final r = runDiffJob(const DiffJobArgs(
        left: a,
        right: b,
        ignoreNumbers: true,
        pairSimilarity: 500,
      ));
      expect(r.stats.identical, isTrue);
    });

    test('isolate 入口的 map 能带上这个开关', () {
      final r = runDiffJobFromMap({
        'left': 'x=1',
        'right': 'x=2',
        'ignoreNumbers': true,
      });
      expect(r.stats.identical, isTrue);
    });
  });
}
