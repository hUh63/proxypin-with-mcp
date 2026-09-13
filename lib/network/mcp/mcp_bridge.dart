import 'dart:async';
import 'dart:convert';

import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/utils/listenable_list.dart';
import 'package:proxypin/network/util/cache.dart';
import 'package:proxypin/network/rules/websocket_rule_manager.dart';

/// MCP 数据桥接，负责从 ProxyPin 收集流量并提供给 MCP Server
class McpBridge implements EventListener {
  static final McpBridge _instance = McpBridge._internal();

  factory McpBridge() => _instance;

  McpBridge._internal();

  /// 主程序的请求容器（由外部设置，避免重复存储）
  ListenableList<HttpRequest>? _requestContainer;

  /// 设置请求容器（从主程序传入）
  void setRequestContainer(ListenableList<HttpRequest> container) {
    _requestContainer = container;
  }

  /// 获取请求源列表（供 McpServer 使用，避免直接依赖 UI 层）
  List<HttpRequest> get source => _requestContainer?.source.toList() ?? [];

  /// 向容器中添加请求（用于 HAR 导入等场景）
  void addRequest(HttpRequest request) {
    _requestContainer?.add(request);
  }

  // 当请求完成（收到响应）时通知 McpServer 推送 SSE
  Function(HttpRequest)? onRequestCompleted;
  
  // UI清除回调（由主程序设置，对应垃圾桶图标的清除功能）
  Function()? onClearUI;

  /// 查询工具是否启用（读取用户配置，默认启用）
  bool isToolEnabled(String name) {
    // 配置尚未加载时视为全部启用
    var config = Configuration.loaded;
    if (config == null) return true;
    return config.mcpToolsEnabled[name] ?? true;
  }

  /// 获取最近的请求列表（增强版过滤）
  List<HttpRequest> getRecentRequests({
    int limit = 20, 
    String? urlFilter, 
    String? method, 
    String? statusCode,
    String? domain,
    int? minDuration,
    int? maxDuration,
    String? headerSearch,      // 新增：搜索 header（key 或 value）
    String? requestBodySearch, // 新增：搜索请求 body
    String? responseBodySearch, // 新增：搜索响应 body
  }) {
    if (_requestContainer == null) return [];
    
    var requests = _requestContainer!.source.toList();
    
    // URL 过滤（支持大小写不敏感）
    if (urlFilter != null && urlFilter.isNotEmpty) {
      requests = requests.where((req) => 
        req.requestUrl.toLowerCase().contains(urlFilter.toLowerCase())
      ).toList();
    }
    
    // HTTP 方法过滤
    if (method != null && method.isNotEmpty) {
      requests = requests.where((req) => 
        req.method.name.toUpperCase() == method.toUpperCase()
      ).toList();
    }
    
    // 状态码过滤（支持精确匹配如 "200"，也支持范围如 "2xx"）
    if (statusCode != null && statusCode.isNotEmpty) {
      requests = requests.where((req) {
        if (req.response == null) return false;
        var code = req.response!.status.code;
        
        // 支持范围查询：2xx, 3xx, 4xx, 5xx
        if (statusCode.endsWith('xx')) {
          var prefix = int.tryParse(statusCode.substring(0, 1));
          if (prefix != null) {
            return code >= prefix * 100 && code < (prefix + 1) * 100;
          }
        }
        
        // 精确匹配：200, 404, 500 等
        return code.toString() == statusCode;
      }).toList();
    }
    
    // 域名过滤
    if (domain != null && domain.isNotEmpty) {
      requests = requests.where((req) {
        try {
          var uri = Uri.parse(req.requestUrl);
          return uri.host.toLowerCase().contains(domain.toLowerCase());
        } catch (e) {
          return false;
        }
      }).toList();
    }
    
    // Header 搜索（搜索请求和响应的 header）
    if (headerSearch != null && headerSearch.isNotEmpty) {
      var searchLower = headerSearch.toLowerCase();
      requests = requests.where((req) {
        // 搜索请求 headers
        var reqMatch = req.headers.toMap().entries.any((entry) =>
          entry.key.toLowerCase().contains(searchLower) ||
          entry.value.toLowerCase().contains(searchLower)
        );
        if (reqMatch) return true;
        
        // 搜索响应 headers
        if (req.response != null) {
          return req.response!.headers.toMap().entries.any((entry) =>
            entry.key.toLowerCase().contains(searchLower) ||
            entry.value.toLowerCase().contains(searchLower)
          );
        }
        return false;
      }).toList();
    }
    
    // 请求 Body 搜索
    if (requestBodySearch != null && requestBodySearch.isNotEmpty) {
      var searchLower = requestBodySearch.toLowerCase();
      requests = requests.where((req) {
        if (req.body == null) return false;
        try {
          var bodyStr = utf8.decode(req.body!, allowMalformed: true);
          return bodyStr.toLowerCase().contains(searchLower);
        } catch (e) {
          return false;
        }
      }).toList();
    }
    
    // 响应 Body 搜索
    if (responseBodySearch != null && responseBodySearch.isNotEmpty) {
      var searchLower = responseBodySearch.toLowerCase();
      requests = requests.where((req) {
        if (req.response?.body == null) return false;
        try {
          var bodyStr = utf8.decode(req.response!.body!, allowMalformed: true);
          return bodyStr.toLowerCase().contains(searchLower);
        } catch (e) {
          return false;
        }
      }).toList();
    }
    
    // 耗时过滤
    if (minDuration != null || maxDuration != null) {
      requests = requests.where((req) {
        if (req.response == null) return false;
        var duration = req.response!.responseTime.difference(req.requestTime).inMilliseconds;
        if (minDuration != null && duration < minDuration) return false;
        if (maxDuration != null && duration > maxDuration) return false;
        return true;
      }).toList();
    }
    
    // 按时间倒序（最新的在前）
    requests.sort((a, b) => b.requestTime.compareTo(a.requestTime));
    
    return requests.take(limit).toList();
  }
  
  /// 根据 ID 获取请求详情
  HttpRequest? getRequestById(String id) {
    if (_requestContainer == null) return null;
    try {
      return _requestContainer!.source.firstWhere((req) => req.requestId == id);
    } catch (e) {
      return null;
    }
  }

  /// 获取当前存储的请求总数
  int get totalCount => _requestContainer?.length ?? 0;
  
  /// 清空所有请求（对应垃圾桶按钮）
  void clear() {
    _requestContainer?.clear();
  }
  
  /// 通过UI清除（调用真正的UI清除方法）
  bool clearWithUI() {
    if (onClearUI != null) {
      try {
        onClearUI!();
        return true;
      } catch (e) {
        logger.e('Failed to call UI clear callback: $e');
        return false;
      }
    }
    return false;
  }
  
  /// 清理早期数据，保留最新的 N 条（内存优化）
  void cleanupEarlyData(int retain) {
    if (_requestContainer == null) return;
    var list = _requestContainer!.source;
    if (list.length <= retain) return;
    
    _requestContainer!.removeRange(0, list.length - retain);
  }
  
  /// 获取请求统计信息
  Map<String, dynamic> getStatistics() {
    if (_requestContainer == null) return {};
    
    var requests = _requestContainer!.source;
    var methodCount = <String, int>{};
    var statusCount = <String, int>{};
    var domainCount = <String, int>{};
    var totalSize = 0;
    var totalDuration = 0;
    var errorCount = 0;
    
    for (var req in requests) {
      // 方法统计
      methodCount[req.method.name] = (methodCount[req.method.name] ?? 0) + 1;
      
      // 状态码统计
      if (req.response != null) {
        var code = req.response!.status.code;
        var codeGroup = '${code ~/ 100}xx';
        statusCount[codeGroup] = (statusCount[codeGroup] ?? 0) + 1;
        
        if (code >= 400) errorCount++;
        
        // 大小统计
        totalSize += (req.body?.length ?? 0) + (req.response!.body?.length ?? 0);
        
        // 耗时统计
        totalDuration += req.response!.responseTime.difference(req.requestTime).inMilliseconds;
      }
      
      // 域名统计
      try {
        var uri = Uri.parse(req.requestUrl);
        var domain = uri.host;
        domainCount[domain] = (domainCount[domain] ?? 0) + 1;
      } catch (e) {
        // ignore
      }
    }
    
    return {
      'total': requests.length,
      'methods': methodCount,
      'statusCodes': statusCount,
      'domains': domainCount,
      'totalSize': totalSize,
      'averageDuration': requests.isEmpty ? 0 : totalDuration ~/ requests.length,
      'errorCount': errorCount,
    };
  }

  @override
  void onRequest(Channel channel, HttpRequest request) {
    // MCP不需要在这里处理，主程序已经添加到容器了
    // 只需要通知回调即可
  }

  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) {
    final request = response.request;
    if (request == null) return;
    
    // 通知请求已完成（收到响应），可用于 SSE 推送
    onRequestCompleted?.call(request);
  }

  @override
  void onMessage(Channel channel, HttpMessage message, WebSocketFrame frame) {
    // 使用规则管理器检查是否应该拦截
    final url = message.requestUrl?.toString() ?? 'unknown';
    final isOutgoing = message is HttpRequest;
    final decision = WebSocketRuleManager().shouldIntercept(url, isOutgoing);
    
    if (!decision.shouldIntercept) return;
    
    // 匹配规则，暂停消息
    pauseWebSocketMessage(frame, url, isOutgoing);
  }

  // ==================== WebSocket Message Interception (v1.6.0+) ====================
  // 使用 WebSocketRuleManager 管理规则和全局开关
  
  // 存储暂停的 WebSocket 帧：frameId -> PausedWebSocketFrame
  final Map<String, PausedWebSocketFrame> _pausedWebSocketDetails = {};
  
  // 暂停的 WebSocket 帧缓存（10 分钟过期）
  final _pausedWebSockets = ExpiringCache<String, PausedWebSocketFrame>(
    duration: const Duration(minutes: 10),
  );

  /// 暂停帧保留时长：超过后惰性清理，避免 _pausedWebSocketDetails 无限增长造成内存泄漏
  static const Duration _pausedTtl = Duration(minutes: 10);

  /// 暂停帧数量上限：MCP 客户端始终不 resume 时的兜底保护（超出丢弃最旧的）
  static const int _maxPausedFrames = 256;

  /// 惰性清理过期 / 超量的暂停帧（在写入与读取时触发）
  void _purgeExpiredPausedFrames() {
    final now = DateTime.now();
    _pausedWebSocketDetails.removeWhere((_, v) => now.difference(v.pausedAt) > _pausedTtl);
    final overflow = _pausedWebSocketDetails.length - _maxPausedFrames;
    if (overflow > 0) {
      final sorted = _pausedWebSocketDetails.entries.toList()
        ..sort((a, b) => a.value.pausedAt.compareTo(b.value.pausedAt));
      for (var i = 0; i < overflow; i++) {
        _pausedWebSocketDetails.remove(sorted[i].key);
        _pausedWebSockets.remove(sorted[i].key);
      }
    }
  }

  /// 登记一条“暂停”的 WebSocket 消息并通知 MCP 客户端。
  ///
  /// 受原始字节直通转发架构限制，本方法不阻塞也不改写实际转发的字节，
  /// 属观测 / 登记语义（MCP 侧可据此 resume / abort）。
  Future<bool> pauseWebSocketMessage(WebSocketFrame frame, String url, bool isOutgoing) async {
    final frameId = 'ws_${DateTime.now().millisecondsSinceEpoch}_${frame.hashCode}';
    final paused = PausedWebSocketFrame(
      frameId: frameId,
      url: url,
      isOutgoing: isOutgoing,
      payload: frame.payloadData,
      opcode: frame.opcode,
      pausedAt: DateTime.now(),
    );
    
    _pausedWebSocketDetails[frameId] = paused;
    _pausedWebSockets.set(frameId, paused);
    _purgeExpiredPausedFrames();
    
    logger.i('WebSocket message paused: $frameId (${isOutgoing ? "outgoing" : "incoming"})');
    
    // 通知 MCP 客户端（通过回调）
    onWebSocketMessage?.call(paused);
    
    // 说明：本方法登记暂停帧并通知 MCP 客户端，由客户端决定 resume / abort。
    // 由于 WebSocket 转发采用原始字节直通（保真、零拷贝），此处不会阻塞或改写
    // 实际转发的字节；resume 时可回写登记内容供 MCP 侧展示。
    return true;
  }

  /// 恢复（释放）暂停的 WebSocket 消息
  Future<bool> resumeWebSocketMessage(String frameId, {String? payload}) async {
    final paused = _pausedWebSocketDetails[frameId];
    if (paused == null) {
      logger.w('Cannot resume: frame not found: $frameId');
      return false;
    }
    
    // 如果有修改的 payload，更新它
    if (payload != null && paused.opcode == 1) { // 1 = text frame
      paused.payload = utf8.encode(payload);
    }
    
    // 从暂停列表中移除
    _pausedWebSocketDetails.remove(frameId);
    _pausedWebSockets.remove(frameId);
    
    logger.i('WebSocket message resumed: $frameId');
    return true;
  }

  /// 中止（丢弃）暂停的 WebSocket 消息
  Future<bool> abortWebSocketMessage(String frameId, {String? reason}) async {
    final paused = _pausedWebSocketDetails[frameId];
    if (paused == null) {
      logger.w('Cannot abort: frame not found: $frameId');
      return false;
    }
    
    // 从暂停列表中移除
    _pausedWebSocketDetails.remove(frameId);
    _pausedWebSockets.remove(frameId);
    
    logger.i('WebSocket message aborted: $frameId, reason: ${reason ?? "none"}');
    return true;
  }

  /// 获取所有暂停的 WebSocket 消息
  List<PausedWebSocketFrame> getPausedWebSocketMessages() {
    _purgeExpiredPausedFrames();
    return _pausedWebSocketDetails.values.toList();
  }

  /// WebSocket 消息回调（用于通知 MCP Server）
  Function(PausedWebSocketFrame)? onWebSocketMessage;

  /// 辅助方法：将 HttpRequest 转换为 JSON（用于 MCP 响应）
  static Map<String, dynamic> requestToJson(HttpRequest request, {bool includeBody = false}) {
    return {
      'id': request.requestId,
      'url': request.requestUrl,
      'method': request.method.name,
      'timestamp': request.requestTime.toIso8601String(),
      'statusCode': request.response?.status.code,
      'duration': request.response?.responseTime.difference(request.requestTime).inMilliseconds,
      if (includeBody) ...{
        'request': {
          'headers': request.headers.toMap(),
          ..._encodeBodyWithMetadata(request.body),
        },
        'response': {
          'statusCode': request.response?.status.code,
          'statusText': request.response?.status.reasonPhrase,
          'headers': request.response?.headers.toMap(),
          ..._encodeBodyWithMetadata(request.response?.body),
        },
      },
    };
  }
  
  /// 编码 body 并返回元数据（包含编码类型、大小、内容）
  static Map<String, dynamic> _encodeBodyWithMetadata(List<int>? body) {
    if (body == null || body.isEmpty) {
      return {
        'body': null,
        'bodySize': 0,
        'bodyEncoding': 'none',
      };
    }
    
    try {
      // 尝试 UTF-8 解码
      var text = utf8.decode(body, allowMalformed: false);
      return {
        'body': text,
        'bodySize': body.length,
        'bodyEncoding': 'utf8',
      };
    } catch (e) {
      // 解码失败，说明是二进制数据，用 Base64 编码
      return {
        'body': base64Encode(body),
        'bodySize': body.length,
        'bodyEncoding': 'base64',
      };
    }
  }
}

