/*
 * Copyright 2024 Hongen Wang All rights reserved.
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

import 'package:proxypin/network/components/manager/hosts_manager.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/util/logger.dart';

import 'interceptor.dart';

/// Hosts interceptor
/// @author wanghongen
class Hosts extends Interceptor {
  Future<HostsManager> get hostsManager async => await HostsManager.instance;

  @override
  int get priority => -1000;

  @override
  Future<HostAndPort> preConnect(HostAndPort hostAndPort) async {
    var host = hostAndPort.host;
    var hostsItem = await hostsManager.then((it) => it.getHosts(host, hostAndPort.port));
    if (hostsItem != null && hostsItem.toAddress != null) {
      logger.d('Hosts: $host:${hostAndPort.port} -> ${hostsItem.displayAddress}');
      // toAddress 允许写成 "1.2.3.4:8443"（UI 的 displayAddress 就展示这种形式），
      // 旧实现整串塞进 copyWith(host:) → Socket.connect 必然失败，用户只看到网络错误。
      var address = hostsItem.toAddress!.trim();
      var targetPort = hostsItem.port ?? hostAndPort.port;
      if (address.startsWith('[')) {
        final end = address.indexOf(']');
        if (end > 0) {
          final rest = address.substring(end + 1);
          if (rest.startsWith(':')) {
            targetPort = int.tryParse(rest.substring(1)) ?? targetPort;
          }
          address = address.substring(1, end);
        }
      } else {
        final parts = address.split(':');
        if (parts.length == 2) {
          final p = int.tryParse(parts[1]);
          if (p != null) {
            address = parts[0];
            targetPort = p;
          }
        }
      }
      return hostAndPort.copyWith(host: address, port: targetPort);
    }
    return hostAndPort;
  }
}
