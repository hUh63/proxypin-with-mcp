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
import 'dart:io' show gzip;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';
import 'package:proxypin/network/util/logger.dart';

/// 字节系 / 抖音签名服务。
///
/// 算法以纯 JS 实现并作为 asset 打包（`assets/js/douyin_sign.js`，
/// X-Medusa 与 TTEncrypt v5 分别在 `assets/js/xmedusa.js`、
/// `assets/js/ttencrypt_v5.js`），运行期在内置 JS 引擎里执行，
/// 因此同一份实现既能被本服务调用，也能被「脚本」功能复用。
/// 所有随版本变化的常量都做了**参数化**，调用方可用 [DouyinSignParams]
/// 覆盖，无需改动算法代码即可适配新版本。
///
/// ⚠️ 算法来自公开逆向资料，默认对齐抖音 v40.5.0；官方更新后可能失效，
/// 届时调整参数或替换 JS 库即可，无需改 Dart。
class DouyinSignParams {
  final int aid;
  final String platform; // android / ios
  final String appVersion;
  final int versionCode;
  final int licenseId;

  /// Android MSSDK 版本号（默认 v4.0.5 = 67503104）
  final int mssdkVersionCodeAndroid;

  /// iOS MSSDK 版本号（默认 v04.09.00 = 67698689）
  final int mssdkVersionCodeIos;

  const DouyinSignParams({
    this.aid = 1128,
    this.platform = 'android',
    this.appVersion = '40.5.0',
    this.versionCode = 400500,
    this.licenseId = 1588093228,
    this.mssdkVersionCodeAndroid = 67503104,
    this.mssdkVersionCodeIos = 67698689,
  });
}

class DouyinSign {
  static JavascriptRuntime? _runtime;
  static Future<void>? _initFuture;
  static const String _assetPath = 'assets/js/douyin_sign.js';
  static const String _medusaAssetPath = 'assets/js/xmedusa.js';
  static const String _ttAssetPath = 'assets/js/ttencrypt_v5.js';

  /// 体积较大的库按需加载：仅在首次调用时才注入引擎。
  static bool _medusaLoaded = false;
  static bool _ttLoaded = false;

  static bool get isReady => _runtime != null;

  static Future<void> _ensure() async {
    if (_runtime != null) return;
    _initFuture ??= _load();
    await _initFuture;
  }

  static Future<void> _load() async {
    final source = await rootBundle.loadString(_assetPath);
    final rt = getJavascriptRuntime(xhr: false);
    final r = rt.evaluate(source);
    if (r.isError) {
      _initFuture = null;
      throw StateError('加载签名库失败: ${r.stringResult}');
    }
    final probe = rt.evaluate('typeof globalThis.DouyinSign');
    if (probe.stringResult != 'object' && probe.stringResult != 'function') {
      _initFuture = null;
      throw StateError('签名库未就绪');
    }
    _runtime = rt;
    logger.d('抖音签名引擎就绪');
  }

  /// 按需把一个大体积签名库注入同一引擎（幂等）。
  static Future<void> _ensureLibrary(String assetPath, String globalName, void Function() markLoaded,
      bool Function() isLoaded) async {
    await _ensure();
    if (isLoaded()) return;
    final source = await rootBundle.loadString(assetPath);
    final r = _runtime!.evaluate(source);
    if (r.isError) {
      throw StateError('加载 $globalName 失败: ${r.stringResult}');
    }
    final probe = _runtime!.evaluate('typeof globalThis.$globalName');
    if (probe.stringResult != 'object' && probe.stringResult != 'function') {
      throw StateError('$globalName 未就绪');
    }
    markLoaded();
    logger.d('$globalName 引擎就绪');
  }

  static Future<void> _ensureMedusa() =>
      _ensureLibrary(_medusaAssetPath, 'XMedusa', () => _medusaLoaded = true, () => _medusaLoaded);

  static Future<void> _ensureTt() =>
      _ensureLibrary(_ttAssetPath, 'TTEncryptV5', () => _ttLoaded = true, () => _ttLoaded);

  /// 在引擎里执行表达式并取回字符串结果。
  static Future<String> _evalString(String expr) async {
    await _ensure();
    final r = _runtime!.evaluate(expr);
    if (r.isError) {
      throw StateError(r.stringResult ?? 'JS 执行失败');
    }
    return r.stringResult ?? '';
  }

  /// 执行表达式并把结果以 JSON 取回。
  static Future<Map<String, dynamic>> _evalJson(String expr) async {
    final wrapped = 'JSON.stringify($expr)';
    final s = await _evalString(wrapped);
    if (s.isEmpty || s == 'undefined' || s == 'null') return {};
    final v = jsonDecode(s);
    return v is Map ? Map<String, dynamic>.from(v) : {};
  }

  /// 执行表达式并取回字节数组（JSON 数组往返）。
  static Future<List<int>> _evalBytes(String expr) async {
    final s = await _evalString('JSON.stringify($expr)');
    if (s.isEmpty || s == 'undefined' || s == 'null') return const [];
    final v = jsonDecode(s);
    if (v is List) return v.whereType<num>().map((e) => e.toInt()).toList();
    return const [];
  }

  /// X-SS-Stub：请求体的大写 MD5（无 body 时返回空串）。
  static Future<String> xssStub(String? body) {
    final b = jsonEncode(body ?? '');
    return _evalString('DouyinSign.xssStub($b)');
  }

  /// X-Khronos：秒级时间戳。
  static Future<int> khronos() async {
    final s = await _evalString('String(DouyinSign.khronos())');
    return int.tryParse(s) ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  /// X-Gorgon（Android 8404 变体）。
  static Future<String> xgorgon({
    required String query,
    String? body,
    int? khronos,
    int? rand,
    int? mssdkVersionCode,
  }) {
    final opts = <String, dynamic>{
      'query': query,
      if (body != null && body.isNotEmpty) 'body': body,
      if (khronos != null) 'khronos': khronos,
      if (rand != null) 'rand': rand,
      if (mssdkVersionCode != null) 'mssdkVersionCode': mssdkVersionCode,
    };
    final arg = jsonEncode(opts);
    return _evalString('DouyinSign.xgorgon($arg)');
  }

  /// X-Gorgon（iOS 变体，随机量可注入以便复现）。
  static Future<String> xgorgonIos({
    required String query,
    String? body,
    int? khronos,
    int? rand1,
    int? rand2,
    String? suffix,
  }) {
    final opts = <String, dynamic>{
      'query': query,
      if (body != null && body.isNotEmpty) 'body': body,
      if (khronos != null) 'khronos': khronos,
      if (rand1 != null) 'rand1': rand1,
      if (rand2 != null) 'rand2': rand2,
      if (suffix != null) 'suffix': suffix,
    };
    final arg = jsonEncode(opts);
    return _evalString('DouyinSign.xgorgonIos($arg)');
  }

  /// X-Helios（Android，64 位 Feistel）。
  static Future<String> helios({int? khronos, int? rand, int? aid, int? licenseId}) {
    final opts = <String, dynamic>{
      if (khronos != null) 'khronos': khronos,
      if (rand != null) 'rand': rand,
      if (aid != null) 'aid': aid,
      if (licenseId != null) 'licenseId': licenseId,
    };
    final arg = jsonEncode(opts);
    return _evalString('DouyinSign.helios($arg)');
  }

  /// X-Helios（iOS，AES-128-ECB 变体）。
  static Future<String> heliosIos({int? khronos, int? rand, int? aid, int? licenseId}) {
    final opts = <String, dynamic>{
      if (khronos != null) 'khronos': khronos,
      if (rand != null) 'rand': rand,
      if (aid != null) 'aid': aid,
      if (licenseId != null) 'licenseId': licenseId,
    };
    final arg = jsonEncode(opts);
    return _evalString('DouyinSign.heliosIos($arg)');
  }

  /// X-Bogus / a_bogus（web 端）。
  static Future<String> xBogus(String query, {String? body}) {
    final q = jsonEncode(query);
    final b = jsonEncode(body ?? '');
    return _evalString('DouyinSign.xBogus($q, $b)');
  }

  static Future<String> aBogus(String query, {String? userAgent}) {
    final q = jsonEncode(query);
    final ua = jsonEncode(userAgent ?? '');
    return _evalString('DouyinSign.aBogus($q, $ua)');
  }

  /// X-Medusa：多维环境 Protobuf 动态挑战签名（Android）。
  ///
  /// [params] 为已解析的查询参数（用于 protobuf 内的 device_id / 版本号等），
  /// [device] 为设备指纹上下文（缺省时库内使用内置默认值）。
  /// 返回 Base64 编码的 `X-Medusa` 头。
  static Future<String> xMedusa({
    required String url,
    Map<String, dynamic> params = const {},
    Map<String, dynamic>? device,
    String? body,
    int? khronos,
    String? lanusk,
  }) async {
    await _ensureMedusa();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final opts = <String, dynamic>{
      'url': url,
      'params': params,
      'khronos': khronos ?? (nowMs ~/ 1000),
      // 显式传入毫秒时间，保证库内计时字段与真实时间一致（而非 khronos*1000）。
      'nowMs': nowMs,
      if (device != null && device.isNotEmpty) 'device': device,
      if (body != null && body.isNotEmpty) 'body': body,
      if (lanusk != null && lanusk.isNotEmpty) 'lanusk': lanusk,
    };
    final arg = jsonEncode(opts);
    return _evalString('XMedusa.encrypt($arg)');
  }

  /// TTEncrypt v5：把任意明文（字符串/字节）加密为抖音
  /// `74 63 05 10 00 00` 开头的密文。内部先做 gzip（level 9, mtime 0）。
  static Future<List<int>> ttEncrypt(List<int> plain) async {
    await _ensureTt();
    final compressed = gzip.encode(plain);
    final arg = jsonEncode(compressed);
    return _evalBytes('TTEncryptV5.encrypt($arg)');
  }

  /// TTEncrypt v5 便捷入口：直接加密字符串。
  static Future<List<int>> ttEncryptString(String text) => ttEncrypt(utf8.encode(text));

  /// TTEncrypt v5 解密：返回 gzip 解压**之前**的原始字节。
  static Future<List<int>> ttDecryptRaw(List<int> cipher) async {
    await _ensureTt();
    final arg = jsonEncode(cipher);
    return _evalBytes('TTEncryptV5.decrypt($arg)');
  }

  /// TTEncrypt v5 解密：完成解密 + gzip 解压，返回明文字符串。
  static Future<String> ttDecrypt(List<int> cipher) async {
    final raw = await ttDecryptRaw(cipher);
    if (raw.isEmpty) return '';
    try {
      return utf8.decode(gzip.decode(raw));
    } catch (_) {
      return utf8.decode(raw, allowMalformed: true);
    }
  }

  /// 七神签名统一入口：一次返回 X-Khronos / X-Gorgon / X-Helios / X-Argus /
  /// X-Ladon / X-TT-Trace-Id（有 body 时含 X-SS-Stub）。
  static Future<Map<String, dynamic>> sevenGods({
    required String query,
    String? body,
    int? khronos,
    DouyinSignParams params = const DouyinSignParams(),
    int? rand,
    int? heliosRand,
    int? rand1,
    int? rand2,
    String? suffix,
  }) {
    final isAndroid = params.platform == 'android';
    final opts = <String, dynamic>{
      'query': query,
      'platform': params.platform,
      'aid': params.aid,
      'licenseId': params.licenseId,
      'mssdkVersionCode':
          isAndroid ? params.mssdkVersionCodeAndroid : params.mssdkVersionCodeIos,
      if (body != null && body.isNotEmpty) 'body': body,
      if (khronos != null) 'khronos': khronos,
      if (rand != null) 'rand': rand,
      if (heliosRand != null) 'heliosRand': heliosRand,
      if (rand1 != null) 'rand1': rand1,
      if (rand2 != null) 'rand2': rand2,
      if (suffix != null) 'suffix': suffix,
    };
    final arg = jsonEncode(opts);
    return _evalJson('DouyinSign.sevenGods($arg)');
  }

  /// 通用入口：调用签名库里任意方法（供高级用户 / 脚本桥接）。
  static Future<String> invoke(String fn, List<dynamic> args) {
    final argStr = args.map(jsonEncode).join(',');
    final name = fn.replaceAll(RegExp('[^A-Za-z0-9_]'), '');
    return _evalString('String(DouyinSign.$name($argStr))');
  }
}
