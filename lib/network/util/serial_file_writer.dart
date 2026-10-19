/*
 * Copyright 2026 Hongen Wang All rights reserved.
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

import 'dart:io';

/// 按文件路径串行化的写入器。
///
/// 配置类文件（rewrite / hosts / block / breakpoint / script / 定时任务…）
/// 都是「整份 JSON 覆盖写」，而保存函数很容易被并发触发：UI 连续拖动、
/// MCP 批量改配置、导入时循环调用。`File.writeAsString` 是「截断 + 写」，
/// 两个写并发时会互相截断/交错，结果是文件被写坏，下次启动配置全丢。
///
/// 这里按路径排队，保证同一文件永远只有一次写在跑；错误通过返回值抛给
/// 调用方，不会卡住后续写入。
class SerialFileWriter {
  static final Map<String, Future<void>> _queues = {};

  static Future<void> writeString(File file, String content, {bool flush = false}) {
    final key = file.path;
    final previous = _queues[key] ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then<void>((_) async {
      await file.writeAsString(content, flush: flush);
    });
    // 队列里只保留「已结束」的 future，避免错误沿链传播把后续写入全卡死。
    _queues[key] = next.catchError((Object _) {});
    return next;
  }

  /// 需要在写入过程中自己控制 I/O（大文件逐条写、复用 IOSink 缓冲）时用这个：
  /// 同一文件的 [action] 会按顺序串行执行。
  static Future<void> run(File file, Future<void> Function(File file) action) {
    final key = file.path;
    final previous = _queues[key] ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then<void>((_) => action(file));
    _queues[key] = next.catchError((Object _) {});
    return next;
  }
}
