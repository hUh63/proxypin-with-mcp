/*
 * SOCKS5 上游代理握手（RFC 1928 + RFC 1929 用户名/口令认证）
 *
 * 上游 #825：此前「外部代理」仅支持 HTTP 代理（发 HTTP CONNECT）；这里补齐 SOCKS5，
 * 与既有的 HTTP 代理路径并存——由 [ProxyInfo.protocol] 选择，默认 http，行为不变。
 *
 * 流程：在已与代理建立 TCP 连接的通道上依次完成
 *   1) 方法协商      -> 05 NMETHODS METHODS
 *   2) 用户名/口令    -> 01 ULEN UNAME PLEN PASSWD（仅当代理选择 0x02）
 *   3) CONNECT 请求  -> 05 01 00 ATYP ADDR PORT
 * 期间使用 [RawCodec] 直接收发原始字节，完成后恢复原有解码器/处理器。
 */
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/channel_dispatcher.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/util/logger.dart';

class Socks5Connect {
  /// 在已连接代理服务器的 [channel] 上完成 SOCKS5 握手，建立到 [target] 的隧道。
  /// 失败抛出 [Exception]（含代理返回的错误码说明）。
  static Future<void> handshake(
      ChannelContext channelContext, HostAndPort target, Channel channel, ProxyInfo proxy) async {
    final oldDecoder = channel.dispatcher.decoder;
    final oldEncoder = channel.dispatcher.encoder;
    final oldHandler = channel.dispatcher.handler;

    final session = _Socks5Session(proxy, target);
    channel.dispatcher.channelHandle(RawCodec(), session);
    try {
      // 1) 方法协商：优先无认证；配置了用户名口令时一并声明
      final methods = proxy.isAuthenticated ? <int>[0x00, 0x02] : <int>[0x00];
      await channel.writeBytes([0x05, methods.length, ...methods]);
      await session.done.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw Exception('SOCKS5 握手超时（代理未响应）');
    } finally {
      channel.dispatcher.handle(oldDecoder, oldEncoder, oldHandler);
    }

    // 握手响应后若代理已开始回传数据（罕见），交回分发器按新的处理器继续处理，避免丢包
    if (session.remaining.isNotEmpty) {
      final leftover = Uint8List.fromList(session.remaining);
      session.remaining.clear();
      logger.d('SOCKS5 握手完成后残余 ${leftover.length} 字节，交回分发器处理');
      unawaited(channel.dispatcher.channelRead(channelContext, channel, leftover));
    }
  }
}

class _Socks5Session extends ChannelHandler<Uint8List> {
  _Socks5Session(this.proxy, this.target);

  final ProxyInfo proxy;
  final HostAndPort target;

  final Completer<void> done = Completer<void>();
  final List<int> remaining = [];

  /// 0=等方法响应 1=等认证响应 2=等 CONNECT 响应 3=完成
  int _stage = 0;
  bool _failed = false;

  @override
  Future<void> channelRead(ChannelContext channelContext, Channel channel, Uint8List msg) async {
    if (_failed || done.isCompleted) {
      remaining.addAll(msg);
      return;
    }
    remaining.addAll(msg);
    _advance(channel);
  }

  void _advance(Channel channel) {
    while (!done.isCompleted && !_failed) {
      switch (_stage) {
        case 0:
          if (remaining.length < 2) return;
          final version = remaining[0];
          final method = remaining[1];
          _consume(2);
          if (version != 0x05) {
            return _fail('代理返回了不支持的 SOCKS 版本 0x${version.toRadixString(16)}');
          }
          if (method == 0xFF) {
            return _fail('代理拒绝了所有可用的认证方式');
          }
          if (method == 0x02) {
            _sendAuth(channel);
            _stage = 1;
          } else {
            _sendConnect(channel);
            _stage = 2;
          }
          break;
        case 1:
          if (remaining.length < 2) return;
          final status = remaining[1];
          _consume(2);
          if (status != 0x00) {
            return _fail('用户名/口令认证被拒绝');
          }
          _sendConnect(channel);
          _stage = 2;
          break;
        case 2:
          if (remaining.length < 4) return;
          final code = remaining[1];
          final atyp = remaining[3];
          int need;
          if (atyp == 0x01) {
            need = 10; // 4 + IPv4(4) + PORT(2)
          } else if (atyp == 0x04) {
            need = 22; // 4 + IPv6(16) + PORT(2)
          } else if (atyp == 0x03) {
            if (remaining.length < 5) return;
            need = 4 + 1 + remaining[4] + 2;
          } else {
            return _fail('代理返回未知地址类型 0x${atyp.toRadixString(16)}');
          }
          if (remaining.length < need) return;
          _consume(need);
          if (code != 0x00) {
            return _fail('代理无法连接目标地址（错误码 ${_codeText(code)}）');
          }
          _stage = 3;
          if (!done.isCompleted) done.complete();
          return;
        default:
          return;
      }
    }
  }

  /// 用户名/口令子协商（RFC 1929）
  void _sendAuth(Channel channel) {
    final user = utf8.encode(proxy.username ?? '');
    final pass = utf8.encode(proxy.password ?? '');
    final userLen = user.length > 255 ? 255 : user.length;
    final passLen = pass.length > 255 ? 255 : pass.length;
    channel.writeBytes([0x01, userLen, ...user.sublist(0, userLen), passLen, ...pass.sublist(0, passLen)]);
  }

  /// CONNECT 请求
  void _sendConnect(Channel channel) {
    final port = target.port ?? 0;
    channel.writeBytes([0x05, 0x01, 0x00, ..._encodeAddress(target.host), (port >> 8) & 0xff, port & 0xff]);
  }

  /// 目标地址编码：IPv4 / IPv6 二进制，否则按域名（长度前缀）
  List<int> _encodeAddress(String host) {
    final address = InternetAddress.tryParse(host);
    if (address != null) {
      if (address.type == InternetAddressType.IPv4) {
        return [0x01, ...address.rawAddress];
      }
      if (address.type == InternetAddressType.IPv6) {
        return [0x04, ...address.rawAddress];
      }
    }
    final domain = utf8.encode(host);
    final len = domain.length > 255 ? 255 : domain.length;
    return [0x03, len, ...domain.sublist(0, len)];
  }

  void _consume(int count) => remaining.removeRange(0, count);

  void _fail(String message) {
    _failed = true;
    if (!done.isCompleted) {
      done.completeError(Exception('SOCKS5 握手失败：$message'));
    }
  }

  String _codeText(int code) {
    switch (code) {
      case 0x01:
        return '1 通用失败';
      case 0x02:
        return '2 规则不允许';
      case 0x03:
        return '3 网络不可达';
      case 0x04:
        return '4 主机不可达';
      case 0x05:
        return '5 连接被拒绝';
      case 0x06:
        return '6 TTL 超时';
      case 0x07:
        return '7 命令不支持';
      case 0x08:
        return '8 地址类型不支持';
      default:
        return '$code';
    }
  }
}
