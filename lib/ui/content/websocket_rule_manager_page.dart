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
import 'package:proxypin/network/rules/websocket_rule.dart';
import 'package:proxypin/network/rules/websocket_rule_manager.dart';
import '../../l10n/app_localizations.dart';

/// WebSocket 规则管理界面
class WebSocketRuleManagerPage extends StatefulWidget {
  const WebSocketRuleManagerPage({super.key});

  @override
  State<WebSocketRuleManagerPage> createState() => _WebSocketRuleManagerPageState();
}

class _WebSocketRuleManagerPageState extends State<WebSocketRuleManagerPage> {
  final WebSocketRuleManager _ruleManager = WebSocketRuleManager();
  List<WebSocketRule> _rules = [];
  bool _isLoading = true;
  bool _globalEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    setState(() => _isLoading = true);
    
    // 确保初始化
    await _ruleManager.init();
    
    setState(() {
      _rules = _ruleManager.rules;
      _globalEnabled = _ruleManager.globalEnabled;
      _isLoading = false;
    });
  }

  Future<void> _toggleGlobalEnabled(bool value) async {
    await _ruleManager.setGlobalEnabled(value);
    setState(() => _globalEnabled = value);
  }

  Future<void> _deleteRule(WebSocketRule rule) async {
    final appLocalizations = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appLocalizations.wsDeleteRule),
        content: Text(appLocalizations.wsDeleteRuleConfirm(rule.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(appLocalizations.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(appLocalizations.delete, style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _ruleManager.deleteRule(rule.id);
      await _loadRules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appLocalizations.wsRuleDeleted)),
        );
      }
    }
  }

  Future<void> _toggleRule(WebSocketRule rule) async {
    await _ruleManager.toggleRule(rule.id);
    await _loadRules();
  }

  Future<void> _editRule(WebSocketRule rule) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => RuleEditDialog(rule: rule),
    );

    if (result != null) {
      final updated = rule.copyWith(
        name: result['name'] as String,
        pattern: result['pattern'] as String,
        mode: result['mode'] as RuleMatchMode,
        description: result['description'] as String?,
        interceptOutgoing: result['interceptOutgoing'] as bool,
        interceptIncoming: result['interceptIncoming'] as bool,
      );
      await _ruleManager.updateRule(rule.id, updated);
      await _loadRules();
    }
  }

  Future<void> _addRule() async {
    final appLocalizations = AppLocalizations.of(context)!;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => RuleEditDialog(),
    );

    if (result != null) {
      await _ruleManager.addRule(
        name: result['name'] as String,
        pattern: result['pattern'] as String,
        mode: result['mode'] as RuleMatchMode,
        description: result['description'] as String?,
        interceptOutgoing: result['interceptOutgoing'] as bool,
        interceptIncoming: result['interceptIncoming'] as bool,
      );
      await _loadRules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appLocalizations.wsRuleAdded)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context)!;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(appLocalizations.wsInterceptRules),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadRules,
            tooltip: appLocalizations.refresh,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 全局开关卡片
                Card(
                  margin: EdgeInsets.all(16),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.rule,
                          size: 32,
                          color: _globalEnabled ? Colors.green : Colors.grey,
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appLocalizations.wsGlobalInterceptToggle,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _globalEnabled
                                    ? appLocalizations.wsGlobalEnabledDesc
                                    : appLocalizations.wsGlobalDisabledDesc,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _globalEnabled,
                          onChanged: _toggleGlobalEnabled,
                        ),
                      ],
                    ),
                  ),
                ),

                // 规则列表
                Expanded(
                  child: _rules.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.rule_folder,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              SizedBox(height: 16),
                              Text(
                                appLocalizations.noRules,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                appLocalizations.wsTapToAddRule,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _rules.length,
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          itemBuilder: (context, index) {
                            final rule = _rules[index];
                            return Card(
                              margin: EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: Icon(
                                  rule.enabled
                                      ? Icons.check_circle
                                      : Icons.cancel,
                                  color: rule.enabled ? Colors.green : Colors.grey,
                                ),
                                title: Text(
                                  rule.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    decoration: rule.enabled
                                        ? null
                                        : TextDecoration.lineThrough,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(height: 4),
                                    Text(
                                      '${_getModeName(appLocalizations, rule.mode)}: ${rule.pattern}',
                                      style: TextStyle(fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (rule.description != null &&
                                        rule.description!.isNotEmpty) ...[
                                      SizedBox(height: 2),
                                      Text(
                                        rule.description!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    SizedBox(height: 2),
                                    Row(
                                      children: [
                                        if (rule.interceptOutgoing)
                                          Chip(
                                            label: Text('OUT',
                                                style: TextStyle(fontSize: 10)),
                                            padding: EdgeInsets.zero,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize.shrinkWrap,
                                            visualDensity: VisualDensity.compact,
                                          ),
                                        if (rule.interceptIncoming) ...[
                                          SizedBox(width: 4),
                                          Chip(
                                            label: Text('IN',
                                                style: TextStyle(fontSize: 10)),
                                            padding: EdgeInsets.zero,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize.shrinkWrap,
                                            visualDensity: VisualDensity.compact,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    switch (value) {
                                      case 'toggle':
                                        _toggleRule(rule);
                                        break;
                                      case 'edit':
                                        _editRule(rule);
                                        break;
                                      case 'delete':
                                        _deleteRule(rule);
                                        break;
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'toggle',
                                      child: Text(rule.enabled ? appLocalizations.disabled : appLocalizations.enable),
                                    ),
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text(appLocalizations.edit),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(
                                        appLocalizations.delete,
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addRule,
        child: Icon(Icons.add),
      ),
    );
  }

  String _getModeName(AppLocalizations appLocalizations, RuleMatchMode mode) {
    switch (mode) {
      case RuleMatchMode.contains:
        return appLocalizations.matchContains;
      case RuleMatchMode.startsWith:
        return appLocalizations.matchStartsWith;
      case RuleMatchMode.endsWith:
        return appLocalizations.matchEndsWith;
      case RuleMatchMode.regex:
        return appLocalizations.matchRegex;
      case RuleMatchMode.exact:
        return appLocalizations.matchExact;
    }
  }
}

/// 规则编辑对话框
class RuleEditDialog extends StatefulWidget {
  final WebSocketRule? rule;

  const RuleEditDialog({super.key, this.rule});

  @override
  State<RuleEditDialog> createState() => _RuleEditDialogState();
}

class _RuleEditDialogState extends State<RuleEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _patternController;
  late TextEditingController _descriptionController;
  late RuleMatchMode _mode;
  late bool _interceptOutgoing;
  late bool _interceptIncoming;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.rule?.name ?? '');
    _patternController = TextEditingController(text: widget.rule?.pattern ?? '');
    _descriptionController =
        TextEditingController(text: widget.rule?.description ?? '');
    _mode = widget.rule?.mode ?? RuleMatchMode.contains;
    _interceptOutgoing = widget.rule?.interceptOutgoing ?? true;
    _interceptIncoming = widget.rule?.interceptIncoming ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _patternController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.rule == null ? appLocalizations.wsAddRule : appLocalizations.wsEditRule),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: appLocalizations.ruleName,
                  hintText: appLocalizations.wsRuleNameHint,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return appLocalizations.wsEnterRuleName;
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _patternController,
                decoration: InputDecoration(
                  labelText: appLocalizations.matchPattern,
                  hintText: appLocalizations.urlPatternHint,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return appLocalizations.wsEnterMatchPattern;
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              DropdownButtonFormField<RuleMatchMode>(
                  isExpanded: true,
                value: _mode,
                decoration: InputDecoration(labelText: appLocalizations.matchMethod),
                items: [
                  DropdownMenuItem(
                    value: RuleMatchMode.contains,
                    child: Text(appLocalizations.matchContains),
                  ),
                  DropdownMenuItem(
                    value: RuleMatchMode.startsWith,
                    child: Text(appLocalizations.matchStartsWith),
                  ),
                  DropdownMenuItem(
                    value: RuleMatchMode.endsWith,
                    child: Text(appLocalizations.matchEndsWith),
                  ),
                  DropdownMenuItem(
                    value: RuleMatchMode.regex,
                    child: Text(appLocalizations.regExp),
                  ),
                  DropdownMenuItem(
                    value: RuleMatchMode.exact,
                    child: Text(appLocalizations.matchExact),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _mode = value);
                },
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: appLocalizations.ruleDescOptional,
                  hintText: appLocalizations.wsRuleDescHint,
                ),
                maxLines: 2,
              ),
              SizedBox(height: 16),
              Text(appLocalizations.wsInterceptDirection, style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      title: Text(appLocalizations.wsOutgoing),
                      value: _interceptOutgoing,
                      onChanged: (value) {
                        setState(() => _interceptOutgoing = value ?? false);
                      },
                    ),
                  ),
                  Expanded(
                    child: CheckboxListTile(
                      title: Text(appLocalizations.wsIncoming),
                      value: _interceptIncoming,
                      onChanged: (value) {
                        setState(() => _interceptIncoming = value ?? false);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(appLocalizations.cancel),
        ),
        TextButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              if (!_interceptOutgoing && !_interceptIncoming) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(appLocalizations.wsSelectDirection)),
                );
                return;
              }
              Navigator.pop(context, {
                'name': _nameController.text,
                'pattern': _patternController.text,
                'mode': _mode,
                'description': _descriptionController.text.isEmpty
                    ? null
                    : _descriptionController.text,
                'interceptOutgoing': _interceptOutgoing,
                'interceptIncoming': _interceptIncoming,
              });
            }
          },
          child: Text(appLocalizations.save),
        ),
      ],
    );
  }
}
