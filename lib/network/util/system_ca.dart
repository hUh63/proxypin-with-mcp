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
/// 先说清和 Magisk 方案的分工。证书页上那个「一键自动安装到系统」走的是
/// **Magisk 模块**（`/data/adb/modules/proxypin_ca` + `post-fs-data.sh`），
/// 这条路对主流设备最稳——开机时由模块挂载，zygote 起来之前就已生效，
/// 且重启后依然在。但它有个前提：设备装了 Magisk / KernelSU / APatch
/// （得有 `/data/adb/modules`），否则只会在 UI 上报「未检测到」然后失败。
///
/// 这里补的正是这个缺口：**没有模块管理器、但有 root** 的设备。
/// 做法是运行时把证书绑进系统信任库目录。代价是**重启后失效**，
/// 换来的是：不往任何持久分区写东西（可逆），也不必重启设备
/// （装完重启一下目标应用即可，需要的话还能重启 zygote 让所有应用立刻感知）。
///
/// 兼容性（对标成熟系统 CA 模块的做法）：
///  1. **多目标**：Android 14+ 的信任库在 APEX（`/apex/com.android.conscrypt/cacerts`，
///     部分机型实际挂在带版本号的分支 `/apex/com.android.conscrypt@<版本>/cacerts`），
///     Android 13 及以下在 `/system/etc/security/cacerts`。这里会**枚举全部存在且
///     尚未挂载的目录逐个处理**，不再只挑第一个——只挂一个时，读另一个目录的应用
///     仍然看不到证书（表现为"装了个寂寞"）。
///  2. **两种挂法**：优先 `mount --bind`（绑一个内容已备好的临时层，语义最干净），
///     失败再退到 `mount -t tmpfs` 覆盖 + 回填内容；都失败则重试，最多 3 轮。
///  3. **SELinux**：先 `restorecon`，再依次尝试 `system_security_cacerts_file` /
///     `apex_security_cacerts_file` 两种上下文，尽量贴近目标目录原有的安全标签。
///  4. **严格校验 + 全量回滚**：每个目录挂载后都要清点证书数量（原有 + 1）；
///    任何一个目录失败，就把**本次已经挂上的全部**摘下，绝不把设备留在
///    信任库残缺（= 全设备 HTTPS 失败）的状态。
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

  /// 是否已经处于「直挂」状态（任一候选目录被覆盖挂载）。
  static Future<bool> isMounted() async {
    if (!supported) {
      return false;
    }
    final r = await _su(_isMountedScript);
    return r.$2.contains('YES');
  }

  /// 运行时把 CA 直挂进系统信任库。返回 (是否成功, 说明)。
  ///
  /// 成功时说明是本次挂上的目录列表；失败时说明是失败原因（含 ERR_ 码）。
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
    // 「MOUNTED 」后面跟着本次真正挂上的目录列表；列表为空说明一个都没挂成，不能算成功。
    final mounted = _after(r.$2, 'MOUNTED ');
    final ok = mounted.isNotEmpty;
    if (ok) {
      logger.i('[SystemCa] mounted runtime CA: $name -> $mounted');
      return (true, mounted);
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

  /// 执行 root 命令：返回 (exitCode, 合并输出)。
  ///
  /// su 首次会弹授权框，等太久会让 UI 空转，所以加超时。
  static Future<(int, String)> _su(String command) async {
    try {
      final r = await Process.run('su', ['-c', command])
          .timeout(const Duration(seconds: 90), onTimeout: () {
        throw const SocketException('su timeout');
      });
      return (r.exitCode, '${r.stdout}${r.stderr}');
    } catch (e) {
      // 设备未 root / 无 su 属常见情况，非应用错误，降级为 WARNING。
      logger.w('[SystemCa] su unavailable (device not rooted?): $e');
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

  /// 取 `PREFIX` 之后到行尾的内容。
  static String _after(String output, String prefix) {
    for (final line in output.split('\n')) {
      final t = line.trim();
      if (t.startsWith(prefix)) {
        return t.substring(prefix.length).trim();
      }
    }
    return '';
  }

  /// raw string：这里的 $ 全部留给 shell 解释
  static const String _mountScript = r'''
WORK=/data/local/tmp/proxypin_ca
[ "$(id -u)" = "0" ] || { echo ERR_NOT_ROOT; exit 1; }

TARGETS=""
collect() {
  [ -d "$1" ] || return 0
  case " $TARGETS " in *" $1 "*) return 0 ;; esac
  TARGETS="$TARGETS $1"
  return 0
}
collect /apex/com.android.conscrypt/cacerts
for d in /apex/com.android.conscrypt@*/cacerts; do collect "$d"; done
collect /system/etc/security/cacerts
[ -n "$TARGETS" ] || { echo ERR_NO_DIR; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK" || { echo ERR_WORKDIR; exit 1; }

DONE_LIST=""
FAIL=""
k=0
for t in $TARGETS; do
  k=$((k+1))
  st="$WORK/stage$k"
  mkdir -p "$st" || { FAIL="$t:ERR_STAGE"; break; }
  # 1) 备份原目录内容（失败即中止，绝不半途开始挂载）
  cp -f "$t"/* "$st"/ 2>/dev/null
  base=$(ls -A "$st" 2>/dev/null | wc -l)
  [ "$base" -ge 1 ] || { FAIL="$t:ERR_BASE"; break; }
  # 2) 放入我们的 CA，并顺带把属性对齐（root:root / 644 / 安全上下文）
  cp -f __CA_PATH__ "$st/__CA_NAME__" || { FAIL="$t:ERR_CP"; break; }
  chmod 644 "$st"/* 2>/dev/null
  chown 0:0 "$st"/* 2>/dev/null
  restorecon -R "$st" 2>/dev/null
  chcon u:object_r:system_security_cacerts_file:s0 "$st"/* 2>/dev/null
  # 3) 挂载：先 bind（语义干净），失败退 tmpfs 覆盖，再失败重试，最多 3 轮
  ok=0
  n=0
  while [ "$n" -lt 3 ]; do
    if mount --bind "$st" "$t" 2>/dev/null; then ok=1; break; fi
    if mount -t tmpfs -o mode=0755 tmpfs "$t" 2>/dev/null; then
      cp -f "$st"/* "$t"/ 2>/dev/null && ok=1 && break
      umount "$t" 2>/dev/null
    fi
    n=$((n+1))
    sleep 1
  done
  [ "$ok" -eq 1 ] || { FAIL="$t:ERR_MOUNT"; break; }
  # 4) 挂上后再对齐一次上下文与属性（部分机型会在挂载后重置）
  restorecon -R "$t" 2>/dev/null
  chmod 644 "$t"/* 2>/dev/null
  chown 0:0 "$t"/* 2>/dev/null
  chcon u:object_r:system_security_cacerts_file:s0 "$t"/* 2>/dev/null \
    || chcon u:object_r:apex_security_cacerts_file:s0 "$t"/* 2>/dev/null
  # 5) 校验：数量必须是「原有 + 1」，否则视为不完整
  now=$(ls -A "$t" 2>/dev/null | wc -l)
  [ "$now" -ge $((base + 1)) ] || { umount "$t" 2>/dev/null || umount -l "$t" 2>/dev/null; FAIL="$t:ERR_VERIFY"; break; }
  DONE_LIST="$DONE_LIST$t "
done

if [ -n "$FAIL" ]; then
  # 全量回滚：本次挂上的全部摘下，绝不留下半残的信任库
  for t in $DONE_LIST; do
    umount "$t" 2>/dev/null || umount -l "$t" 2>/dev/null
  done
  rm -rf "$WORK"
  echo "ERR_ROLLBACK $FAIL"
  exit 1
fi

echo "MOUNTED $DONE_LIST"
''';

  static const String _unmountScript = r'''
WORK=/data/local/tmp/proxypin_ca
for d in /apex/com.android.conscrypt/cacerts /apex/com.android.conscrypt@*/cacerts /system/etc/security/cacerts; do
  [ -d "$d" ] || continue
  # 重复挂载会叠层，循环摘干净（最多 5 层，够用且不会死循环）
  n=0
  while [ "$n" -lt 5 ] && grep -q " $d " /proc/mounts 2>/dev/null; do
    umount "$d" 2>/dev/null || { umount -l "$d" 2>/dev/null; break; }
    n=$((n+1))
  done
done
rm -rf "$WORK"
echo UNMOUNTED
''';

  static const String _isMountedScript = r'''
for d in /apex/com.android.conscrypt/cacerts /apex/com.android.conscrypt@*/cacerts /system/etc/security/cacerts; do
  [ -d "$d" ] || continue
  if grep -q " $d " /proc/mounts 2>/dev/null; then echo YES; exit 0; fi
done
echo NO
''';

  static const String _rollbackScript = r'''
WORK=/data/local/tmp/proxypin_ca
for d in /apex/com.android.conscrypt/cacerts /apex/com.android.conscrypt@*/cacerts /system/etc/security/cacerts; do
  [ -d "$d" ] || continue
  n=0
  while [ "$n" -lt 5 ] && grep -q " $d " /proc/mounts 2>/dev/null; do
    umount "$d" 2>/dev/null || { umount -l "$d" 2>/dev/null; break; }
    n=$((n+1))
  done
done
rm -rf "$WORK"
exit 0
''';
}

extension _StringX on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
