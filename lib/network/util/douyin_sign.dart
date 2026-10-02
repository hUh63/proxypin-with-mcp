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

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';
import 'package:proxypin/network/util/logger.dart';

/// 字节系 / 抖音签名服务。
///
/// 算法以纯 JS 实现并作为 asset 打包（`assets/js/douyin_sign.js`），
/// 运行期在内置 JS 引擎里执行，因此同一份实现既能被本服务调用，
/// 也能被「脚本」功能复用。所有随版本变化的常量都做了**参数化**，
/// 调用方可用 [DouyinSignParams] 覆盖，无需改动算法代码即可适配新版本。
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
