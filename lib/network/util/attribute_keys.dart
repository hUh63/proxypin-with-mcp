/// @author wanghongen
/// 2023/5/23
interface class AttributeKeys {
  static const String host = "HOST";
  static const String domain = "DOMAIN";
  static const String uri = "URI";
  static const String request = "REQUEST";
  static const String remote = "REMOTE";
  static const String proxyInfo = "PROXY_INFO";
  static const String socks5Proxy = "SOCKS5_PROXY";
  static const String processInfo = "PROCESS_INFO";
  static const String skipCapture = "SKIP_CAPTURE";
  /// 该连接是否由反向代理监听端口接入（见 ReverseProxyServer）
  static const String reverseProxy = "REVERSE_PROXY";
  /// 命中的反向代理规则 id
  static const String reverseProxyRule = "REVERSE_PROXY_RULE";
  
  // HTTP/2 相关属性
  static const String h2FallbackToHttp1 = "H2_FALLBACK_TO_HTTP1"; // HTTP/2 降级到 HTTP/1.1
  static const String h2ShouldRetry = "H2_SHOULD_RETRY"; // HTTP/2 连接需要重试
}
