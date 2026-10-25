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

import 'dart:collection';

import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';

import 'flow_view.dart';
import 'history_provider.dart';

/// MCP 抓包数据索引。
///
/// 通过注册到 [ProxyServer.listeners] 以 [EventListener] 身份接收全部流量，
/// 维护 requestId -> [HttpRequest] 的有界缓存，平台无关、不依赖 UI 容器。
/// 仅保留最近 [maxEntries] 条，超出后丢弃最旧的，避免长时间运行导致内存膨胀。
///
/// @author wanghongen
class FlowStore extends EventListener {
  /// 默认保留最近的抓包条数
  static const int defaultMaxEntries = 1000;

  /// 单条流最多保留的 WebSocket/SSE 帧数，超出丢弃最旧的，防止长连接无限累积内存
  static const int defaultMaxFramesPerFlow = 5000;

  final int maxEntries;
  final int maxFramesPerFlow;

  /// 历史抓包数据源；为空时历史相关工具返回空 / 不可用
  final HistoryProvider? historyProvider;

  final LinkedHashMap<String, HttpRequest> _byId = LinkedHashMap();

  /// 每流的有界帧索引：不裁剪共享的 message.messages（App UI 也在用），
  /// 而是单独维护，避免影响界面展示。
  ///
  /// 用 LinkedHashMap 记访问顺序：既按「每流帧数」截断，也按「流数量」淘汰最久未活跃的流。
  /// 只按帧数限制是不够的——一条 WS 长连接的 request 被 1000 条新请求挤出 [_byId] 后，
  /// 后续帧仍会命中 putIfAbsent 重新建表，几十条被淘汰的流各自攒到 5000 帧就无界增长了。
  final LinkedHashMap<String, List<WebSocketFrame>> _wsFrames = LinkedHashMap();

  /// 帧索引最多保留的流数量（与抓包条数上限同量级，足够覆盖活跃长连接）
  static const int defaultMaxFrameFlows = 128;

  final int maxFrameFlows;

  /// 最多在内存中同时保留的历史会话数，超出淘汰最久未访问的，
  /// 与实时缓冲一样防止长时间运行 / 连续翻阅多个大会话导致内存膨胀。
  static const int defaultMaxHistorySessions = 3;

  /// 每个历史会话在缓存里保留的**尾部窗口**条数（最新这些条）。
  ///
  /// 早先缓存的是整份会话的请求列表：一个 10 万条的会话本身就是几百 MB，
  /// 再乘上 3 个 LRU 槽位，翻几个大会话就把内存吃光。现在只缓存最新的
  /// [historyWindowSize] 条——AI 常见的「看最近 N 条 / 翻前几页」都命中窗口，
  /// 大 offset 或 body 搜索这类确实需要全量的操作改为「读一次、不缓存」。
  static const int defaultHistoryWindowSize = 2000;

  /// history_id -> 尾部窗口（LinkedHashMap 记访问顺序，访问移末尾、从头部淘汰）
  final LinkedHashMap<int, _HistoryWindow> _historyCache = LinkedHashMap();

  final int maxHistorySessions;

  final int historyWindowSize;

  FlowStore(
      {this.maxEntries = defaultMaxEntries,
      this.maxFramesPerFlow = defaultMaxFramesPerFlow,
      this.maxFrameFlows = defaultMaxFrameFlows,
      this.historyProvider,
      this.maxHistorySessions = defaultMaxHistorySessions,
      this.historyWindowSize = defaultHistoryWindowSize});

  @override
  void onRequest(Channel channel, HttpRequest request) {
    _put(request);
  }

  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) {
    var request = response.request;
    if (request != null) {
      // 响应到达，回填同一请求对象（response 已挂载），保持其在缓存中的位置不变
      _byId[request.requestId] = request;
    }
  }

  @override
  void onMessage(Channel channel, HttpMessage message, WebSocketFrame frame) {
    var id = message.requestId;
    // remove + 重新插入 = 把该流标记为最近活跃（LinkedHashMap 的插入顺序即淘汰顺序）
    var list = _wsFrames.remove(id);
    list ??= <WebSocketFrame>[];
    list.add(frame);
    if (list.length > maxFramesPerFlow) {
      list.removeRange(0, list.length - maxFramesPerFlow);
    }
    _wsFrames[id] = list;
    while (_wsFrames.length > maxFrameFlows) {
      _wsFrames.remove(_wsFrames.keys.first);
    }
  }

  /// 某条流的帧（有界，不含被淘汰的最旧帧）
  List<WebSocketFrame> frames(String id) => _wsFrames[id] ?? const [];

  void _put(HttpRequest request) {
    // 已存在则先移除，保证刷新后位于最新位置
    _byId.remove(request.requestId);
    _byId[request.requestId] = request;
    _evictIfNeeded();
  }

  void _evictIfNeeded() {
    while (_byId.length > maxEntries) {
      var evicted = _byId.remove(_byId.keys.first);
      if (evicted != null) _wsFrames.remove(evicted.requestId);
    }
  }

  /// 启用时一次性回填已抓到的请求（来自现有 UI 容器）
  void backfill(Iterable<HttpRequest> requests) {
    for (var request in requests) {
      _byId[request.requestId] = request;
    }
    _evictIfNeeded();
  }

  void clear() {
    _byId.clear();
    _wsFrames.clear();
    _historyCache.clear();
  }

  int get count => _byId.length;

  HttpRequest? getById(String id) => _byId[id];

  // ------------------------------------------------------------- history

  /// 全部历史会话元数据；未配置历史数据源时返回空。
  Future<List<HistoryMeta>> listHistories() async => await historyProvider?.list() ?? const [];

  /// 读取整份历史会话（**不写缓存**）。
  ///
  /// 只给「大 offset 分页 / body 搜索 / 按 id 精确找」这类确实需要全量的操作用，
  /// 用完即可被 GC 回收——绝不能塞进 [_historyCache]，否则又回到整份驻留内存。
  Future<List<HttpRequest>> _historyAll(int historyId) async {
    var provider = historyProvider;
    if (provider == null) throw ArgumentError('history not found: $historyId');
    var metas = await provider.list();
    if (!metas.any((m) => m.id == historyId)) {
      throw ArgumentError('history not found: $historyId');
    }
    return await provider.requests(historyId);
  }

  /// 取该会话的尾部窗口（最新 [historyWindowSize] 条），命中缓存则标记最近使用。
  Future<_HistoryWindow> _historyWindow(int historyId) async {
    var cached = _historyCache.remove(historyId);
    if (cached != null) {
      // 命中则标记为最近使用（移到末尾）
      _historyCache[historyId] = cached;
      return cached;
    }
    var all = await _historyAll(historyId);
    var start = all.length > historyWindowSize ? all.length - historyWindowSize : 0;
    var window = _HistoryWindow(
      start > 0 ? all.sublist(start) : List<HttpRequest>.of(all),
      all.length,
    );
    // 会话很大时 all 不再被引用，可立即回收
    _historyCache[historyId] = window;
    _evictHistoryIfNeeded();
    return window;
  }

  /// 历史会话缓存超限时淘汰最久未访问的（LinkedHashMap 头部）。
  void _evictHistoryIfNeeded() {
    while (_historyCache.length > maxHistorySessions) {
      _historyCache.remove(_historyCache.keys.first);
    }
  }

  Future<HttpRequest?> historyGetById(int historyId, String id) async {
    // 先查尾部窗口（AI 通常看最近的请求），未命中再读全量
    var window = await _historyWindow(historyId);
    for (var request in window.items) {
      if (request.requestId == id) return request;
    }
    if (window.total <= window.items.length) return null;
    var all = await _historyAll(historyId);
    for (var request in all) {
      if (request.requestId == id) return request;
    }
    return null;
  }

  Future<List<HttpRequest>> historyQuery(
    int historyId, {
    int limit = 20,
    int offset = 0,
    String? host,
    String? method,
    int? statusFrom,
    int? statusTo,
    String? keyword,
    int? sinceMs,
  }) async {
    // 倒序遍历 = 从最新往前，所以「前 N 条」正好在尾部窗口里；
    // 只有 offset+limit 越过窗口才需要读全量（且不缓存）。
    var window = await _historyWindow(historyId);
    var need = (offset < 0 ? 0 : offset) + limit;
    if (need <= window.items.length) {
      final page = _filter(window.items,
          limit: limit,
          offset: offset,
          host: host,
          method: method,
          statusFrom: statusFrom,
          statusTo: statusTo,
          keyword: keyword,
          sinceMs: sinceMs);
      // 窗口只覆盖最新的若干条：若条件把窗口内的条目滤掉，页可能不满，
      // 而更早的请求里还有匹配项——这时必须回退全量，否则表现为「翻到某页就空了」。
      if (page.length >= limit || window.total <= window.items.length) {
        return page;
      }
    }
    var all = await _historyAll(historyId);
    return _filter(all,
        limit: limit,
        offset: offset,
        host: host,
        method: method,
        statusFrom: statusFrom,
        statusTo: statusTo,
        keyword: keyword,
        sinceMs: sinceMs);
  }

  Future<List<HttpRequest>> historySearch(int historyId, String keyword,
      {String side = 'both', int limit = 20, int offset = 0, int maxSearchBytes = 2 * 1024 * 1024}) async {
    // body 搜索必须扫全量（需要逐条解码），这里读一次不缓存
    var requests = await _historyAll(historyId);
    return await _searchIn(requests, keyword,
        side: side, limit: limit, offset: offset, maxSearchBytes: maxSearchBytes);
  }

  /// 按条件查询抓包，按时间倒序（最新在前）返回，应用 limit/offset。
  List<HttpRequest> query({
    int limit = 20,
    int offset = 0,
    String? host,
    String? method,
    int? statusFrom,
    int? statusTo,
    String? keyword,
    int? sinceMs,
  }) {
    return _filter(_byId.values.toList(growable: false),
        limit: limit,
        offset: offset,
        host: host,
        method: method,
        statusFrom: statusFrom,
        statusTo: statusTo,
        keyword: keyword,
        sinceMs: sinceMs);
  }

  /// 在给定请求集合上按条件过滤，按时间倒序（最新在前）返回，应用 limit/offset。
  /// 实时缓冲与历史会话共用，保证两处过滤口径一致。
  List<HttpRequest> _filter(
    List<HttpRequest> source, {
    required int limit,
    required int offset,
    String? host,
    String? method,
    int? statusFrom,
    int? statusTo,
    String? keyword,
    int? sinceMs,
  }) {
    limit = limit.clamp(1, 100);
    offset = offset < 0 ? 0 : offset;

    var hostLower = host?.toLowerCase();
    var methodUpper = method?.toUpperCase();
    var keywordLower = keyword?.toLowerCase();
    var matched = <HttpRequest>[];

    // 倒序遍历
    for (var i = source.length - 1; i >= 0; i--) {
      var request = source[i];
      if (!_matches(request, hostLower, methodUpper, statusFrom, statusTo, keywordLower, sinceMs)) {
        continue;
      }
      matched.add(request);
    }

    if (offset >= matched.length) {
      return const [];
    }
    var end = (offset + limit).clamp(0, matched.length);
    return matched.sublist(offset, end);
  }

  /// 在请求/响应 body 中做子串搜索（大小写不敏感）。
  ///
  /// 仅搜索文本报文：二进制（图片/音视频/压缩/加密等）与超过 [maxSearchBytes] 的大 body
  /// 会跳过，避免解码与扫描大对象拖慢搜索。返回最新在前的匹配，最多 [limit] 条。
  Future<List<HttpRequest>> search(String keyword,
      {String side = 'both', int limit = 20, int maxSearchBytes = 2 * 1024 * 1024}) async {
    return await _searchIn(_byId.values.toList(growable: false), keyword,
        side: side, limit: limit, maxSearchBytes: maxSearchBytes);
  }

  /// 在给定请求集合上做 body 子串搜索，实时缓冲与历史会话共用同一口径。
  Future<List<HttpRequest>> _searchIn(List<HttpRequest> source, String keyword,
      {required String side, required int limit, int offset = 0, required int maxSearchBytes}) async {
    keyword = keyword.toLowerCase();
    if (keyword.isEmpty) return const [];
    limit = limit.clamp(1, 100);
    offset = offset < 0 ? 0 : offset;
    var matched = <HttpRequest>[];
    var skipped = 0;

    for (var i = source.length - 1; i >= 0; i--) {
      if (matched.length >= limit) break;
      var request = source[i];
      var hit = false;
      if (side != 'response' && await _bodyContains(request, keyword, maxSearchBytes, requestSide: true)) {
        hit = true;
      }
      if (!hit && side != 'request' && await _bodyContains(request, keyword, maxSearchBytes, requestSide: false)) {
        hit = true;
      }
      if (!hit) continue;
      // offset 在「命中集」上生效：搜索也支持翻页，否则模型每次拿到同一批结果
      if (skipped < offset) {
        skipped++;
        continue;
      }
      matched.add(request);
    }
    return matched;
  }

  Future<bool> _bodyContains(HttpRequest request, String keyword, int maxSearchBytes,
      {required bool requestSide}) async {
    var message = requestSide ? request : request.response;
    if (message == null || FlowView.isBinary(message)) return false;
    var body = message.body;
    if (body == null || body.isEmpty || body.length > maxSearchBytes) return false;
    try {
      return (await message.decodeBodyString()).toLowerCase().contains(keyword);
    } catch (_) {
      return false;
    }
  }

  bool _matches(HttpRequest request, String? host, String? method, int? statusFrom, int? statusTo,
      String? keyword, int? sinceMs) {
    if (method != null && method.isNotEmpty && request.methodLabel.toUpperCase() != method) {
      return false;
    }

    if (host != null && host.isNotEmpty) {
      var reqHost = request.requestUri?.host.toLowerCase() ?? request.remoteDomain()?.toLowerCase() ?? '';
      if (!reqHost.contains(host)) {
        return false;
      }
    }

    var status = request.response?.status.code ?? 0;
    if (statusFrom != null && status < statusFrom) {
      return false;
    }
    if (statusTo != null && status > statusTo) {
      return false;
    }

    if (sinceMs != null && request.requestTime.millisecondsSinceEpoch < sinceMs) {
      return false;
    }

    if (keyword != null && keyword.isNotEmpty) {
      var haystack = request.requestUrl.toLowerCase();
      if (!haystack.contains(keyword)) {
        return false;
      }
    }
    return true;
  }
}

/// 历史会话的尾部窗口：最新 [items] 条 + 会话总条数。
class _HistoryWindow {
  /// 正序尾部窗口（items[0] 之后还有 total - items.length 条更早的请求）
  final List<HttpRequest> items;
  final int total;

  const _HistoryWindow(this.items, this.total);
}
