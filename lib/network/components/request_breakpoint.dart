import 'dart:async';
import 'dart:convert';

import 'package:proxypin/network/components/interceptor.dart';
import 'package:proxypin/network/components/manager/environment_manager.dart';
import 'package:proxypin/network/components/manager/request_breakpoint_manager.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/cache.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/multi_window.dart';

import '../http/http_headers.dart';

class RequestBreakpointInterceptor extends Interceptor {
  static RequestBreakpointInterceptor instance =
      RequestBreakpointInterceptor._();

  final manager = RequestBreakpointManager.instance;

  // 被暂停请求/响应的详情（供 MCP 拦截队列查询）
  final Map<String, HttpRequest> _pausedRequestDetails = {};
  final Map<String, HttpResponse> _pausedResponseDetails = {};

  // 10 分钟超时，超时后自动清理详情，避免大请求/响应体长期驻留内存
  late final ExpiringCache<String, Completer<HttpRequest?>> _pausedRequests;
  late final ExpiringCache<String, Completer<HttpResponse?>> _pausedResponses;

  RequestBreakpointInterceptor._() {
    _pausedRequests = ExpiringCache(
      duration: Duration(minutes: 10),
      onExpire: (id, completer) {
        final detail = _pausedRequestDetails.remove(id);
        // 超时必须放行：只清详情不完成 Completer 的话，onRequest 里的
        // completer.future 永不返回，这条请求（连同连接、已读入的 buffer）
        // 会一直挂着，客户端看到的是「无响应」而不是超时。
        if (!completer.isCompleted) {
          logger.w('断点请求 $id 超过 10 分钟未处理，自动放行');
          completer.complete(detail);
        }
      },
    );
    _pausedResponses = ExpiringCache(
      duration: Duration(minutes: 10),
      onExpire: (id, completer) {
        final detail = _pausedResponseDetails.remove(id);
        if (!completer.isCompleted) {
          logger.w('断点响应 $id 超过 10 分钟未处理，自动放行');
          completer.complete(detail);
        }
      },
    );
  }

  /// 待处理拦截数量（请求 + 响应）
  int get pendingCount => _pausedRequests.length + _pausedResponses.length;

  /// 是否有指定 ID 的暂停项
  bool isPaused(String id) =>
      _pausedRequests.containsKey(id) || _pausedResponses.containsKey(id);

  /// 指定 ID 是否为暂停的请求
  bool isRequestPaused(String id) => _pausedRequests.containsKey(id);

  /// 指定 ID 是否为暂停的响应
  bool isResponsePaused(String id) => _pausedResponses.containsKey(id);

  /// 获取被暂停的请求对象（供 MCP approve 修改使用），不存在返回 null
  HttpRequest? getPausedRequest(String id) => _pausedRequestDetails[id];

  /// 用环境变量渲染 {{name}}。若 EnvironmentManager 未加载或未启用,返回原字符串。
  static String? _renderEnv(String? input) =>
      EnvironmentManager.tryRender(input);

  /// 渲染 headers 里所有值中的 {{var}}。多值 header(如 Set-Cookie)每个值独立渲染,不丢值。
  static void _renderHeadersInPlace(HttpHeaders headers) {
    if (EnvironmentManager.instanceOrNull?.enabled != true) return;
    // 先收集需要重写的 (name, renderedList),避免边遍历边改
    final rewrites = <String, List<String>>{};
    headers.forEach((name, values) {
      if (!values.any((v) => v.contains('{{'))) return;
      rewrites[name] = values.map((v) => _renderEnv(v) ?? v).toList();
    });
    // 用 remove + add 重建每个多值列表,保留全部值
    rewrites.forEach((name, values) {
      headers.remove(name);
      for (final v in values) {
        headers.add(name, v);
      }
    });
  }

  /// 渲染 body 里的 {{var}}。仅在 body 看起来是"较小的文本"时才尝试解码替换,
  /// 二进制/大 body/无变量占位时保持原字节不动,避免破坏和无谓的 decode 开销。
  static const int _renderBodyMaxSize = 512 * 1024; // 512KB 以上跳过

  /// 已知的二进制/非文本 MIME 前缀,遇到直接跳过 render
  static const List<String> _binaryContentTypes = [
    'image/',
    'video/',
    'audio/',
    'application/octet-stream',
    'application/zip',
    'application/x-protobuf',
    'application/x-msgpack',
    'application/pdf',
    'font/',
  ];

  static bool _looksBinary(String? contentType) {
    if (contentType == null || contentType.isEmpty) return false;
    final ct = contentType.toLowerCase();
    return _binaryContentTypes.any(ct.startsWith);
  }

  static List<int>? _renderBody(
    List<int>? body,
    String? charset, {
    String? contentType,
  }) {
    if (body == null || body.isEmpty) return body;
    if (EnvironmentManager.instanceOrNull?.enabled != true) return body;
    if (body.length > _renderBodyMaxSize) return body;
    if (_looksBinary(contentType)) return body;
    try {
      final text = (charset == 'utf-8' || charset == 'utf8' || charset == null)
          ? utf8.decode(body)
          : String.fromCharCodes(body);
      if (!text.contains('{{')) return body;
      final rendered = _renderEnv(text) ?? text;
      return (charset == 'utf-8' || charset == 'utf8' || charset == null)
          ? utf8.encode(rendered)
          : rendered.codeUnits;
    } catch (_) {
      return body; // 非法文本,原样返回
    }
  }

  @override
  Future<HttpRequest?> onRequest(HttpRequest request) async {
    RequestBreakpointManager requestBreakpointManager = await manager;
    if (!requestBreakpointManager.enabled) return request;

    var url = request.requestUrl;
    for (var rule in requestBreakpointManager.list) {
      if (rule.match(url, method: request.method) && rule.interceptRequest) {
        Completer<HttpRequest?> completer = Completer();
        _pausedRequests[request.requestId] = completer;
        _pausedRequestDetails[request.requestId] = request;

        // Open Breakpoint Executor Window
        MultiWindow.openWindow(
          "Breakpoint - Request",
          'BreakpointExecutor',
          args: {
            'type': 'request',
            'request': request.toJson(),
            'requestId': request.requestId,
          },
        );

        return completer.future.then((req) {
          if (req == null) {
            logger.d(
              'Request ${request.requestId} was resumed null, aborting request',
            );
            return null;
          }

          request.method = req.method;
          // 先渲染 URI 中的 {{var}}(如 host / path / query 里可能用到)
          final renderedUri = _renderEnv(req.uri) ?? req.uri;
          Uri uri = Uri.parse(renderedUri);
          if (uri.isScheme('https')) {
            request.uri = uri.path + (uri.hasQuery ? "?${uri.query}" : "");
          } else {
            request.uri = uri.toString();
          }

          request.headers.clear();
          request.headers.addAll(req.headers);
          _renderHeadersInPlace(request.headers);
          request.headers.remove(HttpHeaders.CONTENT_ENCODING);

          request.body = _renderBody(
            req.body,
            request.charset,
            contentType: request.headers.contentType,
          );
          logger.d(
            'Resuming request ${request.requestId} with modified request',
          );
          return request;
        });
      }
    }
    return request;
  }

  @override
  Future<HttpResponse?> onResponse(
    HttpRequest request,
    HttpResponse response,
  ) async {
    RequestBreakpointManager requestBreakpointManager = await manager;
    if (!requestBreakpointManager.enabled) return response;

    var url = request.requestUrl;
    for (var rule in requestBreakpointManager.list) {
      if (rule.match(url, method: request.method) && rule.interceptResponse) {
        Completer<HttpResponse?> completer = Completer();
        _pausedResponses[request.requestId] = completer;
        _pausedResponseDetails[request.requestId] = response;

        // Open Breakpoint Executor Window
        MultiWindow.openWindow(
          "Breakpoint - Response",
          'BreakpointExecutor',
          args: {
            'type': 'response',
            'request': request.toJson(),
            'response': response.toJson(),
            'requestId': request.requestId,
          },
        );

        return completer.future.then((res) {
          if (res == null) {
            return null;
          }

          response.status = res.status;
          response.headers.clear();
          response.headers.addAll(res.headers);
          _renderHeadersInPlace(response.headers);
          response.headers.remove(HttpHeaders.CONTENT_ENCODING);

          response.body = _renderBody(
            res.body,
            response.charset,
            contentType: response.headers.contentType,
          );

          logger.d(
            'Resuming response for request ${request.requestId} with modified response',
          );
          return response;
        });
      }
    }
    return response;
  }

  void resumeRequest(String requestId, HttpRequest? request) {
    if (_pausedRequests.containsKey(requestId)) {
      _pausedRequests.remove(requestId)?.complete(request);
    }
    _pausedRequestDetails.remove(requestId);
  }

  void resumeResponse(String requestId, HttpResponse? response) {
    if (_pausedResponses.containsKey(requestId)) {
      _pausedResponses.remove(requestId)?.complete(response);
    }
    _pausedResponseDetails.remove(requestId);
  }

  /// 获取待处理拦截的详情列表（供 MCP get_pending_intercepts 工具使用）
  List<Map<String, dynamic>> pendingIntercepts() {
    final result = <Map<String, dynamic>>[];

    _pausedRequestDetails.forEach((id, req) {
      result.add({
        'id': id,
        'type': 'request',
        'method': req.method,
        'url': req.requestUrl,
        'headers': req.headers.toJson(),
        'body': req.body != null
            ? utf8.decode(req.body!, allowMalformed: true)
            : null,
      });
    });

    _pausedResponseDetails.forEach((id, res) {
      result.add({
        'id': id,
        'type': 'response',
        'status': res.status.code,
        'headers': res.headers.toJson(),
        'body': res.body != null
            ? utf8.decode(res.body!, allowMalformed: true)
            : null,
      });
    });

    return result;
  }
}
