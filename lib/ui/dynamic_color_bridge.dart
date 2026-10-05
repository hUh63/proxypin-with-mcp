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
import 'package:flutter/material.dart' as material;
import 'package:material_ui/material_ui.dart' as mui;

/// 把 `dynamic_color` 2.x 产出的 `material_ui.ColorScheme` 转成本项目在用的
/// `package:flutter/material` 的 `ColorScheme`。
///
/// 为什么要这一步：`dynamic_color` 从 2.0 起改用独立的 `material_ui` 包，
/// 它定义的 `ColorScheme` 与 Flutter 自带的 `ColorScheme` **是两个不同的类**，
/// 不能直接赋给 `ThemeData.colorScheme`。好在两边的颜色字段都是 `dart:ui.Color`、
/// `Brightness` 也是 `dart:ui.Brightness`（同一个类），所以只需逐字段搬运。
///
/// 做法：先用种子色构造一个同亮度的基色板（补齐双方共有的隐含字段），再把
/// 动态色板的 46 个角色逐一覆盖。刻意跳过 `background`/`onBackground`/`surfaceVariant`
/// 三个已被 Flutter 弃用的别名，避免弃用告警。
material.ColorScheme dynamicToMaterialColorScheme(mui.ColorScheme s) {
  final base = material.ColorScheme.fromSeed(seedColor: s.primary, brightness: s.brightness);
  return base.copyWith(
    primary: s.primary,
    onPrimary: s.onPrimary,
    primaryContainer: s.primaryContainer,
    onPrimaryContainer: s.onPrimaryContainer,
    primaryFixed: s.primaryFixed,
    primaryFixedDim: s.primaryFixedDim,
    onPrimaryFixed: s.onPrimaryFixed,
    onPrimaryFixedVariant: s.onPrimaryFixedVariant,
    secondary: s.secondary,
    onSecondary: s.onSecondary,
    secondaryContainer: s.secondaryContainer,
    onSecondaryContainer: s.onSecondaryContainer,
    secondaryFixed: s.secondaryFixed,
    secondaryFixedDim: s.secondaryFixedDim,
    onSecondaryFixed: s.onSecondaryFixed,
    onSecondaryFixedVariant: s.onSecondaryFixedVariant,
    tertiary: s.tertiary,
    onTertiary: s.onTertiary,
    tertiaryContainer: s.tertiaryContainer,
    onTertiaryContainer: s.onTertiaryContainer,
    tertiaryFixed: s.tertiaryFixed,
    tertiaryFixedDim: s.tertiaryFixedDim,
    onTertiaryFixed: s.onTertiaryFixed,
    onTertiaryFixedVariant: s.onTertiaryFixedVariant,
    error: s.error,
    onError: s.onError,
    errorContainer: s.errorContainer,
    onErrorContainer: s.onErrorContainer,
    surface: s.surface,
    onSurface: s.onSurface,
    surfaceDim: s.surfaceDim,
    surfaceBright: s.surfaceBright,
    surfaceContainerLowest: s.surfaceContainerLowest,
    surfaceContainerLow: s.surfaceContainerLow,
    surfaceContainer: s.surfaceContainer,
    surfaceContainerHigh: s.surfaceContainerHigh,
    surfaceContainerHighest: s.surfaceContainerHighest,
    onSurfaceVariant: s.onSurfaceVariant,
    outline: s.outline,
    outlineVariant: s.outlineVariant,
    shadow: s.shadow,
    scrim: s.scrim,
    inverseSurface: s.inverseSurface,
    onInverseSurface: s.onInverseSurface,
    inversePrimary: s.inversePrimary,
    surfaceTint: s.surfaceTint,
  );
}
