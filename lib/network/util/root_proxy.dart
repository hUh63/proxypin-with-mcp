import 'dart:io';

import 'package:proxypin/native/native_method.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android root 模式抓包（上游 #839 Feature Request 2）。
///
/// 不开 VPN，直接用 iptables 把出站 TCP 流量重定向到 ProxyPin 的代理端口，
/// 用来对付「应用检测到 VPN / 系统代理就拒绝联网」这类规避手段。需要设备已 root。
///
/// 与 VPN 模式互斥：两者同时开启时，被重定向的连接会和 VPN 隧道抢同一份流量。
class RootProxy {
  RootProxy._();

  /// 记录「上次退出时 root 模式仍在生效」。
  /// 启动时据此决定要不要清理残留规则 —— 从没用过的用户不该被唤起 su 授权框。
  static const String _prefActive = 'rootProxyActive';

  /// 是否支持（当前仅 Android）
  static bool get supported => Platform.isAndroid;

  /// 上次退出时是否仍处于开启状态。
  static Future<bool> wasActive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefActive) == true;
    } catch (_) {
      return false;
    }
  }

  /// 设备是否已 root 且已授权 su（首次调用会弹出授权框）。
  static Future<bool> isAvailable() async {
    if (!supported) return false;
    return NativeMethod.isRootAvailable();
  }

  /// 重定向当前是否真的生效。
  static Future<bool> isRunning() async {
    if (!supported) return false;
    return NativeMethod.isRootProxyRunning();
  }

  /// 开启重定向。返回：是否成功 + 失败原因。
  static Future<(bool, String)> start(int port) async {
    if (!supported) {
      return (false, 'root capture mode is Android only');
    }
    final result = await NativeMethod.startRootProxy(port);
    if (result.$1) {
      await _setActive(true);
      logger.i('root proxy started on port $port');
    } else {
      logger.w('root proxy start failed: ${result.$2}');
    }
    return result;
  }

  /// 关闭并清理自建链。
  static Future<bool> stop() async {
    if (!supported) return false;
    final ok = await NativeMethod.stopRootProxy();
    await _setActive(false);
    logger.i('root proxy stopped: $ok');
    return ok;
  }

  /// App 启动时调用：清掉上次异常退出遗留的重定向规则。
  ///
  /// 残留规则的表现是「WiFi 连着但所有 App 都上不了网」，用户自己很难想到是
  /// 上次的抓包模式没退干净，所以必须在启动时兜住。
  static Future<void> cleanupIfNeeded() async {
    if (!supported) return;
    if (!await wasActive()) return;
    try {
      final ok = await NativeMethod.cleanupRootProxy();
      logger.i('root proxy stale cleanup: $ok');
      await _setActive(false);
    } catch (e, t) {
      logger.e('root proxy stale cleanup failed', error: e, stackTrace: t);
    }
  }

  static Future<void> _setActive(bool active) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (active) {
        await prefs.setBool(_prefActive, true);
      } else {
        await prefs.remove(_prefActive);
      }
    } catch (e) {
      logger.e('root proxy pref write failed', error: e);
    }
  }
}
