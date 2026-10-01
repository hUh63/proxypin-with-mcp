import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

import '../network/util/crypto.dart';

/// SM4 国密分组密码（GM/T 0002-2012），分组 16 字节，密钥 16 字节。
/// 用官方测试向量校验：key=plain=0123456789abcdeffedcba9876543210
/// -> 681edf34d206965e86b3e94f536e4246。
class Sm4Engine implements BlockCipher {
  static const int _mask = 0xFFFFFFFF;

  static const List<int> _sbox = <int>[
    0xd6, 0x90, 0xe9, 0xfe, 0xcc, 0xe1, 0x3d, 0xb7, 0x16, 0xb6, 0x14, 0xc2, 0x28, 0xfb, 0x2c, 0x05,
    0x2b, 0x67, 0x9a, 0x76, 0x2a, 0xbe, 0x04, 0xc3, 0xaa, 0x44, 0x13, 0x26, 0x49, 0x86, 0x06, 0x99,
    0x9c, 0x42, 0x50, 0xf4, 0x91, 0xef, 0x98, 0x7a, 0x33, 0x54, 0x0b, 0x43, 0xed, 0xcf, 0xac, 0x62,
    0xe4, 0xb3, 0x1c, 0xa9, 0xc9, 0x08, 0xe8, 0x95, 0x80, 0xdf, 0x94, 0xfa, 0x75, 0x8f, 0x3f, 0xa6,
    0x47, 0x07, 0xa7, 0xfc, 0xf3, 0x73, 0x17, 0xba, 0x83, 0x59, 0x3c, 0x19, 0xe6, 0x85, 0x4f, 0xa8,
    0x68, 0x6b, 0x81, 0xb2, 0x71, 0x64, 0xda, 0x8b, 0xf8, 0xeb, 0x0f, 0x4b, 0x70, 0x56, 0x9d, 0x35,
    0x1e, 0x24, 0x0e, 0x5e, 0x63, 0x58, 0xd1, 0xa2, 0x25, 0x22, 0x7c, 0x3b, 0x01, 0x21, 0x78, 0x87,
    0xd4, 0x00, 0x46, 0x57, 0x9f, 0xd3, 0x27, 0x52, 0x4c, 0x36, 0x02, 0xe7, 0xa0, 0xc4, 0xc8, 0x9e,
    0xea, 0xbf, 0x8a, 0xd2, 0x40, 0xc7, 0x38, 0xb5, 0xa3, 0xf7, 0xf2, 0xce, 0xf9, 0x61, 0x15, 0xa1,
    0xe0, 0xae, 0x5d, 0xa4, 0x9b, 0x34, 0x1a, 0x55, 0xad, 0x93, 0x32, 0x30, 0xf5, 0x8c, 0xb1, 0xe3,
    0x1d, 0xf6, 0xe2, 0x2e, 0x82, 0x66, 0xca, 0x60, 0xc0, 0x29, 0x23, 0xab, 0x0d, 0x53, 0x4e, 0x6f,
    0xd5, 0xdb, 0x37, 0x45, 0xde, 0xfd, 0x8e, 0x2f, 0x03, 0xff, 0x6a, 0x72, 0x6d, 0x6c, 0x5b, 0x51,
    0x8d, 0x1b, 0xaf, 0x92, 0xbb, 0xdd, 0xbc, 0x7f, 0x11, 0xd9, 0x5c, 0x41, 0x1f, 0x10, 0x5a, 0xd8,
    0x0a, 0xc1, 0x31, 0x88, 0xa5, 0xcd, 0x7b, 0xbd, 0x2d, 0x74, 0xd0, 0x12, 0xb8, 0xe5, 0xb4, 0xb0,
    0x89, 0x69, 0x97, 0x4a, 0x0c, 0x96, 0x77, 0x7e, 0x65, 0xb9, 0xf1, 0x09, 0xc5, 0x6e, 0xc6, 0x84,
    0x18, 0xf0, 0x7d, 0xec, 0x3a, 0xdc, 0x4d, 0x20, 0x79, 0xee, 0x5f, 0x3e, 0xd7, 0xcb, 0x39, 0x48,
  ];

  static const List<int> _fk = <int>[0xa3b1bac6, 0x56aa3350, 0x677d9197, 0xb27022dc];

  static const List<int> _ck = <int>[
    0x00070e15, 0x1c232a31, 0x383f464d, 0x545b6269, 0x70777e85, 0x8c939aa1, 0xa8afb6bd, 0xc4cbd2d9,
    0xe0e7eef5, 0xfc030a11, 0x181f262d, 0x343b4249, 0x50575e65, 0x6c737a81, 0x888f969d, 0xa4abb2b9,
    0xc0c7ced5, 0xdce3eaf1, 0xf8ff060d, 0x141b2229, 0x30373e45, 0x4c535a61, 0x686f767d, 0x848b9299,
    0xa0a7aeb5, 0xbcc3cad1, 0xd8dfe6ed, 0xf4fb0209, 0x10171e25, 0x2c333a41, 0x484f565d, 0x646b7279,
  ];

  List<int> _rk = const <int>[];
  bool _initialized = false;

  @override
  String get algorithmName => 'SM4';

  @override
  int get blockSize => 16;

  @override
  void reset() {}

  @override
  void init(bool forEncryption, CipherParameters? params) {
    if (params is! KeyParameter) {
      throw ArgumentError('SM4 requires a KeyParameter');
    }
    final key = params.key;
    if (key.length != 16) {
      throw ArgumentError('SM4 key must be 16 bytes');
    }
    final rk = _expandKey(key);
    _rk = forEncryption ? rk : rk.reversed.toList();
    _initialized = true;
  }

  @override
  Uint8List process(Uint8List data) {
    final out = Uint8List(blockSize);
    processBlock(data, 0, out, 0);
    return out;
  }

  @override
  int processBlock(Uint8List inp, int inpOff, Uint8List out, int outOff) {
    if (!_initialized) {
      throw StateError('SM4 engine not initialised');
    }
    final x = List<int>.filled(36, 0);
    for (var i = 0; i < 4; i++) {
      x[i] = _load32(inp, inpOff + i * 4);
    }
    for (var i = 0; i < 32; i++) {
      final t = (x[i + 1] ^ x[i + 2] ^ x[i + 3] ^ _rk[i]) & _mask;
      x[i + 4] = (x[i] ^ _t(t)) & _mask;
    }
    _store32(out, outOff, x[35]);
    _store32(out, outOff + 4, x[34]);
    _store32(out, outOff + 8, x[33]);
    _store32(out, outOff + 12, x[32]);
    return blockSize;
  }

  static int _rotl(int x, int n) => ((x << n) | (x >> (32 - n))) & _mask;

  static int _tau(int a) =>
      (_sbox[(a >> 24) & 0xff] << 24) |
      (_sbox[(a >> 16) & 0xff] << 16) |
      (_sbox[(a >> 8) & 0xff] << 8) |
      _sbox[a & 0xff];

  static int _t(int a) {
    final b = _tau(a);
    return (b ^ _rotl(b, 2) ^ _rotl(b, 10) ^ _rotl(b, 18) ^ _rotl(b, 24)) & _mask;
  }

  static int _tp(int a) {
    final b = _tau(a);
    return (b ^ _rotl(b, 13) ^ _rotl(b, 23)) & _mask;
  }

  static List<int> _expandKey(Uint8List key) {
    final k = List<int>.filled(36, 0);
    for (var i = 0; i < 4; i++) {
      k[i] = _load32(key, i * 4) ^ _fk[i];
    }
    final rk = List<int>.filled(32, 0);
    for (var i = 0; i < 32; i++) {
      final t = (k[i + 1] ^ k[i + 2] ^ k[i + 3] ^ _ck[i]) & _mask;
      k[i + 4] = (k[i] ^ _tp(t)) & _mask;
      rk[i] = k[i + 4];
    }
    return rk;
  }

  static int _load32(Uint8List b, int o) =>
      ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]) & _mask;

  static void _store32(Uint8List b, int o, int v) {
    b[o] = (v >> 24) & 0xff;
    b[o + 1] = (v >> 16) & 0xff;
    b[o + 2] = (v >> 8) & 0xff;
    b[o + 3] = v & 0xff;
  }
}

/// 对称密码工具：AES / DES / 3DES / SM4 / ChaCha20 / XOR，模式 ECB / CBC。
class CipherTools {
  static const List<String> algorithms = <String>['AES', 'DES', '3DES', 'SM4', 'ChaCha20', 'XOR'];
  static const List<String> blockAlgorithms = <String>['AES', 'DES', '3DES', 'SM4'];
  static const List<String> modes = <String>['ECB', 'CBC'];
  static const List<String> paddings = <String>['PKCS7', 'Zero', 'None'];

  static bool isStream(String algorithm) => algorithm == 'ChaCha20' || algorithm == 'XOR';

  static int blockSizeOf(String algorithm) =>
      (algorithm == 'DES' || algorithm == '3DES') ? 8 : 16;

  static List<int> keyLengthsOf(String algorithm) {
    switch (algorithm) {
      case 'AES':
        return const <int>[128, 192, 256];
      case '3DES':
        return const <int>[128, 192];
      case 'ChaCha20':
        return const <int>[128, 256];
      default:
        return const <int>[];
    }
  }

  static int defaultKeyLength(String algorithm) {
    switch (algorithm) {
      case 'AES':
        return 256;
      case '3DES':
        return 192;
      case 'ChaCha20':
        return 256;
      default:
        return 0;
    }
  }

  /// 解析密钥/IV 字符串：支持 `base64:` 前缀，否则按 UTF-8 文本。
  static Uint8List decodeKeyBytes(String value) {
    if (value.startsWith('base64:')) {
      try {
        return Uint8List.fromList(base64.decode(value.substring(7)));
      } catch (_) {
        return Uint8List(0);
      }
    }
    return Uint8List.fromList(utf8.encode(value));
  }

  static Uint8List _fit(Uint8List src, int size) {
    final out = Uint8List(size);
    final n = src.length < size ? src.length : size;
    out.setRange(0, n, src);
    return out;
  }

  static Uint8List _keyBytes(String algorithm, String key, int keyLength) {
    switch (algorithm) {
      case 'AES':
        return _fit(decodeKeyBytes(key), keyLength ~/ 8);
      case 'DES':
        {
          final k8 = _fit(decodeKeyBytes(key), 8);
          final out = Uint8List(24);
          out.setRange(0, 8, k8);
          out.setRange(8, 16, k8);
          out.setRange(16, 24, k8);
          return out;
        }
      case '3DES':
        return _fit(decodeKeyBytes(key), (keyLength == 128 ? 16 : 24));
      case 'SM4':
        return _fit(decodeKeyBytes(key), 16);
      default:
        return decodeKeyBytes(key);
    }
  }

  static BlockCipher _newEngine(String algorithm) {
    switch (algorithm) {
      case 'AES':
        return AESEngine();
      case 'DES':
      case '3DES':
        return DESedeEngine();
      case 'SM4':
        return Sm4Engine();
      default:
        throw ArgumentError('Unsupported algorithm: $algorithm');
    }
  }

  /// 对称加解密统一入口。[input] 为原始字节，返回原始结果字节。
  static Uint8List process(
    Uint8List input, {
    required String algorithm,
    required bool encrypt,
    required String key,
    String mode = 'ECB',
    String padding = 'PKCS7',
    String? iv,
    int keyLength = 256,
  }) {
    if (algorithm == 'XOR') {
      return _xor(input, decodeKeyBytes(key));
    }
    if (algorithm == 'ChaCha20') {
      return _chacha20(input, key, iv, keyLength);
    }

    final bs = blockSizeOf(algorithm);
    final keyBytes = _keyBytes(algorithm, key, keyLength);
    final engine = _newEngine(algorithm);
    final ivBytes = _fit(decodeKeyBytes(iv ?? ''), bs);

    final BlockCipher cipher = mode == 'CBC' ? CBCBlockCipher(engine) : ECBBlockCipher(engine);

    if (padding == 'PKCS7') {
      final padded = PaddedBlockCipherImpl(PKCS7Padding(), cipher);
      final CipherParameters params = mode == 'CBC'
          ? PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
              ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), ivBytes), null)
          : PaddedBlockCipherParameters<KeyParameter, Null>(KeyParameter(keyBytes), null);
      padded.init(encrypt, params);
      return padded.process(input);
    }

    final CipherParameters params = mode == 'CBC'
        ? ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), ivBytes)
        : KeyParameter(keyBytes);
    cipher.init(encrypt, params);

    var data = input;
    if (encrypt) {
      final rem = data.length % bs;
      if (rem != 0) {
        final tmp = Uint8List(data.length + (bs - rem));
        tmp.setRange(0, data.length, data);
        data = tmp;
      }
    } else if (data.length % bs != 0) {
      throw ArgumentError('Ciphertext length must be a multiple of the block size ($bs)');
    }

    final out = Uint8List(data.length);
    var offset = 0;
    while (offset < data.length) {
      final processed = cipher.process(data.sublist(offset, offset + bs));
      out.setRange(offset, offset + bs, processed);
      offset += bs;
    }

    if (!encrypt && padding == 'Zero') {
      var end = out.length;
      while (end > 0 && out[end - 1] == 0) {
        end--;
      }
      return out.sublist(0, end);
    }
    return out;
  }

  static Uint8List _chacha20(Uint8List input, String key, String? iv, int keyLength) {
    final keyBytes = _fit(decodeKeyBytes(key), keyLength == 128 ? 16 : 32);
    final nonce = _fit(decodeKeyBytes(iv ?? ''), 8);
    final cipher = ChaCha20Engine();
    cipher.init(true, ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), nonce));
    final out = Uint8List(input.length);
    cipher.processBytes(input, 0, input.length, out, 0);
    return out;
  }

  static Uint8List _xor(Uint8List input, Uint8List key) {
    if (key.isEmpty) {
      throw ArgumentError('XOR key must not be empty');
    }
    final out = Uint8List(input.length);
    for (var i = 0; i < input.length; i++) {
      out[i] = input[i] ^ key[i % key.length];
    }
    return out;
  }
}

/// 摘要 / 消息认证工具：MD5 / SHA-1 / SHA-224/256/384/512 / SM3 + HMAC。
class HashTools {
  static const List<String> algorithms = <String>[
    'MD5',
    'SHA-1',
    'SHA-224',
    'SHA-256',
    'SHA-384',
    'SHA-512',
    'SM3',
  ];

  static Uint8List digest(String algorithm, Uint8List data) {
    switch (algorithm) {
      case 'MD5':
        return Uint8List.fromList(crypto.md5.convert(data).bytes);
      case 'SHA-1':
        return Uint8List.fromList(crypto.sha1.convert(data).bytes);
      case 'SHA-224':
        return Uint8List.fromList(crypto.sha224.convert(data).bytes);
      case 'SHA-256':
        return Uint8List.fromList(crypto.sha256.convert(data).bytes);
      case 'SHA-384':
        return Uint8List.fromList(crypto.sha384.convert(data).bytes);
      case 'SHA-512':
        return Uint8List.fromList(crypto.sha512.convert(data).bytes);
      case 'SM3':
        return SM3Digest().process(data);
      default:
        throw ArgumentError('Unsupported hash: $algorithm');
    }
  }

  static crypto.Hash _cryptoHash(String algorithm) {
    switch (algorithm) {
      case 'MD5':
        return crypto.md5;
      case 'SHA-1':
        return crypto.sha1;
      case 'SHA-224':
        return crypto.sha224;
      case 'SHA-256':
        return crypto.sha256;
      case 'SHA-384':
        return crypto.sha384;
      case 'SHA-512':
        return crypto.sha512;
      default:
        return crypto.sha256;
    }
  }

  static Uint8List hmac(String algorithm, Uint8List key, Uint8List data) {
    final mac = crypto.Hmac(_cryptoHash(algorithm), key);
    return Uint8List.fromList(mac.convert(data).bytes);
  }

  static String hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// 摘要算法对应的 pointycastle Digest（供 RSA 签名复用）。
  static Digest pcDigest(String algorithm) {
    switch (algorithm) {
      case 'MD5':
        return MD5Digest();
      case 'SHA-1':
        return SHA1Digest();
      case 'SHA-224':
        return SHA224Digest();
      case 'SHA-256':
        return SHA256Digest();
      case 'SHA-384':
        return SHA384Digest();
      case 'SHA-512':
        return SHA512Digest();
      default:
        return SHA256Digest();
    }
  }

  static String digestOidHex(String algorithm) {
    switch (algorithm) {
      case 'MD5':
        return '06082a864886f70d0205';
      case 'SHA-1':
        return '06052b0e03021a';
      case 'SHA-224':
        return '0609608648016503040204';
      case 'SHA-256':
        return '0609608648016503040201';
      case 'SHA-384':
        return '0609608648016503040202';
      case 'SHA-512':
        return '0609608648016503040203';
      default:
        return '0609608648016503040201';
    }
  }
}

/// RSA 工具：加解密（PKCS#1 v1.5 / OAEP）、签名验签（PKCS#1 v1.5）、密钥生成。
class RsaTools {
  static const List<String> signAlgorithms = <String>[
    'MD5',
    'SHA-1',
    'SHA-224',
    'SHA-256',
    'SHA-384',
    'SHA-512',
  ];

  static Uint8List encrypt(Uint8List data, String publicKeyPem, {bool oaep = false}) {
    final key = CryptoUtils.rsaPublicKeyFromPem(publicKeyPem);
    final AsymmetricBlockCipher cipher =
        oaep ? OAEPEncoding(RSAEngine()) : PKCS1Encoding(RSAEngine());
    cipher.init(true, PublicKeyParameter<RSAPublicKey>(key));
    return cipher.process(data);
  }

  static Uint8List decrypt(Uint8List data, String privateKeyPem, {bool oaep = false}) {
    final key = CryptoUtils.rsaPrivateKeyFromPem(privateKeyPem);
    final AsymmetricBlockCipher cipher =
        oaep ? OAEPEncoding(RSAEngine()) : PKCS1Encoding(RSAEngine());
    cipher.init(false, PrivateKeyParameter<RSAPrivateKey>(key));
    return cipher.process(data);
  }

  static Uint8List sign(Uint8List data, String privateKeyPem, String algorithm) {
    final key = CryptoUtils.rsaPrivateKeyFromPem(privateKeyPem);
    final signer = RSASigner(HashTools.pcDigest(algorithm), HashTools.digestOidHex(algorithm));
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(key));
    return signer.generateSignature(data).bytes;
  }

  static bool verify(
      Uint8List data, Uint8List signature, String publicKeyPem, String algorithm) {
    final key = CryptoUtils.rsaPublicKeyFromPem(publicKeyPem);
    final signer = RSASigner(HashTools.pcDigest(algorithm), HashTools.digestOidHex(algorithm));
    signer.init(false, PublicKeyParameter<RSAPublicKey>(key));
    return signer.verifySignature(data, RSASignature(signature));
  }

  /// 生成密钥对，返回 [publicPem, privatePem]。
  static List<String> generateKeyPair({int keySize = 2048}) {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: keySize);
    final publicKey = pair.publicKey as RSAPublicKey;
    final privateKey = pair.privateKey as RSAPrivateKey;
    return <String>[
      CryptoUtils.encodeRSAPublicKeyToPem(publicKey),
      CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
    ];
  }
}
