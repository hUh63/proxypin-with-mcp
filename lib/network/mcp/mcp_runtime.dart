/*
 * Copyright 2023 Hongen Wang
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

import 'package:proxypin/network/util/logger.dart';

/// MCP 工具调用被并发闸拒绝时抛出（忙时快速失败，而不是排长队）。
class McpBusyException implements Exception {
  final String message;

  McpBusyException(this.message);

  @override
  String toString() => message;
}

/// 单次工具调用的审计条目。
///
/// 出于隐私考虑**只记录参数名，不记录参数值**（值可能含抓包内容与凭据）。
class McpCallRecord {
  final DateTime at;
  final String tool;
  final String caller;
  final int durationMs;
  final bool ok;
  final String? error;
  final List<String> argKeys;
  final int argBytes;

  McpCallRecord({
    required this.at,
    required this.tool,
    required this.caller,
    required this.durationMs,
    required this.ok,
    this.error,
    this.argKeys = const [],
    this.argBytes = 0,
  });

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'tool': tool,
        'caller': caller,
        'duration_ms': durationMs,
        'ok': ok,
        if (error != null) 'error': error,
        'arg_keys': argKeys,
        'arg_bytes': argBytes,
      };
}

class _ToolStat {
  int calls = 0;
  int failed = 0;
  int totalMs = 0;
  int maxMs = 0;

  void record(int ms, bool ok) {
    calls++;
    if (!ok) failed++;
    totalMs += ms;
    if (ms > maxMs) maxMs = ms;
  }

  Map<String, dynamic> toJson() => {
        'calls': calls,
        'failed': failed,
        'avg_ms': calls == 0 ? 0 : (totalMs / calls).round(),
        'max_ms': maxMs,
      };
}

/// MCP 运行时指标（进程内累计，服务重启后清零）。
///
/// 与 `get_performance_metrics` 原有的「进程内存 + 抓包统计」不同：
/// 这里衡量的是 **MCP 服务自身**的运行状况（调用量、失败率、并发水位）。
class McpMetrics {
  McpMetrics._();

  static final McpMetrics instance = McpMetrics._();

  DateTime? _startedAt;
  int _totalCalls = 0;
  int _failedCalls = 0;
  int _rejectedCalls = 0;
  int _timeoutCalls = 0;
  int _invalidCalls = 0;
  int _inflight = 0;
  int _peakInflight = 0;
  final Map<String, _ToolStat> _byTool = {};

  void markStarted() {
    _startedAt = DateTime.now();
  }

  void markInflight(int delta) {
    _inflight += delta;
    if (_inflight < 0) _inflight = 0;
    if (_inflight > _peakInflight) _peakInflight = _inflight;
  }

  void recordCall(String tool, int durationMs, bool ok) {
    _totalCalls++;
    if (!ok) _failedCalls++;
    (_byTool[tool] ??= _ToolStat()).record(durationMs, ok);
  }

  void recordRejected() => _rejectedCalls++;

  void recordTimeout() => _timeoutCalls++;

  void recordInvalid() => _invalidCalls++;

  int get inflight => _inflight;

  void reset() {
    _startedAt = DateTime.now();
    _totalCalls = 0;
    _failedCalls = 0;
    _rejectedCalls = 0;
    _timeoutCalls = 0;
    _invalidCalls = 0;
    _inflight = 0;
    _peakInflight = 0;
    _byTool.clear();
  }

  Map<String, dynamic> toJson() {
    final started = _startedAt;
    final tools = <String, dynamic>{};
    final sorted = _byTool.entries.toList()
      ..sort((a, b) => b.value.calls.compareTo(a.value.calls));
    for (final entry in sorted) {
      tools[entry.key] = entry.value.toJson();
    }
    return {
      'started_at': started?.toIso8601String(),
      'uptime_seconds':
          started == null ? 0 : DateTime.now().difference(started).inSeconds,
      'total_calls': _totalCalls,
      'failed_calls': _failedCalls,
      'rejected_calls': _rejectedCalls,
      'timeout_calls': _timeoutCalls,
      'invalid_calls': _invalidCalls,
      'failure_rate': _totalCalls == 0
          ? 0.0
          : double.parse((_failedCalls / _totalCalls).toStringAsFixed(4)),
      'inflight': _inflight,
      'peak_inflight': _peakInflight,
      'tools_reported': tools.length,
      'by_tool': tools,
    };
  }
}

/// MCP 工具调用审计（内存环形缓冲，默认保留最近 500 条）。
class McpAuditLog {
  McpAuditLog._();

  static final McpAuditLog instance = McpAuditLog._();

  final Queue<McpCallRecord> _records = Queue();

  /// 保留条数上限。
  int capacity = 500;

  void add(McpCallRecord record) {
    _records.addLast(record);
    while (_records.length > capacity) {
      _records.removeFirst();
    }
  }

  int get length => _records.length;

  void clear() => _records.clear();

  List<McpCallRecord> recent({int limit = 100, String? tool, bool? onlyFailed}) {
    Iterable<McpCallRecord> it = _records;
    if (tool != null && tool.isNotEmpty) {
      it = it.where((r) => r.tool == tool);
    }
    if (onlyFailed == true) {
      it = it.where((r) => !r.ok);
    }
    final list = it.toList();
    if (list.length > limit) {
      return list.sublist(list.length - limit);
    }
    return list;
  }
}

/// 并发闸。
///
/// Dart 标准库没有 Semaphore，这里用「在飞计数 + 等待队列」实现：
/// 超过 [maxConcurrent] 的调用进入队列，队列也满时**立刻拒绝**
/// （忙时快速失败，避免连接排长队把内存吃满）。
class McpGate {
  McpGate({
    this.maxConcurrent = 16,
    this.queueLimit = 64,
    this.waitTimeout = const Duration(seconds: 5),
  });

  int maxConcurrent;
  int queueLimit;
  Duration waitTimeout;

  int _running = 0;
  int _queued = 0;
  final Queue<Completer<void>> _waiters = Queue();

  bool get isSaturated => _running >= maxConcurrent && _queued >= queueLimit;

  int get queued => _queued;
  int get running => _running;

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running < maxConcurrent) {
      _running++;
    } else {
      if (_queued >= queueLimit) {
        throw McpBusyException(
            'MCP server is busy: $maxConcurrent running, $queueLimit queued. Retry shortly.');
      }
      final completer = Completer<void>();
      _waiters.add(completer);
      _queued++;
      try {
        await completer.future.timeout(waitTimeout);
      } on TimeoutException {
        // 等待超时：把占位从队列里摘掉，避免名额泄漏
        _waiters.remove(completer);
        _queued--;
        throw McpBusyException(
            'MCP server is busy: waited ${waitTimeout.inSeconds}s for a free slot.');
      }
      _queued--;
      _running++;
    }

    try {
      return await task();
    } finally {
      _running--;
      _releaseNext();
    }
  }

  void _releaseNext() {
    while (_waiters.isNotEmpty) {
      final next = _waiters.removeFirst();
      if (!next.isCompleted) {
        next.complete();
        return;
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'max_concurrent': maxConcurrent,
        'queue_limit': queueLimit,
        'wait_timeout_ms': waitTimeout.inMilliseconds,
        'running': _running,
        'queued': _queued,
        'saturated': isSaturated,
      };
}

/// 工具调用的统一执行入口。
///
/// 顺序：Schema 校验 → 并发闸 → per-tool 超时 → 指标与审计。
/// 把这段逻辑收敛在一处，避免在 HTTP / SSE / stdio 等多个入口各写一遍。
class McpToolRuntime {
  McpToolRuntime._();

  /// 默认超时（毫秒）。
  static const int defaultTimeoutMs = 120000;

  /// 按工具覆盖超时：设备类工具走 MethodChannel，卡住时不该占用 120 秒。
  static const Map<String, int> toolTimeoutMs = {
    'shell': 60000,
    'screenshot': 30000,
    'dump_ui': 30000,
    'tap_screen': 30000,
    'long_press': 30000,
    'swipe_screen': 30000,
    'key_event': 30000,
    'input_text': 30000,
    'get_current_activity': 20000,
    'get_device_info': 20000,
    'open_accessibility_settings': 20000,
    'start_proxy': 30000,
    'stop_proxy': 30000,
    'export_har': 60000,
    'import_har': 60000,
    'diagnose_capture': 45000,
    'get_quic_sessions': 45000,
    'get_client_setup': 20000,
    'keep_alive': 45000,
  };

  /// 是否启用按 inputSchema 的参数校验。
  static bool strictValidation = true;

  static final McpGate gate = McpGate();

  static int timeoutMsFor(String tool) => toolTimeoutMs[tool] ?? defaultTimeoutMs;

  /// 统一入口。
  ///
  /// [invoke] 是工具的真正实现（通常是 `_executeTool` 的一个分支）。
  /// [inputSchema] 为该工具的声明式参数约束，用于前置校验。
  static Future<dynamic> run(
    String tool,
    Map<String, dynamic> args,
    Future<dynamic> Function() invoke, {
    Map<String, dynamic>? inputSchema,
    String caller = 'unknown',
  }) async {
    final startedAt = DateTime.now();

    // 1) 参数校验
    if (strictValidation && inputSchema != null) {
      final problem = validateArguments(tool, args, inputSchema);
      if (problem != null) {
        McpMetrics.instance.recordInvalid();
        _audit(tool, caller, startedAt, false, problem, args);
        // 按 MCP 规范，工具级错误作为结果返回（isError: true），而不是协议错误
        return {'error': 'Invalid arguments: $problem'};
      }
    }

    // 2) 并发闸 + 3) 超时
    McpMetrics.instance.markInflight(1);
    try {
      final timeout = Duration(milliseconds: timeoutMsFor(tool));
      // 超时只在闸内做：闸外再套一层 timeout 会在「等待名额」期间抛异常，
      // 绕过 gate 的 finally，导致并发名额泄漏。
      final result = await gate.run(() => invoke().timeout(
            timeout,
            onTimeout: () => throw TimeoutException(
                'Tool "$tool" timed out after ${timeout.inMilliseconds}ms'),
          ));
      final ok = !(result is Map && result.containsKey('error'));
      McpMetrics.instance.recordCall(
          tool, DateTime.now().difference(startedAt).inMilliseconds, ok);
      _audit(tool, caller, startedAt, ok,
          ok ? null : (result is Map ? result['error']?.toString() : null), args);
      return result;
    } on McpBusyException catch (e) {
      McpMetrics.instance.recordRejected();
      _audit(tool, caller, startedAt, false, e.message, args);
      return {'error': e.message};
    } on TimeoutException catch (e) {
      McpMetrics.instance.recordTimeout();
      McpMetrics.instance.recordCall(
          tool, DateTime.now().difference(startedAt).inMilliseconds, false);
      _audit(tool, caller, startedAt, false, e.message ?? 'timeout', args);
      return {'error': 'Tool "$tool" timed out'};
    } catch (e) {
      McpMetrics.instance.recordCall(
          tool, DateTime.now().difference(startedAt).inMilliseconds, false);
      _audit(tool, caller, startedAt, false, e.toString(), args);
      rethrow;
    } finally {
      McpMetrics.instance.markInflight(-1);
    }
  }

  static void _audit(String tool, String caller, DateTime startedAt, bool ok,
      String? error, Map<String, dynamic> args) {
    int bytes = 0;
    try {
      bytes = args.toString().length;
    } catch (_) {
      // 参数无法序列化时忽略长度
    }
    McpAuditLog.instance.add(McpCallRecord(
      at: DateTime.now(),
      tool: tool,
      caller: caller,
      durationMs: DateTime.now().difference(startedAt).inMilliseconds,
      ok: ok,
      error: error,
      argKeys: args.keys.map((k) => k.toString()).toList(growable: false),
      argBytes: bytes,
    ));
  }

  /// 按 JSON-Schema 校验参数，返回第一条错误描述；通过则返回 null。
  ///
  /// 只做**保守**校验：必填项、类型、enum、数值区间。
  /// 未在 schema 中声明的额外参数一律放行（向前兼容）。
  static String? validateArguments(
      String tool, Map<String, dynamic> args, Map<String, dynamic> schema) {
    final type = schema['type'];
    if (type is String && type != 'object') return null;

    final required = schema['required'];
    if (required is List) {
      for (final item in required) {
        if (item is String && !args.containsKey(item)) {
          return 'missing required parameter "$item"';
        }
      }
    }

    final properties = schema['properties'];
    if (properties is Map) {
      for (final entry in properties.entries) {
        final key = entry.key.toString();
        if (!args.containsKey(key)) continue;
        final spec = entry.value;
        if (spec is! Map) continue;
        final problem = _checkValue(key, args[key], spec);
        if (problem != null) return problem;
      }
    }
    return null;
  }

  static String? _checkValue(String key, dynamic value, Map spec) {
    if (value == null) return null; // null 交给工具自己处理

    final type = spec['type'];
    switch (type) {
      case 'string':
        // 宽容：数字与布尔也接受，转成字符串由工具内部处理
        if (value is! String && value is! num && value is! bool) {
          return 'parameter "$key" must be a string';
        }
        break;
      case 'integer':
        if (value is! num) return 'parameter "$key" must be an integer';
        if (value is double && value != value.roundToDouble()) {
          return 'parameter "$key" must be an integer';
        }
        break;
      case 'number':
        if (value is! num) return 'parameter "$key" must be a number';
        break;
      case 'boolean':
        if (value is! bool) return 'parameter "$key" must be a boolean';
        break;
      case 'array':
        if (value is! List) return 'parameter "$key" must be an array';
        break;
      case 'object':
        if (value is! Map) return 'parameter "$key" must be an object';
        break;
    }

    final enums = spec['enum'];
    if (enums is List && enums.isNotEmpty && !enums.contains(value)) {
      return 'parameter "$key" must be one of ${enums.join("/")}';
    }

    if (value is num) {
      final min = spec['minimum'];
      final max = spec['maximum'];
      if (min is num && value < min) return 'parameter "$key" must be >= $min';
      if (max is num && value > max) return 'parameter "$key" must be <= $max';
    }
    return null;
  }

  static String? validateOrNull(
          String tool, Map<String, dynamic> args, Map<String, dynamic>? schema) =>
      schema == null ? null : validateArguments(tool, args, schema);
}

/// 统一记录工具实现内部的异常（供 `_executeTool` 的兜底 catch 使用）。
///
/// 只用位置参数拼接，避免依赖 logger 具名参数的具体签名。
void logMcpError(String where, Object e, [StackTrace? st]) {
  logger.w('MCP tool failed in $where: $e${st == null ? '' : '\n$st'}');
}
