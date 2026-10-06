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
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/transparent/driver_manager.dart';
import 'package:url_launcher/url_launcher.dart';

/// 打开「内核抓包运行库」设置面板：检测 WinDivert 运行库、一键放置、
/// 以及只读探测系统内其它内核抓包能力（NetFilter / Npcap）。
void showDriverSetupDialog(BuildContext context) {
  showDialog(context: context, builder: (_) => const _DriverSetupDialog());
}

class _DriverSetupDialog extends StatefulWidget {
  const _DriverSetupDialog();

  @override
  State<_DriverSetupDialog> createState() => _DriverSetupDialogState();
}

class _DriverSetupDialogState extends State<_DriverSetupDialog> {
  WindivertStatus? _wd;
  KernelDriverStatus? _kds;
  bool _busy = false;
  String _log = '';
  double? _progress;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final wd = WindivertDriver.inspect();
    final kds = await KernelDriverProbe.inspect();
    if (!mounted) return;
    setState(() {
      _wd = wd;
      _kds = kds;
    });
  }

  void _append(String line) {
    if (!mounted) return;
    setState(() => _log = '$_log$line\n');
  }

  Future<void> _download() async {
    final l = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _progress = 0;
      _log = '';
    });
    final err = await WindivertDriver.installFromUrl(
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
      log: _append,
    );
    await _refresh();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = null;
    });
    if (err == null) {
      FlutterToastr.show(l.kernelDriverInstallOk, context);
    } else {
      FlutterToastr.show('${l.kernelDriverInstallFail}: $err', context, backgroundColor: Colors.red);
    }
  }

  Future<void> _pickZip() async {
    final l = AppLocalizations.of(context)!;
    try {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
      if (files == null || files.isEmpty) return;
      final path = files.single.xFile.path;
      setState(() {
        _busy = true;
        _log = '';
      });
      final err = await WindivertDriver.installFromZipFile(path, log: _append);
      await _refresh();
      if (!mounted) return;
      setState(() => _busy = false);
      if (err == null) {
        FlutterToastr.show(l.kernelDriverInstallOk, context);
      } else {
        FlutterToastr.show('${l.kernelDriverInstallFail}: $err', context, backgroundColor: Colors.red);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        FlutterToastr.show('${l.kernelDriverInstallFail}: $e', context, backgroundColor: Colors.red);
      }
    }
  }

  Future<void> _openDir() async {
    try {
      if (Platform.isWindows) {
        await Process.start('explorer', [WindivertDriver.targetDir()]);
      }
    } catch (_) {}
  }

  Future<void> _openRelease() async {
    try {
      await launchUrl(Uri.parse(WindivertDriver.officialReleasesPage), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final wd = _wd;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.memory, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(l.kernelDriverTitle)),
          IconButton(icon: const Icon(Icons.refresh, size: 20), tooltip: l.kernelDriverDetect, onPressed: _busy ? null : _refresh),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      content: SizedBox(
        width: 620,
        height: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wd == null)
                const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator(minHeight: 3))
              else ...[
                _statusRow(l.kernelDriverDllLabel, wd.dllFound, wd.dllPath),
                _statusRow(l.kernelDriverSysLabel, wd.sysFound, wd.sysPath),
                _kv(l.kernelDriverVersionLabel, wd.version ?? '—'),
                _kv(l.kernelDriverTargetLabel, wd.targetDir),
                if (wd.searchedDirs.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(l.kernelDriverSearched, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  ...wd.searchedDirs.take(8).map((d) => Text('· $d',
                      style: TextStyle(fontSize: 11, color: Colors.grey[700]))),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _download,
                      icon: const Icon(Icons.download, size: 18),
                      label: Text(_busy && _progress != null ? l.kernelDriverDownloading : l.kernelDriverDownload),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickZip,
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: Text(l.kernelDriverPickZip),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openDir,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(l.kernelDriverOpenDir),
                    ),
                    TextButton(
                      onPressed: _openRelease,
                      child: Text(l.kernelDriverOpenRelease),
                    ),
                  ],
                ),
                if (_progress != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: _progress, minHeight: 4),
                ],
              ],
              const SizedBox(height: 14),
              const Divider(height: 1, thickness: 0.4),
              const SizedBox(height: 10),
              Text(l.kernelNetfilterTitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              if (_kds != null && _kds!.supported) ...[
                _detectRow(l.kernelNetfilterDriver, _kds!.netfilterDriverFound, _kds!.netfilterDriverPath),
                _detectRow(l.kernelNetfilterService, _kds!.netfilterServiceFound, _kds!.netfilterServiceState),
                _detectRow(l.kernelNfapi, _kds!.nfapiFound, null),
                _detectRow(l.kernelNpcap, _kds!.npcapFound, _kds!.npcapPath),
                const SizedBox(height: 6),
                Text(l.kernelNetfilterNote, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
              ] else
                Text('—', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              if (_log.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(l.kernelDriverLog, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_log, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.close)),
      ],
    );
  }

  Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 130, child: Text(label, style: TextStyle(fontSize: 12.5, color: Colors.grey[700]))),
            Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 12.5))),
          ],
        ),
      );

  Widget _statusRow(String label, bool ok, String? path) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ok ? Icons.check_circle : Icons.cancel_outlined, size: 16, color: ok ? Colors.green : Colors.red),
            const SizedBox(width: 6),
            SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 12.5))),
            Expanded(
              child: Text(path ?? '—',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[700]), overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );

  Widget _detectRow(String label, bool found, String? detail) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(found ? Icons.check_circle : Icons.remove_circle_outline, size: 15, color: found ? Colors.green : Colors.grey),
          const SizedBox(width: 6),
          SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 12.5))),
          Expanded(
            child: Text(
              found ? (detail ?? l.kernelDetected) : l.kernelNotDetected,
              style: TextStyle(fontSize: 11.5, color: found ? Colors.grey[800] : Colors.grey[600]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
