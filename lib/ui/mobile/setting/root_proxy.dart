import 'dart:async';

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/native/vpn.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/util/root_proxy.dart';
import 'package:proxypin/ui/component/widgets.dart';

/// Root 模式抓包设置页（上游 #839 Feature Request 2）。
///
/// 用 iptables 把系统出站流量重定向到本机代理，不开 VPN，
/// 用来抓那些「检测到 VPN / 系统代理就拒绝联网」的应用。
class RootProxySettingPage extends StatefulWidget {
  final ProxyServer proxyServer;

  const RootProxySettingPage({super.key, required this.proxyServer});

  @override
  State<RootProxySettingPage> createState() => _RootProxySettingPageState();
}

class _RootProxySettingPageState extends State<RootProxySettingPage> {
  bool _running = false;
  bool _busy = false;
  bool _checkingRoot = false;

  /// 探测结果：null=还没探测过，true/false=已 root / 不可用
  bool? _rootAvailable;
  String? _message;

  @override
  void initState() {
    super.initState();
    // 不用 await：首帧先把页面渲染出来，状态回来了再刷新
    unawaited(_loadState());
  }

  Future<void> _loadState() async {
    final running = await RootProxy.isRunning();
    if (!mounted) return;
    setState(() => _running = running);
  }

  /// 探测 root 权限。首次会弹出 su 授权框。
  Future<void> _checkRoot() async {
    final localizations = AppLocalizations.of(context)!;
    setState(() {
      _checkingRoot = true;
      _message = null;
    });
    final available = await RootProxy.isAvailable();
    if (!mounted) return;
    setState(() {
      _checkingRoot = false;
      _rootAvailable = available;
      if (!available) {
        _message = localizations.rootProxyNoAccess;
      }
    });
  }

  Future<void> _toggle(bool enable) async {
    final localizations = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _message = null;
    });

    if (!enable) {
      final ok = await RootProxy.stop();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _running = false;
        _message = ok ? localizations.rootProxyClosed : localizations.rootProxyStopError;
      });
      return;
    }

    // 抓包没跑就上重定向 = 把流量引到一个没人监听的端口，等于让设备断网
    if (!widget.proxyServer.isRunning) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = localizations.rootProxyNeedCapture;
      });
      return;
    }

    // 与 VPN 抓包互斥：同时开启时两边会抢同一份流量
    if (Vpn.isVpnStarted) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = localizations.rootProxyNeedStopVpn;
      });
      return;
    }

    final (ok, reason) = await RootProxy.start(widget.proxyServer.port);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _running = ok;
      if (!ok) {
        _message = reason.isEmpty ? localizations.rootProxyStartDenied : localizations.rootProxyStartFailed(reason);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).dividerColor;
    final localizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(localizations.prefRootMode)),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(
              _running ? Icons.check_circle : Icons.pause_circle_outline,
              color: _running ? Colors.green : Colors.grey,
            ),
            title: Text(_running ? localizations.rootProxyActive : localizations.rootProxyInactive),
            subtitle: Text(
              localizations.rootProxyTargetPort(widget.proxyServer.port),
              style: const TextStyle(fontSize: 12),
            ),
            trailing: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : SwitchWidget(
                    value: _running,
                    scale: 0.8,
                    onChanged: (value) {
                      // onChanged 非空，忙碌时自己挡掉
                      if (!_busy) unawaited(_toggle(value));
                    },
                  ),
          ),
          Divider(height: 0, thickness: 0.3, color: dividerColor),
          ListTile(
            leading: const Icon(Icons.security, color: Colors.deepOrange),
            title: Text(localizations.rootProxyCheckRoot),
            subtitle: Text(
              _rootAvailable == null
                  ? localizations.rootProxyFirstCheck
                  : (_rootAvailable! ? localizations.rootProxyGranted : localizations.rootProxyNotGranted),
              style: const TextStyle(fontSize: 12),
            ),
            trailing: _checkingRoot
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right, size: 20),
            onTap: _checkingRoot ? null : _checkRoot,
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(_message!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(localizations.rootProxyNotesTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              localizations.rootProxyNotesBody,
              style: const TextStyle(fontSize: 12, height: 1.6),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
