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

// 设备信息：型号 / 系统 / CPU / 内存 / 电池 / 屏幕 / 存储。
//
// 数据来源刻意「能不引原生就不引原生」：
//   · 型号、系统版本：device_info_plus（已有依赖）；
//   · 内存、CPU 型号、电池：直接读 /proc/meminfo、/proc/cpuinfo、/sys/class/power_supply
//     （这些都是应用可读的伪文件，Android 上不需要任何权限）；
//   · 存储：`df -k /data`（走已有的 shell 通道，读不到就显示 —）；
//   · 屏幕：MediaQuery（本就有的渲染信息）。
//
// 全是只读信息，不写任何东西。

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/native/mcp_screen.dart';
import 'package:proxypin/utils/platform.dart';

class DeviceInfoPage extends StatefulWidget {
  const DeviceInfoPage({super.key});

  @override
  State<DeviceInfoPage> createState() => _DeviceInfoPageState();
}

class _DeviceInfoPageState extends State<DeviceInfoPage> {
  final List<({String group, String key, String value})> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String> _read(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return '';
      final t = await f.readAsString();
      return t.trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _load() async {
    final loc = AppLocalizations.of(context)!;
    final rows = <({String group, String key, String value})>[];
    void add(String g, String k, String v) {
      if (v.trim().isEmpty) return;
      rows.add((group: g, key: k, value: v.trim()));
    }

    // ---- 系统 ----
    add(loc.devPlatform, 'OS', '${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    try {
      final plugin = DeviceInfoPlugin();
      if (Platforms.isAndroid()) {
        final a = await plugin.androidInfo;
        add(loc.devSystem, 'brand', a.brand);
        add(loc.devSystem, 'model', a.model);
        add(loc.devSystem, 'device', a.device);
        add(loc.devSystem, 'Android', '${a.version.release} (SDK ${a.version.sdkInt})');
        add(loc.devSystem, 'fingerprint', a.fingerprint);
      } else if (Platforms.isIOS()) {
        final i = await plugin.iosInfo;
        add(loc.devSystem, 'name', i.name);
        add(loc.devSystem, 'model', i.model);
        add(loc.devSystem, 'system', '${i.systemName} ${i.systemVersion}');
      } else if (Platform.isWindows) {
        final w = await plugin.windowsInfo;
        add(loc.devSystem, 'computerName', w.computerName);
        add(loc.devSystem, 'productName', w.productName);
      } else if (Platform.isMacOS) {
        final m = await plugin.macOsInfo;
        add(loc.devSystem, 'model', m.model);
        add(loc.devSystem, 'os', '${m.osRelease}');
      } else if (Platform.isLinux) {
        final l = await plugin.linuxInfo;
        add(loc.devSystem, 'distro', l.prettyName);
        add(loc.devSystem, 'kernel', l.kernelVersion);
      }
    } catch (e) {
      add(loc.devSystem, 'error', '$e');
    }

    // ---- CPU ----
    add(loc.devCpu, 'cores', '${Platform.numberOfProcessors}');
    if (Platforms.isAndroid() || Platform.isLinux) {
      final cpuinfo = await _read('/proc/cpuinfo');
      final hw = RegExp(r'^(?:Hardware|model name)\s*:\s*(.+)$', multiLine: true).firstMatch(cpuinfo);
      if (hw != null) add(loc.devCpu, 'model', hw.group(1) ?? '');
      // 各核最高频率（读得到就显示，很多机型只能读到 policy 目录）。
      final maxFreq = <String>[];
      try {
        for (final dir in Directory('/sys/devices/system/cpu').listSync()) {
          final name = dir.path.split('/').last;
          if (!RegExp(r'^cpu\d+$').hasMatch(name)) continue;
          final v = await _read('${dir.path}/cpufreq/cpuinfo_max_freq');
          if (v.isNotEmpty) maxFreq.add('${(int.tryParse(v) ?? 0) ~/ 1000} MHz');
          if (maxFreq.length >= 8) break;
        }
      } catch (_) {}
      if (maxFreq.isNotEmpty) add(loc.devCpu, 'max freq', maxFreq.join(' / '));
    }

    // ---- 内存 ----
    final meminfo = await _read('/proc/meminfo');
    if (meminfo.isNotEmpty) {
      int kb(String key) {
        final m = RegExp('^$key:\\s*(\\d+)\\s*kB', multiLine: true).firstMatch(meminfo);
        return int.tryParse(m?.group(1) ?? '') ?? 0;
      }

      final total = kb('MemTotal');
      final avail = kb('MemAvailable');
      if (total > 0) {
        add(loc.devMem, 'total', '${(total / 1024 / 1024).toStringAsFixed(2)} GB');
        if (avail > 0) {
          add(loc.devMem, 'available', '${(avail / 1024 / 1024).toStringAsFixed(2)} GB');
          add(loc.devMem, 'used',
              '${((total - avail) / 1024 / 1024).toStringAsFixed(2)} GB (${((total - avail) * 100 / total).toStringAsFixed(1)}%)');
        }
      }
    }

    // ---- 电池 ----
    const psBase = '/sys/class/power_supply/battery';
    final capacity = await _read('$psBase/capacity');
    if (capacity.isNotEmpty) add(loc.devBattery, 'level', '$capacity%');
    final status = await _read('$psBase/status');
    if (status.isNotEmpty) add(loc.devBattery, 'status', status);
    final volt = await _read('$psBase/voltage_now');
    if (volt.isNotEmpty) {
      final mv = (int.tryParse(volt) ?? 0) ~/ 1000;
      if (mv > 0) add(loc.devBattery, 'voltage', '$mv mV');
    }
    final temp = await _read('$psBase/temp');
    if (temp.isNotEmpty) {
      final t = (int.tryParse(temp) ?? 0) / 10;
      if (t != 0) add(loc.devBattery, 'temp', '${t.toStringAsFixed(1)} °C');
    }

    // ---- 存储 ----
    if (Platforms.isAndroid()) {
      try {
        final r = await McpScreen.shell('df -k /data', mode: 'auto', timeoutMs: 8000);
        final out = '${r['output'] ?? r['stdout'] ?? ''}';
        final line = out.split('\n').where((l) => l.contains('%')).join(' ').trim();
        if (line.isNotEmpty) add(loc.devStorage, '/data', line);
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _rows
        ..clear()
        ..addAll(rows);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final dpr = MediaQuery.of(context).devicePixelRatio;

    // 屏幕信息直接来自渲染层（不依赖原生），放在最前面。
    final screenRows = <({String key, String value})>[
      (key: 'size', value: '${size.width.toStringAsFixed(0)} × ${size.height.toStringAsFixed(0)} dp'),
      (key: 'pixels', value: '${(size.width * dpr).toStringAsFixed(0)} × ${(size.height * dpr).toStringAsFixed(0)} px'),
      (key: 'dp', value: dpr.toStringAsFixed(2)),
    ];

    final groups = <String, List<({String key, String value})>>{};
    for (final r in _rows) {
      groups.putIfAbsent(r.group, () => []).add((key: r.key, value: r.value));
    }
    groups.putIfAbsent(loc.devScreen, () => []).addAll(screenRows);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.devTitle),
        actions: [
          IconButton(
            tooltip: loc.copy,
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () async {
              final buf = StringBuffer();
              groups.forEach((g, list) {
                buf.writeln('[$g]');
                for (final r in list) {
                  buf.writeln('  ${r.key}: ${r.value}');
                }
              });
              await Clipboard.setData(ClipboardData(text: buf.toString()));
              if (!mounted) return;
              FlutterToastr.show(loc.copied, context, duration: 1);
            },
          ),
          IconButton(tooltip: loc.refresh, icon: const Icon(Icons.refresh), onPressed: () {
            setState(() => _loading = true);
            _load();
          }),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
              children: [
                for (final entry in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Text(entry.key,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary)),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(children: [
                      for (var i = 0; i < entry.value.length; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            border: i == entry.value.length - 1
                                ? null
                                : Border(bottom: BorderSide(color: theme.dividerColor, width: 0.4)),
                          ),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(
                              width: 92,
                              child: Text(entry.value[i].key,
                                  style: TextStyle(
                                      fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant)),
                            ),
                            Expanded(
                              child: SelectableText(entry.value[i].value,
                                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                            ),
                          ]),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
    );
  }
}
