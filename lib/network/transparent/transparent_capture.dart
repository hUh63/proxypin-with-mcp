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
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:proxypin/network/transparent/dns.dart';
import 'package:proxypin/network/transparent/inet.dart';
import 'package:proxypin/network/transparent/process_lookup.dart';
import 'package:proxypin/network/transparent/windivert.dart';

/// 内核抓包的抓取范围配置。
class TransparentCaptureConfig {
  /// 要重定向到本地代理的 **TCP 目的端口**（不认系统代理的程序走这里）。
  final List<int> tcpPorts;

  /// 是否嗅探 UDP（只读：读上看一眼再原样放回，不改写地址）。
  final bool captureUdp;

  /// 要嗅探的 UDP 目的端口；含 53 时解析 DNS 查询名。
  final List<int> udpPorts;

  /// DNS 本地改写规则：域名 → IPv4 地址。键可为通配 `*.example.com`（匹配其子域）。
  /// 命中时丢弃原查询并注入伪响应（仅对 A 查询生效）。
  final Map<String, String> dnsRewrite;

  const TransparentCaptureConfig({
    this.tcpPorts = const [80, 443],
    this.captureUdp = false,
    this.udpPorts = const [53],
    this.dnsRewrite = const {},
  });

  Map<String, Object> toJson() => {
        'tcpPorts': tcpPorts,
        'captureUdp': captureUdp,
        'udpPorts': udpPorts,
        'dnsRewrite': dnsRewrite,
      };
}

/// 一条被嗅探到的 DNS 查询。
class DnsEvent {
  final String name;
  final String type;
  final String dst;
  final bool rewritten;
  final DateTime at;

  DnsEvent(this.name, this.type, this.dst, {this.rewritten = false}) : at = DateTime.now();
}

/// 内核级透明抓包的运行统计。
class TransparentCaptureStats {
  int redirectedSyn = 0;
  int redirectedPackets = 0;
  int returnedPackets = 0;
  int skippedSelf = 0;
  int unmatched = 0;
  int totalPackets = 0;
  int udpPackets = 0;
  int dnsQueries = 0;
  int dnsRewritten = 0;
  String? driverVersion;

  /// 最后一次错误信息（供界面展示）
  String? lastError;

  /// 最近嗅探到的 DNS 查询（有界）。
  final List<DnsEvent> recentDns = [];
}

enum TransparentCaptureStart {
  ok,
  notWindows,
  noDriver,
  noPermission,
  alreadyRunning,
  noTcpPorts,
  failed,
}

/// 内核级免代理抓包引擎（Windows，基于 WinDivert）。
///
/// 工作原理（单句柄 + 双向改写，详见 docs/kernel_capture_windivert.md）：
///  1. 用一条组合过滤规则抓「出网 TCP（可配置端口）」与「本地代理回来的回程包」，
///     以及（可选）「出网 UDP（可配置端口）」；
///  2. 出网 TCP SYN：记下 (客户端 ip:port) → 原始目的，再把目的改写成 `127.0.0.1:relayPort`；
///  3. 回程包（源端口 == relayPort）：把源改回原始目的地址；
///  4. UDP：**只读嗅探**，解析 DNS 后原样放回（不做地址改写）；
///  5. 其余报文：属于已映射连接的照改，否则原样放回。
///
/// 被抓的连接落到 [relayPort] 后，由 `TransparentRelay` 用标准 CONNECT 交给既有 MITM 代理。
///
/// **实验特性**：需要管理员权限 + WinDivert 驱动；改动发生在网络路径上，务必在真机验证。
class TransparentCapture {
  static final TransparentCapture instance = TransparentCapture._();

  TransparentCapture._();

  static const int maxDnsEvents = 100;

  Isolate? _isolate;
  ReceivePort? _from;
  SendPort? _to;
  final stats = TransparentCaptureStats();

  /// 当前（或上次）的抓取范围配置。
  TransparentCaptureConfig config = const TransparentCaptureConfig();

  /// 客户端(ip:port) → 原始目的(ip, port)。中继器据此还原真实目标。
  final Map<int, List<int>> _nat = {};

  final StreamController<void> _changes = StreamController<void>.broadcast();

  bool get isRunning => _isolate != null;

  Stream<void> get changes => _changes.stream;

  List<int>? lookupOriginal(int clientIp, int clientPort) => _nat[Ipv4Tcp.natKey(clientIp, clientPort)];

  int get natCount => _nat.length;

  Future<TransparentCaptureStart> start({required int relayPort, TransparentCaptureConfig? config}) async {
    if (config != null) this.config = config;
    if (this.config.tcpPorts.isEmpty && !this.config.captureUdp) return TransparentCaptureStart.noTcpPorts;
    if (!Platform.isWindows) return TransparentCaptureStart.notWindows;
    if (isRunning) return TransparentCaptureStart.alreadyRunning;

    // 用「只读探测」确认驱动可用与权限：以 SNIFF 方式开一个临时句柄。
    final probe = Windivert.tryLoad();
    if (probe == null) return TransparentCaptureStart.noDriver;
    final probeHandle = probe.open('false', flags: WindivertFlag.sniff | WindivertFlag.recvOnly);
    if (probeHandle == null) {
      return TransparentCaptureStart.noPermission;
    }
    probe.close(probeHandle);

    final ready = ReceivePort();
    try {
      final isolate = await Isolate.spawn(_entry, {
        'send': ready.sendPort,
        'relayPort': relayPort,
        'selfPid': pid,
        'config': this.config.toJson(),
      }, debugName: 'proxypin-transparent');

      final completer = Completer<TransparentCaptureStart>();
      late StreamSubscription sub;
      sub = ready.listen((msg) {
        if (msg is Map && msg['type'] == 'ready') {
          _to = msg['port'] as SendPort;
          _isolate = isolate;
          if (!completer.isCompleted) completer.complete(TransparentCaptureStart.ok);
          sub.cancel();
          _changes.add(null);
        } else if (msg is Map && msg['type'] == 'error') {
          stats.lastError = msg['message'] as String?;
          if (!completer.isCompleted) completer.complete(TransparentCaptureStart.failed);
        } else if (msg is Map) {
          _handleIsolateMessage(msg);
        }
      });
      _from = ready;

      return await completer.future.timeout(const Duration(seconds: 8),
          onTimeout: () => TransparentCaptureStart.failed);
    } catch (e) {
      stats.lastError = '$e';
      return TransparentCaptureStart.failed;
    }
  }

  Future<void> stop() async {
    _to?.send('stop');
    // 给 isolate 一点时间自己关句柄
    await Future.delayed(const Duration(milliseconds: 300));
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _to = null;
    _from?.close();
    _from = null;
    _nat.clear();
    stats.lastError = null;
    _changes.add(null);
  }

  void _handleIsolateMessage(Map msg) {
    switch (msg['type']) {
      case 'map':
        final key = msg['key'] as int;
        _nat[key] = [msg['ip'] as int, msg['port'] as int];
        break;
      case 'unmap':
        _nat.remove(msg['key'] as int);
        break;
      case 'dns':
        final name = msg['name'] as String?;
        if (name != null) {
          stats.dnsQueries++;
          stats.recentDns.insert(0,
              DnsEvent(name, msg['qtype'] as String? ?? '', msg['dst'] as String? ?? '', rewritten: msg['rewritten'] == true));
          if (stats.recentDns.length > maxDnsEvents) stats.recentDns.removeLast();
          _changes.add(null);
        }
        break;
      case 'stats':
        stats.redirectedSyn = (msg['syn'] as int?) ?? stats.redirectedSyn;
        stats.redirectedPackets = (msg['redir'] as int?) ?? stats.redirectedPackets;
        stats.returnedPackets = (msg['ret'] as int?) ?? stats.returnedPackets;
        stats.skippedSelf = (msg['self'] as int?) ?? stats.skippedSelf;
        stats.unmatched = (msg['unmatched'] as int?) ?? stats.unmatched;
        stats.totalPackets = (msg['total'] as int?) ?? stats.totalPackets;
        stats.udpPackets = (msg['udp'] as int?) ?? stats.udpPackets;
        stats.dnsQueries = (msg['dns'] as int?) ?? stats.dnsQueries;
        stats.dnsRewritten = (msg['dnsrw'] as int?) ?? stats.dnsRewritten;
        stats.driverVersion = msg['version'] as String?;
        _changes.add(null);
        break;
    }
  }
}

/// isolate 入口：阻塞式收包 + 改写（TCP）/ 嗅探（UDP） + 放回。
void _entry(Map<String, Object> config) {
  final mainSend = config['send'] as SendPort;
  final relayPort = config['relayPort'] as int;
  final selfPid = config['selfPid'] as int;

  final cfg = (config['config'] as Map?) ?? const {};
  final tcpPorts = ((cfg['tcpPorts'] as List?) ?? const [80, 443]).cast<int>();
  final captureUdp = cfg['captureUdp'] == true;
  final udpPorts = ((cfg['udpPorts'] as List?) ?? const [53]).cast<int>();
  final dnsRewrite = <String, String>{};
  final rawRules = cfg['dnsRewrite'];
  if (rawRules is Map) {
    rawRules.forEach((k, v) {
      if (k is String && v is String && v.isNotEmpty) dnsRewrite[k.toLowerCase()] = v;
    });
  }

  final control = ReceivePort();
  var running = true;
  control.listen((msg) {
    if (msg == 'stop') running = false;
  });

  final windivert = Windivert.tryLoad();
  if (windivert == null) {
    mainSend.send({'type': 'error', 'message': 'WinDivert 未安装（缺少 WinDivert.dll）'});
    control.close();
    return;
  }

  // 组合规则：TCP 重定向（出网）+ 中继回程；可选 UDP 嗅探（出网）
  final tcpPart = tcpPorts.isEmpty
      ? '(loopback and tcp.SrcPort == $relayPort)'
      : '((not loopback and (${tcpPorts.map((p) => 'tcp.DstPort == $p').join(' or ')})) '
          'or (loopback and tcp.SrcPort == $relayPort))';
  var filter = 'tcp and outbound and $tcpPart';
  if (captureUdp && udpPorts.isNotEmpty) {
    filter += ' or (udp and outbound and (${udpPorts.map((p) => 'udp.DstPort == $p').join(' or ')}))';
  }

  final handle = windivert.open(filter);
  if (handle == null) {
    mainSend.send({'type': 'error', 'message': '打开 WinDivert 失败（需要管理员权限）'});
    control.close();
    return;
  }

  mainSend.send({'type': 'ready', 'port': control.sendPort});

  const bufferSize = 0xFFFF + 64;
  final packetBuf = malloc<Uint8>(bufferSize);
  final addr = malloc<WindivertAddress>();
  final nat = <int, List<int>>{};

  var syn = 0, redir = 0, ret = 0, self = 0, unmatched = 0, total = 0, udp = 0, dnsCount = 0, dnsRewritten = 0;
  var lastStats = DateTime.now();

  try {
    while (running) {
      final len = windivert.recv(handle, packetBuf, bufferSize, addr);
      if (len <= 0) {
        if (!running) break;
        sleep(const Duration(milliseconds: 5));
        continue;
      }
      total++;
      final copy = Uint8List.fromList(packetBuf.asTypedList(len));

      // ---- UDP（只读嗅探） ----
      if (copy.length >= 20 && copy[9] == Ipv4Udp.protoUdp) {
        final u = Ipv4Udp.parse(copy);
        if (u == null) {
          windivert.send(handle, packetBuf, len, addr);
          continue;
        }
        final owner = ProcessLookup.pidForUdp(_ipBytes(u.srcIp), u.srcPort);
        if (owner == selfPid) {
          self++;
          windivert.send(handle, packetBuf, len, addr);
          continue;
        }
        udp++;
        var injected = false;
        if (u.dstPort == 53) {
          final payload = Uint8List.sublistView(copy, u.payloadOffset);
          final dnsMsg = Dns.parse(payload);
          if (dnsMsg != null && !dnsMsg.isResponse) {
            dnsCount++;
            var rewritten = false;
            if (dnsRewrite.isNotEmpty) {
              final ipv4 = _matchRewrite(dnsRewrite, dnsMsg.name);
              if (ipv4 != null) {
                final resp = Dns.buildResponse(payload, a: ipv4);
                if (resp != null) {
                  final reply = Ipv4Udp.buildReply(copy, resp);
                  windivert.send(handle, Windivert.allocCopy(reply), reply.length, addr);
                  dnsRewritten++;
                  rewritten = true;
                  injected = true;
                }
              }
            }
            mainSend.send({
              'type': 'dns',
              'name': dnsMsg.name,
              'qtype': dnsMsg.typeText,
              'dst': '${u.dstIpText}:${u.dstPort}',
              'rewritten': rewritten,
            });
          }
        }
        if (!injected) windivert.send(handle, packetBuf, len, addr); // 未改写才原样放回
        continue;
      }

      // ---- TCP（改写重定向） ----
      final info = Ipv4Tcp.parse(copy);
      if (info == null) {
        windivert.send(handle, packetBuf, len, addr);
        continue;
      }

      final isLoopbackReturn = (addr.ref.bits >> 18) & 1 == 1 && info.srcPort == relayPort;

      if (isLoopbackReturn) {
        // 回程：源是本地中继，改回原始目的地址
        final orig = nat[Ipv4Tcp.natKey(info.dstIp, info.dstPort)];
        if (orig != null) {
          Ipv4Tcp.rewriteSrc(copy, orig[0], orig[1]);
          windivert.send(handle, Windivert.allocCopy(copy), copy.length, addr);
          ret++;
        } else {
          unmatched++;
          windivert.send(handle, packetBuf, len, addr);
        }
      } else {
        final key = Ipv4Tcp.natKey(info.srcIp, info.srcPort);
        if (info.isSyn) {
          final owner = ProcessLookup.pidForTcp(_ipBytes(info.srcIp), info.srcPort);
          if (owner == selfPid) {
            // 自己（代理进程）出的流量不劫持，避免回环
            self++;
            nat.remove(key);
            windivert.send(handle, packetBuf, len, addr);
            continue;
          }
          nat[key] = [info.dstIp, info.dstPort];
          if (nat.length > 8192) nat.remove(nat.keys.first);
          mainSend.send({'type': 'map', 'key': key, 'ip': info.dstIp, 'port': info.dstPort});
          Ipv4Tcp.rewriteDst(copy, PacketInfo.ipOf('127.0.0.1'), relayPort);
          windivert.send(handle, Windivert.allocCopy(copy), copy.length, addr);
          syn++;
          redir++;
        } else {
          final orig = nat[key];
          if (orig != null) {
            Ipv4Tcp.rewriteDst(copy, PacketInfo.ipOf('127.0.0.1'), relayPort);
            windivert.send(handle, Windivert.allocCopy(copy), copy.length, addr);
            redir++;
            if (info.fin || info.rst) {
              nat.remove(key);
              mainSend.send({'type': 'unmap', 'key': key});
            }
          } else {
            unmatched++;
            windivert.send(handle, packetBuf, len, addr);
          }
        }
      }

      // 每秒回报一次统计
      final now = DateTime.now();
      if (now.difference(lastStats).inMilliseconds >= 1000) {
        lastStats = now;
        mainSend.send({
          'type': 'stats',
          'syn': syn,
          'redir': redir,
          'ret': ret,
          'self': self,
          'unmatched': unmatched,
          'total': total,
          'udp': udp,
          'dns': dnsCount,
          'dnsrw': dnsRewritten,
        });
      }
    }
  } catch (e) {
    mainSend.send({'type': 'error', 'message': '$e'});
  } finally {
    try {
      windivert.shutdown(handle);
    } catch (_) {}
    windivert.close(handle);
    malloc.free(packetBuf);
    malloc.free(addr);
    control.close();
  }
}

/// 在改写规则里匹配域名（精确优先，其次 `*.suffix`），命中返回 IPv4 字节；否则 null。
List<int>? _matchRewrite(Map<String, String> rules, String name) {
  final lower = name.toLowerCase();
  String? value = rules[lower];
  if (value == null) {
    for (final e in rules.entries) {
      if (e.key.startsWith('*.')) {
        final suffix = e.key.substring(1); // .example.com
        if (lower.endsWith(suffix) && lower.length > suffix.length) {
          value = e.value;
          break;
        }
      }
    }
  }
  if (value == null) return null;
  final parts = value.split('.');
  if (parts.length != 4) return null;
  final bytes = <int>[];
  for (final p in parts) {
    final v = int.tryParse(p);
    if (v == null || v < 0 || v > 255) return null;
    bytes.add(v);
  }
  return bytes;
}

Uint8List _ipBytes(int ip) => Uint8List.fromList([(ip >> 24) & 0xFF, (ip >> 16) & 0xFF, (ip >> 8) & 0xFF, ip & 0xFF]);
