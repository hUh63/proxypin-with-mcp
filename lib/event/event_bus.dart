/*
 * 通用事件总线 - 独立于 MCP 的事件系统
 * 支持事件订阅、发布、过滤、历史记录
 */

import 'dart:async';
import 'dart:collection';

import 'package:proxypin/network/util/logger.dart';

/// 事件基类
abstract class AppEvent {
  final String type;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  AppEvent(this.type, {this.data = const {}}) : timestamp = DateTime.now();

  Map<String, dynamic> toJson() => {
        'type': type,
        'timestamp': timestamp.toIso8601String(),
        'data': data,
      };
}

/// HTTP 请求事件
class HttpRequestEvent extends AppEvent {
  HttpRequestEvent({
    required String url,
    required String method,
    int? statusCode,
    Duration? responseTime,
    Map<String, String>? headers,
  }) : super('http_request', data: {
          'url': url,
          'method': method,
          'statusCode': statusCode,
          'responseTime': responseTime?.inMilliseconds,
          'headers': headers,
        });

  String get url => data['url'] as String;
  String get method => data['method'] as String;
  int? get statusCode => data['statusCode'] as int?;
  int? get responseTimeMs => data['responseTime'] as int?;
}

/// 网络状态事件
class NetworkStatusEvent extends AppEvent {
  NetworkStatusEvent.connected() : super('network_connected');
  NetworkStatusEvent.disconnected() : super('network_disconnected');
  NetworkStatusEvent.wifi() : super('network_wifi');
  NetworkStatusEvent.mobile() : super('network_mobile');
  NetworkStatusEvent.weak(int signalStrength) : super('network_weak', data: {'signalStrength': signalStrength});
}

/// 代理状态事件
class ProxyStatusEvent extends AppEvent {
  ProxyStatusEvent.started() : super('proxy_started');
  ProxyStatusEvent.stopped() : super('proxy_stopped');
  ProxyStatusEvent.paused() : super('proxy_paused');
  ProxyStatusEvent.resumed() : super('proxy_resumed');
}

/// 抓包事件
class CaptureEvent extends AppEvent {
  CaptureEvent.started() : super('capture_started');
  CaptureEvent.stopped() : super('capture_stopped');
  CaptureEvent.threshold(int count) : super('capture_threshold', data: {'count': count});
}

/// 脚本事件
class ScriptEvent extends AppEvent {
  ScriptEvent.executed(String scriptName, bool success, {String? error})
      : super('script_executed', data: {
          'scriptName': scriptName,
          'success': success,
          'error': error,
        });
}

/// 自定义事件
class CustomEvent extends AppEvent {
  CustomEvent(String eventType, Map<String, dynamic> data) : super(eventType, data: data);
}

/// 事件处理器 typedef
typedef EventHandler = void Function(AppEvent event);

/// 事件过滤器 typedef
typedef EventFilter = bool Function(AppEvent event);

/// 通用事件总线
class EventBus {
  static final EventBus _instance = EventBus._internal();
  factory EventBus() => _instance;
  EventBus._internal();

  final Map<String, List<_Subscription>> _subscriptions = {};
  final List<AppEvent> _history = [];
  final StreamController<AppEvent> _controller = StreamController<AppEvent>.broadcast();

  /// 获取事件流
  Stream<AppEvent> get stream => _controller.stream;

  /// 获取历史记录
  List<AppEvent> get history => List.unmodifiable(_history);

  /// 订阅事件
  /// [eventType] 事件类型，null 表示订阅所有事件
  /// [handler] 事件处理器
  /// [filter] 可选过滤器
  Subscription subscribe({String? eventType, required EventHandler handler, EventFilter? filter}) {
    final subscription = _Subscription(handler, filter: filter);
    _subscriptions.putIfAbsent(eventType ?? '*', () => []);
    _subscriptions[eventType ?? '*'!]!.add(subscription);
    // 返回公有订阅句柄（与内部 _Subscription 共享 id，取消时按 id 移除）
    return Subscription._(subscription.id, this);
  }

  /// 取消订阅
  void unsubscribe(Subscription subscription) {
    _subscriptions.forEach((key, list) {
      list.removeWhere((sub) => sub.id == subscription.id);
    });
  }

  /// 发布事件
  void publish(AppEvent event) {
    // 添加到历史记录
    if (_history.length >= 100) {
      _history.removeAt(0);
    }
    _history.add(event);

    // 广播到流
    if (!_controller.isClosed) {
      _controller.add(event);
    }

    // 通知订阅者
    final typeSubs = _subscriptions[event.type] ?? [];
    final allSubs = _subscriptions['*'] ?? [];

    for (final sub in [...typeSubs, ...allSubs]) {
      if (sub.isActive && (sub.filter == null || sub.filter!(event))) {
        try {
          sub.handler(event);
        } catch (e, stack) {
          logger.e('EventBus: 事件处理器出错', error: e, stackTrace: stack);
        }
      }
    }
  }

  /// 清空历史记录
  void clearHistory() {
    _history.clear();
  }

  /// 关闭事件总线
  void dispose() {
    _controller.close();
    _subscriptions.clear();
    _history.clear();
  }
}

/// 订阅信息
class _Subscription {
  final String id;
  final EventHandler handler;
  final EventFilter? filter;
  bool _active = true;

  _Subscription(this.handler, {this.filter}) : id = DateTime.now().millisecondsSinceEpoch.toString();

  bool get isActive => _active;

  void cancel() {
    _active = false;
  }
}

/// 通用事件（任意类型 + 数据负载），供各模块直接发布
class GenericEvent extends AppEvent {
  GenericEvent(String type, {Map<String, dynamic> data = const {}}) : super(type, data: data);
}

/// 订阅接口
class Subscription {
  final String _id;
  final EventBus _bus;
  bool _cancelled = false;

  Subscription._(this._id, this._bus);

  String get id => _id;
  bool get isCancelled => _cancelled;

  void cancel() {
    if (!_cancelled) {
      _cancelled = true;
      _bus.unsubscribe(this);
    }
  }
}

extension EventBusExtension on EventBus {
  /// 便捷订阅特定事件类型
  Subscription onHttpRequest(EventHandler handler) {
    return subscribe(eventType: 'http_request', handler: handler);
  }

  Subscription onNetworkStatus(EventHandler handler) {
    return subscribe(eventType: 'network_connected', handler: handler);
  }

  Subscription onProxyStatus(EventHandler handler) {
    return subscribe(eventType: 'proxy_started', handler: handler);
  }

  Subscription onCapture(EventHandler handler) {
    return subscribe(eventType: 'capture_started', handler: handler);
  }

  Subscription onScript(EventHandler handler) {
    return subscribe(eventType: 'script_executed', handler: handler);
  }

  Subscription onCustom(String eventType, EventHandler handler) {
    return subscribe(eventType: eventType, handler: handler);
  }
}
