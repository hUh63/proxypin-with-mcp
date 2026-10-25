import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/suggestion_stats.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(SuggestionStats.resetForTest);
  tearDown(SuggestionStats.resetForTest);

  test('没学过的词权重为 0', () {
    SuggestionStats.seedForTest();
    expect(SuggestionStats.weight('Dart', 'print'), 0);
    expect(SuggestionStats.learnedCount(), 0);
  });

  test('接受过的词权重 > 0，且次数越多权重越高', () {
    SuggestionStats.seedForTest();
    SuggestionStats.recordAccepted('Dart', 'print');
    final once = SuggestionStats.weight('Dart', 'print');
    SuggestionStats.recordAccepted('Dart', 'print');
    SuggestionStats.recordAccepted('Dart', 'print');
    final thrice = SuggestionStats.weight('Dart', 'print');
    expect(once, greaterThan(0));
    expect(thrice, greaterThan(once));
  });

  test('语言大小写不影响统计（归一化）', () {
    SuggestionStats.seedForTest();
    SuggestionStats.recordAccepted('CSharp', 'Console');
    expect(SuggestionStats.weight('csharp', 'Console'), greaterThan(0));
    expect(SuggestionStats.weight('CSHARP', 'Console'), greaterThan(0));
  });

  test('rank 把学过的词提前，未学过的保持原顺序', () {
    SuggestionStats.seedForTest(accepted: {
      'dart': {'return': 9},
    });
    final input = ['if', 'return', 'for', 'print'];
    final ranked = SuggestionStats.rank('Dart', input);
    expect(ranked.first, 'return');
    // 其余三个的相对顺序不变
    expect(ranked.sublist(1), ['if', 'for', 'print']);
  });

  test('曝光很多但从没被接受的词不会排到前面', () {
    SuggestionStats.seedForTest(
      accepted: {
        'dart': {'print': 2},
      },
      shown: {
        'dart': {'console': 200, 'print': 3},
      },
    );
    final ranked = SuggestionStats.rank('Dart', ['console', 'print']);
    expect(ranked.first, 'print');
  });

  test('完全没数据时 rank 原样返回同一个顺序', () {
    SuggestionStats.seedForTest();
    final input = ['b', 'a', 'c'];
    expect(SuggestionStats.rank('Dart', input), input);
  });

  test('不同语言互不干扰', () {
    SuggestionStats.seedForTest(accepted: {
      'python': {'print': 5},
    });
    expect(SuggestionStats.rank('csharp', ['Console', 'print']), ['Console', 'print']);
    expect(SuggestionStats.rank('python', ['Console', 'print']).first, 'print');
  });

  test('forget 之后权重回到 0', () {
    SuggestionStats.seedForTest();
    SuggestionStats.recordAccepted('dart', 'print');
    expect(SuggestionStats.weight('dart', 'print'), greaterThan(0));
    SuggestionStats.forget('dart', 'print');
    expect(SuggestionStats.weight('dart', 'print'), 0);
  });

  test('超长词与空白词被忽略', () {
    SuggestionStats.seedForTest();
    SuggestionStats.recordAccepted('dart', '   ');
    SuggestionStats.recordAccepted('dart', 'x' * 80);
    expect(SuggestionStats.learnedCount('dart'), 0);
  });

  test('每语言最多记 200 个词，超出淘汰次数最低的', () {
    SuggestionStats.seedForTest();
    for (var i = 0; i < 205; i++) {
      SuggestionStats.recordAccepted('dart', 'w$i');
    }
    // 再给 w0 加两次，确保它不会被淘汰
    SuggestionStats.recordAccepted('dart', 'w0');
    SuggestionStats.recordAccepted('dart', 'w0');
    expect(SuggestionStats.learnedCount('dart'), lessThanOrEqualTo(200));
    expect(SuggestionStats.weight('dart', 'w0'), greaterThan(0));
  });
}
