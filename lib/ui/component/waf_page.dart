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
      _toast('先填一条载荷');
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
      _toast('把响应的头或拦截页片段贴进来');
      return;
    }
    setState(() => _fingerprints = WafBypass.detectFrom(text));
  }

  void _applySuggest(String waf) {
    setState(() => _selected
      ..clear()
      ..addAll(WafBypass.suggestFor(waf)));
    _generate();
    _toast('已套用针对 $waf 的组合');
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
      _toast('请先勾选「已获得测试授权」');
      return;
    }
    final url = _url.text.trim();
    if (url.isEmpty) {
      _toast('填一个目标 URL');
      return;
    }
    final headerText = _extraHeaders.text;
    final bodyText = _body.text;
    if (!WafProbe.hasPlaceholder(url) &&
        !WafProbe.hasPlaceholder(headerText) &&
        !WafProbe.hasPlaceholder(bodyText)) {
      _toast('至少要在一处放 {{PAYLOAD}} 标记注入位置');
      return;
    }
    final payload = _payload.text;
    if (payload.isEmpty) {
      _toast('先填一条载荷');
      return;
    }
    setState(() {
      _probing = true;
      _cancel = false;
      _probeDone = 0;
      _probeTotal = 0;
      _probeResults = const [];
    });

    try {
      final results = await WafProbe.probe(
        url: url,
        method: _method,
        headers: _parseHeaders(headerText),
        body: bodyText.isEmpty ? null : bodyText,
        payload: payload,
        techniques: _selected.toList(),
        delayMs: _delayMs,
        timeoutSeconds: _timeoutSec,
        maxProbes: _maxProbes,
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
        _probeResults = results;
        _probing = false;
      });
      final bypass =
          results.where((r) => r.verdict == WafVerdict.passed).length;
      _toast('探测结束：共 ${results.length} 条，疑似绕过 $bypass 条');
    } catch (e) {
      if (!mounted) return;
      setState(() => _probing = false);
      _toast('探测出错：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('WAF 载荷变异', style: TextStyle(fontSize: 16)),
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
      child: const Text(
        '①② 只做本地字符串变换，不发任何请求；③ 的「主动探测」会真的把请求发出去，'
        '所以必须先显式勾选授权。\n'
        '请仅用于你拥有或已获书面授权的目标——未经授权尝试绕过他人系统的防护措施'
        '可能触犯法律。探测为串行发送、单次有总量上限（默认 200 条），不做爆破与并发。',
        style: TextStyle(fontSize: 12),
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
            const Text('① 认一下是什么 WAF（可选）',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('把你已经抓到的响应头或拦截页片段贴进来，按特征比对——不主动探测。',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
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
              FilledButton.tonal(onPressed: _detect, child: const Text('比对')),
              const SizedBox(width: 10),
              if (_fingerprints.isEmpty)
                const Text('未识别', style: TextStyle(fontSize: 12, color: Colors.grey))
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
                child: Text('点一下 WAF 名字即可套用推荐组合',
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
            const Text('② 输入载荷并选择变异方式',
                style: TextStyle(fontWeight: FontWeight.w600)),
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
              FilledButton(onPressed: _generate, child: const Text('生成')),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () => setState(() => _selected.clear()),
                child: const Text('清空选择'),
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
            const Text('③ 主动探测（会真的发请求）',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text(
              '在你想注入的位置写 {{PAYLOAD}}（URL / 头 / 体都行）。'
              '先发一条原始载荷作基线，再逐条发上面勾选的技术，比对响应判断哪条没被拦。',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              '本次将探测（由 ①② 决定）：${_selectedNames()}',
              style: TextStyle(
                  fontSize: 11, color: Theme.of(context).colorScheme.primary),
            ),
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
                labelText: '目标 URL（含 {{PAYLOAD}}）',
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
                labelText: '额外请求头（可选，一行一个）',
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
                labelText: '请求体（可选）',
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
              title: const Text('我已获得对该目标的测试授权',
                  style: TextStyle(fontSize: 12)),
            ),
            Row(children: [
              FilledButton.icon(
                onPressed: _probing ? null : _startProbe,
                icon: const Icon(Icons.radar, size: 16),
                label: const Text('开始探测'),
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
                  child: const Text('停止'),
                ),
              ] else if (_probeResults.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _probeResults = const []),
                  child: const Text('清空结果'),
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
        title: const Text('高级设置',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text('间隔 ${_delayMs}ms · 超时 ${_timeoutSec}s · 单次上限 $_maxProbes 条',
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        children: [
          _slider('请求间隔', _delayMs, WafProbe.minDelayMs, 5000, '${_delayMs}ms',
              (v) => setState(() => _delayMs = v)),
          _slider('单条超时', _timeoutSec, 3, 60, '${_timeoutSec}s',
              (v) => setState(() => _timeoutSec = v)),
          _slider('单次上限', _maxProbes, 10, WafProbe.hardMaxProbes, '$_maxProbes 条',
              (v) => setState(() => _maxProbes = v)),
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                '间隔下限 ${WafProbe.minDelayMs}ms、总量硬顶 ${WafProbe.hardMaxProbes} 条，'
                '这两条不可突破 —— 再往下就不是"探测"而是对目标的流量冲击了。',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ①② 选定的技术名 —— ③ 实际会探测的就是这个集合
  String _selectedNames() {
    if (_selected.isEmpty) return '全部';
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
              : 'HTTP ${r.statusCode ?? '-'} · ${r.bodyLength} 字节 · ${r.durationMs}ms',
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
                _toast('已复制载荷');
              },
              child: const Text('复制载荷'),
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
          _toast('已复制：${v.name}');
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
