/*
 * 分享内容加密（上游 #133：重写规则分享时可选择加密 / 口令保护）
 *
 * 采用口令派生密钥 + 认证加密：
 *   key = PBKDF2-HMAC-SHA256(password, salt, 50000 次) → 32 字节
 *   AES-256-GCM(key, iv) 加密明文，附带认证标签（口令错误或内容被篡改会解密失败）
 *
 * 文本格式：PROXYPIN-ENC1:<base64Url(JSON 封装)>
 * 明文内容不加密时仍走原有明文格式，导入侧自动识别（前缀判断），完全向后兼容。
 */
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:proxypin/network/util/crypto.dart';

class SecureShare {
  static const String prefix = 'PROXYPIN-ENC1:';
  static const int _iterations = 50000;
  static const int _saltLength = 16;
  static const int _ivLength = 12;
  static const int _keyLength = 32;
  static const int _tagBits = 128;
  static const int minPasswordLength = 4;

  /// 内容是否为加密载荷
  static bool isEncrypted(String text) => text.trimLeft().startsWith(prefix);

  /// 加密：口令不足 [minPasswordLength] 位时抛 [ArgumentError]
  static String encrypt(String plaintext, String password) {
    if (password.length < minPasswordLength) {
      throw ArgumentError('口令至少 ${minPasswordLength} 位');
    }
    final random = CryptoUtils.getSecureRandom();
    final salt = random.nextBytes(_saltLength);
    final iv = random.nextBytes(_ivLength);
    final key = _deriveKey(password, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), _tagBits, iv, Uint8List(0)));
    final encrypted = cipher.process(Uint8List.fromList(utf8.encode(plaintext)));

    final envelope = {
      'v': 1,
      'alg': 'AES-256-GCM',
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iter': _iterations,
      'salt': base64Encode(salt),
      'iv': base64Encode(iv),
      'ct': base64Encode(encrypted),
    };
    return prefix + base64Url.encode(utf8.encode(jsonEncode(envelope)));
  }

  /// 解密：口令错误 / 内容被篡改 / 格式不合法时抛 [FormatException]
  static String decrypt(String payload, String password) {
    var text = payload.trim();
    if (!text.startsWith(prefix)) {
      throw const FormatException('不是加密内容');
    }
    Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(utf8.decode(base64Url.decode(text.substring(prefix.length).trim())))
          as Map<String, dynamic>;
    } catch (e) {
      throw const FormatException('加密内容格式损坏');
    }

    final salt = base64Decode(envelope['salt']?.toString() ?? '');
    final iv = base64Decode(envelope['iv']?.toString() ?? '');
    final ct = base64Decode(envelope['ct']?.toString() ?? '');
    final iterations = (envelope['iter'] as num?)?.toInt() ?? _iterations;

    final key = _deriveKey(password, salt, iterations);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), _tagBits, iv, Uint8List(0)));
    try {
      final plain = cipher.process(ct);
      return utf8.decode(plain);
    } catch (e) {
      // GCM 认证失败（口令错误或数据被改动）
      throw const FormatException('口令错误或内容已被篡改');
    }
  }

  /// 口令派生密钥：PBKDF2-HMAC-SHA256（纯 Dart 实现，避免额外依赖）
  static Uint8List _deriveKey(String password, Uint8List salt, [int iterations = _iterations]) {
    return _pbkdf2(utf8.encode(password), salt, iterations, _keyLength);
  }

  /// PBKDF2-HMAC-SHA256：dkLen 字节输出（按 32 字节块迭代异或）
  static Uint8List _pbkdf2(List<int> password, Uint8List salt, int iterations, int dkLen) {
    final hmac = Hmac(sha256, password);
    final blocks = (dkLen / 32).ceil();
    final builder = BytesBuilder();
    for (var block = 1; block <= blocks; block++) {
      final input = <int>[
        ...salt,
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff,
      ];
      var u = hmac.convert(input).bytes;
      final t = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var k = 0; k < t.length; k++) {
          t[k] ^= u[k];
        }
      }
      builder.add(t);
    }
    return Uint8List.fromList(builder.toBytes().sublist(0, dkLen));
  }
}
