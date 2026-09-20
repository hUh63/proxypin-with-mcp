import 'dart:async';

import 'package:flutter/services.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/util/logger.dart';

class Vpn {
  static const MethodChannel proxyVpnChannel = MethodChannel('com.proxy/proxyVpn');

  static bool isVpnStarted = false; //vpn是否已经启动

  /// 统一的通道调用：只负责"发起动作"并吞掉异常。
  ///
  /// VPN 的真实状态由后续的 `isRunning()` / 生命周期回调反映，所以这里不做状态推断；
  /// 但异常必须处理掉，否则会变成 unhandled async error。
  static Future<void> _invokeVpn(String method, [Map<String, dynamic>? args]) async {
    try {
      await proxyVpnChannel.invokeMethod(method, args);
    } catch (e, t) {
      logger.e("vpn method $method failed", error: e, stackTrace: t);
    }
  }

  static List<String> _proxyPassDomains(Configuration configuration) {
    return configuration.proxyPassDomains.split(';').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static void startVpn(String host, int port, Configuration configuration, {bool? ipProxy = false}) {
    List<String>? appList = configuration.appWhitelistEnabled ? configuration.appWhitelist : [];

    List<String>? disallowApps;
    if (appList.isEmpty) {
      disallowApps = configuration.appBlacklist ?? [];
    }

    final proxyPassDomains = _proxyPassDomains(configuration);
    logger.d("Starting VPN with host: $host, port: $port,  proxyPassDomains: $proxyPassDomains");
    // 保持既有乐观语义：prepareVpn 为 false 时系统会弹授权框，用户同意后才真正启动，
    // 这里不做回滚，避免授权期间状态被错误地标成"未启动"。
    unawaited(_invokeVpn("startVpn", {
      "proxyHost": host,
      "proxyPort": port,
      "allowApps": appList,
      "disallowApps": disallowApps,
      "ipProxy": ipProxy,
      "setSystemProxy": configuration.enableSystemProxy,
      "proxyPassDomains": proxyPassDomains,
      "blockQuic": configuration.blockQuic,
      "quicProbe": configuration.quicProbeEnabled,
    }));
    isVpnStarted = true;
  }

  static void stopVpn() {
    unawaited(_invokeVpn("stopVpn"));
    isVpnStarted = false;
  }

  //重启vpn
  static void restartVpn(String host, int port, Configuration configuration, {bool ipProxy = false}) {
    List<String>? appList = configuration.appWhitelistEnabled ? configuration.appWhitelist : [];

    List<String>? disallowApps;
    if (appList.isEmpty) {
      disallowApps = configuration.appBlacklist ?? [];
    }
    final proxyPassDomains = _proxyPassDomains(configuration);
    unawaited(_invokeVpn("restartVpn", {
      "proxyHost": host,
      "proxyPort": port,
      "allowApps": appList,
      "disallowApps": disallowApps,
      "ipProxy": ipProxy,
      "setSystemProxy": configuration.enableSystemProxy,
      "proxyPassDomains": proxyPassDomains,
      "blockQuic": configuration.blockQuic,
      "quicProbe": configuration.quicProbeEnabled,
    }));

    isVpnStarted = true;
  }

  /// 查询 VPN 是否在运行。
  ///
  /// 加了超时与兜底：原生若因异常没回 result，`await invokeMethod` 会永久挂起，
  /// 而本方法处在小窗进入、状态刷新等路径上（上游 #812）。
  static Future<bool> isRunning() async {
    try {
      return await proxyVpnChannel.invokeMethod<bool>("isRunning").timeout(const Duration(seconds: 2)) ?? false;
    } catch (e) {
      logger.e("query vpn running state failed", error: e);
      return false;
    }
  }

  /// 已拦截的 QUIC (UDP:443) 包数量（上游 #489）
  static Future<int> quicBlockedCount() async {
    try {
      return await proxyVpnChannel.invokeMethod("getQuicBlockedCount") ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
