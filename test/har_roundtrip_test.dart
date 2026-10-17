import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/mcp/capture/sensitive_data.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/utils/har.dart';

/// HAR 导入导出链路回归。
///
/// 背景：Har.readFile 原来只认「每行一个 entry」的历史文件格式，
/// 而 Har.writeFile / 收藏导出 / Chrome / Charles 产出的都是单个 JSON 对象，
/// 于是「导出 HAR → 再导入」100% 失败（jsonDecode 得到 {log:...}，
/// 取 har['request'] 为 null 后抛 NoSuchMethodError）。
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('har_roundtrip_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<File> write(String name, String content) async {
    final file = File('${tmp.path}/$name');
    await file.writeAsString(content);
    return file;
  }

  Map<String, dynamic> standardHar({String body = '{"name":"张三"}'}) => {
        'log': {
          'version': '1.2',
          'creator': {'name': 'test', 'version': '1.0'},
          'entries': [
            {
              'startedDateTime': '2024-01-01T00:00:00.000Z',
              'time': 12,
              'request': {
                'method': 'POST',
                'url': 'https://example.com/api?x=1',
                'httpVersion': 'HTTP/1.1',
                'headers': [
                  {'name': 'Content-Type', 'value': 'application/json'}
                ],
                'postData': {'mimeType': 'application/json', 'text': body},
              },
              'response': {
                'status': 200,
                'statusText': 'OK',
                'httpVersion': 'HTTP/1.1',
                'headers': [
                  {'name': 'Content-Type', 'value': 'application/json'}
                ],
                'content': {'size': 11, 'mimeType': 'application/json', 'text': '{"ok":true}'},
              },
            }
          ],
        },
      };

  test('读取标准 HAR（单 JSON 对象）—— 收藏导出后可直接导入', () async {
    final file = await write('standard.har', jsonEncode(standardHar()));
    final list = await Har.readFile(file);

    expect(list, hasLength(1));
    expect(list.single.method, HttpMethod.post);
    expect(list.single.bodyAsString, '{"name":"张三"}');
    expect(list.single.response?.bodyAsString, '{"ok":true}');
  });

  test('writeFile 产出可被 readFile 读回（自导自入往返）', () async {
    final request = HttpRequest(HttpMethod.post, 'https://example.com/api')
      ..headers.add('Content-Type', 'application/json')
      ..body = utf8.encode('{"name":"张三"}');
    final file = File('${tmp.path}/roundtrip.har');
    await Har.writeFile([request], file);

    final list = await Har.readFile(file);
    expect(list, hasLength(1));
    expect(list.single.bodyAsString, '{"name":"张三"}');
  });

  test('历史文件的逐行 entry 格式仍可读取', () async {
    final a = Har.toHar(HttpRequest(HttpMethod.get, 'https://example.com/a'));
    final b = Har.toHar(HttpRequest(HttpMethod.get, 'https://example.com/b'));
    final file = await write('history.har', '${jsonEncode(a)},\n${jsonEncode(b)},\n');

    final list = await Har.readFile(file);
    expect(list.map((e) => e.requestUrl), containsAll(['https://example.com/a', 'https://example.com/b']));
  });

  test('历史文件被截断时跳过坏行，其余记录仍可访问', () async {
    final a = Har.toHar(HttpRequest(HttpMethod.get, 'https://example.com/a'));
    final b = Har.toHar(HttpRequest(HttpMethod.get, 'https://example.com/b'));
    // 中间夹一条写了一半的 entry（模拟进程被强杀）
    final file = await write(
        'truncated.har', '${jsonEncode(a)},\n{"request":{"method":\n${jsonEncode(b)},\n');

    final list = await Har.readFile(file);
    expect(list, hasLength(2));
  });

  test('postData.encoding == base64 时按二进制还原，而不是把 base64 文本当正文', () async {
    final raw = <int>[0x00, 0x01, 0xFE, 0xFF];
    final har = standardHar();
    final entry = (har['log'] as Map)['entries'][0] as Map;
    (entry['request'] as Map)['postData'] = {
      'mimeType': 'application/octet-stream',
      'text': base64Encode(raw),
      'encoding': 'base64',
    };

    final file = await write('base64.har', jsonEncode(har));
    final list = await Har.readFile(file);
    expect(list.single.body, equals(raw));
  });

  test('第三方 HAR 缺少 headers 时不抛类型错误', () async {
    final har = standardHar();
    final entry = (har['log'] as Map)['entries'][0] as Map;
    (entry['request'] as Map).remove('headers');
    (entry['response'] as Map).remove('headers');

    final file = await write('no_headers.har', jsonEncode(har));
    final list = await Har.readFile(file);
    expect(list, hasLength(1));
  });

  test('缺少 request 给出明确 FormatException，而不是 NoSuchMethodError', () async {
    final file = await write('bad.har', jsonEncode({
      'log': {
        'version': '1.2',
        'entries': [
          {'startedDateTime': '2024-01-01T00:00:00.000Z'}
        ]
      }
    }));
    // readFile 会跳过坏 entry，因此返回空列表而不是抛异常
    expect(await Har.readFile(file), isEmpty);
    expect(() => Har.toRequest({'response': {}}), throwsFormatException);
  });

  group('SensitiveData', () {
    test('常见凭据头（含自定义命名）都会被打码', () {
      expect(SensitiveData.isRedactedHeader('Authorization'), isTrue);
      expect(SensitiveData.isRedactedHeader('Cookie'), isTrue);
      expect(SensitiveData.isRedactedHeader('X-Api-Key'), isTrue);
      expect(SensitiveData.isRedactedHeader('X-Gitlab-Token'), isTrue);
      expect(SensitiveData.isRedactedHeader('X-Amz-Security-Token'), isTrue);
      expect(SensitiveData.isRedactedHeader('X-Session-Id'), isTrue);
    });

    test('普通头不被打码', () {
      expect(SensitiveData.isRedactedHeader('Content-Type'), isFalse);
      expect(SensitiveData.isRedactedHeader('Accept'), isFalse);
      expect(SensitiveData.isRedactedHeader('User-Agent'), isFalse);
    });

    test('redactValue 只替换敏感头', () {
      expect(SensitiveData.redactValue('authorization', 'Bearer x'), SensitiveData.placeholder);
      expect(SensitiveData.redactValue('accept', 'application/json'), 'application/json');
    });
  });
}
