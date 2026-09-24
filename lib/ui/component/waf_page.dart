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

/// WAF 载荷变异页。
///
/// 定位成「变异助手」而不是「攻击器」：输入一条载荷，看它在各种等价写法下
/// 长什么样；想真发出去，拿去请求构造 / 重放 / Fuzz 页自己发。
/// 这样既有用，又不会变成一键打别人站点的东西。
class WafPage extends StatefulWidget {
  const WafPage({super.key});

  @override
  State<WafPage> createState() => _WafPageState();
}

class _WafPageState extends State<WafPage> {
  final _payload = TextEditingController(text: "1' OR '1'='1");
  final _response = TextEditingController();
  final Set<String> _selected = {'comment_split', 'case_mix'};
  List<WafVariant> _variants = const [];
  List<String> _fingerprints = const [];

  @override
  void dispose() {
    _payload.dispose();
    _response.dispose();
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
        '只做本地字符串变换，不发任何请求。请仅用于你拥有或已获书面授权的目标——'
        '未经授权尝试绕过他人系统的防护措施可能触犯法律。\n'
        '变换结果可复制到「请求构造 / 重放 / 手动 Fuzz」里自行发送。',
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
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
