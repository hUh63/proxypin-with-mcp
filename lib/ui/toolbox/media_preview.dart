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

// 图片 / 动图 / 视频 / 音频的本地预览。
//
// 编辑器以前只会把文件当文本打开，二进制一进去就是乱码。这里按扩展名分流：
//   * 图片（png/jpg/gif/webp/bmp/ico…）→ 直接渲染。**GIF/WebP 动图自动播放**，
//     因为它就是 Image.file，Flutter 自己会跑帧；
//   * 视频 / 音频 → 显示元信息，并交给系统播放器打开（不引入原生播放器依赖，
//     否则 Windows/Linux 又要各写一套）。
//
// 另外给一个「透明背景棋盘格」，看 PNG 的透明通道时不会被白底骗过去。
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:url_launcher/url_launcher.dart';

/// 媒体类型。
enum MediaKind { image, video, audio, unsupported }

/// 按扩展名判断媒体类型。
MediaKind mediaKindOf(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  const image = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'wbmp'};
  const video = {'mp4', 'm4v', 'mov', 'mkv', 'webm', 'avi', 'flv', 'ts', '3gp'};
  const audio = {'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'opus'};
  if (image.contains(ext)) return MediaKind.image;
  if (video.contains(ext)) return MediaKind.video;
  if (audio.contains(ext)) return MediaKind.audio;
  return MediaKind.unsupported;
}

/// 是否是「可以内置预览的媒体文件」。
bool isPreviewableMedia(String path) => mediaKindOf(path) != MediaKind.unsupported;

/// 媒体预览页。
class MediaPreviewPage extends StatefulWidget {
  final File file;

  /// 可选的标题（默认取文件名）。
  final String? title;

  const MediaPreviewPage({super.key, required this.file, this.title});

  static Future<void> show(BuildContext context, File file, {String? title}) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MediaPreviewPage(file: file, title: title),
    ));
  }

  @override
  State<MediaPreviewPage> createState() => _MediaPreviewPageState();
}

class _MediaPreviewPageState extends State<MediaPreviewPage> {
  late MediaKind _kind = mediaKindOf(widget.file.path);
  bool _fitWidth = true;
  int? _width;
  int? _height;
  int _bytes = 0;
  String? _error;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final stat = await widget.file.stat();
      if (!mounted) return;
      setState(() => _bytes = stat.size);
    } catch (_) {}
    if (_kind != MediaKind.image) return;
    // 只给「不算大」的图片读尺寸，避免把几百 MB 的图整块读进内存。
    if (_bytes > 24 * 1024 * 1024) return;
    try {
      final Uint8List bytes = await widget.file.readAsBytes();
      final ui.Image image = await decodeImageFromList(bytes);
      if (!mounted) return;
      setState(() {
        _width = image.width;
        _height = image.height;
      });
      image.dispose();
    } catch (e) {
      logger.w('media preview: cannot decode ${widget.file.path}: $e');
    }
  }

  String get _name {
    final path = widget.file.path;
    final slash = path.lastIndexOf(Platform.pathSeparator);
    return slash < 0 ? path : path.substring(slash + 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? _name,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
        actions: [
          if (_kind == MediaKind.image)
            IconButton(
              tooltip: _fitWidth ? localizations.mediaActualSize : localizations.mediaFitWidth,
              icon: Icon(_fitWidth ? Icons.fit_screen : Icons.crop_original, size: 18),
              onPressed: () => setState(() => _fitWidth = !_fitWidth),
            ),
          if (_kind == MediaKind.video || _kind == MediaKind.audio)
            IconButton(
              tooltip: localizations.mediaOpenExternal,
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: _openExternal,
            ),
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
      body: Column(children: [
        Expanded(child: _body(theme)),
        _infoBar(theme),
      ]),
    );
  }

  Widget _body(ThemeData theme) {
    switch (_kind) {
      case MediaKind.image:
        final image = Image.file(
          widget.file,
          fit: _fitWidth ? BoxFit.fitWidth : BoxFit.none,
          alignment: Alignment.topCenter,
          errorBuilder: (c, e, s) => _errorBox(theme, '$e'),
        );
        return Container(
          color: theme.brightness == Brightness.dark ? const Color(0xFF1B1B1B) : const Color(0xFFF2F2F2),
          child: CustomPaint(
            // 棋盘格底：透明 PNG / 动图能看出透明区域
            painter: _CheckerPainter(),
            child: InteractiveViewer(
              maxScale: 8,
              child: Center(
                child: _fitWidth
                    ? SizedBox(width: double.infinity, child: image)
                    : SingleChildScrollView(
                        child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: image),
                      ),
              ),
            ),
          ),
        );
      case MediaKind.video:
      case MediaKind.audio:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(_kind == MediaKind.video ? Icons.movie_outlined : Icons.audiotrack_outlined,
                  size: 52, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(_name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              Text(localizations.mediaPlayHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: theme.textTheme.bodySmall?.color)),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _openExternal,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(localizations.mediaOpenExternal),
              ),
            ]),
          ),
        );
      case MediaKind.unsupported:
        return Center(child: Text(localizations.mediaUnsupported, style: const TextStyle(fontSize: 13)));
    }
  }

  Widget _errorBox(ThemeData theme, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.broken_image_outlined, size: 40, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: theme.colorScheme.outline)),
        ]),
      ),
    );
  }

  Widget _infoBar(ThemeData theme) {
    final parts = <String>[
      _sizeText(_bytes),
      if (_width != null && _height != null) '$_width × $_height',
      _kind.name,
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.6)),
      ),
      child: Text(parts.join(' · '),
          style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color)),
    );
  }

  static String _sizeText(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  /// 交系统播放器打开。
  ///
  /// 故意不内置 video_player：它在 Windows / Linux 上要额外装原生实现，
  /// 一个「看一眼」的功能不值得为它加平台分支。桌面端 file:// 打开是可靠的；
  /// 手机上系统不允许直接开 file://，那就明确提示走分享/导出。
  Future<void> _openExternal() async {
    final uri = Uri.file(widget.file.path);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (e) {
      logger.w('media preview: open external failed: $e');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(localizations.mediaOpenExternalFailed), duration: const Duration(seconds: 2)),
    );
  }
}

/// 透明背景棋盘格。
class _CheckerPainter extends CustomPainter {
  static const double _cell = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()..color = const Color(0xFFFFFFFF);
    final dark = Paint()..color = const Color(0xFFE6E6E6);
    canvas.drawRect(Offset.zero & size, light);
    final cols = (size.width / _cell).ceil();
    final rows = (size.height / _cell).ceil();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        if ((x + y).isEven) continue;
        canvas.drawRect(Rect.fromLTWH(x * _cell, y * _cell, _cell, _cell), dark);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
