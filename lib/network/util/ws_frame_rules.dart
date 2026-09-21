import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:proxypin/network/rules/websocket_rule.dart';

/// WebSocket 帧级操纵（上游 #839 Feature Request 1）。
///
/// 这里只做「扫描帧边界 + 按规则处置」，不参与握手、也不碰 permessage-deflate 协商。
/// 设计上刻意保守：扫描不出完整帧、头部有保留位、需要改写的帧是分片帧或压缩帧时，
/// 一律原样放行原始字节 —— 宁可少改一帧，也不能把连接弄坏。
class WsFrameScanner {
  /// 扫描一段字节里包含的完整帧；尾部不完整的帧留给后续 read。
  static List<WsFrameSpan> scan(Uint8List data) {
    final spans = <WsFrameSpan>[];
    var offset = 0;

    while (offset + 2 <= data.length) {
      final b0 = data[offset];
      final b1 = data[offset + 1];
      final fin = (b0 & 0x80) != 0;
      final rsv = b0 & 0x70;
      final opcode = b0 & 0x0f;
      final masked = (b1 & 0x80) != 0;
      var payloadLength = b1 & 0x7f;
      var headerEnd = offset + 2;

      if (payloadLength == 126) {
        if (headerEnd + 2 > data.length) break;
        payloadLength = (data[headerEnd] << 8) | data[headerEnd + 1];
        headerEnd += 2;
      } else if (payloadLength == 127) {
        if (headerEnd + 8 > data.length) break;
        var value = 0;
        for (var i = 0; i < 8; i++) {
          value = (value << 8) | data[headerEnd + i];
        }
        payloadLength = value;
        headerEnd += 8;
      }

      var payloadStart = headerEnd;
      if (masked) {
        if (payloadStart + 4 > data.length) break;
        payloadStart += 4;
      }

      final end = payloadStart + payloadLength;
      if (end > data.length) break; // 帧还没收全

      spans.add(WsFrameSpan(
        offset: offset,
        length: end - offset,
        payloadOffset: payloadStart,
        payloadLength: payloadLength,
        fin: fin,
        opcode: opcode,
        masked: masked,
        rsv: rsv,
      ));
      offset = end;
    }

    return spans;
  }
}

/// 一个完整帧在字节流中的位置与头部信息。
class WsFrameSpan {
  final int offset;
  final int length;
  final int payloadOffset;
  final int payloadLength;
  final bool fin;
  final int opcode;
  final bool masked;
  final int rsv;

  const WsFrameSpan({
    required this.offset,
    required this.length,
    required this.payloadOffset,
    required this.payloadLength,
    required this.fin,
    required this.opcode,
    required this.masked,
    required this.rsv,
  });

  /// 该帧的原始字节（未改动的完整帧，含头部）
  Uint8List bytesOf(Uint8List source) =>
      Uint8List.sublistView(source, offset, offset + length);

  /// 帧内容（解码失败按 latin1 兜底，保证二进制帧也能参与匹配）
  String payloadOf(Uint8List source) {
    final bytes = Uint8List.sublistView(source, payloadOffset, payloadOffset + payloadLength);
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  /// 能不能安全地改写内容：
  /// 分片帧（opcode 0x00）、控制帧（0x08~0x0a）以及被压缩的帧（有 RSV 位）都跳过，
  /// 只改「独立的、未压缩的数据帧」。
  bool get rewritable =>
      fin && rsv == 0 && (opcode == 0x01 || opcode == 0x02);

  bool get isControlFrame => opcode >= 0x08;
}

/// 帧编码器：把改动后的内容重新拼成一个合法的帧。
class WsFrameEncoder {
  static final Random _random = Random();

  /// 按 RFC 6455 编码一个帧。客户端→服务端方向必须带掩码。
  static Uint8List encode({
    required int opcode,
    required List<int> payload,
    required bool masked,
    bool fin = true,
  }) {
    final builder = BytesBuilder();
    builder.addByte((fin ? 0x80 : 0x00) | (opcode & 0x0f));

    final length = payload.length;
    final maskFlag = masked ? 0x80 : 0x00;
    if (length < 126) {
      builder.addByte(maskFlag | length);
    } else if (length <= 0xffff) {
      builder.addByte(maskFlag | 126);
      builder.addByte((length >> 8) & 0xff);
      builder.addByte(length & 0xff);
    } else {
      builder.addByte(maskFlag | 127);
      for (var i = 7; i >= 0; i--) {
        builder.addByte((length >> (8 * i)) & 0xff);
      }
    }

    if (masked) {
      final key = _random.nextInt(0x100000000);
      builder.add([
        (key >> 24) & 0xff,
        (key >> 16) & 0xff,
        (key >> 8) & 0xff,
        key & 0xff,
      ]);
      for (var i = 0; i < length; i++) {
        builder.addByte(payload[i] ^ ((key >> (8 * (3 - i % 4))) & 0xff));
      }
    } else {
      builder.add(payload);
    }

    return builder.toBytes();
  }
}

/// 单帧的处置结果
class WsFrameDecision {
  final WsFrameAction action;
  final String? replacement;
  final int delayMs;

  const WsFrameDecision(this.action, {this.replacement, this.delayMs = 0});

  static const WsFrameDecision allow = WsFrameDecision(WsFrameAction.observe);
}

/// 把规则作用到一段字节上，产出真正要转发出去的字节序列。
class WsFrameInterceptor {
  /// 返回需要写给对端的字节片段列表：
  /// - 空列表 = 该段被规则全部丢弃
  /// - 只有一段且与入参同一实例 = 未做任何改动（走原来的转发路径）
  static Future<List<Uint8List>> apply({
    required Uint8List msg,
    required List<WebSocketRule> rules,
    required bool isFromClient,
  }) async {
    if (msg.isEmpty || rules.isEmpty) {
      return [msg];
    }

    final spans = WsFrameScanner.scan(msg);
    if (spans.isEmpty) {
      return [msg];
    }

    final out = <Uint8List>[];
    var cursor = 0;
    var changed = false;

    for (final span in spans) {
      // 帧与帧之间不应该有间隙，出现间隙说明扫描结果跟真实字节流对不上，整体放弃干预
      if (span.offset != cursor) {
        return [msg];
      }

      final decision = _decide(rules, span, msg);
      switch (decision.action) {
        case WsFrameAction.observe:
          out.add(span.bytesOf(msg));
          break;

        case WsFrameAction.drop:
          changed = true;
          break;

        case WsFrameAction.delay:
          final delay = decision.delayMs;
          if (delay > 0) {
            await Future.delayed(Duration(milliseconds: delay));
          }
          out.add(span.bytesOf(msg));
          break;

        case WsFrameAction.duplicate:
          out.add(span.bytesOf(msg));
          out.add(span.bytesOf(msg));
          changed = true;
          break;

        case WsFrameAction.rewrite:
          if (!span.rewritable) {
            // 分片帧/压缩帧/控制帧不改内容，原样放行
            out.add(span.bytesOf(msg));
            break;
          }
          final payload = utf8.encode(decision.replacement ?? '');
          out.add(WsFrameEncoder.encode(
            opcode: span.opcode,
            payload: payload,
            masked: isFromClient,
          ));
          changed = true;
          break;
      }

      cursor = span.offset + span.length;
    }

    // 尾部可能还留着半截帧，原样带上，交给下一次 read 拼
    if (cursor < msg.length) {
      out.add(Uint8List.sublistView(msg, cursor));
    }

    return changed ? out : [msg];
  }

  static WsFrameDecision _decide(List<WebSocketRule> rules, WsFrameSpan span, Uint8List msg) {
    for (final rule in rules) {
      if (!rule.enabled || rule.action == WsFrameAction.observe) continue;
      // 控制帧默认不参与内容匹配，除非规则没写内容条件
      if (span.isControlFrame && (rule.payloadPattern?.isNotEmpty ?? false)) continue;
      if (!rule.matchesPayload(span.payloadOf(msg))) continue;
      return WsFrameDecision(rule.action, replacement: rule.replacement, delayMs: rule.delayMs);
    }
    return WsFrameDecision.allow;
  }
}
