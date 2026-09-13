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
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/mcp/mcp_automation_manager.dart';

/// MCP 自动化任务管理页面 (Feature 5)
class MCPTaskManagerPage extends StatefulWidget {
  const MCPTaskManagerPage({super.key});

  @override
  State<MCPTaskManagerPage> createState() => _MCPTaskManagerPageState();
}

class _MCPTaskManagerPageState extends State<MCPTaskManagerPage> {
  final _manager = MCPAutomationManager();
  List<MCPAutomationTask> _tasks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);
    await _manager.init();
    setState(() {
      _tasks = _manager.tasks;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.mcpAutomationTasks),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTasks,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showTaskDialog(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tasks.isEmpty
              ? _buildEmptyState()
              : _buildTaskList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.noAutomationTasks,
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _showTaskDialog(),
            icon: const Icon(Icons.add),
            label: Text(AppLocalizations.of(context)!.createTask),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _tasks.length,
      itemBuilder: (context, index) {
        final task = _tasks[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: task.enabled ? Colors.blue : Colors.grey,
              child: Icon(
                _getTriggerIcon(task.triggerType),
                color: Colors.white,
              ),
            ),
            title: Text(
              task.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                decoration: task.enabled ? null : TextDecoration.lineThrough,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(_getTriggerLabel(task.triggerType)),
                Text(
                  AppLocalizations.of(context)!
                      .mcpTaskActionsSummary(task.actions.length, task.executionCount),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            trailing: Switch(
              value: task.enabled,
              onChanged: (value) => _toggleTask(task),
            ),
            onTap: () => _showTaskDetails(task),
            onLongPress: () => _showTaskOptions(task),
          ),
        );
      },
    );
  }

  IconData _getTriggerIcon(AutomationTriggerType type) {
    switch (type) {
      case AutomationTriggerType.onRequest:
        return Icons.http;
      case AutomationTriggerType.onResponse:
        return Icons.swap_horiz;
      case AutomationTriggerType.onInterval:
        return Icons.schedule;
      case AutomationTriggerType.onProxyStart:
      case AutomationTriggerType.onProxyStop:
        return Icons.wifi_tethering;
      case AutomationTriggerType.manual:
        return Icons.touch_app;
    }
  }

  String _getTriggerLabel(AutomationTriggerType type) {
    return type.label;
  }

  Future<void> _showTaskDialog([MCPAutomationTask? task]) async {
    final isEdit = task != null;
    final nameController = TextEditingController(text: task?.name ?? '');
    final descController = TextEditingController(text: task?.description ?? '');
    AutomationTriggerType selectedTrigger = task?.triggerType ?? AutomationTriggerType.onRequest;
    List<AutomationActionType> selectedActions = task?.actions ?? [];
    String urlPattern = task?.conditions['urlPattern'] as String? ?? '';
    
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit
              ? AppLocalizations.of(context)!.mcpEditTask
              : AppLocalizations.of(context)!.mcpAddTask),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.mcpTaskName,
                      prefixIcon: Icon(Icons.label)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.descriptionLabel,
                      prefixIcon: Icon(Icons.description)),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Text(AppLocalizations.of(context)!.mcpTriggerType,
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<AutomationTriggerType>(
                  isExpanded: true,
                  value: selectedTrigger,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: AutomationTriggerType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label))).toList(),
                  onChanged: (v) => setDialogState(() => selectedTrigger = v!),
                ),
                if (selectedTrigger == AutomationTriggerType.onRequest || selectedTrigger == AutomationTriggerType.onResponse) ...[
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.urlPattern,
                      prefixIcon: Icon(Icons.link),
                      hintText: AppLocalizations.of(context)!.urlPatternHint),
                    onChanged: (v) => urlPattern = v,
                  ),
                ],
                const SizedBox(height: 16),
                Text(AppLocalizations.of(context)!.mcpActionType,
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...AutomationActionType.values.map((action) => CheckboxListTile(
                  title: Text(action.label),
                  value: selectedActions.contains(action),
                  onChanged: (checked) => setDialogState(() {
                    if (checked == true) {
                      selectedActions = [...selectedActions, action];
                    } else {
                      selectedActions = selectedActions.where((a) => a != action).toList();
                    }
                  }),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.cancel)),
            FilledButton(
              onPressed: () async {
                if (nameController.text.isEmpty) return;
                if (isEdit) {
                  final updated = task!.copyWith(
                    name: nameController.text,
                    description: descController.text,
                    triggerType: selectedTrigger,
                    actions: selectedActions,
                    conditions: urlPattern.isNotEmpty ? {'urlPattern': urlPattern} : {},
                  );
                  await _manager.updateTask(task.id, updated);
                } else {
                  await _manager.addTask(
                    name: nameController.text,
                    description: descController.text,
                    triggerType: selectedTrigger,
                    actions: selectedActions,
                    conditions: urlPattern.isNotEmpty ? {'urlPattern': urlPattern} : {},
                  );
                }
                Navigator.pop(context);
                await _loadTasks();
              },
              child: Text(isEdit
                  ? AppLocalizations.of(context)!.save
                  : AppLocalizations.of(context)!.add),
            ),
          ],
        ),
      ),
    );
    
    nameController.dispose();
    descController.dispose();
  }

  void _showTaskDetails(MCPAutomationTask task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(task.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(AppLocalizations.of(context)!.descriptionLabel,
                  task.description.isEmpty ? AppLocalizations.of(context)!.none : task.description),
              _buildDetailRow(AppLocalizations.of(context)!.mcpTrigger, task.triggerType.label),
              _buildDetailRow(AppLocalizations.of(context)!.mcpAction,
                  task.actions.map((a) => a.label).join(', ')),
              _buildDetailRow(
                  AppLocalizations.of(context)!.mcpStatus,
                  task.enabled
                      ? AppLocalizations.of(context)!.mcpStatusEnabled
                      : AppLocalizations.of(context)!.mcpStatusDisabled),
              _buildDetailRow(AppLocalizations.of(context)!.executionCount,
                  AppLocalizations.of(context)!.timesCount(task.executionCount)),
              if (task.lastExecutedAt != null)
                _buildDetailRow(AppLocalizations.of(context)!.mcpLastExecuted,
                    _formatDate(task.lastExecutedAt!)),
              _buildDetailRow(
                  AppLocalizations.of(context)!.mcpCreatedAt, _formatDate(task.createdAt)),
              _buildDetailRow(
                  AppLocalizations.of(context)!.mcpUpdatedAt, _formatDate(task.updatedAt)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.close)),
        ],
      ),
    );
  }

  void _showTaskOptions(MCPAutomationTask task) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(AppLocalizations.of(context)!.mcpEditTask),
              onTap: () {
                Navigator.pop(context);
                _showTaskDialog(task);
              },
            ),
            ListTile(
              leading: Icon(task.enabled ? Icons.pause : Icons.play_arrow),
              title: Text(task.enabled
                  ? AppLocalizations.of(context)!.mcpDisableTask
                  : AppLocalizations.of(context)!.mcpEnableTask),
              onTap: () async {
                await _toggleTask(task);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info),
              title: Text(AppLocalizations.of(context)!.mcpViewDetails),
              onTap: () {
                Navigator.pop(context);
                _showTaskDetails(task);
              },
            ),
            if (task.triggerType == AutomationTriggerType.manual)
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: Text(AppLocalizations.of(context)!.mcpRunManually),
                onTap: () async {
                  await _manager.executeTask(task.id);
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(AppLocalizations.of(context)!.mcpTaskTriggered)));
                    await _loadTasks();
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(AppLocalizations.of(context)!.mcpDeleteTask,
                  style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text(AppLocalizations.of(context)!.confirmDelete),
                    content: Text(
                        AppLocalizations.of(context)!.mcpDeleteTaskNameConfirm(task.name)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: Text(AppLocalizations.of(context)!.cancel)),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: Text(AppLocalizations.of(context)!.delete)),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await _manager.deleteTask(task.id);
                  await _loadTasks();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 80, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold))),
      Expanded(child: Text(value)),
    ]),
  );

  String _formatDate(DateTime dt) => '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  Future<void> _toggleTask(MCPAutomationTask task) async {
    await _manager.toggleTask(task.id);
    await _loadTasks();
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }
}
