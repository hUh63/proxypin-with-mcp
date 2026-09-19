import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';

///请求和响应事件监听
abstract class EventListener {
  void onRequest(Channel channel, HttpRequest request);

  void onResponse(ChannelContext channelContext, HttpResponse response);

  void onMessage(Channel channel, HttpMessage message, WebSocketFrame frame) {}
}


class CombinedEventListener extends EventListener {
  final List<EventListener> listeners;

  /// 停止抓包后置为 true：此后到达的事件一律丢弃（上游 #674）。
  ///
  /// 关闭监听/连接是主动动作，但已进入队列的读事件、握手/转发中的回调仍可能
  /// 触发一次；这道闸确保"停止"之后界面不再被这些残留事件更新。
  bool stopped = false;

  CombinedEventListener(this.listeners);

  @override
  void onRequest(Channel channel, HttpRequest request) {
    if (stopped) return;
    for (var element in listeners) {
      element.onRequest(channel, request);
    }
  }

  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) {
    if (stopped) return;
    for (var element in listeners) {
      element.onResponse(channelContext, response);
    }
  }

  @override
  void onMessage(Channel channel, HttpMessage message, WebSocketFrame frame) {
    if (stopped) return;
    for (var element in listeners) {
      element.onMessage(channel, message, frame);
    }
  }
}
