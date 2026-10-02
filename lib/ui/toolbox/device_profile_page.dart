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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/device_profile.dart';

import '../component/buttons.dart';

/// 设备指纹生成器：按机型模板合成一份自洽的 Android 设备指纹。
class DeviceProfilePage extends StatefulWidget {
  const DeviceProfilePage({super.key});

  @override
  State<DeviceProfilePage> createState() => _DeviceProfilePageState();
}

class _DeviceProfilePageState extends State<DeviceProfilePage> {
  String _model = DeviceProfile.models().first;
  Map<String, String> _profile = {};

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  void _generate() {
    setState(() => _profile = DeviceProfile.generate(_model));
  }

  void _copyAll() {
    if (_profile.isEmpty) return;
    Clipboard.setData(ClipboardData(text: DeviceProfile.toQueryString(_profile)));
    FlutterToastr.show(localizations.copied, context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(localizations.toolboxDevice, style: const TextStyle(fontSize: 16)), centerTitle: true),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(15),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(localizations.deviceModel),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<String>(
                  value: _model,
                  isExpanded: true,
                  items: DeviceProfile.models()
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => setState(() => _model = v!),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: Buttons.buttonStyle,
                  onPressed: _generate,
                  icon: const Icon(Icons.smartphone),
                  label: Text(localizations.signCompute),
                ),
              ),
              const SizedBox(width: 12),
              if (_profile.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _copyAll,
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(localizations.signCopyAll),
                ),
            ]),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: _profile.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(localizations.deviceHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _profile.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = _profile.entries.elementAt(i);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(
                          width: 150,
                          child: Text(e.key,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                  color: Theme.of(context).colorScheme.primary)),
                        ),
                        Expanded(
                          child: SelectableText(e.value,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
