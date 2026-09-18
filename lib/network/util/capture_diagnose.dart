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

import 'package:proxypin/native/native_method.dart';
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
    if ((_find('traffic')?.status ?? DiagnoseStatus.ok) == DiagnoseStatus.warn) {
      list.add('当前没有新流量：先在被抓的应用/浏览器里发起一次请求，再让 AI 读取会话列表');
    }

    // 常见"抓不到"的静态排查清单（对应平台限制与客户端特性）
    list.add('若以上都正常仍抓不到，按这几类排查：'
        '① 目标走 QUIC/HTTP3（手机开「拦截 QUIC」、浏览器关 QUIC）；'
        '② Flutter 应用（Dart 自带根证书列表，不读系统 CA）；'
        '③ 应用启用了证书固定（SSL Pinning）；'
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
        final installed = await NativeMethod.isCaInstalled(caPem);
        items.add(DiagnoseItem(
          key: 'certificate',
          title: 'CA 根证书',
          status: installed ? DiagnoseStatus.ok : DiagnoseStatus.error,
          detail: installed
              ? '已在系统信任库中'
              : '未检测到根证书，HTTPS 会握手失败（列表里表现为成片的感叹号包）',
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

    // 4. 最近流量
    int? agoSeconds;
    if (requests.isNotEmpty) {
      agoSeconds = DateTime.now().difference(requests.last.requestTime).inSeconds;
    }
    items.add(DiagnoseItem(
      key: 'traffic',
      title: '最近流量',
      status: (agoSeconds != null && agoSeconds <= 60) ? DiagnoseStatus.ok : DiagnoseStatus.warn,
      detail: requests.isEmpty
          ? '本次会话还没有抓到任何请求'
          : '共 ${requests.length} 条，最新一条在 $agoSeconds 秒前'
              '${agoSeconds <= 60 ? '' : '（当前没有新流量进来）'}',
    ));

    return CaptureDiagnoseResult(items, requestCount: requests.length, latestRequestAgoSeconds: agoSeconds);
  }
}
