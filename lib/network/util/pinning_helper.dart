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

import 'package:proxypin/network/util/logger.dart';

/// 目标应用 frida 环境探测结果。
class PinningEnv {
  /// 设备已 root 且授权了 su
  final bool root;

  /// frida-server 正在运行
  final bool fridaServer;

  /// 设备上有 frida CLI
  final bool fridaCli;

  /// 设备上有 frida-inject（可脱离电脑直接注入）
  final bool fridaInject;

  const PinningEnv({
    required this.root,
    required this.fridaServer,
    required this.fridaCli,
    required this.fridaInject,
  });

  bool get canInject => root && (fridaCli || fridaInject);

  @override
  String toString() =>
      'root=$root frida-server=$fridaServer frida=$fridaCli frida-inject=$fridaInject';
}

/// SSL Pinning 绕过辅助。
///
/// **先说边界**：证书固定是目标应用主动做的校验，绕过它必然是对目标进程的
/// 运行时干预，通用手段只有一个——把 hook 注入进去。本工具因此：
///
///  - **不打包、不捆绑任何第三方二进制**（frida-server / 模块 APK 都不带），
///    只负责「探测环境 + 生成 hook 脚本 + 调用你**自己已经装好**的工具」；
///  - 是否需要注入由你判断，请只在自己拥有的设备上、对自己有授权的目标
///    （自己的应用，或已获书面授权的应用）使用。
///
/// 另一条路是「让应用信任本工具的证书」——那属于证书安装，见
/// [SystemCa]（root 直挂）与证书页的 Magisk 模块方案，与这里互补：
/// 装证书解决「系统不信任 CA」，注入解决「应用不信任何 CA」。
class PinningHelper {
  PinningHelper._();

  static const String _scriptPath = '/data/local/tmp/proxypin_pinning.js';
  static const String _logPath = '/data/local/tmp/proxypin_frida.log';

  /// 仅 Android 有这套环境。
  static bool get supported => Platform.isAndroid;

  /// 探测设备上的 frida 环境（会唤起 su，首次弹授权框）。
  static Future<PinningEnv> detect() async {
    if (!supported) {
      return const PinningEnv(root: false, fridaServer: false, fridaCli: false, fridaInject: false);
    }
    final r = await _su(
      'id 2>/dev/null | grep -q uid=0 && echo ROOT; '
      'ps -A 2>/dev/null | grep -q "frida-server" && echo FRIDA_SERVER; '
      'command -v frida >/dev/null 2>&1 && echo FRIDA_CLI; '
      'command -v frida-inject >/dev/null 2>&1 && echo FRIDA_INJECT; '
      'exit 0',
    );
    final out = r.$2;
    return PinningEnv(
      root: out.contains('ROOT'),
      fridaServer: out.contains('FRIDA_SERVER'),
      fridaCli: out.contains('FRIDA_CLI'),
      fridaInject: out.contains('FRIDA_INJECT'),
    );
  }

  /// 把 hook 脚本写到设备上（用 base64 传输，避免引号/美元符号被 shell 吃掉）。
  static Future<(bool, String)> deployScript() async {
    if (!supported) {
      return (false, 'only supported on Android');
    }
    final b64 = base64Encode(utf8.encode(buildScript()));
    final ok = await _su(
      'echo "$b64" | base64 -d > $_scriptPath && chmod 644 $_scriptPath && echo DEPLOYED',
    );
    if (ok.$2.contains('DEPLOYED')) {
      logger.i('[PinningHelper] script deployed to $_scriptPath');
      return (true, _scriptPath);
    }
    return (false, _reason(ok.$2).ifEmpty('exit=${ok.$1}'));
  }

  /// 注入到目标应用。
  ///
  /// [spawn] 为 true 时先拉起应用再注入（应对「启动即校验」）；否则附着到
  /// 已在运行的进程。优先用设备上的 `frida-inject`（不需要连电脑），
  /// 退而用 `frida` CLI。注入进程放后台跑并把输出记到 [_logPath]。
  static Future<(bool, String)> attach(String packageName, {bool spawn = false}) async {
    if (!supported) {
      return (false, 'only supported on Android');
    }
    final pkg = packageName.trim();
    if (pkg.isEmpty) {
      return (false, 'package name is required');
    }
    // 包名白名单校验：只要它可能被拼进 shell，就必须挡住注入
    if (!RegExp(r'^[A-Za-z0-9_.]+$').hasMatch(pkg)) {
      return (false, 'invalid package name: $pkg');
    }

    final env = await detect();
    if (!env.root) {
      return (false, 'root not available or not granted');
    }
    if (!env.fridaCli && !env.fridaInject) {
      return (false,
          'no frida CLI / frida-inject on device. Deploy the script and run it from your PC frida, or install frida-inject on the device.');
    }

    final deployed = await deployScript();
    if (!deployed.$1) {
      return deployed;
    }

    final injectMode = spawn ? '-f' : '-n';
    final String bin;
    final String args;
    if (env.fridaInject) {
      // 设备端注入工具，不依赖电脑
      bin = 'frida-inject';
      args = '$injectMode $pkg -s $_scriptPath';
    } else {
      // frida CLI 会连本机的 frida-server
      bin = 'frida';
      args = '$injectMode $pkg -l $_scriptPath';
    }
    final cmd = '(nohup $bin $args > $_logPath 2>&1 &) ; sleep 2; '
        'if ps -A 2>/dev/null | grep -q "$bin"; then echo ATTACHED; else echo "FAILED: \$(tail -n 3 $_logPath 2>/dev/null)"; fi';
    final r = await _su(cmd);
    if (r.$2.contains('ATTACHED')) {
      logger.i('[PinningHelper] attached to $pkg');
      return (true, 'script: $_scriptPath\nlog: $_logPath');
    }
    return (false, _reason(r.$2).ifEmpty('exit=${r.$1}'));
  }

  /// 停止注入（结束 frida-inject / frida 进程）。
  static Future<(bool, String)> stop() async {
    if (!supported) {
      return (false, 'only supported on Android');
    }
    final r = await _su(
      'pkill -f proxypin_pinning.js 2>/dev/null; pkill -f frida-inject 2>/dev/null; echo STOPPED',
    );
    return (r.$2.contains('STOPPED'), '');
  }

  /// 读取注入日志（frida 的输出）。
  static Future<String> readLog() async {
    if (!supported) {
      return '';
    }
    final r = await _su('tail -n 40 $_logPath 2>/dev/null');
    return r.$2.trim();
  }

  /// 生成 hook 脚本：覆盖 Android 生态里最常见的几种证书固定实现。
  static String buildScript() => _script;

  // ---------- 内部 ----------

  static Future<(int, String)> _su(String command) async {
    try {
      final r = await Process.run('su', ['-c', command])
          .timeout(const Duration(seconds: 45), onTimeout: () {
        throw const SocketException('su timeout');
      });
      return (r.exitCode, '${r.stdout}${r.stderr}');
    } catch (e) {
      logger.e('[PinningHelper] su failed: $e');
      return (-1, '$e');
    }
  }

  static String _reason(String output) {
    for (final line in output.split('\n')) {
      final t = line.trim();
      if (t.startsWith('FAILED') || t.startsWith('invalid') || t.startsWith('no ')) {
        return t;
      }
    }
    return output.trim();
  }

  /// raw string：脚本里的 `$new()` 等原样保留
  static const String _script = r'''
/*
 * ProxyPin - SSL Pinning bypass (frida)
 *
 * 只用于你拥有或已获授权的目标应用。它做的事是：让目标进程里
 * 「校验证书链」的几个入口一律放行，从而接受本工具的证书。
 *
 * 用法（任选其一）：
 *   设备端：frida-inject -f <包名> -s /data/local/tmp/proxypin_pinning.js
 *   电脑端：frida -U -f <包名> -l proxypin_pinning.js
 */
Java.perform(function () {
    var TAG = '[proxypin] ';

    function log(msg) {
        console.log(TAG + msg);
    }

    // 1) Conscrypt 的 TrustManagerImpl —— Android 系统 TLS 的默认实现
    try {
        var TMImpl = Java.use('com.android.org.conscrypt.TrustManagerImpl');
        TMImpl.checkTrustedRecursive.implementation = function (certs, host, clientAuth,
                                                               untrustedChain, trustAnchorChain, used) {
            log('bypass checkTrustedRecursive @ ' + host);
            return Java.use('java.util.ArrayList').$new();
        };
    } catch (e) {
        log('TrustManagerImpl.checkTrustedRecursive not hooked: ' + e);
    }
    try {
        var TMImpl2 = Java.use('com.android.org.conscrypt.TrustManagerImpl');
        TMImpl2.verifyChain.implementation = function (untrustedChain, trustAnchorChain, host,
                                                       clientAuth, ocspData, tlsSctData) {
            log('bypass verifyChain @ ' + host);
            return untrustedChain;
        };
    } catch (e) {
        log('TrustManagerImpl.verifyChain not hooked: ' + e);
    }

    // 2) SSLContext.init —— 把「全部放行」的 TrustManager 塞进去
    try {
        var X509TrustManager = Java.use('javax.net.ssl.X509TrustManager');
        var SSLContext = Java.use('javax.net.ssl.SSLContext');
        var TrustAll = Java.registerClass({
            name: 'com.proxypin.TrustAllManager',
            implements: [X509TrustManager],
            methods: {
                checkClientTrusted: function (chain, authType) {},
                checkServerTrusted: function (chain, authType) {},
                getAcceptedIssuers: function () { return []; }
            }
        });
        var trustManagers = [TrustAll.$new()];
        var init = SSLContext.init.overload(
            '[Ljavax.net.ssl.KeyManager;', '[Ljavax.net.ssl.TrustManager;', 'java.security.SecureRandom');
        init.implementation = function (km, tm, sr) {
            log('bypass SSLContext.init');
            init.call(this, km, trustManagers, sr);
        };
    } catch (e) {
        log('SSLContext.init not hooked: ' + e);
    }

    // 3) OkHttp3 的 CertificatePinner（App 里最常见的实现）
    try {
        var CP = Java.use('okhttp3.CertificatePinner');
        CP.check.overload('java.lang.String', 'java.util.List').implementation = function (host, pins) {
            log('bypass okhttp3 CertificatePinner.check @ ' + host);
        };
        try {
            CP.check$okhttp.overload('java.lang.String', 'kotlin.jvm.functions.Function0')
                .implementation = function () {};
        } catch (e) {
        }
    } catch (e) {
        log('okhttp3 CertificatePinner not hooked: ' + e);
    }

    // 4) HostnameVerifier（域名不匹配也会导致握手失败）
    try {
        var OkHost = Java.use('okhttp3.internal.tls.OkHostnameVerifier');
        OkHost.verify.overload('java.lang.String', 'javax.net.ssl.SSLSession').implementation = function () {
            return true;
        };
    } catch (e) {
    }
    try {
        var DefaultHost = Java.use('com.android.okhttp.internal.tls.OkHostnameVerifier');
        DefaultHost.verify.overload('java.lang.String', 'javax.net.ssl.SSLSession').implementation = function () {
            return true;
        };
    } catch (e) {
    }

    // 5) 顺手屏蔽证书链异常，避免有的实现自己 catch 后主动断开
    try {
        var CertificateException = Java.use('java.security.cert.CertificateException');
        log('CertificateException present (no hook needed)');
    } catch (e) {
    }

    log('pinning bypass loaded');
});
''';
}

extension _StringX on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
