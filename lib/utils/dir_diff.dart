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

import 'dart:io';
import 'dart:isolate';

/// 一条「目录对比」的结果。
enum DirDiffStatus {
  /// 两边内容一致（或都是空文件）。
  same,

  /// 文本内容不同。
  modified,

  /// 二进制内容不同（大小不同，或大小相同但字节不同）。
  binaryModified,

  /// 只在左侧存在。
  leftOnly,

  /// 只在右侧存在。
  rightOnly,

  /// 读不了（权限 / 符号链接断开 / 路径里有非法字符）。
  error,
}

extension DirDiffStatusX on DirDiffStatus {
  bool get isDifferent =>
      this == DirDiffStatus.modified ||
      this == DirDiffStatus.binaryModified ||
      this == DirDiffStatus.leftOnly ||
      this == DirDiffStatus.rightOnly ||
      this == DirDiffStatus.error;

  String get code => switch (this) {
        DirDiffStatus.same => 'same',
        DirDiffStatus.modified => 'modified',
        DirDiffStatus.binaryModified => 'binary',
        DirDiffStatus.leftOnly => 'left',
        DirDiffStatus.rightOnly => 'right',
        DirDiffStatus.error => 'error',
      };
}

class DirDiffEntry {
  /// 相对路径，一律用 `/` 分隔（Windows 上也一样，方便显示与比较）。
  final String relativePath;
  final DirDiffStatus status;
  final int leftSize;
  final int rightSize;
  final String? note;

  const DirDiffEntry({
    required this.relativePath,
    required this.status,
    this.leftSize = 0,
    this.rightSize = 0,
    this.note,
  });

  String get name {
    final i = relativePath.lastIndexOf('/');
    return i < 0 ? relativePath : relativePath.substring(i + 1);
  }

  /// 相对路径里去掉文件名后的目录部分（用于「按目录分组」）。
  String get dir {
    final i = relativePath.lastIndexOf('/');
    return i < 0 ? '' : relativePath.substring(0, i);
  }
}

class DirDiffResult {
  final List<DirDiffEntry> entries;
  final bool truncated;
  final String? error;

  const DirDiffResult({
    required this.entries,
    this.truncated = false,
    this.error,
  });

  int countOf(DirDiffStatus s) => entries.where((e) => e.status == s).length;

  int get total => entries.length;
  int get differentCount => entries.where((e) => e.status.isDifferent).length;
  bool get hasDifference => differentCount > 0;
}

/// 目录对比。
///
/// 只做「按相对路径配对 + 内容是否一致」这一件事，不产生逐行差异——
/// 点开某一条再交给文本对比页 / 十六进制对比页去做细粒度对比。
class DirDiff {
  /// 默认跳过的目录名（版本库元数据、依赖、构建产物）。逐层比对时会递归，
  /// 这些目录动辄几万个文件，混进来会把列表冲垮。
  static const Set<String> defaultSkipDirs = {
    '.git',
    '.svn',
    '.hg',
    'node_modules',
    'build',
    'dist',
    'out',
    '.dart_tool',
    '.gradle',
    '.idea',
    '.vscode',
    'Pods',
    'target',
    '.next',
    '__pycache__',
    '.venv',
    'venv',
  };

  /// 单个文件的比较上限：更大的按「二进制」处理，只比大小。
  static const int maxContentCompareBytes = 64 * 1024 * 1024;

  static const int _chunk = 64 * 1024;
  static const int _binarySniffBytes = 4096;

  /// 对比两个目录。
  ///
  /// [maxFiles] 是两侧加起来最多扫描多少个文件，超过就停下并标记 truncated。
  /// 扫描放在独立 isolate 里做（`Directory.listSync` 递归几万个文件会明显卡 UI）。
  static Future<DirDiffResult> compare(
    String leftDir,
    String rightDir, {
    int maxFiles = 20000,
    bool compareContent = true,
    Set<String> skipDirs = defaultSkipDirs,
  }) async {
    final left = _normalizeRoot(leftDir);
    final right = _normalizeRoot(rightDir);
    if (left.isEmpty || right.isEmpty) {
      return const DirDiffResult(entries: [], error: 'empty');
    }
    final ld = Directory(left);
    final rd = Directory(right);
    if (!await ld.exists()) {
      return const DirDiffResult(entries: [], error: 'left-missing');
    }
    if (!await rd.exists()) {
      return const DirDiffResult(entries: [], error: 'right-missing');
    }

    final skip = skipDirs.join('\u0001');
    Map<String, int> leftMap;
    Map<String, int> rightMap;
    try {
      final pair = await Isolate.run(() => _scanBoth(left, right, skip, maxFiles));
      leftMap = Map<String, int>.from(pair[0]);
      rightMap = Map<String, int>.from(pair[1]);
    } catch (_) {
      // isolate 不可用时退回同步扫描（结果一样，只是会卡一下）
      leftMap = _scanSync(left, skipDirs, maxFiles);
      rightMap = _scanSync(right, skipDirs, maxFiles);
    }

    final truncated =
        leftMap.length >= maxFiles || rightMap.length >= maxFiles;
    final paths = <String>{...leftMap.keys, ...rightMap.keys}.toList()..sort();

    final entries = <DirDiffEntry>[];
    for (final p in paths) {
      final ls = leftMap[p];
      final rs = rightMap[p];
      if (ls == null) {
        entries.add(DirDiffEntry(
            relativePath: p, status: DirDiffStatus.rightOnly, rightSize: rs ?? 0));
        continue;
      }
      if (rs == null) {
        entries.add(DirDiffEntry(
            relativePath: p, status: DirDiffStatus.leftOnly, leftSize: ls));
        continue;
      }
      if (ls != rs) {
        entries.add(DirDiffEntry(
            relativePath: p,
            status: DirDiffStatus.binaryModified,
            leftSize: ls,
            rightSize: rs));
        continue;
      }
      if (!compareContent || ls == 0) {
        entries.add(DirDiffEntry(
            relativePath: p,
            status: DirDiffStatus.same,
            leftSize: ls,
            rightSize: rs));
        continue;
      }
      if (ls > maxContentCompareBytes) {
        entries.add(DirDiffEntry(
            relativePath: p,
            status: DirDiffStatus.same,
            leftSize: ls,
            rightSize: rs,
            note: 'too-large'));
        continue;
      }
      try {
        final lf = File('$left/$p');
        final rf = File('$right/$p');
        final binary = await _looksBinary(lf) || await _looksBinary(rf);
        final same = await _sameContent(lf, rf);
        entries.add(DirDiffEntry(
          relativePath: p,
          status: same
              ? DirDiffStatus.same
              : (binary ? DirDiffStatus.binaryModified : DirDiffStatus.modified),
          leftSize: ls,
          rightSize: rs,
        ));
      } catch (e) {
        entries.add(DirDiffEntry(
          relativePath: p,
          status: DirDiffStatus.error,
          leftSize: ls,
          rightSize: rs,
          note: '$e',
        ));
      }
    }

    return DirDiffResult(entries: entries, truncated: truncated);
  }

  /// 单个文件对比：返回 null 表示内容一致，否则返回差异描述。
  static Future<String?> compareFiles(String leftFile, String rightFile) async {
    try {
      final lf = File(leftFile);
      final rf = File(rightFile);
      final ls = await lf.length();
      final rs = await rf.length();
      if (ls != rs) return 'size $ls != $rs';
      if (await _sameContent(lf, rf)) return null;
      return 'content differs';
    } catch (e) {
      return '$e';
    }
  }

  static String _normalizeRoot(String p) {
    var s = p.trim();
    if (s.isEmpty) return '';
    while (s.length > 1 && (s.endsWith('/') || s.endsWith('\\'))) {
      // 保留 Windows 盘符根（C:\）与 Unix 根（/）
      if (s.length == 3 && s[1] == ':') break;
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// 顶层函数（供 Isolate.run 使用，避免闭包捕获不可发送的对象）。
  static List<Map<String, int>> _scanBoth(
      String left, String right, String skipJoined, int maxFiles) {
    final skip = skipJoined.split('\u0001').toSet();
    return [
      _scanSync(left, skip, maxFiles),
      _scanSync(right, skip, maxFiles),
    ];
  }

  /// 递归收集「相对路径 -> 文件大小」。目录不单列，只列文件。
  static Map<String, int> _scanSync(
      String root, Set<String> skipDirs, int maxFiles) {
    final out = <String, int>{};
    void walk(Directory dir, String prefix) {
      if (out.length >= maxFiles) return;
      List<FileSystemEntity> list;
      try {
        list = dir.listSync(followLinks: false);
      } catch (_) {
        return;
      }
      for (final e in list) {
        if (out.length >= maxFiles) return;
        final name = e.path.substring(e.path.lastIndexOf(Platform.pathSeparator) + 1);
        final rel = prefix.isEmpty ? name : '$prefix/$name';
        if (e is Directory) {
          if (skipDirs.contains(name)) continue;
          walk(e, rel);
        } else if (e is File) {
          try {
            out[rel] = e.lengthSync();
          } catch (_) {
            out[rel] = -1;
          }
        }
        // Link 直接忽略：跟随可能成环，不跟随又拿不到大小
      }
    }

    walk(Directory(root), '');
    return out;
  }

  static Future<bool> _looksBinary(File f) async {
    RandomAccessFile? raf;
    try {
      raf = await f.open();
      final bytes = await raf.read(_binarySniffBytes);
      return bytes.contains(0);
    } catch (_) {
      return false;
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  static Future<bool> _sameContent(File a, File b) async {
    RandomAccessFile? fa;
    RandomAccessFile? fb;
    try {
      fa = await a.open();
      fb = await b.open();
      while (true) {
        final ba = await fa.read(_chunk);
        final bb = await fb.read(_chunk);
        if (ba.length != bb.length) return false;
        if (ba.isEmpty) return true;
        for (var i = 0; i < ba.length; i++) {
          if (ba[i] != bb[i]) return false;
        }
      }
    } catch (_) {
      return false;
    } finally {
      try {
        await fa?.close();
      } catch (_) {}
      try {
        await fb?.close();
      } catch (_) {}
    }
  }
}
