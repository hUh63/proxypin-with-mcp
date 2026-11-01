import 'dart:convert';

import 'package:charset/charset.dart' as charset;
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_file_reader.dart';

void main() {
  group('decodeTextBytesLenient', () {
    test('纯 ASCII / UTF-8 中文', () {
      expect(decodeTextBytesLenient(utf8.encode('hello')), 'hello');
      expect(decodeTextBytesLenient(utf8.encode('中文内容')), '中文内容');
    });

    test('UTF-8 BOM', () {
      final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode('带 BOM')];
      expect(decodeTextBytesLenient(bytes), '带 BOM');
    });

    test('UTF-16LE BOM', () {
      final text = '你好';
      final bytes = <int>[0xFF, 0xFE];
      for (final unit in text.codeUnits) {
        bytes.add(unit & 0xFF);
        bytes.add((unit >> 8) & 0xFF);
      }
      expect(decodeTextBytesLenient(bytes), text);
    });

    test('GBK 中文（严格 UTF-8 解不开，应退到 GBK）', () {
      final gbk = charset.Charset.getByName('gbk');
      expect(gbk, isNotNull);
      final bytes = gbk!.encode('中文内容');
      expect(decodeTextBytesLenient(bytes), '中文内容');
    });

    test('空字节返回空串', () {
      expect(decodeTextBytesLenient(const <int>[]), '');
    });

    test('任意非法字节不抛异常', () {
      // 0xFF 在 UTF-8 / GBK 里都不是合法起始字节
      expect(() => decodeTextBytesLenient(const [0xFF, 0xFF, 0xFF]), returnsNormally);
    });
  });
}
