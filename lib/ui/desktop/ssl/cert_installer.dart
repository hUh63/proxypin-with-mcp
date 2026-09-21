import 'dart:io';
import 'package:proxypin/network/util/cert/cert_data.dart';
import 'package:proxypin/network/util/logger.dart';

class CertInstaller {
  static Future<bool> installCertificate(File certFile) async {
    try {
      if (Platform.isMacOS) {
        // 使用 security add-trusted-cert 安装证书到登录钥匙串并设为信任根
        final result = await Process.run('security', [
          'add-trusted-cert',
          '-r',
          'trustRoot',
          '-k',
          '${Platform.environment['HOME']}/Library/Keychains/login.keychain-db',
          certFile.path,
        ]);
        logger.d('security add-trusted-cert result: \\${result.stdout} \\${result.stderr}');
        return result.exitCode == 0;
      }

      if (Platform.isWindows) {
        // Windows: 使用 certutil 命令行安装证书到根证书存储区
        final result = await Process.run('certutil', [
          '-addstore',
          '-user',
          'Root',
          certFile.path,
        ]);
        logger.d('certutil addstore result: \\${result.stdout} \\${result.stderr}');
        return result.exitCode == 0;
      }

      if (Platform.isLinux) {
        // 上游 #661：Linux 上普通用户写不进系统信任库，
        // 旧实现直接 copy，权限不足就静默失败（用户只看到“安装失败”）。
        return _installOnLinux(certFile);
      }

      // 其他平台已预留，可通过平台通道扩展
      return false;
    } catch (e) {
      logger.e('Failed to install certificate: $e');
      return false;
    }
  }

  /// Linux 证书安装（上游 #661）：分三步，尽量让普通用户也能装上。
  ///
  /// 1) 直接写系统信任库（以 root 运行时可用）；
  /// 2) 失败则用 pkexec 提权（桌面环境会弹出图形授权框）；
  /// 3) 再失败则装进用户级 NSS 库 ~/.pki/nssdb（Chrome/Chromium 实际信任的是它，
  ///    需要 libnss3-tools 提供 certutil）。
  /// 三步都失败会写明原因，不再静默返回 false。
  static Future<bool> _installOnLinux(File certFile) async {
    final last = certFile.uri.pathSegments.last;
    final certName = last.endsWith('.crt') ? last : '$last.crt';
    final destPath = '/usr/local/share/ca-certificates/$certName';

    // 1) 直接写系统信任库
    try {
      await certFile.copy(destPath);
      final result = await Process.run('update-ca-certificates', []);
      logger.d('update-ca-certificates: ${result.stdout} ${result.stderr}');
      if (result.exitCode == 0) return true;
    } catch (e) {
      logger.d('write system ca store failed (need root?), trying pkexec: $e');
    }

    // 2) pkexec 提权（图形授权）
    try {
      final res = await Process.run('pkexec', [
        'sh',
        '-c',
        'cp "\$1" "\$2" && update-ca-certificates',
        'sh',
        certFile.path,
        destPath,
      ]);
      logger.d('pkexec install ca: ${res.stdout} ${res.stderr}');
      if (res.exitCode == 0) return true;
    } catch (e) {
      logger.d('pkexec install ca failed: $e');
    }

    // 3) 用户级 NSS 信任库（Chrome/Chromium）
    try {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        final db = '$home/.pki/nssdb';
        await Directory(db).create(recursive: true);
        for (final tool in ['certutil', 'nsscertutil']) {
          try {
            final add = await Process.run(tool, [
              '-d',
              'sql:$db',
              '-A',
              '-t',
              'C,,',
              '-n',
              'ProxyPin',
              '-i',
              certFile.path,
            ]);
            logger.d('$tool add user ca: ${add.stdout} ${add.stderr}');
            if (add.exitCode == 0) return true;
          } on ProcessException {
            continue; // 工具不存在，试下一个
          }
        }
      }
    } catch (e) {
      logger.d('install ca to user nss db failed: $e');
    }

    logger.w('install ca on linux failed: need root, or install libnss3-tools for user-level trust');
    return false;
  }

  /// 检查证书是否已安装
  static Future<bool> isCertInstalled(File filePath, X509CertificateData caCert) async {
    String commonName = caCert.subject['2.5.4.3'] ?? 'ProxyPin CA';
    String? sha1 = caCert.sha1Thumbprint;
    logger.d('Checking if certificate is installed: CN=$commonName, SHA1=$sha1');
    try {
      if (Platform.isWindows) {
        List<String> args = ['-user', '-store', 'root'];
        if (sha1 != null) {
          args.add(sha1);
        }
        var res = await Process.run('certutil', args);
        return res.stdout.toString().toLowerCase().contains(commonName.toLowerCase());
      } else if (Platform.isMacOS) {
        var res = await Process.run('security', ['find-certificate', '-c', commonName]);

        if ((res.stdout as String).isNotEmpty) {
          // check if trusted
          var trustRes = await Process.run('security', ['verify-cert', '-c', filePath.path]);

          logger.d('security verify-cert $commonName result: ${trustRes.stdout} ${trustRes.stderr}');
          return (trustRes.stdout as String).contains('certificate verification successful');
        }
        return false;
      } else if (Platform.isLinux) {
        // 只检查 /usr/local/share/ca-certificates/ 下是否有对应证书文件
        final certName = filePath.uri.pathSegments.last.endsWith('.crt')
            ? filePath.uri.pathSegments.last
            : '${filePath.uri.pathSegments.last}.crt';

        var paths = [
          '/usr/local/share/ca-certificates/$certName',
          '/etc/ssl/certs/$certName',
        ];
        for (var p in paths) {
          if (await File(p).exists()) return true;
        }
        // 上游 #661：普通用户装的是用户级 NSS 库，这里一并检查
        final home = Platform.environment['HOME'];
        if (home != null && home.isNotEmpty) {
          try {
            final res = await Process.run('certutil', ['-d', 'sql:$home/.pki/nssdb', '-L']);
            if (res.exitCode == 0 && '${res.stdout}'.contains(commonName)) return true;
          } catch (_) {}
        }
        return false;
      }
    } catch (_) {}
    return false;
  }
}
