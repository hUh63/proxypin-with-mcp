// HPACK 动态表大小更新的边界：对端可以是我们完全不信任的服务器，
// 一个巨大的 size update 就足以让解码表无界增长（内存耗尽）。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/http/h2/hpack/hpack.dart';

/// 把一个整数按 HPACK 的「5 位前缀 + 变长整数」编码成字节。
List<int> sizeUpdate(int value) {
  final out = <int>[];
  if (value < 31) {
    out.add(0x20 | value);
    return out;
  }
  out.add(0x3f);
  var v = value - 31;
  while (true) {
    var b = v & 0x7f;
    v >>= 7;
    if (v > 0) {
      b |= 0x80;
      out.add(b);
    } else {
      out.add(b);
      break;
    }
  }
  return out;
}

void main() {
  test('sizeUpdate 编码与预期一致（自测用）', () {
    expect(sizeUpdate(0), [0x20]);
    expect(sizeUpdate(4096), [0x3f, 0xe1, 0x1f]);
    expect(sizeUpdate(20000), [0x3f, 0x81, 0x9c, 0x01]);
  });

  test('范围内的 size update 正常解码', () {
    final dec = HPackDecoder();
    expect(() => dec.decode(sizeUpdate(0)), returnsNormally);
    expect(() => dec.decode(sizeUpdate(4096)), returnsNormally);
    expect(() => dec.decode(sizeUpdate(HPackDecoder.hardMaxTableSize)),
        returnsNormally);
  });

  test('超过硬上限的 size update 会被拒绝（防内存耗尽）', () {
    final dec = HPackDecoder();
    expect(
        () => dec.decode(sizeUpdate(HPackDecoder.hardMaxTableSize + 1)),
        throwsA(isA<HPackDecodingException>()));
    expect(() => dec.decode(sizeUpdate(20000)),
        throwsA(isA<HPackDecodingException>()));
    // 2^30 这种量级也不能通过（变长整数没有长度上限）
    expect(() => dec.decode(sizeUpdate(1 << 30)),
        throwsA(isA<HPackDecodingException>()));
  });

  test('被拒绝后解码器仍可用（异常不会留下半截状态）', () {
    final dec = HPackDecoder();
    expect(() => dec.decode(sizeUpdate(20000)),
        throwsA(isA<HPackDecodingException>()));
    expect(() => dec.decode(sizeUpdate(1024)), returnsNormally);
  });

  test('updateMaxReceivingHeaderTableSize 只记录、不放大硬上限', () {
    final dec = HPackDecoder();
    // 对端若声明 64KB，不能因此让我们接受 64KB 的表
    dec.updateMaxReceivingHeaderTableSize(65536);
    expect(() => dec.decode(sizeUpdate(32768)),
        throwsA(isA<HPackDecodingException>()));
  });
}
