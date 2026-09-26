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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/components/ai_analyzer.dart';
import 'package:proxypin/network/util/security_audit.dart';
import 'package:proxypin/ui/component/utils.dart';

/// 安全自检的 AI 分析。
///
/// 把自检结果（问题清单，不含响应体原文）交给 AI，拿回风险解读与修复建议。
/// 建议里若包含**调整 ProxyPin 自身设置**的动作，只允许从 [allowedActions]
/// 白名单里挑；应用前一律弹确认 —— 不做静默改配置。
class SecurityAiDialog extends StatefulWidget {
  final SecurityAuditReport report;

  const SecurityAiDialog({super.key, required this.report});

  /// AI 允许建议的配置项（key → 中文说明 + 两种取值的安全含义）
  static const Map<String, String> allowedActions = {
    'enableSsl': 'enableSsl —— 开启 SSL 抓包（不解密 HTTPS 就看不出很多问题）',
    'enableSystemProxy': 'enableSystemProxy —— 开启系统代理',
    'antiCacheEnabled': 'antiCacheEnabled —— 开启防缓存',
    'mcpAllowLan': 'mcpAllowLan —— 允许局域网访问 MCP（关掉更安全）',
    'mcpAuthEnabled': 'mcpAuthEnabled —— MCP 要求鉴权（打开更安全）',
  };

  static String labelOf(BuildContext context, String key) {
    final loc = AppLocalizations.of(context)!;
    switch (key) {
      case 'enableSsl':
        return loc.securityAiActionEnableSsl;
      case 'enableSystemProxy':
        return loc.securityAiActionEnableSystemProxy;
      case 'antiCacheEnabled':
        return loc.securityAiActionAntiCache;
      case 'mcpAllowLan':
        return loc.securityAiActionMcpAllowLan;
      case 'mcpAuthEnabled':
        return loc.securityAiActionMcpAuth;
      default:
        return key;
    }
  }

  /// 把白名单动作写进真实配置（只有这些 key 会被接受）
  static bool applyAction(String key, bool value) {
    final config = Configuration.loaded;
    if (config == null) return false;
    switch (key) {
      case 'enableSsl':
        config.enableSsl = value;
        break;
      case 'enableSystemProxy':
        config.enableSystemProxy = value;
        break;
      case 'antiCacheEnabled':
        config.antiCacheEnabled = value;
        break;
      case 'mcpAllowLan':
        config.mcpAllowLan = value;
        break;
      case 'mcpAuthEnabled':
        config.mcpAuthEnabled = value;
        break;
      default:
        return false;
    }
    config.flushConfig();
    return true;
  }

  @override
  State<SecurityAiDialog> createState() => _SecurityAiDialogState();
}

class _SecurityAiDialogState extends State<SecurityAiDialog> {
  bool _loading = false;
  String? _error;
  String _raw = '';
  _AiAdvice? _advice;

  Future<void> _analyze() async {
    if (!AiAnalyzer.isConfigured) {
      setState(() => _error = AppLocalizations.of(context)!.securityAiNotConfigured);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = await AiAnalyzer.chat([
        {'role': 'user', 'content': _prompt()},
      ]);
      if (!mounted) return;
      setState(() {
        _raw = text;
        _advice = _AiAdvice.tryParse(text);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 只发送问题描述，不发响应体原文
  String _prompt() {
    final b = StringBuffer();
    b.writeln('以下是 ProxyPin 对用户**已抓流量**做被动基线核查的结果'
        '（不含响应体原文，敏感值已脱敏）。请分析并给建议。');
    b.writeln();
    b.writeln('扫描请求数：${widget.report.scannedRequests}');
    b.writeln('发现问题数：${widget.report.issues.length}');
    b.writeln('分类统计：${widget.report.byCategory}');
    b.writeln();
    for (final issue in widget.report.issues.take(40)) {
      b.writeln('- [${issue.severity.name}] ${issue.title} @ ${issue.method} ${issue.url}');
      b.writeln('  详情：${issue.detail}');
    }
    if (widget.report.issues.length > 40) {
      b.writeln('（其余 ${widget.report.issues.length - 40} 条略）');
    }
    b.writeln();
    b.writeln('另外，如果你认为需要调整 ProxyPin 自身设置，只能从下面这份白名单里挑，'
        '没有合适的就返回空数组：');
    SecurityAiDialog.allowedActions.forEach((k, v) => b.writeln('- $v'));
    b.writeln();
    b.writeln('严格按下面这个 JSON 输出，不要加任何其他文字或代码块标记：');
    b.writeln(
        '{"summary":"一句话总结","risks":["最值得先处理的点"],"advice":["可落地的修复建议"],'
        '"actions":[{"key":"enableSsl","value":true,"reason":"为什么"}]}');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.securityAiTitle,
          style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error != null)
                      Text(_error!,
                          style: const TextStyle(fontSize: 12, color: Colors.red)),
                    if (_advice != null) ..._adviceWidgets(_advice!),
                    if (_advice == null && _raw.isNotEmpty) ...[
                      Text(AppLocalizations.of(context)!.securityAiRawFallback,
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 6),
                      SelectableText(_raw, style: const TextStyle(fontSize: 12.5, height: 1.5)),
                    ],
                  ],
                ),
        ),
      ),
      actions: [
        if (_raw.isNotEmpty)
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _raw));
              FlutterToastr.show(
                  AppLocalizations.of(context)!.securityAiCopied, context);
            },
            child: Text(AppLocalizations.of(context)!.copy),
          ),
        TextButton(
          onPressed: _loading ? null : _analyze,
          child: Text(_raw.isEmpty && !_loading
              ? AppLocalizations.of(context)!.securityAiAnalyze
              : AppLocalizations.of(context)!.securityAiReanalyze),
        ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.close)),
      ],
    );
  }

  List<Widget> _adviceWidgets(_AiAdvice advice) {
    final widgets = <Widget>[];
    if (advice.summary.isNotEmpty) {
      widgets.add(Text(advice.summary,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)));
      widgets.add(const SizedBox(height: 10));
    }
    if (advice.risks.isNotEmpty) {
      widgets.add(Text(AppLocalizations.of(context)!.securityAiTopRisks,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)));
      for (final r in advice.risks) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text('• $r', style: const TextStyle(fontSize: 12.5, height: 1.4)),
        ));
      }
      widgets.add(const SizedBox(height: 10));
    }
    if (advice.advice.isNotEmpty) {
      widgets.add(Text(AppLocalizations.of(context)!.securityAiFixes,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)));
      for (final a in advice.advice) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text('• $a', style: const TextStyle(fontSize: 12.5, height: 1.4)),
        ));
      }
      widgets.add(const SizedBox(height: 10));
    }
    if (advice.actions.isNotEmpty) {
      widgets.add(Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context)!.securityAiActionsHeader,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final action in advice.actions) _actionRow(action),
          ],
        ),
      ));
    }
    return widgets;
  }

  Widget _actionRow(_AiAction action) {
    final label = SecurityAiDialog.labelOf(context, action.key);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '$label → ${action.value ? AppLocalizations.of(context)!.securityAiStateOn : AppLocalizations.of(context)!.securityAiStateOff}',
                  style: const TextStyle(fontSize: 12.5)),
              if (action.reason.isNotEmpty)
                Text(action.reason,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
        TextButton(
          onPressed: () => _confirmApply(action),
          child: Text(AppLocalizations.of(context)!.securityAiApply,
              style: const TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }

  void _confirmApply(_AiAction action) {
    showConfirmDialog(
      context,
      title: AppLocalizations.of(context)!.securityAiApplyTitle,
      content: AppLocalizations.of(context)!.securityAiApplyConfirm(
          SecurityAiDialog.labelOf(context, action.key),
          action.value
              ? AppLocalizations.of(context)!.securityAiStateOn
              : AppLocalizations.of(context)!.securityAiStateOff,
          action.reason),
      onConfirm: () {
        final ok = SecurityAiDialog.applyAction(action.key, action.value);
        FlutterToastr.show(
            ok
                ? AppLocalizations.of(context)!.securityAiApplied
                : AppLocalizations.of(context)!.securityAiApplyUnsupported,
            context,
            backgroundColor: ok ? Colors.green : Colors.orange);
      },
    );
  }
}

/// AI 返回的结构化建议
class _AiAdvice {
  final String summary;
  final List<String> risks;
  final List<String> advice;
  final List<_AiAction> actions;

  const _AiAdvice({
    this.summary = '',
    this.risks = const [],
    this.advice = const [],
    this.actions = const [],
  });

  /// 容错解析：AI 有时会把 JSON 包在 ```json 里。解析不了就返回 null（降级成原文展示）。
  static _AiAdvice? tryParse(String text) {
    var body = text.trim();
    final start = body.indexOf('{');
    final end = body.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    body = body.substring(start, end + 1);
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      return _AiAdvice(
        summary: (map['summary'] ?? '').toString(),
        risks: _strings(map['risks']),
        advice: _strings(map['advice']),
        actions: ((map['actions'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => _AiAction.fromJson(Map<String, dynamic>.from(e)))
            // 只接受白名单里的 key
            .where((a) => SecurityAiDialog.allowedActions.containsKey(a.key))
            .toList(),
      );
    } catch (e) {
      return null;
    }
  }

  static List<String> _strings(dynamic value) =>
      ((value as List?) ?? const []).map((e) => e.toString()).toList();
}

class _AiAction {
  final String key;
  final bool value;
  final String reason;

  const _AiAction({required this.key, required this.value, this.reason = ''});

  static _AiAction fromJson(Map<String, dynamic> json) => _AiAction(
        key: (json['key'] ?? '').toString(),
        value: json['value'] == true || json['value'] == 'true',
        reason: (json['reason'] ?? '').toString(),
      );
}
