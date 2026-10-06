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

typedef _GetExtTcpNative = Uint32 Function(
    Pointer<Uint8> table, Pointer<Uint32> size, Int32 order, Uint32 af, Int32 tableClass, Uint32 reserved);
typedef _GetExtTcpDart = int Function(
    Pointer<Uint8> table, Pointer<Uint32> size, int order, int af, int tableClass, int reserved);

/// 由「本地地址:端口」反查进程 PID（`GetExtendedTcpTable`，iphlpapi.dll）。
///
/// WinDivert 的网络层报文**不带进程信息**，所以按进程区分流量要靠这一步回查：
/// 用报文的源地址:端口去 TCP 连接表里找对应行，取 `dwOwningPid`。仅 Windows 可用。
class ProcessLookup {
  static const int _afInet = 2;
  static const int _tcpTableOwnerPidAll = 5;
  static const int _errorInsufficientBuffer = 122;
  static const int _rowSize = 24; // 6 个 DWORD

  static DynamicLibrary? _lib;
  static _GetExtTcpDart? _getExtTcp;

  static bool _ensureLoaded() {
    if (_getExtTcp != null) return true;
    if (!Platform.isWindows) return false;
    try {
      _lib ??= DynamicLibrary.open('iphlpapi.dll');
      _getExtTcp = _lib!.lookupFunction<_GetExtTcpNative, _GetExtTcpDart>('GetExtendedTcpTable');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// [srcIp] 4 字节网络序；[srcPort] 主机序。查不到返回 0。
  static int pidForTcp(Uint8List srcIp, int srcPort) {
    if (!_ensureLoaded()) return 0;
    var size = 0;
    var ret = _getExtTcp!(Pointer<Uint8>.fromAddress(0), Pointer<Uint32>.fromAddress(0).cast(), 0, _afInet,
        _tcpTableOwnerPidAll, 0);
    // 先用一个真实 size 指针申请
    final sizePtr = malloc<Uint32>();
    try {
      ret = _getExtTcp!(Pointer<Uint8>.fromAddress(0), sizePtr, 0, _afInet, _tcpTableOwnerPidAll, 0);
      size = sizePtr.value;
      if (ret != _errorInsufficientBuffer || size <= 4) return 0;

      final buffer = malloc<Uint8>(size);
      try {
        ret = _getExtTcp!(buffer, sizePtr, 0, _afInet, _tcpTableOwnerPidAll, 0);
        if (ret != 0) return 0;

        final bytes = buffer.asTypedList(size);
        final count = _u32(bytes, 0);
        final maxRows = ((size - 4) / _rowSize).floor();
        final rows = count < maxRows ? count : maxRows;
        for (var i = 0; i < rows; i++) {
          final off = 4 + i * _rowSize;
          // dwLocalAddr @ off+4, dwLocalPort @ off+8, dwOwningPid @ off+20
          if (bytes[off + 4] != srcIp[0] ||
              bytes[off + 5] != srcIp[1] ||
              bytes[off + 6] != srcIp[2] ||
              bytes[off + 7] != srcIp[3]) {
            continue;
          }
          // 端口在低 16 位、网络序（内存中为 [hi, lo]）
          final port = (bytes[off + 8 + 1] << 8) | bytes[off + 8];
          if (port == srcPort) {
            return _u32(bytes, off + 20);
          }
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
