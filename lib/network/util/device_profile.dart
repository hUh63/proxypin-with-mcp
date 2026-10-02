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

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 字节系 / 抖音 Android 设备指纹生成器。
///
/// 按机型模板合成一份**内部自洽**的设备指纹（标识 + 硬件 + 系统 + 应用元数据），
/// 用于构造请求环境、比对抓包参数。机型模板取自公开资料，字段保持一致；
/// 如平台方调整字段，可在此扩展模板而不影响调用方。
class DeviceProfile {
  /// 机型模板（字段名与线上请求参数保持一致）
  static const Map<String, Map<String, dynamic>> templates = {
    'xiaomi_14': {
      'device_brand': 'Xiaomi',
      'device_manufacturer': 'Xiaomi',
      'device_model': 'Xiaomi 14',
      'device_type': '23127PN0CC',
      'hardware': 'qcom',
      'cpu_abi': 'arm64-v8a',
      'resolution': '1200*2670',
      'density_dpi': 460,
      'dpi': 460,
      'display_density': 'xxhdpi',
      'os_version': '14',
      'os_api': 34,
      'rom': 'hyperos',
      'rom_version': 'OS1.0.32.0.UNCCNXM',
      'build_serial': 'unknown',
      'build_display': 'UKQ1.230804.001',
      'release_build': 'UKQ1.230804.001_1701234567',
    },
    'xiaomi_13': {
      'device_brand': 'Xiaomi',
      'device_manufacturer': 'Xiaomi',
      'device_model': 'Xiaomi 13',
      'device_type': '2211133C',
      'hardware': 'qcom',
      'cpu_abi': 'arm64-v8a',
      'resolution': '1080*2400',
      'density_dpi': 440,
      'dpi': 440,
      'display_density': 'xxhdpi',
      'os_version': '13',
      'os_api': 33,
      'rom': 'miui',
      'rom_version': 'V14.0.27.0.TMBCNXM',
      'build_serial': 'unknown',
      'build_display': 'TKQ1.221114.001',
      'release_build': 'TKQ1.221114.001_1678901234',
    },
    'huawei_mate60': {
      'device_brand': 'HUAWEI',
      'device_manufacturer': 'HUAWEI',
      'device_model': 'ALN-AL00',
      'device_type': 'HUAWEI Mate 60 Pro',
      'hardware': 'kirin9000s',
      'cpu_abi': 'arm64-v8a',
      'resolution': '1260*2720',
      'density_dpi': 480,
      'dpi': 480,
      'display_density': 'xxhdpi',
      'os_version': '12',
      'os_api': 31,
      'rom': 'harmonyos',
      'rom_version': 'HarmonyOS 4.0.0.138',
      'build_serial': 'unknown',
      'build_display': 'ALN-AL00 4.0.0.138(SP1C00E135R4P9)',
      'release_build': 'ALN-AL00_1693456789',
    },
    'huawei_p60': {
      'device_brand': 'HUAWEI',
      'device_manufacturer': 'HUAWEI',
      'device_model': 'MNA-AL00',
      'device_type': 'HUAWEI P60 Pro',
      'hardware': 'qcom',
      'cpu_abi': 'arm64-v8a',
      'resolution': '1220*2700',
      'density_dpi': 480,
      'dpi': 480,
      'display_density': 'xxhdpi',
      'os_version': '12',
      'os_api': 31,
      'rom': 'harmonyos',
      'rom_version': 'HarmonyOS 3.1.0.170',
      'build_serial': 'unknown',
      'build_display': 'MNA-AL00 3.1.0.170(C00E170R3P11)',
      'release_build': 'MNA-AL00_1681234567',
    },
    'honor_magic6': {
      'device_brand': 'HONOR',
      'device_manufacturer': 'HONOR',
      'device_model': 'BVL-AN16',
      'device_type': 'HONOR Magic 6 Pro',
      'hardware': 'qcom',
      'cpu_abi': 'arm64-v8a',
      'resolution': '1280*2800',
      'density_dpi': 480,
      'dpi': 480,
      'display_density': 'xxhdpi',
      'os_version': '14',
      'os_api': 34,
      'rom': 'magicos',
      'rom_version': 'MagicOS 8.0.0.125',
      'build_serial': 'unknown',
      'build_display': 'BVL-AN16 8.0.0.125(C00E120R4P7)',
      'release_build': 'BVL-AN16_1705678901',
    },
    'oppo_find_x7': {
      'device_brand': 'OPPO',
      'device_manufacturer': 'OPPO',
      'device_model': 'PHZ110',
      'device_type': 'OPPO Find X7',
      'hardware': 'mt6989',
      'cpu_abi': 'arm64-v8a',
      'resolution': '1264*2780',
      'density_dpi': 480,
      'dpi': 480,
      'display_density': 'xxhdpi',
      'os_version': '14',
      'os_api': 34,
      'rom': 'coloros',
      'rom_version': 'ColorOS 14.0.0.301',
      'build_serial': 'unknown',
      'build_display': 'PHZ110_14.0.0.301(CN01)',
      'release_build': 'PHZ110_1704567890',
    },
    'vivo_x100': {
      'device_brand': 'vivo',
      'device_manufacturer': 'vivo',
      'device_model': 'V2309A',
      'device_type': 'vivo X100',
      'hardware': 'mt6989',
      'cpu_abi': 'arm64-v8a',
      'resolution': '1260*2800',
      'density_dpi': 480,
      'dpi': 480,
      'display_density': 'xxhdpi',
      'os_version': '14',
      'os_api': 34,
      'rom': 'originos',
      'rom_version': 'OriginOS 4',
      'build_serial': 'unknown',
      'build_display': 'PD2309A_A_14.0.12.1.W10.V000L1',
      'release_build': 'V2309A_1701234567',
    },
    'pixel_8': {
      'device_brand': 'google',
      'device_manufacturer': 'Google',
      'device_model': 'Pixel 8 Pro',
      'device_type': 'Pixel 8 Pro',
      'hardware': 'husky',
      'cpu_abi': 'arm64-v8a',
      'resolution': '1344*2992',
      'density_dpi': 489,
      'dpi': 489,
      'display_density': 'xxhdpi',
      'os_version': '14',
      'os_api': 34,
      'rom': 'google',
      'rom_version': 'UD1A.230803.041',
      'build_serial': 'unknown',
      'build_display': 'UD1A.230803.041',
      'release_build': 'UD1A.230803.041_1698765432',
    },
    'samsung_s24': {
      'device_brand': 'samsung',
      'device_manufacturer': 'samsung',
      'device_model': 'SM-S9280',
      'device_type': 'Galaxy S24 Ultra',
      'hardware': 'qcom',
      'cpu_abi': 'arm64-v8a',
      'resolution': '1440*3120',
      'density_dpi': 505,
      'dpi': 505,
      'display_density': 'xxxhdpi',
      'os_version': '14',
      'os_api': 34,
      'rom': 'OneUI',
      'rom_version': 'UP1A.231005.007.S9280ZCU1AXB3',
      'build_serial': 'unknown',
      'build_display': 'UP1A.231005.007',
      'release_build': 'UP1A.231005.007_1707000000',
    },
    'oneplus_12': {
      'device_brand': 'OnePlus',
      'device_manufacturer': 'OnePlus',
      'device_model': 'PJD110',
      'device_type': 'OnePlus 12',
      'hardware': 'qcom',
      'cpu_abi': 'arm64-v8a',
      'resolution': '1440*3168',
      'density_dpi': 510,
      'dpi': 510,
      'display_density': 'xxxhdpi',
      'os_version': '14',
      'os_api': 34,
      'rom': 'coloros',
      'rom_version': 'ColorOS 14.0.0.405',
      'build_serial': 'unknown',
      'build_display': 'PJD110_14.0.0.405(CN01)',
      'release_build': 'PJD110_1703456789',
    },
  };

  /// 抖音 v40 应用元数据
  static const Map<String, dynamic> appConfig = {
    'aid': 1128,
    'app_name': 'aweme',
    'display_name': '抖音',
    'package': 'com.ss.android.ugc.aweme',
    'appkey': '57bfa27c67e58e7d923328d3',
    'version_name': '40.5.0',
    'version_code': 400500,
    'update_version_code': 40509900,
    'manifest_version_code': 400501,
    'channel': 'huawei_1128_64',
    'sig_hash': 'aea615ab910015038f73c47e45d21466',
    'sdk_version': '3.7.3-rc.116-douyin',
    'language': 'zh',
    'region': 'CN',
    'tz_name': 'Asia/Shanghai',
    'tz_offset': 28800,
    'carrier': '中国移动',
    'mcc_mnc': '46000',
  };

  static List<String> models() => templates.keys.toList();

  static String _uuid(Random r) {
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static String _randHex(Random r, int n) {
    const h = '0123456789abcdef';
    return List<String>.generate(n, (_) => h[r.nextInt(16)]).join();
  }

  /// 生成一份自洽的设备指纹（键顺序与线上参数一致）。
  static Map<String, String> generate(String modelKey) {
    final t = templates[modelKey] ?? templates['huawei_mate60']!;
    final r = Random.secure();

    final cdid = _uuid(r);
    final clientudid = _uuid(r);
    final openudid =
        md5.convert(utf8.encode('${cdid}_${100000 + r.nextInt(900000)}')).toString().substring(0, 16);
    final googleAid = _uuid(r);
    final mac = List<int>.generate(6, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
    final serialNumber = _randHex(r, 8);
    final udid = List<String>.generate(15, (_) => '${r.nextInt(10)}').join();

    final rawRes = (t['resolution'] as String);
    final parts = rawRes.split('*');
    final w = parts.isNotEmpty ? parts[0] : '1080';
    final h = parts.length > 1 ? parts[1] : '2400';

    final osVersion = '${t['os_version']}';
    final ua = 'Mozilla/5.0 (Linux; Android $osVersion; ${t['device_type']} '
        'Build/${t['build_display']}; wv) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Version/4.0 Chrome/120.0.0.0 Mobile Safari/537.36';

    return <String, String>{
      'openudid': openudid,
      'clientudid': clientudid,
      'cdid': cdid,
      'req_id': _uuid(r),
      'google_aid': googleAid,
      'udid': udid,
      'serial_number': serialNumber,
      'build_serial': '${t['build_serial']}',
      'mac_address': mac,
      'device_brand': '${t['device_brand']}'.toLowerCase(),
      'device_manufacturer': '${t['device_manufacturer']}',
      'device_model': '${t['device_model']}',
      'device_type': '${t['device_type']}',
      'device_category': 'phone',
      'device_platform': 'android',
      'hardware': '${t['hardware']}',
      'cpu_abi': '${t['cpu_abi']}',
      'resolution': '${h}x$w',
      'query_resolution': '${w}*$h',
      'density_dpi': '${t['density_dpi']}',
      'dpi': '${t['dpi']}',
      'display_density': '${t['display_density']}',
      'os': 'Android',
      'os_version': osVersion,
      'os_api': '${t['os_api']}',
      'rom': '${t['rom']}',
      'rom_version': '${t['rom_version']}',
      'build_display': '${t['build_display']}',
      'release_build': '${t['release_build']}',
      'aid': '${appConfig['aid']}',
      'app_name': '${appConfig['app_name']}',
      'package': '${appConfig['package']}',
      'appkey': '${appConfig['appkey']}',
      'version_name': '${appConfig['version_name']}',
      'version_code': '${appConfig['version_code']}',
      'update_version_code': '${appConfig['update_version_code']}',
      'manifest_version_code': '${appConfig['manifest_version_code']}',
      'channel': '${appConfig['channel']}',
      'sig_hash': '${appConfig['sig_hash']}',
      'sdk_version': '${appConfig['sdk_version']}',
      'language': '${appConfig['language']}',
      'region': '${appConfig['region']}',
      'tz_name': '${appConfig['tz_name']}',
      'tz_offset': '${appConfig['tz_offset']}',
      'carrier': '${appConfig['carrier']}',
      'mcc_mnc': '${appConfig['mcc_mnc']}',
      'access': 'wifi',
      'web_ua': ua,
    };
  }

  /// 生成可用于查询串的 `k=v` 文本。
  static String toQueryString(Map<String, String> p) =>
      p.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
}
