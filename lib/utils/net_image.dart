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

// 网络图片加载器。
//
// 为什么不用 `Image.network`：它内部走 dart:io 的 HttpClient，而 **HttpClient 默认
// 会读系统代理设置**。这个 App 本身是个抓包代理——开着 VPN/系统代理时，图片请求会
// 被送进自己的代理链，轻则绕一圈，重则直接失败（表现就是文档里的图全变成链接文字）。
//
// 所以这里显式 `findProxy = DIRECT`：图片直连，不经过本机代理。附带做了内存缓存和
// 大小上限，避免长文档反复拉同一张图。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 图片字节缓存（LRU，最多 [maxEntries] 张 / [maxTotalBytes] 字节）。
class NetImageLoader {
  NetImageLoader._();

  static const int maxEntries = 24;
  static const int maxTotalBytes = 32 * 1024 * 1024;

  /// 单张图上限：超过就当作「加载失败」，不让一张巨图吃掉内存。
  static const int maxBytes = 20 * 1024 * 1024;

  static const Duration timeout = Duration(seconds: 20);

  static final Map<String, Uint8List> _cache = <String, Uint8List>{};
  static final List<String> _order = <String>[];
  static int _bytes = 0;

  /// 正在下载的请求（同一张图并发请求时只发一次）。
  static final Map<String, Future<Uint8List?>> _inflight = <String, Future<Uint8List?>>{};

  /// 取图片字节（带缓存）。失败返回 null。
  static Future<Uint8List?> load(String url) {
    final cached = _cache[url];
    if (cached != null) {
      // 命中就提到队尾（最近使用）
      _order.remove(url);
      _order.add(url);
      return Future.value(cached);
    }
    final pending = _inflight[url];
    if (pending != null) return pending;
    late final Future<Uint8List?> future;
    future = _fetch(url).whenComplete(() {
      // 只删自己：同一个 URL 可能在这次完成前又被发起过一次，
      // 无脑 remove 会把新登记的请求从表里抹掉，后面的调用就会重复下载。
      if (identical(_inflight[url], future)) _inflight.remove(url);
    });
    _inflight[url] = future;
    return future;
  }

  /// 已经缓存过（同步取，供 build 阶段先渲染，避免闪一下转圈）。
  static Uint8List? peek(String url) => _cache[url];

  static void clear() {
    _cache.clear();
    _order.clear();
    _bytes = 0;
  }

  /// 先直连；直连拿不到时再用系统代理试一次。
  ///
  /// 直连是为了避开「App 自己的代理链」（否则开 VPN 时图片必挂），但有些网络
  /// 环境本来就只能经代理出网（公司网 / 需要代理的国际站点），这时直连必失败。
  /// 两种环境都得能用，所以在失败后再给一次带系统代理的机会。
  static Future<Uint8List?> _fetch(String url) async {
    final direct = await _download(url, direct: true);
    if (direct != null) return direct;
    return _download(url, direct: false);
  }

  static Future<Uint8List?> _download(String url, {required bool direct}) async {
    // 文档里的 HTML 写法会把 & 写成 &amp;，直接用会让整条 query 变样（403 / 404）。
    final uri = Uri.tryParse(url.replaceAll('&amp;', '&').trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) return null;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 10);
    // 关键：正常路径直连，不走系统代理（否则抓包 App 会把自己的图片请求也抓走）
    if (direct) client.findProxy = ((_) => 'DIRECT');
    client.userAgent = 'Mozilla/5.0 (compatible; ProxyPin)';
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // 有些图床靠重定向，HttpClient 默认会跟；到这里说明确实拿不到
        await response.drain<void>();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response.timeout(timeout)) {
        total += chunk.length;
        if (total > maxBytes) return null;
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (bytes.isEmpty) return null;
      _put(url, bytes);
      return bytes;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static void _put(String url, Uint8List bytes) {
    if (_cache.containsKey(url)) return;
    _cache[url] = bytes;
    _order.add(url);
    _bytes += bytes.length;
    while (_order.length > maxEntries || _bytes > maxTotalBytes) {
      if (_order.isEmpty) break;
      final first = _order.removeAt(0);
      final removed = _cache.remove(first);
      if (removed != null) _bytes -= removed.length;
    }
  }
}

/// 网络图片：直连加载 + 转圈占位 + 失败降级。
///
/// [errorBuilder] 不给时显示一个带链接的占位块（文档里的图挂了也能知道是哪个地址）。
class NetImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final double? height;
  final double? width;
  final BorderRadius? borderRadius;

  /// 失败时的自定义占位（默认显示链接）。
  final Widget Function(BuildContext context, String url)? errorBuilder;

  const NetImage(
    this.url, {
    super.key,
    this.fit = BoxFit.contain,
    this.height,
    this.width,
    this.borderRadius,
    this.errorBuilder,
  });

  @override
  State<NetImage> createState() => _NetImageState();
}

class _NetImageState extends State<NetImage> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bytes = NetImageLoader.peek(widget.url);
    if (_bytes != null) {
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant NetImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = NetImageLoader.peek(widget.url);
      _loading = _bytes == null;
      if (_bytes == null) _load();
    }
  }

  Future<void> _load() async {
    // 记住发起时的地址：await 期间 widget.url 可能已经换掉（列表回收复用），
    // 那时把旧图的字节写进去会显示成错图。
    final url = widget.url;
    final bytes = await NetImageLoader.load(url);
    if (!mounted || widget.url != url) return;
    setState(() {
      _bytes = bytes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_bytes != null) {
      child = Image.memory(_bytes!, fit: widget.fit, height: widget.height, width: widget.width);
    } else if (_loading) {
      child = SizedBox(
        height: widget.height ?? 90,
        child: const Center(
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    } else {
      final builder = widget.errorBuilder;
      child = builder != null ? builder(context, widget.url) : _linkPlaceholder(context);
    }
    if (widget.borderRadius == null) return child;
    return ClipRRect(borderRadius: widget.borderRadius!, child: child);
  }

  Widget _linkPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(children: [
        Icon(Icons.broken_image_outlined, size: 16, color: theme.colorScheme.outline),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            widget.url,
            maxLines: 2,
            style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
          ),
        ),
      ]),
    );
  }
}
