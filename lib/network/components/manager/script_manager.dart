/*
 * Copyright 2023 Hongen Wang All rights reserved.
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

import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:proxypin/network/components/manager/environment_manager.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/util/cache.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/url_pattern.dart';
import 'package:proxypin/network/util/random.dart';
import 'package:proxypin/storage/path.dart';
import 'package:proxypin/ui/component/device.dart';
import 'package:http/http.dart' as http;

import '../js/script_engine.dart';
import 'package:proxypin/network/util/serial_file_writer.dart';

/// @author wanghongen
/// 2023/10/06
/// js脚本
class ScriptManager {
  static String template = """
// e.g. Add/Update/Remove：Queries、Headers、Body
async function onRequest(context, request) {
  console.log(request.url);
  //Update or add Header
  //request.headers["X-New-Headers"] = "My-Value";
  
  // Update Body use fetch API request，具体文档可网上搜索fetch API
  //request.body = await fetch('https://www.baidu.com/').then(response => response.text());
  return request;
}

//You can modify the Response Data here before it goes to the client
async function onResponse(context, request, response) {
  // response.statusCode = 200;

  //var body = JSON.parse(response.body);
  //body['key'] = "value";
  //response.body = JSON.stringify(body);
  return response;
}
  """;

  /// 内置「抖音签名」脚本模板：命中抖音域名时自动补签名头。
  /// 依赖注入运行时的签名库：DouyinSign / XMedusa / TTEncryptV5
  /// （见 工具箱 → 字节签名）。
  static String douyinTemplate = """
// 抖音（字节系）请求自动签名
// 命中下方域名时自动补 X-Khronos / X-Gorgon / X-Helios / X-SS-Stub（可选 X-Medusa）
const DOUYIN_HOSTS = ['snssdk.com', 'amemv.com', 'douyin.com', 'bytedance.com'];

async function onRequest(context, request) {
  const url = request.url || '';
  if (!DOUYIN_HOSTS.some(function (h) { return url.indexOf(h) >= 0; })) {
    return request;
  }

  const q = url.indexOf('?');
  const query = q >= 0 ? url.substring(q + 1) : '';
  const body = typeof request.body === 'string' ? request.body : '';

  const khronos = DouyinSign.khronos();
  request.headers['X-Khronos'] = String(khronos);
  request.headers['X-Gorgon'] = DouyinSign.xgorgon({ query: query, body: body, khronos: khronos });
  request.headers['X-Helios'] = DouyinSign.helios({ khronos: khronos });
  if (body) {
    request.headers['X-SS-Stub'] = DouyinSign.xssStub(body);
  }

  // X-Medusa（可选，Android）：多维环境动态挑战签名
  // request.headers['X-Medusa'] = XMedusa.encrypt({ url: url, params: {}, khronos: khronos });

  return request;
}

async function onResponse(context, request, response) {
  return response;
}
  """;

  static String separator = Platform.pathSeparator;
  static ScriptManager? _instance;
  bool enabled = true;
  List<ScriptItem> list = [];

  final ExpiringCache<ScriptItem, String> _scriptMap = ExpiringCache<ScriptItem, String>(duration: Duration(minutes: 15));

  static late JavaScriptRuntimePool flutterJsPool;

  static String? deviceId;

  static final List<LogHandler> _logHandlers = [];

  ScriptManager._();

  ///单例
  static Future<ScriptManager> get instance async {
    if (_instance == null) {
      _instance = ScriptManager._();
      await _instance?.reloadScript();
      flutterJsPool = JavaScriptRuntimePool(size: JavaScriptEngine.defaultRuntimePoolSize, consoleLog: consoleLog);
      deviceId = await DeviceUtils.deviceId();

      logger.d('init script manager $deviceId');
    }
    return _instance!;
  }

  static void registerConsoleLog(String fromWindowId) {
    LogHandler logHandler = LogHandler(
        channelId: fromWindowId,
        handle: (logInfo) {
          DesktopMultiWindow.invokeMethod(fromWindowId, "consoleLog", logInfo.toJson()).onError((e, t) {
            logger.e("consoleLog error: $e");
            removeLogHandler(fromWindowId);
          });
        });
    registerLogHandler(logHandler);
  }

  static void registerLogHandler(LogHandler logHandler) {
    if (_logHandlers.any((it) => it.channelId == logHandler.channelId)) {
      _logHandlers.removeWhere((it) => it.channelId == logHandler.channelId);
    }
    _logHandlers.add(logHandler);
  }

  static void removeLogHandler(String channelId) {
    _logHandlers.removeWhere((element) => channelId == element.channelId);
  }

  static dynamic consoleLog(dynamic args) async {
    if (_logHandlers.isEmpty) {
      return;
    }

    var level = args.removeAt(0);
    String output = args.join(' ');
    if (level == 'info') level = 'warn';
    LogInfo logInfo = LogInfo(level, output);
    for (int i = 0; i < _logHandlers.length; i++) {
      _logHandlers[i].handle.call(logInfo);
    }
  }

  ///重新加载脚本
  Future<void> reloadScript() async {
    List<ScriptItem> scripts = [];
    var file = await _path;
    logger.d("reloadScript ${file.path}");

    if (await file.exists()) {
      var content = await file.readAsString();
      if (content.isEmpty) {
        return;
      }
      // 配置损坏时不能让脚本功能整体起不来：逐条容错 + 缺字段按默认处理。
      try {
        var config = jsonDecode(content);
        // 缺 enabled 字段（更早版本的配置文件）时按「开启」处理。
        enabled = config['enabled'] != false;
        final items = config['list'];
        if (items is List) {
          for (var entry in items) {
            try {
              if (entry is Map) scripts.add(ScriptItem.fromJson(entry));
            } catch (e) {
              logger.w('跳过无法解析的脚本: $e');
            }
          }
        }
      } catch (e) {
        logger.e('脚本配置解析失败，按空配置处理', error: e);
      }
    }
    list = scripts;
    _scriptMap.clear();
    _wsHookCached = null;
  }

  /// 同步获取已初始化的实例（未初始化时为 null）
  static ScriptManager? get instanceOrNull => _instance;

  bool? _wsHookCached;
  DateTime? _wsHookCheckedAt;

  /// 声明式检测：需以 `function onWebSocket(...)` 形式定义（支持 async），
  /// 用正则而非简单包含匹配，避免注释中出现该词导致误判与无谓开销。
  static final RegExp _wsHookPattern = RegExp(r'function\s+onWebSocket\b');

  /// 是否存在声明了 `onWebSocket` 的启用脚本（结果缓存 3 秒，避免每帧读盘）
  Future<bool> hasWebSocketHook() async {
    if (!enabled) return false;
    final now = DateTime.now();
    final checkedAt = _wsHookCheckedAt;
    final cached = _wsHookCached;
    if (cached != null && checkedAt != null && now.difference(checkedAt) < const Duration(seconds: 3)) {
      return cached;
    }
    var found = false;
    for (final item in list) {
      if (!item.enabled) continue;
      try {
        // 探测只读缓存，不能为了一段正则去下载远程脚本
        final script = await readCachedScript(item);
        if (script != null && _wsHookPattern.hasMatch(script)) {
          found = true;
          break;
        }
      } catch (_) {}
    }
    _wsHookCached = found;
    _wsHookCheckedAt = now;
    return found;
  }

  /// 把 WebSocket 帧派发给脚本（上游 #722）。
  ///
  /// 语义为**只读捕获**：脚本通过 `onWebSocket(context, ws)` 读取帧内容
  /// （url / 方向 / opcode / payload / rawBody / 长度），不参与转发字节，
  /// 因此不会影响连接稳定性；如需改包请使用「WebSocket 拦截」。
  Future<void> dispatchWebSocketFrame(HttpMessage message, WebSocketFrame frame) async {
    if (!await hasWebSocketHook()) {
      return;
    }

    final url = message.requestUrl ?? '';
    final wsJson = jsonEncode({
      'url': url,
      'direction': frame.isFromClient ? 'client_to_server' : 'server_to_client',
      'opcode': frame.opcode,
      'binary': !frame.isText,
      'text': frame.isText ? frame.payloadDataAsString : null,
      'payload': frame.payloadDataAsString,
      'rawBody': frame.payloadData.toList(),
      'length': frame.payloadLength,
      'time': frame.time.millisecondsSinceEpoch,
    });

    for (final item in list) {
      if (!item.enabled || !item.match(url)) continue;
      try {
        final script = await getScript(item);
        if (script == null || !_wsHookPattern.hasMatch(script)) continue;

        final context = jsonEncode(scriptContext(item));
        await flutterJsPool.run((flutterJs) async {
          await flutterJs.evaluateAsync("var ws = $wsJson, context = $context; $script\n"
              "  (typeof onWebSocket === 'function'"
              " ? Promise.resolve(onWebSocket(context, ws))"
              "    .catch(function(e){ console.error('onWebSocket error: ' + e); })"
              " : null)");
        });
      } catch (e, st) {
        logger.e('WebSocket 脚本执行失败: ${item.name}', error: e, stackTrace: st);
      }
    }
  }

  static Future<File> get _path async {
    final path = await Paths.homePath();
    var file = File('$path${separator}script.json');
    if (!await file.exists()) {
      await file.create();
    }
    return file;
  }

  /// 远程脚本缓存与刷新参数（上游 #973）。
  static const Duration remoteCacheTtl = Duration(minutes: 10);
  static const Duration remoteFetchTimeout = Duration(seconds: 15);

  /// 每个远程地址上次尝试刷新的时间（热路径上的节流，避免反复重试）
  final Map<String, DateTime> _remoteRefreshAt = {};

  Future<String?> getScript(ScriptItem item) async {
    if (_scriptMap.containsKey(item)) {
      return _scriptMap[item]!;
    }

    // 远程脚本：有磁盘缓存就先用缓存，刷新丢到后台，不阻塞当前请求
    if (item.isRemote) {
      final cached = await readCachedScript(item);
      if (cached != null) {
        _scriptMap[item] = cached;
        _refreshRemoteInBackground(item);
        return cached;
      }
      // 首次使用且没有任何缓存：同步取一次（带超时），取到后落盘
      return await downloadRemoteScript(item, persist: true);
    }

    final cached = await readCachedScript(item);
    if (cached == null) {
      return null;
    }
    _scriptMap[item] = cached;
    return cached;
  }

  /// 只读缓存（内存 → 磁盘），**不联网**。
  ///
  /// 脚本编辑器打开、以及「是否存在 onWebSocket」这类探测都走它：远程脚本在
  /// 这些场景下不应该发起网络请求（以前编辑器打开时干脆跳过，导致永远空白）。
  Future<String?> readCachedScript(ScriptItem item) async {
    final mem = _scriptMap[item];
    if (mem != null) {
      return mem;
    }
    final path = item.scriptPath;
    if (path == null || path.isEmpty) {
      return null;
    }
    try {
      final home = await Paths.homePath();
      final file = File(home + path);
      // 脚本文件被手工删掉/移动时以前直接抛，异常会冒到每条命中该规则的请求上。
      if (!await file.exists()) {
        logger.w('脚本文件不存在: ${file.path}');
        return null;
      }
      return await file.readAsString();
    } catch (e) {
      logger.w('读取脚本文件失败: $path', error: e);
      return null;
    }
  }

  /// 下载远程脚本。成功时更新内存缓存，[persist] 为 true 时同时写盘缓存。
  Future<String?> downloadRemoteScript(ScriptItem item, {bool persist = true}) async {
    final url = item.remoteUrl?.trim();
    if (url == null || !_isHttpUrl(url)) {
      return null;
    }
    _remoteRefreshAt[url] = DateTime.now();
    try {
      final resp = await http.get(Uri.parse(url)).timeout(remoteFetchTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        logger.w('远程脚本下载失败 HTTP ${resp.statusCode}: $url');
        return null;
      }
      final content = utf8.decode(resp.bodyBytes, allowMalformed: true);
      if (content.trim().isEmpty) {
        logger.w('远程脚本内容为空: $url');
        return null;
      }
      _scriptMap[item] = content;
      if (persist) {
        await _writeCache(item, content);
      }
      return content;
    } catch (e) {
      logger.w('远程脚本下载异常: $url', error: e);
      return null;
    }
  }

  /// 后台刷新（stale-while-revalidate）：命中缓存后异步拉最新内容，失败保持旧缓存。
  void _refreshRemoteInBackground(ScriptItem item) {
    final url = item.remoteUrl?.trim();
    if (url == null || url.isEmpty) {
      return;
    }
    final last = _remoteRefreshAt[url];
    if (last != null && DateTime.now().difference(last) < remoteCacheTtl) {
      return;
    }
    _remoteRefreshAt[url] = DateTime.now();
    unawaited(downloadRemoteScript(item).catchError((Object e) {
      logger.w('远程脚本后台刷新失败: $url', error: e);
      return null;
    }));
  }

  /// 写脚本缓存文件。远程脚本第一次写时顺便分配 scriptPath 并把配置落盘，
  /// 否则重启后 item 没有路径，缓存文件变成孤儿、脚本又变回空的。
  Future<void> _writeCache(ScriptItem item, String content) async {
    try {
      var path = item.scriptPath;
      if (path == null || path.isEmpty) {
        path = "${separator}scripts${separator}${RandomUtil.randomString(16)}.js";
        item.scriptPath = path;
        unawaited(flushConfig());
      }
      final home = await Paths.homePath();
      final file = File(home + path);
      await file.create(recursive: true);
      await SerialFileWriter.writeString(file, content);
    } catch (e) {
      logger.w('写入脚本缓存失败: ${item.name}', error: e);
    }
  }

  bool _isHttpUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  ///添加脚本
  Future<void> addScript(ScriptItem item, String? script) async {
    // 远程脚本：编辑器里的内容当作初始缓存落盘（#973，重启后不再变空）
    if (item.isRemote) {
      list.add(item);
      if (script != null && script.trim().isNotEmpty) {
        _scriptMap[item] = script;
        await _writeCache(item, script);
      }
      return;
    }

    script ??= template;
    final path = await Paths.homePath();
    String scriptPath = "${separator}scripts$separator${RandomUtil.randomString(16)}.js";
    var file = File(path + scriptPath);
    await file.create(recursive: true);
    await SerialFileWriter.writeString(file, script);
    item.scriptPath = scriptPath;
    list.add(item);
    _scriptMap[item] = script;
  }

  ///更新脚本
  Future<void> updateScript(ScriptItem item, String script) async {
    // 远程脚本：编辑/下载得到的内容写进缓存文件，不能只留在内存（#973）
    if (item.isRemote) {
      _scriptMap[item] = script;
      await _writeCache(item, script);
      return;
    }

    final home = await Paths.homePath();
    final file = File(home + item.scriptPath!);
    // 内容没变也必须在文件缺失时补写：scripts 目录被清理/迁移后，内存里还有
    // 脚本内容，磁盘上却没有 —— 下次启动脚本就变成空的了。
    if (_scriptMap[item] == script && await file.exists()) {
      return;
    }

    await SerialFileWriter.writeString(file, script);
    _scriptMap[item] = script;
  }

  ///删除脚本
  Future<void> removeScript(int index) async {
    var item = list.removeAt(index);
    _scriptMap.remove(item);

    if (item.scriptPath != null) {
      final home = await Paths.homePath();
      // 未 await 的 delete() 失败（文件已被外部清理）会变成未捕获的异步异常，
      // 而且函数返回时文件可能还在。
      try {
        final file = File(home + item.scriptPath!);
        if (await file.exists()) await file.delete();
      } catch (e) {
        logger.w('删除脚本文件失败: ${item.scriptPath}', error: e);
      }
    }
  }

  Future<void> clean() async {
    _scriptMap.clear();
    while (list.isNotEmpty) {
      var item = list.removeLast();
      if (item.scriptPath != null) {
        final home = await Paths.homePath();
        try {
          final file = File(home + item.scriptPath!);
          if (await file.exists()) await file.delete();
        } catch (e) {
          logger.w('删除脚本文件失败: ${item.scriptPath}', error: e);
        }
      }
    }
    await flushConfig();
  }

  ///刷新配置
  Future<void> flushConfig() async {
    final path = await _path;
    await SerialFileWriter.writeString(path, jsonEncode({'enabled': enabled, 'list': list}));
  }

  Map<dynamic, dynamic> scriptSession = {};

  ///脚本上下文
  Map<String, dynamic> scriptContext(ScriptItem item) {
    final env = EnvironmentManager.instanceOrNull?.flatMap() ?? const <String, String>{};
    return {
      'scriptName': item.name,
      'os': Platform.operatingSystem,
      'session': scriptSession,
      'deviceId': deviceId,
      'env': env,
    };
  }

  /// 处理脚本可能修改的 env:diff 后写回 EnvironmentManager 并持久化。
  Future<void> _applyScriptEnv(Map<String, String> envBefore, Map<dynamic, dynamic>? scriptContextResult) async {
    if (scriptContextResult == null) return;
    final envAfter = scriptContextResult['env'];
    if (envAfter is! Map) return;
    final mgr = EnvironmentManager.instanceOrNull;
    if (mgr == null || !mgr.enabled) return;
    final changed = mgr.applyScriptEnvChanges(envBefore, envAfter);
    if (changed) {
      // 节流落盘：脚本命中高频接口时，按请求 flush 等于每请求写一次配置文件
      mgr.scheduleFlush();
    }
  }

  ///运行脚本
  Future<HttpRequest?> runScript(HttpRequest request) async {
    if (!enabled) {
      return request;
    }
    var url = request.domainPath;
    for (var item in list) {
      if (item.enabled && item.match(url)) {
        final ctxMap = scriptContext(item);
        // 记录脚本运行前的 env 快照,便于运行后做 diff
        final envBefore = Map<String, String>.from(ctxMap['env'] as Map);
        var context = jsonEncode(ctxMap);
        var jsRequestMap = await JavaScriptEngine.convertJsRequest(request);
        var jsRequest = jsonEncode(jsRequestMap);
        String? script = await getScript(item);
        if (script == null) {
          continue;
        }

        var result = await flutterJsPool.run((flutterJs) async {
          var jsResult = await flutterJs.evaluateAsync(
              """var request = $jsRequest, context = $context;  request['scriptContext'] = context; $script\n  onRequest(context, request)""");
          return await JavaScriptEngine.jsResultResolve(flutterJs, jsResult);
        });
        if (result == null || result is! Map) {
          // 上游 #885：脚本没有返回有效结果时，此前会直接丢弃请求，
          // 表现为网页/接口莫名打不开。这里改为"放行原始请求"并记录告警。
          // 需要阻断请求请在规则里配置「阻止请求」，不要依赖脚本返回空值。
          logger.w('脚本 "${item.name}" 未返回有效结果，已放行原始请求: $url');
          continue;
        }
        request.attributes['scriptContext'] = result['scriptContext'];
        scriptSession = (result['scriptContext'] as Map?)?['session'] ?? {};
        await _applyScriptEnv(envBefore, result['scriptContext']);
        // 脚本未改动请求时保留原始字节，避免 query 重编码/header 重排破坏签名
        if (!JavaScriptEngine.isRequestUnchanged(jsRequestMap, result)) {
          request = JavaScriptEngine.convertHttpRequest(request, result);
        }
      }
    }
    return request;
  }

  /// 独立运行指定脚本（用合成请求，供定时任务/工作流调用）。
  /// 不作用于真实请求；仅执行脚本逻辑并应用 env 副作用。
  /// 复用 runScript 的上下文注入（context/request/onRequest 调用）。
  Future<Map<String, dynamic>?> runStandalone(ScriptItem item) async {
    if (!enabled || !item.enabled) return null;
    try {
      final request = HttpRequest(HttpMethod.get, 'http://standalone.local/script/${item.name ?? 'unnamed'}');
      final ctxMap = scriptContext(item);
      final envBefore = Map<String, String>.from(ctxMap['env'] as Map);
      var context = jsonEncode(ctxMap);
      var jsRequestMap = await JavaScriptEngine.convertJsRequest(request);
      var jsRequest = jsonEncode(jsRequestMap);
      String? script = await getScript(item);
      if (script == null) return null;
      var result = await flutterJsPool.run((flutterJs) async {
        var jsResult = await flutterJs.evaluateAsync(
            """var request = $jsRequest, context = $context;  request['scriptContext'] = context; $script\n  onRequest(context, request)""");
        return await JavaScriptEngine.jsResultResolve(flutterJs, jsResult);
      });
      if (result == null) return null;
      await _applyScriptEnv(envBefore, result['scriptContext']);
      logger.i('独立运行脚本完成: ${item.name}');
      return result;
    } catch (e, st) {
      logger.e('独立运行脚本失败: ${item.name}', error: e, stackTrace: st);
      return null;
    }
  }

  ///运行脚本
  Future<HttpResponse?> runResponseScript(HttpResponse response) async {
    if (!enabled || response.request == null) {
      return response;
    }

    var request = response.request!;
    var url = request.domainPath;
    for (var item in list) {
      if (item.enabled && item.match(url)) {
        // 响应阶段:优先复用请求阶段设置好的 scriptContext(含中途修改过的 env),
        // 否则新构建一个。用于 diff 的 envBefore 从最终传给 JS 的 context 中取。
        final ctxMap =
            (request.attributes['scriptContext'] as Map?)?.cast<String, dynamic>() ?? scriptContext(item);
        final envBefore = Map<String, String>.from(((ctxMap['env'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
        ));
        var context = jsonEncode(ctxMap);
        var jsRequest = jsonEncode(await JavaScriptEngine.convertJsRequest(request));
        var jsResponse = jsonEncode(await JavaScriptEngine.convertJsResponse(response));
        String? script = await getScript(item);
        if (script == null) {
          continue;
        }

        var result = await flutterJsPool.run((flutterJs) async {
          var jsResult = await flutterJs.evaluateAsync(
              """var response = $jsResponse, context = $context;  response['scriptContext'] = context; $script
            \n  onResponse(context, $jsRequest, response);""");
          return await JavaScriptEngine.jsResultResolve(flutterJs, jsResult);
        });
        if (result == null || result is! Map) {
          // 上游 #885：响应脚本没有返回有效结果时，保持响应原样下发，
          // 不再让客户端收不到任何响应（表现为"有请求有响应但页面白屏"）。
          logger.w('响应脚本 "${item.name}" 未返回有效结果，已放行原始响应: $url');
          continue;
        }
        scriptSession = (result['scriptContext'] as Map?)?['session'] ?? {};
        await _applyScriptEnv(envBefore, result['scriptContext']);
        response = JavaScriptEngine.convertHttpResponse(response, result);
      }
    }
    return response;
  }
}

class LogHandler {
  final String channelId;
  final Function(LogInfo logInfo) handle;

  LogHandler({required this.channelId, required this.handle});
}

class LogInfo {
  final DateTime time;
  final String level;
  final String output;

  LogInfo(this.level, this.output, {DateTime? time}) : time = time ?? DateTime.now();

  factory LogInfo.fromJson(Map<String, dynamic> json) {
    return LogInfo(json['level'], json['output'], time: DateTime.fromMillisecondsSinceEpoch(json['time']));
  }

  Map<String, dynamic> toJson() {
    return {'time': time.millisecondsSinceEpoch, 'level': level, 'output': output};
  }

  @override
  String toString() {
    return '{time: $time, level: $level, output: $output}';
  }
}

class ScriptItem {
  bool enabled = true;
  String? name;
  List<String> urls;
  String? scriptPath;
  List<RegExp?>? urlRegs;

  String? remoteUrl;

  ScriptItem(this.enabled, this.name, dynamic urls, {this.scriptPath, this.remoteUrl})
      : urls = urls is String
            ? (urls.contains(',') ? urls.split(',').map((e) => e.trim()).toList() : [urls])
            : (urls is List<String> ? urls : <String>[]);

  /// 是否远程脚本（配置了 remoteUrl）
  bool get isRemote => remoteUrl != null && remoteUrl!.trim().isNotEmpty;

  // 匹配url，任意一个规则匹配即可
  bool match(String url) {
    urlRegs ??= urls.map((u) => UrlPattern.toHostRegExp(u)).toList();
    for (final reg in urlRegs!) {
      if (reg!.hasMatch(url)) return true;
    }
    return false;
  }

  factory ScriptItem.fromJson(Map<dynamic, dynamic> json) {
    final urlField = json['url'];
    List<String> urls;
    if (urlField is List) {
      urls = urlField.cast<String>();
    } else if (urlField is String) {
      urls = urlField.contains(',') ? urlField.split(',').map((e) => e.trim()).toList() : [urlField];
    } else {
      urls = <String>[];
    }

    return ScriptItem(
      json['enabled'],
      json['name'],
      urls,
      scriptPath: json['scriptPath'],
      remoteUrl: json['remoteUrl'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'name': name,
      'url': urls.length == 1 ? urls[0] : urls,
      'scriptPath': scriptPath,
      if (remoteUrl != null) 'remoteUrl': remoteUrl,
    };
  }

  @override
  String toString() {
    return 'ScriptItem{enabled: $enabled, name: $name, url: $urls, scriptPath: $scriptPath, remoteUrl: $remoteUrl}';
  }
}
