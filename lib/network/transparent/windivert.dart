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
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// WinDivert（basil00，LGPLv3）FFI 绑定 —— 仅 Windows 使用。
///
/// **不需要我们自己签名**：WinDivert 的 `WinDivert.sys` 由项目签名，用户只需
/// 以管理员身份运行并保证 `WinDivert.dll` / `WinDivert64.sys` 可用。
/// 结构与函数签名逐条对齐官方 `windivert.h`（WinDivert 2.2.x）。
///
/// 注意：本文件只在 `Platform.isWindows` 下被真正加载，其它平台 import 无害
/// （`DynamicLibrary.open` 不会执行）。

// ---------- 常量 ----------
class WindivertLayer {
  static const int network = 0;
  static const int networkForward = 1;
  static const int flow = 2;
  static const int socket = 3;
  static const int reflect = 4;
}

class WindivertFlag {
  static const int sniff = 0x0001;
  static const int drop = 0x0002;
  static const int recvOnly = 0x0004;
  static const int sendOnly = 0x0008;
  static const int noInstall = 0x0010;
  static const int fragments = 0x0020;
}

class WindivertParam {
  static const int queueLength = 0;
  static const int queueTime = 1;
  static const int queueSize = 2;
  static const int versionMajor = 3;
  static const int versionMinor = 4;
}

class WindivertShutdown {
  static const int recv = 0x1;
  static const int send = 0x2;
  static const int both = 0x3;
}

/// `WINDIVERT_ADDRESS`，官方布局：INT64 Timestamp + UINT32 位域 + UINT32 Reserved2
/// + 64 字节 union（Network/Flow/Socket/Reflect/Reserved3）。合计 80 字节。
final class WindivertAddress extends Struct {
  @Int64()
  external int timestamp;

  /// 位域：Layer:8 | Event:8 | Sniffed:1 | Outbound:1 | Loopback:1 | Impostor:1 |
  /// IPv6:1 | IPChecksum:1 | TCPChecksum:1 | UDPChecksum:1 | Reserved1:8
  @Uint32()
  external int bits;

  @Uint32()
  external int reserved2;

  @Array(64)
  external Array<Uint8> data;

  int get layer => bits & 0xFF;
  int get event => (bits >> 8) & 0xFF;
  int get outbound => (bits >> 17) & 1;
  int get loopback => (bits >> 18) & 1;
  int get ipv6 => (bits >> 20) & 1;
}

// ---------- 原生签名 ----------
typedef _OpenNative = IntPtr Function(Pointer<Utf8> filter, Int32 layer, Int16 priority, Uint64 flags);
typedef _OpenDart = int Function(Pointer<Utf8> filter, int layer, int priority, int flags);

typedef _RecvNative = Int32 Function(Pointer<Void> handle, Pointer<Uint8> packet, Uint32 packetLen,
    Pointer<Uint32> recvLen, Pointer<WindivertAddress> addr);
typedef _RecvDart = int Function(
    Pointer<Void> handle, Pointer<Uint8> packet, int packetLen, Pointer<Uint32> recvLen, Pointer<WindivertAddress> addr);

typedef _SendNative = Int32 Function(Pointer<Void> handle, Pointer<Uint8> packet, Uint32 packetLen,
    Pointer<Uint32> sendLen, Pointer<WindivertAddress> addr);
typedef _SendDart = int Function(
    Pointer<Void> handle, Pointer<Uint8> packet, int packetLen, Pointer<Uint32> sendLen, Pointer<WindivertAddress> addr);

typedef _CalcChecksumsNative = Int32 Function(
    Pointer<Uint8> packet, Uint32 packetLen, Pointer<WindivertAddress> addr, Uint64 flags);
typedef _CalcChecksumsDart = int Function(
    Pointer<Uint8> packet, int packetLen, Pointer<WindivertAddress> addr, int flags);

typedef _CloseNative = Int32 Function(Pointer<Void> handle);
typedef _CloseDart = int Function(Pointer<Void> handle);

typedef _SetParamNative = Int32 Function(Pointer<Void> handle, Int32 param, Uint64 value);
typedef _SetParamDart = int Function(Pointer<Void> handle, int param, int value);

typedef _ShutdownNative = Int32 Function(Pointer<Void> handle, Int32 how);
typedef _ShutdownDart = int Function(Pointer<Void> handle, int how);

/// WinDivert 动态库封装。加载失败（未安装）时 [tryLoad] 返回 null。
class Windivert {
  final DynamicLibrary _lib;

  late final _OpenDart _open = _lib.lookupFunction<_OpenNative, _OpenDart>('WinDivertOpen');
  late final _RecvDart _recv = _lib.lookupFunction<_RecvNative, _RecvDart>('WinDivertRecv');
  late final _SendDart _send = _lib.lookupFunction<_SendNative, _SendDart>('WinDivertSend');
  late final _CalcChecksumsDart _calcChecksums =
      _lib.lookupFunction<_CalcChecksumsNative, _CalcChecksumsDart>('WinDivertHelperCalcChecksums');
  late final _CloseDart _close = _lib.lookupFunction<_CloseNative, _CloseDart>('WinDivertClose');
  late final _SetParamDart _setParam = _lib.lookupFunction<_SetParamNative, _SetParamDart>('WinDivertSetParam');
  late final _ShutdownDart _shutdown = _lib.lookupFunction<_ShutdownNative, _ShutdownDart>('WinDivertShutdown');

  Windivert._(this._lib);

  static Windivert? tryLoad() {
    if (!Platform.isWindows) return null;
    for (final name in ['WinDivert.dll', 'windivert.dll']) {
      try {
        return Windivert._(DynamicLibrary.open(name));
      } catch (_) {
        // 尝试下一个名字
      }
    }
    return null;
  }

  /// 打开一个 WinDivert 句柄；失败返回 null。
  Pointer<Void>? open(String filter, {int layer = WindivertLayer.network, int priority = 0, int flags = 0}) {
    final f = filter.toNativeUtf8();
    try {
      final h = _open(f, layer, priority, flags);
      // INVALID_HANDLE_VALUE == -1
      if (h == -1 || h == 0) return null;
      return Pointer<Void>.fromAddress(h);
    } catch (_) {
      return null;
    } finally {
      malloc.free(f);
    }
  }

  /// 阻塞读取一个报文到 [buffer]；返回写入 buffer 的字节数，<=0 表示失败/关闭。
  int recv(Pointer<Void> handle, Pointer<Uint8> buffer, int bufferSize, Pointer<WindivertAddress> addr) {
    final len = malloc<Uint32>();
    try {
      final ok = _recv(handle, buffer, bufferSize, len, addr);
      if (ok == 0) return -1;
      return len.value;
    } finally {
      malloc.free(len);
    }
  }

  bool send(Pointer<Void> handle, Pointer<Uint8> buffer, int length, Pointer<WindivertAddress> addr) {
    final sent = malloc<Uint32>();
    try {
      return _send(handle, buffer, length, sent, addr) != 0;
    } finally {
      malloc.free(sent);
    }
  }

  /// 让 WinDivert 重算校验和（flags: 0 表示 IP+TCP+UDP 全部）。
  void calcChecksums(Pointer<Uint8> buffer, int length, Pointer<WindivertAddress> addr) {
    _calcChecksums(buffer, length, addr, 0);
  }

  bool setParam(Pointer<Void> handle, int param, int value) => _setParam(handle, param, value) != 0;

  void shutdown(Pointer<Void> handle, {int how = WindivertShutdown.both}) {
    try {
      _shutdown(handle, how);
    } catch (_) {}
  }

  void close(Pointer<Void> handle) {
    try {
      _close(handle);
    } catch (_) {}
  }

  /// 把裸报文（Uint8List）拷进 native 内存并返回指针（调用方负责 free）。
  static Pointer<Uint8> allocCopy(Uint8List bytes) {
    final p = malloc<Uint8>(bytes.length);
    p.asTypedList(bytes.length).setAll(0, bytes);
    return p;
  }
}
