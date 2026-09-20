import 'dart:io';

import 'package:flutter/services.dart';
import 'package:proxypin/native/vpn.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/launch/launch.dart';
import 'package:proxypin/ui/mobile/mobile.dart';
import 'package:proxypin/utils/lang.dart';

///画中画
class PictureInPicture {
  static bool inPip = false;

  /// 进入小窗要用的代理地址，由启动抓包时写入（SocketLaunch.onStart）。
  ///
  /// `onUserLeaveHint` 之后留给调用系统 API 的窗口极短，这里必须能**同步**取到：
  /// 若等到那一刻再去 await 配置读取 / 网卡枚举，就很容易错过窗口期，
  /// 表现为"返回桌面却不显示小窗"（上游 #812 / #703）。
  static String? proxyHost;
  static int? proxyPort;

  /// 启动抓包成功后记录当前代理地址，供小窗进入时同步取用
  static void updateProxy(String host, int port) {
    proxyHost = host;
    proxyPort = port;
  }

  static final MethodChannel _channel = const MethodChannel('com.proxy/pictureInPicture')
    ..setMethodCallHandler((call) async {
      logger.d("pictureInPicture MethodCallHandler ${call.method}");
      if (call.method == 'cleanSession') {
        MobileApp.requestStateKey.currentState?.clean();
      } else if (call.method == 'exitPictureInPictureMode') {
        inPip = false;
        Vpn.isRunning().then((value) {
          Vpn.isVpnStarted = value;
          SocketLaunch.startStatus.value = ValueWrap.of(value);
        });
      }

      return Future.value();
    });

  ///进入画中画模式
  static Future<bool> enterPictureInPictureMode(String host, int port,
      {List<String>? appList, List<String>? disallowApps}) async {
    try {
      // 原生侧若因异常未回调 result，await 会永久挂起——返回键会因此完全不响应
      final result = await _channel.invokeMethod<bool>('enterPictureInPictureMode',
          {"proxyHost": host, "proxyPort": port, "allowApps": appList, "disallowApps": disallowApps}).timeout(
          const Duration(seconds: 3),
          onTimeout: () => false);
      inPip = result == true;
      return inPip;
    } catch (e) {
      logger.e('enterPictureInPictureMode failed', error: e);
      inPip = false;
      return false;
    }
  }

  ///退出画中画模式
  static Future<bool> exitPictureInPictureMode() async {
    try {
      final exited = await _channel
          .invokeMethod<bool>('exitPictureInPictureMode')
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
      inPip = false;
      return exited == true;
    } catch (e) {
      logger.e('exitPictureInPictureMode failed', error: e);
      inPip = false;
      return false;
    }
  }

  ///发送数据
  ///
  /// 每个请求都会调到这里（iOS 小窗里显示 URL），原生不回 result 时不能挂住，
  /// 所以加超时兜底并吞掉异常。
  static Future<bool> addData(String text) async {
    if (Platform.isIOS && inPip) {
      try {
        await _channel
            .invokeMethod('addData', text.fixAutoLines())
            .timeout(const Duration(seconds: 3), onTimeout: () => null);
      } catch (e) {
        logger.e('addData failed', error: e);
      }
    }
    return false;
  }
}
