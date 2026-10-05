/*
 * Copyright 2023 Hongen Wang
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
import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/channel/connection_registry.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/utils/request_timing.dart';

/// 打开「连接」视图：列出当前活动连接，展开可看每个连接上的请求
/// （HTTP/2 下按 streamId 呈现多路复用），以及到服务端的连接 / TLS 耗时。
void showConnectionTree(BuildContext context) {
  showDialog(context: context, builder: (_) => const _ConnectionTreeDialog());
}

class _ConnectionTreeDialog extends StatefulWidget {
  const _ConnectionTreeDialog();

  @override
  State<_ConnectionTreeDialog> createState() => _ConnectionTreeDialogState();
}

class _ConnectionTreeDialogState extends State<_ConnectionTreeDialog> {
  final ConnectionRegistry _registry = ConnectionRegistry.instance;

  @override
  void initState() {
    super.initState();
    _registry.addListener(_onChange);
  }

  @override
  void dispose() {
    _registry.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final entries = _registry.entries;

    return AlertDialog(
      title: Text(l.connectionTreeTitle),
      contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      content: SizedBox(
        width: 660,
        height: 520,
        child: entries.isEmpty
            ? Center(child: Text(l.connEmpty, style: TextStyle(color: Colors.grey[600])))
            : ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.4),
                itemBuilder: (_, i) => _buildConnection(context, l, entries[i]),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.close)),
      ],
    );
  }

  Widget _buildConnection(BuildContext context, AppLocalizations l, ConnectionEntry e) {
    final protocol = e.isHttp2 ? 'HTTP/2' : 'HTTP/1.1';
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.only(left: 20, bottom: 8),
      title: Row(
        children: [
          _chip(protocol, e.isHttp2 ? Colors.deepPurple : Colors.blueGrey),
          const SizedBox(width: 6),
          if (e.isSsl) _chip('TLS', Colors.green),
          const SizedBox(width: 6),
          Expanded(
            child: Text(e.clientAddress,
                style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      subtitle: Text(
        '${l.connOpened}: ${_hhmmss(e.openedAt)}   ·   ${l.connRequests(e.requestCount)}',
        style: const TextStyle(fontSize: 11.5, color: Colors.grey),
      ),
      children: [
        _kv(l.timingConnect, _ms(e.connectTimeMs)),
        _kv(l.timingTls, _ms(e.tlsTimeMs)),
        const Padding(padding: EdgeInsets.only(top: 6, bottom: 2), child: Divider(height: 1, thickness: 0.3)),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(l.connRecent, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        if (e.recent.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(l.connNoRecent, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          )
        else
          ...e.recent.reversed.take(32).map((r) => _buildRequest(l, r)),
      ],
    );
  }

  Widget _buildRequest(AppLocalizations l, HttpRequest r) {
    final timing = RequestTiming.of(r);
    final status = r.response?.status.code;
    final stream = r.streamId != null && r.protocolVersion == 'HTTP/2' ? ' #${r.streamId}' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text('${r.method.name}$stream',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 40,
            child: Text(status?.toString() ?? '…',
                style: TextStyle(
                    fontSize: 11.5,
                    color: status == null
                        ? Colors.grey
                        : (status >= 400 ? Colors.red : Colors.green))),
          ),
          Expanded(
            child: Text(
              '${l.timingWait} ${_ms(timing.waitMs)} / ${l.timingReceive} ${_ms(timing.receiveMs)}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(r.domainPath,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
      );

  Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: Colors.grey[700]))),
            Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
          ],
        ),
      );

  String _ms(int? v) => v == null ? '—' : '$v ms';

  String _hhmmss(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
