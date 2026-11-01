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

// 文件拆分 / 合并（纯 Dart，流式读写，不会把整个文件读进内存）。
//
// 用途：有些渠道限制单文件大小（邮件附件、上传接口、聊天工具），先把大文件切成
// 几片，到对面再拼回来。参考「编码工具箱」的「文件拆分/合并」，这里补上两块它没有的：
//   · 流式处理（几百 MB 的文件也不会 OOM）；
//   · 合并时自动按 part_0001 的序号排序，不靠用户手选顺序。

import 'dart:io';

/// 拆分结果里的一个分片。
class SplitPart {
  final String path;
  final int bytes;

  const SplitPart(this.path, this.bytes);
}

class FileSplitter {
  FileSplitter._();

  /// 分片文件名前缀 / 后缀（合并时按它找文件）。
  static const String prefix = 'part_';
  static const String suffix = '.bin';

  /// 按「每片最大字节数」拆分，写到 [outDir] 下，返回产出的分片列表。
  ///
  /// [onProgress] 收到 0..1 的进度（按已处理字节算），可以取消（返回 true 停止）。
  static Future<List<SplitPart>> splitBySize(
    File file, {
    required Directory outDir,
    required int chunkSize,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (chunkSize <= 0) throw ArgumentError('chunkSize must be > 0');
    await outDir.create(recursive: true);
    final total = await file.length();
    final parts = <SplitPart>[];
    final raf = await file.open();
    try {
      var read = 0;
      var index = 1;
      final buffer = List<int>.filled(chunkSize, 0);
      while (read < total) {
        if (isCancelled?.call() ?? false) break;
        final want = total - read < chunkSize ? total - read : chunkSize;
        var got = 0;
        while (got < want) {
          final n = await raf.readInto(buffer, got, want);
          if (n <= 0) break;
          got += n;
        }
        if (got <= 0) break;
        final outPath = '${outDir.path}${Platform.pathSeparator}'
            '${prefix}${index.toString().padLeft(4, '0')}$suffix';
        final out = File(outPath);
        await out.writeAsBytes(buffer.sublist(0, got), flush: true);
        parts.add(SplitPart(outPath, got));
        read += got;
        index++;
        onProgress?.call(total == 0 ? 1 : read / total);
      }
    } finally {
      await raf.close();
    }
    return parts;
  }

  /// 按「分成几份」拆分：每片大小 = ceil(total / parts)。
  static Future<List<SplitPart>> splitByCount(
    File file, {
    required Directory outDir,
    required int count,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final total = await file.length();
    final n = count < 1 ? 1 : count;
    var chunk = (total / n).ceil();
    if (chunk < 1) chunk = 1;
    return splitBySize(file,
        outDir: outDir, chunkSize: chunk, onProgress: onProgress, isCancelled: isCancelled);
  }

  /// 在 [dir] 里找出所有 `part_XXXX.bin`，按序号排好。
  static Future<List<File>> findParts(Directory dir) async {
    if (!await dir.exists()) return const [];
    final files = <File>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is! File) continue;
      final name = e.path.split(Platform.pathSeparator).last;
      if (name.startsWith(prefix) && name.endsWith(suffix)) files.add(e);
    }
    int seq(File f) {
      final name = f.path.split(Platform.pathSeparator).last;
      final digits = name.substring(prefix.length, name.length - suffix.length);
      return int.tryParse(digits) ?? 0;
    }

    files.sort((a, b) => seq(a).compareTo(seq(b)));
    return files;
  }

  /// 把 [parts] 按顺序拼到 [outPath]，返回总字节数。
  static Future<int> merge(
    List<File> parts, {
    required String outPath,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var totalSize = 0;
    for (final f in parts) {
      totalSize += await f.length();
    }
    final sink = File(outPath).openWrite();
    var written = 0;
    try {
      final buffer = List<int>.filled(1 << 16, 0);
      for (final f in parts) {
        if (isCancelled?.call() ?? false) break;
        final raf = await f.open();
        try {
          while (true) {
            final n = await raf.readInto(buffer);
            if (n <= 0) break;
            sink.add(buffer.sublist(0, n));
            written += n;
            onProgress?.call(totalSize == 0 ? 1 : written / totalSize);
          }
        } finally {
          await raf.close();
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    return written;
  }
}
