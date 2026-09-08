/*
 * AI 分析对话页（上游 #582）
 * - 完整页面：消息气泡对话 + 多类型多选附件 + AI 配置入口
 * - Agent 模式（开关）：AI 可自动调用 ProxyPin 的 MCP 工具（文本协议 + 自动执行 + 结果回喂）
 * - 附件类型：抓包请求（多选）/ API 端点清单 / 自定义文本
 */
import 'dart:convert';

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/components/ai_analyzer.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/mcp/mcp_bridge.dart';
import 'package:proxypin/network/mcp/mcp_server.dart';
import 'package:proxypin/network/util/api_extractor.dart';

/// 附件：多类型
class _Attachment {
  final String kind; // requests / endpoints / text
  final String label;
  final List<HttpRequest> requests;
  final String content;

  _Attachment.requests(this.requests)
      : kind = 'requests',
        label = '${requests.length} 条请求',
        content = requests
            .map((r) => '【请求】${AiAnalyzer.requestSummary(r)}')
            .join('\n\n');

  _Attachment.endpoints(List<HttpRequest> source)
      : kind = 'endpoints',
        label = 'API 端点清单',
        requests = const [],
        content = _endpointsText(source);

  _Attachment.text(String title, this.content)
      : kind = 'text',
        label = title,
        requests = const [];

  static String _endpointsText(List<HttpRequest> source) {
    final endpoints = ApiExtractor().extract(source);
    if (endpoints.isEmpty) return '（未提取到 API 端点）';
    final buf = StringBuffer('API 端点清单（${endpoints.length} 个，按调用量排序）：\n');
    for (final e in endpoints.take(50)) {
      buf.writeln(
          '- [${e.method}] ${e.domain}${e.path} · 调用 ${e.callCount} 次 · 平均 ${e.avgResponseTime.toStringAsFixed(0)}ms · 成功 ${e.successCount}/错误 ${e.errorCount}');
    }
    if (endpoints.length > 50) buf.writeln('…（其余 ${endpoints.length - 50} 个省略）');
    return buf.toString();
  }
}

/// 对话消息
class _ChatMessage {
  final String role;
  final String content;
  final List<_Attachment> attachments;
  final List<(String, String)> toolCalls; // (工具名, 结果摘要)
  final bool isError;

  /// 发送给 API 的内容：附件内容并入
  String get apiContent {
    if (attachments.isEmpty) return content;
    return '$content\n\n---\n${attachments.map((a) => a.content).join('\n\n')}';
  }

  _ChatMessage({
    required this.role,
    required this.content,
    this.attachments = const [],
    this.toolCalls = const [],
    this.isError = false,
  });
}

/// 会话：支持多对话独立消息列表，可切换/新建/删除
class _AiConversation {
  String title;
  final List<_ChatMessage> messages;
  _AiConversation({this.title = '新对话', List<_ChatMessage>? messages})
      : messages = messages ?? [];
}

class AiChatPage extends StatefulWidget {
  /// 进入页面时自动附加的请求（如从请求长按菜单进入）
  final HttpRequest? initialRequest;

  const AiChatPage({super.key, this.initialRequest});

  @override
  State<StatefulWidget> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // 多对话：会话列表 + 当前索引（_messages 保持原调用点语义 = 当前会话消息）
  final List<_AiConversation> _conversations = [_AiConversation()];
  int _activeConversation = 0;
  List<_ChatMessage> get _messages => _conversations[_activeConversation].messages;
  final List<_Attachment> _attachments = [];
  bool _sending = false;
  bool _agentMode = false;

  @override
  void initState() {
    super.initState();
    _agentMode = Configuration.loaded?.aiAgentEnabled ?? false;
    final initial = widget.initialRequest;
    if (initial != null) {
      _attachments.add(_Attachment.requests([initial]));
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ==================== 多对话管理 ====================

  /// 清除并关闭当前对话（消息清空，保留会话继续使用）
  Future<void> _clearCurrentConversation() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除当前对话', style: TextStyle(fontSize: 16)),
        content: const Text('将清空当前对话的全部消息，且不可恢复。', style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _conversations[_activeConversation]
        ..messages.clear()
        ..title = '新对话';
    });
  }

  /// 新建对话并切换
  void _newConversation() {
    setState(() {
      _conversations.add(_AiConversation());
      _activeConversation = _conversations.length - 1;
    });
    Navigator.of(context).pop(); // 关闭会话列表
  }

  /// 删除会话（至少保留一个）
  void _deleteConversation(int index) {
    if (_conversations.length <= 1) {
      _conversations[0]..messages.clear()..title = '新对话';
      _activeConversation = 0;
    } else {
      _conversations.removeAt(index);
      if (_activeConversation >= _conversations.length) {
        _activeConversation = _conversations.length - 1;
      } else if (_activeConversation > index) {
        _activeConversation--;
      }
    }
  }

  /// 会话列表：切换 / 新建 / 删除
  Future<void> _showConversationSheet() async {
    await showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                child: Row(children: [
                  const Expanded(
                      child: Text('对话列表',
                          style: TextStyle(fontWeight: FontWeight.w600))),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _clearCurrentConversation();
                    },
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('清除当前', style: TextStyle(fontSize: 13)),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _newConversation();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新建对话', style: TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _conversations.length,
                  itemBuilder: (context, index) {
                    final conv = _conversations[index];
                    final active = index == _activeConversation;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        active ? Icons.chat_bubble : Icons.chat_bubble_outline,
                        size: 20,
                        color: active ? Theme.of(context).colorScheme.primary : null,
                      ),
                      title: Text(
                        conv.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: active ? FontWeight.w600 : null),
                      ),
                      subtitle: Text('${conv.messages.length} 条消息',
                          style: const TextStyle(fontSize: 11)),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: '关闭并清除该对话',
                        onPressed: () {
                          setSheetState(() => _deleteConversation(index));
                          if (mounted) setState(() {});
                        },
                      ),
                      onTap: () {
                        setState(() => _activeConversation = index);
                        Navigator.of(sheetContext).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 附件选择 ====================

  Future<void> _pickAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
              padding: EdgeInsets.all(12),
              child: Text('选择要附加的信息', style: TextStyle(fontWeight: FontWeight.w600))),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('抓包请求'),
            subtitle: const Text('从最近 30 条中多选', style: TextStyle(fontSize: 12)),
            onTap: () => Navigator.pop(context, 'requests'),
          ),
          ListTile(
            leading: const Icon(Icons.api),
            title: const Text('API 端点清单'),
            subtitle: const Text('自动提取全部端点与统计', style: TextStyle(fontSize: 12)),
            onTap: () => Navigator.pop(context, 'endpoints'),
          ),
          ListTile(
            leading: const Icon(Icons.notes),
            title: const Text('自定义文本'),
            subtitle: const Text('粘贴任意内容作为上下文', style: TextStyle(fontSize: 12)),
            onTap: () => Navigator.pop(context, 'text'),
          ),
        ]),
      ),
    );
    if (choice == 'requests') {
      await _pickRequests();
    } else if (choice == 'endpoints') {
      final source = McpBridge().getRecentRequests(limit: 200);
      if (source.isEmpty) {
        if (mounted) FlutterToastr.show('暂无抓包请求', context);
        return;
      }
      setState(() => _attachments.add(_Attachment.endpoints(source)));
    } else if (choice == 'text') {
      await _pickCustomText();
    }
  }

  /// 多选抓包请求
  Future<void> _pickRequests() async {
    final requests = McpBridge().getRecentRequests(limit: 30);
    if (requests.isEmpty) {
      FlutterToastr.show('暂无抓包请求', context);
      return;
    }
    final selected = <HttpRequest>{};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const Text('选择抓包请求（可多选）', style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                      onPressed: () => Navigator.pop(context, selected.isNotEmpty),
                      child: const Text('确定')),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final req = requests[index];
                    final checked = selected.contains(req);
                    return CheckboxListTile(
                      dense: true,
                      value: checked,
                      controlAffinity: ListTileControlAffinity.trailing,
                      secondary: Text(req.method.name,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      title: Text(req.requestUrl,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                      subtitle: req.response != null
                          ? Text('状态码 ${req.response!.status.code}',
                              style: const TextStyle(fontSize: 11))
                          : const Text('未响应', style: TextStyle(fontSize: 11)),
                      onChanged: (v) => setSheet(() {
                        v == true ? selected.add(req) : selected.remove(req);
                      }),
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok == true && selected.isNotEmpty) {
      setState(() => _attachments.add(_Attachment.requests(selected.toList())));
    }
  }

  /// 自定义文本附件
  Future<void> _pickCustomText() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义文本', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '粘贴任意内容作为 AI 的上下文',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('确定')),
        ],
      ),
    );
    if (text != null && text.isNotEmpty) {
      setState(() => _attachments.add(_Attachment.text('文本', text)));
    }
  }

  // ==================== 发送与 Agent 循环 ====================

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    if (!AiAnalyzer.isConfigured) {
      final saved = await showAiSettingsDialog(context);
      if (saved != true || !AiAnalyzer.isConfigured) return;
    }

    final attachments = List<_Attachment>.from(_attachments);
    // 捕获当前会话对象：异步等待期间切换/删除会话，本次消息仍归属原会话
    final conv = _conversations[_activeConversation];
    setState(() {
      // 首条消息自动命名会话
      if (conv.messages.isEmpty && conv.title == '新对话') {
        conv.title = text.length > 14 ? '${text.substring(0, 14)}…' : text;
      }
      conv.messages.add(_ChatMessage(role: 'user', content: text, attachments: attachments));
      _attachments.clear();
      _inputController.clear();
      _sending = true;
    });
    _scrollToBottom();

    // 组装 API 消息（附件并入 user 内容）
    final apiMessages = conv.messages.map((m) => {'role': m.role, 'content': m.apiContent}).toList();

    try {
      var round = 0;
      final maxRounds = Configuration.loaded?.aiAgentMaxRounds.clamp(1, 8) ?? 3;
      while (true) {
        final reply = await AiAnalyzer.chat(apiMessages,
            agentMode: _agentMode && round < maxRounds);

        final calls = _agentMode ? _parseToolCalls(reply) : const <_ToolCall>[];
        setState(() {
          conv.messages.add(_ChatMessage(
            role: 'assistant',
            content: _stripToolTags(reply),
            toolCalls: calls.map((c) => (c.name, '')).toList(),
          ));
        });
        _scrollToBottom();

        if (calls.isEmpty || !_agentMode) break;
        round++;
        if (round >= maxRounds) break;

        // 执行工具并回喂结果
        var resultText = '';
        for (final call in calls) {
          try {
            final result = await McpServer().executeTool(call.name, call.arguments);
            resultText += '<tool_result name="${call.name}">\n${_truncateJson(result)}\n</tool_result>\n';
          } catch (e) {
            resultText += '<tool_result name="${call.name}">执行失败: $e</tool_result>\n';
          }
        }
        apiMessages.add({'role': 'assistant', 'content': reply});
        apiMessages.add({'role': 'user', 'content': '工具执行结果：\n$resultText\n请基于以上结果继续回答。'});
      }
    } catch (e) {
      setState(() {
        if (mounted) {
          conv.messages.add(_ChatMessage(role: 'assistant', content: '分析失败：$e', isError: true));
        }
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    _scrollToBottom();
  }

  /// 解析 AI 回复中的 <tool>{...}</tool> 调用
  List<_ToolCall> _parseToolCalls(String reply) {
    final result = <_ToolCall>[];
    final regex = RegExp(r'<tool>\s*(\{.*?\})\s*</tool>', dotAll: true);
    for (final match in regex.allMatches(reply)) {
      try {
        final data = jsonDecode(match.group(1)!);
        if (data is Map<String, dynamic> && data['name'] is String) {
          result.add(_ToolCall(
            data['name'] as String,
            data['arguments'] is Map<String, dynamic>
                ? data['arguments'] as Map<String, dynamic>
                : <String, dynamic>{},
          ));
        }
      } catch (_) {}
    }
    return result;
  }

  String _stripToolTags(String reply) =>
      reply.replaceAll(RegExp(r'<tool>\s*\{.*?\}\s*</tool>', dotAll: true), '').trim();

  String _truncateJson(dynamic result) {
    var s = result is String ? result : jsonEncode(result);
    return s.length <= 4000 ? s : '${s.substring(0, 4000)}…(已截断)';
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI分析', style: TextStyle(fontSize: 16, overflow: TextOverflow.ellipsis)),
        centerTitle: true,
        actions: [
          // Agent 模式开关：AI 自动调用 ProxyPin 功能
          Tooltip(
            message: _agentMode ? 'Agent 模式已开启：AI 可自动调用 ProxyPin 功能' : 'Agent 模式已关闭：仅接收手动消息',
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                setState(() => _agentMode = !_agentMode);
                final config = Configuration.loaded;
                if (config != null) {
                  config.aiAgentEnabled = _agentMode;
                  config.flushConfig();
                }
                FlutterToastr.show(
                  _agentMode ? 'Agent 模式已开启，AI 可自动调用 ProxyPin 功能' : 'Agent 模式已关闭，仅接收手动消息',
                  context,
                  backgroundColor: _agentMode ? Colors.green : Colors.grey,
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.smart_toy_outlined,
                  size: 22,
                  color: _agentMode ? cs.primary : cs.outline,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.attach_file, size: 20),
            tooltip: '附加信息（可多选）',
            onPressed: _pickAttachment,
          ),
          // 多对话管理：新建 / 切换 / 删除 / 清除当前
          IconButton(
            icon: const Icon(Icons.forum_outlined, size: 20),
            tooltip: '对话列表（新建/切换/删除/清除）',
            onPressed: _showConversationSheet,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: 'AI 配置',
            onPressed: () async {
              await showAiSettingsDialog(context);
              setState(() {});
            },
          ),
        ],
      ),
      body: Column(children: [
        // 附件提示条
        if (_attachments.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final a in _attachments)
                  InputChip(
                    label: Text('${a.kind == 'requests' ? '📎' : a.kind == 'endpoints' ? '📊' : '📝'} ${a.label}',
                        style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    onDeleted: () => setState(() => _attachments.remove(a)),
                  ),
              ],
            ),
          ),
        // 消息区
        Expanded(
          child: _messages.isEmpty
              ? _emptyState(cs)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) => _bubble(_messages[index]),
                ),
        ),
        if (_sending)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('AI 正在思考…', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ),
        // 输入区
        SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: _agentMode ? '提问（Agent 模式：AI 可自动查数据）' : '输入问题',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send, size: 18),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _emptyState(ColorScheme cs) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.auto_awesome, size: 44, color: cs.primary.withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        const Text('与 AI 对话分析抓包数据', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Text('点击右上角 📎 附加多条请求 / 端点清单 / 文本',
            style: TextStyle(fontSize: 12, color: cs.outline)),
        const SizedBox(height: 4),
        Text('开启 🤖 Agent 模式可让 AI 自动调用 ProxyPin 功能',
            style: TextStyle(fontSize: 12, color: cs.outline)),
      ]),
    );
  }

  Widget _bubble(_ChatMessage msg) {
    final isUser = msg.role == 'user';
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: msg.isError
              ? cs.errorContainer.withValues(alpha: 0.5)
              : isUser
                  ? cs.primary.withValues(alpha: 0.12)
                  : cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isUser ? 12 : 3),
            bottomRight: Radius.circular(isUser ? 3 : 12),
          ),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 附件标签
          for (final a in msg.attachments)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${a.kind == 'requests' ? '📎' : a.kind == 'endpoints' ? '📊' : '📝'} ${a.label}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: cs.primary, fontStyle: FontStyle.italic),
              ),
            ),
          SelectableText(
            msg.content,
            style: TextStyle(fontSize: 13.5, height: 1.45, color: msg.isError ? cs.error : null),
          ),
          // Agent 工具调用记录
          for (final (name, _) in msg.toolCalls)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.build_circle_outlined, size: 12, color: cs.tertiary),
                const SizedBox(width: 4),
                Text('已调用工具 $name', style: TextStyle(fontSize: 11, color: cs.tertiary)),
              ]),
            ),
          if (!isUser && !msg.isError) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: msg.content));
                FlutterToastr.show('已复制', context);
              },
              child: Icon(Icons.copy, size: 13, color: cs.outline),
            ),
          ],
        ]),
      ),
    );
  }
}

class _ToolCall {
  final String name;
  final Map<String, dynamic> arguments;
  _ToolCall(this.name, this.arguments);
}

/// AI 服务商预设
class _AiProvider {
  final String name;
  final String baseUrl;
  final String modelHint;
  const _AiProvider(this.name, this.baseUrl, this.modelHint);
}

const _aiProviders = [
  _AiProvider('OpenAI', 'https://api.openai.com/v1', 'gpt-4o-mini'),
  _AiProvider('DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat'),
  _AiProvider('通义千问', 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen-plus'),
  _AiProvider('Kimi', 'https://api.moonshot.cn/v1', 'moonshot-v1-8k'),
  _AiProvider('智谱 GLM', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4-flash'),
  _AiProvider('Ollama 本地', 'http://127.0.0.1:11434/v1', 'llama3.1'),
];

/// AI 配置编辑（服务商预设 / 自定义 / 文件导入），返回 true 表示已保存
Future<bool?> showAiSettingsDialog(BuildContext context) async {
  final config = Configuration.loaded;
  if (config == null) return false;
  final baseUrlController = TextEditingController(text: config.aiBaseUrl);
  final keyController = TextEditingController(text: config.aiApiKey);
  final modelController = TextEditingController(text: config.aiModel);
  final extraPromptController = TextEditingController(text: config.aiAgentExtraPrompt);
  var enabled = config.aiEnabled;
  String selectedProvider =
      _aiProviders.any((p) => p.baseUrl == config.aiBaseUrl) ? config.aiBaseUrl : 'custom';

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('AI 分析配置', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用 AI 分析', style: TextStyle(fontSize: 14)),
                subtitle: const Text('OpenAI 兼容接口，数据将发送到你配置的服务',
                    style: TextStyle(fontSize: 12)),
                value: enabled,
                onChanged: (v) => setState(() => enabled = v),
              ),
              const SizedBox(height: 4),
              const Text('服务商', style: TextStyle(fontSize: 12, color: Colors.grey)),
              DropdownButtonFormField<String>(
                  isExpanded: true,
                value: selectedProvider,
                isDense: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: [
                  for (final p in _aiProviders)
                    DropdownMenuItem(value: p.baseUrl, child: Text(p.name, style: const TextStyle(fontSize: 13))),
                  const DropdownMenuItem(value: 'custom', child: Text('自定义服务…', style: TextStyle(fontSize: 13))),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    selectedProvider = v;
                    if (v != 'custom') {
                      final p = _aiProviders.firstWhere((p) => p.baseUrl == v);
                      baseUrlController.text = p.baseUrl;
                      if (modelController.text.isEmpty ||
                          _aiProviders.any((p) => p.modelHint == modelController.text)) {
                        modelController.text = p.modelHint;
                      }
                    }
                  });
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: baseUrlController,
                enabled: selectedProvider == 'custom',
                decoration: InputDecoration(
                  labelText: '接口地址 (Base URL)',
                  hintText: 'https://api.openai.com/v1',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  helperText: selectedProvider == 'custom' ? '自定义服务商，填 OpenAI 兼容地址' : null,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: keyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: modelController,
                decoration: const InputDecoration(
                  labelText: '模型',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Text('Agent 模式', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text('开启 🤖 后 AI 可自动调用 ProxyPin 工具查数据',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              Text('最大工具轮数：${config.aiAgentMaxRounds}',
                  style: const TextStyle(fontSize: 12)),
              Slider(
                value: config.aiAgentMaxRounds.toDouble(),
                min: 1,
                max: 8,
                divisions: 7,
                label: '${config.aiAgentMaxRounds}',
                onChanged: (v) => setState(() => config.aiAgentMaxRounds = v.round()),
              ),
              TextField(
                controller: extraPromptController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Agent 附加指令',
                  hintText: '如：优先检查安全风险；只看 POST 请求…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              // 从文件导入配置
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final file = await FilePicker.pickFile(type: FileType.any);
                    if (file?.path == null) return;
                    final content = await File(file!.path!).readAsString();
                    final data = jsonDecode(content);
                    if (data is! Map<String, dynamic>) throw Exception('格式需为 JSON 对象');
                    setState(() {
                      if (data['baseUrl'] is String) {
                        baseUrlController.text = data['baseUrl'];
                        selectedProvider = _aiProviders.any((p) => p.baseUrl == data['baseUrl'])
                            ? data['baseUrl']
                            : 'custom';
                      }
                      if (data['apiKey'] is String) keyController.text = data['apiKey'];
                      if (data['model'] is String) modelController.text = data['model'];
                      if (data['enabled'] is bool) enabled = data['enabled'];
                    });
                    if (context.mounted) FlutterToastr.show('配置已导入', context, backgroundColor: Colors.green);
                  } catch (e) {
                    if (context.mounted) {
                      FlutterToastr.show('导入失败：$e', context, backgroundColor: Colors.red);
                    }
                  }
                },
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('从文件导入配置 (JSON)'),
              ),
              const Text(
                'JSON 格式：{"baseUrl": "...", "apiKey": "...", "model": "...", "enabled": true}',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              config.aiEnabled = enabled;
              config.aiBaseUrl = baseUrlController.text.trim();
              config.aiApiKey = keyController.text.trim();
              config.aiModel = modelController.text.trim().isEmpty ? 'gpt-4o-mini' : modelController.text.trim();
              config.aiAgentExtraPrompt = extraPromptController.text.trim();
              config.flushConfig();
              Navigator.pop(context, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );

  if (result == true && context.mounted) {
    FlutterToastr.show('AI 配置已保存', context, backgroundColor: Colors.green);
  }
  return result;
}
