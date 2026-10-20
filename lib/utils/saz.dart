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
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart' as charset;
import 'package:brotli/brotli.dart';

/// 一条原始 HTTP 报文（请求或响应）的解析结果。
class _RawMessage {
  final String startLine;
  final List<List<String>> headers; // [[name, value], ...] 保留顺序
  final Uint8List body;
  final Map<String, String> _lower;

  _RawMessage(this.startLine, this.headers, this.body, this._lower);

  String? header(String lowerName) => _lower[lowerName];
}

/// Fiddler SAZ（Session Archive Zip）导入解析器。
///
/// SAZ 本质是一个 zip，里面 `raw/0001_c.txt` 是客户端请求、`raw/0001_s.txt` 是服务端响应
/// （Fiddler 已解密的明文 HTTP）。这里把每一对解析成**标准 HAR entry**（结构对齐
/// `Har.toHar`），再交给既有的 `Har.toRequest` 完成导入 —— 不重复实现 HAR→HttpRequest。
///
/// 纯 Dart（只依赖 archive 与 brotli），因此可单测。
class SazParser {
  static const int maxBody = 128 * 1024 * 1024;

  static final RegExp _rawName = RegExp(r'raw/(\d+)_([csm])\.(txt|xml)', caseSensitive: false);

  /// 解析 .saz 字节为 HAR entry 列表（可直接喂给 `Har.toRequest`）。
  static List<Map<String, dynamic>> parse(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final reqs = <int, Uint8List>{};
    final resps = <int, Uint8List>{};
    final metas = <int, String>{};

    for (final f in archive.files) {
      final m = _rawName.firstMatch(f.name.replaceAll('\\', '/'));
      if (m == null) continue;
      final id = int.tryParse(m.group(1)!);
      if (id == null) continue;
      final kind = m.group(2)!.toLowerCase();
      try {
        final content = f.content;
        if (kind == 'c') {
          reqs[id] = content;
        } else if (kind == 's') {
          resps[id] = content;
        } else {
          metas[id] = utf8.decode(content, allowMalformed: true);
        }
      } catch (_) {
        // 单条损坏不影响整体
      }
    }

    final ids = reqs.keys.toList()..sort();
    final entries = <Map<String, dynamic>>[];
    var seq = 0;
    for (final id in ids) {
      // 单条损坏（gzip 解压失败、chunked 畸形…）不应该让整个 .saz 导入失败：
      // _decodedBody 是会抛的，以前一抛整个 parse 就结束了。
      try {
        final entry = _buildEntry(id, seq, reqs[id]!, resps[id], metas[id]);
        if (entry != null) {
          entries.add(entry);
          seq++;
        }
      } catch (e) {
        io.stderr.writeln('SAZ entry #$id skipped: $e');
      }
    }
    return entries;
  }

  /// 构造单条 HAR entry；返回 null 表示该条应跳过（CONNECT 隧道、空起始行等）。
  static Map<String, dynamic>? _buildEntry(int id, int seq, Uint8List reqBytes, Uint8List? respBytes, String? meta) {
      final req = _parseMessage(reqBytes);
      if (req == null || req.startLine.isEmpty) return null;

      final parts = req.startLine.split(' ');
      final method = parts.isNotEmpty ? parts[0].toUpperCase() : '';
      if (method.isEmpty || method == 'CONNECT') return null; // 隧道握手不导出
      final rawTarget = parts.length > 1 ? parts[1] : '/';
      final version = parts.length > 2 ? parts[2] : 'HTTP/1.1';

      final hostHeader = req.header('host') ?? '';
      final scheme = _schemeFor(rawTarget, hostHeader, meta);
      final url = _buildUrl(rawTarget, hostHeader, scheme);

      final resp = respBytes == null ? null : _parseMessage(respBytes);

      return _entry(
        id: id,
        seq: seq,
        method: method,
        url: url,
        version: version,
        req: req,
        resp: resp,
        startedAt: _startedAtOf(meta),
      );
  }

  static Map<String, dynamic> _entry({
    required int id,
    required int seq,
    required String method,
    required String url,
    required String version,
    required _RawMessage req,
    required _RawMessage? resp,
    DateTime? startedAt,
  }) {
    final reqBody = _decodedBody(req);
    final reqCt = _contentType(req);

    final respBody = resp == null ? null : _decodedBody(resp);
    final respCt = resp == null ? '' : _contentType(resp);
    final respRawCt = resp == null ? '' : _rawContentType(resp);

    Map<String, dynamic>? respMap;
    if (resp != null) {
      final statusParts = resp.startLine.split(' ');
      final status = statusParts.length > 1 ? (int.tryParse(statusParts[1]) ?? 0) : 0;
      final reason = statusParts.length > 2 ? statusParts.sublist(2).join(' ') : '';
      final body = respBody ?? Uint8List(0);
      respMap = {
        'status': status,
        'statusText': reason,
        'httpVersion': statusParts.isNotEmpty ? statusParts[0] : 'HTTP/1.1',
        'headers': _headersOf(resp),
        'content': {
          'size': body.length,
          'mimeType': respCt,
          'text': _isBinary(respCt) ? base64Encode(body) : _decodeText(body, respRawCt),
        },
        'bodySize': body.length,
      };
    }

    return {
      // 有真实抓包时间就用它（Charles 的 _m.xml 里有）；没有则用「导入时刻 + 序号」
      // 保持顺序。以前一律用导入时刻，导入别人的会话后时间全是今天。
      'startedDateTime': (startedAt ?? DateTime.now().add(Duration(milliseconds: seq)))
          .toUtc()
          .toIso8601String(),
      // 以前写 -1：导入方（包括我们自己）会算出「响应比请求早 1ms」的负耗时。
      // SAZ 里没有可靠的耗时字段，写 0 表示同刻完成。
      'time': 0,
      '_id': 'saz-$id',
      'request': {
        'method': method,
        'url': url,
        'httpVersion': version,
        'headers': _headersOf(req),
        if (reqBody.isNotEmpty)
          'postData': {
            'mimeType': reqCt,
            // 与 Har._getPostData 保持一致：用 codeUnits 承载原始字节
            'text': String.fromCharCodes(reqBody),
          },
        'bodySize': reqBody.length,
      },
      'response': respMap,
    };
  }

  static List<Map<String, String>> _headersOf(_RawMessage m) =>
      m.headers.map((h) => {'name': h[0], 'value': h.length > 1 ? h[1] : ''}).toList(growable: false);

  /// 拆出起始行 + 头 + body；找不到分隔则整体当 body。
  static _RawMessage? _parseMessage(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final idx = _headerEnd(bytes);
    if (idx < 0) {
      final text = utf8.decode(bytes, allowMalformed: true);
      final firstLine = text.split(RegExp(r'\r?\n')).first;
      return _RawMessage(firstLine.trim(), const [], Uint8List(0), const {});
    }
    final headerBytes = bytes.sublist(0, idx);
    final bodyStart = (bytes[idx] == 0x0D ? idx + 4 : idx + 2);
    final body = bodyStart < bytes.length ? bytes.sublist(bodyStart) : Uint8List(0);
    final text = latin1.decode(headerBytes, allowInvalid: true);
    final lines = text.split(RegExp(r'\r?\n'));
    final startLine = lines.isNotEmpty ? lines.first.trim() : '';
    final headers = <List<String>>[];
    final lower = <String, String>{};
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final name = line.substring(0, colon).trim();
      final value = line.substring(colon + 1).trim();
      headers.add([name, value]);
      lower[name.toLowerCase()] = value;
    }
    return _RawMessage(startLine, headers, body, lower);
  }

  static int _headerEnd(Uint8List b) {
    for (var i = 0; i + 3 < b.length; i++) {
      if (b[i] == 0x0D && b[i + 1] == 0x0A && b[i + 2] == 0x0D && b[i + 3] == 0x0A) return i;
    }
    for (var i = 0; i + 1 < b.length; i++) {
      if (b[i] == 0x0A && b[i + 1] == 0x0A) return i;
    }
    return -1;
  }

  /// 解 transfer-encoding（chunked）后再解 content-encoding。
  static Uint8List _decodedBody(_RawMessage m) {
    var body = m.body;
    final te = m.header('transfer-encoding')?.toLowerCase() ?? '';
    if (te.contains('chunked')) {
      body = _dechunk(body);
    }
    final ce = m.header('content-encoding')?.toLowerCase() ?? '';
    body = _decodeContentEncoding(body, ce);
    if (body.length > maxBody) body = Uint8List.sublistView(body, 0, maxBody);
    return body;
  }

  static Uint8List _decodeContentEncoding(Uint8List body, String ce) {
    if (body.isEmpty) return body;
    try {
      if (ce.contains('gzip') || ce.contains('x-gzip')) {
        return Uint8List.fromList(io.GZipCodec().decode(body));
      }
      if (ce.contains('deflate')) {
        try {
          return Uint8List.fromList(io.ZLibCodec().decode(body));
        } catch (_) {
          return Uint8List.fromList(io.ZLibDecoder(raw: true).convert(body));
        }
      }
      if (ce.contains('br')) {
        return Uint8List.fromList(brotli.decode(body));
      }
    } catch (_) {
      // 解压失败就用原始字节
    }
    return body;
  }

  static Uint8List _dechunk(Uint8List data) {
    final out = BytesBuilder(copy: false);
    var i = 0;
    while (i < data.length) {
      // 读 chunk-size 行
      var lineEnd = -1;
      for (var j = i; j + 1 < data.length; j++) {
        if (data[j] == 0x0D && data[j + 1] == 0x0A) {
          lineEnd = j;
          break;
        }
        if (data[j] == 0x0A) {
          lineEnd = j;
          break;
        }
      }
      if (lineEnd < 0) break;
      final sizeLine = latin1.decode(data.sublist(i, lineEnd), allowInvalid: true).trim();
      final sizeHex = sizeLine.split(';').first.trim();
      final size = int.tryParse(sizeHex, radix: 16);
      if (size == null) break;
      final dataStart = (data[lineEnd] == 0x0D) ? lineEnd + 2 : lineEnd + 1;
      if (size == 0) break;
      final dataEnd = (dataStart + size <= data.length) ? dataStart + size : data.length;
      out.add(Uint8List.sublistView(data, dataStart, dataEnd));
      // 跳过 chunk 结尾的 CRLF
      i = dataEnd;
      if (i < data.length && data[i] == 0x0D) i++;
      if (i < data.length && data[i] == 0x0A) i++;
    }
    return out.toBytes();
  }

  static String _contentType(_RawMessage m) {
    final ct = m.header('content-type') ?? '';
    final semi = ct.indexOf(';');
    return (semi >= 0 ? ct.substring(0, semi) : ct).trim();
  }

  /// 完整 Content-Type（保留 charset 参数）
  static String _rawContentType(_RawMessage m) => (m.header('content-type') ?? '').trim();

  /// 按 Content-Type 的 charset 解码文本体。
  ///
  /// 旧实现一律 `utf8.decode(..., allowMalformed: true)`，而 `_contentType` 又主动
  /// 截掉了 `; charset=gbk`：国内站点极常见的 GBK / GB2312 响应会被解成一串 U+FFFD，
  /// 且原始字节不可恢复（导入后重放/导出全是坏数据）。这里按 charset 走仓库已有的
  /// charset 包，解不出来再退回 UTF-8 容错，保证不抛异常。
  static String _decodeText(Uint8List body, String contentType) {
    final lower = contentType.toLowerCase();
    final idx = lower.indexOf('charset=');
    if (idx >= 0) {
      var name = contentType.substring(idx + 8).trim();
      final semi = name.indexOf(';');
      if (semi >= 0) name = name.substring(0, semi).trim();
      name = name.replaceAll('"', '').replaceAll("'", '').toLowerCase();
      if (name.isNotEmpty && name != 'utf-8' && name != 'utf8') {
        final encoding = charset.Charset.getByName(name);
        if (encoding != null) {
          try {
            return encoding.decode(body);
          } catch (_) {
            // 落到 UTF-8 容错
          }
        }
      }
    }
    return utf8.decode(body, allowMalformed: true);
  }

  static bool _isBinary(String ct) {
    final t = ct.toLowerCase();
    return t.startsWith('image/') ||
        t.startsWith('audio/') ||
        t.startsWith('video/') ||
        t.startsWith('font/') ||
        t.contains('application/octet-stream') ||
        t.contains('application/pdf') ||
        t.contains('application/zip') ||
        t.contains('application/x-protobuf') ||
        t.contains('application/wasm') ||
        t.contains('application/x-font') ||
        t.contains('application/vnd.ms-') ||
        t.contains('application/x-msdownload');
  }

  /// Charles 的 `raw/N_m.xml` 里带抓包时间（不同版本写法不同：元素形式
  /// `<startTime>2024-05-01T10:20:30.123+08:00</startTime>` 或属性形式）。
  /// 提取不到返回 null，由调用方用「导入时刻 + 序号」兜底。
  static final RegExp _startTimeRe = RegExp(
      r'startTime[^0-9]{0,20}([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+(?:Z|[+-][0-9:]{2,5})?)',
      caseSensitive: false);

  static DateTime? _startedAtOf(String? meta) {
    if (meta == null) return null;
    final m = _startTimeRe.firstMatch(meta);
    if (m == null) return null;
    return DateTime.tryParse(m.group(1)!)?.toLocal();
  }

  static int? _portOf(String host) {
    if (host.isEmpty) return null;
    final colon = host.lastIndexOf(':');
    if (colon < 0) return null;
    return int.tryParse(host.substring(colon + 1));
  }

  static String _schemeFor(String target, String host, String? meta) {
    final t = target.toLowerCase();
    if (t.startsWith('https://')) return 'https';
    if (t.startsWith('http://')) return 'http';
    if (_portOf(host) == 443) return 'https';
    if (meta != null && meta.toLowerCase().contains('https')) return 'https';
    return 'http';
  }

  static String _buildUrl(String target, String host, String scheme) {
    final t = target.toLowerCase();
    if (t.startsWith('http://') || t.startsWith('https://')) return target;
    final h = host.isEmpty ? 'unknown' : host;
    return '$scheme://$h$target';
  }
}
