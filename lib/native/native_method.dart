import 'dart:async';

import 'package:flutter/services.dart';
import 'package:proxypin/network/util/logger.dart';

class NativeMethod {
  static const MethodChannel _channel = MethodChannel('com.proxypin/method');

  /// 检查本地网络（Wi-Fi 或以太网）是否可用 (仅限 iOS)。
  ///
  /// 返回 `true` 如果本地网络可用，否则返回 `false`。
  static Future<bool> requestLocalNetworkAccess() async {
    try {
      final bool isAvailable = await _channel.invokeMethod('requestLocalNetwork');
      logger.d("[NativeMethod] requestLocalNetworkAccess => $isAvailable");
      return isAvailable;
    } on PlatformException catch (e) {
      logger.e("[NativeMethod] requestLocalNetworkAccess error: '${e.message}'.");
      return false;
    } on MissingPluginException {
      // 本平台没有实现该通道（Android 侧曾长期缺失）：按"不可用"处理，不要抛给上层
      logger.d("[NativeMethod] requestLocalNetwork is not implemented on this platform");
      return false;
    }
  }

  /// 检查给定 PEM 证书是否已安装到系统信任库（iOS 钥匙串 / Android AndroidCAStore）
  static Future<bool> isCaInstalled(String pem) async {
    try {
      final bool installed = await _channel.invokeMethod('isCaInstalled', {"pem": pem});
      return installed;
    } on PlatformException catch (e) {
      logger.e("[NativeMethod] isCaInstalled error: ${e.message}");
      return false;
    } on MissingPluginException {
      // 兜底：未实现时按"未安装"处理，由上层给出安装引导。
      // 曾经 Android 缺实现，MissingPluginException 直接冒到抓包自检页变成「CA 根证书 读取失败」。
      logger.d("[NativeMethod] isCaInstalled is not implemented on this platform");
      return false;
    }
  }

  /// iOS: 基于 SSL 策略校验证书链（leaf + CA），仅当 CA 被系统信任时返回 true
  static Future<bool> evaluateChainTrusted(String leafPem, String caPem, {String? host}) async {
    try {
      final bool trusted = await _channel.invokeMethod('evaluateChainTrusted', {
        'leafPem': leafPem,
        'caPem': caPem,
        if (host != null) 'host': host,
      });
      return trusted;
    } on PlatformException catch (e) {
      logger.e("[NativeMethod] evaluateChainTrusted error: ${e.message}");
      return false;
    } on MissingPluginException {
      logger.d("[NativeMethod] evaluateChainTrusted is not implemented on this platform");
      return false;
    }
  }

  // ---------- Android root 模式抓包（上游 #839 Feature Request 2）----------
  //
  // 只有 Android 侧实现；其它平台会抛 MissingPluginException，
  // 这里统一按“不可用”处理，由上层决定是否展示入口。
  // 这几个调用会执行 su，首次会弹 root 授权框，所以都带超时保护——
  // 授权框一直没人点时不能让 UI 永远转圈。

  /// 设备是否已 root 且已授权 su。
  static Future<bool> isRootAvailable() async {
    try {
      final bool? available = await _channel
          .invokeMethod<bool>('isRootAvailable')
          .timeout(const Duration(seconds: 20), onTimeout: () => null);
      return available ?? false;
    } on PlatformException catch (e) {
      logger.e("[NativeMethod] isRootAvailable error: ${e.message}");
      return false;
    } on MissingPluginException {
      logger.d("[NativeMethod] isRootAvailable is not implemented on this platform");
      return false;
    }
  }

  /// root 重定向是否正在生效。
  static Future<bool> isRootProxyRunning() async {
    try {
      final bool? running = await _channel
          .invokeMethod<bool>('isRootProxyRunning')
          .timeout(const Duration(seconds: 20), onTimeout: () => null);
      return running ?? false;
    } on PlatformException catch (e) {
      logger.e("[NativeMethod] isRootProxyRunning error: ${e.message}");
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 开启 root 重定向，返回：是否成功 + 失败原因。
  static Future<(bool, String)> startRootProxy(int port) async {
    try {
      final Map? result = await _channel
          .invokeMethod<Map>('startRootProxy', {'port': port})
          .timeout(const Duration(seconds: 25), onTimeout: () => null);
      if (result == null) {
        return (false, 'timeout');
      }
      return (result['success'] == true, '${result['message'] ?? ''}');
    } on PlatformException catch (e) {
      logger.e("[NativeMethod] startRootProxy error: ${e.message}");
      return (false, e.message ?? 'platform error');
    } on MissingPluginException {
      return (false, 'not implemented on this platform');
    }
  }

  /// 关闭 root 重定向并清理自建链。
  static Future<bool> stopRootProxy() async {
    try {
      final Map? result = await _channel
          .invokeMethod<Map>('stopRootProxy')
          .timeout(const Duration(seconds: 20), onTimeout: () => null);
      return result?['success'] == true;
    } on PlatformException catch (e) {
      logger.e("[NativeMethod] stopRootProxy error: ${e.message}");
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 清理上次异常退出遗留的重定向规则（否则设备会断网）。
  static Future<bool> cleanupRootProxy() async {
    try {
      final bool? cleaned = await _channel
          .invokeMethod<bool>('cleanupRootProxy')
          .timeout(const Duration(seconds: 20), onTimeout: () => null);
      return cleaned ?? false;
    } on PlatformException catch (e) {
      logger.e("[NativeMethod] cleanupRootProxy error: ${e.message}");
      return false;
    } on MissingPluginException {
      return true; // 本来就没有这个能力，无需清理
    }
  }
}
