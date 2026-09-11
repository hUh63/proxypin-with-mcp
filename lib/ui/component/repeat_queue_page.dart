/*
 * 发送队列 / 重放任务中心（上游 #715 查看准备重放的请求列表、#401 定时重放任务状态列表）
 *
 * 重放（单请求多次 / 批量 / 定时）此前只有对话框内的即时统计，关闭页面后无从
 * 查看；本页展示全局 [RepeatTaskManager] 中登记的任务：状态、进度、成败统计、
 * 计划时间与待发送请求清单。
 */
import 'package:flutter/material.dart';
import 'package:proxypin/network/components/repeat_task_manager.dart';

class RepeatQueuePage extends StatelessWidget {
  const RepeatQueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final manager = RepeatTaskManager.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('发送队列',
            style: TextStyle(fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined, size: 20),
            tooltip: '清除已结束的任务',
            onPressed: () => manager.clearFinished(),
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: manager.revision,
        builder: (context, _, __) {
          final tasks = manager.tasks;
          if (tasks.isEmpty) {
            return _empty(cs);
          }
          return Column(children: [
            Container(
              width: double.infinity,
              color: cs.tertiaryContainer.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '这里汇总本次运行期间发起的所有重放任务（单次多次 / 批量 / 定时）：'
                '可查看进行中的进度、成功与失败统计，以及等待发送的请求清单。'
                '任务为内存态，应用重启后清空。',
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
    final (label, color, icon) = _statusStyle(task.status, cs);
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
                tooltip: '取消任务（停止后续发送）',
                onPressed: () => manager.cancel(task),
              ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              color: Theme.of(context).hintColor,
              tooltip: '移除记录',
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
            _stat('成功', task.success, Colors.green),
            _stat('失败', task.failed, Colors.redAccent),
            if (task.retried > 0) _stat('重试', task.retried, Colors.orange),
            _stat('创建', null, null, text: _fmtTime(task.createdAt)),
            if (task.scheduledAt != null)
              _stat('计划', null, cs.primary, text: _fmtTime(task.scheduledAt!)),
          ]),
          if (task.lastError != null && task.failed > 0) ...[
            const SizedBox(height: 6),
            Text('最近错误：${_short(task.lastError!)}',
                style: TextStyle(fontSize: 11, color: cs.error, height: 1.35), maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
          if (task.pending.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('待发送请求（${task.pending.length}）',
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
                child: Text('… 其余 ${task.pending.length - 5} 条',
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

  (String, Color, IconData) _statusStyle(RepeatTaskStatus status, ColorScheme cs) {
    switch (status) {
      case RepeatTaskStatus.scheduled:
        return ('等待发送', cs.primary, Icons.schedule_outlined);
      case RepeatTaskStatus.running:
        return ('发送中', Colors.orange, Icons.play_circle_outline);
      case RepeatTaskStatus.completed:
        return ('已完成', Colors.green, Icons.check_circle_outline);
      case RepeatTaskStatus.canceled:
        return ('已取消', cs.outline, Icons.block_outlined);
    }
  }

  String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  String _short(String s) => s.length > 80 ? '${s.substring(0, 80)}…' : s;

  Widget _empty(ColorScheme cs) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.outbox_outlined, size: 46, color: cs.outlineVariant),
        const SizedBox(height: 10),
        Text('暂无重放任务', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text('发起重放（含批量与定时）后，任务会出现在这里',
            style: TextStyle(fontSize: 12, color: cs.outline), textAlign: TextAlign.center),
      ]),
    );
  }
}
