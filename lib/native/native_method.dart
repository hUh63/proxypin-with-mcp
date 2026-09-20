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
}
