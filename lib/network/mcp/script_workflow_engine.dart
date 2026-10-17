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

import 'dart:async';
import 'package:proxypin/network/util/logger.dart';

/// 脚本执行状态
enum ScriptExecutionStatus {
  pending,
  running,
  success,
  failed,
  skipped,
  timeout,
}

/// 脚本执行结果
class ScriptExecutionResult {
  final String scriptId;
  final ScriptExecutionStatus status;
  final dynamic output;
  final String? error;
  final Duration duration;
  final int retryCount;
  final DateTime startedAt;
  final DateTime completedAt;

  ScriptExecutionResult({
    required this.scriptId,
    required this.status,
    this.output,
    this.error,
    required this.duration,
    this.retryCount = 0,
    required this.startedAt,
    required this.completedAt,
  });

  bool get isSuccess => status == ScriptExecutionStatus.success;
  bool get isFailed => status == ScriptExecutionStatus.failed;

  Map<String, dynamic> toJson() {
    return {
      'scriptId': scriptId,
      'status': status.name,
      'output': output,
      'error': error,
      'durationMs': duration.inMilliseconds,
      'retryCount': retryCount,
      'startedAt': startedAt.toIso8601String(),
      'completedAt': completedAt.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'ScriptExecutionResult(scriptId: $scriptId, status: $status, duration: $duration, retryCount: $retryCount)';
  }
}

/// 脚本工作流节点
class WorkflowNode {
  final String id;
  final String scriptId;
  final String scriptContent;
  final String scriptType; // 'dart', 'javascript', 'shell', 'python'
  final Map<String, dynamic> parameters;
  final List<String> dependencies; // 依赖的前置节点 ID
  final bool continueOnError; // 失败时是否继续执行后续节点
  final int maxRetries; // 最大重试次数
  final Duration retryDelay; // 重试间隔
  final Duration? timeout; // 执行超时

  WorkflowNode({
    required this.id,
    required this.scriptId,
    required this.scriptContent,
    this.scriptType = 'dart',
    this.parameters = const {},
    this.dependencies = const [],
    this.continueOnError = false,
    this.maxRetries = 0,
    this.retryDelay = const Duration(seconds: 1),
    this.timeout,
  });

  @override
  String toString() => 'WorkflowNode(id: $id, scriptId: $scriptId, dependencies: $dependencies)';
}

/// 脚本工作流
class ScriptWorkflow {
  final String id;
  final String name;
  final String description;
  final List<WorkflowNode> nodes;
  final bool enabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ScriptWorkflow({
    required this.id,
    required this.name,
    this.description = '',
    required this.nodes,
    this.enabled = true,
    this.createdAt,
    this.updatedAt,
  });

  /// 获取入口节点（没有依赖的节点）
  List<WorkflowNode> get entryNodes {
    final nodeIds = nodes.map((n) => n.id).toSet();
    return nodes.where((node) {
      return node.dependencies.isEmpty || 
             node.dependencies.every((dep) => !nodeIds.contains(dep));
    }).toList();
  }

  /// 获取指定节点的后继节点
  List<WorkflowNode> getSuccessors(String nodeId) {
    return nodes.where((node) => 
      node.dependencies.contains(nodeId)
    ).toList();
  }

  /// 验证工作流是否有效（依赖完整 + 无循环依赖）
  bool validate() {
    final nodeIds = nodes.map((n) => n.id).toSet();

    // 依赖指向已删除的节点时直接判无效。旧实现走 firstWhere(orElse: throw)：
    // registerWorkflow 里 `if (!workflow.validate())` 期待 false，实际会抛
    // 裸 Exception('Node not found')，工作流连注册都进不去，且 entryNodes
    // 又把这种节点当入口放行，两处语义互相矛盾。
    for (final node in nodes) {
      for (final dep in node.dependencies) {
        if (!nodeIds.contains(dep)) return false;
      }
    }

    final visited = <String>{};
    final recStack = <String>{};

    bool hasCycle(String nodeId) {
      if (recStack.contains(nodeId)) return true;
      if (visited.contains(nodeId)) return false;

      visited.add(nodeId);
      recStack.add(nodeId);

      final node = nodes.firstWhere((n) => n.id == nodeId);
      for (final depId in node.dependencies) {
        if (hasCycle(depId)) return true;
      }

      recStack.remove(nodeId);
      return false;
    }

    for (final node in nodes) {
      if (hasCycle(node.id)) return false;
    }

    return true;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'nodes': nodes.map((n) => {
        'id': n.id,
        'scriptId': n.scriptId,
        'scriptType': n.scriptType,
        'dependencies': n.dependencies,
        'continueOnError': n.continueOnError,
        'maxRetries': n.maxRetries,
      }).toList(),
      'enabled': enabled,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

/// 工作流执行上下文
class WorkflowExecutionContext {
  final String workflowId;
  final Map<String, dynamic> variables;
  final Map<String, ScriptExecutionResult> nodeResults;
  final DateTime startedAt;
  DateTime? completedAt;

  WorkflowExecutionContext({
    required this.workflowId,
    Map<String, dynamic>? variables,
    Map<String, ScriptExecutionResult>? nodeResults,
    required this.startedAt,
    this.completedAt,
  })  : variables = variables ?? {},
        nodeResults = nodeResults ?? {};

  /// 获取节点执行结果
  ScriptExecutionResult? getNodeResult(String nodeId) => nodeResults[nodeId];

  /// 检查所有节点是否完成
  bool get isCompleted => completedAt != null;

  /// 获取执行总时长
  Duration get totalDuration {
    final end = completedAt ?? DateTime.now();
    return end.difference(startedAt);
  }

  /// 获取成功的节点数
  int get successCount => 
    nodeResults.values.where((r) => r.isSuccess).length;

  /// 获取失败的节点数
  int get failedCount => 
    nodeResults.values.where((r) => r.isFailed).length;
}

/// 脚本执行回调类型
typedef ScriptExecutor = Future<dynamic> Function(
  String scriptId,
  String scriptContent,
  String scriptType,
  Map<String, dynamic> parameters,
  Duration? timeout,
);

/// 脚本工作流引擎
/// 支持多脚本顺序执行、并行执行、失败重试、条件跳过等高级功能
/// @author wanghongen
/// 2026-08-21
class ScriptWorkflowEngine {
  static final ScriptWorkflowEngine _instance = ScriptWorkflowEngine._internal();
  factory ScriptWorkflowEngine() => _instance;
  ScriptWorkflowEngine._internal();

  /// 便捷单例访问
  static ScriptWorkflowEngine get instance => _instance;

  // 工作流存储
  final Map<String, ScriptWorkflow> _workflows = {};

  // 执行回调（由外部注入）
  ScriptExecutor? _executor;

  // 执行中的工作流
  final Map<String, WorkflowExecutionContext> _runningWorkflows = {};

  // 执行历史
  final List<WorkflowExecutionContext> _executionHistory = [];
  static const int _maxHistorySize = 50;

  // ==================== 工作流管理 ====================

  /// 设置脚本执行器（由外部注入实际执行逻辑）
  void setExecutor(ScriptExecutor executor) {
    _executor = executor;
    logger.i('脚本执行器已设置');
  }

  /// 注册工作流
  void registerWorkflow(ScriptWorkflow workflow) {
    if (!workflow.validate()) {
      throw ArgumentError('工作流验证失败：存在循环依赖');
    }
    _workflows[workflow.id] = workflow;
    logger.i('注册工作流：${workflow.name} (${workflow.id})');
  }

  /// 注销工作流
  void unregisterWorkflow(String workflowId) {
    _workflows.remove(workflowId);
    logger.d('注销工作流：$workflowId');
  }

  /// 获取工作流
  ScriptWorkflow? getWorkflow(String workflowId) => _workflows[workflowId];

  /// 获取所有工作流
  List<ScriptWorkflow> getWorkflows() => _workflows.values.toList();

  /// 启用工作流
  void enableWorkflow(String workflowId) {
    final workflow = _workflows[workflowId];
    if (workflow != null) {
      _workflows[workflowId] = ScriptWorkflow(
        id: workflow.id,
        name: workflow.name,
        description: workflow.description,
        nodes: workflow.nodes,
        enabled: true,
        createdAt: workflow.createdAt,
        updatedAt: DateTime.now(),
      );
    }
  }

  /// 禁用工作流
  void disableWorkflow(String workflowId) {
    final workflow = _workflows[workflowId];
    if (workflow != null) {
      _workflows[workflowId] = ScriptWorkflow(
        id: workflow.id,
        name: workflow.name,
        description: workflow.description,
        nodes: workflow.nodes,
        enabled: false,
        createdAt: workflow.createdAt,
        updatedAt: DateTime.now(),
      );
    }
  }

  // ==================== 工作流执行 ====================

  /// 执行工作流
  Future<WorkflowExecutionContext> executeWorkflow(
    String workflowId, {
    Map<String, dynamic>? variables,
  }) async {
    final workflow = _workflows[workflowId];
    if (workflow == null) {
      throw ArgumentError('工作流不存在：$workflowId');
    }

    if (!workflow.enabled) {
      throw StateError('工作流已禁用：$workflowId');
    }

    if (_executor == null) {
      throw StateError('脚本执行器未设置');
    }

    logger.i('开始执行工作流：${workflow.name}');

    final context = WorkflowExecutionContext(
      workflowId: workflowId,
      variables: variables,
      startedAt: DateTime.now(),
    );

    _runningWorkflows[workflowId] = context;

    try {
      // 按拓扑顺序执行节点
      await _executeNodesTopologically(workflow, context);
    } catch (e, stackTrace) {
      logger.e('工作流执行失败：${workflow.name}', error: e, stackTrace: stackTrace);
    } finally {
      context.completedAt = DateTime.now();
      _runningWorkflows.remove(workflowId);

      // 记录执行历史
      _executionHistory.add(context);
      if (_executionHistory.length > _maxHistorySize) {
        _executionHistory.removeAt(0);
      }
    }

    logger.i('工作流执行完成：${workflow.name}, 成功：${context.successCount}/${workflow.nodes.length}');
    return context;
  }

  /// 按拓扑顺序执行节点
  Future<void> _executeNodesTopologically(
    ScriptWorkflow workflow,
    WorkflowExecutionContext context,
  ) async {
    final executed = <String>{};
    final pending = workflow.nodes.toSet();

    while (pending.isNotEmpty) {
      // 找出所有可以执行的节点（依赖已满足）
      final readyNodes = pending.where((node) {
        return node.dependencies.every((dep) => executed.contains(dep));
      }).toList();

      if (readyNodes.isEmpty) {
        logger.w('工作流执行停滞：存在未满足的依赖');
        break;
      }

      // 并行执行所有就绪节点
      final futures = readyNodes.map((node) async {
        pending.remove(node);
        await _executeNodeWithRetry(workflow, node, context);
        executed.add(node.id);
      });

      await Future.wait(futures);
    }
  }

  /// 执行节点（带重试）
  Future<void> _executeNodeWithRetry(
    ScriptWorkflow workflow,
    WorkflowNode node,
    WorkflowExecutionContext context,
  ) async {
    // 检查依赖是否成功
    for (final depId in node.dependencies) {
      final depResult = context.nodeResults[depId];
      if (depResult == null || depResult.isFailed) {
        // 依赖失败、但该依赖自己声明了 continueOnError：视为「可继续」。
        // 这是 continueOnError 唯一真正生效的地方（此前它被错用在 status 赋值上，
        // 结果既没让下游继续、又把状态留在 running）。
        WorkflowNode? depNode;
        for (final n in workflow.nodes) {
          if (n.id == depId) {
            depNode = n;
            break;
          }
        }
        if (depResult != null && depResult.isFailed && (depNode?.continueOnError ?? false)) {
          logger.d('节点 ${node.id} 的依赖 $depId 失败，但它声明了 continueOnError，继续执行');
          continue;
        }
        logger.w('跳过节点 ${node.id}：依赖 $depId 执行失败');
        context.nodeResults[node.id] = ScriptExecutionResult(
          scriptId: node.scriptId,
          status: ScriptExecutionStatus.skipped,
          duration: Duration.zero,
          startedAt: DateTime.now(),
          completedAt: DateTime.now(),
        );
        return;
      }
    }

    int attempts = 0;
    final startedAt = DateTime.now();
    ScriptExecutionStatus status = ScriptExecutionStatus.pending;
    dynamic output;
    String? error;

    while (attempts <= node.maxRetries) {
      try {
        logger.d('执行节点 ${node.id} (尝试 ${attempts + 1}/${node.maxRetries + 1})');
        status = ScriptExecutionStatus.running;

        // node.timeout 此前只作为参数透传给 executor，引擎自身不计时：
        // executor 不实现超时（或脚本卡在 JS promise / 网络 IO）时
        // 该节点永久挂起，工作流永不 complete，后台仍占用运行时。
        final timeout = node.timeout;
        output = timeout == null
            ? await _executeNode(node, context)
            : await _executeNode(node, context).timeout(timeout);
        status = ScriptExecutionStatus.success;
        break;
      } on TimeoutException catch (e) {
        attempts++;
        status = ScriptExecutionStatus.timeout;
        error = '执行超时：${e.message ?? e}';
        logger.w('节点 ${node.id} 执行超时 (尝试 $attempts)', error: e);
        if (attempts <= node.maxRetries) {
          await Future.delayed(node.retryDelay);
        }
      } catch (e, stackTrace) {
        attempts++;
        error = e.toString();
        logger.w('节点 ${node.id} 执行失败 (尝试 $attempts): $e', stackTrace: stackTrace);

        if (attempts <= node.maxRetries) {
          logger.d('等待 ${node.retryDelay.inMilliseconds}ms 后重试...');
          await Future.delayed(node.retryDelay);
        }
      }
    }

    final completedAt = DateTime.now();
    // 节点失败就是 failed。continueOnError 的语义是「允许下游节点继续执行」，
    // 不是「把失败伪装成未失败」——此前这里带 `&& !node.continueOnError`，
    // 导致这类节点的 status 永远停在 running（非法终态），且下游依赖检查用
    // isFailed 判断时恒为 false。下游放宽见上方依赖检查。
    if (status != ScriptExecutionStatus.success && status != ScriptExecutionStatus.timeout) {
      status = ScriptExecutionStatus.failed;
    }

    context.nodeResults[node.id] = ScriptExecutionResult(
      scriptId: node.scriptId,
      status: status,
      output: output,
      error: error,
      duration: completedAt.difference(startedAt),
      retryCount: attempts > 0 ? attempts - 1 : 0,
      startedAt: startedAt,
      completedAt: completedAt,
    );
  }

  /// 执行单个节点
  Future<dynamic> _executeNode(
    WorkflowNode node,
    WorkflowExecutionContext context,
  ) async {
    if (_executor == null) {
      throw StateError('脚本执行器未设置');
    }

    // 解析变量
    final resolvedContent = _resolveVariables(node.scriptContent, context.variables);
    final resolvedParams = _resolveVariablesInMap(node.parameters, context.variables);

    return await _executor!(
      node.scriptId,
      resolvedContent,
      node.scriptType,
      resolvedParams,
      node.timeout,
    );
  }

  /// 解析字符串中的变量
  String _resolveVariables(String content, Map<String, dynamic> variables) {
    String result = content;
    variables.forEach((key, value) {
      result = result.replaceAll('{{$key}}', value.toString());
    });
    return result;
  }

  /// 解析 Map 中的变量
  Map<String, dynamic> _resolveVariablesInMap(
    Map<String, dynamic> params,
    Map<String, dynamic> variables,
  ) {
    final resolved = <String, dynamic>{};
    params.forEach((key, value) {
      if (value is String) {
        resolved[key] = _resolveVariables(value, variables);
      } else if (value is Map) {
        resolved[key] = _resolveVariablesInMap(
          Map<String, dynamic>.from(value),
          variables,
        );
      } else {
        resolved[key] = value;
      }
    });
    return resolved;
  }

  // ==================== 执行历史 ====================

  /// 获取执行历史
  List<WorkflowExecutionContext> getExecutionHistory({int? limit}) {
    if (limit == null) return List.unmodifiable(_executionHistory);
    final start = _executionHistory.length - limit.clamp(0, _executionHistory.length);
    return _executionHistory.sublist(start);
  }

  /// 获取正在运行的工作流
  Map<String, WorkflowExecutionContext> getRunningWorkflows() {
    return Map.unmodifiable(_runningWorkflows);
  }

  // ==================== 工作流构建器 ====================

  /// 创建顺序执行工作流
  static ScriptWorkflow createSequentialWorkflow({
    required String id,
    required String name,
    required List<WorkflowNode> nodes,
    String description = '',
  }) {
    // 为每个节点添加前一个节点的依赖
    final linkedNodes = <WorkflowNode>[];
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final dependencies = i > 0 ? [nodes[i - 1].id] : <String>[];
      linkedNodes.add(WorkflowNode(
        id: node.id,
        scriptId: node.scriptId,
        scriptContent: node.scriptContent,
        scriptType: node.scriptType,
        parameters: node.parameters,
        dependencies: dependencies,
        continueOnError: node.continueOnError,
        maxRetries: node.maxRetries,
        retryDelay: node.retryDelay,
        timeout: node.timeout,
      ));
    }

    return ScriptWorkflow(
      id: id,
      name: name,
      description: description,
      nodes: linkedNodes,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// 创建并行执行工作流
  static ScriptWorkflow createParallelWorkflow({
    required String id,
    required String name,
    required List<WorkflowNode> nodes,
    String description = '',
  }) {
    // 所有节点都没有依赖，可以并行执行
    return ScriptWorkflow(
      id: id,
      name: name,
      description: description,
      nodes: nodes,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}

/// 使用示例
class ScriptWorkflowEngineExample {
  /// 示例：顺序执行工作流（带重试）
  static void setupSequentialWorkflow() {
    final engine = ScriptWorkflowEngine();

    final workflow = ScriptWorkflowEngine.createSequentialWorkflow(
      id: 'api_test_workflow',
      name: 'API 测试工作流',
      description: '依次执行登录、获取数据、验证结果',
      nodes: [
        WorkflowNode(
          id: 'login',
          scriptId: 'login_script',
          scriptContent: '''
Future<Map<String, dynamic>> onRequest() async {
  // 登录脚本
  return {'token': 'abc123'};
}
''',
          scriptType: 'dart',
          maxRetries: 3,
          retryDelay: const Duration(seconds: 2),
        ),
        WorkflowNode(
          id: 'fetch_data',
          scriptId: 'fetch_script',
          scriptContent: '''
Future<Map<String, dynamic>> onRequest(Map<String, dynamic> context) async {
  // 使用 token 获取数据
  final token = context['token'];
  return {'data': 'sample'};
}
''',
          scriptType: 'dart',
          dependencies: ['login'],
          maxRetries: 2,
        ),
        WorkflowNode(
          id: 'validate',
          scriptId: 'validate_script',
          scriptContent: '''
Future<bool> onRequest(Map<String, dynamic> context) async {
  // 验证数据
  return context['data'] != null;
}
''',
          scriptType: 'dart',
          dependencies: ['fetch_data'],
        ),
      ],
    );

    engine.registerWorkflow(workflow);
  }

  /// 示例：并行执行工作流
  static void setupParallelWorkflow() {
    final engine = ScriptWorkflowEngine();

    final workflow = ScriptWorkflowEngine.createParallelWorkflow(
      id: 'parallel_check',
      name: '并行健康检查',
      description: '同时检查多个 API 端点',
      nodes: [
        WorkflowNode(
          id: 'check_api1',
          scriptId: 'health_check',
          scriptContent: '// 检查 API 1',
          scriptType: 'dart',
        ),
        WorkflowNode(
          id: 'check_api2',
          scriptId: 'health_check',
          scriptContent: '// 检查 API 2',
          scriptType: 'dart',
        ),
        WorkflowNode(
          id: 'check_api3',
          scriptId: 'health_check',
          scriptContent: '// 检查 API 3',
          scriptType: 'dart',
        ),
      ],
    );

    engine.registerWorkflow(workflow);
  }

  /// 示例：带变量替换的工作流
  static void setupWorkflowWithVariables() {
    final engine = ScriptWorkflowEngine();

    final workflow = ScriptWorkflow(
      id: 'variable_workflow',
      name: '变量替换工作流',
      nodes: [
        WorkflowNode(
          id: 'request',
          scriptId: 'api_request',
          scriptContent: '''
// 使用变量 {{baseUrl}} 和 {{endpoint}}
Future<void> onRequest() async {
  final url = '{{baseUrl}}/{{endpoint}}';
  print('Requesting: \$url');
}
''',
          scriptType: 'dart',
          parameters: {'baseUrl': 'https://api.example.com'},
        ),
      ],
    );

    engine.registerWorkflow(workflow);

    // 执行时传入变量
    // engine.executeWorkflow('variable_workflow', variables: {
    //   'endpoint': 'users',
    // });
  }
}
