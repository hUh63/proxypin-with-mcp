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

// ARTEX 的 7 个面板。页面壳（连接、壳层、页签）在 artex_page.dart。
//
// 设计取向：ARTEX 是 headless 的（web UI 已弃用、内置 LLM 恒 idle），所以这里
// 不是「给浏览器加个壳」，而是把它的 15 个能力做成**能直接干活**的界面 ——
// 建任务、暂停/恢复、加目标、看发现、跑工具（含参数）、读日志、翻工作区。
// 未知字段一律保留原始 JSON（详情页可看 raw），服务端升级不会把页面搞白。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/artex_client.dart';
import 'package:proxypin/network/util/artex_service.dart';
import 'package:proxypin/network/util/artex_session.dart';
import 'package:proxypin/ui/component/ai_analysis.dart';

const JsonEncoder _pretty = JsonEncoder.withIndent('  ');

/// 任务状态 → 颜色。
Color artexStatusColor(ThemeData theme, String status) {
  final s = status.toLowerCase();
  if (s.contains('run') || s.contains('active') || s.contains('exec')) {
    return Colors.green;
  }
  if (s.contains('pause') || s.contains('suspend')) return Colors.orange;
  if (s.contains('fail') || s.contains('error') || s.contains('abort')) return Colors.red;
  if (s.contains('done') || s.contains('complete') || s.contains('finish')) {
    return theme.colorScheme.primary;
  }
  return Colors.blueGrey;
}

/// 严重程度 → 颜色。
Color artexSeverityColor(String severity) {
  switch (severity.toLowerCase()) {
    case 'critical':
    case 'crit':
      return const Color(0xFFB71C1C);
    case 'high':
      return const Color(0xFFE53935);
    case 'medium':
    case 'med':
      return const Color(0xFFFB8C00);
    case 'low':
      return const Color(0xFFFDD835);
    default:
      return const Color(0xFF78909C);
  }
}

/// 面板通用的小标题。
Widget artexSectionTitle(BuildContext context, String text, {Widget? trailing}) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
    child: Row(
      children: [
        Text(text,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const Spacer(),
        if (trailing != null) trailing,
      ],
    ),
  );
}

/// 空态提示。
Widget artexEmpty(BuildContext context, String text, {IconData icon = Icons.inbox_outlined}) {
  final theme = Theme.of(context);
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: theme.disabledColor),
          const SizedBox(height: 10),
          Text(text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
        ],
      ),
    ),
  );
}

/// 复制到剪贴板 + 提示。
Future<void> artexCopy(BuildContext context, String text, String hint) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(hint), duration: const Duration(milliseconds: 1400)),
  );
}

/// 把 JSON 里的一堆字段渲染成「键值」列表（详情页用）。
Widget artexKeyValues(BuildContext context, Map<String, dynamic> data,
    {int maxItems = 40}) {
  final theme = Theme.of(context);
  final rows = <Widget>[];
  var n = 0;
  for (final e in data.entries) {
    if (n++ >= maxItems) break;
    final v = e.value;
    String text;
    if (v is Map || v is List) {
      text = const JsonEncoder().convert(v);
    } else {
      text = '${v ?? ''}';
    }
    if (text.length > 600) text = '${text.substring(0, 600)}…';
    rows.add(Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(e.key,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          ),
          Expanded(
            child: SelectableText(text, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    ));
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
}

/// 底部弹出的大块内容（原始 JSON / 文件内容 / 工具结果）。
Future<void> artexShowTextSheet(
  BuildContext context, {
  required String title,
  required String text,
  bool mono = true,
}) {
  final theme = Theme.of(context);
  final loc = AppLocalizations.of(context)!;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      maxChildSize: 0.94,
      minChildSize: 0.3,
      builder: (ctx2, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall),
                ),
                IconButton(
                  tooltip: loc.copy,
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  onPressed: () => artexCopy(ctx2, text, loc.copied),
                ),
                IconButton(
                  tooltip: loc.close,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(ctx2).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: controller,
              child: SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 22),
                child: SelectableText(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: mono ? 'monospace' : null,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ============================== 概览 ==============================

class ArtexOverviewPanel extends StatelessWidget {
  final ArtexSession session;
  final VoidCallback onRefresh;
  final VoidCallback onOpenConsole;
  final VoidCallback onOpenService;

  const ArtexOverviewPanel({
    super.key,
    required this.session,
    required this.onRefresh,
    required this.onOpenConsole,
    required this.onOpenService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final h = session.health;
        final stats = session.stats;
        return RefreshIndicator(
          onRefresh: () async => session.refresh(),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Card(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (h?.ok ?? false) ? Colors.green : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (h?.ok ?? false) ? loc.artexConnected : 'ARTEX',
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              [
                                if ((h?.version ?? '').isNotEmpty)
                                  '${loc.artexVersion} ${h!.version}',
                                if (h != null) '${h.ms}ms',
                                session.baseUrl,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.hintColor),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: loc.refresh,
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: onRefresh,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    _StatCard(
                      label: loc.artexTasks,
                      value: '${session.tasks.length}',
                      icon: Icons.account_tree_outlined,
                    ),
                    _StatCard(
                      label: loc.artexAssets,
                      value: '${stats['assets'] ?? stats['sites'] ?? '-'}',
                      icon: Icons.dns_outlined,
                    ),
                    _StatCard(
                      label: 'Findings',
                      value: '${stats['findings'] ?? stats['findings_total'] ?? '-'}',
                      icon: Icons.report_gmailerrorred_outlined,
                    ),
                  ],
                ),
              ),
              if (session.activeTask.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(loc.artexActiveTask),
                  subtitle: Text(session.activeTask),
                  trailing: IconButton(
                    tooltip: loc.copy,
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () =>
                        artexCopy(context, session.activeTask, loc.copied),
                  ),
                ),
              Card(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Column(
                  children: [
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.memory_outlined, size: 20),
                      title: Text(loc.artexEngine),
                      subtitle: Text(
                        '${stats['engine_mode'] ?? stats['mode'] ?? session.llm['mode'] ?? 'idle'}'
                        ' · ${loc.artexLlm}: '
                        '${(stats['llm_configured'] == true || session.llm['configured'] == true) ? loc.artexYes : loc.artexNo}',
                      ),
                    ),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.terminal, size: 20),
                      title: Text(loc.artexLocalTitle),
                      subtitle: Text(
                        ArtexService.supported
                            ? (session.service.processAlive
                                ? 'PID ${session.service.pid}'
                                : (session.service.rooted ? 'stopped' : 'no root'))
                            : loc.artexNotAndroid,
                      ),
                      trailing: TextButton(
                        onPressed: onOpenService,
                        child: Text(loc.artexServiceStatus),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onOpenConsole,
                        icon: const Icon(Icons.code, size: 16),
                        label: Text(loc.artexOpenConsole),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(loc.refresh),
                      ),
                    ),
                  ],
                ),
              ),
              if (session.lastError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(session.lastError!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error)),
                ),
              if (stats.isNotEmpty) ...[
                artexSectionTitle(context, 'Stats'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  child: artexKeyValues(context, stats, maxItems: 18),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(height: 6),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor)),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================== 任务 ==============================

class ArtexTasksPanel extends StatelessWidget {
  final ArtexSession session;

  const ArtexTasksPanel({super.key, required this.session});

  Future<void> _create(BuildContext context) async {
    final loc = AppLocalizations.of(context)!;
    final desc = TextEditingController();
    final goal = TextEditingController();
    final name = TextEditingController();
    final theme = Theme.of(context);
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loc.artexCreateTask, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(loc.artexTaskDescHint,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
              const SizedBox(height: 12),
              TextField(
                controller: desc,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: '${loc.artexTaskDesc} *',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: goal,
                decoration: InputDecoration(
                  labelText: loc.artexTaskGoal,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: loc.name,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(loc.cancel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(loc.confirm),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final d = desc.text;
    final g = goal.text;
    final n = name.text;
    desc.dispose();
    goal.dispose();
    name.dispose();
    if (created != true || !context.mounted) return;
    if (d.trim().isEmpty) return;
    final r = await session.createTask(description: d.trim(), goal: g.trim(), name: n.trim());
    if (!context.mounted) return;
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.text)));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(loc.artexTaskCreated)));
    }
  }

  Future<void> _addGoal(BuildContext context, ArtexTask task) async {
    final loc = AppLocalizations.of(context)!;
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.artexAddGoal),
        content: TextField(
          controller: c,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(hintText: loc.artexGoalHint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(loc.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(loc.add)),
        ],
      ),
    );
    final text = c.text;
    c.dispose();
    if (ok != true || text.trim().isEmpty) return;
    final err = await session.addGoal(task.id, text.trim());
    if (!context.mounted) return;
    if (err.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _detail(BuildContext context, ArtexTask task) async {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    Map<String, dynamic> raw = task.raw;
    try {
      final d = await session.client?.task(task.id);
      if (d != null && d.isNotEmpty) raw = d;
    } catch (_) {
      // 详情拿不到就用列表里的字段，别把弹窗卡住
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.66,
        maxChildSize: 0.94,
        builder: (ctx2, controller) => ListView(
          controller: controller,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(task.displayName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: loc.copy,
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () => artexCopy(ctx2, task.id, loc.copied),
                  ),
                ],
              ),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.flag_outlined,
                  size: 20, color: artexStatusColor(theme, task.status)),
              title: Text(task.status),
              subtitle: Text(task.id, style: theme.textTheme.bodySmall),
            ),
            if (task.description.isNotEmpty)
              ListTile(
                dense: true,
                leading: const Icon(Icons.description_outlined, size: 20),
                title: Text(loc.artexTaskDesc),
                subtitle: SelectableText(task.description),
              ),
            if (task.goal.isNotEmpty)
              ListTile(
                dense: true,
                leading: const Icon(Icons.gps_fixed, size: 20),
                title: Text(loc.artexTaskGoal),
                subtitle: SelectableText(task.goal),
              ),
            if (task.goals.isNotEmpty) ...[
              artexSectionTitle(context, 'Goals'),
              for (var i = 0; i < task.goals.length; i++)
                ListTile(
                  dense: true,
                  leading: Text('${i + 1}'),
                  title: Text(task.goals[i]),
                ),
            ],
            artexSectionTitle(context, loc.artexRawJson),
            artexKeyValues(context, raw, maxItems: 40),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        Navigator.of(ctx2).pop();
                        await session.controlTask(task.id, 'pause');
                      },
                      child: Text(loc.artexPause),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        Navigator.of(ctx2).pop();
                        await session.controlTask(task.id, 'resume');
                      },
                      child: Text(loc.artexResume),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        return Stack(
          children: [
            if (session.tasks.isEmpty)
              artexEmpty(context, loc.artexNoTasks, icon: Icons.account_tree_outlined)
            else
              RefreshIndicator(
                onRefresh: () async => session.refresh(),
                child: ListView.separated(
                  padding: const EdgeInsets.only(top: 4, bottom: 96),
                  itemCount: session.tasks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final t = session.tasks[i];
                    final color = artexStatusColor(theme, t.status);
                    return ListTile(
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(t.displayName,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(t.status,
                                style: theme.textTheme.labelSmall?.copyWith(color: color)),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        [
                          t.goal.isEmpty ? t.description : t.goal,
                          if (t.findingsCritical > 0) 'critical ${t.findingsCritical}',
                          if (t.findingsHigh > 0) 'high ${t.findingsHigh}',
                          if (t.id == session.activeTask) '★',
                        ].where((e) => e.isNotEmpty).join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      leading: Icon(
                        t.isRunning
                            ? Icons.play_circle_fill
                            : (t.isPaused ? Icons.pause_circle_filled : Icons.circle_outlined),
                        color: color,
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          switch (v) {
                            case 'pause':
                              await session.controlTask(t.id, 'pause');
                              break;
                            case 'resume':
                              await session.controlTask(t.id, 'resume');
                              break;
                            case 'goal':
                              if (context.mounted) await _addGoal(context, t);
                              break;
                            case 'workspace':
                              await session.loadWorkspace(t.id);
                              break;
                            case 'copy':
                              if (context.mounted) {
                                await artexCopy(context, t.id, loc.copied);
                              }
                              break;
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'pause', child: Text(loc.artexPause)),
                          PopupMenuItem(value: 'resume', child: Text(loc.artexResume)),
                          PopupMenuItem(value: 'goal', child: Text(loc.artexAddGoal)),
                          PopupMenuItem(value: 'workspace', child: Text(loc.artexTabWorkspace)),
                          PopupMenuItem(value: 'copy', child: Text(loc.copy)),
                        ],
                      ),
                      onTap: () => _detail(context, t),
                    );
                  },
                ),
              ),
            Positioned(
              right: 16,
              bottom: 18,
              child: FloatingActionButton.extended(
                onPressed: () => _create(context),
                icon: const Icon(Icons.add),
                label: Text(loc.artexCreateTask),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================== 发现 ==============================

class ArtexFindingsPanel extends StatelessWidget {
  final ArtexSession session;

  const ArtexFindingsPanel({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return StatefulBuilder(builder: (context, setLocal) {
      final severities = <String>{
        for (final f in session.findings) f.severity,
      }.toList()
        ..sort();
      final filtered = session.findings;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${filtered.length}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: loc.refresh,
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () => session.loadFindings(),
                ),
                if (severities.isNotEmpty)
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final s in severities)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: artexSeverityColor(s).withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '$s ${session.findings.where((f) => f.severity == s).length}',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(color: artexSeverityColor(s)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? artexEmpty(context, loc.artexNoFindings,
                    icon: Icons.report_gmailerrorred_outlined)
                : RefreshIndicator(
                    onRefresh: () async => session.loadFindings(),
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final f = filtered[i];
                        final color = artexSeverityColor(f.severity);
                        return ListTile(
                          dense: true,
                          leading: Container(
                            width: 4,
                            height: 34,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          title: Text(
                            f.title.isEmpty ? f.id : f.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [f.severity.toUpperCase(), f.createdAt, f.taskId]
                                .where((e) => e.isNotEmpty)
                                .join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          trailing: TextButton(
                            onPressed: () async {
                              String text = _pretty.convert(f.raw);
                              final c = session.client;
                              if (c != null) {
                                try {
                                  final d = await c.finding(f.id);
                                  if (d.isNotEmpty) text = _pretty.convert(d);
                                } catch (_) {
                                  // 详情接口不可用就看列表里带的
                                }
                              }
                              if (!context.mounted) return;
                              await artexShowTextSheet(context,
                                  title: f.title.isEmpty ? f.id : f.title, text: text);
                            },
                            child: Text(loc.more),
                          ),
                          onLongPress: () => artexCopy(context, _pretty.convert(f.raw), loc.copied),
                        );
                      },
                    ),
                  ),
          ),
        ],
      );
    });
  }
}

// ============================== 工具 ==============================

class ArtexToolsPanel extends StatefulWidget {
  final ArtexSession session;

  const ArtexToolsPanel({super.key, required this.session});

  @override
  State<ArtexToolsPanel> createState() => _ArtexToolsPanelState();
}

class _ArtexToolsPanelState extends State<ArtexToolsPanel> {
  final _search = TextEditingController();
  String _kind = 'all';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await widget.session.loadTools();
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ArtexTool> get _visible {
    final q = _search.text.trim().toLowerCase();
    return widget.session.tools.where((t) {
      if (_kind == 'webpt' && !t.key.startsWith('webpt_')) return false;
      if (_kind == 'custom' && t.kind != 'custom') return false;
      if (q.isEmpty) return true;
      return t.key.toLowerCase().contains(q) ||
          t.name.toLowerCase().contains(q) ||
          t.description.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  Future<void> _run(BuildContext context, ArtexTool tool) async {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final prefill = <String, dynamic>{};
    tool.params.forEach((k, v) {
      // params 可能是 {name: {type, default}} 也可能是 {name: "描述"}
      if (v is Map) {
        final d = v['default'] ?? v['value'];
        if (d != null) prefill[k] = d;
      }
    });
    if (prefill.isEmpty) {
      final tpl = artexWebptTemplates[tool.key];
      if (tpl != null) prefill.addAll(tpl);
    }
    final ctrl = TextEditingController(
        text: prefill.isEmpty ? '{\n  \n}' : _pretty.convert(prefill));
    final result = await showModalBottomSheet<ArtexRunResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.62,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text('${loc.artexRunTool}: ${tool.key}',
                    style: theme.textTheme.titleSmall),
              ),
              if (tool.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(tool.description,
                      style:
                          theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: ctrl,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                    decoration: InputDecoration(
                      labelText: loc.artexRunParams,
                      helperText: loc.artexRunParamsHint,
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(loc.cancel),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          Map<String, dynamic> params;
                          try {
                            final decoded = ctrl.text.trim().isEmpty
                                ? <String, dynamic>{}
                                : jsonDecode(ctrl.text);
                            params = decoded is Map
                                ? artexMapFrom(decoded)
                                : <String, dynamic>{};
                          } catch (e) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('JSON: $e')),
                            );
                            return;
                          }
                          final r = await widget.session.runTool(tool.key, params);
                          if (!ctx.mounted) return;
                          Navigator.of(ctx).pop(r);
                        },
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: Text(loc.artexRun),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    ctrl.dispose();
    if (result == null || !context.mounted) return;
    await artexShowTextSheet(
      context,
      title: '${tool.key} · ${result.ok ? 'OK' : 'FAIL'} · ${result.ms}ms',
      text: result.output.isEmpty ? _pretty.convert(result.raw) : result.output,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      hintText: loc.artexSearchTool,
                      border: const OutlineInputBorder(),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: loc.refresh,
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => widget.session.loadTools(),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              for (final k in const ['all', 'webpt', 'custom'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(switch (k) {
                      'webpt' => 'webpt',
                      'custom' => loc.artexToolKindCustom,
                      _ => loc.all,
                    }),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _visible.isEmpty
              ? artexEmpty(
                  context,
                  _loaded ? loc.artexNoTools : loc.artexLoading,
                  icon: Icons.handyman_outlined,
                )
              : ListView.separated(
                  itemCount: _visible.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final t = _visible[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        t.key.startsWith('webpt_') ? Icons.bolt : Icons.extension_outlined,
                        size: 20,
                        color: t.key.startsWith('webpt_')
                            ? theme.colorScheme.primary
                            : theme.hintColor,
                      ),
                      title: Text(t.key,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12.5)),
                      subtitle: Text(
                        t.description.isEmpty ? t.name : t.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: TextButton(
                        onPressed: () => _run(context, t),
                        child: Text(loc.artexRun),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// webpt 十件套的参数模板（服务端没给默认值时用它兜底预制）。
///
/// 这些键名与 Termux `$HOME/webpt/scripts/tools/` 里的脚本参数一致，也是
/// SKILL.md 里实测过的调用形态 —— 用户点「运行」不用先猜参数名。
const Map<String, Map<String, dynamic>> artexWebptTemplates = {
  'webpt_port_scan': {'target': '', 'ports': '1-1000', 'banner': '1'},
  'webpt_subdomain_enum': {'domain': '', 'wordlist': 'none'},
  'webpt_dir_brute': {'url': '', 'wordlist': '', 'extensions': 'php,html,bak'},
  'webpt_sqli_detect': {'url': '', 'body': 'none', 'method': 'GET'},
  'webpt_xss_detect': {'url': '', 'q': 'FUZZ', 'method': 'GET'},
  'webpt_ssrf_probe': {'url': '', 'mode': 'metadata'},
  'webpt_jwt_attack': {'token': '', 'mode': 'none', 'wordlist': 'none'},
  'webpt_password_spray': {'url': '', 'users': '', 'passwords': ''},
  'webpt_webshell_gen': {'lang': 'php', 'pass': '', 'mode': 'simple', 'filename': ''},
  'webpt_hash_id': {'hash': ''},
};

/// `jsonDecode` 出来的 Map 统一成 `Map<String, dynamic>`。
Map<String, dynamic> artexMapFrom(Map<dynamic, dynamic> m) =>
    m.map((k, v) => MapEntry('$k', v));

// ============================== 日志 ==============================

class ArtexLogsPanel extends StatefulWidget {
  final ArtexSession session;

  const ArtexLogsPanel({super.key, required this.session});

  @override
  State<ArtexLogsPanel> createState() => _ArtexLogsPanelState();
}

class _ArtexLogsPanelState extends State<ArtexLogsPanel> {
  bool _auto = false;
  int _limit = 50;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.session.loadLogs(limit: _limit);
    });
  }

  void _toggleAuto(bool v) {
    setState(() => _auto = v);
    if (v) _poll();
  }

  Future<void> _poll() async {
    while (mounted && _auto) {
      await widget.session.loadLogs(limit: _limit);
      await Future<void>.delayed(const Duration(seconds: 4));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        final lines = widget.session.logs;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 0),
              child: Row(
                children: [
                  Text('${lines.length}',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.hintColor)),
                  const Spacer(),
                  DropdownButton<int>(
                    value: _limit,
                    underline: const SizedBox.shrink(),
                    items: const [30, 50, 100, 200, 500]
                        .map((e) => DropdownMenuItem(value: e, child: Text('$e')))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _limit = v);
                      widget.session.loadLogs(limit: v);
                    },
                  ),
                  IconButton(
                    tooltip: loc.artexAutoRefresh,
                    icon: Icon(_auto ? Icons.pause_circle : Icons.play_circle_outline,
                        size: 20),
                    onPressed: () => _toggleAuto(!_auto),
                  ),
                  IconButton(
                    tooltip: loc.refresh,
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () => widget.session.loadLogs(limit: _limit),
                  ),
                  IconButton(
                    tooltip: loc.copy,
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    onPressed: () => artexCopy(
                      context,
                      lines.map((e) => e.text).join('\n'),
                      loc.copied,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: lines.isEmpty
                  ? artexEmpty(context, loc.artexNoLogs, icon: Icons.terminal)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: lines.length,
                      itemBuilder: (context, i) {
                        final l = lines[i];
                        final lv = l.level.toLowerCase();
                        final color = lv.contains('err')
                            ? Colors.red
                            : (lv.contains('warn')
                                ? Colors.orange
                                : theme.textTheme.bodySmall?.color);
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 2),
                          child: SelectableText(
                            [
                              if (l.time.isNotEmpty) l.time,
                              if (l.level.isNotEmpty) l.level.toUpperCase(),
                              l.text,
                            ].join('  '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              height: 1.4,
                              color: color,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ============================== 工作区 ==============================

class ArtexWorkspacePanel extends StatefulWidget {
  final ArtexSession session;

  const ArtexWorkspacePanel({super.key, required this.session});

  @override
  State<ArtexWorkspacePanel> createState() => _ArtexWorkspacePanelState();
}

class _ArtexWorkspacePanelState extends State<ArtexWorkspacePanel> {
  bool _loading = false;

  Future<void> _pickTask() async {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final s = widget.session;
    if (s.tasks.isEmpty) return;
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          artexSectionTitle(ctx, loc.artexTabTasks),
          for (final t in s.tasks)
            ListTile(
              dense: true,
              leading: Icon(Icons.account_tree_outlined,
                  size: 18, color: artexStatusColor(theme, t.status)),
              title: Text(t.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(t.id, style: theme.textTheme.bodySmall),
              onTap: () => Navigator.of(ctx).pop(t.id),
            ),
        ],
      ),
    );
    if (id == null) return;
    setState(() => _loading = true);
    await s.loadWorkspace(id);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _open(ArtexWorkspaceEntry e) async {
    if (e.isDir) return;
    final c = widget.session.client;
    if (c == null) return;
    setState(() => _loading = true);
    String text;
    try {
      text = await c.readWorkspace(widget.session.workspaceTaskId, e.path);
    } catch (err) {
      text = '$err';
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (!mounted) return;
    await artexShowTextSheet(context, title: e.path, text: text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        final s = widget.session;
        return Column(
          children: [
            ListTile(
              dense: true,
              leading: const Icon(Icons.folder_outlined, size: 20),
              title: Text(
                s.workspaceTaskId.isEmpty ? loc.artexPickTask : s.workspaceTaskId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  IconButton(
                    tooltip: loc.artexPickTask,
                    icon: const Icon(Icons.swap_horiz, size: 20),
                    onPressed: _pickTask,
                  ),
                  IconButton(
                    tooltip: loc.refresh,
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: s.workspaceTaskId.isEmpty
                        ? null
                        : () => s.loadWorkspace(s.workspaceTaskId),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: s.workspace.isEmpty
                  ? artexEmpty(context, loc.artexNoWorkspace,
                      icon: Icons.folder_open_outlined)
                  : ListView.separated(
                      itemCount: s.workspace.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final e = s.workspace[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            e.isDir ? Icons.folder : Icons.insert_drive_file_outlined,
                            size: 20,
                            color: theme.hintColor,
                          ),
                          title: Text(e.path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12)),
                          subtitle: e.size > 0
                              ? Text('${e.size} B',
                                  style: theme.textTheme.labelSmall)
                              : null,
                          onTap: () => _open(e),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
// ============================== AI 与内置服务端 ==============================

/// 「AI 与服务」页。
///
/// ARTEX 的 AI **不再单独配模型**：直接复用 App「设置 → AI 分析」那套
/// OpenAI 兼容接口（[showAiSettingsDialog] 打开的就是设置页同一个对话框）。
/// 填一次，抓包分析、AI 对话、ARTEX 三处都能用。
///
/// 内置服务端是 Dart 实现（ArtexLocalBackend）：任务/发现/日志/会话存本机，
/// 不需要 Termux、root 或 PostgreSQL。Termux 那一套保留成「高级」，
/// 只有确实要连外部 ARTEX 后端的人才需要展开。
class ArtexServicePanel extends StatefulWidget {
  final ArtexSession session;
  final void Function(String message) onToast;

  const ArtexServicePanel({super.key, required this.session, required this.onToast});

  @override
  State<ArtexServicePanel> createState() => _ArtexServicePanelState();
}

class _ArtexServicePanelState extends State<ArtexServicePanel> {
  final _user = TextEditingController();
  bool _busy = false;
  bool _testing = false;
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    _user.text = widget.session.termuxUser;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.session.refreshService();
    });
  }

  @override
  void dispose() {
    _user.dispose();
    super.dispose();
  }

  Future<void> _run(Future<ArtexServiceResult> Function() action) async {
    setState(() => _busy = true);
    final r = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onToast(r.output.isEmpty ? 'done' : r.output.split('\n').first);
    await widget.session.refreshService(withLog: true);
  }

  Future<void> _editAi() async {
    final saved = await showAiSettingsDialog(context);
    if (!mounted) return;
    setState(() {});
    if (saved == true) widget.onToast(AppLocalizations.of(context)!.artexAiSaved);
  }

  Future<void> _testAi() async {
    final loc = AppLocalizations.of(context)!;
    setState(() => _testing = true);
    final r = await widget.session.testAi();
    if (!mounted) return;
    setState(() => _testing = false);
    widget.onToast(r.ok ? '${loc.artexAiOk} · ${_oneLine(r.text)}' : _oneLine(r.text));
  }

  static String _oneLine(String s, [int max = 120]) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= max ? t : '${t.substring(0, max)}…';
  }

  String get _userText =>
      _user.text.trim().isEmpty ? ArtexService.defaultTermuxUser : _user.text.trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final s = widget.session;
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        final ready = s.aiReady;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            artexSectionTitle(context, loc.artexAiTitle),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      ready ? Icons.smart_toy : Icons.smart_toy_outlined,
                      color: ready ? Colors.green : theme.colorScheme.error,
                    ),
                    title: Text(
                      ready ? loc.artexAiConfigured : loc.artexAiNotConfigured,
                    ),
                    subtitle: Text(
                      ready ? s.aiLabel : loc.artexAiShared,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _editAi,
                            icon: const Icon(Icons.tune, size: 18),
                            label: Text(loc.artexAiOpen),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _testing ? null : _testAi,
                            icon: _testing
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.bolt, size: 18),
                            label: Text(loc.artexAiTest),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Text(
                      loc.artexAiShared,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.hintColor, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            artexSectionTitle(context, loc.artexEmbeddedTitle),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: ListTile(
                dense: true,
                leading: Icon(
                  s.connected ? Icons.dns : Icons.cloud_off,
                  color: s.connected ? Colors.green : theme.hintColor,
                  size: 20,
                ),
                title: Text(s.baseUrl, style: const TextStyle(fontSize: 13)),
                subtitle: Text(loc.artexEmbeddedBody,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
                trailing: IconButton(
                  tooltip: loc.refresh,
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: s.busy ? null : () => s.refresh(),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: _advanced,
                onExpansionChanged: (v) => setState(() => _advanced = v),
                leading: const Icon(Icons.terminal, size: 20),
                title: Text(loc.artexAdvanced, style: theme.textTheme.titleSmall),
                subtitle: Text(loc.artexAdvancedHint,
                    style: theme.textTheme.bodySmall),
                children: _termuxChildren(context, theme, loc, s),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 高级项：外部后端 / Termux 启停（默认收起，独立运行的人不用看）。
  List<Widget> _termuxChildren(
      BuildContext context, ThemeData theme, AppLocalizations loc, ArtexSession s) {
    if (!ArtexService.supported) {
      return [
        ListTile(
          leading: const Icon(Icons.info_outline, size: 20),
          title: Text(loc.artexNotAndroid),
          subtitle: Text(loc.artexRemoteOnlyHint, style: theme.textTheme.bodySmall),
        ),
      ];
    }
    return [
      ListTile(
        dense: true,
        leading: Icon(
          s.service.processAlive ? Icons.check_circle : Icons.remove_circle_outline,
          color: s.service.processAlive ? Colors.green : theme.hintColor,
        ),
        title: Text(s.service.processAlive
            ? '${loc.artexRunningNow} · PID ${s.service.pid}'
            : loc.artexStoppedNow),
        subtitle: Text(
          'PG ${s.service.pgAlive ? '✓' : '✕'} · '
          'root ${s.service.rooted ? '✓' : '✕'} · ${_user.text.trim().isEmpty ? ArtexService.defaultTermuxUser : _user.text.trim()}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: IconButton(
          tooltip: loc.refresh,
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: () => s.refreshService(withLog: true),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _user,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: loc.artexTermuxUser,
                  helperText: loc.artexTermuxUserHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              tooltip: loc.artexDetect,
              icon: const Icon(Icons.search, size: 20),
              onPressed: () async {
                final u = await ArtexService.detectTermuxUser();
                if (!mounted) return;
                if (u.isEmpty) {
                  widget.onToast(loc.artexDetectFailed);
                  return;
                }
                setState(() => _user.text = u);
                s.termuxUser = u;
                await s.savePrefs();
                await s.refreshService();
              },
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        final pg = await ArtexService.startPg(_userText);
                        final art = await ArtexService.startArtex(_userText);
                        return ArtexServiceResult(pg.ok || art.ok, '${pg.output}\n${art.output}');
                      }),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text(loc.start),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _run(() => ArtexService.stopArtex(_userText)),
              icon: const Icon(Icons.stop, size: 18),
              label: Text(loc.stop),
            ),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        await ArtexService.stopArtex(_userText);
                        await Future<void>.delayed(const Duration(milliseconds: 600));
                        final pg = await ArtexService.startPg(_userText);
                        final art = await ArtexService.startArtex(_userText);
                        return ArtexServiceResult(pg.ok || art.ok, '${pg.output}\n${art.output}');
                      }),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: Text(loc.artexRestart),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _run(() => ArtexService.startPg(_userText)),
              icon: const Icon(Icons.storage, size: 18),
              label: Text(loc.artexStartPg),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _run(() => ArtexService.stopPg(_userText)),
              icon: const Icon(Icons.power_settings_new, size: 18),
              label: Text(loc.artexStopPg),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _run(() => ArtexService.clearLog(_userText)),
              icon: const Icon(Icons.clear_all, size: 18),
              label: Text(loc.clear),
            ),
          ],
        ),
      ),
      if (_busy)
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: LinearProgressIndicator(minHeight: 2),
        ),
      artexSectionTitle(context, loc.artexTailLog),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.all(10),
        height: 180,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Scrollbar(
          child: SingleChildScrollView(
            child: SelectableText(
              s.serviceLog.isEmpty ? 'no log' : s.serviceLog,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.45),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
    ];
  }
}

// ============================== AI 对话 ==============================

/// 手动 AI 对话入口（底部弹层）。
///
/// 用的是 App「设置 → AI 分析」那套接口，所以这里不需要任何模型配置；
/// 没配的时候直接在气泡里告诉用户去哪填，而不是静默失败。
class ArtexChatSheet extends StatefulWidget {
  final ArtexSession session;
  final String taskId;

  const ArtexChatSheet({super.key, required this.session, this.taskId = ''});

  static Future<void> show(BuildContext context, ArtexSession session,
      {String taskId = ''}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ArtexChatSheet(session: session, taskId: taskId),
    );
  }

  @override
  State<ArtexChatSheet> createState() => _ArtexChatSheetState();
}

class _ArtexChatSheetState extends State<ArtexChatSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, String>> _messages = <Map<String, String>>[];
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _sending = true;
      _input.clear();
    });
    _scrollToEnd();
    final r = await widget.session.chat(text, taskId: widget.taskId);
    if (!mounted) return;
    setState(() {
      _messages.add({'role': 'assistant', 'content': r.text});
      _sending = false;
    });
    _scrollToEnd();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
              child: Row(
                children: [
                  const Icon(Icons.smart_toy, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(loc.artexAiTitle, style: theme.textTheme.titleSmall),
                        Text(
                          widget.session.aiReady
                              ? widget.session.aiLabel
                              : loc.artexAiNotConfigured,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.hintColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: loc.close,
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          loc.artexAiShared,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor, height: 1.6),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[i];
                        final mine = m['role'] == 'user';
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.78,
                            ),
                            decoration: BoxDecoration(
                              color: mine
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SelectableText(
                              m['content'] ?? '',
                              style: theme.textTheme.bodySmall?.copyWith(height: 1.55),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_sending) const LinearProgressIndicator(minHeight: 2),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => unawaited(_send()),
                      decoration: InputDecoration(
                        hintText: loc.artexAiInputHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: loc.send,
                    icon: const Icon(Icons.send, size: 18),
                    onPressed: _sending ? null : () => unawaited(_send()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
