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

import 'dart:async';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:proxypin/utils/text_special_chars.dart';

/// 不可见字符着色用的高亮样式：
/// - currentMatchStyle（蓝）对应 ASCII 空格 / 控制字符；
/// - otherMatchStyle（橙）对应 Unicode 特殊字符。
const MatchHighlightStyle kInvisibleCharHighlightStyle = MatchHighlightStyle(
  currentMatchStyle: TextStyle(backgroundColor: Color(0x5533A1FF)),
  otherMatchStyle: TextStyle(backgroundColor: Color(0x55FF9800)),
);

/// 不可见字符可视化：把空格、制表符、零宽字符等以底色标出。
///
/// 用法：
/// ```dart
/// final highlighter = InvisibleCharHighlighter();
/// highlighter.attach(controller);   // initState
/// highlighter.detach();             // dispose
/// highlighter.setAscii(true);       // 菜单开关
/// ```
///
/// 编辑器内核（code_forge）没有"渲染空白字符"的开关，也不允许注入自定义
/// InlayHint，因此这里用 searchHighlights 给不可见字符**底色**——位置能看见，
/// 但零宽字符本身没有宽度，仍无法显示，请配合「特殊字符检测」定位。
class InvisibleCharHighlighter {
  /// 单个控制字符按 1 个 utf16 code unit 计算，超出上限只着色前 N 个。
  static const int maxHighlights = 3000;

  bool showAscii = false;
  bool showUnicode = false;

  CodeForgeController? _controller;
  VoidCallback? _listener;
  Timer? _timer;
  String _lastText = '';

  bool get enabled => showAscii || showUnicode;

  void attach(CodeForgeController controller) {
    _controller = controller;
    _listener = _onControllerChanged;
    _lastText = controller.text;
    controller.addListener(_listener!);
  }

  void detach() {
    _timer?.cancel();
    _timer = null;
    final listener = _listener;
    if (listener != null) {
      _controller?.removeListener(listener);
    }
    _listener = null;
    _controller = null;
  }

  void setAscii(bool value) {
    showAscii = value;
    apply();
  }

  void setUnicode(bool value) {
    showUnicode = value;
    apply();
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.text == _lastText) return; // 选区 / 滚动变化忽略
    _lastText = controller.text;
    if (!enabled) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 600), apply);
  }

  /// 重新计算并写入高亮（关闭时清空）。
  void apply() {
    final controller = _controller;
    if (controller == null) return;

    if (!enabled) {
      if (controller.searchHighlights.isNotEmpty) {
        controller.searchHighlights = [];
        controller.searchHighlightsChanged = true;
        controller.notifyListeners();
      }
      return;
    }

    final hits = SpecialCharScanner.scan(controller.text,
        ascii: showAscii, unicode: showUnicode, limit: maxHighlights + 1);
    final shown = hits.length > maxHighlights ? hits.sublist(0, maxHighlights) : hits;
    controller.searchHighlights = shown
        .map((h) => SearchHighlight(
              start: h.index,
              end: h.index + 1,
              isCurrentMatch: h.kind == SpecialCharKind.ascii,
            ))
        .toList();
    controller.searchHighlightsChanged = true;
    controller.notifyListeners();
    _lastText = controller.text;
  }
}
