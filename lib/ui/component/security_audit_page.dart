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
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/security_audit.dart';
import 'package:proxypin/network/util/security_rule_store.dart';
import 'package:proxypin/ui/component/utils.dart';

/// 安全自检页：对已抓到的流量做**被动**安全基线核查。
///
/// 只分析、不发送任何请求，把发现按风险等级列出，可导出 Markdown 报告。
class SecurityAuditPage extends StatefulWidget {
  final List<HttpRequest> requests;

  const SecurityAuditPage({super.key, required this.requests});

  @override
  State<SecurityAuditPage> createState() => _SecurityAuditPageState();
}

class _SecurityAuditPageState extends State<SecurityAuditPage> {
  SecurityAuditReport? _report;
  bool _loading = true;
  SecuritySeverity? _filter;
  SecurityRuleStore? _store;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _store?.removeListener(_onRulesChanged);
    super.dispose();
  }

  Future<void> _init() async {
    final store = await SecurityRuleStore.instance;
    store.addListener(_onRulesChanged);
    if (!mounted) return;
    setState(() => _store = store);
    _run();
  }

  void _onRulesChanged() => _run();

  void _run() {
    // 放到下一帧，避免阻塞首屏
    Future.delayed(Duration.zero, () {
      final report = SecurityAuditor.audit(widget.requests, customRules: _store?.rules ?? const []);
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    });
  }

  Color _severityColor(SecuritySeverity severity) {
    if (severity == SecuritySeverity.high) return const Color(0xFFD32F2F);
    if (severity == SecuritySeverity.medium) return const Color(0xFFEF6C00);
    if (severity == SecuritySeverity.low) return const Color(0xFFF9A825);
    return const Color(0xFF607D8B);
  }

  String _severityLabel(SecuritySeverity severity) {
    if (severity == SecuritySeverity.high) return localizations.securityAuditSeverityHigh;
    if (severity == SecuritySeverity.medium) return localizations.securityAuditSeverityMedium;
    if (severity == SecuritySeverity.low) return localizations.securityAuditSeverityLow;
    return localizations.securityAuditSeverityInfo;
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.securityAudit),
        actions: [
          TextButton.icon(
            onPressed: _openRules,
            icon: const Icon(Icons.rule, size: 18),
            label: Text(localizations.securityAuditRules),
          ),
          const SizedBox(width: 4),
          if (report != null && !report.isClean)
            TextButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(localizations.securityAuditExport),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading || report == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                _buildHeader(report),
                const SizedBox(height: 10),
                _buildSummary(report),
                const SizedBox(height: 10),
                _buildFilters(report),
                const SizedBox(height: 6),
                ..._buildIssues(report),
              ],
            ),
    );
  }

  Widget _buildHeader(SecurityAuditReport report) {
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
          Icon(Icons.shield_outlined, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localizations.securityAuditTips,
                  style: TextStyle(fontSize: 12.5, height: 1.45, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  '${localizations.securityAuditScanned}: ${report.scannedRequests}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(SecurityAuditReport report) {
    return Row(
      children: [
        for (final severity in SecuritySeverity.values) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _severityColor(severity).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _severityColor(severity).withValues(alpha: 0.25)),
              ),
              child: Column(
                children: [
                  Text(
                    '${report.count(severity)}',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _severityColor(severity)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _severityLabel(severity),
                    style: TextStyle(fontSize: 11.5, color: _severityColor(severity)),
                  ),
                ],
              ),
            ),
          ),
          if (severity != SecuritySeverity.info) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _buildFilters(SecurityAuditReport report) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        FilterChip(
          label: Text(localizations.securityAuditFilterAll),
          selected: _filter == null,
          onSelected: (_) => setState(() => _filter = null),
        ),
        for (final severity in SecuritySeverity.values)
          if (report.count(severity) > 0)
            FilterChip(
              label: Text('${_severityLabel(severity)} (${report.count(severity)})'),
              selected: _filter == severity,
              onSelected: (_) => setState(() => _filter = severity),
            ),
      ],
    );
  }

  List<Widget> _buildIssues(SecurityAuditReport report) {
    if (report.isClean) {
      return [_buildClean()];
    }
    final issues = _filter == null ? report.issues : report.issues.where((i) => i.severity == _filter).toList();
    if (issues.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(localizations.securityAuditEmpty,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        )
      ];
    }
    return issues.map(_buildIssueCard).toList();
  }

  Widget _buildClean() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.verified_user_outlined, size: 56, color: Colors.green.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text(localizations.securityAuditClean, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              localizations.securityAuditCleanTips,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, height: 1.5, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIssueCard(SecurityIssue issue) {
    final cs = Theme.of(context).colorScheme;
    final color = _severityColor(issue.severity);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.85),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(_severityLabel(issue.severity),
                        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(issue.title,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.link, size: 13, color: cs.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Expanded(
                    child: SelectableText(
                      '${issue.method} ${issue.url}',
                      style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant, fontFamily: 'monospace'),
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Text(issue.detail, style: TextStyle(fontSize: 12.5, height: 1.45, color: cs.onSurface)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, size: 14, color: cs.primary),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '${localizations.securityAuditSuggestion}: ${issue.suggestion}',
                      style: TextStyle(fontSize: 12.5, height: 1.45, color: cs.primary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export() async {
    final report = _report;
    if (report == null) return;
    try {
      final buffer = StringBuffer()
        ..writeln('# ProxyPin ${localizations.securityAudit}')
        ..writeln()
        ..writeln('- ${localizations.securityAuditScanned}: ${report.scannedRequests}')
        ..writeln('- ${localizations.securityAuditIssues}: ${report.issues.length}')
        ..writeln();
      for (final severity in SecuritySeverity.values) {
        final items = report.issues.where((issue) => issue.severity == severity).toList();
        if (items.isEmpty) continue;
        buffer.writeln('## ${_severityLabel(severity)} (${items.length})');
        buffer.writeln();
        for (final issue in items) {
          buffer.writeln('- **${issue.title}** — `${issue.method} ${issue.url}`');
          buffer.writeln('  - ${issue.detail}');
          buffer.writeln('  - ${localizations.securityAuditSuggestion}: ${issue.suggestion}');
        }
        buffer.writeln();
      }
      final Uri? path = await FilePicker.saveFile(
        fileName: 'security-audit-report.md',
        bytes: utf8.encode(buffer.toString()),
      );
      if (path == null) return;
      if (mounted) FlutterToastr.show(localizations.securityAuditExportSuccess, context);
    } catch (e, t) {
      logger.e('导出安全自检报告失败', error: e, stackTrace: t);
      if (mounted) FlutterToastr.show('${localizations.securityAuditExportFailed} $e', context);
    }
  }

  Future<void> _openRules() async {
    final store = _store ?? await SecurityRuleStore.instance;
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => _SecurityRulesDialog(store: store),
    );
  }
}

/// 自定义规则管理对话框
class _SecurityRulesDialog extends StatefulWidget {
  final SecurityRuleStore store;

  const _SecurityRulesDialog({required this.store});

  @override
  State<_SecurityRulesDialog> createState() => _SecurityRulesDialogState();
}

class _SecurityRulesDialogState extends State<_SecurityRulesDialog> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Color _color(SecuritySeverity severity) {
    if (severity == SecuritySeverity.high) return const Color(0xFFD32F2F);
    if (severity == SecuritySeverity.medium) return const Color(0xFFEF6C00);
    if (severity == SecuritySeverity.low) return const Color(0xFFF9A825);
    return const Color(0xFF607D8B);
  }

  String _severityLabel(SecuritySeverity severity) {
    if (severity == SecuritySeverity.high) return localizations.securityAuditSeverityHigh;
    if (severity == SecuritySeverity.medium) return localizations.securityAuditSeverityMedium;
    if (severity == SecuritySeverity.low) return localizations.securityAuditSeverityLow;
    return localizations.securityAuditSeverityInfo;
  }

  @override
  Widget build(BuildContext context) {
    final rules = widget.store.rules;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Expanded(
            child: Text(localizations.securityAuditRules,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          TextButton.icon(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add, size: 18),
            label: Text(localizations.securityAuditRuleNew),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizations.securityAuditRulesTips,
              style: TextStyle(
                  fontSize: 12, height: 1.4, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: rules.isEmpty
                  ? Center(child: Text(localizations.securityAuditRuleEmpty))
                  : ListView.separated(
                      itemCount: rules.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final rule = rules[index];
                        final color = _color(rule.severity);
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(_severityLabel(rule.severity),
                                    style: TextStyle(fontSize: 11, color: color)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(rule.name,
                                    style: const TextStyle(fontSize: 14),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            '${rule.describe()}\n${rule.pattern}',
                            style: const TextStyle(fontSize: 11.5, height: 1.35),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                  value: rule.enabled,
                                  onChanged: (value) => widget.store.setEnabled(rule.id, value)),
                              IconButton(
                                  tooltip: localizations.edit,
                                  onPressed: () => _edit(rule: rule),
                                  icon: const Icon(Icons.edit_outlined, size: 18)),
                              IconButton(
                                  tooltip: localizations.delete,
                                  onPressed: () => _delete(rule),
                                  icon: const Icon(Icons.delete_outline, size: 18)),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _import,
          icon: const Icon(Icons.file_upload_outlined, size: 18),
          label: Text(localizations.securityAuditRuleImport),
        ),
        TextButton.icon(
          onPressed: _export,
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: Text(localizations.securityAuditRuleExport),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(localizations.cancel)),
      ],
    );
  }

  Future<void> _import() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (result == null || result.isEmpty) return;
      final file = result.single;
      final text = await file.xFile.readAsString();
      final decoded = jsonDecode(text);
      List<dynamic> raw;
      if (decoded is List) {
        raw = decoded;
      } else if (decoded is Map && decoded['rules'] is List) {
        raw = decoded['rules'] as List;
      } else {
        if (mounted) FlutterToastr.show(localizations.securityAuditRuleImportFailed, context);
        return;
      }
      final incoming = raw
          .whereType<Map>()
          .map((item) => CustomSecurityRule.fromJson(Map<String, dynamic>.from(item)))
          .where((rule) => rule.name.isNotEmpty && rule.pattern.isNotEmpty)
          .toList();
      if (incoming.isEmpty) {
        if (mounted) FlutterToastr.show(localizations.securityAuditRuleImportEmpty, context);
        return;
      }
      final added = await widget.store.importRules(incoming);
      if (mounted) FlutterToastr.show('${localizations.securityAuditRuleImportSuccess} $added', context);
    } catch (e, t) {
      logger.e('导入自定义安全规则失败', error: e, stackTrace: t);
      if (mounted) FlutterToastr.show('${localizations.securityAuditRuleImportFailed} $e', context);
    }
  }

  Future<void> _export() async {
    final rules = widget.store.rules;
    if (rules.isEmpty) {
      FlutterToastr.show(localizations.securityAuditRuleEmpty, context);
      return;
    }
    try {
      final payload = {
        'type': 'proxypin.security-rules',
        'version': 1,
        'rules': rules.map((rule) => rule.toJson()).toList(growable: false),
      };
      final Uri? path = await FilePicker.saveFile(
        fileName: 'security-rules.json',
        bytes: utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
      );
      if (path == null) return;
      if (mounted) FlutterToastr.show(localizations.securityAuditRuleExportSuccess, context);
    } catch (e, t) {
      logger.e('导出自定义安全规则失败', error: e, stackTrace: t);
      if (mounted) FlutterToastr.show('${localizations.securityAuditRuleExportFailed} $e', context);
    }
  }

  Future<void> _edit({CustomSecurityRule? rule}) async {
    final result = await showDialog<CustomSecurityRule>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SecurityRuleEditorDialog(rule: rule),
    );
    if (result == null) return;
    if (rule == null) {
      await widget.store.add(result);
    } else {
      await widget.store.update(result);
    }
  }

  Future<void> _delete(CustomSecurityRule rule) async {
    await showConfirmDialog(
      context,
      content: '${localizations.securityAuditRuleDeleteConfirm}：${rule.name}',
      onConfirm: () => widget.store.remove(rule.id),
    );
  }
}

/// 自定义规则编辑对话框
class _SecurityRuleEditorDialog extends StatefulWidget {
  final CustomSecurityRule? rule;

  const _SecurityRuleEditorDialog({this.rule});

  @override
  State<_SecurityRuleEditorDialog> createState() => _SecurityRuleEditorDialogState();
}

class _SecurityRuleEditorDialogState extends State<_SecurityRuleEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _pattern;
  late final TextEditingController _suggestion;
  late SecurityRuleTarget _target;
  late SecurityRuleMatchType _matchType;
  late SecuritySeverity _severity;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _name = TextEditingController(text: rule?.name ?? '');
    _pattern = TextEditingController(text: rule?.pattern ?? '');
    _suggestion = TextEditingController(text: rule?.suggestion ?? '');
    _target = rule?.target ?? SecurityRuleTarget.any;
    _matchType = rule?.matchType ?? SecurityRuleMatchType.keyword;
    _severity = rule?.severity ?? SecuritySeverity.medium;
  }

  @override
  void dispose() {
    _name.dispose();
    _pattern.dispose();
    _suggestion.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      FlutterToastr.show(localizations.securityAuditRuleNameRequired, context);
      return;
    }
    final pattern = _pattern.text;
    if (pattern.trim().isEmpty) {
      FlutterToastr.show(localizations.securityAuditRulePatternRequired, context);
      return;
    }
    if (!CustomSecurityRule.isValidPattern(pattern, _matchType)) {
      FlutterToastr.show(localizations.securityAuditRuleInvalidRegex, context);
      return;
    }
    Navigator.pop(
      context,
      CustomSecurityRule(
        id: widget.rule?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        enabled: widget.rule?.enabled ?? true,
        target: _target,
        matchType: _matchType,
        pattern: pattern.trim(),
        severity: _severity,
        suggestion: _suggestion.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool patternInvalid =
        _pattern.text.trim().isNotEmpty && !CustomSecurityRule.isValidPattern(_pattern.text, _matchType);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(widget.rule == null ? localizations.securityAuditRuleNew : localizations.securityAuditRuleEdit,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: localizations.securityAuditRuleName,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<SecurityRuleTarget>(
                      initialValue: _target,
                      decoration: InputDecoration(
                        labelText: localizations.securityAuditRuleTarget,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final target in SecurityRuleTarget.values)
                          DropdownMenuItem(
                            value: target,
                            child: Text(CustomSecurityRule.targetLabel(target),
                                style: const TextStyle(fontSize: 13)),
                          ),
                      ],
                      onChanged: (value) => setState(() => _target = value ?? _target),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<SecurityRuleMatchType>(
                      initialValue: _matchType,
                      decoration: InputDecoration(
                        labelText: localizations.securityAuditRuleMatchType,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final match in SecurityRuleMatchType.values)
                          DropdownMenuItem(
                            value: match,
                            child: Text(CustomSecurityRule.matchLabel(match),
                                style: const TextStyle(fontSize: 13)),
                          ),
                      ],
                      onChanged: (value) => setState(() => _matchType = value ?? _matchType),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pattern,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: localizations.securityAuditRulePattern,
                  hintText: localizations.securityAuditRulePatternHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: patternInvalid ? localizations.securityAuditRuleInvalidRegex : null,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SecuritySeverity>(
                initialValue: _severity,
                decoration: InputDecoration(
                  labelText: localizations.securityAuditRuleSeverity,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final severity in SecuritySeverity.values)
                    DropdownMenuItem(
                      value: severity,
                      child: Text(_severityText(severity), style: const TextStyle(fontSize: 13)),
                    ),
                ],
                onChanged: (value) => setState(() => _severity = value ?? _severity),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _suggestion,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: localizations.securityAuditRuleSuggestion,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
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

  String _severityText(SecuritySeverity severity) {
    if (severity == SecuritySeverity.high) return localizations.securityAuditSeverityHigh;
    if (severity == SecuritySeverity.medium) return localizations.securityAuditSeverityMedium;
    if (severity == SecuritySeverity.low) return localizations.securityAuditSeverityLow;
    return localizations.securityAuditSeverityInfo;
  }
}
