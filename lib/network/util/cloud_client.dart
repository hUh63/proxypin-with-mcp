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
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:proxypin/network/util/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 云端账号（登录后才有）。
class CloudAccount {
  final String username;
  final String displayName;
  final List<String> teams;

  const CloudAccount({required this.username, this.displayName = '', this.teams = const []});
}

/// 实时事件（服务端经 WebSocket 推来）。
///
/// 事件类型约定：
///  - `workspace.created` / `workspace.updated` / `workspace.deleted`：别人动了工作区
///  - `presence`：在线成员变化
///  - `error`：服务端反馈的问题
class CloudEvent {
  final String type;
  final Map<String, dynamic> data;
  final DateTime at;

  CloudEvent(this.type, this.data) : at = DateTime.now();

  String get id => '${data['id'] ?? ''}';
  String get by => '${data['by'] ?? ''}';

  @override
  String toString() => 'CloudEvent($type, by=$by, id=$id)';
}

/// 云同步客户端（账号 + 工作区 + 团队）。
///
/// 服务端由你自己部署（`docs/cloud_server_guide.md` 里有可直接运行的 Node 实现）。
/// 客户端只依赖一个很小的 REST + WebSocket 契约，不绑定任何特定托管商。
///
/// 请求**直连**服务端，不走本工具的代理端口。
class CloudClient {
  CloudClient._();

  static const String _kBaseUrl = 'cloudBaseUrl';
  static const String _kToken = 'cloudToken';
  static const String _kUsername = 'cloudUsername';
  static const String _kDisplayName = 'cloudDisplayName';

  // ---------- 配置 ----------

  static Future<String> baseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_kBaseUrl) ?? '').trim();
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, url.trim());
  }

  static Future<bool> get configured async => (await baseUrl()).isNotEmpty;

  // ---------- 账号 ----------

  static Future<String?> token() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_kToken);
    return (t == null || t.isEmpty) ? null : t;
  }

  static Future<CloudAccount?> account() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(_kUsername);
    if (username == null || username.isEmpty) {
      return null;
    }
    return CloudAccount(
      username: username,
      displayName: prefs.getString(_kDisplayName) ?? username,
    );
  }

  /// 注册。成功后直接写 token（服务端返回即视为已登录）。
  static Future<(bool, String)> register(String username, String password) async {
    final r = await _send('POST', '/auth/register', body: {'username': username, 'password': password});
    return _consumeAuth(r, username);
  }

  /// 登录。
  static Future<(bool, String)> login(String username, String password) async {
    final r = await _send('POST', '/auth/login', body: {'username': username, 'password': password});
    return _consumeAuth(r, username);
  }

  static Future<(bool, String)> _consumeAuth(Map<String, dynamic> r, String username) async {
    if (r['_error'] != null) {
      return (false, '${r['_error']}');
    }
    final token = '${r['token'] ?? ''}';
    if (token.isEmpty) {
      return (false, 'server did not return a token');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    await prefs.setString(_kUsername, '${r['username'] ?? username}');
    await prefs.setString(_kDisplayName, '${r['displayName'] ?? username}');
    logger.i('[Cloud] logged in as $username');
    return (true, '');
  }

  static Future<void> logout() async {
    await CloudRealtime.instance.disconnect();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUsername);
    await prefs.remove(_kDisplayName);
  }

  // ---------- 工作区 ----------

  static Future<List<Map<String, dynamic>>> listWorkspaces() async {
    final r = await _send('GET', '/workspaces', auth: true);
    if (r['_error'] != null) {
      throw HttpException('${r['_error']}');
    }
    final raw = r['workspaces'] ?? r['list'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  /// 推送工作区。[serverId] 为空则新建；[rev] 用于乐观并发控制。
  static Future<Map<String, dynamic>> pushWorkspace({
    required String name,
    required String description,
    required String harJson,
    String? serverId,
    int? rev,
  }) async {
    Object? har;
    if (harJson.trim().isNotEmpty) {
      try {
        har = json.decode(harJson);
      } catch (_) {
        har = harJson;
      }
    }
    final hasId = serverId != null && serverId.isNotEmpty;
    final r = await _send(
      hasId ? 'PUT' : 'POST',
      hasId ? '/workspaces/$serverId' : '/workspaces',
      auth: true,
      body: {
        'name': name,
        'description': description,
        'har': har,
        if (rev != null) 'rev': rev,
      },
    );
    return r;
  }

  /// 拉取工作区（返回 har 与 版本号）。
  static Future<(String har, int rev)> pullWorkspace(String serverId) async {
    final r = await _send('GET', '/workspaces/$serverId', auth: true);
    if (r['_error'] != null) {
      throw HttpException('${r['_error']}');
    }
    final har = r['har'];
    final rev = r['rev'] is int ? r['rev'] as int : 0;
    if (har == null) {
      return ('', rev);
    }
    return (har is String ? har : json.encode(har), rev);
  }

  static Future<void> deleteWorkspace(String serverId) async {
    await _send('DELETE', '/workspaces/$serverId', auth: true);
  }

  // ---------- 团队 ----------

  static Future<List<Map<String, dynamic>>> listMembers() async {
    final r = await _send('GET', '/members', auth: true);
    final raw = r['members'] ?? r['list'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  static Future<(bool, String)> invite(String username) async {
    final r = await _send('POST', '/members', auth: true, body: {'username': username});
    if (r['_error'] != null) {
      return (false, '${r['_error']}');
    }
    return (true, '${r['message'] ?? ''}');
  }

  // ---------- 底层 ----------

  /// 发一个请求。失败时返回 `{'_error': '...'}`，不抛异常（除了调用方自己判断的）。
  static Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    bool auth = false,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final base = await baseUrl();
    if (base.isEmpty) {
      return {'_error': 'cloud server is not configured'};
    }
    final String? token = auth ? await CloudClient.token() : null;
    if (auth && token == null) {
      return {'_error': 'not logged in'};
    }
    var root = base;
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    if (!root.startsWith('http://') && !root.startsWith('https://')) {
      root = 'http://$root';
    }
    final uri = Uri.parse('$root$path');

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        final payload = utf8.encode(json.encode(body));
        request.headers.contentType = ContentType.json;
        request.headers.contentLength = payload.length;
        request.add(payload);
      }
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join().timeout(timeout);
      Map<String, dynamic> parsed = {};
      if (text.trim().isNotEmpty) {
        try {
          final decoded = json.decode(text);
          if (decoded is Map) {
            parsed = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {
          parsed = {'_raw': text};
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final msg = parsed['error'] ?? parsed['message'] ?? 'HTTP ${response.statusCode}';
        return {'_error': '$msg', '_status': response.statusCode};
      }
      return parsed;
    } on SocketException catch (e) {
      return {'_error': 'cannot reach cloud server: ${e.message}'};
    } catch (e) {
      logger.w('[Cloud] $method $path failed: $e');
      return {'_error': '$e'};
    } finally {
      client.close(force: true);
    }
  }
}

/// 实时协同：一条到服务端的 WebSocket 长连接。
///
/// 断线按指数退避重连（1s → 2s → … → 60s 封顶），连上后 25s 发一次 ping 保活。
/// 服务端推来的每个事件都会转发到 [events]，UI 据此刷新别人的改动。
class CloudRealtime {
  CloudRealtime._();
  static final CloudRealtime instance = CloudRealtime._();

  final StreamController<CloudEvent> _events = StreamController<CloudEvent>.broadcast();
  final StreamController<bool> _status = StreamController<bool>.broadcast();

  WebSocket? _socket;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _manualClose = false;

  /// 实时事件流
  Stream<CloudEvent> get events => _events.stream;

  /// 连接状态流（true=已连接）
  Stream<bool> get status => _status.stream;

  bool get connected => _socket != null;

  /// 建立连接。已连上则直接返回。
  Future<void> connect() async {
    if (_socket != null || _manualClose) {
      return;
    }
    final base = await CloudClient.baseUrl();
    final token = await CloudClient.token();
    if (base.isEmpty || token == null) {
      return;
    }
    var root = base;
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    final wsRoot = root.startsWith('https://')
        ? root.replaceFirst('https://', 'wss://')
        : root.replaceFirst(RegExp(r'^http://'), 'ws://');
    final uri = Uri.parse('$wsRoot/ws?token=${Uri.encodeComponent(token)}');
    try {
      final socket = await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 15));
      _socket = socket;
      _attempt = 0;
      _status.add(true);
      logger.i('[Cloud] realtime connected');
      socket.listen(
        (dynamic data) => _handle('$data'),
        onDone: _onClosed,
        onError: (Object e) {
          logger.w('[Cloud] realtime error: $e');
          _onClosed();
        },
        cancelOnError: true,
      );
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          _socket?.add(json.encode({'type': 'ping'}));
        } catch (_) {
          // 连接已坏，交给 onDone/onError 处理
        }
      });
    } catch (e) {
      logger.w('[Cloud] realtime connect failed: $e');
      _status.add(false);
      _scheduleReconnect();
    }
  }

  /// 主动断开（用户关掉实时同步 / 登出）。
  Future<void> disconnect() async {
    _manualClose = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    final socket = _socket;
    _socket = null;
    _status.add(false);
    try {
      await socket?.close();
    } catch (_) {
      // 已经断了就算了
    }
  }

  /// 重新打开（用户开启实时同步）。
  Future<void> reconnect() async {
    _manualClose = false;
    if (_socket == null) {
      await connect();
    }
  }

  void _handle(String raw) {
    if (raw.isEmpty) {
      return;
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        return;
      }
      final type = '${decoded['type'] ?? ''}';
      if (type.isEmpty || type == 'pong') {
        return;
      }
      final data = decoded['data'];
      _events.add(CloudEvent(type, data is Map ? Map<String, dynamic>.from(data) : {}));
    } catch (e) {
      logger.w('[Cloud] bad realtime frame: $e');
    }
  }

  void _onClosed() {
    _socket = null;
    _pingTimer?.cancel();
    _status.add(false);
    if (!_manualClose) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    // 指数退避：1s, 2s, 4s ... 60s 封顶
    final seconds = (1 << _attempt).clamp(1, 60).toInt();
    if (_attempt < 10) {
      _attempt++;
    }
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (!_manualClose) {
        connect();
      }
    });
  }
}
