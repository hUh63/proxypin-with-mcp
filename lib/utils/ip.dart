import 'dart:io';

String? ip;

/// 获取本机ip (en0 or WLAN)优先
Future<String> localIp({bool readCache = true}) async {
  if (!readCache) {
    ip = null;
    ipList = null;
    _ipListTime = null;
  }
  ip ??= await localAddress().then((value) => value.address);
  return ip!;
}

Future<InternetAddress> localAddress() async {
  return await NetworkInterface.list(type: InternetAddressType.IPv4).then((
    interfaces,
  ) {
    interfaces.sort((a, b) {
      return weight(a) - weight(b);
    });
    // 兜底：无可用网卡时返回回环地址，避免 StateError: No element
    for (var interface in interfaces) {
      if (interface.addresses.isNotEmpty) {
        return interface.addresses.first;
      }
    }
    return InternetAddress.loopbackIPv4;
  });
}

List<String>? ipList;
DateTime? _ipListTime;

/// 获取本机所有ip
/// 带 30 秒 TTL 缓存：网络切换（WiFi/VPN）后自动刷新，避免误判本机请求
Future<List<String>> localIps({bool readCache = true}) async {
  if (readCache &&
      ipList != null &&
      _ipListTime != null &&
      DateTime.now().difference(_ipListTime!) < const Duration(seconds: 30)) {
    return ipList!;
  }

  var list = await NetworkInterface.list(type: InternetAddressType.IPv4);
  list.sort((a, b) {
    return weight(a) - weight(b);
  });

  ipList = [];
  for (var element in list) {
    if (element.addresses.isEmpty) continue;
    var address = element.addresses.first.address;
    if (!ipList!.contains(address)) {
      ipList!.add(address);
    }
  }
  _ipListTime = DateTime.now();
  return ipList!;
}

Future<String> networkName() {
  return NetworkInterface.list(type: InternetAddressType.IPv4).then((
    interfaces,
  ) {
    interfaces.sort((a, b) {
      return weight(a) - weight(b);
    });
    return interfaces.first.name;
  });
}

// en0(macos系统) or WLAN(widows设备名)优先
int weight(NetworkInterface it) {
  if (it.name.toUpperCase().startsWith('WLAN')) {
    return -10;
  }
  if (it.name == 'en0') {
    return -1;
  }
  if (it.name.startsWith('ccmn')) {
    return 0;
  }
  return 1;
}
