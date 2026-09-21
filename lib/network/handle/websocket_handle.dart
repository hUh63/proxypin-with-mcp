import 'dart:async';
import 'dart:typed_data';

import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/components/manager/script_manager.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/rules/websocket_rule.dart';
import 'package:proxypin/network/rules/websocket_rule_manager.dart';
import 'package:proxypin/network/util/ws_frame_rules.dart';
import 'package:proxypin/network/util/logger.dart';

/// websocket处理器
class WebSocketChannelHandler extends ChannelHandler<Uint8List> {
  final WebSocketDecoder decoder = WebSocketDecoder();

  final Channel proxyChannel;
  final HttpMessage message;

  WebSocketChannelHandler(this.proxyChannel, this.message);

  @override
  Future<void> channelRead(ChannelContext channelContext, Channel channel, Uint8List msg) async {
    await _forward(channelContext, msg);

    // A single TCP read may carry multiple WebSocket frames (Nagle, TLS record
    // batching, OS coalescing). Drain the decoder until no more full frames
    // remain in its buffer; subsequent iterations pass empty bytes so we only
    // consume what is already buffered.
    Uint8List chunk = msg;
    while (true) {
      WebSocketFrame? frame;
      try {
        frame = decoder.decode(chunk);
      } catch (e, stackTrace) {
        log.e("websocket decode error", error: e, stackTrace: stackTrace);
        break;
      }
      if (frame == null) {
        break;
      }
      frame.isFromClient = message is HttpRequest;

      message.messages.add(frame);
      channelContext.listener?.onMessage(channel, message, frame);

      // 上游 #722：让脚本能捕获 WebSocket 帧（只读派发，异步执行，不影响转发字节）
      final scriptManager = ScriptManager.instanceOrNull;
      if (scriptManager != null && scriptManager.enabled) {
        unawaited(scriptManager.dispatchWebSocketFrame(message, frame));
      }

      logger.d(
          "[${channelContext.clientChannel?.id}] websocket channelRead ${frame.payloadLength} ${frame.fin} ${frame.payloadDataAsString}");

      chunk = _empty;
    }
  }

  /// 转发一段字节。
  ///
  /// 上游 #839 FR1：只在“该方向有生效的帧级规则”时才走帧级处置，
  /// 否则与改造前逐字节一致（直接原样转发）。
  Future<void> _forward(ChannelContext channelContext, Uint8List msg) async {
    final rules = _activeRules();
    if (rules.isEmpty) {
      proxyChannel.writeBytes(msg);
      return;
    }

    final List<Uint8List> segments;
    try {
      segments = await WsFrameInterceptor.apply(
        msg: msg,
        rules: rules,
        isFromClient: message is HttpRequest,
      );
    } catch (e, stackTrace) {
      // 帧级处置出错时回退到原样转发，绝不能因为拦截失败而丢包
      logger.e("websocket frame rule error, forward raw", error: e, stackTrace: stackTrace);
      proxyChannel.writeBytes(msg);
      return;
    }

    if (segments.isEmpty) {
      logger.d("[ws] ${msg.length} bytes dropped by rule");
      return;
    }
    for (final segment in segments) {
      proxyChannel.writeBytes(segment);
    }
  }

  /// 取当前方向上真正会改动字节的规则；没有则返回空表。
  List<WebSocketRule> _activeRules() {
    final manager = WebSocketRuleManager();
    if (!manager.globalEnabled) return const [];
    final rules = manager.getMatchingRules(message.uri);
    if (rules.isEmpty) return const [];
    final fromClient = message is HttpRequest;
    return rules.where((rule) {
      if (!rule.enabled || rule.action == WsFrameAction.observe) return false;
      return fromClient ? rule.interceptOutgoing : rule.interceptIncoming;
    }).toList();
  }

  static final Uint8List _empty = Uint8List(0);
}
