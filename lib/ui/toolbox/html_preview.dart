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

// 文本编辑器里的「预览」。
//
// 编辑 HTML / SVG / Markdown 时最常见的动作就是「看看长什么样」，而切到浏览器
// 再回来心智成本很高。这里就地渲染：
//   * HTML / Vue 模板 / XML 片段 → 交给 HtmlWidget 排版（纯 Dart，无原生 webview）；
//   * Markdown → 复用文档中心那套渲染器（代码块、提示块、表格都对）；
//   * SVG → 包一层 `<html><body>` 后渲染。
//
// 预览只是「看一眼」，不执行脚本（HtmlWidget 本身也不跑 JS），所以不存在
// 网页把你编辑器里的东西读走的问题。
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/component/guide_center.dart';

/// 判断某种语法能不能预览（编辑器工具栏据此决定按钮是否出现）。
bool canPreviewLanguage({required String key, required String label}) {
  final k = key.toLowerCase();
  if (k == 'html' || k == 'xml' || k == 'svg' || k == 'vue' || k == 'markdown') return true;
  final l = label.toLowerCase();
  return l.contains('html') || l.contains('markdown') || l.contains('svg') || l.contains('xml');
}

/// 内容预览页。
class HtmlPreviewPage extends StatelessWidget {
  /// 要预览的源码。
  final String content;

  /// 语法标识（re_highlight 的 key）或语言名，用来决定怎么渲染。
  final String language;

  /// 标题（一般是文件名）。
  final String title;

  const HtmlPreviewPage({
    super.key,
    required this.content,
    required this.language,
    this.title = '',
  });

  static Future<void> show(
    BuildContext context, {
    required String content,
    required String language,
    String title = '',
  }) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HtmlPreviewPage(content: content, language: language, title: title),
    ));
  }

  bool get _isMarkdown => language.toLowerCase().contains('markdown');

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title.isEmpty ? localizations.editorPreview : '${localizations.editorPreview} · $title',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
        ),
        actions: [
          IconButton(
            tooltip: localizations.editorPreviewHint,
            icon: const Icon(Icons.info_outline, size: 18),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(localizations.editorPreviewHint, style: const TextStyle(fontSize: 15)),
                content: Text(localizations.editorPreviewHintBody, style: const TextStyle(fontSize: 13)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localizations.guideGotIt)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Container(
        color: _isMarkdown ? theme.colorScheme.surface : Colors.white,
        child: _isMarkdown
            ? MarkdownLiteView(content: content)
            : SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: HtmlWidget(
                  _wrap(),
                  textStyle: const TextStyle(fontSize: 14, height: 1.5),
                  onTapUrl: (_) async => true,
                ),
              ),
      ),
    );
  }

  /// 片段补成完整文档：HTML 片段没有 `<html>` 时包一层（默认字体/边距更正常）。
  String _wrap() {
    final text = content.trimLeft();
    final lower = text.toLowerCase();
    if (lower.startsWith('<!doctype') || lower.startsWith('<html')) return content;
    if (lower.startsWith('<svg')) {
      return '<html><body style="margin:0">'
          '<div style="display:flex;justify-content:center">$content</div></body></html>';
    }
    return '<html><body>$content</body></html>';
  }
}
