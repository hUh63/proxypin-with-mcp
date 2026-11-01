import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/naming_case.dart';

void main() {
  group('splitIdentifierWords', () {
    test('camelCase', () {
      expect(splitIdentifierWords('userName'), ['user', 'Name']);
      expect(splitIdentifierWords('getHTTPResponseCode'), ['get', 'HTTP', 'Response', 'Code']);
    });

    test('PascalCase', () {
      expect(splitIdentifierWords('UserName'), ['User', 'Name']);
      expect(splitIdentifierWords('HTTPServer'), ['HTTP', 'Server']);
    });

    test('snake / kebab / 空格', () {
      expect(splitIdentifierWords('user_name'), ['user', 'name']);
      expect(splitIdentifierWords('user-name-x'), ['user', 'name', 'x']);
      expect(splitIdentifierWords('user name'), ['user', 'name']);
    });

    test('数字并入当前词', () {
      expect(splitIdentifierWords('user2Name'), ['user2', 'Name']);
      expect(splitIdentifierWords('v2'), ['v2']);
    });

    test('杂字符与空串', () {
      expect(splitIdentifierWords(''), isEmpty);
      expect(splitIdentifierWords('___'), isEmpty);
      expect(splitIdentifierWords('a.b.c'), ['a', 'b', 'c']);
    });
  });

  group('convertNamingCase', () {
    test('camel', () {
      expect(convertNamingCase('user_name', NamingCase.camel), 'userName');
      expect(convertNamingCase('User-Name', NamingCase.camel), 'userName');
      expect(convertNamingCase('userName', NamingCase.camel), 'userName');
    });

    test('pascal', () {
      expect(convertNamingCase('user_name', NamingCase.pascal), 'UserName');
      expect(convertNamingCase('HTTP_SERVER', NamingCase.pascal), 'HttpServer');
    });

    test('snake', () {
      expect(convertNamingCase('User Name', NamingCase.snake), 'user_name');
      expect(convertNamingCase('userName', NamingCase.snake), 'user_name');
    });

    test('kebab', () {
      expect(convertNamingCase('UserName', NamingCase.kebab), 'user-name');
    });

    test('constant', () {
      expect(convertNamingCase('maxRetryCount', NamingCase.constant), 'MAX_RETRY_COUNT');
      expect(convertNamingCase('max-retry', NamingCase.constant), 'MAX_RETRY');
    });

    test('没有可识别单词时原样返回', () {
      expect(convertNamingCase('', NamingCase.camel), '');
      expect(convertNamingCase('!!!', NamingCase.snake), '!!!');
    });

    test('来回转换保持稳定', () {
      const src = 'maxRetryCount';
      final snake = convertNamingCase(src, NamingCase.snake);
      expect(snake, 'max_retry_count');
      expect(convertNamingCase(snake, NamingCase.camel), src);
    });
  });

  group('namingCaseOf', () {
    test('已知 id', () {
      expect(namingCaseOf('camel'), NamingCase.camel);
      expect(namingCaseOf('constant'), NamingCase.constant);
    });

    test('未知 id 返回 null', () {
      expect(namingCaseOf('upper'), isNull);
    });
  });
}
