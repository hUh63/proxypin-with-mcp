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
import 'package:get/get.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/network/http/http.dart';

/// @author wanghongen
/// 2023/8/4
class SearchModel {
  String? keyword;

  //是否区分大小写
  RxBool caseSensitive = RxBool(false);

  //是否使用正则表达式
  RxBool isRegExp = RxBool(false);

  //搜索范围
  Set<Option> searchOptions = {Option.url};

  //请求方法
  HttpMethod? requestMethod;

  //请求类型
  ContentType? requestContentType;

  //响应类型
  ContentType? responseContentType;

  // 状态码范围（包含两端）
  int? statusCodeFrom;
  int? statusCodeTo;

  // 耗时范围，单位毫秒（包含两端）
  int? durationFromMs;
  int? durationToMs;

  // 协议过滤，可选：HTTP (any), WS, SSE, HTTP1, H2. 如果为空则不过滤
  Set<Protocol> protocols = {};

  // 排序字段：time(时间), duration(耗时), statusCode(状态码)
  SortBy sortBy = SortBy.original;
  // 排序方向：asc(升序), desc(降序)
  SortOrder sortOrder = SortOrder.desc;

  SearchModel([this.keyword]);

  bool get isNotEmpty {
    return keyword?.trim().isNotEmpty == true ||
        requestMethod != null ||
        requestContentType != null ||
        responseContentType != null ||
        statusCodeFrom != null ||
        statusCodeTo != null ||
        durationFromMs != null ||
        durationToMs != null ||
        protocols.isNotEmpty;
  }

  bool get isEmpty {
    return !isNotEmpty;
  }

  ///复制对象
  SearchModel clone() {
    var searchModel = SearchModel(keyword);
    searchModel.searchOptions = Set.from(searchOptions);
    searchModel.requestMethod = requestMethod;
    searchModel.requestContentType = requestContentType;
    searchModel.responseContentType = responseContentType;
    searchModel.statusCodeFrom = statusCodeFrom;
    searchModel.statusCodeTo = statusCodeTo;
    searchModel.durationFromMs = durationFromMs;
    searchModel.durationToMs = durationToMs;
    searchModel.protocols = Set.from(protocols);
    searchModel.caseSensitive = RxBool(caseSensitive.value);
    searchModel.isRegExp = RxBool(isRegExp.value);
    searchModel.sortBy = sortBy;
    searchModel.sortOrder = sortOrder;
    return searchModel;
  }

  @override
  String toString() {
    return 'SearchModel{keyword: $keyword, isRegExp: ${isRegExp.value}, searchOptions: $searchOptions, responseContentType: $responseContentType, requestMethod: $requestMethod, requestContentType: $requestContentType, statusRange: [$statusCodeFrom-$statusCodeTo], durationRangeMs: [$durationFromMs-$durationToMs], protocols: $protocols}';
  }

  /// 根据 keyword、caseSensitive、isRegExp 构造一个文本匹配函数。
  /// keyword 为空时返回 null，调用方应自行处理（视作不过滤）。
  /// 正则编译失败时返回一个永远不匹配的 matcher，避免输入半截正则时一直抛异常。
  bool Function(String) buildMatcher() {
    final pattern = keyword;
    if (pattern == null || pattern.isEmpty) {
      return (_) => true;
    }

    // 缓存已编译的匹配器：filter 会对每条记录调用本方法，
    // 正则场景下每次重新编译 RegExp 在大数据量搜索时会明显卡顿。
    final cacheKey = '${isRegExp.value}|${caseSensitive.value}|$pattern';
    if (_matcherCacheKey == cacheKey) {
      return _cachedMatcher!;
    }
    _matcherCacheKey = cacheKey;

    if (isRegExp.value) {
      try {
        final regex = RegExp(pattern, caseSensitive: caseSensitive.value);
        _cachedMatcher = regex.hasMatch;
      } catch (_) {
        _cachedMatcher = (_) => false;
      }
    } else if (caseSensitive.value) {
      _cachedMatcher = (text) => text.contains(pattern);
    } else {
      final lowered = pattern.toLowerCase();
      _cachedMatcher = (text) => text.toLowerCase().contains(lowered);
    }
    return _cachedMatcher!;
  }

  String? _matcherCacheKey;
  bool Function(String)? _cachedMatcher;

  /// 对搜索结果进行排序（增强版：支持相关性评分）(#843)
  List<HttpRequest> sortResults(List<HttpRequest> results) {
    // 原始顺序：保持容器里的既有次序（上游 #843 —— 搜索后结果的序号与未搜索时一致，
    // 便于按序号定位上下文）。这也是搜索的默认行为。
    if (sortBy == SortBy.original) {
      return results;
    }
    if (sortBy == SortBy.relevance && keyword != null && keyword!.isNotEmpty) {
      // 按相关性排序：计算每个请求与关键词的匹配度
      results.sort((a, b) {
        int scoreA = _calculateRelevanceScore(a);
        int scoreB = _calculateRelevanceScore(b);
        return sortOrder == SortOrder.asc ? scoreA - scoreB : scoreB - scoreA;
      });
    } else {
      results.sort((a, b) {
        int comparison = 0;
        switch (sortBy) {
          case SortBy.time:
            comparison = a.requestTime.compareTo(b.requestTime);
            break;
          case SortBy.duration:
            int durationA = a.response?.responseTime.difference(a.requestTime).inMilliseconds ?? 0;
            int durationB = b.response?.responseTime.difference(b.requestTime).inMilliseconds ?? 0;
            comparison = durationA.compareTo(durationB);
            break;
          case SortBy.statusCode:
            int codeA = a.response?.status.code ?? 0;
            int codeB = b.response?.status.code ?? 0;
            comparison = codeA.compareTo(codeB);
            break;
          case SortBy.relevance:
            // 默认按时间降序
            comparison = b.requestTime.compareTo(a.requestTime);
            break;
          case SortBy.original:
            comparison = 0;
            break;
        }
        return sortOrder == SortOrder.asc ? comparison : -comparison;
      });
    }
    return results;
  }

  /// 计算请求与关键词的相关性评分 (#843)
  int _calculateRelevanceScore(HttpRequest request) {
    if (keyword == null || keyword!.isEmpty) return 0;
    
    final pattern = caseSensitive.value ? keyword! : keyword!.toLowerCase();
    int score = 0;
    
    // URL 匹配权重最高 (100 分)
    final urlToCheck = caseSensitive.value ? request.requestUrl : request.requestUrl.toLowerCase();
    if (urlToCheck.contains(pattern)) {
      score += 100;
      // 完全匹配额外加分
      if (urlToCheck == pattern) score += 50;
    }
    
    // 请求方法匹配 (20 分)
    if (request.method.name.toLowerCase().contains(pattern)) {
      score += 20;
    }
    
    // 响应状态码匹配 (30 分)
    final statusCode = request.response?.status.code ?? 0;
    if (statusCode.toString().contains(pattern)) {
      score += 30;
    }
    
    // 请求体匹配 (50 分)
    if (searchOptions.contains(Option.requestBody)) {
      final bodyToCheck = caseSensitive.value 
          ? (request.body?.toString() ?? '') 
          : (request.body?.toString().toLowerCase() ?? '');
      if (bodyToCheck.contains(pattern)) {
        score += 50;
      }
    }
    
    // 响应体匹配 (50 分)
    if (searchOptions.contains(Option.responseBody)) {
      final responseBodyToCheck = caseSensitive.value 
          ? (request.response?.body?.toString() ?? '') 
          : (request.response?.body?.toString().toLowerCase() ?? '');
      if (responseBodyToCheck.contains(pattern)) {
        score += 50;
      }
    }
    
    // 请求头匹配 (40 分)
    if (searchOptions.contains(Option.requestHeader)) {
      for (var entry in request.headers.entries) {
        final headerToCheck = caseSensitive.value 
            ? '${entry.key}: ${entry.value}' 
            : '${entry.key}: ${entry.value}'.toLowerCase();
        if (headerToCheck.contains(pattern)) {
          score += 40;
          break;
        }
      }
    }
    
    // 响应头匹配 (40 分)
    if (searchOptions.contains(Option.responseHeader)) {
      var respHeaders = (request.response?.headers as Map<String, dynamic>?) ?? {};
      for (var entry in respHeaders.entries) {
        final headerToCheck = caseSensitive.value 
            ? '${entry.key}: ${entry.value}' 
            : '${entry.key}: ${entry.value}'.toLowerCase();
        if (headerToCheck.contains(pattern)) {
          score += 40;
          break;
        }
      }
    }
    
    return score;
  }

  ///是否匹配
  bool filter(HttpRequest request, HttpResponse? response) {
    if (isEmpty) {
      return true;
    }

    if (requestMethod != null && requestMethod != request.method) {
      return false;
    }
    if (requestContentType != null &&
        request.contentType != requestContentType) {
      return false;
    }

    if (responseContentType != null &&
        response?.contentType != responseContentType) {
      return false;
    }

    // status range
    if ((statusCodeFrom != null || statusCodeTo != null) && response != null) {
      var code = response.status.code;
      if (statusCodeFrom != null && code < statusCodeFrom!) {
        return false;
      }
      if (statusCodeTo != null && code > statusCodeTo!) {
        return false;
      }
    }

    // duration range
    if ((durationFromMs != null || durationToMs != null) && response != null) {
      var cost = response.responseTime
          .difference(request.requestTime)
          .inMilliseconds;
      if (durationFromMs != null && cost < durationFromMs!) {
        return false;
      }
      if (durationToMs != null && cost > durationToMs!) {
        return false;
      }
    }

    // protocol filters
    if (protocols.isNotEmpty) {
      bool matched = false;
      for (var p in protocols) {
        if (_matchProtocol(p, request, response)) {
          matched = true;
          break;
        }
      }
      if (!matched) {
        return false;
      }
    }

    if (keyword == null || keyword?.isEmpty == true || searchOptions.isEmpty) {
      return true;
    }

    final matches = buildMatcher();
    for (var option in searchOptions) {
      if (keywordFilter(matches, option, request, response)) {
        return true;
      }
    }

    return false;
  }

  bool _matchProtocol(Protocol p, HttpRequest request, HttpResponse? response) {
    switch (p) {
      case Protocol.https:
        return request.hostAndPort?.scheme == 'https://';
      case Protocol.http:
        return request.requestUrl.startsWith('http://');
      case Protocol.ws:
        return request.isWebSocket ||
            (response != null && response.isWebSocket == true);
      case Protocol.sse:
        return response?.contentType == ContentType.sse;
      case Protocol.http1:
        return request.protocolVersion == 'HTTP/1.1';
      case Protocol.h2:
        return request.protocolVersion == 'HTTP/2' ||
            request.protocolVersion == 'h2';
    }
  }

  ///关键字过滤
  bool keywordFilter(
    bool Function(String) matches,
    Option option,
    HttpRequest request,
    HttpResponse? response,
  ) {
    if (option == Option.url) {
      return matches(request.requestUrl);
    }

    if (option == Option.method) {
      return matches(request.method.name);
    }
    if (option == Option.responseContentType &&
        response != null &&
        matches(response.headers.contentType)) {
      return true;
    }

    if (option == Option.requestBody) {
      if (matches(request.bodyPreview)) {
        return true;
      }
      // 仅在用户明确勾选了 WS 协议筛选时才扫描 WebSocket/SSE 等流式消息帧，避免大连接搜索卡顿
      if (protocols.contains(Protocol.ws) &&
          request.messages.isNotEmpty &&
          request.messages.any((m) => matches(m.payloadDataAsString))) {
        return true;
      }
    }
    if (option == Option.responseBody && response != null) {
      if (matches(response.bodyPreview)) {
        return true;
      }
      // 仅在用户明确勾选了 WS 协议筛选时才扫描 WebSocket/SSE 等流式消息帧，避免大连接搜索卡顿
      if (protocols.contains(Protocol.ws) &&
          response.messages.isNotEmpty &&
          response.messages.any((m) => matches(m.payloadDataAsString))) {
        return true;
      }
    }

    if (option == Option.requestHeader || option == Option.responseHeader) {
      var entries = option == Option.requestHeader
          ? request.headers.entries
          : response?.headers.entries ?? [];

      for (var entry in entries) {
        if (matches(entry.key) || entry.value.any(matches)) {
          return true;
        }
      }
    }
    return false;
  }
}

enum Option {
  url,
  method,
  responseContentType,
  requestHeader,
  requestBody,
  responseHeader,
  responseBody,
}

/// 协议快速筛选
enum Protocol { http, https, ws, sse, http1, h2 }

/// 排序字段 (#843)
enum SortBy { original, time, duration, statusCode, relevance }

/// 排序方向 (#843)
enum SortOrder { asc, desc }
