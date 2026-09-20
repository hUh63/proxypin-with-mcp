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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/event/event_bus.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/native/app_lifecycle.dart';
import 'package:proxypin/native/pip.dart';
import 'package:proxypin/native/vpn.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/network/mcp/mcp_bridge.dart';
import 'package:proxypin/network/mcp/mcp_server.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/histories.dart';
import 'package:proxypin/ui/component/app_dialog.dart';
import 'package:proxypin/ui/component/memory_cleanup.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/toolbox/toolbox.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/content/panel.dart';
import 'package:proxypin/ui/launch/launch.dart';
import 'package:proxypin/ui/mobile/menu/drawer.dart';
import 'package:proxypin/ui/mobile/menu/bottom_navigation.dart';
import 'package:proxypin/ui/mobile/menu/menu.dart';
import 'package:proxypin/ui/mobile/request/history.dart';
import 'package:proxypin/ui/mobile/request/list.dart';
import 'package:proxypin/ui/mobile/request/search.dart';
import 'package:proxypin/ui/mobile/widgets/pip.dart';
import 'package:proxypin/ui/mobile/widgets/remote_device.dart';
import 'package:proxypin/utils/ip.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/listenable_list.dart';
import 'package:proxypin/utils/navigator.dart';

import '../app_update/app_update_repository.dart';
import 'package:proxypin/ui/component/multi_window.dart';
import 'package:proxypin/ui/mobile/debug/breakpoint_executor.dart';

///移动端首页
///@author wanghongen
class MobileHomePage extends StatefulWidget {
  final Configuration configuration;
  final AppConfiguration appConfiguration;

  const MobileHomePage(this.configuration, this.appConfiguration, {super.key});

  @override
  State<StatefulWidget> createState() {
    return MobileHomeState();
  }
}

class MobileApp {
  ///请求列表key
  static final GlobalKey<RequestListState> requestStateKey = GlobalKey<RequestListState>();

  ///搜索key
  static final GlobalKey<MobileSearchState> searchStateKey = GlobalKey<MobileSearchState>();

  ///请求列表容器
  static final container = ListenableList<HttpRequest>();

  static final multiSelectController = MultiSelectController();
}

class MobileHomeState extends State<MobileHomePage> implements EventListener, LifecycleListener {
  /// 选择索引
  final ValueNotifier<int> _selectIndex = ValueNotifier(0);

  StreamSubscription<HistoryItem>? _remoteHistorySubscription;
  Subscription? _eventBusSubscription;

  late ProxyServer proxyServer;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void onRequest(Channel channel, HttpRequest request) {
    MobileApp.requestStateKey.currentState!.add(channel, request);
    PictureInPicture.addData(request.requestUrl);

    //监控内存 到达阈值清理
    MemoryCleanupMonitor.onMonitor(onCleanup: () {
      MobileApp.requestStateKey.currentState?.cleanupEarlyData(32);
    });
  }

  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) {
    MobileApp.requestStateKey.currentState!.addResponse(channelContext, response);
    // 上游 #922：响应在详情页打开期间才到达时立即刷新，避免详情页停留在"未响应"
    final panel = NetworkTabController.current;
    final request = response.request;
    if (panel != null && request != null && panel.request.get()?.requestId == request.requestId) {
      panel.change(request, response);
    }
  }

  @override
  void onMessage(Channel channel, HttpMessage message, WebSocketFrame frame) {
    var panel = NetworkTabController.current;
    if (panel?.request.get() == message || panel?.response.get() == message) {
      panel?.changeState();
    }
  }

  @override
  void initState() {
    super.initState();

    AppLifecycleBinding.instance.addListener(this);
    proxyServer = ProxyServer(widget.configuration);
    proxyServer.addListener(this);
    proxyServer.start();

    // 预热本机地址：返回桌面进入小窗的窗口期很短，别把网卡枚举留在那一刻（上游 #812）
    if (Platform.isAndroid) {
      unawaited(localIp().catchError((_) => '127.0.0.1'));
    }

    _remoteHistorySubscription = HistoryStorage.onRemoteImported.listen((item) => _openHistoryPage(item));

    // 订阅 MCP 通知与抓包控制事件（规则引擎/自动化任务发布）
    _eventBusSubscription = EventBus().subscribe(handler: (event) {
      if (event.type == 'notification') {
        if (!mounted) return;
        final title = event.data['title']?.toString() ?? 'ProxyPin';
        final message = event.data['message']?.toString() ?? '';
        CustomToast('$title：$message').show(context);
      } else if (event.type == 'mcp_capture_control') {
        final action = event.data['action']?.toString();
        if (action == 'stop') {
          unawaited(proxyServer.stop());
        } else if (action == 'start') {
          unawaited(proxyServer.start());
        }
      }
    });

    // MCP 初始化
    McpBridge().setRequestContainer(MobileApp.container);
    McpBridge().onClearUI = () {
      MobileApp.requestStateKey.currentState?.clean();
    };
    proxyServer.addListener(McpBridge());
    // MCP 服务：默认启用且自动启动，应用启动即运行（可在 MCP 设置页关闭）
    if (widget.configuration.mcpEnabled && widget.configuration.mcpAutoStart) {
      McpServer().start();
    }

    if (widget.appConfiguration.upgradeNoticeV30) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showUpgradeNotice();
      });
    } else if (Platform.isAndroid) {
      AppUpdateRepository.checkUpdate(context);
    }

    // Handle breakpoint window on mobile
    MultiWindow.onOpenWindow = (widgetName, args) async {
      if (widgetName == 'BreakpointExecutor' && args != null) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BreakpointExecutor(
              requestId: args['requestId'],
              request: HttpRequest.fromJson(jsonDecode(jsonEncode(args['request']))),
              response:
                  args['response'] == null ? null : HttpResponse.fromJson(jsonDecode(jsonEncode(args['response']))),
              isResponse: args['type'] == 'response',
            ),
          ),
        );
      }
    };
  }

  @override
  void dispose() {
    AppLifecycleBinding.instance.removeListener(this);
    _remoteHistorySubscription?.cancel();
    final eventSub = _eventBusSubscription;
    if (eventSub != null) EventBus().unsubscribe(eventSub);
    McpServer().stop(persistState: false);
    super.dispose();
  }

  void toRequestsView(HistoryItem item, HistoryStorage storage) {}

  void _openHistoryPage(HistoryItem item) {
    _selectIndex.value = 2;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      Navigator.of(context)
          .push(MaterialPageRoute(
              builder: (BuildContext context) => HistoryRecord(history: item, proxyServer: proxyServer)))
          .then((value) async {
        Future.delayed(const Duration(seconds: 60), () => item.requests = null);
      });
    });
  }

  int exitTime = 0;

  var requestPageNavigatorKey = GlobalKey<NavigatorState>();
  var toolboxNavigatorKey = GlobalKey<NavigatorState>();
  var configNavigatorKey = GlobalKey<NavigatorState>();
  var settingNavigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    var navigationView = [
      NavigatorPage(
          navigatorKey: requestPageNavigatorKey,
          child: RequestPage(proxyServer: proxyServer, appConfiguration: widget.appConfiguration)),
      NavigatorPage(
          navigatorKey: toolboxNavigatorKey,
          child: Scaffold(
              appBar: PreferredSize(
                  preferredSize: const Size.fromHeight(42),
                  child: AppBar(
                      title: Text(localizations.toolbox,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
                      centerTitle: true)),
              body: Toolbox(proxyServer: proxyServer, requestContainer: MobileApp.container))),
      NavigatorPage(navigatorKey: configNavigatorKey, child: ConfigPage(proxyServer: proxyServer)),
      NavigatorPage(
          navigatorKey: settingNavigatorKey,
          child: SettingPage(proxyServer: proxyServer, appConfiguration: widget.appConfiguration)),
    ];

    if (!widget.appConfiguration.bottomNavigation) _selectIndex.value = 0;

    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) {
            return;
          }

          if (navigationView[_selectIndex.value].onPopInvoked()) {
            return;
          }

          if (await enterPictureInPicture()) {
            return;
          }

          if (DateTime.now().millisecondsSinceEpoch - exitTime > 1500) {
            exitTime = DateTime.now().millisecondsSinceEpoch;
            if (mounted) {
              FlutterToastr.show(localizations.appExitTips, this.context,
                  rootNavigator: true, duration: FlutterToastr.lengthLong);
            }
            return;
          }
          //退出程序
          SystemNavigator.pop();
        },
        child: ValueListenableBuilder<int>(
            valueListenable: _selectIndex,
            builder: (context, index, child) => Scaffold(
                body: IndexedStack(index: index, children: navigationView),
                bottomNavigationBar: widget.appConfiguration.bottomNavigation
                    ? Container(
                        constraints: const BoxConstraints(maxHeight: 85),
                        // padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                        child: ClipRRect(
                            // borderRadius: BorderRadius.circular(16),
                            child: Theme(
                          data: Theme.of(context).copyWith(splashColor: Colors.transparent),
                          child: BottomNavigationBar(
                            type: BottomNavigationBarType.fixed,
                            iconSize: 23,
                            showSelectedLabels: false,
                            showUnselectedLabels: false,
                            selectedFontSize: 2,
                            unselectedFontSize: 2,
                            elevation: 0,
                            items: [
                              BottomNavigationBarItem(
                                  tooltip: localizations.requests,
                                  icon: const Icon(Icons.workspaces_outlined),
                                  label: localizations.requests),
                              BottomNavigationBarItem(
                                  tooltip: localizations.toolbox,
                                  icon: const Icon(Icons.hardware_outlined),
                                  label: localizations.toolbox),
                              BottomNavigationBarItem(
                                  tooltip: localizations.config,
                                  icon: const Icon(Icons.description_outlined),
                                  label: localizations.config),
                              BottomNavigationBarItem(
                                  tooltip: localizations.setting,
                                  icon: const Icon(Icons.settings_outlined),
                                  label: localizations.setting),
                            ],
                            currentIndex: _selectIndex.value,
                            onTap: (index) => _selectIndex.value = index,
                          ),
                        )))
                    : null)));
  }

  @override
  void onUserLeaveHint() {
    // 返回值无意义（失败时系统会保持原样），但不能让 Future 变成 unhandled error
    unawaited(enterPictureInPicture());
  }

  /// 进入小窗（画中画）。
  ///
  /// 这个函数处在 `onUserLeaveHint` 与返回键两条"用户手势"路径上，调用系统 API 的窗口很短，
  /// 所以这里刻意只用**同步**数据源（`AppConfiguration.current` 与启动时缓存的代理地址），
  /// 不再 `await` 配置读取 / 网卡枚举——那些 await 排在系统 API 之前时，
  /// 冷启动首次离开应用会因为错过窗口期而"返回桌面却没有小窗"（上游 #812 / #703）。
  ///
  /// 另外整个过程包了 try/catch：早期版本一旦抛出（例如原生 channels 异常），
  /// 调用方（返回键处理）会直接中断，既不进小窗、也不提示"再按一次退出"（上游 #812）。
  Future<bool> enterPictureInPicture() async {
    try {
      if (!Vpn.isVpnStarted || !Platform.isAndroid) {
        return false;
      }

      if (AppConfiguration.current?.pipEnabled.value != true) {
        return false;
      }

      // 优先用启动时缓存的地址（同步，零等待）；缓存缺失时（例如应用重启而 VPN 仍由
      // 系统保留、启动回调没再走过）回退到异步取本机地址，保证行为不退化。
      final host = PictureInPicture.proxyHost ?? await localIp();
      final port = PictureInPicture.proxyPort ?? proxyServer.port;

      List<String> appList =
          proxyServer.configuration.appWhitelistEnabled ? proxyServer.configuration.appWhitelist : [];
      List<String>? disallowApps;
      if (appList.isEmpty) {
        disallowApps = proxyServer.configuration.appBlacklist ?? [];
      }

      return PictureInPicture.enterPictureInPictureMode(host, port, appList: appList, disallowApps: disallowApps);
    } catch (e, t) {
      logger.e('enter picture in picture failed', error: e, stackTrace: t);
      return false;
    }
  }

  /// 当前正在显示的画中画窗口路由。
  ///
  /// 用**引用**精确移除，而不是 `maybePop`：小窗期间用户可能在上面又打开了断点页 / 详情页，
  /// `maybePop` 只会弹掉栈顶那一个，小窗路由就永久留在栈里——之后全屏看到的是这张
  /// 空白的请求列表页，返回键行为也跟着错乱（上游 #724：断点用几次后卡在白页）。
  /// 两个标志位同时保证重复回调不会 push 出多个小窗路由。
  Route<void>? _pipWindowRoute;

  @override
  onPictureInPictureModeChanged(bool isInPictureInPictureMode) async {
    if (!mounted) {
      return;
    }

    if (isInPictureInPictureMode) {
      if (_pipWindowRoute != null) {
        return;
      }

      final route = PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) {
            return PictureInPictureWindow(MobileApp.container,
                searchModel: MobileApp.requestStateKey.currentState?.currentSearchModel);
          });
      _pipWindowRoute = route;
      unawaited(Navigator.of(context).push(route));
      return;
    }

    final route = _pipWindowRoute;
    _pipWindowRoute = null;
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }

    Vpn.isRunning().then((value) {
      Vpn.isVpnStarted = value;
      SocketLaunch.startStatus.value = ValueWrap.of(value);
    });
  }

  void showUpgradeNotice() {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    String content = isCN
        ? '提示：默认不会开启HTTPS抓包，请安装证书后再开启HTTPS抓包。\n\n'
            '1. 新增弱网模拟功能，支持自定义延迟、丢包、带宽限制等网络条件；\n'
            '2. 新增环境变量高亮，URL 和 Headers 支持环境变量渲染与颜色区分；\n'
            '3. 新增 GraphQL 操作名称识别与展示；\n'
            '4. 新增请求重写规则检测，Body 视图中标识匹配的重写规则；\n'
            '5. 增强 HTTP/2：实现大体积 Body 流式传输，优化 Header 编解码，新增分块传输解码与统一 Body 读取逻辑；\n'
            '6. 增强 cURL 生成：改进 multipart/form-data 和二进制 Body 的导出；\n'
            '7. 修复：Android VPN 网络切换导致抓包中断、WebSocket 多帧合并丢失、Socket 连接异常关闭、裸域名请求 URI 为空等问题。\n'
        : 'Note: HTTPS capture is disabled by default — please install the certificate before enabling HTTPS capture.\n\n'
            '1. Added weak network simulation with customizable latency, packet loss, and bandwidth throttling;\n'
            '2. Added environment variable highlighting with color-coded variable rendering in URLs and headers;\n'
            '3. Added GraphQL operation name recognition and display;\n'
            '4. Added request rewrite rule detection with rule matching indicators in the Body view;\n'
            '5. Enhanced HTTP/2: streaming for large bodies, improved header handling, chunked transfer decoding and unified body reading;\n'
            '6. Enhanced cURL generation: better multipart/form-data and binary body export;\n'
            '7. Fixed: Android VPN capture interruption on network switch, WebSocket frame merging loss, socket hang-up, empty URI for bare domains, and more.\n';
    showAlertDialog(isCN ? '更新内容V${AppConfiguration.version}' : "What's new in V${AppConfiguration.version}", content,
        () {
      widget.appConfiguration.upgradeNoticeV30 = false;
      widget.appConfiguration.flushConfig();
    });
  }

  void showAlertDialog(String title, String content, Function onClose) {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
              scrollable: true,
              actions: [
                TextButton(
                    onPressed: () {
                      onClose.call();
                      Navigator.pop(context);
                    },
                    child: Text(localizations.close))
              ],
              title: Text(title, style: const TextStyle(fontSize: 18)),
              content: SelectableText(content));
        });
  }
}

class RequestPage extends StatefulWidget {
  final ProxyServer proxyServer;
  final AppConfiguration appConfiguration;

  const RequestPage({super.key, required this.proxyServer, required this.appConfiguration});

  @override
  State<RequestPage> createState() => RequestPageState();
}

class RequestPageState extends State<RequestPage> {
  /// 远程连接
  final ValueNotifier<RemoteModel> remoteDevice = ValueNotifier(RemoteModel(connect: false));

  late ProxyServer proxyServer;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    proxyServer = widget.proxyServer;

    //远程连接
    remoteDevice.addListener(() {
      if (remoteDevice.value.connect) {
        proxyServer.configuration.remoteHost = "http://${remoteDevice.value.host}:${remoteDevice.value.port}";
        checkConnectTask(context);
      } else {
        proxyServer.configuration.remoteHost = null;
      }
    });
  }

  @override
  void dispose() {
    remoteDevice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Scaffold(
        appBar: _MobileAppBar(widget.appConfiguration, proxyServer, remoteDevice: remoteDevice),
        drawer: widget.appConfiguration.bottomNavigation
            ? null
            : DrawerWidget(proxyServer: proxyServer, container: MobileApp.container),
        floatingActionButton: _launchActionButton(),
        body: ValueListenableBuilder(
            valueListenable: remoteDevice,
            builder: (context, value, _) {
              return Column(children: [
                value.connect ? remoteConnect(value) : const SizedBox(),
                Expanded(
                    child: RequestListWidget(
                        key: MobileApp.requestStateKey,
                        proxyServer: proxyServer,
                        list: MobileApp.container,
                        selectionController: MobileApp.multiSelectController))
              ]);
            }),
      ),
      PictureInPictureIcon(proxyServer),
    ]);
  }

  Widget _launchActionButton() {
    var theme = Theme.of(context);
    return Theme(
        data: ThemeData.from(colorScheme: theme.colorScheme, textTheme: theme.textTheme, useMaterial3: true),
        child: FloatingActionButton(
          onPressed: null,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: SocketLaunch(
              proxyServer: proxyServer,
              size: 36,
              startup: proxyServer.configuration.startup,
              serverLaunch: false,
              onStart: () async {
                String host = Platform.isAndroid ? await localIp(readCache: false) : "127.0.0.1";
                int port = proxyServer.port;
                if (Platform.isIOS) {
                  await proxyServer.retryBind();
                }

                if (remoteDevice.value.ipProxy == true) {
                  host = remoteDevice.value.host!;
                  port = remoteDevice.value.port!;
                }

                // 记下代理地址，供返回桌面时同步进入小窗（不再 await 网卡枚举）
                PictureInPicture.updateProxy(host, port);
                Vpn.startVpn(host, port, proxyServer.configuration, ipProxy: remoteDevice.value.ipProxy);
              },
              onStop: () => Vpn.stopVpn()),
        ));
  }

  /// 远程连接
  Widget remoteConnect(RemoteModel value) {
    return Container(
        margin: const EdgeInsets.only(top: 5, bottom: 5),
        height: 56,
        width: double.infinity,
        child: ElevatedButton(
          style: ButtonStyle(
              shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (BuildContext context) {
            return RemoteDevicePage(remoteDevice: remoteDevice, proxyServer: proxyServer);
          })),
          child: Text(localizations.remoteConnected(remoteDevice.value.os ?? ', ${remoteDevice.value.hostname}'),
              style: Theme.of(context).textTheme.titleMedium),
        ));
  }

  /// 检查远程连接
  Future<void> checkConnectTask(BuildContext context) async {
    int retry = 0;
    Timer.periodic(const Duration(milliseconds: 15000), (timer) async {
      if (remoteDevice.value.connect == false) {
        timer.cancel();
        return;
      }

      try {
        var response = await HttpClients.get("http://${remoteDevice.value.host}:${remoteDevice.value.port}/ping")
            .timeout(const Duration(seconds: 3));
        if (response.bodyAsString == "pong") {
          retry = 0;
          return;
        }
      } catch (e) {
        retry++;
      }

      if (retry > 3) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();

          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(localizations.remoteConnectDisconnect),
              action: SnackBarAction(
                  label: localizations.disconnect,
                  onPressed: () {
                    timer.cancel();
                    remoteDevice.value = RemoteModel(connect: false);
                  })));
        }
      }
    });
  }
}

/// 移动端AppBar
class _MobileAppBar extends StatelessWidget implements PreferredSizeWidget {
  final AppConfiguration appConfiguration;
  final ProxyServer proxyServer;
  final ValueNotifier<RemoteModel> remoteDevice;

  const _MobileAppBar(this.appConfiguration, this.proxyServer, {required this.remoteDevice});

  Future<void> _onClear(BuildContext context, AppLocalizations localizations) async {
    if (!appConfiguration.clearConfirm) {
      MobileApp.requestStateKey.currentState?.clean();
      return;
    }

    showConfirmDialog(context, title: localizations.clearConfirm, onConfirm: () {
      MobileApp.requestStateKey.currentState?.clean();
    });
  }

  @override
  Size get preferredSize => const Size.fromHeight(42);

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    var bottomNavigation = appConfiguration.bottomNavigation;

    return AppBar(
        leading: bottomNavigation ? const SizedBox() : null,
        systemOverlayStyle: Platform.isAndroid
            ? SystemUiOverlayStyle(
                systemNavigationBarColor: ColorScheme.of(context).surface,
                statusBarColor: ColorScheme.of(context).surface)
            : null,
        title: MobileSearch(
            key: MobileApp.searchStateKey, onSearch: (val) => MobileApp.requestStateKey.currentState?.search(val)),
        actions: [
          IconButton(
              tooltip: localizations.clear,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _onClear(context, localizations)),
          const SizedBox(width: 2),
          MoreMenu(proxyServer: proxyServer, remoteDevice: remoteDevice),
          const SizedBox(width: 10),
        ]);
  }
}
