import 'dart:io';

import 'package:flutter/services.dart';
import 'package:proxypin/storage/path.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:path_provider/path_provider.dart';

class FileRead {
  static String? userHome;

  static Future<File> homeDir() async {
    if (userHome != null) {
      return File("${userHome!}${Platform.pathSeparator}.proxypin");
    }
    if (Platforms.isDesktop()) {
      // 便携模式（上游 #285）：程序目录存在 portable 标记时，配置随程序目录存放
      if (await Paths.isPortable()) {
        userHome = await Paths.homePath();
      } else {
        userHome = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      }
    } else {
      userHome = (await getApplicationSupportDirectory()).path;
    }

    var separator = Platform.pathSeparator;
    return File("${userHome!}$separator.proxypin");
  }

  static Future<String> readAsString(String file) async {
    return rootBundle.loadString(file);
    // return File(file).readAsString();
  }

  static Future<Uint8List> read(String file) async {
    return rootBundle.load(file).then((bateData) => bateData.buffer.asUint8List());
    // return File(file).readAsBytes();
  }

  static String? _uuid;

  static Future<String> get iosUuid async {
    if (_uuid == null) {
      var applicationPath = (await getApplicationSupportDirectory()).path;
      var uuidPattern = RegExp(r'/Application/([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})/');
      var match = uuidPattern.firstMatch(applicationPath);

      _uuid = match?.group(1);
    }
    return _uuid!;
  }

  static Future<Uint8List> readFile(String path) async {
    if (Platform.isIOS) {
      var uuid = await iosUuid;
      //ios替换uuid
      var uuidPattern = RegExp(r'/Application/[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/');
      path = path.replaceAll(uuidPattern, '/Application/$uuid/');
    }

    return File(path).readAsBytes();
  }
}
