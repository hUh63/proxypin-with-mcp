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
import 'dart:typed_data';

/// IPv4 + TCP 的最小解析 / 改写 / 校验和实现（纯 Dart，无平台依赖）。
///
/// 透明代理（WinDivert / WFP）要做的事就两步：**认得出一条 TCP 连接**、
/// 把它的目的地址改写到本地代理、再**把校验和算回来**。这里把这套逻辑抽成纯函数，
/// 与平台无关，因此可以本地单测（见 test 目录 / 本地 Dart 用例）。
class Ipv4Tcp {
  static const int protoTcp = 6;

  /// 解析一条 IPv4/TCP 报文；不是 IPv4/TCP 返回 null。
  static PacketInfo? parse(Uint8List packet) {
    if (packet.length < 20) return null;
    final version = packet[0] >> 4;
    if (version != 4) return null;
    final ihl = (packet[0] & 0x0F) * 4;
    if (ihl < 20 || packet.length < ihl + 20) return null;
    if (packet[9] != protoTcp) return null;

    final totalLength = (packet[2] << 8) | packet[3];
    final frag = (packet[6] << 8) | packet[7];
    // 忽略分片（偏移非 0 或 MF 置位）：透明代理只处理未分片的报文
    if ((frag & 0x1FFF) != 0) return null;

    final srcIp = _readU32(packet, 12);
    final dstIp = _readU32(packet, 16);

    final tcp = ihl;
    final srcPort = (packet[tcp] << 8) | packet[tcp + 1];
    final dstPort = (packet[tcp + 2] << 8) | packet[tcp + 3];
    final dataOffset = (packet[tcp + 12] >> 4) * 4;
    if (dataOffset < 20 || packet.length < tcp + dataOffset) return null;
    final flags = packet[tcp + 13];

    return PacketInfo(
      packet: packet,
      ipHeaderLength: ihl,
      tcpOffset: tcp,
      payloadOffset: tcp + dataOffset,
      declaredLength: totalLength,
      srcIp: srcIp,
      dstIp: dstIp,
      srcPort: srcPort,
      dstPort: dstPort,
      flags: flags,
    );
  }

  /// 把目的地址改写为 [ip]:[port]（就地修改），并重算 IP/TCP 校验和。
  static void rewriteDst(Uint8List packet, int ip, int port) {
    _writeU32(packet, 16, ip);
    final ihl = (packet[0] & 0x0F) * 4;
    packet[ihl + 2] = (port >> 8) & 0xFF;
    packet[ihl + 3] = port & 0xFF;
    recomputeChecksums(packet);
  }

  /// 把源地址改写为 [ip]:[port]（就地修改），并重算 IP/TCP 校验和。
  static void rewriteSrc(Uint8List packet, int ip, int port) {
    _writeU32(packet, 12, ip);
    final ihl = (packet[0] & 0x0F) * 4;
    packet[ihl] = (port >> 8) & 0xFF;
    packet[ihl + 1] = port & 0xFF;
    recomputeChecksums(packet);
  }

  /// 重算 IPv4 头校验和与 TCP 校验和（就地）。
  static void recomputeChecksums(Uint8List packet) {
    final ihl = (packet[0] & 0x0F) * 4;
    // IP 头校验和
    packet[10] = 0;
    packet[11] = 0;
    final ipSum = _checksum(packet, 0, ihl);
    packet[10] = (ipSum >> 8) & 0xFF;
    packet[11] = ipSum & 0xFF;

    // TCP 校验和（含伪首部）
    final tcpOffset = ihl;
    final tcpLength = packet.length - tcpOffset;
    if (tcpLength <= 0) return;
    packet[tcpOffset + 16] = 0;
    packet[tcpOffset + 17] = 0;
    var sum = 0;
    sum += _checksumPartial(packet, 12, 8); // src + dst IP
    sum += protoTcp;
    sum += tcpLength;
    sum += _checksumPartial(packet, tcpOffset, tcpLength);
    final tcpSum = _fold16(sum);
    packet[tcpOffset + 16] = (tcpSum >> 8) & 0xFF;
    packet[tcpOffset + 17] = tcpSum & 0xFF;
  }

  /// NAT 映射键：以「客户端源地址:端口」标识一条连接。
  static int natKey(int srcIp, int srcPort) => (srcIp & 0xFFFFFFFF) ^ ((srcPort & 0xFFFF) << 20);

  // ---------- helpers ----------

  static int _readU32(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static void _writeU32(Uint8List b, int o, int v) {
    b[o] = (v >> 24) & 0xFF;
    b[o + 1] = (v >> 16) & 0xFF;
    b[o + 2] = (v >> 8) & 0xFF;
    b[o + 3] = v & 0xFF;
  }

  static int _checksum(Uint8List data, int offset, int length) {
    var sum = 0;
    var i = offset;
    final end = offset + length;
    while (i + 1 < end) {
      sum += (data[i] << 8) | data[i + 1];
      i += 2;
    }
    if (i < end) sum += data[i] << 8;
    return _fold16(sum);
  }

  static int _checksumPartial(Uint8List data, int offset, int length) {
    var sum = 0;
    var i = offset;
    final end = offset + length;
    while (i + 1 < end) {
      sum += (data[i] << 8) | data[i + 1];
      i += 2;
    }
    if (i < end) sum += data[i] << 8;
    return sum;
  }

  static int _fold16(int sum) {
    while (sum > 0xFFFF) {
      sum = (sum & 0xFFFF) + (sum >> 16);
    }
    return (~sum) & 0xFFFF;
  }
}

/// IPv4 + UDP 的最小解析（纯 Dart）。
///
/// UDP 是无连接的，透明抓取时只做「读上看一眼、再原样放回」，不改写地址；
/// 这里复用 [PacketInfo] 承载字段（`tcpOffset` 即 UDP 头偏移）。
class Ipv4Udp {
  static const int protoUdp = 17;

  /// 解析一条 IPv4/UDP 报文；不是 IPv4/UDP 返回 null。
  static PacketInfo? parse(Uint8List packet) {
    if (packet.length < 20) return null;
    if ((packet[0] >> 4) != 4) return null;
    final ihl = (packet[0] & 0x0F) * 4;
    if (ihl < 20 || packet.length < ihl + 8) return null;
    if (packet[9] != protoUdp) return null;

    final totalLength = (packet[2] << 8) | packet[3];
    final frag = (packet[6] << 8) | packet[7];
    // 忽略分片
    if ((frag & 0x1FFF) != 0) return null;

    final srcIp = (packet[12] << 24) | (packet[13] << 16) | (packet[14] << 8) | packet[15];
    final dstIp = (packet[16] << 24) | (packet[17] << 16) | (packet[18] << 8) | packet[19];

    final udp = ihl;
    final srcPort = (packet[udp] << 8) | packet[udp + 1];
    final dstPort = (packet[udp + 2] << 8) | packet[udp + 3];

    return PacketInfo(
      packet: packet,
      ipHeaderLength: ihl,
      tcpOffset: udp,
      payloadOffset: udp + 8,
      declaredLength: totalLength,
      srcIp: srcIp,
      dstIp: dstIp,
      srcPort: srcPort,
      dstPort: dstPort,
      flags: 0,
    );
  }
}

class PacketInfo {
  final Uint8List packet;
  final int ipHeaderLength;
  final int tcpOffset;
  final int payloadOffset;
  final int declaredLength;
  final int srcIp;
  final int dstIp;
  final int srcPort;
  final int dstPort;
  final int flags;

  const PacketInfo({
    required this.packet,
    required this.ipHeaderLength,
    required this.tcpOffset,
    required this.payloadOffset,
    required this.declaredLength,
    required this.srcIp,
    required this.dstIp,
    required this.srcPort,
    required this.dstPort,
    required this.flags,
  });

  bool get syn => (flags & 0x02) != 0;
  bool get ack => (flags & 0x10) != 0;
  bool get fin => (flags & 0x01) != 0;
  bool get rst => (flags & 0x04) != 0;
  bool get isSyn => syn && !ack;
  int get payloadLength => packet.length - payloadOffset;

  String get srcIpText => ipText(srcIp);
  String get dstIpText => ipText(dstIp);

  /// int → 点分十进制
  static String ipText(int ip) =>
      '${(ip >> 24) & 0xFF}.${(ip >> 16) & 0xFF}.${(ip >> 8) & 0xFF}.${ip & 0xFF}';

  static int ipOf(String text) {
    final parts = text.split('.');
    if (parts.length != 4) return 0;
    var v = 0;
    for (final p in parts) {
      v = (v << 8) | (int.tryParse(p) ?? 0);
    }
    return v;
  }
}
