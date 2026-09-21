import 'dart:async';

import 'package:flutter/material.dart';
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
        _message = '没有拿到 root 权限：设备可能未 root，或你没有在授权框里点允许';
      }
    });
  }

  Future<void> _toggle(bool enable) async {
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
        _message = ok ? '已关闭，iptables 规则已清理' : '关闭时出错：规则可能仍在，建议重试或重启设备';
      });
      return;
    }

    // 与 VPN 抓包互斥：同时开启时两边会抢同一份流量
    if (Vpn.isVpnStarted) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '请先停止 VPN 抓包：两种抓包方式不能同时开启';
      });
      return;
    }

    final (ok, reason) = await RootProxy.start(widget.proxyServer.port);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _running = ok;
      if (!ok) {
        _message = reason.isEmpty ? '开启失败，请确认已授予 root 权限' : '开启失败：$reason';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).dividerColor;

    return Scaffold(
      appBar: AppBar(title: const Text('Root 模式抓包')),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(
              _running ? Icons.check_circle : Icons.pause_circle_outline,
              color: _running ? Colors.green : Colors.grey,
            ),
            title: Text(_running ? '重定向已生效' : '未生效'),
            subtitle: Text(
              '目标端口：${widget.proxyServer.port}　防护：异常退出后会在下次启动时自动清理规则',
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
            title: const Text('检测 root 权限'),
            subtitle: Text(
              _rootAvailable == null
                  ? '首次检测会弹出 su 授权框'
                  : (_rootAvailable! ? '已获得 root 权限' : '未获得 root 权限'),
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('说明', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '· 需要设备已 root 并授予 su 权限；\n'
              '· 原理是往 nat 表加一条只属于 ProxyPin 的链，把出站 TCP 连接转到代理端口，'
              '不做任何其它改动；\n'
              '· 只处理 IPv4，IPv6 流量保持直连；\n'
              '· 与 VPN 抓包互斥，开启前请先关掉 VPN；\n'
              '· 若手机出现「连着 WiFi 但上不了网」，先关掉这里；App 每次启动也会自动清理残留规则。',
              style: TextStyle(fontSize: 12, height: 1.6),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
