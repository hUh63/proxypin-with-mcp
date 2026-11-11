import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/api_endpoint_page.dart';
import 'package:proxypin/ui/component/capture_plan_page.dart';
import 'package:proxypin/ui/component/capture_diagnose_page.dart';
import 'package:proxypin/ui/component/fuzzer_page.dart';
import 'package:proxypin/ui/component/security_audit_page.dart';
import 'package:proxypin/ui/toolbox/js_restore_page.dart';
import 'package:proxypin/ui/component/quic_sessions_page.dart';
import 'dart:io';

import 'package:proxypin/ui/component/kernel_capture_dialog.dart';
import 'package:proxypin/ui/component/repeat_queue_page.dart';

import 'package:file_picker/file_picker.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/guide_center.dart';
import 'package:proxypin/ui/component/ai_analysis.dart';
import 'package:proxypin/ui/toolbox/dev_tools.dart';
import 'package:proxypin/ui/toolbox/calculator_page.dart';
import 'package:proxypin/ui/component/pinning_page.dart';
import 'package:proxypin/ui/component/workspace_page.dart';
import 'package:proxypin/ui/component/cloud_page.dart';
import 'package:proxypin/ui/component/waf_page.dart';
import 'package:proxypin/ui/component/multi_window.dart';
import 'package:proxypin/ui/mobile/request/request_editor.dart';
import 'package:proxypin/ui/mobile/setting/mcp_connection.dart';
import 'package:proxypin/ui/toolbox/qr_code_page.dart';
import 'package:proxypin/ui/toolbox/regexp.dart';
import 'package:proxypin/ui/toolbox/timestamp.dart';
import 'package:proxypin/ui/toolbox/net_tools.dart';
import 'package:proxypin/ui/toolbox/convert_page.dart';
import 'package:proxypin/ui/toolbox/crc_page.dart';
import 'package:proxypin/ui/toolbox/device_spoof_page.dart';
import 'package:proxypin/ui/toolbox/artex_page.dart';
import 'package:proxypin/ui/toolbox/artex_webview.dart';
import 'package:proxypin/ui/toolbox/device_info_page.dart';
import 'package:proxypin/ui/toolbox/hex_diff_page.dart';
import 'package:proxypin/ui/toolbox/three_way_merge.dart';
import 'package:proxypin/ui/toolbox/file_split_page.dart';
import 'package:proxypin/ui/component/performance_dashboard.dart';
import 'package:proxypin/ui/component/log_viewer_page.dart';
import 'package:proxypin/utils/platform.dart';

import 'cert_hash.dart';
import 'cert_check_page.dart';
import 'cipher_page.dart';
import 'sign_page.dart';
import 'device_profile_page.dart';
import 'encoder.dart';
import 'hash_page.dart';
import 'hash_audit_page.dart';
import 'package:proxypin/ui/desktop/left_menus/replay_tasks.dart' as replay_desktop;
import 'package:proxypin/ui/mobile/request/replay_tasks.dart';

import 'rsa_page.dart';
import 'js_run.dart';
import 'json_viewer.dart';
import 'network_diagnostics.dart';
import 'file_preview.dart';
import 'dir_diff_page.dart';
import 'text_diff.dart';
import 'text_editor.dart';
import 'websocket_request.dart';
import 'xml_viewer.dart';

class Toolbox extends StatefulWidget {
  final ProxyServer? proxyServer;

  /// 当前抓包请求容器（由调用方传入，用于 API 端点提取等需要数据源的工具）
  final Iterable<HttpRequest>? requestContainer;

  const Toolbox({super.key, this.proxyServer, this.requestContainer});

  @override
  State<StatefulWidget> createState() {
    return _ToolboxState();
  }
}

class _ToolboxState extends State<Toolbox> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  /// 手机端宫格横向收紧（间距 4、项水平 padding 8、按内容定宽），保证 4 项一行整屏放下；桌面端不变
  bool get mobile => Platforms.isMobile();

  /// 工具搜索框。工具箱有近 50 个入口，手机一屏只能放 12 个格子，
  /// 靠滚动找「时间戳」这种次要工具要翻七八屏 —— 直接打字过滤最快。
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  /// `_group` 在构建时把「组名 + 条目」登记进来，搜索时按它过滤。
  final List<({String label, List<Widget> items})> _groupData = [];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 分组容器：手机端 = 设计稿 p-sec2 小灰标题 + p-tbcard 白卡宫格（与配置/设置页白卡同一语言）；
  /// 桌面端 = Divider + 14px 标题 + 裸宫格（首组无标题，[desktopHeader] 控制）
  Widget _group(String label, List<Widget> items, {bool desktopHeader = true}) {
    _groupData.add((label: label, items: items));
    return _groupView(label, items, desktopHeader: desktopHeader);
  }

  /// 纯渲染（不登记），搜索结果的卡片也走它。
  Widget _groupView(String label, List<Widget> items, {bool desktopHeader = true}) {
    var theme = Theme.of(context);
    if (mobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 5),
            child: Text(label,
                style:
                    TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurfaceVariant))),
        Container(
            // start 对齐的 Column 里必须显式拉满，否则 Wrap 按内容收缩、4 列变 3 列
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 2),
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
            decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.55)),
                borderRadius: BorderRadius.circular(10)),
            child: Wrap(children: items)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (desktopHeader) ...[
        const Divider(thickness: 0.3),
        // 设计稿 .tb-sec：12px 灰标签
        Text(label,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurfaceVariant)),
      ],
      Wrap(spacing: 6, children: items),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    // 每帧重新登记：图标是新建的 widget 实例，搜索索引必须跟着换。
    _groupData.clear();
    final allGroups = Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
              _group(localizations.request, [
                  IconText(
                    icon: Icons.http,
                    text: "HTTP",
                    onTap: httpRequest,
                    tooltip: localizations.httpRequest,
                  ),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context)
                              .push(MaterialPageRoute(builder: (context) => const WebSocketRequestPage()));
                          return;
                        }
                        MultiWindow.openWindow('WebSocket', 'WebSocketRequestPage', size: const Size(800, 600));
                      },
                      icon: Icons.wifi_tethering,
                      text: 'WebSocket',
                      tooltip: 'WebSocket'),
                  IconText(
                    icon: Icons.javascript,
                    text: 'JavaScript',
                    tooltip: 'JavaScript',
                    onTap: () async {
                      if (Platforms.isMobile()) {
                        Navigator.of(context).push(MaterialPageRoute(builder: (context) => const JavaScript()));
                        return;
                      }

                      var size = MediaQuery.of(context).size;
                      MultiWindow.openWindow('JavaScript', 'JavaScript', size: Size(960, size.height));
                    },
                  ),
                  IconText(
                      onTap: () async {
                        // 上游 v1.4.0：可查看/暂停/取消的重放任务
                        if (Platforms.isMobile()) {
                          Navigator.of(context)
                              .push(MaterialPageRoute(builder: (context) => const ReplayTasksPage()));
                          return;
                        }
                        await replay_desktop.showReplayTasksDialog(context);
                      },
                      icon: Icons.schedule_outlined,
                      text: localizations.replayTasks,
                      tooltip: localizations.replayTasks),
              ]),
              _group(localizations.toolboxGroupDiff, [
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TextDiffPage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.textDiff, 'TextDiffPage', size: const Size(1100, 720));
                      },
                      icon: Icons.difference_outlined,
                      text: localizations.textDiff),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          await DirDiffPage.show(context);
                          return;
                        }
                        MultiWindow.openWindow(localizations.dirDiff, 'DirDiffPage',
                            size: const Size(1000, 700));
                      },
                      icon: Icons.folder_copy_outlined,
                      text: localizations.dirDiff,
                      tooltip: localizations.dirDiff),
                  IconText(
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => const HexDiffPage()));
                      },
                      icon: Icons.compare_arrows,
                      text: localizations.hexDiffTitle,
                      tooltip: localizations.hexDiffTitle),
                  IconText(
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => const ThreeWayMergePage()));
                      },
                      icon: Icons.merge_type,
                      text: localizations.diffThreeWay,
                      tooltip: localizations.diffThreeWay),
              ]),
              _group(localizations.toolboxGroupEncode, [
                  IconText(
                    onTap: () => encodeWindow(EncoderType.url, context),
                    icon: Icons.swap_horiz,
                    text: localizations.toolboxEncodeEntry,
                    tooltip: localizations.toolboxEncodeEntryTip,
                  ),
                  IconText(
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const HashPage(initialIndex: 0))),
                    icon: Icons.fingerprint,
                    text: localizations.toolboxHashEntry,
                    tooltip: localizations.toolboxHashEntryTip,
                  ),
                  IconText(
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => const ConvertPage()));
                      },
                      icon: Icons.swap_horiz,
                      text: localizations.toolboxConvert,
                      tooltip: localizations.toolboxConvert),
                  IconText(
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => const CrcPage()));
                      },
                      icon: Icons.fingerprint,
                      text: 'CRC32',
                      tooltip: 'CRC32 / zip 条目 CRC'),
                  IconText(
                    onTap: () => HashAuditPage.show(context),
                    icon: Icons.manage_search,
                    text: localizations.hashAudit,
                    tooltip: localizations.hashAudit,
                  ),
              ]),
              _group(localizations.toolboxGroupCipher, [
                  IconText(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const CipherPage(initialAlgorithm: 'AES'))),
                    icon: Icons.enhanced_encryption_outlined,
                    text: localizations.toolboxCipherEntry,
                    tooltip: localizations.toolboxCipherEntryTip,
                  ),
                  IconText(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (context) => const RsaPage())),
                    icon: Icons.security_outlined,
                    text: 'RSA',
                    tooltip: localizations.toolboxRsaTip,
                  ),
                  IconText(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (context) => const SignPage())),
                    icon: Icons.verified_outlined,
                    text: localizations.toolboxSign,
                    tooltip: localizations.toolboxSign,
                  ),
              ]),
              _group(localizations.toolboxGroupText, [
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const JsonViewerPage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.jsonViewer, 'JsonViewerPage', size: const Size(780, 820));
                      },
                      icon: Icons.data_object,
                      text: 'JSON'),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const XmlViewerPage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.xmlViewer, 'XmlViewerPage', size: const Size(900, 700));
                      },
                      icon: Icons.code,
                      text: 'XML'),
                  IconText(
                      onTap: () async {
                        // 文件预览：图片/动图/音视频/压缩包/文本/网页/二进制，按类型自动分流
                        try {
                          final picked = await FilePicker.pickFile(type: FileType.any);
                          final path = picked?.path;
                          if (path == null || !context.mounted) return;
                          await FilePreviewPage.show(context, File(path));
                        } catch (e) {
                          logger.w('file preview failed: $e');
                        }
                      },
                      icon: Icons.perm_media_outlined,
                      text: localizations.filePreview,
                      tooltip: localizations.filePreviewTip),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          await Navigator.of(context).push(
                              MaterialPageRoute(builder: (context) => const JsRestorePage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.jsRestore, 'JsRestorePage',
                            size: const Size(900, 760));
                      },
                      icon: Icons.auto_fix_high_outlined,
                      text: localizations.jsRestore,
                      tooltip: localizations.jsRestoreTips),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TextEditorPage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.textEditor, 'TextEditorPage', size: const Size(900, 800));
                      },
                      icon: Icons.note_alt_outlined,
                      text: localizations.textEditor,
                      tooltip: localizations.textEditor),
              ]),
              _group(localizations.toolboxGroupNetwork, [
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          await Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) => const NetworkDiagnosticsPage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.networkDiagnostics,
                            'NetworkDiagnosticsPage', size: const Size(560, 740));
                      },
                      icon: Icons.health_and_safety_outlined,
                      text: localizations.networkDiagnostics,
                      tooltip: localizations.networkDiagnostics),
                  IconText(
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => const NetToolsPage()));
                      },
                      icon: Icons.wifi_tethering,
                      text: localizations.netTools,
                      tooltip: localizations.netTools),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          await Navigator.of(context).push(
                              MaterialPageRoute(builder: (context) => const CapturePlanPage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.capturePlan, 'CapturePlanPage',
                            size: const Size(720, 760));
                      },
                      icon: Icons.route_outlined,
                      text: localizations.capturePlan),
                  IconText(
                      onTap: () {
                        // 抓包自检：只读检测代理/证书/流量状态，并列出常见抓不到的原因
                        final source = (widget.requestContainer ?? const <HttpRequest>[]).toList();
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => CaptureDiagnosePage(requests: source)));
                      },
                      icon: Icons.fact_check_outlined,
                      text: localizations.captureDiagnose,
                      tooltip: localizations.captureDiagnoseTip),
                  if (Platform.isWindows)
                    IconText(
                        onTap: () => showKernelCaptureDialog(context),
                        icon: Icons.shield_moon_outlined,
                        text: localizations.toolboxKernelCapture,
                        tooltip: localizations.kernelCaptureTitle),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          await Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) => const QuicSessionsPage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.toolboxQuic, 'QuicSessionsPage',
                            size: const Size(760, 640));
                      },
                      icon: Icons.hub_outlined,
                      text: localizations.toolboxQuic,
                      tooltip: localizations.toolboxQuicTip),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          await Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) => const RepeatQueuePage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.toolboxSendQueue, 'RepeatQueuePage',
                            size: const Size(760, 640));
                      },
                      icon: Icons.outbox_outlined,
                      text: localizations.toolboxSendQueue,
                      tooltip: localizations.toolboxSendQueueTip),
                  IconText(
                      onTap: () {
                        // 从当前抓包数据提取 API 端点
                        final source = (widget.requestContainer ?? const <HttpRequest>[]).toList();
                        ApiEndpointUtils.showEndpoints(context, source);
                      },
                      icon: Icons.api,
                      text: localizations.toolboxApiEndpoints,
                      tooltip: localizations.toolboxApiEndpointsTip),
              ]),
              _group(localizations.toolboxGroupSecurity, [
                  IconText(
                      onTap: () {
                        // 对已抓到的流量做被动安全基线核查（不发送任何请求）
                        final source = (widget.requestContainer ?? const <HttpRequest>[]).toList();
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => SecurityAuditPage(requests: source)));
                      },
                      icon: Icons.shield_outlined,
                      text: localizations.securityAudit,
                      tooltip: localizations.securityAuditTips),
                  IconText(
                      onTap: () {
                        // 手动 Fuzz：把用户自填的取值逐条替换进请求发送并对照响应
                        final source = (widget.requestContainer ?? const <HttpRequest>[]).toList();
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => FuzzerPage(requests: source)));
                      },
                      icon: Icons.science_outlined,
                      text: localizations.fuzzer,
                      tooltip: localizations.fuzzerTips),
                  IconText(
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (context) => const WafPage())),
                      icon: Icons.security_outlined,
                      text: localizations.toolboxNavWaf,
                      tooltip: localizations.toolboxNavWafTip),
                  IconText(
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (context) => const PinningPage())),
                      icon: Icons.lock_open_outlined,
                      text: localizations.toolboxSslPinning,
                      tooltip: localizations.toolboxNavPinningTip),
              ]),
              _group(localizations.toolboxGroupDevice, [
                  IconText(
                    onTap: _showDeviceHub,
                    icon: Icons.smartphone,
                    text: localizations.toolboxDeviceEntry,
                    tooltip: localizations.toolboxDeviceEntryTip,
                  ),
                  IconText(
                    onTap: _showCertHub,
                    icon: Icons.verified_user_outlined,
                    text: localizations.toolboxCertEntry,
                    tooltip: localizations.toolboxCertEntryTip,
                  ),
                  IconText(
                      onTap: () {
                        // 直接进 ARTEX 自己的前端（本地托管 + WebView），
                        // 和官方 App 一致；原生面板在右上角菜单里。
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => const ArtexWebPage()));
                      },
                      icon: Icons.hub_outlined,
                      text: 'ARTEX',
                      tooltip: localizations.artexConsole),
              ]),
              _group(localizations.toolboxGroupUtilities, [
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TimestampPage()));
                          return;
                        }

                        MultiWindow.openWindow(localizations.timestamp, 'TimestampPage', size: const Size(700, 350));
                      },
                      icon: Icons.av_timer,
                      text: localizations.timestamp,
                      tooltip: localizations.timestamp),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const RegExpPage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.regExp, 'RegExpPage', size: const Size(800, 720));
                      },
                      icon: Icons.find_in_page_outlined,
                      text: localizations.regExp,
                      tooltip: localizations.regExp),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const QrCodePage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.qrCode, 'QrCodePage');
                      },
                      icon: Icons.qr_code_2,
                      text: localizations.qrCode,
                      tooltip: localizations.qrCode),
                  IconText(
                    icon: Icons.calculate_outlined,
                    text: localizations.calcTitle,
                    tooltip: localizations.toolboxNavCalcTip,
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) => const CalculatorPage()));
                    },
                  ),
                  IconText(
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => const FileSplitPage()));
                      },
                      icon: Icons.call_split,
                      text: localizations.fileSplitTitle,
                      tooltip: localizations.fileSplitTitle),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const LogViewerPage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.toolboxNavLogView, 'LogViewerPage', size: const Size(900, 700));
                      },
                      icon: Icons.article_outlined,
                      text: localizations.toolboxLog,
                      tooltip: localizations.toolboxLogTip),
              ]),
              _group(localizations.toolboxGroupExtend, [
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const PerformanceDashboard()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.toolboxPerformance, 'PerformanceDashboard', size: const Size(900, 700));
                      },
                      icon: Icons.speed,
                      text: localizations.toolboxPerformance,
                      tooltip: localizations.toolboxPerformanceTip),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const McpConnectionPage()));
                          return;
                        }
                        MultiWindow.openWindow('MCP', 'McpConnectionPage');
                      },
                      icon: Icons.cast_connected,
                      text: 'MCP',
                      tooltip: localizations.toolboxNavMcpTip),
                  IconText(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) =>
                              WorkspacePage(requestContainer: widget.requestContainer))),
                      icon: Icons.workspaces,
                      text: localizations.wsPageTitle,
                      tooltip: localizations.toolboxNavWorkspaceTip),
                  IconText(
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (context) => const CloudPage())),
                      icon: Icons.cloud_outlined,
                      text: localizations.cloudTitle,
                      tooltip: localizations.toolboxNavCloudTip),
                  IconText(
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => const DevToolsPage(initialIndex: 0)));
                      },
                      icon: Icons.build_circle_outlined,
                      text: localizations.toolboxDevTools,
                      tooltip: localizations.toolboxDevToolsTip),
                  IconText(
                      onTap: () => showGuideCenter(context),
                      icon: Icons.menu_book_outlined,
                      text: localizations.toolboxDocs,
                      tooltip: localizations.toolboxDocsTip),
                  IconText(
                      onTap: () {
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const AiChatPage()));
                      },
                      icon: Icons.psychology_outlined,
                      text: localizations.aiTitle,
                      tooltip: localizations.toolboxNavAiTip),
              ]),
              // 手机端底部导航会盖住最后一行图标，留一段可滚动的空白。
              if (mobile) const SizedBox(height: 28),
            ],
    );
    return IconTheme(
        // 设计稿 .tb-item svg：20px（全局 IconTheme 统一，移动端共用）
        data: IconTheme.of(context).copyWith(color: IconTheme.of(context).color?.withValues(alpha: 0.65), size: 20),
        child: Column(children: [
          _searchBar(),
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                // 手机端卡片/标题自带水平留白（桌面端保持 10）
                padding: mobile ? EdgeInsets.zero : const EdgeInsets.all(10),
                child: _query.isEmpty ? allGroups : _searchResult(),
              ),
            ),
          ),
        ]));
  }

  /// 顶部搜索框（固定，不随宫格滚动）。
  Widget _searchBar() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: TextField(
        controller: _searchCtrl,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18),
          hintText: localizations.toolboxSearchHint,
          hintStyle: const TextStyle(fontSize: 12.5),
          border: const OutlineInputBorder(),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  }),
        ),
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
      ),
    );
  }

  /// 搜索结果：按「名称 / 提示语」子串匹配（中英文都能搜），仍按原来的分组展示。
  Widget _searchResult() {
    final q = _query;
    final groups = <({String label, List<Widget> items})>[];
    for (final g in _groupData) {
      final hits = g.items.where((w) {
        if (w is! IconText) return false;
        return w.text.toLowerCase().contains(q) ||
            (w.tooltip ?? '').toLowerCase().contains(q);
      }).toList();
      if (hits.isNotEmpty) groups.add((label: g.label, items: hits));
    }
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 30, 14, 4),
        child: Text(localizations.toolboxSearchEmpty,
            style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final g in groups) _groupView(g.label, g.items)],
    );
  }

  /// 把「同一件事的多个入口」收成一个：点开再选具体哪一个。
  ///
  /// 手机一屏只放得下 12 个格子，同类工具各占一格会把别的挤到七八屏之外；
  /// 合并后仍然一步可达（列表就在手指边上），但宫格清爽很多。
  Future<void> _showHub(
      String title, List<({IconData icon, String label, String hint, VoidCallback open})> items) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(title,
                style: TextStyle(
                    fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
          ),
          const Divider(height: 1),
          for (var i = 0; i < items.length; i++)
            ListTile(
              dense: true,
              leading: Icon(items[i].icon, size: 20),
              title: Text(items[i].label, style: const TextStyle(fontSize: 13)),
              subtitle: items[i].hint.isEmpty
                  ? null
                  : Text(items[i].hint, style: const TextStyle(fontSize: 11)),
              onTap: () => Navigator.pop(ctx, i),
            ),
        ]),
      ),
    );
    if (!mounted || picked == null || picked >= items.length) return;
    items[picked].open();
  }

  /// 设备三件套：设备信息 / 机型伪装 / 设备档案。
  void _showDeviceHub() {
    _showHub(localizations.toolboxDeviceEntry, [
      (
        icon: Icons.info_outline,
        label: localizations.devTitle,
        hint: '',
        open: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (context) => const DeviceInfoPage())),
      ),
      (
        icon: Icons.phone_android,
        label: localizations.spoofTitle,
        hint: '',
        open: () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (context) => const DeviceSpoofPage()));
        },
      ),
      (
        icon: Icons.smartphone,
        label: localizations.toolboxDevice,
        hint: '',
        open: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (context) => const DeviceProfilePage())),
      ),
    ]);
  }

  /// 证书两件套：算指纹 / 校验证书链。
  void _showCertHub() {
    _showHub(localizations.toolboxCertEntry, [
      (
        icon: Icons.tag,
        label: localizations.certHashName,
        hint: '',
        open: () {
          if (Platforms.isMobile()) {
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (context) => const CertHashPage()));
            return;
          }
          MultiWindow.openWindow(localizations.certHashName, 'CertHashPage');
        },
      ),
      (
        icon: Icons.verified_outlined,
        label: localizations.toolboxCertCheck,
        hint: '',
        open: () {
          if (Platforms.isMobile()) {
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (context) => const CertCheckPage()));
            return;
          }
          MultiWindow.openWindow(localizations.toolboxCertCheck, 'CertCheckPage',
              size: const Size(720, 640));
        },
      ),
    ]);
  }


  Future<void> httpRequest() async {
    if (Platforms.isMobile()) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (context) => MobileRequestEditor(proxyServer: widget.proxyServer)));
      return;
    }

    var size = MediaQuery.of(context).size;

    MultiWindow.openWindow(localizations.httpRequest, "RequestEditor", size: Size(960, size.height));
  }

  Widget _cipherButton(String label, String algorithm, IconData icon) {
    return IconText(
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => CipherPage(initialAlgorithm: algorithm))),
      icon: icon,
      text: label,
      tooltip: localizations.cipherButtonTip(label),
    );
  }
}

class IconText extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? tooltip;

  /// 图标着色（设计稿按工具类别配色），为空时跟随 IconTheme
  final Color? color;

  /// Called when the user taps this part of the material.
  final GestureTapCallback? onTap;

  const IconText({super.key, required this.icon, required this.text, this.onTap, this.tooltip, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = text;
    return Tooltip(
      message: tooltip ?? label,
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: theme.colorScheme.primary.withValues(alpha: 0.06),
          splashColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            constraints: const BoxConstraints(minWidth: 92),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
