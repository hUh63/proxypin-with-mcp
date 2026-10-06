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
import 'dart:convert';

import 'package:proxypin/network/channel/connection_registry.dart';
import 'package:proxypin/network/http/http.dart';

enum DiagnosticLevel { info, warn, error }

/// 一条基于「连接登记表」推导出的自检结论。
class DiagnosticIssue {
  final DiagnosticLevel level;
  final String title;
  final String detail;
  final String? connectionId;

  const DiagnosticIssue(this.level, this.title, this.detail, {this.connectionId});
}

/// 连接视图的自检报告（用于真机验证 HTTP/2 连接树与分阶段耗时是否按预期采集）。
class ConnectionDiagnosticsReport {
  final DateTime generatedAt;
  final int connectionCount;
  final int http2Count;
  final int http1Count;
  final int tlsCount;
  final int totalRequests;
  final int cachedRequests;
  final int withStreamId;
  final int withConnectTime;
  final int withTlsTime;
  final int maxConnections;
  final List<DiagnosticIssue> issues;

  ConnectionDiagnosticsReport({
    required this.generatedAt,
    required this.connectionCount,
    required this.http2Count,
    required this.http1Count,
    required this.tlsCount,
    required this.totalRequests,
    required this.cachedRequests,
    required this.withStreamId,
    required this.withConnectTime,
    required this.withTlsTime,
    required this.maxConnections,
    required this.issues,
  });

  int get errorCount => issues.where((i) => i.level == DiagnosticLevel.error).length;
  int get warnCount => issues.where((i) => i.level == DiagnosticLevel.warn).length;
  int get infoCount => issues.where((i) => i.level == DiagnosticLevel.info).length;

  bool get healthy => errorCount == 0 && warnCount == 0;
}

/// 连接树 / 分阶段耗时的自检器（纯 Dart，无 Flutter 依赖，便于单测）。
///
/// 它不改变任何运行时行为，只是把 [ConnectionRegistry] 的现状翻成
/// 「哪些指标采到了、哪些没采到、哪些自相矛盾」的清单，帮助在真机上一眼看懂。
class ConnectionDiagnostics {
  static ConnectionDiagnosticsReport analyze(List<ConnectionEntry> entries) {
    final issues = <DiagnosticIssue>[];
    var http2 = 0, http1 = 0, tls = 0, totalReq = 0, cached = 0, withStream = 0, withConn = 0, withTls = 0;

    for (final e in entries) {
      if (e.isHttp2) {
        http2++;
      } else {
        http1++;
      }
      if (e.isSsl) tls++;
      totalReq += e.requestCount;
      cached += e.recent.length;

      var hasH2 = false;
      for (final r in e.recent) {
        final isH2 = r.protocolVersion == 'HTTP/2';
        if (isH2) hasH2 = true;
        if (r.streamId != null) {
          withStream++;
          if (!isH2) {
            issues.add(DiagnosticIssue(
              DiagnosticLevel.warn,
              '请求带 streamId 但协议不是 HTTP/2',
              '${r.method.name} ${r.uri} · streamId=${r.streamId} · proto=${r.protocolVersion}',
              connectionId: e.id,
            ));
          }
        } else if (isH2) {
          issues.add(DiagnosticIssue(
            DiagnosticLevel.info,
            'HTTP/2 请求未解析到 streamId',
            '${r.method.name} ${r.uri}（连接树里该请求不会显示 #streamId）',
            connectionId: e.id,
          ));
        }
        if (r.connectTimeMs != null) withConn++;
        if (r.tlsTimeMs != null) withTls++;
      }

      if (e.requestCount > 0 && e.recent.isEmpty) {
        issues.add(DiagnosticIssue(
          DiagnosticLevel.warn,
          '连接有请求计数，但最近请求列表为空',
          'requestCount=${e.requestCount}，recent=0（登记时序可能异常）',
          connectionId: e.id,
        ));
      }
      if (e.isHttp2 && !hasH2 && e.recent.isNotEmpty) {
        issues.add(DiagnosticIssue(
          DiagnosticLevel.warn,
          '连接标记为 HTTP/2，但近期请求里没有 HTTP/2',
          '${e.clientAddress}（协议判定与请求实际协议不一致）',
          connectionId: e.id,
        ));
      }
      if (e.isSsl && e.requestCount > 0 && e.tlsTimeMs == null) {
        issues.add(DiagnosticIssue(
          DiagnosticLevel.info,
          'TLS 连接未采集到握手耗时',
          '${e.clientAddress}（若目标是明文转发或无 TLS 握手则不适用）',
          connectionId: e.id,
        ));
      }
      if (e.recent.length >= ConnectionRegistry.maxRecentPerConnection) {
        issues.add(DiagnosticIssue(
          DiagnosticLevel.info,
          '连接的最近请求已满（被裁剪）',
          '${e.clientAddress}：仅保留最近 ${ConnectionRegistry.maxRecentPerConnection} 条',
          connectionId: e.id,
        ));
      }
    }

    if (entries.length >= ConnectionRegistry.maxConnections) {
      issues.add(const DiagnosticIssue(
        DiagnosticLevel.warn,
        '活动连接数达到上限',
        '老连接可能被淘汰，连接视图未必完整；可在压测后复位再看',
      ));
    }
    if (totalReq > 0 && withConn == 0) {
      issues.add(const DiagnosticIssue(
        DiagnosticLevel.info,
        '所有请求都未采集到连接耗时（connectTimeMs）',
        'HTTP/1.1 keep-alive 复用连接时，「连接」阶段可能为空，属正常',
      ));
    }
    if (tls > 0 && totalReq > 0 && withTls == 0) {
      issues.add(const DiagnosticIssue(
        DiagnosticLevel.info,
        '所有 TLS 请求都未采集到 TLS 握手耗时',
        '连接被复用时不会重新握手，属正常；若刚建立连接仍为空，需检查埋点',
      ));
    }

    return ConnectionDiagnosticsReport(
      generatedAt: DateTime.now(),
      connectionCount: entries.length,
      http2Count: http2,
      http1Count: http1,
      tlsCount: tls,
      totalRequests: totalReq,
      cachedRequests: cached,
      withStreamId: withStream,
      withConnectTime: withConn,
      withTlsTime: withTls,
      maxConnections: ConnectionRegistry.maxConnections,
      issues: issues,
    );
  }

  /// 生成可导出的 JSON 报告（含汇总、问题清单、逐连接明细）。
  static String toJson(List<ConnectionEntry> entries, ConnectionDiagnosticsReport report) {
    final conns = entries.map((e) {
      return {
        'id': e.id,
        'clientAddress': e.clientAddress,
        'protocol': e.isHttp2 ? 'HTTP/2' : 'HTTP/1.1',
        'ssl': e.isSsl,
        'requestCount': e.requestCount,
        'connectTimeMs': e.connectTimeMs,
        'tlsTimeMs': e.tlsTimeMs,
        'openedAt': e.openedAt.toIso8601String(),
        'lastActive': e.lastActive.toIso8601String(),
        'recent': e.recent.map((r) {
          return {
            'method': r.method.name,
            'uri': r.uri,
            'protocol': r.protocolVersion,
            'streamId': r.streamId,
            'status': r.response?.status.code,
            'connectTimeMs': r.connectTimeMs,
            'tlsTimeMs': r.tlsTimeMs,
            'connectionReused': r.connectionReused,
          };
        }).toList(),
      };
    }).toList();

    final data = {
      'generatedAt': report.generatedAt.toIso8601String(),
      'summary': {
        'connectionCount': report.connectionCount,
        'http2Count': report.http2Count,
        'http1Count': report.http1Count,
        'tlsCount': report.tlsCount,
        'totalRequests': report.totalRequests,
        'cachedRequests': report.cachedRequests,
        'withStreamId': report.withStreamId,
        'withConnectTime': report.withConnectTime,
        'withTlsTime': report.withTlsTime,
        'maxConnections': report.maxConnections,
        'errorCount': report.errorCount,
        'warnCount': report.warnCount,
        'infoCount': report.infoCount,
      },
      'issues': report.issues
          .map((i) => {
                'level': i.level.name,
                'title': i.title,
                'detail': i.detail,
                if (i.connectionId != null) 'connectionId': i.connectionId,
              })
          .toList(),
      'connections': conns,
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }
}
