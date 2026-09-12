/*
 * 去缓存拦截器（Anticache）
 *
 * 作用：剥掉客户端的条件请求头（If-Modified-Since / If-None-Match / If-Range），
 * 并强制 Cache-Control/Pragma 为 no-cache，使服务端每次真正回源，
 * 便于抓包/调试时看到完整响应（缓存命中的 304 会拿不到 body）。
 *
 * 参考：mitmproxy 的 anticache、Proxyman 的 No Caching。
 * 与其它拦截器的关系：优先级设为靠前（priority 10），在改写/脚本之前先清理请求头。
 */
import 'package:proxypin/network/components/interceptor.dart';
import 'package:proxypin/network/http/http.dart';

class AntiCacheInterceptor extends Interceptor {
  @override
  int get priority => 10;

  @override
  Future<HttpRequest?> onRequest(HttpRequest request) async {
    request.headers.remove('If-Modified-Since');
    request.headers.remove('If-None-Match');
    request.headers.remove('If-Range');
    request.headers.set('Cache-Control', 'no-cache');
    request.headers.set('Pragma', 'no-cache');
    return request;
  }
}
