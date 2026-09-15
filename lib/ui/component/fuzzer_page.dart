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
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/request_fuzzer.dart';

/// 手动 Fuzz：把你自己写的取值逐条替换进一条请求发送，把响应摆在一起对照。
///
/// - payload 完全由你填写，工具不内置任何载荷或漏洞字典；
/// - 不自动判定"是否有漏洞"，只记录状态码 / 耗时 / 长度 / 内容差异；
/// - 结论由人下——工具只是把重复劳动自动化。
class FuzzerPage extends StatefulWidget {
  final List<HttpRequest> requests;

  const FuzzerPage({super.key, required this.requests});

  @override
  State<FuzzerPage> createState() => _FuzzerPageState();
}

class _FuzzerPageState extends State<FuzzerPage> {
  static const int maxTemplates = 300;

  final TextEditingController _fieldController = TextEditingController(text: 'id');
  final TextEditingController _placeholderController = TextEditingController(text: '{{FUZZ}}');
  final TextEditingController _payloadController = TextEditingController();
  final TextEditingController _intervalController = TextEditingController(text: '200');

  late List<HttpRequest> _templates;
  int _templateIndex = 0;
  FuzzTarget _target = FuzzTarget.queryParam;
  bool _sendBaseline = true;
  bool _running = false;
  final List<FuzzOutcome> _results = [];
  FuzzOutcome? _baseline;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    // 只保留最近的一批请求作为可选模板（新的在前）
    final list = widget.requests.toList().reversed.take(maxTemplates).toList();
    _templates = list;
  }

  @override
  void dispose() {
    _fieldController.dispose();
    _placeholderController.dispose();
    _payloadController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  String _targetLabel(FuzzTarget target) {
    switch (target) {
      case FuzzTarget.queryParam:
        return localizations.fuzzerTargetQuery;
      case FuzzTarget.header:
        return localizations.fuzzerTargetHeader;
      case FuzzTarget.jsonField:
        return localizations.fuzzerTargetJson;
      case FuzzTarget.bodyPlaceholder:
        return localizations.fuzzerTargetBody;
    }
  }

  FuzzConfig get _config => FuzzConfig(
        target: _target,
        field: _fieldController.text,
        placeholder: _placeholderController.text,
        intervalMs: int.tryParse(_intervalController.text.trim()) ?? 200,
        timeoutSeconds: 15,
        sendBaseline: _sendBaseline,
      );

  Future<void> _start() async {
    if (_templates.isEmpty) {
      FlutterToastr.show(localizations.fuzzerNoTemplate, context);
      return;
    }
    final payloads = RequestFuzzer.parsePayloads(_payloadController.text);
    if (payloads.isEmpty) {
      FlutterToastr.show(localizations.fuzzerPayloadEmpty, context);
      return;
    }

    final template = _templates[_templateIndex];
    final config = _config;
    setState(() {
      _running = true;
      _results.clear();
      _baseline = null;
    });

    try {
      if (config.sendBaseline) {
        final base = await RequestFuzzer.send(
          template,
          index: -1,
          payload: localizations.fuzzerBaseline,
          timeoutSeconds: config.timeoutSeconds,
          baseline: true,
        );
        _baseline = base;
        if (mounted) setState(() => _results.add(base));
      }

      for (var i = 0; i < payloads.length; i++) {
        if (!_running || !mounted) break;
        final variant = RequestFuzzer.buildVariant(template, config, payloads[i]);
        final outcome = await RequestFuzzer.send(
          variant,
          index: i,
          payload: payloads[i],
          timeoutSeconds: config.timeoutSeconds,
        );
        final withDiff = _baseline == null ? outcome : outcome.withDiff(RequestFuzzer.diffOf(_baseline!, outcome));
        if (!mounted) break;
        setState(() => _results.add(withDiff));
        if (config.intervalMs > 0) {
          await Future.delayed(Duration(milliseconds: config.intervalMs));
        }
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _stop() => setState(() => _running = false);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.fuzzer),
        actions: [
          if (_results.isNotEmpty)
            TextButton.icon(
              onPressed: _running ? null : () => setState(() => _results.clear()),
              icon: const Icon(Icons.clear_all, size: 18),
              label: Text(localizations.fuzzerClear),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildTips(cs),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              children: [
                _buildTemplatePicker(cs),
                const SizedBox(height: 10),
                _buildInjectConfig(cs),
                const SizedBox(height: 10),
                _buildPayloads(cs),
                const SizedBox(height: 10),
                _buildRunBar(cs),
                const SizedBox(height: 10),
                _buildResults(cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTips(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      color: cs.primary.withValues(alpha: 0.05),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: cs.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(localizations.fuzzerTips,
                style: TextStyle(fontSize: 11.5, height: 1.35, color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplatePicker(ColorScheme cs) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(localizations.fuzzerTemplate, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: _templates.isEmpty
              ? Text(localizations.fuzzerNoTemplate, style: TextStyle(fontSize: 12, color: cs.error))
              : DropdownButtonFormField<int>(
                  initialValue: _templateIndex,
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: [
                    for (var i = 0; i < _templates.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          '${_templates[i].method.name.toUpperCase()} ${_templates[i].pathAndQuery}',
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _running ? null : (value) => setState(() => _templateIndex = value ?? 0),
                ),
        ),
      ],
    );
  }

  Widget _buildInjectConfig(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(localizations.fuzzerTarget, style: const TextStyle(fontSize: 13)),
            ),
            Expanded(
              child: DropdownButtonFormField<FuzzTarget>(
                initialValue: _target,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: [
                  for (final target in FuzzTarget.values)
                    DropdownMenuItem(
                      value: target,
                      child: Text(_targetLabel(target), style: const TextStyle(fontSize: 13)),
                    ),
                ],
                onChanged: _running ? null : (value) => setState(() => _target = value ?? _target),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_target == FuzzTarget.bodyPlaceholder)
          TextField(
            controller: _placeholderController,
            enabled: !_running,
            decoration: InputDecoration(
              labelText: localizations.fuzzerPlaceholder,
              hintText: '{{FUZZ}}',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          )
        else
          TextField(
            controller: _fieldController,
            enabled: !_running,
            decoration: InputDecoration(
              labelText: localizations.fuzzerField,
              hintText: localizations.fuzzerFieldHint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
      ],
    );
  }

  Widget _buildPayloads(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(localizations.fuzzerPayloads, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 4),
        TextField(
          controller: _payloadController,
          enabled: !_running,
          minLines: 4,
          maxLines: 8,
          style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: localizations.fuzzerPayloadsHint,
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding: const EdgeInsets.all(10),
          ),
        ),
      ],
    );
  }

  Widget _buildRunBar(ColorScheme cs) {
    return Row(
      children: [
        FilledButton.icon(
          onPressed: _running ? null : _start,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: Text(localizations.fuzzerStart),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _running ? _stop : null,
          icon: const Icon(Icons.stop, size: 18),
          label: Text(localizations.fuzzerStop),
        ),
        const SizedBox(width: 12),
        Text(localizations.fuzzerInterval, style: const TextStyle(fontSize: 12.5)),
        const SizedBox(width: 6),
        SizedBox(
          width: 72,
          child: TextField(
            controller: _intervalController,
            enabled: !_running,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, suffixText: 'ms'),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const Spacer(),
        Row(
          children: [
            SizedBox(
              height: 24,
              child: Switch(
                value: _sendBaseline,
                onChanged: _running ? null : (value) => setState(() => _sendBaseline = value),
              ),
            ),
            const SizedBox(width: 4),
            Text(localizations.fuzzerSendBaseline, style: const TextStyle(fontSize: 12.5)),
          ],
        ),
      ],
    );
  }

  Widget _buildResults(ColorScheme cs) {
    if (_results.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        alignment: Alignment.center,
        child: Text(localizations.fuzzerNoResult, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(localizations.fuzzerResult, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            if (_running) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
            const Spacer(),
            Text('${_results.length}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 6),
        _buildHeaderRow(cs),
        const Divider(height: 1),
        for (final outcome in _results) _buildResultRow(cs, outcome),
      ],
    );
  }

  Widget _buildHeaderRow(ColorScheme cs) {
    const style = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600);
    final color = cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 30, child: Text('#', style: style.copyWith(color: color))),
          Expanded(flex: 3, child: Text('payload', style: style.copyWith(color: color))),
          SizedBox(width: 46, child: Text(localizations.fuzzerStatus, style: style.copyWith(color: color))),
          SizedBox(width: 60, child: Text(localizations.fuzzerLength, style: style.copyWith(color: color))),
          SizedBox(width: 60, child: Text(localizations.fuzzerDuration, style: style.copyWith(color: color))),
        ],
      ),
    );
  }

  Widget _buildResultRow(ColorScheme cs, FuzzOutcome outcome) {
    final statusColor = outcome.error != null
        ? cs.error
        : (outcome.statusCode != null && outcome.statusCode! >= 400 ? cs.error : cs.primary);
    return InkWell(
      onTap: () => _showBody(outcome),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text(outcome.baseline ? '—' : '${outcome.index + 1}',
                      style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    outcome.payload,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
                SizedBox(
                  width: 46,
                  child: Text(
                    outcome.error != null ? 'ERR' : '${outcome.statusCode ?? '-'}',
                    style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600),
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text('${outcome.bodyLength}', style: const TextStyle(fontSize: 11.5)),
                ),
                SizedBox(
                  width: 60,
                  child: Text('${outcome.durationMs}ms', style: const TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
            if (outcome.diff.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 30, top: 2),
                child: Text(outcome.diff,
                    style: TextStyle(fontSize: 11, color: cs.tertiary)),
              ),
            if (outcome.error != null)
              Padding(
                padding: const EdgeInsets.only(left: 30, top: 2),
                child: Text(outcome.error!, style: TextStyle(fontSize: 11, color: cs.error), maxLines: 2),
              ),
          ],
        ),
      ),
    );
  }

  void _showBody(FuzzOutcome outcome) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('${outcome.statusCode ?? outcome.error ?? ''} · ${outcome.payload}',
            style: const TextStyle(fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 460),
          child: Scrollbar(
            child: SingleChildScrollView(
              child: SelectableText(
                outcome.body.isEmpty ? (outcome.error ?? '') : outcome.body,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace', height: 1.4),
              ),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: outcome.body));
              if (context.mounted) FlutterToastr.show(localizations.copied, context);
            },
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: Text(localizations.copy),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(localizations.close)),
        ],
      ),
    );
  }
}
