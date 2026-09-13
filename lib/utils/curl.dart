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

import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/http_headers.dart';
import 'package:proxypin/utils/lang.dart';
import 'dart:convert';

/// 复制为 fetch 请求
String copyAsFetch(HttpRequest request) {
  final headers = request.headers.entries.where((entry) => entry.key.toLowerCase() != 'content-length').toList();

  final sb = StringBuffer();
  sb.writeln('fetch(${jsonEncode(request.requestUrl)}, {');
  sb.writeln('  method: ${jsonEncode(request.method.name.toUpperCase())},');

  if (headers.isNotEmpty) {
    sb.writeln('  headers: {');
    for (final entry in headers) {
      sb.writeln('    ${jsonEncode(entry.key)}: ${jsonEncode(entry.value)},');
    }
    sb.writeln('  },');
  }

  if (request.bodyAsString.isNotEmpty) {
    sb.writeln('  body: ${jsonEncode(request.bodyAsString)},');
  }

  sb.writeln('});');
  return sb.toString();
}

///复制cURL请求
String curlRequest(HttpRequest request) {
  String contentType = request.headers.contentType;
  bool isMultipart = contentType.toLowerCase().contains('multipart/form-data');

  // 先尝试构造 multipart -F 列表；成功才丢弃 Content-Type，让 curl 自动生成。
  // 失败（body 为空/无法解析）时保留原 Content-Type，避免生成损坏的 curl。
  String? multipartBody = isMultipart ? _buildMultipartFormData(request) : null;
  bool dropContentType = multipartBody != null;

  List<String> headers = [];
  request.headers.forEach((key, values) {
    String lowerKey = key.toLowerCase();
    // 跳过 content-length（curl 会自动计算）
    if (lowerKey == 'content-length') return;
    // multipart 成功转成 -F 时才跳过 content-type
    if (dropContentType && lowerKey == 'content-type') return;
    // 跳过 accept-encoding 中的 br（curl 不支持 brotli）
    if (lowerKey == 'accept-encoding') {
      for (var val in values) {
        String filtered =
            val.split(',').map((e) => e.trim()).where((e) => !e.toLowerCase().startsWith('br')).join(', ');
        if (filtered.isNotEmpty) {
          headers.add("  -H '$key: $filtered' ");
        }
      }
      return;
    }

    for (var val in values) {
      headers.add("  -H '$key: $val' ");
    }
  });

  String body = '';
  if (multipartBody != null) {
    body = multipartBody;
  } else if (isMultipart) {
    // multipart 但 body 缺失（如大文件流式未缓存）：给个占位符提示
    body = "  --data-binary '@<PATH_TO_FILE>' \\\n";
  } else if (request.bodyAsString.isNotEmpty) {
    body = "  --data '${request.bodyAsString}' \\\n";
  }

  return "curl -X ${request.method.name} '${request.requestUrl}' \\\n"
      "${headers.join('\\\n')} \\\n $body  --compressed";
}

/// 解析 multipart body 为 curl 的 -F 参数列表；解析失败返回 null。
String? _buildMultipartFormData(HttpRequest request) {
  String? boundary = _extractBoundary(request.headers.contentType);
  String bodyStr = request.bodyAsString;
  if (boundary == null || bodyStr.isEmpty) return null;

  final headerBodySplit = RegExp(r'\r?\n\r?\n');
  // 只去掉两侧换行，保留 header/body 之间的空行
  final trimNewlines = RegExp(r'^(\r?\n)+|(\r?\n)+$');
  final List<String> formFields = [];

  for (String part in bodyStr.split('--$boundary')) {
    part = part.replaceAll(trimNewlines, '');
    if (part.isEmpty || part == '--') continue;

    final sections = part.split(headerBodySplit);
    if (sections.length < 2) {
      // 没有 body 的 part（如空文件字段）：仍尝试从纯 header 里解析出 filename/name
      final name = _extractDispositionParam(part, 'name');
      final filename = _extractDispositionParam(part, 'filename');
      if (name != null && filename != null) {
        formFields.add('  -F "${_fixMojibake(name)}=@${_fixMojibake(filename)}" ');
      }
      continue;
    }

    final headerSection = sections[0];
    // rejoin 剩余段以防 body 里也有空行；再去掉结尾的 \r\n
    final valueSection = sections.sublist(1).join('\r\n\r\n').replaceAll(RegExp(r'\r?\n$'), '');

    final name = _extractDispositionParam(headerSection, 'name');
    if (name == null) continue;

    final filename = _extractDispositionParam(headerSection, 'filename');
    if (filename != null) {
      formFields.add('  -F "${_fixMojibake(name)}=@${_fixMojibake(filename)}" ');
    } else {
      final escaped = _fixMojibake(valueSection).replaceAll("'", "'\\''");
      formFields.add("  -F '${_fixMojibake(name)}=$escaped' ");
    }
  }

  if (formFields.isEmpty) return null;
  return "${formFields.join('\\\n')} \\\n";
}

/// bodyAsString 在 utf8.decode 失败时会走 String.fromCharCodes 逐字节转 char，
/// 若原始字节是 UTF-8 会得到 Latin-1 乱码。这里把 code units 当字节再 UTF-8 解一次。
String _fixMojibake(String s) {
  bool needsFix = false;
  for (int i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c > 0xFF) return s; // 已是正常 Unicode，无需修复
    if (c >= 0x80) needsFix = true;
  }
  if (!needsFix) return s;
  try {
    return utf8.decode(s.codeUnits);
  } catch (_) {
    return s;
  }
}

String? _extractBoundary(String contentType) {
  // multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW
  // 也兼容带引号: boundary="xxx"
  RegExp regExp = RegExp(r'boundary=(?:"([^"]+)"|([^\s;]+))', caseSensitive: false);
  Match? match = regExp.firstMatch(contentType);
  return match?.group(1) ?? match?.group(2);
}

String? _extractDispositionParam(String header, String paramName) {
  // Content-Disposition: form-data; name="field1"; filename="test.pdf"
  // 加前导边界(行首/空白/分号)，避免 name 匹配到 filename 的子串
  RegExp regExp = RegExp('(?:^|[;\\s])$paramName="([^"]*)"', caseSensitive: false);
  Match? match = regExp.firstMatch(header);
  if (match != null) return match.group(1);

  // 也处理无引号的情况: name=field1
  regExp = RegExp('(?:^|[;\\s])$paramName=([^\\s;]+)', caseSensitive: false);
  match = regExp.firstMatch(header);
  return match?.group(1);
}

class Curl {
  static const String _h = "-H";
  static const String _header = "--header";
  static const String _x = "-X";
  static const String _request = "--request";
  static const String _data = "--data";
  static const String _dataRaw = "--data-raw";
  static const String _d = "-d";

  /// 需要忽略其取值的 cURL 参数（避免其取值被误判为请求 URL，参考 Reqable 的 cURL 导入）
  static const Set<String> _valueFlagsToSkip = {
    '-o', '--output', // 输出文件
    '-x', '--proxy', // 代理地址（取值可能含 http://）
    '--connect-timeout', '--max-time', '-m', '--retry', '--retry-delay',
    '--cacert', '--cert', '--key', '--capath',
    '-w', '--write-out', '--resolve', '--interface',
    '-A', '--user-agent', '-e', '--referer',
  };

  /// 预处理 cURL 文本（参考 Reqable）：
  /// 1) 丢弃整行注释（以 `#` 或 `//` 开头）；
  /// 2) 去除引号外的行尾注释（` #...` / ` //...`，`://` 不会被误判）；
  /// 3) 去除行尾续行符 `\`，并将换行 / Tab 归一为空格。
  static String _preprocessCurl(String raw) {
    final buf = StringBuffer();
    for (final rawLine in raw.split('\n')) {
      final trimmedLeft = rawLine.trimLeft();
      if (trimmedLeft.startsWith('#') || trimmedLeft.startsWith('//')) {
        continue; // 整行注释
      }
      var line = _stripTrailingComment(rawLine);
      line = line.replaceFirst(RegExp(r'\\\s*$'), ''); // 续行符
      buf.write(line);
      buf.write(' ');
    }
    return buf.toString().replaceAll(RegExp(r'[\t\r\n]'), ' ').trim();
  }

  /// 去除引号外的行尾注释：` #...` 或 ` //...`
  static String _stripTrailingComment(String line) {
    bool inQuotes = false;
    String quoteChar = '';
    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c == quoteChar) inQuotes = false;
        continue;
      }
      if (c == '"' || c == "'") {
        inQuotes = true;
        quoteChar = c;
        continue;
      }
      final prevIsSpace = i > 0 && (line[i - 1] == ' ' || line[i - 1] == '\t');
      if (c == '#' && prevIsSpace) {
        return line.substring(0, i);
      }
      if (c == '/' && i + 1 < line.length && line[i + 1] == '/' && prevIsSpace) {
        return line.substring(0, i);
      }
    }
    return line;
  }

  static HttpRequest parse(String curlCommand) {
    HttpMethod method = HttpMethod.get;
    HttpHeaders headers = HttpHeaders();

    String? url;
    String? data;

    // 预处理：剥离注释、合并续行符、归一空白（参考 Reqable 的 cURL 导入能力）
    String trimmedCommand = _preprocessCurl(curlCommand).replaceFirst('curl', '').trim();

    List<String> parts = [];
    String currentPart = '';
    bool inQuotes = false;
    bool inBody = false;

    // 处理可能包含引号的参数
    for (int i = 0; i < trimmedCommand.length; i++) {
      String char = trimmedCommand[i];
      if (char == '"' || char == "'") {
        if (inBody) {
          currentPart += char;
          continue;
        }

        // 如果当前字符是引号，切换 inQuotes 状态
        inQuotes = !inQuotes;
      } else if (char == ' ' && !inQuotes) {
        if (inBody && currentPart.length > 2) {
          // 如果当前部分是数据，去掉前后的引号
          currentPart = currentPart.substring(1, currentPart.length - 1);
        }

        if (currentPart == '-d' || currentPart == '--data' || currentPart == '--data-raw') {
          inBody = true;
        } else {
          inBody = false;
        }

        parts.add(currentPart);
        currentPart = '';
      } else {
        currentPart += char;
      }
    }

    if (currentPart.isNotEmpty) {
      if (inBody && currentPart.length > 2) {
        // 如果当前部分是数据，去掉前后的引号
        currentPart = currentPart.substring(1, currentPart.length - 1);
      }

      parts.add(currentPart);
    }

    String protocolVersion = "HTTP/1.1";

    // 遍历参数列表进行解析
    for (int i = 0; i < parts.length; i++) {
      String part = parts[i];
      if (part == _x || part == _request) {
        // 解析请求方法
        if (i + 1 < parts.length) {
          method = HttpMethod.valueOf(parts[++i]);
        }
      } else if (part == _h || part == _header) {
        // 解析请求头
        if (i + 1 < parts.length) {
          String headerStr = parts[++i];
          List<String> headerParts = headerStr.splitFirst(':'.codeUnits.first);
          if (headerParts.length == 2) {
            headers.add(headerParts[0], headerParts[1]);
          }
        }
      } else if (part == _d || part == _dataRaw || part == _data) {
        // 解析请求数据
        if (i + 1 < parts.length) {
          data = parts[++i];
        }
      } else if (url == null && !part.startsWith('-') && part.contains("http")) {
        // 解析请求 URL
        url = part.replaceAll("'", "").replaceAll('"', '');
      } else if (_valueFlagsToSkip.contains(part)) {
        // 忽略带取值的非目标参数（如 -o 输出文件、--proxy 代理地址），避免取值被误判为 URL
        if (i + 1 < parts.length) i++;
      } else if ("--http2" == part) {
        // protocolVersion = "HTTP2";
      }
    }

    if (data?.isNotEmpty == true && method == HttpMethod.get) {
      method = HttpMethod.post;
    }

    HttpRequest request = HttpRequest(method, url ?? '', protocolVersion: protocolVersion);
    request.headers.addAll(headers);
    request.body = data?.codeUnits;
    return request;
  }
}

//判断是否结束
int endIndex(String str) {
  for (int i = 0; i < str.length; i++) {
    if (str[i] == '\'') {
      if (i == 0 || str[i - 1] != '\\') {
        return i;
      }
    }
  }
  return -1;
}
