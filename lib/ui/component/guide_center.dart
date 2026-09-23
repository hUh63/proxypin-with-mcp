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
import 'package:flutter/services.dart' show Clipboard, ClipboardData, rootBundle;
import 'package:flutter_toastr/flutter_toastr.dart';

/// 内置文档中心：离线查看全部功能使用教程、规范文档与开发文档。
///
/// 文档以 Markdown 资源打包（见 pubspec.yaml assets），运行时按需加载，
/// 由轻量渲染器展示（标题/列表/代码块/引用/分隔线/表格文本化）。
class GuideDoc {
  final String id;
  final String title;
  final String category;
  final String assetPath;
  final IconData icon;

  const GuideDoc(this.id, this.title, this.category, this.assetPath, this.icon);
}

class GuideCenter {
  GuideCenter._();

  /// 内置文档清单（id 即 asset 相对路径的 key）
  static const List<GuideDoc> docs = [
    GuideDoc('overview', '功能总览', '快速上手', 'docs/overview.md', Icons.grid_view_outlined),
    GuideDoc('quick_start', '快速上手', '快速上手', 'docs/quick_start.md', Icons.rocket_launch_outlined),
    GuideDoc('certificate_https', '证书与 HTTPS 抓包', '快速上手', 'docs/certificate_https.md', Icons.security_outlined),
    GuideDoc('features_tips', '常用功能技巧', '快速上手', 'docs/features_tips.md', Icons.tips_and_updates_outlined),
    GuideDoc('capture_plan', '采集方案指南', '功能指南', 'docs/capture_plan_guide.md', Icons.route_outlined),
    GuideDoc('security_audit', '安全自检指南', '功能指南', 'docs/security_audit_guide.md', Icons.shield_outlined),
    GuideDoc('mcp_runtime', 'MCP 运行时指南', '功能指南', 'docs/mcp_runtime_guide.md', Icons.dns_outlined),
    GuideDoc('ssl_pinning', '抓不到 HTTPS 排查', '功能指南', 'docs/ssl_pinning_guide.md', Icons.enhanced_encryption_outlined),
    GuideDoc('js_restore', 'JS 还原指南', '功能指南', 'docs/js_restore_guide.md', Icons.auto_fix_high_outlined),
    GuideDoc('fuzzer', '手动 Fuzz 指南', '功能指南', 'docs/fuzzer_guide.md', Icons.science_outlined),
    GuideDoc('extension_guide', '扩展与定制指南', '功能指南', 'docs/extension_guide.md', Icons.extension_outlined),
    GuideDoc('platform_limits', '平台与技术边界', '功能指南', 'docs/platform_limits.md', Icons.construction_outlined),
    GuideDoc('tun_mode', 'TUN 模式可行性评估', '功能指南', 'docs/tun_mode_evaluation.md', Icons.lan_outlined),
    GuideDoc('script', '脚本开发指南', '功能指南', 'docs/script_guide.md', Icons.terminal_outlined),
    GuideDoc('rewrite', '请求重写指南', '功能指南', 'docs/rewrite_guide.md', Icons.edit_note_outlined),
    GuideDoc('environment', '环境变量指南', '功能指南', 'docs/environment_guide.md', Icons.text_snippet_outlined),
    GuideDoc('report_server', '上报服务器指南', '功能指南', 'docs/report_server.md', Icons.cloud_upload_outlined),
    GuideDoc('ai_analysis', 'AI 分析使用指南', '功能指南', 'docs/ai_analysis.md', Icons.auto_awesome_outlined),
    GuideDoc('mcp_automation', 'MCP 自动化指南', '自动化', 'docs/MCP_AUTOMATION_GUIDE.md', Icons.smart_toy_outlined),
    GuideDoc('workflow_tutorial', '工作流编排教程', '自动化', 'docs/WORKFLOW_TUTORIAL.md', Icons.account_tree_outlined),
    GuideDoc('changelog', '更新日志', '文档', 'CHANGELOG.md', Icons.history),
    GuideDoc('agents', '开发文档', '文档', 'AGENTS.md', Icons.code),
    GuideDoc('readme_cn', '项目说明', '文档', 'README_CN.md', Icons.description_outlined),
  ];

  static GuideDoc? byId(String id) {
    for (final d in docs) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// 加载文档内容
  static Future<String> load(GuideDoc doc) async {
    try {
      return await rootBundle.loadString(doc.assetPath);
    } catch (e) {
      return '文档加载失败：$e';
    }
  }

  /// 清除文档本地缓存（重置按钮使用：重新从 assets 加载默认内容）
  static void clearCache(GuideDoc doc) {
    // 文档实时从 assets 读取，无额外缓存层；预留扩展点（用户标注持久化等）
  }
}

/// 文档中心页面：按分类分组的文档列表 + 搜索
class GuideCenterPage extends StatefulWidget {
  const GuideCenterPage({super.key});

  @override
  State<GuideCenterPage> createState() => _GuideCenterPageState();
}

class _GuideCenterPageState extends State<GuideCenterPage> {
  String _keyword = '';

  @override
  Widget build(BuildContext context) {
    final filtered = GuideCenter.docs
        .where((d) => _keyword.isEmpty || d.title.contains(_keyword) || d.category.contains(_keyword))
        .toList();

    // 按分类分组（保持清单顺序）
    final categories = <String>[];
    for (final d in filtered) {
      if (!categories.contains(d.category)) categories.add(d.category);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('使用文档', style: TextStyle(fontSize: 16)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: '搜索文档',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _keyword = v.trim()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                final docs = filtered.where((d) => d.category == category).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 6, left: 4),
                      child: Text(category,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
                    ),
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        children: [
                          for (final doc in docs)
                            ListTile(
                              dense: true,
                              leading: Icon(doc.icon, size: 20, color: Theme.of(context).colorScheme.primary),
                              title: Text(doc.title, style: const TextStyle(fontSize: 14)),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => GuideArticlePage(doc: doc)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 单篇文档阅读页
class GuideArticlePage extends StatefulWidget {
  final GuideDoc doc;

  const GuideArticlePage({super.key, required this.doc});

  @override
  State<GuideArticlePage> createState() => _GuideArticlePageState();
}

class _GuideArticlePageState extends State<GuideArticlePage> {
  String? _content;

  @override
  void initState() {
    super.initState();
    GuideCenter.load(widget.doc).then((content) {
      if (mounted) setState(() => _content = content);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.doc.title, style: const TextStyle(fontSize: 16)),
        centerTitle: true,
        actions: [
          // 重置按钮：恢复文档默认的重点标记说明
          IconButton(
            icon: const Icon(Icons.restart_alt, size: 20),
            tooltip: '重置重点标记说明',
            onPressed: () {
              showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                        title: const Text('重点标记说明', style: TextStyle(fontSize: 15)),
                        content: const Text(
                          '文档中的重点使用多种标记方式呈现：\n\n'
                          '• ==黄色高亮==：关键操作步骤\n'
                          '• 粗体（主题色）：重要概念与入口\n'
                          '• __实线下划线__：需要特别注意的设置\n'
                          '• ~橙色波浪线~：易错点提醒\n'
                          '• ~~删除线~~：已废弃或不推荐的做法\n'
                          '• 等宽底色：命令、路径、代码\n\n'
                          '代码块右下角提供「示例」（演示说明）与「复制」按钮。',
                          style: TextStyle(fontSize: 13, height: 1.6),
                        ),
                        actions: [
                          TextButton(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(
                                    text: '重点标记语法：**粗体** ==高亮== __下划线__ ~~删除线~~ ~波浪线~ 代码；代码块上方可加 <!--demo:说明--> 提供示例说明。'));
                                FlutterToastr.show('标记语法已复制', context);
                              },
                              child: const Text('复制语法')),
                          TextButton(
                              onPressed: () {
                                // 清除本地阅读缓存，下次进入按默认重新渲染
                                GuideCenter.clearCache(widget.doc);
                                setState(() => _content = null);
                                GuideCenter.load(widget.doc).then((content) {
                                  if (mounted) setState(() => _content = content);
                                });
                                Navigator.pop(context);
                                FlutterToastr.show('已恢复默认标记', context, backgroundColor: Colors.green);
                              },
                              child: const Text('重置')),
                        ],
                      ));
            },
          ),
        ],
      ),
      body: _content == null
          ? const Center(child: CircularProgressIndicator())
          : MarkdownLiteView(content: _content!),
    );
  }
}

/// 轻量 Markdown 渲染视图（无第三方依赖）：
/// 支持 #/##/### 标题、- 与 1. 列表、``` 代码块、> 引用、--- 分隔线、表格文本化、**粗体**。
class MarkdownLiteView extends StatelessWidget {
  final String content;

  const MarkdownLiteView({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    try {
      return _build(context);
    } catch (e) {
      // 渲染防御：异常时展示原始内容与错误信息，避免整页白屏
      return SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('渲染异常（已降级为纯文本）：$e',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error)),
          ),
          SelectableText(content, style: const TextStyle(fontSize: 13.5, height: 1.5)),
        ]),
      );
    }
  }

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = content.split('\n');
    final widgets = <Widget>[];
    final buffer = <String>[];
    bool inCode = false;
    final codeLines = <String>[];
    var lastHeading = ''; // 当前章节标题（供示例弹窗展示）

    // 重点标记解析：**粗体** ==高亮== __下划线__ ~~删除线~~ ~波浪线~ `代码`
    List<InlineSpan> parseInline(String text, TextStyle base) {
      final spans = <InlineSpan>[];
      final reg = RegExp(r'\*\*(.+?)\*\*|==(.+?)==|__(.+?)__|~~(.+?)~~|~([^~]+?)~|`([^`]+?)`');
      int last = 0;
      for (final m in reg.allMatches(text)) {
        if (m.start > last) {
          spans.add(TextSpan(text: text.substring(last, m.start), style: base));
        }
        // 捕获组与正则一一对应：g1 粗体 / g2 高亮 / g3 下划线 / g4 删除线 / g5 波浪线 / g6 代码
        final bold = m.group(1);
        final highlight = m.group(2);
        final underline = m.group(3);
        final strike = m.group(4);
        final wavy = m.group(5);
        final code = m.group(6);
        if (bold != null) {
          spans.add(TextSpan(
              text: bold, style: base.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)));
        } else if (highlight != null) {
          spans.add(TextSpan(
              text: highlight,
              style: base.copyWith(
                backgroundColor: const Color(0xFFFFF176).withValues(alpha: theme.brightness == Brightness.dark ? 0.35 : 0.85),
                fontWeight: FontWeight.w600,
              )));
        } else if (underline != null) {
          spans.add(TextSpan(
              text: underline,
              style: base.copyWith(decoration: TextDecoration.underline, decorationThickness: 2.2, fontWeight: FontWeight.w600)));
        } else if (strike != null) {
          spans.add(TextSpan(
              text: strike,
              style: base.copyWith(decoration: TextDecoration.lineThrough, color: theme.colorScheme.outline)));
        } else if (wavy != null) {
          spans.add(TextSpan(
              text: wavy,
              style: base.copyWith(decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.wavy, decorationColor: Colors.orange, decorationThickness: 1.6)));
        } else if (code != null) {
          spans.add(TextSpan(
              text: code,
              style: base.copyWith(
                  fontFamily: 'monospace', fontSize: (base.fontSize ?? 14) - 1.5, backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7), color: theme.brightness == Brightness.dark ? const Color(0xFFE6B455) : const Color(0xFFB35900))));
        }
        last = m.end;
      }
      if (last < text.length) {
        spans.add(TextSpan(text: text.substring(last), style: base));
      }
      return spans.isEmpty ? [TextSpan(text: text, style: base)] : spans;
    }

    // 安全截取：避免对短行做 substring 越界（RangeError）
    String cut(String t, int start) =>
        t.length > start ? t.substring(start) : t;

    void flushParagraph() {
      if (buffer.isEmpty) return;
      final text = buffer.join('\n');
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SelectableText.rich(
          TextSpan(children: parseInline(text, theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14))),
        ),
      ));
      buffer.clear();
    }

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trimLeft().startsWith('```')) {
        if (inCode) {
          final codeText = codeLines.join('\n');
          final demo = codeLines.isNotEmpty && codeLines.first.trimLeft().startsWith('<!--demo:')
              ? codeLines.first.trimLeft().replaceAll('<!--demo:', '').replaceAll('-->', '').trim()
              : null;
          final displayCode = demo == null ? codeText : codeLines.skip(1).join('\n');
          widgets.add(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark ? Colors.grey[900] : const Color(0xFF1E1E1E),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: SelectableText(
                displayCode,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Color(0xFFD4D4D4), height: 1.5),
              ),
            ),
            // 代码块操作条：示例（演示说明）+ 复制
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 2),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark ? Colors.grey[900] : const Color(0xFF1E1E1E),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton.icon(
                  onPressed: () {
                    showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                              title: Text('示例 · $lastHeading', style: const TextStyle(fontSize: 15)),
                              content: Text(
                                demo ?? '这段代码/配置演示了「$lastHeading」章节的用法。将其填入对应功能页即可复现效果。',
                                style: const TextStyle(fontSize: 13.5, height: 1.5),
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了')),
                              ],
                            ));
                  },
                  icon: const Icon(Icons.play_circle_outline, size: 15),
                  label: const Text('示例', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                ),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: displayCode));
                    FlutterToastr.show('代码已复制', context);
                  },
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('复制', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                ),
              ]),
            ),
            const SizedBox(height: 10),
          ]));
          codeLines.clear();
          inCode = false;
        } else {
          flushParagraph();
          inCode = true;
        }
        continue;
      }
      if (inCode) {
        codeLines.add(raw);
        continue;
      }

      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        flushParagraph();
        continue;
      }
      if (trimmed == '---' || trimmed == '***') {
        flushParagraph();
        widgets.add(const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(thickness: 0.5),
        ));
        continue;
      }
      if (trimmed.startsWith('### ')) {
        flushParagraph();
        lastHeading = cut(trimmed, 4);
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text(cut(trimmed, 4),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ));
        continue;
      }
      if (trimmed.startsWith('## ')) {
        flushParagraph();
        lastHeading = cut(trimmed, 3);
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(cut(trimmed, 3),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ));
        continue;
      }
      if (trimmed.startsWith('# ')) {
        flushParagraph();
        lastHeading = cut(trimmed, 2);
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 10),
          child: Text(cut(trimmed, 2),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ));
        continue;
      }
      if (trimmed.startsWith('> ')) {
        flushParagraph();
        widgets.add(Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border(left: BorderSide(width: 3, color: theme.colorScheme.primary)),
          ),
          child: Text(cut(trimmed, 2), style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
        ));
        continue;
      }
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        buffer.add('• ${cut(trimmed, 2)}');
        continue;
      }
      final numbered = RegExp(r'^(\d+)\.\s+(.*)');
      if (numbered.hasMatch(trimmed)) {
        final m = numbered.firstMatch(trimmed)!;
        buffer.add('${m.group(1)}. ${m.group(2)}');
        continue;
      }
      if (trimmed.startsWith('|')) {
        // 表格行：按原样等宽展示（配合上下空行区分）
        buffer.add(trimmed);
        continue;
      }
      buffer.add(trimmed);
    }
    flushParagraph();
    if (inCode && codeLines.isNotEmpty) {
      widgets.add(SelectableText(codeLines.join('\n'),
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace')));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets),
    );
  }
}

/// 打开文档中心（全部文档）
void showGuideCenter(BuildContext context) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => const GuideCenterPage()));
}

/// 打开指定文档（供各功能页的单篇教程入口）
void showGuideArticle(BuildContext context, String docId) {
  final doc = GuideCenter.byId(docId);
  if (doc == null) return;
  Navigator.push(context, MaterialPageRoute(builder: (_) => GuideArticlePage(doc: doc)));
}
