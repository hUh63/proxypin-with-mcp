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

typedef _GetExtNative = Uint32 Function(
    Pointer<Uint8> table, Pointer<Uint32> size, Int32 order, Uint32 af, Int32 tableClass, Uint32 reserved);
typedef _GetExtDart = int Function(
    Pointer<Uint8> table, Pointer<Uint32> size, int order, int af, int tableClass, int reserved);

/// 由「本地地址:端口」反查进程 PID（`GetExtendedTcpTable` / `GetExtendedUdpTable`，iphlpapi.dll）。
///
/// WinDivert 的网络层报文**不带进程信息**，所以按进程区分流量要靠这一步回查：
/// 用报文的源地址:端口去连接表里找对应行，取 `dwOwningPid`。仅 Windows 可用。
class ProcessLookup {
  static const int _afInet = 2;
  static const int _tcpTableOwnerPidAll = 5;
  static const int _udpTableOwnerPid = 1;
  static const int _errorInsufficientBuffer = 122;
  static const int _tcpRowSize = 24; // MIB_TCPROW_OWNER_PID：6 个 DWORD
  static const int _udpRowSize = 12; // MIB_UDPROW_OWNER_PID：3 个 DWORD

  static DynamicLibrary? _lib;
  static _GetExtDart? _getExtTcp;
  static _GetExtDart? _getExtUdp;

  static bool _ensureLoaded() {
    if (_getExtTcp != null) return true;
    if (!Platform.isWindows) return false;
    try {
      _lib ??= DynamicLibrary.open('iphlpapi.dll');
      _getExtTcp = _lib!.lookupFunction<_GetExtNative, _GetExtDart>('GetExtendedTcpTable');
      try {
        _getExtUdp = _lib!.lookupFunction<_GetExtNative, _GetExtDart>('GetExtendedUdpTable');
      } catch (_) {
        _getExtUdp = null;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// [srcIp] 4 字节网络序；[srcPort] 主机序。查不到返回 0。
  static int pidForTcp(Uint8List srcIp, int srcPort) =>
      _pidFor(_getExtTcp, _tcpTableOwnerPidAll, _tcpRowSize, srcIp, srcPort, addrOffset: 4, portOffset: 8, pidOffset: 20);

  /// UDP 版：由本地地址:端口反查 PID。查不到返回 0。
  static int pidForUdp(Uint8List localIp, int localPort) =>
      _pidFor(_getExtUdp, _udpTableOwnerPid, _udpRowSize, localIp, localPort, addrOffset: 0, portOffset: 4, pidOffset: 8);

  static int _pidFor(_GetExtDart? fn, int tableClass, int rowSize, Uint8List ip, int port,
      {required int addrOffset, required int portOffset, required int pidOffset}) {
    if (fn == null || !_ensureLoaded()) return 0;
    final sizePtr = malloc<Uint32>();
    try {
      var ret = fn(Pointer<Uint8>.fromAddress(0), sizePtr, 0, _afInet, tableClass, 0);
      final size = sizePtr.value;
      if (ret != _errorInsufficientBuffer || size <= 4) return 0;

      final buffer = malloc<Uint8>(size);
      try {
        ret = fn(buffer, sizePtr, 0, _afInet, tableClass, 0);
        if (ret != 0) return 0;

        final bytes = buffer.asTypedList(size);
        final count = _u32(bytes, 0);
        final maxRows = ((size - 4) / rowSize).floor();
        final rows = count < maxRows ? count : maxRows;
        for (var i = 0; i < rows; i++) {
          final off = 4 + i * rowSize;
          final a = off + addrOffset;
          if (bytes[a] != ip[0] || bytes[a + 1] != ip[1] || bytes[a + 2] != ip[2] || bytes[a + 3] != ip[3]) {
            continue;
          }
          // 端口在低 16 位、网络序（内存中为 [hi, lo]）
          final p = off + portOffset;
          final rowPort = (bytes[p + 1] << 8) | bytes[p];
          if (rowPort == port) return _u32(bytes, off + pidOffset);
        }
        return 0;
      } finally {
        malloc.free(buffer);
      }
    } catch (_) {
      return 0;
    } finally {
      malloc.free(sizePtr);
    }
  }

  static int _u32(Uint8List b, int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
}
