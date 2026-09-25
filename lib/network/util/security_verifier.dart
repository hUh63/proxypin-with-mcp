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
import 'dart:io';

import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';

/// 一个 host 的核验事实
class VerifyResult {
  final String host;
  final bool ok;
  final int? statusCode;
  final Map<String, String> headers;
  final String? error;

  const VerifyResult({
    required this.host,
    required this.ok,
    this.statusCode,
    this.headers = const {},
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'host': host,
        'ok': ok,
        'status': statusCode,
        'error': error,
        'missing_headers': missingHeaders,
      };

  /// 缺失的安全响应头（只列我们核对的这几个）
  List<String> get missingHeaders => SecurityVerifier.headerChecks.keys
      .where((name) => !headers.containsKey(name))
      .toList();
}

/// 主动核验：对「已经抓到的」目标重发一次，看安全响应头在不在。
///
/// 边界（刻意不做的事）：
/// - 只针对**已经在抓包列表里出现过**的 host，不扫端口、不试协议、不投载荷；
/// - 每个 host 只发**一次** GET，串行 + 固定间隔，总量有上限；
/// - 只看「响应头有没有这一条」，是配置层面的基线核查，
///   不下「这里有问题/有漏洞」的结论 —— 结论由人下。
///
/// 之所以要「主动」：被动审计只能看你已经抓到的那几条流量，如果当时抓的是
/// 一个 API 响应，可能压根没带首页的响应头。重发一次能把这块补齐。
class SecurityVerifier {
  /// 一次最多核验多少个 host
  static const int maxHosts = 50;

  /// 默认每条之间的间隔（毫秒）
  static const int defaultDelayMs = 500;

  /// 要核对的安全响应头基线
  static const Map<String, String> headerChecks = {
    'strict-transport-security': 'HSTS —— 让浏览器以后只用 HTTPS 访问',
    'content-security-policy': 'CSP —— 限制页面能加载执行哪些资源',
    'x-content-type-options': '禁止浏览器自行猜测 Content-Type',
    'x-frame-options': '防止页面被别的站点嵌套（点击劫持）',
    'referrer-policy': '控制 Referer 带出去多少信息',
  };

  /// 从已抓到的请求里取出 host 列表（去重、保持出现顺序）
  static List<String> hostsFrom(List<HttpRequest> requests,
      {int limit = maxHosts}) {
    final seen = <String>{};
    final out = <String>[];
    for (final request in requests) {
      final raw = request.headers.host?.trim();
      if (raw == null || raw.isEmpty) continue;
      final bare = raw.split(':').first.trim();
      if (bare.isEmpty || seen.contains(bare)) continue;
      seen.add(bare);
      out.add(bare);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// 核验一个 host：发一次 GET，收集响应头。
  ///
  /// 证书不校验 —— 我们只看响应头，不想因为自签证书而拿不到结果。
  static Future<VerifyResult> verifyHost(String host,
      {Duration timeout = const Duration(seconds: 12)}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    client.badCertificateCallback = (cert, h, p) => true;
    try {
      final request = await client.getUrl(Uri.parse('https://$host/'));
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        headers[name.toLowerCase()] = values.join(', ');
      });
      await response.drain<void>();
      return VerifyResult(
        host: host,
        ok: true,
        statusCode: response.statusCode,
        headers: headers,
      );
    } catch (e) {
      logger.w('安全核验：$host 请求失败 $e');
      return VerifyResult(host: host, ok: false, error: e.toString());
    } finally {
      client.close(force: true);
    }
  }

  /// 逐个核验（串行 + 间隔）
  static Future<List<VerifyResult>> verifyAll(
    List<String> hosts, {
    int delayMs = defaultDelayMs,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final results = <VerifyResult>[];
    for (var i = 0; i < hosts.length; i++) {
      if (isCancelled?.call() == true) break;
      if (i > 0 && delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }
      results.add(await verifyHost(hosts[i]));
      onProgress?.call(i + 1, hosts.length);
    }
    return results;
  }
}
