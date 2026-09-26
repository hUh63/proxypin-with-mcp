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
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/quic/quic_1rtt.dart';
import 'package:proxypin/network/util/quic/quic_keylog.dart';
import 'package:proxypin/network/util/quic/quic_probe.dart';
import 'package:proxypin/ui/component/utils.dart';

class QuicSessionsPage extends StatelessWidget {
  const QuicSessionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.quicTitle,
            style: const TextStyle(fontSize: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.key_outlined, size: 20),
            tooltip: loc.quicKeylogTooltip,
            onPressed: () => _importKeylog(context),
          ),
          IconButton(
            icon: const Icon(Icons.copy_all_outlined, size: 20),
            tooltip: loc.quicCopySessionsTooltip,
            onPressed: () async {
              final sessions = QuicProbe.instance.sessions
                ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
              if (sessions.isEmpty) return;
              final text = sessions
                  .map((s) => '${s.host.isEmpty ? loc.quicNoSni : s.host}\t${s.version}\t${s.remote}\t'
                      '${loc.quicPacketsBytes(s.packets, _humanBytes(s.bytes))}\t'
                      '${loc.quicLastActivity(_time(s.lastSeen))}')
                  .join('\n');
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                FlutterToastr.show(loc.quicCopiedSessions(sessions.length), context,
                    duration: 2);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: loc.quicRefreshTooltip,
            onPressed: () => QuicProbe.instance.revision.value++,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 20),
            tooltip: loc.quicClearRecords,
            onPressed: () => showConfirmDialog(context,
                title: loc.quicClearRecords,
                content: loc.quicClearConfirm,
                onConfirm: () => QuicProbe.instance.clear()),
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
                    ? loc.quicBannerNoKeylog
                    : loc.quicBannerKeylogLoaded(QuicKeylogStore.instance.entryCount,
                        QuicKeylogStore.instance.connectionCount),
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
                      s.host.isNotEmpty ? s.host : loc.quicNoSniUnresolved,
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
                      '${loc.quicSessionSummary(s.version, s.remote, _time(s.firstSeen), _ago(loc, s.lastSeen))}\n'
                      '${loc.quicSessionIds(s.dcid.length >= 6 ? s.dcid.substring(0, 6) : s.dcid, s.packets, s.frames, _humanBytes(s.bytes), s.decrypted.isNotEmpty ? loc.quicDecryptedSegments(s.decrypted.length) : '')}',
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
              Text(AppLocalizations.of(context)!.quicTimelineTitle,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const Spacer(),
              Text(
                activeBuckets == 0
                    ? AppLocalizations.of(context)!.quicTimelineNoData
                    : AppLocalizations.of(context)!
                        .quicTimelineSummary(total, _humanBytes(totalBytes), activeBuckets),
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
              Text(AppLocalizations.of(context)!.quicTenMinutesAgo,
                  style: TextStyle(fontSize: 10, color: cs.outline)),
              const Spacer(),
              Text(AppLocalizations.of(context)!.quicPerCellTenSeconds,
                  style: TextStyle(fontSize: 10, color: cs.outline)),
              const Spacer(),
              Text(AppLocalizations.of(context)!.quicNow,
                  style: TextStyle(fontSize: 10, color: cs.outline)),
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
              ? AppLocalizations.of(context)!
                  .quicImportedNKeys(added, QuicKeylogStore.instance.connectionCount)
              : AppLocalizations.of(context)!.quicNoNewKeyEntries,
          context,
          duration: 3,
        );
      }
      QuicProbe.instance.revision.value++;
    } catch (e) {
      if (context.mounted) {
        FlutterToastr.show(
            AppLocalizations.of(context)!.quicImportFailed('$e'),
            context,
            duration: 3);
      }
    }
  }

  /// 查看某个会话解密出来的流数据
  void _showDecrypted(BuildContext context, QuicSession session) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            AppLocalizations.of(context)!.quicDecryptedTitle(session.host.isEmpty
                ? AppLocalizations.of(context)!.quicNoSniUnresolved
                : session.host),
            style: const TextStyle(fontSize: 15),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.quicDecryptedAbout(
                    session.decrypted.length,
                    session.qpackTable.insertCount > 0
                        ? AppLocalizations.of(context)!.quicQpackTableUsed(
                            session.qpackTable.insertCount, session.qpackTable.length)
                        : AppLocalizations.of(context)!.quicQpackTableUnused),
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
                                  Text(
                                      AppLocalizations.of(context)!
                                          .quicHttp3Headers(item.headers.length),
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
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.close)),
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
          cell(AppLocalizations.of(context)!.quicStatConnections, '${sessions.length}'),
          cell(AppLocalizations.of(context)!.quicStatHosts, '${hosts.length}'),
          cell(AppLocalizations.of(context)!.quicStatPackets, '$packets'),
          cell(AppLocalizations.of(context)!.quicStatTraffic, _humanBytes(bytes)),
          cell(AppLocalizations.of(context)!.quicStatActive, '$active',
              color: active > 0 ? Colors.green : cs.onSurfaceVariant),
        ],
      ),
    );
  }

  static String _humanBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}K';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}M';
  }

  static String _ago(AppLocalizations loc, DateTime t) {
    final seconds = DateTime.now().difference(t).inSeconds;
    if (seconds < 60) return loc.quicSecondsAgo(seconds);
    if (seconds < 3600) return loc.quicMinutesAgo(seconds ~/ 60);
    return loc.quicHoursAgo(seconds ~/ 3600);
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
            Text(AppLocalizations.of(context)!.quicEmptyTitle,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.quicEmptyDesc,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.6),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.quicEmptyHint,
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
