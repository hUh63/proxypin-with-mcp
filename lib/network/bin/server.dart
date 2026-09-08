/*
 * Copyright 2023 Hongen Wang All rights reserved.
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

import 'dart:async';
import 'dart:io';

import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/components/hosts.dart';
import 'package:proxypin/network/components/interceptor.dart';
import 'package:proxypin/network/components/network_condition.dart';
import 'package:proxypin/network/components/report_server_interceptor.dart';
import 'package:proxypin/network/components/request_block.dart';
import 'package:proxypin/network/components/request_rewrite.dart';
import 'package:proxypin/network/components/script.dart';
import 'package:proxypin/network/handle/http_proxy_handle.dart';
import 'package:proxypin/network/mcp/mcp_automation_manager.dart';
import 'package:proxypin/network/util/quic/quic_probe.dart';
import 'package:proxypin/network/mcp/mcp_event_automation.dart';
import 'package:proxypin/network/mcp/mcp_rule_engine.dart';
import 'package:proxypin/network/mcp/script_workflow_engine.dart';
import 'package:proxypin/network/components/manager/script_manager.dart';
import 'package:proxypin/network/components/js/script_engine.dart';
import 'package:proxypin/network/util/crts.dart';
import 'package:proxypin/utils/platform.dart';

import '../components/request_map.dart';
import '../http/codec.dart';
import '../channel/network.dart';
import '../util/logger.dart';
import '../util/system_proxy.dart';
import 'listener.dart';
import 'package:proxypin/network/components/request_breakpoint.dart';

Future<void> main() async {
  var configuration = await Configuration.instance;
  ProxyServer(configuration).start();
}

/// 代理服务器
class ProxyServer {
  static ProxyServer? current;

  //socket服务
  Server? server;

  //请求事件监听
  List<EventListener> listeners = [];

  //配置
  final Configuration configuration;

  ProxyServer(this.configuration) {
    current = this;
  }

  //是否启动
  bool get isRunning => server?.isRunning ?? false;

  ///是否启用https抓包
  bool get enableSsl => configuration.enableSsl;

  int get port => configuration.port;

  set enableSsl(bool enableSsl) {
    configuration.enableSsl = enableSsl;
    if (server == null || server?.isRunning == false) {
      return;
    }

    if (configuration.enableSystemProxy) {
      SystemProxy.setSslProxyEnable(enableSsl, port);
    }
  }

  /// 启动代理服务
  Future<Server> start() async {
    // 启动 QUIC 元数据探测监听（VPN 层会将 UDP:443 首包抄送到本机端口）
    unawaited(QuicProbe.instance.start());
    Server server = Server(configuration, listener: CombinedEventListener(listeners));

    List<Interceptor> interceptors = [
      Hosts(),
      RequestMapInterceptor.instance,
      RequestRewriteInterceptor.instance,
      ScriptInterceptor(),
      RequestBlockInterceptor(),
      RequestBreakpointInterceptor.instance, // Register the interceptor
      NetworkConditionInterceptor.instance,
      ReportServerInterceptor()
    ];

    interceptors.sort((a, b) => a.priority.compareTo(b.priority));

    server.initChannel((channel) {
      channel.dispatcher.handle(
        HttpRequestCodec(),
        HttpResponseCodec(),
        HttpProxyChannelHandler(listener: CombinedEventListener(listeners), interceptors: interceptors),
      );
    });

    return server.bind(port).then((serverSocket) async {
      logger.i("listen on $port");
      this.server = server;
      if (configuration.enableSystemProxy) {
        setSystemProxyEnable(true);
      }

      //初始化证书
      CertificateManager.initCAConfig();
      // 加载已持久化的 MCP 规则 + 触发代理启动事件
      try {
        await McpRuleEngine().loadRules();
      } catch (e, s) {
        logger.e('加载 MCP 规则失败', error: e, stackTrace: s);
      }
      // 接线工作流引擎：ScriptWorkflowEngine 的 DAG 执行器 → ScriptManager 真实脚本执行
      try {
        ScriptWorkflowEngine.instance.setExecutor((
          String scriptId,
          String scriptContent,
          String scriptType,
          Map<String, dynamic> parameters,
          Duration? timeout,
        ) async {
          // 按名查找 ScriptManager 中的脚本，走 runStandalone 路径（含 env 副作用）
          final mgr = await ScriptManager.instance;
          final scriptItem = mgr.list.cast<ScriptItem?>().firstWhere(
            (s) => s?.name == scriptId || s?.name == parameters['scriptName'],
            orElse: () => null,
          );
          if (scriptItem != null) {
            return await mgr.runStandalone(scriptItem);
          }
          // 找不到已注册脚本时，尝试直接执行 JavaScript 内容
          if (scriptType == 'javascript' && scriptContent.isNotEmpty) {
            return await ScriptManager.flutterJsPool.run((flutterJs) async {
              final jsResult = await flutterJs.evaluateAsync(
                'var context = ${parameters is Map ? parameters.toString() : '{}'}; $scriptContent\n  onRequest(context, {})');
              return await JavaScriptEngine.jsResultResolve(flutterJs, jsResult);
            });
          }
          logger.w('工作流节点 $scriptId 找不到匹配脚本，跳过');
          return null;
        });
        logger.i('ScriptWorkflowEngine 执行器已接线');
      } catch (e, s) {
        logger.e('接线 ScriptWorkflowEngine 执行器失败', error: e, stackTrace: s);
      }
      try {
        McpEventAutomation().triggerProxyStatusChange(ProxyStatus.started);
      } catch (e, s) {
        logger.e('触发代理启动事件失败', error: e, stackTrace: s);
      }
      // 触发 MCP 自动化任务（onProxyStart 触发器）
      try {
        unawaited(MCPAutomationManager().onProxyStart().catchError((e, s) {
          logger.e('MCP 自动化 onProxyStart 触发失败', error: e, stackTrace: s);
        }));
      } catch (_) {}
      // 代理启动时也评估规则引擎（proxyStatus 条件）
      try {
        unawaited(McpRuleEngine().evaluate({
          'type': 'proxyStatus',
          'status': 'started',
          'timestamp': DateTime.now().toIso8601String(),
        }).catchError((e, s) {
          logger.e('代理启动规则评估失败', error: e, stackTrace: s);
        }));
      } catch (_) {}
      return server;
    });
  }

  /// 停止代理服务
  Future<Server?> stop() async {
    QuicProbe.instance.stop();
    if (!isRunning) {
      return server;
    }

    if (configuration.enableSystemProxy) {
      await setSystemProxyEnable(false);
    }
    logger.i("stop on $port");
    await server?.stop();
    try {
      McpEventAutomation().triggerProxyStatusChange(ProxyStatus.stopped);
    } catch (e, s) {
      logger.e('触发代理停止事件失败', error: e, stackTrace: s);
    }
    // 触发 MCP 自动化任务（onProxyStop 触发器）
    try {
      unawaited(MCPAutomationManager().onProxyStop().catchError((e, s) {
        logger.e('MCP 自动化 onProxyStop 触发失败', error: e, stackTrace: s);
      }));
    } catch (_) {}
    // 代理停止时评估规则引擎
    try {
      unawaited(McpRuleEngine().evaluate({
        'type': 'proxyStatus',
        'status': 'stopped',
        'timestamp': DateTime.now().toIso8601String(),
      }).catchError((e, s) {
        logger.e('代理停止规则评估失败', error: e, stackTrace: s);
      }));
    } catch (_) {}
    return server;
  }

  /// 设置系统代理
  Future<void> setSystemProxyEnable(bool enable) async {
    if (!Platforms.isDesktop()) {
      return;
    }

    //关闭系统代理 恢复成外部代理地址
    if (!enable && configuration.externalProxy?.enabled == true) {
      await SystemProxy.setSystemProxy(configuration.externalProxy!.port!, enableSsl, configuration.proxyPassDomains);
      return;
    }

    await SystemProxy.setSystemProxyEnable(port, enable, enableSsl, passDomains: configuration.proxyPassDomains);
  }

  /// 重启代理服务
  Future<void> restart() async {
    await stop().whenComplete(() => start());
  }

  ///检查是否监听端口 没有监听则启动
  Future<void> retryBind() async {
    try {
      await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 350));
    } catch (e) {
      logger.d('端口未被占用，尝试重新绑定 $port');
      await restart();
    }
  }

  ///添加监听器
  void addListener(EventListener listener) {
    listeners.add(listener);
  }
}
