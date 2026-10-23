/*
 * Server-Sent Events (text/event-stream) incremental decoder
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/util/compress.dart';

/// Parse SSE stream chunks into message frames.
/// We reuse WebSocketFrame as a generic message container so UI and listeners work.
class SseDecoder {
  /// 已解码文本缓冲（保留尚未成行的尾部）。
  final StringBuffer _lineBuf = StringBuffer();

  /// 增量 UTF-8 解码器。
  ///
  /// 旧实现是 `utf8.decode(bytes, allowMalformed: true)` **逐块**解码，
  /// 一旦一个多字节字符（中文、emoji）被 TCP 分片切断，就会在两个块里
  /// 各解出 U+FFFD，SSE 内容出现乱码。改用 chunked conversion 后，
  /// 未完成的多字节序列会被保留到下一块继续拼装。
  late final ByteConversionSink _utf8Sink =
      utf8.decoder.startChunkedConversion(_StringSinkAdapter(_lineBuf));

  /// 行扫描游标：记录已消费到的位置，避免每次 `toString()` 后从头 substring（O(n²)）。
  int _scanOffset = 0;

  // current event fields
  final StringBuffer _data = StringBuffer();
  String? _event;
  String? _id;
  int? _retry;

  /// Feed a chunk of bytes and return zero or more frames assembled.
  List<WebSocketFrame> feed(Uint8List bytes) {
    final List<WebSocketFrame> frames = [];

    _utf8Sink.add(bytes);

    final String current = _lineBuf.toString();
    // 必须区分两个位置：
    //  - searchFrom：继续查找 '\n' 的起点（其之前已确认不含 '\n'，避免重复扫描）；
    //  - lineStart ：当前（可能尚未结束的）行在 current 中的起点。
    // 早先二者共用一个变量。逐字节喂入时 searchFrom 会等于 current.length，
    // 新到的 '\n' 恰好落在该下标上，把 searchFrom 当行起点就会解析出空行、
    // 整行被丢弃（sse_chunked_test 的逐字节用例即由此失败）。
    int searchFrom = _scanOffset;
    int lineStart = 0;
    int consumedEnd = 0;

    while (true) {
      final int nl = current.indexOf('\n', searchFrom);
      if (nl == -1) break;

      String line = current.substring(lineStart, nl);
      searchFrom = nl + 1;
      lineStart = searchFrom;
      consumedEnd = searchFrom;

      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);

      if (line.isEmpty) {
        // 事件结束：有 data 才产出一帧（上游 v1.4.0 抽成 _takeEvent，供 flush 复用）
        final pending = _takeEvent();
        if (pending != null) frames.add(pending);
        _resetEventState();
        continue;
      }

      if (line.startsWith(':')) {
        // comment line – ignore
        continue;
      }

      final int colon = line.indexOf(':');
      final String field = (colon == -1) ? line : line.substring(0, colon);
      String value = (colon == -1) ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);

      switch (field) {
        case 'data':
          _data.write(value);
          _data.write('\n');
          break;
        case 'event':
          _event = value;
          break;
        case 'id':
          _id = value;
          break;
        case 'retry':
          _retry = int.tryParse(value);
          break;
        default:
          // 不少 AI 聊天接口的事件流不用 `data:` 前缀，而是 `15:{...}` / `0:"token"`
          // 这类「数字下标 + 冒号 + 正文」。原实现整行丢弃 → SSE 面板一片空白。
          // 只认纯数字字段名：标准 SSE 里的未知字段（`unknown: x`）仍按规范忽略。
          if (RegExp(r'^\d+$').hasMatch(field)) {
            frames.add(_textFrame(value.isEmpty ? line : value));
          }
          break;
      }
    }

    // 丢弃已消费部分，仅保留未成行的尾部；避免缓冲随流长度无界增长。
    if (consumedEnd > 0) {
      final String rest = current.substring(consumedEnd);
      _lineBuf
        ..clear()
        ..write(rest);
      _scanOffset = 0;
    } else {
      // 本次没有消费任何完整行：整个缓冲都是未完成行，必须完整保留。
      _scanOffset = current.length;
    }

    return frames;
  }

  /// 流出结束（对端关闭 / h2 END_STREAM）时把残留内容产出：
  /// 既包括没有空行结尾的 `data:` 事件，也包括最后一行没收到换行符的情况。
  List<WebSocketFrame> flush() {
    final frames = <WebSocketFrame>[];
    if (_lineBuf.isNotEmpty) {
      frames.addAll(feed(Uint8List.fromList(utf8.encode('\n'))));
    }
    final pending = _takeEvent();
    if (pending != null) frames.add(pending);
    _resetEventState();
    return frames;
  }

  WebSocketFrame? _takeEvent() {
    if (_data.isEmpty) return null;
    String dataValue = _data.toString();
    if (dataValue.endsWith('\n')) dataValue = dataValue.substring(0, dataValue.length - 1);

    // Build a text frame from the SSE event. Include event/id headers if present as a prefix comment.
    final String payloadText = _event == null && _id == null
        ? dataValue
        : _buildLabeledPayload(dataValue, event: _event, id: _id, retry: _retry);

    return _textFrame(payloadText);
  }

  void _resetEventState() {
    _data.clear();
    _event = null;
    _id = null;
    _retry = null;
  }

  String _buildLabeledPayload(String data, {String? event, String? id, int? retry}) {
    final StringBuffer b = StringBuffer();
    if (event != null && event.isNotEmpty) b.writeln('event: $event');
    if (id != null && id.isNotEmpty) b.writeln('id: $id');
    if (retry != null) b.writeln('retry: $retry');
    b.write(data);
    return b.toString();
  }

  WebSocketFrame _textFrame(String text) {
    final bytes = utf8.encode(text);
    return WebSocketFrame(
      fin: true,
      opcode: 0x01, // text
      mask: false,
      payloadLength: bytes.length,
      maskingKey: 0,
      payloadData: Uint8List.fromList(bytes),
    );
  }
}

/// 把 chunked UTF-8 解码器的输出直接写入 [StringBuffer]。
class _StringSinkAdapter implements Sink<String> {
  final StringBuffer _buffer;

  _StringSinkAdapter(this._buffer);

  @override
  void add(String data) => _buffer.write(data);

  @override
  void close() {}
}

/// True when the event-stream body is not plaintext and must be buffered
/// until it can be inflated. Parsing those bytes as SSE yields no events.
bool sseBodyIsEncoded(String? contentEncoding) {
  if (contentEncoding == null) return false;
  // 与 HttpHeaders.isGzip 同理：`gzip, br` 这类多重编码、`gzip;q=1` 带参数
  // 都不能用字符串相等判断，否则压缩事件流会被当明文解析（面板空白）。
  final value = contentEncoding.toLowerCase();
  return value.contains('gzip') ||
      value.contains('br') ||
      value.contains('deflate') ||
      value.contains('zstd');
}

/// Inflate a finished event-stream body and split it into events.
/// Returns an empty list when [contentEncoding] is unsupported or the bytes
/// are not valid compressed data. Callers keep the original headers.
Future<List<WebSocketFrame>> decodeEncodedEventStream(Uint8List encoded, String? contentEncoding) async {
  final List<int>? plain = await _inflateSse(encoded, contentEncoding);
  if (plain == null) return const [];
  final parsed = SseDecoder();
  final frames = parsed.feed(Uint8List.fromList(plain));
  frames.addAll(parsed.flush());
  return frames;
}

Future<List<int>?> _inflateSse(Uint8List encoded, String? contentEncoding) async {
  if (encoded.isEmpty) return null;

  final List<int> out;
  switch (contentEncoding) {
    case 'gzip':
    case 'x-gzip':
      out = gzipDecode(encoded);
      break;
    case 'br':
      out = brDecode(encoded);
      break;
    case 'deflate':
      out = zlibDecode(encoded);
      break;
    case 'zstd':
      final decoded = await zstdDecode(encoded);
      if (decoded == null || identical(decoded, encoded)) return null;
      out = decoded;
      break;
    default:
      return null;
  }
  // The decoders return the input unchanged when inflation fails.
  if (identical(out, encoded)) return null;
  return out;
}
