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
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:proxypin/l10n/app_localizations.dart';

/// 内置 HTML 渲染预览。
///
/// 用纯 Dart 的 `flutter_widget_from_html_core` 把抓到的 HTML **渲染成页面**（而不是
/// 只看源码），全平台可用、不引入 webview / 原生依赖。代价是**不执行 JavaScript**，
/// 纯静态渲染 —— 依赖 JS 才能出内容的 SPA 页面预览不出来（界面已给出提示）。
void showHtmlPreview(BuildContext context, String html) {
  final l = AppLocalizations.of(context)!;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.htmlPreview),
          const SizedBox(height: 2),
          Text(l.htmlPreviewNoJs, style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: SizedBox(
        width: 760,
        height: 580,
        child: Container(
          width: double.infinity,
          color: Colors.white,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: HtmlWidget(
              html,
              textStyle: const TextStyle(color: Colors.black87, fontSize: 14),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.close)),
      ],
    ),
  );
}
