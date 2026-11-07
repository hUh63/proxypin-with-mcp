import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 本地历史里的一份快照。
class LocalSnapshot {
  const LocalSnapshot({
    required this.epoch,
    required this.bytes,
    required this.lines,
  });

  /// 毫秒时间戳（同时也是文件名）。
  final int epoch;

  /// 这份快照的字节数。
  final int bytes;

  /// 行数。
  final int lines;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(epoch);
}

/// 文件本地历史。
///
/// VS Code 的 Timeline、IntelliJ 的 Local History 都是这个意思：**不依赖版本
/// 控制**，每次保存前把「磁盘上原来那份」留一份，事后能回看、能取回。
///
/// 语义上刻意定成「保存前的旧内容」，所以：
/// - 第一次保存后，历史里是「你改之前的那一版」；
/// - 连续保存 N 次（内容没变）不会产生 N 份，内容相同直接跳过；
/// - 只留最近 [maxEntries] 份，超了删最旧。
class LocalHistory {
  LocalHistory._();

  /// 每个文件最多留几份。
  static int maxEntries = 20;

  /// 超过这个大小就不记录了（几十 MB 的日志文件存 20 份没意义，还会把
  /// 应用的文档目录撑爆）。
  static int maxBytes = 2 * 1024 * 1024;

  /// 目录名的稳定前缀，方便用户在文件管理器里认出来。
  static const String folderName = 'text_editor_history';

  /// 测试时可以注入一个临时目录；正常运行时为 null，走
  /// `getApplicationDocumentsDirectory()/text_editor_history`。
  static Directory? overrideRoot;

  static Directory? _rootCache;

  static Future<Directory?> _root() async {
    final injected = overrideRoot;
    if (injected != null) {
      if (!injected.existsSync()) injected.createSync(recursive: true);
      return injected;
    }
    final cached = _rootCache;
    if (cached != null && cached.existsSync()) return cached;
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}$folderName');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _rootCache = dir;
      return dir;
    } catch (_) {
      return null;
    }
  }

  /// 一个路径对应的目录名。
  ///
  /// 用 FNV-1a 摘要 + 文件名尾巴：摘要保证不同路径不撞、文件名尾巴方便
  /// 人肉辨认。**不要**用 `String.hashCode` —— Dart 不保证它跨版本稳定，
  /// 升级后历史会全部「消失」（其实还在，只是算出了另一个目录名）。
  static String keyOf(String path) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(path)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    final hex = hash.toRadixString(16).padLeft(8, '0');
    var base = path.split(RegExp(r'[/\\]')).last;
    base = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (base.length > 40) base = base.substring(0, 40);
    if (base.isEmpty) base = 'file';
    return '${hex}_$base';
  }

  static Future<Directory?> _dirOf(String path) async {
    final root = await _root();
    if (root == null) return null;
    final dir = Directory('${root.path}${Platform.pathSeparator}${keyOf(path)}');
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {
        return null;
      }
    }
    return dir;
  }

  /// 某个文件的全部快照，按时间**升序**。
  static Future<List<LocalSnapshot>> list(String path) async {
    if (path.isEmpty) return const <LocalSnapshot>[];
    final dir = await _dirOf(path);
    if (dir == null || !dir.existsSync()) return const <LocalSnapshot>[];
    final result = <LocalSnapshot>[];
    try {
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        final epoch = int.tryParse(name.replaceAll('.txt', ''));
        if (epoch == null) continue;
        var bytes = 0;
        var lines = 1;
        try {
          bytes = entity.lengthSync();
          lines = _countLines(entity.readAsStringSync());
        } catch (_) {
          continue;
        }
        result.add(LocalSnapshot(epoch: epoch, bytes: bytes, lines: lines));
      }
    } catch (_) {}
    result.sort((a, b) => a.epoch.compareTo(b.epoch));
    return result;
  }

  /// 留一份快照。相同的旧内容不重复记录。
  ///
  /// 返回 true 表示真的写了新的一份。
  static Future<bool> record(String path, String text, {int? epoch}) async {
    if (path.isEmpty || text.isEmpty) return false;
    if (utf8.encode(text).length > maxBytes) return false;
    final dir = await _dirOf(path);
    if (dir == null) return false;
    try {
      final existing = await list(path);
      if (existing.isNotEmpty) {
        final latest = await read(path, existing.last.epoch);
        if (latest == text) return false;
      }
      var stamp = epoch ?? DateTime.now().millisecondsSinceEpoch;
      // 同一毫秒内两次保存（保存全部 + 自动保存）不要互相覆盖。
      while (File(_fileOf(dir, stamp).path).existsSync()) {
        stamp++;
      }
      await _fileOf(dir, stamp).writeAsString(text, flush: true);
      final after = await list(path);
      if (after.length > maxEntries) {
        final drop = after.length - maxEntries;
        for (var i = 0; i < drop; i++) {
          try {
            await _fileOf(dir, after[i].epoch).delete();
          } catch (_) {}
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 读回一份快照。
  static Future<String?> read(String path, int epoch) async {
    final dir = await _dirOf(path);
    if (dir == null) return null;
    try {
      final file = _fileOf(dir, epoch);
      if (!file.existsSync()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// 删掉一份快照。
  static Future<void> remove(String path, int epoch) async {
    final dir = await _dirOf(path);
    if (dir == null) return;
    try {
      final file = _fileOf(dir, epoch);
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  /// 清空某个文件的全部历史。
  static Future<void> clear(String path) async {
    if (path.isEmpty) return;
    final root = await _root();
    if (root == null) return;
    try {
      final dir = Directory('${root.path}${Platform.pathSeparator}${keyOf(path)}');
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  static File _fileOf(Directory dir, int epoch) =>
      File('${dir.path}${Platform.pathSeparator}$epoch.txt');

  static int _countLines(String text) {
    if (text.isEmpty) return 0;
    var lines = 1;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) lines++;
    }
    // 以换行结尾时，最后那个空行不算一行（和编辑器状态栏的口径一致）。
    if (text.endsWith('\n')) lines--;
    return lines;
  }

  /// 人性化的时间。
  static String formatTime(DateTime t, {DateTime? now}) {
    final base = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final sameDay =
        base.year == t.year && base.month == t.month && base.day == t.day;
    final hm = '${two(t.hour)}:${two(t.minute)}';
    if (sameDay) return hm;
    if (base.year == t.year) return '${two(t.month)}-${two(t.day)} $hm';
    return '${t.year}-${two(t.month)}-${two(t.day)} $hm';
  }

  /// 人性化的体积。
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
