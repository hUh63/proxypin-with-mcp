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
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/mcp/mcp_bridge.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/rules/websocket_rule_manager.dart';
import 'package:proxypin/ui/component/app_dialog.dart';
import 'package:proxypin/ui/component/json/json_text.dart';
import 'package:proxypin/ui/component/json/json_viewer.dart';
import 'package:proxypin/ui/component/json/theme.dart';
import 'package:proxypin/utils/lang.dart';

import 'websocket_rule_manager_page.dart';

/// WebSocket 拦截管理界面 (v1.6.0+)
/// 显示所有暂停的 WebSocket 消息，支持恢复/中止/修改
class WebSocketInterceptManager extends StatefulWidget {
  const WebSocketInterceptManager({super.key});

  @override
  State<WebSocketInterceptManager> createState() => _WebSocketInterceptManagerState();
}

class _WebSocketInterceptManagerState extends State<WebSocketInterceptManager> {
  List<PausedWebSocketFrame> _pausedMessages = [];
  bool _globalEnabled = false;
  final WebSocketRuleManager _ruleManager = WebSocketRuleManager();

  @override
  void initState() {
    super.initState();
    _initRuleManager();
  }

  Future<void> _initRuleManager() async {
    await _ruleManager.init();
    setState(() {
      _globalEnabled = _ruleManager.globalEnabled;
    });
    _loadPausedMessages();
  }

  void _loadPausedMessages() {
    setState(() {
      _pausedMessages = McpBridge().getPausedWebSocketMessages();
    });
  }

  Future<void> _toggleGlobalEnabled(bool enabled) async {
    await _ruleManager.setGlobalEnabled(enabled);
    setState(() {
      _globalEnabled = enabled;
    });
    if (enabled) {
      _loadPausedMessages();
    }
  }

  void _resumeMessage(PausedWebSocketFrame frame) {
    final appLocalizations = AppLocalizations.of(context)!;
    McpBridge().resumeWebSocketMessage(frame.frameId);
    _loadPausedMessages();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appLocalizations.wsMessageResumed), duration: const Duration(seconds: 1)),
      );
    }
  }

  void _abortMessage(PausedWebSocketFrame frame) {
    final appLocalizations = AppLocalizations.of(context)!;
    // reason 为程序化参数（传给网络/MCP 层），保持固定值，不随界面语言变化
    McpBridge().abortWebSocketMessage(frame.frameId, reason: 'user abort');
    _loadPausedMessages();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appLocalizations.wsMessageAborted), duration: const Duration(seconds: 1)),
      );
    }
  }

  void _editMessage(PausedWebSocketFrame frame) {
    showDialog(
      context: context,
      builder: (context) => _PayloadEditDialog(frame: frame, onSaved: (newPayload) {
        McpBridge().resumeWebSocketMessage(frame.frameId,
            payload: utf8.decode(newPayload, allowMalformed: true));
        _loadPausedMessages();
      }),
    );
  }

  void _navigateToRuleManager() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const WebSocketRuleManagerPage(),
      ),
    ).then((_) {
      // 返回后重新加载规则状态
      _initRuleManager();
      _loadPausedMessages();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appLocalizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(appLocalizations.wsInterceptManagement),
        actions: [
          IconButton(
            icon: const Icon(Icons.rule),
            tooltip: appLocalizations.wsManageRules,
            onPressed: _navigateToRuleManager,
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部控制栏
          _buildControlCard(theme),
          
          // 消息列表
          Expanded(
            child: _pausedMessages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.web_asset_off, size: 64, color: theme.colorScheme.outline),
                        const SizedBox(height: 16),
                        Text(
                          _globalEnabled 
                            ? appLocalizations.wsNoPausedMessages 
                            : appLocalizations.wsGlobalDisabledHint,
                          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _pausedMessages.length,
                    padding: const EdgeInsets.all(8),
                    itemBuilder: (context, index) {
                      final frame = _pausedMessages[index];
                      return _buildMessageCard(frame, theme);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlCard(ThemeData theme) {
    final appLocalizations = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _globalEnabled ? Icons.shield : Icons.shield_outlined,
              color: _globalEnabled ? theme.colorScheme.primary : theme.colorScheme.outline,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appLocalizations.wsGlobalInterceptToggle,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _globalEnabled 
                      ? appLocalizations.wsGlobalEnabledInterceptDesc 
                      : appLocalizations.wsGlobalDisabledDesc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
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
    );
  }

  Widget _buildMessageCard(PausedWebSocketFrame frame, ThemeData theme) {
    final appLocalizations = AppLocalizations.of(context)!;
    final isOutgoing = frame.isOutgoing;
    final duration = DateTime.now().difference(frame.pausedAt);
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isOutgoing 
              ? theme.colorScheme.primaryContainer 
              : theme.colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            isOutgoing ? 'OUT' : 'IN',
            style: theme.textTheme.labelSmall?.copyWith(
              color: isOutgoing 
                ? theme.colorScheme.onPrimaryContainer 
                : theme.colorScheme.onTertiaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          frame.url,
          style: theme.textTheme.bodyMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          appLocalizations.wsPausedInfo(_getOpcodeName(frame.opcode), duration.inSeconds, frame.payloadPreview),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: appLocalizations.wsModifyPayload,
              onPressed: () => _editMessage(frame),
              color: theme.colorScheme.primary,
            ),
            IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: appLocalizations.wsResume,
              onPressed: () => _resumeMessage(frame),
              color: theme.colorScheme.tertiary,
            ),
            IconButton(
              icon: const Icon(Icons.stop),
              tooltip: appLocalizations.wsAbort,
              onPressed: () => _abortMessage(frame),
              color: theme.colorScheme.error,
            ),
          ],
        ),
        children: [
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appLocalizations.wsFullUrl, style: theme.textTheme.labelSmall),
                const SizedBox(height: 4),
                SelectionArea(
                  child: Text(
                    frame.url,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 12),
                Text(appLocalizations.wsPayloadPreview, style: theme.textTheme.labelSmall),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectionArea(
                    child: Text(
                      frame.payloadPreview,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  appLocalizations.wsPausedAt(_formatDateTime(frame.pausedAt)),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getOpcodeName(int opcode) {
    switch (opcode) {
      case 0x01: return 'Text';
      case 0x02: return 'Binary';
      case 0x08: return 'Close';
      case 0x09: return 'Ping';
      case 0x0A: return 'Pong';
      default: return 'Unknown';
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}

/// Payload 编辑对话框
class _PayloadEditDialog extends StatefulWidget {
  final PausedWebSocketFrame frame;
  final Function(Uint8List) onSaved;

  const _PayloadEditDialog({required this.frame, required this.onSaved});

  @override
  State<_PayloadEditDialog> createState() => _PayloadEditDialogState();
}

class _PayloadEditDialogState extends State<_PayloadEditDialog> {
  late TextEditingController _textController;
  String _viewMode = 'text'; // text, json, hex

  @override
  void initState() {
    super.initState();
    try {
      _textController = TextEditingController(text: utf8.decode(widget.frame.payload, allowMalformed: true));
    } catch (e) {
      _textController = TextEditingController(text: '[Binary Data]');
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Uint8List _getPayload() {
    if (_viewMode == 'hex') {
      // HEX 模式解析
      final hex = _textController.text.replaceAll(' ', '').replaceAll('\n', '');
      return Uint8List.fromList(List.generate(hex.length ~/ 2, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)));
    } else if (_viewMode == 'json') {
      // JSON 模式 - 保存为 UTF-8
      return Uint8List.fromList(utf8.encode(_textController.text));
    } else {
      // Text 模式
      return Uint8List.fromList(utf8.encode(_textController.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appLocalizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(appLocalizations.wsModifyPayload),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 视图切换
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'text', label: Text(appLocalizations.text)),
                ButtonSegment(value: 'json', label: Text('JSON')),
                ButtonSegment(value: 'hex', label: Text('HEX')),
              ],
              selected: {_viewMode},
              onSelectionChanged: (Set<String> selected) {
                setState(() {
                  _viewMode = selected.first;
                  if (_viewMode == 'hex') {
                    // 转换为 HEX 显示
                    final hex = widget.frame.payload.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
                    _textController.text = hex.toUpperCase();
                  } else if (_viewMode == 'json') {
                    // 尝试格式化 JSON
                    try {
                      final text = utf8.decode(widget.frame.payload, allowMalformed: true);
                      final json = jsonDecode(text);
                      _textController.text = const JsonEncoder.withIndent('  ').convert(json);
                    } catch (e) {
                      // 不是有效 JSON，保持原样
                    }
                  } else {
                    // Text 模式
                    _textController.text = utf8.decode(widget.frame.payload, allowMalformed: true);
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            // 编辑器
            SizedBox(
              height: 300,
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.all(8),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(appLocalizations.cancel),
        ),
        FilledButton(
          onPressed: () {
            widget.onSaved(_getPayload());
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(appLocalizations.wsPayloadModifiedResumed), duration: const Duration(seconds: 2)),
            );
          },
          child: Text(appLocalizations.wsSaveAndResume),
        ),
      ],
    );
  }
}
