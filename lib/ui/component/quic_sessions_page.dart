/*
 * QUIC 连接元数据页（上游 #489）
 * VPN 抓包运行时，ProxyVpnService 把 UDP:443 首包抄送本机，QuicProbe 解密
 * QUIC v1 Initial 后在此展示：SNI 域名 / QUIC 版本 / 连接 ID / 包与帧统计。
 */
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/util/quic/quic_1rtt.dart';
import 'package:proxypin/network/util/quic/quic_keylog.dart';
import 'package:proxypin/network/util/quic/quic_probe.dart';

class QuicSessionsPage extends StatelessWidget {
  const QuicSessionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('QUIC 连接',
            style: TextStyle(fontSize: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.key_outlined, size: 20),
            tooltip: '导入密钥日志（SSLKEYLOGFILE）后即可解密 1-RTT 流数据',
            onPressed: () => _importKeylog(context),
          ),
          IconButton(
            icon: const Icon(Icons.copy_all_outlined, size: 20),
            tooltip: '复制会话列表（制表符分隔，可直接贴进表格）',
            onPressed: () async {
              final sessions = QuicProbe.instance.sessions
                ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
              if (sessions.isEmpty) return;
              final text = sessions
                  .map((s) => '${s.host.isEmpty ? '(无SNI)' : s.host}\t${s.version}\t${s.remote}\t'
                      '${s.packets}包 / ${_humanBytes(s.bytes)}\t最后活动 ${_time(s.lastSeen)}')
                  .join('\n');
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                FlutterToastr.show('已复制 ${sessions.length} 条会话记录', context, duration: 2);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: '刷新（等待新的 QUIC 包到达）',
            onPressed: () => QuicProbe.instance.revision.value++,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 20),
            tooltip: '清空记录',
            onPressed: () => QuicProbe.instance.clear(),
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: QuicProbe.instance.revision,
        builder: (context, _, __) {
          final sessions = QuicProbe.instance.sessions
            ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen)); // 最近活动优先
          if (sessions.isEmpty) {
            return _empty(cs, context);
          }
          return Column(children: [
            // 顶部提示条：诚实说明能力边界
            Container(
              width: double.infinity,
              color: cs.tertiaryContainer.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                QuicKeylogStore.instance.isEmpty
                    ? '仅展示 QUIC 连接级元数据（哪些域名在走 QUIC、连接统计）。'
                        'HTTP/3 内容受 TLS 1.3 加密，默认无法解为明文；'
                        '点右上角「钥匙」导入密钥日志（SSLKEYLOGFILE）后，命中的连接会自动解密 1-RTT 流数据；'
                        '或开启「拦截 QUIC」强制定向 TCP 抓取完整请求。'
                    : '已导入 ${QuicKeylogStore.instance.entryCount} 条密钥（覆盖 '
                        '${QuicKeylogStore.instance.connectionCount} 个连接）。'
                        '命中连接自动解密 1-RTT（仅客户端方向；HEADERS 按 QPACK 解码，含动态表）。'
                        '未命中的连接请开启「拦截 QUIC」回落 TCP 抓取。',
                style: TextStyle(
                    fontSize: 11, color: cs.onTertiaryContainer, height: 1.4),
              ),
            ),
            _buildSummary(context, sessions),
            _buildTimeline(context),
            Expanded(
              child: ListView.builder(
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final s = sessions[index];
                  return ListTile(
                    dense: true,
                    leading: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.hub_outlined,
                          size: 18, color: cs.onPrimaryContainer),
                    ),
                    title: Text(
                      s.host.isNotEmpty ? s.host : '（未解出 SNI）',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            s.host.isNotEmpty ? FontWeight.w600 : FontWeight.w400,
                        color: s.host.isNotEmpty
                            ? cs.onSurface
                            : cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      'QUIC ${s.version} · ${s.remote} · 首见 ${_time(s.firstSeen)} · 最后活动 ${_ago(s.lastSeen)}\n'
                      '连接 ${s.dcid.length >= 6 ? s.dcid.substring(0, 6) : s.dcid}… · '
                      '${s.packets} 包 / ${s.frames} 帧 · ${_humanBytes(s.bytes)}'
                      '${s.decrypted.isNotEmpty ? ' · 已解密 ${s.decrypted.length} 段' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        color: s.decrypted.isNotEmpty ? Colors.green.shade700 : cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    isThreeLine: true,
                    onTap: s.decrypted.isEmpty ? null : () => _showDecrypted(context, s),
                    trailing: s.decrypted.isEmpty
                        ? null
                        : Icon(Icons.lock_open_outlined, size: 16, color: Colors.green.shade600),
                  );
                },
              ),
            ),
          ]);
        },
      ),
    );
  }

  /// 时间轴：最近 10 分钟、每 10 秒一格的 QUIC 包量柱状图（旧 → 新）
  Widget _buildTimeline(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final packets = QuicProbe.instance.timelinePackets();
    final bytes = QuicProbe.instance.timelineBytes();
    final maxValue = packets.fold<int>(0, (max, v) => v > max ? v : max);
    final total = packets.fold<int>(0, (sum, v) => sum + v);
    final totalBytes = bytes.fold<int>(0, (sum, v) => sum + v);
    final activeBuckets = packets.where((v) => v > 0).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('最近 10 分钟 QUIC 包量', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const Spacer(),
              Text(
                activeBuckets == 0
                    ? '暂无数据'
                    : '共 $total 包 · ${_humanBytes(totalBytes)} · $activeBuckets 段有流量',
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 54,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final value in packets)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0.5),
                      child: Container(
                        height: maxValue == 0 ? 2 : (value / maxValue * 52).clamp(2.0, 52.0),
                        decoration: BoxDecoration(
                          color: value > 0 ? cs.primary : cs.outlineVariant.withValues(alpha: 0.35),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('10 分钟前', style: TextStyle(fontSize: 10, color: cs.outline)),
              const Spacer(),
              Text('每格 10 秒', style: TextStyle(fontSize: 10, color: cs.outline)),
              const Spacer(),
              Text('现在', style: TextStyle(fontSize: 10, color: cs.outline)),
            ],
          ),
        ],
      ),
    );
  }

  /// 导入密钥日志（NSS key log / SSLKEYLOGFILE）——被动旁路解密 QUIC 的唯一可行路径
  Future<void> _importKeylog(BuildContext context) async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files == null || files.isEmpty) return;

      final bytes = await files.first.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);
      final added = QuicKeylogStore.instance.importText(text);

      if (context.mounted) {
        FlutterToastr.show(
          added > 0
              ? '已导入 $added 条密钥，覆盖 ${QuicKeylogStore.instance.connectionCount} 个连接'
              : '没有解析到新的密钥条目（请确认文件是 NSS key log 格式）',
          context,
          duration: 3,
        );
      }
      QuicProbe.instance.revision.value++;
    } catch (e) {
      if (context.mounted) {
        FlutterToastr.show('导入失败：$e', context, duration: 3);
      }
    }
  }

  /// 查看某个会话解密出来的流数据
  void _showDecrypted(BuildContext context, QuicSession session) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${session.host.isEmpty ? '(未解出 SNI)' : session.host} · 解密内容',
            style: const TextStyle(fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '共 ${session.decrypted.length} 段（客户端发送方向，1-RTT）。'
                'HEADERS 为 QPACK 压缩：静态表与动态表引用均已解码，动态表由本连接的'
                '「QPACK 编码器流」按序还原${session.qpackTable.insertCount > 0 ? '（已插入 ${session.qpackTable.insertCount} 条，当前存活 ${session.qpackTable.length} 条）' : '（本连接未使用动态表）'}。',
                style: TextStyle(fontSize: 11.5, height: 1.45, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: session.decrypted.length,
                  itemBuilder: (context, index) {
                    final item = session.decrypted[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'stream ${item.streamId} · '
                            '${item.uniStreamType != null ? h3UniStreamTypeName(item.uniStreamType!) : http3FrameName(item.frameType)} · '
                            '${item.length}B${item.fin ? ' · FIN' : ''} · ${_time(item.time)}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          SelectableText(item.preview,
                              style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', height: 1.4)),
                          if (item.headers.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('HTTP/3 头部 · QPACK 已解码 ${item.headers.length} 项',
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  for (final h in item.headers)
                                    SelectableText('${h.name}: ${h.value}',
                                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.4)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  /// 顶部统计条：连接 / 域名 / 包 / 流量 / 活跃数（30 秒内还有活动的会话）
  Widget _buildSummary(BuildContext context, List<QuicSession> sessions) {
    final cs = Theme.of(context).colorScheme;
    final hosts = sessions.map((s) => s.host).where((h) => h.isNotEmpty).toSet();
    final packets = sessions.fold<int>(0, (sum, s) => sum + s.packets);
    final bytes = sessions.fold<int>(0, (sum, s) => sum + s.bytes);
    final active = sessions.where((s) => DateTime.now().difference(s.lastSeen).inSeconds <= 30).length;

    Widget cell(String label, String value, {Color? color}) {
      return Expanded(
        child: Column(
          children: [
            Text(value,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color ?? cs.onSurface)),
            Text(label, style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          cell('连接', '${sessions.length}'),
          cell('域名', '${hosts.length}'),
          cell('包', '$packets'),
          cell('流量', _humanBytes(bytes)),
          cell('活跃', '$active', color: active > 0 ? Colors.green : cs.onSurfaceVariant),
        ],
      ),
    );
  }

  static String _humanBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}K';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}M';
  }

  static String _ago(DateTime t) {
    final seconds = DateTime.now().difference(t).inSeconds;
    if (seconds < 60) return '$seconds 秒前';
    if (seconds < 3600) return '${seconds ~/ 60} 分钟前';
    return '${seconds ~/ 3600} 小时前';
  }

  Widget _empty(ColorScheme cs, BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hub_outlined, size: 44, color: cs.outlineVariant),
            const SizedBox(height: 14),
            const Text('尚未捕获到 QUIC 连接',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              '开启 VPN 抓包后，目标应用使用 QUIC/HTTP3 时（如视频、部分社交与游戏应用），'
              '会自动记录其连接：域名(SNI)、QUIC 版本、连接 ID 与包/帧统计。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.6),
            ),
            const SizedBox(height: 16),
            Text(
              '提示：多数应用默认走 TCP/HTTP2，若需看到 QUIC 记录，可在偏好设置临时关闭「拦截 QUIC」后重开抓包；'
              '业务明文仍需开启「拦截 QUIC」回落 TCP 后抓取。',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11.5, color: cs.outline, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  static String _time(DateTime t) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
  }
}
