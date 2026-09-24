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
import 'dart:convert';
import 'dart:io';

import 'package:proxypin/network/util/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 自定义工作区服务端的连接配置。
class WorkspaceServerConfig {
  final String baseUrl;
  final String token;

  const WorkspaceServerConfig({required this.baseUrl, this.token = ''});

  bool get isValid => baseUrl.trim().isNotEmpty;

  @override
  String toString() => 'WorkspaceServerConfig($baseUrl, token=${token.isEmpty ? '-' : '***'})';
}

/// 自定义工作区服务端客户端。
///
/// 只约定一个很小的 REST 契约，服务端可以是你自己写的任何东西
/// （见 `docs/workspace_guide.md`，里面附了 Node.js 参考实现）：
///
/// ```
/// GET    {base}/workspaces            -> {"workspaces":[{id,name,description,updatedAt,requestCount}]}
/// POST   {base}/workspaces            <- {name,description,har}  -> {"id":"..."}
/// PUT    {base}/workspaces/{id}       <- {name,description,har}  -> {"id":"..."}
/// GET    {base}/workspaces/{id}       -> {"har":{...}}
/// DELETE {base}/workspaces/{id}
/// ```
///
/// 认证走 `Authorization: Bearer <token>`（token 可留空）。
/// 请求**直连**，不经过本工具的代理端口，避免自己抓自己。
class WorkspaceServer {
  WorkspaceServer._();

  static const String _kBaseUrl = 'workspaceServerBaseUrl';
  static const String _kToken = 'workspaceServerToken';

  static Future<WorkspaceServerConfig> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return WorkspaceServerConfig(
        baseUrl: prefs.getString(_kBaseUrl) ?? '',
        token: prefs.getString(_kToken) ?? '',
      );
    } catch (e) {
      logger.e('[WorkspaceServer] load config failed: $e');
      return const WorkspaceServerConfig(baseUrl: '');
    }
  }

  static Future<void> saveConfig(WorkspaceServerConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, config.baseUrl.trim());
    await prefs.setString(_kToken, config.token.trim());
  }

  /// 列出服务端已有的工作区。
  static Future<List<Map<String, dynamic>>> list(WorkspaceServerConfig config) async {
    final r = await _send('GET', _endpoint(config, '/workspaces'), config.token);
    final raw = r['workspaces'] ?? r['list'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  /// 把工作区推给服务端（[serverId] 为空则新建，否则更新）。返回服务端 id。
  static Future<String> push(
    WorkspaceServerConfig config, {
    required String name,
    required String description,
    required String harJson,
    String? serverId,
  }) async {
    Object? har;
    if (harJson.trim().isNotEmpty) {
      try {
        har = json.decode(harJson);
      } catch (_) {
        har = harJson;
      }
    }
    final body = {'name': name, 'description': description, 'har': har};
    final hasId = serverId != null && serverId.isNotEmpty;
    final r = await _send(
      hasId ? 'PUT' : 'POST',
      _endpoint(config, hasId ? '/workspaces/$serverId' : '/workspaces'),
      config.token,
      body: body,
    );
    final id = r['id'] ?? r['_id'] ?? serverId;
    return id == null ? '' : '$id';
  }

  /// 从服务端取回工作区的 HAR JSON。
  static Future<String> pull(WorkspaceServerConfig config, String serverId) async {
    final r = await _send('GET', _endpoint(config, '/workspaces/$serverId'), config.token);
    final har = r['har'];
    if (har == null) {
      return r['raw'] == null ? '' : json.encode(r['raw']);
    }
    return har is String ? har : json.encode(har);
  }

  /// 删除服务端的工作区。
  static Future<void> deleteRemote(WorkspaceServerConfig config, String serverId) async {
    await _send('DELETE', _endpoint(config, '/workspaces/$serverId'), config.token);
  }

  // ---------- 内部 ----------

  static Uri _endpoint(WorkspaceServerConfig config, String path) {
    var base = config.baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'http://$base';
    }
    return Uri.parse('$base$path');
  }

  static Future<Map<String, dynamic>> _send(
    String method,
    Uri uri,
    String token, {
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token.trim().isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${token.trim()}');
      }
      if (body != null) {
        final payload = utf8.encode(json.encode(body));
        request.headers.contentType = ContentType.json;
        request.headers.contentLength = payload.length;
        request.add(payload);
      }
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final brief = text.length > 200 ? text.substring(0, 200) : text;
        throw HttpException('HTTP ${response.statusCode} $brief', uri: uri);
      }
      if (text.trim().isEmpty) {
        return {};
      }
      final decoded = json.decode(text);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      if (decoded is List) {
        return {'list': decoded};
      }
      return {'raw': decoded};
    } finally {
      client.close(force: true);
    }
  }
}
