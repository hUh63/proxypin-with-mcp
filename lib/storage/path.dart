import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:proxypin/utils/platform.dart';

class Paths {
  static String? _homePath;
  static final Map<String, File> _cache = {};

  /// 便携模式标记文件名（放在可执行文件同目录即启用）
  static const List<String> portableMarkers = ['portable', 'portable.txt'];

  /// 便携模式下的数据目录名（位于可执行文件同目录）
  static const String portableDataDir = 'proxypin_data';

  /// 数据根目录。
  ///
  /// 上游 #285 便携版：桌面端若可执行文件同目录存在 `portable` / `portable.txt`
  /// 标记文件，则全部数据（配置、证书、脚本、历史等）写入程序目录下的
  /// `proxypin_data`，整目录拷走即可携带全部设置与证书；否则仍使用系统
  /// 应用支持目录。
  static Future<String> homePath() async {
    if (_homePath != null) return _homePath!;

    _homePath = await _resolveHomePath();
    return _homePath!;
  }

  /// 是否处于便携模式（供 UI 展示）
  static Future<bool> isPortable() async {
    if (!Platforms.isDesktop()) return false;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      for (final marker in portableMarkers) {
        if (await File('${exeDir.path}${Platform.pathSeparator}$marker').exists()) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  static Future<String> _resolveHomePath() async {
    if (Platforms.isDesktop()) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent;
        for (final marker in portableMarkers) {
          final markerFile = File('${exeDir.path}${Platform.pathSeparator}$marker');
          if (await markerFile.exists()) {
            final dataDir = Directory('${exeDir.path}${Platform.pathSeparator}$portableDataDir');
            if (!await dataDir.exists()) {
              await dataDir.create(recursive: true);
            }
            return dataDir.path;
          }
        }
      } catch (_) {
        // 便携探测失败时回退到系统目录，不影响正常使用
      }
    }
    return getApplicationSupportDirectory().then((it) => it.path);
  }

  //获取配置路径
  static Future<File> getPath(String fileName) async {
    if (_cache.containsKey(fileName)) {
      return _cache[fileName]!;
    }

    final home = await homePath();
    var file = File('$home${Platform.pathSeparator}$fileName');

    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    _cache[fileName] = file;
    return file;
  }

  static Future<File> createFile(String dir, String filename) async {
    final home = await homePath();
    var file = File('$home${Platform.pathSeparator}$dir${Platform.pathSeparator}$filename');
    return file.create(recursive: true);
  }
}
