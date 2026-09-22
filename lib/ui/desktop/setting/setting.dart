/*
 * Copyright 2023 Hongen Wang All rights reserved.
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
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/components/manager/hosts_manager.dart';
import 'package:proxypin/network/components/manager/network_condition_manager.dart';
import 'package:proxypin/network/components/manager/request_block_manager.dart';
import 'package:proxypin/network/util/system_proxy.dart';
import 'package:proxypin/ui/component/capture_body_limit.dart';
import 'package:proxypin/ui/component/multi_window.dart';
import 'package:proxypin/ui/component/proxy_port_setting.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/desktop/setting/about.dart';
import 'package:proxypin/ui/desktop/setting/backup_management.dart';
import 'package:proxypin/ui/desktop/setting/config_management.dart';
import 'package:proxypin/ui/desktop/setting/external_proxy.dart';
import 'package:proxypin/ui/desktop/setting/hosts.dart';
import 'package:proxypin/ui/desktop/setting/mcp_connection.dart';
import 'package:proxypin/ui/desktop/setting/request_block.dart';
import 'package:proxypin/ui/desktop/setting/theme.dart';
import 'package:proxypin/ui/desktop/setting/weak_network.dart';
import 'package:proxypin/ui/desktop/toolbar/mcp_panel.dart';

import 'filter.dart';

///设置菜单
/// @author wanghongen
/// 2023/10/8
class Setting extends StatefulWidget {
  final ProxyServer proxyServer;

  const Setting({super.key, required this.proxyServer});

  @override
  State<Setting> createState() => _SettingState();
}

class _SettingState extends State<Setting> {
  late Configuration configuration;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    configuration = widget.proxyServer.configuration;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, child) {
        return IconButton(
            icon: const Icon(Icons.settings, size: 21),
            tooltip: localizations.setting,
            onPressed: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            });
      },
      menuChildren: [
        _ProxyMenu(proxyServer: widget.proxyServer),
        item(localizations.domainFilter, onPressed: hostFilter),
        item(localizations.hosts, onPressed: hosts),
        item(localizations.requestBlock, onPressed: showRequestBlock),
        item(localizations.requestRewrite, onPressed: requestRewrite),
        item(localizations.requestMap, onPressed: requestMap),
        item(localizations.requestCrypto, onPressed: showRequestCrypto),
        item(localizations.script,
            onPressed: () => MultiWindow.openWindow(localizations.script, 'ScriptWidget', size: const Size(800, 780))),
        item(localizations.breakpoint, onPressed: requestBreakpoint),
        item(localizations.weakNetwork, onPressed: showWeakNetwork),
        item(localizations.externalProxy, onPressed: setExternalProxy),
        item('抓包内容上限',
            onPressed: () => showCaptureBodyLimitDialog(context, widget.proxyServer.configuration),
            leadingIcon: Icons.data_usage),
        const Divider(),
        item('MCP 连接', onPressed: showMcpConnection, leadingIcon: Icons.cloud),
        item('MCP 自动化', onPressed: showMcpAutomation, leadingIcon: Icons.auto_awesome),
        item('配置管理', onPressed: showConfigManagement, leadingIcon: Icons.settings_suggest),
        item('备份管理', onPressed: showBackupManagement, leadingIcon: Icons.backup),
        item('主题设置', onPressed: showThemeSetting, leadingIcon: Icons.palette),
        const Divider(),
        item(localizations.about, onPressed: showAbout, leadingIcon: Icons.info),
        item(localizations.mcpService, onPressed: () => McpServiceDialog.show(context, widget.proxyServer)),
        item(localizations.about, onPressed: showAbout),
      ],
    );
  }

  Widget item(String text, {VoidCallback? onPressed, IconData? leadingIcon}) {
    return MenuItemButton(
        leadingIcon: leadingIcon != null ? Icon(leadingIcon, size: 18) : null,
        trailingIcon: const Icon(Icons.arrow_right),
        onPressed: onPressed,
        child: Padding(
            padding: const EdgeInsets.only(left: 10, right: 5),
            child: Text(text, style: const TextStyle(fontSize: 14))));
  }

  void showAbout() {
    showDialog(context: context, builder: (context) => DesktopAbout());
  }

  /// 显示 MCP 连接设置
  void showMcpConnection() {
    showDialog(
        barrierDismissible: false,
        context: context,
        builder: (context) {
          return Dialog(
            child: SizedBox(
              width: 800,
              height: 700,
              child: DesktopMcpConnection(configuration: configuration),
            ),
          );
        });
  }

  /// 显示 MCP 自动化设置
  void showMcpAutomation() {
    MultiWindow.openWindow('MCP 自动化', 'McpAutomationWidget', size: const Size(900, 700));
  }

  /// 显示备份管理
  void showBackupManagement() {
    showDialog(
        barrierDismissible: false,
        context: context,
        builder: (context) {
          return Dialog(
            child: SizedBox(
              width: 700,
              height: 600,
              child: DesktopBackupManagement(configuration: configuration),
            ),
          );
        });
  }

  /// 显示配置管理
  void showConfigManagement() {
    showDialog(
        barrierDismissible: false,
        context: context,
        builder: (context) {
          return Dialog(
            child: SizedBox(
              width: 700,
              height: 600,
              child: DesktopConfigManagement(proxyServer: widget.proxyServer),
            ),
          );
        });
  }

  /// 显示主题设置（在顶部工具栏已有独立入口）
  void showThemeSetting() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('主题设置在顶部工具栏，点击太阳/月亮图标即可切换')),
    );
  }

  ///设置外部代理地址
  void setExternalProxy() {
    showDialog(
        barrierDismissible: false,
        context: context,
        builder: (context) {
          return ExternalProxyDialog(configuration: widget.proxyServer.configuration);
        });
  }

  ///请求重写Dialog
  void requestRewrite() async {
    MultiWindow.openWindow(localizations.requestRewrite, 'RequestRewriteWidget', size: const Size(800, 750));
  }

  void requestBreakpoint() async {
    MultiWindow.openWindow(localizations.breakpoint, 'RequestBreakpointPage', size: const Size(800, 750));
  }

  ///请求本地映射
  void requestMap() async {
    if (!mounted) return;
    MultiWindow.openWindow(localizations.requestMap, 'RequestMapPage', size: const Size(800, 720));
  }

  ///show域名过滤Dialog
  void hostFilter() {
    showDialog(
        barrierDismissible: false, context: context, builder: (context) => FilterDialog(configuration: configuration));
  }

  ///show域名过滤Dialog
  void hosts() async {
    var hosts = await HostsManager.instance;
    if (!mounted) return;
    showDialog(barrierDismissible: false, context: context, builder: (context) => HostsDialog(hostsManager: hosts));
  }

  //请求屏蔽
  void showRequestBlock() async {
    var requestBlockManager = await RequestBlockManager.instance;
    if (!mounted) return;
    showDialog(
        barrierDismissible: false,
        context: context,
        builder: (context) => RequestBlock(requestBlockManager: requestBlockManager));
  }

  void showRequestCrypto() {
    MultiWindow.openWindow(localizations.requestCrypto, 'RequestCryptoPage', size: const Size(820, 750));
  }

  void showWeakNetwork() async {
    var manager = await NetworkConditionManager.instance;
    if (!mounted) return;
    showDialog(
        barrierDismissible: false,
        context: context,
        builder: (context) => WeakNetworkDialog(manager: manager));
  }
}

///代理菜单
class _ProxyMenu extends StatefulWidget {
  final ProxyServer proxyServer;

  const _ProxyMenu({required this.proxyServer});

  @override
  State<StatefulWidget> createState() => _ProxyMenuState();
}

class _ProxyMenuState extends State<_ProxyMenu> {
  var textEditingController = TextEditingController();

  late Configuration configuration;
  bool changed = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    configuration = widget.proxyServer.configuration;
    textEditingController.text = configuration.proxyPassDomains;
    super.initState();
  }

  @override
  void dispose() {
    if (configuration.proxyPassDomains != textEditingController.text) {
      changed = true;
      configuration.proxyPassDomains = textEditingController.text;
      SystemProxy.setProxyPassDomains(configuration.proxyPassDomains);
    }

    if (changed) {
      configuration.flushConfig();
    }
    textEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isEn = localizations.localeName.startsWith("en");
    return SubmenuButton(
      menuChildren: [
        PortWidget(proxyServer: widget.proxyServer, textStyle: const TextStyle(fontSize: 13)),
        const Divider(thickness: 0.3, height: 8),
        setSystemProxy(),
        resetSystemProxy(),
        const Divider(thickness: 0.3, height: 8),
        Row(children: [
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.only(left: 15),
                  child: Text("SOCKS5", style: const TextStyle(fontSize: 14)))),
          SwitchWidget(
              value: configuration.enableSocks5,
              scale: 0.75,
              onChanged: (val) {
                configuration.enableSocks5 = val;
                changed = true;
              }),
          SizedBox(width: 10)
        ]),
        const Divider(thickness: 0.3, height: 8),
        Row(children: [
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.only(left: 15),
                  child: Text(localizations.enabledHTTP2, style: const TextStyle(fontSize: 14)))),
          SwitchWidget(
              value: configuration.enabledHttp2,
              scale: 0.75,
              onChanged: (val) {
                configuration.enabledHttp2 = val;
                changed = true;
              }),
          SizedBox(width: 10)
        ]),
        const Divider(thickness: 0.3, height: 8),
        const SizedBox(height: 3),
        Padding(
            padding: const EdgeInsets.only(left: 15),
            child: Row(children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(localizations.proxyIgnoreDomain, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(isEn ? "Use ';' to separate multiple entries": "多个使用;分割", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
              Padding(
                  padding: const EdgeInsets.only(left: 35),
                  child: TextButton(
                    child: Text(localizations.reset),
                    onPressed: () {
                      textEditingController.text = SystemProxy.proxyPassDomains;
                    },
                  ))
            ])),
        const SizedBox(height: 5),
        Padding(
            padding: const EdgeInsets.only(left: 15, right: 5),
            child: TextField(
                textInputAction: TextInputAction.done,
                style: const TextStyle(fontSize: 13),
                controller: textEditingController,
                decoration: const InputDecoration(
                    contentPadding: EdgeInsets.all(10),
                    border: OutlineInputBorder(),
                    constraints: BoxConstraints(minWidth: 190, maxWidth: 190)),
                maxLines: 5,
                minLines: 1)),
        const SizedBox(height: 10),
      ],
      child: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Text(localizations.proxy, style: const TextStyle(fontSize: 14))),
    );
  }

  ///设置系统代理
  Widget setSystemProxy() {
    return Row(children: [
      Expanded(
          child: Padding(
              padding: const EdgeInsets.only(left: 15, right: 20),
              child: Text(localizations.setAs + localizations.systemProxy, style: const TextStyle(fontSize: 14)))),
      Transform.scale(
          scale: 0.75,
          child: Switch(
              hoverColor: Colors.transparent,
              value: configuration.enableSystemProxy,
              onChanged: (val) {
                widget.proxyServer.setSystemProxyEnable(val);
                configuration.enableSystemProxy = val;
                setState(() {
                  changed = true;
                });
              })),
      SizedBox(width: 10)
    ]);
  }

  /// 网络救援：清除系统代理残留（上游 #886）
  ///
  /// 异常退出/强杀后系统代理可能仍指向已经不存在的本地端口，导致整机断网；
  /// 这里一键把系统代理设置清干净。
  Widget resetSystemProxy() {
    return Row(children: [
      Expanded(
          child: Padding(
              padding: const EdgeInsets.only(left: 15, right: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('清除系统代理残留', style: const TextStyle(fontSize: 14)),
                Text('异常退出后网络打不开时点这里恢复',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
              ]))),
      OutlinedButton.icon(
        onPressed: () async {
          await SystemProxy.resetSystemProxy();
          if (mounted) {
            FlutterToastr.show('已清除系统代理设置，网络应恢复正常', context, duration: 3);
          }
        },
        icon: const Icon(Icons.build_outlined, size: 16),
        label: const Text('修复'),
      ),
      const SizedBox(width: 10),
    ]);
  }
}
