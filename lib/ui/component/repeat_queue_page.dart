/*
 * 发送队列 / 重放任务中心（上游 #715 查看准备重放的请求列表、#401 定时重放任务状态列表）
 *
 * 重放（单请求多次 / 批量 / 定时）此前只有对话框内的即时统计，关闭页面后无从
 * 查看；本页展示全局 [RepeatTaskManager] 中登记的任务：状态、进度、成败统计、
 * 计划时间与待发送请求清单。
 */
import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/components/repeat_task_manager.dart';

class RepeatQueuePage extends StatelessWidget {
  const RepeatQueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final manager = RepeatTaskManager.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.rqTitle,
            style: const TextStyle(fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined, size: 20),
            tooltip: AppLocalizations.of(context)!.rqClearFinished,
            onPressed: () => manager.clearFinished(),
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: manager.revision,
        builder: (context, _, __) {
          final tasks = manager.tasks;
          if (tasks.isEmpty) {
            return _empty(context, cs);
          }
          return Column(children: [
            Container(
              width: double.infinity,
              color: cs.tertiaryContainer.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                AppLocalizations.of(context)!.rqIntro,
                style: TextStyle(fontSize: 11, color: cs.onTertiaryContainer, height: 1.4),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                itemCount: tasks.length,
                itemBuilder: (context, index) => _taskCard(context, manager, tasks[index], cs),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _taskCard(BuildContext context, RepeatTaskManager manager, RepeatTask task, ColorScheme cs) {
    final (label, color, icon) =
        _statusStyle(AppLocalizations.of(context)!, task.status, cs);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
              ]),
            ),
            const Spacer(),
            if (!task.isFinished)
              IconButton(
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                color: cs.error,
                tooltip: AppLocalizations.of(context)!.rqCancelTask,
                onPressed: () => manager.cancel(task),
              ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              color: Theme.of(context).hintColor,
              tooltip: AppLocalizations.of(context)!.rqRemoveRecord,
              onPressed: () => manager.remove(task),
            ),
          ]),
          const SizedBox(height: 4),
          Text(task.title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 5,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('${task.executed}/${task.total}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 2, children: [
            _stat(AppLocalizations.of(context)!.success, task.success, Colors.green),
            _stat(AppLocalizations.of(context)!.fail, task.failed, Colors.redAccent),
            if (task.retried > 0)
              _stat(AppLocalizations.of(context)!.rqStatRetried, task.retried, Colors.orange),
            _stat(AppLocalizations.of(context)!.create, null, null, text: _fmtTime(task.createdAt)),
            if (task.scheduledAt != null)
              _stat(AppLocalizations.of(context)!.rqStatPlanned, null, cs.primary,
                  text: _fmtTime(task.scheduledAt!)),
          ]),
          if (task.lastError != null && task.failed > 0) ...[
            const SizedBox(height: 6),
            Text(AppLocalizations.of(context)!.rqLastError(_short(task.lastError!)),
                style: TextStyle(fontSize: 11, color: cs.error, height: 1.35), maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
          if (task.pending.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(AppLocalizations.of(context)!.rqPendingRequests(task.pending.length),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
            const SizedBox(height: 2),
            ...task.pending.take(5).map((p) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(children: [
                    Icon(Icons.subdirectory_arrow_right, size: 12, color: cs.outline),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(p,
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                )),
            if (task.pending.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(AppLocalizations.of(context)!.rqMoreRemaining(task.pending.length - 5),
                    style: TextStyle(fontSize: 11, color: cs.outline)),
              ),
          ],
        ]),
      ),
    );
  }

  Widget _stat(String label, int? value, Color? color, {String? text}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label ',
          style: TextStyle(fontSize: 11, color: color ?? Colors.grey)),
      Text(text ?? '${value ?? 0}',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    ]);
  }

  (String, Color, IconData) _statusStyle(
      AppLocalizations loc, RepeatTaskStatus status, ColorScheme cs) {
    switch (status) {
      case RepeatTaskStatus.scheduled:
        return (loc.rqStatusScheduled, cs.primary, Icons.schedule_outlined);
      case RepeatTaskStatus.running:
        return (loc.rqStatusRunning, Colors.orange, Icons.play_circle_outline);
      case RepeatTaskStatus.completed:
        return (loc.rqStatusCompleted, Colors.green, Icons.check_circle_outline);
      case RepeatTaskStatus.canceled:
        return (loc.rqStatusCanceled, cs.outline, Icons.block_outlined);
    }
  }

  String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  String _short(String s) => s.length > 80 ? '${s.substring(0, 80)}…' : s;

  Widget _empty(BuildContext context, ColorScheme cs) {
    final loc = AppLocalizations.of(context)!;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.outbox_outlined, size: 46, color: cs.outlineVariant),
        const SizedBox(height: 10),
        Text(loc.rqEmptyTitle, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(loc.rqEmptyHint,
            style: TextStyle(fontSize: 12, color: cs.outline), textAlign: TextAlign.center),
      ]),
    );
  }
}
