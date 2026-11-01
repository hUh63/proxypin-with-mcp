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

// 网络诊断：Ping / DNS / 端口扫描 / HTTP 检测 / 局域网扫描。
//
// 五个 Tab 对应「工具箱 1.0」Net 模块的五件事。差别在于这里不跑 shell：
// Android 上根本没有 ping/nc 这些二进制，用 dart:io 做反而更稳、还能跨平台。
//
// 交互上的共识：
//   · 每个操作都能中途停止（扫描动辄几十秒，不能要求用户等）；
//   · 结果边跑边出，不等到最后一次性刷出来；
//   · 每个操作都记录耗时并支持复制整段报告。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/net_diagnostics.dart';

class NetToolsPage extends StatefulWidget {
  const NetToolsPage({super.key});

  @override
  State<NetToolsPage> createState() => _NetToolsPageState();
}

class _NetToolsPageState extends State<NetToolsPage> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 5, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.netTools),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: loc.netPing),
            Tab(text: loc.netDns),
            Tab(text: loc.netPortScan),
            Tab(text: loc.netHttp),
            Tab(text: loc.netLanScan),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _PingTab(),
          _DnsTab(),
          _PortScanTab(),
          _HttpTab(),
          _LanTab(),
        ],
      ),
    );
  }
}

/// 结果区的公共外壳：等宽滚动列表 + 右上角复制整段。
class _ResultPane extends StatelessWidget {
  final List<String> lines;
  final bool busy;
  final VoidCallback? onStop;

  const _ResultPane({required this.lines, this.busy = false, this.onStop});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final text = lines.join('\n');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(4),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      child: Column(children: [
        Row(children: [
          if (busy) const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          Text('${lines.length} ${loc.netLines}',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
          const Spacer(),
          if (busy && onStop != null)
            TextButton(
              onPressed: onStop,
              child: Text(loc.cancel, style: const TextStyle(fontSize: 12)),
            ),
          if (text.isNotEmpty)
            IconButton(
              tooltip: loc.copy,
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) FlutterToastr.show(loc.copied, context, duration: 1);
              },
            ),
        ]),
        const SizedBox(height: 4),
        Expanded(
          child: SingleChildScrollView(
            child: SelectableText(
              text.isEmpty ? '—' : text,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace', height: 1.35),
            ),
          ),
        ),
      ]),
    );
  }
}

// ---------------- Ping ----------------

class _PingTab extends StatefulWidget {
  const _PingTab();

  @override
  State<_PingTab> createState() => _PingTabState();
}

class _PingTabState extends State<_PingTab> {
  final _host = TextEditingController(text: 'www.baidu.com');
  final _port = TextEditingController(text: '443');
  final List<String> _lines = [];
  bool _busy = false;
  bool _cancel = false;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final loc = AppLocalizations.of(context)!;
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 443;
    if (host.isEmpty || _busy) return;
    _cancel = false;
    setState(() {
      _busy = true;
      _lines
        ..clear()
        ..add('${loc.netPingTo} $host:$port');
    });
    var ok = 0;
    var total = 0;
    await NetDiagnostics.pingSeries(host, port: port, count: 4, isCancelled: () => _cancel, onResult: (r) {
      total++;
      if (r.ok) ok++;
      if (!mounted) return;
      setState(() => _lines.add(r.ok
          ? '  ${r.ms} ms'
          : '  ${loc.netFail} · ${r.ms} ms · ${r.error ?? ''}'));
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lines.add(_cancel ? loc.netStopped : '${loc.netPingDone} $ok/$total');
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(children: [
        Row(children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _host,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: loc.netHost,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Port',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _busy ? null : _run,
            child: Text(loc.netStart),
          ),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: _ResultPane(
            lines: _lines,
            busy: _busy,
            onStop: _busy ? () => setState(() => _cancel = true) : null,
          ),
        ),
      ]),
    );
  }
}

// ---------------- DNS ----------------

class _DnsTab extends StatefulWidget {
  const _DnsTab();

  @override
  State<_DnsTab> createState() => _DnsTabState();
}

class _DnsTabState extends State<_DnsTab> {
  final _host = TextEditingController();
  final List<String> _lines = [];
  bool _busy = false;

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final loc = AppLocalizations.of(context)!;
    final host = _host.text.trim();
    if (host.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _lines.clear();
    });
    final r = await NetDiagnostics.dnsLookup(host);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lines.add('$host  (${r.ms} ms)');
      if (r.error != null) {
        _lines.add('  ${loc.netFail}: ${r.error}');
      } else if (r.addresses.isEmpty) {
        _lines.add('  ${loc.netNoResult}');
      } else {
        for (final a in r.addresses) {
          _lines.add('  $a');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _host,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: loc.netHost,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _busy ? null : _run, child: Text(loc.netQuery)),
        ]),
        const SizedBox(height: 8),
        Expanded(child: _ResultPane(lines: _lines, busy: _busy)),
      ]),
    );
  }
}

// ---------------- 端口扫描 ----------------

class _PortScanTab extends StatefulWidget {
  const _PortScanTab();

  @override
  State<_PortScanTab> createState() => _PortScanTabState();
}

class _PortScanTabState extends State<_PortScanTab> {
  final _host = TextEditingController(text: '127.0.0.1');
  final _start = TextEditingController(text: '1');
  final _end = TextEditingController(text: '1024');
  final List<String> _lines = [];
  bool _busy = false;
  bool _cancel = false;
  int _done = 0;
  int _total = 1;

  @override
  void dispose() {
    _host.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final loc = AppLocalizations.of(context)!;
    final host = _host.text.trim();
    var start = int.tryParse(_start.text.trim()) ?? 1;
    var end = int.tryParse(_end.text.trim()) ?? 1024;
    if (start < 1) start = 1;
    if (end > 65535) end = 65535;
    if (end < start) {
      final t = start;
      start = end;
      end = t;
    }
    if (host.isEmpty || _busy) return;
    _cancel = false;
    _done = 0;
    _total = end - start + 1;
    setState(() {
      _busy = true;
      _lines
        ..clear()
        ..add('$host  $start-$end');
    });
    await NetDiagnostics.scanPorts(
      host,
      start: start,
      end: end,
      isCancelled: () => _cancel,
      onResult: (r) {
        _done++;
        if (!mounted || !r.open) return;
        setState(() => _lines.add('  ${r.port}  open  ${r.ms} ms'));
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lines.add(_cancel
          ? '${loc.netStopped} $_done/$_total'
          : '${loc.netScanDone} $_done/$_total');
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(children: [
        Row(children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _host,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: loc.netHost,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _start,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'From',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _end,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'To',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          FilledButton(onPressed: _busy ? null : _run, child: Text(loc.netStart)),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: _ResultPane(
            lines: _lines,
            busy: _busy,
            onStop: _busy ? () => setState(() => _cancel = true) : null,
          ),
        ),
      ]),
    );
  }
}

// ---------------- HTTP 检测 ----------------

class _HttpTab extends StatefulWidget {
  const _HttpTab();

  @override
  State<_HttpTab> createState() => _HttpTabState();
}

class _HttpTabState extends State<_HttpTab> {
  final _url = TextEditingController(text: 'https://www.baidu.com');
  final List<String> _lines = [];
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final loc = AppLocalizations.of(context)!;
    final url = _url.text.trim();
    if (url.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _lines.clear();
    });
    final r = await NetDiagnostics.probeHttp(url);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.error != null) {
        _lines.add('${loc.netFail}: ${r.error}  (${r.ms} ms)');
        return;
      }
      _lines.add('HTTP ${r.status}  ·  ${r.ms} ms');
      r.headers.forEach((k, v) => _lines.add('  $k: $v'));
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _url,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'URL',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _busy ? null : _run, child: Text(loc.netCheck)),
        ]),
        const SizedBox(height: 8),
        Expanded(child: _ResultPane(lines: _lines, busy: _busy)),
      ]),
    );
  }
}

// ---------------- 局域网扫描 ----------------

class _LanTab extends StatefulWidget {
  const _LanTab();

  @override
  State<_LanTab> createState() => _LanTabState();
}

class _LanTabState extends State<_LanTab> {
  final _subnet = TextEditingController();
  final List<String> _lines = [];
  bool _busy = false;
  bool _cancel = false;

  @override
  void dispose() {
    _subnet.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    final subnet = await NetDiagnostics.localSubnet();
    if (!mounted) return;
    if (subnet == null) {
      final loc = AppLocalizations.of(context)!;
      FlutterToastr.show(loc.netNoSubnet, context, duration: 2);
      return;
    }
    setState(() => _subnet.text = subnet);
  }

  Future<void> _run() async {
    final loc = AppLocalizations.of(context)!;
    var subnet = _subnet.text.trim();
    // 允许用户直接粘 `192.168.1.5`：末尾那段数字当主机号去掉。
    if (subnet.split('.').length == 4) {
      subnet = subnet.split('.').sublist(0, 3).join('.');
    }
    if (subnet.split('.').length != 3 || _busy) return;
    _cancel = false;
    setState(() {
      _busy = true;
      _lines
        ..clear()
        ..add('$subnet.1 - $subnet.254');
    });
    await NetDiagnostics.sweepLan(
      subnet,
      isCancelled: () => _cancel,
      onFound: (h) {
        if (!mounted) return;
        setState(() => _lines.add('  ${h.ip}  ${h.openPorts.join(',')}  ${h.ms} ms'));
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lines.add(_cancel ? loc.netStopped : loc.netScanDone2('${_lines.length - 1}'));
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _subnet,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: loc.netSubnet,
                hintText: '192.168.1',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          OutlinedButton(onPressed: _detect, child: Text(loc.netDetect)),
          const SizedBox(width: 6),
          FilledButton(onPressed: _busy ? null : _run, child: Text(loc.netScan)),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: _ResultPane(
            lines: _lines,
            busy: _busy,
            onStop: _busy ? () => setState(() => _cancel = true) : null,
          ),
        ),
      ]),
    );
  }
}
