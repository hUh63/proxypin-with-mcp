/*
 * 断点（Breakpoint）状态机端到端测试。
 *
 * 覆盖 lib/network/components/request_breakpoint.dart 的完整状态流转：
 *   请求挂起 → 放行(原样) / 修改后放行 / 中止(null)
 *   响应挂起 → 放行 / 修改后放行 / 中止(null)
 *   规则不匹配 / 未启用 时不得暂停（直通）
 *   pendingIntercepts / getPausedRequest / isPaused 等查询接口的一致性
 *
 * 说明：暂停流程内部会打开「断点执行器」子窗口（MultiWindow.openWindow）。
 * 该调用**未被 await**，在测试环境必然抛出「窗口插件不可用」异常。因此这里把
 * 触发暂停的调用放进 runZonedGuarded，只吞掉窗口插件类异常（其它异常照旧失败），
 * 这样 CI 上既不会因未处理的异步异常而误判，也不会掩盖真实缺陷。
 *
 * 不打 integration 标签，CI 会真实执行。
 */
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/components/manager/request_breakpoint_manager.dart';
import 'package:proxypin/network/components/request_breakpoint.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/util/file_read.dart';

@Timeout(Duration(seconds: 60))

/// 开始一次「可能被暂停」的拦截：把未处理的窗口插件异常收进 [errors]。
Future<T> _beginPaused<T>(Future<T> Function() body, List<Object> errors) {
  final guarded = runZonedGuarded<Future<T>?>(() => body(), (Object e, StackTrace s) => errors.add(e));
  expect(guarded, isNotNull, reason: '拦截回调同步抛异常（不应发生）：$errors');
  return guarded!;
}

void _expectOnlyWindowPluginErrors(List<Object> errors) {
  for (final e in errors) {
    final text = '$e'.toLowerCase();
    expect(text, anyOf(contains('plugin'), contains('channel'), contains('window')),
        reason: '断点暂停只应产生「窗口插件不可用」类异常，出现其它异常需排查：$e');
  }
}

HttpRequest _req(String url, HttpMethod method) =>
    HttpRequest(method, url, protocolVersion: 'HTTP/1.1')..hostAndPort = HostAndPort.of(url);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late io.Directory work;
  late RequestBreakpointManager manager;
  final interceptor = RequestBreakpointInterceptor.instance;
  final errors = <Object>[];

  setUpAll(() async {
    work = await io.Directory.systemTemp.createTemp('proxypin-breakpoint-');
    FileRead.userHome = work.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => work.path,
    );
    manager = await RequestBreakpointManager.instance;
  });

  tearDownAll(() async {
    FileRead.userHome = null;
    try {
      await work.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    errors.clear();
    manager.enabled = true;
    manager.list = [];
  });

  group('RequestBreakpointRule 匹配语义', () {
    test('enabled / 正则 / 方法过滤', () {
      final rule = RequestBreakpointRule(url: r'paused\.example\.com', method: HttpMethod.post);
      expect(rule.match('http://paused.example.com/api', method: HttpMethod.post), isTrue);
      expect(rule.match('http://paused.example.com/api', method: HttpMethod.get), isFalse);
      expect(rule.match('http://paused.example.com/api'), isTrue, reason: '调用方不给方法时不做方法过滤');
      expect(rule.match('http://other.example.com/api', method: HttpMethod.post), isFalse);

      rule.enabled = false;
      expect(rule.match('http://paused.example.com/api', method: HttpMethod.post), isFalse);

      final fromJson = RequestBreakpointRule.fromJson(
          {'enabled': true, 'url': r'x\.com', 'method': 'POST', 'interceptResponse': false});
      expect(fromJson.method, HttpMethod.post);
      expect(fromJson.interceptRequest, isTrue);
      expect(fromJson.interceptResponse, isFalse);
      final back = fromJson.toJson();
      expect(back['url'], r'x\.com');
      expect(back['method'], 'POST');
      expect(back['interceptResponse'], isFalse);
      expect(RequestBreakpointRule.fromJson({'method': 'NOT_A_METHOD', 'url': 'x'}).method, isNull,
          reason: '非法方法名降级为「不过滤」而不是抛异常');
    });
  });

  group('请求断点状态机', () {
    test('不匹配规则 / 未启用时直通，不进入暂停', () async {
      manager.list = [RequestBreakpointRule(url: r'other\.com')];
      final request = _req('http://pass.example.com/a', HttpMethod.get);
      final started = _beginPaused(() => interceptor.onRequest(request), errors);
      expect(identical(await started.timeout(const Duration(seconds: 5)), request), isTrue);
      expect(interceptor.isPaused(request.requestId), isFalse);

      manager.enabled = false;
      final request2 = _req('http://other.com/a', HttpMethod.get);
      final started2 = _beginPaused(() => interceptor.onRequest(request2), errors);
      expect(identical(await started2.timeout(const Duration(seconds: 5)), request2), isTrue);
      expect(interceptor.isPaused(request2.requestId), isFalse);
      expect(interceptor.pendingCount, 0);
      expect(errors, isEmpty, reason: '未进入暂停就不应触发窗口打开');
    });

    test('挂起 → 中止（resume null）：返回 null 并从队列移除', () async {
      manager.list = [RequestBreakpointRule(url: r'paused\.example\.com', interceptResponse: false)];
      final request = _req('http://paused.example.com/api/x', HttpMethod.get);
      final started = _beginPaused(() => interceptor.onRequest(request), errors);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(interceptor.isPaused(request.requestId), isTrue, reason: '匹配规则后必须挂起');
      expect(interceptor.isRequestPaused(request.requestId), isTrue);
      expect(interceptor.isResponsePaused(request.requestId), isFalse);
      expect(interceptor.pendingCount, 1);
      expect(identical(interceptor.getPausedRequest(request.requestId), request), isTrue);
      final pending = interceptor.pendingIntercepts();
      expect(pending, hasLength(1));
      expect(pending.single['id'], request.requestId);
      expect(pending.single['type'], 'request');
      expect(pending.single['method'], HttpMethod.get);
      expect(pending.single['url'], 'http://paused.example.com/api/x');

      interceptor.resumeRequest(request.requestId, null);
      expect(await started.timeout(const Duration(seconds: 5)), isNull, reason: '中止语义 = 返回 null');
      expect(interceptor.isPaused(request.requestId), isFalse);
      expect(interceptor.pendingCount, 0);
      expect(interceptor.getPausedRequest(request.requestId), isNull);
      _expectOnlyWindowPluginErrors(errors);
    });

    test('挂起 → 原样放行：返回同一个请求对象', () async {
      manager.list = [RequestBreakpointRule(url: r'paused\.example\.com', interceptResponse: false)];
      final request = _req('http://paused.example.com/api/x', HttpMethod.post);
      final started = _beginPaused(() => interceptor.onRequest(request), errors);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(interceptor.pendingCount, 1);

      final edited = _req('http://paused.example.com/api/x', HttpMethod.post);
      edited.headers.set('X-Edited', 'noop');
      interceptor.resumeRequest(request.requestId, edited);

      final resumed = (await started.timeout(const Duration(seconds: 5)))!;
      expect(identical(resumed, request), isTrue, reason: '必须复用原请求对象（代理链路依赖其身份）');
      expect(resumed.headers.get('X-Edited'), 'noop');
      expect(interceptor.pendingCount, 0);
      _expectOnlyWindowPluginErrors(errors);
    });

    test('挂起 → 修改后放行：方法 / URI / 头 / body 全部以修改版为准', () async {
      manager.list = [RequestBreakpointRule(url: r'paused\.example\.com', interceptResponse: false)];
      final request = _req('http://paused.example.com/api/original', HttpMethod.get);
      request.headers.set('X-Old', '1');
      request.headers.set('Content-Encoding', 'gzip');
      request.body = utf8.encode('original-body');

      final started = _beginPaused(() => interceptor.onRequest(request), errors);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(interceptor.pendingCount, 1);

      final modified = HttpRequest(HttpMethod.put, '/api/edited?q=1')..body = utf8.encode('edited-body');
      modified.headers.set('X-New', '2');
      modified.headers.set('X-Old', '3');
      modified.headers.set('Content-Encoding', 'gzip');

      interceptor.resumeRequest(request.requestId, modified);
      final resumed = await started.timeout(const Duration(seconds: 5));

      expect(identical(resumed, request), isTrue);
      expect(resumed!.method, HttpMethod.put);
      expect(resumed.uri, '/api/edited?q=1');
      expect(resumed.headers.get('X-New'), '2');
      expect(resumed.headers.get('X-Old'), '3', reason: '头的修改版必须整体覆盖');
      expect(resumed.headers.get(HttpHeaders.CONTENT_ENCODING), isNull, reason: 'Content-Encoding 必须被移除');
      expect(utf8.decode(resumed.body!), 'edited-body');
      expect(interceptor.pendingCount, 0);
      _expectOnlyWindowPluginErrors(errors);
    });

    test('resumeRequest 对未知 id 是安全空操作', () {
      interceptor.resumeRequest('not-exist', _req('http://x.com/a', HttpMethod.get));
      expect(interceptor.isPaused('not-exist'), isFalse);
    });
  });

  group('响应断点状态机', () {
    test('响应挂起 → 修改后放行：状态码 / 头 / body 生效', () async {
      manager.list = [RequestBreakpointRule(url: r'paused\.example\.com', interceptRequest: false)];
      final request = _req('http://paused.example.com/api/y', HttpMethod.get);
      final response = HttpResponse(HttpStatus.newStatus(200, 'OK'))
        ..body = utf8.encode('origin')
        ..request = request
        ..headers.set('X-Origin', '1');

      final started = _beginPaused(() => interceptor.onResponse(request, response), errors);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(interceptor.isResponsePaused(request.requestId), isTrue);
      expect(interceptor.isRequestPaused(request.requestId), isFalse);
      expect(interceptor.pendingCount, 1);
      final pending = interceptor.pendingIntercepts().single;
      expect(pending['type'], 'response');
      expect(pending['status'], 200);

      final mocked = HttpResponse(HttpStatus.newStatus(503, 'Mocked'))
        ..body = utf8.encode('mocked-body')
        ..headers.set('X-Mock', 'yes')
        ..headers.set('Content-Encoding', 'gzip');
      interceptor.resumeResponse(request.requestId, mocked);

      final resumed = (await started.timeout(const Duration(seconds: 5)))!;
      expect(identical(resumed, response), isTrue);
      expect(resumed.status.code, 503);
      expect(resumed.status.reasonPhrase, 'Mocked');
      expect(utf8.decode(resumed.body!), 'mocked-body');
      expect(resumed.headers.get('X-Mock'), 'yes');
      expect(resumed.headers.get(HttpHeaders.CONTENT_ENCODING), isNull);
      expect(interceptor.pendingCount, 0);
      _expectOnlyWindowPluginErrors(errors);
    });

    test('响应挂起 → 中止（resume null）：返回 null', () async {
      manager.list = [RequestBreakpointRule(url: r'paused\.example\.com', interceptRequest: false)];
      final request = _req('http://paused.example.com/api/z', HttpMethod.get);
      final response = HttpResponse(HttpStatus.newStatus(200, 'OK'))..request = request;

      final started = _beginPaused(() => interceptor.onResponse(request, response), errors);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(interceptor.isResponsePaused(request.requestId), isTrue);

      interceptor.resumeResponse(request.requestId, null);
      expect(await started.timeout(const Duration(seconds: 5)), isNull);
      expect(interceptor.isPaused(request.requestId), isFalse);
      expect(interceptor.pendingCount, 0);
      _expectOnlyWindowPluginErrors(errors);
    });

    test('响应不匹配规则时直通', () async {
      manager.list = [RequestBreakpointRule(url: r'other\.com', interceptRequest: false)];
      final request = _req('http://pass.example.com/api', HttpMethod.get);
      final response = HttpResponse(HttpStatus.newStatus(200, 'OK'))..request = request;
      final started = _beginPaused(() => interceptor.onResponse(request, response), errors);
      expect(identical(await started.timeout(const Duration(seconds: 5)), response), isTrue);
      expect(interceptor.pendingCount, 0);
    });
  });

  test('请求与响应可同时处于挂起态（pendingCount 汇总）', () async {
    manager.list = [
      RequestBreakpointRule(url: r'paused\.example\.com', interceptRequest: true, interceptResponse: true),
    ];
    final request = _req('http://paused.example.com/api/both', HttpMethod.post);
    final response = HttpResponse(HttpStatus.newStatus(200, 'OK'))..request = request;

    final reqStarted = _beginPaused(() => interceptor.onRequest(request), errors);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final respStarted = _beginPaused(() => interceptor.onResponse(request, response), errors);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(interceptor.isRequestPaused(request.requestId), isTrue);
    expect(interceptor.isResponsePaused(request.requestId), isTrue);
    expect(interceptor.pendingCount, 2);
    expect(interceptor.pendingIntercepts().map((e) => e['type']).toSet(), {'request', 'response'});

    interceptor.resumeRequest(request.requestId, null);
    interceptor.resumeResponse(request.requestId, null);
    expect(await reqStarted.timeout(const Duration(seconds: 5)), isNull);
    expect(await respStarted.timeout(const Duration(seconds: 5)), isNull);
    expect(interceptor.pendingCount, 0);
    _expectOnlyWindowPluginErrors(errors);
  });
}
