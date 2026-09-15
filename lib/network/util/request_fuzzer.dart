/*
 * Copyright 2023 Hongen Wang All rights reserved.
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

import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/network/util/logger.dart';

/// 手动 Fuzz（变体发送）。
///
/// 定位：**把用户自己给出的取值，逐条替换进一条请求并发送**，然后把每条响应
/// 的状态码 / 耗时 / 长度 / 内容摆在一起，由人来比对。
///
/// 明确不做的事：
/// - 不内置任何攻击载荷或漏洞字典（payload 完全由使用者填写）；
/// - 不自动判定"是否存在漏洞"，不自动利用、不自动扩大战果；
/// - 不自动判定"成功/失败"——结果只是事实记录，结论由人下。
///
/// 它和「重放」是同一类能力，只是把单次重放变成"按清单逐条重放并对照"。
enum FuzzTarget {
  /// 替换 URL 查询串里某个参数的值
  queryParam,

  /// 替换某个请求头的值
  header,

  /// 替换 JSON 请求体里某个字段的值
  jsonField,

  /// 把请求体里的占位符整体替换（默认 `{{FUZZ}}`）
  bodyPlaceholder,
}

class FuzzConfig {
  final FuzzTarget target;
  final String field;
  final String placeholder;
  final int intervalMs;
  final int timeoutSeconds;
  final bool sendBaseline;

  const FuzzConfig({
    this.target = FuzzTarget.queryParam,
    this.field = '',
    this.placeholder = '{{FUZZ}}',
    this.intervalMs = 200,
    this.timeoutSeconds = 15,
    this.sendBaseline = true,
  });
}

class FuzzOutcome {
  final int index;
  final String payload;
  final bool ok;
  final int? statusCode;
  final String? reasonPhrase;
  final int durationMs;
  final int bodyLength;
  final String? error;
  final String body;

  /// 是否为基线（原始请求）
  final bool baseline;

  /// 与基线的差异标记：状态码变化 / 长度变化
  final String diff;

  const FuzzOutcome({
    required this.index,
    required this.payload,
    required this.ok,
    this.statusCode,
    this.reasonPhrase,
    required this.durationMs,
    required this.bodyLength,
    this.error,
    this.body = '',
    this.baseline = false,
    this.diff = '',
  });

  FuzzOutcome withDiff(String value) => FuzzOutcome(
        index: index,
        payload: payload,
        ok: ok,
        statusCode: statusCode,
        reasonPhrase: reasonPhrase,
        durationMs: durationMs,
        bodyLength: bodyLength,
        error: error,
        body: body,
        baseline: baseline,
        diff: value,
      );
}

class RequestFuzzer {
  /// 响应体保留上限（用于结果对照，避免大响应撑爆内存）
  static const int maxBodyKept = 256 * 1024;

  /// 根据模板与配置构造一条变体请求。
  static HttpRequest buildVariant(HttpRequest template, FuzzConfig config, String payload) {
    final request = HttpRequest(template.method, template.uri, protocolVersion: template.protocolVersion);
    request.headers.addAll(template.headers);
    if (template.body != null) {
      request.body = List<int>.from(template.body!);
    }
    request.requestTime = DateTime.now();

    switch (config.target) {
      case FuzzTarget.queryParam:
        final uri = template.requestUri;
        if (uri != null && config.field.trim().isNotEmpty) {
          final params = <String, dynamic>{};
          uri.queryParametersAll.forEach((key, value) {
            params[key] = value.length == 1 ? value.first : value;
          });
          params[config.field.trim()] = payload;
          final updated = uri.replace(queryParameters: params);
          request.uri = '${updated.path}${updated.hasQuery ? '?${updated.query}' : ''}';
        }
        break;

      case FuzzTarget.header:
        if (config.field.trim().isNotEmpty) {
          request.headers.set(config.field.trim(), payload);
        }
        break;

      case FuzzTarget.jsonField:
        final text = template.bodyAsString;
        final field = config.field.trim();
        if (text.isNotEmpty && field.isNotEmpty) {
          try {
            final decoded = jsonDecode(text);
            if (decoded is Map) {
              final map = Map<String, dynamic>.from(decoded);
              map[field] = payload;
              request.body = utf8.encode(jsonEncode(map));
            }
          } catch (e) {
            logger.w('Fuzz：请求体不是合法 JSON，跳过字段替换');
          }
        }
        break;

      case FuzzTarget.bodyPlaceholder:
        final placeholder = config.placeholder.isEmpty ? '{{FUZZ}}' : config.placeholder;
        final text = template.bodyAsString.replaceAll(placeholder, payload);
        request.body = utf8.encode(text);
        break;
    }

    return request;
  }

  /// 发送一条（变体）请求并记录事实。
  static Future<FuzzOutcome> send(
    HttpRequest request, {
    required int index,
    required String payload,
    int timeoutSeconds = 15,
    bool baseline = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await HttpClients.proxyRequest(
        request,
        timeout: Duration(seconds: timeoutSeconds),
      );
      stopwatch.stop();
      return FuzzOutcome(
        index: index,
        payload: payload,
        ok: true,
        statusCode: response.status.code,
        reasonPhrase: response.status.reasonPhrase,
        durationMs: stopwatch.elapsedMilliseconds,
        bodyLength: response.body?.length ?? 0,
        body: _safeBody(response),
        baseline: baseline,
      );
    } catch (e) {
      stopwatch.stop();
      return FuzzOutcome(
        index: index,
        payload: payload,
        ok: false,
        durationMs: stopwatch.elapsedMilliseconds,
        bodyLength: 0,
        error: e.toString(),
        baseline: baseline,
      );
    }
  }

  static String _safeBody(HttpResponse response) {
    try {
      if ((response.body?.length ?? 0) > maxBodyKept) {
        return '[响应过大，仅保留前 ${maxBodyKept ~/ 1024} KB]\n${response.bodyAsString.substring(0, maxBodyKept)}';
      }
      return response.bodyAsString;
    } catch (_) {
      return '';
    }
  }

  /// 计算与基线的差异描述（只陈述事实，不做判断）。
  static String diffOf(FuzzOutcome baseline, FuzzOutcome current) {
    final parts = <String>[];
    if (baseline.statusCode != current.statusCode) {
      parts.add('状态 ${baseline.statusCode ?? '-'} → ${current.statusCode ?? '-'}');
    }
    if (baseline.bodyLength != current.bodyLength) {
      final delta = current.bodyLength - baseline.bodyLength;
      parts.add('长度 ${delta >= 0 ? '+' : ''}$delta');
    }
    final ratio = baseline.durationMs == 0 ? 0.0 : (current.durationMs - baseline.durationMs) / baseline.durationMs;
    if (ratio.abs() > 0.5) {
      parts.add('耗时 ${(ratio * 100).toStringAsFixed(0)}%');
    }
    if (current.error != null) {
      parts.add('请求异常');
    }
    return parts.join('，');
  }

  /// 解析 payload 文本框：一行一个，忽略空行与 `#` 开头的注释行。
  static List<String> parsePayloads(String text) {
    return text
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty && !line.trimLeft().startsWith('#'))
        .toList();
  }
}
