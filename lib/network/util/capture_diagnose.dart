/*
 * Copyright 2025 Hongen Wang All rights reserved.
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

import 'dart:io';

import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/native/native_method.dart';
import 'package:proxypin/native/vpn.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/crts.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/system_proxy.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:proxy_manager/proxy_manager.dart';

/// 抓包链路只读自检（上游 #890 / #860 / #896）。
///
/// 同时供两个入口使用：
/// - UI：`lib/ui/component/capture_diagnose_page.dart`
/// - MCP：`diagnose_capture` 工具（让 AI 先拿到结论再给建议）
///
/// 本类**只读取状态**，不修改系统代理、不写配置。

enum DiagnoseStatus { ok, warn, error, info }

class DiagnoseItem {
  final String key;
  final String title;
  final String detail;
  final DiagnoseStatus status;

  DiagnoseItem({required this.key, required this.title, required this.detail, required this.status});

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title,
        'status': status.name,
        'detail': detail,
      };
}

class CaptureDiagnoseResult {
  final List<DiagnoseItem> items;

  /// 当前会话已抓到的请求数
  final int requestCount;

  /// 最新一条请求距今多少秒（无请求时为 null）
  final int? latestRequestAgoSeconds;

  CaptureDiagnoseResult(this.items, {required this.requestCount, this.latestRequestAgoSeconds});

  bool get healthy => items.every((item) => item.status != DiagnoseStatus.error);

  DiagnoseItem? _find(String key) {
    for (final item in items) {
      if (item.key == key) return item;
    }
    return null;
  }

  /// 可直接交给 LLM 的结构化结论
  Map<String, dynamic> toJson(AppLocalizations loc) => {
        'healthy': healthy,
        'summary': healthy ? loc.diagSummaryOk : loc.diagSummaryIssues,
        'requestCount': requestCount,
        'latestRequestAgoSeconds': latestRequestAgoSeconds,
        'items': items.map((item) => item.toJson()).toList(),
        'suggestions': suggestions(loc),
      };

  /// 根据检测结果生成可执行建议
  List<String> suggestions(AppLocalizations loc) {
    final list = <String>[];

    if (_find('proxy_server')?.status == DiagnoseStatus.error) {
      list.add(loc.diagSuggestStartProxy);
    }
    if (_find('certificate')?.status == DiagnoseStatus.error) {
      list.add(loc.diagSuggestInstallCert);
    }
    if (_find('system_proxy')?.status == DiagnoseStatus.warn) {
      list.add(loc.diagSuggestSystemProxy);
    }
    if (_find('ssl_pinning')?.status == DiagnoseStatus.warn) {
      list.add(loc.diagSuggestPinning);
    }
    if ((_find('traffic')?.status ?? DiagnoseStatus.ok) == DiagnoseStatus.warn) {
      list.add(loc.diagSuggestNoTraffic);
    }

    // 常见"抓不到"的静态排查清单（对应平台限制与客户端特性）
    list.add(loc.diagSuggestChecklist);

    return list;
  }
}

class CaptureDiagnose {
  /// 执行检测；[requests] 传入当前会话已抓到的请求（可为空）
  static Future<CaptureDiagnoseResult> run(List<HttpRequest> requests, AppLocalizations loc) async {
    final items = <DiagnoseItem>[];

    // 1. 代理服务
    final server = ProxyServer.current;
    final running = server?.isRunning ?? false;
    items.add(DiagnoseItem(
      key: 'proxy_server',
      title: loc.diagItemProxyService,
      status: running ? DiagnoseStatus.ok : DiagnoseStatus.error,
      detail: running ? loc.diagProxyListening(server!.port) : loc.diagProxyNotRunning,
    ));

    // 2. 流量入口
    if (Platforms.isDesktop()) {
      try {
        final proxy = await SystemProxy.getSystemProxy(ProxyTypes.http);
        final expected = server?.port ?? 0;
        final isLocal =
            proxy != null && (proxy.host == '127.0.0.1' || proxy.host.toLowerCase() == 'localhost');
        final matched = isLocal && proxy.port == expected;
        items.add(DiagnoseItem(
          key: 'system_proxy',
          title: loc.diagItemSystemProxy,
          status: matched ? DiagnoseStatus.ok : DiagnoseStatus.warn,
          detail: matched
              ? loc.diagSystemProxyMatched(proxy!.host, proxy.port)
              : (proxy == null
                  ? loc.diagSystemProxyOff
                  : loc.diagSystemProxyMismatch(proxy.host, proxy.port, expected)),
        ));
      } catch (e) {
        items.add(DiagnoseItem(
          key: 'system_proxy',
          title: loc.diagItemSystemProxy,
          status: DiagnoseStatus.warn,
          detail: loc.diagReadFailed('$e'),
        ));
      }
    } else {
      items.add(DiagnoseItem(
        key: 'system_proxy',
        title: loc.diagItemTrafficEntry,
        status: DiagnoseStatus.info,
        detail: loc.diagMobileVpnEntry,
      ));
    }

    // 3. CA 根证书
    try {
      final caPem = await CertificateManager.certificatePem();
      if (Platforms.isMobile()) {
        // 上游 #200/#652/#728/#741：安卓上“装了证书却抓不到 HTTPS”多半是装进了用户库，
        // 所以这里把安装位置也测出来，直接把原因归属说清楚
        final scope = Platforms.isAndroid() ? await NativeMethod.caInstallScope(caPem) : 'unknown';
        String detail;
        bool ok;
        if (scope == 'system') {
          ok = true;
          detail = loc.diagCaInSystemStore;
        } else if (scope == 'user') {
          ok = false;
          detail = loc.diagCaUserStore;
        } else {
          final installed = await NativeMethod.isCaInstalled(caPem);
          ok = installed;
          detail = installed
              ? loc.diagCaInstalledUnknown
              : (Platforms.isAndroid() ? loc.diagCaMissingAndroid : loc.diagCaMissingDesktop);
        }
        items.add(DiagnoseItem(
          key: 'certificate',
          title: loc.diagItemCaRoot,
          status: ok ? DiagnoseStatus.ok : DiagnoseStatus.error,
          detail: detail,
        ));
      } else {
        items.add(DiagnoseItem(
          key: 'certificate',
          title: loc.diagItemCaRoot,
          status: DiagnoseStatus.info,
          detail: loc.diagCaDesktopHint,
        ));
      }
    } catch (e) {
      logger.e('自检读取证书失败', error: e);
      items.add(DiagnoseItem(
        key: 'certificate',
        title: loc.diagItemCaRoot,
        status: DiagnoseStatus.warn,
        detail: loc.diagReadFailed('$e'),
      ));
    }

    // 3.4 SSL 证书固定（疑似）
    // 判据：某个域名只出现在 CONNECT 隧道里，从来没有一条解密后的 HTTPS 请求，
    // 而 CA 又是正确安装的。「隧道通、内容读不到」这个组合最常见的原因就是
    // 应用内置了证书固定（SSL Pinning），或者应用自带根证书列表、根本不读系统 CA。
    // 这类应用通常表现为"打开就提示无网络/连接失败"，容易被误判成代理配错了。
    var certReady = false;
    for (final item in items) {
      if (item.key == 'certificate' && item.status == DiagnoseStatus.ok) {
        certReady = true;
        break;
      }
    }
    final connectOnlyHosts = _connectOnlyHosts(requests);
    if (certReady && connectOnlyHosts.isNotEmpty) {
      final sample = connectOnlyHosts.take(5).join('、');
      items.add(DiagnoseItem(
        key: 'ssl_pinning',
        title: loc.diagItemSslPinning,
        status: DiagnoseStatus.warn,
        detail: loc.diagSslPinningDetail(connectOnlyHosts.length, sample),
      ));
    }

    // 3.5 Windows 增强接管（上游 #577 / #896）
    // 这个功能一直都存在，但默认关闭、入口又深，导致"某些进程抓不到"的用户
    // 根本不知道可以打开它 —— 所以在自检里直接点出来。
    if (Platform.isWindows) {
      final takeoverOn = Configuration.loaded?.winTakeoverEnabled ?? false;
      items.add(DiagnoseItem(
        key: 'win_takeover',
        title: loc.diagItemWinTakeover,
        status: takeoverOn ? DiagnoseStatus.ok : DiagnoseStatus.info,
        detail: takeoverOn ? loc.diagWinTakeoverOn : loc.diagWinTakeoverOff,
      ));
    }

    // 4. 最近流量
    int? agoSeconds;
    if (requests.isNotEmpty) {
      agoSeconds = DateTime.now().difference(requests.last.requestTime).inSeconds;
    }
    items.add(DiagnoseItem(
      key: 'traffic',
      title: loc.diagItemRecentTraffic,
      status: (agoSeconds != null && agoSeconds <= 60) ? DiagnoseStatus.ok : DiagnoseStatus.warn,
      detail: agoSeconds == null
          ? loc.diagNoRequests
          : (agoSeconds <= 60
              ? loc.diagTrafficFresh(requests.length, agoSeconds)
              : loc.diagTrafficStale(requests.length, agoSeconds)),
    ));

    // 5. VPN 扩展内存水位（仅 iOS，上游 #903）
    //    扩展是独立进程、有独立内存上限，超限会被系统杀掉（现象：网络全断 + 小窗消失）。
    if (Platforms.isIOS()) {
      final memory = await Vpn.vpnMemory();
      if (memory == null) {
        items.add(DiagnoseItem(
          key: 'extension_memory',
          title: loc.diagItemExtensionMemory,
          status: DiagnoseStatus.info,
          detail: loc.diagExtMemUnavailable,
        ));
      } else {
        final rssMb = _toMb(memory['rssBytes']);
        final peakMb = _toMb(memory['peakBytes']);
        final bufferedMb = _toMb(memory['bufferedBytes']);
        final connections = memory['connections'] ?? 0;
        // iOS 给网络扩展的内存上限量级在 50MB，接近就该预警（用数值比较，不能用格式化后的字符串）
        final nearLimit = _megaBytes(memory['peakBytes']) >= 45;
        items.add(DiagnoseItem(
          key: 'extension_memory',
          title: loc.diagItemExtensionMemory,
          status: nearLimit ? DiagnoseStatus.warn : DiagnoseStatus.ok,
          detail: loc.diagExtMemDetail(rssMb, peakMb, '$connections', bufferedMb) +
              (nearLimit ? loc.diagExtMemNearLimit : ''),
        ));
      }
    }

    return CaptureDiagnoseResult(items, requestCount: requests.length, latestRequestAgoSeconds: agoSeconds);
  }

  /// 只建立了 CONNECT 隧道、却没有任何解密后请求的域名。
  ///
  /// 只看这两个集合的差集：出现过解密请求的域名即使也建过隧道，也不算嫌疑
  /// （那说明解密是成功的）。宁可漏报也不误报。
  static List<String> _connectOnlyHosts(List<HttpRequest> requests) {
    final tunnelHosts = <String>{};
    final decryptedHosts = <String>{};
    for (final request in requests) {
      final host = request.hostAndPort?.host?.toLowerCase();
      if (host == null || host.isEmpty) continue;
      if (request.method == HttpMethod.connect) {
        tunnelHosts.add(host);
      } else {
        final url = request.requestUrl;
        if (url != null && url.toLowerCase().startsWith('https://')) {
          decryptedHosts.add(host);
        }
      }
    }
    final only = tunnelHosts.difference(decryptedHosts).toList()..sort();
    return only;
  }

  static double _megaBytes(dynamic bytes) {
    final value = bytes is num ? bytes.toDouble() : 0.0;
    return value / 1048576;
  }

  static String _toMb(dynamic bytes) => _megaBytes(bytes).toStringAsFixed(1);
}
