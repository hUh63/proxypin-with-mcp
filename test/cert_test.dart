/*
 * 服务器证书签发单测（仓库 CA -> 叶子证书）。
 *
 * 原文件是 @Tags(['integration']) 的“假测试”：只 print，无断言，且去读一个
 * **仓库里并不存在**的 assets/certs/server.key（必然失败）。
 *
 * 这里改为真断言，并去掉 integration 标签：整条链路只用仓库内的
 * assets/certs/ca.crt + ca_key.pem 与纯 Dart 的 pointycastle，
 * 不碰网络、不碰原生库，CI 可真跑（与 test/cert_san_test.dart 同一套 API）。
 */

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:proxypin/network/util/cert/basic_constraints.dart';
import 'package:proxypin/network/util/cert/cert_data.dart';
import 'package:proxypin/network/util/cert/extension.dart';
import 'package:proxypin/network/util/cert/key_usage.dart' as x509;
import 'package:proxypin/network/util/cert/x509.dart';
import 'package:proxypin/network/util/crypto.dart';

/// 用仓库 CA 私钥为给定公钥签发一张服务器证书（保留原用例的签发参数）。
String _generateServerCertificate(
  X509CertificateData caRoot,
  RSAPublicKey serverPubKey,
  RSAPrivateKey caPriKey,
  List<String> sans, {
  String? serialNumber,
}) {
  // 按 CA 证书 subject 动态生成目标服务器证书的 issuer / subject
  final subject = <String, String>{
    'C': 'CN',
    'ST': 'BJ',
    'L': 'Beijing',
    'O': 'Proxy',
    'OU': 'ProxyPin',
    'CN': 'ProxyPin CA (test)',
  };

  return X509Utils.generateSelfSignedCertificate(
    caRoot,
    serverPubKey,
    caPriKey,
    365,
    serialNumber: serialNumber ?? DateTime.now().microsecondsSinceEpoch.toString(),
    keyUsage: x509.ExtensionKeyUsage(x509.ExtensionKeyUsage.keyCertSign | x509.ExtensionKeyUsage.cRLSign),
    extKeyUsage: [ExtendedKeyUsage.SERVER_AUTH],
    basicConstraints: BasicConstraints(isCA: true),
    sans: sans,
    subject: subject,
  );
}

void main() {
  late X509CertificateData caRoot;
  late RSAPrivateKey caPrivateKey;
  late AsymmetricKeyPair serverKeyPair;

  setUpAll(() async {
    final caPem = await File('assets/certs/ca.crt').readAsString();
    caRoot = X509Utils.x509CertificateFromPem(caPem);

    final caKeyPem = await File('assets/certs/ca_key.pem').readAsString();
    caPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(caKeyPem);

    serverKeyPair = CryptoUtils.generateRSAKeyPair();
  });

  test('仓库 CA 证书可解析：subject / issuer 非空，有效期有序', () {
    expect(caRoot.subject, isNotEmpty);
    expect(caRoot.subject['2.5.4.3'], isA<String>());
    expect(caRoot.issuer, isNotEmpty);
    expect(caRoot.validity.notAfter.isAfter(caRoot.validity.notBefore), isTrue);
  });

  test('用 CA 私钥签发服务器证书：PEM 结构 + SAN + issuer 归属 CA', () {
    final pem = _generateServerCertificate(
      caRoot,
      serverKeyPair.publicKey as RSAPublicKey,
      caPrivateKey,
      ['127.0.0.1', 'localhost'],
    );

    expect(pem, startsWith(X509Utils.BEGIN_CERT));
    expect(pem, endsWith(X509Utils.END_CERT));

    final cert = X509Utils.x509CertificateFromPem(pem);
    expect(cert.subjectAlternativNames, containsAll(['127.0.0.1', 'localhost']));
    expect(cert.validity.notBefore.isBefore(DateTime.now()), isTrue);
    expect(cert.validity.notAfter.isAfter(DateTime.now()), isTrue);

    // issuer 的 DN 值必须来自仓库 CA 的 subject
    final caValues = caRoot.subject.values.whereType<String>().toSet();
    final issuerValues = cert.issuer.values.whereType<String>().toSet();
    expect(issuerValues.intersection(caValues), isNotEmpty,
        reason: 'issuer=$issuerValues 必须包含 CA subject 的字段：ca=$caValues');
  });

  test('serialNumber 被原样写入证书', () {
    final pem = _generateServerCertificate(
      caRoot,
      serverKeyPair.publicKey as RSAPublicKey,
      caPrivateKey,
      ['serial.example.com'],
      serialNumber: '123456',
    );

    final cert = X509Utils.x509CertificateFromPem(pem);
    expect(cert.serialNumber, BigInt.parse('123456'));
  });

  test('subject 覆盖生效：CN 为传入值而非 CA 的 CN', () {
    final pem = _generateServerCertificate(
      caRoot,
      serverKeyPair.publicKey as RSAPublicKey,
      caPrivateKey,
      ['cn.example.com'],
    );

    final cert = X509Utils.x509CertificateFromPem(pem);
    expect(cert.subject['2.5.4.3'], 'ProxyPin CA (test)');
    expect(cert.subject['2.5.4.3'], isNot(caRoot.subject['2.5.4.3']));
  });
}
