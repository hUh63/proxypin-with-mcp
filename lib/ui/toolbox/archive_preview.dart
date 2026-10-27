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

// 压缩包预览（zip / jar / apk / docx / xlsx / tar / tar.gz…）。
//
// 只是「看看里面有什么、顺手看一眼某个文本文件」——不做解压到磁盘、不做编辑。
// 7z / rar 没有纯 Dart 解码器，明确告诉用户，而不是转半天没反应。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/logger.dart';

/// 支持的压缩格式（按扩展名判断）。
enum ArchiveKind { zip, tar, tarGz, gzip, unsupported }

ArchiveKind archiveKindOf(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.zip') ||
      lower.endsWith('.jar') ||
      lower.endsWith('.apk') ||
      lower.endsWith('.aar') ||
      lower.endsWith('.xpi') ||
      lower.endsWith('.docx') ||
      lower.endsWith('.xlsx') ||
      lower.endsWith('.pptx') ||
      lower.endsWith('.epub')) {
    return ArchiveKind.zip;
  }
  if (lower.endsWith('.tar')) return ArchiveKind.tar;
  if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) return ArchiveKind.tarGz;
  if (lower.endsWith('.gz')) return ArchiveKind.gzip;
  return ArchiveKind.unsupported;
}

bool isArchiveFile(String path) => archiveKindOf(path) != ArchiveKind.unsupported;

/// 压缩包里的一个条目。
class ArchiveEntryInfo {
  final String name;
  final int size;
  final bool isFile;
  const ArchiveEntryInfo(this.name, this.size, this.isFile);
}

/// 压缩包预览页。
class ArchivePreviewPage extends StatefulWidget {
  final File file;

  const ArchivePreviewPage({super.key, required this.file});

  static Future<void> show(BuildContext context, File file) {
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArchivePreviewPage(file: file)));
  }

  @override
  State<ArchivePreviewPage> createState() => _ArchivePreviewPageState();
}

class _ArchivePreviewPageState extends State<ArchivePreviewPage> {
  /// 超过这个大小就不解析了——解压是「整包进内存」，几百 MB 会直接 OOM。
  static const int _maxBytes = 200 * 1024 * 1024;

  /// 解压后的总大小上限：超过就当作可疑包（zip bomb / 超大镜像），不展开。
  static const int _maxUnpacked = 512 * 1024 * 1024;

  static final RegExp _textExt = RegExp(
      r'\.(json|xml|html?|js|ts|css|py|java|kt|cs|c|cpp|h|go|rs|php|rb|sh|ya?ml|toml|ini|log|txt|md)$');
  static final RegExp _imageExt = RegExp(r'\.(png|jpe?g|gif|webp|bmp|ico)$');

  Archive? _archive;
  List<ArchiveEntryInfo> _entries = const <ArchiveEntryInfo>[];
  bool _loading = true;
  String? _error;
  String _filter = '';

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final kind = archiveKindOf(widget.file.path);
    if (kind == ArchiveKind.unsupported) {
      setState(() {
        _loading = false;
        _error = localizations.mediaUnsupported;
      });
      return;
    }
    try {
      final stat = await widget.file.stat();
      if (stat.size > _maxBytes) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = localizations.mediaUnsupported;
        });
        return;
      }
      final bytes = await widget.file.readAsBytes();
      final archive = _decode(kind, bytes);
      // zip bomb 粗判：解压后总量远超输入时不继续——后面的「点开条目」会再复刻
      // 一份字节，几百 MB 的包在手机上很容易直接把进程顶掉。
      var unpacked = 0;
      for (final f in archive.files) {
        unpacked += f.size;
      }
      if (unpacked > _maxUnpacked) {
        throw const FormatException('解压后体积过大');
      }
      if (!mounted) return;
      setState(() {
        _archive = archive;
        _entries = archive.files
            .map((f) => ArchiveEntryInfo(f.name, f.size, f.isFile))
            .where((e) => e.name.isNotEmpty)
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _loading = false;
      });
    } catch (e) {
      logger.w('archive preview failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Archive _decode(ArchiveKind kind, Uint8List bytes) {
    switch (kind) {
      case ArchiveKind.zip:
        return ZipDecoder().decodeBytes(bytes);
      case ArchiveKind.tar:
        return TarDecoder().decodeBytes(bytes);
      case ArchiveKind.tarGz:
        return TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
      case ArchiveKind.gzip:
        final raw = GZipDecoder().decodeBytes(bytes);
        if (raw.length > _maxUnpacked) {
          throw const FormatException('解压后体积过大');
        }
        // 单个 .gz 就是一份压缩数据，没有条目结构，直接当成一个文件展示
        return Archive()
          ..addFile(ArchiveFile(widget.file.path.split(Platform.pathSeparator).last, raw.length, raw));
      case ArchiveKind.unsupported:
        return Archive();
    }
  }

  List<ArchiveEntryInfo> get _visible {
    final key = _filter.trim().toLowerCase();
    if (key.isEmpty) return _entries;
    return _entries.where((e) => e.name.toLowerCase().contains(key)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.file.path.split(Platform.pathSeparator).last;
    return Scaffold(
      appBar: AppBar(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
        actions: [
          IconButton(
            tooltip: localizations.copy,
            icon: const Icon(Icons.link, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.file.path));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(localizations.copied), duration: const Duration(milliseconds: 1200)),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5)),
                  ),
                )
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: TextField(
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: localizations.search,
                        prefixIcon: const Icon(Icons.search, size: 16),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                        hintStyle: const TextStyle(fontSize: 12.5),
                      ),
                      style: const TextStyle(fontSize: 12.5),
                      onChanged: (v) => setState(() => _filter = v),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('${_entries.length}',
                          style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color)),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _visible.length,
                      itemBuilder: (context, i) {
                        final e = _visible[i];
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: Icon(e.isFile ? _iconFor(e.name) : Icons.folder_outlined, size: 16),
                          title: Text(e.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                          trailing: e.isFile
                              ? Text(_size(e.size),
                                  style: TextStyle(fontSize: 10.5, color: theme.textTheme.bodySmall?.color))
                              : null,
                          onTap: e.isFile ? () => _openEntry(e.name) : null,
                        );
                      },
                    ),
                  ),
                ]),
    );
  }

  static IconData _iconFor(String name) {
    final lower = name.toLowerCase();
    if (_imageExt.hasMatch(lower)) return Icons.image_outlined;
    if (RegExp(r'\.(mp4|mov|mkv|webm|avi)$').hasMatch(lower)) return Icons.movie_outlined;
    if (RegExp(r'\.(mp3|wav|flac|ogg|m4a)$').hasMatch(lower)) return Icons.audiotrack_outlined;
    if (_textExt.hasMatch(lower)) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  /// 打开条目：图片就地显示，文本弹窗显示，其余说明不支持。
  Future<void> _openEntry(String name) async {
    final archive = _archive;
    if (archive == null) return;
    ArchiveFile? file;
    for (final f in archive.files) {
      if (f.name == name) {
        file = f;
        break;
      }
    }
    if (file == null) return;
    final data = file.content;
    final bytes = data is Uint8List ? data : (data is List<int> ? Uint8List.fromList(data) : null);
    if (bytes == null) return;
    final lower = name.toLowerCase();
    if (_imageExt.hasMatch(lower)) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: InteractiveViewer(maxScale: 6, child: Image.memory(bytes, fit: BoxFit.contain)),
        ),
      );
      return;
    }
    if (_textExt.hasMatch(lower)) {
      final text = _decodeText(bytes);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(name, style: const TextStyle(fontSize: 14)),
          content: SizedBox(
            width: 640,
            height: 480,
            child: SingleChildScrollView(
              child: SelectableText(text,
                  style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', height: 1.45)),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localizations.close))],
        ),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(localizations.mediaUnsupported), duration: const Duration(seconds: 2)),
    );
  }

  /// 文本解码：UTF-8 优先，失败退容错 UTF-8，再退 latin1（保证一定能显示）。
  static String _decodeText(Uint8List bytes) {
    final limit = bytes.length > 400 * 1024 ? Uint8List.sublistView(bytes, 0, 400 * 1024) : bytes;
    try {
      return utf8.decode(limit);
    } catch (_) {
      try {
        return utf8.decode(limit, allowMalformed: true);
      } catch (_) {
        return latin1.decode(limit, allowInvalid: true);
      }
    }
  }
}
