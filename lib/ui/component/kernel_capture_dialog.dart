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
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/transparent/transparent_capture.dart';
import 'package:proxypin/network/transparent/transparent_relay.dart';

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
  final _capture = TransparentCapture.instance;
  StreamSubscription? _sub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sub = _capture.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final l = AppLocalizations.of(context)!;
    final server = ProxyServer.current;
    if (server == null || !server.isRunning) {
      FlutterToastr.show(l.kernelCaptureNeedServer, context, backgroundColor: Colors.orange);
      return;
    }
    setState(() => _busy = true);
    try {
      final relayPort = await TransparentRelay.instance.start(proxyPort: server.port);
      final result = await _capture.start(relayPort: relayPort);
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
        width: 560,
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
              _kv(l.kernelCaptureDriver, s.driverVersion ?? (isWindows ? '—' : l.kernelCaptureNotWindows)),
              _kv(l.kernelCaptureNat, '${_capture.natCount}'),
              _kv(l.kernelCaptureRelayed, '${TransparentRelay.instance.relayed}'),
              const SizedBox(height: 6),
              Text(
                l.kernelCaptureStats(s.redirectedSyn, s.returnedPackets, s.skippedSelf),
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
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
}
