/*
 * PKCS#12 生成 / 解析往返单测。
 *
 * 原文件硬编码了 `C:\Users\wanghongen\Downloads\*.p12`：文件不存在直接 return，
 * 等于永远空跑（且该路径在非 Windows 上毫无意义）。
 *
 * 这里改为平台无关的**自包含往返测试**：临时生成 RSA 密钥对 + 由仓库 CA
 * 签发的证书 -> Pkcs12.generatePkcs12 -> Pkcs12.parsePkcs12，
 * 断言返回结构与 CertificateManager.importPkcs12 的契约一致（[0]=私钥，[1]=证书），
 * 且证书 subject / serial、私钥模数与输入一致。
 * 纯 Dart（pointycastle），无网络 / 原生库，CI 可真跑。
 */

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:proxypin/network/util/cert/cert_data.dart';
import 'package:proxypin/network/util/cert/pkcs12.dart';
import 'package:proxypin/network/util/cert/x509.dart';
import 'package:proxypin/network/util/crypto.dart';

/// 生成一张「由仓库 CA 签发」的服务器证书 PEM。
String _issueCert(X509CertificateData caRoot, RSAPublicKey leafPub, RSAPrivateKey caPri, String cn) {
  return X509Utils.generateSelfSignedCertificate(
    caRoot,
    leafPub,
    caPri,
    365,
    serialNumber: '42',
    sans: [cn],
    subject: {'C': 'CN', 'O': 'ProxyPin', 'CN': cn},
  );
}

void main() {
  late X509CertificateData caRoot;
  late RSAPrivateKey caPrivateKey;
  late AsymmetricKeyPair leafKeyPair;
  late String leafCertPem;
  late String leafKeyPem;

  setUpAll(() async {
    caRoot = X509Utils.x509CertificateFromPem(await File('assets/certs/ca.crt').readAsString());
    caPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(await File('assets/certs/ca_key.pem').readAsString());

    leafKeyPair = CryptoUtils.generateRSAKeyPair();
    leafCertPem = _issueCert(caRoot, leafKeyPair.publicKey as RSAPublicKey, caPrivateKey, 'pkcs12.example.com');
    leafKeyPem = CryptoUtils.encodeRSAPrivateKeyToPem(leafKeyPair.privateKey as RSAPrivateKey);
  });

  test('生成 PKCS#12 产出合法 DER（SEQUENCE 开头）且非空', () {
    final bytes = Pkcs12.generatePkcs12(leafKeyPem, [leafCertPem], password: '123');

    expect(bytes, isA<Uint8List>());
    expect(bytes, isNotEmpty);
    expect(bytes[0], 0x30, reason: 'PKCS#12 顶层应为 ASN.1 SEQUENCE');
  });

  test('generatePkcs12 -> parsePkcs12 往返：返回 [私钥, 证书]（importPkcs12 契约）', () {
    final bytes = Pkcs12.generatePkcs12(leafKeyPem, [leafCertPem], password: '123');
    final pems = Pkcs12.parsePkcs12(bytes, password: '123');

    expect(pems, isNotEmpty);
    expect(pems.length, 2, reason: 'importPkcs12 依赖 [0]=私钥 [1]=证书：$pems');
    expect(pems[0], contains('BEGIN PRIVATE KEY'));
    expect(pems[1], contains('BEGIN CERTIFICATE'));
  });

  test('解析出的证书与原始证书 subject / serial 一致', () {
    final bytes = Pkcs12.generatePkcs12(leafKeyPem, [leafCertPem], password: '123');
    final pems = Pkcs12.parsePkcs12(bytes, password: '123');

    final parsed = X509Utils.x509CertificateFromPem(pems[1]);
    final original = X509Utils.x509CertificateFromPem(leafCertPem);

    expect(parsed.subject, equals(original.subject));
    expect(parsed.serialNumber, original.serialNumber);
    expect(parsed.serialNumber, BigInt.parse('42'));
  });

  test('解析出的私钥可用（能把 PKCS#8 还原成 RSA 私钥）', () {
    final bytes = Pkcs12.generatePkcs12(leafKeyPem, [leafCertPem], password: '123');
    final pems = Pkcs12.parsePkcs12(bytes, password: '123');

    final key = CryptoUtils.rsaPrivateKeyFromPem(pems[0]);
    expect(key.modulus, (leafKeyPair.privateKey as RSAPrivateKey).modulus);
  });
}
