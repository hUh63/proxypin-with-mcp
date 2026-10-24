import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/mqtt/mqtt_packet.dart';

/// 组装一个 PUBLISH(QoS0) 报文：0x30 + remaining length + topic + payload
List<int> _publish(String topic, List<int> payload) {
  final topicBytes = topic.codeUnits;
  final body = <int>[..._u16(topicBytes.length), ...topicBytes, ...payload];
  return <int>[0x30, ..._remainingLength(body.length), ...body];
}

List<int> _u16(int v) => [v >> 8 & 0xff, v & 0xff];

/// MQTT 变长编码：每 7 位一段，低 7 位在前，末字节最高位 0
List<int> _remainingLength(int length) {
  final out = <int>[];
  var value = length;
  do {
    var digit = value % 128;
    value ~/= 128;
    if (value > 0) digit |= 0x80;
    out.add(digit);
  } while (value > 0);
  return out;
}

void main() {
  group('MqttPacketFramer', () {
    test('单字节分片也能攒出完整报文', () {
      final packetBytes = _publish('a/b', [1, 2, 3]);
      final framer = MqttPacketFramer(true);
      final packets = <MqttPacket>[];
      for (final byte in packetBytes) {
        packets.addAll(framer.add([byte]));
      }
      expect(packets.length, 1);
      expect(packets.first.topic, 'a/b');
      expect(packets.first.bytes, packetBytes);
      expect(packets.first.fromClient, isTrue);
    });

    test('同一块里连续多个报文按顺序产出', () {
      final a = _publish('t1', [1]);
      final b = <int>[0xc0, 0x00]; // PINGREQ
      final c = _publish('t2', [2, 3]);
      final framer = MqttPacketFramer(false);
      final packets = framer.add([...a, ...b, ...c]);
      expect(packets.length, 3);
      expect(packets[0].topic, 't1');
      expect(packets[1].typeName, 'PINGREQ');
      expect(packets[1].remainingLength, 0);
      expect(packets[2].topic, 't2');
      expect(packets.every((p) => !p.fromClient), isTrue);
    });

    test('尾巴上不完整的报文留到下次继续', () {
      final a = _publish('topic', [9, 9, 9]);
      final framer = MqttPacketFramer(true);
      final first = framer.add(a.sublist(0, a.length - 1));
      expect(first, isEmpty);
      final second = framer.add(a.sublist(a.length - 1));
      expect(second.length, 1);
      expect(second.first.bytes, a);
    });

    test('remaining length 超过四字节直接报错（不静默吃字节）', () {
      final framer = MqttPacketFramer(true);
      expect(() => framer.add([0x30, 0xff, 0xff, 0xff, 0xff, 0xff]),
          throwsA(isA<FormatException>()));
    });

    test('超过抓包上限的报文被跳过，后续报文仍能解析', () {
      // 声明一个 8MB 的 PUBLISH（超过 4MB 上限），随后紧跟一个 PINGREQ
      final hugeLength = 8 * 1024 * 1024;
      final big = _publish('big', List<int>.filled(hugeLength - 9, 0));
      final ping = <int>[0xc0, 0x00];
      final framer = MqttPacketFramer(true);
      final first = framer.add(big);
      expect(first, isEmpty);
      final second = framer.add(ping);
      expect(second.length, 1);
      expect(second.first.typeName, 'PINGREQ');
    });

    test('大报文一次到达时可以抓下来（4MB 以内）', () {
      final payload = List<int>.filled(1024 * 1024, 7);
      final packetBytes = _publish('big/topic', payload);
      final framer = MqttPacketFramer(false);
      final packets = framer.add(packetBytes);
      expect(packets.length, 1);
      expect(packets.first.remainingLength, packetBytes.length - packets.first.headerLength);
      expect(packets.first.topic, 'big/topic');
    });
  });

  group('MqttPacket.fromBytes', () {
    test('解析已完成的报文', () {
      final bytes = _publish('x', [0x41]);
      final packet = MqttPacket.fromBytes(Uint8List.fromList(bytes), true);
      expect(packet.typeName, 'PUBLISH');
      expect(packet.topic, 'x');
    });

    test('长度不符时报「不完整」', () {
      final bytes = _publish('x', [0x41]);
      expect(() => MqttPacket.fromBytes(Uint8List.fromList(bytes.sublist(1)), true),
          throwsA(isA<FormatException>()));
    });
  });
}
