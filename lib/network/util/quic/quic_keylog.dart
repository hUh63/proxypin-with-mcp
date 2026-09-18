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

import 'dart:convert';
import 'dart:typed_data';

import 'package:proxypin/network/util/logger.dart';

/// TLS 密钥日志（NSS key log / `SSLKEYLOGFILE`）的解析与保存（上游 #489）。
///
/// 被动旁路抓 QUIC 时，会话密钥由 ECDHE 协商、无法自行推导；唯一可行路径是让
/// **目标应用自己导出密钥日志**，再按其中的 `*_TRAFFIC_SECRET_0` 解密 1-RTT 包。
///
/// 文件格式（每行）：
/// ```
/// QUIC_SERVER_TRAFFIC_SECRET_0 <client_random_hex> <secret_hex>
/// CLIENT_TRAFFIC_SECRET_0 <client_random_hex> <secret_hex>
/// ```
/// 带 `QUIC_` 前缀的是 QUIC 连接用，不带前缀的是 TCP TLS 用；这里**按去掉前缀后的
/// 标签统一存放**，两种写法都能命中。
class QuicKeylogStore {
  QuicKeylogStore._();

  static final QuicKeylogStore instance = QuicKeylogStore._();

  /// client_random(hex, 小写) -> { 归一化标签 -> secret }
  final Map<String, Map<String, Uint8List>> _entries = {};

  /// 已导入的条目数（同一连接的多个标签各算一条）
  int get entryCount => _entries.values.fold(0, (sum, map) => sum + map.length);

  /// 涉及多少个连接（按 client_random 去重）
  int get connectionCount => _entries.length;

  bool get isEmpty => _entries.isEmpty;

  static String _normalizeLabel(String label) {
    var value = label.trim().toUpperCase();
    if (value.startsWith('QUIC_')) {
      value = value.substring('QUIC_'.length);
    }
    return value;
  }

  /// 解析密钥日志文本；返回本次新增的条目数
  int importText(String text) {
    var added = 0;
    for (final rawLine in const LineSplitter().convert(text)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 3) continue;

      final label = _normalizeLabel(parts[0]);
      final random = parts[1].toLowerCase();
      final secretHex = parts[2];
      final secret = _hexToBytes(secretHex);
      if (secret == null || random.isEmpty) continue;

      final bucket = _entries.putIfAbsent(random, () => {});
      if (bucket[label] == null) {
        bucket[label] = secret;
        added++;
      }
    }
    if (added > 0) {
      logger.i('QUIC 密钥日志已导入 $added 条，覆盖 $connectionCount 个连接');
    }
    return added;
  }

  /// 该 client_random 是否有可用于解密客户端发送方向（1-RTT）的密钥
  bool hasClientTrafficSecret(String clientRandomHex) =>
      _entries[clientRandomHex.toLowerCase()]?['CLIENT_TRAFFIC_SECRET_0'] != null;

  /// 取客户端方向的 1-RTT 流量密钥（客户端 → 服务端）
  Uint8List? clientTrafficSecret(String clientRandomHex) =>
      _entries[clientRandomHex.toLowerCase()]?['CLIENT_TRAFFIC_SECRET_0'];

  /// 取服务端方向的 1-RTT 流量密钥（服务端 → 客户端）
  Uint8List? serverTrafficSecret(String clientRandomHex) =>
      _entries[clientRandomHex.toLowerCase()]?['SERVER_TRAFFIC_SECRET_0'];

  /// 已导入的 client_random 列表（便于界面展示）
  List<String> get clientRandoms => _entries.keys.toList();

  void clear() {
    _entries.clear();
  }

  static Uint8List? _hexToBytes(String hex) {
    if (hex.isEmpty || hex.length.isOdd) return null;
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) return null;
      out[i] = byte;
    }
    return out;
  }
}
