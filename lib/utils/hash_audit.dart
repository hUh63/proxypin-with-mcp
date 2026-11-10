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

// 哈希识别与口令恢复（纯 Dart，无 Flutter 依赖，可单测）。
//
// 用途：自有数据审计 —— 拿到一批 hash（自家数据库导出、自己的取证镜像、
// 自己搭的靶机），判断用的什么算法、口令强度够不够、哪些弱口令能还原。
//
// **可恢复**（算法简单、每秒百万级，字典/掩码攻击现实可行）：
//   MD5 / SHA-1 / SHA-256 / SHA-512 / NTLM / {SHA} / {SSHA} / $SHA512$
//   bcrypt（有现成实现，但每候选几十毫秒，只适合小字典）
//   明文（口令库被误存成明文时，直接比对）
//
// **仅识别**（crypt 系列：$1$ $apr1$ $5$ $6$ / LM）：
//   这几类要正确实现 crypt 的字节置换与轮函数，写错了会静默不命中
//   （跑半小时零结果，看不出是实现错了还是口令真不在字典里）。
//   与其给一个不可靠的结果，不如明确告诉用户「识别到了，恢复请用 hashcat/john」。
//
// 攻击方式：字典（含变形规则）/ 掩码（?l?u?d?s?a）/ 纯数字范围。
// 计算跑在独立 isolate，主线程只收进度。

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/digests/md4.dart';

/// 哈希种类。
enum HashKind {
  md5,
  sha1,
  sha256,
  sha512,
  ntlm,
  lm,
  sha1Base64,
  ssha,
  sha512Raw,
  md5Crypt,
  apr1,
  sha256Crypt,
  sha512Crypt,
  bcrypt,
  plain,
  unknown,
}

extension HashKindInfo on HashKind {
  String get label => switch (this) {
        HashKind.md5 => 'MD5',
        HashKind.sha1 => 'SHA-1',
        HashKind.sha256 => 'SHA-256',
        HashKind.sha512 => 'SHA-512',
        HashKind.ntlm => 'NTLM',
        HashKind.lm => 'LM',
        HashKind.sha1Base64 => '{SHA}',
        HashKind.ssha => '{SSHA}',
        HashKind.sha512Raw => r'$SHA512$',
        HashKind.md5Crypt => r'$1$ md5crypt',
        HashKind.apr1 => r'$apr1$',
        HashKind.sha256Crypt => r'$5$ sha256crypt',
        HashKind.sha512Crypt => r'$6$ sha512crypt',
        HashKind.bcrypt => r'$2*$ bcrypt',
        HashKind.plain => '明文',
        HashKind.unknown => '未知',
      };

  /// 能不能做字典/掩码恢复。
  bool get recoverable => switch (this) {
        HashKind.md5 ||
        HashKind.sha1 ||
        HashKind.sha256 ||
        HashKind.sha512 ||
        HashKind.ntlm ||
        HashKind.sha1Base64 ||
        HashKind.ssha ||
        HashKind.sha512Raw ||
        HashKind.bcrypt ||
        HashKind.plain =>
          true,
        _ => false,
      };

  /// 每个候选都很贵（bcrypt）。
  bool get slow => this == HashKind.bcrypt;

  /// 带盐（同口令不同人算出来不一样）。
  bool get salted => this == HashKind.ssha || this == HashKind.bcrypt;
}

/// 一条待审计的哈希。
class HashTarget {
  /// 行里的用户名（`user:hash` 形式时才有）。
  final String user;
  final String raw;
  final HashKind kind;

  /// 归一化摘要：hex 小写 / base64 原文 / crypt 整串。
  final String digest;

  const HashTarget({
    required this.user,
    required this.raw,
    required this.kind,
    required this.digest,
  });

  String get display => user.isEmpty ? raw : '$user:$raw';

  Map<String, dynamic> toJson() => {'user': user, 'raw': raw, 'kind': kind.index, 'digest': digest};

  factory HashTarget.fromJson(Map<String, dynamic> j) => HashTarget(
        user: '${j['user'] ?? ''}',
        raw: '${j['raw'] ?? ''}',
        kind: HashKind.values[(j['kind'] is int ? j['kind'] as int : 0).clamp(0, HashKind.values.length - 1)],
        digest: '${j['digest'] ?? ''}',
      );

  @override
  String toString() => display;
}

/// 识别 + 校验。
class HashAudit {
  HashAudit._();

  static final RegExp _hex = RegExp(r'^[0-9a-fA-F]+$');

  /// bcrypt 校验实现（由 UI 层注入，避免 utils 层硬依赖 bcrypt 包）。
  static bool Function(String pw, String hash)? bcryptImpl;

  /// 一行文本 → 哈希（识别不出返回 null）。
  static HashTarget? parseLine(String line) {
    var s = line.trim();
    if (s.isEmpty || s.startsWith('#')) return null;

    // pwdump 格式：user:uid:LM:NT:::
    final parts = s.split(':');
    if (parts.length >= 7 && !s.contains(r'$')) {
      final lm = parts[2].trim();
      final nt = parts[3].trim();
      if (nt.length == 32 && _isHex(nt)) {
        return HashTarget(user: parts[0], raw: nt, kind: HashKind.ntlm, digest: nt.toLowerCase());
      }
      if (lm.length == 32 && _isHex(lm)) {
        return HashTarget(user: parts[0], raw: lm, kind: HashKind.lm, digest: lm.toLowerCase());
      }
    }

    // user:hash（含 $ 的 crypt 串本身有冒号风险低，这里只处理无 $ 前缀的）
    var user = '';
    if (!s.startsWith(r'$') && !s.startsWith('{') && s.contains(':')) {
      final idx = s.indexOf(':');
      final head = s.substring(0, idx);
      final tail = s.substring(idx + 1).trim();
      if (head.isNotEmpty && !head.contains(' ') && tail.isNotEmpty && !head.contains(r'$')) {
        user = head;
        s = tail;
      }
    }

    if (s.startsWith(r'$2')) {
      final pieces = s.split(r'$');
      if (pieces.length >= 4) {
        return HashTarget(user: user, raw: s, kind: HashKind.bcrypt, digest: s);
      }
    }
    if (s.startsWith(r'$1$')) {
      return HashTarget(user: user, raw: s, kind: HashKind.md5Crypt, digest: s);
    }
    if (s.startsWith(r'$apr1$')) {
      return HashTarget(user: user, raw: s, kind: HashKind.apr1, digest: s);
    }
    if (s.startsWith(r'$5$')) {
      return HashTarget(user: user, raw: s, kind: HashKind.sha256Crypt, digest: s);
    }
    if (s.startsWith(r'$6$')) {
      return HashTarget(user: user, raw: s, kind: HashKind.sha512Crypt, digest: s);
    }
    if (s.startsWith(r'$SHA512$')) {
      final hex = s.substring(8).trim();
      if (_isHex(hex)) {
        return HashTarget(user: user, raw: s, kind: HashKind.sha512Raw, digest: hex.toLowerCase());
      }
    }
    if (s.startsWith('{SHA}')) {
      return HashTarget(user: user, raw: s, kind: HashKind.sha1Base64, digest: s.substring(5));
    }
    if (s.startsWith('{SSHA}')) {
      return HashTarget(user: user, raw: s, kind: HashKind.ssha, digest: s.substring(6));
    }
    if (s.startsWith('{MD5}')) {
      return HashTarget(user: user, raw: s, kind: HashKind.md5, digest: s.substring(5).toLowerCase());
    }

    if (_isHex(s)) {
      return switch (s.length) {
        32 => HashTarget(user: user, raw: s, kind: HashKind.md5, digest: s.toLowerCase()),
        40 => HashTarget(user: user, raw: s, kind: HashKind.sha1, digest: s.toLowerCase()),
        64 => HashTarget(user: user, raw: s, kind: HashKind.sha256, digest: s.toLowerCase()),
        128 => HashTarget(user: user, raw: s, kind: HashKind.sha512, digest: s.toLowerCase()),
        _ => null,
      };
    }
    return null;
  }

  /// 多行文本 → 哈希列表（去重，保持顺序）。
  static List<HashTarget> parseAll(String text) {
    final out = <HashTarget>[];
    final seen = <String>{};
    for (final line in text.split('\n')) {
      final t = parseLine(line);
      if (t == null) continue;
      if (seen.add(t.display)) out.add(t);
    }
    return out;
  }

  static bool _isHex(String s) => s.isNotEmpty && _hex.hasMatch(s);

  // ---------- 校验 ----------

  /// 候选口令是否与 [target] 匹配。
  static bool verify(HashTarget t, String candidate) {
    switch (t.kind) {
      case HashKind.plain:
        return t.raw == candidate;
      case HashKind.md5:
        return md5.convert(utf8.encode(candidate)).toString() == t.digest;
      case HashKind.sha1:
        return sha1.convert(utf8.encode(candidate)).toString() == t.digest;
      case HashKind.sha256:
        return sha256.convert(utf8.encode(candidate)).toString() == t.digest;
      case HashKind.sha512:
      case HashKind.sha512Raw:
        return sha512.convert(utf8.encode(candidate)).toString() == t.digest;
      case HashKind.ntlm:
        return ntlm(candidate) == t.digest;
      case HashKind.sha1Base64:
        return base64Encode(sha1.convert(utf8.encode(candidate)).bytes) == t.digest;
      case HashKind.ssha:
        return _ssha(candidate, t.digest);
      case HashKind.bcrypt:
        final impl = bcryptImpl;
        if (impl == null) return false;
        try {
          return impl(candidate, t.raw);
        } catch (_) {
          return false;
        }
      case HashKind.lm:
      case HashKind.md5Crypt:
      case HashKind.apr1:
      case HashKind.sha256Crypt:
      case HashKind.sha512Crypt:
      case HashKind.unknown:
        return false;
    }
  }

  /// NTLM = MD4(UTF-16LE(password))，32 位小写 hex。
  static String ntlm(String pw) {
    final units = <int>[];
    for (final rune in pw.runes) {
      if (rune <= 0xFFFF) {
        units.add(rune & 0xFF);
        units.add((rune >> 8) & 0xFF);
      } else {
        final v = rune - 0x10000;
        final hi = 0xD800 + (v >> 10);
        final lo = 0xDC00 + (v & 0x3FF);
        units.addAll([hi & 0xFF, (hi >> 8) & 0xFF, lo & 0xFF, (lo >> 8) & 0xFF]);
      }
    }
    final out = MD4Digest().process(Uint8List.fromList(units));
    return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// {SSHA}：base64(sha1(pw + salt))，盐是 base64 尾部超出 20 字节的部分。
  static bool _ssha(String pw, String b64) {
    final List<int> raw;
    try {
      raw = base64.decode(base64.normalize(b64));
    } catch (_) {
      return false;
    }
    if (raw.length < 20) return false;
    final salt = raw.length > 20 ? raw.sublist(20) : const <int>[];
    final digest = sha1.convert([...utf8.encode(pw), ...salt]).bytes;
    for (var i = 0; i < 20; i++) {
      if (digest[i] != raw[i]) return false;
    }
    return true;
  }

  // ---------- 候选生成 ----------

  /// 掩码 → 字符集：`?l` 小写、`?u` 大写、`?d` 数字、`?s` 符号、`?a` 全部。
  static List<String>? maskToCharset(String mask) {
    final chars = <String>[];
    for (var i = 0; i < mask.length; i++) {
      final c = mask[i];
      if (c == '?') {
        if (i + 1 >= mask.length) return null;
        final t = mask[i + 1];
        i++;
        switch (t) {
          case 'l':
            chars.addAll('abcdefghijklmnopqrstuvwxyz'.split(''));
          case 'u':
            chars.addAll('ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''));
          case 'd':
            chars.addAll('0123456789'.split(''));
          case 's':
            chars.addAll(r'''!@#$%^&*()-_=+[]{};:'",.<>/?\|~`'''.split(''));
          case 'a':
            chars.addAll('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.split(''));
          case '?':
            chars.add('?');
          default:
            return null;
        }
      } else {
        chars.add(c);
      }
    }
    return chars.isEmpty ? null : chars;
  }

  /// 掩码的候选总数（开始前估算用）。
  static int maskSpace(String mask) {
    final cs = maskToCharset(mask);
    if (cs == null) return 0;
    var total = 1;
    for (final c in cs) {
      total *= c.length;
      if (total > 50000000) return 50000000;
    }
    return total;
  }

  /// 口令变形规则（对标 john 的常用 rules 子集）。
  static List<String> applyRules(String word, int level) {
    if (level <= 0) return [word];
    final out = <String>{word};
    final cap = word.isEmpty ? word : word[0].toUpperCase() + word.substring(1);
    out.add(cap);
    out.add(word.toUpperCase());
    out.add(word.toLowerCase());
    for (final suffix in const ['1', '123', '1234', '12345', '!', '2024', '2025', '2026']) {
      out.add('$word$suffix');
    }
    if (level >= 2) {
      final leet = word
          .replaceAll('a', '@')
          .replaceAll('o', '0')
          .replaceAll('i', '1')
          .replaceAll('e', '3')
          .replaceAll('s', r'$');
      out.add(leet);
      out.add(leet.toUpperCase());
      out.add(String.fromCharCodes(word.runes.toList().reversed));
      out.add(cap);
      out.add('$cap${word.length}');
    }
    return out.where((e) => e.isNotEmpty).toList();
  }
}

/// 攻击参数（可序列化，直接传给 isolate）。
class CrackJob {
  final List<HashTarget> targets;
  final List<String> words;
  final List<String> masks;
  final int ruleLevel;

  /// 候选上限（防止掩码写错把手机烤了）。
  final int maxCandidates;

  const CrackJob({
    required this.targets,
    this.words = const [],
    this.masks = const [],
    this.ruleLevel = 0,
    this.maxCandidates = 3000000,
  });

  Map<String, dynamic> toJson() => {
        'targets': targets.map((t) => t.toJson()).toList(),
        'words': words,
        'masks': masks,
        'ruleLevel': ruleLevel,
        'maxCandidates': maxCandidates,
      };

  factory CrackJob.fromJson(Map<String, dynamic> j) => CrackJob(
        targets: ((j['targets'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => HashTarget.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        words: ((j['words'] as List?) ?? const []).map((e) => '$e').toList(),
        masks: ((j['masks'] as List?) ?? const []).map((e) => '$e').toList(),
        ruleLevel: (j['ruleLevel'] as num?)?.toInt() ?? 0,
        maxCandidates: (j['maxCandidates'] as num?)?.toInt() ?? 3000000,
      );
}

/// 进度消息（isolate → 主线程）。
class CrackProgress {
  final int tried;
  final int found;
  final bool done;
  final Map<String, String> result;
  const CrackProgress(this.tried, this.found, {this.done = false, this.result = const {}});
}

/// 停表（跨 isolate 用：主线程只发一个「取消」信号）。
class CrackHandle {
  final SendPort _control;
  bool _cancelled = false;
  CrackHandle(this._control);

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _control.send('cancel');
  }
}

/// 一次攻击的会话（isolate 里跑，主线程收进度）。
class HashCrackSession {
  final ReceivePort _receiver = ReceivePort();
  Isolate? _isolate;
  SendPort? _control;
  bool _stopped = false;

  final void Function(CrackProgress p)? onProgress;
  final void Function(String raw, String plain)? onFound;
  final Completer<Map<String, String>> _done = Completer<Map<String, String>>();

  HashCrackSession._({this.onProgress, this.onFound});

  /// 开始跑（[job] 会被序列化发给 isolate）。
  static Future<HashCrackSession> start(
    CrackJob job, {
    void Function(CrackProgress p)? onProgress,
    void Function(String raw, String plain)? onFound,
  }) async {
    final session = HashCrackSession._(onProgress: onProgress, onFound: onFound);
    final isolate = await Isolate.spawn(_crackEntry, [session._receiver.sendPort, job.toJson()]);
    session._isolate = isolate;
    session._receiver.listen((msg) {
      if (msg is SendPort) {
        session._control = msg;
        return;
      }
      if (msg is Map) {
        final done = msg['done'] == true;
        final progress = CrackProgress(
          (msg['tried'] as num?)?.toInt() ?? 0,
          (msg['found'] as num?)?.toInt() ?? 0,
          done: done,
          result: ((msg['new'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v')),
        );
        if (progress.result.isNotEmpty) {
          progress.result.forEach((k, v) => session.onFound?.call(k, v));
        }
        session.onProgress?.call(progress);
        if (done) {
          if (!session._done.isCompleted) session._done.complete(progress.result);
          session._receiver.close();
          session._isolate?.kill(priority: Isolate.immediate);
        }
      }
    });
    return session;
  }

  Future<Map<String, String>> get result => _done.future;

  void cancel() {
    if (_stopped) return;
    _stopped = true;
    _control?.send('cancel');
    // 一秒内没自己退出就硬杀（大掩码可能在一次 hash 里）
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!_done.isCompleted) {
        _isolate?.kill(priority: Isolate.immediate);
        if (!_done.isCompleted) _done.complete(const {});
        _receiver.close();
      }
    });
  }
}

/// isolate 入口：`[SendPort, jobMap]`。
@pragma('vm:entry-point')
Future<void> _crackEntry(List<dynamic> args) async {
  final main = args[0] as SendPort;
  final job = CrackJob.fromJson(Map<String, dynamic>.from(args[1] as Map));
  final ctrl = ReceivePort();
  main.send(ctrl.sendPort);
  var cancelled = false;
  ctrl.listen((m) {
    if (m == 'cancel') cancelled = true;
  });

  final found = <String, String>{};   // 待上报的新命中
  final solved = <String>{};          // 已经解出的目标（raw）
  var tried = 0;
  const batch = 20000;

  // 按算法分组：同一候选只算一次摘要，再和该算法的所有目标比。
  final byKind = <HashKind, List<HashTarget>>{};
  for (final t in job.targets) {
    if (!t.kind.recoverable) continue;
    byKind.putIfAbsent(t.kind, () => []).add(t);
  }
  if (byKind.isEmpty) {
    main.send({'done': true, 'tried': 0, 'found': 0, 'new': <String, String>{}});
    ctrl.close();
    return;
  }

  Map<String, String> checkOne(String cand) {
    final hits = <String, String>{};
    for (final entry in byKind.entries) {
      final kind = entry.key;
      final list = entry.value;
      if (list.every((t) => solved.contains(t.raw))) continue;
      String? digest;
      switch (kind) {
        case HashKind.md5:
          digest = md5.convert(utf8.encode(cand)).toString();
        case HashKind.sha1:
          digest = sha1.convert(utf8.encode(cand)).toString();
        case HashKind.sha256:
          digest = sha256.convert(utf8.encode(cand)).toString();
        case HashKind.sha512:
        case HashKind.sha512Raw:
          digest = sha512.convert(utf8.encode(cand)).toString();
        case HashKind.ntlm:
          digest = HashAudit.ntlm(cand);
        case HashKind.sha1Base64:
          digest = base64Encode(sha1.convert(utf8.encode(cand)).bytes);
        default:
          digest = null;
      }
      if (digest != null) {
        for (final t in list) {
          if (solved.contains(t.raw)) continue;
          if (t.digest == digest) hits[t.raw] = cand;
        }
      } else {
        // 带盐 / 慢算法：只能逐个校验
        for (final t in list) {
          if (solved.contains(t.raw)) continue;
          if (HashAudit.verify(t, cand)) hits[t.raw] = cand;
        }
      }
    }
    return hits;
  }

  /// 上报新命中（[found] 只放「还没报过的」，[solved] 放全部已解出的）。
  void report(Map<String, String> hits) {
    if (hits.isEmpty) return;
    found.addAll(hits);
    solved.addAll(hits.keys);
    main.send({'tried': tried, 'found': solved.length, 'new': hits});
  }

  void flush({bool done = false}) {
    main.send({'tried': tried, 'found': solved.length, 'done': done});
  }

  /// （函数体内不能声明 getter，写成普通函数）
  bool allSolved() => byKind.values.expand((e) => e).every((t) => solved.contains(t.raw));

  // ---- 字典 + 规则 ----
  for (final w in job.words) {
    if (cancelled) break;
    for (final cand in HashAudit.applyRules(w, job.ruleLevel)) {
      report(checkOne(cand));
      tried++;
      if (tried % batch == 0) {
        if (cancelled) break;
        flush();
        if (allSolved()) break;
      }
      if (tried >= job.maxCandidates) break;
    }
    if (cancelled || tried >= job.maxCandidates) break;
  }

  // ---- 掩码 ----
  if (!cancelled && tried < job.maxCandidates) {
    for (final mask in job.masks) {
      final cs = HashAudit.maskToCharset(mask);
      if (cs == null) continue;
      final idx = List<int>.filled(cs.length, 0);
      final buf = List<int>.filled(cs.length, 0);
      var exhausted = false;
      while (!exhausted && !cancelled && tried < job.maxCandidates) {
        for (var i = 0; i < cs.length; i++) {
          buf[i] = cs[i].codeUnitAt(idx[i]);
        }
        final cand = String.fromCharCodes(buf);
        report(checkOne(cand));
        tried++;
        if (tried % batch == 0) {
          flush();
          if (cancelled || allSolved()) break;
        }
        // 进位
        var p = cs.length - 1;
        while (p >= 0) {
          idx[p]++;
          if (idx[p] < cs[p].length) break;
          idx[p] = 0;
          p--;
          if (p < 0) exhausted = true;
        }
      }
      if (cancelled || tried >= job.maxCandidates) break;
    }
  }

  flush(done: true);
  ctrl.close();
}

