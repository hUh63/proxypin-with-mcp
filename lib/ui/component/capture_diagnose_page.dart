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

import 'package:flutter/material.dart';
import 'package:proxypin/native/native_method.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/crts.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/system_proxy.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:proxy_manager/proxy_manager.dart';

/// 抓包自检（上游 #890 / #860 / #896）：一页看清"为什么抓不到流量"。
///
/// 只做**只读检测 + 结论展示**，不修改系统设置；检测项包括代理服务、系统代理、
/// CA 证书、最近是否真的有流量，下面再列出最常见的几类"抓不到"及其对策。
class CaptureDiagnosePage extends StatefulWidget {
  /// 当前已抓到的请求（用于判断最近是否有流量）
  final List<HttpRequest> requests;

  const CaptureDiagnosePage({super.key, this.requests = const []});

  @override
  State<CaptureDiagnosePage> createState() => _CaptureDiagnosePageState();
}

enum _Level { ok, warn, error, info }

class _Check {
  final String title;
  final String detail;
  final _Level level;

  _Check(this.title, this.detail, this.level);
}

class _CaptureDiagnosePageState extends State<CaptureDiagnosePage> {
  bool _loading = true;
  List<_Check> _checks = [];

  @override
  void initState() {
    super.initState();
    _run();
  }

  Color _color(BuildContext context, _Level level) {
    final cs = Theme.of(context).colorScheme;
    switch (level) {
      case _Level.ok:
        return Colors.green;
      case _Level.warn:
        return Colors.orange;
      case _Level.error:
        return cs.error;
      case _Level.info:
        return cs.primary;
    }
  }

  IconData _icon(_Level level) {
    switch (level) {
      case _Level.ok:
        return Icons.check_circle_outline;
      case _Level.warn:
        return Icons.error_outline;
      case _Level.error:
        return Icons.cancel_outlined;
      case _Level.info:
        return Icons.info_outline;
    }
  }

  Future<void> _run() async {
    setState(() => _loading = true);
    final checks = <_Check>[];

    // 1. 代理服务是否在监听
    final server = ProxyServer.current;
    final running = server?.isRunning ?? false;
    checks.add(_Check(
      '代理服务',
      running ? '正在监听 127.0.0.1:${server!.port}' : '未在运行。先点「开始抓包」，再回来自检',
      running ? _Level.ok : _Level.error,
    ));

    // 2. 流量出口：桌面看系统代理，移动端由 VPN 接管
    if (Platforms.isDesktop()) {
      try {
        final proxy = await SystemProxy.getSystemProxy(ProxyTypes.http);
        final expected = server?.port ?? 0;
        final isLocal = proxy != null && (proxy.host == '127.0.0.1' || proxy.host.toLowerCase() == 'localhost');
        final matched = isLocal && proxy.port == expected;
        checks.add(_Check(
          '系统代理',
          matched
              ? '已指向本应用 ${proxy!.host}:${proxy.port}'
              : (proxy == null
                  ? '系统代理未开启。可在「偏好设置」打开系统代理，或改用其它方式让流量走代理'
                  : '当前指向 ${proxy.host}:${proxy.port}，与本应用端口 $expected 不一致（可能被其它代理工具接管，或上次异常退出未清干净）'),
          matched ? _Level.ok : _Level.warn,
        ));
      } catch (e) {
        logger.e('自检读取系统代理失败', error: e);
        checks.add(_Check('系统代理', '读取失败：$e', _Level.warn));
      }
    } else {
      checks.add(_Check('流量入口', '移动端由 VPN 通道接管 IP 层流量（无需系统代理）', _Level.info));
    }

    // 3. CA 根证书
    try {
      final caPem = await CertificateManager.certificatePem();
      if (Platforms.isMobile()) {
        final installed = await NativeMethod.isCaInstalled(caPem);
        checks.add(_Check(
          'CA 根证书',
          installed ? '已在系统信任库中' : '未检测到根证书。到「证书」页安装并在系统设置里开启完全信任，否则 HTTPS 会握手失败（感叹号包）',
          installed ? _Level.ok : _Level.error,
        ));
      } else {
        checks.add(_Check('CA 根证书', '桌面端请在「证书」页确认根证书已装入系统受信任根（Windows 需选"受信任的根证书颁发机构"）', _Level.info));
      }
    } catch (e) {
      checks.add(_Check('CA 根证书', '读取失败：$e', _Level.warn));
    }

    // 4. 最近是否真的有流量
    final requests = widget.requests;
    if (requests.isEmpty) {
      checks.add(_Check('最近流量', '本次会话还没抓到任何请求。若刚开启抓包，先在被抓的应用里操作几下', _Level.warn));
    } else {
      final latest = requests.last.requestTime;
      final seconds = DateTime.now().difference(latest).inSeconds;
      final active = seconds <= 60;
      checks.add(_Check(
        '最近流量',
        '共 ${requests.length} 条，最新一条在 ${seconds < 60 ? '$seconds 秒' : '${seconds ~/ 60} 分钟'}前'
        '${active ? '' : '。当前没有新流量进来，按下面几条逐个排查'}',
        active ? _Level.ok : _Level.warn,
      ));
    }

    if (!mounted) return;
    setState(() {
      _checks = checks;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('抓包自检'),
        actions: [
          IconButton(
            tooltip: '重新检测',
            onPressed: _loading ? null : _run,
            icon: const Icon(Icons.refresh, size: 20),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text('检查本机抓包链路是否通畅；这里只做只读检测，不会改你的系统设置。',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (final check in _checks) _buildCheck(context, check),
          const SizedBox(height: 16),
          _buildCommonCauses(context),
        ],
      ),
    );
  }

  Widget _buildCheck(BuildContext context, _Check check) {
    final color = _color(context, check.level);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon(check.level), size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(check.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(check.detail, style: const TextStyle(fontSize: 12, height: 1.45)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommonCauses(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const items = <(String, String)>[
      ('走 QUIC / HTTP3 的目标', '手机端开「拦截 QUIC」让应用回落 TCP；桌面浏览器可在 chrome://flags 里关闭 QUIC 后重试'),
      ('Flutter 应用', 'Dart 自带一份根证书列表，不读系统 CA —— 装了证书也抓不到 HTTPS。需在应用侧信任，或改抓其网络库调用'),
      ('启用了证书固定（SSL Pinning）的应用', '应用内置了证书指纹，MITM 会被拒绝，表现为成片的握手失败（感叹号包）'),
      ('Windows 上自带网络栈的进程', '系统代理管不到它们。用「偏好设置 → Windows 接管增强」，仍不行则把 ProxyPin 挂到支持 TUN 的工具下'),
      ('Mac App Store 上架的应用', '沙箱 + 强制签名，系统代理无效，需要 Network Extension/TUN（本仓未签名构建，做不了）'),
      ('只改了代理但应用不理会', '换应用自身的代理设置，或用支持 TUN 的工具统一接管'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.help_outline, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            const Text('抓不到流量？按这几条对号入座', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        for (final (title, desc) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.7), shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                      Text(desc, style: TextStyle(fontSize: 11.5, height: 1.45, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
