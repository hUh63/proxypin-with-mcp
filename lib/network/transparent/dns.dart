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

/// 一条 DNS 查询/应答的摘要（从 UDP 负载解析）。
class DnsMessage {
  final String name;
  final int qtype;
  final int qclass;
  final bool isResponse;
  final bool truncated;

  const DnsMessage({
    required this.name,
    required this.qtype,
    required this.qclass,
    required this.isResponse,
    required this.truncated,
  });

  String get typeText => Dns.typeName(qtype);
}

/// 极简 DNS 报文解析（纯 Dart，无平台依赖）。
///
/// 只做一件事：从 UDP 负载里取出**第一个 question 的查询名与类型**，供「内核抓包」
/// 面板把访问的域名显示出来。不解析 answer、不处理压缩指针（question 段本不该有指针）。
class Dns {
  static const int typeA = 1;
  static const int typeNS = 2;
  static const int typeCNAME = 5;
  static const int typeSOA = 6;
  static const int typePTR = 12;
  static const int typeMX = 15;
  static const int typeTXT = 16;
  static const int typeAAAA = 28;
  static const int typeSRV = 33;
  static const int typeHTTPS = 65;

  /// 端口 53 的一次 UDP 负载 → [DnsMessage]；不是合法 DNS 查询/应答返回 null。
  static DnsMessage? parse(Uint8List payload) {
    if (payload.length < 12) return null;
    final flags = (payload[2] << 8) | payload[3];
    final isResponse = (flags & 0x8000) != 0;
    final truncated = (flags & 0x0200) != 0;
    final qdCount = (payload[4] << 8) | payload[5];
    if (qdCount < 1) return null;

    var off = 12;
    final labels = <String>[];
    var guard = 0;
    while (off < payload.length && guard++ < 128) {
      final len = payload[off];
      if (len == 0) {
        off++;
        break;
      }
      // question 段出现压缩指针（0xC0）说明不是标准查询，放弃
      if ((len & 0xC0) != 0) return null;
      if (off + 1 + len > payload.length) return null;
      labels.add(String.fromCharCodes(payload.sublist(off + 1, off + 1 + len)));
      off += 1 + len;
    }
    if (off + 4 > payload.length) return null;
    final qtype = (payload[off] << 8) | payload[off + 1];
    final qclass = (payload[off + 2] << 8) | payload[off + 3];
    final name = labels.isEmpty ? '.' : labels.join('.');
    return DnsMessage(
      name: name,
      qtype: qtype,
      qclass: qclass,
      isResponse: isResponse,
      truncated: truncated,
    );
  }

  static String typeName(int t) {
    switch (t) {
      case typeA:
        return 'A';
      case typeNS:
        return 'NS';
      case typeCNAME:
        return 'CNAME';
      case typeSOA:
        return 'SOA';
      case typePTR:
        return 'PTR';
      case typeMX:
        return 'MX';
      case typeTXT:
        return 'TXT';
      case typeAAAA:
        return 'AAAA';
      case typeSRV:
        return 'SRV';
      case typeHTTPS:
        return 'HTTPS';
      default:
        return 'TYPE$t';
    }
  }

  /// 由 [query] 查询报文构造一个响应：命中 [a]（IPv4，4 字节）或 [aaaa]（IPv6，16 字节）
  /// 时带上 A/AAAA 答案；否则返回 NOERROR 空答案响应。解析失败返回 null。
  ///
  /// 用于「DNS 本地改写」：命中规则时丢弃原查询、注入本响应。
  static Uint8List? buildResponse(Uint8List query, {List<int>? a, List<int>? aaaa, int ttl = 60}) {
    final msg = parse(query);
    if (msg == null || msg.isResponse) return null;

    // question 段结束位置
    var off = 12;
    var guard = 0;
    while (off < query.length && guard++ < 128) {
      final len = query[off];
      if (len == 0) {
        off++;
        break;
      }
      if ((len & 0xC0) != 0) return null;
      off += 1 + len;
    }
    final qEnd = off + 4;
    if (qEnd > query.length) return null;

    List<int>? rdata;
    if (msg.qtype == typeA && a != null && a.length == 4) {
      rdata = a;
    } else if (msg.qtype == typeAAAA && aaaa != null && aaaa.length == 16) {
      rdata = aaaa;
    }

    final b = BytesBuilder();
    b.add([query[0], query[1]]); // txid
    b.add([0x81, 0x80]); // QR=1, RD=1, RA=1, RCODE=0
    b.add([0x00, 0x01]); // QDCOUNT
    b.add([0x00, rdata != null ? 0x01 : 0x00]); // ANCOUNT
    b.add([0x00, 0x00]); // NSCOUNT
    b.add([0x00, 0x00]); // ARCOUNT
    b.add(query.sublist(12, qEnd)); // 原 question
    if (rdata != null) {
      b.add([0xC0, 0x0C]); // 名字指针 → offset 12
      b.add([(msg.qtype >> 8) & 0xFF, msg.qtype & 0xFF]);
      b.add([0x00, 0x01]); // class IN
      b.add([(ttl >> 24) & 0xFF, (ttl >> 16) & 0xFF, (ttl >> 8) & 0xFF, ttl & 0xFF]);
      b.add([0x00, rdata.length]);
      b.add(rdata);
    }
    return b.toBytes();
  }
}
