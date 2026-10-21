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

import 'package:proxypin/network/util/cert/cert_data.dart';

/// 证书风险评估等级。
enum CertRiskLevel {
  /// 未发现已知问题
  safe,

  /// 存在需要关注的问题（过期、弱签名算法、自签名…）
  warning,

  /// 命中已知被攻破 / 已被主流信任库移除的 CA
  critical,
}

/// 单条检查结论。
class CertRiskFinding {
  /// 结论代码（便于程序判断，如 compromised-ca / expired）
  final String code;

  final CertRiskLevel level;

  /// 人类可读的说明
  final String detail;

  const CertRiskFinding(this.code, this.level, this.detail);
}

/// 一次证书检查的完整结果。
class CertRiskReport {
  final List<CertRiskFinding> findings;

  /// 证书 subject（DN 里各项拼起来，便于展示）
  final String subject;

  /// 证书 issuer
  final String issuer;

  final DateTime? notBefore;
  final DateTime? notAfter;

  /// SHA-256 指纹
  final String? sha256;

  const CertRiskReport({
    required this.findings,
    required this.subject,
    required this.issuer,
    this.notBefore,
    this.notAfter,
    this.sha256,
  });

  /// 汇总等级：critical > warning > safe
  CertRiskLevel get level {
    var level = CertRiskLevel.safe;
    for (final f in findings) {
      if (f.level == CertRiskLevel.critical) return CertRiskLevel.critical;
      if (f.level == CertRiskLevel.warning) level = CertRiskLevel.warning;
    }
    return level;
  }

  /// 是否命中已知被攻破的 CA（当前指 2026-10 eMudhra / emSign 事件）
  bool get compromised => findings.any((f) => f.code == 'compromised-ca');
}

/// 证书风险检测。
///
/// 定位是**防御性检测**：告诉你「这张证书 / 这条链是不是已经不可信」，
/// 不做任何私钥推导、也不签发任何证书 —— 那些属于攻击能力。
class CertRiskCheck {
  /// 已知被攻破的 CA 名称特征（2026-10 eMudhra emSign 事件）。
  ///
  /// 该系列 8 张中间 CA 的私钥熵极低，2026-10-17 起已被 Chrome / Firefox /
  /// Apple / Microsoft 从信任库移除。任何仍由它们签发的证书都必须视为不可信。
  static const List<String> compromisedCaMarkers = ['emsign', 'emudhra'];

  /// 本次事件涉及的中间证书数量（用于提示文案）
  static const int compromisedIntermediateCount = 8;

  /// RSA 密钥位数下限（低于此值视为弱密钥）
  static const int minRsaBits = 2048;

  /// 检查一张证书。
  ///
  /// [now] 仅用于测试注入当前时间。
  static CertRiskReport inspect(X509CertificateData certificate, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final findings = <CertRiskFinding>[];

    final subject = _flatten(certificate.subject);
    final issuer = _flatten(certificate.issuer);

    // 1) 已知被攻破的 CA
    final subjectLower = subject.toLowerCase();
    final issuerLower = issuer.toLowerCase();
    for (final marker in compromisedCaMarkers) {
      if (subjectLower.contains(marker) || issuerLower.contains(marker)) {
        findings.add(CertRiskFinding(
          'compromised-ca',
          CertRiskLevel.critical,
          'Issued by a CA whose private key is known to be compromised '
              '($compromisedIntermediateCount intermediate CAs, 2026-10 eMudhra/emSign). '
              'Treat this certificate as untrusted and replace it.',
        ));
        break;
      }
    }

    // 2) 有效期
    final notAfter = certificate.validity.notAfter;
    final notBefore = certificate.validity.notBefore;
    if (notAfter.isBefore(current)) {
      findings.add(CertRiskFinding(
        'expired',
        CertRiskLevel.warning,
        'Certificate expired at ${_formatTime(notAfter)}.',
      ));
    } else if (notBefore.isAfter(current)) {
      findings.add(CertRiskFinding(
        'not-yet-valid',
        CertRiskLevel.warning,
        'Certificate is not valid before ${_formatTime(notBefore)}.',
      ));
    }

    // 3) 公钥强度
    final publicKey = certificate.publicKeyData;
    final algorithm = (publicKey.algorithm ?? '').toLowerCase();
    final keyLength = publicKey.length;
    if (keyLength != null && algorithm.contains('rsa') && keyLength < minRsaBits) {
      findings.add(CertRiskFinding(
        'weak-key',
        CertRiskLevel.warning,
        'RSA key is only $keyLength bits (recommended >= $minRsaBits).',
      ));
    }

    // 4) 弱签名算法
    final signature = (certificate.signatureAlgorithm ?? '').toLowerCase();
    if (signature.contains('md5') || signature.contains('sha1') || signature.contains('sha-1')) {
      findings.add(CertRiskFinding(
        'weak-signature',
        CertRiskLevel.warning,
        'Signed with a deprecated digest (${certificate.signatureAlgorithm}).',
      ));
    }

    // 5) 自签名（公网证书自签名 = 可疑，通常意味着中间人设备或配置错误）
    if (subject.isNotEmpty && subject == issuer) {
      findings.add(const CertRiskFinding(
        'self-signed',
        CertRiskLevel.warning,
        'Certificate is self-signed. On the public Internet this usually means '
            'an interception device or a mis-configured server.',
      ));
    }

    return CertRiskReport(
      findings: findings,
      subject: subject,
      issuer: issuer,
      notBefore: notBefore,
      notAfter: notAfter,
      sha256: certificate.sha256Thumbprint,
    );
  }

  /// 把 subject / issuer（OID -> 值）拼成可读字符串。
  static String _flatten(Map<String, String?> dn) {
    final parts = <String>[];
    dn.forEach((key, value) {
      if (value == null || value.isEmpty) return;
      parts.add('${_oidLabel(key)}=$value');
    });
    return parts.join(', ');
  }

  /// 常见 DN OID 的短名，其余原样保留。
  static String _oidLabel(String key) {
    switch (key) {
      case '2.5.4.3':
        return 'CN';
      case '2.5.4.6':
        return 'C';
      case '2.5.4.7':
        return 'L';
      case '2.5.4.8':
        return 'ST';
      case '2.5.4.10':
        return 'O';
      case '2.5.4.11':
        return 'OU';
      case '1.2.840.113549.1.9.1':
        return 'E';
      default:
        return key;
    }
  }

  static String _formatTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    final local = time.toLocal();
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
