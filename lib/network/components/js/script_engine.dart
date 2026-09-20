import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_js/flutter_js.dart';
import 'package:proxypin/network/components/js/xhr.dart';

import '../../http/http.dart';
import '../../http/http.dart' as http;
import '../../http/http_headers.dart';
import '../../util/lang.dart';
import '../../util/logger.dart';
import '../../util/uri.dart';
import 'file.dart';
import 'md5.dart';
import 'requests.dart';
import 'require.dart';

class JavaScriptRuntimePool {
  final int size;
  final Function(dynamic args)? consoleLog;

  final List<_PooledJavaScriptRuntime> _runtimes = [];

  JavaScriptRuntimePool({required int size, this.consoleLog}) : size = size < 1 ? 1 : size;

  Future<T> run<T>(Future<T> Function(JavascriptRuntime flutterJs) action) async {
    final runtime = _selectRuntime();
    runtime.pending++;
    try {
      final flutterJs = await runtime.flutterJs.onError((error, stackTrace) {
        _runtimes.remove(runtime);
        _releaseRuntime(runtime);
        throw error!;
      });
      return await JavaScriptEngine.synchronized(flutterJs, () => action(flutterJs));
    } on TimeoutException catch (e) {
      _runtimes.remove(runtime);
      _releaseRuntime(runtime);
      logger.e('JavaScript runtime timed out and was removed from pool: $e');
      rethrow;
    } finally {
      runtime.pending--;
    }
  }

  /// 释放一个被移出池的运行时：取消其 XHR 轮询定时器并销毁运行时（上游 #674）。
  ///
  /// 此前只是 `_runtimes.remove(runtime)`，运行时与它的 20ms 轮询定时器都不再回收；
  /// 反复出现脚本超时/异常时会累积大量空转定时器，CPU 持续上升。
  void _releaseRuntime(_PooledJavaScriptRuntime runtime) {
    unawaited(runtime.flutterJs
        .then((js) {
          js.disposeXhr();
          js.dispose();
        })
        .catchError((Object _) {}));
  }

  Future<void> dispose() async {
    final runtimes = List<_PooledJavaScriptRuntime>.of(_runtimes);
    _runtimes.clear();
    for (final runtime in runtimes) {
      final js = await runtime.flutterJs;
      js.disposeXhr();
      js.dispose();
    }
  }

  _PooledJavaScriptRuntime _selectRuntime() {
    for (final runtime in _runtimes) {
      if (runtime.pending == 0) {
        return runtime;
      }
    }

    if (_runtimes.length < size) {
      final runtime = _PooledJavaScriptRuntime(JavaScriptEngine.getJavaScript(consoleLog: consoleLog));
      _runtimes.add(runtime);
      return runtime;
    }

    return _runtimes.reduce((current, next) => current.pending <= next.pending ? current : next);
  }
}

class _PooledJavaScriptRuntime {
  final Future<JavascriptRuntime> flutterJs;
  int pending = 0;

  _PooledJavaScriptRuntime(this.flutterJs);
}

class JavaScriptEngine {
  static final _runtimeLocks = Expando<Future<void>>('javascriptRuntimeLocks');

  static int defaultRuntimePoolSize = 4;
  static Duration runtimeTimeout = const Duration(seconds: 30);

  static Future<T> synchronized<T>(JavascriptRuntime flutterJs, Future<T> Function() action) async {
    while (_runtimeLocks[flutterJs] != null) {
      await _runtimeLocks[flutterJs]!.timeout(runtimeTimeout);
    }

    final completer = Completer<void>();
    _runtimeLocks[flutterJs] = completer.future;
    var completed = false;
    try {
      return await action().timeout(runtimeTimeout);
    } finally {
      _runtimeLocks[flutterJs] = null;
      if (!completed) {
        completed = true;
        completer.complete();
      }
    }
  }

  static Future<JavascriptRuntime> getJavaScript({Function(dynamic args)? consoleLog}) async {
    final JavascriptRuntime flutterJs = getJavascriptRuntime(xhr: false);

    // register channel callback
    if (consoleLog != null) {
      final channelCallbacks = JavascriptRuntime.channelFunctionsRegistered[flutterJs.getEngineInstanceId()];
      channelCallbacks!["ConsoleLog"] = consoleLog;
    }
    Md5Bridge.registerMd5(flutterJs);
    FileBridge.registerFile(flutterJs);
    // 上游 #719：注入全局 require(url) / loadLibrary(url)，支持加载第三方 JS 库
    RequireBridge.registerRequire(flutterJs);

    // 上游 #645：注入全局 clearRequests() / removeRequest(id)，让脚本能自行清理列表
    RequestsBridge.registerRequests(flutterJs);

    flutterJs.enableFetch2();
    return flutterJs;
  }

  /// js结果转换
  static Future<dynamic> jsResultResolve(JavascriptRuntime flutterJs, JsEvalResult jsResult) async {
    try {
      if (jsResult.isPromise || jsResult.rawResult is Future) {
        jsResult = await flutterJs.handlePromise(jsResult);
      }

      if (jsResult.isPromise || jsResult.rawResult is Future) {
        jsResult = await flutterJs.handlePromise(jsResult);
      }
    } catch (e) {
      throw SignalException(jsResult.stringResult);
    }

    var result = jsResult.rawResult;
    if (Platform.isMacOS || Platform.isIOS) {
      result = flutterJs.convertValue(jsResult);
    }
    if (result is String) {
      result = jsonDecode(result);
    }
    if (jsResult.isError) {
      logger.e('jsResultResolve error: ${jsResult.stringResult}');
      throw SignalException(jsResult.stringResult);
    }
    return result;
  }

  //转换js request
  static Future<Map<String, dynamic>> convertJsRequest(HttpRequest request) async {
    var requestUri = request.requestUri;
    return {
      'host': requestUri?.host,
      'url': request.requestUrl,
      'path': requestUri?.path,
      'queries': requestUri?.queryParameters,
      'headers': headersForScript(request.headers),
      'method': request.method.name,
      'body': await request.decodeBodyString(),
      'rawBody': request.body
    };
  }

  /// 上游 #901: 多值响应头（如多个 Set-Cookie）在脚本上下文中保留为数组，
  /// 不再用 toMap() 的 join(";") 合并——Set-Cookie 里的分号是 Cookie 参数分隔符，
  /// 合并后回写会被客户端当成单条 Cookie 解析，导致会话丢失。
  /// 单值头仍输出字符串，兼容既有脚本；回写侧字符串走 set、数组走 addValues。
  static Map<String, dynamic> headersForScript(HttpHeaders headers) {
    final Map<String, dynamic> result = {};
    headers.forEach((name, values) {
      if (values.length == 1) {
        result[name] = values.first;
      } else {
        result[name] = List<String>.of(values);
      }
    });
    return result;
  }

  /// 脚本是否未修改请求：返回对象去掉 scriptContext 后与原始请求结构一致即视为未改动。
  /// 用于在脚本未真正改动请求时跳过 convertHttpRequest 的有损重建（避免 query 重编码/header 重排破坏签名）。
  /// 直接复用 runScript 已构建的请求 Map 做结构化深比较，无需再次序列化。
  static bool isRequestUnchanged(Map<dynamic, dynamic> originalRequest, dynamic result) {
    if (result is! Map) return false;
    final copy = Map<dynamic, dynamic>.of(result)..remove('scriptContext');
    return _deepEquals(copy, originalRequest);
  }

  static bool _deepEquals(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  //转换js response
  static Future<Map<String, dynamic>> convertJsResponse(HttpResponse response) async {
    dynamic body = await response.decodeBodyString();
    if (response.contentType.isBinary) {
      body = response.body;
    }

    return {
      'headers': headersForScript(response.headers),
      'statusCode': response.status.code,
      'body': body,
      'rawBody': response.body
    };
  }

  //http request
  static HttpRequest convertHttpRequest(HttpRequest request, Map<dynamic, dynamic> map) {
    request.headers.clear();
    request.method = http.HttpMethod.values.firstWhere((element) => element.name == map['method']);
    String query = UriUtils.mapToQuery(map['queries']);

    var requestUri = request.requestUri!.replace(path: map['path'], query: query);
    if (requestUri.isScheme('https')) {
      var query = requestUri.query;
      request.uri = requestUri.path + (query.isNotEmpty ? '?${requestUri.query}' : '');
    } else {
      request.uri = requestUri.toString();
    }

    map['headers'].forEach((key, value) {
      if (value is List) {
        request.headers.addValues(key, value.map((e) => e.toString()).toList());
        return;
      }
      request.headers.set(key, value);
    });

    request.headers.remove(HttpHeaders.CONTENT_ENCODING);
    request.headers.remove(HttpHeaders.TRANSFER_ENCODING);

    //判断是否是二进制
    if (Lists.getElementType(map['body']) == int) {
      request.body = Lists.convertList<int>(map['body']);
    } else {
      request.body = map['body']?.toString().codeUnits;

      if (request.body != null && (request.charset == 'utf-8' || request.charset == 'utf8')) {
        request.body = utf8.encode(map['body'].toString());
      }
    }

    // 上游 #844：脚本改了 body 之后必须同步 Content-Length。
    // 否则会带着旧的 Content-Length 发出，服务端按旧长度读包等不到数据 → 卡住/超时。
    if (request.body != null) {
      request.headers.contentLength = request.body!.length;
    }
    return request;
  }

  //http response
  static HttpResponse convertHttpResponse(HttpResponse response, Map<dynamic, dynamic> map) {
    response.headers.clear();
    response.status = HttpStatus.valueOf(map['statusCode']);
    map['headers'].forEach((key, value) {
      if (value is List) {
        response.headers.addValues(key, value.map((e) => e.toString()).toList());
        return;
      }

      response.headers.set(key, value);
    });

    response.headers.remove(HttpHeaders.CONTENT_ENCODING);
    response.headers.remove(HttpHeaders.TRANSFER_ENCODING);

    //判断是否是二进制
    if (Lists.getElementType(map['body']) == int) {
      response.body = Lists.convertList<int>(map['body']);
    } else {
      response.body = map['body']?.toString().codeUnits;
      if (response.body != null && (response.charset == 'utf-8' || response.charset == 'utf8')) {
        response.body = utf8.encode(map['body'].toString());
      }
    }

    // 上游 #844：响应体被脚本改写后同步 Content-Length，
    // 否则客户端按旧长度读取，等不到剩余字节 → 抓包显示 200 但 App 侧超时。
    if (response.body != null) {
      response.headers.contentLength = response.body!.length;
    }

    return response;
  }
}
