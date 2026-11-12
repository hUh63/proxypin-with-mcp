import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/snippet_placeholders.dart';

void main() {
  const vars = SnippetVariables(
    fileName: 'main.dart',
    filePath: '/home/me/proj/lib/main.dart',
    selection: 'picked',
  );
  final now = DateTime(2026, 3, 7, 9, 5, 2);

  String expand(String s) => expandSnippetVariables(s, vars, now: now);

  group('文件相关变量', () {
    test(r'$TM_FILENAME', () {
      expect(expand(r'$TM_FILENAME'), 'main.dart');
    });
    test(r'${TM_FILENAME} 花括号写法', () {
      expect(expand(r'${TM_FILENAME}'), 'main.dart');
    });
    test(r'$TM_FILENAME_BASE 去掉扩展名', () {
      expect(expand(r'$TM_FILENAME_BASE'), 'main');
    });
    test(r'$TM_DIRECTORY', () {
      expect(expand(r'$TM_DIRECTORY'), '/home/me/proj/lib');
    });
    test(r'$TM_FILEPATH', () {
      expect(expand(r'$TM_FILEPATH'), '/home/me/proj/lib/main.dart');
    });
    test('没有文件名时展开成空串', () {
      expect(expandSnippetVariables(r'$TM_FILENAME', const SnippetVariables()), '');
    });
  });

  group('时间变量', () {
    test(r'$CURRENT_YEAR', () {
      expect(expand(r'$CURRENT_YEAR'), '2026');
    });
    test(r'$CURRENT_YEAR_SHORT 两位', () {
      expect(expand(r'$CURRENT_YEAR_SHORT'), '26');
    });
    test('月日时分秒补零', () {
      expect(expand(r'$CURRENT_MONTH'), '03');
      expect(expand(r'$CURRENT_DATE'), '07');
      expect(expand(r'$CURRENT_HOUR'), '09');
      expect(expand(r'$CURRENT_MINUTE'), '05');
      expect(expand(r'$CURRENT_SECOND'), '02');
    });
    test(r'$CURRENT_DATETIME', () {
      expect(expand(r'$CURRENT_DATETIME'), '2026-03-07 09:05:02');
    });
  });

  group('其它变量', () {
    test(r'$SELECTION', () {
      expect(expand(r'$SELECTION'), 'picked');
    });
    test(r'$UUID 形状正确', () {
      final v = expand(r'$UUID');
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
          .hasMatch(v), isTrue);
    });
    test(r'$RANDOM 是 6 位数字', () {
      expect(RegExp(r'^\d{6}$').hasMatch(expand(r'$RANDOM')), isTrue);
    });
    test(r'$RANDOM_HEX 是 6 位十六进制', () {
      expect(RegExp(r'^[0-9a-f]{6}$').hasMatch(expand(r'$RANDOM_HEX')), isTrue);
    });
  });

  group('不该被误伤', () {
    test('占位符 $1 不受影响', () {
      expect(expand(r'fn();$1'), r'fn();$1');
    });
    test('占位符 \${1:默认值} 不受影响', () {
      expect(expand('x = \${1:默认值};'), 'x = \${1:默认值};');
    });
    test(r'$0 不受影响', () {
      expect(expand(r'end$0'), r'end$0');
    });
    test('未知变量原样保留', () {
      expect(expand(r'echo $foo'), r'echo $foo');
      expect(expand('\${HOME}/bin'), '\${HOME}/bin');
    });
    test('没有 $ 时原样返回', () {
      expect(expand('plain text'), 'plain text');
    });
  });

  group('组合场景', () {
    test('变量与占位符混排', () {
      // 展开后仍保留占位符，交给下一步 parseSnippetPlaceholders。
      expect(expand(r'// $TM_FILENAME$1'), r'// main.dart$1');
    });
    test('多个变量', () {
      expect(expand(r'$CURRENT_YEAR-$CURRENT_MONTH-a $TM_FILENAME_BASE'),
          r'2026-03-a main');
    });
    test('展开后仍能被占位符解析器处理', () {
      final expanded = expand('// \${1:todo} \$TM_FILENAME');
      final parsed = parseSnippetPlaceholders(expanded);
      expect(parsed.text, '// todo main.dart');
      expect(parsed.stops.length, 1);
    });
  });
}
