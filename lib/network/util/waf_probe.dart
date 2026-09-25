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

import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/request_fuzzer.dart';
import 'package:proxypin/network/util/waf_bypass.dart';

/// 一条探测的判定结论。
enum WafVerdict {
  /// 基线请求（原始载荷），只作对照，不参与结论
  baseline,

  /// 被拦下了：状态码命中拦截码，或响应体命中拦截特征
  blocked,

  /// 与基线一致：这一条**疑似绕过了**，值得人工确认
  passed,

  /// 响应有变化但不像拦截（可能被改写/业务差异），需要人看一眼
  changed,

  /// 请求本身没发出去（连不上、超时、URL 不合法）
  failed,
}

/// 一条探测的事实 + 结论。
class WafProbeResult {
  /// 技术 id；基线为 `baseline`
  final String technique;

  /// 技术名
  final String name;

  /// 实际发送的载荷
  final String payload;

  final WafVerdict verdict;
  final int? statusCode;
  final int bodyLength;
  final int durationMs;
  final String? error;

  /// 响应体片段（截断，用于展示与特征判定）
  final String bodySnippet;

  const WafProbeResult({
    required this.technique,
    required this.name,
    required this.payload,
    required this.verdict,
    this.statusCode,
    this.bodyLength = 0,
    this.durationMs = 0,
    this.error,
    this.bodySnippet = '',
  });

  WafProbeResult withVerdict(WafVerdict value) => WafProbeResult(
        technique: technique,
        name: name,
        payload: payload,
        verdict: value,
        statusCode: statusCode,
        bodyLength: bodyLength,
        durationMs: durationMs,
        error: error,
        bodySnippet: bodySnippet,
      );

  Map<String, dynamic> toJson() => {
        'technique': technique,
        'name': name,
        'payload': payload,
        'verdict': verdict.name,
        'status': statusCode,
        'length': bodyLength,
        'duration_ms': durationMs,
        'error': error,
      };
}

/// WAF 主动探测：先发一条基线（原始载荷），再逐条发变异载荷，比对响应判断是否被拦。
///
/// 边界（刻意不做的事，请不要把这些加进来）：
/// - 不内置攻击载荷字典、不做载荷的组合搜索/爆破；
/// - 不并发：串行发送 + 可配置间隔，单次总量有硬上限（[maxProbes]）；
/// - 不自动利用、不自动提取数据、不做反溯源/代理轮换；
/// - 判定只陈述事实（状态码 / 长度 / 特征词），不输出「漏洞」「高危」这类结论——
///   疑似绕过是一条线索，是否成立要人自己确认。
///
/// 只对你拥有或已获书面授权的目标使用。
class WafProbe {
  /// 单次发送请求数的**默认**上限（含基线）。用户可在高级设置里调。
  static const int defaultMaxProbes = 200;

  /// 单次请求数的**硬顶**：无论用户怎么配都不会超过这个数，防止误配成失控流量
  static const int hardMaxProbes = 2000;

  /// 每条之间的**默认**间隔（毫秒）
  static const int defaultDelayMs = 300;

  /// 间隔**下限**（毫秒）：再快就不是"探测"而是对目标的流量冲击了
  static const int minDelayMs = 100;

  /// 单条超时的默认值（秒）
  static const int defaultTimeoutSeconds = 15;

  /// 这些状态码通常意味着「请求被挡在应用之外」
  static const Set<int> blockStatusCodes = {403, 406, 418, 419, 429, 501, 999};

  /// 响应体里的拦截特征（大小写不敏感）
  static const List<String> blockMarkers = [
    'access denied',
    'request blocked',
    'request rejected',
    'your request has been blocked',
    'not acceptable',
    'web application firewall',
    'illegal request',
    'malicious request',
    '安全拦截',
    '拒绝访问',
    '请求已被拦截',
    '非法请求',
    '您的请求存在风险',
  ];

  /// 载荷占位符（两个都认）
  static const List<String> placeholders = ['{{PAYLOAD}}', '{{FUZZ}}'];

  /// URL / 头 / 体里是否放了载荷占位符
  static bool hasPlaceholder(String text) =>
      placeholders.any((p) => text.contains(p));

  /// 把占位符换成实际载荷；没有占位符时原样返回
  static String inject(String text, String payload) {
    var out = text;
    for (final p in placeholders) {
      out = out.replaceAll(p, payload);
    }
    return out;
  }

  /// 判定一条结果。给了基线就做对照，没给就只按绝对特征判。
  static WafVerdict judge({
    required bool ok,
    required int? statusCode,
    required int bodyLength,
    required String bodySnippet,
    int? baseStatus,
    int? baseLength,
  }) {
    if (!ok) return WafVerdict.failed;
    final lower = bodySnippet.toLowerCase();
    if (blockMarkers.any((m) => lower.contains(m))) {
      return WafVerdict.blocked;
    }
    if (statusCode != null && blockStatusCodes.contains(statusCode)) {
      return WafVerdict.blocked;
    }
    if (baseStatus != null) {
      if (statusCode == baseStatus && similarLength(baseLength ?? 0, bodyLength)) {
        return WafVerdict.passed;
      }
      return WafVerdict.changed;
    }
    return WafVerdict.changed;
  }

  /// 两个长度是否算「基本一致」（15% 以内）
  static bool similarLength(int a, int b) {
    if (a == b) return true;
    final max = a > b ? a : b;
    if (max == 0) return true;
    return (a - b).abs() / max <= 0.15;
  }

  /// 按技术筛出「真的会改变载荷」的变体（原样返回的没有探测价值）。
  ///
  /// [techniques] 为空表示全部技术。
  static List<WafVariant> buildVariants(String payload, List<String> techniques) {
    final all = WafBypass.mutateAll(payload);
    final picked = techniques.isEmpty
        ? all
        : all.where((v) => techniques.contains(v.technique)).toList();
    return picked.where((v) => v.output != payload).toList();
  }

  /// 一次发完（内部就是「一批发到底」的会话）。
  ///
  /// 条目多、想中途停下来看的场景，直接用 [WafProbeSession] 一批批发。
  /// [url] / [headers] / [body] 里用 `{{PAYLOAD}}` 标记注入位置。
  /// 返回的列表第 0 条是基线。
  static Future<List<WafProbeResult>> probe({
    required String url,
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
    required String payload,
    List<String> techniques = const [],
    int delayMs = defaultDelayMs,
    int timeoutSeconds = defaultTimeoutSeconds,
    int maxProbes = defaultMaxProbes,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final session = WafProbeSession(
      url: url,
      payload: payload,
      method: method,
      headers: headers,
      body: body,
      variants: buildVariants(payload, techniques),
      batchSize: maxProbes.clamp(1, hardMaxProbes),
      delayMs: delayMs,
      timeoutSeconds: timeoutSeconds,
    );
    await session.nextBatch(onProgress: onProgress, isCancelled: isCancelled);
    return session.results;
  }

  static Future<WafProbeResult> _sendOne({
    required String url,
    required String method,
    required Map<String, String> headers,
    String? body,
    required String payload,
    required String technique,
    required String name,
    required int timeoutSeconds,
  }) async {
    final finalUrl = inject(url, payload);
    HttpRequest request;
    try {
      request = HttpRequest(HttpMethod.valueOf(method), finalUrl,
          protocolVersion: 'HTTP/1.1');
    } catch (e) {
      logger.w('WAF 探测：URL 解析失败 $finalUrl : $e');
      return WafProbeResult(
        technique: technique,
        name: name,
        payload: payload,
        verdict: WafVerdict.failed,
        error: 'URL 不合法：$e',
      );
    }
    headers.forEach((key, value) {
      request.headers.set(key, inject(value, payload));
    });
    if (body != null && body.isNotEmpty) {
      request.body = utf8.encode(inject(body, payload));
    }

    final outcome = await RequestFuzzer.send(
      request,
      index: 1,
      payload: payload,
      timeoutSeconds: timeoutSeconds,
      baseline: technique == 'baseline',
    );
    return WafProbeResult(
      technique: technique,
      name: name,
      payload: payload,
      verdict: judge(
        ok: outcome.ok,
        statusCode: outcome.statusCode,
        bodyLength: outcome.bodyLength,
        bodySnippet: outcome.body,
      ),
      statusCode: outcome.statusCode,
      bodyLength: outcome.bodyLength,
      durationMs: outcome.durationMs,
      error: outcome.error,
      bodySnippet: snippet(outcome.body),
    );
  }

  /// 响应体片段（用于展示与特征判定）
  static String snippet(String body, {int max = 512}) {
    if (body.length <= max) return body;
    return body.substring(0, max);
  }

  /// 判定结论的展示文案
  static String verdictLabel(WafVerdict verdict) {
    switch (verdict) {
      case WafVerdict.baseline:
        return '基线';
      case WafVerdict.blocked:
        return '被拦截';
      case WafVerdict.passed:
        return '疑似绕过';
      case WafVerdict.changed:
        return '响应有变化';
      case WafVerdict.failed:
        return '请求失败';
    }
  }
}

/// 分批探测会话。
///
/// 为什么是分批而不是一次发完：条目多时（比如把整套字典喂进来）一次发完
/// 既是一段长时间的持续请求，也失去了中途停下的机会。分批让人始终握着
/// 「要不要继续」这个决定权，界面也不会被一个长任务卡住。
class WafProbeSession {
  final String url;
  final String method;
  final Map<String, String> headers;
  final String? body;
  final String payload;

  /// 每批发多少条
  final int batchSize;
  final int delayMs;
  final int timeoutSeconds;

  final List<WafVariant> _queue;
  final List<WafProbeResult> results = [];

  int? _baseStatus;
  int? _baseLength;
  bool _baseDone = false;

  WafProbeSession({
    required this.url,
    required this.payload,
    this.method = 'GET',
    this.headers = const {},
    this.body,
    required List<WafVariant> variants,
    this.batchSize = WafProbe.defaultMaxProbes,
    this.delayMs = WafProbe.defaultDelayMs,
    this.timeoutSeconds = WafProbe.defaultTimeoutSeconds,
  }) : _queue = List.of(variants);

  /// 还没发的条数（不含基线）
  int get remaining => _queue.length;

  /// 队列已空（基线也发过了）
  bool get finished => _baseDone && _queue.isEmpty;

  /// 总条数（含基线）
  int get totalCount => _queue.length + results.length + (_baseDone ? 0 : 1);

  /// 发下一批。第一批会先补一条基线；基线只在第一批发。
  Future<List<WafProbeResult>> nextBatch({
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final batch = <WafProbeResult>[];
    // 间隔夹一下下限，避免配成 0 变成无间隔冲击
    final gap = delayMs < WafProbe.minDelayMs ? WafProbe.minDelayMs : delayMs;

    if (!_baseDone) {
      if (isCancelled?.call() == true) return batch;
      final base = await WafProbe._sendOne(
        url: url,
        method: method,
        headers: headers,
        body: body,
        payload: payload,
        technique: 'baseline',
        name: '基线（原始载荷）',
        timeoutSeconds: timeoutSeconds,
      );
      _baseDone = true;
      if (base.verdict != WafVerdict.failed) {
        _baseStatus = base.statusCode;
        _baseLength = base.bodyLength;
      }
      results.add(base);
      batch.add(base);
      onProgress?.call(results.length, totalCount);
    }

    final take = _queue.length < batchSize ? _queue.length : batchSize;
    for (var i = 0; i < take; i++) {
      if (isCancelled?.call() == true) break;
      await Future.delayed(Duration(milliseconds: gap));
      final v = _queue.removeAt(0);
      final raw = await WafProbe._sendOne(
        url: url,
        method: method,
        headers: headers,
        body: body,
        payload: v.output,
        technique: v.technique,
        name: v.name,
        timeoutSeconds: timeoutSeconds,
      );
      // 用基线对照后判定
      final verdict = WafProbe.judge(
        ok: raw.verdict != WafVerdict.failed,
        statusCode: raw.statusCode,
        bodyLength: raw.bodyLength,
        bodySnippet: raw.bodySnippet,
        baseStatus: _baseStatus,
        baseLength: _baseLength,
      );
      results.add(raw.withVerdict(verdict));
      batch.add(results.last);
      onProgress?.call(results.length, totalCount);
    }
    return batch;
  }
}
