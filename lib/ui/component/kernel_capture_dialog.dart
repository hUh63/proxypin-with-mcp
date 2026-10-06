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
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/transparent/driver_manager.dart';
import 'package:proxypin/network/transparent/transparent_capture.dart';
import 'package:proxypin/network/transparent/transparent_relay.dart';
import 'package:proxypin/ui/component/driver_setup_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 内核级免代理抓包（实验）。详见 docs/kernel_capture_windivert.md。
void showKernelCaptureDialog(BuildContext context) {
  showDialog(context: context, builder: (_) => const _KernelCaptureDialog());
}

class _KernelCaptureDialog extends StatefulWidget {
  const _KernelCaptureDialog();

  @override
  State<_KernelCaptureDialog> createState() => _KernelCaptureDialogState();
}

class _KernelCaptureDialogState extends State<_KernelCaptureDialog> {
  static const String _prefsKey = 'kernel_capture_config_v1';

  final _capture = TransparentCapture.instance;
  final _tcpPortsCtrl = TextEditingController(text: '80,443');
  final _udpPortsCtrl = TextEditingController(text: '53');
  final _dnsRulesCtrl = TextEditingController();
  StreamSubscription? _sub;
  bool _busy = false;
  bool _driverReady = false;
  bool _captureUdp = false;

  @override
  void initState() {
    super.initState();
    _driverReady = WindivertDriver.inspect().ready;
    _loadConfig();
    _sub = _capture.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tcpPortsCtrl.dispose();
    _udpPortsCtrl.dispose();
    _dnsRulesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _tcpPortsCtrl.text = ((m['tcpPorts'] as List?)?.join(',') ?? '80,443');
        _udpPortsCtrl.text = ((m['udpPorts'] as List?)?.join(',') ?? '53');
        _captureUdp = m['captureUdp'] == true;
        final rw = m['dnsRewrite'];
        if (rw is Map) {
          _dnsRulesCtrl.text = rw.entries.map((e) => '${e.key}=${e.value}').join('\n');
        }
      });
    } catch (_) {
      // 配置损坏则用默认
    }
  }

  Future<void> _saveConfig(TransparentCaptureConfig cfg) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(cfg.toJson()));
    } catch (_) {}
  }

  static List<int> _parsePorts(String text) {
    final out = <int>[];
    for (final p in text.split(RegExp(r'[,，\s]+'))) {
      final v = int.tryParse(p.trim());
      if (v != null && v > 0 && v <= 65535 && !out.contains(v)) out.add(v);
    }
    return out;
  }

  /// 每行 `域名=IP`；`#` 开头为注释；键可为 `*.example.com`。
  static Map<String, String> _parseDnsRules(String text) {
    final map = <String, String>{};
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final i = t.indexOf('=');
      if (i <= 0) continue;
      final k = t.substring(0, i).trim().toLowerCase();
      final v = t.substring(i + 1).trim();
      if (k.isNotEmpty && v.isNotEmpty) map[k] = v;
    }
    return map;
  }

  Future<void> _start() async {
    final l = AppLocalizations.of(context)!;
    final server = ProxyServer.current;
    if (server == null || !server.isRunning) {
      FlutterToastr.show(l.kernelCaptureNeedServer, context, backgroundColor: Colors.orange);
      return;
    }
    final cfg = TransparentCaptureConfig(
      tcpPorts: _parsePorts(_tcpPortsCtrl.text),
      captureUdp: _captureUdp,
      udpPorts: _parsePorts(_udpPortsCtrl.text),
      dnsRewrite: _parseDnsRules(_dnsRulesCtrl.text),
    );
    setState(() => _busy = true);
    try {
      await _saveConfig(cfg);
      final relayPort = await TransparentRelay.instance.start(proxyPort: server.port);
      final result = await _capture.start(relayPort: relayPort, config: cfg);
      if (!mounted) return;
      switch (result) {
        case TransparentCaptureStart.ok:
          FlutterToastr.show(l.kernelCaptureStartOk, context);
          break;
        case TransparentCaptureStart.notWindows:
          FlutterToastr.show(l.kernelCaptureNotWindows, context, backgroundColor: Colors.red);
          break;
        case TransparentCaptureStart.noDriver:
          FlutterToastr.show(l.kernelCaptureNoDriver, context, backgroundColor: Colors.red);
          break;
        case TransparentCaptureStart.noPermission:
          FlutterToastr.show(l.kernelCaptureNeedAdmin, context, backgroundColor: Colors.red);
          break;
        case TransparentCaptureStart.noTcpPorts:
          FlutterToastr.show(l.kernelCaptureNoPorts, context, backgroundColor: Colors.orange);
          break;
        case TransparentCaptureStart.alreadyRunning:
          break;
        case TransparentCaptureStart.failed:
          FlutterToastr.show('${l.kernelCaptureFailed}: ${_capture.stats.lastError ?? ''}', context,
              backgroundColor: Colors.red);
          break;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    try {
      await _capture.stop();
      await TransparentRelay.instance.stop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final s = _capture.stats;
    final running = _capture.isRunning;
    final isWindows = Platform.isWindows;

    return AlertDialog(
      title: Text(l.kernelCaptureTitle),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l.kernelCaptureWarning, style: const TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _kv(l.kernelCaptureStatus, running ? l.kernelCaptureRunning : l.kernelCaptureStopped,
                  color: running ? Colors.green : Colors.grey),
              _driverRow(l, s.driverVersion, isWindows),
              _kv(l.kernelCaptureNat, '${_capture.natCount}'),
              _kv(l.kernelCaptureRelayed, '${TransparentRelay.instance.relayed}'),
              const SizedBox(height: 6),
              Text(
                l.kernelCaptureStats(s.redirectedSyn, s.returnedPackets, s.skippedSelf),
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
              _kv(l.kernelCaptureUdpPackets, '${s.udpPackets}'),
              _kv(l.kernelCaptureDns, '${s.dnsQueries}'),
              _kv(l.kernelCaptureDnsRewritten, '${s.dnsRewritten}'),
              const SizedBox(height: 10),
              const Divider(height: 1, thickness: 0.4),
              const SizedBox(height: 8),
              Text(l.kernelCaptureScope, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(l.kernelCaptureTcpPorts, style: const TextStyle(fontSize: 12.5)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _tcpPortsCtrl,
                      enabled: !running,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '80,443',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(l.kernelCaptureUdp, style: const TextStyle(fontSize: 12.5)),
                value: _captureUdp,
                onChanged: running ? null : (v) => setState(() => _captureUdp = v),
              ),
              if (_captureUdp)
                Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(l.kernelCaptureUdpPorts, style: const TextStyle(fontSize: 12.5)),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _udpPortsCtrl,
                        enabled: !running,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '53',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              if (_captureUdp) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(l.kernelCaptureDnsRewrite, style: const TextStyle(fontSize: 12.5)),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _dnsRulesCtrl,
                  enabled: !running,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'example.com=1.2.3.4\n*.corp.local=10.0.0.1',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                ),
              ],
              if (s.recentDns.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Divider(height: 1, thickness: 0.4),
                const SizedBox(height: 8),
                Text(l.kernelCaptureRecentDns, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ...s.recentDns.take(12).map((d) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text(
                        '${d.rewritten ? '✓ ' : ''}${d.type}  ${d.name}  →  ${d.dst}',
                        style: TextStyle(fontSize: 11.5, color: d.rewritten ? Colors.green[800] : Colors.grey[800]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.close)),
        FilledButton(
          onPressed: _busy ? null : (running ? _stop : _start),
          child: Text(running ? l.kernelCaptureStop : l.kernelCaptureStart),
        ),
      ],
    );
  }

  Widget _kv(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700]))),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      );

  /// 驱动行：状态点 + 版本/说明 + 「检测/安装驱动」入口。
  Widget _driverRow(AppLocalizations l, String? version, bool isWindows) {
    final ready = _driverReady;
    final text = version ??
        (isWindows ? (ready ? l.kernelDriverStatusOk : l.kernelDriverStatusMissing) : l.kernelCaptureNotWindows);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(ready ? Icons.check_circle : Icons.error_outline, size: 15, color: ready ? Colors.green : Colors.orange),
          const SizedBox(width: 6),
          Expanded(child: Text(l.kernelCaptureDriver, style: TextStyle(fontSize: 13, color: Colors.grey[700]))),
          Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          if (isWindows)
            TextButton(
              onPressed: () => showDriverSetupDialog(context),
              child: Text(l.kernelCaptureDriverCheck),
            ),
        ],
      ),
    );
  }
}
