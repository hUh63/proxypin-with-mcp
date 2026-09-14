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

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _run() {
    // 放到下一帧，避免阻塞首屏
    Future.delayed(Duration.zero, () {
      final report = SecurityAuditor.audit(widget.requests);
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
}
