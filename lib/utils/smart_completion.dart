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

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「智能预测」（本地代码补全）的全局开关。
///
/// 打开时：编辑器在输入时给出候选 —— 文档里出现过的词、当前语言的常用关键字、
/// 以及按**光标上下文 / 代码格式**推断的候选（JSON 的 key、XML 的标签…）；
/// 关闭时完全不提示。开关状态全局共享，任一编辑器页切换后其它页立即同步。
class SmartCompletion {
  SmartCompletion._();

  static const String _prefKey = 'smart_completion_v1';

  /// 全局开关状态。默认开启。
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  static bool _loaded = false;

  /// 从本地偏好读取开关状态（幂等，重复调用只读一次）。
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final value = await SharedPreferencesAsync().getBool(_prefKey);
      if (value != null) enabled.value = value;
    } catch (_) {
      // 读取失败时保持默认值。
    }
  }

  /// 切换并持久化开关状态。
  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    try {
      await SharedPreferencesAsync().setBool(_prefKey, value);
    } catch (_) {
      // 持久化失败不影响本次会话内的状态。
    }
  }
}
