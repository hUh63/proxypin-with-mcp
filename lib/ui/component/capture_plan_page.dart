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

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/manager/capture_plan_manager.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/utils.dart';

/// 采集方案页：把一次抓包任务模板化——域名规则 + 操作步骤，
/// 一键把域名规则应用到域名过滤器（借鉴 proxypin-mcp-workbench 的 Capture Plan）。
class CapturePlanPage extends StatefulWidget {
  const CapturePlanPage({super.key});

  @override
  State<CapturePlanPage> createState() => _CapturePlanPageState();
}

class _CapturePlanPageState extends State<CapturePlanPage> {
  CapturePlanManager? _manager;
  bool _loading = true;
  final Set<String> _expandedIds = {};

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _manager?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final manager = await CapturePlanManager.instance;
    manager.addListener(_onChanged);
    if (!mounted) return;
    setState(() {
      _manager = manager;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final plans = _manager?.plans ?? const <CapturePlan>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.capturePlan),
        actions: [
          TextButton.icon(
            onPressed: _loading ? null : () => _showEditor(),
            icon: const Icon(Icons.add, size: 18),
            label: Text(localizations.capturePlanNew),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : plans.isEmpty
              ? _buildEmpty()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 8),
                    ...plans.map(_buildPlanCard),
                  ],
                ),
    );
  }

  Widget _buildEmpty() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.route_outlined, size: 56, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(localizations.capturePlanEmpty, style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () => _showEditor(),
            icon: const Icon(Icons.add, size: 18),
            label: Text(localizations.capturePlanNew),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              localizations.capturePlanTips,
              style: TextStyle(fontSize: 12.5, height: 1.45, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(CapturePlan plan) {
    final cs = Theme.of(context).colorScheme;
    final expanded = _expandedIds.contains(plan.id);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                expanded ? _expandedIds.remove(plan.id) : _expandedIds.add(plan.id);
              });
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.route, size: 18, color: cs.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                plan.name,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (plan.builtIn)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: cs.tertiary.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  localizations.capturePlanBuiltin,
                                  style: TextStyle(fontSize: 10, color: cs.tertiary),
                                ),
                              ),
                          ],
                        ),
                        if (plan.appName.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              plan.appName,
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Builder(builder: (context) {
                    return PopupMenuButton<String>(
                      tooltip: '',
                      icon: const Icon(Icons.more_vert, size: 20),
                      onSelected: (value) => _onMenu(value, plan),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'apply',
                          height: 38,
                          enabled: plan.includeDomains.isNotEmpty || plan.excludeDomains.isNotEmpty,
                          child: Row(children: [
                            const Icon(Icons.filter_alt_outlined, size: 18),
                            const SizedBox(width: 10),
                            Text(localizations.capturePlanApply),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'edit',
                          height: 38,
                          child: Row(children: [
                            const Icon(Icons.edit_outlined, size: 18),
                            const SizedBox(width: 10),
                            Text(localizations.edit),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'copy',
                          height: 38,
                          child: Row(children: [
                            const Icon(Icons.copy_all_outlined, size: 18),
                            const SizedBox(width: 10),
                            Text(localizations.capturePlanCopy),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'export',
                          height: 38,
                          child: Row(children: [
                            const Icon(Icons.file_download_outlined, size: 18),
                            const SizedBox(width: 10),
                            Text(localizations.capturePlanExport),
                          ]),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'delete',
                          height: 38,
                          child: Row(children: [
                            Icon(Icons.delete_outline, size: 18, color: cs.error),
                            const SizedBox(width: 10),
                            Text(localizations.delete, style: TextStyle(color: cs.error)),
                          ]),
                        ),
                      ],
                    );
                  }),
                  Switch(
                    value: plan.enabled,
                    onChanged: (value) => _manager?.setEnabled(plan.id, value),
                  ),
                  const SizedBox(width: 4),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 20, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
          if (plan.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Text(
                plan.description,
                style: TextStyle(fontSize: 12.5, height: 1.45, color: cs.onSurfaceVariant),
              ),
            ),
          if (plan.includeDomains.isNotEmpty || plan.excludeDomains.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...plan.includeDomains.map((d) => _buildDomainChip(d, true)),
                  ...plan.excludeDomains.map((d) => _buildDomainChip(d, false)),
                ],
              ),
            ),
          if (expanded) _buildSteps(plan),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildDomainChip(String domain, bool include) {
    final cs = Theme.of(context).colorScheme;
    final color = include ? cs.primary : cs.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(include ? Icons.add_circle_outline : Icons.remove_circle_outline, size: 12, color: color),
          const SizedBox(width: 4),
          Text(domain, style: TextStyle(fontSize: 11.5, color: color, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildSteps(CapturePlan plan) {
    final cs = Theme.of(context).colorScheme;
    if (plan.steps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Text(
          localizations.capturePlanNoSteps,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          Text(
            localizations.capturePlanSteps,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          ...List.generate(plan.steps.length, (index) {
            final step = plan.steps[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Text('${index + 1}', style: TextStyle(fontSize: 11, color: cs.primary)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(step.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        if (step.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              step.description,
                              style: TextStyle(fontSize: 12, height: 1.4, color: cs.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _onMenu(String action, CapturePlan plan) async {
    switch (action) {
      case 'apply':
        await _apply(plan);
        break;
      case 'edit':
        await _showEditor(plan: plan);
        break;
      case 'copy':
        await _copy(plan);
        break;
      case 'export':
        await _export(plan);
        break;
      case 'delete':
        await _delete(plan);
        break;
    }
  }

  Future<void> _apply(CapturePlan plan) async {
    await CapturePlanManager.applyToFilter(plan);
    if (mounted) {
      FlutterToastr.show(localizations.capturePlanApplied, context);
    }
  }

  Future<void> _copy(CapturePlan plan) async {
    final copy = CapturePlan(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '${plan.name} ${localizations.capturePlanCopySuffix}',
      appName: plan.appName,
      description: plan.description,
      includeDomains: plan.includeDomains,
      excludeDomains: plan.excludeDomains,
      steps: plan.steps,
    );
    await _manager?.add(copy);
  }

  Future<void> _delete(CapturePlan plan) async {
    await showConfirmDialog(
      context,
      content: '${localizations.capturePlanDeleteConfirm}：${plan.name}',
      onConfirm: () async {
        await _manager?.remove(plan.id);
        if (mounted) FlutterToastr.show(localizations.deleteSuccess, context);
      },
    );
  }

  Future<void> _export(CapturePlan plan) async {
    try {
      final content = const JsonEncoder.withIndent('  ').convert(plan.toJson());
      final safeName = plan.name.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
      final Uri? path = await FilePicker.saveFile(
        fileName: '${safeName.isEmpty ? 'capture-plan' : safeName}.capture-plan.json',
        bytes: utf8.encode(content),
      );
      if (path == null) return;
      if (mounted) FlutterToastr.show(localizations.capturePlanExportSuccess, context);
    } catch (e, t) {
      logger.e('导出采集方案失败', error: e, stackTrace: t);
      if (mounted) FlutterToastr.show('${localizations.capturePlanExportFailed} $e', context);
    }
  }

  Future<void> _showEditor({CapturePlan? plan}) async {
    final result = await showDialog<CapturePlan>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CapturePlanEditorDialog(plan: plan),
    );
    if (result == null) return;
    if (plan == null) {
      await _manager?.add(result);
    } else {
      await _manager?.update(result);
    }
  }
}

/// 采集方案编辑对话框。
class _CapturePlanEditorDialog extends StatefulWidget {
  final CapturePlan? plan;

  const _CapturePlanEditorDialog({this.plan});

  @override
  State<_CapturePlanEditorDialog> createState() => _CapturePlanEditorDialogState();
}

class _CapturePlanEditorDialogState extends State<_CapturePlanEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _appController;
  late final TextEditingController _descController;
  late final TextEditingController _includeController;
  late final TextEditingController _excludeController;
  late final List<_StepController> _steps;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    _nameController = TextEditingController(text: plan?.name ?? '');
    _appController = TextEditingController(text: plan?.appName ?? '');
    _descController = TextEditingController(text: plan?.description ?? '');
    _includeController = TextEditingController(text: (plan?.includeDomains ?? const []).join('\n'));
    _excludeController = TextEditingController(text: (plan?.excludeDomains ?? const []).join('\n'));
    _steps = (plan?.steps ?? const <CapturePlanStep>[])
        .map((step) => _StepController(title: step.title, description: step.description))
        .toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _appController.dispose();
    _descController.dispose();
    _includeController.dispose();
    _excludeController.dispose();
    for (final step in _steps) {
      step.dispose();
    }
    super.dispose();
  }

  List<String> _parseDomains(String text) {
    return text
        .split(RegExp(r'[,\n;]+'))
        .map(CaptureDomainMatcher.normalizePattern)
        .where((value) => value.isNotEmpty)
        .where(CaptureDomainMatcher.isValidPattern)
        .toSet()
        .toList();
  }

  /// 文本里写了但格式不合法的域名，用于提示（不会被保存）。
  List<String> _invalidDomains(String text) {
    return text
        .split(RegExp(r'[,\n;]+'))
        .map(CaptureDomainMatcher.normalizePattern)
        .where((value) => value.isNotEmpty)
        .where((value) => !CaptureDomainMatcher.isValidPattern(value))
        .toList();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      FlutterToastr.show(localizations.capturePlanNameRequired, context);
      return;
    }
    final include = _parseDomains(_includeController.text);
    final exclude = _parseDomains(_excludeController.text);
    final plan = CapturePlan(
      schemaVersion: widget.plan?.schemaVersion ?? CapturePlan.currentSchemaVersion,
      id: widget.plan?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      appName: _appController.text.trim(),
      description: _descController.text.trim(),
      enabled: widget.plan?.enabled ?? true,
      builtIn: widget.plan?.builtIn ?? false,
      includeDomains: include,
      excludeDomains: exclude,
      steps: _steps
          .where((step) => step.title.text.trim().isNotEmpty || step.description.text.trim().isNotEmpty)
          .map((step) => CapturePlanStep(
                id: '${DateTime.now().microsecondsSinceEpoch}-${step.hashCode}',
                title: step.title.text.trim(),
                description: step.description.text.trim(),
              ))
          .toList(),
    );
    Navigator.pop(context, plan);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(widget.plan == null ? localizations.capturePlanNew : localizations.capturePlanEdit,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: localizations.capturePlanName,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _appController,
                decoration: InputDecoration(
                  labelText: localizations.capturePlanAppName,
                  hintText: localizations.capturePlanAppNameHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: localizations.capturePlanDesc,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _includeController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: localizations.capturePlanInclude,
                  hintText: localizations.capturePlanDomainsHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _excludeController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: localizations.capturePlanExclude,
                  hintText: localizations.capturePlanDomainsHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(localizations.capturePlanSteps,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => setState(() => _steps.add(_StepController())),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(localizations.capturePlanAddStep),
                  ),
                ],
              ),
              ...List.generate(_steps.length, (index) {
                final step = _steps[index];
                return Padding(
                  key: ValueKey<int>(identityHashCode(step)),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text('${index + 1}.', style: const TextStyle(fontSize: 13)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          children: [
                            TextField(
                              controller: step.title,
                              decoration: InputDecoration(
                                labelText: localizations.capturePlanStepTitle,
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: step.description,
                              maxLines: 2,
                              decoration: InputDecoration(
                                labelText: localizations.capturePlanStepDesc,
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          _steps.removeAt(index).dispose();
                        }),
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        tooltip: localizations.delete,
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(localizations.cancel)),
        FilledButton(onPressed: _submit, child: Text(localizations.save)),
      ],
    );
  }
}

class _StepController {
  final TextEditingController title;
  final TextEditingController description;

  _StepController({String title = '', String description = ''})
      : title = TextEditingController(text: title),
        description = TextEditingController(text: description);

  void dispose() {
    title.dispose();
    description.dispose();
  }
}
