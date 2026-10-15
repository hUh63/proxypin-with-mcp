/*
 * HTTP 基础类型单测。
 *
 * 原文件是 @Tags(['integration']) 的“假测试”：main() 里 print ContentType / Uri，
 * 再用 dart:io HttpClient 经本机 7890 代理去请求 www.v2ex.com（需要手工起代理，
 * 且没有任何断言）。这里把**确定性部分**（ContentType.parse、Uri.parse）改成真断言，
 * 去掉 integration 标签让 CI 真实执行；
 * 真正需要代理的端到端 MITM 链路由 test/integration/https_mitm_test.dart 覆盖
 * （它自建本地 HTTPS 服务 + 真实 CONNECT，不依赖外部代理，且不打 integration 标签）。
 */

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContentType.parse', () {
    test('解析 mimeType / primaryType / subType，无 charset 时为 null', () {
      final contentType = ContentType.parse('application/json');

      expect(contentType.mimeType, 'application/json');
      expect(contentType.primaryType, 'application');
      expect(contentType.subType, 'json');
      expect(contentType.charset, isNull);
    });

    test('带 charset 参数时正确提取', () {
      final contentType = ContentType.parse('application/json; charset=utf-8');

      expect(contentType.mimeType, 'application/json');
      expect(contentType.charset, 'utf-8');
      expect(contentType.toString(), 'application/json; charset=utf-8');
    });

    test('构造后再 parse 回同一 mime / charset', () {
      const original = ContentType('text', 'html', charset: 'gbk');
      final parsed = ContentType.parse(original.toString());

      expect(parsed.mimeType, original.mimeType);
      expect(parsed.charset, original.charset);
    });
  });

  group('Uri.parse', () {
    test('提取 scheme / host', () {
      final uri = Uri.parse('https://www.v2ex.com');

      expect(uri.scheme, 'https');
      expect(uri.host, 'www.v2ex.com');
      expect(uri.hasPort, isFalse);
    });

    test('https 默认端口与显式端口一致', () {
      expect(Uri.parse('https://www.v2ex.com:443').port, 443);
      expect(Uri.parse('https://www.v2ex.com').port, 443);
    });
  });
}
