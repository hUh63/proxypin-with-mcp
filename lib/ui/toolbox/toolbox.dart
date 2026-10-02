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
import 'package:proxypin/ui/component/repeat_queue_page.dart';
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
import 'package:proxypin/ui/component/performance_dashboard.dart';
import 'package:proxypin/ui/component/log_viewer_page.dart';
import 'package:proxypin/utils/platform.dart';

import 'cert_hash.dart';
import 'cipher_page.dart';
import 'encoder.dart';
import 'hash_page.dart';
import 'rsa_page.dart';
import 'js_run.dart';
import 'json_viewer.dart';
import 'network_diagnostics.dart';
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

  @override
  Widget build(BuildContext context) {
    return IconTheme(
        data: IconTheme.of(context).copyWith(color: IconTheme.of(context).color?.withValues(alpha: 0.65), size: 22),
        child: SingleChildScrollView(
            child: Container(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top quick actions
              Wrap(
                spacing: 6,
                children: [
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
                    icon: Icons.calculate_outlined,
                    text: localizations.calcTitle,
                    tooltip: localizations.toolboxNavCalcTip,
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) => const CalculatorPage()));
                    },
                  ),
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
                ],
              ),
              const Divider(thickness: 0.3),
              Text(localizations.view, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Wrap(
                spacing: 6,
                children: [
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
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TextEditorPage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.textEditor, 'TextEditorPage', size: const Size(900, 800));
                      },
                      icon: Icons.note_alt_outlined,
                      text: localizations.textEditor,
                      tooltip: localizations.textEditor),
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
                ],
              ),
              const Divider(thickness: 0.3),
              Text(localizations.encode, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Wrap(
                spacing: 6,
                children: [
                  IconText(
                    onTap: () => encodeWindow(EncoderType.url, context),
                    icon: Icons.link,
                    text: 'URL',
                    tooltip: localizations.toolboxEncodeUrlTip,
                  ),
                  IconText(
                    onTap: () => encodeWindow(EncoderType.base64, context),
                    icon: Icons.format_bold_outlined,
                    text: 'Base64',
                    tooltip: localizations.toolboxEncodeBase64Tip,
                  ),
                  IconText(
                    onTap: () => encodeWindow(EncoderType.unicode, context),
                    icon: Icons.format_underline_outlined,
                    text: 'Unicode',
                    tooltip: localizations.toolboxEncodeUnicodeTip,
                  ),
                  IconText(
                    onTap: () => encodeWindow(EncoderType.base32, context),
                    icon: Icons.text_fields,
                    text: 'Base32',
                    tooltip: localizations.toolboxEncodeBase32Tip,
                  ),
                  IconText(
                    onTap: () => encodeWindow(EncoderType.hex, context),
                    icon: Icons.numbers,
                    text: 'Hex',
                    tooltip: localizations.toolboxEncodeHexTip,
                  ),
                  IconText(
                    onTap: () => encodeWindow(EncoderType.html, context),
                    icon: Icons.html,
                    text: 'HTML',
                    tooltip: localizations.toolboxEncodeHtmlTip,
                  ),
                  IconText(
                    onTap: () => encodeWindow(EncoderType.gzip, context),
                    icon: Icons.archive_outlined,
                    text: 'GZip',
                    tooltip: localizations.toolboxEncodeGzipTip,
                  ),
                  IconText(
                    onTap: () => encodeWindow(EncoderType.deflate, context),
                    icon: Icons.compress,
                    text: 'Deflate',
                    tooltip: localizations.toolboxEncodeDeflateTip,
                  ),
                  IconText(
                    onTap: () => encodeWindow(EncoderType.urlParams, context),
                    icon: Icons.manage_search,
                    text: localizations.toolboxUrlParams,
                    tooltip: localizations.toolboxUrlParamsTip,
                  ),
                  IconText(
                    onTap: () => encodeWindow(EncoderType.md5, context),
                    icon: Icons.tag_outlined,
                    text: 'MD5',
                    tooltip: localizations.toolboxMd5Tip,
                  ),
                ],
              ),
              const Divider(thickness: 0.3),
              Text(localizations.cipher, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Wrap(
                spacing: 6,
                children: [
                  _cipherButton('AES', 'AES', Icons.enhanced_encryption_outlined),
                  _cipherButton('DES', 'DES', Icons.lock_outline),
                  _cipherButton('3DES', '3DES', Icons.lock_reset),
                  _cipherButton('SM4', 'SM4', Icons.verified_user_outlined),
                  _cipherButton('ChaCha20', 'ChaCha20', Icons.vpn_key_outlined),
                  _cipherButton('XOR', 'XOR', Icons.exposure_outlined),
                  IconText(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (context) => const RsaPage())),
                    icon: Icons.security_outlined,
                    text: 'RSA',
                    tooltip: localizations.toolboxRsaTip,
                  ),
                ],
              ),
              const Divider(thickness: 0.3),
              Text(localizations.toolboxHash, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Wrap(
                spacing: 6,
                children: [
                  IconText(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (context) => const HashPage(initialIndex: 0))),
                    icon: Icons.fingerprint,
                    text: 'Hash',
                    tooltip: localizations.toolboxHashTip,
                  ),
                  IconText(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (context) => const HashPage(initialIndex: 1))),
                    icon: Icons.key_outlined,
                    text: 'HMAC',
                    tooltip: 'HMAC',
                  ),
                  IconText(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (context) => const HashPage(initialIndex: 2))),
                    icon: Icons.password,
                    text: 'Bcrypt',
                    tooltip: localizations.toolboxBcryptTip,
                  ),
                ],
              ),
              const Divider(thickness: 0.3),
              Text(localizations.toolboxGroupUtilities, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Wrap(
                spacing: 6,
                children: [
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
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const CertHashPage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.certHashName, 'CertHashPage');
                      },
                      icon: Icons.key_outlined,
                      text: localizations.certHashName,
                      tooltip: localizations.certHashName),
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
                ],
              ),
              const Divider(thickness: 0.3),
              Text(localizations.toolboxGroupRuntime, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Wrap(
                spacing: 6,
                children: [
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
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const LogViewerPage()));
                          return;
                        }
                        MultiWindow.openWindow(localizations.toolboxNavLogView, 'LogViewerPage', size: const Size(900, 700));
                      },
                      icon: Icons.article_outlined,
                      text: localizations.toolboxLog,
                      tooltip: localizations.toolboxLogTip),
                ],
              ),
              const Divider(thickness: 0.3),
              Text(localizations.toolboxGroupCapture, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Wrap(
                spacing: 6,
                children: [
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
                        // 从当前抓包数据提取 API 端点
                        final source = (widget.requestContainer ?? const <HttpRequest>[]).toList();
                        ApiEndpointUtils.showEndpoints(context, source);
                      },
                      icon: Icons.api,
                      text: localizations.toolboxApiEndpoints,
                      tooltip: localizations.toolboxApiEndpointsTip),
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
                      onTap: () {
                        // 抓包自检：只读检测代理/证书/流量状态，并列出常见抓不到的原因
                        final source = (widget.requestContainer ?? const <HttpRequest>[]).toList();
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => CaptureDiagnosePage(requests: source)));
                      },
                      icon: Icons.fact_check_outlined,
                      text: localizations.captureDiagnose,
                      tooltip: localizations.captureDiagnoseTip),
                  IconText(
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (context) => const PinningPage())),
                      icon: Icons.lock_open_outlined,
                      text: localizations.toolboxSslPinning,
                      tooltip: localizations.toolboxNavPinningTip),
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
                ],
              ),
              const Divider(thickness: 0.3),
              Text(localizations.other, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Wrap(
                spacing: 6,
                children: [
                  IconText(
                      onTap: () => showGuideCenter(context),
                      icon: Icons.menu_book_outlined,
                      text: localizations.toolboxDocs,
                      tooltip: localizations.toolboxDocsTip),
                  IconText(
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => const DevToolsPage(initialIndex: 0)));
                      },
                      icon: Icons.build_circle_outlined,
                      text: localizations.toolboxDevTools,
                      tooltip: localizations.toolboxDevToolsTip),
                  IconText(
                      onTap: () {
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const AiChatPage()));
                      },
                      icon: Icons.psychology_outlined,
                      text: localizations.aiTitle,
                      tooltip: localizations.toolboxNavAiTip),
                ],
              ),
            ],
          ),
        )));
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

  /// Called when the user taps this part of the material.
  final GestureTapCallback? onTap;

  const IconText({super.key, required this.icon, required this.text, this.onTap, this.tooltip});

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
                Icon(icon),
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
