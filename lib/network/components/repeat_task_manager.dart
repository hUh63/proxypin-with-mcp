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

import 'dart:math';

import 'package:flutter/foundation.dart';

/// 重放任务状态
enum RepeatTaskStatus {
  /// 已排期，等待开始（如定时重放的延时阶段）
  scheduled,

  /// 正在发送
  running,

  /// 全部发送完成
  completed,

  /// 用户取消
  canceled,
}

/// 一次重放任务（单请求多次 / 批量 / 定时）
///
/// 上游 #715（查看准备重放的请求列表）与 #401（定时重放任务状态列表）：
/// 重放此前只有对话框内的即时统计，关闭页面后无从查看；这里把每个任务
/// 登记到全局 [RepeatTaskManager]，UI 可随时查看进度、成败与待发送清单。
class RepeatTask {
  /// 任务 id
  final String id;

  /// 任务标题，如 `GET api.example.com/user`
  String title;

  /// 创建时间
  final DateTime createdAt;

  /// 计划开始时间（定时重放才有）
  DateTime? scheduledAt;

  /// 状态
  RepeatTaskStatus status;

  /// 计划总次数
  int total;

  /// 已执行次数
  int executed;

  /// 成功次数
  int success;

  /// 失败次数
  int failed;

  /// 重试次数
  int retried;

  /// 最近一次错误
  String? lastError;

  /// 待发送请求摘要（#715：准备发送的请求列表）
  List<String> pending;

  RepeatTask({
    required this.id,
    required this.title,
    required this.createdAt,
    this.scheduledAt,
    this.status = RepeatTaskStatus.scheduled,
    this.total = 1,
    this.executed = 0,
    this.success = 0,
    this.failed = 0,
    this.retried = 0,
    this.lastError,
    this.pending = const [],
  });

  bool get isFinished => status == RepeatTaskStatus.completed || status == RepeatTaskStatus.canceled;

  /// 进度 0.0 ~ 1.0
  double get progress => total <= 0 ? 0 : (executed / total).clamp(0.0, 1.0);

  /// 剩余待发送次数
  int get remaining => max(0, total - executed);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'scheduledAt': scheduledAt?.millisecondsSinceEpoch,
        'status': status.name,
        'total': total,
        'executed': executed,
        'success': success,
        'failed': failed,
        'retried': retried,
        'lastError': lastError,
        'pending': pending,
      };
}

/// 重放任务管理器（单例，内存态：进程内有效，重启清空）
class RepeatTaskManager {
  RepeatTaskManager._();

  static final RepeatTaskManager instance = RepeatTaskManager._();

  /// 仅保留最近 [maxTasks] 条任务，避免长期运行无限增长
  static const int maxTasks = 50;

  final List<RepeatTask> tasks = [];

  /// 变更通知（UI 用 ValueListenableBuilder 订阅）
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final Random _random = Random();

  String _newId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(1 << 20).toRadixString(16)}';

  /// 创建任务并登记
  RepeatTask create({
    required String title,
    int total = 1,
    DateTime? scheduledAt,
    List<String> pending = const [],
  }) {
    final task = RepeatTask(
      id: _newId(),
      title: title,
      createdAt: DateTime.now(),
      scheduledAt: scheduledAt,
      status: RepeatTaskStatus.scheduled,
      total: total,
      pending: List<String>.unmodifiable(pending),
    );
    tasks.insert(0, task);
    if (tasks.length > maxTasks) {
      tasks.removeRange(maxTasks, tasks.length);
    }
    notify();
    return task;
  }

  /// 标记任务开始发送
  void markRunning(RepeatTask task) {
    if (task.status == RepeatTaskStatus.canceled) {
      return;
    }
    task.status = RepeatTaskStatus.running;
    task.scheduledAt = null;
    notify();
  }

  /// 记录一次执行结果
  void record(RepeatTask task, {required bool ok, String? error}) {
    task.executed++;
    if (ok) {
      task.success++;
    } else {
      task.failed++;
      task.lastError = error;
    }
    notify();
  }

  /// 记录一次重试
  void recordRetry(RepeatTask task) {
    task.retried++;
    notify();
  }

  /// 标记任务完成
  void markCompleted(RepeatTask task) {
    if (task.status == RepeatTaskStatus.canceled) {
      return;
    }
    task.status = RepeatTaskStatus.completed;
    notify();
  }

  /// 取消任务
  void cancel(RepeatTask task) {
    if (!task.isFinished) {
      task.status = RepeatTaskStatus.canceled;
      notify();
    }
  }

  /// 移除单条记录
  void remove(RepeatTask task) {
    tasks.remove(task);
    notify();
  }

  /// 清除已结束的记录（进行中的保留）
  void clearFinished() {
    tasks.removeWhere((t) => t.isFinished);
    notify();
  }

  /// 清空全部
  void clear() {
    tasks.clear();
    notify();
  }

  void notify() => revision.value++;
}
