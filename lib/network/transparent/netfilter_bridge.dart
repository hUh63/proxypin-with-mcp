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
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _StartNative = Int32 Function(Pointer<Utf8> driverName, Uint16 relayPort, Uint32 selfPid);
typedef _StartDart = int Function(Pointer<Utf8> driverName, int relayPort, int selfPid);

typedef _AddRuleNative = Int32 Function(Uint16 port);
typedef _AddRuleDart = int Function(int port);

typedef _StopNative = Void Function();
typedef _StopDart = void Function();

typedef _LookupNative = Int32 Function(
    Uint32 clientIp, Uint16 clientPort, Pointer<Uint32> outIp, Pointer<Uint16> outPort);
typedef _LookupDart = int Function(
    int clientIp, int clientPort, Pointer<Uint32> outIp, Pointer<Uint16> outPort);

typedef _CountersNative = Uint64 Function(
    Pointer<Uint64> syn, Pointer<Uint64> connected, Pointer<Uint64> closed, Pointer<Uint64> skipped);
typedef _CountersDart = int Function(
    Pointer<Uint64> syn, Pointer<Uint64> connected, Pointer<Uint64> closed, Pointer<Uint64> skipped);

class NetfilterBridgeStats {
  final int redirected;
  final int connected;
  final int closed;
  final int skipped;

  const NetfilterBridgeStats({
    required this.redirected,
    required this.connected,
    required this.closed,
    required this.skipped,
  });
}

/// NetFilter SDK **原生桥**的 Dart 控制面：加载 `netfilter_bridge.dll`（见
/// `native/netfilter_bridge/`），由原生侧完成真正的读写与地址改写。
///
/// 数据面（`NF_EventHandler` 回调 + `NF_TCP_CONN_INFO` 改写）留在原生 C++ 侧，
/// Dart 只负责启动、加规则、查原始目标、读计数。DLL 不在位时 [available] 为 false。
class NetfilterBridge {
  static const String dllName = 'netfilter_bridge.dll';
  static final NetfilterBridge instance = NetfilterBridge._();

  NetfilterBridge._();

  DynamicLibrary? _lib;
  _StartDart? _start;
  _AddRuleDart? _addRule;
  _StopDart? _stop;
  _LookupDart? _lookup;
  _CountersDart? _counters;

  bool get available => _lib != null;

  /// 在候选目录找 `netfilter_bridge.dll`（exe 同目录 → 当前目录 → PATH）。
  static String? locate() {
    if (!Platform.isWindows) return null;
    final dirs = <String>[];
    try {
      dirs.add(File(Platform.resolvedExecutable).parent.path);
    } catch (_) {}
    try {
      dirs.add(Directory.current.path);
    } catch (_) {}
    final path = Platform.environment['PATH'];
    if (path != null) dirs.addAll(path.split(';'));
    for (final d in dirs) {
      if (d.trim().isEmpty) continue;
      final p = _join(d, dllName);
      if (File(p).existsSync()) return p;
    }
    return null;
  }

  /// 加载桥 DLL；成功返回 true。DLL 不存在返回 false（功能优雅降级）。
  bool load() {
    if (_lib != null) return true;
    if (!Platform.isWindows) return false;
    final located = locate();
    final candidates = <String>[
      if (located != null) located,
      dllName,
    ];
    for (final c in candidates) {
      try {
        final lib = DynamicLibrary.open(c);
        _start = lib.lookupFunction<_StartNative, _StartDart>('nfb_start');
        _addRule = lib.lookupFunction<_AddRuleNative, _AddRuleDart>('nfb_add_tcp_rule');
        _stop = lib.lookupFunction<_StopNative, _StopDart>('nfb_stop');
        _lookup = lib.lookupFunction<_LookupNative, _LookupDart>('nfb_lookup_original');
        _counters = lib.lookupFunction<_CountersNative, _CountersDart>('nfb_get_counters');
        _lib = lib;
        return true;
      } catch (_) {
        // 换下一个候选
      }
    }
    return false;
  }

  /// 启动：初始化驱动并挂事件处理器。成功返回 0。
  int start({required int relayPort, required int selfPid, String driverName = 'nfdriver'}) {
    if (!load()) return -1;
    final name = driverName.toNativeUtf8();
    try {
      return _start!(name, relayPort, selfPid);
    } finally {
      malloc.free(name);
    }
  }

  /// 为某 TCP 目的端口添加规则。成功返回 0。
  int addTcpRule(int port) {
    final fn = _addRule;
    if (fn == null) return -1;
    return fn(port);
  }

  void stop() => _stop?.call();

  /// 返回 [origIp, origPort]；查不到返回 null。
  List<int>? lookupOriginal(int clientIp, int clientPort) {
    final fn = _lookup;
    if (fn == null) return null;
    final outIp = malloc<Uint32>();
    final outPort = malloc<Uint16>();
    try {
      if (fn(clientIp, clientPort, outIp, outPort) == 1) {
        return [outIp.value, outPort.value];
      }
      return null;
    } finally {
      malloc.free(outIp);
      malloc.free(outPort);
    }
  }

  NetfilterBridgeStats counters() {
    final fn = _counters;
    if (fn == null) {
      return const NetfilterBridgeStats(redirected: 0, connected: 0, closed: 0, skipped: 0);
    }
    final s = malloc<Uint64>();
    final c = malloc<Uint64>();
    final cl = malloc<Uint64>();
    final sk = malloc<Uint64>();
    try {
      final redirected = fn(s, c, cl, sk);
      return NetfilterBridgeStats(
          redirected: redirected, connected: c.value, closed: cl.value, skipped: sk.value);
    } finally {
      malloc.free(s);
      malloc.free(c);
      malloc.free(cl);
      malloc.free(sk);
    }
  }

  static String _join(String dir, String name) {
    if (dir.endsWith('\\') || dir.endsWith('/')) return '$dir$name';
    return '$dir${Platform.pathSeparator}$name';
  }
}
