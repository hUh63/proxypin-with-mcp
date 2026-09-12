/*
 * AI 请求分析（上游 #582）：把抓包的请求/响应摘要发给 OpenAI 兼容接口，
 * 返回接口功能解读、字段说明与风险提示。
 */

import 'dart:convert';
import 'dart:io' show HttpClient, HttpHeaders;

import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/mcp/mcp_server.dart';

class AiAnalyzer {
  AiAnalyzer._();

  static const String systemPrompt =
      '你是资深 Web/接口安全分析师。分析抓包数据时用简体中文，'
      '输出结构清晰：先一句话概括接口用途，再分「请求要点」「响应要点」「值得注意的风险或异常」三部分，'
      '敏感信息（密钥、token、手机号等）只提示存在并脱敏，不要原文复述。'
      '回答保持简洁专业，支持基于上下文继续追问。';

  static bool get isConfigured {
    final config = Configuration.loaded;
    return config != null && config.aiEnabled && config.aiApiKey.isNotEmpty;
  }

  /// 多轮对话：messages 为 [{role, content}]；agentMode 时注入 ProxyPin 工具协议
  static Future<String> chat(List<Map<String, String>> messages,
      {bool agentMode = false}) async {
    final config = Configuration.loaded;
    if (config == null || !config.aiEnabled || config.aiApiKey.isEmpty) {
      throw Exception('尚未配置 AI 服务：请到「设置 → MCP Connection → AI 分析」填写接口地址与 API Key');
    }

    // 兼容两种填写方式：baseUrl（https://host/v1）或完整接口（.../chat/completions）
    final raw = config.aiBaseUrl.endsWith('/')
        ? config.aiBaseUrl.substring(0, config.aiBaseUrl.length - 1)
        : config.aiBaseUrl;
    final endpoint = raw.toLowerCase().endsWith('/chat/completions')
        ? raw
        : '$raw/chat/completions';

    final client = HttpClient();
    try {
      final request2 = await client.postUrl(Uri.parse(endpoint));
      request2.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request2.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${config.aiApiKey}');
      request2.add(utf8.encode(jsonEncode({
        'model': config.aiModel,
        'temperature': 0.3,
        'messages': [
          {'role': 'system', 'content': agentPrompt(agentMode)},
          ...messages,
        ],
      })));

      final response = await request2.close().timeout(const Duration(seconds: 90));
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        throw Exception('AI 接口返回 ${response.statusCode}：${_truncate(body, 300)}');
      }
      final data = jsonDecode(body);
      final content = data['choices']?[0]?['message']?['content'];
      if (content is! String || content.isEmpty) {
        throw Exception('AI 未返回内容：${_truncate(body, 300)}');
      }
      return content;
    } finally {
      client.close();
    }
  }

  /// Agent 模式附加的工具协议说明（工具清单来自 MCP Server）
  static String agentPrompt(bool agentMode) {
    if (!agentMode) return systemPrompt;
    try {
      final tools = McpServer().getTools();
      final buf = StringBuffer(systemPrompt);
      buf.writeln();
      buf.writeln('\n## ProxyPin 工具调用');
      buf.writeln('当需要查看 ProxyPin 内的抓包数据/配置时，你可以在回复中单独一行输出（可多次）：');
      buf.writeln('<tool>{"name":"工具名","arguments":{...}}</tool>');
      buf.writeln('系统会执行并把结果以 tool_result 回喂给你，之后请基于结果继续回答。仅在你确实需要数据时调用。');
      buf.writeln('可用工具：');
      for (final t in tools) {
        final name = t['name'] ?? '';
        final desc = (t['description'] ?? '').toString();
        buf.writeln('- $name: ${desc.length > 120 ? '${desc.substring(0, 120)}…' : desc}');
      }
      final extra = Configuration.loaded?.aiAgentExtraPrompt ?? '';
      if (extra.trim().isNotEmpty) {
        buf.writeln();
        buf.writeln('## 用户附加指令');
        buf.writeln(extra.trim());
      }
      return buf.toString();
    } catch (_) {
      return systemPrompt;
    }
  }

  /// 单请求分析（封装为一次 chat 调用）
  static Future<String> analyze(HttpRequest request) {
    return chat([
      {'role': 'user', 'content': '请分析这条抓包请求：\n\n${requestSummary(request)}'},
    ]);
  }

  /// 生成请求+响应的分析摘要（供 AI 输入与对话页附加展示）
  static String requestSummary(HttpRequest request) {
    final buf = StringBuffer();
    buf.writeln('${request.method} ${request.requestUrl}');
    try {
      buf.writeln('请求头:');
      request.headers.forEach((k, v) => buf.writeln('  $k: ${_truncate(v.toString(), 200)}'));
    } catch (_) {}
    try {
      final body = request.bodyAsString;
      if (body.isNotEmpty) {
        buf.writeln('请求体(${request.headers.contentType}):');
        buf.writeln(_truncate(body, 3500));
      }
    } catch (_) {}

    final response = request.response;
    if (response != null) {
      buf.writeln();
      buf.writeln('## 响应');
      buf.writeln('状态码: ${response.status.code} ${response.status.reasonPhrase}');
      try {
        response.headers.forEach((k, v) => buf.writeln('  $k: ${_truncate(v.toString(), 200)}'));
      } catch (_) {}
      try {
        final body = response.bodyAsString;
        if (body.isNotEmpty) {
          buf.writeln('响应体:');
          buf.writeln(_truncate(body, 3500));
        }
      } catch (_) {}
    } else {
      buf.writeln();
      buf.writeln('## 响应');
      buf.writeln('（响应尚未返回或未选中）');
    }
    return buf.toString();
  }

  static String _truncate(String s, int max) {
    s = s.trim();
    if (s.length <= max) return s;
    var end = max;
    // 避免在 UTF-16 代理对（emoji/增补字符）中间截断，产生半字符乱码
    if (end > 0 && end < s.length) {
      var unit = s.codeUnitAt(end - 1);
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        end -= 1;
      }
    }
    return '${s.substring(0, end)}…(已截断)';
  }
}
