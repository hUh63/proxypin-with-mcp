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

/// QUIC v1 Initial 包密钥派生（上游 #489：root/VPN 管道下解析 QUIC 连接的第一步）。
///
/// 依据 RFC 9001 §5.2 与 RFC 8446 §7.1：
///   initial_secret      = HKDF-Extract(initial_salt, client_dst_connection_id)
///   client_initial_secret = HKDF-Expand-Label(initial_secret, "client in", "", 32)
///   key / iv / hp        = HKDF-Expand-Label(client_initial_secret, "quic key/iv/hp", "", n)
/// 派生结果已对照 RFC 9001 附录 A.1 官方测试向量（见 [verifyRfc9001Vector]）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// RFC 9001 固定 Initial 盐
const List<int> quicV1InitialSalt = [
  0x38, 0x76, 0x2c, 0xf7, 0xf5, 0x59, 0x34, 0xb3,
  0x4d, 0x17, 0x9a, 0xe6, 0xa4, 0xc8, 0x0c, 0xad, 0xcc, 0xbb, 0x7f, 0x0a,
];

/// QUIC v1 Initial 阶段密钥集
class QuicInitialKeys {
  final Uint8List initialSecret;
  final Uint8List clientInitialSecret;
  final Uint8List key; // 16B AES-128
  final Uint8List iv; // 12B
  final Uint8List hp; // 16B header protection

  QuicInitialKeys({
    required this.initialSecret,
    required this.clientInitialSecret,
    required this.key,
    required this.iv,
    required this.hp,
  });
}

Uint8List _hmacSha256(List<int> key, List<int> data) {
  return Uint8List.fromList(Hmac(sha256, key).convert(data).bytes);
}

/// HKDF-Extract（RFC 5869）
Uint8List _hkdfExtract(List<int> salt, List<int> ikm) => _hmacSha256(salt, ikm);

/// HKDF-Expand（RFC 5869），一次性展开到 [length]
Uint8List _hkdfExpand(List<int> prk, List<int> info, int length) {
  final out = BytesBuilder();
  Uint8List t = Uint8List(0);
  var i = 1;
  while (out.length < length) {
    final input = BytesBuilder()..add(t)..add(info)..addByte(i++);
    t = _hmacSha256(prk, input.toBytes());
    out.add(t);
  }
  final bytes = out.toBytes();
  return Uint8List.sublistView(bytes, 0, length);
}

/// TLS 1.3 HKDF-Expand-Label（RFC 8446 §7.1）
Uint8List _hkdfExpandLabel(List<int> secret, String label, List<int> context, int length) {
  final labelBytes = utf8.encode('tls13 $label');
  final info = BytesBuilder()
    ..add(_uint16(length))
    ..addByte(labelBytes.length)
    ..add(labelBytes)
    ..addByte(context.length)
    ..add(context);
  return _hkdfExpand(secret, info.toBytes(), length);
}

Uint8List _uint16(int v) => Uint8List.fromList([(v >> 8) & 0xff, v & 0xff]);

/// 由客户端目的连接 ID 派生 QUIC v1 Initial 密钥
QuicInitialKeys deriveQuicV1InitialKeys(List<int> clientDstConnectionId) {
  final salt = Uint8List.fromList(quicV1InitialSalt);
  final cid = Uint8List.fromList(clientDstConnectionId);
  final initialSecret = _hkdfExtract(salt, cid);
  final clientInitialSecret = _hkdfExpandLabel(initialSecret, 'client in', const [], 32);
  final key = _hkdfExpandLabel(clientInitialSecret, 'quic key', const [], 16);
  final iv = _hkdfExpandLabel(clientInitialSecret, 'quic iv', const [], 12);
  final hp = _hkdfExpandLabel(clientInitialSecret, 'quic hp', const [], 16);
  return QuicInitialKeys(
    initialSecret: initialSecret,
    clientInitialSecret: clientInitialSecret,
    key: key,
    iv: iv,
    hp: hp,
  );
}

String _hex(List<int> b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

/// RFC 9001 附录 A.1 测试向量自检；派生不符时抛异常
void verifyRfc9001Vector() {
  const cidHex = '8394c8f03e515708';
  final cid = Uint8List.fromList(_hexToBytes(cidHex));
  final k = deriveQuicV1InitialKeys(cid);
  const expect = {
    'initial_secret': '7db5df06e7a69e432496adedb00851923595221596ae2ae9fb8115c1e9ed0a44',
    'client_initial': 'c00cf151ca5be075ed0ebfb5c80323c42d6b7db67881289af4008f1f6c357aea',
    'key': '1f369613dd76d5467730efcbe3b1a22d',
    'iv': 'fa044b2f42a3fd3b46fb255c',
    'hp': '9f50449e04a0e810283a1e9933adedd2',
  };
  if (_hex(k.initialSecret) != expect['initial_secret'] ||
      _hex(k.clientInitialSecret) != expect['client_initial'] ||
      _hex(k.key) != expect['key'] ||
      _hex(k.iv) != expect['iv'] ||
      _hex(k.hp) != expect['hp']) {
    throw StateError('QUIC Initial 密钥派生与 RFC 9001 A.1 测试向量不一致');
  }
}

List<int> _hexToBytes(String hex) {
  final out = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}
