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
  Map<String, dynamic> toJson() => {
        'healthy': healthy,
        'summary': healthy ? '抓包链路基本就绪' : '检测到会影响抓包的问题，见 items 中的 error 项',
        'requestCount': requestCount,
        'latestRequestAgoSeconds': latestRequestAgoSeconds,
        'items': items.map((item) => item.toJson()).toList(),
        'suggestions': suggestions,
      };

  /// 根据检测结果生成可执行建议
  List<String> get suggestions {
    final list = <String>[];

    if (_find('proxy_server')?.status == DiagnoseStatus.error) {
      list.add('先启动抓包服务（调用 start_proxy 工具，或让用户在界面上点「开始抓包」）');
    }
    if (_find('certificate')?.status == DiagnoseStatus.error) {
      list.add('安装并信任根证书：HTTPS 未信任时会成片出现握手失败（列表里的感叹号包）');
    }
    if (_find('system_proxy')?.status == DiagnoseStatus.warn) {
      list.add('系统代理没有指向本应用：让用户在「偏好设置」打开系统代理，或确认是否被其它代理工具接管');
    }
    if (_find('ssl_pinning')?.status == DiagnoseStatus.warn) {
      list.add('存在疑似证书固定的域名：这类应用需要在设备上做运行时干预才能解密，'
          '常见做法是靠 hook 框架（如 LSPosed 配合 TrustMeAlready 这类模块）。'
          '请注意这属于对目标应用的干预，只应在你自己的设备、且在你拥有授权的范围内使用');
    }
    if ((_find('traffic')?.status ?? DiagnoseStatus.ok) == DiagnoseStatus.warn) {
      list.add('当前没有新流量：先在被抓的应用/浏览器里发起一次请求，再让 AI 读取会话列表');
    }

    // 常见"抓不到"的静态排查清单（对应平台限制与客户端特性）
    list.add('若以上都正常仍抓不到，按这几类排查：'
        '① 目标走 QUIC/HTTP3（手机开「拦截 QUIC」、浏览器关 QUIC）；'
        '② Flutter 应用（Dart 自带根证书列表，不读系统 CA）；'
        '③ 应用启用了证书固定（SSL Pinning）—— 若上方出现「SSL 证书固定（疑似）」项即命中；'
        '④ Windows 上自带网络栈的进程（需「Windows 接管增强」或 TUN 类工具）；'
        '⑤ Mac App Store 沙箱应用（需 Network Extension/TUN，本仓未签名构建无法接管）');

    return list;
  }
}

class CaptureDiagnose {
  /// 执行检测；[requests] 传入当前会话已抓到的请求（可为空）
  static Future<CaptureDiagnoseResult> run(List<HttpRequest> requests) async {
    final items = <DiagnoseItem>[];

    // 1. 代理服务
    final server = ProxyServer.current;
    final running = server?.isRunning ?? false;
    items.add(DiagnoseItem(
      key: 'proxy_server',
      title: '代理服务',
      status: running ? DiagnoseStatus.ok : DiagnoseStatus.error,
      detail: running
          ? '正在监听 127.0.0.1:${server!.port}'
          : '未在运行，抓不到任何流量。先点「开始抓包」',
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
          title: '系统代理',
          status: matched ? DiagnoseStatus.ok : DiagnoseStatus.warn,
          detail: matched
              ? '已指向本应用 ${proxy!.host}:${proxy.port}'
              : (proxy == null
                  ? '系统代理未开启，应用流量不会经过本工具'
                  : '指向 ${proxy.host}:${proxy.port}，与本应用端口 $expected 不一致（可能被其它代理工具接管，或上次异常退出残留）'),
        ));
      } catch (e) {
        items.add(DiagnoseItem(
          key: 'system_proxy',
          title: '系统代理',
          status: DiagnoseStatus.warn,
          detail: '读取失败：$e',
        ));
      }
    } else {
      items.add(DiagnoseItem(
        key: 'system_proxy',
        title: '流量入口',
        status: DiagnoseStatus.info,
        detail: '移动端由 VPN 通道接管 IP 层流量（无需系统代理）',
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
          detail = '已在系统信任库中';
        } else if (scope == 'user') {
          ok = false;
          detail = '只在「用户证书库」：Android 7 起应用默认不信任用户证书，'
              '所以会出现“证书装了但 HTTPS 抓不到或报错”。'
              '要全应用生效需 root 装进系统证书目录'
              '（Android 14+ 是 /apex/com.android.conscrypt/cacerts），'
              '或给目标 App 配 network_security_config';
        } else {
          final installed = await NativeMethod.isCaInstalled(caPem);
          ok = installed;
          detail = installed
              ? '已安装（未能区分系统库/用户库）'
              : (Platforms.isAndroid()
                  ? '未检测到根证书：去「HTTPS 证书 → 安装根证书」按引导安装；'
                      '安装时请选「CA 证书」而不是「VPN 和应用证书」'
                  : '未检测到根证书，HTTPS 会握手失败（列表里表现为成片的感叹号包）');
        }
        items.add(DiagnoseItem(
          key: 'certificate',
          title: 'CA 根证书',
          status: ok ? DiagnoseStatus.ok : DiagnoseStatus.error,
          detail: detail,
        ));
      } else {
        items.add(DiagnoseItem(
          key: 'certificate',
          title: 'CA 根证书',
          status: DiagnoseStatus.info,
          detail: '桌面端请在「证书」页确认根证书已装入系统受信任根',
        ));
      }
    } catch (e) {
      logger.e('自检读取证书失败', error: e);
      items.add(DiagnoseItem(
        key: 'certificate',
        title: 'CA 根证书',
        status: DiagnoseStatus.warn,
        detail: '读取失败：$e',
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
        title: 'SSL 证书固定（疑似）',
        status: DiagnoseStatus.warn,
        detail: 'CA 证书已就绪，但有 ${connectOnlyHosts.length} 个域名只建立了 TLS 隧道、'
            '内容始终读不到：$sample。'
            '这通常意味着对方启用了证书固定（SSL Pinning），或自带根证书列表不读系统 CA。'
            '注意这类应用并不是"没网络"——它拒绝了本工具的证书，所以主动断开了连接。',
      ));
    }

    // 3.5 Windows 增强接管（上游 #577 / #896）
    // 这个功能一直都存在，但默认关闭、入口又深，导致"某些进程抓不到"的用户
    // 根本不知道可以打开它 —— 所以在自检里直接点出来。
    if (Platform.isWindows) {
      final takeoverOn = Configuration.loaded?.winTakeoverEnabled ?? false;
      items.add(DiagnoseItem(
        key: 'win_takeover',
        title: 'Windows 增强接管',
        status: takeoverOn ? DiagnoseStatus.ok : DiagnoseStatus.info,
        detail: takeoverOn
            ? '已开启：WinHTTP 服务、CLI 工具（curl/git/node）等也会走代理'
            : '未开启：自带网络栈的应用、WinHTTP 服务与 CLI 工具可能抓不到。'
                '可在「偏好设置 → Windows 接管」打开（WinHTTP 部分需要管理员权限）',
      ));
    }

    // 4. 最近流量
    int? agoSeconds;
    if (requests.isNotEmpty) {
      agoSeconds = DateTime.now().difference(requests.last.requestTime).inSeconds;
    }
    items.add(DiagnoseItem(
      key: 'traffic',
      title: '最近流量',
      status: (agoSeconds != null && agoSeconds <= 60) ? DiagnoseStatus.ok : DiagnoseStatus.warn,
      detail: agoSeconds == null
          ? '本次会话还没有抓到任何请求'
          : (agoSeconds <= 60
              ? '共 ${requests.length} 条，最新一条在 $agoSeconds 秒前'
              : '共 ${requests.length} 条，最新一条在 $agoSeconds 秒前（当前没有新流量进来）'),
    ));

    // 5. VPN 扩展内存水位（仅 iOS，上游 #903）
    //    扩展是独立进程、有独立内存上限，超限会被系统杀掉（现象：网络全断 + 小窗消失）。
    if (Platforms.isIOS()) {
      final memory = await Vpn.vpnMemory();
      if (memory == null) {
        items.add(DiagnoseItem(
          key: 'extension_memory',
          title: '扩展内存',
          status: DiagnoseStatus.info,
          detail: '未取到（VPN 未启动时读不到扩展进程）',
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
          title: '扩展内存',
          status: nearLimit ? DiagnoseStatus.warn : DiagnoseStatus.ok,
          detail: '当前 $rssMb MB，峰值 $peakMb MB，连接 $connections 条，待发缓冲 $bufferedMb MB'
              '${nearLimit ? '（已接近扩展内存上限，建议降低并发或缩小待发缓冲上限）' : ''}',
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
