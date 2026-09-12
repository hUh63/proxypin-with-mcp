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
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/components/ws_traffic_server.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/path.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/component/ws_traffic_port_dialog.dart';
import 'package:proxypin/ui/configuration.dart';

/// @author wanghongen
/// 2024/1/2
class Preference extends StatefulWidget {
  final Configuration configuration;
  final AppConfiguration appConfiguration;

  const Preference(this.appConfiguration, this.configuration, {super.key});

  @override
  State<StatefulWidget> createState() => _PreferenceState();
}

class _PreferenceState extends State<Preference> {
  late Configuration configuration;
  late AppConfiguration appConfiguration;

  final memoryCleanupController = TextEditingController();
  final memoryCleanupList = [null, 512, 1024, 2048, 4096];

  /// 是否处于便携模式（上游 #285）：程序目录存在 portable / portable.txt 标记
  bool _portable = false;
  String? _portableDir;

  @override
  void initState() {
    super.initState();
    configuration = widget.configuration;
    appConfiguration = widget.appConfiguration;
    Paths.isPortable().then((value) async {
      if (!value) return;
      final dir = await Paths.homePath();
      if (mounted) {
        setState(() {
          _portable = true;
          _portableDir = dir;
        });
      }
    });
    if (!memoryCleanupList.contains(appConfiguration.memoryCleanupThreshold)) {
      memoryCleanupController.text = appConfiguration.memoryCleanupThreshold.toString();
    }
  }

  @override
  void dispose() {
    memoryCleanupController.dispose();
    super.dispose();
  }

  /// 上游 #756：切换 WebSocket 流量推送开关（整行可点，避免只能点很小的开关）
  Future<void> _toggleWsTraffic(bool value) async {
    final localizations = AppLocalizations.of(context)!;
    setState(() => configuration.wsTrafficEnabled = value);
    configuration.flushConfig();
    final ok = await ProxyServer.current?.applyWsTraffic() ?? false;
    if (value && !ok) {
      // 启动失败（多为端口被占用）：回滚开关，避免"开着但没服务"
      setState(() => configuration.wsTrafficEnabled = false);
      configuration.flushConfig();
    }
    if (!mounted) return;
    FlutterToastr.show(
        !value
            ? localizations.wsTrafficStopped
            : ok
                ? localizations.wsTrafficStarted('${configuration.wsTrafficPort}')
                : localizations.wsTrafficStartFailed('${configuration.wsTrafficPort}'),
        context);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    var titleStyle = Theme.of(context).textTheme.titleSmall;
    var subtitleStyle = TextStyle(fontSize: 12, color: Colors.grey);

    return AlertDialog(
        scrollable: true,
        title: Row(children: [
          const Icon(Icons.settings, size: 20),
          const SizedBox(width: 10),
          Text(localizations.preference, style: Theme.of(context).textTheme.titleMedium),
          const Expanded(child: Align(alignment: Alignment.topRight, child: CloseButton()))
        ]),
        content: SizedBox(
            width: 400,
            child: Column(children: [
              Row(children: [
                SizedBox(width: 100, child: Text("${localizations.language}: ", style: titleStyle)),
                DropdownButton<Locale>(
                    value: appConfiguration.language,
                    isExpanded: true,
                    onChanged: (Locale? value) => appConfiguration.language = value,
                    focusColor: Colors.transparent,
                    items: [
                      DropdownMenuItem(value: null, child: Text(localizations.followSystem)),
                      const DropdownMenuItem(value: Locale.fromSubtags(languageCode: "zh"), child: Text("简体中文")),
                      const DropdownMenuItem(
                          value: Locale.fromSubtags(languageCode: "zh", scriptCode: "Hant"), child: Text("繁體中文")),
                      const DropdownMenuItem(value: Locale.fromSubtags(languageCode: "vi"), child: Text("Tiếng Việt")),
                      const DropdownMenuItem(value: Locale.fromSubtags(languageCode: "th"), child: Text("ไทย")),
                      const DropdownMenuItem(value: Locale.fromSubtags(languageCode: "es"), child: Text("Español")),
                      const DropdownMenuItem(value: Locale.fromSubtags(languageCode: "en"), child: Text("English")),
                    ]),
              ]),
              //主题
              Row(children: [
                SizedBox(width: 100, child: Text("${localizations.theme}: ", style: titleStyle)),
                DropdownButton<ThemeMode>(
                    value: appConfiguration.themeMode,
                    onChanged: (ThemeMode? value) => appConfiguration.themeMode = value!,
                    focusColor: Colors.transparent,
                    items: [
                      DropdownMenuItem(value: ThemeMode.system, child: Text(localizations.followSystem)),
                      DropdownMenuItem(value: ThemeMode.light, child: Text(localizations.themeLight)),
                      DropdownMenuItem(value: ThemeMode.dark, child: Text(localizations.themeDark)),
                    ]),
              ]),
              Tooltip(
                  message: localizations.material3,
                  child: Row(
                    children: [
                      SizedBox(width: 100, child: Text("Material3: ", style: titleStyle)),
                      Transform.scale(
                          scale: 0.75,
                          child: Switch(
                            value: appConfiguration.useMaterial3,
                            onChanged: (bool value) => appConfiguration.useMaterial3 = value,
                          ))
                    ],
                  )),
              //主题颜色
              Row(children: [
                SizedBox(
                    width: 120,
                    child: Text("${localizations.themeColor}: ", style: titleStyle, textAlign: TextAlign.start)),
              ]),
              themeColor(context),
              const Divider(),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(localizations.minimizeToTrayTitle, style: titleStyle),
                  subtitle: Text(localizations.minimizeToTraySubtitle, style: subtitleStyle),
                  trailing: SwitchWidget(
                      scale: 0.75,
                      value: appConfiguration.minimizeToTray ?? false,
                      onChanged: (value) {
                        appConfiguration.minimizeToTray = value;
                        appConfiguration.flushConfig();
                      })),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(localizations.autoStartup, style: titleStyle),
                  //默认是否启动
                  subtitle: Text(localizations.autoStartupDescribe, style: subtitleStyle),
                  trailing: SwitchWidget(
                      scale: 0.75,
                      value: configuration.startup,
                      onChanged: (value) {
                        configuration.startup = value;
                        configuration.flushConfig();
                      })),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(localizations.clearConfirm, style: titleStyle),
                  subtitle: Text(localizations.clearConfirmSubtitle, style: subtitleStyle),
                  trailing: SwitchWidget(
                      scale: 0.75,
                      value: appConfiguration.clearConfirm,
                      onChanged: (value) {
                        appConfiguration.clearConfirm = value;
                        appConfiguration.flushConfig();
                      })),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(localizations.memoryCleanup, style: titleStyle),
                  subtitle: Text(localizations.memoryCleanupSubtitle, style: subtitleStyle),
                  trailing: memoryCleanup(context, localizations)),

              const Divider(),
              // WebSocket 实时流量推送（上游 #756）
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(localizations.wsTrafficPush, style: titleStyle),
                  subtitle: Text(
                      configuration.wsTrafficEnabled
                          ? (WsTrafficServer.instance.isRunning
                              ? localizations.wsTrafficSubtitleRunning(
                                  '${configuration.wsTrafficPort}', '${WsTrafficServer.instance.clientCount}')
                              : localizations.wsTrafficSubtitleNotRunning('${configuration.wsTrafficPort}'))
                          : localizations.wsTrafficSubtitleOff('${configuration.wsTrafficPort}'),
                      style: subtitleStyle),
                  trailing: SwitchWidget(
                      scale: 0.75,
                      value: configuration.wsTrafficEnabled,
                      onChanged: (value) => _toggleWsTraffic(value)),
                  onTap: () => _toggleWsTraffic(!configuration.wsTrafficEnabled)),
              if (configuration.wsTrafficEnabled)
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(localizations.wsTrafficHistory, style: titleStyle),
                    subtitle: Text(localizations.wsTrafficHistoryDesc, style: subtitleStyle),
                    trailing: SwitchWidget(
                        scale: 0.75,
                        value: configuration.wsTrafficHistoryEnabled,
                        onChanged: (value) {
                          setState(() => configuration.wsTrafficHistoryEnabled = value);
                          configuration.flushConfig();
                          WsTrafficServer.instance.broadcastConfig();
                        }),
                    onTap: () {
                      setState(() => configuration.wsTrafficHistoryEnabled = !configuration.wsTrafficHistoryEnabled);
                      configuration.flushConfig();
                      WsTrafficServer.instance.broadcastConfig();
                    }),
              // 上游 #756：端口此前只能改配置文件（被占用时开关无法开启），这里提供图形化修改入口
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(localizations.wsTrafficPort, style: titleStyle),
                  subtitle: Text(
                      configuration.wsTrafficEnabled
                          ? localizations.wsTrafficPortListening('${configuration.wsTrafficPort}')
                          : localizations.wsTrafficPortCurrent('${configuration.wsTrafficPort}'),
                      style: subtitleStyle),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${configuration.wsTrafficPort}',
                        style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(width: 4),
                    Icon(Icons.edit, size: 16, color: Theme.of(context).colorScheme.primary),
                  ]),
                  onTap: () async {
                    final port = await showWsTrafficPortDialog(context, currentPort: configuration.wsTrafficPort);
                    if (port == null || port == configuration.wsTrafficPort) return;
                    configuration.wsTrafficPort = port;
                    configuration.flushConfig();
                    if (configuration.wsTrafficEnabled) {
                      final ok = await ProxyServer.current?.applyWsTraffic() ?? false;
                      if (!mounted) return;
                      if (!ok) {
                        setState(() => configuration.wsTrafficEnabled = false);
                        configuration.flushConfig();
                      }
                      FlutterToastr.show(
                          ok
                              ? localizations.wsTrafficPortChangedListening('$port')
                              : localizations.wsTrafficPortChangedFailed('$port'),
                          context);
                    } else if (mounted) {
                      FlutterToastr.show(localizations.wsTrafficPortChangedPending('$port'), context);
                    }
                    if (mounted) setState(() {});
                  }),

              // 上游 #285：便携模式此前无任何界面提示，用户放了标记文件也无从确认
              if (_portable)
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.usb, size: 18, color: Theme.of(context).colorScheme.primary),
                    title: Text(localizations.portableModeEnabled, style: titleStyle),
                    subtitle: Text(localizations.portableModeDataDir('${_portableDir ?? ''}'),
                        style: subtitleStyle, maxLines: 2, overflow: TextOverflow.ellipsis)),

              SizedBox(height: 5),
            ])));
  }

  ///主题颜色
  Widget themeColor(BuildContext context) {
    return Wrap(
      children: ColorMapping.colors.entries.map((pair) {
        var dividerColor = Theme.of(context).focusColor;
        var background = appConfiguration.themeColor == pair.value ? dividerColor : Colors.transparent;

        return GestureDetector(
            onTap: () => appConfiguration.setThemeColor = pair.key,
            child: Tooltip(
              message: pair.key,
              child: Container(
                margin: const EdgeInsets.all(4.0),
                decoration: BoxDecoration(
                  color: background,
                  border: Border.all(color: Colors.transparent, width: 8),
                ),
                child: Dot(color: pair.value, size: 15),
              ),
            ));
      }).toList(),
    );
  }

  bool memoryCleanupOpened = false;

  ///内存清理
  Widget memoryCleanup(BuildContext context, AppLocalizations localizations) {
    try {
      return DropdownButton<int>(
          value: appConfiguration.memoryCleanupThreshold,
          isExpanded: true,
          onTap: () {
            memoryCleanupOpened = true;
          },
          onChanged: (val) {
            memoryCleanupOpened = false;
            setState(() {
              appConfiguration.memoryCleanupThreshold = val;
            });
            appConfiguration.flushConfig();
          },
          underline: Container(),
          items: [
            DropdownMenuItem(value: null, child: Text(localizations.unlimited)),
            const DropdownMenuItem(value: 512, child: Text("512M")),
            const DropdownMenuItem(value: 1024, child: Text("1024M")),
            const DropdownMenuItem(value: 2048, child: Text("2048M")),
            const DropdownMenuItem(value: 4096, child: Text("4096M")),
            DropdownMenuInputItem(
                controller: memoryCleanupController,
                child: Container(
                    constraints: BoxConstraints(maxWidth: 65, minWidth: 35),
                    child: TextField(
                        controller: memoryCleanupController,
                        onSubmitted: (value) {
                          setState(() {});
                          appConfiguration.memoryCleanupThreshold = int.tryParse(value);
                          appConfiguration.flushConfig();

                          if (memoryCleanupOpened) {
                            memoryCleanupOpened = false;
                            Navigator.pop(context);
                            return;
                          }
                        },
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(5),
                          FilteringTextInputFormatter.allow(RegExp("[0-9]"))
                        ],
                        decoration: InputDecoration(hintText: localizations.custom, suffixText: "M")))),
          ]);
    } catch (e) {
      appConfiguration.memoryCleanupThreshold = null;
      logger.e('memory button build error', error: e, stackTrace: StackTrace.current);
      return const SizedBox();
    }
  }
}

class DropdownMenuInputItem extends DropdownMenuItem<int> {
  final TextEditingController controller;

  @override
  int? get value => int.tryParse(controller.text) ?? 0;

  const DropdownMenuInputItem({super.key, required this.controller, required super.child});
}
