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

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:proxypin/network/mcp/script_workflow_engine.dart';
import 'package:proxypin/ui/component/guide_center.dart';
import 'package:toastification/toastification.dart';

/// 脚本工作流管理器页面
/// 用于管理脚本工作流的创建、编辑、执行和监控
class ScriptWorkflowManagerPage extends StatefulWidget {
  const ScriptWorkflowManagerPage({super.key});

  @override
  State<ScriptWorkflowManagerPage> createState() =>
      _ScriptWorkflowManagerPageState();
}

class _ScriptWorkflowManagerPageState extends State<ScriptWorkflowManagerPage> {
  final ScriptWorkflowEngine _engine = ScriptWorkflowEngine.instance;
  final TextEditingController _workflowNameController = TextEditingController();
  final TextEditingController _nodeScriptController = TextEditingController();
  final TextEditingController _nodeTimeoutController = TextEditingController();
  final TextEditingController _retryCountController = TextEditingController();
  final TextEditingController _retryDelayController = TextEditingController();

  ScriptWorkflow? _editingWorkflow;
  WorkflowNode? _editingNode;
  bool _isExecuting = false;
  ExecutionHistory? _currentExecution;

  @override
  void dispose() {
    _workflowNameController.dispose();
    _nodeScriptController.dispose();
    _nodeTimeoutController.dispose();
    _retryCountController.dispose();
    _retryDelayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('脚本工作流管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '使用教程',
            onPressed: () => showGuideArticle(context, 'workflow_tutorial'),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建工作流',
            onPressed: _showCreateWorkflowDialog,
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: '执行选中工作流',
            onPressed: _isExecuting ? null : _executeSelectedWorkflow,
          ),
        ],
      ),
      body: Row(
        children: [
          // 左侧：工作流列表
          Expanded(
            flex: 2,
            child: _buildWorkflowList(),
          ),
          // 右侧：工作流详情
          Expanded(
            flex: 3,
            child: _buildWorkflowDetail(),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowList() {
    final workflows = _engine.listWorkflows();
    
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(
            '工作流列表',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: workflows.isEmpty
              ? const Center(
                  child: Text('暂无工作流，点击右上角 + 创建'),
                )
              : ListView.builder(
                  itemCount: workflows.length,
                  itemBuilder: (context, index) {
                    final workflow = workflows[index];
                    final isSelected = _editingWorkflow?.id == workflow.id;
                    return ListTile(
                      title: Text(workflow.name),
                      subtitle: Text(
                        '${workflow.nodes.length} 个节点 | '
                        '${workflow.executionHistory.where((h) => h.status == ExecutionStatus.success).length} 次成功',
                      ),
                      selected: isSelected,
                      onTap: () {
                        setState(() {
                          _editingWorkflow = workflow;
                        });
                      },
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            _showEditWorkflowDialog(workflow);
                          } else if (value == 'delete') {
                            _confirmDeleteWorkflow(workflow);
                          } else if (value == 'duplicate') {
                            _duplicateWorkflow(workflow);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('编辑'),
                          ),
                          const PopupMenuItem(
                            value: 'duplicate',
                            child: Text('复制'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('删除', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildWorkflowDetail() {
    if (_editingWorkflow == null) {
      return const Center(
        child: Text('请选择一个工作流查看详情'),
      );
    }

    final workflow = _editingWorkflow!;

    return Column(
      children: [
        // 工作流信息卡片
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workflow.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text('描述：${workflow.description ?? "无"}'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildStatChip(
                      '节点数',
                      '${workflow.nodes.length}',
                      Icons.folder,
                    ),
                    const SizedBox(width: 8),
                    _buildStatChip(
                      '执行次数',
                      '${workflow.executionHistory.length}',
                      Icons.history,
                    ),
                    const SizedBox(width: 8),
                    _buildStatChip(
                      '成功率',
                      '${_calculateSuccessRate(workflow)}%',
                      Icons.trending_up,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // 节点列表
        Expanded(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  '工作流节点',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: workflow.nodes.length,
                  itemBuilder: (context, index) {
                    final node = workflow.nodes[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: ExpansionTile(
                        title: Text('${index + 1}. ${node.name}'),
                        subtitle: Text(
                          '类型：${node.type} | 超时：${node.timeoutSeconds}s | '
                          '重试：${node.retryCount}次',
                        ),
                        leading: CircleAvatar(
                          backgroundColor: _getNodeStatusColor(node),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              _showEditNodeDialog(node);
                            } else if (value == 'delete') {
                              _confirmDeleteNode(node);
                            } else if (value == 'move_up' && index > 0) {
                              _moveNode(workflow, node, -1);
                            } else if (value == 'move_down' &&
                                index < workflow.nodes.length - 1) {
                              _moveNode(workflow, node, 1);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('编辑'),
                            ),
                            PopupMenuItem(
                              value: 'move_up',
                              enabled: index > 0,
                              child: const Text('上移'),
                            ),
                            PopupMenuItem(
                              value: 'move_down',
                              enabled: index < workflow.nodes.length - 1,
                              child: const Text('下移'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('删除', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('脚本内容:', style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    node.script,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                if (node.dependencies.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  const Text('依赖节点:', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: node.dependencies
                                        .map((dep) => Chip(
                                              label: Text(dep,
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: Theme.of(context).colorScheme.onPrimaryContainer)),
                                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                            ))
                                        .toList(),
                                  ),
                                ],
                                if (node.variables.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  const Text('变量:', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: node.variables.entries
                                        .map((e) => Chip(
                                              label: Text('${e.key}={{${e.value}}}',
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: Theme.of(context).colorScheme.onSecondaryContainer)),
                                              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                                            ))
                                        .toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // 执行历史
        if (_editingWorkflow!.executionHistory.isNotEmpty)
          Container(
            height: 150,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    '最近执行记录',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: _editingWorkflow!.executionHistory
                        .take(5)
                        .map((history) => _buildHistoryTile(history))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),

        // 底部操作按钮
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('添加节点'),
                  onPressed: () => _showAddNodeDialog(workflow),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: _isExecuting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_isExecuting ? '执行中...' : '执行工作流'),
                onPressed: _isExecuting ? null : () => _executeWorkflow(workflow),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatChip(String label, String value, IconData icon) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text('$label: $value', style: const TextStyle(fontSize: 12)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildHistoryTile(ExecutionHistory history) {
    return ListTile(
      dense: true,
      leading: Icon(
        history.status == ExecutionStatus.success
            ? Icons.check_circle
            : history.status == ExecutionStatus.failed
                ? Icons.error
                : Icons.pending,
        color: history.status == ExecutionStatus.success
            ? Colors.green
            : history.status == ExecutionStatus.failed
                ? Colors.red
                : Colors.orange,
      ),
      title: Text(
        history.startedAt.toString().substring(0, 19),
        style: const TextStyle(fontSize: 12),
      ),
      subtitle: Text(
        '耗时：${history.totalDuration.inMilliseconds}ms | '
        '成功：${history.successCount}/${history.totalCount}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: history.errorMessage != null
          ? IconButton(
              icon: const Icon(Icons.info_outline, size: 16),
              onPressed: () => _showErrorDialog(history.errorMessage!),
            )
          : null,
    );
  }

  Color _getNodeStatusColor(WorkflowNode node) {
    // 根据节点执行状态返回颜色
    return Colors.blue;
  }

  int _calculateSuccessRate(ScriptWorkflow workflow) {
    if (workflow.executionHistory.isEmpty) return 0;
    final successCount = workflow.executionHistory
        .where((h) => h.status == ExecutionStatus.success)
        .length;
    return (successCount / workflow.executionHistory.length * 100).round();
  }

  // ==================== 对话框方法 ====================

  void _showCreateWorkflowDialog() {
    _workflowNameController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建工作流'),
        content: TextField(
          controller: _workflowNameController,
          decoration: const InputDecoration(
            labelText: '工作流名称',
            hintText: '例如：自动登录流程',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_workflowNameController.text.isNotEmpty) {
                final workflow = ScriptWorkflow(
                  name: _workflowNameController.text,
                  description: '',
                  nodes: [],
                );
                _engine.addWorkflow(workflow);
                setState(() {});
                Navigator.pop(context);
                toastification.show(
                  title: const Text('创建成功'),
                  type: ToastificationType.success,
                );
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _showEditWorkflowDialog(ScriptWorkflow workflow) {
    _workflowNameController.text = workflow.name;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑工作流'),
        content: TextField(
          controller: _workflowNameController,
          decoration: const InputDecoration(
            labelText: '工作流名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_workflowNameController.text.isNotEmpty) {
                workflow.name = _workflowNameController.text;
                setState(() {});
                Navigator.pop(context);
                toastification.show(
                  title: const Text('保存成功'),
                  type: ToastificationType.success,
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteWorkflow(ScriptWorkflow workflow) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除工作流 "${workflow.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              _engine.removeWorkflow(workflow.id);
              if (_editingWorkflow?.id == workflow.id) {
                setState(() {
                  _editingWorkflow = null;
                });
              }
              Navigator.pop(context);
              toastification.show(
                title: const Text('删除成功'),
                type: ToastificationType.success,
              );
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _duplicateWorkflow(ScriptWorkflow workflow) {
    final duplicated = ScriptWorkflow(
      name: '${workflow.name} (副本)',
      description: workflow.description,
      nodes: workflow.nodes.map((node) => WorkflowNode(
        id: DateTime.now().millisecondsSinceEpoch.toString() + node.id,
        name: node.name,
        type: node.type,
        script: node.script,
        timeoutSeconds: node.timeoutSeconds,
        retryCount: node.retryCount,
        retryDelaySeconds: node.retryDelaySeconds,
        dependencies: List.from(node.dependencies),
        variables: Map.from(node.variables),
      )).toList(),
    );
    _engine.addWorkflow(duplicated);
    setState(() {});
    toastification.show(
      title: const Text('复制成功'),
      type: ToastificationType.success,
    );
  }

  void _showAddNodeDialog(ScriptWorkflow workflow) {
    _nodeScriptController.clear();
    _nodeTimeoutController.text = '30';
    _retryCountController.text = '3';
    _retryDelayController.text = '1';
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加节点'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: '节点名称',
                    hintText: '例如：执行登录脚本',
                  ),
                  onChanged: (value) {
                    // 可以在这里保存节点名称
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nodeScriptController,
                  decoration: const InputDecoration(
                    labelText: '脚本内容',
                    hintText: '输入 JavaScript 或 Dart 脚本',
                  ),
                  maxLines: 5,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nodeTimeoutController,
                  decoration: const InputDecoration(
                    labelText: '超时时间 (秒)',
                    hintText: '30',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _retryCountController,
                  decoration: const InputDecoration(
                    labelText: '重试次数',
                    hintText: '3',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _retryDelayController,
                  decoration: const InputDecoration(
                    labelText: '重试间隔 (秒)',
                    hintText: '1',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                final node = WorkflowNode(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: '节点 ${workflow.nodes.length + 1}',
                  type: NodeType.script,
                  script: _nodeScriptController.text,
                  timeoutSeconds: int.tryParse(_nodeTimeoutController.text) ?? 30,
                  retryCount: int.tryParse(_retryCountController.text) ?? 3,
                  retryDelaySeconds: int.tryParse(_retryDelayController.text) ?? 1,
                );
                workflow.addNode(node);
                setState(() {});
                Navigator.pop(context);
                toastification.show(
                  title: const Text('添加成功'),
                  type: ToastificationType.success,
                );
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditNodeDialog(WorkflowNode node) {
    _nodeScriptController.text = node.script;
    _nodeTimeoutController.text = node.timeoutSeconds.toString();
    _retryCountController.text = node.retryCount.toString();
    _retryDelayController.text = node.retryDelaySeconds.toString();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑节点'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: '节点名称',
                  initialValue: node.name,
                ),
                onChanged: (value) => node.name = value,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nodeScriptController,
                decoration: const InputDecoration(
                  labelText: '脚本内容',
                ),
                maxLines: 5,
                onChanged: (value) => node.script = value,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nodeTimeoutController,
                decoration: const InputDecoration(
                  labelText: '超时时间 (秒)',
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) => node.timeoutSeconds = int.tryParse(value) ?? 30,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _retryCountController,
                decoration: const InputDecoration(
                  labelText: '重试次数',
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) => node.retryCount = int.tryParse(value) ?? 3,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _retryDelayController,
                decoration: const InputDecoration(
                  labelText: '重试间隔 (秒)',
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) => node.retryDelaySeconds = int.tryParse(value) ?? 1,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              node.script = _nodeScriptController.text;
              node.timeoutSeconds = int.tryParse(_nodeTimeoutController.text) ?? 30;
              node.retryCount = int.tryParse(_retryCountController.text) ?? 3;
              node.retryDelaySeconds = int.tryParse(_retryDelayController.text) ?? 1;
              setState(() {});
              Navigator.pop(context);
              toastification.show(
                title: const Text('保存成功'),
                type: ToastificationType.success,
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteNode(WorkflowNode node) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除节点 "${node.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              _editingWorkflow?.removeNode(node.id);
              setState(() {});
              Navigator.pop(context);
              toastification.show(
                title: const Text('删除成功'),
                type: ToastificationType.success,
              );
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _moveNode(ScriptWorkflow workflow, WorkflowNode node, int offset) {
    final index = workflow.nodes.indexOf(node);
    final newIndex = index + offset;
    if (newIndex >= 0 && newIndex < workflow.nodes.length) {
      workflow.nodes[index] = workflow.nodes[newIndex];
      workflow.nodes[newIndex] = node;
      setState(() {});
    }
  }

  // ==================== 执行方法 ====================

  Future<void> _executeWorkflow(ScriptWorkflow workflow) async {
    setState(() {
      _isExecuting = true;
    });

    try {
      final result = await _engine.executeWorkflow(workflow.id);
      setState(() {
        _currentExecution = result;
      });

      if (result.status == ExecutionStatus.success) {
        toastification.show(
          title: const Text('执行成功'),
          description: Text('耗时：${result.totalDuration.inMilliseconds}ms'),
          type: ToastificationType.success,
        );
      } else {
        toastification.show(
          title: const Text('执行失败'),
          description: Text(result.errorMessage ?? '未知错误'),
          type: ToastificationType.error,
        );
      }
    } catch (e) {
      toastification.show(
        title: const Text('执行异常'),
        description: Text(e.toString()),
        type: ToastificationType.error,
      );
    } finally {
      setState(() {
        _isExecuting = false;
      });
    }
  }

  Future<void> _executeSelectedWorkflow() async {
    if (_editingWorkflow != null) {
      await _executeWorkflow(_editingWorkflow!);
    }
  }

  void _showErrorDialog(String errorMessage) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('错误详情'),
        content: SingleChildScrollView(
          child: SelectableText(
            errorMessage,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
