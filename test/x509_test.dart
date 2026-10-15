/*
 * X509 subject hash 单测。
 *
 * 原文件只是读 assets/certs/ca.crt、print(getSubjectHashName(...))，无断言。
 * 这里改为真断言：CA 证书可解析、subject 非空、subject hash 为稳定的 8 位
 * 十六进制（OpenSSL X509_NAME_hash 风格），纯 Dart，无网络依赖。
 */

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/util/cert/cert_data.dart';
import 'package:proxypin/network/util/cert/x509.dart';

void main() {
  late X509CertificateDataHolder holder;

  setUpAll(() async {
    final caPem = await File('assets/certs/ca.crt').readAsString();
    holder = X509CertificateDataHolder(X509Utils.x509CertificateFromPem(caPem));
  });

  test('仓库 CA 证书可解析且 subject 非空', () {
    final caRoot = holder.cert;
    expect(caRoot.subject, isNotEmpty);
    expect(caRoot.subject['2.5.4.3'], isA<String>());
    expect(caRoot.subject['2.5.4.6'], 'CN'); // C=CN
  });

  test('subject hash 为 8 位小写十六进制', () {
    final hash = X509Utils.getSubjectHashName(holder.cert.subject);
    expect(hash, matches(RegExp(r'^[0-9a-f]{8}$')));
  });

  test('subject hash 可重复计算（确定性）', () {
    final first = X509Utils.getSubjectHashName(holder.cert.subject);
    final second = X509Utils.getSubjectHashName(holder.cert.subject);
    expect(second, first);
  });

  test('不同 subject 得到不同 hash', () {
    final other = Map<String, String?>.from(holder.cert.subject);
    other['2.5.4.3'] = '${other['2.5.4.3']} (other)';
    expect(X509Utils.getSubjectHashName(other),
        isNot(X509Utils.getSubjectHashName(holder.cert.subject)));
  });
}

/// 简单持有者，避免顶层可变状态被 lint 抱怨。
class X509CertificateDataHolder {
  final X509CertificateData cert;

  X509CertificateDataHolder(this.cert);
}
