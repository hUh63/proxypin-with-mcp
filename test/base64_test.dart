/*
 * Base64 / 十六进制转换单测。
 *
 * 原文件只有在 main() 里 print 的“假测试”，零断言、对回归无任何保护；
 * 这里保留原有验证意图（base64 解码、hex 字符串转 Base64），改为真断言。
 * 纯 Dart 标准库，无网络 / 原生依赖，CI 可跑。
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// 十六进制字符串（空格分隔）转 Base64 —— 原用例里的辅助函数。
String hexToBase64(String hex) {
  var arr = hex.split(' ');
  List<int> bytes = [];
  for (int i = 0; i < arr.length; i++) {
    bytes.add(int.parse(arr[i], radix: 16));
  }
  return base64Encode(Uint8List.fromList(bytes));
}

void main() {
  group('base64Decode', () {
    test('解码得到预期字节序列', () {
      expect(
        base64Decode('CiRjNjJlOTc0ZC1j'),
        [10, 36, 99, 54, 50, 101, 57, 55, 52, 100, 45, 99],
      );
    });

    test('解码后 utf8 还原出带换行的原文', () {
      expect(utf8.decode(base64Decode('CiRjNjJlOTc0ZC1j')), '\n\$c62e974d-c');
    });

    test('base64 往返稳定', () {
      const encoded = 'CiRjNjJlOTc0ZC1j';
      expect(base64Encode(base64Decode(encoded)), encoded);
    });
  });

  group('十六进制字符串转 Base64', () {
    test('gzip 魔数开头的一串 hex 可正确转换', () {
      const hex = '1F 8B 08 00 00 00 00 00 00 FF DD 58 CF';
      // 0x1F8B 为 gzip 魔数
      expect(hexToBase64(hex), 'H4sIAAAAAAAA/91Yzw==');
    });

    test('转换结果可解码回原始字节', () {
      const hex = '1F 8B 08 00 00 00 00 00 00 FF DD 58 CF';
      final bytes = base64Decode(hexToBase64(hex));
      expect(bytes.length, 13);
      expect(bytes[0], 0x1F);
      expect(bytes[1], 0x8B);
      expect(bytes[12], 0xCF);
    });
  });
}
