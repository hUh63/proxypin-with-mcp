/*
 * Copyright 2023 Hongen Wang All rights reserved.
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

/// 覆盖证书风险检测：已知被攻破 CA、过期、弱密钥、弱签名、自签名。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/util/cert/cert_data.dart';
import 'package:proxypin/utils/cert_risk_check.dart';

final _now = DateTime(2026, 6, 1, 12);

X509CertificateData _cert({
  Map<String, String?>? subject,
  Map<String, String?>? issuer,
  DateTime? notBefore,
  DateTime? notAfter,
  String signatureAlgorithm = 'SHA256withRSAEncryption',
  String keyAlgorithm = 'RSA',
  int? keyLength = 2048,
}) =>
    X509CertificateData(
      version: 3,
      serialNumber: BigInt.one,
      signatureAlgorithm: signatureAlgorithm,
      issuer: issuer ?? {'2.5.4.3': 'Test Intermediate CA'},
      validity: X509CertificateValidity(
        notBefore: notBefore ?? _now.subtract(const Duration(days: 10)),
        notAfter: notAfter ?? _now.add(const Duration(days: 100)),
      ),
      subject: subject ?? {'2.5.4.3': 'example.com'},
      publicKeyData: X509CertificatePublicKeyData(algorithm: keyAlgorithm, length: keyLength),
      subjectAlternativNames: const ['example.com'],
      signature: '00',
    );

void main() {
  group('CertRiskCheck.inspect', () {
    test('由 emSign 中级证书签发 -> critical', () {
      final report = CertRiskCheck.inspect(
        _cert(issuer: {'2.5.4.3': 'emSign TLS Issuing ECC CA 1', '2.5.4.10': 'eMudhra Limited'}),
        now: _now,
      );
      expect(report.level, CertRiskLevel.critical);
      expect(report.compromised, isTrue);
      expect(report.findings.any((f) => f.code == 'compromised-ca'), isTrue);
    });

    test('issuer 大小写不同也能识别', () {
      final report = CertRiskCheck.inspect(
        _cert(issuer: {'2.5.4.3': 'EMSIGN ECC CA'}),
        now: _now,
      );
      expect(report.compromised, isTrue);
    });

    test('自身是 emSign 证书（subject 命中）也算 critical', () {
      final report = CertRiskCheck.inspect(
        _cert(
          subject: {'2.5.4.3': 'emSign Root CA G3'},
          issuer: {'2.5.4.3': 'emSign Root CA G3'},
        ),
        now: _now,
      );
      expect(report.level, CertRiskLevel.critical);
    });

    test('正常证书 -> safe 且无 findings', () {
      final report = CertRiskCheck.inspect(_cert(), now: _now);
      expect(report.level, CertRiskLevel.safe);
      expect(report.findings, isEmpty);
      expect(report.compromised, isFalse);
      expect(report.issuer, contains('Test Intermediate CA'));
    });

    test('已过期 -> warning/expired', () {
      final report = CertRiskCheck.inspect(
        _cert(
          notBefore: _now.subtract(const Duration(days: 400)),
          notAfter: _now.subtract(const Duration(days: 1)),
        ),
        now: _now,
      );
      expect(report.level, CertRiskLevel.warning);
      expect(report.findings.any((f) => f.code == 'expired'), isTrue);
    });

    test('尚未生效 -> warning/not-yet-valid', () {
      final report = CertRiskCheck.inspect(
        _cert(notBefore: _now.add(const Duration(days: 2))),
        now: _now,
      );
      expect(report.findings.any((f) => f.code == 'not-yet-valid'), isTrue);
    });

    test('RSA 1024 -> weak-key；RSA 2048 不报', () {
      expect(
        CertRiskCheck.inspect(_cert(keyLength: 1024), now: _now).findings.any((f) => f.code == 'weak-key'),
        isTrue,
      );
      expect(
        CertRiskCheck.inspect(_cert(keyLength: 2048), now: _now).findings.any((f) => f.code == 'weak-key'),
        isFalse,
      );
    });

    test('SHA1 签名 -> weak-signature', () {
      final report = CertRiskCheck.inspect(_cert(signatureAlgorithm: 'SHA1withRSA'), now: _now);
      expect(report.findings.any((f) => f.code == 'weak-signature'), isTrue);
    });

    test('自签名 -> self-signed', () {
      final report = CertRiskCheck.inspect(
        _cert(
          subject: {'2.5.4.3': 'self.example.com'},
          issuer: {'2.5.4.3': 'self.example.com'},
        ),
        now: _now,
      );
      expect(report.findings.any((f) => f.code == 'self-signed'), isTrue);
    });

    test('critical 优先级高于 warning', () {
      final report = CertRiskCheck.inspect(
        _cert(
          issuer: {'2.5.4.3': 'emSign CA'},
          notAfter: _now.subtract(const Duration(days: 1)),
        ),
        now: _now,
      );
      expect(report.level, CertRiskLevel.critical);
    });
  });
}
