/*
 * Copyright 2026 Hongen Wang All rights reserved.
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
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/douyin_sign.dart';

import '../component/buttons.dart';
import '../component/request_pick_sheet.dart';
import '../component/text_field.dart';
import '../component/tool_kit.dart';

/// 解析 URL：只保留 `?` 之后的查询串；没有 `?` 则整段当作查询串。
String extractQuery(String input) {
  final t = input.trim();
  final i = t.indexOf('?');
  return i >= 0 ? t.substring(i + 1) : t;
}

/// 字节系 / 抖音签名计算器：输入 URL 与请求体，输出各签名头。
///
/// 算法以 JS 实现（见 [DouyinSign]），版本相关常量在「参数」标签页调整，
/// 三个标签页共享同一份参数。
class SignPage extends StatefulWidget {
  const SignPage({super.key});

  @override
  State<SignPage> createState() => _SignPageState();
}

class _SignPageState extends State<SignPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final ValueNotifier<DouyinSignParams> _params =
      ValueNotifier(const DouyinSignParams());

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _params.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.toolboxSign, style: const TextStyle(fontSize: 16)),
        centerTitle: true,
        bottom: TabBar(controller: _tab, isScrollable: true, tabs: [
          Tab(text: localizations.signTabSign),
          Tab(text: localizations.signTabWeb),
          const Tab(text: 'X-Medusa'),
          const Tab(text: 'TTEncrypt'),
          Tab(text: localizations.signTabParams),
        ]),
      ),
      body: TabBarView(controller: _tab, children: [
        _SignTab(params: _params),
        const _WebBogusTab(),
        _MedusaTab(params: _params),
        const _TtEncryptTab(),
        _ParamsTab(params: _params),
      ]),
    );
  }
}

/// 七神签名页
class _SignTab extends StatefulWidget {
  final ValueNotifier<DouyinSignParams> params;

  const _SignTab({required this.params});

  @override
  State<_SignTab> createState() => _SignTabState();
}

class _SignTabState extends State<_SignTab> {
  final _url = TextEditingController();
  final _body = TextEditingController();
  String _platform = 'android';
  bool _busy = false;
  Map<String, String> _result = {};

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void dispose() {
    _url.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _compute() async {
    final query = extractQuery(_url.text);
    if (query.isEmpty) {
      FlutterToastr.show(localizations.signNeedInput, context, duration: 2);
      return;
    }
    setState(() => _busy = true);
    try {
      final base = widget.params.value;
      final res = await DouyinSign.sevenGods(
        query: query,
        body: _body.text.trim().isEmpty ? null : _body.text,
        params: DouyinSignParams(
          aid: base.aid,
          licenseId: base.licenseId,
          mssdkVersionCodeAndroid: base.mssdkVersionCodeAndroid,
          mssdkVersionCodeIos: base.mssdkVersionCodeIos,
          appVersion: base.appVersion,
          versionCode: base.versionCode,
          platform: _platform,
        ),
      );
      if (!mounted) return;
      setState(() {
        _result = res.map((k, v) => MapEntry(k, v.toString()));
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      FlutterToastr.show(localizations.commonError('$e'), context, duration: 3, backgroundColor: Colors.red);
    }
  }

  /// 从抓包列表挑一条请求，自动填 URL 与 body（省得在手机上抄）。
  Future<void> _pickFromCapture() async {
    final req = await RequestPickSheet.show(context);
    if (req == null || !mounted) return;
    String body = '';
    try {
      body = await req.decodeBodyString();
    } catch (_) {
      body = '';
    }
    if (!mounted) return;
    setState(() {
      _url.text = req.requestUrl;
      if (body.isNotEmpty) _body.text = body;
    });
  }

  void _copyAll() {
    if (_result.isEmpty) return;
    final text = _result.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    Clipboard.setData(ClipboardData(text: text));
    FlutterToastr.show(localizations.copied, context);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(15), children: [
      ToolIntro(
        margin: EdgeInsets.zero,
        text: '把一条抓到的 API 请求（URL + body）粘进来，生成可直接用的字节系签名头。',
        input: '请求 URL（含 ?query）；POST 请求把 body 一并填上',
        output: 'X-Gorgon / X-Khronos / X-Argus 等签名头，可整段复制',
        onExample: () => setState(() {
          _url.text =
              'https://api22-normal-c-useast2a.tiktokv.com/aweme/v1/feed/?aweme_id=1&aid=1128&version_code=300904&device_platform=android';
          _body.text = '';
        }),
        presets: [
          ToolPreset('Android', () => setState(() => _platform = 'android')),
          ToolPreset('iOS', () => setState(() => _platform = 'ios')),
        ],
        help: '签名只与 URL 的 query、body 和设备参数有关：query 里的参数顺序不要重排，'
            '签名才和服务端算出来的一致。要换 App 版本/设备号，去「参数」页改。',
      ),
      Row(children: [
        Text(localizations.signPlatform),
        const SizedBox(width: 12),
        DropdownButton<String>(
          value: _platform,
          items: const [
            DropdownMenuItem(value: 'android', child: Text('Android')),
            DropdownMenuItem(value: 'ios', child: Text('iOS')),
          ],
          onChanged: (v) => setState(() => _platform = v!),
        ),
      ]),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _pickFromCapture,
          icon: const Icon(Icons.inbox_outlined, size: 16),
          label: const Text('从抓包选择', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
        ),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: _url,
        minLines: 1,
        maxLines: 3,
        onTapOutside: (e) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: decoration(context, label: localizations.signUrl, hintText: localizations.signUrlHint),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _body,
        minLines: 2,
        maxLines: 6,
        onTapOutside: (e) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: decoration(context, label: localizations.signBody),
      ),
      const SizedBox(height: 14),
      Center(
        child: FilledButton.icon(
          style: Buttons.buttonStyle,
          onPressed: _busy ? null : _compute,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.vpn_key_outlined),
          label: Text(localizations.signCompute),
        ),
      ),
      const SizedBox(height: 16),
      if (_result.isNotEmpty) ...[
        Row(children: [
          Text(localizations.signHeaders, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const Spacer(),
          TextButton.icon(
            onPressed: _copyAll,
            icon: const Icon(Icons.copy, size: 16),
            label: Text(localizations.signCopyAll),
          ),
        ]),
        const SizedBox(height: 4),
        ..._result.entries.map((e) => _HeaderRow(name: e.key, value: e.value)),
      ],
    ]);
  }
}

class _HeaderRow extends StatelessWidget {
  final String name;
  final String value;

  const _HeaderRow({required this.name, required this.value});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(name, style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
            const Spacer(),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                FlutterToastr.show(l.copied, context);
              },
              child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.copy, size: 16)),
            ),
          ]),
          const SizedBox(height: 4),
          SelectableText(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
        ]),
      ),
    );
  }
}

/// Web 端 a_bogus / X-Bogus
class _WebBogusTab extends StatefulWidget {
  const _WebBogusTab();

  @override
  State<_WebBogusTab> createState() => _WebBogusTabState();
}

class _WebBogusTabState extends State<_WebBogusTab> {
  final _query = TextEditingController();
  final _ua = TextEditingController(
      text: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36');
  final _body = TextEditingController();
  Map<String, String> _result = {};

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void dispose() {
    _query.dispose();
    _ua.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _compute() async {
    final query = extractQuery(_query.text);
    if (query.isEmpty) {
      FlutterToastr.show(localizations.signNeedInput, context, duration: 2);
      return;
    }
    try {
      final xb = await DouyinSign.xBogus(query, body: _body.text.trim());
      final ab = await DouyinSign.aBogus(query, userAgent: _ua.text);
      if (!mounted) return;
      setState(() => _result = {'X-Bogus': xb, 'a_bogus': ab});
    } catch (e) {
      if (!mounted) return;
      FlutterToastr.show(localizations.commonError('$e'), context, duration: 3, backgroundColor: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(15), children: [
      ToolIntro(
        margin: EdgeInsets.zero,
        text: '网页版（douyin.com）的 a_bogus / X-Bogus 签名：粘网页端请求的 query 即可。',
        input: '网页端请求 URL，例如 /aweme/v1/web/aweme/detail/?...',
        output: 'a_bogus（含 X-Bogus 兼容写法）',
        onExample: () => setState(() {
          _query.text =
              'https://www.douyin.com/aweme/v1/web/aweme/detail/?aweme_id=1&device_platform=webapp&aid=6383&channel=channel_pc_web';
        }),
        help: '网页端签名和 App 端不是一套：web 用 a_bogus，App 用 X-Gorgon。粘错端会算出来但对不上服务端。',
      ),
      TextField(
        controller: _query,
        minLines: 1,
        maxLines: 2,
        decoration: decoration(context, label: localizations.signUrl, hintText: localizations.signUrlHint),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _body,
        minLines: 1,
        maxLines: 3,
        decoration: decoration(context, label: localizations.signBody),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _ua,
        minLines: 1,
        maxLines: 3,
        decoration: decoration(context, label: 'User-Agent'),
      ),
      const SizedBox(height: 14),
      Center(
        child: FilledButton.icon(
          style: Buttons.buttonStyle,
          onPressed: _compute,
          icon: const Icon(Icons.calculate_outlined),
          label: Text(localizations.signCompute),
        ),
      ),
      const SizedBox(height: 16),
      ..._result.entries.map((e) => _HeaderRow(name: e.key, value: e.value)),
    ]);
  }
}

/// 版本参数（降低版本耦合）——改动会实时同步到签名页。
class _ParamsTab extends StatefulWidget {
  final ValueNotifier<DouyinSignParams> params;

  const _ParamsTab({required this.params});

  @override
  State<_ParamsTab> createState() => _ParamsTabState();
}

class _ParamsTabState extends State<_ParamsTab> {
  final _aid = TextEditingController(text: '1128');
  final _appVersion = TextEditingController(text: '40.5.0');
  final _versionCode = TextEditingController(text: '400500');
  final _licenseId = TextEditingController(text: '1588093228');
  final _mssdkAndroid = TextEditingController(text: '67503104');
  final _mssdkIos = TextEditingController(text: '67698689');

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    for (final c in [_aid, _appVersion, _versionCode, _licenseId, _mssdkAndroid, _mssdkIos]) {
      c.addListener(_push);
    }
  }

  void _push() {
    widget.params.value = DouyinSignParams(
      aid: int.tryParse(_aid.text.trim()) ?? 1128,
      appVersion: _appVersion.text.trim(),
      versionCode: int.tryParse(_versionCode.text.trim()) ?? 400500,
      licenseId: int.tryParse(_licenseId.text.trim()) ?? 1588093228,
      mssdkVersionCodeAndroid: int.tryParse(_mssdkAndroid.text.trim()) ?? 67503104,
      mssdkVersionCodeIos: int.tryParse(_mssdkIos.text.trim()) ?? 67698689,
    );
  }

  @override
  void dispose() {
    for (final c in [_aid, _appVersion, _versionCode, _licenseId, _mssdkAndroid, _mssdkIos]) {
      c.removeListener(_push);
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(15), children: [
      ToolIntro(
        margin: EdgeInsets.zero,
        text: '签名参数：这些值会参与签名计算，和抓包里的保持一致才能对上服务端。',
        input: 'AID / App 版本 / versionCode / License ID / MSSDK 版本',
        output: '无需输出——改完回「签名」页重新计算即可',
        help: '默认值取自常见公开版本；如果你抓的是特定版本 App，把这些值抄成抓包 set-cookie/query 里的即可。',
      ),
      Text(localizations.signParamsHint, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
      const SizedBox(height: 14),
      _field('AID', _aid),
      _field(localizations.signAppVersion, _appVersion),
      _field(localizations.signVersionCode, _versionCode),
      _field('License ID', _licenseId),
      _field('${localizations.signMssdk} (Android)', _mssdkAndroid),
      _field('${localizations.signMssdk} (iOS)', _mssdkIos),
    ]);
  }

  Widget _field(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.text,
        onTapOutside: (e) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: decoration(context, label: label),
      ),
    );
  }
}

/// 把输入（URL 或查询串）解析成参数表，供 X-Medusa 的 protobuf 使用。
Map<String, dynamic> parseQueryParams(String input) {
  final query = extractQuery(input);
  if (query.isEmpty) return const {};
  try {
    return Uri.splitQueryString(query);
  } catch (_) {
    return const {};
  }
}

/// X-Medusa 签名页
class _MedusaTab extends StatefulWidget {
  final ValueNotifier<DouyinSignParams> params;

  const _MedusaTab({required this.params});

  @override
  State<_MedusaTab> createState() => _MedusaTabState();
}

class _MedusaTabState extends State<_MedusaTab> {
  final _url = TextEditingController();
  final _device = TextEditingController();
  final _lanusk = TextEditingController();
  bool _busy = false;
  String _result = '';

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void dispose() {
    _url.dispose();
    _device.dispose();
    _lanusk.dispose();
    super.dispose();
  }

  Future<void> _compute() async {
    final url = _url.text.trim();
    if (url.isEmpty) {
      FlutterToastr.show(localizations.signNeedInput, context, duration: 2);
      return;
    }
    setState(() => _busy = true);
    try {
      var device = <String, dynamic>{};
      final devText = _device.text.trim();
      if (devText.isNotEmpty) {
        final decoded = jsonDecode(devText);
        if (decoded is Map) device = Map<String, dynamic>.from(decoded);
      }
      final res = await DouyinSign.xMedusa(
        url: url,
        params: parseQueryParams(url),
        device: device,
        lanusk: _lanusk.text.trim().isEmpty ? null : _lanusk.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _result = res;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      FlutterToastr.show(localizations.commonError('$e'), context, duration: 3, backgroundColor: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(15), children: [
      ToolIntro(
        margin: EdgeInsets.zero,
        text: 'X-Medusa 签名：需要完整 URL（含 query），可选覆盖设备信息与 lanusk。',
        input: '完整请求 URL；设备信息（JSON，选填）',
        output: 'X-Medusa 头',
        onExample: () => setState(() {
          _url.text =
              'https://api16-normal-c-useast1a.tiktokv.com/aweme/v1/aweme/post/?sec_user_id=1&max_cursor=0&count=20&aid=1233';
          _device.text = '';
          _lanusk.text = '';
        }),
        help: '设备信息留空会用内置默认设备；填 JSON 时只需要和抓包里的候选字段一致，多余的会被忽略。',
      ),
      Text(localizations.signMedusaHint, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
      const SizedBox(height: 14),
      TextField(
        controller: _url,
        minLines: 1,
        maxLines: 3,
        onTapOutside: (e) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: decoration(context, label: localizations.signUrl, hintText: localizations.signUrlHint),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _device,
        minLines: 2,
        maxLines: 5,
        onTapOutside: (e) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: decoration(context, label: localizations.signMedusaDevice),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _lanusk,
        onTapOutside: (e) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: decoration(context, label: localizations.signMedusaSalt),
      ),
      const SizedBox(height: 14),
      Center(
        child: FilledButton.icon(
          style: Buttons.buttonStyle,
          onPressed: _busy ? null : _compute,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.shield_outlined),
          label: Text(localizations.signCompute),
        ),
      ),
      const SizedBox(height: 16),
      if (_result.isNotEmpty) ...[
        Row(children: [
          Text(localizations.signHeaders, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _result));
              FlutterToastr.show(localizations.copied, context);
            },
            icon: const Icon(Icons.copy, size: 16),
            label: Text(localizations.signCopyAll),
          ),
        ]),
        const SizedBox(height: 4),
        _HeaderRow(name: 'X-Medusa', value: _result),
      ],
    ]);
  }
}

/// TTEncrypt v5 载荷加解密页
class _TtEncryptTab extends StatefulWidget {
  const _TtEncryptTab();

  @override
  State<_TtEncryptTab> createState() => _TtEncryptTabState();
}

class _TtEncryptTabState extends State<_TtEncryptTab> {
  final _input = TextEditingController();
  bool _busy = false;
  String _result = '';

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _run(bool encrypt) async {
    final text = _input.text.trim();
    if (text.isEmpty) {
      FlutterToastr.show(localizations.signNeedInput, context, duration: 2);
      return;
    }
    setState(() => _busy = true);
    try {
      final String out;
      if (encrypt) {
        final bytes = await DouyinSign.ttEncryptString(text);
        out = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      } else {
        out = await DouyinSign.ttDecrypt(_hexToBytes(text));
      }
      if (!mounted) return;
      setState(() {
        _result = out;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      FlutterToastr.show(localizations.commonError('$e'), context, duration: 3, backgroundColor: Colors.red);
    }
  }

  List<int> _hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final bytes = <int>[];
    for (var i = 0; i + 1 < clean.length; i += 2) {
      bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(15), children: [
      ToolIntro(
        margin: EdgeInsets.zero,
        text: 'TTEncrypt v5 载荷加/解密：粘十六进制密文（或明文）直接转换。',
        input: '十六进制字符串（可含空格/换行）',
        output: '转换后的十六进制或明文',
        onExample: () => setState(() {
          _input.text = '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
        }),
        help: 'kestream 随机时同一份明文每次结果不同，属正常；要逐字节比对请用测试向量。',
      ),
      Text(localizations.signTtHint, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
      const SizedBox(height: 14),
      TextField(
        controller: _input,
        minLines: 3,
        maxLines: 10,
        onTapOutside: (e) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: decoration(
          context,
          label: '${localizations.signTtPlain} / ${localizations.signTtCipher}',
        ),
      ),
      const SizedBox(height: 14),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        FilledButton.icon(
          style: Buttons.buttonStyle,
          onPressed: _busy ? null : () => _run(true),
          icon: const Icon(Icons.lock_outline, size: 18),
          label: Text(localizations.signTtEncryptBtn),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          style: Buttons.buttonStyle,
          onPressed: _busy ? null : () => _run(false),
          icon: const Icon(Icons.lock_open_outlined, size: 18),
          label: Text(localizations.signTtDecryptBtn),
        ),
      ]),
      const SizedBox(height: 16),
      ToolResultBox(
        title: localizations.signHeaders,
        value: _result,
        emptyHint: '加密/解密结果会出现在这里',
        saveName: 'ttencrypt',
        minHeight: 90,
      ),
    ]);
  }
}
