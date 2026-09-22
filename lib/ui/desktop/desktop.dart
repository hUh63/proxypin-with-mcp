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
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:proxypin/event/event_bus.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/mcp/mcp_bridge.dart';
import 'package:proxypin/network/mcp/mcp_server.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/system_proxy.dart';
import 'package:proxypin/network/util/windows_takeover.dart';
import 'package:proxypin/storage/histories.dart';
import 'package:proxypin/ui/component/app_dialog.dart';
import 'package:proxypin/ui/component/memory_cleanup.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/content/panel.dart';
import 'package:proxypin/ui/desktop/left_menus/favorite.dart';
import 'package:proxypin/ui/desktop/left_menus/history.dart';
import 'package:proxypin/ui/desktop/left_menus/navigation.dart';
import 'package:proxypin/ui/desktop/request/list.dart';
import 'package:proxypin/ui/desktop/toolbar/toolbar.dart';
import 'package:proxypin/ui/desktop/widgets/windows_toolbar.dart';
import 'package:proxypin/utils/listenable_list.dart';
import 'package:proxy_manager/proxy_manager.dart';

import '../app_update/app_update_repository.dart';
import '../component/split_view.dart';
import '../toolbox/toolbox.dart';

/// @author wanghongen
/// 2023/10/8
class DesktopHomePage extends StatefulWidget {
  final Configuration configuration;
  final AppConfiguration appConfiguration;

  const DesktopHomePage(this.configuration, this.appConfiguration, {super.key, required});

  @override
  State<DesktopHomePage> createState() => _DesktopHomePagePageState();
}

class _DesktopHomePagePageState extends State<DesktopHomePage> implements EventListener {
  static final container = ListenableList<HttpRequest>();

  static final GlobalKey<DesktopRequestListState> requestListStateKey = GlobalKey<DesktopRequestListState>();

  final ValueNotifier<int> _selectIndex = ValueNotifier(0);
  StreamSubscription<HistoryItem>? _remoteHistorySubscription;
  Subscription? _eventBusSubscription;

  late ProxyServer proxyServer = ProxyServer(widget.configuration);
  late NetworkTabController panel;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void onRequest(Channel channel, HttpRequest request) {
    requestListStateKey.currentState!.add(channel, request);

    if (request.attributes['quickShare'] == true) {
      _selectIndex.value = 0;
      panel.change(request, request.response);
    }

    //监控内存 到达阈值清理
    MemoryCleanupMonitor.onMonitor(onCleanup: () {
      requestListStateKey.currentState?.cleanupEarlyData(32);
    });
  }

  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) {
    requestListStateKey.currentState!.addResponse(channelContext, response);
    // 上游 #922：响应在详情页打开期间才到达时立即刷新，避免详情页停留在"未响应"
    final request = response.request;
    if (request != null && panel.request.get()?.requestId == request.requestId) {
      panel.change(request, response);
    }
  }

  @override
  void onMessage(Channel channel, HttpMessage message, WebSocketFrame frame) {
    if (panel.request.get() == message || panel.response.get() == message) {
      panel.changeState();
    }
  }

  @override
  void initState() {
    super.initState();
    proxyServer.addListener(this);
    panel = NetworkTabController(tabStyle: const TextStyle(fontSize: 16), proxyServer: proxyServer);
    _remoteHistorySubscription = HistoryStorage.onRemoteImported.listen((_) {
      if (mounted) {
        _selectIndex.value = 2;
      }
    });

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
    McpBridge().setRequestContainer(container);
    McpBridge().onClearUI = () {
      requestListStateKey.currentState?.clean();
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
    } else {
      AppUpdateRepository.checkUpdate(context);
    }

    // 上游 #886：启动自愈，清掉上次异常退出残留、指向本机已失效端口的系统代理
    unawaited(_repairStaleSystemProxy());
  }

  /// 上游 #886：系统代理残留自愈。
  ///
  /// 崩溃/强杀/卸载后系统代理可能仍指向 `127.0.0.1:<本应用端口>`，而那个端口已无人监听，
  /// 用户会表现为"整机网页全打不开"。这里只在以下条件同时成立时清理，避免误伤其它本地代理工具：
  /// 1. 用户没有开启「系统代理」开关（否则启动后本应用会正常接管）；
  /// 2. 代理指向 127.0.0.1 / localhost，且端口正是本应用的代理端口。
  Future<void> _repairStaleSystemProxy() async {
    try {
      if (widget.configuration.enableSystemProxy) return;

      final proxy = await SystemProxy.getSystemProxy(ProxyTypes.http);
      if (proxy == null) return;

      final host = proxy.host.toLowerCase();
      if ((host == '127.0.0.1' || host == 'localhost') && proxy.port == widget.configuration.port) {
        await SystemProxy.resetSystemProxy();
        logger.i('检测到残留的系统代理 ${proxy.host}:${proxy.port}，已自动清除');
      }
    } catch (e, t) {
      logger.e('系统代理自愈检查失败', error: e, stackTrace: t);
    }

    // 同理检查 Windows 增强接管的残留（WinHTTP + 代理环境变量）：
    // 这两处不会随进程结束自动消失，残留会让整机代理到一个死端口。
    try {
      if (!widget.configuration.winTakeoverEnabled) {
        await WindowsTakeover.repairStaleLayered(widget.configuration.port);
      }
    } catch (e, t) {
      logger.e('Windows 接管自愈检查失败', error: e, stackTrace: t);
    }
  }

  @override
  void dispose() {
    _remoteHistorySubscription?.cancel();
    final eventSub = _eventBusSubscription;
    if (eventSub != null) EventBus().unsubscribe(eventSub);
    McpServer().stop(persistState: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var navigationView = [
      DesktopRequestListWidget(key: requestListStateKey, proxyServer: proxyServer, list: container, panel: panel),
      Favorites(panel: panel),
      HistoryPageWidget(proxyServer: proxyServer, container: container, panel: panel),
      Toolbox(requestContainer: container)
    ];

    return Scaffold(
        appBar: Tab(
            child: Container(
          padding: EdgeInsets.only(bottom: 2.5),
          margin: EdgeInsets.only(bottom: 5),
          decoration: BoxDecoration(
              // color: Theme.of(context).brightness == Brightness.dark ? null : Color(0xFFF9F9F9),
              border: Border(
                  bottom: BorderSide(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                      width: Platform.isMacOS ? 0.2 : 0.55))),
          child: Platform.isMacOS
              ? Toolbar(proxyServer, requestListStateKey)
              : WindowsToolbar(title: Toolbar(proxyServer, requestListStateKey)),
        )),
        body: Row(
          children: [
            LeftNavigationBar(
                selectIndex: _selectIndex, appConfiguration: widget.appConfiguration, proxyServer: proxyServer),
            Expanded(
              child: VerticalSplitView(
                  ratio: widget.appConfiguration.panelRatio,
                  minRatio: 0.15,
                  maxRatio: 0.9,
                  onRatioChanged: (ratio) {
                    widget.appConfiguration.panelRatio = double.parse(ratio.toStringAsFixed(2));
                    widget.appConfiguration.flushConfig();
                  },
                  left: ValueListenableBuilder(
                      valueListenable: _selectIndex,
                      builder: (_, index, __) =>
                          LazyIndexedStack(index: index < 0 ? 0 : index, children: navigationView)),
                  right: panel),
            )
          ],
        ));
  }

  //更新引导
  void showUpgradeNotice() {
    bool isCN = Localizations.localeOf(context) == const Locale.fromSubtags(languageCode: 'zh');

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) {
          return AlertDialog(
              scrollable: true,
              actions: [
                TextButton(
                    onPressed: () {
                      widget.appConfiguration.upgradeNoticeV30 = false;
                      widget.appConfiguration.flushConfig();
                      Navigator.pop(context);
                    },
                    child: Text(localizations.close))
              ],
              title: Text(isCN ? '更新内容V${AppConfiguration.version}' : "What's new in V${AppConfiguration.version}",
                  style: const TextStyle(fontSize: 18)),
              content: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: SelectableText(
                      isCN
                          ? '提示：默认不会开启HTTPS抓包，请安装证书后再开启HTTPS抓包。\n'
                              '点击HTTPS抓包(加锁图标)，选择安装根证书，按照提示操作即可。\n\n'
                              '1. 新增弱网模拟功能，支持自定义延迟、丢包、带宽限制等网络条件；\n'
                              '2. 新增环境变量高亮，URL 和 Headers 支持环境变量渲染与颜色区分；\n'
                              '3. 新增 GraphQL 操作名称识别与展示；\n'
                              '4. 新增请求重写规则检测，Body 视图中标识匹配的重写规则；\n'
                              '5. 增强 HTTP/2：实现大体积 Body 流式传输，优化 Header 编解码，新增分块传输解码与统一 Body 读取逻辑；\n'
                              '6. 增强 cURL 生成：改进 multipart/form-data 和二进制 Body 的导出；\n'
                              '7. 修复：Android VPN 网络切换导致抓包中断、WebSocket 多帧合并丢失、Socket 连接异常关闭、裸域名请求 URI 为空等问题。\n'
                          : 'Note: HTTPS capture is disabled by default — please install the certificate before enabling HTTPS capture.\n'
                              'Click the HTTPS capture (lock) icon, choose "Install Root Certificate", and follow the prompts to complete installation.\n\n'
                              '1. Added weak network simulation with customizable latency, packet loss, and bandwidth throttling;\n'
                              '2. Added environment variable highlighting with color-coded variable rendering in URLs and headers;\n'
                              '3. Added GraphQL operation name recognition and display;\n'
                              '4. Added request rewrite rule detection with rule matching indicators in the Body view;\n'
                              '5. Enhanced HTTP/2: streaming for large bodies, improved header handling, chunked transfer decoding and unified body reading;\n'
                              '6. Enhanced cURL generation: better multipart/form-data and binary body export;\n'
                              '7. Fixed: Android VPN capture interruption on network switch, WebSocket frame merging loss, socket hang-up, empty URI for bare domains, and more.\n',
                      style: const TextStyle(fontSize: 14))));
        });
  }
}
