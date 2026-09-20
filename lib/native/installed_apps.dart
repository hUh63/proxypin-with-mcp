import 'package:flutter/services.dart';

class InstalledApps {
  static const MethodChannel _methodChannel = MethodChannel('com.proxy/installedApps');

  /// 已安装应用列表。
  ///
  /// [withVersion] 为 true 时逐个应用查询 versionName——这是一次跨进程调用，
  /// 冷启动时可能在几百个应用上累计到数秒（上游 #783 第 2 条）。
  /// UI 并不展示版本号，所以默认不查。
  static Future<List<AppInfo>> getInstalledApps(
    bool withIcon, {
    String? packageNamePrefix,
    bool includeSystemApps = false,
    bool withVersion = false,
  }) {
    return _methodChannel.invokeListMethod<Map>('getInstalledApps', {
      "withIcon": withIcon,
      "packageNamePrefix": packageNamePrefix,
      "includeSystemApps": includeSystemApps,
      "withVersion": withVersion,
    }).then((value) => value?.map((e) => AppInfo.formJson(e)).toList() ?? []);
  }

  static Future<AppInfo> getAppInfo(String packageName) async {
    return _methodChannel
        .invokeMethod<Map>('getAppInfo', {"packageName": packageName}).then((value) => AppInfo.formJson(value!));
  }
}

class AppInfo {
  String? name;
  String? packageName;
  String? versionName;

  //icon
  Uint8List? icon;

  bool? inValid;

  AppInfo({
    this.name,
    this.packageName,
    this.versionName,
    this.icon,
    this.inValid,
  });

  AppInfo.formJson(Map<dynamic, dynamic> json) {
    name = json['name'];
    packageName = json['packageName'];
    versionName = json['versionName'];
    icon = json['icon'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['name'] = name;
    data['packageName'] = packageName;
    data['versionName'] = versionName;
    data['icon'] = icon;
    return data;
  }

  @override
  String toString() {
    return toJson().toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is AppInfo) {
      return packageName == other.packageName;
    }
    return false;
  }

  @override
  int get hashCode => packageName.hashCode;
}
