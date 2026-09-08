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

/// QUIC 连接元数据探测（上游 #489）。
///
/// 数据流：ProxyVpnService（VPN 模式）捕获 UDP:443 首包 → 抄送本机 [QUIC_PROBE_PORT]
/// → 本监听器解密 QUIC v1 Initial → 提取 SNI/QUIC 版本/连接 ID 等元数据 → 内存会话列表
/// （列表经 [revision] ValueNotifier 通知 UI）。
///
/// 说明：QUIC 业务数据（HTTP/3 请求响应）经 TLS 1.3 加密无法解密（业界一致）；
/// 本模块展示的是"哪些 App/域名在走 QUIC、建立多少连接"的连接级元数据。

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/quic/quic_keys.dart';
import 'package:proxypin/network/util/quic/quic_packet.dart';

/// 本机 QUIC 探测监听端口（与 ProxyVpnService.QUIC_PROBE_PORT 一致）
const int quicProbePort = 41745;

/// QUIC 连接会话
class QuicSession {
  /// SNI 域名（ClientHello 中 server_name；未解出为空）
  String host;
  /// QUIC 版本号（十六进制，0x00000001 = v1）
  final String version;
  /// 客户端目的连接 ID（hex，会话去重键）
  final String dcid;
  /// 远端信息 IP:port（探测包来自源五元组）
  final String remote;
  final DateTime firstSeen;
  int packets;
  int frames;

  QuicSession({
    required this.host,
    required this.version,
    required this.dcid,
    required this.remote,
    required this.firstSeen,
    this.packets = 1,
    this.frames = 0,
  });
}

/// QUIC 探测单例：UDP 监听 + Initial 解析 + 会话管理
class QuicProbe {
  QuicProbe._();
  static final QuicProbe instance = QuicProbe._();

  final Map<String, QuicSession> _sessions = {}; // key = dcid
  final ValueNotifier<int> revision = ValueNotifier(0);
  final List<String> _probeLog = <String>[]; // 最近解析日志（供 UI 调试展示）

  DatagramSocket? _socket;
  bool _started = false;

  List<QuicSession> get sessions => _sessions.values.toList();

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      _socket = await DatagramSocket.bind(InternetAddress.loopbackIPv4, quicProbePort);
      _socket!.listen(_onDatagram, onError: (Object e) {
        logger.w('QUIC 探测监听异常', error: e);
      });
    } catch (e) {
      logger.w('QUIC 探测监听启动失败', error: e);
    }
  }

  void stop() {
    _started = false;
    _socket?.close();
    _socket = null;
  }

  /// 清空会话（UI 手动刷新/清空时调用）
  void clear() {
    _sessions.clear();
    _probeLog.clear();
    revision.value++;
  }

  void _onDatagram(Datagram datagram) {
    final data = datagram.data;
    if (data.length < 12 || data.length > 2048) return;
    try {
      final packet = Uint8List.fromList(data);
      final info = parseQuicInitial(packet); // 明文字段 + Header Protection
      final dcidHex = _hex(info.dcid);
      final existing = _sessions[dcidHex];
      final remote = '${datagram.address.address}:${datagram.port}';
      if (existing != null) {
        // 会话已建立：仅计数（Kotlin 侧已按 30s 节流，此处兜底）
        existing.packets++;
        revision.value++;
        return;
      }

      // 新会话：尝试解密 Initial 提取 SNI
      var host = '';
      var frames = 0;
      final dec = decryptQuicInitial(packet);
      if (dec != null && dec.cryptoData != null) {
        frames = dec.frameCount;
        host = extractServerName(dec.cryptoData!) ?? '';
      }

      _sessions[dcidHex] = QuicSession(
        host: host,
        version: '0x${info.version.toRadixString(16).padLeft(8, '0')}',
        dcid: dcidHex,
        remote: remote,
        firstSeen: DateTime.now(),
        packets: 1,
        frames: frames,
      );
      if (_sessions.length > 200) {
        // 上限保护：移除最早会话
        final oldest = _sessions.values.reduce(
            (a, b) => a.firstSeen.isBefore(b.firstSeen) ? a : b);
        _sessions.remove(oldest.dcid);
      }
      revision.value++;
    } catch (_) {/* 非 QUIC/损坏包忽略 */}
  }

  static String _hex(List<int> b) =>
      b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
}

/// 从解密后的 CRYPTO 数据中提取 TLS ClientHello 的 SNI（server_name）。
/// 解析失败/未携带 SNI 返回 null。
String? extractServerName(Uint8List cryptoData) {
  try {
    var off = 0;
    // 遍历 TLS record：handshake(0x16)
    while (off + 5 <= cryptoData.length) {
      final type = cryptoData[off];
      final len = (cryptoData[off + 3] << 8) | cryptoData[off + 4];
      if (off + 5 + len > cryptoData.length) return null;
      if (type == 0x16) {
        final hs = off + 5;
        if (len < 4) return null;
        final hsType = cryptoData[hs];
        if (hsType == 0x01) {
          // ClientHello body（跳过 4 字节 handshake type+length）
          final body = hs + 4;
          if (cryptoData.length < body + 4) return null;
          return _parseClientHello(Uint8List.sublistView(cryptoData, body));
        }
      }
      off += 5 + len;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// ClientHello 解析（body 起始 = 跳过 handshake 头）
String? _parseClientHello(Uint8List ch) {
  var p = 0;
  p += 2; // legacy_version
  p += 32; // random
  final sidLen = ch[p];
  p += 1 + sidLen; // session_id
  final csLen = (ch[p] << 8) | ch[p + 1];
  p += 2 + csLen; // cipher_suites
  final compLen = ch[p];
  p += 1 + compLen; // compression_methods
  if (p + 2 > ch.length) return null;
  final extTotal = (ch[p] << 8) | ch[p + 1];
  p += 2;
  final extEnd = p + extTotal;
  if (extEnd > ch.length) return null;
  while (p + 4 <= extEnd) {
    final extType = (ch[p] << 8) | ch[p + 1];
    final extLen = (ch[p + 2] << 8) | ch[p + 3];
    p += 4;
    if (p + extLen > extEnd) return null;
    if (extType == 0x0000) {
      // server_name：list(2) + type(1) + nameLen(2) + host
      final data = Uint8List.sublistView(ch, p, p + extLen);
      if (data.length < 5) return null;
      final nameType = data[2];
      final nameLen = (data[3] << 8) | data[4];
      if (nameType != 0 || data.length < 5 + nameLen) return null;
      return utf8.decode(
          Uint8List.sublistView(data, 5, 5 + nameLen),
          allowMalformed: true);
    }
    p += extLen;
  }
  return null;
}
