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

import 'package:flutter/material.dart';

/// 页面底色：在 M3 的 `surfaceContainerLowest` 上叠一层**极淡的主题色**。
///
/// 为什么不直接用 `surfaceContainerLowest`：Material 3 的 neutral 色板把这个
/// 档位压到了两个极值 —— 浅色下是 `#FFFFFF`、深色下是 `#0F0F0F`，几乎不带
/// seed 的色度。换主题色（红/绿/紫）时它一个像素都不会变，用户看到的就是
/// 「背景写死了、不跟随主题」。
///
/// 这里把 `primary` 按 5%（深色 10%，深色下需要更多才看得出来）混进去：
/// 每种主题色都有可感知的差别，同时仍然是浅底，文字对比度不受影响。
Color surfaceTintOf(ColorScheme scheme) {
  final alpha = scheme.brightness == Brightness.dark ? 0.10 : 0.05;
  return Color.alphaBlend(
    scheme.primary.withValues(alpha: alpha),
    scheme.surfaceContainerLowest,
  );
}

/// 二级面板（卡片/输入区/代码编辑器）：比页面底色再淡一档的主题色。
///
/// 页面底色变「有色」之后，面板保持接近纯白/纯黑就能拉开层次；
/// 但完全纯白在部分主题下会显得很刺眼，所以也留一点主题色。
Color surfacePanelOf(ColorScheme scheme) {
  final alpha = scheme.brightness == Brightness.dark ? 0.05 : 0.02;
  return Color.alphaBlend(
    scheme.primary.withValues(alpha: alpha),
    scheme.surfaceContainerLowest,
  );
}
