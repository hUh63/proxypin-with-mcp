import 'dart:io';

import 'package:flutter/services.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/util/process_info.dart';

class ProcessInfoPlugin {
  static const MethodChannel _methodChannel = MethodChannel('com.proxy/processInfo');

  /// 按本地端口查所属进程信息。
  ///
  /// 加了超时：这个调用在抓包链路上被 await（`network/util/process_info.dart`），
  /// 原生若因异常没回 result，请求处理会永久卡在这一行；超时按"查不到"处理（返回 null）。
  static Future<ProcessInfo?> getProcessByPort(String host, int port) {
    return _methodChannel
        .invokeMethod<Map>('getProcessByPort', {"host": host, "port": port})
        .timeout(const Duration(seconds: 3), onTimeout: () => null)
        .then((process) {
      if (process == null) return null;

      return ProcessInfo(process['packageName'], process['name'], process['packageName'],
          os: Platform.operatingSystem,
          icon: process['icon'],
          remoteHost: process['remoteHost'],
          remotePost: process['remotePort']);
    });
  }

  /// 查某个本地端口对应的远端地址（VPN 转发使用）。
  ///
  /// 同样处在抓包热路径上（ssl 握手 / 请求派发都会 await 它），必须保险：
  /// 超时或异常一律返回 null，调用方本来就接受 null（表示"拿不到"）。
  static Future<HostAndPort?> getRemoteAddressByPort(int port) async {
    if (!Platform.isAndroid) return null;

    return _methodChannel
        .invokeMethod<Map>('getRemoteAddressByPort', {"port": port})
        .timeout(const Duration(seconds: 1), onTimeout: () => null)
        .then((process) {
      if (process == null) return null;
      return HostAndPort.host(process['remoteHost'], process['remotePort']);
    }).catchError((_) => null);
  }
}
