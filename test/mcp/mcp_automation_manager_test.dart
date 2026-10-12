/*
 * MCP 自动化任务单元测试（对齐当前 API 重写）
 *
 * 覆盖：任务模型的条件匹配（请求 / 响应）、序列化往返、copyWith、
 * 以及管理器在未初始化态下的只读行为。
 * 不触碰文件系统与网络，可在 CI 上稳定运行。
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/mcp/mcp_automation_manager.dart';

MCPAutomationTask _task({
  String id = 't1',
  AutomationTriggerType trigger = AutomationTriggerType.onRequest,
  Map<String, dynamic> conditions = const {},
  List<AutomationActionType> actions = const [AutomationActionType.sendNotification],
  bool enabled = true,
}) =>
    MCPAutomationTask(
      id: id,
      name: 'task-$id',
      description: 'desc',
      triggerType: trigger,
      actions: actions,
      conditions: conditions,
      enabled: enabled,
    );

void main() {
  group('MCPAutomationTask.matchesRequest', () {
    test('触发类型不是 onRequest 时一律不匹配', () {
      final task = _task(trigger: AutomationTriggerType.onProxyStart, conditions: const {});
      expect(task.matchesRequest({'url': 'https://a.com/x', 'method': 'GET'}), isFalse);
    });

    test('无条件时 onRequest 任务匹配任意请求', () {
      expect(_task().matchesRequest({'url': 'https://a.com/x', 'method': 'GET'}), isTrue);
    });

    test('urlPattern 按包含匹配', () {
      final task = _task(conditions: {'urlPattern': '/api/'});
      expect(task.matchesRequest({'url': 'https://a.com/api/user', 'method': 'GET'}), isTrue);
      expect(task.matchesRequest({'url': 'https://a.com/web/user', 'method': 'GET'}), isFalse);
    });

    test('urlPattern 命中但请求缺 url 时不匹配', () {
      final task = _task(conditions: {'urlPattern': '/api/'});
      expect(task.matchesRequest({'method': 'GET'}), isFalse);
    });

    test('methods 白名单匹配', () {
      final task = _task(conditions: {'methods': ['POST', 'PUT']});
      expect(task.matchesRequest({'url': 'https://a.com/x', 'method': 'POST'}), isTrue);
      expect(task.matchesRequest({'url': 'https://a.com/x', 'method': 'GET'}), isFalse);
      expect(task.matchesRequest({'url': 'https://a.com/x'}), isFalse);
    });

    test('headers 必须全部精确相等', () {
      final task = _task(conditions: {
        'headers': {'X-Env': 'staging'}
      });
      expect(
        task.matchesRequest({
          'url': 'https://a.com/x',
          'method': 'GET',
          'headers': {'X-Env': 'staging', 'Other': '1'},
        }),
        isTrue,
      );
      expect(
        task.matchesRequest({
          'url': 'https://a.com/x',
          'method': 'GET',
          'headers': {'X-Env': 'prod'},
        }),
        isFalse,
      );
      expect(task.matchesRequest({'url': 'https://a.com/x', 'method': 'GET'}), isFalse);
    });

    test('多个条件之间是「与」关系', () {
      final task = _task(conditions: {
        'urlPattern': '/api/',
        'methods': ['POST'],
      });
      expect(task.matchesRequest({'url': 'https://a.com/api/x', 'method': 'POST'}), isTrue);
      expect(task.matchesRequest({'url': 'https://a.com/api/x', 'method': 'GET'}), isFalse);
      expect(task.matchesRequest({'url': 'https://a.com/web/x', 'method': 'POST'}), isFalse);
    });
  });

  group('MCPAutomationTask.matchesResponse', () {
    test('触发类型不是 onResponse 时不匹配', () {
      final task = _task(trigger: AutomationTriggerType.onRequest);
      expect(task.matchesResponse({'status': 200}), isFalse);
    });

    test('statusCode 精确匹配', () {
      final task = _task(
        trigger: AutomationTriggerType.onResponse,
        conditions: {'statusCode': 500},
      );
      expect(task.matchesResponse({'statusCode': 500}), isTrue);
      expect(task.matchesResponse({'statusCode': 200}), isFalse);
      expect(task.matchesResponse({}), isFalse);
    });

    test('urlPattern 对响应同样生效', () {
      final task = _task(
        trigger: AutomationTriggerType.onResponse,
        conditions: {'urlPattern': '/api/'},
      );
      expect(task.matchesResponse({'url': 'https://a.com/api/x'}), isTrue);
      expect(task.matchesResponse({'url': 'https://a.com/web/x'}), isFalse);
    });
  });

  group('MCPAutomationTask 序列化', () {
    test('toJson / fromJson 往返保持关键字段', () {
      final original = _task(
        id: 'round',
        trigger: AutomationTriggerType.onResponse,
        conditions: {
          'statusCodes': [404]
        },
        actions: [AutomationActionType.exportData, AutomationActionType.callWebhook],
        enabled: false,
      );
      final restored = MCPAutomationTask.fromJson(original.toJson());

      expect(restored.id, 'round');
      expect(restored.name, original.name);
      expect(restored.triggerType, AutomationTriggerType.onResponse);
      expect(restored.enabled, isFalse);
      expect(restored.conditions['statusCodes'], [404]);
      expect(restored.actions, [AutomationActionType.exportData, AutomationActionType.callWebhook]);
      expect(restored.createdAt.toIso8601String(), original.createdAt.toIso8601String());
    });

    test('未知触发 / 动作类型回退到默认而不抛异常', () {
      final json = _task().toJson()
        ..['triggerType'] = 'not-a-trigger'
        ..['actions'] = ['not-an-action'];
      final restored = MCPAutomationTask.fromJson(json);
      expect(restored.triggerType, AutomationTriggerType.manual);
      expect(restored.actions, [AutomationActionType.runScript]);
    });
  });

  group('MCPAutomationTask.copyWith', () {
    test('只改传入的字段，id 与创建时间保持不变', () {
      final task = _task(id: 'c1');
      final updated = task.copyWith(name: '新名字', enabled: false);

      expect(updated.id, 'c1');
      expect(updated.name, '新名字');
      expect(updated.enabled, isFalse);
      expect(updated.description, task.description);
      expect(updated.createdAt, task.createdAt);
      expect(updated.updatedAt.isBefore(task.updatedAt), isFalse);
    });
  });

  group('MCPAutomationManager 只读行为', () {
    test('未初始化时任务列表为空，导出为空数组', () async {
      final manager = MCPAutomationManager();
      expect(manager.tasks, isEmpty);
      expect(manager.enabledTasks, isEmpty);
      final exported = await manager.exportTasks();
      expect(exported, '[]');
    });
  });
}
