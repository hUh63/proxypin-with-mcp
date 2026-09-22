/*
 * Windows 接管增强（上游 #577：无法代理 Sandboxie 内软件流量）
 *
 * 背景：Windows 上仅设置 WinINET 系统代理（HKCU\...\Internet Settings）时，以下流量不会走代理：
 *   - 自带网络栈的桌面应用（如微信）
 *   - 使用 WinHTTP 的服务/组件
 *   - CLI 工具（curl / git / node / 包管理器 / 容器）
 *   - Sandboxie 沙箱内程序
 * 完整的 TUN 全局接管需要内核级虚拟网卡（WinTun 驱动）+ 用户态 TCP/IP 协议栈（Clash 那种），
 * 属于原生/驱动级工程，且必须驱动签名，纯 Dart 无法安全落地（误加路由会直接断网）。
 *
 * 因此本版提供**分层增强接管**（安全、纯 Dart、可回滚）：
 *   1. WinINET 系统代理（由 SystemProxy 负责）
 *   2. WinHTTP 代理（netsh winhttp set proxy）——覆盖使用 WinHTTP 的服务与部分应用
 *   3. 用户环境变量 HTTP_PROXY / HTTPS_PROXY / ALL_PROXY（含小写）——覆盖 curl/git/node/容器等
 * 并检测 Sandboxie / 管理员权限 / wintun.dll，供界面提示与后续升级。
 *
 * 说明：对"自行直连"的应用（含沙箱内自带网络栈的程序）环境变量仍不生效，这类场景需要真正的
 * TUN 接管（见 docs/features_tips.md「Windows 全局接管（上游 #577）」）。
 */
import 'dart:io';

import 'package:proxypin/network/util/logger.dart';

/// Windows 接管环境检测结果
class WindowsTakeoverStatus {
  final bool isWindows;
  final bool isAdmin;
  final bool sandboxieInstalled;
  final bool wintunPresent;

  const WindowsTakeoverStatus({
    required this.isWindows,
    required this.isAdmin,
    required this.sandboxieInstalled,
    required this.wintunPresent,
  });
}

/// 分层接管应用结果
class WindowsTakeoverResult {
  final bool winHttp;
  final bool envVars;
  final String? message;

  const WindowsTakeoverResult({required this.winHttp, required this.envVars, this.message});

  bool get anySuccess => winHttp || envVars;
}

class WindowsTakeover {
  WindowsTakeover._();

  /// 需要设置/清理的代理环境变量（大小写各一份，兼容不同工具链）
  static const List<String> _proxyEnvNames = [
    'HTTP_PROXY',
    'HTTPS_PROXY',
    'ALL_PROXY',
    'http_proxy',
    'https_proxy',
    'all_proxy',
  ];

  /// 检测运行环境：是否管理员、是否安装 Sandboxie、是否具备 wintun.dll
  static Future<WindowsTakeoverStatus> detect() async {
    if (!Platform.isWindows) {
      return const WindowsTakeoverStatus(
          isWindows: false, isAdmin: false, sandboxieInstalled: false, wintunPresent: false);
    }

    return WindowsTakeoverStatus(
      isWindows: true,
      isAdmin: await isAdmin(),
      sandboxieInstalled: await _isSandboxieInstalled(),
      wintunPresent: _isWintunPresent(),
    );
  }

  /// 是否以管理员身份运行（`net session` 仅管理员可执行成功）
  static Future<bool> isAdmin() async {
    if (!Platform.isWindows) return false;
    try {
      final r = await Process.run('net', ['session'], runInShell: false);
      return r.exitCode == 0;
    } catch (e) {
      logger.w('WindowsTakeover.isAdmin failed', error: e);
      return false;
    }
  }

  static Future<bool> _isSandboxieInstalled() async {
    final pf = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final pf86 = Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
    final candidates = [
      '$pf\\Sandboxie-Plus\\Start.exe',
      '$pf\\Sandboxie-Plus\\SbieCtrl.exe',
      '$pf\\Sandboxie\\Start.exe',
      '$pf86\\Sandboxie-Plus\\Start.exe',
      '$pf86\\Sandboxie\\Start.exe',
    ];
    for (final p in candidates) {
      try {
        if (await File(p).exists()) return true;
      } catch (_) {}
    }
    return false;
  }

  static bool _isWintunPresent() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      if (File('$exeDir\\wintun.dll').existsSync()) return true;
      final windir = Platform.environment['WINDIR'] ?? r'C:\Windows';
      return File('$windir\\System32\\wintun.dll').existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 应用分层增强接管：WinHTTP 代理 + 用户环境变量
  static Future<WindowsTakeoverResult> enableLayered(String host, int port) async {
    if (!Platform.isWindows) {
      return const WindowsTakeoverResult(winHttp: false, envVars: false, message: 'not windows');
    }
    final addr = '$host:$port';

    // WinHTTP：需要管理员权限
    bool winHttpOk = false;
    String? message;
    try {
      final r = await Process.run('netsh', ['winhttp', 'set', 'proxy', addr], runInShell: false);
      winHttpOk = r.exitCode == 0;
      if (!winHttpOk) {
        message = 'WinHTTP 设置失败（通常需要管理员权限）：${(r.stderr ?? '').toString().trim()}';
      }
    } catch (e) {
      message = 'WinHTTP 设置异常：$e';
      logger.w('netsh winhttp set proxy failed', error: e);
    }

    // 用户环境变量：无需管理员
    bool envOk = false;
    try {
      for (final name in _proxyEnvNames) {
        await Process.run('setx', [name, 'http://$addr'], runInShell: false);
      }
      envOk = true;
    } catch (e) {
      logger.w('setx proxy env failed', error: e);
    }

    return WindowsTakeoverResult(winHttp: winHttpOk, envVars: envOk, message: message);
  }

  /// 启动自愈（上游 #886 的延伸）：清掉上次异常退出残留的 WinHTTP 代理与代理环境变量。
  ///
  /// 为什么需要：`netsh winhttp set proxy` 是**系统级**设置，`setx` 写的是用户级环境变量——
  /// 两者都不会因为我们被强杀而自动消失。它们指向已经没人监听的 127.0.0.1:<本应用端口> 时，
  /// 用户会表现为"网页打不开 / git、curl 全都连不上"。
  ///
  /// 只在"指向 127.0.0.1 且端口正好是本应用端口"时清理，避免误伤用户自己配的其它代理。
  static Future<void> repairStaleLayered(int port) async {
    if (!Platform.isWindows) return;

    final needle = '127.0.0.1:$port';
    final localhostNeedle = 'localhost:$port';

    // 1) WinHTTP
    try {
      final r = await Process.run('netsh', ['winhttp', 'show', 'proxy'], runInShell: false);
      final out = '${r.stdout}${r.stderr}';
      if (r.exitCode == 0 && (out.contains(needle) || out.contains(localhostNeedle))) {
        await Process.run('netsh', ['winhttp', 'reset', 'proxy'], runInShell: false);
        logger.i('检测到残留的 WinHTTP 代理（指向本应用端口 $port），已重置');
      }
    } catch (e) {
      logger.w('WinHTTP 残留检查失败', error: e);
    }

    // 2) 代理环境变量（用 reg 读用户级，当前进程环境可能还没继承到）
    for (final name in _proxyEnvNames) {
      try {
        final value = await _userEnvValue(name);
        if (value == null || value.isEmpty) continue;
        if (!value.contains(needle) && !value.contains(localhostNeedle)) continue;
        await Process.run('setx', [name, ''], runInShell: false);
        logger.i('检测到残留的代理环境变量 $name=$value，已清空');
      } catch (e) {
        logger.w('代理环境变量残留检查失败', error: e);
      }
    }
  }

  /// 读用户级环境变量（HKCU\Environment）
  static Future<String?> _userEnvValue(String name) async {
    try {
      final r = await Process.run(
          'reg', ['query', r'HKCU\Environment', '/v', name], runInShell: false);
      if (r.exitCode != 0) return null;
      final match = RegExp('$name\\s+REG_[A-Z_]+\\s+(.*)').firstMatch('${r.stdout}');
      return match?.group(1)?.trim();
    } catch (_) {
      return null;
    }
  }

  /// 还原：重置 WinHTTP 代理并清空代理环境变量
  static Future<void> disableLayered() async {
    if (!Platform.isWindows) return;
    try {
      await Process.run('netsh', ['winhttp', 'reset', 'proxy'], runInShell: false);
    } catch (e) {
      logger.w('netsh winhttp reset proxy failed', error: e);
    }
    try {
      for (final name in _proxyEnvNames) {
        await Process.run('setx', [name, ''], runInShell: false);
      }
    } catch (e) {
      logger.w('clear proxy env failed', error: e);
    }
  }
}
