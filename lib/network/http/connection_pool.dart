/*
 * 高性能连接池 - 支持并发请求处理
 * 功能：连接复用、智能重试、线程安全、性能监控
 */

import 'dart:async';
import 'dart:io';
import 'dart:collection';
import 'package:proxypin/network/channel/connection_registry.dart';
import 'package:proxypin/network/util/logger.dart';

/// 连接配置
class ConnectionConfig {
  final int maxConnections;        // 最大连接数
  final int maxConnectionsPerHost; // 每主机最大连接数
  final Duration connectionTimeout; // 连接超时
  final Duration idleTimeout;       // 空闲超时
  final bool keepAlive;            // 保持连接
  final int retryCount;            // 重试次数
  final Duration retryDelay;       // 重试延迟

  const ConnectionConfig({
    this.maxConnections = 50,
    this.maxConnectionsPerHost = 10,
    this.connectionTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 60),
    this.keepAlive = true,
    this.retryCount = 3,
    this.retryDelay = const Duration(milliseconds: 500),
  });

  ConnectionConfig copyWith({
    int? maxConnections,
    int? maxConnectionsPerHost,
    Duration? connectionTimeout,
    Duration? idleTimeout,
    bool? keepAlive,
    int? retryCount,
    Duration? retryDelay,
  }) {
    return ConnectionConfig(
      maxConnections: maxConnections ?? this.maxConnections,
      maxConnectionsPerHost: maxConnectionsPerHost ?? this.maxConnectionsPerHost,
      connectionTimeout: connectionTimeout ?? this.connectionTimeout,
      idleTimeout: idleTimeout ?? this.idleTimeout,
      keepAlive: keepAlive ?? this.keepAlive,
      retryCount: retryCount ?? this.retryCount,
      retryDelay: retryDelay ?? this.retryDelay,
    );
  }
}

/// 连接统计信息
class ConnectionStats {
  int totalRequests = 0;
  int successfulRequests = 0;
  int failedRequests = 0;
  int retryCount = 0;
  Duration totalResponseTime = Duration.zero;
  int activeConnections = 0;
  int idleConnections = 0;
  DateTime startTime = DateTime.now();

  /// 平均响应时间
  Duration get avgResponseTime => totalRequests > 0 
    ? Duration(milliseconds: totalResponseTime.inMilliseconds ~/ totalRequests)
    : Duration.zero;

  /// 成功率
  double get successRate => totalRequests > 0 ? successfulRequests / totalRequests : 0;

  /// QPS (每秒请求数)
  double get qps {
    final elapsed = DateTime.now().difference(startTime).inSeconds;
    return elapsed > 0 ? totalRequests / elapsed : 0;
  }

  Map<String, dynamic> toJson() => {
    'totalRequests': totalRequests,
    'successfulRequests': successfulRequests,
    'failedRequests': failedRequests,
    'retryCount': retryCount,
    'avgResponseTimeMs': avgResponseTime.inMilliseconds,
    'successRate': successRate,
    'qps': qps,
    'activeConnections': activeConnections,
    'idleConnections': idleConnections,
  };
}

/// 连接池项
class _PooledConnection {
  final HttpClient client;
  final String host;
  final int port;
  DateTime lastUsed;
  bool inUse;
  int useCount;

  _PooledConnection({
    required this.client,
    required this.host,
    required this.port,
    required this.lastUsed,
    this.inUse = false,
    this.useCount = 0,
  });

  bool get isExpired => lastUsed.difference(DateTime.now()).abs() > const Duration(seconds: 60);
}

/// 高性能连接池
class ConnectionPool {
  static final ConnectionPool instance = ConnectionPool();

  /// 最近请求发生时刻（毫秒），用于算实时 QPS
  final List<int> _recentRequestAt = <int>[];
  static const int _qpsWindowMs = 5000;

  /// 上报一次真实流量。
  ///
  /// `execute()` 在本项目里没有调用点（转发走自研网络层），统计如果只挂在它上面，
  /// 性能面板会永远是 0。改由响应处理链路上报。
  void recordTraffic({required int elapsedMs, int? statusCode}) {
    final failed = statusCode == null || statusCode >= 400;
    _stats.totalRequests++;
    if (failed) {
      _stats.failedRequests++;
    } else {
      _stats.successfulRequests++;
    }
    _stats.totalResponseTime += Duration(milliseconds: elapsedMs < 0 ? 0 : elapsedMs);

    final now = DateTime.now().millisecondsSinceEpoch;
    _recentRequestAt.add(now);
    _trimQpsWindow(now);
  }

  void _trimQpsWindow(int now) {
    var drop = 0;
    while (drop < _recentRequestAt.length && now - _recentRequestAt[drop] > _qpsWindowMs) {
      drop++;
    }
    if (drop > 0) {
      _recentRequestAt.removeRange(0, drop);
    }
  }

  /// 5 秒窗口内的实时 QPS（旧实现用「总请求数 / 进程运行秒数」，只会越跑越小）
  double get currentQps {
    _trimQpsWindow(DateTime.now().millisecondsSinceEpoch);
    if (_recentRequestAt.isEmpty) return 0;
    return _recentRequestAt.length / (_qpsWindowMs / 1000);
  }

  /// 获取连接池统计信息
  Map<String, dynamic> getStats() {
    // 活跃连接取真实连接注册表，而不是从未被 execute() 累加过的计数器。
    _stats.activeConnections = ConnectionRegistry.instance.count;
    _stats.idleConnections = _pools.values.fold<int>(0, (sum, q) => sum + q.length);
    final json = _stats.toJson();
    json['qps'] = currentQps;
    return json;
  }

  final ConnectionConfig _config;
  final ConnectionStats _stats = ConnectionStats();

  // 连接池存储
  final Map<String, Queue<_PooledConnection>> _pools = {};
  final Map<String, int> _activePerHost = {};
  
  // 信号量控制并发
  int _totalActive = 0;
  final _mutex = Mutex();

  // 重试策略
  final Set<int> _retryableStatusCodes = {408, 429, 500, 502, 503, 504};

  ConnectionPool({ConnectionConfig? config}) : _config = config ?? const ConnectionConfig();

  /// 执行带重试的 HTTP 请求
  Future<HttpClientResponse> execute(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final startTime = DateTime.now();
    _stats.totalRequests++;

    try {
      final response = await _executeWithRetry(method, url, headers: headers, body: body);
      
      final elapsed = DateTime.now().difference(startTime);
      _stats.totalResponseTime += elapsed;
      _stats.successfulRequests++;
      
      return response;
    } catch (e) {
      _stats.failedRequests++;
      logger.e('请求失败：$method ${url.host}${url.path} - $e');
      rethrow;
    }
  }

  /// 带重试的执行
  Future<HttpClientResponse> _executeWithRetry(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    Exception? lastError;

    for (var attempt = 0; attempt <= _config.retryCount; attempt++) {
      try {
        final response = await _executeRequest(method, url, headers: headers, body: body);
        
        // 检查是否需要重试
        if (_retryableStatusCodes.contains(response.statusCode)) {
          _stats.retryCount++;
          lastError = HttpException('可重试的状态码：${response.statusCode}');
          
          if (attempt < _config.retryCount) {
            final delay = _config.retryDelay * (attempt + 1);
            logger.w('第${attempt + 1}次重试，延迟${delay.inMilliseconds}ms');
            await Future.delayed(delay);
            continue;
          }
        }
        
        return response;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        
        if (attempt < _config.retryCount) {
          _stats.retryCount++;
          final delay = _config.retryDelay * (attempt + 1);
          logger.w('第${attempt + 1}次重试，延迟${delay.inMilliseconds}ms - $e');
          await Future.delayed(delay);
        }
      }
    }

    throw lastError ?? Exception('请求失败');
  }

  /// 执行单个请求
  Future<HttpClientResponse> _executeRequest(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final client = await _acquireConnection(url);
    
    try {
      final request = await client.openUrl(method, url);
      
      // 设置超时
      
      // 添加请求头
      if (headers != null) {
        headers.forEach((key, value) {
          request.headers.set(key, value);
        });
      }
      
      // 添加请求体
      if (body != null) {
        if (body is String) {
          request.write(body);
        } else if (body is List<int>) {
          request.add(body);
        } else if (body is Map) {
          request.headers.set('Content-Type', 'application/json');
          request.write(body.toString());
        }
      }
      
      final response = await request.close();
      return response;
    } finally {
      _releaseConnection(client, url.host);
    }
  }

  /// 获取连接
  Future<HttpClient> _acquireConnection(Uri url) async {
    await _mutex.acquire();
    
    try {
      final host = url.host;
      final port = url.port ?? (url.scheme == 'https' ? 443 : 80);
      final poolKey = '$host:$port';
      
      // 检查每主机连接数限制
      final activePerHost = _activePerHost[poolKey] ?? 0;
      if (activePerHost >= _config.maxConnectionsPerHost) {
        // 等待有空闲连接
        await _waitForAvailableConnection(poolKey);
      }
      
      // 尝试从池中获取空闲连接
      final pool = _pools[poolKey];
      if (pool != null && pool.isNotEmpty) {
        final conn = pool.removeFirst();
        if (!conn.isExpired && conn.client.isActive) {
          conn.inUse = true;
          conn.useCount++;
          conn.lastUsed = DateTime.now();
          _totalActive++;
          _activePerHost[poolKey] = (_activePerHost[poolKey] ?? 0) + 1;
          _updateStats();
          return conn.client;
        } else {
          // 关闭过期连接
          conn.client.close();
        }
      }
      
      // 创建新连接
      final client = HttpClient()
        ..connectionTimeout = _config.connectionTimeout
        ..idleTimeout = _config.idleTimeout
        ..maxConnectionsPerHost = _config.maxConnectionsPerHost;
      
      final conn = _PooledConnection(
        client: client,
        host: host,
        port: port,
        lastUsed: DateTime.now(),
        inUse: true,
        useCount: 1,
      );
      
      _totalActive++;
      _activePerHost[poolKey] = (_activePerHost[poolKey] ?? 0) + 1;
      _updateStats();
      
      return client;
    } finally {
      _mutex.release();
    }
  }

  /// 释放连接
  void _releaseConnection(HttpClient client, String host) {
    _mutex.acquire().then((_) {
      try {
        final poolKey = host;
        
        if (_config.keepAlive) {
          // 回收到池中
          final pool = _pools.putIfAbsent(poolKey, () => Queue());
          // 找到对应的连接项
          for (var conn in pool) {
            if (conn.client == client) {
              conn.inUse = false;
              conn.lastUsed = DateTime.now();
              break;
            }
          }
        } else {
          client.close();
        }
        
        _totalActive--;
        _activePerHost[poolKey] = (_activePerHost[poolKey] ?? 0) - 1;
        if (_activePerHost[poolKey]! <= 0) {
          _activePerHost.remove(poolKey);
        }
        
        _updateStats();
      } finally {
        _mutex.release();
      }
    });
  }

  /// 等待可用连接
  Future<void> _waitForAvailableConnection(String poolKey) async {
    final checkInterval = const Duration(milliseconds: 100);
    final timeout = _config.connectionTimeout;
    final startTime = DateTime.now();
    
    while (DateTime.now().difference(startTime) < timeout) {
      await _mutex.acquire();
      try {
        final activePerHost = _activePerHost[poolKey] ?? 0;
        if (activePerHost < _config.maxConnectionsPerHost) {
          return;
        }
      } finally {
        _mutex.release();
      }
      await Future.delayed(checkInterval);
    }
    
    throw TimeoutException('等待连接超时');
  }

  /// 更新统计
  void _updateStats() {
    _stats.activeConnections = _totalActive;
    _stats.idleConnections = _pools.values.fold(0, (sum, pool) => sum + pool.where((c) => !c.inUse).length);
  }

  /// 获取统计信息
  ConnectionStats get stats => _stats;

  /// 清空连接池
  Future<void> clear() async {
    await _mutex.acquire();
    try {
      for (var pool in _pools.values) {
        for (var conn in pool) {
          conn.client.close();
        }
      }
      _pools.clear();
      _activePerHost.clear();
      _totalActive = 0;
      _updateStats();
      logger.i('连接池已清空');
    } finally {
      _mutex.release();
    }
  }

  /// 关闭连接池
  Future<void> dispose() async {
    await clear();
    logger.i('连接池已关闭');
  }
}

/// 简单的互斥锁实现
class Mutex {
  final _queue = Queue<Completer<void>>();
  bool _locked = false;

  Future<void> acquire() async {
    final completer = Completer<void>();
    _queue.add(completer);
    
    if (!_locked) {
      _locked = true;
      _queue.removeFirst();
      completer.complete();
    } else {
      await completer.future;
    }
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeFirst().complete();
    } else {
      _locked = false;
    }
  }
}

/// HTTP 客户端扩展
extension HttpClientExtension on HttpClient {
  bool get isActive => true; // 简化判断
}
