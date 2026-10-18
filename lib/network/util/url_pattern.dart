import 'package:proxypin/network/util/logger.dart';

/// Shared URL wildcard-to-regex conversion utilities.
///
/// Many rule classes (rewrite, map, block, hosts, script, report-server, host-filter)
/// convert user-facing wildcard patterns (`*`, `?`) into [RegExp].
/// This file centralises that logic so changes to escaping or expansion
/// only need to happen in one place.
class UrlPattern {
  UrlPattern._();

  /// Convert a user-facing wildcard [pattern] to a [RegExp].
  ///
  /// `*` is expanded to `.*` and the first literal `?` is escaped to `\?`.
  static RegExp toRegExp(String pattern) {
    try {
      return RegExp(toRegExpString(pattern));
    } catch (e) {
      // 同 toHostRegExp：非法规则退化为永不匹配，不要在请求路径上抛。
      logger.w('非法的 URL 匹配规则，按永不匹配处理: $pattern', error: e);
      return RegExp(r'(?!)');
    }
  }

  /// Return the regex source string for a wildcard [pattern]
  /// without wrapping it in [RegExp] — useful when callers
  /// need to cache or compare the raw string.
  static String toRegExpString(String pattern) {
    return pattern.replaceAll("*", ".*").replaceFirst('?', '\\?');
  }

  /// Simpler variant used by host / domain matching where only
  /// `*` → `.*` expansion is needed (no `?` escaping).
  static RegExp toHostRegExp(String pattern) {
    // 用户手写的规则可能不是合法正则（例如只写了个 `[`）。这里不能抛：
    // 它在每条请求的匹配路径上，抛一次就是一条异常 + 一段日志，且会连带
    // 拖慢整条链路。非法规则退化成「永不匹配」。
    try {
      return RegExp(pattern.replaceAll("*", ".*"));
    } catch (e) {
      logger.w('非法的 URL 匹配规则，按永不匹配处理: $pattern', error: e);
      return RegExp(r'(?!)');
    }
  }
}
