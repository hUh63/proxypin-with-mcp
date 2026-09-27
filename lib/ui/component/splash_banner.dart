/*
 * 启动页 - 克制、有质感的品牌呈现
 *
 * 设计原则（去"AI 味"）：
 * - 不做花哨轮播/弹跳动效，只保留一次干净的淡入上移
 * - 配色从主题 colorScheme.primary 派生（开启莫奈取色时自动跟随壁纸色）
 * - 层级：Logo → 名称 → 一行小字 → 底部细进度条，留白呼吸
 *
 * 背景模式（splashBackground）：
 * - off          原生启动页（默认，不叠加自定义启动页）
 * - gradient     主题色渐变（莫奈取色时跟随壁纸）
 * - custom       自定义图片（加深色遮罩保证可读）
 * - transparent  跟随应用主题背景
 */

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/configuration.dart';

class SplashBanner extends StatefulWidget {
  final VoidCallback? onComplete;
  final Duration duration;

  /// 背景模式：gradient 主题色渐变 / custom 自定义图片 / transparent 跟随主题
  final String backgroundMode;

  /// 自定义背景图片文件（backgroundMode == custom 时使用）
  final File? backgroundImage;

  /// 自定义小字文本（为空时显示版本信息）
  final String? subtitle;

  const SplashBanner({
    super.key,
    this.onComplete,
    this.duration = const Duration(milliseconds: 1800),
    this.backgroundMode = 'gradient',
    this.backgroundImage,
    this.subtitle,
  });

  @override
  State<SplashBanner> createState() => _SplashBannerState();
}

class _SplashBannerState extends State<SplashBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _offset;
  bool _exiting = false;
  Timer? _doneTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 620));
    final curve =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _opacity = Tween(begin: 0.0, end: 1.0).animate(curve);
    _offset = Tween(begin: 14.0, end: 0.0).animate(curve);
    _controller.forward();

    // 展示时长到达后：先淡出 260ms，再交还主页面，避免切换生硬
    _doneTimer = Timer(widget.duration, () {
      if (!mounted) return;
      setState(() => _exiting = true);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) widget.onComplete?.call();
      });
    });
  }

  @override
  void dispose() {
    _doneTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mode = widget.backgroundMode;
    final hasImage = mode == 'custom' && widget.backgroundImage != null;

    // 前景色：跟随主题模式下用主题前景色（随主题/深浅模式变化）
    final Color foreground =
        (mode == 'transparent') ? cs.onSurface : Colors.white;

    Widget? backgroundLayer;
    if (hasImage) {
      backgroundLayer = Stack(fit: StackFit.expand, children: [
        Image.file(widget.backgroundImage!, fit: BoxFit.cover),
        // 遮罩 + 底部渐晕，保证文字与小字可读且不生硬
        Container(color: Colors.black.withValues(alpha: 0.45)),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.5, 1.0],
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.35),
              ],
            ),
          ),
        ),
      ]);
    } else if (mode == 'gradient') {
      // 主题色（莫奈取色时为壁纸派生色）135° 深浅渐变，克制而有层次
      final base = cs.primary;
      final deep = Color.lerp(base, Colors.black, 0.42)!;
      final mid = Color.lerp(base, Colors.black, 0.18)!;
      backgroundLayer = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.55, 1.0],
            colors: [deep, mid, base],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: mode == 'transparent'
          ? Theme.of(context).scaffoldBackgroundColor
          : null,
      body: Stack(fit: StackFit.expand, children: [
        if (backgroundLayer != null) backgroundLayer,
        SafeArea(
          child: AnimatedOpacity(
            opacity: _exiting ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(children: [
                const Spacer(flex: 5),
                FadeTransition(
                  opacity: _opacity,
                  child: AnimatedBuilder(
                    animation: _offset,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(0, _offset.value),
                      child: child,
                    ),
                    child: Column(children: [
                      // Logo：主色低饱和容器，去白底与重阴影
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: (mode == 'transparent'
                                  ? cs.primary
                                  : Colors.white)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: (mode == 'transparent'
                                    ? cs.primary
                                    : Colors.white)
                                .withValues(alpha: 0.22),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.security,
                          size: 38,
                          color: mode == 'transparent'
                              ? cs.primary
                              : Colors.white,
                        ),
                      ),
                      const SizedBox(height: 30),
                      // 应用名：细字重 + 宽字距，安静高级
                      Text(
                        'ProxyPin',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w300,
                          color: foreground,
                          letterSpacing: 7,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.subtitle?.isNotEmpty == true
                            ? widget.subtitle!
                            : AppLocalizations.of(context)!.splashSubtitle(AppConfiguration.version),
                        style: TextStyle(
                          fontSize: 13,
                          color: foreground.withValues(alpha: 0.72),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ]),
                  ),
                ),
                const Spacer(flex: 6),
                // 底部：细进度条 + 版权，替代"特性轮播"
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    valueColor:
                        AlwaysStoppedAnimation(foreground.withValues(alpha: 0.85)),
                    backgroundColor: foreground.withValues(alpha: 0.14),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'ProxyPin Open Source',
                  style: TextStyle(
                    fontSize: 11,
                    color: foreground.withValues(alpha: 0.45),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 22),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// 原启动页（off 模式）：系统启动画面的无缝延续。
/// - 背景跟随应用主题 surface（深浅模式 / 莫奈取色自动变化）
/// - 应用图标一次克制的放大动画（系统画面是静态图标，这里完成"放大"瞬间）
/// - 无文字、无进度条，动画结束立即进入主界面
class NativeStyleSplash extends StatefulWidget {
  final VoidCallback? onComplete;

  const NativeStyleSplash({super.key, this.onComplete});

  @override
  State<NativeStyleSplash> createState() => _NativeStyleSplashState();
}

class _NativeStyleSplashState extends State<NativeStyleSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _exiting = false;
  bool _started = false;
  Timer? _doneTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 560));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // 预载透明底图标（icon_foreground.png，95% 透明）后再开始放大动画：
    // 透明底 + srcIn 染色只染图案本身，保留 ∞ 图形并随主题色变化；
    // 若用不透明 icon.png 整体染色会变成纯色块，图案会消失
    precacheImage(const AssetImage('assets/icon_foreground.png'), context)
        .whenComplete(() {
      if (!mounted) return;
      _controller.forward();
      // 放大完成后淡出交还主界面，整体约 1 秒，接近系统启动画面的自然衔接
      _doneTimer = Timer(const Duration(milliseconds: 780), () {
        if (!mounted) return;
        setState(() => _exiting = true);
        Future.delayed(const Duration(milliseconds: 180), () {
          if (mounted) widget.onComplete?.call();
        });
      });
    });
  }

  @override
  void dispose() {
    _doneTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final curve =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: AnimatedOpacity(
          opacity: _exiting ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: ScaleTransition(
            scale: Tween(begin: 0.55, end: 1.0).animate(curve),
            child: Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                // 圆角正方形底（与自适应图标一致的视觉语言）
                color: cs.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                    color: cs.primary.withValues(alpha: 0.28), width: 1.5),
              ),
              alignment: Alignment.center,
              // 图标随主题色/莫奈取色染色（与 Android 13 themed icon 同风格）：
              // 冷启动系统画面为静态彩色图标，进入应用后由此处即时跟随主题
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(cs.primary, BlendMode.srcIn),
                child: Image.asset('assets/icon_foreground.png',
                    width: 64, height: 64),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
