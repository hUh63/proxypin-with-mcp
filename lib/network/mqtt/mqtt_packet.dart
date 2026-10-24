import 'dart:convert';
import 'dart:typed_data';

import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';

/// A complete MQTT control packet. The wire bytes are retained unchanged.
class MqttPacket {
  static const typeNames = [
    'RESERVED',
    'CONNECT',
    'CONNACK',
    'PUBLISH',
    'PUBACK',
    'PUBREC',
    'PUBREL',
    'PUBCOMP',
    'SUBSCRIBE',
    'SUBACK',
    'UNSUBSCRIBE',
    'UNSUBACK',
    'PINGREQ',
    'PINGRESP',
    'DISCONNECT',
    'AUTH',
  ];

  final Uint8List bytes;
  final bool fromClient;
  final int headerLength;
  final int remainingLength;

  MqttPacket(
    this.bytes,
    this.fromClient,
    this.headerLength,
    this.remainingLength,
  );

  /// Decode one already framed packet, such as a packet loaded from history.
  factory MqttPacket.fromBytes(Uint8List bytes, bool fromClient) {
    if (bytes.length < 2) throw const FormatException('Short MQTT packet');
    var index = 1;
    var multiplier = 1;
    var remaining = 0;
    while (true) {
      if (index >= bytes.length || index > 4) {
        throw const FormatException('Invalid MQTT remaining length');
      }
      final digit = bytes[index++];
      remaining += (digit & 0x7f) * multiplier;
      if ((digit & 0x80) == 0) break;
      multiplier *= 128;
    }
    if (index + remaining != bytes.length) {
      throw const FormatException('Incomplete MQTT packet');
    }
    return MqttPacket(bytes, fromClient, index, remaining);
  }

  int get type => bytes[0] >> 4;
  int get flags => bytes[0] & 0x0f;
  String get typeName => typeNames[type];
  String get direction => fromClient ? 'client-to-server' : 'server-to-client';

  int? get packetId {
    final offset = headerLength + (type == 3 ? 2 + (topicBytes?.length ?? 0) : 0);
    if (type == 3 && ((flags >> 1) & 3) == 0) return null;
    if (type != 3 && !{4, 5, 6, 7, 8, 9, 10, 11}.contains(type)) return null;
    if (offset + 2 > bytes.length) return null;
    return (bytes[offset] << 8) | bytes[offset + 1];
  }

  Uint8List? get topicBytes {
    if (type != 3 || headerLength + 2 > bytes.length) return null;
    final length = (bytes[headerLength] << 8) | bytes[headerLength + 1];
    final start = headerLength + 2;
    if (start + length > bytes.length) return null;
    return Uint8List.sublistView(bytes, start, start + length);
  }

  String? get topic {
    final raw = topicBytes;
    if (raw == null) return null;
    return utf8.decode(raw, allowMalformed: true);
  }

  int? get connackCode => type == 2 && remainingLength >= 2 ? bytes[headerLength + 1] : null;

  WebSocketFrame toMessage() => WebSocketFrame(
        fin: true,
        opcode: 2,
        mask: false,
        payloadLength: bytes.length,
        maskingKey: 0,
        payloadData: bytes,
      )..isFromClient = fromClient;

  /// One display record represents the MQTT connection. Packets are stored in
  /// its messages list, using the same history container as WebSocket frames.
  static HttpRequest connectionRecord(HostAndPort remote) {
    final host = remote.host.contains(':') && !remote.host.startsWith('[') ? '[${remote.host}]' : remote.host;
    final request = HttpRequest(
      HttpMethod.mqtt,
      'mqtts://$host:${remote.port}',
      protocolVersion: 'MQTT',
    )..hostAndPort = remote;
    return request;
  }
}

/// Stream framing is independent of socket chunk boundaries. Oversized packets
/// are forwarded by the relay but skipped here to bound capture memory.
class MqttPacketFramer {
  static const maxCapturedPacketLength = 4 * 1024 * 1024;
  final bool fromClient;
  final List<int> _pending = [];
  int _skipRemaining = 0;

  /// 头部解析完成后已知的整包长度（含固定头部）；-1 表示还没收齐头部。
  ///
  /// 旧实现每加入一个字节就把 remaining length 整体重算一遍，一个 4MB 的
  /// PUBLISH 会做上千万次循环。现在只在头部阶段逐字节累积，之后按已知长度
  /// 批量拷贝。
  int _expectedLength = -1;
  int _headerLength = 0;

  MqttPacketFramer(this.fromClient);

  List<MqttPacket> add(List<int> chunk) {
    final packets = <MqttPacket>[];
    var offset = 0;
    while (offset < chunk.length) {
      if (_skipRemaining > 0) {
        final skipped = _skipRemaining < chunk.length - offset ? _skipRemaining : chunk.length - offset;
        _skipRemaining -= skipped;
        offset += skipped;
        continue;
      }

      // 头部阶段：逐字节累积，直到 remaining length 的续位结束
      if (_expectedLength < 0) {
        _pending.add(chunk[offset++]);
        if (_pending.length < 2) continue;

        var multiplier = 1;
        var remaining = 0;
        var index = 1;
        while (index < _pending.length && index <= 4) {
          final digit = _pending[index];
          remaining += (digit & 0x7f) * multiplier;
          index++;
          if ((digit & 0x80) == 0) break;
          multiplier *= 128;
        }
        if ((_pending[index - 1] & 0x80) != 0) {
          if (index == 5) {
            throw const FormatException(
              'MQTT remaining length exceeds four bytes',
            );
          }
          continue;
        }

        _headerLength = index;
        _expectedLength = index + remaining;
        if (_expectedLength > maxCapturedPacketLength) {
          // 超大报文：只转发不抓包，跳过剩余字节（内存有界）
          _skipRemaining = _expectedLength - _pending.length;
          _pending.clear();
          _expectedLength = -1;
          continue;
        }
        if (_pending.length == _expectedLength) {
          packets.add(MqttPacket(
            Uint8List.fromList(_pending),
            fromClient,
            _headerLength,
            _expectedLength - _headerLength,
          ));
          _pending.clear();
          _expectedLength = -1;
        }
        continue;
      }

      // 已知整包长度：一次拷贝够用多少就拷多少
      final need = _expectedLength - _pending.length;
      final available = chunk.length - offset;
      if (need > available) {
        _pending.addAll(chunk.sublist(offset));
        offset = chunk.length;
        continue;
      }
      _pending.addAll(chunk.sublist(offset, offset + need));
      offset += need;
      packets.add(MqttPacket(
        Uint8List.fromList(_pending),
        fromClient,
        _headerLength,
        _expectedLength - _headerLength,
      ));
      _pending.clear();
      _expectedLength = -1;
    }
    return packets;
  }
}
