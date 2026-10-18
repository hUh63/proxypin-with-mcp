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
import 'package:get/get.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/network/components/repeat_task_manager.dart';
import 'package:proxypin/ui/component/api_endpoint_page.dart';
import 'package:proxypin/ui/component/memory_cleanup.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';
import 'package:proxypin/ui/component/connection_tree.dart';
import 'package:proxypin/ui/component/request_compare_page.dart';
import 'package:proxypin/ui/component/traffic_analytics.dart';
import 'package:proxypin/ui/component/selection_action_bar.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/content/panel.dart';
import 'package:proxypin/ui/desktop/request/report_servers.dart';
import 'package:proxypin/ui/desktop/request/request.dart';
import 'package:proxypin/ui/desktop/request/request_sequence.dart';
import 'package:proxypin/ui/desktop/request/search.dart';
import 'package:proxypin/utils/export_request.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/listenable_list.dart';

import '../../component/model/search_model.dart';
import 'domains.dart';

/// @author wanghongen
class DesktopRequestListWidget extends StatefulWidget {
  final ProxyServer proxyServer;
  final ListenableList<HttpRequest>? list;
  final NetworkTabController panel;

  const DesktopRequestListWidget({super.key, required this.proxyServer, this.list, required this.panel});

  @override
  State<StatefulWidget> createState() {
    return DesktopRequestListState();
  }
}

class DesktopRequestListState extends State<DesktopRequestListWidget> with AutomaticKeepAliveClientMixin {
  final GlobalKey<RequestSequenceState> requestSequenceKey = GlobalKey<RequestSequenceState>();
  final GlobalKey<DomainWidgetState> domainListKey = GlobalKey<DomainWidgetState>();
  final GlobalKey<SearchState> searchKey = GlobalKey<SearchState>();
  TabController? _tabController;

  //请求列表容器
  ListenableList<HttpRequest> container = ListenableList();

  bool sortDesc = true;

  /// 上游 #967：用户手动滚动或选中某条请求后，暂停「自动跟随最新」。
  /// 新请求只累加计数并显示提示条，当前视图保持不动；点击提示条恢复。
  /// 旧行为是每来一条新请求就重建列表，用户正在看的内容会被不断顶走，
  /// 表现为「自动滚动到最新」。
  bool _followPaused = false;
  final List<HttpRequest> _pausedRequests = [];
  final Map<String, Channel> _pausedChannels = {};

  /// 暂停期间到达的响应：请求还没进视图，直接 setResponse 会丢，恢复时补上。
  final Map<String, (ChannelContext, HttpResponse)> _pausedResponses = {};

  /// 选中集合监听（ListenableList 需要事件对象，不能用裸函数）。
  late final OnchangeListEvent<String> _selectionEvent = OnchangeListEvent<String>(_onSelectionChanged);

  // 选择控制器
  final MultiSelectController selectionController = MultiSelectController();

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    if (widget.list != null) {
      container = widget.list!;
    }
    selectionController.selectedIds.addListener(_selectionEvent);
  }

  /// 选中任意请求（用户正在查看详情）时停止自动跟随。
  void _onSelectionChanged() {
    if (selectionController.selectedIds.isNotEmpty) _pauseFollow();
  }

  void _pauseFollow() {
    if (_followPaused || !mounted) return;
    setState(() => _followPaused = true);
  }

  /// 恢复自动跟随：把暂停期间挂起的请求按到达顺序补进当前视图。
  void _resumeFollow() {
    if (!_followPaused || !mounted) return;
    final pending = List<HttpRequest>.of(_pausedRequests);
    _pausedRequests.clear();
    setState(() => _followPaused = false);
    for (final request in pending) {
      final channel = _pausedChannels.remove(request.requestId);
      if (channel == null) continue;
      domainListKey.currentState?.add(channel, request);
      requestSequenceKey.currentState?.add(request);
      // 请求进了视图才能挂响应，否则响应会丢（暂停期间的请求看起来一直 pending）。
      final cached = _pausedResponses.remove(request.requestId);
      if (cached != null) {
        domainListKey.currentState?.addResponse(cached.$1, cached.$2);
        requestSequenceKey.currentState?.addResponse(cached.$2);
      }
    }
    _pausedChannels.clear();
    _pausedResponses.clear();
    _trimOverflow();
  }

  bool get isSelectionMode => selectionController.isSelectionMode;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    selectionController.selectedIds.removeListener(_selectionEvent);
    RequestWidget.removeAutoReadByIds(container.map((request) => request.requestId));
    selectionController.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    List<Tab> tabs = [
      Tab(child: Text(localizations.domainList, style: const TextStyle(fontSize: 13))),
      Tab(child: Text(localizations.sequence, style: const TextStyle(fontSize: 13))),
    ];

    return FocusableActionDetector(
        autofocus: true,
        shortcuts: {
          SingleActivator(LogicalKeyboardKey.escape): const _ClearSelectionIntent(),
        },
        actions: {
          _ClearSelectionIntent: CallbackAction<_ClearSelectionIntent>(onInvoke: (intent) {
            if (_isTextInputFocused()) {
              return null;
            }
            if (isSelectionMode) {
              selectionController.clear();
            }
            return null;
          }),
        },
        child: DefaultTabController(
            length: tabs.length,
            child: Builder(builder: (tabContext) {
              _tabController = DefaultTabController.of(tabContext);
              return Scaffold(
                  appBar: AppBar(
                    toolbarHeight: 40,
                    title: SizedBox(height: 40, child: TabBar(tabs: tabs, dividerColor: Colors.transparent)),
                    automaticallyImplyLeading: false,
                    actions: [popupMenus()],
                  ),
                  bottomNavigationBar: Search(key: searchKey, onSearch: search),
                  body: Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: Column(children: [
                        if (_followPaused && _pausedRequests.isNotEmpty) _followPausedBanner(),
                        Obx(() => selectionController.selectionMode.value
                            ? SelectionActionBar(
                                selectionController: selectionController,
                                onSelectAll: () {
                                  // 全选必须基于「当前视图」，不能是未过滤的全量：
                                  // 旧实现用 container.source，过滤态下会把看不见的请求
                                  // 一起选中，ActionBar 显示 N 条，而删除/导出走的是过滤后
                                  // 的 selectedRequests() → 实际只操作 M 条（N != M），
                                  // 用户会误以为已经清空了全部。
                                  // 两个 Tab 共用同一套过滤条件（selectedIds 是集合，
                                  // 与展示顺序无关），因此统一取 DomainList 的当前视图。
                                  final Iterable<HttpRequest> view =
                                      domainListKey.currentState?.currentView() ?? container.source;
                                  selectionController.selectAll(view.map((r) => r.requestId));
                                },
                                onRepeat: repeatSelected,
                                onCompare: compareSelected,
                                onExport: exportSelected,
                                onDelete: deleteSelected)
                            : SizedBox()),
                        Expanded(
                            child: NotificationListener<ScrollNotification>(
                                onNotification: (notification) {
                                  // 用户自己拖动列表即视为「正在阅读」，停止自动跟随。
                                  if (notification is ScrollStartNotification && notification.dragDetails != null) {
                                    _pauseFollow();
                                  }
                                  return false;
                                },
                                child: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [
                          DomainList(
                            key: domainListKey,
                            list: container,
                            panel: widget.panel,
                            proxyServer: widget.proxyServer,
                            selectionController: selectionController,
                            selectionHandlers: RequestSelectionHandlers(
                              onRangeSelection: rangeSelectRequest,
                              onDeleteSelected: deleteSelected,
                              onRepeatSelected: repeatSelected,
                              onExportSelected: exportSelected,
                            ),
                            onRemove: domainListRemove,
                          ),
                          RequestSequence(
                            key: requestSequenceKey,
                            container: container,
                            proxyServer: widget.proxyServer,
                            selectionController: selectionController,
                            selectionHandlers: RequestSelectionHandlers(
                              onRangeSelection: rangeSelectRequest,
                              onDeleteSelected: deleteSelected,
                              onRepeatSelected: repeatSelected,
                              onExportSelected: exportSelected,
                            ),
                            onRemove: sequenceRemove,
                            onInitialized: () {
                              if (searchKey.currentState?.searchModel.isNotEmpty == true) {
                                requestSequenceKey.currentState?.search(searchKey.currentState!.searchModel);
                              }
                            },
                          ),
                        ]))),
                      ])));
            })));
  }

  bool _isTextInputFocused() {
    return FocusManager.instance.primaryFocus?.context?.widget is EditableText;
  }

  Widget popupMenus() {
    return PopupMenuButton<_RequestListMenuAction>(
        offset: const Offset(0, 32),
        icon: const Icon(Icons.more_vert_outlined, size: 20),
        onSelected: _onMenuSelected,
        itemBuilder: (BuildContext context) {
          return <PopupMenuEntry<_RequestListMenuAction>>[
            _menuItem(_RequestListMenuAction.search,
                icon: const Icon(Icons.search, size: 17), text: localizations.search),
            _menuItem(_RequestListMenuAction.export,
                icon: const Icon(Icons.share, size: 16), text: localizations.viewExport),
            _menuItem(_RequestListMenuAction.repeat,
                icon: const Icon(Icons.repeat, size: 16), text: localizations.repeatAllRequests),
            _menuItem(_RequestListMenuAction.select,
                icon: const Icon(Icons.checklist_outlined, size: 16), text: localizations.select),
            _menuItem(_RequestListMenuAction.sort,
                icon: const Icon(Icons.sort, size: 16),
                text: sortDesc ? localizations.timeAsc : localizations.timeDesc),
            _menuItem(_RequestListMenuAction.report,
                icon: const Icon(Icons.cloud_upload_outlined, size: 16), text: localizations.reportServers),
            _menuItem(_RequestListMenuAction.apiEndpoints,
                icon: const Icon(Icons.api, size: 16), text: localizations.toolboxApiEndpoints),
            _menuItem(_RequestListMenuAction.trafficAnalytics,
                icon: const Icon(Icons.insights, size: 16), text: localizations.trafficAnalytics),
            _menuItem(_RequestListMenuAction.connections,
                icon: const Icon(Icons.hub_outlined, size: 16), text: localizations.connectionTree),
          ];
        });
  }

  PopupMenuEntry<_RequestListMenuAction> _menuItem(_RequestListMenuAction value,
      {required Icon icon, required String text}) {
    return CustomPopupMenuItem<_RequestListMenuAction>(
        value: value, height: 37, child: IconText(icon: icon, text: text, textStyle: const TextStyle(fontSize: 13)));
  }

  void _onMenuSelected(_RequestListMenuAction action) {
    switch (action) {
      case _RequestListMenuAction.search:
        searchKey.currentState?.searchDialog();
        break;
      case _RequestListMenuAction.export:
        export('ProxyPin_${DateTime.now().dateFormat()}.har');
        break;
      case _RequestListMenuAction.repeat:
        repeatAllRequests();
        break;
      case _RequestListMenuAction.select:
        selectionController.toggleSelectionMode();
        break;
      case _RequestListMenuAction.sort:
        setState(() {
          sortDesc = !sortDesc;
        });
        requestSequenceKey.currentState?.sort(sortDesc);
        domainListKey.currentState?.sort(sortDesc);
        break;
      case _RequestListMenuAction.report:
        showReportServersDialog(context);
        break;
      case _RequestListMenuAction.apiEndpoints:
        // 用当前抓包数据提取 API 端点（同进程打开，支持导出 OpenAPI/Postman/JSON）
        ApiEndpointUtils.showEndpoints(context, container.source);
        break;
      case _RequestListMenuAction.trafficAnalytics:
        // 对当前抓包列表做聚合统计（Top 域名/类型/状态码、最慢、最大）
        showTrafficAnalytics(context, container.source);
        break;
      case _RequestListMenuAction.connections:
        // 活动连接视图（HTTP/2 连接树 + 连接/TLS 耗时）
        showConnectionTree(context);
        break;
    }
  }

  ///添加请求
  void add(Channel channel, HttpRequest request) {
    container.add(request);

    // 上游 #967：暂停期间不往当前视图插入，避免把用户正在看的内容顶走。
    if (_followPaused) {
      _pausedRequests.add(request);
      _pausedChannels[request.requestId] = channel;
      // 挂起队列也要有上限：用户长时间不点恢复时不能无限制占内存。
      const maxPaused = 2000;
      if (_pausedRequests.length > maxPaused) {
        final dropped = _pausedRequests.removeAt(0);
        _pausedChannels.remove(dropped.requestId);
      }
      if (mounted) setState(() {});
      return;
    }

    domainListKey.currentState?.add(channel, request);
    requestSequenceKey.currentState?.add(request);
    _trimOverflow();
  }

  /// 超出上限时丢弃最旧请求（上游 #899）。
  void _trimOverflow() {
    final maxCount = AppConfiguration.current?.maxRequestCount ?? 0;
    if (maxCount > 0 && container.length > maxCount) {
      final overflow = container.length - maxCount;
      final removed = container.removeRange(0, overflow);
      // 上游 #839 Bug 3：与移动端同理，改用增量 remove 避免每次都全量重建。
      domainListKey.currentState?.remove(removed);
      requestSequenceKey.currentState?.remove(removed);
      RequestWidget.removeAutoReadByIds(removed.map((request) => request.requestId));
      selectionController.prune(container.map((request) => request.requestId));
      MemoryCleanupMonitor.releaseAll(removed);
    }
  }

  /// 暂停自动跟随时的提示条：点击把挂起的请求补进列表。
  Widget _followPausedBanner() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: InkWell(
        onTap: _resumeFollow,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(children: [
            Icon(Icons.arrow_upward, size: 15, color: scheme.onSecondaryContainer),
            const SizedBox(width: 6),
            Expanded(
              child: Text(localizations.newRequestsPaused(_pausedRequests.length),
                  style: TextStyle(fontSize: 12, color: scheme.onSecondaryContainer)),
            ),
          ]),
        ),
      ),
    );
  }

  ///添加响应
  void addResponse(ChannelContext channelContext, HttpResponse response) {
    // 暂停期间该请求尚未进入视图，先缓存响应，恢复时与请求一起补进去。
    final requestId = response.request?.requestId ?? response.requestId;
    if (_followPaused && requestId != null && _pausedChannels.containsKey(requestId)) {
      _pausedResponses[requestId] = (channelContext, response);
      return;
    }

    domainListKey.currentState?.addResponse(channelContext, response);
    requestSequenceKey.currentState?.addResponse(response);
  }

  void remove(List<HttpRequest> list) {
    container.removeWhere((element) => list.contains(element));
    domainListKey.currentState?.remove(list);
    requestSequenceKey.currentState?.remove(list);
    RequestWidget.removeAutoReadByIds(list.map((request) => request.requestId));
  }

  ///移除
  void domainListRemove(List<HttpRequest> list) {
    container.removeWhere((element) => list.contains(element));
    requestSequenceKey.currentState?.remove(list);
    RequestWidget.removeAutoReadByIds(list.map((request) => request.requestId));
    selectionController.prune(container.map((request) => request.requestId));
  }

  ///全部请求删除
  void sequenceRemove(List<HttpRequest> list) {
    container.removeWhere((element) => list.contains(element));
    domainListKey.currentState?.remove(list);
    RequestWidget.removeAutoReadByIds(list.map((request) => request.requestId));
    selectionController.prune(container.map((request) => request.requestId));
  }

  void search(SearchModel searchModel) {
    // 搜索要覆盖暂停期间挂起的请求：先补回视图，否则搜不到它们。
    if (_followPaused) _resumeFollow();
    domainListKey.currentState?.search(searchModel);
    requestSequenceKey.currentState?.search(searchModel);
  }

  List<HttpRequest>? currentView() {
    return domainListKey.currentState?.currentView();
  }

  ///清理
  void clean() {
    final removed = container.source.toList();
    setState(() {
      _pausedRequests.clear();
      _pausedChannels.clear();
      _pausedResponses.clear();
      _followPaused = false;
      RequestWidget.removeAutoReadByIds(container.map((request) => request.requestId));
      container.clear();
      domainListKey.currentState?.clean();
      requestSequenceKey.currentState?.clean();
      widget.panel.change(null, null);
      selectionController.clear();
    });
    // 上游 #899：清空后立即释放字节数据
    MemoryCleanupMonitor.releaseAll(removed);
  }

  void cleanupEarlyData(int retain) {
    var list = container.source;
    if (list.length <= retain) {
      return;
    }

    var removeRange = container.removeRange(0, list.length - retain);

    // 上游 #839 Bug 3：同 add() 超限分支，增量移除而不是全量重建
    domainListKey.currentState?.remove(removeRange);
    requestSequenceKey.currentState?.remove(removeRange);

    RequestWidget.removeAutoReadByIds(removeRange.map((request) => request.requestId));
    selectionController.prune(container.map((request) => request.requestId));
    // 上游 #899：被清理的请求立刻释放字节数据
    MemoryCleanupMonitor.releaseAll(removeRange);
  }

  void deleteSelected() {
    final selectedRequests = domainListKey.currentState?.selectedRequests();
    if (selectedRequests == null || selectedRequests.isEmpty) {
      return;
    }

    showConfirmDialog(context, content: '${localizations.delete} ${selectedRequests.length} ${localizations.request}?',
        onConfirm: () {
      setState(() {
        remove(selectedRequests);
        selectionController.clear();
      });
      if (mounted) {
        FlutterToastr.show(localizations.deleteSuccess, context);
      }
    });
  }

  void rangeSelectRequest(HttpRequest request) {
    switch (_tabController?.index) {
      case 1:
        requestSequenceKey.currentState?.selectRange(request);
        break;
      case 0:
      default:
        domainListKey.currentState?.selectRange(request);
        break;
    }
  }

  void repeatSelected() {
    final selectedRequests = domainListKey.currentState?.selectedRequests();
    _repeatRequests(selectedRequests);
    selectionController.clear();
  }

  /// 请求对比：选中恰好两条时可用（复用已实现的请求对比分析页）
  void compareSelected() {
    final selected = domainListKey.currentState?.selectedRequests() ?? [];
    if (selected.length != 2) {
      FlutterToastr.show(localizations.compareNeedTwo, context);
      return;
    }
    RequestCompareUtils.showCompare(context, selected[0], selected[1],
        responseA: selected[0].response, responseB: selected[1].response);
  }

  Future<void> exportSelected() async {
    final selectedRequests = domainListKey.currentState?.selectedRequests();
    if (selectedRequests == null || selectedRequests.isEmpty) {
      return;
    }

    final folderName = 'proxypin_export_${DateTime.now().dateFormat()}';
    showExportDialog(context, selectedRequests, folderName, onExportSuccess: () {
      selectionController.clear();
    }, onImport: (imported) => container.addAll(imported));
  }

  ///导出
  Future<void> export(String fileName) async {
    //获取请求
    List<HttpRequest>? requests = currentView();
    if (requests == null) return;
    final folderName = 'proxypin_${DateTime.now().dateFormat()}';
    showExportDialog(context, requests, folderName,
        onImport: (imported) => container.addAll(imported));
  }

  ///重发所有请求
  void repeatAllRequests() async {
    var requests = currentView();
    _repeatRequests(requests);
  }

  void _repeatRequests(List<HttpRequest>? requests) async {
    if (requests == null) return;

    var localizations = AppLocalizations.of(context);
    final proxyServer = widget.proxyServer;

    // 上游 #715/#401：批量重放登记到「发送队列」
    final task = RepeatTaskManager.instance.create(
      title: localizations!.repeatBatchCount(requests.length),
      total: requests.length,
      pending: requests.map((r) => '${r.methodLabel} ${r.domainPath}').toList(),
    );
    RepeatTaskManager.instance.markRunning(task);

    for (var request in requests) {
      if (task.status == RepeatTaskStatus.canceled) break;
      var httpRequest = request.copy(uri: request.requestUrl);
      var proxyInfo = proxyServer.isRunning ? ProxyInfo.of("127.0.0.1", proxyServer.port) : null;
      try {
        // 上游 #892：批量重放原来只给 3 秒超时，稍慢的接口会成批失败（用户报“100 次只成功 70 次”）
        await HttpClients.proxyRequest(httpRequest, proxyInfo: proxyInfo, timeout: const Duration(seconds: 10));
        RepeatTaskManager.instance.record(task, ok: true);
        if (mounted) {
          FlutterToastr.show(localizations!.reSendRequest, rootNavigator: true, context);
        }
      } catch (e) {
        RepeatTaskManager.instance.record(task, ok: false, error: e.toString());
        if (mounted) {
          FlutterToastr.show('${localizations!.fail} $e', rootNavigator: true, context);
        }
      }
    }
    RepeatTaskManager.instance.markCompleted(task);
  }
}

class _ClearSelectionIntent extends Intent {
  const _ClearSelectionIntent();
}

enum _RequestListMenuAction { search, export, repeat, select, sort, report, apiEndpoints, trafficAnalytics, connections }
