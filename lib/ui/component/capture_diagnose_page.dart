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

import 'package:flutter/material.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/capture_diagnose.dart';

/// 抓包自检（上游 #890 / #860 / #896）：一页看清"为什么抓不到流量"。
///
/// 检测逻辑在 `lib/network/util/capture_diagnose.dart`，同一份结论也通过 MCP 的
/// `diagnose_capture` 工具暴露给 AI，界面这边只负责展示。
class CaptureDiagnosePage extends StatefulWidget {
  /// 当前已抓到的请求（用于判断最近是否有流量）
  final List<HttpRequest> requests;

  const CaptureDiagnosePage({super.key, this.requests = const []});

  @override
  State<CaptureDiagnosePage> createState() => _CaptureDiagnosePageState();
}

class _CaptureDiagnosePageState extends State<CaptureDiagnosePage> {
  bool _loading = true;
  CaptureDiagnoseResult? _result;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _loading = true);
    final result = await CaptureDiagnose.run(widget.requests);
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  Color _color(BuildContext context, DiagnoseStatus status) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case DiagnoseStatus.ok:
        return Colors.green;
      case DiagnoseStatus.warn:
        return Colors.orange;
      case DiagnoseStatus.error:
        return cs.error;
      case DiagnoseStatus.info:
        return cs.primary;
    }
  }

  IconData _icon(DiagnoseStatus status) {
    switch (status) {
      case DiagnoseStatus.ok:
        return Icons.check_circle_outline;
      case DiagnoseStatus.warn:
        return Icons.error_outline;
      case DiagnoseStatus.error:
        return Icons.cancel_outlined;
      case DiagnoseStatus.info:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final result = _result;
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
                child: Text('检查本机抓包链路是否通畅；只做只读检测，不会改你的系统设置。'
                    '同样的结论也能通过 MCP 工具 diagnose_capture 交给 AI。',
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
          else if (result != null) ...[
            for (final item in result.items) _buildItem(context, item),
            if (!result.healthy) ...[
              const SizedBox(height: 4),
              _buildSuggestions(context, result),
            ],
          ],
          const SizedBox(height: 16),
          _buildCommonCauses(context),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, DiagnoseItem item) {
    final color = _color(context, item.status);
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
            Icon(_icon(item.status), size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(item.detail, style: const TextStyle(fontSize: 12, height: 1.45)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestions(BuildContext context, CaptureDiagnoseResult result) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('先做这几步', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final tip in result.suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('· $tip', style: const TextStyle(fontSize: 12, height: 1.45)),
            ),
        ],
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
