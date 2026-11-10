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
import 'dart:convert';
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
  /// 模块是否已经装好（用户自己装过同一模块也算）。
  static Future<bool> isModuleInstalled() async {
    if (!supported) return false;
    final r = await _su('[ -d /data/adb/modules/proxypin_cert ] && echo YES || echo NO');
    return r.$2.contains('YES');
  }

  /// 装成 **Magisk / KernelSU / APatch 模块**（重启后依然有效）。
  ///
  /// 和 [mountRuntime] 的区别：[mountRuntime] 是运行时 bind 挂载，只活在内存里、
  /// 重启即失效；模块方式由模块管理器在开机早期加载，重启后依然在，是长期使用的正解。
  /// 代价是装完**要重启一次设备**。
  ///
  /// 写文件不用 `cat > file <<EOF`（su 的 shell 对 heredoc 支持不一致），
  /// 一律 base64 解码落盘：内容里带什么字符都不会被 shell 解释。
  static Future<(bool, String)> installModule() async {
    if (!supported) {
      return (false, 'only supported on Android');
    }
    final String name;
    final String certB64;
    try {
      name = await CertificateManager.systemCertificateName();
      final bytes = await (await CertificateManager.certificateFile()).readAsBytes();
      certB64 = base64Encode(bytes);
    } catch (e) {
      logger.e('[SystemCa] prepare cert failed: $e');
      return (false, 'cannot prepare certificate: $e');
    }
    final propB64 = base64Encode(utf8.encode(_moduleProp));
    final svcB64 = base64Encode(utf8.encode(_moduleServiceSh.replaceAll('__CA_NAME__', name)));
    final uniB64 = base64Encode(utf8.encode(_moduleUninstallSh));
    final script = _moduleInstallScript
        .replaceAll('__PROP_B64__', propB64)
        .replaceAll('__CERT_B64__', certB64)
        .replaceAll('__SVC_B64__', svcB64)
        .replaceAll('__UNI_B64__', uniB64)
        .replaceAll('__CA_NAME__', name);
    final r = await _su(script);
    final ok = r.$2.contains('INSTALLED');
    final reason = ok ? '' : _lastError(r.$2).ifEmpty('exit=${r.$1}');
    logger.i('[SystemCa] install module: ok=$ok $reason');
    return (ok, ok ? name : reason);
  }

  /// 卸载模块：先摘掉当前注入（立即恢复信任库），再删模块目录。
  static Future<(bool, String)> uninstallModule() async {
    if (!supported) {
      return (false, 'only supported on Android');
    }
    final r = await _su(_moduleRemoveScript);
    final ok = r.$2.contains('UNINSTALLED');
    final reason = ok ? '' : _lastError(r.$2).ifEmpty('exit=${r.$1}');
    logger.i('[SystemCa] uninstall module: ok=$ok $reason');
    return (ok, reason);
  }

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
MAIN_T=""
MAIN_STAGE=""
for t in $TARGETS; do
  k=$((k+1))
  st="$WORK/stage$k"
  mkdir -p "$st" || { FAIL="$t:ERR_STAGE"; break; }
  [ -z "$MAIN_T" ] && { MAIN_T="$t"; MAIN_STAGE="$st"; }
  # 1) 备份原目录内容（失败即中止，绝不半途开始挂载）
  # 用「文件数严格相等」判断备份是否完整。旧实现只要求 base>=1，
  # 任何一个文件复制失败（超长文件名 / 不可读 / tmp 空间不足）都会被放过，
  # 随后把「子集」bind 到系统信任库 —— 被漏掉的 CA 全部失效，大量 HTTPS
  # 握手失败，而数量校验用的是同一个 base，仍然自洽通过并报成功。
  orig=$(find "$t" -maxdepth 1 -type f 2>/dev/null | wc -l)
  cp -f "$t"/* "$st"/ 2>/dev/null
  base=$(find "$st" -maxdepth 1 -type f 2>/dev/null | wc -l)
  [ "$orig" -ge 1 ] && [ "$base" -eq "$orig" ] || { FAIL="$t:ERR_BASE"; break; }
  # 2) 放入我们的 CA，并顺带把属性对齐（root:root / 644 / 安全上下文）
  cp -f __CA_PATH__ "$st/__CA_NAME__" || { FAIL="$t:ERR_CP"; break; }
  chmod 644 "$st"/* 2>/dev/null
  chown 0:0 "$st"/* 2>/dev/null
  restorecon -R "$st" 2>/dev/null
  chcon u:object_r:system_security_cacerts_file:s0 "$st"/* 2>/dev/null
  # 3) 挂载：先 bind（语义干净），失败退 tmpfs 覆盖，再失败重试，最多 3 轮。
  #    挂之前先摘掉已有挂载：重复点「装进系统」不能叠层（叠了之后卸载要循环摘，
  #    且中间态是新旧混合的信任库）。
  n=0
  while [ "$n" -lt 5 ] && grep -q " $t " /proc/mounts 2>/dev/null; do
    umount "$t" 2>/dev/null || { umount -l "$t" 2>/dev/null; break; }
    n=$((n+1))
  done
  ok=0
  n=0
  while [ "$n" -lt 3 ]; do
    # toybox 的 mount 不认 util-linux 的 --bind（部分机型上直接静默失败），
    # 所以先试 -o bind，再退 --bind。
    if mount -o bind "$st" "$t" 2>/dev/null || mount --bind "$st" "$t" 2>/dev/null; then ok=1; break; fi
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

# 6) 补注入进程命名空间。
#    Magisk/Zygisk 的 denylist（以及部分 ROM 的 APEX 隔离）会给目标 App 独立的
#    mount namespace —— 这些进程看不到第 3 步挂的层，表现就是「证书装了但目标 App
#    仍然握手失败」。用 /proc/PID/root/<目标>/<证书名> 零 fork 预判：能看到就跳过，
#    看不到才对它的 namespace 补一次 bind（timeout 兜底，绝不阻塞）。
NS_OK=0
NS_TOTAL=0
if [ -n "$MAIN_T" ] && [ -n "$MAIN_STAGE" ]; then
  left=40
  for p in /proc/[0-9]*; do
    [ "$left" -le 0 ] && break
    [ -e "$p/root$MAIN_T" ] || continue
    NS_TOTAL=$((NS_TOTAL+1))
    if [ -e "$p/root$MAIN_T/__CA_NAME__" ]; then continue; fi
    left=$((left-1))
    pid=${p#/proc/}
    if timeout 3 nsenter --mount="$p/ns/mnt" -- mount -o bind "$MAIN_STAGE" "$MAIN_T" 2>/dev/null \
      || timeout 3 nsenter -t "$pid" -m -- mount -o bind "$MAIN_STAGE" "$MAIN_T" 2>/dev/null; then
      NS_OK=$((NS_OK+1))
    fi
  done
fi
echo "NS $NS_OK/$NS_TOTAL"
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

  /// 开机脚本（模块版）。
  ///
  /// Magisk 的 `system/` 目录覆盖能搞定 Android 13 及以下的
  /// `/system/etc/security/cacerts`；但 14+ 的信任库搬进了 Conscrypt APEX，
  /// system 覆盖碰不到，只能靠开机脚本把证书 bind 进 APEX。
  ///
  /// 下面每一条约束都是实测换来的（对标成熟系统 CA 模块的修复清单）：
  ///   1) toybox 的 mount **不认** `--bind`，必须写 `-o bind`，否则静默失败；
  ///   2) 挂载必须幂等——重复挂会叠层，之后卸载要循环摘好几层；
  ///   3) 判 `/proc/<pid>/ns/mnt` 要用 `-e` 不能用 `-d`（nsfs 节点，`-d` 恒假）；
  ///   4) Magisk denylist / Zygisk 会给目标 App 独立 mount namespace，
  ///      只在 init 的 namespace 里挂，目标 App 依然看不到 → 必须逐个补挂；
  ///      用 `/proc/<pid>/root/<目标>` 预判，能看到就跳过，省掉大部分 nsenter；
  ///   5) 合并层要做健康检查（文件数和原目录一致 + 不少于 20 张），
  ///      否则可能把信任库清空，表现是全设备 HTTPS 全部报证书错误；
  ///   6) 进任何命名空间都要 `timeout` 兜底——开机脚本卡住会拖死整个 boot。
  static const String _moduleServiceSh = r'''#!/system/bin/sh
# ProxPin CA injector (module mode)
MODDIR=${0%/*}
[ -d "$MODDIR" ] || MODDIR=/data/adb/modules/proxypin_cert
CERT=__CA_NAME__
APEX=/apex/com.android.conscrypt/cacerts
LEGACY=/system/etc/security/cacerts
WORK=/dev/proxypin_ca
LOG=/data/local/tmp/proxypin_cert.log
MIN_CERTS=20

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

# 等开机完成（最多 180s），APEX 这时候才是就绪的
c=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$c" -lt 180 ]; do
  sleep 1
  c=$((c+1))
done
log "---- start (boot_completed=${c}s, api=$(getprop ro.build.version.sdk)) ----"

[ -d "$APEX" ] || { log "no APEX dir, nothing to do"; exit 0; }

SRC=""
[ -f "$MODDIR/system/etc/security/cacerts/$CERT" ] && SRC="$MODDIR/system/etc/security/cacerts"
[ -z "$SRC" ] && [ -f "/data/misc/user/0/cacerts-added/$CERT" ] && SRC="/data/misc/user/0/cacerts-added"
[ -z "$SRC" ] && { log "cert not found: $CERT"; exit 0; }
log "cert source: $SRC/$CERT"

inject() {
  t="$1"
  [ -d "$t" ] || return 0

  # 幂等：已经挂过就先摘（最多 5 层）
  n=0
  while [ "$n" -lt 5 ] && grep -q " $t " /proc/mounts 2>/dev/null; do
    umount "$t" 2>/dev/null || { umount -l "$t" 2>/dev/null; break; }
    n=$((n+1))
  done

  rm -rf "$WORK"
  mkdir -p "$WORK" || return 1

  # 合并层 = 原目录全部文件 + 我们的证书
  orig=$(find "$t" -maxdepth 1 -type f 2>/dev/null | wc -l)
  cp -f "$t"/* "$WORK"/ 2>/dev/null
  cp -f "$SRC/$CERT" "$WORK/$CERT" || { log "copy cert failed"; return 1; }
  base=$(find "$WORK" -maxdepth 1 -type f 2>/dev/null | wc -l)
  # 健康检查：数量对不上或过少，宁可不挂（挂错的代价是全设备 HTTPS 全挂）
  if [ "$base" -ne $((orig + 1)) ] || [ "$base" -lt "$MIN_CERTS" ]; then
    log "health check failed: orig=$orig base=$base, skip $t"
    return 1
  fi
  chmod 644 "$WORK"/* 2>/dev/null
  chown 0:0 "$WORK"/* 2>/dev/null
  restorecon -R "$WORK" 2>/dev/null
  chcon u:object_r:system_security_cacerts_file:s0 "$WORK"/* 2>/dev/null
  chcon u:object_r:apex_security_cacerts_file:s0 "$WORK"/* 2>/dev/null

  # toybox 不认 --bind，先 -o bind；失败退 tmpfs 覆盖
  if mount -o bind "$WORK" "$t" 2>/dev/null || mount --bind "$WORK" "$t" 2>/dev/null; then
    log "bound -> $t"
  elif mount -t tmpfs -o mode=0755 tmpfs "$t" 2>/dev/null; then
    cp -f "$WORK"/* "$t"/ 2>/dev/null
    log "tmpfs -> $t"
  else
    log "mount failed -> $t"
    return 1
  fi
  restorecon -R "$t" 2>/dev/null
  now=$(ls -A "$t" 2>/dev/null | wc -l)
  if [ "$now" -lt "$MIN_CERTS" ]; then
    log "post-check failed: $now lt $MIN_CERTS, umount $t"
    umount "$t" 2>/dev/null || umount -l "$t" 2>/dev/null
    return 1
  fi
  [ -f "$t/$CERT" ] || { log "cert not visible after mount: $t"; return 1; }
  return 0
}

ok=0
inject "$APEX" && ok=1
for d in /apex/com.android.conscrypt@*/cacerts; do
  [ -d "$d" ] && { inject "$d" && ok=1; }
done
[ "$ok" -eq 1 ] || log "WARN: main targets not injected"

# 补注入：denylist 里的进程有独立 namespace，看不到上面挂的层。
# 只有主目标真的挂上了才补（否则会把「只有我们证书的层」挂进别的命名空间，
# 等于把那些进程的信任库清空 —— 比不生效严重得多）。
NSOK=0
NSTOTAL=0
left=40
[ "$ok" -eq 1 ] || left=0
for p in /proc/[0-9]*; do
  [ "$left" -le 0 ] && break
  [ -e "$p/root$APEX" ] || continue
  NSTOTAL=$((NSTOTAL+1))
  [ -e "$p/root$APEX/$CERT" ] && continue
  left=$((left-1))
  pid=${p#/proc/}
  if timeout 3 nsenter --mount="$p/ns/mnt" -- mount -o bind "$WORK" "$APEX" 2>/dev/null \
    || timeout 3 nsenter -t "$pid" -m -- mount -o bind "$WORK" "$APEX" 2>/dev/null; then
    NSOK=$((NSOK+1))
  fi
done
log "namespace: injected $NSOK / seen $NSTOTAL"
log "---- done ----"
exit 0
''';

  /// 模块卸载脚本：把注入层摘干净，并让模块管理器在重启后不再加载。
  static const String _moduleUninstallSh = r'''#!/system/bin/sh
LOG=/data/local/tmp/proxypin_cert.log
for d in /apex/com.android.conscrypt/cacerts /apex/com.android.conscrypt@*/cacerts; do
  [ -d "$d" ] || continue
  n=0
  while [ "$n" -lt 5 ] && grep -q " $d " /proc/mounts 2>/dev/null; do
    umount "$d" 2>/dev/null || { umount -l "$d" 2>/dev/null; break; }
    n=$((n+1))
  done
done
rm -rf /dev/proxypin_ca
echo "[$(date '+%Y-%m-%d %H:%M:%S')] uninstalled" >> "$LOG"
exit 0
''';

  static const String _moduleProp = r'''id=proxypin_cert
name=ProxPin CA Injector
version=v1.0
versionCode=1
author=ProxPin
description=Inject the ProxPin CA into the system / Conscrypt APEX trust store. Written at runtime by ProxPin; removing the module restores the original store.
minApi=21
maxApi=36
''';

  /// 装模块用的 shell：所有文件内容都是 base64，写盘时解码。
  /// `__X__` 由 Dart 侧替换（raw string 里的 `$` 全留给 shell）。
  static const String _moduleInstallScript = r'''
M=/data/adb/modules/proxypin_cert
[ -d /data/adb/modules ] || { echo ERR_NO_MODDIR; exit 1; }
mkdir -p "$M/system/etc/security/cacerts" || { echo ERR_MKDIR; exit 1; }
# 旧版本用的是 proxypin_ca（post-fs-data 时机、无健康检查），同时存在会互相打架
rm -rf /data/adb/modules/proxypin_ca
if echo aGk= | base64 -d >/dev/null 2>&1; then B64D="base64 -d"; else B64D="base64 -D"; fi
echo '__PROP_B64__' | $B64D > "$M/module.prop" 2>/dev/null || { echo ERR_PROP; exit 1; }
echo '__CERT_B64__' | $B64D > "$M/system/etc/security/cacerts/__CA_NAME__" 2>/dev/null || { echo ERR_CERT; exit 1; }
echo '__SVC_B64__' | $B64D > "$M/service.sh" 2>/dev/null || { echo ERR_SVC; exit 1; }
echo '__UNI_B64__' | $B64D > "$M/uninstall.sh" 2>/dev/null || { echo ERR_UNI; exit 1; }
chmod 644 "$M/module.prop" "$M/system/etc/security/cacerts/__CA_NAME__" 2>/dev/null
chmod 755 "$M/service.sh" "$M/uninstall.sh" 2>/dev/null
chown -R 0:0 "$M" 2>/dev/null
# 之前点过「移除/停用」的话要清掉这两个标记，否则新装的模块开机不加载
rm -f "$M/remove" "$M/disable"
[ -f "$M/module.prop" ] && [ -f "$M/system/etc/security/cacerts/__CA_NAME__" ] || { echo ERR_VERIFY; exit 1; }
echo INSTALLED
''';

  /// 卸模块用的 shell：先跑模块自带的 uninstall.sh 摘掉注入层，再删目录。
  static const String _moduleRemoveScript = r'''
for M in /data/adb/modules/proxypin_cert /data/adb/modules/proxypin_ca; do
  if [ -f "$M/uninstall.sh" ]; then sh "$M/uninstall.sh" >/dev/null 2>&1; fi
  rm -rf "$M"
done
for d in /apex/com.android.conscrypt/cacerts /apex/com.android.conscrypt@*/cacerts; do
  [ -d "$d" ] || continue
  n=0
  while [ "$n" -lt 5 ] && grep -q " $d " /proc/mounts 2>/dev/null; do
    umount "$d" 2>/dev/null || { umount -l "$d" 2>/dev/null; break; }
    n=$((n+1))
  done
done
[ -d /data/adb/modules/proxypin_cert ] && { echo ERR_RM; exit 1; }
echo UNINSTALLED
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
