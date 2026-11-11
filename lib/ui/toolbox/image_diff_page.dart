import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';

/// 图片对比（Kaleidoscope / Beyond Compare 的图片模式在手机上的版本）。
///
/// 文本对比管不了「截图和设计稿差在哪」这类活：改版前后各截一张、UI 还原度验收、
/// 同一个界面在两台设备上的渲染差异。逐像素比对的实现不需要解码成字节数组再算 ——
/// 直接把第二张图用 `BlendMode.difference` 画在第一张上面，相同处是黑的、
/// 有差异的地方自己会亮起来，GPU 顺手就做完了（大图也不卡）。
class ImageDiffPage extends StatefulWidget {
  const ImageDiffPage({super.key, this.initialLeft, this.initialRight});

  final String? initialLeft;
  final String? initialRight;

  static Future<void> show(BuildContext context, {String? left, String? right}) {
    return Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ImageDiffPage(initialLeft: left, initialRight: right)));
  }

  @override
  State<ImageDiffPage> createState() => _ImageDiffPageState();
}

class _ImageDiffPageState extends State<ImageDiffPage> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  ui.Image? _left;
  ui.Image? _right;
  String _leftName = '';
  String _rightName = '';
  int _leftBytes = 0;
  int _rightBytes = 0;

  /// 0 = 并排，1 = 叠加滑块，2 = 差异高亮
  int _mode = 0;

  /// 叠加模式下分界线的位置（0~1）。
  double _split = 0.5;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLeft != null) _loadPath(true, widget.initialLeft!);
    if (widget.initialRight != null) _loadPath(false, widget.initialRight!);
  }

  @override
  void dispose() {
    _left?.dispose();
    _right?.dispose();
    super.dispose();
  }

  String _baseName(String path) {
    final i = path.lastIndexOf(Platform.pathSeparator);
    return i >= 0 ? path.substring(i + 1) : path;
  }

  Future<void> _pick(bool left) async {
    String? path;
    try {
      final picked = await FilePicker.pickFile(type: FileType.image);
      path = picked?.path;
    } catch (_) {
      final picked = await FilePicker.pickFile();
      path = picked?.path;
    }
    if (path == null) return;
    await _loadPath(left, path);
  }

  Future<void> _loadPath(bool left, String path) async {
    setState(() => _busy = true);
    ui.Image? img;
    var bytes = 0;
    try {
      final file = File(path);
      if (!await file.exists()) {
        if (mounted) _toast(localizations.editorFileMissing);
        return;
      }
      final data = await file.readAsBytes();
      if (data.length > 64 * 1024 * 1024) {
        if (mounted) _toast(localizations.imageDiffTooLarge);
        return;
      }
      bytes = data.length;
      final codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      img = frame.image;
    } catch (e) {
      if (mounted) _toast('${localizations.fail}: $e');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) {
      img.dispose();
      return;
    }
    setState(() {
      if (left) {
        _left?.dispose();
        _left = img;
        _leftName = _baseName(path);
        _leftBytes = bytes;
      } else {
        _right?.dispose();
        _right = img;
        _rightName = _baseName(path);
        _rightBytes = bytes;
      }
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _swap() {
    setState(() {
      final img = _left;
      _left = _right;
      _right = img;
      final name = _leftName;
      _leftName = _rightName;
      _rightName = name;
      final b = _leftBytes;
      _leftBytes = _rightBytes;
      _rightBytes = b;
    });
  }

  static String _fmtBytes(int n) {
    if (n <= 0) return '-';
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.imageDiffTitle),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: localizations.imageDiffSwap,
            icon: const Icon(Icons.swap_horiz),
            onPressed: (_left == null && _right == null) ? null : _swap,
          ),
        ],
      ),
      body: Column(children: [
        _modeBar(),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _body()),
        _infoBar(),
      ]),
    );
  }

  /// 三个模式按钮用「图标 + tooltip」：小语种的「Side by side」这类标签
  /// 在 360dp 屏上会把 SegmentedButton 撑爆。
  Widget _modeBar() {
    final items = [
      (0, Icons.view_column_outlined, localizations.diffSideBySide),
      (1, Icons.vertical_split_outlined, localizations.imageDiffOverlay),
      (2, Icons.difference_outlined, localizations.imageDiffDifference),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
      child: Row(children: [
        for (final (i, icon, label) in items)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Tooltip(
              message: label,
              child: IconButton.filledTonal(
                isSelected: _mode == i,
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _mode = i),
                icon: Icon(icon),
              ),
            ),
          ),
        const Spacer(),
      ]),
    );
  }

  Widget _body() {
    if (_left == null && _right == null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.image_outlined, size: 44, color: Theme.of(context).hintColor),
          const SizedBox(height: 10),
          Text(localizations.imageDiffHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            FilledButton.tonalIcon(
              onPressed: () => _pick(true),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text(localizations.imageDiffPickLeft),
            ),
            const SizedBox(width: 10),
            FilledButton.tonalIcon(
              onPressed: () => _pick(false),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text(localizations.imageDiffPickRight),
            ),
          ]),
        ]),
      );
    }
    switch (_mode) {
      case 1:
        return _overlayView();
      case 2:
        return _differenceView();
      default:
        return _sideBySideView();
    }
  }

  Widget _pane(ui.Image? img, String name, bool left) {
    if (img == null) {
      return InkWell(
        onTap: () => _pick(left),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_photo_alternate_outlined, size: 26, color: Theme.of(context).hintColor),
            const SizedBox(height: 6),
            Text(left ? localizations.imageDiffPickLeft : localizations.imageDiffPickRight,
                style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
          ]),
        ),
      );
    }
    return InteractiveViewer(
      maxScale: 8,
      child: RawImage(image: img, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
    );
  }

  Widget _sideBySideView() {
    final theme = Theme.of(context);
    return Row(children: [
      Expanded(child: Column(children: [
        _nameBar(_leftName, true),
        Expanded(child: _pane(_left, _leftName, true)),
      ])),
      VerticalDivider(width: 1, thickness: 1, color: theme.dividerColor),
      Expanded(child: Column(children: [
        _nameBar(_rightName, false),
        Expanded(child: _pane(_right, _rightName, false)),
      ])),
    ]);
  }

  Widget _nameBar(String name, bool left) {
    return Container(
      height: 22,
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '—' : name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10.5, color: Theme.of(context).hintColor),
      ),
    );
  }

  /// 叠加：左图铺底、右图按分界线裁切盖在上面，拖中间的线看「哪块变了」。
  Widget _overlayView() {
    final a = _left;
    final b = _right;
    if (a == null || b == null) {
      return Center(
          child: Text(localizations.imageDiffNeedBoth,
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)));
    }
    return LayoutBuilder(builder: (context, c) {
      final x = c.maxWidth * _split;
      return Stack(fit: StackFit.expand, children: [
        RawImage(image: a, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
        ClipRect(
          clipper: _RightClipper(_split),
          child: RawImage(image: b, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
        ),
        // 分界线 + 拖动手柄（放在最上层，且用 opaque 命中测试抢在缩放之前）。
        Positioned(
          left: x - 14,
          top: 0,
          bottom: 0,
          width: 28,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) {
              setState(() => _split = (_split + d.delta.dx / c.maxWidth).clamp(0.02, 0.98));
            },
            child: Center(
              child: Container(
                width: 2,
                color: Theme.of(context).colorScheme.primary,
                child: Center(
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.drag_indicator,
                        size: 14, color: Theme.of(context).colorScheme.onPrimary),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]);
    });
  }

  /// 差异：第二张图用 difference 混合，相同处变黑、不同处自己亮起来。
  Widget _differenceView() {
    final a = _left;
    final b = _right;
    if (a == null || b == null) {
      return Center(
          child: Text(localizations.imageDiffNeedBoth,
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)));
    }
    return InteractiveViewer(
      maxScale: 8,
      child: SizedBox.expand(child: CustomPaint(painter: _DifferencePainter(a, b))),
    );
  }

  Widget _infoBar() {
    final a = _left;
    final b = _right;
    if (a == null && b == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final sizeA = a == null ? '-' : '${a.width}×${a.height}';
    final sizeB = b == null ? '-' : '${b.width}×${b.height}';
    final mismatch = a != null && b != null && (a.width != b.width || a.height != b.height);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'L: $sizeA · ${_fmtBytes(_leftBytes)}    R: $sizeB · ${_fmtBytes(_rightBytes)}',
          style: TextStyle(fontSize: 10.5, color: theme.hintColor),
        ),
        if (mismatch)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(localizations.imageDiffSizeMismatch,
                style: TextStyle(fontSize: 10.5, color: theme.colorScheme.error)),
          ),
      ]),
    );
  }
}

/// 只保留分界线右侧的部分。
class _RightClipper extends CustomClipper<Rect> {
  _RightClipper(this.split);

  final double split;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(size.width * split, 0, size.width, size.height);

  @override
  bool shouldReclip(covariant _RightClipper oldClipper) => oldClipper.split != split;
}

/// 差异画笔：A 打底，B 用 difference 混上去。
///
/// 两张图尺寸不同时都按 `BoxFit.cover` 拉进同一个矩形 —— 会轻微失真，但
/// 「同一张图的两版」几乎总是同尺寸，真不同尺寸时至少能一眼看出来。
class _DifferencePainter extends CustomPainter {
  _DifferencePainter(this.a, this.b);

  final ui.Image a;
  final ui.Image b;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF000000);
    canvas.drawRect(Offset.zero & size, bg);
    final srcA = Rect.fromLTWH(0, 0, a.width.toDouble(), a.height.toDouble());
    final srcB = Rect.fromLTWH(0, 0, b.width.toDouble(), b.height.toDouble());
    final dst = _cover(a.width / a.height, size);
    canvas.drawImageRect(a, srcA, dst, Paint()..filterQuality = FilterQuality.medium);
    canvas.drawImageRect(
        b,
        srcB,
        dst,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..blendMode = BlendMode.difference);
  }

  /// BoxFit.cover 的目标矩形。
  Rect _cover(double ratio, Size size) {
    final boxRatio = size.width / size.height;
    double w;
    double h;
    if (ratio > boxRatio) {
      h = size.height;
      w = h * ratio;
    } else {
      w = size.width;
      h = w / ratio;
    }
    return Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);
  }

  @override
  bool shouldRepaint(covariant _DifferencePainter oldDelegate) =>
      oldDelegate.a != a || oldDelegate.b != b;
}
