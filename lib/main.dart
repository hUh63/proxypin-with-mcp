/*
 * Copyright 2023 Hongen Wang All rights reserved.
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/mcp/transport/mcp_stdio_bridge.dart';
import 'package:proxypin/network/components/manager/environment_manager.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/backup_service.dart';
import 'package:proxypin/ui/component/log_viewer_page.dart' show LogManager, LogLevel;
import 'package:proxypin/ui/mobile/setting/mcp_connection.dart';
import 'package:proxypin/network/util/mtls.dart';
import 'package:proxypin/network/rules/websocket_rule_manager.dart';
import 'package:proxypin/network/util/root_proxy.dart';
import 'package:proxypin/ui/component/chinese_font.dart';
import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:proxypin/ui/component/multi_window.dart';
import 'package:proxypin/ui/component/splash_banner.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/desktop/desktop.dart';
import 'package:proxypin/ui/mobile/mobile.dart';
import 'package:proxypin/utils/desktop_support.dart';
import 'package:proxypin/utils/navigator.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/app_localizations.dart';

///主入口
///@author wanghongen
void main(List<String> args) async {
  // MCP stdio 转发进程：不初始化任何 GUI/Rust，直接转发到 App 内 HTTP bridge
  if (args.contains('--mcp-stdio')) {
    await McpStdioBridge.run(args);
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();
  try {
    await RustLib.init();
  } catch (e) {
    // code_forge Rust FFI initialization may fail on iOS 14.x due to
    // deployment-target / cargokit-build incompatibilities. Degrade
    // gracefully instead of crashing the whole app at startup.
    logger.w('RustLib.init failed: $e');
  }

  // 上游 #839 FR2：清理上次异常退出遗留的 root 抓包重定向规则。
  // 残留规则的表现是“连着 WiFi 但所有 App 上不了网”，必须在启动时兜住；
  // 没开过 root 模式的用户不会被唤起 su 授权框（内部有标记判断）。
  unawaited(RootProxy.cleanupIfNeeded());

  // 上游 #839 FR1：提前加载 WebSocket 帧级规则。
  // 以前只有打开过“WebSocket 拦截”页面才会 init，
  // 导致应用刚启动时规则列表是空的、帧操纵不生效。
  unawaited(WebSocketRuleManager().init());

  // 自动备份：旧实现 autoBackupConfig() 有实现、有开关，却全仓没有调用点，
  // 所以「自动备份」从来没触发过。这里按配置的间隔在启动后补一次。
  unawaited(BackupService.autoBackupNow());

  // 把运行日志同步进内存队列，供「工具箱 → 日志」页实时查看
  logBridge = (level, message, error, stackTrace) {
    LogManager().addLog(
      switch (level) {
        Level.debug => LogLevel.debug,
        Level.warning => LogLevel.warning,
        Level.error => LogLevel.error,
        _ => LogLevel.info,
      },
      'app',
      message,
      stackTrace: stackTrace?.toString(),
    );
  };

  // 原生（悬浮球面板「MCP 设置」等）请求跳转 MCP 设置页
  const MethodChannel('com.proxy/toFlutter').setMethodCallHandler((call) async {
    if (call.method == 'openMcpSettings' && Platform.isAndroid) {
      final nav = navigatorHelper.navigatorKey.currentState;
      if (nav == null) return;
      await nav.push(MaterialPageRoute(
          builder: (_) => const McpConnectionPage()));
    } else if (call.method == 'floatingBallConfigChanged') {
      // 悬浮球面板原生直写偏好后，同步 Dart 侧 SharedPreferences 内存缓存，
      // 避免设置页读到旧值（如"关闭后自动启用"）
      final m = (call.arguments is Map) ? (call.arguments as Map) : null;
      if (m == null) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        if (m['enabled'] is bool) {
          await prefs.setBool('floatingBallEnabled', m['enabled'] as bool);
        }
        if (m['autoDock'] is bool) {
          await prefs.setBool('floatingBallAutoDock', m['autoDock'] as bool);
        }
        if (m['color'] is int) {
          await prefs.setInt('floatingBallColor', m['color'] as int);
        }
        if (m['alpha'] is int) {
          await prefs.setInt('floatingBallAlpha', m['alpha'] as int);
        }
      } catch (_) {}
    }
  });

  // 冷启动自动恢复悬浮球：仅当用户开启过才随应用启动（默认关闭不打扰）；
  // 必须在启动早期执行，避免"重进设置页才出现"
  if (Platform.isAndroid) {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('floatingBallEnabled') ?? false) {
        await const MethodChannel('com.proxy/floatingBall').invokeMethod('start', {
          'autoDock': prefs.getBool('floatingBallAutoDock') ?? true,
          'color': prefs.getInt('floatingBallColor') ?? 0xFF6750A4,
          'alpha': prefs.getInt('floatingBallAlpha') ?? 255,
          'running': false,
          'silent': true, // 无悬浮窗权限时静默跳过，不跳系统设置打扰
        });
      }
    } catch (_) {/* 插件未就绪或失败不影响启动 */}
  }

  final windowController = Platforms.isDesktop() ? await DesktopMultiWindow.ensureInitialized() : null;

  var instance = AppConfiguration.instance;

  //多窗口
  if (args.firstOrNull == 'multi_window') {
    final windowId = windowController!.windowId;
    final argument =
        windowController.arguments.isEmpty ? const {} : jsonDecode(windowController.arguments) as Map<String, dynamic>;
    DesktopMultiWindow.initializeFromArguments(argument);
    var appConfiguration = await instance;

    if (Platform.isMacOS) {
      windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }
    if (appConfiguration.themeMode != ThemeMode.system) {
      windowManager.setBrightness(appConfiguration.themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light);
    }
    runApp(FluentApp(multiWindow(windowId, argument), appConfiguration));
    return;
  }

  var configuration = Configuration.instance;
  // 预热环境变量,避免第一个请求命中时才 IO
  unawaited(EnvironmentManager.preload());
  // 恢复 mTLS 客户端证书（上游 #366）
  unawaited(() async {
    try {
      var config = await configuration;
      await Mtls.restore(config.mtlsChainPath, config.mtlsKeyPath);
    } catch (e) {
      logger.e('mTLS 证书恢复失败', error: e);
    }
  }());
  //移动端
  if (Platforms.isMobile()) {
    var appConfiguration = await instance;
    var config = await configuration;
    runApp(FluentApp(
        SplashGate(child: MobileHomePage(config, appConfiguration), appConfiguration: appConfiguration),
        appConfiguration));
    return;
  }

  var appConfiguration = await instance;
  if (Platforms.isDesktop()) {
    await DesktopSupport.initialize(appConfiguration);
  }

  runApp(FluentApp(DesktopHomePage(await configuration, appConfiguration), appConfiguration));
}

/// 启动页门控：先展示 SplashBanner（Logo 动画 + 版本信息），完成后切换到主页面。
/// 仅移动端启用（手机应用启动页符合用户预期；桌面端保持直接进入，不拖慢启动）。
/// 支持偏好设置自定义：开关、时长、背景（默认/自定义图片/透明）、自定义小字。
class SplashGate extends StatefulWidget {
  final Widget child;
  final AppConfiguration appConfiguration;

  const SplashGate({super.key, required this.child, required this.appConfiguration});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    if (!_showSplash) return widget.child;

    final config = widget.appConfiguration;
    // 总开关关闭：不做任何启动页，直接进入主界面
    if (!config.splashEnabled) {
      return widget.child;
    }
    // 背景选"原生启动页(off)"：不叠加品牌启动页，改为系统画面的延续——
    // 主题色背景 + 应用图标放大动画（跟随应用主题，含莫奈取色与深浅模式）
    if (config.splashBackground == 'off') {
      return NativeStyleSplash(
        onComplete: () {
          if (mounted) setState(() => _showSplash = false);
        },
      );
    }

    final backgroundFile =
        config.splashBackground == 'custom' && config.splashBackgroundPath != null
            ? File(config.splashBackgroundPath!)
            : null;

    return SplashBanner(
      duration: Duration(milliseconds: config.splashDurationMs.clamp(500, 10000)),
      backgroundMode: config.splashBackground,
      backgroundImage: backgroundFile,
      subtitle: config.splashSubtitle,
      onComplete: () {
        if (mounted) setState(() => _showSplash = false);
      },
    );
  }
}

class FluentApp extends StatelessWidget {
  final Widget home;
  final AppConfiguration appConfiguration;

  const FluentApp(this.home, this.appConfiguration, {super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
        valueListenable: appConfiguration.globalChange,
        builder: (_, current, __) {
          // 莫奈取色：Android 12+ 从壁纸提取动态色板（monetEnabled 关闭或低版本回退到固定主题）
          return DynamicColorBuilder(
              builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            final useMonet = appConfiguration.monetEnabled;
            final ThemeData lightTheme;
            final ThemeData darkTheme;
            if (useMonet && lightDynamic != null) {
              lightTheme = theme(Brightness.light)
                  .copyWith(colorScheme: lightDynamic.harmonized());
            } else {
              lightTheme = theme(Brightness.light);
            }
            if (useMonet && darkDynamic != null) {
              darkTheme = theme(Brightness.dark)
                  .copyWith(colorScheme: darkDynamic.harmonized());
            } else {
              darkTheme = theme(Brightness.dark);
            }
            return MaterialApp(
              title: 'ProxyPin',
              debugShowCheckedModeBanner: false,
              navigatorKey: navigatorHelper.navigatorKey,
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: appConfiguration.themeMode,
              locale: appConfiguration.language,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: home,
            );
          });
        });
  }

  ThemeData theme(Brightness brightness) {
    bool useMaterial3 = appConfiguration.useMaterial3;
    bool isDark = brightness == Brightness.dark;

    Color? themeColor = isDark ? appConfiguration.themeColor : appConfiguration.themeColor;
    Color? cardColor = isDark ? Color(0XFF3C3C3C) : Colors.white;
    Color? surfaceContainer = isDark ? Colors.grey[800] : Colors.white;

    Color? secondary = useMaterial3 ? null : themeColor;
    if (themeColor is MaterialColor) {
      secondary = themeColor[500];
    }

    var colorScheme = ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: themeColor,
      primary: themeColor,
      surface: cardColor,
      secondary: secondary,
      onPrimary: isDark ? Colors.white : null,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainer,
    );

    // 预测性返回：开启时使用 Material 3 预测返回页面转场（Android 14+ 生效，其他平台回退默认转场）
    final pageTransitions = appConfiguration.predictiveBackEnabled && !Platform.isWindows
        ? const PageTransitionsTheme(builders: {
            TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          })
        : null;

    var themeData = ThemeData(
      brightness: brightness,
      useMaterial3: appConfiguration.useMaterial3,
      colorScheme: colorScheme,
      // 仅开启预测性返回时覆盖 Android 页面转场；关闭时不设置，保留主题默认转场
      pageTransitionsTheme: pageTransitions,
    );

    if (!appConfiguration.useMaterial3) {
      themeData = themeData.copyWith(
        appBarTheme: themeData.appBarTheme.copyWith(
          iconTheme: themeData.iconTheme.copyWith(size: 20),
          backgroundColor: themeData.canvasColor,
          elevation: 0,
          titleTextStyle: themeData.textTheme.titleMedium,
        ),
        tabBarTheme: themeData.tabBarTheme.copyWith(
          labelColor: themeData.colorScheme.primary,
          indicatorColor: themeColor,
          unselectedLabelColor: themeData.textTheme.titleMedium?.color,
        ),
      );
    }

    if (Platform.isWindows) {
      themeData = themeData.useSystemChineseFont();
    }

    return themeData.copyWith(
        dialogTheme:
            themeData.dialogTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }
}
