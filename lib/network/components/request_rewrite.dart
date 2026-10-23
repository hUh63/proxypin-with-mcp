/*
 * Copyright 2024 Hongen Wang All rights reserved.
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
import 'dart:convert';

import 'package:charset/charset.dart' as charset;
import 'package:proxypin/network/components/interceptor.dart';
import 'package:proxypin/network/components/manager/environment_manager.dart';
import 'package:proxypin/network/components/manager/request_rewrite_manager.dart';
import 'package:proxypin/network/http/constants.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/util/cache.dart';
import 'package:proxypin/network/util/file_read.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/uri.dart';
import 'package:proxypin/utils/lang.dart';

import 'manager/rewrite_rule.dart';

///  RequestRewriteComponent is a component that can rewrite the request before sending it to the server.
/// @author Hongen Wang
class RequestRewriteInterceptor extends Interceptor {
  static RequestRewriteInterceptor instance = RequestRewriteInterceptor._();

  final requestRewriteManager = RequestRewriteManager.instance;

  RequestRewriteInterceptor._();

  /// 已编译正则缓存：重写规则可能被高频请求命中，避免每条请求都重新编译
  static final _regexCache = LruCache<String, RegExp>(256);

  /// 构造 RegExp；若未启用正则则自动转义为字面量匹配，若 pattern 不合法则回退为字面量匹配
  /// 分组引用正则：`$1` / `${1}`
  static final RegExp _groupRefRegExp = RegExp(r'\$\{(\d+)\}|\$(\d+)');

  /// 展开正则替换模板中的分组引用（上游 #925）
  ///
  /// 支持 `$0`~`$99`（`$0` = 整段匹配）与 `${1}` 写法。用单次遍历替换：
  /// - 多位数分组号不会被拆错（`$11` 不会先当成 `$1` 再补个 `1`）；
  /// - 分组内容里恰好含 `$1` 这类文本时，也不会被二次替换；
  /// - 越界引用（如正则里只有 1 个分组却写了 `$2`）保持原样，便于排查写法。
  static String _expandRegexGroups(String template, Match match) {
    if (!template.contains(r'$')) return template;
    return template.replaceAllMapped(_groupRefRegExp, (ref) {
      final index = int.tryParse(ref.group(1) ?? ref.group(2) ?? '');
      if (index == null || index > match.groupCount) {
        return ref.group(0)!;
      }
      return match.group(index) ?? '';
    });
  }

  static RegExp _toRegExp(
    String pattern, {
    bool useRegex = true,
    bool caseSensitive = true,
  }) {
    final key = '$useRegex|$caseSensitive|$pattern';
    return _regexCache.pubIfAbsent(key, () {
      if (!useRegex) {
        return RegExp(RegExp.escape(pattern), caseSensitive: caseSensitive);
      }
      try {
        return RegExp(pattern, caseSensitive: caseSensitive);
      } catch (_) {
        return RegExp(RegExp.escape(pattern), caseSensitive: caseSensitive);
      }
    });
  }

  /// 用环境变量渲染 {{name}}。若 EnvironmentManager 未加载或未启用,返回原字符串。
  /// 注意:只对写入请求/响应的字段渲染,key(匹配正则)不做变量替换,避免正则元字符与变量语法混淆。
  static String? _renderEnv(String? input) =>
      EnvironmentManager.tryRender(input);

  /// 生成一个副本,其中所有会输出到请求/响应的字段(value/redirectUrl/body/headers/path/queryParam)已做变量渲染。
  /// 原始配置不修改。
  static RewriteItem _renderItem(RewriteItem item) {
    if (EnvironmentManager.instanceOrNull?.enabled != true) return item;
    // 快速判断:所有相关字符串字段都不含 `{{` 时直接返回原对象,避免拷贝开销。
    // 多值 header(List,如 Set-Cookie)需逐个值检查。
    bool hasToken(dynamic v) =>
        v is String ? v.contains('{{') : (v is List ? v.any((e) => e is String && e.contains('{{')) : false);
    final values = item.values;
    if (!hasToken(values['value']) &&
        !hasToken(values['redirectUrl']) &&
        !hasToken(values['body']) &&
        !hasToken(values['path']) &&
        !hasToken(values['queryParam']) &&
        !(values['headers'] is Map &&
            (values['headers'] as Map).values.any(hasToken))) {
      return item;
    }
    final copy = RewriteItem(item.type, item.enabled, values: Map.of(values));
    copy.value = _renderEnv(copy.value);
    copy.redirectUrl = _renderEnv(copy.redirectUrl);
    copy.body = _renderEnv(copy.body);
    copy.path = _renderEnv(copy.path);
    copy.queryParam = _renderEnv(copy.queryParam);
    final headers = copy.headers;
    if (headers != null) {
      copy.headers = headers.map((k, v) {
        if (v is List) {
          return MapEntry(k, v.map((e) => _renderEnv(e.toString()) ?? e.toString()).toList());
        }
        return MapEntry(k, _renderEnv(v) ?? v);
      });
    }
    return copy;
  }

  @override
  Future<HttpRequest?> onRequest(HttpRequest request) async {
    //重写请求
    try {
      var url = request.requestUrl;
      await requestRewrite(url, request);
    } catch (e, t) {
      // 单条规则出错（正则写坏、变量渲染失败、文件读取失败）不能让整条请求失败：
      // 记录后按「未改写」继续转发，与 onResponse 的处理保持一致。
      logger.e('[${request.requestId}] 请求重写异常 ', error: e, stackTrace: t);
    }
    return request;
  }

  @override
  Future<HttpResponse?> onResponse(
    HttpRequest request,
    HttpResponse response,
  ) async {
    //重写响应
    try {
      var url = request.requestUrl;
      await responseRewrite(url, response);
    } catch (e, t) {
      // 不要把异常信息写进响应体：客户端会收到 "FormatException: ..." 之类
      // 的 Dart 异常文本，真实响应内容直接丢失，比不改写还糟。
      logger.e('[${request.requestId}] 响应重写异常 ', error: e, stackTrace: t);
    }
    return response;
  }

  ///获取重定向
  Future<String?> getRedirectRule(String? url) async {
    var manager = await requestRewriteManager;
    var rewriteRule = manager.getRewriteRule(url, [RuleType.redirect]);
    if (rewriteRule == null) {
      return null;
    }

    var rewriteItems = await manager.getRewriteItems(rewriteRule);
    var redirectUrl = rewriteItems
        ?.firstWhereOrNull((element) => element.enabled)
        ?.redirectUrl;
    // 先做通配符替换(基于模板中的字面 `*`),再做环境变量渲染;
    // 顺序反过来会把变量值中的 `*` 也当成通配符替换,破坏 URL。
    if (rewriteRule.url.contains("*") && redirectUrl?.contains("*") == true) {
      String ruleUrl = rewriteRule.url.replaceAll("*", "");
      redirectUrl = redirectUrl?.replaceAll("*", url!.replaceAll(ruleUrl, ""));
    }
    redirectUrl = _renderEnv(redirectUrl);
    return redirectUrl;
  }

  /// 重写请求
  Future<void> requestRewrite(String url, HttpRequest request) async {
    var manager = await RequestRewriteManager.instance;
    var rewriteRule = manager.getRewriteRule(url, [
      RuleType.requestReplace,
      RuleType.requestUpdate,
    ]);

    if (rewriteRule?.type == RuleType.requestReplace) {
      var rewriteItems = await manager.getRewriteItems(rewriteRule!);
      if (rewriteItems == null) {
        return;
      }
      for (var item in rewriteItems) {
        if (item.enabled) {
          await _replaceRequest(request, _renderItem(item));
        }
      }
    }

    if (rewriteRule?.type == RuleType.requestUpdate) {
      var rewriteItems = await manager.getRewriteItems(rewriteRule!);
      if (rewriteItems == null) {
        return;
      }
      for (var item in rewriteItems) {
        if (item.enabled) {
          await _updateRequest(request, _renderItem(item));
        }
      }
    }
  }

  /// 重写响应
  Future<bool> responseRewrite(String? url, HttpResponse response) async {
    var manager = await RequestRewriteManager.instance;

    var rewriteRule = manager.getRewriteRule(url, [
      RuleType.responseReplace,
      RuleType.responseUpdate,
    ]);
    if (rewriteRule == null) {
      return false;
    }

    if (rewriteRule.type == RuleType.responseReplace) {
      var rewriteItems = await manager.getRewriteItems(rewriteRule);
      if (rewriteItems == null) {
        return false;
      }
      for (var item in rewriteItems) {
        if (item.enabled) {
          await _replaceResponse(response, _renderItem(item));
        }
      }
      return true;
    }

    if (rewriteRule.type == RuleType.responseUpdate) {
      var rewriteItems = await manager.getRewriteItems(rewriteRule);
      if (rewriteItems == null) {
        return false;
      }

      for (var item in rewriteItems) {
        if (item.enabled) {
          await _updateMessage(response, _renderItem(item));
        }
      }
      return true;
    }

    return false;
  }

  Future<void> _updateRequest(HttpRequest request, RewriteItem item) async {
    var paramTypes = [
      RewriteType.addQueryParam,
      RewriteType.removeQueryParam,
      RewriteType.updateQueryParam,
    ];

    if (paramTypes.contains(item.type)) {
      var requestUri = request.requestUri;
      Map<String, dynamic> queryParameters = LinkedHashMap.from(
        requestUri!.queryParameters,
      );

      switch (item.type) {
        case RewriteType.addQueryParam:
          queryParameters[item.key!] = item.value;
          break;
        case RewriteType.removeQueryParam:
          if (item.value?.trim().isNotEmpty == true) {
            var val = queryParameters[item.key!];
            if (val == null ||
                !_toRegExp(
                  item.value!,
                  useRegex: item.useRegex,
                ).hasMatch(val)) {
              break;
            }
          }
          queryParameters.remove(item.key!);
          break;
        case RewriteType.updateQueryParam:
          var itemKey = item.key;
          if (itemKey == null || itemKey.trim().isEmpty) return;

          var entries = Map.of(queryParameters).entries;
          var regExp = _toRegExp(item.key!, useRegex: item.useRegex);

          for (var entry in entries) {
            var line = "${entry.key}=${entry.value}";

            if (regExp.hasMatch(line)) {
              // 上游 #925：此处此前直接把 $1/$2 原样写回，正则分组不生效
              line = line.replaceAllMapped(regExp, (m) => _expandRegexGroups(item.value ?? '', m));
              var pair = line.splitFirst(HttpConstants.equal);
              if (pair.first != entry.key) queryParameters.remove(entry.key);

              queryParameters[pair.first] = pair.length > 1 ? pair.last : '';
              break;
            }
          }
          break;
        default:
          break;
      }
      requestUri = requestUri.replace(
        query: UriUtils.mapToQuery(queryParameters),
      );
      if (requestUri.isScheme('https')) {
        request.uri =
            requestUri.path +
            (requestUri.hasQuery ? "?${requestUri.query}" : "");
      } else {
        request.uri = requestUri.toString();
      }
      return;
    }

    await _updateMessage(request, item);
  }

  /// 按报文声明的字符集把改写后的文本编码回字节。
  ///
  /// 以前非 UTF-8 分支写的是 `text.codeUnits`——String 里的中文码点 > 0xFF，
  /// codeUnits 得到的是 UTF-16 码元，写回去客户端必然是乱码（GBK 站点上改写
  /// 一个中文串就坏一条请求）。
  static List<int> _encodeText(String text, String? charsetName) {
    final name = (charsetName ?? 'utf-8').toLowerCase();
    if (name == 'utf-8' || name == 'utf8') return utf8.encode(text);
    try {
      final encoding = charset.Charset.getByName(name);
      if (encoding != null) return encoding.encode(text);
    } catch (_) {
      // 未知/不支持的字符集，退回 UTF-8：比写 UTF-16 码元安全。
    }
    return utf8.encode(text);
  }

  //修改消息
  Future<void> _updateMessage(HttpMessage message, RewriteItem item) async {
    if (item.type == RewriteType.updateBody && message.body != null) {
      String body = (await message.decodeBodyString()).replaceAllMapped(
        _toRegExp(item.key!, useRegex: item.useRegex),
        (match) => _expandRegexGroups(item.value ?? '', match),
      );

      message.body = _encodeText(body, message.charset);

      message.headers.remove(HttpHeaders.CONTENT_ENCODING);
      message.headers.contentLength = message.body!.length;
      return;
    }

    if (item.type == RewriteType.addHeader) {
      message.headers.set(item.key!, item.value ?? '');
      return;
    }

    if (item.type == RewriteType.removeHeader) {
      if (item.value?.trim().isNotEmpty == true) {
        var val = message.headers.get(item.key!);
        if (val == null ||
            !_toRegExp(item.value!, useRegex: item.useRegex).hasMatch(val)) {
          return;
        }
      }
      message.headers.remove(item.key!);
      return;
    }

    if (item.type == RewriteType.updateHeader) {
      if (item.key == null || item.key?.trim().isEmpty == true) return;

      var headers = Map.of(message.headers.getHeaders());
      var regExp = _toRegExp(
        item.key!,
        useRegex: item.useRegex,
        caseSensitive: false,
      );

      headers.forEach((key, values) {
        var line = "$key: ${values.firstOrNull ?? ''}";
        if (regExp.hasMatch(line)) {
          // 上游 #925：同样支持 $1/$2 等分组引用
          line = line.replaceAllMapped(regExp, (m) => _expandRegexGroups(item.value ?? '', m));
          var pair = line.splitFirst(HttpConstants.colon);
          if (pair.first != key) message.headers.remove(key);
          message.headers.set(pair.first, pair.length > 1 ? pair.last : '');
        }
      });
      return;
    }
  }

  //替换请求
  Future<void> _replaceRequest(HttpRequest request, RewriteItem item) async {
    if (item.type == RewriteType.replaceRequestLine) {
      request.method = item.method ?? request.method;
      final baseUri = Uri.tryParse(request.requestUrl);
      if (baseUri == null) {
        logger.w('重写请求行失败：URL 无法解析 (${request.requestUrl})');
        return;
      }
      var uri = baseUri.replace(path: item.path, query: item.queryParam);
      if (uri.isScheme('https')) {
        request.uri = uri.path + (uri.hasQuery ? "?${uri.query}" : "");
      } else {
        request.uri = uri.toString();
      }
      return;
    }
    await _replaceHttpMessage(request, item);
  }

  //替换相应
  Future<void> _replaceResponse(HttpResponse response, RewriteItem item) async {
    if (item.type == RewriteType.replaceResponseStatus &&
        item.statusCode != null) {
      response.status = HttpStatus.valueOf(item.statusCode!);
      return;
    }
    await _replaceHttpMessage(response, item);
  }

  Future<void> _replaceHttpMessage(
    HttpMessage message,
    RewriteItem item,
  ) async {
    if ((item.type == RewriteType.replaceRequestHeader ||
            item.type == RewriteType.replaceResponseHeader) &&
        item.headers != null) {
      item.headers?.forEach((key, value) {
        message.headers.remove(key);
        if (value is List) {
          for (var v in value) {
            message.headers.add(key, v.toString());
          }
        } else {
          message.headers.set(key, value.toString());
        }
      });
      return;
    }

    if (item.type == RewriteType.replaceResponseBody ||
        item.type == RewriteType.replaceRequestBody) {
      if (item.bodyType == ReplaceBodyType.file.name) {
        if (item.bodyFile == null) return;

        // 文件被删/路径失效时 readFile 会抛 PathNotFoundException；旧实现让它
        // 冒到 onResponse 的 catch，于是响应体被替换成异常文本。
        List<int>? bytes;
        try {
          bytes = await FileRead.readFile(item.bodyFile!);
        } catch (e) {
          logger.w('重写用的文件读取失败，保留原始报文: ${item.bodyFile}', error: e);
          return;
        }
        message.body = bytes;
        message.headers.contentLength = bytes.length;
        message.headers.remove(HttpHeaders.CONTENT_ENCODING);
        return;
      }

      if (item.body != null) {
        message.body = _encodeText(item.body!, message.charset);
        message.headers.contentLength = message.body!.length;
        message.headers.remove(HttpHeaders.CONTENT_ENCODING);
      }
      return;
    }
  }
}
