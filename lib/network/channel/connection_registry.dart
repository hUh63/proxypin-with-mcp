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
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';

/// 一条客户端连接的快照（用于「连接」视图 / HTTP/2 连接树）。
class ConnectionEntry {
  final String id;
  final String clientAddress;
  final DateTime openedAt;

  bool isSsl;
  bool isHttp2;
  int? connectTimeMs; // 到服务端的 TCP 连接耗时（含 DNS）
  int? tlsTimeMs; // 到服务端的 TLS 握手耗时
  int requestCount = 0;
  DateTime lastActive;

  /// 最近经过本连接的请求（有界），UI 展开时按 streamId 呈现多路复用。
  final List<HttpRequest> recent = [];

  ConnectionEntry({required this.id, required this.clientAddress})
      : openedAt = DateTime.now(),
        isSsl = false,
        isHttp2 = false,
        lastActive = DateTime.now();
}

/// 活动连接登记表。
///
/// 客户端连接在 `Server.bind` 里被接受时登记，socket 结束时注销；每个请求经过
/// `ChannelDispatcher.prepareRequest` 时记一笔。纯内存、只读侧，不影响转发逻辑。
/// UI（连接视图）通过 [addListener] 订阅变化。
class ConnectionRegistry {
  static final ConnectionRegistry instance = ConnectionRegistry._();

  ConnectionRegistry._();

  static const int maxRecentPerConnection = 100;
  static const int maxConnections = 500;

  final Map<String, ConnectionEntry> _entries = <String, ConnectionEntry>{};
  final List<void Function()> _listeners = <void Function()>[];

  List<ConnectionEntry> get entries => _entries.values.toList(growable: false);

  int get count => _entries.length;

  void addListener(void Function() listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    if (_listeners.isEmpty) return;
    for (final listener in List<void Function()>.of(_listeners)) {
      try {
        listener();
      } catch (_) {
        // 单个订阅者异常不影响其它订阅者
      }
    }
  }

  void register(ChannelContext context) {
    final channel = context.clientChannel;
    if (channel == null) return;
    final id = channel.id;
    final entry = ConnectionEntry(id: id, clientAddress: _addressOf(context));
    try {
      entry.isSsl = channel.isSsl;
    } catch (_) {}
    _entries[id] = entry;
    if (_entries.length > maxConnections) {
      final oldest = _entries.keys.first;
      if (oldest != id) _entries.remove(oldest);
    }
    _notify();
  }

  void unregister(ChannelContext context) {
    final id = context.clientChannel?.id;
    if (id == null) return;
    if (_entries.remove(id) != null) _notify();
  }

  void noteRequest(ChannelContext context, HttpRequest request) {
    final id = context.clientChannel?.id;
    if (id == null) return;
    final entry = _entries[id];
    if (entry == null) return;
    entry.requestCount++;
    entry.lastActive = DateTime.now();
    if (request.protocolVersion == 'HTTP/2') entry.isHttp2 = true;
    if (entry.recent.length >= maxRecentPerConnection) entry.recent.removeAt(0);
    entry.recent.add(request);
    entry.connectTimeMs ??= request.connectTimeMs;
    entry.tlsTimeMs ??= request.tlsTimeMs;
    _notify();
  }

  void clear() {
    _entries.clear();
    _notify();
  }

  String _addressOf(ChannelContext context) {
    try {
      final addr = context.clientChannel?.remoteSocketAddress;
      if (addr != null) return '${addr.host}:${addr.port}';
    } catch (_) {}
    return '-';
  }
}
