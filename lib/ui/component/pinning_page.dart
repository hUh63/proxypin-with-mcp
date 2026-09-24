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
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/pinning_helper.dart';

/// SSL Pinning 绕过辅助页。
///
/// 定位：**探测 + 生成 + 调用**，不打包任何第三方二进制。
/// 界面上把「这一步在做什么、需要什么前提、边界在哪」讲清楚，
/// 避免用户以为点一下就能自动绕过所有应用的证书固定。
class PinningPage extends StatefulWidget {
  const PinningPage({super.key});

  @override
  State<PinningPage> createState() => _PinningPageState();
}

class _PinningPageState extends State<PinningPage> {
  final _package = TextEditingController();
  PinningEnv? _env;
  bool _checking = false;
  bool _spawn = true;
  String _log = '';

  AppLocalizations get localizations => AppLocalizations.of(context)!;
  bool get _isCN => localizations.localeName == 'zh';

  @override
  void initState() {
    super.initState();
    if (PinningHelper.supported) {
      _refresh();
    }
  }

  @override
  void dispose() {
    _package.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _checking = true);
    final env = await PinningHelper.detect();
    if (!mounted) return;
    setState(() {
      _env = env;
      _checking = false;
    });
  }

  void _toast(String msg, {int seconds = 5}) {
    FlutterToastr.show(msg, context, rootNavigator: true, duration: seconds);
  }

  Future<void> _deploy() async {
    final r = await PinningHelper.deployScript();
    if (!mounted) return;
    _toast(r.$1
        ? (_isCN ? '脚本已部署到 ${r.$2}' : 'Script deployed to ${r.$2}')
        : (_isCN ? '部署失败：${r.$2}' : 'Deploy failed: ${r.$2}'));
  }

  Future<void> _attach() async {
    final pkg = _package.text.trim();
    if (pkg.isEmpty) {
      _toast(_isCN ? '请填写目标应用包名' : 'Enter the target package name');
      return;
    }
    _toast(_isCN ? '正在注入…' : 'Attaching…', seconds: 2);
    final r = await PinningHelper.attach(pkg, spawn: _spawn);
    if (!mounted) return;
    if (r.$1) {
      _toast(_isCN ? '已注入：${r.$2}' : 'Attached: ${r.$2}', seconds: 6);
      _loadLog();
    } else {
      _toast(_isCN ? '注入失败：${r.$2}' : 'Attach failed: ${r.$2}', seconds: 7);
    }
  }

  Future<void> _stop() async {
    final r = await PinningHelper.stop();
    if (!mounted) return;
    _toast(r.$1
        ? (_isCN ? '已停止注入' : 'Injection stopped')
        : (_isCN ? '停止失败' : 'Stop failed'));
  }

  Future<void> _loadLog() async {
    final log = await PinningHelper.readLog();
    if (!mounted) return;
    setState(() => _log = log);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(_isCN ? 'SSL Pinning 绕过辅助' : 'SSL Pinning Bypass Helper',
            style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: _isCN ? '刷新环境' : 'Refresh',
            onPressed: _checking ? null : _refresh,
            icon: _checking
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !PinningHelper.supported
          ? Center(child: Text(_isCN ? '仅 Android 支持' : 'Android only'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _notice(),
                const SizedBox(height: 12),
                _envCard(),
                const SizedBox(height: 16),
                _step1(),
                const SizedBox(height: 16),
                _step2(),
                const SizedBox(height: 12),
                Row(children: [
                  OutlinedButton(onPressed: _stop, child: Text(_isCN ? '停止注入' : 'Stop')),
                  const SizedBox(width: 10),
                  TextButton(onPressed: _loadLog, child: Text(_isCN ? '查看注入日志' : 'View log')),
                ]),
                if (_log.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(_log,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                  ),
                ],
                const SizedBox(height: 20),
                _step3(),
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
        _isCN
            ? '仅在你拥有的设备上、对你**有授权**的目标应用使用（自己的应用，或已获书面授权的应用）。\n'
                '绕过证书固定属于对目标进程的运行时干预，未经授权使用可能违反对方协议或法律。\n'
                '本工具不内置任何第三方二进制（frida-server / Xposed 模块都不带）。'
            : 'Use only on devices you own and on apps you are authorized to test. '
                'Bypassing certificate pinning is runtime intervention into the target process. '
                'No third-party binaries (frida-server, Xposed modules) are bundled.',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _envCard() {
    final env = _env;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isCN ? '环境检测' : 'Environment',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (env == null)
              Text(_isCN ? '检测中…' : 'checking…')
            else ...[
              _envRow('root', env.root),
              _envRow('frida-server', env.fridaServer),
              _envRow('frida CLI', env.fridaCli),
              _envRow('frida-inject', env.fridaInject),
              const SizedBox(height: 6),
              Text(
                env.canInject
                    ? (_isCN ? '可以注入：设备端已具备 frida 工具' : 'Ready to attach')
                    : (_isCN
                        ? '还不能注入。需要：① root 已授权；② 设备上有 frida-inject（推荐，可脱离电脑）或 frida CLI。\n'
                            '没有也行——脚本照样能生成，你把它拿到电脑上用 frida -U -f <包名> -l 脚本 注入。'
                        : 'Not ready. Need root + frida-inject (recommended) or frida CLI on device. '
                            'You can still generate the script and run it from a PC.'),
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _envRow(String label, bool ok) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(ok ? Icons.check_circle : Icons.cancel, size: 15, color: ok ? Colors.green : Colors.grey),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13)),
      ]),
    );
  }

  Widget _step1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_isCN ? '① 生成并部署 hook 脚本' : '1. Generate & deploy hook script',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          _isCN
              ? '覆盖常见实现：Conscrypt TrustManagerImpl、SSLContext.init、OkHttp CertificatePinner、HostnameVerifier。'
              : 'Covers Conscrypt TrustManagerImpl, SSLContext.init, OkHttp CertificatePinner, HostnameVerifier.',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton(onPressed: _deploy, child: Text(_isCN ? '部署到设备' : 'Deploy to device')),
          const SizedBox(width: 10),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: PinningHelper.buildScript()));
              _toast(_isCN ? '脚本已复制' : 'Script copied', seconds: 2);
            },
            child: Text(_isCN ? '复制脚本' : 'Copy script'),
          ),
        ]),
      ],
    );
  }

  Widget _step2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_isCN ? '② 注入到目标应用' : '2. Attach to target app',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _package,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            labelText: _isCN ? '包名（如 com.example.app）' : 'Package name',
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _spawn,
          onChanged: (v) => setState(() => _spawn = v),
          title: Text(_isCN ? '启动时注入（应对「启动即校验」）' : 'Spawn mode (app checks on launch)',
              style: const TextStyle(fontSize: 13)),
        ),
        FilledButton.tonal(
          onPressed: _attach,
          child: Text(_isCN ? '注入' : 'Attach'),
        ),
      ],
    );
  }

  Widget _step3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_isCN ? '还有别的办法吗？' : 'Other options',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          _isCN
              ? '· 先确认不是「证书没装好」：抓包自检里第 2 层才是证书固定，第 1 层装系统证书就能解决（见证书页）。\n'
                  '· 有 Magisk/LSPosed 的设备，用现成的 pinning 绕过模块更省事，与本工具是并列关系。\n'
                  '· Flutter 应用用 Dart 自己的根证书列表，不读系统 CA，需要专门处理。'
              : '· First rule out "CA not installed": layer 1 is solved by installing the CA into the system store.\n'
                  '· With Magisk/LSPosed, a ready-made pinning-bypass module is simpler.\n'
                  '· Flutter apps use Dart\'s own root list and need separate handling.',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}
