import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/components/interceptor.dart';
import 'package:proxypin/network/handle/http_proxy_handle.dart';
import 'package:proxypin/network/http/http.dart';

/// 上游 #956 回归测试。
///
/// 当响应不支持解析（无 Content-Length、无 Transfer-Encoding，靠连接关闭定界）
/// 时，代理会走“原样转发”路径而不经过 HttpResponseProxyHandler。修复要求该路径
/// 仍触发响应拦截器链（脚本 onResponse），否则依赖 onResponse 的脚本会静默失效。
/// 此处直接验证抽取出的 [runResponseInterceptors]。
class _RecordingInterceptor extends Interceptor {
  int calls = 0;
  HttpResponse? last;
  bool returnNull = false;

  @override
  Future<HttpResponse?> onResponse(HttpRequest request, HttpResponse response) async {
    calls++;
    last = response;
    return returnNull ? null : response;
  }
}

void main() {
  test('runResponseInterceptors 依次调用 onResponse 链', () async {
    final a = _RecordingInterceptor();
    final b = _RecordingInterceptor();
    final request = HttpRequest(HttpMethod.get, 'http://example.com/no-length');
    final response = HttpResponse(HttpStatus.ok, protocolVersion: 'HTTP/1.1');
    response.request = request;

    await runResponseInterceptors([a, b], request, response);

    expect(a.calls, 1);
    expect(b.calls, 1);
    expect(b.last, same(response));
  });

  test('某个拦截器返回 null 时中断后续链', () async {
    final a = _RecordingInterceptor()..returnNull = true;
    final b = _RecordingInterceptor();
    final request = HttpRequest(HttpMethod.get, 'http://example.com/');
    final response = HttpResponse(HttpStatus.ok);

    await runResponseInterceptors([a, b], request, response);

    expect(a.calls, 1);
    expect(b.calls, 0);
  });

  test('空拦截器列表为空操作、不抛异常', () async {
    final request = HttpRequest(HttpMethod.get, 'http://example.com/');
    final response = HttpResponse(HttpStatus.ok);

    await runResponseInterceptors(const [], request, response);
  });
}
