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
/// - 不内置任何攻击载荷或漏洞字典（取值完全由使用者填写）；
/// - 不自动判定"是否存在漏洞"，不自动利用、不自动扩大战果；
/// - 不给出"安全/高危"之类的结论——结果只是事实记录，结论由人下。
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

/// 一个注入项：往哪里注入、用什么取值列表
class FuzzInjection {
  final FuzzTarget target;
  final String field;
  final String placeholder;
  final List<String> values;

  const FuzzInjection({
    this.target = FuzzTarget.queryParam,
    this.field = '',
    this.placeholder = '{{FUZZ}}',
    this.values = const [''],
  });

  FuzzInjection copyWith({
    FuzzTarget? target,
    String? field,
    String? placeholder,
    List<String>? values,
  }) =>
      FuzzInjection(
        target: target ?? this.target,
        field: field ?? this.field,
        placeholder: placeholder ?? this.placeholder,
        values: values ?? this.values,
      );

  /// 展示标签：`字段=取值`（占位符模式显示占位符）
  String labelOf(String value) {
    switch (target) {
      case FuzzTarget.queryParam:
      case FuzzTarget.header:
      case FuzzTarget.jsonField:
        return '${field.isEmpty ? '?' : field}=$value';
      case FuzzTarget.bodyPlaceholder:
        return value;
    }
  }
}

/// 一次组合：每个注入项各取一个值
class FuzzCase {
  final List<String> values;
  final String label;

  const FuzzCase({required this.values, required this.label});
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
  final bool baseline;
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

  Map<String, dynamic> toJson() => {
        'index': index,
        'payload': payload,
        'baseline': baseline,
        'ok': ok,
        'status': statusCode,
        'length': bodyLength,
        'duration_ms': durationMs,
        'error': error,
        'diff': diff,
      };
}

class RequestFuzzer {
  /// 响应体保留上限（用于结果对照，避免大响应撑爆内存）
  static const int maxBodyKept = 256 * 1024;

  /// 单次最多生成的组合数（防止笛卡尔积爆炸）
  static const int maxCombinations = 500;

  /// 生成组合（笛卡尔积）。
  ///
  /// 每个注入项的可选值来自它的 [FuzzInjection.values]；空列表按一个空值处理。
  /// 超过 [limit] 时截断（调用方应据此提示用户）。
  static List<FuzzCase> buildCases(List<FuzzInjection> injections, {int limit = maxCombinations}) {
    if (injections.isEmpty) return const [];

    var cases = <FuzzCase>[
      const FuzzCase(values: [], label: '')
    ];

    for (final injection in injections) {
      final values = injection.values.isEmpty ? const [''] : injection.values;
      final next = <FuzzCase>[];
      for (final current in cases) {
        for (final value in values) {
          final values2 = [...current.values, value];
          final labelParts = <String>[...current.label.split(' & ').where((e) => e.isNotEmpty)];
          labelParts.add(injection.labelOf(value));
          next.add(FuzzCase(values: values2, label: labelParts.join(' & ')));
          if (next.length >= limit) break;
        }
        if (next.length >= limit) break;
      }
      cases = next;
      if (cases.length >= limit) break;
    }
    return cases;
  }

  /// 组合总数（用于在 UI 上预览，可能大于 [maxCombinations]）
  static int combinationCount(List<FuzzInjection> injections) {
    if (injections.isEmpty) return 0;
    var total = 1;
    for (final injection in injections) {
      total *= (injection.values.isEmpty ? 1 : injection.values.length);
      if (total > 1000000) return total; // 防止溢出
    }
    return total;
  }

  /// 根据模板与注入项构造一条变体请求。
  static HttpRequest buildVariant(
    HttpRequest template,
    List<FuzzInjection> injections,
    List<String> values,
  ) {
    final request = HttpRequest(template.method, template.uri, protocolVersion: template.protocolVersion);
    request.headers.addAll(template.headers);
    if (template.body != null) {
      request.body = List<int>.from(template.body!);
    }
    request.requestTime = DateTime.now();

    for (var i = 0; i < injections.length; i++) {
      final value = i < values.length ? values[i] : '';
      _applyInjection(request, injections[i], value);
    }
    return request;
  }

  static void _applyInjection(HttpRequest request, FuzzInjection injection, String value) {
    switch (injection.target) {
      case FuzzTarget.queryParam:
        final uri = request.requestUri;
        final field = injection.field.trim();
        if (uri != null && field.isNotEmpty) {
          final params = <String, dynamic>{};
          uri.queryParametersAll.forEach((key, v) {
            params[key] = v.length == 1 ? v.first : v;
          });
          params[field] = value;
          final updated = uri.replace(queryParameters: params);
          request.uri = '${updated.path}${updated.hasQuery ? '?${updated.query}' : ''}';
        }
        break;

      case FuzzTarget.header:
        if (injection.field.trim().isNotEmpty) {
          request.headers.set(injection.field.trim(), value);
        }
        break;

      case FuzzTarget.jsonField:
        final text = request.bodyAsString;
        final field = injection.field.trim();
        if (text.isNotEmpty && field.isNotEmpty) {
          try {
            final decoded = jsonDecode(text);
            if (decoded is Map) {
              final map = Map<String, dynamic>.from(decoded);
              map[field] = value;
              request.body = utf8.encode(jsonEncode(map));
            }
          } catch (e) {
            logger.w('Fuzz：请求体不是合法 JSON，跳过字段替换');
          }
        }
        break;

      case FuzzTarget.bodyPlaceholder:
        final placeholder = injection.placeholder.isEmpty ? '{{FUZZ}}' : injection.placeholder;
        final text = request.bodyAsString.replaceAll(placeholder, value);
        request.body = utf8.encode(text);
        break;
    }
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
        return '[响应过大，仅保留前 ${maxBodyKept ~/ 1024} KB]\n'
            '${response.bodyAsString.substring(0, maxBodyKept)}';
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

  /// 解析取值文本框：一行一个，忽略空行与 `#` 开头的注释行。
  static List<String> parsePayloads(String text) {
    return text
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty && !line.trimLeft().startsWith('#'))
        .toList();
  }

  // ===== 结果导出（留证用） =====

  /// 导出为 CSV（一行一条结果），便于用表格工具统计。
  static String toCsv(List<FuzzOutcome> results) {
    final buffer = StringBuffer();
    buffer.writeln('index,payload,baseline,status,length,duration_ms,diff,error');
    for (final r in results) {
      buffer.writeln([
        r.baseline ? '' : '${r.index + 1}',
        r.payload,
        r.baseline ? '1' : '0',
        r.statusCode?.toString() ?? '',
        '${r.bodyLength}',
        '${r.durationMs}',
        r.diff,
        r.error ?? '',
      ].map(_csvCell).join(','));
    }
    return buffer.toString();
  }

  /// 导出为 JSON（结构化，便于程序处理）。
  static String toJson(List<FuzzOutcome> results, {String? template}) {
    final payload = <String, dynamic>{
      'generated_at': DateTime.now().toIso8601String(),
      if (template != null) 'template': template,
      'total': results.length,
      'results': results.map((r) => r.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static String _csvCell(String value) {
    final needsQuote = value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r');
    final escaped = value.replaceAll('"', '""').replaceAll('\r\n', ' ').replaceAll('\n', ' ');
    return needsQuote ? '"$escaped"' : escaped;
  }
}
