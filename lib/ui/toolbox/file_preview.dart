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

// 通用「文件预览」入口：拿到一个文件，按类型挑最合适的看板。
//
//   * 图片 / 动图 / 视频 / 音频 → 媒体预览页
//   * zip / jar / apk / docx / tar.gz → 压缩包条目页
//   * html / htm              → 网页渲染（可切源码）
//   * 文本类（txt / log / md / json / xml / 代码…）→ 只读文本查看（可一键丢进编辑器）
//   * 其余二进制              → 明确说明，并给前 512 字节的十六进制，方便判断真实类型
//
// 工具箱的「文件预览」和文本编辑器的「打开文件」都走这里，省得两处各判一遍。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/toolbox/archive_preview.dart';
import 'package:proxypin/ui/toolbox/html_preview.dart';
import 'package:proxypin/ui/toolbox/media_preview.dart';
import 'package:proxypin/ui/toolbox/text_editor.dart';

/// 文件类别（决定用哪个预览页）。
enum FilePreviewKind { media, archive, html, text, binary }

/// 文本类扩展名。
final RegExp _textExt = RegExp(
    r'\.(txt|log|md|markdown|json|jsonc|xml|ya?ml|toml|ini|conf|cfg|properties|env|csv|tsv|'
    r'js|mjs|cjs|jsx|ts|tsx|css|scss|less|html?|vue|svelte|py|java|kt|kts|cs|c|cc|cpp|h|hpp|'
    r'go|rs|rb|php|lua|swift|dart|sh|bash|zsh|bat|ps1|sql|gradle|pro|make|cmake|dockerfile|'
    r'http|har|pem|crt|cer|key|txt)$');

/// 按扩展名判断用哪个预览页。
FilePreviewKind filePreviewKindOf(String path) {
  if (isArchiveFile(path)) return FilePreviewKind.archive;
  if (isPreviewableMedia(path)) return FilePreviewKind.media;
  final lower = path.toLowerCase();
  if (lower.endsWith('.html') || lower.endsWith('.htm') || lower.endsWith('.svg')) {
    return FilePreviewKind.html;
  }
  if (_textExt.hasMatch(lower)) return FilePreviewKind.text;
  return FilePreviewKind.binary;
}

/// 统一预览入口。
class FilePreviewPage {
  FilePreviewPage._();

  /// 打开一个文件的预览。返回值在用户关闭预览后完成。
  static Future<void> show(BuildContext context, File file, {String? title}) async {
    final path = file.path;
    final kind = filePreviewKindOf(path);
    switch (kind) {
      case FilePreviewKind.media:
        await MediaPreviewPage.show(context, file, title: title);
      case FilePreviewKind.archive:
        await ArchivePreviewPage.show(context, file);
      case FilePreviewKind.html:
        String content;
        try {
          content = await _readText(file);
        } catch (e) {
          logger.w('file preview: read failed $e');
          if (!context.mounted) return;
          await _showBinary(context, file);
          return;
        }
        if (!context.mounted) return;
        await HtmlPreviewPage.show(context, content: content, language: 'html', title: title ?? _baseName(path));
      case FilePreviewKind.text:
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TextViewerPage(file: file, title: title ?? _baseName(path)),
        ));
      case FilePreviewKind.binary:
        await _showBinary(context, file);
    }
  }

  /// 预览一段**内存里的字节**（抓包响应体就是这么来的）。
  ///
  /// 落到临时文件后复用同一套分流逻辑——视频/压缩包本来就要「有个文件」才能交给
  /// 系统播放器或解压器，所以这里不另写一套内存渲染。
  static Future<void> showBytes(
    BuildContext context,
    List<int> bytes, {
    required String fileName,
    String? contentType,
  }) async {
    if (bytes.isEmpty) return;
    // 文件名来自 HTTP 头（content-disposition），不可信：可能带路径分隔符，
    // 直接拼进临时路径会写到目录外，甚至失败。
    final name = _withExtension(_safeName(fileName), contentType);
    await _sweepTemp();
    try {
      final dir = Directory.systemTemp;
      final file = File('${dir.path}${Platform.pathSeparator}pv_'
          '${DateTime.now().millisecondsSinceEpoch}_$name');
      await file.writeAsBytes(bytes, flush: true);
      if (!context.mounted) return;
      await show(context, file, title: name);
    } catch (e) {
      logger.w('file preview: showBytes failed $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.mediaUnsupported),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  static bool _swept = false;

  /// 清掉上次运行遗留的预览临时文件。
  ///
  /// 不能「关掉预览就删」：音视频是交给系统播放器打开的，删早了播放器就读不到。
  /// 所以改成会话内第一次落临时文件前，清掉 1 小时前的旧文件——反复预览大视频
  /// 不会把临时目录堆满。
  static Future<void> _sweepTemp() async {
    if (_swept) return;
    _swept = true;
    try {
      final dir = Directory.systemTemp;
      if (!await dir.exists()) return;
      final cutoff = DateTime.now().subtract(const Duration(hours: 1));
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        if (!_baseName(entity.path).startsWith('pv_')) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) await entity.delete();
        } catch (_) {
          // 单个文件删不掉不影响预览。
        }
      }
    } catch (_) {
      // 临时目录不可读也不影响预览。
    }
  }

  /// 把 HTTP 头里来的文件名洗成能安全拼进临时路径的形式。
  static final RegExp _unsafeName = RegExp(r'[<>:"/\\|?*\x00-\x1f]');

  static String _safeName(String raw) {
    var name = raw.replaceAll(_unsafeName, '_').trim();
    // 去掉可能残留的 ../ 与开头结尾的点
    name = name.replaceAll(RegExp(r'\.\.'), '_');
    name = name.replaceAll(RegExp(r'^\.+'), '');
    if (name.isEmpty) return 'preview';
    if (name.length > 80) {
      final dot = name.lastIndexOf('.');
      if (dot > 0 && name.length - dot <= 10) {
        name = '${name.substring(0, 80 - (name.length - dot))}${name.substring(dot)}';
      } else {
        name = name.substring(0, 80);
      }
    }
    return name;
  }

  /// 名字里没扩展名时按 content-type 补一个，否则分流会判成「未知二进制」。
  static String _withExtension(String name, String? contentType) {
    if (name.contains('.')) return name;
    final type = (contentType ?? '').toLowerCase();
    if (type.contains('png')) return '$name.png';
    if (type.contains('jpeg') || type.contains('jpg')) return '$name.jpg';
    if (type.contains('gif')) return '$name.gif';
    if (type.contains('webp')) return '$name.webp';
    if (type.contains('svg')) return '$name.svg';
    if (type.contains('mp4')) return '$name.mp4';
    if (type.contains('webm')) return '$name.webm';
    if (type.contains('quicktime') || type.contains('mov')) return '$name.mov';
    if (type.contains('mpeg')) return '$name.mp3';
    if (type.contains('wav')) return '$name.wav';
    if (type.contains('zip')) return '$name.zip';
    if (type.contains('html')) return '$name.html';
    if (type.contains('json')) return '$name.json';
    return name;
  }

  static String _baseName(String path) {
    final slash = path.lastIndexOf(Platform.pathSeparator);
    return slash < 0 ? path : path.substring(slash + 1);
  }

  static Future<String> _readText(File file) async {
    final bytes = await file.readAsBytes();
    // 大文件只读前面一段：预览不需要全文，别把内存撑爆。
    final limit = bytes.length > 2 * 1024 * 1024 ? Uint8List.sublistView(bytes, 0, 2 * 1024 * 1024) : bytes;
    try {
      return utf8.decode(limit);
    } catch (_) {
      return utf8.decode(limit, allowMalformed: true);
    }
  }

  /// 未知二进制：说明 + 前 512 字节十六进制（能看出是不是 zip/png/elf 等）。
  static Future<void> _showBinary(BuildContext context, File file) async {
    String head = '';
    int length = 0;
    try {
      final raf = await file.open();
      try {
        final bytes = await raf.read(512);
        length = await raf.length();
        head = _hexDump(bytes);
      } finally {
        await raf.close();
      }
    } catch (e) {
      logger.w('file preview: hex dump failed $e');
    }
    if (!context.mounted) return;
    final localizations = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_baseName(file.path), style: const TextStyle(fontSize: 14)),
        content: SizedBox(
          width: 560,
          height: 360,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${localizations.mediaUnsupported} · ${_sizeText(length)}',
                style: const TextStyle(fontSize: 11.5)),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(head,
                    style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', height: 1.4)),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localizations.close)),
        ],
      ),
    );
  }

  static String _hexDump(Uint8List bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length; i += 16) {
      final end = (i + 16 <= bytes.length) ? i + 16 : bytes.length;
      final chunk = bytes.sublist(i, end);
      final hex = chunk.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      final ascii = chunk.map((b) => (b >= 32 && b < 127) ? String.fromCharCode(b) : '.').join();
      buffer.writeln('${i.toRadixString(16).padLeft(6, '0')}  ${hex.padRight(47)}  $ascii');
    }
    return buffer.toString();
  }

  static String _sizeText(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}

/// 只读文本查看器（带行号、搜索、丢进编辑器）。
class TextViewerPage extends StatefulWidget {
  final File file;
  final String title;

  const TextViewerPage({super.key, required this.file, required this.title});

  @override
  State<TextViewerPage> createState() => _TextViewerPageState();
}

class _TextViewerPageState extends State<TextViewerPage> {
  String? _text;
  String? _error;
  bool _truncated = false;
  int _bytes = 0;
  String _query = '';

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stat = await widget.file.stat();
      _bytes = stat.size;
      final bytes = await widget.file.readAsBytes();
      const limit = 4 * 1024 * 1024;
      final short = bytes.length > limit;
      final slice = short ? Uint8List.sublistView(bytes, 0, limit) : bytes;
      String text;
      try {
        text = utf8.decode(slice);
      } catch (_) {
        text = utf8.decode(slice, allowMalformed: true);
      }
      if (!mounted) return;
      setState(() {
        _text = text;
        _truncated = short;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _text;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
        actions: [
          if (text != null)
            IconButton(
              tooltip: localizations.textEditor,
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TextEditorPage(initialText: text),
              )),
            ),
          if (text != null)
            IconButton(
              tooltip: localizations.copy,
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(localizations.copied), duration: const Duration(milliseconds: 1200)),
                );
              },
            ),
        ],
      ),
      body: Column(children: [
        if (text != null)
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
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
        Expanded(child: _body(theme, text)),
        _footer(theme),
      ]),
    );
  }

  Widget _body(ThemeData theme, String? text) {
    if (_error != null) {
      return Center(
          child: Text(_error!, style: const TextStyle(fontSize: 12.5), textAlign: TextAlign.center));
    }
    if (text == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    final lines = text.split('\n');
    final hits = <int>[];
    if (_query.isNotEmpty) {
      final lower = _query.toLowerCase();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].toLowerCase().contains(lower)) hits.add(i);
      }
    }
    return ListView.builder(
      itemCount: hits.isEmpty ? lines.length : hits.length,
      itemBuilder: (context, i) {
        final index = hits.isEmpty ? i : hits[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0.5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 40,
              child: Text('${index + 1}',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 10, color: theme.textTheme.bodySmall?.color)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(lines[index],
                  style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', height: 1.45)),
            ),
          ]),
        );
      },
    );
  }

  Widget _footer(ThemeData theme) {
    final parts = <String>[
      FilePreviewPage._sizeText(_bytes),
      if (_query.isNotEmpty) '·',
      if (_query.isNotEmpty) _query,
      if (_truncated) '· first 4 MB',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.6)),
      ),
      child: Text(parts.join(' '), style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color)),
    );
  }
}
