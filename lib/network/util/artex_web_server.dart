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

// ARTEX 官方前端（assets/artex_web）的本地托管服务。
//
// ARTEX 2.2.7 的安卓端就是这个结构：把 Next.js 静态导出的整站放进 assets，起一个
// 本地 HTTP 服务（原来的 `com.artex.app.LocalServer`），WebView 打开
// `http://127.0.0.1:<port>/`。前端所有请求都是**同源相对路径**（`/api/health`、
// `/api/logs/stream`…），token 存在 localStorage 的 `artex_token` 里，SSE 走
// `?token=`。
//
// 所以这里照抄：
//   1. 静态：`/` → index.html，`/dashboard` → dashboard/index.html（Next 的
//      trailingSlash 导出形态），找不到再退 `<path>.html`，最后 404 页面。
//   2. 反代：`/api/**` 原样转发到后端（默认 127.0.0.1:8787），响应流式回吐 ——
//      SSE（日志/活动流）必须边收边 flush，否则界面一直转圈。
//
// 好处：前端不需要任何改动（没有 CORS、没有 baseUrl 注入），后端地址换了只要改
// 这里的 proxyBase，UI 立刻跟着走。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:proxypin/network/util/artex_local_backend.dart';
import 'package:proxypin/network/util/logger.dart';

class ArtexWebServer {
  static final ArtexWebServer instance = ArtexWebServer._();

  ArtexWebServer._();

  static const String _assetRoot = 'assets/artex_web';

  /// 单文件缓存上限（9.5MB 整站，缓存常用 chunk 就够，别整站常驻）。
  static const int _cacheLimit = 24 * 1024 * 1024;

  final Map<String, Uint8List> _cache = <String, Uint8List>{};
  int _cacheBytes = 0;

  HttpServer? _server;
  int _port = 0;

  /// 后端地址（`/api/**` 转发目标）。空串 = 不转发，前端走内置离线演示数据。
  String proxyBase = 'http://127.0.0.1:8787';

  /// 最近一次错误（给界面显示）。
  String? lastError;

  bool get running => _server != null;

  int get port => _port;

  String get origin => 'http://127.0.0.1:$_port';

  /// 起服务。已起则直接返回端口（换后端地址不需要重启）。
  Future<int> start({String? base, int preferredPort = 0}) async {
    if (base != null) proxyBase = base.trim();
    final server = _server;
    if (server != null) return _port;
    try {
      final bound = await HttpServer.bind(InternetAddress.loopbackIPv4, preferredPort);
      bound.autoCompress = false; // 前端 chunk 已经压缩过，二次压缩只会白耗 CPU
      _server = bound;
      _port = bound.port;
      lastError = null;
      bound.listen(_handle, onError: (Object e) {
        logger.w('[ArtexWeb] accept error: $e');
      });
      logger.i('[ArtexWeb] serving $_assetRoot on $origin -> ${proxyBase.isEmpty ? "demo" : proxyBase}');
      return _port;
    } catch (e) {
      lastError = '$e';
      logger.e('[ArtexWeb] bind failed: $e');
      rethrow;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _port = 0;
    try {
      await server?.close(force: true);
    } catch (_) {
      // 关不掉就算了，进程退出也会释放
    }
  }

  // ---------------------------------------------------------------- 路由

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == '/api' || path.startsWith('/api/')) {
        await _proxy(request);
        return;
      }
      await _serveStatic(request);
    } catch (e) {
      lastError = '$e';
      logger.w('[ArtexWeb] $e');
      try {
        request.response.statusCode = 500;
        request.response.write('$e');
        await request.response.close();
      } catch (_) {
        // 连接已断
      }
    }
  }

  // ---------------------------------------------------------------- 静态

  Future<void> _serveStatic(HttpRequest request) async {
    final uriPath = request.uri.path;
    final candidates = <String>[];
    if (uriPath == '/' || uriPath.isEmpty) {
      candidates.add('index.html');
    } else {
      final clean = uriPath.startsWith('/') ? uriPath.substring(1) : uriPath;
      if (uriPath.endsWith('/')) {
        candidates.add('${clean}index.html');
      } else {
        candidates.add(clean);
        candidates.add('$clean/index.html');
        candidates.add('$clean.html');
      }
    }

    for (final rel in candidates) {
      final data = await _readAsset(rel);
      if (data != null) {
        _writeData(request.response, rel, data);
        return;
      }
    }

    final notFound = await _readAsset('404.html');
    if (notFound != null) {
      request.response.statusCode = 404;
      _writeData(request.response, '404.html', notFound);
    } else {
      request.response.statusCode = 404;
      request.response.write('Not found: $uriPath');
      await request.response.close();
    }
  }

  Future<Uint8List?> _readAsset(String rel) async {
    final cached = _cache[rel];
    if (cached != null) return cached;
    try {
      final data = await rootBundle.load('$_assetRoot/$rel');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      // 只缓存小文件，避免把整站 9.5MB 全塞进内存
      if (bytes.length <= 512 * 1024) {
        if (_cacheBytes + bytes.length > _cacheLimit) {
          _cache.clear();
          _cacheBytes = 0;
        }
        _cache[rel] = bytes;
        _cacheBytes += bytes.length;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  void _writeData(HttpResponse response, String rel, Uint8List data) {
    response.headers.contentType = _contentTypeOf(rel);
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.contentLength = data.length;
    response.add(data);
    unawaited(response.close());
  }

  static ContentType _contentTypeOf(String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'html':
        return ContentType('text', 'html', charset: 'utf-8');
      case 'js':
      case 'mjs':
        return ContentType('application', 'javascript', charset: 'utf-8');
      case 'css':
        return ContentType('text', 'css', charset: 'utf-8');
      case 'json':
        return ContentType('application', 'json', charset: 'utf-8');
      case 'txt':
        return ContentType('text', 'plain', charset: 'utf-8');
      case 'svg':
        return ContentType('image', 'svg+xml', charset: 'utf-8');
      case 'png':
        return ContentType('image', 'png');
      case 'jpg':
      case 'jpeg':
        return ContentType('image', 'jpeg');
      case 'webp':
        return ContentType('image', 'webp');
      case 'ico':
        return ContentType('image', 'x-icon');
      case 'woff2':
        return ContentType('font', 'woff2');
      case 'woff':
        return ContentType('font', 'woff');
      case 'ttf':
        return ContentType('font', 'ttf');
      default:
        return ContentType('application', 'octet-stream');
    }
  }

  // ---------------------------------------------------------------- 反代

  /// 把 `/api/**` 转发到 [proxyBase]，流式回吐（SSE 依赖这个）。
  ///
  /// [proxyBase] 为空（独立模式）或外部后端连不上时，交给 App 内置的
  /// [ArtexLocalBackend] —— 这样「前后端都在 App 里」，不需要 Termux/root/PG。
  Future<void> _proxy(HttpRequest request) async {
    final base = proxyBase.trim();
    final response = request.response;
    if (base.isEmpty) {
      await ArtexLocalBackend.instance.handle(request);
      return;
    }

    final target = Uri.parse('$base${request.uri.path}')
        .replace(query: request.uri.hasQuery ? request.uri.query : null);
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      // 本地回环，绝不能被系统代理（也就是我们自己）再抓一遍
      client.findProxy = (_) => 'DIRECT';
      client.badCertificateCallback = (cert, host, port) => true;

      final upstream = await client.openUrl(request.method, target);
      // 头：转发除「逐跳」之外的全部（token 在 Authorization 里，必须带过去）
      request.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower == 'host' ||
            lower == 'connection' ||
            lower == 'keep-alive' ||
            lower == 'transfer-encoding' ||
            lower == 'content-length' ||
            lower == 'accept-encoding') {
          return;
        }
        for (final v in values) {
          upstream.headers.add(name, v);
        }
      });
      upstream.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');

      final body = await request.fold<List<int>>(<int>[], (prev, chunk) => prev..addAll(chunk));
      if (body.isNotEmpty) {
        upstream.contentLength = body.length;
        upstream.add(body);
      }

      final resp = await upstream.close().timeout(const Duration(seconds: 300));
      response.statusCode = resp.statusCode;
      response.bufferOutput = false; // SSE：来一段吐一段
      resp.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower == 'transfer-encoding' ||
            lower == 'connection' ||
            lower == 'keep-alive' ||
            lower == 'content-length' ||
            lower == 'content-encoding') {
          return;
        }
        for (final v in values) {
          response.headers.add(name, v);
        }
      });

      await for (final chunk in resp) {
        response.add(chunk);
        await response.flush();
      }
      await response.close();
    } catch (e) {
      logger.w('[ArtexWeb] proxy ${request.uri.path} failed: $e -> embedded fallback');
      // 外部后端不可用：降级到内置服务端（响应已开始写的场景除外）
      try {
        await ArtexLocalBackend.instance.handle(request);
      } catch (inner) {
        logger.w('[ArtexWeb] embedded fallback failed: $inner');
        try {
          response.statusCode = HttpStatus.badGateway;
          response.write('{"error":"${e.toString().replaceAll('"', "'")}"}');
          await response.close();
        } catch (_) {
          // 响应头已经发出去 / 连接已断：只能放弃
        }
      }
    } finally {
      client?.close(force: false);
    }
  }
}
