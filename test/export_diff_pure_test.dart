/*
 * 导出 / 差异工具纯函数补测（零覆盖模块）。
 *
 * 覆盖：PcapNg（合成 PCAPNG：块结构 + IPv4/TCP 校验和 + 时间戳）、
 *       ExcelExport（xlsx 打包 + XML 转义 + 行映射）、
 *       TextDiff（行级 diff / 差异块配对 / 统计 / 并排对齐行 / 字符级 diff）、
 *       JsCompiler（语法校验 + 压缩：压缩结果本身仍可解析）。
 *
 * 全部为纯计算，无 socket / 无原生依赖；不打 integration 标签，CI 会真实执行。
 */
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/utils/excel_export.dart';
import 'package:proxypin/utils/js_compiler.dart';
import 'package:proxypin/utils/pcapng.dart';
import 'package:proxypin/utils/text_diff.dart';

// ---------- PCAPNG 解析小工具（独立于被测实现，用来交叉验证） ----------

class _Block {
  final int type;
  final int totalLength;
  final Uint8List bytes;

  _Block(this.type, this.totalLength, this.bytes);
}

List<_Block> _readBlocks(Uint8List data) {
  final blocks = <_Block>[];
  var offset = 0;
  while (offset + 12 <= data.length) {
    final type = _u32(data, offset);
    final total = _u32(data, offset + 4);
    expect(total % 4, 0, reason: 'PCAPNG 块长度必须 4 字节对齐：offset=$offset total=$total');
    expect(offset + total, lessThanOrEqualTo(data.length), reason: '块长度越界：offset=$offset');
    expect(_u32(data, offset + total - 4), total, reason: '块尾的 total_length 必须与块头一致');
    blocks.add(_Block(type, total, Uint8List.sublistView(data, offset + 8, offset + total - 4)));
    offset += total;
  }
  expect(offset, data.length, reason: '必须正好走完整个文件');
  return blocks;
}

int _u32(Uint8List d, int o) => d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | (d[o + 3] << 24);

int _u16be(List<int> d, int o) => (d[o] << 8) | d[o + 1];

int _onesComplementSum(List<int> data) {
  var sum = 0;
  for (var i = 0; i + 1 < data.length; i += 2) {
    sum += (data[i] << 8) | data[i + 1];
  }
  if (data.length.isOdd) sum += data.last << 8;
  while (sum > 0xFFFF) {
    sum = (sum & 0xFFFF) + (sum >> 16);
  }
  return sum;
}

/// 解析一个 EPB 里负载的以太网帧，校验 IPv4 / TCP 校验和并取回各字段。
({
  List<int> srcIp,
  List<int> dstIp,
  int srcPort,
  int dstPort,
  int seq,
  int ack,
  List<int> payload,
}) _parseFrame(Uint8List epbPayload) {
  expect(_u16be(epbPayload, 12), 0x0800, reason: 'EtherType 必须是 IPv4');
  final ipOffset = 14;
  final ip = epbPayload.sublist(ipOffset);
  expect(ip[0] >> 4, 4);
  expect(ip[0] & 0x0F, 5, reason: 'IHL 必须是 5（无选项）');
  expect(ip[9], 6, reason: '协议必须是 TCP');
  final ipTotal = _u16be(ip, 2);
  expect(ipTotal, ip.length, reason: 'IPv4 total length 必须覆盖整个 IP 报文');

  final ipHeader = ip.sublist(0, 20);
  expect(_onesComplementSum(ipHeader), 0xFFFF, reason: 'IPv4 头校验和必须自洽');

  final tcpOffset = ipOffset + 20;
  final tcp = epbPayload.sublist(tcpOffset);
  final tcpLength = tcp.length;
  final srcIp = ip.sublist(12, 16);
  final dstIp = ip.sublist(16, 20);
  final pseudo = <int>[...srcIp, ...dstIp, 0, 6, (tcpLength >> 8) & 0xFF, tcpLength & 0xFF];
  expect(_onesComplementSum(<int>[...pseudo, ...tcp]), 0xFFFF, reason: 'TCP 校验和必须自洽（含伪首部）');

  return (
    srcIp: srcIp,
    dstIp: dstIp,
    srcPort: _u16be(tcp, 0),
    dstPort: _u16be(tcp, 2),
    seq: _u32(Uint8List.fromList(tcp), 4),
    ack: _u32(Uint8List.fromList(tcp), 8),
    payload: tcp.sublist(20),
  );
}

HttpRequest _req(String url, HttpMethod method) =>
    HttpRequest(method, url, protocolVersion: 'HTTP/1.1')..hostAndPort = HostAndPort.of(url);

void main() {
  group('PcapNg', () {
    test('build：块结构、时间戳与帧内容（IPv4/TCP 校验和自洽）', () {
      final requestBytes = utf8.encode('GET /a?b=1 HTTP/1.1\r\nHost: x\r\n\r\n');
      final responseBytes = utf8.encode('HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi');
      final reqTime = DateTime.utc(2026, 2, 3, 4, 5, 6, 7, 8);
      final respTime = reqTime.add(const Duration(milliseconds: 250));

      final bytes = PcapNg.build([
        PcapSession(
          clientIp: [192, 168, 1, 10],
          clientPort: 51234,
          serverIp: [93, 184, 216, 34],
          serverPort: 443,
          requestBytes: requestBytes,
          responseBytes: responseBytes,
          requestTime: reqTime,
          responseTime: respTime,
        ),
      ]);

      final blocks = _readBlocks(bytes);
      expect(blocks.map((b) => b.type).toList(), [0x0A0D0D0A, 1, 6, 6],
          reason: 'SHB + IDB + 请求 EPB + 响应 EPB');
      expect(blocks[0].bytes.length, 20);
      expect(_u32(blocks[0].bytes, 0), 0x1A2B3C4D, reason: '字节序 magic');
      expect(blocks[1].bytes.length, 12);
      expect(_u16be(blocks[1].bytes, 0), 1, reason: 'link type 必须是 Ethernet');

      // 请求帧：先校验 EPB 的 caplen/origlen 与补零
      final reqCapLen = _u32(blocks[2].bytes, 12);
      final reqOrigLen = _u32(blocks[2].bytes, 16);
      expect(reqCapLen, reqOrigLen);
      expect(blocks[2].bytes.sublist(20 + reqCapLen).every((b) => b == 0), isTrue, reason: 'EPB 负载需 4 字节补零');
      final reqTs = (_u32(blocks[2].bytes, 4) << 32) | _u32(blocks[2].bytes, 8);
      expect(reqTs, reqTime.microsecondsSinceEpoch, reason: '时间戳（微秒）必须一致');
      final reqFrameBytes = blocks[2].bytes.sublist(20, 20 + reqCapLen);
      final reqFrame = _parseFrame(reqFrameBytes);
      expect(reqFrame.srcIp, [192, 168, 1, 10]);
      expect(reqFrame.dstIp, [93, 184, 216, 34]);
      expect(reqFrame.srcPort, 51234);
      expect(reqFrame.dstPort, 443);
      expect(reqFrame.seq, 1);
      expect(reqFrame.ack, 1);
      expect(reqFrame.payload, requestBytes, reason: '请求字节必须原样落在 TCP payload 里');

      // 响应帧：方向相反，ack = 请求长度 + 1
      final respCapLen = _u32(blocks[3].bytes, 12);
      expect(respCapLen, _u32(blocks[3].bytes, 16));
      final respTs = (_u32(blocks[3].bytes, 4) << 32) | _u32(blocks[3].bytes, 8);
      expect(respTs, respTime.microsecondsSinceEpoch);
      final respFrame = _parseFrame(blocks[3].bytes.sublist(20, 20 + respCapLen));
      expect(respFrame.srcIp, [93, 184, 216, 34]);
      expect(respFrame.dstIp, [192, 168, 1, 10]);
      expect(respFrame.srcPort, 443);
      expect(respFrame.dstPort, 51234);
      expect(respFrame.seq, 1);
      expect(respFrame.ack, 1 + requestBytes.length);
      expect(respFrame.payload, responseBytes);
    });

    test('build：只有请求（无响应时间）时只写一个 EPB；空输入只有 SHB+IDB', () {
      final only = PcapNg.build([
        PcapSession(
          clientIp: [10, 0, 0, 1],
          clientPort: 1000,
          serverIp: [10, 0, 0, 2],
          serverPort: 80,
          requestBytes: utf8.encode('GET / HTTP/1.1\r\n\r\n'),
          responseBytes: utf8.encode('HTTP/1.1 200 OK\r\n\r\n'),
          requestTime: DateTime.utc(2026, 1, 1),
        ),
      ]);
      expect(_readBlocks(only).map((b) => b.type).toList(), [0x0A0D0D0A, 1, 6]);

      final empty = PcapNg.build(const []);
      expect(_readBlocks(empty).map((b) => b.type).toList(), [0x0A0D0D0A, 1]);
    });

    test('parseIpv4：仅接受合法点分十进制', () {
      expect(PcapNg.parseIpv4('192.168.0.1'), [192, 168, 0, 1]);
      expect(PcapNg.parseIpv4('0.0.0.0'), [0, 0, 0, 0]);
      expect(PcapNg.parseIpv4(null), isNull);
      expect(PcapNg.parseIpv4('1.2.3'), isNull);
      expect(PcapNg.parseIpv4('1.2.3.256'), isNull);
      expect(PcapNg.parseIpv4('a.b.c.d'), isNull);
      expect(PcapNg.parseIpv4('::1'), isNull);
    });
  });

  group('ExcelExport', () {
    test('buildWorkbook：产出合法 zip，工作表 XML 转义与单元格引用正确', () {
      final bytes = ExcelExport.buildWorkbook([
        ['#', 'Name & Co', 'Note'],
        [1, 'a & b', '<tag>'],
        [2, "quote'd", '双引号"x"'],
      ], sheetName: '测试/Sheet:1');

      expect(bytes.length, greaterThan(100));
      expect(utf8.decode(bytes.sublist(0, 2)), 'PK', reason: '必须是 zip 容器');

      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toSet();
      expect(names, containsAll(<String>[
        '[Content_Types].xml',
        'xl/workbook.xml',
        'xl/_rels/workbook.xml.rels',
        'xl/worksheets/sheet1.xml',
      ]));

      final sheet = archive.files.firstWhere((f) => f.name == 'xl/worksheets/sheet1.xml');
      final xml = utf8.decode(List<int>.from(sheet.content as List<int>));
      expect(xml, contains('<row r="1">'));
      expect(xml, contains('<row r="3">'));
      expect(xml, contains('r="A1"'));
      expect(xml, contains('r="C3"'));
      // 数字单元格
      expect(xml, contains('<c r="A2"><v>1</v></c>'));
      // 字符串单元格 + 转义
      expect(xml, contains('t="inlineStr"'));
      expect(xml, contains('a &amp; b'));
      expect(xml, contains('&lt;tag&gt;'));
      expect(xml, contains('&apos;'));
      expect(xml, contains('&quot;'));
      expect(xml, isNot(contains('<tag>')), reason: '原文必须被转义，不能出现裸标签');

      final workbook = archive.files.firstWhere((f) => f.name == 'xl/workbook.xml');
      final workbookXml = utf8.decode(List<int>.from(workbook.content as List<int>));
      expect(workbookXml, contains('name="测试_Sheet_1"'), reason: '非法字符被替换为下划线');
    });

    test('buildWorkbook：表名为空回退默认；requestsToXlsx 映射抓包模型', () {
      final emptyName = ExcelExport.buildWorkbook(const [
        ['h'],
      ], sheetName: '');
      final archive = ZipDecoder().decodeBytes(emptyName);
      final workbook = archive.files.firstWhere((f) => f.name == 'xl/workbook.xml');
      expect(utf8.decode(List<int>.from(workbook.content as List<int>)), contains('name="ProxyPin"'));

      final request = _req('http://api.example.com/v1/items?x=1', HttpMethod.post);
      request.body = utf8.encode('{"a":1}');
      request.requestTime = DateTime(2026, 3, 4, 5, 6, 7);
      final response = HttpResponse(HttpStatus.newStatus(201, 'Created'))
        ..body = utf8.encode('created')
        ..request = request
        ..responseTime = request.requestTime.add(const Duration(milliseconds: 12))
        ..headers.contentType = 'application/json';
      request.response = response;

      final bytes = ExcelExport.requestsToXlsx([request]);
      final sheet = ZipDecoder().decodeBytes(bytes).files.firstWhere((f) => f.name == 'xl/worksheets/sheet1.xml');
      final xml = utf8.decode(List<int>.from(sheet.content as List<int>));
      expect(xml, contains('Method'));
      expect(xml, contains('POST'));
      expect(xml, contains('<v>201</v>'), reason: '状态码必须是数字单元格');
      expect(xml, contains('api.example.com'));
      expect(xml, contains('/v1/items'));
      expect(xml, contains('<v>12</v>'), reason: '耗时 12ms 必须是数字');
      expect(xml, contains('<v>7</v>'), reason: '请求体 7 字节');
      expect(xml, contains('application/json'));
      expect(xml, contains('<row r="2">'), reason: '表头 1 行 + 数据 1 行');
    });
  });

  group('TextDiff', () {
    test('diffLines：相同 / 插入 / 删除 / 尾部空行', () {
      final same = diffLines('a\nb\nc', 'a\nb\nc');
      expect(same, hasLength(3));
      expect(same.every((d) => d.type == LineDiffType.equal), isTrue);
      expect(same.map((d) => d.leftLine).toList(), [1, 2, 3]);
      expect(same.map((d) => d.rightLine).toList(), [1, 2, 3]);

      final ins = diffLines('a\nc', 'a\nb\nc');
      expect(ins.where((d) => d.type == LineDiffType.insert).map((d) => d.text).toList(), ['b']);
      expect(ins.where((d) => d.type == LineDiffType.delete), isEmpty);
      final inserted = ins.firstWhere((d) => d.type == LineDiffType.insert);
      expect(inserted.leftLine, isNull);
      expect(inserted.rightLine, 2);

      final del = diffLines('a\nb\nc', 'a\nc');
      final deleted = del.firstWhere((d) => d.type == LineDiffType.delete);
      expect(deleted.text, 'b');
      expect(deleted.leftLine, 2);
      expect(deleted.rightLine, isNull);

      // 尾部空行差异必须保留（split('\n') 而非 LineSplitter）
      final trailing = diffLines('a\n', 'a');
      expect(trailing.where((d) => d.type == LineDiffType.delete).map((d) => d.text).toList(), ['']);
    });

    test('diffLines：ignoreCase / ignoreWhitespace 只影响「是否相同」的判定', () {
      expect(diffLines('A\nB', 'a\nb').any((d) => d.type != LineDiffType.equal), isTrue);
      expect(diffLines('A\nB', 'a\nb', ignoreCase: true).every((d) => d.type == LineDiffType.equal), isTrue);
      expect(diffLines('a b', 'ab').any((d) => d.type != LineDiffType.equal), isTrue);
      expect(diffLines('a b', 'ab', ignoreWhitespace: true).every((d) => d.type == LineDiffType.equal), isTrue);
      // 归一化只用于判定，不改展示文本
      final wsIgnored = diffLines(' A ', 'A', ignoreWhitespace: true);
      expect(wsIgnored, hasLength(1));
      expect(wsIgnored.single.type, LineDiffType.equal);
    });

    test('buildDiffBlocks / diffStats：修改行配对与统计口径', () {
      final diffs = diffLines('a\nfoo = 1\nc', 'a\nfoo = 2\nc');
      final blocks = buildDiffBlocks(diffs);
      expect(blocks, hasLength(1));
      expect(blocks.single.isModify, isTrue);
      expect(blocks.single.leftLines, [1]);
      expect(blocks.single.rightLines, [1]);
      expect(blocks.single.pairs, hasLength(1));
      expect(blocks.single.rightLocalOfLeft(0), 0);
      expect(blocks.single.leftLocalOfRight(0), 0);

      final stats = diffStats(blocks);
      expect(stats.modified, 1);
      expect(stats.added, 0);
      expect(stats.deleted, 0);
      expect(stats.identical, isFalse);

      // 完全无关的删除 + 新增：相似度不足，不配对
      final unrelated = buildDiffBlocks(diffLines('a\nb\nc', 'a\nZZZ\nc'));
      expect(unrelated.single.pairs, isEmpty);
      expect(unrelated.single.isModify, isFalse);
      final unrelatedStats = diffStats(unrelated);
      expect(unrelatedStats.modified, 0);
      expect(unrelatedStats.added, 1);
      expect(unrelatedStats.deleted, 1);

      // 纯新增
      final pureAdd = diffStats(buildDiffBlocks(diffLines('a\nb', 'a\nnew\nb')));
      expect(pureAdd.added, 1);
      expect(pureAdd.deleted, 0);
      expect(pureAdd.modified, 0);

      // 完全相同
      final identical = diffStats(buildDiffBlocks(diffLines('x\ny', 'x\ny')));
      expect(identical.identical, isTrue);
      expect(buildDiffBlocks(diffLines('x\ny', 'x\ny')), isEmpty);
    });

    test('alignedDiffRows：并排对齐行（行号 1-based，缺失侧为空）', () {
      final rows = alignedDiffRows('a\nfoo = 1\nc', 'a\nfoo = 2\nc');
      expect(rows, hasLength(3));
      expect(rows.every((r) => r.type == DiffRowType.modified || r.type == DiffRowType.equal), isTrue);
      final modified = rows.firstWhere((r) => r.type == DiffRowType.modified);
      expect(modified.leftText, 'foo = 1');
      expect(modified.rightText, 'foo = 2');
      expect(modified.leftLine, 2);
      expect(modified.rightLine, 2);

      final added = alignedDiffRows('a\nc', 'a\nb\nc');
      final addedRow = added.firstWhere((r) => r.type == DiffRowType.added);
      expect(addedRow.leftText, isNull);
      expect(addedRow.leftLine, isNull);
      expect(addedRow.rightText, 'b');
      expect(addedRow.rightLine, 2);
      expect(added.first.leftText, 'a');

      final deleted = alignedDiffRows('a\nb\nc', 'a\nc');
      final deletedRow = deleted.firstWhere((r) => r.type == DiffRowType.deleted);
      expect(deletedRow.rightText, isNull);
      expect(deletedRow.leftText, 'b');
    });

    test('diffChars：字符级改动区间（半开区间），可还原出改动内容', () {
      final inserted = diffChars('hello world', 'hello brave world');
      expect(inserted.leftRanges, isEmpty);
      expect(inserted.rightRanges.map((r) => 'hello brave world'.substring(r.start, r.end)).join(), 'brave ');

      final removed = diffChars('hello brave world', 'hello world');
      expect(removed.rightRanges, isEmpty);
      expect(removed.leftRanges.map((r) => 'hello brave world'.substring(r.start, r.end)).join(), 'brave ');

      final changed = diffChars('foo = 1', 'foo = 2');
      expect(changed.leftRanges.map((r) => 'foo = 1'.substring(r.start, r.end)).join(), '1');
      expect(changed.rightRanges.map((r) => 'foo = 2'.substring(r.start, r.end)).join(), '2');

      final same = diffChars('abc', 'abc');
      expect(same.leftRanges, isEmpty);
      expect(same.rightRanges, isEmpty);
    });
  });

  group('JsCompiler', () {
    test('check：合法 JS 返回 null，语法错误返回信息', () {
      expect(JsCompiler.check('var a = 1; function f(x) { return x + 1; }'), isNull);
      expect(JsCompiler.check('for (var i = 0; i < 3; i++) { console.log(i); }'), isNull);
      expect(JsCompiler.check('const f = (a, b) => a * b;'), isNull);
      expect(JsCompiler.check('var a = ;'), isNotNull);
      expect(JsCompiler.check('function f( { return 1; }'), isNotNull);
      expect(JsCompiler.check('if (a) {'), isNotNull);
    });

    test('minify：注释被移除、体积变小，且压缩产物仍可解析', () {
      const src = '''
// 顶部注释
function add(a, b) {
  /* 块注释 */
  var sum = a + b; // 行尾注释
  return sum * 2;
}
console.log(add(1, 2));
''';
      final out = JsCompiler.minify(src);
      expect(out, isNotNull);
      expect(out!.length, lessThan(src.length));
      expect(out.contains('//'), isFalse, reason: '注释必须被剥掉');
      expect(out.contains('/*'), isFalse);
      expect(out, contains('function'));
      expect(JsCompiler.check(out), isNull, reason: '压缩结果必须是合法 JS');

      final noRename = JsCompiler.minify(src, rename: false);
      expect(noRename, isNotNull);
      expect(noRename, contains('sum'), reason: 'rename: false 必须保留局部变量名');
      expect(JsCompiler.check(noRename!), isNull);
    });

    test('minify：输入非法时返回 null（不抛异常）', () {
      expect(JsCompiler.minify('var a = ;'), isNull);
      expect(JsCompiler.minify('function ( {'), isNull);
      expect(JsCompiler.minify('while (a) {'), isNull);
    });
  });
}
