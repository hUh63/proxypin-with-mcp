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
      await _atomicWrite(file, content, flush: flush);
    });
    // 队列里只保留「已结束」的 future，避免错误沿链传播把后续写入全卡死。
    _queues[key] = next.catchError((Object _) {});
    return next;
  }

  /// 先写同目录临时文件再 rename，尽量做到「要么是旧内容、要么是新内容」。
  ///
  /// `writeAsString` 是「截断 + 写」：写的过程中若被读取（UI 刷新、MCP 查询、
  /// 另一个模块 reload），读到的可能是空文件或半截 JSON —— 半截 JSON 解析失败后
  /// 该模块会退回默认值，下次保存再把默认值写回磁盘，用户的配置就永久丢了。
  static Future<void> _atomicWrite(File file, String content, {bool flush = false}) async {
    final tmp = File('${file.path}.tmp');
    try {
      await tmp.writeAsString(content, flush: flush);
      await tmp.rename(file.path);
    } catch (_) {
      // 少数平台/文件系统上目标已存在时 rename 会失败：退回直接覆盖。
      try {
        await file.writeAsString(content, flush: flush);
      } finally {
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {
          // 清理失败不影响主流程
        }
      }
    }
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
