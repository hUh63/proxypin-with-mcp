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

// 机型伪装：读当前 ro.product.* 属性，按预设一键改写（需 Root）。
//
// 实现走现有的 McpScreen.shell 通道（支持 root / Shizuku / Dhizuku），不新开原生接口：
//   · `ro.*` 属性在正常系统里**只读**，setprop 改不动 —— 只有 Magisk 的 resetprop
//     能改（内存级，重启即恢复）；
//   · 所以先探测 `which resetprop`，有就用它，没有才退 setprop 并如实提示「大概率
//     不生效」。
//
// 用途：装 App 时把自己设备伪装成另一台机型做兼容性验证、跑自动化脚本需要固定机型
// 指纹、复现某个机型专属问题。改完重启就恢复，不写入任何持久分区。

import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/native/mcp_screen.dart';

/// 一套机型预设（就是那几条 ro.product 属性）。
class DeviceSpoofPreset {
  final String brand;
  final String model;
  final String device;
  final String manufacturer;
  final String? fingerprint;

  const DeviceSpoofPreset({
    required this.brand,
    required this.model,
    required this.device,
    required this.manufacturer,
    this.fingerprint,
  });

  String get label => '$manufacturer $model';
}

class DeviceSpoof {
  DeviceSpoof._();

  /// 常用测试机型：覆盖四个厂商、两种 Android 版本段的指纹格式。
  static const List<DeviceSpoofPreset> presets = [
    DeviceSpoofPreset(
      brand: 'Xiaomi',
      model: '23127PN0CC',
      device: 'houji',
      manufacturer: 'Xiaomi',
      fingerprint: 'Xiaomi/houji/houji:14/UKQ1.231003.002/OS1.0.1.0.UNCCNXM:user/release-keys',
    ),
    DeviceSpoofPreset(
      brand: 'Redmi',
      model: '23113RKC6C',
      device: 'manet',
      manufacturer: 'Redmi',
      fingerprint: 'Redmi/manet/manet:14/UKQ1.230804.001/OS1.0.2.0.UNLCNXM:user/release-keys',
    ),
    DeviceSpoofPreset(
      brand: 'samsung',
      model: 'SM-S9180',
      device: 'dm3q',
      manufacturer: 'samsung',
      fingerprint: 'samsung/dm3q/dp1:14/UP1A.231005.007/S9180ZHU2BWL1:user/release-keys',
    ),
    DeviceSpoofPreset(
      brand: 'google',
      model: 'Pixel 8',
      device: 'shiba',
      manufacturer: 'Google',
      fingerprint: 'google/shiba/shiba:14/UQ1A.240205.004/11269751:user/release-keys',
    ),
    DeviceSpoofPreset(
      brand: 'HUAWEI',
      model: 'ALN-AL00',
      device: 'ALN',
      manufacturer: 'HUAWEI',
      fingerprint: 'HUAWEI/ALN-AL00/HUALN:12/HUAWEIALN-AL00/4.2.1.1:user/release-keys',
    ),
  ];

  /// 要读写的属性（顺序即界面上的显示顺序）。
  static const List<String> keys = [
    'ro.product.brand',
    'ro.product.model',
    'ro.product.device',
    'ro.product.manufacturer',
    'ro.build.fingerprint',
  ];

  static Future<String> _getProp(String key) async {
    try {
      final r = await McpScreen.shell('getprop $key', mode: 'auto', timeoutMs: 8000);
      final out = '${r['output'] ?? r['stdout'] ?? ''}'.trim();
      return out;
    } catch (_) {
      return '';
    }
  }

  /// 读当前这一组属性。
  static Future<Map<String, String>> readCurrent() async {
    final out = <String, String>{};
    for (final k in keys) {
      out[k] = await _getProp(k);
    }
    return out;
  }

  /// resetprop 是否可用（Magisk / KernelSU 自带）。
  static Future<bool> hasResetProp() async {
    try {
      final r = await McpScreen.shell('which resetprop', mode: 'auto', timeoutMs: 8000);
      final out = '${r['output'] ?? r['stdout'] ?? ''}'.trim();
      return out.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 应用一套预设。返回 (成功写入的属性数, 提示信息)。
  static Future<({int applied, bool usedResetProp})> apply(DeviceSpoofPreset p) async {
    final useResetProp = await hasResetProp();
    final cmd = useResetProp ? 'resetprop' : 'setprop';
    final pairs = <String, String>{
      'ro.product.brand': p.brand,
      'ro.product.model': p.model,
      'ro.product.device': p.device,
      'ro.product.manufacturer': p.manufacturer,
      if (p.fingerprint != null) 'ro.build.fingerprint': p.fingerprint!,
    };
    var ok = 0;
    // 一条命令里顺序执行，减少一次授权的往返。
    final script = pairs.entries.map((e) => "$cmd '${e.key}' '${e.value}'").join('; ');
    try {
      final r = await McpScreen.shell(script, mode: 'root', timeoutMs: 20000);
      final code = r['exitCode'] ?? r['code'];
      final output = '${r['output'] ?? r['stdout'] ?? ''}';
      // shell 通道不逐个报错，用「退出码 + 输出里有没有 denied」判成败；
      // 逐个再读一遍是最实在的校验。
      final after = await readCurrent();
      for (final e in pairs.entries) {
        if ((after[e.key] ?? '').trim() == e.value) ok++;
      }
      if (ok == 0 && (output.contains('denied') || output.contains('not found') || code == 127)) {
        return (applied: 0, usedResetProp: useResetProp);
      }
    } catch (_) {
      return (applied: 0, usedResetProp: useResetProp);
    }
    return (applied: ok, usedResetProp: useResetProp);
  }
}

/// 机型伪装页。
class DeviceSpoofPage extends StatefulWidget {
  const DeviceSpoofPage({super.key});

  @override
  State<DeviceSpoofPage> createState() => _DeviceSpoofPageState();
}

class _DeviceSpoofPageState extends State<DeviceSpoofPage> {
  Map<String, String> _current = const {};
  Map<String, String> _backup = const {};
  bool _resetProp = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _toast(String msg) {
    if (!mounted) return;
    FlutterToastr.show(msg, context, duration: 2);
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final cur = await DeviceSpoof.readCurrent();
    final rp = await DeviceSpoof.hasResetProp();
    if (!mounted) return;
    setState(() {
      _current = cur;
      if (_backup.isEmpty) _backup = Map<String, String>.from(cur);
      _resetProp = rp;
      _busy = false;
    });
  }

  Future<void> _apply(DeviceSpoofPreset p) async {
    final loc = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    final r = await DeviceSpoof.apply(p);
    final cur = await DeviceSpoof.readCurrent();
    if (!mounted) return;
    setState(() {
      _current = cur;
      _busy = false;
    });
    if (r.applied == 0) {
      _toast(loc.spoofFailed);
    } else {
      _toast(loc.spoofApplied('${r.applied}'));
    }
  }

  Future<void> _restore() async {
    final loc = AppLocalizations.of(context)!;
    if (_backup.isEmpty) return;
    final p = DeviceSpoofPreset(
      brand: _backup['ro.product.brand'] ?? '',
      model: _backup['ro.product.model'] ?? '',
      device: _backup['ro.product.device'] ?? '',
      manufacturer: _backup['ro.product.manufacturer'] ?? '',
      fingerprint: _backup['ro.build.fingerprint'],
    );
    setState(() => _busy = true);
    final r = await DeviceSpoof.apply(p);
    final cur = await DeviceSpoof.readCurrent();
    if (!mounted) return;
    setState(() {
      _current = cur;
      _busy = false;
    });
    _toast(r.applied == 0 ? loc.spoofFailed : loc.spoofRestored);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.spoofTitle),
        actions: [
          IconButton(tooltip: loc.refresh, icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
        children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            Chip(
              avatar: Icon(_resetProp ? Icons.check_circle : Icons.info_outline,
                  size: 15, color: _resetProp ? Colors.green : Colors.orange),
              label: Text(_resetProp ? 'resetprop' : 'setprop（ro.* 可能改不动）',
                  style: const TextStyle(fontSize: 11.5)),
              visualDensity: VisualDensity.compact,
            ),
            Chip(
              avatar: const Icon(Icons.security, size: 15),
              label: Text(loc.spoofNeedRoot, style: const TextStyle(fontSize: 11.5)),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 10),
          Text(loc.spoofCurrent, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(border: Border.all(color: theme.dividerColor)),
            child: Column(children: [
              for (final k in DeviceSpoof.keys)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(children: [
                    Expanded(
                      flex: 4,
                      child: Text(k.replaceFirst('ro.product.', '').replaceFirst('ro.build.', ''),
                          style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant)),
                    ),
                    Expanded(
                      flex: 6,
                      child: SelectableText(_current[k] ?? '—',
                          style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace')),
                    ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Text(loc.spoofPresets, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton(onPressed: _busy ? null : _restore, child: Text(loc.spoofRestore)),
          ]),
          for (final p in DeviceSpoof.presets)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                title: Text(p.label, style: const TextStyle(fontSize: 13)),
                subtitle: Text('${p.brand} · ${p.device}',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                trailing: FilledButton.tonal(
                  onPressed: _busy ? null : () => _apply(p),
                  child: Text(loc.spoofApply, style: const TextStyle(fontSize: 12)),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(loc.spoofNote, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
