/*
 * MCP 工具级测试（此前为零覆盖）。
 *
 * 覆盖目标：
 *   1) 工具定义完整性：tools/list 中每条工具的 name 唯一、description 非空、
 *      inputSchema 是合法 JSON Schema（type=object / properties 为对象 /
 *      required 为字符串数组且都在 properties 中声明）。
 *   2) 两个已确证缺陷的回归：
 *      - `list_hosts` 同时存在于原生表与厂商表，曾未纳入过滤集合导致 tools/list 重名；
 *      - `get_certificate_status` 因 McpActions 未注入 certStatusProvider 而永远返回占位值。
 *   3) 未知工具名、必填参数缺失等错误语义（返回明确错误而不是崩溃）。
 *   4) 无副作用只读工具的正常路径（get_tool_catalog / get_client_setup /
 *      get_proxy_status / get_ssl_proxying_list / get_mcp_audit）。
 *
 * 说明：直接实例化 `McpServer()`（单例）并通过公开入口 `getTools()` / `executeTool()` /
 * `sendRequest()` 驱动，不需要 Flutter binding、真实网络或原生库，因此**不打 integration 标签**。
 * 测试环境未加载 Configuration，`McpBridge().isToolEnabled()` 一律视为启用。
 */

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/mcp/capture/cert_status.dart';
import 'package:proxypin/mcp/capture/flow_store.dart';
import 'package:proxypin/mcp/protocol/mcp_actions.dart';
import 'package:proxypin/network/mcp/mcp_server.dart';

void main() {
  final server = McpServer();

  group('工具定义完整性（tools/list）', () {
    final tools = server.getTools();

    test('工具表非空，规模符合预期（约 98 条）', () {
      expect(tools, isNotEmpty);
      expect(tools.length, greaterThanOrEqualTo(90));
      expect(tools.length, lessThan(150), reason: '工具表异常膨胀，可能存在重复注册');
    });

    test('工具名唯一：不存在重名工具（list_hosts 回归）', () {
      final names = tools.map((t) => t['name'] as String).toList();
      final seen = <String>{};
      final duplicates = <String>[];
      for (final n in names) {
        if (!seen.add(n)) duplicates.add(n);
      }
      expect(duplicates, isEmpty, reason: 'tools/list 返回了重名工具：$duplicates');
    });

    test('list_hosts 只暴露一次（原生实现优先，厂商同名项被隐藏）', () {
      final count = tools.where((t) => t['name'] == 'list_hosts').length;
      expect(count, 1, reason: '原生表与厂商表都定义了 list_hosts，过滤后应只保留一条，实际 $count 条');
    });

    test('关键工具存在', () {
      final names = tools.map((t) => t['name']).toSet();
      expect(
        names,
        containsAll(['get_tool_catalog', 'list_hosts', 'get_certificate_status', 'set_config', 'import_har']),
      );
    });

    test('每个工具的 name / description 均非空', () {
      for (final t in tools) {
        final name = t['name'];
        expect(name, isA<String>(), reason: '工具缺少 name 字段：$t');
        expect((name as String).trim(), isNotEmpty);
        final desc = t['description'];
        expect(desc, isA<String>(), reason: '$name 缺少 description');
        expect((desc as String).trim(), isNotEmpty, reason: '$name 的 description 为空');
      }
    });

    test('每个 inputSchema 是合法 JSON Schema 对象', () {
      for (final t in tools) {
        final name = t['name'];
        final schema = t['inputSchema'];
        expect(schema, isA<Map>(), reason: '$name 的 inputSchema 不是对象：$schema');
        final s = schema as Map;
        // 顶层必须是 object（也兼容 ['object'] 形式的联合类型）
        expect(s['type'], contains('object'), reason: '$name 的 inputSchema.type 必须是 object');

        final properties = s['properties'];
        if (properties != null) {
          expect(properties, isA<Map>(), reason: '$name 的 properties 必须是对象');
        }

        final required = s['required'];
        if (required != null) {
          expect(required, isA<List>(), reason: '$name 的 required 必须是数组');
          for (final r in required as List) {
            expect(r, isA<String>(), reason: '$name 的 required 项必须是字符串');
            if (properties is Map) {
              expect(properties.containsKey(r), isTrue,
                  reason: '$name 的 required 项 "$r" 未在 properties 中声明');
            }
          }
        }
      }
    });
  });

  group('厂商工具源（McpActions）', () {
    final actions = McpActions(store: FlowStore());
    final official = actions.tools();

    test('厂商表确实定义了 list_hosts（重名的来源）', () {
      expect(official.map((t) => t.name), contains('list_hosts'));
    });

    test('厂商表暴露 get_certificate_status', () {
      expect(official.map((t) => t.name), contains('get_certificate_status'));
    });

    test('certStatusProvider 契约：注入后原样返回其查询结果', () async {
      final withProvider = McpActions(
        store: FlowStore(),
        certStatusProvider: () async => {'available': true, 'installed': true, 'stub': true},
      );
      final tool = withProvider.tools().firstWhere((t) => t.name == 'get_certificate_status');
      final result = await tool.handler({});
      expect(result, isA<Map>());
      expect((result as Map)['stub'], isTrue);
    });

    test('certStatusProvider 缺省时返回桌面端占位值（接线前的行为）', () async {
      final tool = official.firstWhere((t) => t.name == 'get_certificate_status');
      final result = await tool.handler({}) as Map;
      expect(result['available'], isFalse);
      expect(result['reason'], 'certificate status is only available in the desktop app');
    });
  });

  group('只读工具正常路径', () {
    test('get_tool_catalog 返回分组结构，总数与工具表一致', () async {
      final result = await server.executeTool('get_tool_catalog', {}) as Map;
      expect(result['total'], isA<int>());
      expect(result['groups'], isA<Map>());
      expect(result['note'], isA<String>());
      final groups = result['groups'] as Map;
      expect(groups, isNotEmpty);
      for (final v in groups.values) {
        expect(v, isA<List>());
      }
      // catalog 自身不计入统计
      expect(result['total'], server.getTools().length - 1);
    });

    test('get_client_setup 返回 streamable-http 端点与客户端命令', () async {
      final result = await server.executeTool('get_client_setup', {}) as Map;
      expect(result['transport'], 'streamable-http');
      expect(result['endpoint'], contains('127.0.0.1'));
      expect(result['endpoint'], contains('/mcp'));
      expect(result['bearer_token_required'], isFalse);
      expect(result['commands'], isA<Map>());
      final commands = result['commands'] as Map;
      expect(commands['curl'], contains('tools/list'));
    });

    test('get_proxy_status 在代理未启动时返回 isRunning=false', () async {
      final result = await server.executeTool('get_proxy_status', {}) as Map;
      expect(result.containsKey('isRunning'), isTrue);
      expect(result['isRunning'], isFalse);
    });

    test('get_ssl_proxying_list 返回白/黑名单结构', () async {
      final result = await server.executeTool('get_ssl_proxying_list', {}) as Map;
      expect(result['whitelist'], isA<Map>());
      expect(result['blacklist'], isA<Map>());
      expect(result['semantics'], isA<String>());
      for (final key in ['whitelist', 'blacklist']) {
        final entry = result[key] as Map;
        expect(entry['enabled'], isA<bool>());
        expect(entry['count'], isA<int>());
        expect(entry['rules'], isA<List>());
      }
    });

    test('get_mcp_audit 返回审计环形缓冲结构', () async {
      final result = await server.executeTool('get_mcp_audit', {'limit': 5}) as Map;
      expect(result['buffered'], isA<int>());
      expect(result['returned'], isA<int>());
      expect(result['records'], isA<List>());
    });

    test('calculator 缺少必填 op 时返回参数校验错误', () async {
      final result = await server.executeTool('calculator', {}) as Map;
      expect(result['error'], isA<String>());
      expect(result['error'], contains('missing required parameter'));
      expect(result['error'], contains('op'));
    });

    test('calculator add 走正常路径返回精确结果', () async {
      final result = await server.executeTool('calculator', {
        'op': 'add',
        'a': 2,
        'b': 3,
      }) as Map;
      expect(result['operation'], 'add');
      expect(result['result'], '5');
      expect(result['exact'], isTrue);
    });
  });

  group('参数校验与错误语义', () {
    test('必填参数缺失 → 参数校验错误（import_har.har_content）', () async {
      final result = await server.executeTool('import_har', {});
      expect(result, isA<Map>());
      final m = result as Map;
      expect(m['error'], isA<String>());
      expect(m['error'], contains('missing required parameter'));
      expect(m['error'], contains('har_content'));
    });

    test('未知工具名 → executeTool 抛出明确错误（不静默）', () async {
      await expectLater(
        server.executeTool('__no_such_tool__', {}),
        throwsA(predicate((Object? e) => e.toString().contains('Unknown tool'))),
      );
    });

    test('未知工具名 → tools/call 以 isError 结果返回而非崩溃', () async {
      final res = await server.sendRequest('tools/call', {
        'name': '__no_such_tool__',
        'arguments': <String, dynamic>{},
      });
      expect(res, isNotNull);
      expect(res!['isError'], isTrue);
      final content = res['content'] as List;
      expect(content, isNotEmpty);
      expect((content.first as Map)['text'], contains('Unknown tool'));
    });

    test('tools/call 缺少 name → 协议级错误（无 result）', () async {
      final res = await server.sendRequest('tools/call', {'arguments': <String, dynamic>{}});
      expect(res, isNull);
    });
  });

  group('已确证缺陷的回归', () {
    test('CertStatus.query 是 get_certificate_status 的数据源，返回 available 且不抛异常', () async {
      final result = await CertStatus.query();
      expect(result, isA<Map<String, dynamic>>());
      expect(result.containsKey('available'), isTrue);
      expect(result['available'], isA<bool>());
    });

    test('get_certificate_status 已接线：返回真实 CA 状态而非桌面端占位', () async {
      final result = await server.executeTool('get_certificate_status', {});
      expect(result, isA<Map>());
      final m = result as Map;
      expect(m.containsKey('available'), isTrue, reason: '返回结构缺少 available：$m');
      expect(m['available'], isA<bool>());
      expect(
        m,
        isNot(equals({
          'available': false,
          'reason': 'certificate status is only available in the desktop app',
        })),
        reason: 'McpActions 未注入 certStatusProvider，get_certificate_status 退化为占位值',
      );
      // 桌面平台应返回 available=true（CA 未初始化时 installed=false + reason=CA not initialized）
      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        expect(m['available'], isTrue, reason: '桌面平台的 CA 状态查询应可用：$m');
      }
    });

    test('tools/list 无重名（list_hosts 只出现一次）', () async {
      final res = await server.sendRequest('tools/list');
      expect(res, isNotNull);
      final list = (res!['tools'] as List).cast<Map>();
      final names = list.map((t) => t['name'] as String).toList();
      expect(names.toSet().length, names.length, reason: 'tools/list 仍有重名工具');
      expect(names.where((n) => n == 'list_hosts').length, 1);
    });
  });
}
