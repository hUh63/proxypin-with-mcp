import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/ui/component/api_endpoint_page.dart';
import 'package:proxypin/ui/component/quic_sessions_page.dart';
import 'package:proxypin/ui/component/guide_center.dart';
import 'package:proxypin/ui/component/ai_analysis.dart';
import 'package:proxypin/ui/toolbox/dev_tools.dart';
import 'package:proxypin/ui/component/multi_window.dart';
import 'package:proxypin/ui/mobile/request/request_editor.dart';
import 'package:proxypin/ui/mobile/setting/mcp_connection.dart';
import 'package:proxypin/ui/toolbox/qr_code_page.dart';
import 'package:proxypin/ui/toolbox/regexp.dart';
import 'package:proxypin/ui/toolbox/timestamp.dart';
import 'package:proxypin/ui/component/performance_dashboard.dart';
import 'package:proxypin/ui/component/log_viewer_page.dart';
import 'package:proxypin/utils/platform.dart';

import 'aes_page.dart';
import 'cert_hash.dart';
import 'encoder.dart';
import 'js_run.dart';
import 'json_viewer.dart';
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
                        MultiWindow.openWindow("JSON Viewer", 'JsonViewerPage', size: const Size(780, 820));
                      },
                      icon: Icons.data_object,
                      text: 'JSON'),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const XmlViewerPage()));
                          return;
                        }
                        MultiWindow.openWindow("XML Viewer", 'XmlViewerPage', size: const Size(900, 700));
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
                    tooltip: 'URL Encode/Decode',
                  ),
                  IconText(
                    onTap: () => encodeWindow(EncoderType.base64, context),
                    icon: Icons.format_bold_outlined,
                    text: 'Base64',
                    tooltip: 'Base64 Encode/Decode',
                  ),
                  IconText(
                    onTap: () => encodeWindow(EncoderType.unicode, context),
                    icon: Icons.format_underline_outlined,
                    text: 'Unicode',
                    tooltip: 'Unicode Encode/Decode',
                  ),
                  IconText(
                    onTap: () => encodeWindow(EncoderType.md5, context),
                    icon: Icons.tag_outlined,
                    text: 'MD5',
                    tooltip: 'MD5 Hash',
                  ),
                ],
              ),
              const Divider(thickness: 0.3),
              Text(localizations.cipher, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Wrap(
                spacing: 6,
                children: [
                  IconText(
                    onTap: () {
                      if (Platforms.isMobile()) {
                        Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AesPage()));
                        return;
                      }
                      MultiWindow.openWindow("AES", "AesPage", size: const Size(700, 672));
                    },
                    icon: Icons.enhanced_encryption_outlined,
                    text: 'AES',
                    tooltip: 'AES Encrypt/Decrypt',
                  ),
                ],
              ),
              const Divider(thickness: 0.3),
              Text(localizations.other, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
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
                      tooltip: 'MCP Server 设置'),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const PerformanceDashboard()));
                          return;
                        }
                        MultiWindow.openWindow('性能监控', 'PerformanceDashboard', size: const Size(900, 700));
                      },
                      icon: Icons.speed,
                      text: '性能监控',
                      tooltip: '性能监控仪表盘'),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          Navigator.of(context).push(MaterialPageRoute(builder: (context) => const LogViewerPage()));
                          return;
                        }
                        MultiWindow.openWindow('日志查看', 'LogViewerPage', size: const Size(900, 700));
                      },
                      icon: Icons.article_outlined,
                      text: '日志',
                      tooltip: '日志查看与过滤'),
                  IconText(
                      onTap: () {
                        // 从当前抓包数据提取 API 端点
                        final source = (widget.requestContainer ?? const <HttpRequest>[]).toList();
                        ApiEndpointUtils.showEndpoints(context, source);
                      },
                      icon: Icons.api,
                      text: 'API 端点',
                      tooltip: '从抓包数据提取 API 端点'),
                  IconText(
                      onTap: () async {
                        if (Platforms.isMobile()) {
                          await Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) => const QuicSessionsPage()));
                          return;
                        }
                        MultiWindow.openWindow('QUIC 连接', 'QuicSessionsPage',
                            size: const Size(760, 640));
                      },
                      icon: Icons.hub_outlined,
                      text: 'QUIC 连接',
                      tooltip: 'QUIC/HTTP3 连接元数据（SNI/版本/统计）'),
                  IconText(
                      onTap: () => showGuideCenter(context),
                      icon: Icons.menu_book_outlined,
                      text: '使用文档',
                      tooltip: '功能教程 / 规范文档 / 开发文档'),
                  IconText(
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => const DevToolsPage(initialIndex: 0)));
                      },
                      icon: Icons.build_circle_outlined,
                      text: '开发工具',
                      tooltip: 'Cron 表达式 / JWT 解码 / UUID / SHA 哈希'),
                  IconText(
                      onTap: () {
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const AiChatPage()));
                      },
                      icon: Icons.psychology_outlined,
                      text: 'AI 分析',
                      tooltip: 'AI 对话分析抓包数据（支持 Agent 模式）'),
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
