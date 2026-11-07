import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/local_history.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lh_test_');
    LocalHistory.overrideRoot = root;
    LocalHistory.maxEntries = 20;
    LocalHistory.maxBytes = 2 * 1024 * 1024;
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
    LocalHistory.overrideRoot = null;
  });

  group('keyOf', () {
    test('同一路径稳定', () {
      expect(LocalHistory.keyOf('/a/b/c.txt'), LocalHistory.keyOf('/a/b/c.txt'));
    });

    test('不同路径不撞', () {
      expect(LocalHistory.keyOf('/a/b/c.txt'),
          isNot(LocalHistory.keyOf('/a/b/d.txt')));
    });

    test('保留文件名尾巴便于识别', () {
      expect(LocalHistory.keyOf('/x/y/main.dart'), endsWith('main.dart'));
    });

    test('中文名被替换成下划线（文件系统安全）', () {
      final key = LocalHistory.keyOf('/x/说明.txt');
      expect(key.contains('说明'), isFalse);
      expect(key.endsWith('.txt'), isTrue);
    });
  });

  group('record / read', () {
    test('写一份能读回', () async {
      final ok = await LocalHistory.record('/p/a.txt', 'hello', epoch: 1000);
      expect(ok, isTrue);
      expect(await LocalHistory.read('/p/a.txt', 1000), 'hello');
    });

    test('内容相同不重复记录', () async {
      await LocalHistory.record('/p/a.txt', 'same', epoch: 1000);
      final again = await LocalHistory.record('/p/a.txt', 'same', epoch: 2000);
      expect(again, isFalse);
      expect((await LocalHistory.list('/p/a.txt')).length, 1);
    });

    test('内容不同就多记一份', () async {
      await LocalHistory.record('/p/a.txt', 'v1', epoch: 1000);
      await LocalHistory.record('/p/a.txt', 'v2', epoch: 2000);
      final list = await LocalHistory.list('/p/a.txt');
      expect(list.length, 2);
      expect(list.first.epoch, 1000);
      expect(list.last.epoch, 2000);
    });

    test('同一毫秒内两次保存不会互相覆盖', () async {
      await LocalHistory.record('/p/a.txt', 'v1', epoch: 5000);
      await LocalHistory.record('/p/a.txt', 'v2', epoch: 5000);
      final list = await LocalHistory.list('/p/a.txt');
      expect(list.length, 2);
      expect(list.map((e) => e.epoch).toSet().length, 2);
    });

    test('不同文件互不影响', () async {
      await LocalHistory.record('/p/a.txt', 'aaa', epoch: 1000);
      await LocalHistory.record('/p/b.txt', 'bbb', epoch: 1000);
      expect((await LocalHistory.list('/p/a.txt')).length, 1);
      expect((await LocalHistory.list('/p/b.txt')).length, 1);
      expect(await LocalHistory.read('/p/a.txt', 1000), 'aaa');
    });
  });

  group('上限与清理', () {
    test('超过 maxEntries 删最旧', () async {
      LocalHistory.maxEntries = 3;
      for (var i = 1; i <= 5; i++) {
        await LocalHistory.record('/p/a.txt', 'v$i', epoch: 1000 + i);
      }
      final list = await LocalHistory.list('/p/a.txt');
      expect(list.length, 3);
      expect(list.first.epoch, 1003);
      expect(list.last.epoch, 1005);
    });

    test('超大内容不记录', () async {
      LocalHistory.maxBytes = 8;
      final ok = await LocalHistory.record('/p/a.txt', 'x' * 100, epoch: 1000);
      expect(ok, isFalse);
      expect(await LocalHistory.list('/p/a.txt'), isEmpty);
    });

    test('空内容不记录', () async {
      expect(await LocalHistory.record('/p/a.txt', '', epoch: 1000), isFalse);
    });

    test('remove / clear', () async {
      await LocalHistory.record('/p/a.txt', 'v1', epoch: 1000);
      await LocalHistory.record('/p/a.txt', 'v2', epoch: 2000);
      await LocalHistory.remove('/p/a.txt', 1000);
      expect((await LocalHistory.list('/p/a.txt')).length, 1);
      await LocalHistory.clear('/p/a.txt');
      expect(await LocalHistory.list('/p/a.txt'), isEmpty);
    });
  });

  group('格式化', () {
    test('当天只显示时分', () {
      final now = DateTime(2026, 11, 7, 15, 0);
      final t = DateTime(2026, 11, 7, 9, 5);
      expect(LocalHistory.formatTime(t, now: now), '09:05');
    });

    test('同年不同日显示月日', () {
      final now = DateTime(2026, 11, 7, 15, 0);
      final t = DateTime(2026, 3, 9, 9, 5);
      expect(LocalHistory.formatTime(t, now: now), '03-09 09:05');
    });

    test('跨年显示完整日期', () {
      final now = DateTime(2026, 11, 7, 15, 0);
      final t = DateTime(2025, 12, 31, 23, 59);
      expect(LocalHistory.formatTime(t, now: now), '2025-12-31 23:59');
    });

    test('体积', () {
      expect(LocalHistory.formatBytes(512), '512 B');
      expect(LocalHistory.formatBytes(2048), '2.0 KB');
      expect(LocalHistory.formatBytes(3 * 1024 * 1024), '3.0 MB');
    });
  });
}
