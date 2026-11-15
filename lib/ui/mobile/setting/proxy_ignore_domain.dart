/*
 * Copyright 2026 Hongen Wang
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
import 'package:proxypin/native/vpn.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/util/system_proxy.dart';

/// 代理忽略域名独立编辑页（设计稿 tag-4：卡内嵌输入框改为 push 全屏编辑页——
/// 手机端卡内输入体验差，且与其它入口行形态统一）。
/// 失焦 / 返回时自动保存；「重置」恢复系统默认忽略列表。
class ProxyIgnoreDomainPage extends StatefulWidget {
  final Configuration configuration;

  const ProxyIgnoreDomainPage({super.key, required this.configuration});

  @override
  State<ProxyIgnoreDomainPage> createState() => _ProxyIgnoreDomainPageState();
}

class _ProxyIgnoreDomainPageState extends State<ProxyIgnoreDomainPage> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.configuration.proxyPassDomains);
    _focus.addListener(() {
      if (!_focus.hasFocus) _save(notify: true);
    });
  }

  @override
  void dispose() {
    _save();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// [notify]：只在「用户改完失焦」时提示 —— dispose 里也会调这个，
  /// 那时候页面已经要销毁，弹提示会报错，也确实没意义。
  void _save({bool notify = false}) {
    if (_controller.text == widget.configuration.proxyPassDomains) return;
    widget.configuration.proxyPassDomains = _controller.text;
    widget.configuration.flushConfig();
    // 旁路域名只在建立 VPN 时传给原生：VPN 在跑的时候改完不重启等于白改。
    if (notify && mounted && Vpn.isVpnStarted) {
      FlutterToastr.show(localizations.vpnRestartToApply, context, duration: 3);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');
    var theme = Theme.of(context);

    return Scaffold(
        appBar: AppBar(
            centerTitle: true, title: Text(localizations.proxyIgnoreDomain, style: const TextStyle(fontSize: 16))),
        body: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(isCN ? "多个使用;分割" : "Use ';' to separate multiple entries",
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              TextField(
                  focusNode: _focus,
                  controller: _controller,
                  style: const TextStyle(fontSize: 14),
                  maxLines: 10,
                  minLines: 5,
                  onTapOutside: (_) => _focus.unfocus(),
                  onSubmitted: (_) => _save(),
                  decoration:
                      const InputDecoration(contentPadding: EdgeInsets.all(10), border: OutlineInputBorder())),
              Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                      child: Text(localizations.reset),
                      onPressed: () {
                        _controller.text = SystemProxy.proxyPassDomains;
                        _save();
                      })),
            ])));
  }
}
