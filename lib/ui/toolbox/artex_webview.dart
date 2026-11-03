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

// ARTEX 控制台 —— 直接跑 ARTEX 自己的前端（不是重画的界面）。
//
// ARTEX 2.2.7 的安卓端结构就是：assets 里放 Next.js 静态导出的整站 + 本地 HTTP
// 服务 + WebView。这里逐项照抄：
//   * `ArtexWebServer` 托管 assets/artex_web（含 /api 反代）；
//   * WebView 打开 `http://127.0.0.1:<port>/`，登录态/路由/主题全是原版；
//   * 顶部工具栏和后端地址对话框与官方 App 一致（后端地址可改、可留空跑离线演示）；
//   * 多一个「本地运行」：用 root 在 Termux 里起 PG + ARTEX，起来后自动重载，
//     等于把「软件里直接本地运行」补齐。
//
// 桌面端没有 WebView 实现（webview_flutter 只覆盖 Android/iOS/macOS），退回系统
// 浏览器打开同一个本地地址 —— 地址是 127.0.0.1，浏览器一样能用。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/util/artex_service.dart';
import 'package:proxypin/network/util/artex_web_server.dart';
import 'package:proxypin/ui/toolbox/artex_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ArtexWebPage extends StatefulWidget {
  const ArtexWebPage({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ArtexWebPage()),
    );
  }

  @override
  State<ArtexWebPage> createState() => _ArtexWebPageState();
}

class _ArtexWebPageState extends State<ArtexWebPage> {
  /// webview_flutter 只实现了这三个平台；其余走系统浏览器。
  static bool get _hasWebView => Platform.isAndroid || Platform.isIOS;

  WebViewController? _web;
  int _progress = 0;
  bool _starting = false;
  bool _backendUp = false;

  /// true = 用 App 内置服务端（独立运行）；false = 连外部 ARTEX 后端。
  bool _embedded = true;
  String _baseUrl = 'http://127.0.0.1:8787';

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    // 页面退出不停服务（返回再进来不用重起，WebView 也能秒开）；显式停由「更多」菜单做。
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    FlutterToastr.show(msg, context, duration: 2);
  }

  Future<void> _bootstrap() async {
    try {
      final conf = await Configuration.instance;
      _embedded = conf.artexEmbedded;
      _baseUrl = conf.artexBaseUrl.trim().isEmpty ? 'http://127.0.0.1:8787' : conf.artexBaseUrl.trim();
    } catch (_) {
      // 配置读不到就用默认值
    }
    final server = ArtexWebServer.instance;
    int port;
    try {
      port = await server.start(base: _embedded ? '' : _baseUrl);
    } catch (e) {
      if (!mounted) return;
      _toast('ARTEX web: $e');
      return;
    }
    await _probeBackend();
    if (!mounted) return;
    if (_hasWebView) {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Theme.of(context).colorScheme.surface)
        ..setNavigationDelegate(NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _progress = 0);
          },
          // localStorage 里存着 artex_token，必须开 DOM storage，否则每次都要重登
          onNavigationRequest: (req) {
            final url = req.url;
            if (url.startsWith('http://127.0.0.1:$port') || url.startsWith('about:') || url.startsWith('data:')) {
              return NavigationDecision.navigate;
            }
            // 站外链接（文档/下载）交给系统浏览器，别把 WebView 变成浏览器
            unawaited(_openExternal(url));
            return NavigationDecision.prevent;
          },
        ));
      // 老版本 Android 上 localStorage 需要手动开
      try {
        await controller.enableZoom(false);
      } catch (_) {}
      await controller.loadRequest(Uri.parse('http://127.0.0.1:$port/'));
      if (!mounted) return;
      setState(() => _web = controller);
    } else {
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _probeBackend() async {
    if (_embedded) {
      // 内置服务端由本进程提供，天然可用
      if (mounted) setState(() => _backendUp = true);
      return;
    }
    final base = _baseUrl.trim();
    if (base.isEmpty) {
      if (mounted) setState(() => _backendUp = false);
      return;
    }
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3)
        ..findProxy = ((_) => 'DIRECT')
        ..badCertificateCallback = (cert, host, port) => true;
      final req = await client.getUrl(Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/api/health'))
          .timeout(const Duration(seconds: 4));
      final resp = await req.close().timeout(const Duration(seconds: 4));
      await resp.drain<void>();
      if (mounted) setState(() => _backendUp = resp.statusCode >= 200 && resp.statusCode < 300);
    } catch (_) {
      if (mounted) setState(() => _backendUp = false);
    } finally {
      client?.close(force: true);
    }
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _reload() async {
    await _probeBackend();
    final web = _web;
    if (web != null) {
      await web.reload();
    } else {
      await _openExternal(ArtexWebServer.instance.origin);
    }
    if (mounted) setState(() {});
  }

  /// 后端地址（与官方 App 的「后端地址」对话框一致：留空 = 内置离线演示站）。
  Future<void> _editBackend() async {
    final loc = AppLocalizations.of(context)!;
    final ctrl = TextEditingController(text: _baseUrl);
    var useEmbedded = _embedded;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.artexBackendAddress),
        content: StatefulBuilder(
          builder: (ctx2, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: useEmbedded,
                title: Text(loc.artexEmbeddedMode,
                    style: const TextStyle(fontSize: 13.5)),
                subtitle: Text(loc.artexEmbeddedHint,
                    style: const TextStyle(fontSize: 11.5)),
                onChanged: (v) => setLocal(() => useEmbedded = v),
              ),
              if (!useEmbedded) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: 'http://127.0.0.1:8787',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(loc.artexBackendHint,
                    style: TextStyle(fontSize: 12, color: Theme.of(ctx).hintColor)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.save),
          ),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return;
    _embedded = useEmbedded;
    if (text.isNotEmpty) _baseUrl = text;
    ArtexWebServer.instance.proxyBase = useEmbedded ? '' : _baseUrl;
    try {
      final conf = await Configuration.instance;
      conf.artexEmbedded = useEmbedded;
      if (text.isNotEmpty) conf.artexBaseUrl = text;
      await conf.flushConfig();
    } catch (_) {}
    await _reload();
    if (mounted) _toast(useEmbedded ? loc.artexEmbeddedOn : loc.artexConnected);
  }

  /// 本地运行：起 PG + ARTEX，成功后自动重载（这就是「软件里直接跑起来」）。
  Future<void> _startLocal() async {
    final loc = AppLocalizations.of(context)!;
    if (!ArtexService.supported) {
      _toast(loc.artexNotAndroid);
      return;
    }
    if (_starting) return;
    setState(() => _starting = true);
    try {
      // 没有 root 就别让用户看一堆 ProcessException：直接切内置服务端
      final rooted = await ArtexService.hasRoot();
      if (!rooted) {
        await _switchToEmbedded(loc.artexNoRootSwitch);
        return;
      }
      var user = '';
      try {
        final conf = await Configuration.instance;
        user = conf.artexTermuxUser;
      } catch (_) {}
      if (user.trim().isEmpty) {
        final detected = await ArtexService.detectTermuxUser();
        if (detected.isNotEmpty) user = detected;
      }
      final pg = await ArtexService.startPg(user);
      final art = await ArtexService.startArtex(
        user,
        addr: _addrOf(_baseUrl, 8787),
        proxy: _addrOf(_baseUrl, 8788),
      );
      if (!mounted) return;
      // 起来需要一两秒（PG 先就绪 ARTEX 才连得上）
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await _probeBackend();
        if (_backendUp) break;
      }
      if (!mounted) return;
      if (pg.output.contains(ArtexService.noRootMarker) ||
          art.output.contains(ArtexService.noRootMarker)) {
        await _switchToEmbedded(loc.artexNoRootSwitch);
        return;
      }
      if (_backendUp) {
        _toast(loc.artexConnected);
        await _reload();
      } else {
        final tail = await ArtexService.tailLog(user, lines: 40);
        if (!mounted) return;
        final msg = [pg.output, art.output, tail.output].where((e) => e.trim().isNotEmpty).join('\n');
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(loc.artexStartFailed),
            content: SizedBox(
              width: double.maxFinite,
              height: 260,
              child: SingleChildScrollView(
                child: SelectableText(msg,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5)),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(loc.close),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// 切到内置服务端并重载（无 root / 外部后端不可用时用）。
  Future<void> _switchToEmbedded(String message) async {
    _embedded = true;
    ArtexWebServer.instance.proxyBase = '';
    try {
      final conf = await Configuration.instance;
      conf.artexEmbedded = true;
      await conf.flushConfig();
    } catch (_) {}
    await _probeBackend();
    await _reload();
    if (!mounted) return;
    _toast(message);
  }

  /// 从 baseUrl 里抠出「主机:端口」，端口按需替换。
  static String _addrOf(String baseUrl, int fallbackPort) {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null || uri.host.isEmpty) return '127.0.0.1:$fallbackPort';
    return '${uri.host}:${uri.hasPort ? uri.port : fallbackPort}';
  }

  Future<void> _menuAction(String action) async {
    final loc = AppLocalizations.of(context)!;
    switch (action) {
      case 'backend':
        await _editBackend();
        break;
      case 'local':
        await _startLocal();
        break;
      case 'browser':
        await _openExternal(ArtexWebServer.instance.origin);
        break;
      case 'native':
        await ArtexPage.show(context);
        break;
      case 'stop':
        await ArtexWebServer.instance.stop();
        if (!mounted) return;
        _toast(loc.artexServerStopped);
        await _bootstrap();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return PopScope(
      // 返回键先退 WebView 的历史（前端是单页应用，直接退出会丢掉当前页）
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final web = _web;
        if (web != null && await web.canGoBack()) {
          await web.goBack();
          return;
        }
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('ARTEX'),
        actions: [
          if (_progress > 0 && _progress < 100)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, value: _progress / 100),
                ),
              ),
            ),
          IconButton(
            tooltip: loc.artexBackendAddress,
            icon: const Icon(Icons.dns_outlined),
            onPressed: () => _menuAction('backend'),
          ),
          IconButton(
            tooltip: loc.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
          PopupMenuButton<String>(
            onSelected: (v) => unawaited(_menuAction(v)),
            itemBuilder: (_) => [
              if (!_embedded)
                PopupMenuItem(value: 'local', child: Text(loc.artexStartLocal)),
              PopupMenuItem(value: 'browser', child: Text(loc.artexOpenInBrowser)),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'native', child: Text(loc.artexNativePanel)),
              PopupMenuItem(value: 'stop', child: Text(loc.artexStopServer)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress > 0 && _progress < 100)
            LinearProgressIndicator(value: _progress / 100, minHeight: 2),
          if (!_backendUp || _embedded) _modeBanner(loc),
          Expanded(child: _content(loc)),
        ],
      ),
      floatingActionButton: _starting
          ? const FloatingActionButton(
              onPressed: null,
              child: SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : null,
      ),
    );
  }

  /// 顶部状态条：
  ///   * 内置服务端 → 绿色「独立运行」条（点一下看说明）；
  ///   * 外部后端不可达 → 红色提示 + 「本地启动」。
  Widget _modeBanner(AppLocalizations loc) {
    final theme = Theme.of(context);
    if (_embedded) {
      return Material(
        color: theme.colorScheme.primaryContainer,
        child: InkWell(
          onTap: _editBackend,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                Icon(Icons.offline_bolt_outlined,
                    size: 17, color: theme.colorScheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(loc.artexEmbeddedOn,
                      style: TextStyle(
                          fontSize: 12, color: theme.colorScheme.onPrimaryContainer)),
                ),
                Icon(Icons.chevron_right,
                    size: 16, color: theme.colorScheme.onPrimaryContainer),
              ],
            ),
          ),
        ),
      );
    }
    return Material(
      color: theme.colorScheme.errorContainer,
      child: InkWell(
        onTap: _startLocal,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loc.artexBackendOfflineHint,
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onErrorContainer),
                ),
              ),
              Text(loc.artexStartLocal,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onErrorContainer)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(AppLocalizations loc) {
    final web = _web;
    if (web != null) {
      return WebViewWidget(controller: web);
    }
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.open_in_browser, size: 38, color: theme.hintColor),
            const SizedBox(height: 12),
            Text(loc.artexWebViewDesktopHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openExternal(ArtexWebServer.instance.origin),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(loc.artexOpenInBrowser),
            ),
          ],
        ),
      ),
    );
  }
}
