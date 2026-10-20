/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/// 覆盖 HAR 导入（Har.toRequest）的宽容解析。
///
/// 重点回归：第三方 HAR 里 httpVersion 常缺失、status 常是字符串、startedDateTime
/// 可能是非法时间；裸强转会抛 TypeError，整条 entry 被丢弃（用户看到「导入失败」
/// 或导入后少了记录）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/har.dart';

Map<String, dynamic> _entry({
  Map<String, dynamic>? request,
  Map<String, dynamic>? response,
  dynamic startedDateTime,
}) =>
    <String, dynamic>{
      'startedDateTime': startedDateTime ?? '2026-01-02T03:04:05.000Z',
      'time': 12,
      'request': request ??
          <String, dynamic>{
            'method': 'GET',
            'url': 'https://a.com/x',
            'httpVersion': 'HTTP/1.1',
            'headers': <Map<String, dynamic>>[],
          },
      if (response != null) 'response': response,
    };

void main() {
  group('Har.toRequest', () {
    test('缺 httpVersion 时回落到 HTTP/1.1', () {
      final req = Har.toRequest(_entry(request: {
        'method': 'GET',
        'url': 'https://a.com/x',
        'headers': <Map<String, dynamic>>[],
      }));
      expect(req.protocolVersion, 'HTTP/1.1');
      expect(req.requestUrl, 'https://a.com/x');
    });

    test('缺 url 时抛 FormatException（可读错误而不是 TypeError）', () {
      expect(
        () => Har.toRequest(_entry(request: {'method': 'GET'})),
        throwsA(isA<FormatException>()),
      );
    });

    test('status 是数字字符串 / statusText 是数字都能解析', () {
      final req = Har.toRequest(_entry(response: {
        'status': '404',
        'statusText': 404,
        'httpVersion': 'HTTP/1.1',
        'headers': <Map<String, dynamic>>[],
        'content': {'text': 'nf'},
      }));
      expect(req.response?.status.code, 404);
    });

    test('缺 httpVersion 的响应同样回落，不丢记录', () {
      final req = Har.toRequest(_entry(response: {
        'status': 200,
        'headers': <Map<String, dynamic>>[],
      }));
      expect(req.response?.status.code, 200);
      expect(req.response?.protocolVersion, 'HTTP/1.1');
    });

    test('startedDateTime 非法时不抛异常', () {
      final req = Har.toRequest(_entry(startedDateTime: 'not-a-date'));
      expect(req.requestTime.year, greaterThan(2000));
    });

    test('postData 声明 base64 时按字节解码', () {
      final payload = [0x00, 0x01, 0xFE, 0xFF];
      final req = Har.toRequest(_entry(request: {
        'method': 'POST',
        'url': 'https://a.com/x',
        'httpVersion': 'HTTP/1.1',
        'headers': <Map<String, dynamic>>[],
        'postData': {'text': base64Encode(payload), 'encoding': 'base64'},
      }));
      expect(req.body, payload);
    });

    test('中文 body 按 UTF-8 还原（不是 UTF-16 码元）', () {
      final req = Har.toRequest(_entry(request: {
        'method': 'POST',
        'url': 'https://a.com/x',
        'httpVersion': 'HTTP/1.1',
        'headers': <Map<String, dynamic>>[],
        'postData': {'text': '中文'},
      }));
      expect(req.body, utf8.encode('中文'));
    });

    test('_app 不是 Map 时忽略，不抛 TypeError', () {
      final e = _entry()..['_app'] = 'oops';
      expect(Har.toRequest(e).processInfo, isNull);
    });

    test('readEntries 逐条容错：坏 entry 被跳过，好的保留', () {
      final list = Har.readEntries(<dynamic>[
        _entry(),
        {'request': null},
        'not-a-map',
        _entry(),
      ]);
      expect(list.length, 2);
    });
  });
}
