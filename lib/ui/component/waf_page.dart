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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/util/waf_bypass.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/waf_probe.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WAF 载荷变异 + 主动探测页。
///
/// ① 认 WAF（被动比对你已抓到的响应）、② 生成本地变异、③ 主动探测（会真发请求）。
/// ③ 需要显式勾选授权；串行发送、单次有总量上限，不做爆破/并发/自动利用。
class WafPage extends StatefulWidget {
  const WafPage({super.key});

  @override
  State<WafPage> createState() => _WafPageState();
}

class _WafPageState extends State<WafPage> {
  // 高级设置（持久化）
  static const _kDelay = 'waf_probe_delay_ms';
  static const _kTimeout = 'waf_probe_timeout_s';
  static const _kMax = 'waf_probe_max';
  int _delayMs = WafProbe.defaultDelayMs;
  int _timeoutSec = WafProbe.defaultTimeoutSeconds;
  int _maxProbes = WafProbe.defaultMaxProbes;

  final _payload = TextEditingController(text: "1' OR '1'='1");
  final _response = TextEditingController();
  final Set<String> _selected = {'comment_split', 'case_mix'};
  List<WafVariant> _variants = const [];
  List<String> _fingerprints = const [];

  // ---- 主动探测 ----
  final _url = TextEditingController(
      text: 'https://target.example.com/search?q={{PAYLOAD}}');
  final _extraHeaders = TextEditingController();
  final _body = TextEditingController();
  String _method = 'GET';
  bool _authorized = false;
  bool _probing = false;
  WafProbeSession? _session;
  bool _cancel = false;
  int _probeDone = 0;
  int _probeTotal = 0;
  List<WafProbeResult> _probeResults = const [];

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _delayMs = p.getInt(_kDelay) ?? WafProbe.defaultDelayMs;
        _timeoutSec = p.getInt(_kTimeout) ?? WafProbe.defaultTimeoutSeconds;
        _maxProbes = p.getInt(_kMax) ?? WafProbe.defaultMaxProbes;
      });
    });
  }

  /// 高级设置落盘
  void _saveProbePrefs() {
    SharedPreferences.getInstance().then((p) {
      p.setInt(_kDelay, _delayMs);
      p.setInt(_kTimeout, _timeoutSec);
      p.setInt(_kMax, _maxProbes);
    });
  }

  @override
  void dispose() {
    _payload.dispose();
    _response.dispose();
    _url.dispose();
    _extraHeaders.dispose();
    _body.dispose();
    super.dispose();
  }

  void _toast(String msg, {int seconds = 3}) {
    FlutterToastr.show(msg, context, rootNavigator: true, duration: seconds);
  }

  void _generate() {
    final payload = _payload.text;
    if (payload.isEmpty) {
      _toast(AppLocalizations.of(context)!.wafLoadFirst);
      return;
    }
    final selected = _selected.toList();
    if (selected.isEmpty) {
      setState(() => _variants = WafBypass.mutateAll(payload));
    } else {
      setState(() => _variants = WafBypass.mutate(payload, selected));
    }
  }

  void _detect() {
    final text = _response.text;
    if (text.trim().isEmpty) {
      _toast(AppLocalizations.of(context)!.wafPasteResponse);
      return;
    }
    setState(() => _fingerprints = WafBypass.detectFrom(text));
  }

  void _applySuggest(String waf) {
    setState(() => _selected
      ..clear()
      ..addAll(WafBypass.suggestFor(waf)));
    _generate();
    _toast(AppLocalizations.of(context)!.wafAppliedCombo(waf));
  }

  /// 解析「一行一个」的请求头文本
  Map<String, String> _parseHeaders(String text) {
    final map = <String, String>{};
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final idx = trimmed.indexOf(':');
      if (idx <= 0) continue;
      map[trimmed.substring(0, idx).trim()] = trimmed.substring(idx + 1).trim();
    }
    return map;
  }

  Future<void> _startProbe() async {
    if (!_authorized) {
      _toast(AppLocalizations.of(context)!.wafNeedAuth);
      return;
    }
    final url = _url.text.trim();
    if (url.isEmpty) {
      _toast(AppLocalizations.of(context)!.wafNeedUrl);
      return;
    }
    final headerText = _extraHeaders.text;
    final bodyText = _body.text;
    if (!WafProbe.hasPlaceholder(url) &&
        !WafProbe.hasPlaceholder(headerText) &&
        !WafProbe.hasPlaceholder(bodyText)) {
      _toast(AppLocalizations.of(context)!.wafNeedPlaceholder('{{PAYLOAD}}'));
      return;
    }
    final payload = _payload.text;
    if (payload.isEmpty) {
      _toast(AppLocalizations.of(context)!.wafLoadFirst);
      return;
    }
    // 建会话：队列化，后面一批一批发
    final session = WafProbeSession(
      url: url,
      payload: payload,
      method: _method,
      headers: _parseHeaders(headerText),
      body: bodyText.isEmpty ? null : bodyText,
      variants: WafProbe.buildVariants(payload, _selected.toList()),
      batchSize: _maxProbes,
      delayMs: _delayMs,
      timeoutSeconds: _timeoutSec,
    );

    if (session.totalCount <= 1) {
      _toast(AppLocalizations.of(context)!.wafNoVariant);
      return;
    }

    setState(() {
      _session = session;
      _probing = true;
      _cancel = false;
      _probeDone = 0;
      _probeTotal = session.totalCount;
      _probeResults = const [];
    });
    await _runBatch(session);
  }

  /// 发一批（第一批含基线）
  Future<void> _runBatch(WafProbeSession session) async {
    try {
      await session.nextBatch(
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _probeDone = done;
            _probeTotal = total;
          });
        },
        isCancelled: () => _cancel,
      );
      if (!mounted) return;
      setState(() {
        _probeResults = List.of(session.results);
        _probing = false;
      });
      if (session.finished) {
        final bypass =
            session.results.where((r) => r.verdict == WafVerdict.passed).length;
        _toast(AppLocalizations.of(context)!
            .wafDoneAll(session.results.length, bypass));
      } else {
        _toast(AppLocalizations.of(context)!
            .wafBatchDone(session.remaining));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _probing = false);
      _toast(AppLocalizations.of(context)!.wafProbeError('$e'));
    }
  }

  /// 继续下一批（沿用同一会话，基线不重发）
  Future<void> _continueBatch() async {
    final session = _session;
    if (session == null || _probing || session.finished) return;
    setState(() {
      _probing = true;
      _cancel = false;
    });
    await _runBatch(session);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(AppLocalizations.of(context)!.wafTitle,
            style: const TextStyle(fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _notice(),
          const SizedBox(height: 12),
          _fingerprintCard(),
          const SizedBox(height: 12),
          _payloadCard(),
          const SizedBox(height: 12),
          _probeCard(),
          const SizedBox(height: 8),
          _advancedCard(),
          const SizedBox(height: 12),
          if (_probeResults.isNotEmpty) ..._probeResults.map(_probeResultTile),
          if (_variants.isNotEmpty) ..._variants.map(_variantTile),
        ],
      ),
    );
  }

  Widget _notice() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        AppLocalizations.of(context)!.wafDisclaimer,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _fingerprintCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context)!.wafStep1Title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(AppLocalizations.of(context)!.wafStep1Hint,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: _response,
              maxLines: 3,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'Server: cloudflare\nHTTP/1.1 403 Forbidden ...',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              FilledButton.tonal(
                  onPressed: _detect,
                  child: Text(AppLocalizations.of(context)!.wafCompare)),
              const SizedBox(width: 10),
              if (_fingerprints.isEmpty)
                Text(AppLocalizations.of(context)!.wafNotIdentified,
                    style: const TextStyle(fontSize: 12, color: Colors.grey))
              else
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _fingerprints
                        .map((w) => ActionChip(
                              label: Text(w, style: const TextStyle(fontSize: 11)),
                              onPressed: () => _applySuggest(w),
                            ))
                        .toList(),
                  ),
                ),
            ]),
            if (_fingerprints.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(AppLocalizations.of(context)!.wafPickNameHint,
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _payloadCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context)!.wafStep2Title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _payload,
              maxLines: 3,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText: "1' OR '1'='1",
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: WafBypass.techniques
                  .map((t) => FilterChip(
                        label: Text(t.name, style: const TextStyle(fontSize: 11)),
                        tooltip: t.description,
                        selected: _selected.contains(t.id),
                        onSelected: (on) => setState(() {
                          if (on) {
                            _selected.add(t.id);
                          } else {
                            _selected.remove(t.id);
                          }
                        }),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 10),
            Row(children: [
              FilledButton(
                  onPressed: _generate,
                  child: Text(AppLocalizations.of(context)!.wafGenerate)),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () => setState(() => _selected.clear()),
                child: Text(AppLocalizations.of(context)!.wafClearSelection),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _probeCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context)!.wafStep3Title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)!.wafStep3Hint('{{PAYLOAD}}'),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)!.wafWillProbe(_selectedNames()),
              style: TextStyle(
                  fontSize: 11, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 2),
            Text(AppLocalizations.of(context)!.wafBatchHint(_maxProbes),
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: ['GET', 'POST', 'PUT']
                  .map((m) => ChoiceChip(
                        label: Text(m, style: const TextStyle(fontSize: 11)),
                        selected: _method == m,
                        onSelected: (_) => setState(() => _method = m),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _url,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                labelText: AppLocalizations.of(context)!.wafTargetUrl,
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _extraHeaders,
              maxLines: 2,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                labelText: AppLocalizations.of(context)!.wafExtraHeaders,
                hintText: 'User-Agent: {{PAYLOAD}}',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _body,
              maxLines: 2,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                labelText: AppLocalizations.of(context)!.wafBodyOptional,
                hintText: '{"q":"{{PAYLOAD}}"}',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            CheckboxListTile(
              value: _authorized,
              onChanged: (v) => setState(() => _authorized = v ?? false),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(AppLocalizations.of(context)!.wafAuthCheckbox,
                  style: TextStyle(fontSize: 12)),
            ),
            Row(children: [
              FilledButton.icon(
                onPressed: _probing
                    ? null
                    : (_session == null || _session!.finished
                        ? _startProbe
                        : _continueBatch),
                icon: Icon(
                    (_session == null || _session!.finished)
                        ? Icons.radar
                        : Icons.skip_next,
                    size: 16),
                label: Text((_session == null || _session!.finished)
                    ? AppLocalizations.of(context)!.wafStartProbe
                    : AppLocalizations.of(context)!
                        .wafNextBatch(_session!.remaining)),
              ),
              const SizedBox(width: 10),
              if (_probing) ...[
                Expanded(
                  child: LinearProgressIndicator(
                    value: _probeTotal == 0 ? null : _probeDone / _probeTotal,
                  ),
                ),
                const SizedBox(width: 8),
                Text('$_probeDone/$_probeTotal',
                    style: const TextStyle(fontSize: 11)),
                TextButton(
                  onPressed: () => setState(() => _cancel = true),
                  child: Text(AppLocalizations.of(context)!.stop),
                ),
              ] else if (_probeResults.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    _probeResults = const [];
                    _session = null;
                    _probeDone = 0;
                    _probeTotal = 0;
                  }),
                  child: Text(AppLocalizations.of(context)!.wafClearResults),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _slider(String label, int value, int min, int max, String display,
      ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const Spacer(),
          Text(display, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          onChanged: (v) => onChanged(v.round()),
          onChangeEnd: (_) => _saveProbePrefs(),
        ),
      ],
    );
  }

  Widget _advancedCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        title: Text(AppLocalizations.of(context)!.wafAdvanced,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(
            AppLocalizations.of(context)!
                .wafAdvancedSummary(_delayMs, _timeoutSec, _maxProbes),
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        children: [
          _slider(AppLocalizations.of(context)!.wafInterval, _delayMs,
              WafProbe.minDelayMs, 5000, '${_delayMs}ms',
              (v) => setState(() => _delayMs = v)),
          _slider(AppLocalizations.of(context)!.wafTimeout, _timeoutSec, 3, 60,
              '${_timeoutSec}s',
              (v) => setState(() => _timeoutSec = v)),
          _slider(AppLocalizations.of(context)!.wafMaxProbes, _maxProbes, 10,
              WafProbe.hardMaxProbes,
              AppLocalizations.of(context)!.wafNRecords(_maxProbes),
              (v) => setState(() => _maxProbes = v)),
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                AppLocalizations.of(context)!.wafLimitsHard(
                    WafProbe.minDelayMs, WafProbe.hardMaxProbes),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ①② 选定的技术名 —— ③ 实际会探测的就是这个集合
  String _selectedNames() {
    if (_selected.isEmpty) return AppLocalizations.of(context)!.wafAll;
    final names = <String>[];
    for (final t in WafBypass.techniques) {
      if (_selected.contains(t.id)) names.add(t.name);
    }
    return names.join('、');
  }

  Color _verdictColor(WafVerdict v) {
    switch (v) {
      case WafVerdict.passed:
        return Colors.green;
      case WafVerdict.blocked:
        return Colors.red;
      case WafVerdict.changed:
        return Colors.orange;
      case WafVerdict.failed:
        return Colors.grey;
      case WafVerdict.baseline:
        return Colors.blue;
    }
  }

  Widget _probeResultTile(WafProbeResult r) {
    final color = _verdictColor(r.verdict);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        leading: Icon(Icons.circle, size: 10, color: color),
        title: Row(children: [
          Expanded(
            child: Text(r.name,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(WafProbe.verdictLabel(r.verdict),
                style: TextStyle(fontSize: 10, color: color)),
          ),
        ]),
        subtitle: Text(
          r.error != null
              ? r.error!
              : AppLocalizations.of(context)!.wafResultMeta(
                  '${r.statusCode ?? '-'}', r.bodyLength, r.durationMs),
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(r.payload,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
          if (r.bodySnippet.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(r.bodySnippet,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: r.payload));
                _toast(AppLocalizations.of(context)!.wafPayloadCopied);
              },
              child: Text(AppLocalizations.of(context)!.wafCopyPayload),
            ),
          ),
        ],
      ),
    );
  }

  Widget _variantTile(WafVariant v) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: v.output));
          _toast(AppLocalizations.of(context)!.wafCopied(v.name));
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(v.name,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
                const Icon(Icons.copy, size: 14, color: Colors.grey),
              ]),
              const SizedBox(height: 4),
              SelectableText(
                v.output,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              if (v.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(v.note,
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
