/*
 * Copyright 2026 Hongen Wang All rights reserved.
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

// 网络诊断：Ping（TCP 握手延迟）/ DNS 查询 / 端口扫描 / HTTP 检测 / 局域网扫描。
//
// 能力对标「工具箱 1.0」里的 Net 模块。它那边是 Kotlin 直接跑 shell，
// 这里全部用 dart:io 做（跨平台、不需要 ping 二进制 —— Android 上根本没有）。
//
// 几个工程上的取舍：
//   · Ping 用 TCP connect 计时而不是 ICMP：ICMP 在 Android 上要 raw socket，
//     非 Root 不可用；TCP 握手延迟对「通不通 / 多久」这个判断已足够。
//   · 并发一律做成「固定窗口」而不是一次性发 N 个协程：手机上一次发几百个
//     socket 会把 fd 用光，也容易被对端当扫描打。
//   · 所有结果都带耗时，界面上能直接看出「最慢的是哪个」。

import 'dart:async';
import 'dart:io';

/// 一次 TCP 探测的结果。
class PingResult {
  final String host;
  final int port;
  final bool ok;
  final int ms;
  final String? error;

  const PingResult({
    required this.host,
    required this.port,
    required this.ok,
    required this.ms,
    this.error,
  });
}

/// 端口扫描的一行。
class PortResult {
  final int port;
  final bool open;
  final int ms;

  const PortResult(this.port, this.open, this.ms);
}

/// 局域网里发现的一台设备。
class LanHost {
  final String ip;
  final List<int> openPorts;
  final int ms;

  const LanHost(this.ip, this.openPorts, this.ms);
}

/// HTTP 检测结果。
class HttpProbeResult {
  final int? status;
  final int ms;
  final bool https;
  final Map<String, String> headers;
  final String? error;
  final int? bodyBytes;

  const HttpProbeResult({
    this.status,
    required this.ms,
    required this.https,
    this.headers = const {},
    this.error,
    this.bodyBytes,
  });

  bool get ok => (status ?? 0) > 0;
}

class NetDiagnostics {
  NetDiagnostics._();

  /// TCP 探活（当作 Ping 用）：连上就算通，耗时就是握手延迟。
  static Future<PingResult> tcpPing(String host, {int port = 443, Duration timeout = const Duration(seconds: 3)}) async {
    final started = DateTime.now();
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      final ms = DateTime.now().difference(started).inMilliseconds;
      return PingResult(host: host, port: port, ok: true, ms: ms);
    } catch (e) {
      final ms = DateTime.now().difference(started).inMilliseconds;
      return PingResult(host: host, port: port, ok: false, ms: ms, error: _shortError(e));
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  /// 多次 Ping（间隔 300ms），逐条回调，界面上能边跑边看。
  static Future<void> pingSeries(
    String host, {
    int port = 443,
    int count = 4,
    void Function(PingResult)? onResult,
    bool Function()? isCancelled,
  }) async {
    for (var i = 0; i < count; i++) {
      if (isCancelled?.call() ?? false) return;
      final r = await tcpPing(host, port: port);
      onResult?.call(r);
      if (i + 1 < count) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  /// DNS 查询（A + AAAA 一起查）。
  static Future<({List<String> addresses, int ms, String? error})> dnsLookup(
      String host, {Duration timeout = const Duration(seconds: 5)}) async {
    final started = DateTime.now();
    try {
      final list = await InternetAddress.lookup(host).timeout(timeout);
      final addrs = <String>[];
      for (final a in list) {
        final s = '${a.address} (${a.type.name})';
        if (!addrs.contains(s)) addrs.add(s);
      }
      return (addresses: addrs, ms: DateTime.now().difference(started).inMilliseconds, error: null);
    } catch (e) {
      return (
        addresses: const <String>[],
        ms: DateTime.now().difference(started).inMilliseconds,
        error: _shortError(e),
      );
    }
  }

  /// 反查 PTR（很多域名查不到，查不到就返回 null，别当失败）。
  static Future<String?> reverseLookup(String ip) async {
    try {
      final addr = InternetAddress.tryParse(ip);
      if (addr == null) return null;
      final host = await addr.reverse().timeout(const Duration(seconds: 3));
      return host.host;
    } catch (_) {
      return null;
    }
  }

  /// 端口扫描：固定窗口并发，逐个回调（界面上边扫边列出已开放的端口）。
  ///
  /// [concurrency] 别开太大：Android 单个进程 fd 上限通常 1024，且大并发
  /// 在弱网下会让「连接超时」误判成「关闭」。
  static Future<List<PortResult>> scanPorts(
    String host, {
    int start = 1,
    int end = 1024,
    int concurrency = 32,
    Duration timeout = const Duration(milliseconds: 800),
    void Function(PortResult)? onResult,
    bool Function()? isCancelled,
  }) async {
    final results = <PortResult>[];
    var next = start;
    final limit = end < start ? start : end;

    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() ?? false) return;
        final port = next++;
        if (port > limit) return;
        final started = DateTime.now();
        Socket? socket;
        var open = false;
        try {
          socket = await Socket.connect(host, port, timeout: timeout);
          open = true;
        } catch (_) {
          open = false;
        } finally {
          try {
            socket?.destroy();
          } catch (_) {}
        }
        final r = PortResult(port, open, DateTime.now().difference(started).inMilliseconds);
        results.add(r);
        onResult?.call(r);
      }
    }

    final workers = <Future<void>>[];
    final n = concurrency.clamp(1, 128);
    for (var i = 0; i < n; i++) {
      workers.add(worker());
    }
    await Future.wait(workers);
    results.sort((a, b) => a.port.compareTo(b.port));
    return results;
  }

  /// HTTP 检测：只取响应头（不下载正文），顺便看看 TLS 用的是哪个协议。
  static Future<HttpProbeResult> probeHttp(String url, {Duration timeout = const Duration(seconds: 10)}) async {
    final started = DateTime.now();
    var target = url.trim();
    if (!target.startsWith('http://') && !target.startsWith('https://')) {
      target = 'https://$target';
    }
    final uri = Uri.tryParse(target);
    if (uri == null || uri.host.isEmpty) {
      return HttpProbeResult(ms: 0, https: target.startsWith('https'), error: 'URL 不合法');
    }
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = timeout;
      // 诊断场景要看到真实证书问题，所以这里**不**跳过校验。
      // 注意是 headUrl(Uri)：dart:io 的 HttpClient 没有 head(Uri) 这个重载。
      final request = await client.headUrl(uri).timeout(timeout);
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      final headers = <String, String>{};
      response.headers.forEach((k, v) => headers[k] = v.join(', '));
      final ms = DateTime.now().difference(started).inMilliseconds;
      return HttpProbeResult(
        status: response.statusCode,
        ms: ms,
        https: uri.scheme == 'https',
        headers: headers,
      );
    } catch (e) {
      return HttpProbeResult(
        ms: DateTime.now().difference(started).inMilliseconds,
        https: uri.scheme == 'https',
        error: _shortError(e),
      );
    } finally {
      client?.close(force: true);
    }
  }

  /// 本机所在网段（取第一个私有 IPv4 的 /24）。
  static Future<String?> localSubnet() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final it in interfaces) {
        for (final addr in it.addresses) {
          if (addr.isLoopback) continue;
          final ip = addr.address;
          if (ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.')) {
            final parts = ip.split('.');
            if (parts.length == 4) return '${parts[0]}.${parts[1]}.${parts[2]}';
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// 局域网扫描：按网段扫 1~254，每个地址探几个常用端口。
  ///
  /// 不用 ICMP（见文件头说明），改用「TCP 握手成功即认为在线」；
  /// 每台最多探 [ports] 里的几个端口，命中一个就算在线并保留全部命中端口。
  static Future<List<LanHost>> sweepLan(
    String subnet, {
    List<int> ports = const [80, 443, 22, 445, 8080],
    Duration timeout = const Duration(milliseconds: 400),
    int concurrency = 64,
    void Function(LanHost)? onFound,
    bool Function()? isCancelled,
  }) async {
    final found = <LanHost>[];
    var next = 1;

    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() ?? false) return;
        final host = next++;
        if (host > 254) return;
        final ip = '$subnet.$host';
        final started = DateTime.now();
        final open = <int>[];
        for (final port in ports) {
          if (isCancelled?.call() ?? false) return;
          Socket? socket;
          try {
            socket = await Socket.connect(ip, port, timeout: timeout);
            open.add(port);
          } catch (_) {
            // 单个端口关着很正常，继续下一个。
          } finally {
            try {
              socket?.destroy();
            } catch (_) {}
          }
          if (open.isNotEmpty) break; // 命中一个就够判断在线，别把整段端口全打一遍
        }
        if (open.isNotEmpty) {
          final h = LanHost(ip, open, DateTime.now().difference(started).inMilliseconds);
          found.add(h);
          onFound?.call(h);
        }
      }
    }

    final workers = <Future<void>>[];
    final n = concurrency.clamp(1, 128);
    for (var i = 0; i < n; i++) {
      workers.add(worker());
    }
    await Future.wait(workers);
    found.sort((a, b) {
      int key(LanHost h) => int.tryParse(h.ip.split('.').last) ?? 0;
      return key(a).compareTo(key(b));
    });
    return found;
  }

  /// 把 SocketException 之类的长消息压成一行（界面上一行放不下）。
  static String _shortError(Object e) {
    final msg = e.toString();
    if (msg.contains('Connection refused')) return '拒绝连接';
    if (msg.contains('timed out') || msg.contains('TimeoutException')) return '超时';
    if (msg.contains('Failed host lookup')) return '域名解析失败';
    if (msg.contains('Network is unreachable')) return '网络不可达';
    if (msg.contains('certificate')) return '证书校验失败';
    return msg.length > 80 ? '${msg.substring(0, 80)}…' : msg;
  }
}
