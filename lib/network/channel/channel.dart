/*
 * Copyright 2023 Hongen Wang All rights reserved.
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

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/channel/host_port.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/util/mtls.dart';
import 'package:proxypin/network/util/socket_address.dart';

import 'channel_dispatcher.dart';

///处理I/O事件或截获I/O操作
///[T] 读取的数据类型
///@author wanghongen
abstract class ChannelHandler<T> {
  var log = logger;

  ///连接建立
  void channelActive(ChannelContext context, Channel channel) {}

  ///读取数据事件
  Future<void> channelRead(
    ChannelContext channelContext,
    Channel channel,
    T msg,
  ) async {}

  ///连接断开
  void channelInactive(ChannelContext channelContext, Channel channel) {
    //log.i("[${channel.id}] close $channel");
  }

  void exceptionCaught(
    ChannelContext channelContext,
    Channel channel,
    dynamic error, {
    StackTrace? trace,
  }) {
    HostAndPort? host = channelContext.host;
    log.e(
      "[${channel.id}] exceptionCaught $host $channel",
      error: error,
      stackTrace: trace,
    );
    channel.close();
  }
}

///与网络套接字或组件的连接，能够进行读、写、连接和绑定等I/O操作。
class Channel {
  final int _id;
  final ChannelDispatcher dispatcher = ChannelDispatcher();
  Socket _socket;

  //是否打开
  bool isOpen = true;

  //此通道连接到的远程地址
  final InetSocketAddress remoteSocketAddress;

  //是否写入中
  bool isWriting = false;

  //待写队列：Socket.add 在 dart:io 中是同步排队的，
  //用 FIFO 队列替代原来的忙等轮询，避免高并发下 writeBytes 互相阻塞。
  final Queue<List<int>> _writeQueue = Queue();
  bool _draining = false;

  Object? error; //异常
  //是否使用代理
  bool useProxy = false;

  /// socket 读订阅。关闭通道时一并取消——否则（如"停止抓包"后）残留连接仍会
  /// 触发读回调、继续解析与转发，表现为"停止后仍在处理流量"。
  StreamSubscription<Uint8List>? _socketSubscription;

  /// 记录本通道的 socket 读订阅（由 [Network.listen] / [ChannelDispatcher.listen] 注册）。
  ///
  /// 只记录、不取消上一个订阅：TLS 升级会用安全套接字重新 `listen`，
  /// 对已被 `SecureSocket.secureServer` 接管的旧订阅执行 cancel 有中断连接的风险。
  /// 关闭通道时只取消**当前**订阅即可满足"停止后不再处理数据"。
  void attachSocketSubscription(StreamSubscription<Uint8List> subscription) {
    _socketSubscription = subscription;
  }

  Channel(this._socket)
    : _id = DateTime.now().millisecondsSinceEpoch + Random().nextInt(999999),
      remoteSocketAddress = InetSocketAddress(
        _socket.remoteAddress,
        _socket.remotePort,
      );

  ///返回此channel的全局唯一标识符。
  String get id => _id.toRadixString(36);

  Socket get socket => _socket;

  void serverSecureSocket(
    SecureSocket secureSocket,
    ChannelContext channelContext,
  ) {
    _socket = secureSocket;
    _socket.done.then((value) => isOpen = false);
    dispatcher.listen(this, channelContext);
  }

  //向远程发起ssl连接
  Future<SecureSocket> secureSocket(
    ChannelContext channelContext, {
    String? host,
    List<String>? supportedProtocols,
  }) async {
    SecureSocket secureSocket = await SecureSocket.secure(
      socket,
      host: host,
      supportedProtocols: supportedProtocols,
      context: Mtls.securityContext,
      onBadCertificate: (certificate) => true,
    );

    _socket = secureSocket;
    _socket.done.then((value) => isOpen = false);
    dispatcher.listen(this, channelContext);

    return secureSocket;
  }

  Future<SecureSocket> startSecureSocket(
    ChannelContext channelContext, {
    String? host,
    List<String>? supportedProtocols,
  }) async {
    SecureSocket secureSocket = await SecureSocket.secure(
      socket,
      host: host,
      supportedProtocols: supportedProtocols,
      context: Mtls.securityContext,
      onBadCertificate: (certificate) => true,
    );

    _socket = secureSocket;
    _socket.done.then((value) => isOpen = false);
    return secureSocket;
  }

  void listen(ChannelContext channelContext) {
    dispatcher.listen(this, channelContext);
  }

  String? get selectedProtocol =>
      isSsl && isOpen ? (_socket as SecureSocket).selectedProtocol : null;

  ///是否是ssl链接
  bool get isSsl => _socket is SecureSocket;

  ///远程服务器证书(仅ssl链接有效)
  X509Certificate? get peerCertificate => _socket is SecureSocket
      ? (_socket as SecureSocket).peerCertificate
      : null;

  Future<void> write(ChannelContext channelContext, Object obj) async {
    var data = dispatcher.encoder.encode(channelContext, obj);
    await writeBytes(data);
  }

  Future<void> writeBytes(List<int> bytes) async {
    if (isClosed) {
      logger.w(
        "[$id] $remoteSocketAddress channel is closed",
        stackTrace: StackTrace.current,
      );
      return;
    }

    // Socket.add 内部同步排队，按到达顺序写入即可，无需等待前一次写完。
    // 只在同一事件循环内串行排空，避免无界增长。
    _writeQueue.add(bytes);
    if (_draining) return;
    _draining = true;
    try {
      while (_writeQueue.isNotEmpty) {
        final chunk = _writeQueue.removeFirst();
        if (!isClosed) {
          _socket.add(chunk);
        }
      }
    } catch (e, t) {
      if (e is StateError && e.message == "StreamSink is closed") {
        logger.w(
          "[$id] $remoteSocketAddress write error channel is closed $e",
          stackTrace: t,
        );
      } else {
        logger.e("[$id] write error", error: e, stackTrace: t);
      }
    } finally {
      _draining = false;
    }
  }

  ///写入并关闭此channel
  Future<void> writeAndClose(ChannelContext channelContext, Object obj) async {
    await write(channelContext, obj);
    close();
  }

  ///关闭此channel
  void close() async {
    if (isClosed) {
      return;
    }

    isOpen = false;
    // 先取消读订阅，确保不会再收到数据事件
    _socketSubscription?.cancel();
    _socketSubscription = null;
    await _socket.close();
  }

  ///返回此channel是否打开
  bool get isClosed => !isOpen;

  @override
  String toString() {
    return 'Channel($id $remoteSocketAddress';
  }
}
