/*
 * 脚本工作流引擎单元测试
 *
 * 对齐当前 ScriptWorkflowEngine 的真实 API：
 *   registerWorkflow / unregisterWorkflow / getWorkflow / getWorkflows
 *   enableWorkflow / disableWorkflow / setExecutor / executeWorkflow / getExecutionHistory
 * （旧版本曾使用 WorkflowDefinition / createWorkflow / listWorkflows / ScriptType 等已不存在的类型与方法，
 *   本文件已重写为与实现一致。）
 *
 * 覆盖：注册与检索、循环依赖拒绝、拓扑顺序、并行执行、失败重试、依赖失败跳过、变量替换、执行历史。
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/mcp/script_workflow_engine.dart';

ScriptWorkflow buildWorkflow(String id, List<WorkflowNode> nodes, {bool enabled = true}) =>
    ScriptWorkflow(id: id, name: 'wf-$id', nodes: nodes, enabled: enabled);

WorkflowNode node(
  String id, {
  List<String> deps = const [],
  int maxRetries = 0,
  Duration retryDelay = const Duration(milliseconds: 1),
  String content = '',
  Map<String, dynamic> parameters = const {},
}) =>
    WorkflowNode(
      id: id,
      scriptId: id,
      scriptContent: content,
      scriptType: 'javascript',
      dependencies: deps,
      maxRetries: maxRetries,
      retryDelay: retryDelay,
      parameters: parameters,
    );

void main() {
  late ScriptWorkflowEngine engine;

  setUp(() {
    // engine 是单例，测试间清空已注册的工作流，避免相互污染。
    engine = ScriptWorkflowEngine();
    for (final wf in engine.getWorkflows()) {
      engine.unregisterWorkflow(wf.id);
    }
    engine.setExecutor(
      (scriptId, scriptContent, scriptType, parameters, timeout) async => scriptId,
    );
  });

  group('工作流注册与检索', () {
    test('注册后可检索，注销后消失', () {
      engine.registerWorkflow(buildWorkflow('wf_1', [node('n1')]));
      expect(engine.getWorkflows().length, 1);
      expect(engine.getWorkflow('wf_1')?.name, 'wf-wf_1');

      engine.unregisterWorkflow('wf_1');
      expect(engine.getWorkflow('wf_1'), isNull);
      expect(engine.getWorkflows(), isEmpty);
    });

    test('启用 / 禁用切换', () {
      engine.registerWorkflow(buildWorkflow('wf_2', [node('n1')]));
      engine.disableWorkflow('wf_2');
      expect(engine.getWorkflow('wf_2')?.enabled, false);

      engine.enableWorkflow('wf_2');
      expect(engine.getWorkflow('wf_2')?.enabled, true);
    });
  });

  group('工作流结构', () {
    test('无依赖时 validate 通过，entryNodes 覆盖全部节点', () {
      final wf = buildWorkflow('wf_3', [node('a'), node('b')]);
      expect(wf.validate(), true);
      expect(wf.entryNodes.map((n) => n.id).toSet(), {'a', 'b'});
    });

    test('getSuccessors 返回直接后继', () {
      final wf = buildWorkflow('wf_4', [
        node('a'),
        node('b', deps: ['a']),
        node('c', deps: ['a']),
      ]);
      expect(wf.getSuccessors('a').map((n) => n.id).toSet(), {'b', 'c'});
    });

    test('循环依赖：validate 返回 false，注册被拒（ArgumentError）', () {
      final wf = buildWorkflow('wf_5', [node('a', deps: ['b']), node('b', deps: ['a'])]);
      expect(wf.validate(), false);
      expect(() => engine.registerWorkflow(wf), throwsA(isA<ArgumentError>()));
    });
  });

  group('工作流执行', () {
    test('依赖链按拓扑顺序执行', () async {
      final order = <String>[];
      engine.setExecutor((scriptId, scriptContent, scriptType, parameters, timeout) async {
        order.add(scriptId);
        return scriptId;
      });
      engine.registerWorkflow(buildWorkflow('wf_6', [
        node('step_1'),
        node('step_2', deps: ['step_1']),
        node('step_3', deps: ['step_2']),
      ]));

      final ctx = await engine.executeWorkflow('wf_6');
      expect(ctx.successCount, 3);
      expect(order, ['step_1', 'step_2', 'step_3']);
      expect(ctx.isCompleted, true);
    });

    test('无依赖节点并行执行（总耗时远小于串行累加）', () async {
      engine.setExecutor((scriptId, scriptContent, scriptType, parameters, timeout) async {
        await Future.delayed(const Duration(milliseconds: 200));
        return scriptId;
      });
      engine.registerWorkflow(buildWorkflow('wf_7', [node('p1'), node('p2'), node('p3')]));

      final sw = Stopwatch()..start();
      final ctx = await engine.executeWorkflow('wf_7');
      sw.stop();

      expect(ctx.successCount, 3);
      // 三个 200ms 无依赖节点：引擎用 Future.wait 并行执行，总耗时 ≈ 200ms；
      // 若退化为串行则 ≥ 600ms。取 500ms 作阈值，兼顾调度余量与区分度。
      expect(sw.elapsedMilliseconds, lessThan(500));
    });

    test('失败节点按 maxRetries 重试后成功', () async {
      var attempts = 0;
      engine.setExecutor((scriptId, scriptContent, scriptType, parameters, timeout) async {
        attempts++;
        if (attempts < 3) throw StateError('boom');
        return scriptId;
      });
      engine.registerWorkflow(buildWorkflow('wf_8', [node('n1', maxRetries: 2)]));

      final ctx = await engine.executeWorkflow('wf_8');
      expect(attempts, 3); // 首次 + 2 次重试
      expect(ctx.successCount, 1);
      expect(ctx.nodeResults['n1']?.isSuccess, true);
    });

    test('依赖节点失败时下游被跳过', () async {
      engine.setExecutor((scriptId, scriptContent, scriptType, parameters, timeout) async {
        if (scriptId == 'bad') throw StateError('fail');
        return scriptId;
      });
      engine.registerWorkflow(buildWorkflow('wf_9', [
        node('bad'),
        node('good', deps: ['bad']),
      ]));

      final ctx = await engine.executeWorkflow('wf_9');
      expect(ctx.nodeResults['bad']?.isFailed, true);
      expect(ctx.nodeResults['good']?.status, ScriptExecutionStatus.skipped);
      expect(ctx.failedCount, 1);
    });

    test('变量在脚本内容与参数中被替换', () async {
      String? seenContent;
      Map<String, dynamic>? seenParams;
      engine.setExecutor((scriptId, scriptContent, scriptType, parameters, timeout) async {
        seenContent = scriptContent;
        seenParams = parameters;
        return scriptId;
      });
      engine.registerWorkflow(buildWorkflow('wf_10', [
        node('n1', content: 'GET {{baseUrl}}/api', parameters: {'token': '{{token}}'}),
      ]));

      await engine.executeWorkflow('wf_10', variables: {
        'baseUrl': 'https://example.com',
        'token': 'T-1',
      });
      expect(seenContent, 'GET https://example.com/api');
      expect(seenParams?['token'], 'T-1');
    });

    test('执行已禁用的工作流抛 StateError', () async {
      engine.registerWorkflow(buildWorkflow('wf_11', [node('n1')]));
      engine.disableWorkflow('wf_11');
      await expectLater(engine.executeWorkflow('wf_11'), throwsA(isA<StateError>()));
    });

    test('执行不存在的工作流抛 ArgumentError', () async {
      await expectLater(engine.executeWorkflow('nope'), throwsA(isA<ArgumentError>()));
    });
  });

  group('执行历史', () {
    test('执行后写入历史，可按条数取最近记录', () async {
      engine.registerWorkflow(buildWorkflow('wf_12', [node('n1')]));
      await engine.executeWorkflow('wf_12');
      await engine.executeWorkflow('wf_12');

      final all = engine.getExecutionHistory();
      expect(all.length, greaterThanOrEqualTo(2));
      expect(all.last.isCompleted, true);

      final recent = engine.getExecutionHistory(limit: 1);
      expect(recent.length, 1);
    });
  });
}
