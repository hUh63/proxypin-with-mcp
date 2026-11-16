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

import 'package:flutter/material.dart';
import 'package:proxypin/ui/component/surface_tint.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

/// 代码编辑器的配色：语法 token 沿用 atom-one，但**背景与前景取自 App 配色方案**。
///
/// 以前直接用 atom-one 自带的背景（浅色 #FAFAFA / 深色 #282C34）：换主题色、
/// 开莫奈取色、或者浅深切换时，编辑器区域永远是一片固定的灰白/深灰，
/// 跟周围的卡片、页面底色对不上，看着就像「背景是写死的」。
///
/// 这里只覆盖 `root`（背景 + 默认文字色），语法高亮的各个 token 色不动 ——
/// atom-one 的两套 token 色在浅/深底上都已经调好，换掉反而难看。
Map<String, TextStyle> editorThemeOf(BuildContext context) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final base = isDark ? atomOneDarkTheme : atomOneLightTheme;
  final merged = Map<String, TextStyle>.from(base);
  merged['root'] = (base['root'] ?? const TextStyle()).copyWith(
    color: theme.colorScheme.onSurface,
    // 用「带一点主题色的面板色」而不是 surface：#FFFFFF / #0F0F0F 这类纯色
    // 换主题色时不变，编辑器区域看起来像贴了一张白纸。
    backgroundColor: surfacePanelOf(theme.colorScheme),
  );
  return merged;
}
