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
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/mcp/mcp_server.dart';
import 'package:proxypin/network/util/crts.dart';
import 'package:proxypin/utils/ip.dart';

/// 网络诊断 / 连接自检（借鉴 proxypin-mcp-workbench 的「连接诊断」）。
///
/// 汇总抓包必备要素的当前状态：代理服务、监听端口、本机局域网地址、
/// 根 CA 证书、MCP 服务，并给出手机抓包常见问题的排障提示。
class NetworkDiagnosticsPage extends StatefulWidget {
  const NetworkDiagnosticsPage({super.key});

  @override
  State<NetworkDiagnosticsPage> createState() => _NetworkDiagnosticsPageState();
}

class _NetworkDiagnosticsPageState extends State<NetworkDiagnosticsPage> {
  bool _loading = true;
  bool _proxyRunning = false;
  int _proxyPort = 0;
  List<String> _ips = [];
  bool _caExists = false;
  String _caPath = '';
  bool _mcpRunning = false;
  int _mcpPort = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);

    final proxy = ProxyServer.current;
    final proxyRunning = proxy?.isRunning ?? false;
    final proxyPort = proxy?.port ?? 0;

    List<String> ips = [];
    try {
      ips = await localIps(readCache: false);
    } catch (_) {
      ips = [];
    }

    bool caExists = false;
    String caPath = '';
    try {
      final file = await CertificateManager.certificateFile();
      caExists = await file.exists();
      caPath = file.path;
    } catch (_) {
      caExists = false;
    }

    final mcp = McpServer();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _proxyRunning = proxyRunning;
      _proxyPort = proxyPort;
      _ips = ips;
      _caExists = caExists;
      _caPath = caPath;
      _mcpRunning = mcp.isRunning;
      _mcpPort = mcp.port;
    });
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    FlutterToastr.show(AppLocalizations.of(context)!.copySuccess, context);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.networkDiagnostics),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: localizations.refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _statusCard(
                  theme,
                  icon: Icons.wifi_tethering,
                  title: localizations.diagProxyService,
                  value: _proxyRunning ? localizations.diagRunning : localizations.diagStopped,
                  ok: _proxyRunning,
                ),
                _statusCard(
                  theme,
                  icon: Icons.numbers,
                  title: localizations.diagListeningPort,
                  value: _proxyPort > 0 ? '$_proxyPort' : '-',
                  ok: _proxyPort > 0,
                  onCopy: _proxyPort > 0 ? () => _copy('$_proxyPort') : null,
                ),
                _statusCard(
                  theme,
                  icon: Icons.lan_outlined,
                  title: localizations.diagLanAddress,
                  value: _ips.isEmpty ? localizations.diagNoLanAddress : _ips.join('\n'),
                  ok: _ips.isNotEmpty,
                  onCopy: _ips.isNotEmpty ? () => _copy(_ips.join('\n')) : null,
                ),
                _statusCard(
                  theme,
                  icon: Icons.verified_user_outlined,
                  title: localizations.diagRootCa,
                  value: _caExists ? localizations.diagCaReady : localizations.diagCaMissing,
                  subtitle: _caPath.isEmpty ? null : _caPath,
                  ok: _caExists,
                  onCopy: _caExists ? () => _copy(_caPath) : null,
                ),
                _statusCard(
                  theme,
                  icon: Icons.cast_connected,
                  title: localizations.diagMcpService,
                  value: '${_mcpRunning ? localizations.diagRunning : localizations.diagStopped}'
                      ' · ${_mcpPort}',
                  ok: _mcpRunning,
                  onCopy: () => _copy('$_mcpPort'),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.lightbulb_outline, size: 18),
                          const SizedBox(width: 6),
                          Text(localizations.diagHints,
                              style: theme.textTheme.titleSmall),
                        ]),
                        const SizedBox(height: 8),
                        _hint(localizations.diagHintPhoneProxy),
                        _hint(localizations.diagHintCa),
                        _hint(localizations.diagHintFirewall),
                        _hint(localizations.diagHintMcp),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
    );
  }

  Widget _hint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _statusCard(ThemeData theme,
      {required IconData icon,
      required String title,
      required String value,
      String? subtitle,
      required bool ok,
      VoidCallback? onCopy}) {
    final color = ok ? Colors.green : theme.colorScheme.error;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
            if (subtitle != null)
              Text(subtitle,
                  style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
          ],
        ),
        trailing: onCopy == null
            ? null
            : IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: AppLocalizations.of(context)!.copy,
                onPressed: onCopy,
              ),
      ),
    );
  }
}
