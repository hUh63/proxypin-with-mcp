/*
 * Copyright 2025 Hongen Wang All rights reserved.
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

import 'package:proxypin/network/util/quic/quic_keys.dart';
import 'package:proxypin/network/util/quic/quic_packet.dart';

/// QUIC 1-RTT（short header）包解密与 STREAM 帧解析（上游 #489）。
///
/// 前提：已经通过**密钥日志**拿到 traffic secret（见 QuicKeylogStore）。
/// 本文件只做"解到流数据层"：
///   short header → 解保护 → AEAD 解密 → 帧解析 → STREAM 数据
/// HTTP/3 的 HEADERS 帧内部是 QPACK 压缩，本版不做解码，仅给出帧类型与数据预览。

/// 解出的一个 STREAM 帧
class QuicStreamFrame {
  final int streamId;
  final int offset;
  final bool fin;
  final Uint8List data;

  QuicStreamFrame({required this.streamId, required this.offset, required this.fin, required this.data});
}

/// 一个 1-RTT 包的解密结果
class QuicDecryptedPacket {
  final int packetNumber;
  final Uint8List payload;
  final List<QuicStreamFrame> streams;

  QuicDecryptedPacket({required this.packetNumber, required this.payload, required this.streams});
}

/// 解密客户端发送方向的 1-RTT 包。
///
/// [destCidLength]：客户端发出的包所使用的 DCID 长度
/// （= 服务端在 Initial 包里声明的 SCID 长度）。
/// 解密失败（包不完整、AEAD 校验不过）返回 null。
QuicDecryptedPacket? decryptShortHeaderPacket(
  Uint8List packet,
  QuicTrafficKeys keys, {
  required int destCidLength,
}) {
  if (packet.length < 1 + destCidLength + 1 + 16) return null;
  if ((packet[0] & 0x80) != 0) return null; // long header，不是 1-RTT

  final pnOffset = 1 + destCidLength;
  if (pnOffset + 4 + 16 > packet.length) return null;

  // 采样从包号字段之后 4 字节开始，取 16 字节
  final sample = Uint8List.sublistView(packet, pnOffset + 4, pnOffset + 4 + 16);
  final mask = headerMask(keys.hp, sample);

  // short header 只保护首字节的低 5 位
  final first = packet[0] ^ (mask[0] & 0x1f);
  final pnLen = (first & 0x03) + 1;
  if (pnOffset + pnLen > packet.length) return null;

  var packetNumber = 0;
  for (var i = 0; i < pnLen; i++) {
    packetNumber = (packetNumber << 8) | (packet[pnOffset + i] ^ mask[1 + i]);
  }

  final headerEnd = pnOffset + pnLen;
  final aad = Uint8List.fromList(packet.sublist(0, headerEnd));
  final ciphertext = Uint8List.sublistView(packet, headerEnd, packet.length);

  // nonce = iv XOR 包号（右对齐 8 字节）
  final nonce = Uint8List.fromList(keys.iv);
  for (var i = 0; i < 8; i++) {
    nonce[nonce.length - 1 - i] ^= (packetNumber >> (8 * i)) & 0xff;
  }

  final plain = aes128GcmDecrypt(keys.key, nonce, aad, ciphertext);
  if (plain == null) return null;

  return QuicDecryptedPacket(
    packetNumber: packetNumber,
    payload: plain,
    streams: parseStreamFrames(plain),
  );
}

/// 解析帧中的 STREAM 帧（其它帧类型按规范长度跳过）。
/// 遇到无法识别的帧类型就停止，避免把后续字节误解析。
List<QuicStreamFrame> parseStreamFrames(Uint8List payload) {
  final frames = <QuicStreamFrame>[];
  var pos = 0;

  int? readVarInt() {
    if (pos >= payload.length) return null;
    final first = payload[pos];
    final len = 1 << (first >> 6);
    if (pos + len > payload.length) return null;
    var value = first & 0x3f;
    for (var i = 1; i < len; i++) {
      value = (value << 8) | payload[pos + i];
    }
    pos += len;
    return value;
  }

  while (pos < payload.length) {
    final type = readVarInt();
    if (type == null) break;

    if (type == 0x00 || type == 0x01) {
      continue; // PADDING / PING
    }
    if (type == 0x02 || type == 0x03) {
      // ACK：largest / delay / rangeCount / firstRange + rangeCount 组 (gap, length)
      final largest = readVarInt();
      final delay = readVarInt();
      final rangeCount = readVarInt();
      final firstRange = readVarInt();
      if (largest == null || delay == null || rangeCount == null || firstRange == null) break;
      var ok = true;
      for (var i = 0; i < rangeCount; i++) {
        if (readVarInt() == null || readVarInt() == null) {
          ok = false;
          break;
        }
      }
      if (!ok) break;
      continue;
    }
    if (type == 0x06) {
      // CRYPTO：length + data（握手数据，本版跳过）
      final len = readVarInt();
      if (len == null || pos + len > payload.length) break;
      pos += len;
      continue;
    }
    if (type >= 0x08 && type <= 0x0f) {
      // STREAM：低 3 位 = OFF(0x04) / LEN(0x02) / FIN(0x01)
      final streamId = readVarInt();
      if (streamId == null) break;

      var offset = 0;
      if ((type & 0x04) != 0) {
        offset = readVarInt() ?? 0;
      }

      var length = payload.length - pos;
      if ((type & 0x02) != 0) {
        final explicit = readVarInt();
        if (explicit == null) break;
        length = explicit;
      }
      if (pos + length > payload.length) length = payload.length - pos;

      frames.add(QuicStreamFrame(
        streamId: streamId,
        offset: offset,
        fin: (type & 0x01) != 0,
        data: Uint8List.sublistView(payload, pos, pos + length),
      ));
      pos += length;
      continue;
    }

    break; // 其它帧类型（MAX_DATA / NEW_CONNECTION_ID 等）不解析
  }

  return frames;
}

/// HTTP/3 帧类型名（RFC 9114），用于给预览加个说明
String http3FrameName(int type) {
  switch (type) {
    case 0x00:
      return 'DATA';
    case 0x01:
      return 'HEADERS(QPACK 压缩)';
    case 0x03:
      return 'CANCEL_PUSH';
    case 0x04:
      return 'SETTINGS';
    case 0x05:
      return 'PUSH_PROMISE';
    case 0x07:
      return 'GOAWAY';
    case 0x0d:
      return 'MAX_PUSH_ID';
    default:
      return '0x${type.toRadixString(16)}';
  }
}

/// 生成流数据的可读预览：可打印 ASCII 原样显示，其余转成 `\xNN`。
String previewStreamData(Uint8List data, {int limit = 400}) {
  final out = StringBuffer();
  final end = data.length < limit ? data.length : limit;
  for (var i = 0; i < end; i++) {
    final byte = data[i];
    if (byte == 0x0a) {
      out.write('\\n');
    } else if (byte == 0x0d) {
      out.write('\\r');
    } else if (byte == 0x09) {
      out.write('\\t');
    } else if (byte >= 0x20 && byte < 0x7f) {
      out.writeCharCode(byte);
    } else {
      out.write('\\x${byte.toRadixString(16).padLeft(2, '0')}');
    }
  }
  if (data.length > end) out.write('…(+${data.length - end}B)');
  return out.toString();
}
