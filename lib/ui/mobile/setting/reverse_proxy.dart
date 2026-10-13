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
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/reverse/reverse_proxy.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/network/reverse/reverse_proxy_server.dart';

/// 反向代理设置页：按路径把请求转发到不同上游。
///
/// 与正向代理的区别是「目标由谁决定」——正代由客户端指定，反代由路径规则决定。
/// 转发复用同一条处理链，因此反代进来的流量照样出现在抓包列表里。
class ReverseProxySetting extends StatefulWidget {
  final Configuration configuration;

  const ReverseProxySetting({super.key, required this.configuration});

  @override
  State<ReverseProxySetting> createState() => _ReverseProxySettingState();
}

class _ReverseProxySettingState extends State<ReverseProxySetting> {
  Configuration get conf => widget.configuration;

  AppLocalizations get loc => AppLocalizations.of(context)!;
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _subColor => Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey;

  void _persist() {
    conf.flushConfig();
    ReverseProxy.load(enabled: conf.reverseProxyEnabled, port: conf.reverseProxyPort, rules: conf.reverseProxyRules);
  }

  /// 保存后同步到运行中的服务。
  void _applyAndNotify() {
    _persist();
    // 让运行状态与配置保持一致（开启且有规则就重启，否则停掉）
    ReverseProxyServer.apply(conf);
  }

  Future<void> _toggleEnabled(bool value) async {
    setState(() => conf.reverseProxyEnabled = value);
    _applyAndNotify();
  }

  Future<void> _editPort() async {
    final controller = TextEditingController(text: conf.reverseProxyPort.toString());
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.reverseProxyPort),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(hintText: '8888', border: const OutlineInputBorder(), isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(loc.cancel)),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text.trim());
              if (n == null || n < 1 || n > 65535) {
                FlutterToastr.show(loc.mcpPortInvalid, ctx, position: FlutterToastr.center);
                return;
              }
              if (n == conf.port) {
                FlutterToastr.show(loc.reverseProxyPortConflict, ctx, position: FlutterToastr.center);
                return;
              }
              Navigator.pop(ctx, n);
            },
            child: Text(loc.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) {
      setState(() => conf.reverseProxyPort = value);
      _applyAndNotify();
    }
  }

  Future<void> _showRuleDialog([ReverseProxyRule? rule]) async {
    final prefixCtrl = TextEditingController(text: rule?.prefix ?? '/');
    final targetCtrl = TextEditingController(text: rule?.target ?? 'http://127.0.0.1:3000');
    final hostCtrl = TextEditingController(text: rule?.hostHeader ?? '');
    var stripPrefix = rule?.stripPrefix ?? false;
    var enabled = rule?.enabled ?? true;
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(rule == null ? loc.reverseProxyAdd : loc.reverseProxyEdit),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: prefixCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: loc.reverseProxyPrefix,
                    hintText: '/api',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return loc.cannotBeEmpty;
                    if (!s.startsWith('/')) return loc.reverseProxyPrefixInvalid;
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: targetCtrl,
                  decoration: InputDecoration(
                    labelText: loc.reverseProxyTarget,
                    hintText: 'http://127.0.0.1:3000',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return loc.reverseProxyNeedTarget;
                    final uri = Uri.tryParse(s);
                    if (uri == null || uri.host.isEmpty) return loc.reverseProxyTargetInvalid;
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: hostCtrl,
                  decoration: InputDecoration(
                    labelText: loc.reverseProxyHostHeader,
                    hintText: loc.reverseProxyHostHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(loc.reverseProxyStripPrefix, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(loc.reverseProxyStripPrefixDesc, style: const TextStyle(fontSize: 11)),
                  value: stripPrefix,
                  onChanged: (v) => setDialogState(() => stripPrefix = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(loc.enable, style: const TextStyle(fontSize: 14)),
                  value: enabled,
                  onChanged: (v) => setDialogState(() => enabled = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(ctx, true);
              },
              child: Text(loc.save),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      final hostText = hostCtrl.text.trim();
      setState(() {
        final list = List<ReverseProxyRule>.from(conf.reverseProxyRules);
        if (rule == null) {
          list.add(ReverseProxyRule(
            id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
            prefix: ReverseProxyRule.normalizePrefix(prefixCtrl.text),
            target: targetCtrl.text.trim(),
            stripPrefix: stripPrefix,
            hostHeader: hostText.isEmpty ? null : hostText,
            enabled: enabled,
          ));
        } else {
          final idx = list.indexOf(rule);
          if (idx >= 0) {
            list[idx] = rule.copyWith(
              prefix: ReverseProxyRule.normalizePrefix(prefixCtrl.text),
              target: targetCtrl.text.trim(),
              stripPrefix: stripPrefix,
              hostHeader: hostText,
              clearHostHeader: hostText.isEmpty,
              enabled: enabled,
            );
          }
        }
        conf.reverseProxyRules = list;
      });
      _applyAndNotify();
    }
    prefixCtrl.dispose();
    targetCtrl.dispose();
    hostCtrl.dispose();
  }

  Future<void> _remove(ReverseProxyRule rule) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.delete),
        content: Text('${rule.prefix} → ${rule.target}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(loc.delete)),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        conf.reverseProxyRules = List<ReverseProxyRule>.from(conf.reverseProxyRules)..remove(rule);
      });
      _applyAndNotify();
    }
  }

  void _toggleRule(ReverseProxyRule rule, bool value) {
    setState(() {
      final list = List<ReverseProxyRule>.from(conf.reverseProxyRules);
      final idx = list.indexOf(rule);
      if (idx >= 0) list[idx] = rule.copyWith(enabled: value);
      conf.reverseProxyRules = list;
    });
    _applyAndNotify();
  }

  @override
  Widget build(BuildContext context) {
    final rules = conf.reverseProxyRules;
    final dividerColor = _isDark ? Colors.white12 : Colors.black12;
    final running = ReverseProxyServer.current?.isRunning ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.reverseProxy),
        actions: [
          IconButton(
            tooltip: loc.reset,
            icon: const Icon(Icons.restart_alt, size: 20),
            onPressed: () => setState(() => ReverseProxy.resetHits()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRuleDialog(),
        icon: const Icon(Icons.add),
        label: Text(loc.reverseProxyAdd),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.swap_calls, color: Colors.deepOrange),
            title: Text(loc.reverseProxyEnabled),
            subtitle: Text(loc.reverseProxyDesc, style: TextStyle(fontSize: 12, color: _subColor)),
            value: conf.reverseProxyEnabled,
            onChanged: _toggleEnabled,
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.settings_ethernet, size: 20),
            title: Text(loc.reverseProxyPort),
            subtitle: Text('${conf.reverseProxyPort}',
                style: TextStyle(fontSize: 12, color: _subColor)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (conf.reverseProxyEnabled)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(running ? loc.reverseProxyRunning : loc.reverseProxyStopped,
                      style: TextStyle(
                          fontSize: 11, color: running ? Colors.green : Colors.orange)),
                ),
              const Icon(Icons.arrow_forward_ios, size: 14),
            ]),
            onTap: _editPort,
          ),
          Divider(height: 0, thickness: 0.3, color: dividerColor),
          if (rules.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
              child: Column(children: [
                Icon(Icons.swap_calls, size: 40, color: _subColor),
                const SizedBox(height: 12),
                Text(loc.reverseProxyEmpty,
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: _subColor)),
                const SizedBox(height: 8),
                Text(loc.reverseProxyHint,
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: _subColor)),
              ]),
            ),
          ...rules.map((rule) {
            final hits = ReverseProxy.hitsOf(rule);
            return ListTile(
              dense: true,
              leading: Icon(Icons.alt_route,
                  color: rule.enabled ? Colors.deepOrange : _subColor, size: 20),
              title: Text(rule.prefix, style: const TextStyle(fontSize: 13.5)),
              subtitle: Text(
                hits > 0 ? '${rule.target}  ·  ${loc.reverseProxyHit} ×$hits' : rule.target,
                style: const TextStyle(fontSize: 11.5),
              ),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                SwitchWidget(value: rule.enabled, scale: 0.7, onChanged: (v) => _toggleRule(rule, v)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: loc.edit,
                  onPressed: () => _showRuleDialog(rule),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: loc.delete,
                  onPressed: () => _remove(rule),
                ),
              ]),
              onTap: () => _showRuleDialog(rule),
            );
          }),
        ],
      ),
    );
  }
}
