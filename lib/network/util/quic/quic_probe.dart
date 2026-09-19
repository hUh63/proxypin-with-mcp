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

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/quic/qpack_decoder.dart';
import 'package:proxypin/network/util/quic/quic_1rtt.dart';
import 'package:proxypin/network/util/quic/quic_keylog.dart';
import 'package:proxypin/network/util/quic/quic_keys.dart';
import 'package:proxypin/network/util/quic/quic_packet.dart';

/// 本机 QUIC 探测监听端口（与 ProxyVpnService.QUIC_PROBE_PORT 一致）
const int quicProbePort = 41745;

/// 单个会话最多保留多少条解密出来的流片段（避免长连接吃内存）
const int maxDecryptedStreams = 200;

/// 用密钥日志解开的一个流片段（上游 #489：keylog 解密路径）
class QuicDecryptedStream {
  final int streamId;
  final int offset;
  final bool fin;

  /// HTTP/3 帧类型（流数据首个 varint，尽力而为）
  final int frameType;

  /// 可读预览（可见 ASCII 原样，其余转 \xNN）
  final String preview;

  final int length;
  final DateTime time;

  /// 若该帧是 HTTP/3 HEADERS 且成功 QPACK 解码，这里存放解出的头部字段
  final List<QpackHeaderField> headers;

  QuicDecryptedStream({
    required this.streamId,
    required this.offset,
    required this.fin,
    required this.frameType,
    required this.preview,
    required this.length,
    required this.time,
    this.headers = const [],
  });
}

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

  /// 最后一次看到该连接的时间（UI 用来判断活跃度、排序）
  DateTime lastSeen;

  int packets;
  int frames;

  /// 累计字节数（只统计被抄送过来的 QUIC 包，用于估算规模）
  int bytes;

  /// 客户端发包时使用的 DCID 长度（= 服务端 SCID 长度），用于定位 1-RTT 包头
  int destCidLength;

  /// ClientHello.random（hex）——密钥日志以它为索引
  String clientRandom;

  /// 已解密的流片段（导入密钥日志后才能拿到；上限见 [maxDecryptedStreams]）
  final List<QuicDecryptedStream> decrypted = [];

  QuicSession({
    required this.host,
    required this.version,
    required this.dcid,
    required this.remote,
    required this.firstSeen,
    DateTime? lastSeen,
    this.packets = 1,
    this.frames = 0,
    this.bytes = 0,
    this.destCidLength = 0,
    this.clientRandom = '',
  }) : lastSeen = lastSeen ?? firstSeen;
}

/// QUIC 探测单例：UDP 监听 + Initial 解析 + 会话管理
class QuicProbe {
  QuicProbe._();
  static final QuicProbe instance = QuicProbe._();

  final Map<String, QuicSession> _sessions = {}; // key = dcid
  final ValueNotifier<int> revision = ValueNotifier(0);
  final List<String> _probeLog = <String>[]; // 最近解析日志（供 UI 调试展示）

  /// 时间轴：最近 10 分钟、每 10 秒一个桶（供会话页展示"流量随时间的变化"）
  static const int timelineBucketCount = 60;
  static const int timelineBucketMs = 10 * 1000;
  final List<int> _bucketPackets = List<int>.filled(timelineBucketCount, 0);
  final List<int> _bucketBytes = List<int>.filled(timelineBucketCount, 0);
  final List<int> _bucketSlot = List<int>.filled(timelineBucketCount, -1);

  /// 1-RTT 密钥缓存（client_random → keys），避免每个包都重算 HKDF
  final Map<String, QuicTrafficKeys> _trafficKeysCache = {};

  void _recordTimeline(int bytes) {
    final slot = DateTime.now().millisecondsSinceEpoch ~/ timelineBucketMs;
    final index = slot % timelineBucketCount;
    if (_bucketSlot[index] != slot) {
      // 该桶已被新的时间槽复用，重置后再累加
      _bucketSlot[index] = slot;
      _bucketPackets[index] = 0;
      _bucketBytes[index] = 0;
    }
    _bucketPackets[index]++;
    _bucketBytes[index] += bytes;
  }

  /// 按时间升序（旧 → 新）返回每桶的包数
  List<int> timelinePackets() => _readTimeline(_bucketPackets);

  /// 按时间升序（旧 → 新）返回每桶的字节数
  List<int> timelineBytes() => _readTimeline(_bucketBytes);

  List<int> _readTimeline(List<int> buckets) {
    final nowSlot = DateTime.now().millisecondsSinceEpoch ~/ timelineBucketMs;
    final result = List<int>.filled(timelineBucketCount, 0);
    for (var i = 0; i < timelineBucketCount; i++) {
      final slot = nowSlot - (timelineBucketCount - 1 - i);
      final index = slot % timelineBucketCount;
      result[i] = _bucketSlot[index] == slot ? buckets[index] : 0;
    }
    return result;
  }

  List<QuicSession> get sessions => _sessions.values.toList();



  /// 清空会话（UI 手动刷新/清空时调用）
  void clear() {
    _sessions.clear();
    _probeLog.clear();
    _trafficKeysCache.clear();
    for (var i = 0; i < timelineBucketCount; i++) {
      _bucketSlot[i] = -1;
      _bucketPackets[i] = 0;
      _bucketBytes[i] = 0;
    }
    revision.value++;
  }

  /// 尝试用密钥日志解开一条客户端发出的 1-RTT 包（上游 #489）
  ///
  /// 只有导入了密钥日志、且该连接的 CLIENT_TRAFFIC_SECRET_0 命中时才会解出内容。
  void _tryDecrypt1Rtt(QuicSession session, Uint8List packet) {
    if (session.clientRandom.isEmpty || session.destCidLength <= 0) return;

    final secret = QuicKeylogStore.instance.clientTrafficSecret(session.clientRandom);
    if (secret == null) return;

    final keys = _trafficKeysCache[session.clientRandom] ??= deriveQuicV1TrafficKeys(secret);
    final result = decryptShortHeaderPacket(packet, keys, destCidLength: session.destCidLength);
    if (result == null || result.streams.isEmpty) return;

    for (final frame in result.streams) {
      if (session.decrypted.length >= maxDecryptedStreams) break;
      // 流起始处的帧可能是 HTTP/3 HEADERS：尝试 QPACK 解码出头部（上游 #489）
      final headers = frame.offset == 0
          ? (decodeHttp3Headers(frame.data)?.fields ?? const <QpackHeaderField>[])
          : const <QpackHeaderField>[];
      session.decrypted.add(QuicDecryptedStream(
        streamId: frame.streamId,
        offset: frame.offset,
        fin: frame.fin,
        // HTTP/3 帧类型是 varint；小值（DATA/HEADERS/SETTINGS）时首个字节即可代表
        frameType: frame.data.isNotEmpty ? frame.data[0] : -1,
        preview: previewStreamData(frame.data, limit: 300),
        length: frame.data.length,
        time: DateTime.now(),
        headers: headers,
      ));
    }
  }

  /// 处理一个 UDP:443 首包（由持有 socket 的网络层调用，本类保持纯解析无 IO）
  void handlePacket(List<int> data, String remote) {
    if (data.length < 12 || data.length > 2048) return;
    try {
      final packet = Uint8List.fromList(data);
      final info = parseQuicInitial(packet); // 明文字段 + Header Protection
      _recordTimeline(data.length); // 时间轴统计（与是否新会话无关）
      final dcidHex = _hex(info.dcid);
      final existing = _sessions[dcidHex];
      if (existing != null) {
        // 会话已建立：计数 + 若有密钥日志则尝试解开 1-RTT（1-RTT 无类型字段，靠首字节高位区分）
        existing.packets++;
        existing.bytes += data.length;
        existing.lastSeen = DateTime.now();
        _tryDecrypt1Rtt(existing, packet);
        revision.value++;
        return;
      }

      // 新会话：尝试解密 Initial 提取 SNI
      var host = '';
      var frames = 0;
      var clientRandom = '';
      final dec = decryptQuicInitial(packet);
      if (dec != null && dec.cryptoData != null) {
        frames = dec.frameCount;
        host = extractServerName(dec.cryptoData!) ?? '';
        // 从同一个 ClientHello 里取 random：密钥日志正是以它为索引
        final random = extractClientRandom(dec.cryptoData!);
        if (random != null) clientRandom = _hex(random);
      }

      _sessions[dcidHex] = QuicSession(
        host: host,
        version: '0x${info.version.toRadixString(16).padLeft(8, '0')}',
        dcid: dcidHex,
        remote: remote,
        firstSeen: DateTime.now(),
        packets: 1,
        frames: frames,
        bytes: data.length,
        // 客户端发出的包用服务端 SCID 作为 DCID，长度必须记下来才能定位 1-RTT 包头
        destCidLength: info.scid.length,
        clientRandom: clientRandom,
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

/// 从解密后的 CRYPTO 数据中提取 TLS ClientHello 的 random（32 字节）。
///
/// 密钥日志（SSLKEYLOGFILE）以 client_random 为索引，拿到它才能把日志条目与
/// 这条 QUIC 连接对上。解析失败返回 null。
Uint8List? extractClientRandom(Uint8List cryptoData) {
  var off = 0;
  while (off + 5 <= cryptoData.length) {
    final type = cryptoData[off];
    final len = (cryptoData[off + 3] << 8) | cryptoData[off + 4];
    if (off + 5 + len > cryptoData.length) return null;
    if (type == 0x16) {
      final hs = off + 5;
      // handshake: type(1) + length(3) + version(2) + random(32)
      if (len >= 4 + 2 + 32 && cryptoData[hs] == 0x01) {
        final start = hs + 4 + 2;
        if (start + 32 <= cryptoData.length) {
          return Uint8List.sublistView(cryptoData, start, start + 32);
        }
      }
    }
    off += 5 + len;
  }
  return null;
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
