/*
 * Copyright 2023 Hongen Wang
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
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/utils/traffic_stats.dart';

/// 打开「流量分析」对话框：对当前抓包列表做聚合统计。
///
/// 对标 HTTP Debugger Pro 的流量报表，纯读侧、不改变任何抓包数据。
void showTrafficAnalytics(BuildContext context, List<HttpRequest> requests) {
  showDialog(
    context: context,
    builder: (ctx) => _TrafficAnalyticsDialog(requests: requests),
  );
}

class _TrafficAnalyticsDialog extends StatelessWidget {
  final List<HttpRequest> requests;

  const _TrafficAnalyticsDialog({required this.requests});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final stats = TrafficStats.compute(requests);

    return AlertDialog(
      title: Text(l.trafficAnalyticsTitle),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: 560,
        child: stats.total == 0
            ? Text(l.trafficEmpty, style: TextStyle(color: Colors.grey[600]))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _section(context, l.trafficOverview),
                    _kv(l.trafficTotal, '${stats.total}'),
                    _kv(l.trafficSuccess, '${stats.success}', color: Colors.green),
                    _kv(l.trafficFail, '${stats.fail}', color: Colors.red),
                    _kv(l.trafficPending, '${stats.pending}', color: Colors.orange),
                    _kv(l.trafficUplinkBytes, TrafficStats.formatBytes(stats.totalRequestBytes)),
                    _kv(l.trafficDownlinkBytes, TrafficStats.formatBytes(stats.totalResponseBytes)),
                    _kv(l.trafficAvgTime, '${stats.avgDurationMs} ms'),
                    const SizedBox(height: 8),
                    _barSection(context, l.trafficTopHosts, stats.topHosts, stats.total),
                    _barSection(context, l.trafficTopContentTypes, stats.topContentTypes, stats.total),
                    _barSection(context, l.trafficStatusCodes, stats.statusCodes, stats.total),
                    _listSection(context, l.trafficSlowest, stats.slowest,
                        (e) => '${e.method} ${_shortUrl(e)}  ·  ${e.durationMs} ms'),
                    _listSection(context, l.trafficLargest, stats.largest,
                        (e) => '${e.method} ${_shortUrl(e)}  ·  ${TrafficStats.formatBytes(e.bytes)}'),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.close)),
      ],
    );
  }

  static String _shortUrl(RequestEntry e) {
    final u = e.url;
    return u.length > 64 ? '${u.substring(0, 64)}…' : u;
  }

  Widget _section(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          )),
    );
  }

  Widget _kv(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700]))),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _barSection(BuildContext context, String title, List<CountEntry> entries, int total) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(context, title),
        ...entries.map((e) {
          final share = e.share(total);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 220,
                  child: Text(e.label.isEmpty ? '-' : e.label,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: share,
                      minHeight: 8,
                      backgroundColor: Colors.grey[200],
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text('${e.count}  ${(share * 100).toStringAsFixed(0)}%',
                      textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _listSection(
      BuildContext context, String title, List<RequestEntry> entries, String Function(RequestEntry) fmt) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(context, title),
        ...entries.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(fmt(e),
                  style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis),
            )),
      ],
    );
  }
}
