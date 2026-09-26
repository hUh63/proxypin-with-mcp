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
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/mcp/mcp_server.dart';
import 'package:proxypin/ui/desktop/toolbar/mcp_panel.dart';
import 'package:proxypin/ui/component/multi_window.dart';
import 'package:proxypin/ui/desktop/setting/mcp_automation.dart';

/// 桌面端 MCP 连接设置页面
class DesktopMcpConnection extends StatefulWidget {
  final Configuration configuration;

  const DesktopMcpConnection({super.key, required this.configuration});

  @override
  State<DesktopMcpConnection> createState() => _DesktopMcpConnectionState();
}

class _DesktopMcpConnectionState extends State<DesktopMcpConnection> {
  bool _loading = true;
  String? _deviceIp;
  late TextEditingController _portController;
  int _configuredPort = 9010;
  bool _mcpEnabled = true;
  bool _mcpAutoStart = false;
  Map<String, bool> _toolsEnabled = {};

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController(text: '9010');
    McpServer().onStatusChanged = _onMcpStatusChanged;
    _loadInfo();
  }

  @override
  void dispose() {
    McpServer().onStatusChanged = null;
    _portController.dispose();
    super.dispose();
  }

  void _onMcpStatusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadInfo() async {
    setState(() => _loading = true);
    try {
      _deviceIp = await _getLocalIp();
      _configuredPort = widget.configuration.mcpPort;
      _mcpEnabled = widget.configuration.mcpEnabled;
      _mcpAutoStart = widget.configuration.mcpAutoStart;
      _toolsEnabled = Map<String, bool>.from(widget.configuration.mcpToolsEnabled);
      _portController.text = _configuredPort.toString();
    } catch (e) {
      // ignore
    }
    setState(() => _loading = false);
  }

  Future<String> _getLocalIp() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
        return result.first.address;
      }
    } catch (e) {
      // ignore
    }
    return '127.0.0.1';
  }

  Future<void> _toggleMcpService(bool enabled) async {
    widget.configuration.mcpEnabled = enabled;
    await widget.configuration.flushConfig();

    if (enabled) {
      await McpServer().start();
    } else {
      await McpServer().stop();
    }

    setState(() {
      _mcpEnabled = enabled;
    });
  }

  Future<void> _toggleAutoStart(bool enabled) async {
    widget.configuration.mcpAutoStart = enabled;
    await widget.configuration.flushConfig();
    setState(() {
      _mcpAutoStart = enabled;
    });
  }

  Future<void> _toggleTool(String name, bool enabled) async {
    widget.configuration.mcpToolsEnabled[name] = enabled;
    await widget.configuration.flushConfig();
    setState(() {
      _toolsEnabled[name] = enabled;
    });
  }

  Future<void> _applyPort() async {
    final loc = AppLocalizations.of(context)!;
    final newPort = int.tryParse(_portController.text.trim());
    if (newPort == null || newPort < 1 || newPort > 65535) {
      _showSnackBar(loc.mcpPortInvalid);
      return;
    }

    if (newPort == _configuredPort) {
      _showSnackBar(loc.mcpPortUnchanged);
      return;
    }

    widget.configuration.mcpPort = newPort;
    await widget.configuration.flushConfig();

    if (widget.configuration.mcpEnabled) {
      await McpServer().restart();
    }

    setState(() {
      _configuredPort = newPort;
    });
    _showSnackBar(loc.mcpPortApplied(newPort.toString()));
  }

  void _copyText(String text, String tip) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnackBar(tip);
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final mcpServer = McpServer();
    final port = _configuredPort;
    final ip = _deviceIp ?? '127.0.0.1';
    final apiUrl = 'http://$ip:$port/mcp';
    final sseUrl = 'http://$ip:$port/sse';
    final isRunning = mcpServer.isRunning;
    final lastError = mcpServer.lastError;

    final configJson = const JsonEncoder.withIndent('  ').convert({
      'mcpServers': {
        'proxypin': {'url': apiUrl},
      },
    });

    final tools = mcpServer.getTools();

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.desktopMcpConnection),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            onPressed: () => McpServiceDialog.show(context, ProxyServer.current!),
            tooltip: loc.mcpConnDeskClientWizard,
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            onPressed: () {
              MultiWindow.openWindow(loc.mcpAutoTitle, 'McpAutomationWidget', size: const Size(900, 700));
            },
            tooltip: loc.mcpConnAutomationConfig,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // 远程接入安全：局域网暴露与 Bearer 鉴权
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: Text(loc.mcpAllowLan),
                        subtitle: Text(loc.mcpConnAllowLanHint, style: const TextStyle(fontSize: 12)),
                        value: widget.configuration.mcpAllowLan,
                        onChanged: (v) async {
                          setState(() => widget.configuration.mcpAllowLan = v);
                          ConfigAutoSave.markChanged();
                          // 开、关都要重启：只处理「开」会让服务在关闭后继续监听 0.0.0.0。
                          // 未运行的实例不必被这个开关拉起来，下次启动时应用配置即可。
                          if (McpServer().isRunning) await McpServer().restart();
                        },
                      ),
                      const Divider(height: 0),
                      SwitchListTile(
                        title: Text(loc.mcpConnTokenAuth),
                        subtitle: Text(
                          widget.configuration.mcpAuthEnabled
                              ? loc.mcpConnTokenAuthRequired
                              : loc.mcpConnTokenAuthDisabled,
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.configuration.mcpAuthEnabled ? null : Colors.red,
                          ),
                        ),
                        value: widget.configuration.mcpAuthEnabled,
                        onChanged: (v) async {
                          setState(() => widget.configuration.mcpAuthEnabled = v);
                          ConfigAutoSave.markChanged();
                          if (McpServer().isRunning) await McpServer().restart();
                        },
                      ),
                      const Divider(height: 0),
                      SwitchListTile(
                        title: Text(loc.mcpConnKeepAlive),
                        subtitle: Text(
                            loc.mcpConnKeepAliveDesc,
                            style: const TextStyle(fontSize: 12)),
                        value: widget.configuration.mcpKeepAlive,
                        onChanged: (v) async {
                          setState(() => widget.configuration.mcpKeepAlive = v);
                          ConfigAutoSave.markChanged();
                          try {
                            await McpServer().setKeepAlive(v);
                          } catch (e) {
                            debugPrint('keep-alive failed: $e');
                          }
                        },
                      ),
                      const Divider(height: 0),
                      SwitchListTile(
                        title: Text(loc.mcpConnStrictValidation),
                        subtitle: Text(loc.mcpConnStrictValidationDesc,
                            style: const TextStyle(fontSize: 12)),
                        value: widget.configuration.mcpStrictValidation,
                        onChanged: (v) async {
                          setState(() => widget.configuration.mcpStrictValidation = v);
                          ConfigAutoSave.markChanged();
                          McpServer().setStrictValidation(v);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // MCP 服务开关与端口配置
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: Text(loc.mcpService),
                        subtitle: Text(
                          _mcpEnabled
                              ? (isRunning
                                    ? loc.mcpServiceRunning(port.toString())
                                    : (lastError != null
                                          ? loc.mcpServiceError(lastError)
                                          : loc.mcpServiceEnabledNotRunning))
                              : loc.mcpServiceDisabled,
                          style: const TextStyle(fontSize: 12),
                        ),
                        secondary: Icon(
                          _mcpEnabled
                              ? (isRunning ? Icons.cloud_done : Icons.cloud_queue)
                              : Icons.cloud_off,
                          color: _mcpEnabled
                              ? (isRunning ? Colors.green : Colors.orange)
                              : Colors.grey,
                        ),
                        value: _mcpEnabled,
                        onChanged: _toggleMcpService,
                      ),
                      const Divider(height: 0),
                      SwitchListTile(
                        title: Text(loc.mcpConnAutoStart),
                        subtitle: Text(
                          loc.mcpAutoStartDescribe,
                          style: const TextStyle(fontSize: 12),
                        ),
                        secondary: const Icon(Icons.power, color: Colors.blue),
                        value: _mcpAutoStart,
                        onChanged: _toggleAutoStart,
                      ),
                      const Divider(height: 0),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(loc.mcpConnDeskPortConfig, style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _portController,
                                    decoration: InputDecoration(
                                      labelText: loc.mcpConnDeskServicePort,
                                      hintText: '9010',
                                      border: const OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                ElevatedButton(
                                  onPressed: _applyPort,
                                  child: Text(loc.securityAiApply),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 连接信息
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(loc.mcpConnConnectionInfo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 16),
                        _buildInfoRow('MCP URL', apiUrl, Icons.link),
                        const SizedBox(height: 8),
                        _buildInfoRow('SSE URL', sseUrl, Icons.http),
                        const SizedBox(height: 8),
                        _buildInfoRow(loc.mcpConnDeskIpAddress, ip, Icons.wifi),
                        const SizedBox(height: 8),
                        _buildInfoRow(loc.mcpPort, port.toString(), Icons.settings),
                        const SizedBox(height: 8),
                        _buildInfoRow(loc.mcpStatus, isRunning ? loc.mcpStatusRunning : loc.mcpStatusStopped, isRunning ? Icons.check_circle : Icons.stop),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // AI 配置指南
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(loc.mcpConnAiConfigGuide, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 12),
                        Text(
                          loc.mcpConnDeskAiConfigHint,
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: SelectableText(
                            configJson,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () => _copyText(configJson, loc.mcpConnDeskConfigCopied),
                              icon: const Icon(Icons.copy, size: 16),
                              label: Text(loc.mcpConnDeskCopyConfig),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 控制模式
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(loc.mcpConnControlMode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 12),
                        Text(
                          loc.mcpConnDeskControlModeDesc,
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        _buildModeItem(
                          loc.mcpConnDeskModeMcpTitle,
                          loc.mcpConnDeskModeMcpDesc,
                          Icons.star,
                          Colors.blue,
                        ),
                        const SizedBox(height: 8),
                        _buildModeItem(
                          'SSE',
                          loc.mcpConnDeskModeSseDesc,
                          Icons.stream,
                          Colors.orange,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 可用工具列表
                if (tools.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(loc.mcpConnAvailableTools, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          ...tools.map((tool) {
                            final name = tool['name'] as String;
                            final description = tool['description'] as String?;
                            return SwitchListTile(
                              title: Text(name),
                              subtitle: Text(description ?? ''),
                              value: _toolsEnabled[name] ?? true,
                              onChanged: (value) => _toggleTool(name, value),
                              dense: true,
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    final loc = AppLocalizations.of(context)!;
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 16),
          onPressed: () => _copyText(value, loc.mcpCopied),
          tooltip: loc.mcpCopy,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  Widget _buildModeItem(String title, String desc, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
                Text(
                  desc,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
