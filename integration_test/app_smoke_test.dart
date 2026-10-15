/*
 * 桌面端「真实 App 冒烟」集成测试。
 *
 * 与 test/ 下的单元测试不同，这里跑的是**真实的 Linux 桌面 App**：
 *   `flutter test integration_test -d linux`（CI 里由 xvfb 提供虚拟显示）
 * 因此它会真实走一遍：
 *   - 桌面插件注册（window_manager / dynamic_color / tray_manager / path_provider …）
 *   - code_forge 的 Rust FFI 初始化（RustLib.init）
 *   - SharedPreferences、Assets、l10n 加载
 *   - 桌面版主界面（DesktopHomePage）渲染
 * 这些是 build-desktop.yml（只 build 不 run）完全覆盖不到的部分。
 *
 * 第二个用例进一步验证「真实桌面运行时里的抓包核心」：
 *   真正启动 ProxyServer → 真实客户端经代理 → 真实源站 → 断言明文转发成功。
 *
 * 注意：本文件属于 integration_test（由 desktop-smoke.yml 单独驱动），
 * 不参与 quality.yml 的 `flutter test --exclude-tags integration`。
 */
import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:proxypin/main.dart' as app;
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '桌面端冷启动冒烟：App 能启动并渲染主界面',
    (tester) async {
      // 让真实异步初始化（Rust FFI / 插件 / 偏好）有机会推进。
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 3)),
      );

      // 冷启动是异步的：循环 pump 直到 MaterialApp 出现（最多 ~30s）。
      var appeared = false;
      for (var i = 0; i < 300; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(MaterialApp).evaluate().isNotEmpty) {
          appeared = true;
          break;
        }
      }

      expect(
        appeared,
        isTrue,
        reason: '桌面端主界面（MaterialApp）应当被渲染出来',
      );
      // 启动过程不应有未捕获异常（插件缺失 / 初始化崩溃会在这里暴露）。
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    '桌面端真实网络栈：代理服务监听并转发一次 loopback 请求',
    (tester) async {
      await tester.runAsync(() async {
        // 1) 本地源站
        final origin = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
        final originSub = origin.listen((req) {
          req.response.statusCode = 200;
          req.response.headers.contentType = io.ContentType.text;
          req.response.write('origin-ok:${req.uri.path}');
          req.response.close();
        });

        final config = await Configuration.instance;
        // CI 无桌面会话，不要真的去改系统代理（那是全局副作用）。
        config.enableSystemProxy = false;

        final proxy = ProxyServer(config);
        await proxy.start();

        try {
          // 2) 真实客户端经代理访问源站
          final client = io.HttpClient();
          client.findProxy = (_) => 'PROXY 127.0.0.1:${config.port}';
          try {
            final req = await client.getUrl(
              Uri.parse('http://127.0.0.1:${origin.port}/ping'),
            );
            final resp = await req.close();
            final body = await resp.transform(io.utf8.decoder).join();

            expect(resp.statusCode, 200, reason: '经代理转发应拿到源站状态码');
            expect(body, 'origin-ok:/ping', reason: '经代理转发应拿到源站明文响应体');
          } finally {
            client.close(force: true);
          }
        } finally {
          // 3) 无论断言是否失败都要清理，避免端口/监听泄漏影响后续用例
          await proxy.stop();
          await originSub.cancel();
          await origin.close(force: true);
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
