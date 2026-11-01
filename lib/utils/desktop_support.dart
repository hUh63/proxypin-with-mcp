import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/desktop/window_listener.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../network/util/logger.dart';
import '../ui/component/multi_window.dart';

class DesktopSupport {
  static const _minimumWindowSize = Size(1000, 600);

  static Future<void> initialize(AppConfiguration appConfiguration) async {
    try {
      await windowManager.ensureInitialized();

      final defaultWindowSize = Platform.isMacOS ? const Size(1230, 750) : const Size(1100, 650);
      final windowSize = _sanitizeWindowSize(appConfiguration.windowSize, defaultWindowSize);
      appConfiguration.windowSize = windowSize;

      final windowOptions = WindowOptions(
        minimumSize: _minimumWindowSize,
        size: windowSize,
        titleBarStyle: TitleBarStyle.hidden,
      );
      if (appConfiguration.themeMode != ThemeMode.system) {
        await windowManager
            .setBrightness(appConfiguration.themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light);
      }

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        final position = appConfiguration.windowPosition;
        if (position != null && await _isPositionVisible(position, windowSize)) {
          await windowManager.setPosition(position);
        } else {
          if (position != null) {
            appConfiguration.windowPosition = null;
          }
          //位置无效(如显示器已断开)时居中显示，避免窗口跑到屏幕外不可见
          await windowManager.center();
        }

        await windowManager.show();
        await windowManager.focus();

        // 兜底：某些多屏 / DPI 组合下，setPosition 完成后窗口仍落在可视区外
        // （setPosition 用的是逻辑像素，副屏缩放比不同时会被换算到屏幕外）。
        // 1.2 秒后再确认一次，不在可见区就居中重开。
        Future.delayed(const Duration(milliseconds: 1200), () async {
          try {
            final visible = await windowManager.isVisible();
            final pos = await windowManager.getPosition();
            final size = await windowManager.getSize();
            if (visible && await _isPositionVisible(pos, size)) return;
            logger.w('Window not visible after show (pos=$pos size=$size), recentering');
            await windowManager.center();
            await windowManager.show();
            await windowManager.focus();
          } catch (e) {
            logger.w('window visibility fallback failed: $e');
          }
        });
      });

      windowManager.addListener(WindowChangeListener(appConfiguration));
      registerMethodHandler();
    } catch (e) {
      logger.e('Error during desktop initialization: $e');
    }
  }

  /// 把窗口拉回主屏居中，并清掉保存的位置（设置页的「重置窗口位置」）。
  static Future<void> resetWindowPosition(AppConfiguration appConfiguration) async {
    appConfiguration.windowPosition = null;
    appConfiguration.flushConfig();
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  /// 修复配置文件中可能残留的无效窗口尺寸。
  ///
  /// 旧配置可能包含 0、负数、NaN、Infinity 或远大于当前显示器的尺寸。
  /// 这些值会被 window_manager 直接用于创建窗口，Windows 上可能表现为
  /// 白屏、窗口不可见或 Flutter surface 无法正常布局。
  static Size _sanitizeWindowSize(Size? savedSize, Size defaultSize) {
    if (savedSize == null || !savedSize.width.isFinite || !savedSize.height.isFinite) {
      return defaultSize;
    }

    final width = savedSize.width.clamp(_minimumWindowSize.width, 3840.0);
    final height = savedSize.height.clamp(_minimumWindowSize.height, 2160.0);
    final sanitized = Size(width.toDouble(), height.toDouble());

    if (sanitized != savedSize) {
      logger.w('Invalid saved window size $savedSize, using $sanitized');
    }
    return sanitized;
  }

  /// 校验保存的窗口位置是否落在某个显示器的可见范围内。
  /// 显示器断开或分辨率变化后，旧位置可能在所有屏幕之外，导致窗口不可见。
  static Future<bool> _isPositionVisible(Offset position, Size windowSize) async {
    try {
      final displays = await screenRetriever.getAllDisplays();
      if (displays.isEmpty || !position.dx.isFinite || !position.dy.isFinite) return false;

      // 判定改成「标题栏与显示器要有足够重叠」：
      // 只看左上角点不够 —— 多屏 + 不同缩放比时窗口宽度会变，左上角刚好压在
      // 某个显示器边缘、实际内容整块落在屏幕外，用户看到的就是「打开了但没窗口」
      // （上游 #984）。
      const titleBarHeight = 40.0;
      const minOverlapW = 120.0;
      const minOverlapH = 20.0;
      for (final display in displays) {
        final origin = display.visiblePosition ?? Offset.zero;
        final size = display.visibleSize ?? display.size;
        final left = origin.dx;
        final top = origin.dy;
        final right = left + size.width;
        final bottom = top + size.height;

        final overlapW = min(position.dx + windowSize.width, right) - max(position.dx, left);
        final overlapH = min(position.dy + titleBarHeight, bottom) - max(position.dy, top);
        if (overlapW >= minOverlapW && overlapH >= minOverlapH) {
          return true;
        }
      }
      return false;
    } catch (e) {
      logger.e("Error validating window position: $e");
      // 校验失败时不使用保存的位置，回退到居中显示。
      return false;
    }
  }
}
