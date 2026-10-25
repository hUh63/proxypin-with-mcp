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
import 'package:proxypin/network/http/http.dart';

/// 一个「标签 + 计数」维度（域名 / 内容类型 / 状态码）。
class CountEntry {
  final String label;
  final int count;
  final int bytes;

  const CountEntry(this.label, this.count, this.bytes);

  double share(int total) => total <= 0 ? 0 : count / total;
}

/// 单条请求的排行项（最慢 / 最大）。
class RequestEntry {
  final String method;
  final String url;
  final String host;
  final int status;
  final int durationMs;
  final int bytes;

  const RequestEntry({
    required this.method,
    required this.url,
    required this.host,
    required this.status,
    required this.durationMs,
    required this.bytes,
  });
}

/// 从 [HttpRequest] 拍平出来的轻量行：字段全是基础类型，可安全跨 isolate 传递。
///
/// 统计里真正贵的是「遍历 + 两次全量排序」，几万条时同步跑会卡住 UI 帧；
/// 所以拆成两步：UI 侧 [TrafficStats.rowsOf] 取行（O(n)，无排序），
/// 再把行丢进 isolate 跑 [TrafficStats.computeRows]。
class TrafficRow {
  final String method;
  final String url;
  final String host;
  final String contentType;
  final bool hasResponse;
  final int status;
  final int durationMs;
  final int requestBytes;
  final int responseBytes;

  const TrafficRow({
    required this.method,
    required this.url,
    required this.host,
    required this.contentType,
    required this.hasResponse,
    required this.status,
    required this.durationMs,
    required this.requestBytes,
    required this.responseBytes,
  });
}

/// 抓包列表的流量聚合统计（纯计算，无 flutter 依赖，可单测）。
///
/// 对标 HTTP Debugger Pro 的「流量报表」：总览、Top 域名 / 内容类型 / 状态码、
/// 最慢请求、最大响应。注意与 `performance_dashboard.dart` 区分——那个看的是
/// 连接池 / QPS 等**运行时基础设施指标**，这里看的是**已抓到的请求本身**的分布。
class TrafficStats {
  final int total;
  final int success;
  final int fail;
  final int pending;
  final int totalRequestBytes;
  final int totalResponseBytes;
  final int avgDurationMs;
  final List<CountEntry> topHosts;
  final List<CountEntry> topContentTypes;
  final List<CountEntry> statusCodes;
  final List<RequestEntry> slowest;
  final List<RequestEntry> largest;

  const TrafficStats({
    required this.total,
    required this.success,
    required this.fail,
    required this.pending,
    required this.totalRequestBytes,
    required this.totalResponseBytes,
    required this.avgDurationMs,
    required this.topHosts,
    required this.topContentTypes,
    required this.statusCodes,
    required this.slowest,
    required this.largest,
  });

  /// 把请求列表拍平成轻量行（O(n)、不排序）。
  static List<TrafficRow> rowsOf(List<HttpRequest> requests) {
    final rows = <TrafficRow>[];
    for (final r in requests) {
      final resp = r.response;
      rows.add(TrafficRow(
        method: r.methodLabel,
        url: r.requestUrl,
        host: r.hostAndPort?.host ?? '',
        contentType: _baseContentType(resp?.headers.contentType),
        hasResponse: resp != null,
        status: resp?.status.code ?? 0,
        durationMs: resp == null ? 0 : resp.responseTime.difference(r.requestTime).inMilliseconds,
        requestBytes: r.originalBodyLength ?? r.body?.length ?? 0,
        responseBytes: resp?.originalBodyLength ?? resp?.body?.length ?? 0,
      ));
    }
    return rows;
  }

  /// 聚合 + 排序（纯数据，可作为 isolate 入口）。
  static TrafficStats computeRows(List<TrafficRow> rows, {int topN = 10}) {
    var success = 0;
    var fail = 0;
    var pending = 0;
    var reqBytes = 0;
    var respBytes = 0;
    var durationSum = 0;
    var timedCount = 0;

    final hostCount = <String, int>{};
    final hostBytes = <String, int>{};
    final typeCount = <String, int>{};
    final statusCount = <String, int>{};
    final entries = <RequestEntry>[];

    for (final r in rows) {
      reqBytes += r.requestBytes;

      if (!r.hasResponse) {
        pending++;
      } else {
        final code = r.status;
        if (code >= 400 || code == 0) {
          fail++;
        } else {
          success++;
        }
        statusCount['$code'] = (statusCount['$code'] ?? 0) + 1;
        respBytes += r.responseBytes;
        durationSum += r.durationMs;
        timedCount++;
        entries.add(RequestEntry(
          method: r.method,
          url: r.url,
          host: r.host,
          status: code,
          durationMs: r.durationMs,
          bytes: r.responseBytes,
        ));
      }

      hostCount[r.host] = (hostCount[r.host] ?? 0) + 1;
      hostBytes[r.host] = (hostBytes[r.host] ?? 0) + r.responseBytes;

      if (r.contentType.isNotEmpty) {
        typeCount[r.contentType] = (typeCount[r.contentType] ?? 0) + 1;
      }
    }

    final slowest = List<RequestEntry>.of(entries)..sort((a, b) => b.durationMs.compareTo(a.durationMs));
    final largest = List<RequestEntry>.of(entries)..sort((a, b) => b.bytes.compareTo(a.bytes));

    return TrafficStats(
      total: rows.length,
      success: success,
      fail: fail,
      pending: pending,
      totalRequestBytes: reqBytes,
      totalResponseBytes: respBytes,
      avgDurationMs: timedCount == 0 ? 0 : (durationSum / timedCount).round(),
      topHosts: _top(hostCount, hostBytes, topN),
      topContentTypes: _top(typeCount, const {}, topN),
      statusCodes: _top(statusCount, const {}, topN),
      slowest: slowest.take(topN).toList(growable: false),
      largest: largest.take(topN).toList(growable: false),
    );
  }

  /// 同步便捷版（小列表 / 单测）。大列表请用
  /// `compute(TrafficStats.computeRows, TrafficStats.rowsOf(list))` 放到 isolate。
  static TrafficStats compute(List<HttpRequest> requests, {int topN = 10}) =>
      computeRows(rowsOf(requests), topN: topN);

  static String _baseContentType(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final semi = raw.indexOf(';');
    final base = (semi >= 0 ? raw.substring(0, semi) : raw).trim().toLowerCase();
    return base;
  }

  static List<CountEntry> _top(Map<String, int> counts, Map<String, int> bytes, int topN) {
    final list = counts.entries
        .map((e) => CountEntry(e.key, e.value, bytes[e.key] ?? 0))
        .toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : b.bytes.compareTo(a.bytes);
      });
    return list.take(topN).toList(growable: false);
  }

  /// 人类可读的字节数。
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(2)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
}
