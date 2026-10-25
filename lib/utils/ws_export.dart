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
import 'package:proxypin/network/http/websocket.dart';

/// WebSocket 会话导出（上游 #976：希望导出 WS 会话、内容为 Protobuf 二进制）。
///
/// HAR 的 `_webSocketMessages` 只能放文本或 base64，脚本里还得再解一层编码；
/// 这里直接给**原始二进制帧**，protobuf 可以直接喂给 `protoc --decode_raw`：
///
/// - `frames.jsonl`：每帧一行元信息（seq / dir / opcode / time / length，
///   文本帧给 `text`，二进制帧给 `base64`），脚本按行读即可；
/// - `frames/0001_client.bin` …：每个二进制（或非文本）帧一份原始 payload；
/// - `frames.txt`：给人看的文本转录（帧序号 / 方向 / 时间 / opcode / 内容）；
/// - `README.txt`：字段与目录说明。
class WsExport {
  WsExport._();

  /// 单帧导出上限：一条几十 MB 的帧（大文件推送）不该把 zip 撑爆，
  /// 超出的部分只保留前缀并在 jsonl 里标 `clipped`。
  static const int maxFrameBytes = 8 * 1024 * 1024;

  static const Map<int, String> _opcodeNames = {
    0x0: 'continuation',
    0x1: 'text',
    0x2: 'binary',
    0x3: 'reserved3',
    0x4: 'reserved4',
    0x5: 'reserved5',
    0x6: 'reserved6',
    0x7: 'reserved7',
    0x8: 'close',
    0x9: 'ping',
    0xa: 'pong',
  };

  static String opcodeName(int opcode) => _opcodeNames[opcode] ?? 'opcode$opcode';

  /// 只生成 JSONL（每帧一行），便于脚本直接流式处理。
  static String buildJsonl(HttpRequest request) {
    final buffer = StringBuffer();
    var seq = 0;
    for (final frame in request.messages) {
      seq++;
      buffer.writeln(jsonEncode(_frameRecord(seq, frame)));
    }
    return buffer.toString();
  }

  static Map<String, dynamic> _frameRecord(int seq, WebSocketFrame frame) {
    final payload = frame.payloadData;
    final clipped = payload.length > maxFrameBytes;
    final data = clipped ? payload.sublist(0, maxFrameBytes) : payload;
    final isText = frame.opcode == 0x1;
    return {
      'seq': seq,
      'dir': frame.isFromClient ? 'client' : 'server',
      'opcode': frame.opcode,
      'opcodeName': opcodeName(frame.opcode),
      'fin': frame.fin,
      'time': frame.time.toUtc().toIso8601String(),
      'length': payload.length,
      if (clipped) 'clipped': true,
      if (clipped) 'returned': data.length,
      'encoding': isText ? 'utf8' : 'base64',
      'data': isText ? utf8.decode(data, allowMalformed: true) : base64Encode(data),
    };
  }

  /// 生成 zip（结构见类注释）。
  static Uint8List buildZip(HttpRequest request) {
    final archive = Archive();
    void addText(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    final jsonl = StringBuffer();
    final transcript = StringBuffer();
    transcript.writeln('WebSocket session: ${request.requestUrl}');
    transcript.writeln('frames: ${request.messages.length}');
    transcript.writeln('');

    var seq = 0;
    for (final frame in request.messages) {
      seq++;
      jsonl.writeln(jsonEncode(_frameRecord(seq, frame)));

      final dir = frame.isFromClient ? 'client' : 'server';
      final payload = frame.payloadData;
      final clipped = payload.length > maxFrameBytes;
      final data = clipped ? payload.sublist(0, maxFrameBytes) : payload;

      // 非文本帧（binary / ping / pong / close 的 payload）落成独立 .bin，
      // Protobuf 之类的原始字节可以直接拿去解码
      if (frame.opcode != 0x1 && data.isNotEmpty) {
        final name = 'frames/${seq.toString().padLeft(4, '0')}_$dir.bin';
        archive.addFile(ArchiveFile(name, data.length, data));
      }

      final preview = frame.opcode == 0x1 ? utf8.decode(data, allowMalformed: true) : '<${data.length} bytes>';
      transcript.writeln('#$seq ${frame.time.toUtc().toIso8601String()} $dir '
          '${opcodeName(frame.opcode)} ${payload.length}B${clipped ? ' (clipped)' : ''}');
      transcript.writeln(preview.length > 2000 ? '${preview.substring(0, 2000)}…' : preview);
      transcript.writeln('');
    }

    addText('frames.jsonl', jsonl.toString());
    addText('frames.txt', transcript.toString());
    addText(
        'README.txt',
        'ProxyPin WebSocket export\n'
        '\n'
        'frames.jsonl   one JSON object per frame:\n'
        '               {seq, dir(client|server), opcode, opcodeName, fin, time,\n'
        '                length, encoding(utf8|base64), data, [clipped, returned]}\n'
        'frames/*.bin   raw payload of every non-text frame (protobuf goes here as-is);\n'
        '               decode with e.g. `protoc --decode_raw < frames/0001_client.bin`\n'
        'frames.txt     human readable transcript\n'
        '\n'
        'Frames larger than ${maxFrameBytes ~/ (1024 * 1024)}MB are clipped and marked in jsonl.\n');

    final out = ZipEncoder().encode(archive);
    return Uint8List.fromList(out);
  }
}
