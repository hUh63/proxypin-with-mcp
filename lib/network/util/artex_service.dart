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

// ARTEX 本地服务管理（Termux 原生环境）。
//
// ARTEX 是跑在 Termux 里的 Go 二进制（`$HOME/artex-bin/artex`），数据在
// `$HOME/artex-bin/data`，PG 数据目录 `$HOME/pgdata`。本 App 与 Termux 是不同
// uid，所以要动它只能走 root：`su <termux用户> -c '<命令>'`。
//
// 三条实测纪律（踩过，别改）：
//   1. 环境变量三件套必须带：PATH / HOME / LD_PRELOAD（少了 LD_PRELOAD 会
//      在 bionic 上直接崩）；
//   2. 启动顺序 PG → ARTEX（ARTEX 启动即连 PG，连不上会降级/退出）；
//   3. `ARTEX_TRUST_LOOPBACK=1` 让本机回环免 token，本 App 才能免登录直连。
//
// 非 Android 平台（桌面）不支持：ARTEX 只跑在 Termux 里，桌面端连远程实例即可。

import 'dart:async';
import 'dart:io';

import 'package:proxypin/network/util/logger.dart';

/// 一次 shell 操作的结果。
class ArtexServiceResult {
  final bool ok;
  final String output;

  const ArtexServiceResult(this.ok, this.output);

  ArtexServiceResult copyWith({bool? ok, String? output}) =>
      ArtexServiceResult(ok ?? this.ok, output ?? this.output);

  @override
  String toString() => output;
}

/// 本地运行状态快照。
class ArtexServiceStatus {
  final bool rooted;
  final bool processAlive;
  final bool pgAlive;
  final String pid;
  final String termuxUser;
  final String detail;

  const ArtexServiceStatus({
    required this.rooted,
    required this.processAlive,
    required this.pgAlive,
    required this.pid,
    required this.termuxUser,
    required this.detail,
  });

  static const ArtexServiceStatus unknown = ArtexServiceStatus(
    rooted: false,
    processAlive: false,
    pgAlive: false,
    pid: '',
    termuxUser: '',
    detail: '',
  );
}

class ArtexService {
  /// Termux 的默认 uid（多数机器上就是这个，探测失败时的兜底）。
  static const String defaultTermuxUser = 'u0_a353';

  static const String _termuxData = '/data/data/com.termux';
  static const String _home = '/data/data/com.termux/files/home';
  static const String _bin = '/data/data/com.termux/files/usr/bin';
  static const String _lib = '/data/data/com.termux/files/usr/lib';

  /// 所有命令共用的环境前缀（照抄实测命令，勿删改顺序）。
  static const String envPrefix =
      'export PATH=$_bin:\$PATH; export HOME=$_home; '
      'export LD_PRELOAD=$_lib/libandroid-shmem.so;';

  static bool get supported => Platform.isAndroid;

  /// 执行 root 命令，返回 (exitCode, 合并输出)。
  ///
  /// `su` 首次会弹授权框，等太久会让 UI 空转，所以加超时；失败不抛异常，
  /// 让调用方把输出直接展示出来（未 root 是很常见的正常状态）。
  static Future<(int, String)> _sh(String command,
      {Duration timeout = const Duration(seconds: 60)}) async {
    if (!supported) {
      return (-1, 'only supported on Android');
    }
    try {
      final r = await Process.run('su', ['-c', command]).timeout(
        timeout,
        onTimeout: () => throw TimeoutException('su timeout'),
      );
      final out = '${r.stdout}${r.stderr}'.trim();
      return (r.exitCode, out);
    } catch (e) {
      logger.w('[ArtexService] su failed: $e');
      return (-1, '$e');
    }
  }

  /// 以 Termux 用户身份执行（带环境三件套）。
  static Future<ArtexServiceResult> asTermux(String user, String command,
      {Duration timeout = const Duration(seconds: 60)}) async {
    final u = user.trim().isEmpty ? defaultTermuxUser : user.trim();
    final escaped = command.replaceAll("'", "'\\''");
    final (code, out) = await _sh("su $u -c '$envPrefix $escaped'", timeout: timeout);
    return ArtexServiceResult(code == 0, out);
  }

  /// 探测 Termux 的 uid：`ls -ld /data/data/com.termux` 的 owner 就是它。
  ///
  /// 探测不到（没装 Termux / 无 root）时返回空串，由界面提示用户手填。
  static Future<String> detectTermuxUser() async {
    final (code, out) = await _sh('ls -ld $_termuxData 2>/dev/null', timeout: const Duration(seconds: 20));
    if (code != 0) return '';
    // 形如：drwx------ 5 u0_a353 u0_a353 4096 ...
    final parts = out.split(RegExp(r'\s+'));
    for (final p in parts) {
      if (RegExp(r'^u\d+_a\d+$').hasMatch(p)) return p;
    }
    return '';
  }

  /// 是否已 root（`id -u` 返回 0）。
  static Future<bool> hasRoot() async {
    if (!supported) return false;
    final (code, out) = await _sh('id -u', timeout: const Duration(seconds: 15));
    return code == 0 && out.trim() == '0';
  }

  static Future<ArtexServiceResult> startPg(String user) {
    return asTermux(
      user,
      'pg_ctl -D \$HOME/pgdata -l \$HOME/pg.log start 2>&1 || echo PG_ALREADY_OR_FAILED',
    );
  }

  static Future<ArtexServiceResult> stopPg(String user) {
    return asTermux(user, 'pg_ctl -D \$HOME/pgdata -m fast stop 2>&1 || true');
  }

  /// 启 ARTEX（命令与 SKILL.md 实测版本逐字一致）。
  static Future<ArtexServiceResult> startArtex(
    String user, {
    String addr = '127.0.0.1:8787',
    String proxy = '127.0.0.1:8788',
    String pgDsn = 'postgres://postgres@127.0.0.1:5432/artex?sslmode=disable',
  }) {
    final cmd = 'export ARTEX_PG_DSN="$pgDsn"; export ARTEX_TRUST_LOOPBACK=1; '
        'cd \$HOME/artex-bin && '
        'nohup ./artex -addr $addr -proxy $proxy > \$HOME/artex.log 2>&1 & echo PID=\$!';
    final r = asTermux(user, cmd, timeout: const Duration(seconds: 45));
    return r;
  }

  static Future<ArtexServiceResult> stopArtex(String user) {
    return asTermux(
      user,
      'pkill -f "artex-bin/artex" 2>/dev/null; sleep 1; '
      'if pgrep -f "artex-bin/artex" >/dev/null 2>&1; then echo STILL_RUNNING; else echo STOPPED; fi',
      timeout: const Duration(seconds: 30),
    );
  }

  /// 进程状态（进程 + PG）。
  static Future<ArtexServiceStatus> status(String user) async {
    if (!supported) return ArtexServiceStatus.unknown;
    final rooted = await hasRoot();
    final u = user.trim().isEmpty ? defaultTermuxUser : user.trim();
    final cmd = 'echo "ROOT=\$(id -u)"; '
        'echo "PID=\$(pgrep -f artex-bin/artex 2>/dev/null | head -n1)"; '
        'echo "ARTC=\$(pgrep -c -f artex-bin/artex 2>/dev/null)"; '
        'echo "PGC=\$(pgrep -c -f postgres 2>/dev/null)"; '

    final r = await asTermux(u, cmd, timeout: const Duration(seconds: 25));
    String pick(String key) {
      for (final line in r.output.split('\n')) {
        final t = line.trim();
        if (t.startsWith('$key=')) return t.substring(key.length + 1).trim();
      }
      return '';
    }

    final pid = pick('PID');
    final artc = int.tryParse(pick('ARTC')) ?? 0;
    final pgc = int.tryParse(pick('PGC')) ?? 0;
    return ArtexServiceStatus(
      rooted: rooted,
      processAlive: artc > 0,
      pgAlive: pgc > 0,
      pid: pid,
      termuxUser: u,
      detail: r.output,
    );
  }

  /// 读 ARTEX 的运行日志（用于「本地运行」面板的日志尾巴）。
  static Future<ArtexServiceResult> tailLog(String user, {int lines = 80}) {
    final n = lines.clamp(10, 2000);
    return asTermux(
      user,
      'tail -n $n \$HOME/artex.log 2>/dev/null || echo "NO_LOG_FILE"',
      timeout: const Duration(seconds: 25),
    );
  }

  /// 清空运行日志（重启前收一下，免得尾巴全是历史）。
  static Future<ArtexServiceResult> clearLog(String user) {
    return asTermux(user, ': > \$HOME/artex.log && echo CLEARED');
  }
}
