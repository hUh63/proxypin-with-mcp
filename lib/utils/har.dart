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
import 'dart:typed_data';

import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/content_type.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/process_info.dart';
import 'package:proxypin/ui/configuration.dart';

class Har {
  static int maxBodyLength = 1024 * 1024 * 4;

  /// 请求/响应体大小（上游 #773）：body 被「抓包内容上限」裁剪后，
  /// `body.length` 已不是原始大小，优先取 `originalBodyLength`。
  static int _bodySize(List<int>? body, int? originalLength) => originalLength ?? body?.length ?? -1;

  static List<Map> _entries(List<HttpRequest> list) {
    return list.map((e) => toHar(e)).toList();
  }

  static Map toHar(HttpRequest request) {
    Map har = {
      "startedDateTime": request.requestTime.toUtc().toIso8601String(), // 请求发出的时间(ISO 8601)
      "time": request.response?.responseTime.difference(request.requestTime).inMilliseconds ?? -1, // 请求耗时，单位毫秒
      "pageref": "ProxyPin", // 页面标识
      "_id": request.requestId, // 页面标识
      '_app': request.processInfo?.toJson(),
      "request": {
        "method": request.methodLabel, // 请求方法
        "url": request.requestUrl, // 请求地址
        "httpVersion": request.protocolVersion, // HTTP协议版本
        "cookies": [], // 请求携带的cookie
        "headers": _headers(request), // 请求头
        "queryString": _getQueryString(request), // 请求参数
        "postData": _getPostData(request), // 请求体
        "headersSize": -1, // 请求头大小
        "bodySize": _bodySize(request.body, request.originalBodyLength), // 请求体大小
      },
      "cache": {},
      'timings': {
        'send': 0,
        'wait': request.response?.responseTime.difference(request.requestTime).inMilliseconds ?? -1,
        'receive': 0,
      },
      'serverIPAddress': request.response?.remoteHost ?? '', // 服务器IP地址
    };

    har['response'] = {
      // 没有响应不是 HTTP/1.1 回退；保留空协议和可明确判断的缺失状态。
      '_responseAvailable': request.response != null,
      '_originalContentEncoding': request.response?.headers.get(HttpHeaders.CONTENT_ENCODING),
      "status": request.response?.status.code ?? 0, // 响应状态码
      "statusText": request.response?.status.reasonPhrase ?? '', // 响应状态码描述
      "httpVersion": request.response?.protocolVersion ?? '', // HTTP协议版本，未知不猜测
      "cookies": [], // 响应携带的cookie
      "headers": _headers(request.response), // 响应头
      "content": {
        "size": _bodySize(request.response?.body, request.response?.originalBodyLength), // 响应体大小
        "mimeType": _getContentType(request.response?.headers.contentType), // 响应体类型
        "text": _getResponseText(request.response),
        // HAR 规范：text 是 base64 时必须显式声明 encoding（请求侧的 postData 一直
        // 有，响应侧漏了）。少了它，Chrome DevTools / Charles 会把二进制响应当文本，
        // 图片/字体全成乱码。
        if (request.response?.contentType.isBinary == true) "encoding": "base64",
      },
      "redirectURL": '', // 重定向地址
      "headersSize": -1, // 响应头大小
      "bodySize": _bodySize(request.response?.body, request.response?.originalBodyLength), // 响应体大小
    };

    // WebSocket / SSE 会话：HAR 规范没有这部分，但 Chrome DevTools 的
    // `_webSocketMessages` 已是事实标准（DevTools / Charles / 各类 HAR 工具都认）。
    // 二进制帧（opcode=2，例如 protobuf）的 data 按 base64 给，配合 opcode 足以还原。
    // 单帧超大时截断：一个几十 MB 的帧会把 HAR 撑到没法打开。
    if (request.messages.isNotEmpty) {
      const maxFrame = 1024 * 1024;
      har['_webSocketMessages'] = request.messages.map((frame) {
        final payload = frame.payloadData;
        final clipped = payload.length > maxFrame;
        final data = clipped ? payload.sublist(0, maxFrame) : payload;
        return {
          'type': frame.isFromClient ? 'send' : 'receive',
          // DevTools 的 time 是「秒」浮点
          'time': frame.time.millisecondsSinceEpoch / 1000.0,
          'opcode': frame.opcode,
          'data': frame.isText ? utf8.decode(data, allowMalformed: true) : base64Encode(data),
          if (clipped) '_truncated': true,
        };
      }).toList();
    }
    return har;
  }

  static Map toHarRequest(HttpRequest request) {
    return {
      "startedDateTime": request.requestTime.toUtc().toIso8601String(),
      "time": -1,
      "pageref": "ProxyPin",
      "_id": request.requestId,
      "_phase": "request",
      '_app': request.processInfo?.toJson(),
      "request": {
        "method": request.methodLabel,
        "url": request.requestUrl,
        "httpVersion": request.protocolVersion,
        "cookies": [],
        "headers": _headers(request),
        "queryString": _getQueryString(request),
        "postData": _getPostData(request),
        "headersSize": -1,
        "bodySize": _bodySize(request.body, request.originalBodyLength),
      },
      "response": null,
      "cache": {},
      'timings': {'send': 0, 'wait': -1, 'receive': 0},
      'serverIPAddress': '',
    };
  }

  static Map toHarResponse(HttpRequest request) {
    return {
      "startedDateTime": request.requestTime.toUtc().toIso8601String(),
      "time": request.response?.responseTime.difference(request.requestTime).inMilliseconds ?? -1,
      "pageref": "ProxyPin",
      "_id": request.requestId,
      "_phase": "response",
      '_app': request.processInfo?.toJson(),
      "request": {
        "method": request.methodLabel,
        "url": request.requestUrl,
      },
      "response": {
        '_responseAvailable': request.response != null,
        '_originalContentEncoding': request.response?.headers.get(HttpHeaders.CONTENT_ENCODING),
        "status": request.response?.status.code ?? 0,
        "statusText": request.response?.status.reasonPhrase ?? '',
        "httpVersion": request.response?.protocolVersion ?? '',
        "cookies": [],
        "headers": _headers(request.response),
        "content": {
          "size": _bodySize(request.response?.body, request.response?.originalBodyLength),
          "mimeType": _getContentType(request.response?.headers.contentType),
          "text": _getResponseText(request.response),
          if (request.response?.contentType.isBinary == true) "encoding": "base64",
        },
        "redirectURL": '',
        "headersSize": -1,
        "bodySize": _bodySize(request.response?.body, request.response?.originalBodyLength),
      },
      "cache": {},
      'timings': {
        'send': 0,
        'wait': request.response?.responseTime.difference(request.requestTime).inMilliseconds ?? -1,
        'receive': 0,
      },
      'serverIPAddress': request.response?.remoteHost ?? '',
    };
  }

  static Future<String> writeJson(List<HttpRequest> list, {String title = ''}) async {
    var entries = _entries(list);
    Map har = {};
    title = title.contains("ProxyPin") ? title : "[ProxyPin]$title";
    har["log"] = {
      "version": "1.2",
      "creator": {"name": "ProxyPin", "version": AppConfiguration.version},
      "pages": [
        {
          "title": title,
          "id": "ProxyPin",
          "startedDateTime": list.firstOrNull?.requestTime.toUtc().toIso8601String(),
          "pageTimings": {"onContentLoad": -1, "onLoad": -1}
        }
      ],
      "entries": entries,
    };
    return jsonEncode(har);
  }

  /// 流式写入 HAR 文件：逐条序列化 entry 并追加到 StringBuffer，
  /// 避免大列表时「entries 全量 Map + 完整 JSON 字符串」双份驻留内存（OOM 风险）。
  static Future<File> writeFile(List<HttpRequest> list, File file, {String title = ''}) async {
    title = title.contains("ProxyPin") ? title : "[ProxyPin]$title";
    final buf = StringBuffer();
    buf.write('{"log":{"version":"1.2",');
    buf.write('"creator":{"name":"ProxyPin","version":${jsonEncode(AppConfiguration.version)}},');
    buf.write('"pages":[{"title":${jsonEncode(title)},"id":"ProxyPin",');
    buf.write('"startedDateTime":${jsonEncode(list.firstOrNull?.requestTime.toUtc().toIso8601String())},');
    buf.write('"pageTimings":{"onContentLoad":-1,"onLoad":-1}}],');
    buf.write('"entries":[');
    for (var i = 0; i < list.length; i++) {
      if (i > 0) buf.write(',');
      buf.write(jsonEncode(toHar(list[i])));
    }
    buf.write(']}}');
    return file.writeAsString(buf.toString());
  }

  //读取文件
  static Future<List<HttpRequest>> readFile(File file) async {
    final text = await file.readAsString();
    final trimmed = text.trim();
    if (trimmed.isEmpty) return [];

    // 历史文件是「每行一个 entry」的追加写格式；而本仓库 writeFile 以及
    // Chrome / Charles / Fiddler 等导出的标准 HAR 是「单个 JSON 对象」。
    // 旧实现只认前一种：收藏页「导出 HAR → 再导入」时 readAsLines 只得到一行，
    // jsonDecode 得到 {log:...}，取 har['request'] 为 null 后直接抛
    // NoSuchMethodError —— 该功能等于完全不可用，第三方 HAR 同样必失败。
    if (trimmed.startsWith('{')) {
      try {
        final root = jsonDecode(trimmed);
        final log = root is Map ? root['log'] : null;
        final entries = log is Map ? log['entries'] : null;
        if (entries is List) return readEntries(entries);
      } catch (_) {
        // 不是合法整 JSON（可能被截断），继续按逐行格式解析
      }
    }

    final list = <HttpRequest>[];
    var skipped = 0;
    for (final value in text.split(RegExp(r'\r?\n'))) {
      var line = value.trim();
      if (line.isEmpty) continue;
      if (line.endsWith(',')) line = line.substring(0, line.length - 1);
      try {
        list.add(toRequest(jsonDecode(line)));
      } catch (_) {
        // 进程被强杀 / 磁盘写满时最后一条 entry 可能只写了一半。
        // 旧实现一抛就终止，导致整份历史都打不开；现在跳过坏行继续。
        skipped++;
      }
    }
    if (skipped > 0) logger.w('HAR 读取跳过 $skipped 条损坏记录');
    return list;
  }

  /// 把 HAR 的 entries 数组转成请求列表（逐条容错，坏 entry 不拖垮整份文件）
  static List<HttpRequest> readEntries(List entries) {
    final list = <HttpRequest>[];
    var skipped = 0;
    for (final entry in entries) {
      if (entry is! Map) {
        skipped++;
        continue;
      }
      try {
        list.add(toRequest(entry));
      } catch (_) {
        skipped++;
      }
    }
    if (skipped > 0) logger.w('HAR 读取跳过 $skipped 条无效记录');
    return list;
  }

  static List<Map> _headers(HttpMessage? message) {
    var headers = <Map<String, String>>[];
    var contentEncodingName = message?.headers.getOriginalName(HttpHeaders.CONTENT_ENCODING);

    // 文本 body 导出的是 bodyAsString（**已解码**）。头里还留着 Content-Encoding
    // 的话，导入方（包括我们自己）会再解压一次：gzip 响应「导出→导入」后正文
    // 直接变乱码。二进制 body 导出的是原始字节（base64），保留头才是对的。
    // 旧实现只跳过了 br，gzip/deflate 全留着。
    final textBody = message?.contentType.isBinary != true;

    message?.headers.forEach((name, values) {
      for (var element in values) {
        if (textBody && contentEncodingName != null && name == contentEncodingName) {
          continue;
        }
        headers.add({'name': name, 'value': element});
      }
    });
    return headers;
  }

  /// HAR 的 text 字段转回原始字节。
  ///
  /// 历史包袱：旧版 ProxyPin 用 `String.fromCharCodes(原始字节)` 写出，每个字节
  /// 变成一个 ≤0xFF 的码点；新版与第三方 HAR 写的则是真正的 Unicode 文本。
  /// 直接 codeUnits 会让新版的中文体变成「UTF-16 码元」而非 UTF-8 字节，
  /// 直接 utf8.encode 又会让旧数据二次编码。用「是否出现 >0xFF 的码点」区分。
  static List<int> _bodyFromText(String text) {
    for (final unit in text.codeUnits) {
      if (unit > 0xFF) return utf8.encode(text);
    }
    return text.codeUnits;
  }

  /// har to request
  static HttpRequest toRequest(Map har) {
    final request = har['request'];
    // 第三方 HAR 里 request / headers 都可能缺失或类型不对，裸强转会抛
    // TypeError，被 UI 统一显示成「导入失败: type ... is not a subtype」。
    if (request is! Map) {
      throw const FormatException('invalid HAR entry: missing request');
    }
    final method = request['method']?.toString() ?? 'GET';
    final headers = request['headers'] is List ? request['headers'] as List : const [];

    final url = request['url']?.toString();
    if (url == null || url.trim().isEmpty) {
      throw const FormatException('invalid HAR entry: missing request.url');
    }
    // 第三方 HAR 里 httpVersion 常缺失：HttpRequest 的 protocolVersion 是非空 String，
    // 直接透传 dynamic null 会抛 TypeError，整条 entry 被丢掉。
    final protocol = request['httpVersion']?.toString() ?? 'HTTP/1.1';

    final parsedMethod = HttpMethod.valueOf(method);
    final httpRequest = HttpRequest(parsedMethod, url,
        protocolVersion: protocol,
        rawMethod: parsedMethod == HttpMethod.unknown ? method : null);
    if (har.containsKey("_id")) httpRequest.requestId = har['_id'].toString(); // 页面标识
    final appInfo = har['_app'];
    httpRequest.processInfo =
        appInfo is Map ? ProcessInfo.fromJson(Map<String, dynamic>.from(appInfo)) : null;

    // HAR 1.2 用 postData.encoding == 'base64' 标明 text 是 base64；
    // 忽略它会把 base64 文本当正文（体积膨胀 33%，重放/另存全错）。
    final postData = request['postData'];
    if (postData is Map) {
      final text = postData['text']?.toString();
      if (text != null) {
        if (postData['encoding'] == 'base64') {
          try {
            httpRequest.body = base64Decode(text);
          } catch (_) {
            httpRequest.body = _bodyFromText(text);
          }
        } else {
          httpRequest.body = _bodyFromText(text);
        }
      }
    }
    for (final element in headers) {
      if (element is! Map) continue;
      final name = element['name']?.toString();
      if (name == null) continue;
      final value = element['value'];
      httpRequest.headers.add(name, value is List ? value.join(',') : value?.toString() ?? '');
    }
    final response = har['response'];
    HttpResponse? httpResponse;
    // status 在第三方 HAR 里可能是字符串 "200"，statusText 可能是数字；
    // 一律先解析成 int/String 再构造，避免 TypeError 丢整条记录。
    final rawStatus = response is Map ? response['status'] : null;
    final statusCode = rawStatus is num ? rawStatus.toInt() : int.tryParse('$rawStatus'.trim());
    if (response is Map && statusCode != null) {
      final rawStatusText = response['statusText'];
      httpResponse = HttpResponse(
          HttpStatus.newStatus(statusCode, rawStatusText == null ? null : '$rawStatusText'),
          protocolVersion: response['httpVersion']?.toString() ?? 'HTTP/1.1');
      final responseHeaders = response['headers'] is List ? response['headers'] as List : const [];
      for (final element in responseHeaders) {
        if (element is! Map) continue;
        final name = element['name']?.toString();
        if (name == null) continue;
        final value = element['value'];
        httpResponse.headers.add(name, value is List ? value.join(',') : value?.toString() ?? '');
      }

      final content = response['content'];
      final responseText = content is Map ? content['text'] : null;
      if (responseText != null) {
        final isBase64 = content is Map && content['encoding'] == 'base64';
        if (isBase64 || httpResponse.contentType.isBinary) {
          try {
            httpResponse.body = base64Decode(responseText.toString());
          } catch (e) {
            httpResponse.body = _bodyFromText(responseText.toString());
          }
        } else {
          httpResponse.body = _bodyFromText(responseText.toString());
        }
      }
    }

    httpRequest.response = httpResponse;
    httpResponse?.request = httpRequest;
    httpRequest.hostAndPort = HostAndPort.of(httpRequest.requestUrl);
    httpResponse?.remoteHost = har['serverIPAddress']; // 服务器IP地址

    //请求时间
    final startedAt = har['startedDateTime'] == null ? null : DateTime.tryParse('${har['startedDateTime']}');
    if (startedAt != null) {
      httpRequest.requestTime = startedAt.toLocal();
    }
    if (har['time'] != null) {
      // 第三方 HAR 里 time 可能是 -1（未完成/未知）或非数字：直接换算会得到
      // 「响应早于请求」的负耗时，列表里显示 -1ms。只接受 >= 0 的耗时。
      final timeMs = double.tryParse(har['time'].toString())?.toInt();
      if (timeMs != null && timeMs >= 0) {
        httpRequest.response?.responseTime =
            httpRequest.requestTime.add(Duration(milliseconds: timeMs));
      }
    }
    return httpRequest;
  }

  static List<Map<String, String>> _getQueryString(HttpRequest request) {
    final queryStringList = <Map<String, String>>[];
    final queries = request.requestUri?.queryParametersAll;
    queries?.forEach((key, valueList) {
      for (var value in valueList) {
        queryStringList.add({"name": key, "value": value});
      }
    });
    return queryStringList;
  }

  static Map<String, dynamic> _getPostData(HttpRequest request) {
    final mimeType = request.headers.contentType; // 请求体类型
    if (request.body == null) return {"mimeType": mimeType};

    // 请求体是原始字节。旧实现用 String.fromCharCodes 把每个字节当码点，
    // 含中文的 UTF-8 体会变成 mojibake（同一份 HAR 里响应侧却用的是正确解码的
    // bodyAsString），外部工具打开/回放全是乱码。
    if (request.contentType.isBinary) {
      return {
        "mimeType": mimeType,
        "text": base64Encode(request.body!),
        "encoding": "base64",
      };
    }
    final map = <String, dynamic>{"mimeType": mimeType, "text": request.bodyAsString};
    if (request.contentType == ContentType.formData || request.contentType == ContentType.formUrl) {
      map["params"] = []; // 请求体参数
    }
    return map;
  }

  static String _getResponseText(HttpResponse? response) {
    final responseBody = response?.body;
    if (responseBody == null) {
      return '';
    }
    if (response?.contentType.isBinary == true) {
      return base64Encode(responseBody);
    }

    return response?.bodyAsString ?? '';
  }

  //获取contentType
  static String? _getContentType(String? type) {
    if (type == null) {
      return '';
    }
    var indexOf = type.indexOf("charset=");
    if (indexOf == -1) {
      return type;
    }
    var contentType = type.substring(0, indexOf).trimRight();
    if (contentType.endsWith(";")) {
      return contentType.substring(0, contentType.length - 1);
    }
    return contentType;
  }
}
