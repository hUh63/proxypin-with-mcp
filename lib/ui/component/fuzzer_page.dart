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
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/fuzz_dictionary.dart';
import 'package:proxypin/network/util/request_fuzzer.dart';
import 'package:proxypin/ui/component/fuzz_dictionary_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 手动 Fuzz：把你自己写的取值逐条替换进一条请求发送，把响应摆在一起对照。
///
/// - 取值完全由你填写，工具不内置任何载荷或漏洞字典；
/// - 不自动判定"是否有漏洞"，只记录状态码 / 耗时 / 长度 / 内容差异；
/// - 支持多个注入项，一次跑它们的组合（笛卡尔积）。
class FuzzerPage extends StatefulWidget {
  final List<HttpRequest> requests;

  const FuzzerPage({super.key, required this.requests});

  @override
  State<FuzzerPage> createState() => _FuzzerPageState();
}

/// 单个注入项的编辑状态
class _InjectionEditor {
  FuzzTarget target;
  final TextEditingController field;
  final TextEditingController placeholder;
  final TextEditingController values;

  _InjectionEditor({
    this.target = FuzzTarget.queryParam,
    String field = 'id',
    String placeholder = '{{FUZZ}}',
    String values = '',
  })  : field = TextEditingController(text: field),
        placeholder = TextEditingController(text: placeholder),
        values = TextEditingController(text: values);

  FuzzInjection toInjection() => FuzzInjection(
        target: target,
        field: field.text.trim(),
        placeholder: placeholder.text,
        values: RequestFuzzer.parsePayloads(values.text),
      );

  void dispose() {
    field.dispose();
    placeholder.dispose();
    values.dispose();
  }
}

class _FuzzerPageState extends State<FuzzerPage> {
  static const int maxTemplates = 300;
  static const String _kAnomalyRules = 'fuzz_anomaly_rules_v1';

  final TextEditingController _intervalController = TextEditingController(text: '200');
  final List<_InjectionEditor> _injections = [];

  late List<HttpRequest> _templates;
  int _templateIndex = 0;
  bool _sendBaseline = true;
  bool _running = false;
  final List<FuzzOutcome> _results = [];
  FuzzOutcome? _baseline;

  /// 每条结果命中的比对规则（key = FuzzOutcome.index）
  final Map<int, List<String>> _anomalyHits = {};
  List<FuzzAnomalyRule> _rules = FuzzAnomaly.defaults();

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _templates = widget.requests.toList().reversed.take(maxTemplates).toList();
    _injections.add(_InjectionEditor());
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() => _rules = FuzzAnomaly.decode(p.getString(_kAnomalyRules)));
    });
  }

  @override
  void dispose() {
    _intervalController.dispose();
    for (final injection in _injections) {
      injection.dispose();
    }
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

  List<FuzzInjection> get _activeInjections =>
      _injections.map((e) => e.toInjection()).where((e) => e.values.isNotEmpty).toList();

  int get _intervalMs => int.tryParse(_intervalController.text.trim()) ?? 200;

  Future<void> _start() async {
    if (_templates.isEmpty) {
      FlutterToastr.show(localizations.fuzzerNoTemplate, context);
      return;
    }
    final injections = _activeInjections;
    if (injections.isEmpty) {
      FlutterToastr.show(localizations.fuzzerPayloadEmpty, context);
      return;
    }

    final template = _templates[_templateIndex];
    final totalCombinations = RequestFuzzer.combinationCount(injections);
    final cases = RequestFuzzer.buildCases(injections);
    if (cases.isEmpty) {
      FlutterToastr.show(localizations.fuzzerPayloadEmpty, context);
      return;
    }
    if (totalCombinations > cases.length) {
      FlutterToastr.show(localizations.fuzzerTooManyCases, context);
    }

    setState(() {
      _running = true;
      _results.clear();
      _anomalyHits.clear();
      _baseline = null;
    });

    try {
      if (_sendBaseline) {
        final base = await RequestFuzzer.send(
          template,
          index: -1,
          payload: localizations.fuzzerBaseline,
          baseline: true,
        );
        _baseline = base;
        if (mounted) setState(() => _results.add(base));
      }

      for (var i = 0; i < cases.length; i++) {
        if (!_running || !mounted) break;
        final variant = RequestFuzzer.buildVariant(template, injections, cases[i].values);
        final outcome = await RequestFuzzer.send(variant, index: i, payload: cases[i].label);
        final withDiff = _baseline == null ? outcome : outcome.withDiff(RequestFuzzer.diffOf(_baseline!, outcome));
        if (!mounted) break;
        setState(() {
          _results.add(withDiff);
          // 按当前规则跟基线比一遍，命中什么就标什么
          final hits = FuzzAnomaly.match(withDiff, _baseline, _rules);
          if (hits.isNotEmpty) _anomalyHits[withDiff.index] = hits;
        });
        if (_intervalMs > 0) {
          await Future.delayed(Duration(milliseconds: _intervalMs));
        }
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _stop() => setState(() => _running = false);

  Future<void> _export(bool asJson) async {
    if (_results.isEmpty) return;
    try {
      final template = '${_templates[_templateIndex].method.name.toUpperCase()} '
          '${_templates[_templateIndex].pathAndQuery}';
      final content = asJson ? RequestFuzzer.toJson(_results, template: template) : RequestFuzzer.toCsv(_results);
      final Uri? path = await FilePicker.saveFile(
        fileName: 'fuzz-result.${asJson ? 'json' : 'csv'}',
        bytes: utf8.encode(content),
      );
      if (path == null) return;
      if (mounted) FlutterToastr.show(localizations.fuzzerExportSuccess, context);
    } catch (e, t) {
      logger.e('导出 Fuzz 结果失败', error: e, stackTrace: t);
      if (mounted) FlutterToastr.show('${localizations.fuzzerExportFailed} $e', context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final combinationCount = RequestFuzzer.combinationCount(_activeInjections);
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.fuzzer),
        actions: [
          if (_results.isNotEmpty && !_running)
            PopupMenuButton<String>(
              tooltip: localizations.fuzzerExport,
              icon: const Icon(Icons.file_download_outlined, size: 20),
              onSelected: (value) => _export(value == 'json'),
              itemBuilder: (context) => [
                PopupMenuItem(value: 'csv', height: 38, child: Text(localizations.fuzzerExportCsv)),
                PopupMenuItem(value: 'json', height: 38, child: Text(localizations.fuzzerExportJson)),
              ],
            ),
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Flexible(
                      child: Text(localizations.fuzzerInjection,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    if (combinationCount > 0)
                      Flexible(
                        child: Text(
                          '${localizations.fuzzerCombinations}: $combinationCount',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              color: combinationCount > RequestFuzzer.maxCombinations ? cs.error : cs.onSurfaceVariant),
                        ),
                      ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _running ? null : () => setState(() => _injections.add(_InjectionEditor(field: ''))),
                      icon: const Icon(Icons.add, size: 17),
                      label: Text(localizations.fuzzerAddInjection),
                    ),
                  ],
                ),
                for (var i = 0; i < _injections.length; i++) _buildInjectionCard(cs, i),
                const SizedBox(height: 6),
                _buildRunBar(cs),
                const SizedBox(height: 12),
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

  Widget _buildInjectionCard(ColorScheme cs, int index) {
    final injection = _injections[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${index + 1}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<FuzzTarget>(
                  initialValue: injection.target,
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: [
                    for (final target in FuzzTarget.values)
                      DropdownMenuItem(
                        value: target,
                        child: Text(_targetLabel(target), style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                  onChanged: _running ? null : (value) => setState(() => injection.target = value ?? injection.target),
                ),
              ),
              const SizedBox(width: 8),
              if (_injections.length > 1)
                IconButton(
                  tooltip: localizations.delete,
                  onPressed: _running
                      ? null
                      : () => setState(() {
                            _injections.removeAt(index).dispose();
                          }),
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (injection.target == FuzzTarget.bodyPlaceholder)
            TextField(
              controller: injection.placeholder,
              enabled: !_running,
              decoration: InputDecoration(
                labelText: localizations.fuzzerPlaceholder,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            )
          else
            TextField(
              controller: injection.field,
              enabled: !_running,
              decoration: InputDecoration(
                labelText: localizations.fuzzerField,
                hintText: localizations.fuzzerFieldHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          const SizedBox(height: 8),
          Row(children: [
            TextButton.icon(
              onPressed: _running
                  ? null
                  : () async {
                      final dict = await FuzzDictionaryDialog.show(context);
                      if (dict == null || !mounted) return;
                      try {
                        final values = await FuzzDictionaryStore.resolve(dict);
                        if (!mounted) return;
                        setState(() => injection.values.text = values.join('\n'));
                        FlutterToastr.show(
                            '已填入「${dict.name}」共 ${values.length} 条', context,
                            duration: 2);
                      } catch (e) {
                        if (!mounted) return;
                        FlutterToastr.show('字典展开失败：$e', context,
                            duration: 3, backgroundColor: Colors.red);
                      }
                    },
              icon: const Icon(Icons.menu_book_outlined, size: 16),
              label: const Text('从字典填充', style: TextStyle(fontSize: 12)),
            ),
            const Spacer(),
            Text(
                '${RequestFuzzer.parsePayloads(injection.values.text).length} 条',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ]),
          const SizedBox(height: 4),
          TextField(
            controller: injection.values,
            enabled: !_running,
            minLines: 3,
            maxLines: 6,
            style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: localizations.fuzzerPayloadsHint,
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding: const EdgeInsets.all(10),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildRunBar(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: _running ? null : _start,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text(localizations.fuzzerStart),
            ),
            OutlinedButton.icon(
              onPressed: _running ? _stop : null,
              icon: const Icon(Icons.stop, size: 18),
              label: Text(localizations.fuzzerStop),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(localizations.fuzzerInterval, style: const TextStyle(fontSize: 12.5)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 76,
                  child: TextField(
                    controller: _intervalController,
                    enabled: !_running,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, suffixText: 'ms'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        // 开关单独一行：Switch 标准高度 48，硬塞进小盒子会被裁切
        InkWell(
          onTap: _running ? null : () => setState(() => _sendBaseline = !_sendBaseline),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 44,
                  height: 28,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Switch(
                      value: _sendBaseline,
                      onChanged: _running ? null : (value) => setState(() => _sendBaseline = value),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(localizations.fuzzerSendBaseline, style: const TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        _buildRules(cs),
      ],
    );
  }

  /// 判定规则设置：勾选启用、填参数。工具只按规则标差异，不下漏洞结论。
  Widget _buildRules(ColorScheme cs) {
    final enabledNames =
        _rules.where((r) => r.enabled).map((r) => r.name).join('、');
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        title: const Text('判定规则（与基线比对）',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(
          enabledNames.isEmpty ? '未启用任何规则' : '已启用：$enabledNames',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('规则只负责标出「和基线不一样」，不代表这里就有漏洞 —— 结论由你下。',
                style: TextStyle(fontSize: 10.5, color: Colors.grey)),
          ),
          for (final rule in _rules) _ruleRow(rule, cs),
        ],
      ),
    );
  }

  Widget _ruleRow(FuzzAnomalyRule rule, ColorScheme cs) {
    final needsParam = rule.id == FuzzAnomaly.keyword ||
        rule.id == FuzzAnomaly.lengthChanged ||
        rule.id == FuzzAnomaly.slower;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
          width: 34,
          child: Checkbox(
            value: rule.enabled,
            onChanged: _running
                ? null
                : (v) => setState(() {
                      final i = _rules.indexWhere((e) => e.id == rule.id);
                      if (i >= 0) _rules[i] = _rules[i].copyWith(enabled: v ?? false);
                      _saveRules();
                    }),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rule.name, style: const TextStyle(fontSize: 12.5)),
              Text(rule.description,
                  style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
            ],
          ),
        ),
        if (needsParam)
          SizedBox(
            width: 116,
            child: TextFormField(
              key: ValueKey(rule.id),
              initialValue: rule.param,
              enabled: !_running,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: rule.id == FuzzAnomaly.keyword ? '关键字' : null,
                suffixText: rule.id == FuzzAnomaly.slower
                    ? 'ms'
                    : (rule.id == FuzzAnomaly.keyword ? null : '%'),
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) {
                final i = _rules.indexWhere((e) => e.id == rule.id);
                if (i >= 0) _rules[i] = _rules[i].copyWith(param: v);
              },
              onFieldSubmitted: (_) => _saveRules(),
              onTapOutside: (_) => _saveRules(),
            ),
          ),
      ]),
    );
  }

  void _saveRules() {
    SharedPreferences.getInstance()
        .then((p) => p.setString(_kAnomalyRules, FuzzAnomaly.encode(_rules)));
  }

  Widget _buildResults(ColorScheme cs) {
    if (_results.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        alignment: Alignment.center,
        child: Text(localizations.fuzzerNoResult, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
      );
    }
    final compact = MediaQuery.sizeOf(context).width < 420;
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
        _buildHeaderRow(cs, compact),
        const Divider(height: 1),
        for (final outcome in _results) _buildResultRow(cs, outcome, compact),
      ],
    );
  }

  Widget _buildHeaderRow(ColorScheme cs, bool compact) {
    const style = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600);
    final color = cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 30, child: Text('#', style: style.copyWith(color: color))),
          Expanded(flex: 3, child: Text('payload', style: style.copyWith(color: color))),
          SizedBox(width: compact ? 40 : 46, child: Text(localizations.fuzzerStatus, style: style.copyWith(color: color))),
          // 窄屏不显示长度列（改在每行第二行给出），避免 payload 被挤到看不清
          if (!compact) SizedBox(width: 60, child: Text(localizations.fuzzerLength, style: style.copyWith(color: color))),
          SizedBox(width: compact ? 54 : 60, child: Text(localizations.fuzzerDuration, style: style.copyWith(color: color))),
        ],
      ),
    );
  }

  Widget _buildResultRow(ColorScheme cs, FuzzOutcome outcome, bool compact) {
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
                  width: compact ? 40 : 46,
                  child: Text(
                    outcome.error != null ? 'ERR' : '${outcome.statusCode ?? '-'}',
                    style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600),
                  ),
                ),
                if (!compact)
                  SizedBox(width: 60, child: Text('${outcome.bodyLength}', style: const TextStyle(fontSize: 11.5))),
                SizedBox(
                    width: compact ? 54 : 60,
                    child: Text('${outcome.durationMs}ms', style: const TextStyle(fontSize: 11.5))),
              ],
            ),
            if (compact || outcome.diff.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 30, top: 2),
                child: Text(
                  compact
                      ? [
                          '${localizations.fuzzerLength} ${outcome.bodyLength}',
                          if (outcome.diff.isNotEmpty) outcome.diff,
                        ].join(' · ')
                      : outcome.diff,
                  style: TextStyle(fontSize: 11, color: cs.tertiary),
                ),
              ),
            if (outcome.error != null)
              Padding(
                padding: const EdgeInsets.only(left: 30, top: 2),
                child: Text(outcome.error!, style: TextStyle(fontSize: 11, color: cs.error), maxLines: 2),
              ),
            if (_anomalyHits[outcome.index]?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(left: 30, top: 3),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final hit in _anomalyHits[outcome.index]!)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: cs.errorContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(hit,
                            style: TextStyle(
                                fontSize: 10.5, color: cs.onErrorContainer)),
                      ),
                  ],
                ),
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
