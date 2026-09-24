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
import 'dart:io';

import 'package:proxypin/network/util/crts.dart';
import 'package:proxypin/network/util/logger.dart';

/// Root 直挂系统信任库（**没有 Magisk 时的兜底**）。
///
/// 先说清和现有方案的分工。证书页上那个「一键自动安装到系统」走的是
/// **Magisk 模块**（`/data/adb/modules/proxypin_ca` + `post-fs-data.sh`），
/// 这条路对主流设备最稳——开机时由模块挂载，zygote 起来之前就已生效，
/// 且重启后依然在。但它有个前提：设备装了 Magisk / KernelSU / APatch
/// （得有 `/data/adb/modules`），否则只会在 UI 上报「未检测到」然后失败。
///
/// 这里补的正是这个缺口：**没有模块管理器、但有 root** 的设备。
/// 做法是运行时用 tmpfs 覆盖挂载系统信任库目录。代价是**重启后失效**，
/// 换来的是：不往任何持久分区写东西（可逆），也不必重启设备
/// （装完重启一下目标应用即可，需要的话还能重启 zygote 让所有应用立刻感知）。
///
/// 安全约定（写错的后果是设备所有 HTTPS 失败，务必遵守）：
///  1. 先把原目录证书**完整复制**到工作目录，并清点数量；
///  2. 铺回目标目录后再清点一次，少于「原有 + 1」立刻 umount 回滚；
///  3. 任何一步失败都回滚，绝不把设备留在信任库残缺的状态。
class SystemCa {
  SystemCa._();

  /// 仅 Android 有这套机制。
  static bool get supported => Platform.isAndroid;

  /// 设备是否装了模块管理器（有 /data/adb/modules）。会唤起 su。
  static Future<bool> hasModuleManager() async {
    if (!supported) {
      return false;
    }
    final r = await _su('[ -d /data/adb/modules ] && echo YES || echo NO');
    return r.$2.contains('YES');
  }

  /// 设备是否已 root 且授权了 su。
  static Future<bool> hasRoot() async {
    if (!supported) {
      return false;
    }
    final r = await _su('id');
    return r.$2.contains('uid=0');
  }

  /// 是否已经处于「直挂」状态。
  static Future<bool> isMounted() async {
    if (!supported) {
      return false;
    }
    final r = await _su(
      'if [ -d $_workDir ]; then '
      'DIR=""; for d in $_candidates; do if [ -d "\$d" ]; then DIR="\$d"; break; fi; done; '
      'if [ -n "\$DIR" ] && grep -q " \$DIR " /proc/mounts; then echo YES; else echo NO; fi; '
      'else echo NO; fi',
    );
    return r.$2.contains('YES');
  }

  /// 运行时把 CA 直挂进系统信任库。返回 (是否成功, 说明)。
  static Future<(bool, String)> mountRuntime() async {
    if (!supported) {
      return (false, 'only supported on Android');
    }
    final String name;
    final String caPath;
    try {
      name = await CertificateManager.systemCertificateName();
      caPath = (await CertificateManager.certificateFile()).path;
    } catch (e) {
      logger.e('[SystemCa] prepare cert failed: $e');
      return (false, 'cannot prepare certificate: $e');
    }

    // 用占位符拼脚本：raw string 里 $ 原样留给 shell，只有证书路径/文件名走 Dart 插值
    final script = _mountScript
        .replaceAll('__CA_PATH__', '"$caPath"')
        .replaceAll('__CA_NAME__', name);
    final r = await _su(script);
    final ok = r.$2.contains('MOUNTED');
    if (ok) {
      logger.i('[SystemCa] mounted runtime CA: $name');
      return (true, name);
    }
    final reason = _lastError(r.$2).ifEmpty('exit=${r.$1}');
    logger.w('[SystemCa] mount failed: $reason');
    // 兜底清理，别让用户带着半成品环境
    await _su(_rollbackScript);
    return (false, reason);
  }

  /// 卸载直挂（摘掉覆盖挂载，系统原有信任库原封不动）。
  static Future<(bool, String)> unmountRuntime() async {
    if (!supported) {
      return (false, 'only supported on Android');
    }
    final r = await _su(_unmountScript);
    final ok = r.$2.contains('UNMOUNTED');
    final reason = ok ? '' : _lastError(r.$2).ifEmpty('exit=${r.$1}');
    logger.i('[SystemCa] unmount runtime: ok=$ok $reason');
    return (ok, reason);
  }

  /// 重启 zygote，让已启动的应用立刻重新读取信任库。
  ///
  /// 信任库有缓存，刚挂上的证书在已运行的应用里看不到；重启 zygote 会连带
  /// 重启所有应用**以及本 App 自己**，界面闪一下属预期。
  static Future<(bool, String)> restartZygote() async {
    if (!supported) {
      return (false, 'only supported on Android');
    }
    final r = await _su('setprop ctl.restart zygote 2>/dev/null || { stop zygote; start zygote; }; echo DONE');
    final ok = r.$2.contains('DONE');
    return (ok, ok ? '' : _lastError(r.$2).ifEmpty('exit=${r.$1}'));
  }

  // ---------- 内部 ----------

  static const String _workDir = '/data/local/tmp/proxypin_ca';
  static const String _candidates =
      '/apex/com.android.conscrypt/cacerts /system/etc/security/cacerts';

  /// 执行 root 命令：返回 (exitCode, 合并输出)。
  ///
  /// su 首次会弹授权框，等太久会让 UI 空转，所以加超时。
  static Future<(int, String)> _su(String command) async {
    try {
      final r = await Process.run('su', ['-c', command])
          .timeout(const Duration(seconds: 60), onTimeout: () {
        throw const SocketException('su timeout');
      });
      return (r.exitCode, '${r.stdout}${r.stderr}');
    } catch (e) {
      logger.e('[SystemCa] su failed: $e');
      return (-1, '$e');
    }
  }

  static String _lastError(String output) {
    for (final line in output.split('\n')) {
      final t = line.trim();
      if (t.startsWith('ERR_')) {
        return t;
      }
    }
    return output.trim();
  }

  /// raw string：这里的 $ 全部留给 shell 解释
  static const String _mountScript = r'''
set -e
DIR=""
for d in /apex/com.android.conscrypt/cacerts /system/etc/security/cacerts; do
  if [ -d "$d" ]; then DIR="$d"; break; fi
done
if [ -z "$DIR" ]; then echo ERR_NO_DIR; exit 1; fi
WORK=/data/local/tmp/proxypin_ca
rm -rf "$WORK"
mkdir -p "$WORK"
cp -f "$DIR"/* "$WORK"/ 2>/dev/null || true
BASE=$(ls "$WORK" | wc -l)
if [ "$BASE" -lt 1 ]; then echo ERR_BASE; exit 1; fi
cp -f __CA_PATH__ "$WORK/__CA_NAME__"
chmod 644 "$WORK"/* 2>/dev/null || true
chown 0:0 "$WORK"/* 2>/dev/null || true
mount -t tmpfs tmpfs "$DIR" || { echo ERR_MOUNT; exit 1; }
cp -f "$WORK"/* "$DIR"/
chmod 644 "$DIR"/* 2>/dev/null || true
chown 0:0 "$DIR"/* 2>/dev/null || true
restorecon "$DIR" 2>/dev/null || chcon u:object_r:system_security_cacerts_file:s0 "$DIR"/* 2>/dev/null || true
NOW=$(ls "$DIR" | wc -l)
if [ "$NOW" -lt $((BASE + 1)) ]; then umount "$DIR" 2>/dev/null || true; echo ERR_VERIFY; exit 1; fi
echo MOUNTED
''';

  static const String _unmountScript = r'''
DIR=""
for d in /apex/com.android.conscrypt/cacerts /system/etc/security/cacerts; do
  if [ -d "$d" ]; then DIR="$d"; break; fi
done
if [ -n "$DIR" ] && grep -q " $DIR " /proc/mounts; then
  umount "$DIR" 2>/dev/null || umount -l "$DIR" 2>/dev/null || { echo ERR_UMOUNT; exit 1; }
fi
rm -rf /data/local/tmp/proxypin_ca
echo UNMOUNTED
''';

  static const String _rollbackScript = r'''
DIR=""
for d in /apex/com.android.conscrypt/cacerts /system/etc/security/cacerts; do
  if [ -d "$d" ]; then DIR="$d"; break; fi
done
if [ -n "$DIR" ] && [ -d /data/local/tmp/proxypin_ca ]; then
  umount "$DIR" 2>/dev/null || umount -l "$DIR" 2>/dev/null || true
fi
exit 0
''';
}

extension _StringX on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
