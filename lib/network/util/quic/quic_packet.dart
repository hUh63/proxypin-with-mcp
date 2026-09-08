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

/// QUIC v1 包解析与 Initial 解密（上游 #489 管线第二步）。
///
/// 依据 RFC 9000/9001：
///  - 长头包明文字段解析：版本 / DCID / SCID / token
///  - Header Protection（RFC 9001 §5.4）：AES-ECB(hp, sample) 掩码 → 包号长度与包号
///  - Initial payload 解密（RFC 9001 §5.2）：AES-128-GCM，
///    nonce = iv XOR 包号(8B 大端)，AAD = 未加密头 + 解保护后的包号区；标签失败返 null
///  - 帧遍历：拼接 CRYPTO 数据（含 TLS ClientHello 前缀），供上层提取 SNI
///
/// 密钥派生见 [deriveQuicV1InitialKeys]（RFC 9001 A.1 向量已内置校验）。
/// 失败路径均安全返回（null/false/FormatException 由上层忽略该包）。
library;

import 'dart:typed_data';

import 'package:pointycastle/pointycastle.dart';

import 'quic_keys.dart';

/// 解析结果（明文字段 + 解密后信息）
class QuicInitialInfo {
  final int version;
  final Uint8List dcid;
  final Uint8List scid;
  final bool hasToken;
  final int packetNumber;
  final int frameCount;
  final Uint8List? cryptoData; // 本包内 CRYPTO 帧数据拼接
  final bool decrypted;

  const QuicInitialInfo({
    required this.version,
    required this.dcid,
    required this.scid,
    required this.hasToken,
    required this.packetNumber,
    this.frameCount = 0,
    this.cryptoData,
    this.decrypted = false,
  });
}

class _Reader {
  final Uint8List data;
  int pos = 0;
  _Reader(this.data);

  int readByte() {
    if (pos >= data.length) throw RangeError('QUIC 数据不足');
    return data[pos++];
  }

  Uint8List readBytes(int n) {
    if (pos + n > data.length) throw RangeError('QUIC 数据不足');
    final out = Uint8List.sublistView(data, pos, pos + n);
    pos += n;
    return out;
  }

  /// varint（RFC 9000 §16）
  int readVarInt() {
    final first = readByte();
    final len = 1 << (first >> 6);
    var value = first & 0x3f;
    for (var i = 1; i < len; i++) {
      value = (value << 8) | readByte();
    }
    return value;
  }
}

/// 从长头 Initial 包中取明文字段并解 Header Protection；
/// 返回明文头结束位置、pn 长度与 pn、dcid/scid 及解保护后的完整头（AAD）。
({int pnOffset, int pnLen, int pn, int version, Uint8List dcid, Uint8List scid, bool hasToken, Uint8List aad})
    _parseHeader(Uint8List packet, Uint8List hp) {
  final r = _Reader(packet);
  final first = r.readByte();
  if ((first & 0xc0) != 0xc0) throw const FormatException('非长头包');
  if (((first >> 4) & 0x03) != 0x00) throw const FormatException('非 Initial 包');

  final version = (r.readByte() << 24) |
      (r.readByte() << 16) |
      (r.readByte() << 8) |
      r.readByte();
  final dcid = r.readBytes(r.readByte());
  final scid = r.readBytes(r.readByte());
  final tokenLen = r.readVarInt();
  final hasToken = tokenLen > 0;
  if (tokenLen > 0) r.readBytes(tokenLen);

  final pnOffset = r.pos;
  if (packet.length < pnOffset + 4 + 16) {
    throw const FormatException('包太短，无法采样');
  }
  final sample = Uint8List.sublistView(packet, pnOffset, pnOffset + 16);
  final mask = headerMask(hp, sample);
  final unprotectedFirst = first ^ (mask[0] & 0x1f);
  final pnLen = (unprotectedFirst & 0x03) + 1;

  var pn = 0;
  for (var i = 0; i < pnLen; i++) {
    pn = (pn << 8) | (packet[pnOffset + i] ^ mask[i + 1]);
  }
  // 解保护后的完整头（AAD）：byte0（解保留位）+ 明文 + pn 明文区
  final aad = Uint8List.fromList(packet.sublist(0, pnOffset + pnLen));
  aad[0] = unprotectedFirst;
  for (var i = 0; i < pnLen; i++) {
    aad[pnOffset + i] ^= mask[i + 1];
  }
  return (
    pnOffset: pnOffset,
    pnLen: pnLen,
    pn: pn,
    version: version,
    dcid: dcid,
    scid: scid,
    hasToken: hasToken,
    aad: aad,
  );
}

/// Header Protection 掩码前 5 字节：AES-ECB(hp, sample)（RFC 9001 §5.4.3）
Uint8List headerMask(Uint8List hp, Uint8List sample) {
  final cipher = ECBBlockCipher(AESEngine())..init(true, KeyParameter(hp));
  final out = Uint8List(16);
  cipher.processBlock(sample, 0, out, 0);
  return Uint8List.sublistView(out, 0, 5);
}

/// 解析长头 Initial 包（明文字段 + Header Protection），不解密 payload。
/// 非 Initial / 数据不足抛 FormatException。
QuicInitialInfo parseQuicInitial(Uint8List packet) {
  final keys = deriveQuicV1InitialKeys(_dcidOf(packet));
  final h = _parseHeader(packet, keys.hp);
  return QuicInitialInfo(
    version: h.version,
    dcid: h.dcid,
    scid: h.scid,
    hasToken: h.hasToken,
    packetNumber: h.pn,
  );
}

/// 解密 Initial payload。成功返回解出帧数据；密钥不符/损坏返回 null。
/// [frameScan] 为 true 时顺带遍历帧并返回 CRYPTO 拼接与帧计数。
QuicInitialInfo? decryptQuicInitial(Uint8List packet, {bool frameScan = true}) {
  try {
    final keys = deriveQuicV1InitialKeys(_dcidOf(packet));
    final h = _parseHeader(packet, keys.hp);
    final headerEnd = h.pnOffset + h.pnLen;
    if (packet.length < headerEnd + 16) return null;
    final aad = h.aad;

    // nonce = iv XOR pn(8B 大端)
    final nonce = Uint8List.fromList(keys.iv);
    var pn = h.pn;
    for (var i = 7; i >= 0; i--) {
      nonce[i] ^= (pn & 0xff);
      pn >>= 8;
    }

    final ciphertext = Uint8List.sublistView(packet, headerEnd, packet.length);
    final plain = aes128GcmDecrypt(keys.key, nonce, aad, ciphertext);
    if (plain == null) return null;

    var frameCount = 0;
    Uint8List? crypto;
    if (frameScan) {
      final scan = scanFrames(plain);
      frameCount = scan.$1;
      crypto = scan.$2;
    }
    return QuicInitialInfo(
      version: h.version,
      dcid: h.dcid,
      scid: h.scid,
      hasToken: h.hasToken,
      packetNumber: h.pn,
      frameCount: frameCount,
      cryptoData: crypto,
      decrypted: true,
    );
  } catch (_) {
    return null;
  }
}

/// AES-128-GCM 解密（点城堡 GCMBlockCipher）；标签校验失败返回 null
Uint8List? aes128GcmDecrypt(
    Uint8List key, Uint8List iv, Uint8List aad, Uint8List ciphertextWithTag) {
  try {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, aad));
    final out = Uint8List(cipher.getOutputSize(ciphertextWithTag.length));
    var len =
        cipher.processBytes(ciphertextWithTag, 0, ciphertextWithTag.length, out, 0);
    try {
      len += cipher.doFinal(out, len);
    } catch (_) {
      return null;
    }
    return Uint8List.sublistView(out, 0, len);
  } catch (_) {
    return null;
  }
}

/// 遍历 QUIC 帧：返回 (帧计数, CRYPTO 数据拼接)。
/// CRYPTO 帧 type=0x06（含变长 offset/length/data）。
(int, Uint8List?) scanFrames(Uint8List payload) {
  final r = _Reader(payload);
  final crypto = BytesBuilder();
  var count = 0;
  try {
    while (r.pos < payload.length) {
      final type = r.readVarInt();
      count++;
      if (type == 0x06) {
        // CRYPTO：offset + length + data
        r.readVarInt(); // offset（跨包重组由上层做）
        final len = r.readVarInt();
        crypto.add(r.readBytes(len));
      } else if (type == 0x00 || type == 0x01 || type == 0x02) {
        // PADDING / PING / ACK（ACK 后续变长字段，直接忽略余下帧避免误读）
        if (type == 0x00) continue;
        if (type == 0x01) continue;
        // ACK 帧长度不定，保守终止扫描
        break;
      } else {
        // 其它帧（STREAM 等）长度不定，跳过本包剩余内容（帧边界需 FL 位）
        break;
      }
    }
  } catch (_) {/* 数据不足按包尾处理 */}
  final b = crypto.toBytes();
  return (count, b.isEmpty ? null : Uint8List.fromList(b));
}

/// 提取包中 DCID（头部偏移固定：1+4 版本后 1 字节长度）
Uint8List _dcidOf(Uint8List packet) {
  final len = packet[5];
  return Uint8List.sublistView(packet, 6, 6 + len);
}
