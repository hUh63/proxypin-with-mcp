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

import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/url_pattern.dart';
import 'package:proxypin/utils/lang.dart';

///重写规则
///@author: wanghongen
enum RuleType {
  // body("重写消息体"), //OLD VERSION

  requestReplace,
  responseReplace,
  requestUpdate,
  responseUpdate,
  redirect;

  String label(AppLocalizations loc) => switch (this) {
        RuleType.requestReplace => loc.rewriteRuleTypeRequestReplace,
        RuleType.responseReplace => loc.rewriteRuleTypeResponseReplace,
        RuleType.requestUpdate => loc.rewriteRuleTypeRequestUpdate,
        RuleType.responseUpdate => loc.rewriteRuleTypeResponseUpdate,
        RuleType.redirect => loc.rewriteRuleTypeRedirect,
      };

  static RuleType fromName(String name) {
    return values.firstWhere((element) => element.name == name);
  }
}

class RequestRewriteRule {
  bool enabled;
  RuleType type;

  String? name;
  String url;
  RegExp _urlReg;
  String? rewritePath;

  /// Mock 场景名：同一场景下的规则可一键批量启停；null / 空 表示未归类
  String? scenario;

  // 可选的 HTTP 方法匹配；null 表示匹配任意方法
  HttpMethod? method;

  RequestRewriteRule(
      {this.enabled = true,
      this.name,
      required this.url,
      required this.type,
      this.rewritePath,
      this.scenario,
      this.method})
      : _urlReg = UrlPattern.toRegExp(url);

  bool match(String url, {RuleType? type, HttpMethod? method}) {
    if (!enabled) return false;
    if (type != null && this.type != type) return false;

    // 如果调用方提供了 method，则当规则定义了 method 时进行比较；如果调用方未提供 method，则不按方法过滤（向后兼容）
    if (method != null && this.method != null && this.method != method) return false;

    return _urlReg.hasMatch(url);
  }

  bool matchUrl(String url, RuleType type) {
    return this.type == type && _urlReg.hasMatch(url);
  }

  /// 从json中创建
  factory RequestRewriteRule.formJson(Map<dynamic, dynamic> map) {
    HttpMethod? method;
    try {
      if (map['method'] != null) {
        method = HttpMethod.valueOf(map['method'].toString());
      }
    } catch (e) {
      // ignore invalid method
    }

    return RequestRewriteRule(
        enabled: map['enabled'] == true,
        name: map['name'],
        url: map['url'] ?? map['domain'] + map['path'],
        type: RuleType.fromName(map['type']),
        rewritePath: map['rewritePath'],
        scenario: map['scenario'],
        method: method);
  }

  void updatePathReg() {
    _urlReg = UrlPattern.toRegExp(url);
  }

  Map<String, dynamic> toJson() {
    var json = {
      'name': name,
      'enabled': enabled,
      'url': url,
      'type': type.name,
      'rewritePath': rewritePath,
      'scenario': scenario,
    };

    if (method != null) {
      json['method'] = method!.name;
    }

    return json;
  }
}

enum ReplaceBodyType {
  text,
  file;

  String label(AppLocalizations loc) => switch (this) {
        ReplaceBodyType.text => loc.rewriteBodyTypeText,
        ReplaceBodyType.file => loc.rewriteBodyTypeFile,
      };
}

class RewriteItem {
  bool enabled;
  RewriteType type;

  //key redirectUrl, method, path, queryParam, headers, body, statusCode
  final Map<String, dynamic> values = {};

  RewriteItem(this.type, this.enabled, {Map<dynamic, dynamic>? values}) {
    if (values != null) {
      this.values.addAll(Map.from(values));
    }
  }

  factory RewriteItem.fromJson(Map<dynamic, dynamic> map) {
    return RewriteItem(RewriteType.fromName(map['type']), map['enabled'], values: map['values']);
  }

  static List<RewriteItem> fromRequest(HttpRequest request) {
    List<RewriteItem> items = [];
    items.add(RewriteItem(RewriteType.replaceRequestLine, false)..path = request.requestUri?.path);
    items.add(RewriteItem(RewriteType.replaceRequestHeader, false)..headers = request.headers.toMap());
    items.add(RewriteItem(RewriteType.replaceRequestBody, true)..body = request.getBodyString());

    return items;
  }

  static List<RewriteItem> fromResponse(HttpResponse response) {
    List<RewriteItem> items = [];
    items.add(RewriteItem(RewriteType.replaceResponseStatus, false)..statusCode = response.status.code);
    items.add(RewriteItem(RewriteType.replaceResponseHeader, false)..headers = response.headers.toMap());
    items.add(RewriteItem(RewriteType.replaceResponseBody, true)..body = response.getBodyString());

    return items;
  }

  //key
  String? get key => values['key'];

  set key(String? key) => values['key'] = key;

  bool get useRegex => values['useRegex'] != false;

  set useRegex(bool useRegex) => values['useRegex'] = useRegex;

  String? get value => values['value'];

  set value(String? value) => values['value'] = value;

  //redirectUrl
  String? get redirectUrl => values['redirectUrl'];

  set redirectUrl(String? redirectUrl) => values['redirectUrl'] = redirectUrl;

  //method
  HttpMethod? get method => values['method'] == null
      ? null
      : HttpMethod.values.firstWhereOrNull((element) => element.name == values['method']);

  set method(HttpMethod? method) => values['method'] = method?.name;

  String? get path => values['path'];

  set path(String? path) => values['path'] = path;

  //queryParam
  String? get queryParam => values['queryParam'];

  set queryParam(String? queryParam) => values['queryParam'] = queryParam;

  //statusCode
  int? get statusCode => values['statusCode'];

  set statusCode(int? statusCode) => values['statusCode'] = statusCode;

  //headers
  Map<String, dynamic>? get headers => values['headers'] == null ? null : Map.from(values['headers']);

  set headers(Map<String, dynamic>? headers) => values['headers'] = headers;

  //body
  String? get body => values['body'];

  set body(String? body) => values['body'] = body;

  String? get bodyType => values['bodyType'];

  set bodyType(String? bodyType) => values['bodyType'] = bodyType;

  String? get bodyFile => values['bodyFile'];

  set bodyFile(String? bodyFile) => values['bodyFile'] = bodyFile;

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'type': type.name,
      'values': values,
    };
  }

  @override
  String toString() {
    return toJson().toString();
  }
}

enum RewriteType {
  //重定向
  redirect,

  //替换请求
  replaceRequestLine,
  replaceRequestHeader,
  replaceRequestBody,
  replaceResponseStatus,
  replaceResponseHeader,
  replaceResponseBody,

  //修改请求
  updateBody,
  addQueryParam,
  removeQueryParam,
  updateQueryParam,
  addHeader,
  removeHeader,
  updateHeader,
  ;

  static List<RewriteType> updateRequest = [
    updateBody,
    addQueryParam,
    updateQueryParam,
    removeQueryParam,
    addHeader,
    updateHeader,
    removeHeader
  ];

  static List<RewriteType> updateResponse = [updateBody, addHeader, updateHeader, removeHeader];

  String label(AppLocalizations loc) => switch (this) {
        RewriteType.redirect => loc.redirect,
        RewriteType.replaceRequestLine => loc.requestLine,
        RewriteType.replaceRequestHeader => loc.requestHeader,
        RewriteType.replaceRequestBody => loc.requestBody,
        RewriteType.replaceResponseStatus => loc.statusCode,
        RewriteType.replaceResponseHeader => loc.responseHeader,
        RewriteType.replaceResponseBody => loc.responseBody,
        RewriteType.updateBody => loc.rewriteTypeUpdateBody,
        RewriteType.addQueryParam => loc.rewriteTypeAddQueryParam,
        RewriteType.removeQueryParam => loc.rewriteTypeRemoveQueryParam,
        RewriteType.updateQueryParam => loc.rewriteTypeUpdateQueryParam,
        RewriteType.addHeader => loc.rewriteTypeAddHeader,
        RewriteType.removeHeader => loc.rewriteTypeRemoveHeader,
        RewriteType.updateHeader => loc.rewriteTypeUpdateHeader,
      };

  static RewriteType fromName(String name) {
    return values.firstWhere((element) => element.name == name);
  }

  String getDescribe(AppLocalizations loc) => label(loc);
}
