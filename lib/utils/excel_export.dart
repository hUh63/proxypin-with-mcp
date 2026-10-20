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
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:proxypin/network/http/http.dart';

/// 单个单元格：要么是数字，要么是字符串（内联）。
class _Cell {
  final bool isNumber;
  final num? number;
  final String? text;

  const _Cell.number(this.number) : isNumber = true, text = null;
  const _Cell.string(this.text) : isNumber = false, number = null;

  static _Cell n(num? v) => _Cell.number(v ?? 0);
  static _Cell s(String? v) => _Cell.string(v ?? '');
}

/// 极简 XLSX 写出器 —— 不引入任何 Excel 库，只用已有的 `archive` 打 zip。
///
/// 产出的是一个合法的 `.xlsx`（SpreadsheetML，单工作表 + 内联字符串），
/// Excel / WPS / Numbers 均可直接打开。用于把抓包列表导成表格，
/// 对标 HTTP Debugger Pro 的 Excel 导出。
class ExcelExport {
  /// 把请求列表导出为 xlsx 字节。
  static Uint8List requestsToXlsx(List<HttpRequest> requests, {String sheetName = 'ProxyPin'}) {
    final rows = <List<Object?>>[
      ['#', 'Time', 'Method', 'Status', 'Protocol', 'Host', 'Path', 'Process',
        'Duration(ms)', 'ReqSize(B)', 'RespSize(B)', 'Content-Type'],
    ];

    var seq = 0;
    for (final r in requests) {
      seq++;
      final resp = r.response;
      final duration = resp == null ? -1 : resp.responseTime.difference(r.requestTime).inMilliseconds;
      rows.add([
        seq,
        _formatTime(r.requestTime),
        r.methodLabel,
        resp?.status.code ?? 0,
        r.protocolVersion,
        r.hostAndPort?.host ?? '',
        r.domainPath,
        r.processInfo?.name ?? '',
        duration,
        _bodySize(r.body, r.originalBodyLength),
        _bodySize(resp?.body, resp?.originalBodyLength),
        resp?.headers.contentType ?? '',
      ]);
    }

    return buildWorkbook(rows, sheetName: sheetName);
  }

  /// 纯函数：把「行 × 列」的值（String / num）序列化成 xlsx 字节。
  /// 与具体抓包模型解耦，便于单测。
  static Uint8List buildWorkbook(List<List<Object?>> rows, {String sheetName = 'ProxyPin'}) {
    final cells = rows
        .map((row) => row.map((v) => v is num ? _Cell.n(v) : _Cell.s(v?.toString())).toList(growable: false))
        .toList(growable: false);
    return _build(cells, _safeSheetName(sheetName));
  }

  /// 请求/响应体大小：body 被「抓包内容上限」裁剪后 length 已不是原始大小，
  /// 优先取 originalBodyLength（与 har.dart 的口径一致）。
  static int _bodySize(List<int>? body, int? originalLength) => originalLength ?? body?.length ?? 0;

  static String _formatTime(DateTime dt) {
    final l = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}:${two(l.second)}.'
        '${three(l.millisecond)}';
  }

  /// 工作表名：<=31 字符，且不能含 []:*?/\ 这些非法字符。
  static String _safeSheetName(String name) {
    var s = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), '_');
    if (s.isEmpty) s = 'ProxyPin';
    if (s.length > 31) {
      var end = 31;
      // 别把代理对劈成两半，否则会留下孤立代理项。
      final unit = s.codeUnitAt(end - 1);
      if (unit >= 0xD800 && unit <= 0xDBFF) end -= 1;
      s = s.substring(0, end);
    }
    // Excel 不允许工作表名以单引号开头/结尾。
    while (s.startsWith("'")) {
      s = s.substring(1);
    }
    while (s.endsWith("'")) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty) s = 'ProxyPin';
    return s;
  }

  /// 0 -> A, 25 -> Z, 26 -> AA ...
  static String _colName(int index) {
    var i = index;
    final sb = StringBuffer();
    while (i >= 0) {
      sb.write(String.fromCharCode(65 + (i % 26)));
      i = (i ~/ 26) - 1;
    }
    return String.fromCharCodes(sb.toString().codeUnits.reversed);
  }

  /// XML 1.0 不允许出现的字符：0x00-0x08 / 0x0B / 0x0C / 0x0E-0x1F / 0xFFFE / 0xFFFF。
  /// 抓包数据里的请求头、URL、进程名经常带这些原始控制字节，混进 sheet1.xml 后
  /// Excel / WPS 会报「发现不可读取的内容」并拒绝打开整个文件。
  static final RegExp _xmlInvalidChars =
      RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]');

  static String _xmlEscape(String value) {
    var v = value;
    if (v.contains(_xmlInvalidChars)) {
      v = v.replaceAll(_xmlInvalidChars, '');
    }
    return v
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static Uint8List _build(List<List<_Cell>> rows, String sheetName) {
    final sheet = StringBuffer();
    sheet.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sheet.write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
    sheet.write('<sheetData>');
    for (var r = 0; r < rows.length; r++) {
      final rowNo = r + 1;
      sheet.write('<row r="$rowNo">');
      final row = rows[r];
      for (var c = 0; c < row.length; c++) {
        final ref = '${_colName(c)}$rowNo';
        final cell = row[c];
        if (cell.isNumber) {
          sheet.write('<c r="$ref"><v>${cell.number}</v></c>');
        } else {
          final t = _xmlEscape(cell.text ?? '');
          sheet.write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">$t</t></is></c>');
        }
      }
      sheet.write('</row>');
    }
    sheet.write('</sheetData></worksheet>');

    final archive = Archive();
    void add(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add('[Content_Types].xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '</Types>');

    add('_rels/.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        'Target="xl/workbook.xml"/>'
        '</Relationships>');

    add('xl/workbook.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="${_xmlEscape(sheetName)}" sheetId="1" r:id="rId1"/></sheets>'
        '</workbook>');

    add('xl/_rels/workbook.xml.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
        'Target="worksheets/sheet1.xml"/>'
        '</Relationships>');

    add('xl/worksheets/sheet1.xml', sheet.toString());

    final out = ZipEncoder().encode(archive);
    return Uint8List.fromList(out);
  }
}
