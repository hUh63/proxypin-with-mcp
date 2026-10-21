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
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/cert/cert_data.dart';
import 'package:proxypin/network/util/cert/x509.dart';
import 'package:proxypin/utils/cert_risk_check.dart';

/// 证书风险检测页。
///
/// 防御性工具：连接目标站点取回它的证书，判断它是否由已知被攻破的 CA 签发
/// （如 2026-10 emSign / eMudhra 事件），以及是否存在过期、弱密钥、弱签名、
/// 自签名等问题。
///
/// 刻意**不提供**任何私钥推导 / 证书签发能力 —— 那是攻击侧的东西。
class CertCheckPage extends StatefulWidget {
  const CertCheckPage({super.key});

  @override
  State<CertCheckPage> createState() => _CertCheckPageState();
}

class _CertCheckPageState extends State<CertCheckPage> {
  final TextEditingController _controller = TextEditingController(text: 'example.com');
  bool _loading = false;
  String? _error;
  CertRiskReport? _report;
  String? _negotiated;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _report = null;
      _negotiated = null;
    });
    try {
      final uri = Uri.tryParse(input.contains('://') ? input : 'https://$input');
      final host = uri?.host ?? '';
      if (host.isEmpty) {
        throw const FormatException('Invalid host');
      }
      final port = uri!.hasPort ? uri.port : 443;
      final socket = await SecureSocket.connect(
        host,
        port,
        timeout: const Duration(seconds: 10),
        // 证书有问题（含过期/未知 CA）时也要继续，否则就检测不到问题本身。
        // 这里只用于读取证书做诊断，不参与任何信任决策。
        onBadCertificate: (_) => true,
      );
      try {
        final cert = socket.peerCertificate;
        if (cert == null) {
          throw StateError('No peer certificate');
        }
        final data = X509Utils.x509CertificateFromPem(_toPem(cert.der));
        final report = CertRiskCheck.inspect(data);
        if (!mounted) return;
        setState(() {
          _report = report;
          _negotiated = socket.selectedProtocol;
        });
      } finally {
        socket.destroy();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _toPem(List<int> der) {
    final encoded = base64.encode(der);
    final buffer = StringBuffer('-----BEGIN CERTIFICATE-----\n');
    for (var i = 0; i < encoded.length; i += 64) {
      final end = i + 64 > encoded.length ? encoded.length : i + 64;
      buffer.writeln(encoded.substring(i, end));
    }
    buffer.write('-----END CERTIFICATE-----');
    return buffer.toString();
  }

  Color _levelColor(CertRiskLevel level) => switch (level) {
        CertRiskLevel.safe => Colors.green,
        CertRiskLevel.warning => Colors.orange,
        CertRiskLevel.critical => Colors.red,
      };

  IconData _levelIcon(CertRiskLevel level) => switch (level) {
        CertRiskLevel.safe => Icons.verified_user,
        CertRiskLevel.warning => Icons.report_problem_outlined,
        CertRiskLevel.critical => Icons.dangerous,
      };

  String _levelLabel(CertRiskLevel level) => switch (level) {
        CertRiskLevel.safe => localizations.certCheckSafe,
        CertRiskLevel.warning => localizations.certCheckWarning,
        CertRiskLevel.critical => localizations.certCheckCritical,
      };

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: Text(localizations.toolboxCertCheck)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    labelText: localizations.toolboxCertCheck,
                    hintText: localizations.certCheckHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _run(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _loading ? null : _run,
                child: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(localizations.certCheckRun),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('${localizations.certCheckFailed}: $_error'),
              ),
            ),
          if (report != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_levelIcon(report.level), color: _levelColor(report.level)),
                        const SizedBox(width: 8),
                        Text(
                          _levelLabel(report.level),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: _levelColor(report.level)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _kv('Subject', report.subject),
                    _kv('Issuer', report.issuer),
                    if (report.notBefore != null) _kv('Not before', '${report.notBefore}'),
                    if (report.notAfter != null) _kv('Not after', '${report.notAfter}'),
                    if (_negotiated != null) _kv('ALPN', _negotiated!),
                    if (report.sha256 != null) _kv('SHA-256', report.sha256!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (report.findings.isEmpty)
              ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: Text(localizations.certCheckNoIssues),
              )
            else
              for (final finding in report.findings)
                ListTile(
                  leading: Icon(_levelIcon(finding.level), color: _levelColor(finding.level)),
                  title: Text(finding.code),
                  subtitle: Text(finding.detail),
                ),
            const SizedBox(height: 12),
            Text(
              localizations.certCheckNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 84,
              child: Text(key, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            Expanded(
              child: SelectableText(value, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
}
