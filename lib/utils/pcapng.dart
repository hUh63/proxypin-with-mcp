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

/// 合成一条连接上的一个请求 / 响应往返（承载的都是**已解密的明文 HTTP**字节）。
class PcapSession {
  final List<int> clientIp; // 4 bytes
  final int clientPort;
  final List<int> serverIp; // 4 bytes
  final int serverPort;
  final List<int> requestBytes;
  final List<int> responseBytes;
  final DateTime requestTime;
  final DateTime? responseTime;

  PcapSession({
    required this.clientIp,
    required this.clientPort,
    required this.serverIp,
    required this.serverPort,
    required this.requestBytes,
    required this.responseBytes,
    required this.requestTime,
    this.responseTime,
  });
}

/// 极简 PCAPNG 写出器（纯 Dart，可单测）。
///
/// 说明：ProxyPin 工作在 TCP 流层、且对 TLS 做了 MITM，手里只有**解密后的明文 HTTP
/// 字节**，没有原始链路层报文。因此这里按「一条请求 = 一个请求报文 + 一个响应报文」
/// **合成** 以太网 / IPv4 / TCP 帧写入 PCAPNG（正确的 IPv4 头校验和与 TCP 校验和），
/// 这样 Wireshark 能打开并按 TCP 流重组查看明文 HTTP。
///
/// 注意事项：合成帧里 HTTPS 流量的端口仍是 443，但内容是明文，Wireshark 默认会按
/// TLS 解析而显示为乱码，需要右键 → Decode As → HTTP。
class PcapNg {
  static const List<int> _clientMac = [0x02, 0x00, 0x00, 0x00, 0x00, 0x01];
  static const List<int> _serverMac = [0x02, 0x00, 0x00, 0x00, 0x00, 0x02];

  static Uint8List build(List<PcapSession> sessions) {
    final out = BytesBuilder(copy: false);
    _sectionHeader(out);
    _interfaceDescription(out);

    for (final s in sessions) {
      var clientSeq = 1;
      var serverSeq = 1;

      if (s.requestBytes.isNotEmpty) {
        final frame = _ethernet(
          srcMac: _clientMac,
          dstMac: _serverMac,
          srcIp: s.clientIp,
          dstIp: s.serverIp,
          srcPort: s.clientPort,
          dstPort: s.serverPort,
          seq: clientSeq,
          ack: serverSeq,
          payload: s.requestBytes,
        );
        _enhancedPacket(out, s.requestTime, frame);
        clientSeq += s.requestBytes.length;
      }

      final respTime = s.responseTime;
      if (s.responseBytes.isNotEmpty && respTime != null) {
        final frame = _ethernet(
          srcMac: _serverMac,
          dstMac: _clientMac,
          srcIp: s.serverIp,
          dstIp: s.clientIp,
          srcPort: s.serverPort,
          dstPort: s.clientPort,
          seq: serverSeq,
          ack: clientSeq,
          payload: s.responseBytes,
        );
        _enhancedPacket(out, respTime, frame);
        serverSeq += s.responseBytes.length;
      }
    }
    return out.toBytes();
  }

  // ---------- block writers ----------

  static void _sectionHeader(BytesBuilder b) {
    const total = 28;
    _u32(b, 0x0A0D0D0A);
    _u32(b, total);
    _u32(b, 0x1A2B3C4D); // byte-order magic
    _u16(b, 1); // major
    _u16(b, 0); // minor
    _i64(b, -1); // section length: unspecified
    _u32(b, total);
  }

  static void _interfaceDescription(BytesBuilder b) {
    const total = 20;
    _u32(b, 0x00000001);
    _u32(b, total);
    _u16(b, 1); // link type: Ethernet
    _u16(b, 0);
    _u32(b, 0); // snaplen: unlimited
    _u32(b, total);
  }

  static void _enhancedPacket(BytesBuilder b, DateTime time, List<int> frame) {
    final padded = _pad4(frame.length);
    final total = 32 + padded; // 28-byte fixed part + 4-byte trailing length... see below
    final ts = time.toUtc().microsecondsSinceEpoch;
    final tsHigh = (ts >> 32) & 0xFFFFFFFF;
    final tsLow = ts & 0xFFFFFFFF;

    _u32(b, 0x00000006); // EPB
    _u32(b, total);
    _u32(b, 0); // interface id
    _u32(b, tsHigh);
    _u32(b, tsLow);
    _u32(b, frame.length); // captured
    _u32(b, frame.length); // original
    b.add(frame);
    for (var i = frame.length; i < padded; i++) {
      b.addByte(0);
    }
    _u32(b, total);
  }

  // ---------- frame builders ----------

  static List<int> _ethernet({
    required List<int> srcMac,
    required List<int> dstMac,
    required List<int> srcIp,
    required List<int> dstIp,
    required int srcPort,
    required int dstPort,
    required int seq,
    required int ack,
    required List<int> payload,
  }) {
    final tcp = _tcp(srcIp, dstIp, srcPort, dstPort, seq, ack, payload);
    final ip = _ipv4(srcIp, dstIp, tcp);
    final frame = <int>[];
    frame.addAll(dstMac);
    frame.addAll(srcMac);
    frame.addAll([0x08, 0x00]); // IPv4
    frame.addAll(ip);
    return frame; // ip already contains tcp
  }

  static List<int> _ipv4(List<int> srcIp, List<int> dstIp, List<int> payload) {
    final totalLength = 20 + payload.length;
    final header = <int>[
      0x45, // version 4, IHL 5
      0x00,
      (totalLength >> 8) & 0xFF,
      totalLength & 0xFF,
      0x00, 0x00, // identification
      0x40, 0x00, // flags: DF
      64, // TTL
      6, // protocol TCP
      0x00, 0x00, // checksum placeholder
      ...srcIp,
      ...dstIp,
    ];
    final checksum = _checksum(header);
    header[10] = (checksum >> 8) & 0xFF;
    header[11] = checksum & 0xFF;
    return <int>[...header, ...payload];
  }

  static List<int> _tcp(
    List<int> srcIp,
    List<int> dstIp,
    int srcPort,
    int dstPort,
    int seq,
    int ack,
    List<int> payload,
  ) {
    final header = <int>[
      (srcPort >> 8) & 0xFF, srcPort & 0xFF,
      (dstPort >> 8) & 0xFF, dstPort & 0xFF,
      (seq >> 24) & 0xFF, (seq >> 16) & 0xFF, (seq >> 8) & 0xFF, seq & 0xFF,
      (ack >> 24) & 0xFF, (ack >> 16) & 0xFF, (ack >> 8) & 0xFF, ack & 0xFF,
      0x50, // data offset 5 (<<4), reserved 0
      0x18, // PSH + ACK
      0xFF, 0xFF, // window
      0x00, 0x00, // checksum placeholder
      0x00, 0x00, // urgent pointer
    ];
    final tcpLength = header.length + payload.length;

    // 伪首部
    final pseudo = <int>[
      ...srcIp,
      ...dstIp,
      0x00,
      6,
      (tcpLength >> 8) & 0xFF,
      tcpLength & 0xFF,
    ];
    final checksum = _checksum(<int>[...pseudo, ...header, ...payload]);
    header[16] = (checksum >> 8) & 0xFF;
    header[17] = checksum & 0xFF;
    return <int>[...header, ...payload];
  }

  /// 16 位反码校验和
  static int _checksum(List<int> data) {
    var sum = 0;
    for (var i = 0; i + 1 < data.length; i += 2) {
      sum += ((data[i] & 0xFF) << 8) | (data[i + 1] & 0xFF);
    }
    if (data.length.isOdd) {
      sum += (data.last & 0xFF) << 8;
    }
    while (sum > 0xFFFF) {
      sum = (sum & 0xFFFF) + (sum >> 16);
    }
    return (~sum) & 0xFFFF;
  }

  static int _pad4(int length) => (length + 3) & ~3;

  static void _u16(BytesBuilder b, int v) {
    b.addByte(v & 0xFF);
    b.addByte((v >> 8) & 0xFF);
  }

  static void _u32(BytesBuilder b, int v) {
    b.addByte(v & 0xFF);
    b.addByte((v >> 8) & 0xFF);
    b.addByte((v >> 16) & 0xFF);
    b.addByte((v >> 24) & 0xFF);
  }

  static void _i64(BytesBuilder b, int v) {
    for (var i = 0; i < 8; i++) {
      b.addByte((v >> (8 * i)) & 0xFF);
    }
  }

  /// 把点分字符串转 4 字节 IPv4；非 IP 字面量返回 null。
  static List<int>? parseIpv4(String? value) {
    if (value == null) return null;
    final parts = value.split('.');
    if (parts.length != 4) return null;
    final out = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return null;
      out.add(n);
    }
    return out;
  }
}
