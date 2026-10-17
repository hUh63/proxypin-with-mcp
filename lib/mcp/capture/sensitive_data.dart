/*
 * Copyright 2026 Hongen Wang All rights reserved.
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

/// MCP 导出给 AI 前的敏感数据脱敏策略，FlowView / CurlBuilder / McpActions 共用，
/// 避免敏感头清单在多处各维护一份导致边界不一致。
///
/// @author wanghongen
class SensitiveData {
  SensitiveData._();

  /// 需要打码的请求/响应头（统一小写比较）
  static const Set<String> redactedHeaders = {
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
    'www-authenticate',
    'proxy-authenticate',
    'x-api-key',
    'api-key',
    'apikey',
    'x-auth-token',
    'x-access-token',
    'x-csrf-token',
    'x-xsrf-token',
    'x-id-token',
    'x-refresh-token',
    'private-token',
    'x-amz-security-token',
    'x-goog-api-key',
  };

  /// 名字里含这些片段的头也视为凭据（覆盖各家自定义命名，
  /// 如 X-Gitlab-Token / X-Session-Id / X-Client-Secret）。
  static const List<String> _sensitiveFragments = [
    'token',
    'api-key',
    'apikey',
    'secret',
    'session',
    'password',
    'credential',
  ];

  /// 合法但会被上面片段误伤的头，先放行
  static const Set<String> _nonSensitive = {'content-type', 'content-length'};

  /// 打码占位符
  static const String placeholder = '***redacted***';

  /// 该头是否属于敏感头
  static bool isRedactedHeader(String name) {
    final lower = name.toLowerCase();
    if (_nonSensitive.contains(lower)) return false;
    if (redactedHeaders.contains(lower)) return true;
    return _sensitiveFragments.any(lower.contains);
  }

  /// 敏感头返回占位符，否则原值
  static String redactValue(String name, String value) =>
      isRedactedHeader(name) ? placeholder : value;
}
