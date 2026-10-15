/*
 * URL / query 解析单测。
 *
 * 原文件只有 print，无断言。这里保留原有验证意图：
 *   - Uri.queryParameters 对真实长 URL 的解析（含 URL 编码的 JSON 参数）；
 *   - UriUtils.mapToQuery(map) 的编码与保序拼接；
 *   - uri.replace(query: ...) 往返语义。
 * 纯 Dart，无网络依赖，CI 可跑。
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/util/uri.dart';

const String _xiaohongshuUrl =
    'https://edith.xiaohongshu.com/api/sns/v6/homefeed?client_volume=0.25'
    '&geo=eyJsYXRpdHVkZSI6NDAuMDU5MDkxOTAyNzk4OSwibG9uZ2l0dWRlIjoxMTYuNDEwMjA2OTMzNDYyN30%3D'
    '&known_signal=%7B%22nqe_level%22%3A6%2C%22hp_con%22%3A0%2C%22device_level%22%3A1%2C'
    '%22m_active%22%3A0%2C%22device_model%22%3A%22iPhone%2013%20Pro%22%7D'
    '&last_card_position=4&last_live_id=&last_live_position=-1'
    '&num=20&oid=homefeed_recommend&orientation=portait&personalization=1'
    '&refresh_type=1&unread_begin_note_id=67136eaa0000000026034b5b'
    '&unread_end_note_id=67307eaf000000003c019503&unread_note_count=6'
    '&use_jpeg=1&user_action=0';

void main() {
  group('Uri.queryParameters', () {
    test('拆解小红书 homefeed URL 的路径与关键参数', () {
      final uri = Uri.parse(_xiaohongshuUrl);

      expect(uri.scheme, 'https');
      expect(uri.host, 'edith.xiaohongshu.com');
      expect(uri.path, '/api/sns/v6/homefeed');

      final query = uri.queryParameters;
      expect(query['num'], '20');
      expect(query['oid'], 'homefeed_recommend');
      expect(query['orientation'], 'portait');
      expect(query['unread_note_count'], '6');
      expect(query['use_jpeg'], '1');
      // 空值参数不应被丢掉
      expect(query.containsKey('last_live_id'), isTrue);
      expect(query['last_live_id'], '');
    });

    test('URL 编码的 JSON 参数被还原', () {
      final query = Uri.parse(_xiaohongshuUrl).queryParameters;
      expect(query['known_signal'], contains('"nqe_level":6'));
      expect(query['known_signal'], contains('"device_model":"iPhone 13 Pro"'));
    });
  });

  group('UriUtils.mapToQuery', () {
    test('逐项 URL 编码并用 & 拼接（保序）', () {
      final map = <String, String>{'a': '1', 'b': 'x y', 'c': '中文&='};
      expect(UriUtils.mapToQuery(map), 'a=1&b=x%20y&c=%E4%B8%AD%E6%96%87%26%3D');
    });

    test('null 入参返回空串', () {
      expect(UriUtils.mapToQuery(null), '');
    });

    test('空 map 返回空串', () {
      expect(UriUtils.mapToQuery(<String, String>{}), '');
    });
  });

  group('uri.replace', () {
    test('用 mapToQuery 重建 query 后解析结果与原始一致', () {
      final uri = Uri.parse('https://a.com/x?num=20&oid=homefeed_recommend');
      final rebuilt = uri.replace(query: UriUtils.mapToQuery(uri.queryParameters));

      expect(Uri.parse(rebuilt.toString()).queryParameters, uri.queryParameters);
      expect(rebuilt.path, '/x');
    });

    test('Uri.encodeComponent 结果与 mapToQuery 使用同一套编码', () {
      expect(Uri.encodeComponent('中文&='), UriUtils.mapToQuery({'k': '中文&='}).substring(2));
    });
  });
}
