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
import 'dart:typed_data';

import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/components/hosts.dart';
import 'package:proxypin/network/components/interceptor.dart';
import 'package:proxypin/network/components/network_condition.dart';
import 'package:proxypin/network/components/report_server_interceptor.dart';
import 'package:proxypin/network/components/request_block.dart';
import 'package:proxypin/network/components/request_rewrite.dart';
import 'package:proxypin/network/components/script.dart';
import 'package:proxypin/network/components/ws_traffic_server.dart';
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
import '../util/windows_takeover.dart';
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

  /// QUIC 元数据探测监听（VPN 层经本机 TCP 抄送 UDP:443 首包到此，见 QuicProbe）
  ServerSocket? _quicProbeSocket;

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
    unawaited(_startQuicProbeListener());
    // 启动 WebSocket 流量推送服务（上游 #756）
    if (configuration.wsTrafficEnabled) {
      _startWsTrafficServer().ignore();
    }
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
    _stopQuicProbeListener();
    // 停止 WebSocket 流量推送服务（上游 #756）
    try {
      await WsTrafficServer.instance.stop();
    } catch (e) {
      logger.w('WebSocket 流量推送服务停止异常', error: e);
    }
    if (!isRunning) {
      return server;
    }

    if (configuration.enableSystemProxy) {
      await setSystemProxyEnable(false);
    }
    // 上游 #577：还原 Windows 分层增强接管（WinHTTP + 环境变量）
    if (Platform.isWindows && configuration.winTakeoverEnabled) {
      try {
        await WindowsTakeover.disableLayered();
      } catch (e) {
        logger.w('还原 Windows 增强接管失败', error: e);
      }
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

  /// 启动 QUIC 元数据探测监听：接收 VPN 层经本机 TCP 抄送的 UDP:443 首包
  Future<void> _startQuicProbeListener() async {
    try {
      _quicProbeSocket =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, quicProbePort);
      _quicProbeSocket!.listen((client) {
        // 单包即发即断：数据可能拆包，防抖合并后交给解析器
        final buffer = BytesBuilder();
        Timer? t;
        client.listen((chunk) {
          buffer.add(chunk);
          t?.cancel();
          t = Timer(const Duration(milliseconds: 80), () {
            try {
              QuicProbe.instance
                  .handlePacket(buffer.toBytes(), client.remoteAddress.address);
            } catch (_) {}
            try { client.close(); } catch (_) {}
          });
        }, onDone: () {
          t?.cancel();
          try {
            if (buffer.length > 0) {
              QuicProbe.instance
                  .handlePacket(buffer.toBytes(), client.remoteAddress.address);
            }
          } catch (_) {}
        }, onError: (Object e) {
          logger.w('QUIC 探测连接异常', error: e);
        });
      }, onError: (Object e) {
        logger.w('QUIC 探测监听异常', error: e);
      });
    } catch (e) {
      logger.w('QUIC 探测监听启动失败', error: e);
    }
  }

  void _stopQuicProbeListener() {
    try {
      _quicProbeSocket?.close();
    } catch (_) {}
    _quicProbeSocket = null;
  }

  /// 启动 WebSocket 流量推送服务（上游 #756），返回是否启动成功
  Future<bool> _startWsTrafficServer() async {
    try {
      final traffic = WsTrafficServer.instance;
      if (!listeners.contains(traffic)) {
        listeners.add(traffic);
      }
      await traffic.start(configuration);
      return true;
    } catch (e) {
      logger.w('WebSocket 流量推送服务启动失败', error: e);
      return false;
    }
  }

  /// 应用 WebSocket 流量推送配置（偏好设置切换开关时即时生效，无需重启抓包）。
  /// 返回 true 表示服务正在运行；启动失败返回 false，由调用方提示用户。
  Future<bool> applyWsTraffic() async {
    if (configuration.wsTrafficEnabled) {
      return _startWsTrafficServer();
    }
    try {
      await WsTrafficServer.instance.stop();
    } catch (_) {}
    return false;
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
