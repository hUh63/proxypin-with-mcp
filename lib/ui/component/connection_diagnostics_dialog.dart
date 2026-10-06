/*
 * Copyright 2023 Hongen Wang
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
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/channel/connection_diagnostics.dart';
import 'package:proxypin/network/channel/connection_registry.dart';

/// 打开「连接树自检」面板：把连接登记表的现状翻成可读的检查清单，
/// 并支持一键导出报告，便于在真机上验证 HTTP/2 连接树与分阶段耗时。
void showConnectionDiagnostics(BuildContext context) {
  showDialog(context: context, builder: (_) => const _ConnectionDiagnosticsDialog());
}

class _ConnectionDiagnosticsDialog extends StatefulWidget {
  const _ConnectionDiagnosticsDialog();

  @override
  State<_ConnectionDiagnosticsDialog> createState() => _ConnectionDiagnosticsDialogState();
}

class _ConnectionDiagnosticsDialogState extends State<_ConnectionDiagnosticsDialog> {
  final ConnectionRegistry _registry = ConnectionRegistry.instance;
  late ConnectionDiagnosticsReport _report;
  late List<ConnectionEntry> _entries;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _entries = _registry.entries;
    _report = ConnectionDiagnostics.analyze(_entries);
  }

  void _rerun() => setState(_refresh);

  Future<void> _copy() async {
    final l = AppLocalizations.of(context)!;
    final json = ConnectionDiagnostics.toJson(_entries, _report);
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) FlutterToastr.show(l.connDiagCopied, context);
  }

  Future<void> _export() async {
    final l = AppLocalizations.of(context)!;
    try {
      final json = ConnectionDiagnostics.toJson(_entries, _report);
      final bytes = Uint8List.fromList(utf8.encode(json));
      final Uri? path = await FilePicker.saveFile(
        fileName: 'connection_report.json',
        bytes: bytes,
      );
      if (path != null && mounted) {
        FlutterToastr.show(l.connDiagExported(path.toString()), context);
      }
    } catch (e) {
      if (mounted) {
        FlutterToastr.show(l.connDiagFailed('$e'), context, backgroundColor: Colors.red);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final r = _report;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.fact_check_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(l.connDiagTitle)),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: l.connDiagRun,
            onPressed: _rerun,
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      content: SizedBox(
        width: 640,
        height: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statChip(l.connDiagTotalConn, '${r.connectionCount}',
                    cap: r.connectionCount >= r.maxConnections),
                _statChip('HTTP/2', '${r.http2Count}'),
                _statChip('HTTP/1.1', '${r.http1Count}'),
                _statChip(l.connDiagTlsConn, '${r.tlsCount}'),
                _statChip(l.connDiagRequests, '${r.totalRequests}'),
              ],
            ),
            const SizedBox(height: 12),
            _coverage(l.connDiagCoverageStream, r.withStreamId, r.cachedRequests),
            _coverage(l.connDiagCoverageConnect, r.withConnectTime, r.cachedRequests),
            _coverage(l.connDiagCoverageTls, r.withTlsTime, r.cachedRequests),
            const SizedBox(height: 10),
            const Divider(height: 1, thickness: 0.4),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  if (r.healthy)
                    const Icon(Icons.check_circle_outline, size: 16, color: Colors.green)
                  else
                    const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      r.healthy ? l.connDiagHealthy : l.connDiagIssues(r.errorCount, r.warnCount, r.infoCount),
                      style: TextStyle(fontSize: 12.5, color: r.healthy ? Colors.green[800] : Colors.grey[800]),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: r.issues.isEmpty
                  ? Center(child: Text(l.connDiagHealthy, style: TextStyle(color: Colors.grey[600])))
                  : ListView.builder(
                      itemCount: r.issues.length,
                      itemBuilder: (_, i) => _buildIssue(r.issues[i]),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _copy, child: Text(l.connDiagCopy)),
        TextButton(onPressed: _export, child: Text(l.connDiagExport)),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.close)),
      ],
    );
  }

  Widget _buildIssue(DiagnosticIssue issue) {
    late final IconData icon;
    late final Color color;
    switch (issue.level) {
      case ConnDiagLevel.error:
        icon = Icons.error_outline;
        color = Colors.red;
        break;
      case ConnDiagLevel.warn:
        icon = Icons.warning_amber_rounded;
        color = Colors.orange;
        break;
      case ConnDiagLevel.info:
        icon = Icons.info_outline;
        color = Colors.blueGrey;
        break;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(issue.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(issue.detail,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[700])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, {bool cap = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (cap ? Colors.orange : Theme.of(context).colorScheme.primary).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ', style: TextStyle(fontSize: 11.5, color: Colors.grey[700])),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: cap ? Colors.orange[800] : Theme.of(context).colorScheme.primary)),
        ],
      ),
    );
  }

  Widget _coverage(String label, int done, int total) {
    final ratio = total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Text('$label  $done/$total',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
