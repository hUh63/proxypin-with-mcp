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
        ? localizations.pinningDeployDone(r.$2)
        : localizations.pinningDeployFailed(r.$2));
  }

  Future<void> _attach() async {
    final pkg = _package.text.trim();
    if (pkg.isEmpty) {
      _toast(localizations.pinningNeedPackage);
      return;
    }
    _toast(localizations.pinningAttaching, seconds: 2);
    final r = await PinningHelper.attach(pkg, spawn: _spawn);
    if (!mounted) return;
    if (r.$1) {
      _toast(localizations.pinningAttached(r.$2), seconds: 6);
      _loadLog();
    } else {
      _toast(localizations.pinningAttachFailed(r.$2), seconds: 7);
    }
  }

  Future<void> _stop() async {
    final r = await PinningHelper.stop();
    if (!mounted) return;
    _toast(r.$1 ? localizations.pinningStopDone : localizations.pinningStopFailed);
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
        title: Text(localizations.pinningTitle, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: localizations.pinningRefreshEnv,
            onPressed: _checking ? null : _refresh,
            icon: _checking
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !PinningHelper.supported
          ? Center(child: Text(localizations.pinningAndroidOnly))
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
                  OutlinedButton(onPressed: _stop, child: Text(localizations.stop)),
                  const SizedBox(width: 10),
                  TextButton(onPressed: _loadLog, child: Text(localizations.pinningViewLog)),
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
        localizations.pinningNotice,
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
            Text(localizations.pinningEnvTitle,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (env == null)
              Text(localizations.pinningChecking)
            else ...[
              _envRow('root', env.root),
              _envRow('frida-server', env.fridaServer),
              _envRow('frida CLI', env.fridaCli),
              _envRow('frida-inject', env.fridaInject),
              const SizedBox(height: 6),
              Text(
                env.canInject ? localizations.pinningReady : localizations.pinningNotReady,
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
        Text(localizations.pinningStep1Title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          localizations.pinningStep1Hint,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton(onPressed: _deploy, child: Text(localizations.pinningDeploy)),
          const SizedBox(width: 10),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: PinningHelper.buildScript()));
              _toast(localizations.pinningScriptCopied, seconds: 2);
            },
            child: Text(localizations.pinningCopyScript),
          ),
        ]),
      ],
    );
  }

  Widget _step2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(localizations.pinningStep2Title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _package,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            labelText: localizations.pinningPackageHint,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _spawn,
          onChanged: (v) => setState(() => _spawn = v),
          title: Text(localizations.pinningSpawn,
              style: const TextStyle(fontSize: 13)),
        ),
        FilledButton.tonal(
          onPressed: _attach,
          child: Text(localizations.pinningAttach),
        ),
      ],
    );
  }

  Widget _step3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(localizations.pinningOtherOptions,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          localizations.pinningOtherHint,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}
