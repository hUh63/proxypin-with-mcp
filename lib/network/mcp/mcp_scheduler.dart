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
import 'dart:convert';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/cron_expression.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/path.dart';

/// 无参数无返回值的回调类型
typedef VoidCallback = void Function();

/// 可序列化任务执行器：UI 层启动时注册一次。
/// 把"动作描述"(type+参数) 还原为真实执行，使定时任务可跨重启持久化。
typedef TaskActionExecutor = Future<void> Function(Map<String, dynamic> descriptor);

/// MCP 定时任务调度器
/// 支持一次性任务、每日重复任务和固定间隔任务，可持久化到 mcp_tasks.json
class McpScheduler {
  static final McpScheduler _instance = McpScheduler._internal();
  factory McpScheduler() => _instance;
  McpScheduler._internal();

  final List<ScheduledTask> _tasks = [];
  Timer? _checkTimer;
  TaskActionExecutor? _executor;

  /// 注册动作执行器（UI 层启动时调用一次）
  void setActionExecutor(TaskActionExecutor executor) => _executor = executor;

  /// 添加定时任务
  /// [action] 仅本会话即时触发（闭包不可序列化）；[actionDescriptor] 可持久化，
  /// 重启加载后由 [setActionExecutor] 注册的执行器触发。二者任一非空即可。
  ///
  /// [repeatMode] 重复方式：none 一次性 / daily 每天 / weekly 每周 / interval 固定间隔 / cron 表达式；
  /// [weekdays] weekly 模式选中的星期（1=周一 ... 7=周日）；
  /// [repeatCount] 重复次数，null 表示无限重复。
  void scheduleTask({
    required String name,
    required DateTime executeAt,
    VoidCallback? action,
    Map<String, dynamic>? actionDescriptor,
    bool repeatDaily = false,
    String repeatMode = 'none',
    int? repeatCount,
    int? intervalMinutes,
    List<int>? weekdays,
    String? cronExpression,
  }) {
    // 兼容旧参数：未显式指定 repeatMode 时按 repeatDaily 推断
    final mode = (repeatMode == 'none' && repeatDaily) ? 'daily' : repeatMode;
    final task = ScheduledTask(
      name: name,
      executeAt: executeAt,
      action: action,
      actionDescriptor: actionDescriptor,
      repeatMode: mode,
      repeatCount: repeatCount,
      intervalMinutes: intervalMinutes,
      weekdays: weekdays,
      cronExpression: cronExpression,
    );
    _tasks.add(task);
    logger.i('添加定时任务：$name，执行时间：$executeAt，模式：$mode，次数：${repeatCount ?? '无限'}');

    _startCheckTimer();
  }

  /// 启动检查定时器
  void _startCheckTimer() {
    if (_checkTimer != null && _checkTimer!.isActive) return;

    _checkTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkTasks());
    logger.d('定时任务检查器已启动');
  }

  /// 检查并执行到期的任务
  Future<void> _checkTasks() async {
    final now = DateTime.now();

    for (final task in _tasks) {
      if (task.isCancelled) continue;

      if (now.isAfter(task.executeAt) || now.isAtSameMomentAs(task.executeAt)) {
        // 任务到期，执行
        try {
          logger.i('执行定时任务：${task.name}');
          await _runTask(task);
          task.lastExecuted = now;
          task.executedCount++;

          // 计算下一次执行时间 / 是否结束
          if (task.repeatMode == 'daily') {
            // 设置为明天的同一时间
            task.executeAt = DateTime(
              now.year,
              now.month,
              now.day + 1,
              task.executeAt.hour,
              task.executeAt.minute,
              task.executeAt.second,
            );
            logger.d('定时任务 ${task.name} 下次执行时间：${task.executeAt}');
          } else if (task.repeatMode == 'weekly' && task.weekdays != null && task.weekdays!.isNotEmpty) {
            // 从明天开始找第一个选中的星期
            var next = DateTime(now.year, now.month, now.day + 1, task.executeAt.hour, task.executeAt.minute,
                task.executeAt.second);
            for (int i = 0; i < 8; i++) {
              if (task.weekdays!.contains(next.weekday)) break;
              next = next.add(const Duration(days: 1));
            }
            task.executeAt = next;
            logger.d('定时任务 ${task.name} 下次执行时间：${task.executeAt}');
          } else if (task.repeatMode == 'interval' && task.intervalMinutes != null && task.intervalMinutes! > 0) {
            task.executeAt = now.add(Duration(minutes: task.intervalMinutes!));
            logger.d('定时任务 ${task.name} 下次执行时间：${task.executeAt}');
          } else if (task.repeatMode == 'cron' && task.cronExpression != null) {
            // Cron 表达式：计算下一个匹配时间；解析失败则结束任务
            final next = CronExpression(task.cronExpression!).next(now);
            if (next == null) {
              task.isCancelled = true;
              logger.w('定时任务 ${task.name} Cron 表达式无效：${task.cronExpression}');
            } else {
              task.executeAt = next;
              logger.d('定时任务 ${task.name} 下次执行时间：${task.executeAt}');
            }
          } else {
            task.isCancelled = true;
            logger.d('一次性任务 ${task.name} 已完成');
          }

          // 达到重复次数上限则结束
          if (!task.isCancelled && task.repeatCount != null && task.executedCount >= task.repeatCount!) {
            task.isCancelled = true;
            logger.i('定时任务 ${task.name} 已完成全部 ${task.repeatCount} 次执行');
          }

          if (task.isCancelled) {
            await saveTasks();
          } else {
            await saveTasks();
          }
        } catch (e) {
          logger.e('执行定时任务 ${task.name} 失败', error: e);
        }
      }
    }

    // 清理已取消的任务
    _tasks.removeWhere((task) => task.isCancelled);
  }

  /// 执行单个任务：优先闭包，否则用执行器跑动作描述
  Future<void> _runTask(ScheduledTask task) async {
    if (task.action != null) {
      task.action!();
      return;
    }
    if (task.actionDescriptor != null) {
      if (_executor != null) {
        await _executor!(task.actionDescriptor!);
      } else {
        logger.w('任务 ${task.name} 有动作描述但未注册执行器，跳过');
      }
    }
  }

  /// 取消所有任务
  void cancelAll() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _tasks.clear();
    logger.i('已取消所有定时任务');
  }

  /// 取消单个定时任务（按名称，避免误删全部）
  void cancelTask(String name) {
    for (final task in _tasks) {
      if (task.name == name && !task.isCancelled) {
        task.isCancelled = true;
      }
    }
    _tasks.removeWhere((task) => task.isCancelled);
    logger.i('已取消定时任务：$name');
  }

  /// 获取任务列表
  List<ScheduledTask> get tasks => List.unmodifiable(_tasks);

  /// 持久化（仅持久化带动作描述的任务，闭包无法序列化）
  Future<void> saveTasks() async {
    try {
      final file = await Paths.getPath('mcp_tasks.json');
      final data = _tasks
          .where((t) => t.actionDescriptor != null && !t.isCancelled)
          .map((t) => t.toJson())
          .toList();
      await file.writeAsString(jsonEncode(data));
    } catch (e, st) {
      logger.e('保存定时任务失败', error: e, stackTrace: st);
    }
  }

  /// 启动时加载持久化任务（动作描述 → 由执行器触发）
  Future<void> loadTasks() async {
    try {
      final file = await Paths.getPath('mcp_tasks.json');
      if (!await file.exists()) return;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return;
      final list = jsonDecode(content) as List<dynamic>;
      final now = DateTime.now();
      for (final e in list) {
        final t = ScheduledTask.fromJson(e as Map<String, dynamic>);
        if (t.isCancelled) continue;
        final isRepeating = t.repeatMode != 'none';
        // 重复任务过期（应用停用一段时间后）推进到下一个执行点，避免永不执行；
        // cron 解析失败或一次性任务过期则丢弃
        if (isRepeating && t.executeAt.isBefore(now)) {
          DateTime? next;
          switch (t.repeatMode) {
            case 'daily':
              next = DateTime(now.year, now.month, now.day, t.executeAt.hour, t.executeAt.minute, t.executeAt.second);
              if (!next.isAfter(now)) next = next!.add(const Duration(days: 1));
              break;
            case 'weekly':
              if (t.weekdays.isNotEmpty) {
                next = DateTime(now.year, now.month, now.day, t.executeAt.hour, t.executeAt.minute);
                for (int i = 0; i < 9; i++) {
                  if (t.weekdays.contains(next!.weekday) && next.isAfter(now)) break;
                  next = next.add(const Duration(days: 1));
                }
              }
              break;
            case 'interval':
              next = now.add(Duration(minutes: t.intervalMinutes ?? 30));
              break;
            case 'cron':
              next = t.cronExpression == null ? null : CronExpression(t.cronExpression!).next(now);
              break;
          }
          if (next == null || !next.isAfter(now)) continue;
          t.executeAt = next;
        } else if (!t.repeatDaily && t.executeAt.isBefore(now)) {
          // 一次性任务已过期
          continue;
        }
        _tasks.add(t);
      }
      _startCheckTimer();
      logger.i('已加载 ${_tasks.length} 个持久化定时任务');
    } catch (e, st) {
      logger.e('加载定时任务失败', error: e, stackTrace: st);
    }
  }
}

/// 定时任务
class ScheduledTask {
  final String name;
  DateTime executeAt;
  final VoidCallback? action; // 本会话闭包（不持久化）
  final Map<String, dynamic>? actionDescriptor; // 可序列化动作描述

  /// 重复方式：none 一次性 / daily 每天 / weekly 每周 / interval 固定间隔 / cron 表达式
  final String repeatMode;

  /// cron 模式的表达式（分 时 日 月 星期）
  final String? cronExpression;

  /// 重复次数上限，null 表示无限（仅 daily/weekly/interval 模式有效）
  final int? repeatCount;

  /// interval 模式的间隔分钟数
  final int? intervalMinutes;

  /// weekly 模式选中的星期（1=周一 ... 7=周日）
  final List<int> weekdays;

  DateTime? lastExecuted;
  int executedCount = 0;
  bool isCancelled = false;

  /// 兼容旧字段：是否每日重复
  bool get repeatDaily => repeatMode == 'daily';

  ScheduledTask({
    required this.name,
    required this.executeAt,
    this.action,
    this.actionDescriptor,
    String repeatMode = 'none',
    this.repeatCount,
    this.intervalMinutes,
    List<int>? weekdays,
    this.lastExecuted,
    bool repeatDaily = false,
    this.cronExpression,
  })  : repeatMode = (repeatMode == 'none' && repeatDaily) ? 'daily' : repeatMode,
        weekdays = weekdays ?? const [];

  Map<String, dynamic> toJson() => {
        'name': name,
        'executeAt': executeAt.toIso8601String(),
        'repeatMode': repeatMode,
        'repeatDaily': repeatDaily, // 兼容旧版本读取
        if (repeatCount != null) 'repeatCount': repeatCount,
        if (intervalMinutes != null) 'intervalMinutes': intervalMinutes,
        if (weekdays.isNotEmpty) 'weekdays': weekdays,
        if (cronExpression != null) 'cronExpression': cronExpression,
        'executedCount': executedCount,
        if (actionDescriptor != null) 'action': actionDescriptor,
        if (lastExecuted != null) 'lastExecuted': lastExecuted!.toIso8601String(),
      };

  factory ScheduledTask.fromJson(Map<String, dynamic> json) {
    // 兼容旧版本：仅 repeatDaily 字段
    final String mode;
    if (json['repeatMode'] is String) {
      mode = json['repeatMode'] as String;
    } else {
      mode = json['repeatDaily'] == true ? 'daily' : 'none';
    }
    final task = ScheduledTask(
      name: json['name'] as String,
      executeAt: DateTime.parse(json['executeAt'] as String),
      actionDescriptor: json['action'] as Map<String, dynamic>?,
      repeatMode: mode,
      repeatCount: json['repeatCount'] is int ? json['repeatCount'] as int : null,
      intervalMinutes: json['intervalMinutes'] is int ? json['intervalMinutes'] as int : null,
      weekdays: (json['weekdays'] as List?)?.whereType<int>().toList(),
      lastExecuted: json['lastExecuted'] == null ? null : DateTime.tryParse(json['lastExecuted'] as String),
      cronExpression: json['cronExpression'] as String?,
    );
    task.executedCount = json['executedCount'] is int ? json['executedCount'] as int : 0;
    return task;
  }

  /// 重复方式描述（供 UI 展示）
  String repeatLabel(AppLocalizations loc) {
    final weekdayNames = {
      1: loc.mcpSchedMon,
      2: loc.mcpSchedTue,
      3: loc.mcpSchedWed,
      4: loc.mcpSchedThu,
      5: loc.mcpSchedFri,
      6: loc.mcpSchedSat,
      7: loc.mcpSchedSun,
    };
    switch (repeatMode) {
      case 'daily':
        final rc = repeatCount;
        return rc == null ? loc.mcpSchedDaily : loc.mcpSchedDailyCount(rc);
      case 'weekly':
        final days = weekdays.map((w) => weekdayNames[w] ?? '$w').join(loc.mcpSchedWeekdaySep);
        final rc = repeatCount;
        return rc == null ? loc.mcpSchedWeekly(days) : loc.mcpSchedWeeklyCount(days, rc);
      case 'interval':
        final m = intervalMinutes ?? 0;
        final rc = repeatCount;
        return rc == null ? loc.mcpSchedInterval(m) : loc.mcpSchedIntervalCount(m, rc);
      case 'cron':
        return 'Cron: ${cronExpression ?? ''}';
      default:
        return loc.mcpSchedOnce;
    }
  }

  @override
  String toString() {
    return 'ScheduledTask(name: $name, executeAt: $executeAt, repeatMode: $repeatMode, weekdays: $weekdays, repeatCount: $repeatCount)';
  }
}
