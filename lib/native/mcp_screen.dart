import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// MCP Screen Control - Dart 端桥接
///
/// 封装 Android 原生 MethodChannel "com.proxy/mcpScreen"，
/// 提供 UI 自动化和设备控制能力。
///
/// 仅 Android 平台可用，桌面端调用会抛出 UnsupportedError。
class McpScreen {
  static const _channel = MethodChannel('com.proxy/mcpScreen');

  // 原生若因异常/未授权没有回 result，await invokeMethod 会永久挂起，
  // 因此下面每处调用都带超时兜底（授权类等待用户操作，给到 60s）。

  static bool get isSupported => Platform.isAndroid;

  /// 获取设备信息（型号、品牌、Android 版本、IP、Root/无障碍状态）
  static Future<Map<String, dynamic>> getDeviceInfo() async {
    final result = await _channel.invokeMethod('getDeviceInfo').timeout(const Duration(seconds: 10));
    return Map<String, dynamic>.from(result);
  }

  /// 获取当前前台 Activity
  static Future<String> getCurrentActivity() async {
    return await _channel.invokeMethod('getCurrentActivity').timeout(const Duration(seconds: 5));
  }

  /// 导出当前 UI 层级
  /// [clickableOnly] 仅返回可点击元素
  /// [packageFilter] 按包名过滤
  static Future<String> dumpUi({
    bool clickableOnly = false,
    String? packageFilter,
  }) async {
    return await _channel.invokeMethod('dumpUi', {
      'clickableOnly': clickableOnly,
      if (packageFilter != null) 'packageFilter': packageFilter,
    }).timeout(const Duration(seconds: 20));
  }

  /// 点击坐标
  static Future<bool> tap(int x, int y) async {
    return await _channel.invokeMethod('tap', {'x': x, 'y': y}).timeout(const Duration(seconds: 10));
  }

  /// 长按坐标（指定持续时长）
  static Future<bool> click(int x, int y, {int duration = 50}) async {
    return await _channel.invokeMethod('click', {
      'x': x,
      'y': y,
      'duration': duration,
    }).timeout(const Duration(seconds: 10));
  }

  /// 滑动手势
  static Future<bool> swipe(
    int x1,
    int y1,
    int x2,
    int y2, {
    int duration = 300,
  }) async {
    return await _channel.invokeMethod('swipe', {
      'x1': x1,
      'y1': y1,
      'x2': x2,
      'y2': y2,
      'duration': duration,
    }).timeout(const Duration(seconds: 10));
  }

  /// 按键事件
  /// keycode: 3=HOME, 4=BACK, 26=POWER, 82=MENU, 187=RECENTS
  static Future<bool> keyEvent(int keycode) async {
    return await _channel.invokeMethod('keyEvent', {'keycode': keycode}).timeout(const Duration(seconds: 10));
  }

  /// 在当前焦点元素上输入文本
  static Future<bool> inputText(String text) async {
    return await _channel.invokeMethod('inputText', {'text': text}).timeout(const Duration(seconds: 10));
  }

  /// 截屏（需 Root），返回 Base64 编码的 PNG
  static Future<String> screenshot() async {
    return await _channel.invokeMethod('screenshot').timeout(const Duration(seconds: 30));
  }

  /// 打开无障碍设置页面
  static Future<bool> openAccessibilitySettings() async {
    return await _channel.invokeMethod('openAccessibilitySettings').timeout(const Duration(seconds: 10));
  }

  /// 打开 Shizuku 授权页面（需已安装 Shizuku）
  static Future<bool> openShizukuSettings() async {
    return await _channel.invokeMethod('openShizukuSettings').timeout(const Duration(seconds: 10));
  }

  /// 请求 Shizuku 授权（弹出授权弹窗）
  static Future<bool> requestShizukuAuthorization() async {
    return await _channel.invokeMethod('requestShizukuAuthorization').timeout(const Duration(seconds: 60));
  }

  /// 请求 Dhizuku 授权
  static Future<bool> requestDhizukuAuthorization() async {
    return await _channel.invokeMethod('requestDhizukuAuthorization').timeout(const Duration(seconds: 60));
  }

  /// 请求 Root 授权（触发 Superuser 弹窗）
  static Future<bool> requestRootAuthorization() async {
    return await _channel.invokeMethod('requestRootAuthorization').timeout(const Duration(seconds: 60));
  }

  /// 执行 Shell 命令
  /// [mode] 权限模式: root / shizuku / dhizuku / auto（默认 auto）
  /// [useSu] 是否使用 root 权限（mode 未指定时的兼容参数）
  /// [timeoutMs] 超时时间（毫秒）
  static Future<Map<String, dynamic>> shell(
    String command, {
    bool useSu = false,
    String? mode,
    int timeoutMs = 10000,
  }) async {
    final result = await _channel.invokeMethod('shell', {
      'command': command,
      'useSu': useSu,
      if (mode != null) 'mode': mode,
      'timeoutMs': timeoutMs,
    }).timeout(Duration(milliseconds: timeoutMs + 5000));
    return Map<String, dynamic>.from(result);
  }
}
