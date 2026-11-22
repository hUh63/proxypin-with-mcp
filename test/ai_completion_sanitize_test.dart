import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/ui/toolbox/editor_ai_complete.dart';

void main() {
  group('行内补全输出清洗', () {
    test('去掉代码围栏', () {
      expect(sanitizeCompletion('```dart\nfoo();\n```'), 'foo();');
      expect(sanitizeCompletion('```\nbar()\n```'), 'bar()');
    });

    test('去掉与光标前重复的部分', () {
      expect(
        sanitizeCompletion('  return result;', currentLinePrefix: '  return '),
        'result;',
      );
    });

    test('重复前缀只在真匹配时才去', () {
      expect(sanitizeCompletion('total = 1;', currentLinePrefix: '  return '),
          'total = 1;');
    });

    test('模型回 nothing 视为没有补全', () {
      expect(sanitizeCompletion('nothing'), isNull);
      expect(sanitizeCompletion('  NOTHING \n'), isNull);
    });

    test('空内容返回 null', () {
      expect(sanitizeCompletion(''), isNull);
      expect(sanitizeCompletion('   \n\n  '), isNull);
    });

    test('首尾空行去掉，中间空行保留', () {
      expect(sanitizeCompletion('\n\na();\n\nb();\n\n'), 'a();\n\nb();');
    });

    test('超过行数上限被截断', () {
      final raw = List.generate(30, (i) => 'l$i').join('\n');
      final out = sanitizeCompletion(raw)!;
      expect(out.split('\n').length, 12);
      expect(out.startsWith('l0'), isTrue);
    });

    test('CRLF 归一成 LF', () {
      expect(sanitizeCompletion('a();\r\nb();'), 'a();\nb();');
    });
  });
}
