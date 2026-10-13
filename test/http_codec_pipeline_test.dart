/*
 * HTTP/1.1 pipelining 的编解码层单测。
 *
 * 背景：客户端可以把多个请求合并到同一次 TCP 写入。此时 `ChannelDispatcher`
 * 一次读入的 buffer 里会有多条消息，`HttpCodec.decode` 必须逐条解析、且
 * **不能把后续消息的字节当成当前消息的 body 吃掉**。
 *
 * 早前的实现用 `data.readAvailableBytes()` 取走全部可读字节，`BodyReader`
 * 又无条件把它们并入 body，导致第一个请求吞掉后面所有请求的字节，
 * 上层 `clearRead()` 再一并丢弃 —— 表现为「同一连接只有第一个请求被处理」。
 *
 * 这里用纯 codec 单测锁定修复，不依赖 socket。
 */
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/codec.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/byte_buf.dart';

void main() {
  test('pipelining：同一次缓冲里解析两个带 body 的 POST', () {
    final codec = HttpRequestCodec();
    final ctx = ChannelContext();
    final buf = ByteBuf();
    buf.add(latin1.encode('POST /a HTTP/1.1\r\nHost: h\r\nContent-Length: 3\r\n\r\nAAA'
        'POST /b HTTP/1.1\r\nHost: h\r\nContent-Length: 4\r\n\r\nBBBB'));

    final r1 = codec.decode(ctx, buf);
    expect(r1.isDone, isTrue, reason: '第 1 个请求应解析完成');
    expect((r1.data as HttpRequest).uri, '/a');
    expect(utf8.decode(r1.data!.body!), 'AAA', reason: 'body 必须只含属于本条消息的字节');
    expect(buf.isReadable(), isTrue, reason: '第 2 个请求的字节必须保留在 buffer 里');

    final r2 = codec.decode(ctx, buf);
    expect(r2.isDone, isTrue, reason: '第 2 个请求应解析完成');
    expect((r2.data as HttpRequest).uri, '/b');
    expect(utf8.decode(r2.data!.body!), 'BBBB');
    expect(buf.isReadable(), isFalse, reason: '全部消费后 buffer 应为空');
  });

  test('pipelining：无 body 的 GET 后紧跟第二个请求', () {
    final codec = HttpRequestCodec();
    final ctx = ChannelContext();
    final buf = ByteBuf();
    buf.add(latin1.encode('GET /a HTTP/1.1\r\nHost: h\r\n\r\n'
        'GET /b HTTP/1.1\r\nHost: h\r\n\r\n'));

    final r1 = codec.decode(ctx, buf);
    expect(r1.isDone, isTrue);
    expect((r1.data as HttpRequest).uri, '/a');
    expect(buf.isReadable(), isTrue, reason: '无 body 时不得消费后续请求的字节');

    final r2 = codec.decode(ctx, buf);
    expect(r2.isDone, isTrue);
    expect((r2.data as HttpRequest).uri, '/b');
  });

  test('body 分两次到达：第一次不足时不得消费后续（跨读事件累积）', () {
    final codec = HttpRequestCodec();
    final ctx = ChannelContext();
    final buf = ByteBuf();
    buf.add(latin1.encode('POST /a HTTP/1.1\r\nHost: h\r\nContent-Length: 6\r\n\r\nabc'));

    final r1 = codec.decode(ctx, buf);
    expect(r1.isDone, isFalse, reason: 'body 未到齐时应继续等待');

    buf.add(latin1.encode('def'));
    final r2 = codec.decode(ctx, buf);
    expect(r2.isDone, isTrue);
    expect(utf8.decode(r2.data!.body!), 'abcdef');
  });
}
