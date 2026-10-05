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
      final req = _parseMessage(reqs[id]!);
      if (req == null || req.startLine.isEmpty) continue;

      final parts = req.startLine.split(' ');
      final method = parts.isNotEmpty ? parts[0].toUpperCase() : '';
      if (method.isEmpty || method == 'CONNECT') continue; // 隧道握手不导出
      final rawTarget = parts.length > 1 ? parts[1] : '/';
      final version = parts.length > 2 ? parts[2] : 'HTTP/1.1';

      final hostHeader = req.header('host') ?? '';
      final scheme = _schemeFor(rawTarget, hostHeader, metas[id]);
      final url = _buildUrl(rawTarget, hostHeader, scheme);

      final resp = resps[id] == null ? null : _parseMessage(resps[id]!);

      entries.add(_entry(
        id: id,
        seq: seq++,
        method: method,
        url: url,
        version: version,
        req: req,
        resp: resp,
      ));
    }
    return entries;
  }

  static Map<String, dynamic> _entry({
    required int id,
    required int seq,
    required String method,
    required String url,
    required String version,
    required _RawMessage req,
    required _RawMessage? resp,
  }) {
    final reqBody = _decodedBody(req);
    final reqCt = _contentType(req);

    final respBody = resp == null ? null : _decodedBody(resp);
    final respCt = resp == null ? '' : _contentType(resp);

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
          'text': _isBinary(respCt) ? base64Encode(body) : utf8.decode(body, allowMalformed: true),
        },
        'bodySize': body.length,
      };
    }

    return {
      'startedDateTime': DateTime.now().add(Duration(milliseconds: seq)).toUtc().toIso8601String(),
      'time': -1,
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

  static bool _isBinary(String ct) {
    final t = ct.toLowerCase();
    return t.startsWith('image/') ||
        t.startsWith('audio/') ||
        t.startsWith('video/') ||
        t.startsWith('font/') ||
        t.contains('application/octet-stream') ||
        t.contains('application/pdf') ||
        t.contains('application/zip') ||
        t.contains('application/x-protobuf');
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
