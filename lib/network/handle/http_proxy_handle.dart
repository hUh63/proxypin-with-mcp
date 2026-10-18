import 'dart:async';
import 'dart:convert';

import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/components/host_filter.dart';
import 'package:proxypin/network/components/interceptor.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/components/manager/rewrite_rule.dart';
import 'package:proxypin/network/components/request_rewrite.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_client.dart';
import 'package:proxypin/network/http/connection_pool.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/mcp/mcp_automation_manager.dart';
import 'package:proxypin/network/mcp/mcp_event_automation.dart';
import 'package:proxypin/network/mcp/mcp_rule_engine.dart';
import 'package:proxypin/network/reverse/reverse_proxy.dart';
import 'package:proxypin/network/util/capture_body_limiter.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/proxy_helper.dart';
import 'package:proxypin/network/util/attribute_keys.dart';
import 'package:proxypin/network/util/uri.dart';
import 'package:proxypin/utils/ip.dart';

/// http请求处理器
class HttpProxyChannelHandler extends ChannelHandler<HttpRequest> {
  EventListener? listener;

  final List<Interceptor> interceptors;

  /// 本连接是否由反向代理监听端口接入。为 true 时，请求目标由路径规则决定，
  /// 而不是由客户端指定（见 [ReverseProxy.rewrite]）。
  final bool reverseProxy;

  HttpProxyChannelHandler({this.listener, required this.interceptors, this.reverseProxy = false});

  @override
  Future<void> channelRead(ChannelContext channelContext, Channel channel, HttpRequest msg) async {
    //下载证书
    if (msg.uri == 'http://proxy.pin/ssl' || msg.requestUrl == 'http://127.0.0.1:${channel.socket.port}/ssl') {
      ProxyHelper.crtDownload(channelContext, channel, msg);
      return;
    }

    // 反向代理：先把请求目标改写成规则指定的上游，再走正常转发。
    // 必须放在下面「请求本服务」判断之前——否则 Host 指向本机监听端口时会被
    // 误判为「请求本服务」而短路。
    if (reverseProxy) {
      if (!ReverseProxy.rewrite(channelContext, msg)) {
        final body = utf8.encode('No reverse proxy rule matched: ${msg.path}');
        final resp = HttpResponse(
            HttpStatus.newStatus(502, 'Reverse proxy: no rule matched'),
            protocolVersion: msg.protocolVersion)
          ..request = msg
          ..body = body
          ..headers.contentType = 'text/plain; charset=utf-8'
          ..headers.contentLength = body.length;
        listener?.onResponse(channelContext, resp);
        channel.writeAndClose(channelContext, resp);
        return;
      }
    }

    //请求本服务
    if (((await localIps()).contains(msg.hostAndPort?.host) || '127.0.0.1' == msg.hostAndPort?.host) &&
        msg.hostAndPort?.port == channel.socket.port) {
      ProxyHelper.localRequest(channelContext, msg, channel, listener: listener);
      return;
    }

    //代理转发请求
    try {
      await forward(channelContext, channel, msg).catchError((error, trace) {
        exceptionCaught(channelContext, channel, error, trace: trace);
      });
    } catch (error, trace) {
      exceptionCaught(channelContext, channel, error, trace: trace);
    }
  }

  @override
  void exceptionCaught(ChannelContext channelContext, Channel channel, error, {StackTrace? trace}) {
    super.exceptionCaught(channelContext, channel, error, trace: trace);
    ProxyHelper.exceptionHandler(channelContext, channel, listener, channelContext.currentRequest, error);
    for (var interceptor in interceptors) {
      interceptor.onError(channelContext.currentRequest, error, trace);
    }
  }

  @override
  void channelInactive(ChannelContext channelContext, Channel channel) {
    Channel? remoteChannel = channelContext.serverChannel;
    remoteChannel?.close();
    // log.d("[${channel.id}] close  ${channel.error}");
  }

  /// 转发请求
  Future<void> forward(ChannelContext channelContext, Channel channel, HttpRequest httpRequest) async {
    // log.d("[${channel.id}] ${httpRequest.method.name} ${httpRequest.requestUrl}");
    //获取远程连接
    Channel? remoteChannel;

    if (channel.error != null) {
      final tryRewriteHandler =
          await _tryHandleRewriteResponseOnConnectFailure(channelContext, channel, httpRequest, channel.error);
      if (!tryRewriteHandler) {
        ProxyHelper.exceptionHandler(channelContext, channel, listener, httpRequest, channel.error);
        return;
      }
    } else {
      try {
        remoteChannel = await _getRemoteChannel(channelContext, channel, httpRequest);
      } catch (error, stackTrace) {
        log.e("[${channel.id}] 连接异常 ${httpRequest.method.name} ${httpRequest.requestUrl}",
            error: error, stackTrace: stackTrace);
        if (httpRequest.method == HttpMethod.connect) {
          channel.error = error; //记录异常
          //https代理新建connect连接请求 返回ok 会继续发起正常请求 可以获取到请求内容
          await channel.write(
              channelContext,
              HttpResponse(HttpStatus.ok.reason('Connection established'),
                  protocolVersion: httpRequest.protocolVersion));
          return;
        } else {
          final tryRewriteHandler =
              await _tryHandleRewriteResponseOnConnectFailure(channelContext, channel, httpRequest, channel.error);
          if (!tryRewriteHandler) {
            rethrow;
          }
        }
      }
    }

    //实现抓包代理转发
    if (httpRequest.method != HttpMethod.connect) {
      // log.d(
      //     "[${channel.id}] streamId:${httpRequest.streamId ?? ''} ${httpRequest.protocolVersion}  ${httpRequest.method.name} ${httpRequest.requestUrl}");
      if (HostFilter.filter(httpRequest.hostAndPort?.host, path: httpRequest.pathAndQuery)) {
        await remoteChannel?.write(channelContext, httpRequest);
        return;
      }

      HttpRequest? request = httpRequest;

      //拦截器
      for (var interceptor in interceptors) {
        try {
          request = await interceptor.onRequest(request!);
        } catch (e, s) {
          // 单个脚本/重写规则抛异常不能让整条请求挂掉（异常会冒到 dispatcher，
          // 直接关闭客户端连接，表现为「一开脚本所有请求都失败」）。
          log.e('请求拦截器执行失败: ${interceptor.runtimeType}', error: e, stackTrace: s);
          continue;
        }
        if (request == null) {
          listener?.onRequest(channel, httpRequest);
          channel.close();
          remoteChannel?.close();
          return;
        }
      }
      channelContext.currentRequest = request;

      listener?.onRequest(channel, request!);

      // 触发 MCP 事件自动化（HTTP 请求事件，按 URL 正则匹配）。
      // 未注册监听器时为空操作，不阻塞代理转发。
      try {
        McpEventAutomation().triggerHttpRequest(request!);
      } catch (e, s) {
        log.e('MCP triggerHttpRequest 失败', error: e, stackTrace: s);
      }

      // 触发 MCP 自动化任务（onRequest 触发器，按 URL/方法/Header 条件匹配）。
      // 未注册任务时为空操作，不阻塞代理转发。
      try {
        final reqMap = <String, dynamic>{
          'url': request!.requestUrl ?? '',
          'method': request.method.name,
          'headers': request.headers.toMap(),
        };
        unawaited(MCPAutomationManager().onRequest(reqMap).catchError((e, s) {
          log.e('MCP 自动化 onRequest 触发失败', error: e, stackTrace: s);
          // 必须返回与 Future 同类型的值：onRequest 是 Future<List<String>>，
          // handler 返回 void 会抛 Invalid argument(s) (onError)，
          // 异常就会逃出 catchError 并打断转发链路。
          return const <String>[];
        }));
      } catch (e, s) {
        log.e('MCP 自动化 onRequest 触发失败', error: e, stackTrace: s);
      }

      // MCP 自动化「拦截请求」动作：命中 onRequest 触发器 + blockRequest 动作的任务时，
      // 在真实发出请求前短路返回 403，不再转发。
      try {
        final blockMap = <String, dynamic>{
          'url': request!.requestUrl ?? '',
          'method': request.method.name,
          'headers': request.headers.toMap(),
        };
        if (await MCPAutomationManager().shouldBlockRequest(blockMap)) {
          log.i('[MCP Automation] Blocked request by automation rule: ${request.requestUrl}');
          final blockResp = HttpResponse(HttpStatus.newStatus(403, 'Blocked by MCP Automation'),
              protocolVersion: request.protocolVersion)
            ..request = request;
          blockResp.headers.set('X-ProxyPin-MCP-Blocked', 'true');
          listener?.onResponse(channelContext, blockResp);
          channel.writeAndClose(channelContext, blockResp);
          remoteChannel?.close();
          return;
        }
      } catch (e, s) {
        log.e('MCP 自动化 blockRequest 检查失败', error: e, stackTrace: s);
      }

      for (var interceptor in interceptors) {
        var response = await interceptor.execute(request!);
        if (response != null) {
          listener?.onResponse(channelContext, response);
          channel.writeAndClose(channelContext, response);
          // 上游连接在 forward 开头就建好了。本地 mock / 阻断短路时必须关掉：
          // Channel.close() 会先 cancel 读订阅，onDone 不再触发，channelInactive
          // 里的兜底也随之失效 → 每条被 mock 的请求都留一条无人回收的 socket。
          remoteChannel?.close();
          return;
        }
      }

      //重定向
      var uri = request!.domainPath;
      String? redirectUrl = await (RequestRewriteInterceptor.instance).getRedirectRule(uri);
      if (redirectUrl?.isNotEmpty == true) {
        await redirect(channelContext, channel, request, redirectUrl!);
        return;
      }

      //http1 直接请求  不需要携带域名
      if ((remoteChannel != null && !remoteChannel.useProxy) &&
          request.protocolVersion == HttpMessage.http1Version &&
          request.uri.startsWith(HostAndPort.httpScheme)) {
        final requestUri = request.requestUri!;
        request.uri = "${requestUri.path}${requestUri.hasQuery ? '?${requestUri.query}' : ''}";
      }
      await remoteChannel?.write(channelContext, request);
      // 转发完成后按「抓包内容上限」裁剪请求体（上游 #773）
      if (request != null) CaptureBodyLimiter.limit(request);
    }
  }

  Future<bool> _tryHandleRewriteResponseOnConnectFailure(
      ChannelContext channelContext, Channel clientChannel, HttpRequest request, dynamic error) async {
    final manager = await RequestRewriteManager.instance;
    final rewriteRule = manager.getRewriteRule(request.requestUrl, [RuleType.responseReplace, RuleType.responseUpdate]);
    if (rewriteRule == null) {
      return false;
    }

    final message = error.toString();
    final body = utf8.encode(message);
    final response = HttpResponse(HttpStatus.newStatus(502, message), protocolVersion: request.protocolVersion)
      ..request = request
      ..body = body
      ..headers.contentType = 'text/plain'
      ..headers.contentLength = body.length;

    log.d(
        "[${clientChannel.id}] tryHandleRewriteResponseOnConnectFailure for ${request.requestUrl} with rule ${rewriteRule.url} error: $error");
    var proxyHandler = HttpResponseProxyHandler(clientChannel, interceptors, listener: listener);
    await proxyHandler.channelRead(channelContext, clientChannel, response);
    return true;
  }

  //重定向
  Future<void> redirect(
      ChannelContext channelContext, Channel channel, HttpRequest httpRequest, String redirectUrl) async {
    var proxyHandler = HttpResponseProxyHandler(channel, interceptors, listener: listener);

    var redirectUri = UriBuild.build(redirectUrl, params: httpRequest.queries.isEmpty ? null : httpRequest.queries);
    log.d("[${channel.id}] 重定向 $redirectUri");

    if (redirectUri.isScheme('https')) {
      httpRequest.uri = redirectUri.path + (redirectUri.hasQuery ? '?${redirectUri.query}' : '');
    } else {
      httpRequest.uri = redirectUri.toString();
    }
    httpRequest.headers.host = '${redirectUri.host}${redirectUri.hasPort ? ':${redirectUri.port}' : ''}';
    var redirectChannel = await HttpClients.connect(redirectUri, proxyHandler, channelContext);
    // 旧上游连接（forward 开头为原始目标建立的）必须关闭：serverChannel 被顶掉后
    // channelInactive 只会关「当前」那条，旧 socket 变成无人回收的半开连接。
    final previousChannel = channelContext.serverChannel;
    channelContext.serverChannel = redirectChannel;
    if (previousChannel != null && !identical(previousChannel, redirectChannel)) {
      previousChannel.close();
    }
    await redirectChannel.write(channelContext, httpRequest);
  }

  /// 获取远程连接
  Future<Channel> _getRemoteChannel(
      ChannelContext channelContext, Channel clientChannel, HttpRequest httpRequest) async {
    //客户端连接 作为缓存
    Channel? remoteChannel = await channelContext.readyServerChannel;
    if (remoteChannel != null) {
      return remoteChannel;
    }

    var hostAndPort = httpRequest.hostAndPort ?? getHostAndPort(httpRequest);
    channelContext.host = hostAndPort;

    //远程转发
    HostAndPort? remote = channelContext.getAttribute(AttributeKeys.remote);
    //外部代理
    ProxyInfo? proxyInfo = channelContext.getAttribute(AttributeKeys.proxyInfo);

    if (remote != null || proxyInfo != null) {
      HostAndPort connectHost = remote ?? HostAndPort.host(proxyInfo!.host, proxyInfo.port!);
      final proxyChannel = await connectRemote(channelContext, clientChannel, connectHost);
      proxyChannel.useProxy = true;

      //代理建立完连接判断是否是https 需要发起connect请求
      if (httpRequest.method == HttpMethod.connect) {
        //proxy Authorization
        if (proxyInfo?.isAuthenticated == true) {
          String auth = base64Encode(utf8.encode("${proxyInfo?.username}:${proxyInfo?.password}"));
          httpRequest.headers.set(HttpHeaders.PROXY_AUTHORIZATION, 'Basic $auth');
        }

        await proxyChannel.write(channelContext, httpRequest);
      } else {
        if (clientChannel.isSsl) {
          await HttpClients.connectRequest(channelContext, hostAndPort, proxyChannel, proxyInfo: proxyInfo);
          await proxyChannel.secureSocket(channelContext,
              host: hostAndPort.host, supportedProtocols: httpRequest.protocolVersion == "HTTP/2" ? ["h2"] : null);
        }
      }

      return proxyChannel;
    }

    HostAndPort remoteAddress = hostAndPort;

    final ProxyInfo? socksProxy = channelContext.getAttribute(AttributeKeys.socks5Proxy);
    if (socksProxy != null) {
      remoteAddress = hostAndPort.copyWith(host: socksProxy.host, port: socksProxy.port!);
    }

    for (var interceptor in interceptors) {
      remoteAddress = await interceptor.preConnect(remoteAddress);
    }

    final proxyChannel = await connectRemote(channelContext, clientChannel, remoteAddress);
    // 是否对上游做 TLS：反向代理必须看 target 的 scheme（旧实现只看
    // clientChannel.isSsl —— 明文反代到 https:// 上游会把明文 HTTP 打进 443，
    // TLS 反代到 http:// 上游又会强行握手，两种情况都必然失败）。
    // 正向代理保持原语义（CONNECT 目标不一定是 443，不能只看端口）。
    final bool needsTls = reverseProxy ? remoteAddress.isSsl() : clientChannel.isSsl;
    if (needsTls) {
      await proxyChannel.secureSocket(channelContext,
          host: hostAndPort.host,
          supportedProtocols: channelContext.clientChannel?.selectedProtocol == null
              ? null
              : [channelContext.clientChannel!.selectedProtocol!]);
    }

    //https代理新建连接请求
    if (httpRequest.method == HttpMethod.connect) {
      await clientChannel.write(channelContext,
          HttpResponse(HttpStatus.ok.reason('Connection established'), protocolVersion: httpRequest.protocolVersion));
    }
    return proxyChannel;
  }

  /// 连接远程
  Future<Channel> connectRemote(ChannelContext channelContext, Channel clientChannel, HostAndPort connectHost) async {
    var proxyHandler = HttpResponseProxyHandler(clientChannel, interceptors, listener: listener);
    var proxyChannel = await channelContext.connectServerChannel(connectHost, proxyHandler);
    return proxyChannel;
  }
}

/// 顺序执行响应拦截器链：任一回调返回 null 即中断（表示停止处理），空列表为空操作。
///
/// 供 [HttpResponseProxyHandler] 的正常路径与 close-delimited 直通路径共用（上游 #956）。
Future<void> runResponseInterceptors(
    List<Interceptor> interceptors, HttpRequest request, HttpResponse response) async {
  if (interceptors.isEmpty) return;
  HttpResponse? r = response;
  for (var interceptor in interceptors) {
    try {
      r = await interceptor.onResponse(request, r!);
    } catch (e, s) {
      // 同请求方向：单个拦截器异常不应吞掉整条响应（此前会让客户端收不到任何数据）。
      log.e('响应拦截器执行失败: ${interceptor.runtimeType}', error: e, stackTrace: s);
      continue;
    }
    if (r == null) break;
  }
}

/// http响应代理
class HttpResponseProxyHandler extends ChannelHandler<HttpResponse> {
  //客户端的连接
  final Channel clientChannel;

  EventListener? listener;
  final List<Interceptor> interceptors;

  HttpResponseProxyHandler(this.clientChannel, this.interceptors, {this.listener});

  /// 对“不支持解析”的响应（如 close-delimited、超大 body）补跑一次响应拦截器链，
  /// 使脚本/重写等的 onResponse 仍被触发（修复上游 #956）。空拦截器为空操作。
  Future<void> interceptUnsupportedResponse(HttpRequest request, HttpResponse response) =>
      runResponseInterceptors(interceptors, request, response);

  /// 上报性能统计（性能面板的请求量 / 成功率 / 平均耗时 / QPS 全依赖它）。
  ///
  /// 早先这些数字只由 [ConnectionPool.execute] 累加，而转发走的是自研网络层、
  /// execute() 从未被调用，面板因此长期显示 0。
  void _recordTraffic(HttpRequest? request, HttpResponse response) {
    try {
      final start = request?.requestTime;
      final elapsed = start == null ? 0 : response.responseTime.difference(start).inMilliseconds;
      ConnectionPool.instance.recordTraffic(elapsedMs: elapsed, statusCode: response.status?.code);
    } catch (e) {
      log.w('record traffic failed', error: e);
    }
  }

  @override
  Future<void> channelRead(ChannelContext channelContext, Channel channel, HttpResponse msg) async {
    var request = msg.request ?? channelContext.currentRequest;
    request?.response = msg;
    _recordTraffic(request, msg);

    // 响应就绪后评估 MCP 规则引擎（此时 request/response 字段齐全，
    // 可匹配 URL、方法、状态码、耗时、大小等全部条件）。
    // 未注册规则时为空操作，不阻塞转发。
    if (request != null) {
      unawaited(McpRuleEngine().evaluate(request).catchError((e, s) {
        log.e('MCP 规则引擎评估失败', error: e, stackTrace: s);
      }));
      // 触发 MCP 自动化任务（onResponse 触发器，按 URL/状态码条件匹配）。
      // 未注册任务时为空操作，不阻塞转发。
      try {
        final respMap = <String, dynamic>{
          'url': request.requestUrl ?? '',
          'statusCode': msg.status?.code ?? 0,
        };
        unawaited(MCPAutomationManager().onResponse(respMap).catchError((e, s) {
          log.e('MCP 自动化 onResponse 触发失败', error: e, stackTrace: s);
          return const <String>[];
        }));
      } catch (e, s) {
        log.e('MCP 自动化 onResponse 触发失败', error: e, stackTrace: s);
      }
    }

    //域名是否过滤
    if (HostFilter.filter(request?.hostAndPort?.host, path: request?.pathAndQuery) || request?.method == HttpMethod.connect) {
      await clientChannel.write(channelContext, msg);
      return;
    }

    // log.i("[${clientChannel.id}] Response $msg");

    HttpResponse? response = msg;
    //请求上下文缺失（如 h2 响应早于请求关联）时直接透传，不走拦截器
    if (request == null) {
      listener?.onResponse(channelContext, msg);
      await clientChannel.write(channelContext, msg);
      return;
    }
    //拦截器
    for (var interceptor in interceptors) {
      response = await interceptor.onResponse(request, response!);
      if (response == null) {
        logger.d("[${clientChannel.id}] Interceptor returned null, stopping processing");
        // Interceptor returned null, stopping processing
        listener?.onResponse(channelContext, msg);
        channel.close();
        return;
      }
    }

    // Ensure request is linked if not present
    response?.request ??= request;
    listener?.onResponse(channelContext, response!);
    //发送给客户端
    await clientChannel.write(channelContext, response!);
    // 转发完成后按「抓包内容上限」裁剪 body（上游 #773）
    CaptureBodyLimiter.limit(response!);
  }

  @override
  void channelInactive(ChannelContext channelContext, Channel channel) {
    clientChannel.close();
  }

  @override
  void exceptionCaught(ChannelContext channelContext, Channel channel, error, {StackTrace? trace}) {
    super.exceptionCaught(channelContext, channel, error, trace: trace);
    for (var interceptor in interceptors) {
      interceptor.onError(channelContext.currentRequest, error, trace);
    }
  }
}
