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

import 'package:code_forge/code_forge.dart';

/// 不可见字符可视化的开关（真正的绘制在编辑器内核里完成）。
///
/// 编辑器内核（本 fork 版 code_forge）新增了 `InvisibleCharsStyle`：
/// 它会在**不改动文本**的前提下叠加绘制标记——空格画中点、制表符与控制字符画横条、
/// 零宽与 Unicode 特殊字符画竖线，因此连零宽字符也能被看见，而且完全不影响
/// 光标位置、选区与命中测试。
///
/// 这里只负责保存开关状态并生成内核需要的样式对象；页面把它传给 `CodeForge`
/// 的 `invisibleChars` 参数即可。
class InvisibleCharHighlighter {
  bool showAscii = false;
  bool showUnicode = false;

  bool get enabled => showAscii || showUnicode;

  void setAscii(bool value) => showAscii = value;

  void setUnicode(bool value) => showUnicode = value;

  /// 传给编辑器内核的样式。
  InvisibleCharsStyle get style =>
      InvisibleCharsStyle(ascii: showAscii, unicode: showUnicode);
}
