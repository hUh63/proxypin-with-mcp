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

/// 覆盖 MCP 自动化任务的条件匹配（纯模型，无需启动代理）。
///
/// 重点回归：条件值来自 MCP 工具入参 / 持久化 JSON，类型并不可靠，旧实现用
/// `as String` / `as List` / `as int` 强转，一旦类型不符就在转发热路径上抛
/// TypeError，规则静默失效。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/mcp/mcp_automation_manager.dart';

MCPAutomationTask _task(
  Map<String, dynamic> conditions, {
  AutomationTriggerType trigger = AutomationTriggerType.onRequest,
}) =>
    MCPAutomationTask(
      id: 't',
      name: 't',
      triggerType: trigger,
      actions: const [AutomationActionType.sendNotification],
      conditions: conditions,
    );

void main() {
  group('MCPAutomationTask.matchesRequest', () {
    test('urlPattern 非字符串（数字）不再抛 TypeError', () {
      final t = _task({'urlPattern': 8080});
      expect(t.matchesRequest({'url': 'http://a.com:8080/x', 'method': 'GET'}), isTrue);
      expect(t.matchesRequest({'url': 'http://a.com/x', 'method': 'GET'}), isFalse);
    });

    test('urlPattern 为空串时不过滤', () {
      final t = _task({'urlPattern': ''});
      expect(t.matchesRequest({'url': 'http://a.com/x', 'method': 'GET'}), isTrue);
    });

    test('methods 支持 List，也兼容 "GET,POST" 字符串', () {
      expect(_task({'methods': ['POST']}).matchesRequest({'url': 'u', 'method': 'GET'}), isFalse);
      expect(_task({'methods': ['POST']}).matchesRequest({'url': 'u', 'method': 'POST'}), isTrue);
      expect(_task({'methods': 'get, post'}).matchesRequest({'url': 'u', 'method': 'POST'}), isTrue);
      expect(_task({'methods': ['GET']}).matchesRequest({'url': 'u', 'method': 'get'}), isTrue,
          reason: '方法名大小写不敏感');
    });

    test('headers 匹配忽略头名大小写', () {
      final t = _task({
        'headers': {'content-type': 'application/json'}
      });
      final req = {
        'url': 'u',
        'method': 'POST',
        'headers': {'Content-Type': 'application/json'},
      };
      expect(t.matchesRequest(req), isTrue);
    });

    test('headers 条件类型异常时不抛异常，直接不匹配', () {
      final t = _task({'headers': 'not-a-map'});
      expect(t.matchesRequest({'url': 'u', 'method': 'GET', 'headers': {}}), isFalse,
          reason: '条件本身坏掉时宁可不命中，也不能崩');
      final t2 = _task({
        'headers': {'a': 'b'}
      });
      expect(t2.matchesRequest({'url': 'u', 'method': 'GET', 'headers': 'oops'}), isFalse);
    });

    test('触发器类型不匹配时直接返回 false', () {
      final t = _task({'urlPattern': 'a'}, trigger: AutomationTriggerType.onResponse);
      expect(t.matchesRequest({'url': 'a', 'method': 'GET'}), isFalse);
    });
  });

  group('MCPAutomationTask.matchesResponse', () {
    test('statusCode 支持数字与数字字符串', () {
      final byInt = _task({'statusCode': 404}, trigger: AutomationTriggerType.onResponse);
      expect(byInt.matchesResponse({'url': 'u', 'statusCode': 404}), isTrue);
      expect(byInt.matchesResponse({'url': 'u', 'statusCode': 200}), isFalse);

      final byStr = _task({'statusCode': '404'}, trigger: AutomationTriggerType.onResponse);
      expect(byStr.matchesResponse({'url': 'u', 'statusCode': 404}), isTrue);

      final byDouble = _task({'statusCode': 404.0}, trigger: AutomationTriggerType.onResponse);
      expect(byDouble.matchesResponse({'url': 'u', 'statusCode': 404}), isTrue);
    });

    test('statusCode 无法解析时视为不过滤，不抛异常', () {
      final t = _task({'statusCode': 'abc'}, trigger: AutomationTriggerType.onResponse);
      expect(t.matchesResponse({'url': 'u', 'statusCode': 500}), isTrue);
    });

    test('urlPattern 组合条件', () {
      final t = _task({'urlPattern': '/api', 'statusCode': 500},
          trigger: AutomationTriggerType.onResponse);
      expect(t.matchesResponse({'url': 'http://a.com/api/x', 'statusCode': 500}), isTrue);
      expect(t.matchesResponse({'url': 'http://a.com/web/x', 'statusCode': 500}), isFalse);
    });
  });
}
