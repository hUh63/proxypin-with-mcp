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
import 'package:proxypin/network/transparent/inet.dart';
import 'package:proxypin/network/transparent/process_lookup.dart';
import 'package:proxypin/network/transparent/windivert.dart';

/// 内核级透明抓包的运行统计。
class TransparentCaptureStats {
  int redirectedSyn = 0;
  int redirectedPackets = 0;
  int returnedPackets = 0;
  int skippedSelf = 0;
  int unmatched = 0;
  int totalPackets = 0;
  String? driverVersion;

  /// 最后一次错误信息（供界面展示）
  String? lastError;
}

enum TransparentCaptureStart {
  ok,
  notWindows,
  noDriver,
  noPermission,
  alreadyRunning,
  failed,
}

/// 内核级免代理抓包引擎（Windows，基于 WinDivert）。
///
/// 工作原理（单句柄 + 双向改写，详见 docs/kernel_capture_windivert.md）：
///  1. 用一条组合过滤规则抓「出网 TCP 80/443」与「本地代理回来的回程包」；
///  2. 出网 SYN：记下 (客户端 ip:port) → 原始目的，再把目的改写成 `127.0.0.1:relayPort`；
///  3. 回程包（源端口 == relayPort）：把源改回原始目的地址；
///  4. 其余报文：属于已映射连接的照改，否则原样放回。
///
/// 被抓的连接落到 [relayPort] 后，由 `TransparentRelay` 用标准 CONNECT 交给既有 MITM 代理。
///
/// **实验特性**：需要管理员权限 + WinDivert 驱动；改动发生在网络路径上，务必在真机验证。
class TransparentCapture {
  static final TransparentCapture instance = TransparentCapture._();

  TransparentCapture._();

  Isolate? _isolate;
  ReceivePort? _from;
  SendPort? _to;
  final stats = TransparentCaptureStats();

  /// 客户端(ip:port) → 原始目的(ip, port)。中继器据此还原真实目标。
  final Map<int, List<int>> _nat = {};

  final StreamController<void> _changes = StreamController<void>.broadcast();

  bool get isRunning => _isolate != null;

  Stream<void> get changes => _changes.stream;

  List<int>? lookupOriginal(int clientIp, int clientPort) => _nat[Ipv4Tcp.natKey(clientIp, clientPort)];

  int get natCount => _nat.length;

  Future<TransparentCaptureStart> start({required int relayPort}) async {
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
      case 'stats':
        stats.redirectedSyn = (msg['syn'] as int?) ?? stats.redirectedSyn;
        stats.redirectedPackets = (msg['redir'] as int?) ?? stats.redirectedPackets;
        stats.returnedPackets = (msg['ret'] as int?) ?? stats.returnedPackets;
        stats.skippedSelf = (msg['self'] as int?) ?? stats.skippedSelf;
        stats.unmatched = (msg['unmatched'] as int?) ?? stats.unmatched;
        stats.totalPackets = (msg['total'] as int?) ?? stats.totalPackets;
        stats.driverVersion = msg['version'] as String?;
        _changes.add(null);
        break;
    }
  }
}

/// isolate 入口：阻塞式收包 + 改写 + 放回。
void _entry(Map<String, Object> config) {
  final mainSend = config['send'] as SendPort;
  final relayPort = config['relayPort'] as int;
  final selfPid = config['selfPid'] as int;

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

  // 一条组合规则同时覆盖「出网 80/443」与「中继回程」两类报文
  final filter = 'tcp and outbound and '
      '((not loopback and (tcp.DstPort == 80 or tcp.DstPort == 443)) '
      'or (loopback and tcp.SrcPort == $relayPort))';

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

  var syn = 0, redir = 0, ret = 0, self = 0, unmatched = 0, total = 0;
  var lastStats = DateTime.now();

  try {
    while (running) {
      final len = windivert.recv(handle, packetBuf, bufferSize, addr);
      if (len <= 0) {
        if (!running) break;
        // 短暂错误（超时/队列空）：稍等再试
        sleep(const Duration(milliseconds: 5));
        continue;
      }
      total++;
      final bytes = packetBuf.asTypedList(len);
      final copy = Uint8List.fromList(bytes);
      final info = Ipv4Tcp.parse(copy);
      if (info == null) {
        windivert.send(handle, packetBuf, len, addr);
        continue;
      }

      final isLoopbackReturn = (addr.ref.bits >> 18) & 1 == 1 && info.srcPort == relayPort;

      if (isLoopbackReturn) {
        // 回程：源是本地中继，改回原始目的地址
        final clientIp = info.dstIp;
        final clientPort = info.dstPort;
        final orig = nat[Ipv4Tcp.natKey(clientIp, clientPort)];
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

Uint8List _ipBytes(int ip) => Uint8List.fromList([(ip >> 24) & 0xFF, (ip >> 16) & 0xFF, (ip >> 8) & 0xFF, ip & 0xFF]);
