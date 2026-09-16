/*
 * Copyright 2025 Hongen Wang All rights reserved.
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

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 图片 data URI 解析（上游 #873：脚本日志直接输出图片，例如二维码）。
///
/// 脚本里 `console.log('data:image/png;base64,' + base64)` 输出后，
/// 日志面板会把它渲染成图片，免去"复制 base64 → 另行转码"的来回。
/// 返回 null 表示不是可识别的图片 data URI（按普通文本处理）。

final RegExp _imageDataUri = RegExp(
  r'^data:image/(png|jpe?g|gif|webp|bmp);base64,([A-Za-z0-9+/=\s]+)$',
  caseSensitive: false,
);

/// base64 长度上限（约 1.5MB 原始数据），避免一条日志把内存吃光
const int maxImageDataUriLength = 2 * 1024 * 1024;

/// 解析图片 data URI；不是图片或解码失败时返回 null
Uint8List? decodeImageDataUri(String text) {
  final trimmed = text.trim();
  if (!trimmed.startsWith('data:image/')) return null;
  if (trimmed.length > maxImageDataUriLength) return null;

  final match = _imageDataUri.firstMatch(trimmed);
  if (match == null) return null;

  try {
    return base64Decode(match.group(2)!.replaceAll(RegExp(r'\s'), ''));
  } catch (_) {
    return null;
  }
}

/// 日志内容渲染（上游 #873）：内容若是图片 data URI 就直接显示图片，
/// 否则按普通文本显示。脚本里 `console.log('data:image/png;base64,' + b64)` 即可出图。
Widget scriptLogContent(String output, {TextStyle? style, double size = 160}) {
  final image = decodeImageDataUri(output);
  if (image == null) {
    return SelectableText(output, style: style);
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(image, width: size, height: size, fit: BoxFit.contain),
        ),
      ),
      Text(
        'image · ${(image.lengthInBytes / 1024).toStringAsFixed(1)} KB',
        style: (style ?? const TextStyle()).copyWith(fontSize: 11, color: Colors.grey),
      ),
    ],
  );
}
