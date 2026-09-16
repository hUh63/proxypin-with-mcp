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

/// 国际化域名（IDN）处理工具。
///
/// 背景（上游 #923）：URL 编码的主机名（如 `%E5%B0%8F%E5%BA%A6.%E4%B8%AD%E5%9B%BD`）
/// 含 `%` 字符，Dart 的 `InternetAddress.lookup` 会把 `%` 误判为 IPv6 链路本地地址的
/// scope id，抛出 `FormatException`，导致请求直接失败。
///
/// 修复策略：连接前对主机名做清洗——
/// 1. 若主机含 `%` 且不是合法 IPv6，先做百分号解码还原为原始域名；
/// 2. 若解码后含非 ASCII 字符（中文域名等），转换为 Punycode（RFC 3492）的 ASCII 形式
///    （`小度.中国` → `xn--*****.xn--fiqs8s`），保证系统 DNS 可以解析。
library;

/// 连接前清洗主机名（上游 #923）。
///
/// 1. 去掉 IPv6 的方括号（`[::1]` → `::1`）；
/// 2. 非 IPv6 且含 `%` 的主机做百分号解码（`%E5%B0%8F%E5%BA%A6…` → `小度…`）；
///    IPv6 一定含 `:`，其 `%` 是 scope id（如 `fe80::1%eth0`），不能解码；
/// 3. 含非 ASCII 字符时转 Punycode，保证系统 DNS 可以解析。
///
/// 所有 `Socket.connect` / `SecureSocket.connect` 之前都应经过本函数。
String sanitizeConnectHost(String host) {
  var result = host;
  if (result.startsWith('[') && result.endsWith(']')) {
    result = result.substring(1, result.length - 1);
  }
  if (result.contains('%') && !result.contains(':')) {
    try {
      result = Uri.decodeComponent(result);
    } catch (_) {
      // 解码失败时按原样处理，由后续 DNS 解析给出错误
    }
  }
  return idnToAscii(result);
}

/// 将主机名转换为 DNS 可解析的 ASCII 形式（IDNA/Punycode）。
/// 纯 ASCII 输入原样返回；解码失败时返回原始输入（由上层按域名解析失败处理）。
String idnToAscii(String host) {
  // 去掉 IPv6 方括号场景不在此处理，本函数只处理普通域名
  if (host.isEmpty || host.codeUnits.every((c) => c < 128)) {
    return host;
  }
  try {
    final labels = host.toLowerCase().split('.');
    final out = <String>[];
    for (final label in labels) {
      if (label.isEmpty) {
        out.add(label);
      } else if (label.codeUnits.every((c) => c < 128)) {
        out.add(label);
      } else {
        out.add('xn--${punycodeEncode(label)}');
      }
    }
    return out.join('.');
  } catch (_) {
    return host;
  }
}

/// RFC 3492 Punycode 编码（单标签）。
String punycodeEncode(String input) {
  const base = 36, tmin = 1, tmax = 26, skew = 38, damp = 700;
  const initialBias = 72, initialN = 128;
  final chars = input.runes.toList();

  final output = StringBuffer();
  final basic = chars.where((c) => c < 128).toList();
  for (final c in basic) {
    output.writeCharCode(c);
  }
  final basicLength = basic.length;
  if (basicLength > 0) {
    output.write('-');
  }

  var n = initialN;
  var delta = 0;
  var bias = initialBias;
  var handled = basicLength;

  while (handled < chars.length) {
    // 找到尚未处理的最小码点
    var m = 0x10FFFF + 1;
    for (final c in chars) {
      if (c >= n && c < m) m = c;
    }
    if (m > 0x10FFFF) break;
    delta += (m - n) * (handled + 1);
    n = m;
    for (final c in chars) {
      if (c < n) {
        delta++;
        continue;
      }
      if (c == n) {
        var q = delta;
        for (var k = base;; k += base) {
          final t = k <= bias
              ? tmin
              : (k >= bias + tmax ? tmax : k - bias);
          if (q < t) break;
          output.writeCharCode(_encodeDigit(t + (q - t) % (base - t)));
          q = (q - t) ~/ (base - t);
        }
        output.writeCharCode(_encodeDigit(q));
        bias = _adapt(delta, handled + 1, handled == basicLength);
        delta = 0;
        handled++;
      }
    }
    delta++;
    n++;
  }
  return output.toString();
}

int _adapt(int delta, int numPoints, bool firstTime) {
  const base = 36, tmin = 1, tmax = 26, skew = 38, damp = 700;
  delta = firstTime ? delta ~/ damp : delta ~/ 2;
  delta += delta ~/ numPoints;
  var k = 0;
  while (delta > ((base - tmin) * tmax) ~/ 2) {
    delta ~/= base - tmin;
    k += base;
  }
  return k + (((base - tmin + 1) * delta) ~/ (delta + skew));
}

int _encodeDigit(int d) {
  const base = 36, tmax = 26;
  if (d < tmax) return 0x61 + d; // a-z
  return 0x30 + (d - tmax); // 0-9，最多到 base-1=35
}
