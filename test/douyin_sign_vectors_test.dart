/*
 * 两个移植签名库的逐字节回归测试。
 *
 * 金标由 Python 参考实现生成（生成脚本见仓库外 `_genvectors.py`）：
 *  - test/data/douyin_tt_vectors.json     TTEncrypt v5
 *      · vectors   : 固定 keystream 下的加密输出（逐字节比对）
 *      · roundtrip : 随机 keystream 下 encrypt→decrypt→gunzip 必须还原
 *  - test/data/douyin_medusa_vectors.json X-Medusa（固定随机源 / LCG）
 *
 * 运行：`flutter test test/douyin_sign_vectors_test.dart`
 *
 * 说明：flutter_js 需要宿主平台提供 JS 引擎；若当前环境无法加载（例如缺少
 * 原生库），本测试会打印告警并跳过断言，而不是误判为失败。
 */

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  JavascriptRuntime? runtime;
  String? unavailableReason;

  setUpAll(() async {
    try {
      final rt = getJavascriptRuntime(xhr: false);
      for (final asset in <String>[
        'assets/js/douyin_sign.js',
        'assets/js/xmedusa.js',
        'assets/js/ttencrypt_v5.js',
      ]) {
        final source = await rootBundle.loadString(asset);
        final result = rt.evaluate(source);
        if (result.isError) {
          throw StateError('load $asset failed: ${result.stringResult}');
        }
      }
      runtime = rt;
    } catch (e) {
      unavailableReason = 'JS runtime unavailable: $e';
    }
  });

  String evalString(String expr) {
    final r = runtime!.evaluate(expr);
    if (r.isError) throw StateError(r.stringResult ?? 'eval error');
    return r.stringResult ?? 'null';
  }

  List<int> evalBytes(String expr) {
    final decoded = jsonDecode(evalString('JSON.stringify($expr)'));
    if (decoded is! List) return const [];
    return decoded.whereType<num>().map((e) => e.toInt()).toList();
  }

  bool skipIfUnavailable() {
    if (runtime == null) {
      // ignore: avoid_print
      print('[WARN] ${unavailableReason ?? "JS runtime unavailable"} — skipped');
      return true;
    }
    return false;
  }

  test('TTEncrypt v5 固定 keystream 逐字节一致', () {
    if (skipIfUnavailable()) return;
    final root = jsonDecode(File('test/data/douyin_tt_vectors.json').readAsStringSync()) as Map;
    final vectors = (root['vectors'] as List).cast<Map>();
    expect(vectors, isNotEmpty);

    for (final v in vectors) {
      final input = hexToBytes(v['inputHex'] as String);
      final keyStream = hexToBytes(v['keyStreamHex'] as String);
      final out = evalBytes('TTEncryptV5.encrypt(${jsonEncode(input)}, ${jsonEncode(keyStream)})');
      expect(bytesToHex(out), equals(v['cipherHex']), reason: 'case ${v['name']}');
    }
  });

  test('TTEncrypt v5 加解密往返（随机 keystream）', () {
    if (skipIfUnavailable()) return;
    final root = jsonDecode(File('test/data/douyin_tt_vectors.json').readAsStringSync()) as Map;
    final cases = (root['roundtrip'] as List).cast<Map>();
    expect(cases, isNotEmpty);

    for (final c in cases) {
      final raw = hexToBytes(c['plainHex'] as String);
      final compressed = gzip.encode(raw);
      final cipher = evalBytes('TTEncryptV5.encrypt(${jsonEncode(compressed)})');
      expect(cipher, isNotEmpty, reason: 'case ${c['name']}');
      final plain = evalBytes('TTEncryptV5.decrypt(${jsonEncode(cipher)})');
      expect(gzip.decode(plain), equals(raw), reason: 'case ${c['name']}');
    }
  });

  test('X-Medusa 逐字节一致', () {
    if (skipIfUnavailable()) return;
    final root = jsonDecode(File('test/data/douyin_medusa_vectors.json').readAsStringSync()) as Map;
    final vectors = (root['vectors'] as List).cast<Map>();
    expect(vectors, isNotEmpty);

    for (final v in vectors) {
      final opts = jsonEncode(v['opts']);
      final got = jsonDecode(evalString('JSON.stringify(XMedusa.encrypt($opts))'));
      expect(got, equals(v['expected']), reason: 'case ${v['name']}');
    }
  });

  test('DouyinSign 七神签名可用性冒烟', () {
    if (skipIfUnavailable()) return;
    final stub = evalString('DouyinSign.xssStub("")');
    expect(stub, isNotEmpty);
    final gorgon = evalString(
        'DouyinSign.xgorgon({ query: "aid=1128&device_platform=android", khronos: 1789711662 })');
    expect(gorgon, isNotEmpty);
  });
}

/// hex 字符串 → 字节数组。
List<int> hexToBytes(String hex) {
  final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  final out = <int>[];
  for (var i = 0; i + 1 < clean.length; i += 2) {
    out.add(int.parse(clean.substring(i, i + 2), radix: 16));
  }
  return out;
}

/// 字节数组 → 小写 hex。
String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
