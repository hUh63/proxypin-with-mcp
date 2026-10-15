/*
 * 工具层 / 纯函数补测（零覆盖模块，低风险、可离线跑）。
 *
 * 覆盖：WafBypass（指纹识别 + 载荷变异）、RequestFuzzer（组合生成 + 变体构造 + 取值解析）、
 *       RequestComparator（请求/响应差异对比）、TrafficStats（流量聚合统计）、
 *       RegexpUtil（编译 / 捕获组 / 替换表达式展开）。
 *
 * 全部为纯计算，无 socket / 无原生依赖；不打 integration 标签，CI 会真实执行。
 */
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/request_comparator.dart';
import 'package:proxypin/network/util/request_fuzzer.dart';
import 'package:proxypin/network/util/waf_bypass.dart';
import 'package:proxypin/utils/regexp_util.dart';
import 'package:proxypin/utils/traffic_stats.dart';

/// 构造一条「带 host 信息」的请求（hostAndPort 决定 host/域名统计口径）。
HttpRequest _req(String url, HttpMethod method, {String? body}) {
  final request = HttpRequest(method, url, protocolVersion: 'HTTP/1.1')..hostAndPort = HostAndPort.of(url);
  if (body != null) request.body = utf8.encode(body);
  return request;
}

HttpResponse _resp(int code, String reason, {String? body, String? contentType}) {
  final response = HttpResponse(HttpStatus.newStatus(code, reason))
    ..body = body == null ? null : utf8.encode(body);
  if (contentType != null) response.headers.contentType = contentType;
  return response;
}

void main() {
  group('RegexpUtil', () {
    test('compileRegExp：空模式与非法模式返回 null，修饰符生效', () {
      expect(compileRegExp('', const RegexpFlags()), isNull);
      expect(compileRegExp('(', const RegexpFlags()), isNull, reason: '语法错误必须返回 null 而不是抛异常');

      final ci = compileRegExp('abc', const RegexpFlags(ignoreCase: true));
      expect(ci, isNotNull);
      expect(ci!.hasMatch('ABC'), isTrue);

      final multiline = compileRegExp(r'^b', const RegexpFlags(multiLine: true))!;
      expect(multiline.hasMatch('a\nb'), isTrue);
      expect(compileRegExp(r'^b', const RegexpFlags())!.hasMatch('a\nb'), isFalse);

      final dotAll = compileRegExp(r'a.b', const RegexpFlags(dotAll: true))!;
      expect(dotAll.hasMatch('a\nb'), isTrue);
    });

    test('RegexpFlags.label / 相等性 / copyWith', () {
      expect(const RegexpFlags(ignoreCase: true, multiLine: true, dotAll: true).label, 'ims');
      expect(const RegexpFlags(unicode: true).label, 'u');
      expect(const RegexpFlags().label, '');

      const base = RegexpFlags(ignoreCase: true, multiLine: true, dotAll: true, unicode: false);
      expect(base, const RegexpFlags(ignoreCase: true, multiLine: true, dotAll: true, unicode: false));
      expect(base.copyWith(unicode: true) == base, isFalse);
      expect(base.copyWith(ignoreCase: false).label, 'ms');
      expect(base.hashCode, const RegexpFlags(ignoreCase: true, multiLine: true, dotAll: true, unicode: false).hashCode);
    });

    test('captureGroupsOf 枚举捕获组（不含 0 号整体匹配）', () {
      final m = RegExp(r'(\w+)@(\w+)\.(\w+)').firstMatch('user@mail.com')!;
      final groups = captureGroupsOf(m);
      expect(groups.map((g) => g.index), [1, 2, 3]);
      expect(groups.map((g) => g.value), ['user', 'mail', 'com']);

      final noGroup = RegExp(r'\d+').firstMatch('123')!;
      expect(captureGroupsOf(noGroup), isEmpty);
    });

    test('expandReplacement：组引用 / ${n} / 转义 / 大小写', () {
      final m = RegExp(r'(\w+)@(\w+)').firstMatch('USER@host')!;
      expect(expandReplacement(r'$2/$1', m), 'host/USER');
      expect(expandReplacement(r'${2}-${1}', m), 'host-USER');
      expect(expandReplacement(r'\$1', m), r'$1', reason: r'\$' + ' 表示字面量美元');
      expect(expandReplacement(r'\n', m), '\n');
      expect(expandReplacement(r'[$0]', m), '[USER@host]');
      expect(expandReplacement(r'\U$1', m), 'USER');
      expect(expandReplacement(r'\u$1', m), 'User');
      expect(expandReplacement(r'\l$1', m), 'uSER');

      // 越界组引用返回空串，不抛异常
      expect(expandReplacement(r'$9', m), '');
      final digits = RegExp(r'\d+').firstMatch('42')!;
      expect(captureGroupsOf(digits), isEmpty);
      expect(expandReplacement(r'$1', digits), '');
    });

    test('replaceWithExpansion：替换次数与展开结果', () {
      final result = replaceWithExpansion('a1 b2 c3', RegExp(r'(\d)'), r'[$1]');
      expect(result.text, 'a[1] b[2] c[3]');
      expect(result.count, 3);

      final none = replaceWithExpansion('abc', RegExp(r'\d'), r'X');
      expect(none.text, 'abc');
      expect(none.count, 0);
    });
  });

  group('WafBypass（纯逻辑部分）', () {
    test('detectFrom：按响应文本命中的 WAF 指纹', () {
      expect(WafBypass.detectFrom('HTTP/1.1 403\nCF-RAY: 1\nserver: cloudflare'), ['Cloudflare']);
      final hits = WafBypass.detectFrom('X-Sucuri-ID: 123\nsafedog');
      expect(hits, containsAll(<String>['Sucuri', '安全狗']));
      expect(WafBypass.detectFrom('HTTP/1.1 200 OK\ncontent-type: text/plain'), isEmpty);
      expect(WafBypass.fingerprints.containsKey('ModSecurity'), isTrue);
    });

    test('suggestFor：按 WAF 类型给出技术组合，未知类型给默认组合', () {
      expect(WafBypass.suggestFor('Cloudflare'), contains('whitespace_alt'));
      expect(WafBypass.suggestFor('ModSecurity'), contains('double_write'));
      expect(WafBypass.suggestFor('阿里云 WAF'), WafBypass.suggestFor('安全狗'));
      expect(WafBypass.suggestFor('不存在的WAF'), ['url_encode', 'comment_split', 'case_mix']);
      expect(WafBypass.suggestFor('Cloudflare'), isNot(equals(WafBypass.suggestFor('F5 BIG-IP'))));
    });

    test('mutate / mutateAll：变异是「等价写法」而非加密，且组合可复现', () async {
      final loc = await lookupAppLocalizations(const Locale('en'));
      const payload = 'select * from users where id=1';

      final variants = WafBypass.mutateAll(payload, loc);
      final ids = variants.map((v) => v.technique).toList();
      expect(ids, containsAll(<String>['url_encode', 'double_url', 'case_mix', 'base64_wrap', 'hex_wrap', 'chunked']),
          reason: '每种技术都要产出一条变体');
      final byId = {for (final v in variants) v.technique: v.output};

      expect(byId['url_encode'], Uri.encodeComponent(payload));
      expect(byId['double_url'], Uri.encodeComponent(Uri.encodeComponent(payload)));
      expect(byId['base64_wrap'], base64.encode(utf8.encode(payload)));
      expect(utf8.decode(base64.decode(byId['base64_wrap']!)), payload, reason: 'base64 变体必须可还原');
      expect(byId['hex_wrap'], startsWith('0x'));
      expect(byId['chunked'], endsWith('0\r\n\r\n'), reason: 'chunked 变体必须以结束块结尾');
      expect(byId['case_mix'], isNot(payload));
      expect(byId['case_mix']!.toLowerCase(), payload.toLowerCase());
      // 注释切分：空白被 /**/ 取代，语义等价
      expect(byId['comment_split'], contains('/**/'));

      // 组合结果 = 按顺序逐项叠加
      final combined = WafBypass.mutate(payload, ['url_encode', 'case_mix'], loc);
      expect(combined, hasLength(3), reason: '组合 1 条 + 单项 2 条');
      expect(combined.first.technique, 'url_encode + case_mix');
      String single(String id, String input) => WafBypass.mutate(input, [id], loc).last.output;
      expect(combined.first.output, single('case_mix', single('url_encode', payload)));

      // 推荐组合里的技术 id 必须真实存在（防止 suggestFor 与 techniques 漂移）
      final knownIds = WafBypass.techniques(loc).map((t) => t.id).toSet();
      for (final waf in WafBypass.fingerprints.keys) {
        expect(knownIds.containsAll(WafBypass.suggestFor(waf)), isTrue, reason: '$waf 的推荐技术存在未知 id');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('RequestFuzzer（纯逻辑部分）', () {
    test('combinationCount / buildCases 笛卡尔积与上限截断', () {
      expect(RequestFuzzer.combinationCount([]), 0);
      final one = [const FuzzInjection(target: FuzzTarget.queryParam, field: 'id', values: ['1', '2', '3'])];
      expect(RequestFuzzer.combinationCount(one), 3);

      final two = [
        const FuzzInjection(target: FuzzTarget.queryParam, field: 'id', values: ['1', '2']),
        const FuzzInjection(target: FuzzTarget.header, field: 'X-A', values: ['a', 'b', 'c']),
      ];
      expect(RequestFuzzer.combinationCount(two), 6);

      final cases = RequestFuzzer.buildCases(two);
      expect(cases, hasLength(6));
      expect(cases.first.values, ['1', 'a']);
      expect(cases.first.label, 'id=1 & X-A=a');
      expect(cases.map((c) => c.values.join('|')).toSet(), hasLength(6), reason: '组合不能重复');

      // 每个注入项可选值为空时按一个空值处理
      final empty = [const FuzzInjection(target: FuzzTarget.queryParam, field: 'id')];
      expect(RequestFuzzer.combinationCount(empty), 1);
      expect(RequestFuzzer.buildCases(empty).single.label, 'id=');

      // limit 截断
      final limited = RequestFuzzer.buildCases(two, limit: 4);
      expect(limited, hasLength(4));
      expect(RequestFuzzer.buildCases([]), isEmpty);
    });

    test('buildVariant：query / header / json 字段 / body 占位符 四种注入', () {
      final template = _req('http://api.example.com/v1/items?id=1&keep=yes', HttpMethod.post,
          body: '{"name":"tom","keep":true}');
      template.headers.set('X-Token', 'origin');
      template.headers.set('User-Agent', 'proxypin');

      // queryParam：替换 id，保留其它参数
      final q = RequestFuzzer.buildVariant(
          template, [const FuzzInjection(target: FuzzTarget.queryParam, field: 'id', values: ["1' or 1=1"])], ["1' or 1=1"]);
      expect(q.requestUri!.queryParameters['id'], "1' or 1=1");
      expect(q.requestUri!.queryParameters['keep'], 'yes');
      expect(q.method, HttpMethod.post);
      expect(q.headers.get('X-Token'), 'origin', reason: '变体必须继承模板 headers');

      // header：覆盖已有头 + 新增头
      final h = RequestFuzzer.buildVariant(
          template,
          [
            const FuzzInjection(target: FuzzTarget.header, field: 'User-Agent', values: ['sqlmap']),
            const FuzzInjection(target: FuzzTarget.header, field: 'X-New', values: ['1']),
          ],
          ['sqlmap', '1']);
      expect(h.headers.get('User-Agent'), 'sqlmap');
      expect(h.headers.get('X-New'), '1');
      expect(h.headers.get('X-Token'), 'origin');

      // jsonField：只替换命中的字段，其它字段保持
      final j = RequestFuzzer.buildVariant(
          template, [const FuzzInjection(target: FuzzTarget.jsonField, field: 'name', values: ['<script>'])], ['<script>']);
      final decoded = jsonDecode(j.bodyAsString) as Map<String, dynamic>;
      expect(decoded['name'], '<script>');
      expect(decoded['keep'], true);

      // bodyPlaceholder：整串替换占位符
      final tpl2 = _req('http://api.example.com/p', HttpMethod.post, body: 'a={{FUZZ}}&b={{FUZZ}}');
      final p = RequestFuzzer.buildVariant(
          tpl2, [const FuzzInjection(target: FuzzTarget.bodyPlaceholder, values: ['X'])], ['X']);
      expect(p.bodyAsString, 'a=X&b=X');

      // 非法 JSON 不得抛异常、也不得改动原始 body
      final bad = _req('http://api.example.com/p', HttpMethod.post, body: 'not-json');
      final unchanged = RequestFuzzer.buildVariant(
          bad, [const FuzzInjection(target: FuzzTarget.jsonField, field: 'name', values: ['x'])], ['x']);
      expect(unchanged.bodyAsString, 'not-json');

      // 模板本身不被改动（buildVariant 必须复制）
      expect(template.bodyAsString, '{"name":"tom","keep":true}');
      expect(template.requestUri!.queryParameters['id'], '1');
    });

    test('parsePayloads：一行一个取值，忽略空行与 # 注释', () {
      final values = RequestFuzzer.parsePayloads("1\n\n# 注释\n 2 \n3\n#\n");
      expect(values, ['1', ' 2 ', '3']);
      expect(RequestFuzzer.parsePayloads(''), isEmpty);
      expect(RequestFuzzer.parsePayloads('# only comment'), isEmpty);
    });

    test('toCsv：表头 + 逐行结果（baseline 行 index 留空）', () {
      const baseline = FuzzOutcome(index: 0, payload: 'seed', ok: true, durationMs: 5, bodyLength: 5, baseline: true);
      const probe =
          FuzzOutcome(index: 0, payload: "1' or '1", ok: true, statusCode: 500, durationMs: 9, bodyLength: 42);
      final csv = RequestFuzzer.toCsv([baseline, probe]);
      final lines = const LineSplitter().convert(csv);
      expect(lines.first, startsWith('index,payload,baseline,status,length,duration_ms'));
      expect(lines, hasLength(3));
      expect(lines[1], contains(',seed,1,'));
      expect(lines[2], contains('1,1\' or \'1,0,500,42,9'));
    });
  });

  group('RequestComparator', () {
    test('完全相同的两个请求：无差异', () {
      final a = _req('http://api.example.com/v1/items?id=1', HttpMethod.post, body: '{"a":1}');
      final b = _req('http://api.example.com/v1/items?id=1', HttpMethod.post, body: '{"a":1}');
      final result = RequestComparator().compare(a, b);
      expect(result.hasChanges, isFalse);
      expect(result.totalChanges, 0);
      expect(result.urlChanged, isFalse);
      expect(result.methodChanged, isFalse);
      expect(result.headerDiffs, isEmpty);
      expect(result.queryDiffs, isEmpty);
      expect(result.bodyDiff?.hasChanged, isNot(true));
      expect(result.summary, isNotEmpty);
    });

    test('URL / 方法 / 头 / 查询串 / body 差异都能识别', () {
      final a = _req('http://api.example.com/v1/items?id=1&keep=1', HttpMethod.get, body: 'aaa');
      a.headers.set('X-Token', 'old');
      a.headers.set('X-Only-A', '1');
      final b = _req('http://api.example.com/v1/items?id=2&keep=1&add=9', HttpMethod.post, body: 'bbb');
      b.headers.set('X-Token', 'new');
      b.headers.set('X-Only-B', '2');

      final result = RequestComparator().compare(a, b);
      expect(result.urlChanged, isTrue);
      expect(result.methodChanged, isTrue);

      final byName = {for (final d in result.headerDiffs) d.fieldName.toLowerCase(): d};
      expect(byName['x-token']?.type, CompareType.modified);
      expect(byName['x-token']?.oldValue, 'old');
      expect(byName['x-token']?.newValue, 'new');
      expect(byName['x-only-b']?.type, CompareType.added);
      expect(byName['x-only-a']?.type, CompareType.removed);
      expect(byName['x-only-b']?.hasChanged, isTrue);

      final queryByName = {for (final d in result.queryDiffs) d.fieldName: d};
      expect(queryByName['id']?.type, CompareType.modified);
      expect(queryByName['add']?.type, CompareType.added);

      expect(result.bodyDiff?.type, CompareType.modified);
      expect(result.bodyDiff?.oldValue, 'aaa');
      expect(result.bodyDiff?.newValue, 'bbb');
      expect(result.totalChanges, greaterThanOrEqualTo(6));
    });

    test('响应状态码 / 响应头 / 响应体差异', () {
      final a = _req('http://api.example.com/x', HttpMethod.get);
      final b = _req('http://api.example.com/x', HttpMethod.get);
      final respA = _resp(200, 'OK', body: 'ok', contentType: 'text/plain')
        ..request = a
        ..headers.set('X-Trace', '1');
      final respB = _resp(503, 'Service Unavailable', body: 'down', contentType: 'application/json')
        ..request = b
        ..headers.set('X-Trace', '2');

      final result = RequestComparator().compare(a, b, responseA: respA, responseB: respB);
      expect(result.statusCodeChanged, isTrue);
      expect(result.responseBodyDiff?.type, CompareType.modified);
      expect(result.responseBodyDiff?.newValue, 'down');
      final respHeaderByName = {for (final d in result.responseHeaderDiffs) d.fieldName.toLowerCase(): d};
      expect(respHeaderByName['x-trace']?.type, CompareType.modified);
      expect(respHeaderByName['content-type']?.type, CompareType.modified);
      expect(result.responseA?.status.code, 200);
      expect(result.responseB?.status.code, 503);
    });
  });

  group('TrafficStats', () {
    test('compute：总览 / 域名 / 状态码 / 内容类型 / 最慢 / 最大', () {
      final t0 = DateTime(2026, 1, 1, 0, 0, 0);
      final r1 = _req('http://a.example.com/x', HttpMethod.get, body: '0123456789');
      final r2 = _req('http://a.example.com/y', HttpMethod.get, body: 'ab');
      final r3 = _req('http://b.example.com/z', HttpMethod.post);

      r1.requestTime = t0;
      r1.response = _resp(200, 'OK', body: '0123456789', contentType: 'application/json; charset=utf-8')
        ..request = r1
        ..responseTime = t0.add(const Duration(milliseconds: 100));
      r2.requestTime = t0;
      r2.response = _resp(404, 'Not Found', body: 'boom', contentType: 'text/plain')
        ..request = r2
        ..responseTime = t0.add(const Duration(milliseconds: 300));
      r3.requestTime = t0;

      final stats = TrafficStats.compute([r1, r2, r3]);
      expect(stats.total, 3);
      expect(stats.success, 1);
      expect(stats.fail, 1, reason: '4xx 计为失败');
      expect(stats.pending, 1, reason: '无响应计为 pending');
      expect(stats.totalRequestBytes, 12);
      expect(stats.totalResponseBytes, 14);
      expect(stats.avgDurationMs, 200, reason: '仅统计已完成的响应');

      expect(stats.topHosts.map((e) => e.label), ['a.example.com', 'b.example.com']);
      expect(stats.topHosts.first.count, 2);
      expect(stats.topHosts.first.bytes, 14);
      expect(stats.topHosts.first.share(stats.total), closeTo(2 / 3, 1e-9));
      expect(stats.topHosts.last.share(0), 0);

      expect(stats.statusCodes.map((e) => e.label), containsAll(<String>['200', '404']));
      expect(stats.statusCodes.firstWhere((e) => e.label == '404').count, 1);

      expect(stats.topContentTypes.map((e) => e.label), containsAll(<String>['application/json', 'text/plain']));
      expect(stats.topContentTypes.every((e) => !e.label.contains(';')), isTrue);

      expect(stats.slowest.map((e) => e.durationMs), [300, 100]);
      expect(stats.slowest.first.url, 'http://a.example.com/y');
      expect(stats.largest.map((e) => e.bytes), [10, 4]);
      expect(stats.largest.first.status, 200);

      final topOne = TrafficStats.compute([r1, r2, r3], topN: 1);
      expect(topOne.topHosts, hasLength(1));
      expect(topOne.slowest, hasLength(1));
      expect(topOne.slowest.single.durationMs, 300);
      expect(topOne.statusCodes, hasLength(1));
    });

    test('空列表与一致状态码统计', () {
      final empty = TrafficStats.compute([]);
      expect(empty.total, 0);
      expect(empty.avgDurationMs, 0);
      expect(empty.topHosts, isEmpty);
      expect(empty.slowest, isEmpty);
      expect(empty.totalResponseBytes, 0);
    });

    test('formatBytes 单位换算', () {
      expect(TrafficStats.formatBytes(0), '0 B');
      expect(TrafficStats.formatBytes(1023), '1023 B');
      expect(TrafficStats.formatBytes(2048), '2.0 KB');
      expect(TrafficStats.formatBytes(1024 * 1024), '1.00 MB');
      expect(TrafficStats.formatBytes(3 * 1024 * 1024 * 1024), '3.00 GB');
    });
  });
}
