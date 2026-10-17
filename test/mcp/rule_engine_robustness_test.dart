import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/mcp/mcp_rule_engine.dart';
import 'package:proxypin/network/mcp/script_workflow_engine.dart';

/// 规则引擎 / 工作流结构健壮性回归。
void main() {
  group('规则条件：matches 运算符', () {
    Condition matches(String pattern) => Condition(
          type: ConditionType.custom,
          field: 'x',
          operator: Operator.matches,
          value: pattern,
        );

    test('非法正则（"(" / "[a-"）返回 false，不抛 FormatException', () {
      // 旧实现直接 RegExp(value)，抛出的异常会让 evaluate 的 every() 中断，
      // 后续所有规则（含 critical）都不再评估。
      expect(matches('(').evaluate({'x': 'abc'}), isFalse);
      expect(matches('[a-').evaluate({'x': 'abc'}), isFalse);
    });

    test('合法正则仍正常匹配', () {
      expect(matches(r'^a.c$').evaluate({'x': 'abc'}), isTrue);
      expect(matches('^z').evaluate({'x': 'abc'}), isFalse);
    });
  });

  group('工作流结构：依赖完整性', () {
    WorkflowNode node(String id, {List<String> deps = const []}) => WorkflowNode(
          id: id,
          scriptId: id,
          scriptContent: '',
          scriptType: 'javascript',
          dependencies: deps,
        );

    test('依赖指向已删除节点时 validate 返回 false（而不是抛 Exception）', () {
      final wf = ScriptWorkflow(id: 'wf_missing_dep', name: 'missing-dep', nodes: [node('b', deps: ['a'])]);
      expect(wf.validate(), isFalse);
    });

    test('注册缺依赖的工作流被明确拒绝（ArgumentError）', () {
      final engine = ScriptWorkflowEngine();
      final wf = ScriptWorkflow(id: 'wf_missing_dep_2', name: 'missing-dep-2', nodes: [node('b', deps: ['a'])]);
      expect(() => engine.registerWorkflow(wf), throwsA(isA<ArgumentError>()));
      expect(engine.getWorkflow('wf_missing_dep_2'), isNull);
    });
  });
}
