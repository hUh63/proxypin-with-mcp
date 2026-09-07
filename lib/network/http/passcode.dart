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

/// 请求口令（上游 #920）：把选中请求压缩为一段可粘贴分享的口令文本，
/// 对方从剪贴板导入即可还原请求（含响应）到抓包列表。
///
/// 编码：`PROXYPIN1:` + base64Url(gzip(json))，导出时剥离 `_id` 以避免导入后
/// 与现有请求 ID 冲突。格式升级时递增前缀版本号。
import 'dart:convert';
import 'dart:io';

import 'package:proxypin/network/http/http.dart';

const String passcodePrefix = 'PROXYPIN1:';

String encodeRequestPasscode(List<HttpRequest> requests) {
  final list = requests.map((e) {
    final requestJson = e.toJson()..remove('_id');
    return {
      'request': requestJson,
      if (e.response != null) 'response': e.response!.toJson(),
    };
  }).toList();
  return passcodePrefix + base64Url.encode(gzip.encode(utf8.encode(jsonEncode(list))));
}

List<HttpRequest> decodeRequestPasscode(String text) {
  final t = text.trim();
  if (!t.startsWith(passcodePrefix)) {
    throw const FormatException('不是有效的 ProxyPin 口令');
  }
  final data = utf8.decode(gzip.decode(base64Url.decode(t.substring(passcodePrefix.length).trim())));
  final list = jsonDecode(data) as List;
  return list.map((e) {
    final map = Map<String, dynamic>.from(e);
    final request = HttpRequest.fromJson(Map<String, dynamic>.from(map['request']));
    if (map['response'] is Map) {
      request.response = HttpResponse.fromJson(Map<String, dynamic>.from(map['response']));
    }
    return request;
  }).toList();
}
