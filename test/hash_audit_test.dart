import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/hash_audit.dart';

void main() {
  group('识别', () {
    test('常见 hex 长度', () {
      expect(HashAudit.parseLine('5f4dcc3b5aa765d61d8327deb882cf99')!.kind, HashKind.md5);
      expect(HashAudit.parseLine('5baa61e4c9b93f3f0682250b6cf8331b7ee68fd8')!.kind, HashKind.sha1);
      expect(
          HashAudit.parseLine(
                  '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8')!
              .kind,
          HashKind.sha256);
      expect(
          HashAudit.parseLine(
                  'b109f3bbbc244eb82441917ed06d618b9008dd09b3befd1b5e07394c706a8bb980b1d7785e5976ec049b46df5f1326af5a2ea6d103fd07c95385ffab0cacbc86')!
              .kind,
          HashKind.sha512);
    });

    test('带前缀的框架格式', () {
      expect(HashAudit.parseLine('{SHA}W6ph5Mm5Pz8GgiULbPgzG37mj9g=')!.kind, HashKind.sha1Base64);
      expect(HashAudit.parseLine(r'$SHA512$abc')!.kind, HashKind.sha512Raw);
      expect(HashAudit.parseLine(r'$SHA512$zzz'), isNull); // 非 hex，识别不出
      expect(HashAudit.parseLine(r'$6$salt$hash')!.kind, HashKind.sha512Crypt);
      expect(HashAudit.parseLine(r'$1$salt$hash')!.kind, HashKind.md5Crypt);
      expect(HashAudit.parseLine(r'$apr1$salt$hash')!.kind, HashKind.apr1);
      expect(HashAudit.parseLine(r'$2a$05$abcdefghijklmnopqrstuv')!.kind, HashKind.bcrypt);
    });

    test('user:hash 与 pwdump', () {
      final a = HashAudit.parseLine('alice:5f4dcc3b5aa765d61d8327deb882cf99')!;
      expect(a.user, 'alice');
      expect(a.kind, HashKind.md5);

      final b = HashAudit.parseLine(
          'bob:1000:0893955f62e600b7aad3b435b51404ee:f83c01861fdd23b4354465fe6d7f6402:::')!;
      expect(b.user, 'bob');
      expect(b.kind, HashKind.ntlm);
      expect(b.digest, 'f83c01861fdd23b4354465fe6d7f6402');
    });

    test('无法识别的行返回 null', () {
      expect(HashAudit.parseLine('hello world'), isNull);
      expect(HashAudit.parseLine(''), isNull);
      expect(HashAudit.parseLine('#comment'), isNull);
    });

    test('parseAll 去重并保持顺序', () {
      final list = HashAudit.parseAll(
          '5f4dcc3b5aa765d61d8327deb882cf99\n5f4dcc3b5aa765d61d8327deb882cf99\n'
          '5baa61e4c9b93f3f0682250b6cf8331b7ee68fd8');
      expect(list.length, 2);
      expect(list.first.kind, HashKind.md5);
      expect(list.last.kind, HashKind.sha1);
    });
  });

  group('校验', () {
    HashTarget t(String hash) => HashAudit.parseLine(hash)!;

    test('MD5 / SHA1 / SHA256 / SHA512', () {
      expect(HashAudit.verify(t('5f4dcc3b5aa765d61d8327deb882cf99'), 'password'), isTrue);
      expect(HashAudit.verify(t('5f4dcc3b5aa765d61d8327deb882cf99'), 'passworD'), isFalse);
      expect(HashAudit.verify(t('5baa61e4c9b93f3f0682250b6cf8331b7ee68fd8'), 'password'), isTrue);
      expect(
          HashAudit.verify(
              t('5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8'), 'password'),
          isTrue);
      expect(
          HashAudit.verify(
              t('b109f3bbbc244eb82441917ed06d618b9008dd09b3befd1b5e07394c706a8bb980b1d7785e5976ec049b46df5f1326af5a2ea6d103fd07c95385ffab0cacbc86'),
              'password'),
          isTrue);
    });

    test('大写 hex 也能匹配', () {
      expect(HashAudit.verify(t('5F4DCC3B5AA765D61D8327DEB882CF99'), 'password'), isTrue);
    });

    test('空口令', () {
      expect(HashAudit.verify(t('d41d8cd98f00b204e9800998ecf8427e'), ''), isTrue);
    });

    test('NTLM', () {
      // MD4(UTF-16LE("password"))
      expect(HashAudit.ntlm('password'), '8846f7eaee8fb117ad06bdd830b7586c');
      expect(HashAudit.verify(t('8846f7eaee8fb117ad06bdd830b7586c'), 'password'), isTrue);
    });

    test('{SHA} 与 {SSHA}', () {
      expect(HashAudit.verify(t('{SHA}W6ph5Mm5Pz8GgiULbPgzG37mj9g='), 'password'), isTrue);
      // base64(sha1("password" + "NaCl") + "NaCl")
      expect(HashAudit.verify(t('{SSHA}QCdIktL+AaarHg+95cIrgxLRB4BOYUNs'), 'password'), isTrue);
      expect(HashAudit.verify(t('{SSHA}QCdIktL+AaarHg+95cIrgxLRB4BOYUNs'), 'passwordx'), isFalse);
    });

    test('不可恢复的类型一律 false（不给出错误的「已破解」）', () {
      for (final hash in [r'$6$salt$hash', r'$1$salt$hash', r'$apr1$salt$hash']) {
        final target = HashAudit.parseLine(hash);
        if (target == null) continue;
        expect(HashAudit.verify(target, 'password'), isFalse);
        expect(target.kind.recoverable, isFalse);
      }
    });
  });

  group('掩码与规则', () {
    test('掩码字符集', () {
      expect(HashAudit.maskToCharset('?d?d')!.length, 20); // 两段各 10
      expect(HashAudit.maskToCharset('?l')!.length, 26);
      expect(HashAudit.maskToCharset('a?d')!.length, 11);
      expect(HashAudit.maskToCharset('?x'), isNull);
    });

    test('掩码空间估算', () {
      expect(HashAudit.maskSpace('?d?d?d?d'), 10000);
      expect(HashAudit.maskSpace('?l?l'), 676);
    });

    test('规则变形包含原词', () {
      expect(HashAudit.applyRules('pass', 0), ['pass']);
      final r1 = HashAudit.applyRules('pass', 1);
      expect(r1, contains('pass'));
      expect(r1, contains('Pass'));
      expect(r1, contains('PASS'));
      expect(r1, contains('pass123'));
      final r2 = HashAudit.applyRules('pass', 2);
      expect(r2, contains(r'p@$$'));
      expect(r2, contains('ssap'));
    });
  });

  group('会话参数', () {
    test('CrackJob 序列化往返', () {
      final job = CrackJob(
        targets: [HashAudit.parseLine('5f4dcc3b5aa765d61d8327deb882cf99')!],
        words: const ['password'],
        masks: const ['?d?d'],
        ruleLevel: 1,
      );
      final back = CrackJob.fromJson(job.toJson());
      expect(back.targets.single.kind, HashKind.md5);
      expect(back.words, ['password']);
      expect(back.ruleLevel, 1);
    });
  });
}
