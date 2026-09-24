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
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 计算与编解码引擎。
///
/// 参考 calculate-mcp（MIT）的能力范围用 Dart 重新实现，供两处共用：
/// 1. 工具箱页的各类计算器 UI；
/// 2. MCP 的 `calculator` 工具（让 AI 在分析抓包时能直接算补码 / CRC / 字节序）。
///
/// 全部运算都是**纯函数**：同样的入参必然得到同样的结果，不读写任何外部状态。
class CalcEngine {
  CalcEngine._();

  /// 数制与二进制类运算
  static const List<String> binaryOps = [
    'int_convert',
    'bitwise',
    'endian_swap',
    'ieee754',
    'crc',
    'hash',
    'mod_op',
    'codec',
  ];

  /// 基础算术
  static const List<String> arithmeticOps = [
    'add',
    'subtract',
    'multiply',
    'division',
    'modulo',
    'sum',
    'floor',
    'ceiling',
    'round',
  ];

  /// 统计
  static const List<String> statisticsOps = ['mean', 'median', 'mode', 'min', 'max'];

  /// 三角函数与角度换算
  static const List<String> trigonometryOps = [
    'sin',
    'cos',
    'tan',
    'arcsin',
    'arccos',
    'arctan',
    'degrees_to_radians',
    'radians_to_degrees',
  ];

  /// 全部支持的运算名
  static List<String> get operations => [
        ...binaryOps,
        ...arithmeticOps,
        ...statisticsOps,
        ...trigonometryOps,
      ];

  /// 统一入口。任何失败都以 `{'error': ...}` 返回，不抛异常。
  static Map<String, dynamic> run(String op, Map<String, dynamic> args) {
    final name = op.trim().toLowerCase();
    try {
      switch (name) {
        case 'int_convert':
          return _intConvert(args);
        case 'bitwise':
          return _bitwise(args);
        case 'endian_swap':
          return _endianSwap(args);
        case 'ieee754':
          return _ieee754(args);
        case 'crc':
          return _crc(args);
        case 'hash':
          return _hash(args);
        case 'mod_op':
          return _modOp(args);
        case 'codec':
          return _codec(args);
        case 'add':
        case 'subtract':
        case 'multiply':
        case 'division':
        case 'modulo':
        case 'floor':
        case 'ceiling':
        case 'round':
        case 'sum':
          return _arithmetic(name, args);
        case 'mean':
        case 'median':
        case 'mode':
        case 'min':
        case 'max':
          return _statistics(name, args);
        case 'sin':
        case 'cos':
        case 'tan':
        case 'arcsin':
        case 'arccos':
        case 'arctan':
        case 'degrees_to_radians':
        case 'radians_to_degrees':
          return _trigonometry(name, args);
        default:
          return {'error': 'Unknown operation: $op', 'supported': operations};
      }
    } catch (e) {
      return {'error': '$name failed: $e'};
    }
  }

  // ================= 数值解析与位宽工具 =================

  /// 解析十进制 / 0x / 0b / 0o 字面量（允许负号与下划线分隔）。
  static BigInt parseBigInt(Object? value) {
    if (value is int) return BigInt.from(value);
    if (value is double) {
      if (value == value.roundToDouble()) return BigInt.from(value);
      throw FormatException('not an integer: $value');
    }
    var text = (value ?? '').toString().trim().replaceAll('_', '').replaceAll(' ', '');
    if (text.isEmpty) throw const FormatException('empty value');
    var negative = false;
    if (text.startsWith('-')) {
      negative = true;
      text = text.substring(1);
    } else if (text.startsWith('+')) {
      text = text.substring(1);
    }
    BigInt result;
    final lower = text.toLowerCase();
    if (lower.startsWith('0x')) {
      result = BigInt.parse(text.substring(2), radix: 16);
    } else if (lower.startsWith('0b')) {
      result = BigInt.parse(text.substring(2), radix: 2);
    } else if (lower.startsWith('0o')) {
      result = BigInt.parse(text.substring(2), radix: 8);
    } else {
      result = BigInt.parse(text);
    }
    return negative ? -result : result;
  }

  /// 按位宽取无符号补码。
  static BigInt maskTo(BigInt value, int width) {
    final mask = (BigInt.one << width) - BigInt.one;
    return value & mask;
  }

  /// 把无符号补码解释为有符号值。
  static BigInt toSigned(BigInt masked, int width) {
    final signBit = BigInt.one << (width - 1);
    if ((masked & signBit) != BigInt.zero) {
      return masked - (BigInt.one << width);
    }
    return masked;
  }

  static String _hex(BigInt value, int width) {
    final digits = (width / 4).ceil();
    final text = value.toRadixString(16).toUpperCase().padLeft(digits, '0');
    return '0x$text';
  }

  /// 宽松取整：接受 int / double / 十进制或 0x、0b、0o 字符串。
  ///
  /// 两个调用方传进来的形态不同——工具箱 UI 传的是输入框文本（String），
  /// MCP 传的是 JSON 数字或字符串。曾因此踩坑：`args['b'] as num?` 在遇到
  /// 字符串时**直接抛 TypeError**（`as` 失败是抛错，不是返回 null），
  /// 表现为「位运算一按计算就报 type 'String' is not a subtype of type 'num?'」。
  /// 这里统一收口，不再对入参做强制类型转换。
  static int? _intOf(Object? value, {int? fallback}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) {
      if (value == value.roundToDouble()) return value.toInt();
      return fallback;
    }
    final text = value.toString().trim();
    if (text.isEmpty) return fallback;
    try {
      return parseBigInt(text).toInt();
    } on FormatException {
      return fallback;
    }
  }

  /// 解析位移量。越界（负数或超过 4096）返回 null，由调用方给出明确报错。
  static int? _shiftOf(Map<String, dynamic> args) {
    final shift = _intOf(args['shift'] ?? args['b'], fallback: 0) ?? 0;
    if (shift < 0 || shift > 4096) return null;
    return shift;
  }

  static int _widthOf(Map<String, dynamic> args, {int fallback = 64}) {
    final width = _intOf(args['width'], fallback: fallback) ?? fallback;
    if (width <= 0 || width > 4096) throw FormatException('width out of range: $width');
    return width;
  }

  static List<int> _bytesFrom(Object? value, String? format) {
    if (format == 'utf8' || format == 'text' || format == 'string') {
      return utf8.encode((value ?? '').toString());
    }
    if (format == 'base64') {
      return base64.decode((value ?? '').toString().trim());
    }
    // 默认按 hex 解析
    var text = (value ?? '').toString().trim().replaceAll('_', '').replaceAll(' ', '');
    text = text.replaceAll(RegExp(r'^0x', caseSensitive: false), '');
    if (text.isEmpty) return const [];
    if (text.length.isOdd) text = '0$text';
    final out = <int>[];
    for (var i = 0; i < text.length; i += 2) {
      out.add(int.parse(text.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  // ================= 1. 数制与补码转换 =================

  static Map<String, dynamic> _intConvert(Map<String, dynamic> args) {
    final raw = (args['value'] ?? '').toString().trim();
    if (raw.isEmpty) return {'error': 'value is required'};
    final width = _widthOf(args);
    final big = parseBigInt(raw);
    final masked = maskTo(big, width);
    final signed = toSigned(masked, width);
    final binText = masked.toRadixString(2).padLeft(width, '0');
    final byteLength = (width / 8).ceil();
    final leBytes = _bigIntToBytes(masked, byteLength).reversed.toList();
    final beBytes = _bigIntToBytes(masked, byteLength);
    return {
      'input': raw,
      'width': width,
      'hex': _hex(masked, width),
      'decimal_unsigned': masked.toString(),
      'decimal_signed': signed.toString(),
      'binary': binText,
      'binary_grouped': _groupBits(binText),
      'octal': masked.toRadixString(8),
      'big_endian_hex': beBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      'little_endian_hex': leBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      'ascii': _printableAscii(beBytes),
    };
  }

  static List<int> _bigIntToBytes(BigInt value, int length) {
    final out = List<int>.filled(length, 0);
    var v = value;
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (v & BigInt.from(0xFF)).toInt();
      v = v >> 8;
    }
    return out;
  }

  static String _groupBits(String bits) {
    final buffer = StringBuffer();
    for (var i = 0; i < bits.length; i++) {
      if (i > 0 && (bits.length - i) % 4 == 0) buffer.write(' ');
      buffer.write(bits[i]);
    }
    return buffer.toString();
  }

  static String _printableAscii(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b >= 0x20 && b < 0x7F ? String.fromCharCode(b) : '.');
    }
    return buffer.toString();
  }

  // ================= 2. 位运算 =================

  static Map<String, dynamic> _bitwise(Map<String, dynamic> args) {
    final operation = (args['operation'] ?? args['op'] ?? 'and').toString().toLowerCase();
    final width = _widthOf(args, fallback: 32);
    final a = maskTo(parseBigInt(args['a']), width);
    final b = (args.containsKey('b') && args['b'] != null)
        ? maskTo(parseBigInt(args['b']), width)
        : BigInt.zero;
    // 位移量只在位移类运算里解析，见下面的 _shiftOf —— 对 and/or/xor 来说
    // 第二个操作数是参与运算的数，不是位移量，无条件解析会误判。

    BigInt result;
    switch (operation) {
      case 'and':
        result = a & b;
        break;
      case 'or':
        result = a | b;
        break;
      case 'xor':
        result = a ^ b;
        break;
      case 'not':
        result = maskTo(~a, width);
        break;
      case 'shl': {
        final s = _shiftOf(args);
        if (s == null) return {'error': 'shift out of range (0-4096)'};
        result = maskTo(a << s, width);
        break;
      }
      case 'shr': {
        // 逻辑右移：先按无符号看待
        final s = _shiftOf(args);
        if (s == null) return {'error': 'shift out of range (0-4096)'};
        result = a >> s;
        break;
      }
      case 'sar': {
        // 算术右移：先按有符号看待
        final s = _shiftOf(args);
        if (s == null) return {'error': 'shift out of range (0-4096)'};
        result = maskTo(toSigned(a, width) >> s, width);
        break;
      }
      case 'rol': {
        final s = _shiftOf(args);
        if (s == null) return {'error': 'shift out of range (0-4096)'};
        result = _rotateLeft(a, s, width);
        break;
      }
      case 'ror': {
        final s = _shiftOf(args);
        if (s == null) return {'error': 'shift out of range (0-4096)'};
        result = _rotateRight(a, s, width);
        break;
      }
      default:
        return {'error': 'Unknown bitwise operation: $operation'};
    }

    result = maskTo(result, width);
    return {
      'operation': operation,
      'width': width,
      'a': _hex(a, width),
      'b': _hex(b, width),
      'result': _hex(result, width),
      'result_decimal': result.toString(),
      'result_decimal_signed': toSigned(result, width).toString(),
      'result_binary': result.toRadixString(2).padLeft(width, '0'),
    };
  }

  static BigInt _rotateLeft(BigInt value, int shift, int width) {
    final s = shift % width;
    if (s == 0) return maskTo(value, width);
    return maskTo((value << s) | (value >> (width - s)), width);
  }

  static BigInt _rotateRight(BigInt value, int shift, int width) {
    final s = shift % width;
    if (s == 0) return maskTo(value, width);
    return maskTo((value >> s) | (value << (width - s)), width);
  }

  // ================= 3. 字节序转换 =================

  static Map<String, dynamic> _endianSwap(Map<String, dynamic> args) {
    final input = args['value'] ?? args['hex'];
    if (input == null) return {'error': 'value (hex string) is required'};
    final declared = _intOf(args['widthBytes']);
    var bytes = _bytesFrom(input, 'hex');
    if (bytes.isEmpty) return {'error': 'value is empty'};
    if (declared != null && declared > 0) {
      if (bytes.length > declared) {
        bytes = bytes.sublist(0, declared);
      } else {
        // 补零到声明宽度（大端语义：高位在前）
        bytes = [...List<int>.filled(declared - bytes.length, 0), ...bytes];
      }
    }
    final reversed = bytes.reversed.toList();
    String hexOf(List<int> list) => list.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return {
      'widthBytes': bytes.length,
      'input_be_hex': hexOf(bytes),
      'input_le_hex': hexOf(reversed),
      'swapped_hex': hexOf(reversed),
      'as_big_endian_decimal': BigInt.parse(hexOf(bytes).isEmpty ? '0' : hexOf(bytes), radix: 16).toString(),
      'as_little_endian_decimal': BigInt.parse(hexOf(reversed).isEmpty ? '0' : hexOf(reversed), radix: 16).toString(),
    };
  }

  // ================= 4. IEEE 754 =================

  static Map<String, dynamic> _ieee754(Map<String, dynamic> args) {
    final precision = (args['precision'] ?? 'float32').toString().toLowerCase();
    final isSingle = precision == 'float32' || precision == 'single' || precision == '32';
    final inputValue = args['value'] ?? args['input'];
    if (inputValue == null) return {'error': 'value is required'};
    final text = inputValue.toString().trim();

    final bd = ByteData(8);
    double numericValue;
    BigInt rawBits;
    if (text.toLowerCase().startsWith('0x') ||
        (text.isNotEmpty && RegExp(r'^[0-9a-fA-F]+$').hasMatch(text) && text.length >= 8 && !text.contains('.'))) {
      rawBits = parseBigInt(text);
      final bits = isSingle ? 32 : 64;
      rawBits = maskTo(rawBits, bits);
      if (isSingle) {
        bd.setUint32(0, rawBits.toInt(), Endian.big);
        numericValue = bd.getFloat32(0, Endian.big);
      } else {
        bd.setUint64(0, rawBits.toInt(), Endian.big);
        numericValue = bd.getFloat64(0, Endian.big);
      }
    } else {
      numericValue = double.parse(text);
      if (isSingle) {
        bd.setFloat32(0, numericValue, Endian.big);
        rawBits = BigInt.from(bd.getUint32(0, Endian.big));
      } else {
        bd.setFloat64(0, numericValue, Endian.big);
        rawBits = BigInt.from(bd.getUint64(0, Endian.big));
      }
    }

    final bits = isSingle ? 32 : 64;
    final expBits = isSingle ? 8 : 11;
    final mantBits = isSingle ? 23 : 52;
    final bias = isSingle ? 127 : 1023;

    final sign = maskTo(rawBits >> (bits - 1), 1).toInt();
    final rawExp = maskTo(rawBits >> mantBits, expBits).toInt();
    final mantissa = maskTo(rawBits, mantBits);

    String type;
    if (rawExp == 0 && mantissa == BigInt.zero) {
      type = 'zero';
    } else if (rawExp == 0) {
      type = 'subnormal';
    } else if (rawExp == (1 << expBits) - 1) {
      type = mantissa == BigInt.zero ? 'infinity' : 'nan';
    } else {
      type = 'normal';
    }

    return {
      'precision': isSingle ? 'float32' : 'float64',
      'value': numericValue.isNaN ? 'NaN' : numericValue,
      'sign': sign == 0 ? '+' : '-',
      'raw_bits_hex': _hex(rawBits, bits),
      'binary': rawBits.toRadixString(2).padLeft(bits, '0'),
      'raw_exponent_decimal': rawExp,
      'biased_exponent': rawExp - bias,
      'mantissa_hex': '0x${mantissa.toRadixString(16).toUpperCase().padLeft((mantBits / 4).ceil(), '0')}',
      'mantissa_fraction': mantissa.toDouble() / (1 << mantBits).toDouble(),
      'type': type,
    };
  }

  // ================= 5. CRC 校验 =================

  static const Map<String, List<int>> _crcParams = {
    // name: [poly, init, reflect, xorOut, outBits]
    'crc32': [0xEDB88320, 0xFFFFFFFF, 1, 0xFFFFFFFF, 32],
    'crc16_ccitt': [0x1021, 0xFFFF, 0, 0, 16],
    'crc16_modbus': [0xA001, 0xFFFF, 1, 0, 16],
    'crc16_xmodem': [0x1021, 0x0000, 0, 0, 16],
    'crc16_ibm': [0xA001, 0x0000, 1, 0, 16],
  };

  static Map<String, dynamic> _crc(Map<String, dynamic> args) {
    final algorithm = (args['algorithm'] ?? 'crc32').toString().toLowerCase();
    final params = _crcParams[algorithm];
    if (params == null) {
      return {'error': 'Unknown CRC algorithm: $algorithm', 'supported': _crcParams.keys.toList()};
    }
    final data = _bytesFrom(args['data'] ?? args['input'], (args['inputFormat'] ?? 'hex').toString());
    final value = _crcCompute(data, params[0], params[1], params[2] == 1, params[3], params[4]);
    final digits = params[4] ~/ 4;
    return {
      'algorithm': algorithm,
      'bytes': data.length,
      'input_hex': data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      'crc': '0x${value.toRadixString(16).toUpperCase().padLeft(digits, '0')}',
      'crc_decimal': value,
    };
  }

  static int _crcCompute(
      List<int> data, int poly, int init, bool reflect, int xorOut, int outBits) {
    final mask = outBits == 32 ? 0xFFFFFFFF : 0xFFFF;
    final topBit = outBits == 32 ? 0x80000000 : 0x8000;
    var crc = init & mask;
    for (final byte in data) {
      if (reflect) {
        crc ^= byte;
        for (var i = 0; i < 8; i++) {
          crc = (crc & 1) != 0 ? (crc >> 1) ^ poly : crc >> 1;
        }
      } else {
        crc ^= (byte << (outBits - 8));
        for (var i = 0; i < 8; i++) {
          crc = (crc & topBit) != 0 ? ((crc << 1) ^ poly) : (crc << 1);
        }
      }
      crc &= mask;
    }
    return (crc ^ xorOut) & mask;
  }

  // ================= 6. 哈希 =================

  static Map<String, dynamic> _hash(Map<String, dynamic> args) {
    final algorithm = (args['algorithm'] ?? 'sha256').toString().toLowerCase();
    final data = _bytesFrom(args['data'] ?? args['input'], (args['inputFormat'] ?? 'utf8').toString());
    late Digest digest;
    switch (algorithm) {
      case 'md5':
        digest = md5.convert(data);
        break;
      case 'sha1':
        digest = sha1.convert(data);
        break;
      case 'sha256':
        digest = sha256.convert(data);
        break;
      case 'sha512':
        digest = sha512.convert(data);
        break;
      default:
        return {
          'error': 'Unknown hash algorithm: $algorithm',
          'supported': ['md5', 'sha1', 'sha256', 'sha512'],
        };
    }
    return {
      'algorithm': algorithm,
      'bytes': data.length,
      'hex': digest.toString(),
      'base64': base64.encode(digest.bytes),
    };
  }

  // ================= 7. 数论（大数模运算） =================

  static Map<String, dynamic> _modOp(Map<String, dynamic> args) {
    final action = (args['action'] ?? args['op'] ?? 'mod_pow').toString().toLowerCase();
    switch (action) {
      case 'mod_pow':
        final base = parseBigInt(args['base'] ?? args['a']);
        final exp = parseBigInt(args['exponent'] ?? args['b']);
        final modulus = parseBigInt(args['modulus'] ?? args['m']);
        if (modulus == BigInt.zero) return {'error': 'modulus must not be zero'};
        return {
          'action': 'mod_pow',
          'result': base.modPow(exp, modulus).toString(),
        };
      case 'mod_inverse':
        final a = parseBigInt(args['a'] ?? args['value']);
        final modulus = parseBigInt(args['modulus'] ?? args['m']);
        final inv = _modInverse(a, modulus);
        if (inv == null) {
          return {'error': 'no modular inverse exists (a and modulus are not coprime)'};
        }
        return {'action': 'mod_inverse', 'result': inv.toString()};
      case 'gcd':
        final a = parseBigInt(args['a'] ?? args['value']);
        final b = parseBigInt(args['b'] ?? args['value2']);
        return {'action': 'gcd', 'result': a.gcd(b).toString()};
      case 'lcm':
        final a = parseBigInt(args['a'] ?? args['value']);
        final b = parseBigInt(args['b'] ?? args['value2']);
        if (a == BigInt.zero || b == BigInt.zero) return {'action': 'lcm', 'result': '0'};
        final gcdValue = a.gcd(b);
        return {'action': 'lcm', 'result': ((a * b).abs() ~/ gcdValue).toString()};
      default:
        return {'error': 'Unknown mod action: $action', 'supported': ['mod_pow', 'mod_inverse', 'gcd', 'lcm']};
    }
  }

  /// 扩展欧几里得求模逆元
  static BigInt? _modInverse(BigInt a, BigInt modulus) {
    if (modulus == BigInt.zero) return null;
    var t = BigInt.zero;
    var newT = BigInt.one;
    var r = modulus;
    var newR = a % modulus;
    while (newR != BigInt.zero) {
      final quotient = r ~/ newR;
      final tmpT = t - quotient * newT;
      t = newT;
      newT = tmpT;
      final tmpR = r - quotient * newR;
      r = newR;
      newR = tmpR;
    }
    if (r > BigInt.one) return null; // 不互质
    if (t < BigInt.zero) t += modulus;
    return t;
  }

  // ================= 8. 数据编解码 =================

  static Map<String, dynamic> _codec(Map<String, dynamic> args) {
    final action = (args['action'] ?? 'to_base64').toString().toLowerCase();
    final raw = (args['input'] ?? args['value'] ?? '').toString();
    switch (action) {
      case 'to_base64':
        return {'action': action, 'result': base64.encode(utf8.encode(raw))};
      case 'from_base64':
        return {'action': action, 'result': utf8.decode(base64.decode(raw.trim()), allowMalformed: true)};
      case 'to_base64_url':
        return {
          'action': action,
          'result': base64Url.encode(utf8.encode(raw)).replaceAll('=', ''),
        };
      case 'from_base64_url':
        var text = raw.trim().replaceAll('-', '+').replaceAll('_', '/');
        while (text.length % 4 != 0) {
          text += '=';
        }
        return {'action': action, 'result': utf8.decode(base64.decode(text), allowMalformed: true)};
      case 'to_hex':
        return {
          'action': action,
          'result': utf8.encode(raw).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        };
      case 'from_hex':
        return {
          'action': action,
          'result': utf8.decode(_bytesFrom(raw, 'hex'), allowMalformed: true),
        };
      case 'to_url':
        return {'action': action, 'result': Uri.encodeComponent(raw)};
      case 'from_url':
        return {'action': action, 'result': Uri.decodeComponent(raw)};
      default:
        return {
          'error': 'Unknown codec action: $action',
          'supported': [
            'to_base64',
            'from_base64',
            'to_base64_url',
            'from_base64_url',
            'to_hex',
            'from_hex',
            'to_url',
            'from_url',
          ],
        };
    }
  }

  // ================= 9. 基础算术 =================

  /// 两个操作数都是整数时用 BigInt 精确计算，否则退回 double。
  static Map<String, dynamic> _arithmetic(String op, Map<String, dynamic> args) {
    if (op == 'sum') {
      final list = _numberList(args['values'] ?? args['numbers']);
      if (list.isEmpty) return {'error': 'values must be a non-empty array'};
      if (list.every((e) => e is BigInt)) {
        var total = BigInt.zero;
        for (final e in list) {
          total += e as BigInt;
        }
        return {'operation': op, 'result': total.toString(), 'exact': true};
      }
      var total = 0.0;
      for (final e in list) {
        total += _toDouble(e);
      }
      return {'operation': op, 'result': total, 'exact': false};
    }

    if (op == 'floor' || op == 'ceiling' || op == 'round') {
      final value = _toDouble(args['value'] ?? args['a']);
      final result = op == 'floor' ? value.floor() : (op == 'ceiling' ? value.ceil() : value.round());
      return {'operation': op, 'input': value, 'result': result};
    }

    final a = _parseNumber(args['a'] ?? args['value']);
    final b = _parseNumber(args['b'] ?? args['value2']);
    if (a is BigInt && b is BigInt) {
      switch (op) {
        case 'add':
          return {'operation': op, 'result': (a + b).toString(), 'exact': true};
        case 'subtract':
          return {'operation': op, 'result': (a - b).toString(), 'exact': true};
        case 'multiply':
          return {'operation': op, 'result': (a * b).toString(), 'exact': true};
        case 'division':
          if (b == BigInt.zero) return {'error': 'division by zero'};
          final quotient = a ~/ b;
          final remainder = a % b;
          return {
            'operation': op,
            'result': quotient.toString(),
            'remainder': remainder.toString(),
            'exact': remainder == BigInt.zero,
          };
        case 'modulo':
          if (b == BigInt.zero) return {'error': 'modulo by zero'};
          return {'operation': op, 'result': (a % b).toString(), 'exact': true};
      }
    }

    final da = _toDouble(a);
    final db = _toDouble(b);
    switch (op) {
      case 'add':
        return {'operation': op, 'result': da + db, 'exact': false};
      case 'subtract':
        return {'operation': op, 'result': da - db, 'exact': false};
      case 'multiply':
        return {'operation': op, 'result': da * db, 'exact': false};
      case 'division':
        if (db == 0) return {'error': 'division by zero'};
        return {'operation': op, 'result': da / db, 'exact': false};
      case 'modulo':
        if (db == 0) return {'error': 'modulo by zero'};
        return {'operation': op, 'result': da % db, 'exact': false};
    }
    return {'error': 'Unsupported arithmetic operation: $op'};
  }

  static Object _parseNumber(Object? value) {
    if (value is int) return BigInt.from(value);
    if (value is BigInt) return value;
    if (value is double) return value;
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) throw const FormatException('number is required');
    if (text.contains('.') || text.contains('e') || text.contains('E')) {
      return double.parse(text);
    }
    return parseBigInt(text);
  }

  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is BigInt) return value.toDouble();
    return double.parse((value ?? '').toString().trim());
  }

  static List<Object> _numberList(Object? value) {
    if (value is List) {
      return value.map(_parseNumber).toList();
    }
    if (value is String) {
      return value
          .split(RegExp(r'[,\s]+'))
          .where((e) => e.isNotEmpty)
          .map((e) => _parseNumber(e))
          .toList();
    }
    throw const FormatException('values must be an array or comma separated string');
  }

  // ================= 10. 统计 =================

  static Map<String, dynamic> _statistics(String op, Map<String, dynamic> args) {
    final list = _numberList(args['values'] ?? args['numbers']).map(_toDouble).toList();
    if (list.isEmpty) return {'error': 'values must be a non-empty array'};
    switch (op) {
      case 'mean':
        var total = 0.0;
        for (final v in list) {
          total += v;
        }
        return {'operation': op, 'count': list.length, 'result': total / list.length};
      case 'median':
        final sorted = [...list]..sort();
        final mid = sorted.length ~/ 2;
        final median = sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
        return {'operation': op, 'count': list.length, 'result': median};
      case 'mode':
        final counts = <double, int>{};
        for (final v in list) {
          counts[v] = (counts[v] ?? 0) + 1;
        }
        var best = counts.entries.first;
        for (final entry in counts.entries) {
          if (entry.value > best.value) best = entry;
        }
        return {
          'operation': op,
          'count': list.length,
          'result': best.key,
          'occurrences': best.value,
        };
      case 'min':
        return {'operation': op, 'count': list.length, 'result': list.reduce((a, b) => a < b ? a : b)};
      case 'max':
        return {'operation': op, 'count': list.length, 'result': list.reduce((a, b) => a > b ? a : b)};
    }
    return {'error': 'Unsupported statistics operation: $op'};
  }

  // ================= 11. 三角函数与角度换算 =================

  static Map<String, dynamic> _trigonometry(String op, Map<String, dynamic> args) {
    final value = _toDouble(args['value'] ?? args['a']);
    switch (op) {
      case 'sin':
        return {'operation': op, 'input': value, 'unit': 'radian', 'result': math.sin(value)};
      case 'cos':
        return {'operation': op, 'input': value, 'unit': 'radian', 'result': math.cos(value)};
      case 'tan':
        return {'operation': op, 'input': value, 'unit': 'radian', 'result': math.tan(value)};
      case 'arcsin':
        if (value < -1 || value > 1) return {'error': 'arcsin domain is [-1, 1]'};
        return {'operation': op, 'input': value, 'unit': 'radian', 'result': math.asin(value)};
      case 'arccos':
        if (value < -1 || value > 1) return {'error': 'arccos domain is [-1, 1]'};
        return {'operation': op, 'input': value, 'unit': 'radian', 'result': math.acos(value)};
      case 'arctan':
        return {'operation': op, 'input': value, 'unit': 'radian', 'result': math.atan(value)};
      case 'degrees_to_radians':
        return {'operation': op, 'input_degrees': value, 'result': value * math.pi / 180};
      case 'radians_to_degrees':
        return {'operation': op, 'input_radians': value, 'result': value * 180 / math.pi};
    }
    return {'error': 'Unsupported trigonometry operation: $op'};
  }
}
