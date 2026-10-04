/*
 * Server-Sent Events (text/event-stream) incremental decoder
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:proxypin/network/http/websocket.dart';

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
    int start = _scanOffset;

    while (true) {
      final int nl = current.indexOf('\n', start);
      if (nl == -1) break;

      String line = current.substring(start, nl);
      start = nl + 1;

      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);

      if (line.isEmpty) {
        // End of event: emit if any data collected
        if (_data.isNotEmpty) {
          String dataValue = _data.toString();
          if (dataValue.endsWith('\n')) dataValue = dataValue.substring(0, dataValue.length - 1);

          // Build a text frame from the SSE event. Include event/id headers if present as a prefix comment.
          final String payloadText = _event == null && _id == null
              ? dataValue
              : _buildLabeledPayload(dataValue, event: _event, id: _id, retry: _retry);

          frames.add(_textFrame(payloadText));
        }
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
          // ignore unknown fields
          break;
      }
    }

    // 丢弃已消费部分，仅保留未成行的尾部；避免缓冲随流长度无界增长。
    if (start > 0) {
      final String rest = current.substring(start);
      _lineBuf
        ..clear()
        ..write(rest);
      _scanOffset = 0;
    } else {
      _scanOffset = current.length;
    }

    return frames;
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
