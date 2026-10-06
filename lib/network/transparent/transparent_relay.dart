/*
 * Copyright 2023 Hongen Wang
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
import 'dart:convert';
import 'dart:io';

import 'package:proxypin/network/transparent/inet.dart';
import 'package:proxypin/network/transparent/transparent_capture.dart';

/// 透明流量中继：把被 WinDivert 劫持到本地的连接，用标准 `CONNECT` 交给既有
/// MITM 代理（`TransparentCapture` 只做地址改写，代理协议由这里补上）。
///
/// 一条被劫持的连接到达时，其「对端地址」正是原客户端 (ip:port)，
/// 据此向 [TransparentCapture] 查回原始目的地址，再连本地代理端口发 CONNECT。
class TransparentRelay {
  static final TransparentRelay instance = TransparentRelay._();

  TransparentRelay._();

  ServerSocket? _server;
  int _proxyPort = 0;
  int relayed = 0;

  int get port => _server?.port ?? 0;

  bool get isRunning => _server != null;

  Future<int> start({required int proxyPort}) async {
    if (_server != null) return port;
    _proxyPort = proxyPort;
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_onConnection, onError: (_) {});
    return _server!.port;
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  Future<void> _onConnection(Socket client) async {
    final ip = PacketInfo.ipOf(client.remoteAddress.address);
    final orig = TransparentCapture.instance.lookupOriginal(ip, client.remotePort);
    if (orig == null) {
      client.destroy();
      return;
    }
    final host = PacketInfo.ipText(orig[0]);
    final port = orig[1];

    Socket proxySocket;
    try {
      proxySocket = await Socket.connect(InternetAddress.loopbackIPv4, _proxyPort,
          timeout: const Duration(seconds: 5));
    } catch (_) {
      client.destroy();
      return;
    }

    final buffer = <int>[];
    var handshaked = false;
    late StreamSubscription sub;

    sub = proxySocket.listen((data) {
      if (!handshaked) {
        buffer.addAll(data);
        final idx = _headerEnd(buffer);
        if (idx < 0) return; // 等代理应答头到齐
        final header = latin1.decode(buffer.sublist(0, idx), allowInvalid: true);
        final ok = header.startsWith('HTTP/') && RegExp(r'\s2\d\d\s').hasMatch(header.split('\r\n').first);
        handshaked = true;
        final rest = buffer.sublist(idx + 4);
        if (!ok) {
          client.destroy();
          proxySocket.destroy();
          return;
        }
        relayed++;
        if (rest.isNotEmpty) client.add(rest);
        client.listen((d) => proxySocket.add(d),
            onDone: () => proxySocket.destroy(), onError: (_) => proxySocket.destroy());
      } else {
        client.add(data);
      }
    }, onDone: () => client.destroy(), onError: (_) => client.destroy());

    proxySocket.write('CONNECT $host:$port HTTP/1.1\r\nHost: $host:$port\r\n\r\n');
    await sub.asFuture<void>().catchError((_) {});
  }

  static int _headerEnd(List<int> b) {
    for (var i = 0; i + 3 < b.length; i++) {
      if (b[i] == 0x0D && b[i + 1] == 0x0A && b[i + 2] == 0x0D && b[i + 3] == 0x0A) return i;
    }
    return -1;
  }
}
