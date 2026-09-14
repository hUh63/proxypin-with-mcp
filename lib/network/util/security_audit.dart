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

/// 被动安全自检（Security Self-Audit）。
///
/// 只读地分析**已经抓到的**请求 / 响应，从中发现常见的安全隐患：
/// 明文传输、敏感信息泄露、Cookie 缺少安全属性、缺失安全响应头、
/// 服务器指纹与报错信息泄露、CORS 过宽、JWT 未签名 / 无过期等。
///
/// **边界**：本审计器**不发送任何请求**，不构造、不投递攻击载荷，
/// 不做注入探测 / 爆破 / 绕过。它回答的问题是"我已经抓到的流量里，
/// 有哪些看起来不安全的写法"，属于防御性基线核查，
/// 与主动漏洞利用工具是两回事。
library;

import 'dart:convert';

import 'package:proxypin/network/http/http.dart';

/// 风险等级
enum SecuritySeverity {
  high,
  medium,
  low,
  info;

  /// 用于排序的权重（越小越严重）
  int get weight => index;
}

/// 单条风险
class SecurityIssue {
  final String rule;
  final SecuritySeverity severity;
  final String title;
  final String detail;
  final String suggestion;
  final String method;
  final String url;
  final String requestId;

  const SecurityIssue({
    required this.rule,
    required this.severity,
    required this.title,
    required this.detail,
    required this.suggestion,
    required this.method,
    required this.url,
    required this.requestId,
  });
}

/// 审计汇总
class SecurityAuditReport {
  final List<SecurityIssue> issues;
  final int scannedRequests;

  const SecurityAuditReport({required this.issues, required this.scannedRequests});

  int count(SecuritySeverity severity) => issues.where((issue) => issue.severity == severity).length;

  bool get isClean => issues.isEmpty;
}

/// 被动安全审计器
class SecurityAuditor {
  /// 单条 body 参与内容检测的上限（超过则只做头部检测，避免卡顿）
  static const int maxBodyBytes = 512 * 1024;

  /// 一次最多分析的请求数
  static const int maxRequests = 5000;

  static SecurityAuditReport audit(List<HttpRequest> requests) {
    final seen = <String>{};
    final issues = <SecurityIssue>[];
    final limited = requests.length > maxRequests ? requests.sublist(requests.length - maxRequests) : requests;

    for (final request in limited) {
      _inspect(request, (issue) {
        final key = '${issue.rule}|${issue.method}|${issue.url}';
        if (seen.add(key)) {
          issues.add(issue);
        }
      });
    }

    issues.sort((a, b) {
      final byWeight = a.severity.weight.compareTo(b.severity.weight);
      if (byWeight != 0) return byWeight;
      return a.url.compareTo(b.url);
    });
    return SecurityAuditReport(issues: issues, scannedRequests: limited.length);
  }

  static void _inspect(HttpRequest request, void Function(SecurityIssue) emit) {
    final url = request.requestUrl;
    final uri = request.requestUri;
    final method = request.method.name.toUpperCase();
    final response = request.response;

    final reqBody = _safeBody(request);
    final respBody = response == null ? '' : _safeBody(response);

    // 1. 明文 HTTP 传输
    if (uri != null && uri.scheme.toLowerCase() == 'http') {
      final sensitiveInUrl = _hasSensitiveQuery(uri);
      final sensitiveInBody = _hasSensitiveField(reqBody);
      if (sensitiveInUrl || sensitiveInBody) {
        emit(_issue(
          rule: 'plaintext-http-sensitive',
          severity: SecuritySeverity.high,
          title: '明文 HTTP 传输敏感信息',
          detail: '该请求通过 http:// 明文发送，且${sensitiveInUrl ? ' URL 查询串' : ' 请求体'}中包含密码 / 令牌等敏感字段，中间人可直接读取。',
          suggestion: '改用 HTTPS；确需 HTTP 时避免在 URL 与请求体中直接承载凭据。',
          method: method, url: url, requestId: request.requestId,
        ));
      } else if (method != 'GET' && _hasBody(request)) {
        emit(_issue(
          rule: 'plaintext-http-body',
          severity: SecuritySeverity.medium,
          title: '明文 HTTP 传输请求体',
          detail: '该请求使用 http:// 且带请求体，内容在链路上完全明文。',
          suggestion: '对涉及登录、支付、隐私的接口强制 HTTPS。',
          method: method, url: url, requestId: request.requestId,
        ));
      }
    }

    // 2. URL 查询串携带敏感参数
    if (uri != null && _hasSensitiveQuery(uri)) {
      final names = _sensitiveQueryNames(uri);
      emit(_issue(
        rule: 'sensitive-in-url',
        severity: SecuritySeverity.medium,
        title: '敏感参数出现在 URL 中',
        detail: '查询参数 ${names.map((n) => '「$n」').join('、')} 疑似承载凭据 / 密钥。URL 会被写入浏览器历史、代理与服务器日志。',
        suggestion: '把敏感参数改放到请求体或请求头（如 Authorization）。',
        method: method, url: url, requestId: request.requestId,
      ));
    }

    // 3. 请求体 / 表单中的明文凭据
    if (_hasPasswordField(reqBody)) {
      emit(_issue(
        rule: 'plaintext-password-body',
        severity: uri != null && uri.scheme.toLowerCase() == 'http' ? SecuritySeverity.high : SecuritySeverity.medium,
        title: '请求体明文提交密码',
        detail: '请求体中存在 password / pwd 等字段且值为明文。',
        suggestion: '确保链路全程 HTTPS，服务端避免把密码回显或写入日志。',
        method: method, url: url, requestId: request.requestId,
      ));
    }

    if (response == null) return;

    // 4. Cookie 缺少安全属性
    for (final cookie in _setCookies(response)) {
      final lower = cookie.toLowerCase();
      final missing = <String>[];
      if (!lower.contains('secure')) missing.add('Secure');
      if (!lower.contains('httponly')) missing.add('HttpOnly');
      if (!lower.contains('samesite')) missing.add('SameSite');
      if (missing.isNotEmpty) {
        final name = cookie.split('=').first.trim();
        emit(_issue(
          rule: 'cookie-weak-flag',
          severity: missing.contains('Secure') && missing.contains('HttpOnly')
              ? SecuritySeverity.medium
              : SecuritySeverity.low,
          title: 'Cookie 缺少安全属性',
          detail: 'Set-Cookie「$name」缺少 ${missing.join(' / ')}，存在被脚本读取或明文传输的风险。',
          suggestion: '为会话 Cookie 补全 Secure、HttpOnly，并按需设置 SameSite=Lax/Strict。',
          method: method, url: url, requestId: request.requestId,
        ));
      }
    }

    // 5. 缺少基础安全响应头（仅 HTML 页面）
    final contentType = response.headers.contentType.toLowerCase();
    if (contentType.contains('text/html')) {
      final missingHeaders = <String>[];
      if (response.headers.get('X-Content-Type-Options') == null) missingHeaders.add('X-Content-Type-Options');
      if (response.headers.get('Content-Security-Policy') == null) missingHeaders.add('Content-Security-Policy');
      if (missingHeaders.length == 2) {
        emit(_issue(
          rule: 'missing-security-headers',
          severity: SecuritySeverity.low,
          title: 'HTML 响应缺少安全头',
          detail: '缺少 ${missingHeaders.join(' / ')}，浏览器侧的内容嗅探与脚本注入缺少额外约束。',
          suggestion: '按需补齐 nosniff、CSP 等安全响应头。',
          method: method, url: url, requestId: request.requestId,
        ));
      }
    }

    // 6. 服务器 / 框架指纹泄露
    for (final header in const ['Server', 'X-Powered-By', 'X-AspNet-Version', 'X-Generator']) {
      final value = response.headers.get(header);
      if (value != null && value.trim().isNotEmpty) {
        emit(_issue(
          rule: 'server-fingerprint',
          severity: SecuritySeverity.info,
          title: '响应暴露服务器指纹',
          detail: '$header: $value，便于攻击者针对性选择已知漏洞。',
          suggestion: '在网关层隐藏或泛化版本信息。',
          method: method, url: url, requestId: request.requestId,
        ));
      }
    }

    // 7. 响应体敏感信息明文
    if (_hasPrivateKey(respBody)) {
      emit(_issue(
        rule: 'private-key-leak',
        severity: SecuritySeverity.high,
        title: '响应体疑似包含私钥',
        detail: '响应内容中出现 PEM 私钥标记，若为真实密钥属严重泄露。',
        suggestion: '立即轮换该密钥，确认服务端不会把私钥下发到客户端。',
        method: method, url: url, requestId: request.requestId,
      ));
    }
    final secrets = _detectSecrets(respBody);
    if (secrets.isNotEmpty) {
      emit(_issue(
        rule: 'secret-in-response',
        severity: SecuritySeverity.high,
        title: '响应体明文返回敏感字段',
        detail: '检测到 ${secrets.map((n) => '「$n」').join('、')} 等字段以明文返回。',
        suggestion: '最小化返回字段；密钥类信息不应下发到客户端。',
        method: method, url: url, requestId: request.requestId,
      ));
    }
    final pii = _detectPii(respBody);
    if (pii.isNotEmpty) {
      emit(_issue(
        rule: 'pii-in-response',
        severity: SecuritySeverity.medium,
        title: '响应体包含个人敏感信息',
        detail: '检测到 ${pii.map((n) => '「$n」').join('、')} 字段携带疑似身份证 / 手机号等个人数据。',
        suggestion: '对个人数据做脱敏或按最小必要原则返回，并遵守数据合规要求。',
        method: method, url: url, requestId: request.requestId,
      ));
    }

    // 8. 报错 / 堆栈信息泄露
    final trace = _detectStackTrace(respBody);
    if (trace != null && response.status.code >= 400) {
      emit(_issue(
        rule: 'error-disclosure',
        severity: SecuritySeverity.medium,
        title: '错误响应泄露内部信息',
        detail: '响应中出现调试 / 堆栈特征（$trace），可能暴露框架、路径或数据库结构。',
        suggestion: '生产环境关闭详细报错，统一返回通用错误信息。',
        method: method, url: url, requestId: request.requestId,
      ));
    }

    // 9. CORS 配置过宽
    final allowOrigin = response.headers.get('Access-Control-Allow-Origin')?.trim();
    final allowCredentials = response.headers.get('Access-Control-Allow-Credentials')?.trim().toLowerCase();
    if (allowOrigin == '*' && allowCredentials == 'true') {
      emit(_issue(
        rule: 'cors-wildcard-credentials',
        severity: SecuritySeverity.medium,
        title: 'CORS 允许任意源且携带凭据',
        detail: 'Access-Control-Allow-Origin 为 *，同时 Allow-Credentials 为 true，跨站读取凭据的风险很高。',
        suggestion: '把允许源收敛为固定白名单，避免 * 与 Allow-Credentials 同时出现。',
        method: method, url: url, requestId: request.requestId,
      ));
    }

    // 10. JWT 未签名 / 无过期
    final jwt = _firstJwt(respBody) ?? _firstJwt(request.headers.get('Authorization') ?? '');
    if (jwt != null) {
      final header = _decodeJwtPart(jwt, 0);
      final payload = _decodeJwtPart(jwt, 1);
      final alg = header?['alg']?.toString().toLowerCase();
      if (alg == 'none') {
        emit(_issue(
          rule: 'jwt-alg-none',
          severity: SecuritySeverity.high,
          title: 'JWT 使用 alg=none（未签名）',
          detail: '该令牌声明算法为 none，任何人可篡改载荷而无法被校验。',
          suggestion: '服务端强制校验签名算法，拒绝 alg=none。',
          method: method, url: url, requestId: request.requestId,
        ));
      } else if (payload != null && payload['exp'] == null) {
        emit(_issue(
          rule: 'jwt-no-expiry',
          severity: SecuritySeverity.low,
          title: 'JWT 未设置过期时间',
          detail: '令牌载荷中缺少 exp 字段，签发后长期有效。',
          suggestion: '为令牌设置合理的过期时间并支持刷新。',
          method: method, url: url, requestId: request.requestId,
        ));
      }
    }

    // 11. 过时协议版本
    if (request.protocolVersion == 'HTTP/1.0') {
      emit(_issue(
        rule: 'http-1-0',
        severity: SecuritySeverity.info,
        title: '使用过时的 HTTP/1.0',
        detail: '该连接使用 HTTP/1.0，连接复用与缓存策略较落后。',
        suggestion: '升级到 HTTP/1.1 或 HTTP/2。',
        method: method, url: url, requestId: request.requestId,
      ));
    }
  }

  // ===== 工具方法 =====

  static SecurityIssue _issue({
    required String rule,
    required SecuritySeverity severity,
    required String title,
    required String detail,
    required String suggestion,
    required String method,
    required String url,
    required String requestId,
  }) =>
      SecurityIssue(
        rule: rule,
        severity: severity,
        title: title,
        detail: detail,
        suggestion: suggestion,
        method: method,
        url: url,
        requestId: requestId,
      );

  static bool _hasBody(HttpMessage message) => (message.body?.isNotEmpty ?? false);

  /// 读取 body 文本，超过上限则返回空串（跳过内容检测）。
  static String _safeBody(HttpMessage message) {
    final length = message.body?.length ?? 0;
    if (length == 0 || length > maxBodyBytes) return '';
    try {
      return message.bodyAsString;
    } catch (_) {
      return '';
    }
  }

  static const List<String> _sensitiveKeys = [
    'password', 'passwd', 'pwd', 'secret', 'token', 'access_token', 'refresh_token',
    'api_key', 'apikey', 'api-key', 'access_key', 'accesskey', 'private_key', 'privatekey',
    'session', 'sessionid', 'session_id', 'authorization', 'credential', 'signature', 'sign', 'auth',
  ];

  static String _normalizeKey(String key) => key.toLowerCase().replaceAll('-', '').replaceAll('_', '');

  static bool _isSensitiveKey(String key) {
    final normalized = _normalizeKey(key);
    return _sensitiveKeys.any((s) => _normalizeKey(s) == normalized);
  }

  static bool _hasSensitiveQuery(Uri uri) => uri.queryParametersAll.keys.any(_isSensitiveKey);

  static List<String> _sensitiveQueryNames(Uri uri) =>
      uri.queryParametersAll.keys.where(_isSensitiveKey).toList();

  static final RegExp _jsonField = RegExp(r'"([A-Za-z0-9_\-]{2,40})"\s*:\s*"([^"]{4,})"');

  static bool _hasSensitiveField(String text) {
    if (text.isEmpty) return false;
    for (final match in _jsonField.allMatches(text)) {
      if (_isSensitiveKey(match.group(1)!)) return true;
    }
    // 表单编码：k=v&...
    for (final pair in text.split('&')) {
      final idx = pair.indexOf('=');
      if (idx > 0 && _isSensitiveKey(pair.substring(0, idx))) return true;
    }
    return false;
  }

  static bool _hasPasswordField(String text) {
    if (text.isEmpty) return false;
    final normalized = text.toLowerCase();
    return RegExp(r'"(password|passwd|pwd)"\s*:').hasMatch(normalized) ||
        RegExp(r'(^|&)(password|passwd|pwd)=').hasMatch(normalized);
  }

  static List<String> _setCookies(HttpResponse response) {
    return response.headers.getList('Set-Cookie') ?? const [];
  }

  static final RegExp _pemPrivateKey = RegExp(r'-----BEGIN (RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----');
  static final RegExp _awsKey = RegExp(r'AKIA[0-9A-Z]{16}');

  static bool _hasPrivateKey(String text) => text.isNotEmpty && _pemPrivateKey.hasMatch(text);

  static List<String> _detectSecrets(String text) {
    if (text.isEmpty) return const [];
    final found = <String>{};
    for (final match in _jsonField.allMatches(text)) {
      final key = match.group(1)!;
      final value = match.group(2)!;
      if (_isSensitiveKey(key) && !value.contains('***') && value.length >= 6) {
        found.add(key);
      }
    }
    if (_awsKey.hasMatch(text)) found.add('AWS Access Key');
    if (_pemPrivateKey.hasMatch(text)) found.add('私钥');
    return found.toList();
  }

  static final RegExp _idCard = RegExp(r'\b\d{17}[\dXx]\b');
  static final RegExp _phone = RegExp(r'\b1[3-9]\d{9}\b');

  static List<String> _detectPii(String text) {
    if (text.isEmpty) return const [];
    final found = <String>{};
    if (RegExp(r'"(idCard|id_card|idNumber|id_number)"\s*:\s*"', caseSensitive: false).hasMatch(text) &&
        _idCard.hasMatch(text)) {
      found.add('身份证号');
    }
    if (RegExp(r'"(phone|mobile|telephone|cellphone)"\s*:\s*"', caseSensitive: false).hasMatch(text) &&
        _phone.hasMatch(text)) {
      found.add('手机号');
    }
    return found.toList();
  }

  static const List<String> _traceSignatures = [
    'Traceback (most recent call last)',
    'Exception in thread',
    'at com.',
    'at org.springframework',
    'at java.',
    'SQL syntax',
    'You have an error in your SQL syntax',
    'ORA-0',
    'PG::SyntaxError',
    'mysql_fetch',
    'NullReferenceException',
    'System.NullReferenceException',
    'Fatal error:',
    'Whoops\\',
    'Stack trace:',
  ];

  static String? _detectStackTrace(String text) {
    if (text.isEmpty) return null;
    final sample = text.length > 20000 ? text.substring(0, 20000) : text;
    for (final signature in _traceSignatures) {
      if (sample.contains(signature)) return signature;
    }
    return null;
  }

  static final RegExp _jwtPattern = RegExp(r'eyJ[A-Za-z0-9_\-]{5,}\.[A-Za-z0-9_\-]{5,}\.[A-Za-z0-9_\-]*');

  static String? _firstJwt(String text) {
    if (text.isEmpty) return null;
    final match = _jwtPattern.firstMatch(text);
    return match?.group(0);
  }

  static Map<String, dynamic>? _decodeJwtPart(String jwt, int index) {
    try {
      final parts = jwt.split('.');
      if (parts.length <= index) return null;
      var segment = parts[index];
      final mod = segment.length % 4;
      if (mod > 0) segment = segment.padRight(segment.length + (4 - mod), '=');
      final decoded = utf8.decode(base64Url.decode(segment));
      final value = jsonDecode(decoded);
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } catch (_) {
      return null;
    }
  }
}
