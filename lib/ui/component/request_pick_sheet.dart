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

// 「从抓包选择一条请求」——工具箱里那些需要 URL/body 的页面统一用它。
//
// 之前字节签名 / WAF 探测 / Fuzz 这些页面都让人自己手抄 URL、手抄 body：
// 手机上没有方便的复制路径，用户只能从抓包列表里一层层点开、长按复制、再切回来粘，
// 用起来就像个「AI 实验台」。这里给一个共用的选择器：最近 500 条（倒序），
// 带搜索，点一下就回填 URL + body。

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/mcp/mcp_bridge.dart';

class RequestPickSheet extends StatefulWidget {
  /// 展示条数上限（最近的在前）。
  final int limit;

  const RequestPickSheet({super.key, this.limit = 500, this.scroll});

  /// 弹出选择器；用户取消返回 null。
  static Future<HttpRequest?> show(BuildContext context, {int limit = 500}) {
    return showModalBottomSheet<HttpRequest>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.94,
        minChildSize: 0.35,
        builder: (ctx, controller) => RequestPickSheet(limit: limit, scroll: controller),
      ),
    );
  }

  final ScrollController? scroll;

  @override
  State<RequestPickSheet> createState() => _RequestPickSheetState();
}

class _RequestPickSheetState extends State<RequestPickSheet> {
  final TextEditingController _search = TextEditingController();
  late List<HttpRequest> _all = const <HttpRequest>[];

  @override
  void initState() {
    super.initState();
    // 新的在前：用户大多想用刚抓到的那条
    final src = McpBridge().source;
    // 只取尾部 limit 条再倒序：抓包上千条时不要整表复制两遍
    final tail = src.length > widget.limit ? src.sublist(src.length - widget.limit) : src;
    _all = tail.reversed.toList(growable: false);
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// `requestUrl` 是拼出来的，畸形 URI 会抛，列表不能因此整页崩。
  static String _urlOf(HttpRequest r) {
    try {
      return r.requestUrl;
    } catch (_) {
      return '${r.hostAndPort?.scheme ?? 'http'}://${r.hostAndPort?.host ?? '?'}${r.path}';
    }
  }

  List<HttpRequest> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all
        .where((r) =>
            _urlOf(r).toLowerCase().contains(q) ||
            r.methodLabel.toLowerCase().contains(q))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final list = _visible;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: loc.search,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              Text('${list.length} / ${_all.length}',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor)),
              const Spacer(),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _all.isEmpty ? '还没有抓到的请求 —— 先去抓包' : loc.search,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                    ),
                  ),
                )
              : ListView.separated(
                  controller: widget.scroll,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = list[i];
                    final method = r.methodLabel;
                    return ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(method,
                            style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary)),
                      ),
                      title: Text(_urlOf(r),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                      subtitle: (r.body?.isNotEmpty ?? false)
                          ? Text('body ${r.body!.length} B',
                              style: theme.textTheme.labelSmall)
                          : null,
                      onTap: () => Navigator.of(context).pop(r),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
