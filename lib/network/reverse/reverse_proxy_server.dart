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

import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/components/hosts.dart';
import 'package:proxypin/network/components/interceptor.dart';
import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/components/network_condition.dart';
import 'package:proxypin/network/components/report_server_interceptor.dart';
import 'package:proxypin/network/components/anti_cache_interceptor.dart';
import 'package:proxypin/network/components/request_block.dart';
import 'package:proxypin/network/components/request_rewrite.dart';
import 'package:proxypin/network/components/script.dart';
import 'package:proxypin/network/components/request_breakpoint.dart';
import 'package:proxypin/network/handle/http_proxy_handle.dart';
import 'package:proxypin/network/util/logger.dart';

import '../channel/network.dart';
import '../components/request_map.dart';
import '../http/codec.dart';
import '../channel/channel.dart';
import 'reverse_proxy.dart';

/// 反向代理服务器：独立监听一个端口，按路径规则把请求转发到配置的上游。
///
/// 与 [ProxyServer]（正向代理）的区别只在「目标由谁决定」：正向代理由客户端
/// 指定，反代由路径规则决定。除此之外**完全复用同一条处理链**——拦截器、抓包
/// 列表、Map Local、断点、脚本都能命中反代进来的流量。
class ReverseProxyServer {
  static ReverseProxyServer? current;

  /// 抓包事件监听器（由 [ProxyServer] 在启动时注入）。
  ///
  /// 反代**复用同一条事件链**，所以反代进来的请求/响应同样会出现在抓包列表里；
  /// 这里注入的就是正向代理正在用的那个 CombinedEventListener。
  static EventListener? listener;

  Server? _server;
  final Configuration configuration;

  ReverseProxyServer(this.configuration) {
    current = this;
  }

  bool get isRunning => _server?.isRunning ?? false;

  int get port => ReverseProxy.port;

  /// 启动反代服务。端口被占用等失败会抛出，由调用方提示。
  Future<void> start() async {
    if (isRunning) return;

    final effective = listener ?? CombinedEventListener(const []);
    final server = Server(configuration, listener: effective);

    // 与正向代理保持同一套拦截器（同一个排序规则），因此规则行为完全一致。
    List<Interceptor> interceptors = [
      Hosts(),
      RequestMapInterceptor.instance,
      RequestRewriteInterceptor.instance,
      ScriptInterceptor(),
      RequestBlockInterceptor(),
      RequestBreakpointInterceptor.instance,
      NetworkConditionInterceptor.instance,
      if (configuration.antiCacheEnabled) AntiCacheInterceptor(),
      ReportServerInterceptor()
    ];
    interceptors.sort((a, b) => a.priority.compareTo(b.priority));

    server.initChannel((channel) {
      channel.dispatcher.handle(
        HttpRequestCodec(),
        HttpResponseCodec(),
        HttpProxyChannelHandler(listener: effective, interceptors: interceptors, reverseProxy: true),
      );
    });

    await server.bind(port);
    _server = server;
    logger.i('[ReverseProxy] listen on $port, ${ReverseProxy.rules.length} rule(s)');
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server == null) return;
    try {
      await server.stop();
      logger.i('[ReverseProxy] stopped');
    } catch (e) {
      logger.e('[ReverseProxy] stop failed', error: e);
    }
  }

  /// 端口变更或规则变更后重启。
  Future<void> restart() async {
    await stop();
    if (ReverseProxy.enabled) {
      await start();
    }
  }

  /// 让运行状态与当前 [ReverseProxy] 配置一致。
  ///
  /// UI 与 MCP 工具改完配置后都调这里：开启且有规则就（重）启动，否则停掉。
  /// 这样调用方无需依赖 [ProxyServer]，避免循环依赖。
  static Future<void> apply(Configuration configuration) async {
    try {
      if (!ReverseProxy.enabled || ReverseProxy.rules.isEmpty) {
        await current?.stop();
        return;
      }
      await (current ?? ReverseProxyServer(configuration)).restart();
    } catch (e, s) {
      logger.e('[ReverseProxy] apply failed', error: e, stackTrace: s);
    }
  }
}
