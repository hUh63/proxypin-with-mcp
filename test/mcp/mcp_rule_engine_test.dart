/*
 * MCP 规则引擎单元测试（对齐当前 API 重写）
 *
 * 覆盖：条件求值、JSON 往返、规则可用性、规则管理、评估与动作执行、执行历史。
 * 全程不触碰文件系统与网络，可在 CI 上稳定运行。
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/mcp/mcp_rule_engine.dart';

Condition _cond(Operator op, String field, dynamic value) =>
    Condition(type: ConditionType.custom, field: field, operator: op, value: value);

Rule _rule({
  String id = 'r1',
  List<Condition>? conditions,
  List<Action>? actions,
  RulePriority priority = RulePriority.normal,
  bool enabled = true,
  DateTime? expiresAt,
}) =>
    Rule(
      id: id,
      name: 'rule-$id',
      conditions: conditions ?? [_cond(Operator.equals, 'method', 'GET')],
      actions: actions ?? [],
      priority: priority,
      enabled: enabled,
      expiresAt: expiresAt,
    );

void main() {
  group('Condition 求值', () {
    final ctx = {
      'method': 'GET',
      'url': 'https://api.example.com/v1/user',
      'status': 200,
      'headers': {'X-Trace': 'abc'},
    };

    test('equals / notEquals', () {
      expect(_cond(Operator.equals, 'method', 'GET').evaluate(ctx), isTrue);
      expect(_cond(Operator.equals, 'method', 'POST').evaluate(ctx), isFalse);
      expect(_cond(Operator.notEquals, 'method', 'POST').evaluate(ctx), isTrue);
    });

    test('字符串包含 / 前后缀', () {
      expect(_cond(Operator.contains, 'url', 'api.example').evaluate(ctx), isTrue);
      expect(_cond(Operator.startsWith, 'url', 'https://').evaluate(ctx), isTrue);
      expect(_cond(Operator.endsWith, 'url', '/v1/user').evaluate(ctx), isTrue);
      expect(_cond(Operator.contains, 'url', 'nope').evaluate(ctx), isFalse);
    });

    test('正则匹配', () {
      expect(_cond(Operator.matches, 'url', r'/v\d+/').evaluate(ctx), isTrue);
      expect(_cond(Operator.matches, 'url', r'/v\d{3,}/').evaluate(ctx), isFalse);
      // value 是 RegExp 时应直接使用
      expect(_cond(Operator.matches, 'url', RegExp(r'example\.com')).evaluate(ctx), isTrue);
    });

    test('数值比较', () {
      expect(_cond(Operator.greaterThan, 'status', 199).evaluate(ctx), isTrue);
      expect(_cond(Operator.lessThan, 'status', 201).evaluate(ctx), isTrue);
      expect(_cond(Operator.greaterThanOrEqual, 'status', 200).evaluate(ctx), isTrue);
      expect(_cond(Operator.lessThanOrEqual, 'status', 200).evaluate(ctx), isTrue);
      expect(_cond(Operator.greaterThan, 'status', 200).evaluate(ctx), isFalse);
    });

    test('列表包含', () {
      expect(_cond(Operator.inList, 'method', ['GET', 'HEAD']).evaluate(ctx), isTrue);
      expect(_cond(Operator.inList, 'method', ['POST']).evaluate(ctx), isFalse);
      expect(_cond(Operator.notInList, 'method', ['POST']).evaluate(ctx), isTrue);
    });

    test('存在性判断', () {
      expect(_cond(Operator.exists, 'method', null).evaluate(ctx), isTrue);
      expect(_cond(Operator.notExists, 'missing', null).evaluate(ctx), isTrue);
      expect(_cond(Operator.notExists, 'method', null).evaluate(ctx), isFalse);
    });

    test('点号路径访问嵌套字段', () {
      expect(_cond(Operator.equals, 'headers.X-Trace', 'abc').evaluate(ctx), isTrue);
      expect(_cond(Operator.equals, 'headers.X-Trace', 'zzz').evaluate(ctx), isFalse);
    });

    test('字段缺失与空 context 不抛异常', () {
      expect(_cond(Operator.equals, 'nope', 'x').evaluate(ctx), isFalse);
      expect(_cond(Operator.exists, 'nope', null).evaluate(ctx), isFalse);
      expect(_cond(Operator.equals, 'method', 'GET').evaluate(null), isFalse);
      // 路径中途为 null 时应安全返回
      expect(_cond(Operator.equals, 'headers.deep.more', 'x').evaluate(ctx), isFalse);
    });
  });

  group('JSON 往返', () {
    test('Condition 往返保持字段与操作符', () {
      final original = _cond(Operator.contains, 'url', 'api');
      final restored = Condition.fromJson(original.toJson());
      expect(restored.field, 'url');
      expect(restored.operator, Operator.contains);
      expect(restored.value, 'api');
      expect(restored.type, ConditionType.custom);
    });

    test('Action 往返保持类型与参数', () {
      final original = Action(
        type: ActionType.log,
        target: 'console',
        parameters: {'level': 'info'},
      );
      final restored = Action.fromJson(original.toJson());
      expect(restored.type, ActionType.log);
      expect(restored.target, 'console');
      expect(restored.parameters?['level'], 'info');
    });

    test('Rule 往返保持条件 / 动作 / 优先级 / 开关', () {
      final original = _rule(
        id: 'r-json',
        conditions: [
          _cond(Operator.equals, 'method', 'POST'),
          _cond(Operator.endsWith, 'url', '/login'),
        ],
        actions: [Action(type: ActionType.notify, target: 'toast')],
        priority: RulePriority.high,
        enabled: false,
      );
      final restored = Rule.fromJson(original.toJson());
      expect(restored.id, 'r-json');
      expect(restored.conditions.length, 2);
      expect(restored.actions.length, 1);
      expect(restored.priority, RulePriority.high);
      expect(restored.enabled, isFalse);
    });

    test('未知枚举值回退到默认而非抛异常', () {
      final restored = Rule.fromJson({
        'id': 'x',
        'name': 'x',
        'conditions': [],
        'actions': [],
        'priority': 'not-a-priority',
      });
      expect(restored.priority, RulePriority.normal);
      expect(restored.enabled, isTrue);
    });
  });

  group('Rule 可用性', () {
    test('enabled=false 时不可用', () {
      expect(_rule(enabled: false).isAvailable, isFalse);
    });

    test('已过期时 isExpired 为真且不可用', () {
      final expired = _rule(expiresAt: DateTime.now().subtract(const Duration(minutes: 1)));
      expect(expired.isExpired, isTrue);
      expect(expired.isAvailable, isFalse);
    });

    test('未过期且开启时可用', () {
      final active = _rule(expiresAt: DateTime.now().add(const Duration(minutes: 5)));
      expect(active.isExpired, isFalse);
      expect(active.isAvailable, isTrue);
    });
  });

  group('McpRuleEngine 规则管理', () {
    late McpRuleEngine engine;

    setUp(() {
      engine = McpRuleEngine();
      engine.clearRules();
    });

    tearDown(() => engine.clearRules());

    test('添加 / 读取 / 清空', () {
      engine.addRule(_rule(id: 'a'));
      engine.addRule(_rule(id: 'b'));
      expect(engine.getRules().length, 2);
      engine.clearRules();
      expect(engine.getRules(), isEmpty);
    });

    test('按 id 删除', () {
      engine.addRule(_rule(id: 'a'));
      engine.addRule(_rule(id: 'b'));
      engine.removeRule('a');
      final ids = engine.getRules().map((r) => r.id).toList();
      expect(ids, ['b']);
    });

    test('启用 / 禁用', () {
      engine.addRule(_rule(id: 'a'));
      engine.disableRule('a');
      expect(engine.getRules().single.enabled, isFalse);
      engine.enableRule('a');
      expect(engine.getRules().single.enabled, isTrue);
    });

    test('更新规则', () {
      engine.addRule(_rule(id: 'a'));
      engine.updateRule('a', _rule(id: 'a', enabled: false));
      expect(engine.getRules().single.enabled, isFalse);
    });

    test('高优先级规则排在前面', () {
      engine.addRule(_rule(id: 'low', priority: RulePriority.low));
      engine.addRule(_rule(id: 'critical', priority: RulePriority.critical));
      expect(engine.getRules().first.id, 'critical');
    });
  });

  group('规则评估与动作执行', () {
    late McpRuleEngine engine;

    setUp(() {
      engine = McpRuleEngine();
      engine.clearRules();
    });

    tearDown(() => engine.clearRules());

    test('条件全部匹配时执行动作', () async {
      var hits = 0;
      engine.addRule(_rule(
        id: 'hit',
        conditions: [
          _cond(Operator.equals, 'method', 'GET'),
          _cond(Operator.contains, 'url', 'example'),
        ],
        actions: [Action(type: ActionType.custom, callback: (_, __) async => hits++)],
      ));
      await engine.evaluate({'method': 'GET', 'url': 'https://example.com/a'});
      expect(hits, 1);
    });

    test('任一条件不匹配则不执行动作', () async {
      var hits = 0;
      engine.addRule(_rule(
        id: 'miss',
        conditions: [
          _cond(Operator.equals, 'method', 'POST'),
        ],
        actions: [Action(type: ActionType.custom, callback: (_, __) async => hits++)],
      ));
      await engine.evaluate({'method': 'GET'});
      expect(hits, 0);
    });

    test('被禁用的规则不参与评估', () async {
      var hits = 0;
      engine.addRule(_rule(
        id: 'off',
        enabled: false,
        actions: [Action(type: ActionType.custom, callback: (_, __) async => hits++)],
      ));
      await engine.evaluate({'method': 'GET'});
      expect(hits, 0);
    });

    test('动作抛异常不会中断评估', () async {
      var second = 0;
      engine.addRule(_rule(
        id: 'boom',
        actions: [Action(type: ActionType.custom, callback: (_, __) async => throw StateError('boom'))],
      ));
      engine.addRule(_rule(
        id: 'after',
        actions: [Action(type: ActionType.custom, callback: (_, __) async => second++)],
      ));
      await engine.evaluate({'method': 'GET'});
      expect(second, 1, reason: '前一个规则的动作失败，后面的规则仍应执行');
    });

    test('执行历史记录匹配与跳过，并按 limit 截取', () async {
      engine.addRule(_rule(id: 'm1', conditions: [_cond(Operator.equals, 'method', 'GET')]));
      engine.addRule(_rule(id: 'm2', conditions: [_cond(Operator.equals, 'method', 'POST')]));

      await engine.evaluate({'method': 'GET'});

      // 引擎是单例、历史跨用例累积，因此只断言「本次评估新增的两条」。
      final lastTwo = engine.getExecutionHistory(limit: 2);
      expect(lastTwo.length, 2);
      expect(lastTwo.map((h) => h.ruleId).toList(), ['m1', 'm2']);
      expect(lastTwo.where((h) => h.matched).length, 1);
      expect(engine.getExecutionHistory(limit: 1).length, 1);
    });
  });
}
