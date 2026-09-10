import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:http/http.dart' as http;
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/components/manager/script_manager.dart';
import 'package:proxypin/network/mcp/mcp_event_automation.dart';
import 'package:proxypin/network/mcp/mcp_rule_engine.dart';
import 'package:proxypin/network/mcp/mcp_scheduler.dart';
import 'package:proxypin/network/mcp/mcp_server.dart';
import 'package:proxypin/network/util/cron_expression.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/path.dart';
import 'package:proxypin/ui/component/guide_center.dart';
import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:proxypin/utils/platform.dart';

/// MCP 自动化配置页面
/// 定时任务 · 事件监听 · 规则引擎 · Prompts · Roots · 工作流
class McpAutomationPage extends StatefulWidget {
  const McpAutomationPage({super.key});

  @override
  State<StatefulWidget> createState() => _McpAutomationPageState();
}

class _McpAutomationPageState extends State<McpAutomationPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTab = 0;

  final McpScheduler _scheduler = McpScheduler();
  final McpEventAutomation _eventAutomation = McpEventAutomation();
  final McpRuleEngine _ruleEngine = McpRuleEngine();
  final McpServer _mcpServer = McpServer();

  // 本地已注册事件监听器（保留 callback 引用以便移除/切换）
  final List<_RegisteredEventListener> _registeredListeners = [];

  // 工作流（本地持久化）
  final List<Map<String, dynamic>> _workflows = [];

  List<Map<String, dynamic>> _prompts = [];
  List<Map<String, dynamic>> _roots = [];
  List<Map<String, dynamic>> _tools = [];

  /// MCP 运行状态；null 表示首次状态尚未拉取（避免进入页面先闪"已停止"）
  bool? _mcpRunning;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _currentTab = _tabController.index);
      }
    });
    _bootstrap();
    // 立即拉取一次真实状态（不等 2 秒定时器），消除"已停止"闪现
    _refreshMcpStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshMcpStatus());
  }

  /// 拉取 MCP 运行状态：桌面子窗口为独立 isolate，McpServer 单例与主窗口不共享，
  /// 通过 IPC 拉取主窗口真实运行状态；移动端直接读本地单例。
  Future<void> _refreshMcpStatus() async {
    bool running;
    try {
      if (Platforms.isDesktop()) {
        final res = await DesktopMultiWindow.invokeMainWindowMethod('getMcpStatus');
        running = res is Map && res['running'] == true;
      } else {
        running = _mcpServer.isRunning;
      }
    } catch (e) {
      logger.w('拉取 MCP 状态失败', error: e);
      return;
    }
    if (!mounted) return;
    if (running != _mcpRunning) setState(() => _mcpRunning = running);
  }

  /// 启动/停止 MCP 服务（移动端直连本地单例；桌面端经 IPC 操作主窗口的 McpServer）。
  /// 返回操作后的实际运行状态，供 UI 校验开关是否生效。
  Future<bool> _setMcpRunning(bool target) async {
    try {
      if (Platforms.isDesktop()) {
        final res = await DesktopMultiWindow.invokeMainWindowMethod(target ? 'startMcp' : 'stopMcp');
        return res is Map && res['running'] == true;
      }
      if (target) {
        // 启动视为用户主动启用，先解锁总开关（McpServer.start 会校验 mcpEnabled）
        Configuration.loaded?.mcpEnabled = true;
        await _mcpServer.start();
      } else {
        await _mcpServer.stop();
      }
      return _mcpServer.isRunning;
    } catch (e) {
      logger.e('切换 MCP 运行状态失败', error: e);
      return !target; // 失败时保持原状
    }
  }

  Future<void> _bootstrap() async {
    await _ruleEngine.loadRules();
    await _loadWorkflows();
    await _loadRoots();
    // 注册任务执行器并加载持久化定时任务
    _scheduler.setActionExecutor(_executeTaskDescriptor);
    await _scheduler.loadTasks();
    _refreshMcpData();
    if (mounted) setState(() {});
  }

  void _refreshMcpData() {
    try {
      _prompts = _mcpServer.getPrompts();
      _tools = _mcpServer.getTools();
      // Roots 由本页自由编辑并持久化（mcp_roots.json），不随服务端状态刷新覆盖
    } catch (e) {
      logger.w('加载 MCP prompts/tools 失败', error: e);
    }
  }

  // ==================== Roots 本地持久化 ====================

  /// 加载 Roots：优先读取 mcp_roots.json（用户编辑后的完整列表）；
  /// 无持久化文件时以 MCP Server 内置默认 Roots 作为初始列表。
  Future<void> _loadRoots() async {
    try {
      final file = await Paths.getPath('mcp_roots.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final list = jsonDecode(content) as List<dynamic>;
          _roots = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } else {
        _roots = _mcpServer.getRoots();
      }
      // 同步到 MCP Server，roots/list 立即生效
      _mcpServer.setRoots(_roots);
    } catch (e, st) {
      logger.e('加载 Roots 失败', error: e, stackTrace: st);
      _roots = _mcpServer.getRoots();
    }
  }

  /// 保存 Roots：写入 mcp_roots.json 并同步到 MCP Server（桌面端额外通知主窗口重载）
  Future<void> _saveRoots() async {
    try {
      final file = await Paths.getPath('mcp_roots.json');
      await file.writeAsString(jsonEncode(_roots));
      _mcpServer.setRoots(_roots);
      if (Platforms.isDesktop()) {
        unawaited(DesktopMultiWindow.invokeMainWindowMethod('refreshMcpRoots', {'roots': _roots}));
      }
    } catch (e, st) {
      logger.e('保存 Roots 失败', error: e, stackTrace: st);
    }
  }

  /// 添加/编辑 Root（uri + 名称，uri 必填）
  Future<void> _showRootDialog(BuildContext context, Map<String, dynamic>? existing) async {
    final isEdit = existing != null;
    final uriController = TextEditingController(text: existing?['uri']?.toString() ?? '');
    final nameController = TextEditingController(text: existing?['name']?.toString() ?? '');
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? '编辑 Root' : '添加 Root'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: uriController,
                decoration: const InputDecoration(
                  labelText: 'URI *',
                  border: OutlineInputBorder(),
                  hintText: 'proxypin://workspace 或 file:///path/to/dir',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '名称', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final uri = uriController.text.trim();
              if (uri.isEmpty) {
                FlutterToastr.show('请输入 Root URI', context, duration: 2, backgroundColor: Colors.red);
                return;
              }
              final name = nameController.text.trim().isEmpty ? uri : nameController.text.trim();
              // 局部变量避免可空类型提升问题
              final existingRoot = existing;
              setState(() {
                if (existingRoot != null) {
                  existingRoot['uri'] = uri;
                  existingRoot['name'] = name;
                } else {
                  _roots.add({'uri': uri, 'name': name});
                }
              });
              await _saveRoots();
              if (context.mounted) Navigator.pop(context);
              FlutterToastr.show(isEdit ? 'Root 已更新' : 'Root 已添加', context, duration: 2,
                  backgroundColor: Colors.green);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 删除 Root
  Future<void> _deleteRoot(Map<String, dynamic> root) async {
    setState(() => _roots.remove(root));
    await _saveRoots();
    if (mounted) {
      FlutterToastr.show('Root 已删除', context, duration: 2, backgroundColor: Colors.green);
    }
  }

  /// MCP 协议请求：桌面端经 IPC 转发到主窗口运行中的 McpServer；
  /// 移动端直接调本地单例（同进程）。
  Future<Map<String, dynamic>?> _mcpSendRequest(String method, [Map<String, dynamic>? params]) async {
    if (Platforms.isDesktop()) {
      try {
        final res =
            await DesktopMultiWindow.invokeMainWindowMethod('mcpSendRequest', {'method': method, 'params': params});
        if (res is Map) return Map<String, dynamic>.from(res);
        return null;
      } catch (e, s) {
        logger.e('mcpSendRequest IPC 失败: $method', error: e, stackTrace: s);
        return null;
      }
    }
    return _mcpServer.sendRequest(method, params);
  }

  /// 桌面端规则变更后通知主窗口重载（移动端同进程无需通知）
  void _notifyRulesChanged() {
    if (Platforms.isDesktop()) {
      unawaited(DesktopMultiWindow.invokeMainWindowMethod('refreshMcpRules'));
    }
  }

  /// 按脚本名称独立运行（供定时任务/工作流调用）。
  /// 复用 ScriptManager.runStandalone，用合成请求跑脚本的 onRequest。
  Future<void> _runScriptByName(String name) async {
    try {
      final mgr = await ScriptManager.instance;
      ScriptItem? item;
      for (final s in mgr.list) {
        if (s.name == name) {
          item = s;
          break;
        }
      }
      if (item == null) {
        logger.w('脚本不存在: $name');
        if (mounted) FlutterToastr.show('脚本不存在: $name', context, backgroundColor: Colors.orange);
        return;
      }
      await mgr.runStandalone(item);
      if (mounted) FlutterToastr.show('脚本已执行: $name', context, backgroundColor: Colors.green);
    } catch (e, s) {
      logger.e('执行脚本失败: $name', error: e, stackTrace: s);
      if (mounted) FlutterToastr.show('脚本执行失败: $e', context, backgroundColor: Colors.red);
    }
  }

  Future<void> _loadWorkflows() async {
    try {
      final file = await Paths.getPath('mcp_workflows.json');
      if (!await file.exists()) return;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return;
      final list = jsonDecode(content) as List<dynamic>;
      _workflows.addAll(list.cast<Map<String, dynamic>>());
    } catch (e, st) {
      logger.e('加载工作流失败', error: e, stackTrace: st);
    }
  }

  Future<void> _saveWorkflows() async {
    try {
      final file = await Paths.getPath('mcp_workflows.json');
      await file.writeAsString(jsonEncode(_workflows));
    } catch (e, st) {
      logger.e('保存工作流失败', error: e, stackTrace: st);
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('MCP 自动化', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            _buildStatusIndicator(),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '使用教程',
            onPressed: () => showGuideArticle(context, 'mcp_automation'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () {
              _refreshMcpData();
              setState(() {});
              FlutterToastr.show('已刷新', context, duration: 1, backgroundColor: Colors.green);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          // 靠左对齐：scrollable TabBar 默认 startOffset 会带起始缩进，
          // 显式指定 start 使 6 个 Tab 从最左侧开始显示
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: '定时任务', icon: Icon(Icons.schedule)),
            Tab(text: '事件监听', icon: Icon(Icons.event)),
            Tab(text: '规则引擎', icon: Icon(Icons.rule)),
            Tab(text: 'Prompts', icon: Icon(Icons.chat)),
            Tab(text: 'Roots', icon: Icon(Icons.folder_open)),
            Tab(text: '工作流', icon: Icon(Icons.auto_awesome)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildScheduledTasksTab(),
          _buildEventListenersTab(),
          _buildRuleEngineTab(),
          _buildPromptsTab(),
          _buildRootsTab(),
          _buildWorkflowTab(),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }

  // ==================== MCP 连接状态指示器 ====================

  /// 状态指示器 + 运行开关：
  /// 未拉取到首次状态前显示"检测中…"，避免进入页面先闪"已停止"再变"运行中"。
  Widget _buildStatusIndicator() {
    final running = _mcpRunning;
    final Color color;
    final String text;
    if (running == null) {
      color = Colors.orange;
      text = '检测中…';
    } else if (running) {
      color = Colors.green;
      text = '运行中';
    } else {
      color = Colors.grey;
      text = '已停止';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 8, color: color),
              const SizedBox(width: 6),
              Text(text, style: TextStyle(fontSize: 12, color: color)),
            ],
          ),
        ),
        // 运行开关：电源图标随状态变色，点击启停（替代过大的 Switch）
        Tooltip(
          message: running == true ? '点击停止 MCP 自动化' : '点击启动 MCP 自动化',
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: running == null
                ? null // 状态未确认前禁用，避免误操作
                : () async {
                    final prev = _mcpRunning;
                    // 乐观更新，操作失败再回滚
                    setState(() => _mcpRunning = !running!);
                    final ok = await _setMcpRunning(!running);
                    if (!mounted) return;
                    setState(() => _mcpRunning = ok);
                    if (!running && !ok) {
                      FlutterToastr.show('MCP 服务启动失败，请检查设置中是否已启用 MCP 服务',
                          context, duration: 2, backgroundColor: Colors.red);
                    } else if (running) {
                      FlutterToastr.show('MCP 服务已停止', context, duration: 2,
                          backgroundColor: Colors.green);
                    } else {
                      FlutterToastr.show('MCP 服务已启动', context, duration: 2,
                          backgroundColor: Colors.green);
                    }
                    if (ok != prev) _refreshMcpData();
                  },
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.power_settings_new,
                size: 20,
                color: running == true
                    ? Colors.green
                    : (running == null ? Colors.grey.shade400 : Colors.grey),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== FAB 分派（按当前 tab） ====================

  Widget? _buildFab() {
    switch (_currentTab) {
      case 0:
        return FloatingActionButton(
            heroTag: 'fab_task', onPressed: () => _showAddTaskDialog(context), child: const Icon(Icons.add));
      case 1:
        return FloatingActionButton(
            heroTag: 'fab_event', onPressed: () => _showAddEventListenerDialog(context), child: const Icon(Icons.add));
      case 2:
        return FloatingActionButton(
            heroTag: 'fab_rule', onPressed: () => _showRuleDialog(context, null), child: const Icon(Icons.add));
      case 3:
        return FloatingActionButton(
            heroTag: 'fab_prompt',
            onPressed: () => _showPromptInvokeDialog(context, null),
            child: const Icon(Icons.play_arrow));
      case 5:
        return FloatingActionButton(
            heroTag: 'fab_workflow', onPressed: () => _showWorkflowDialog(context, null), child: const Icon(Icons.add));
      case 4:
        // Roots：自由添加/编辑/删除
        return FloatingActionButton(
            heroTag: 'fab_root', onPressed: () => _showRootDialog(context, null), child: const Icon(Icons.add));
      default:
        return null;
    }
  }

  // ==================== Tab 1: 定时任务 ====================

  Widget _buildScheduledTasksTab() {
    final tasks = _scheduler.tasks;
    if (tasks.isEmpty) {
      return _emptyState(Icons.schedule, '暂无定时任务', '点击右下角 + 添加新任务\n可同时选择执行时间与执行内容');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        final isInterval = task.repeatMode == 'interval';
        final isDaily = task.repeatMode == 'daily';
        final isWeekly = task.repeatMode == 'weekly';
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isDaily
                  ? Colors.blue
                  : isWeekly
                      ? Colors.teal
                      : isInterval
                          ? Colors.deepPurple
                          : Colors.green,
              child: Icon(
                  isDaily
                      ? Icons.repeat
                      : isWeekly
                          ? Icons.date_range
                          : isInterval
                              ? Icons.timer_outlined
                              : Icons.play_circle_outline,
                  color: Colors.white,
                  size: 20),
            ),
            title: Text(task.name),
            subtitle: Text(
              '${task.repeatLabel} • ${isInterval ? '下次：' : ''}${_formatTime(task.executeAt)}'
              '${task.lastExecuted != null ? ' • 上次：${_formatTime(task.lastExecuted!)}' : ''}'
              '${task.repeatCount != null ? ' • 已执行 ${task.executedCount}/${task.repeatCount} 次' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _cancelTask(task),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAddTaskDialog(BuildContext context) async {
    final nameController = TextEditingController();
    DateTime selectedTime = DateTime.now().add(const Duration(minutes: 1));
    // 定时方式：none 一次性 / daily 每天 / weekly 每周 / interval 固定间隔
    String repeatMode = 'none';
    int? repeatCount;
    int intervalMinutes = 30;
    List<int> selectedWeekdays = [];
    final repeatCountController = TextEditingController();
    final intervalController = TextEditingController(text: '30');
    final cronController = TextEditingController();
    DateTime? cronPreview;
    int actionType = 1; // 0 执行脚本 1 调用MCP工具 2 执行工作流 3 发送Webhook
    // 子配置
    String? selectedScript;
    String? selectedTool;
    String? selectedWorkflow;
    final webhookUrlController = TextEditingController(text: 'https://');

    List<String> scriptNames = [];
    List<String> toolNames = [];
    List<String> workflowNames = _workflows.map((w) => w['name']?.toString() ?? '').toList();

    Future<void> loadOptions() async {
      try {
        final mgr = await ScriptManager.instance;
        scriptNames = mgr.list.map((s) => s.name ?? '').where((n) => n.isNotEmpty).toList();
      } catch (e) {
        logger.w('加载脚本列表失败', error: e);
      }
      try {
        toolNames = _tools.map((t) => t['name']?.toString() ?? '').where((n) => n.isNotEmpty).toList();
      } catch (_) {}
    }

    await loadOptions();

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加定时任务'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: '任务名称', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  const Text('定时方式:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  // 5 种方式用 ChoiceChip 流式布局，避免 SegmentedButton 一行放不下溢出
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (value, label, icon) in const [
                        ('none', '一次性', Icons.play_circle_outline),
                        ('daily', '每天', Icons.repeat),
                        ('weekly', '每周', Icons.date_range),
                        ('interval', '间隔', Icons.timer_outlined),
                        ('cron', 'Cron', Icons.code),
                      ])
                        ChoiceChip(
                          label: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(icon, size: 14, color: repeatMode == value ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.outline),
                              const SizedBox(width: 4),
                              Text(label, style: const TextStyle(fontSize: 12)),
                            ]),
                          ),
                          selected: repeatMode == value,
                          selectedColor: Theme.of(context).colorScheme.primary,
                          labelStyle: TextStyle(color: repeatMode == value ? Theme.of(context).colorScheme.onPrimary : null),
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          onSelected: (sel) {
                            if (sel) setDialogState(() => repeatMode = value);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Cron 表达式模式：表达式输入 + 下次执行预览
                  if (repeatMode == 'cron') ...[
                    TextField(
                      controller: cronController,
                      decoration: const InputDecoration(
                        labelText: 'Cron 表达式',
                        border: OutlineInputBorder(),
                        hintText: '分 时 日 月 星期，如 0 9 * * 1-5',
                        helperText: '支持 * , - / 通配符',
                      ),
                      onChanged: (v) => setDialogState(() => cronPreview = CronExpression(v).next(DateTime.now())),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      cronPreview == null
                          ? (cronController.text.isEmpty ? '请输入 Cron 表达式' : '表达式无效，请检查')
                          : '下次执行: ${cronPreview!.year}-${cronPreview!.month.toString().padLeft(2, '0')}-${cronPreview!.day.toString().padLeft(2, '0')} ${cronPreview!.hour.toString().padLeft(2, '0')}:${cronPreview!.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                          fontSize: 12,
                          color: cronPreview == null ? Colors.orange : Colors.green),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final (expr, desc) in const [
                          ('0 9 * * 1-5', '工作日9点'),
                          ('*/30 * * * *', '每30分钟'),
                          ('0 0 * * *', '每天零点'),
                        ])
                          ActionChip(
                            label: Text(desc, style: const TextStyle(fontSize: 11)),
                            onPressed: () => setDialogState(() {
                              cronController.text = expr;
                              cronPreview = CronExpression(expr).next(DateTime.now());
                            }),
                          ),
                      ],
                    ),
                  ],
                  // 一次性 / 每天 / 每周：选择执行时刻
                  if (repeatMode != 'interval' && repeatMode != 'cron') ...[
                    Text(repeatMode == 'none' ? '执行日期与时间:' : '执行时间:'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // 一次性任务：日历选择日期
                        if (repeatMode == 'none')
                          ElevatedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedTime,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                                helpText: '选择执行日期',
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  selectedTime = DateTime(
                                    picked.year, picked.month, picked.day,
                                    selectedTime.hour, selectedTime.minute,
                                  );
                                  if (selectedTime.isBefore(DateTime.now())) {
                                    // 选了今天但时间已过，自动顺延到明天同一时刻由时间选择决定
                                    selectedTime = picked;
                                  }
                                });
                              }
                            },
                            icon: const Icon(Icons.calendar_month),
                            label: Text('${selectedTime.year}-${selectedTime.month.toString().padLeft(2, '0')}-${selectedTime.day.toString().padLeft(2, '0')}'),
                          ),
                        // 时间选择（所有非间隔模式）
                        ElevatedButton.icon(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(selectedTime),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                selectedTime = DateTime(
                                  selectedTime.year, selectedTime.month, selectedTime.day,
                                  picked.hour, picked.minute,
                                );
                                if (repeatMode == 'none' && selectedTime.isBefore(DateTime.now())) {
                                  selectedTime = selectedTime.add(const Duration(days: 1));
                                }
                              });
                            }
                          },
                          icon: const Icon(Icons.access_time),
                          label: Text('${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}'),
                        ),
                      ],
                    ),
                  ],
                  // 每周模式：星期多选
                  if (repeatMode == 'weekly') ...[
                    const SizedBox(height: 8),
                    const Text('重复于:', style: TextStyle(fontSize: 13)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final entry in const {1: '一', 2: '二', 3: '三', 4: '四', 5: '五', 6: '六', 7: '日'}.entries)
                          FilterChip(
                            label: Text('周${entry.value}', style: const TextStyle(fontSize: 12)),
                            selected: selectedWeekdays.contains(entry.key),
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            onSelected: (sel) {
                              setDialogState(() {
                                if (sel) {
                                  selectedWeekdays.add(entry.key);
                                } else {
                                  selectedWeekdays.remove(entry.key);
                                }
                                selectedWeekdays.sort();
                              });
                            },
                          ),
                      ],
                    ),
                    if (selectedWeekdays.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('请至少选择一个星期', style: TextStyle(fontSize: 12, color: Colors.orange)),
                      ),
                  ],
                  // 固定间隔：间隔分钟数
                  if (repeatMode == 'interval') ...[
                    TextField(
                      controller: intervalController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '间隔分钟数',
                        border: OutlineInputBorder(),
                        helperText: '如填 30，表示每 30 分钟自动执行一次',
                        helperMaxLines: 2,
                      ),
                      onChanged: (v) => intervalMinutes = int.tryParse(v) ?? 30,
                    ),
                  ],
                  // 重复次数（仅重复模式）
                  if (repeatMode != 'none') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: repeatCountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '重复次数',
                        border: OutlineInputBorder(),
                        helperText: '如填 5，表示共执行 5 次后自动结束；留空 = 无限重复',
                        helperMaxLines: 2,
                      ),
                      onChanged: (v) => repeatCount = int.tryParse(v),
                    ),
                  ],
                  const Divider(),
                  const Text('执行任务:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: actionType,
                    isExpanded: true,
                    isDense: true,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('执行脚本', maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false)),
                      DropdownMenuItem(value: 1, child: Text('调用 MCP 工具', maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false)),
                      DropdownMenuItem(value: 2, child: Text('执行工作流', maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false)),
                      DropdownMenuItem(value: 3, child: Text('发送 Webhook', maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false)),
                    ],
                    selectedItemBuilder: _selectedItems<int>(const [0, 1, 2, 3],
                        (v) => const ['执行脚本', '调用 MCP 工具', '执行工作流', '发送 Webhook'][v]),
                    onChanged: (v) => setDialogState(() => actionType = v ?? 1),
                  ),
                  const SizedBox(height: 8),
                  if (actionType == 0)
                    _optionDropdown(scriptNames, selectedScript, '选择脚本',
                        (v) => setDialogState(() => selectedScript = v),
                        emptyHint: '暂无脚本，先在脚本页添加'),
                  if (actionType == 1)
                    _optionDropdown(toolNames, selectedTool, '选择 MCP 工具',
                        (v) => setDialogState(() => selectedTool = v),
                        emptyHint: _mcpRunning == true ? '暂无工具' : 'MCP 未启动，无法获取工具'),
                  if (actionType == 2)
                    _optionDropdown(workflowNames, selectedWorkflow, '选择工作流',
                        (v) => setDialogState(() => selectedWorkflow = v),
                        emptyHint: '暂无工作流，先在工作流页添加'),
                  if (actionType == 3)
                    TextField(
                      controller: webhookUrlController,
                      decoration: const InputDecoration(labelText: 'Webhook URL', border: OutlineInputBorder()),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty) {
                  FlutterToastr.show('请输入任务名称', context, duration: 2, backgroundColor: Colors.red);
                  return;
                }
                if (repeatMode == 'interval' && intervalMinutes <= 0) {
                  FlutterToastr.show('请输入有效的间隔分钟数', context, duration: 2, backgroundColor: Colors.red);
                  return;
                }
                if (repeatMode == 'weekly' && selectedWeekdays.isEmpty) {
                  FlutterToastr.show('请至少选择一个星期', context, duration: 2, backgroundColor: Colors.red);
                  return;
                }
                if (repeatMode == 'cron' && CronExpression(cronController.text.trim()).next(DateTime.now()) == null) {
                  FlutterToastr.show('Cron 表达式无效', context, duration: 2, backgroundColor: Colors.red);
                  return;
                }
                final descriptor = _buildTaskDescriptor(actionType, nameController.text,
                    script: selectedScript, tool: selectedTool, workflow: selectedWorkflow, webhookUrl: webhookUrlController.text);
                if (descriptor == null) {
                  FlutterToastr.show('请完善执行任务配置', context, duration: 2, backgroundColor: Colors.red);
                  return;
                }
                // 一次性任务从所选日期时间起算；间隔任务从当前时间起算；每周任务从所选时刻起算；Cron 由表达式计算
                var executeAt = selectedTime;
                if (repeatMode == 'interval') {
                  executeAt = DateTime.now().add(Duration(minutes: intervalMinutes));
                } else if (repeatMode == 'cron') {
                  executeAt = CronExpression(cronController.text.trim()).next(DateTime.now()) ?? selectedTime;
                } else if (repeatMode == 'weekly' && executeAt.isBefore(DateTime.now())) {
                  // 时刻已过：推进到下一个选中的星期
                  var next = executeAt.add(const Duration(days: 1));
                  for (int i = 0; i < 8; i++) {
                    if (selectedWeekdays.contains(next.weekday)) break;
                    next = next.add(const Duration(days: 1));
                  }
                  executeAt = next;
                }
                _scheduler.scheduleTask(
                  name: nameController.text,
                  executeAt: executeAt,
                  actionDescriptor: descriptor,
                  repeatMode: repeatMode,
                  repeatCount: repeatCount,
                  intervalMinutes: repeatMode == 'interval' ? intervalMinutes : null,
                  weekdays: repeatMode == 'weekly' ? selectedWeekdays : null,
                  cronExpression: repeatMode == 'cron' ? cronController.text.trim() : null,
                );
                await _scheduler.saveTasks();
                Navigator.pop(context);
                FlutterToastr.show('定时任务已添加', context, duration: 2, backgroundColor: Colors.green);
                setState(() {});
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  /// 根据动作类型构造可序列化动作描述（跨重启由执行器还原执行）
  Map<String, dynamic>? _buildTaskDescriptor(int type, String taskName,
      {String? script, String? tool, String? workflow, String? webhookUrl}) {
    switch (type) {
      case 0: // 执行脚本
        if (script == null || script.isEmpty) return null;
        return {'type': 0, 'name': taskName, 'script': script};
      case 1: // 调用 MCP 工具
        if (tool == null || tool.isEmpty) return null;
        return {'type': 1, 'name': taskName, 'tool': tool};
      case 2: // 执行工作流
        if (workflow == null || workflow.isEmpty) return null;
        final wf = _workflows.firstWhere(
          (w) => w['name'] == workflow,
          orElse: () => <String, dynamic>{},
        );
        if (wf.isEmpty) return null;
        return {'type': 2, 'name': taskName, 'workflow': wf};
      case 3: // 发送 Webhook
        if (webhookUrl == null || webhookUrl.isEmpty || !webhookUrl.startsWith('http')) return null;
        return {'type': 3, 'name': taskName, 'webhookUrl': webhookUrl};
    }
    return null;
  }

  /// 任务执行器（由 McpScheduler 在任务到期时调用，UI 无关，可后台触发）
  Future<void> _executeTaskDescriptor(Map<String, dynamic> desc) async {
    final type = desc['type'] as int? ?? 1;
    final taskName = desc['name'] as String? ?? '';
    try {
      switch (type) {
        case 0: // 执行脚本
          final script = desc['script'] as String?;
          if (script != null && script.isNotEmpty) await _runScriptByName(script);
          break;
        case 1: // 调用 MCP 工具
          final tool = desc['tool'] as String?;
          if (tool != null && tool.isNotEmpty) {
            final res = await _mcpSendRequest('tools/call', {'name': tool, 'arguments': {}});
            logger.i('[$taskName] 工具 $tool 返回: $res');
          }
          break;
        case 2: // 执行工作流
          final wf = desc['workflow'] as Map<String, dynamic>?;
          if (wf != null) await _executeWorkflowNodes(wf);
          break;
        case 3: // 发送 Webhook
          final url = desc['webhookUrl'] as String?;
          if (url != null && url.startsWith('http')) {
            final r = await http.post(Uri.parse(url),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'task': taskName, 'timestamp': DateTime.now().toIso8601String()}));
            logger.i('[$taskName] Webhook 响应: ${r.statusCode}');
          }
          break;
      }
      logger.i('[$taskName] 定时任务执行完成 (type=$type)');
    } catch (e, s) {
      logger.e('[$taskName] 定时任务执行失败', error: e, stackTrace: s);
    }
  }

  void _cancelTask(ScheduledTask task) {
    _scheduler.cancelTask(task.name);
    unawaited(_scheduler.saveTasks());
    setState(() {});
    FlutterToastr.show('任务已取消', context, duration: 2, backgroundColor: Colors.green);
  }

  // ==================== Tab 2: 事件监听 ====================

  Widget _buildEventListenersTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_registeredListeners.isEmpty)
          _emptyStateInline(Icons.event, '暂无事件监听器', '点击 + 注册监听器\n触发时可执行日志/任务')
        else
          ..._registeredListeners.map((l) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _eventTypeColor(l.eventName),
                    child: Icon(_eventTypeIcon(l.eventName), color: Colors.white, size: 20),
                  ),
                  title: Text(l.description),
                  subtitle: Text(l.eventName, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: l.enabled,
                        onChanged: (v) => _toggleEventListener(l, v),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                        onPressed: () => _removeEventListener(l),
                      ),
                    ],
                  ),
                ),
              )),
        const SizedBox(height: 60),
        _infoCard(Colors.blue, Icons.info_outline, '事件类型说明',
            '• HTTP 请求事件：匹配 URL 正则触发\n• 网络状态事件：连接/断开/wifi/弱网\n• 代理状态事件：启动/停止/暂停/恢复\n• 抓包阈值事件：抓包数达到阈值'),
      ],
    );
  }

  void _showAddEventListenerDialog(BuildContext context) {
    int eventType = 0; // 0 http 1 network 2 proxy 3 capture
    final patternController = TextEditingController(text: '.*');
    NetworkStatus networkStatus = NetworkStatus.disconnected;
    ProxyStatus proxyStatus = ProxyStatus.started;
    final thresholdController = TextEditingController(text: '100');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加事件监听器'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    isDense: true,
                    value: eventType,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('HTTP 请求事件', maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false)),
                      DropdownMenuItem(value: 1, child: Text('网络状态事件', maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false)),
                      DropdownMenuItem(value: 2, child: Text('代理状态事件', maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false)),
                      DropdownMenuItem(value: 3, child: Text('抓包阈值事件', maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false)),
                    ],
                    selectedItemBuilder: _selectedItems<int>(const [0, 1, 2, 3],
                        (v) => const ['HTTP 请求事件', '网络状态事件', '代理状态事件', '抓包阈值事件'][v]),
                    onChanged: (v) => setDialogState(() => eventType = v ?? 0),
                  ),
                  const SizedBox(height: 12),
                  if (eventType == 0)
                    TextField(
                      controller: patternController,
                      decoration: const InputDecoration(
                          labelText: 'URL 正则', hintText: '.*', border: OutlineInputBorder()),
                    ),
                  if (eventType == 1)
                    DropdownButtonFormField<NetworkStatus>(
                      isExpanded: true,
                      isDense: true,
                      value: networkStatus,
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                      items: NetworkStatus.values
                          .map((s) => DropdownMenuItem(value: s, child: _dropdownText(s.name)))
                          .toList(),
                      selectedItemBuilder: _selectedItems<NetworkStatus>(NetworkStatus.values, (s) => s.name),
                      onChanged: (v) => setDialogState(() => networkStatus = v ?? NetworkStatus.disconnected),
                    ),
                  if (eventType == 2)
                    DropdownButtonFormField<ProxyStatus>(
                      isExpanded: true,
                      isDense: true,
                      value: proxyStatus,
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                      items: ProxyStatus.values
                          .map((s) => DropdownMenuItem(value: s, child: _dropdownText(s.name)))
                          .toList(),
                      selectedItemBuilder: _selectedItems<ProxyStatus>(ProxyStatus.values, (s) => s.name),
                      onChanged: (v) => setDialogState(() => proxyStatus = v ?? ProxyStatus.started),
                    ),
                  if (eventType == 3)
                    TextField(
                      controller: thresholdController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '抓包数量阈值', border: OutlineInputBorder()),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            ElevatedButton(
              onPressed: () {
                String eventName = '';
                String desc = '';
                final EventCallback callback = (data) {
                  logger.i('事件触发 $eventName: $data');
                };
                switch (eventType) {
                  case 0:
                    eventName = 'http_request:${patternController.text}';
                    desc = 'HTTP 请求: ${patternController.text}';
                    break;
                  case 1:
                    eventName = 'network_status:${networkStatus.name}';
                    desc = '网络状态: ${networkStatus.name}';
                    break;
                  case 2:
                    eventName = 'proxy_status:${proxyStatus.name}';
                    desc = '代理状态: ${proxyStatus.name}';
                    break;
                  default:
                    final n = int.tryParse(thresholdController.text) ?? 0;
                    eventName = 'capture_threshold:$n';
                    desc = '抓包阈值: $n';
                }
                _eventAutomation.addListener(eventName, callback);
                _registeredListeners.add(_RegisteredEventListener(
                    eventName: eventName, description: desc, callback: callback, enabled: true));
                Navigator.pop(context);
                FlutterToastr.show('监听器已注册', context, duration: 2, backgroundColor: Colors.green);
                setState(() {});
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleEventListener(_RegisteredEventListener l, bool enable) {
    if (enable) {
      _eventAutomation.addListener(l.eventName, l.callback);
    } else {
      _eventAutomation.removeListener(l.eventName, l.callback);
    }
    setState(() => l.enabled = enable);
  }

  void _removeEventListener(_RegisteredEventListener l) {
    _eventAutomation.removeListener(l.eventName, l.callback);
    setState(() => _registeredListeners.remove(l));
    FlutterToastr.show('监听器已移除', context, duration: 2, backgroundColor: Colors.green);
  }

  Color _eventTypeColor(String eventName) {
    if (eventName.startsWith('http_request')) return Colors.blue;
    if (eventName.startsWith('network_status')) return Colors.green;
    if (eventName.startsWith('proxy_status')) return Colors.orange;
    if (eventName.startsWith('capture_threshold')) return Colors.purple;
    return Colors.grey;
  }

  IconData _eventTypeIcon(String eventName) {
    if (eventName.startsWith('http_request')) return Icons.http;
    if (eventName.startsWith('network_status')) return Icons.wifi;
    if (eventName.startsWith('proxy_status')) return Icons.security;
    if (eventName.startsWith('capture_threshold')) return Icons.filter_alt;
    return Icons.event;
  }

  // ==================== Tab 3: 规则引擎 ====================

  Widget _buildRuleEngineTab() {
    final rules = _ruleEngine.rules;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (rules.isEmpty)
          _emptyStateInline(Icons.rule, '暂无自动化规则', '点击 + 添加规则\n规则可根据条件自动执行操作')
        else
          ...rules.map((rule) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: _rulePriorityColor(rule.priority),
                    child: Icon(Icons.rule, color: Colors.white, size: 20),
                  ),
                  title: Text(rule.name),
                  subtitle: Text(
                    '${rule.conditions.length} 条件 • ${rule.actions.length} 操作 • ${rule.enabled ? '已启用' : '已禁用'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(value: rule.enabled, onChanged: (v) => _toggleRule(rule, v)),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _showRuleDialog(context, rule),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                        onPressed: () => _deleteRule(rule),
                      ),
                    ],
                  ),
                  children: [
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('条件:', style: TextStyle(fontWeight: FontWeight.bold)),
                          ...rule.conditions.map((c) => Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('• ${_formatCondition(c)}'),
                              )),
                          const SizedBox(height: 12),
                          const Text('操作:', style: TextStyle(fontWeight: FontWeight.bold)),
                          ...rule.actions.map((a) => Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('• ${_formatAction(a)}'),
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        const SizedBox(height: 60),
        _infoCard(Colors.purple, Icons.lightbulb_outline, '规则引擎说明',
            '支持 14 种条件运算符与 8 种操作类型\n规则持久化到 mcp_rules.json，跨重启保留'),
      ],
    );
  }

  void _showRuleDialog(BuildContext context, Rule? existing) {
    final isEdit = existing != null;
    final nameController = TextEditingController(text: existing?.name ?? '');
    final descController = TextEditingController(text: existing?.description ?? '');
    RulePriority priority = existing?.priority ?? RulePriority.normal;
    bool enabled = existing?.enabled ?? true;

    // 可编辑的条件/操作行
    final conditions = List<_ConditionRow>.from(
        existing?.conditions.map((c) => _ConditionRow.fromCondition(c)) ?? [_ConditionRow()]);
    final actions = List<_ActionRow>.from(
        existing?.actions.map((a) => _ActionRow.fromAction(a)) ?? [_ActionRow()]);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? '编辑规则' : '添加规则'),
          // 限制弹窗最大宽度/高度：避免宽屏下弹窗撑满整个屏幕、
          // 内容超高时 actions 被顶出屏幕外（内部可滚动）
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.sizeOf(context).height * 0.82,
            ),
            child: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: '规则名称', border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 8),
                  TextField(
                      controller: descController,
                      decoration: const InputDecoration(labelText: '描述', border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<RulePriority>(
                    value: priority,
                    isExpanded: true,
                    isDense: true,
                    decoration: const InputDecoration(labelText: '优先级', border: OutlineInputBorder(), isDense: true),
                    items: RulePriority.values.map((p) => DropdownMenuItem(value: p, child: _dropdownText(p.name))).toList(),
                    selectedItemBuilder: _selectedItems<RulePriority>(RulePriority.values, (p) => p.name),
                    onChanged: (v) => setDialogState(() => priority = v ?? RulePriority.normal),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('启用'),
                      Switch(value: enabled, onChanged: (v) => setDialogState(() => enabled = v)),
                    ],
                  ),
                  const Divider(),
                  _sectionHeader('条件', () => setDialogState(() => conditions.add(_ConditionRow()))),
                  ...conditions.asMap().entries.map((e) {
                    final i = e.key;
                    final c = e.value;
                    final fields = _ConditionRow.fieldsForType(c.type);
                    return _removableTile(
                      title: Column(children: [
                        // 条件类型选择
                        DropdownButtonFormField<ConditionType>(
                          // custom 类型不在候选列表，编辑持久化规则时退化为 httpRequest，避免断言崩溃
                          value: (c.type != ConditionType.custom && ConditionType.values.contains(c.type))
                              ? c.type
                              : ConditionType.httpRequest,
                          isExpanded: true,
                          isDense: true,
                          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: '条件类型', isDense: true),
                          items: [
                            for (final t in ConditionType.values)
                              if (t != ConditionType.custom)
                                DropdownMenuItem(value: t, child: _dropdownText(_conditionTypeLabel(t))),
                          ],
                          selectedItemBuilder: (context) => [
                            for (final t in ConditionType.values)
                              if (t != ConditionType.custom)
                                Align(alignment: Alignment.centerLeft, child: _dropdownText(_conditionTypeLabel(t))),
                          ],
                          onChanged: (v) => setDialogState(() {
                            c.type = v ?? ConditionType.httpRequest;
                            // 切换类型时重置字段为第一个可用字段
                            final newFields = _ConditionRow.fieldsForType(c.type);
                            c.field = newFields.isNotEmpty ? newFields.first : 'url';
                            c.valueController.clear();
                          }),
                        ),
                        const SizedBox(height: 6),
                        // 字段独占整行：长字段名(如「请求 Content-Type」)在任何屏幕宽度/字号下都完整显示，
                        // 配合 isDense + 单行省略 + Tooltip，彻底消除"只显示前半截"的问题
                        DropdownButtonFormField<String>(
                          value: fields.contains(c.field) ? c.field : (fields.isNotEmpty ? fields.first : 'url'),
                          isExpanded: true,
                          isDense: true,
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                          items: fields
                              .map((f) => DropdownMenuItem(value: f, child: _dropdownText(_ConditionRow.fieldDisplayName(c.type, f))))
                              .toList(),
                          selectedItemBuilder: _selectedItems<String>(fields, (f) => _ConditionRow.fieldDisplayName(c.type, f)),
                          onChanged: (v) => setDialogState(() => c.field = v ?? fields.first),
                        ),
                        const SizedBox(height: 6),
                        // 运算符独占整行：不再与字段争抢宽度
                        DropdownButtonFormField<Operator>(
                          value: c.operator,
                          isExpanded: true,
                          isDense: true,
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                          items: Operator.values.map((o) => DropdownMenuItem(value: o, child: _dropdownText(_formatOperator(o)))).toList(),
                          selectedItemBuilder: _selectedItems<Operator>(Operator.values, _formatOperator),
                          onChanged: (v) => setDialogState(() => c.operator = v ?? Operator.equals),
                        ),
                      ]),
                      subtitle: _buildValueEditor(c, setDialogState),
                      onDelete: () => setDialogState(() => conditions.removeAt(i)),
                    );
                  }),
                  const SizedBox(height: 8),
                  _sectionHeader('操作', () => setDialogState(() => actions.add(_ActionRow()))),
                  ...actions.asMap().entries.map((e) {
                    final i = e.key;
                    final a = e.value;
                    return _removableTile(
                      title: DropdownButtonFormField<ActionType>(
                        value: a.type,
                        isExpanded: true,
                        isDense: true,
                        decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                        items: ActionType.values
                            .map((t) => DropdownMenuItem(value: t, child: _dropdownText(_formatActionType(t))))
                            .toList(),
                        selectedItemBuilder: _selectedItems<ActionType>(ActionType.values, _formatActionType),
                        onChanged: (v) => setDialogState(() => a.type = v ?? ActionType.log),
                      ),
                      subtitle: TextField(
                        controller: a.targetController,
                        decoration: InputDecoration(
                         
                          labelText: a.type == ActionType.sendWebhook ? 'Webhook URL' : '目标 / 参数(JSON)',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      onDelete: () => setDialogState(() => actions.removeAt(i)),
                    );
                  }),
                ],
              ),
            ),
          ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty) {
                  FlutterToastr.show('请输入规则名称', context, duration: 2, backgroundColor: Colors.red);
                  return;
                }
                final condList = conditions
                    .where((c) => c.field.isNotEmpty && c.valueController.text.isNotEmpty)
                    .map((c) => c.toCondition())
                    .toList();
                final actList = actions
                    .where((a) => a.targetController.text.isNotEmpty)
                    .map((a) => a.toAction())
                    .toList();
                final id = existing?.id ?? 'rule_${DateTime.now().millisecondsSinceEpoch}';
                final rule = Rule(
                  id: id,
                  name: nameController.text,
                  description: descController.text,
                  conditions: condList,
                  actions: actList,
                  priority: priority,
                  enabled: enabled,
                );
                if (isEdit) {
                  _ruleEngine.updateRule(id, rule);
                } else {
                  _ruleEngine.addRule(rule);
                }
                await _ruleEngine.saveRules();
                _notifyRulesChanged();
                if (context.mounted) Navigator.pop(context);
                FlutterToastr.show(isEdit ? '规则已更新' : '规则已添加', context, duration: 2, backgroundColor: Colors.green);
                setState(() {});
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleRule(Rule rule, bool enable) {
    if (enable) {
      _ruleEngine.enableRule(rule.id);
    } else {
      _ruleEngine.disableRule(rule.id);
    }
    _ruleEngine.saveRules();
    _notifyRulesChanged();
    setState(() {});
    FlutterToastr.show(enable ? '规则已启用' : '规则已禁用', context, duration: 2, backgroundColor: Colors.green);
  }

  void _deleteRule(Rule rule) {
    _ruleEngine.removeRule(rule.id);
    _ruleEngine.saveRules();
    _notifyRulesChanged();
    setState(() {});
    FlutterToastr.show('规则已删除', context, duration: 2, backgroundColor: Colors.green);
  }

  Color _rulePriorityColor(RulePriority priority) {
    switch (priority) {
      case RulePriority.high:
      case RulePriority.critical:
        return Colors.red;
      case RulePriority.normal:
        return Colors.orange;
      case RulePriority.low:
        return Colors.green;
    }
  }

  String _formatCondition(Condition c) {
    final typeLabel = switch (c.type) {
      ConditionType.httpRequest => 'HTTP',
      ConditionType.proxyStatus => '代理',
      ConditionType.networkStatus => '网络',
      ConditionType.systemStatus => '系统',
      ConditionType.custom => '自定义',
    };
    final fieldName = _ConditionRow.fieldDisplayName(c.type, c.field);
    return '[$typeLabel] $fieldName ${_formatOperator(c.operator)} ${c.value}';
  }

  String _conditionTypeLabel(ConditionType type) {
    switch (type) {
      case ConditionType.httpRequest: return 'HTTP 请求';
      case ConditionType.proxyStatus: return '代理状态';
      case ConditionType.networkStatus: return '网络状态';
      case ConditionType.systemStatus: return '系统状态';
      case ConditionType.custom: return '自定义';
    }
  }

  /// 下拉菜单项的统一文本样式：显式单行、超宽省略、禁止换行。
  ///
  /// DropdownButtonFormField 的「选中值显示区」高度由输入框固定，长文本（如
  /// 「请求 Content-Type」）默认会自动换行，第二行随即被高度裁掉——用户只看到
  /// 前半截（如「请求 Co」），且既无省略号也无法滚动。这里统一约束为单行 +
  /// ellipsis，配合 isExpanded 与 isDense，保证任意宽度/字号下都可完整辨识。
  static Widget _dropdownText(String text) => text.isEmpty
      ? const SizedBox.shrink()
      : Tooltip(
          // 长按/悬停可查看被省略的完整文本，避免"看不全又无从得知"的困惑
          message: text,
          waitDuration: const Duration(milliseconds: 500),
          child: Text(
            text,
            style: const TextStyle(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        );

  /// 生成 dropdown 的 selectedItemBuilder：让选中值左对齐并按单行省略渲染，
  /// 避免复用菜单项 widget（可换行）导致的裁切。
  static List<Widget> Function(BuildContext) _selectedItems<T>(
      List<T> values, String Function(T) label) {
    return (context) => values
        .map((v) => Align(alignment: Alignment.centerLeft, child: _dropdownText(label(v))))
        .toList();
  }

  /// 下拉输入框统一样式：紧凑（isDense）且留出更小的内容内边距，
  /// 让可用文本宽度最大化，减少长文本被省略的概率。
  static const InputBorder _dropdownBorder = OutlineInputBorder();

  /// 条件值编辑器:枚举型 status 字段(代理/网络状态)在 equals/notEquals 时用下拉,
  /// 其余情况(数值/正则/列表/时间戳等)用文本框。
  Widget _buildValueEditor(_ConditionRow c, void Function(VoidCallback) setDialogState) {
    final opts = _ConditionRow.valueOptions(c.type, c.field);
    if (opts != null && (c.operator == Operator.equals || c.operator == Operator.notEquals)) {
      return DropdownButtonFormField<String>(
        value: opts.contains(c.valueController.text) ? c.valueController.text : null,
        isExpanded: true,
        isDense: true,
        decoration: const InputDecoration(labelText: '值', border: OutlineInputBorder(), isDense: true),
        items: opts
            .map((v) => DropdownMenuItem(value: v, child: _dropdownText(_ConditionRow.valueDisplayName(c.type, v))))
            .toList(),
        selectedItemBuilder: _selectedItems<String>(opts, (v) => _ConditionRow.valueDisplayName(c.type, v)),
        onChanged: (v) => setDialogState(() => c.valueController.text = v ?? ''),
      );
    }
    return TextField(
      controller: c.valueController,
      decoration: const InputDecoration(labelText: '值', border: OutlineInputBorder(), isDense: true),
    );
  }

  String _formatOperator(Operator operator) {
    switch (operator) {
      case Operator.equals: return '=';
      case Operator.notEquals: return '≠';
      case Operator.greaterThan: return '>';
      case Operator.lessThan: return '<';
      case Operator.greaterThanOrEqual: return '≥';
      case Operator.lessThanOrEqual: return '≤';
      case Operator.contains: return '包含';
      case Operator.startsWith: return '始于';
      case Operator.endsWith: return '终于';
      case Operator.matches: return '匹配';
      case Operator.inList: return '在...中';
      case Operator.notInList: return '不在...中';
      case Operator.exists: return '存在';
      case Operator.notExists: return '不存在';
    }
  }

  String _formatAction(Action a) {
    return '${_formatActionType(a.type)}: ${a.target ?? a.parameters ?? ''}';
  }

  String _formatActionType(ActionType type) {
    switch (type) {
      case ActionType.log: return '记录';
      case ActionType.notify: return '通知';
      case ActionType.stopCapture: return '停止抓包';
      case ActionType.startCapture: return '开始抓包';
      case ActionType.exportData: return '导出数据';
      case ActionType.executeScript: return '执行脚本';
      case ActionType.sendWebhook: return '发送 Webhook';
      case ActionType.custom: return '自定义';
    }
  }

  // ==================== Tab 4: Prompts ====================

  Widget _buildPromptsTab() {
    if (_prompts.isEmpty) {
      return _emptyState(Icons.chat, '暂无 Prompts', _mcpRunning == true ? '点击 + 调用 Prompt' : 'MCP 服务未启动，请先在连接页启动');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _prompts.length,
      itemBuilder: (context, index) {
        final p = _prompts[index];
        final name = p['name']?.toString() ?? '';
        final desc = p['description']?.toString() ?? '';
        // 防御：arguments 可能不是 List（异常数据直接白屏），统一安全转换
        final args = p['arguments'] is List ? (p['arguments'] as List) : const [];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.chat, color: Colors.white, size: 20)),
            title: Text(name),
            subtitle: Text(
              args.isEmpty
                  ? desc
                  : '$desc\n参数: ${args.map((a) => a is Map ? a['name'] : a).join(', ')}',
              style: const TextStyle(fontSize: 12),
            ),
            isThreeLine: args.isNotEmpty,
            onTap: () => _showPromptInvokeDialog(context, p),
          ),
        );
      },
    );
  }

  void _showPromptInvokeDialog(BuildContext context, Map<String, dynamic>? prompt) {
    final prompts = _prompts;
    if (prompts.isEmpty) {
      FlutterToastr.show('暂无可用 Prompt', context, backgroundColor: Colors.orange);
      return;
    }
    Map<String, dynamic> selected = prompt ?? prompts.first;
    final argControllers = <String, TextEditingController>{};

    // 按 name 查找 prompt（下拉框用 String 值，避免 Map 引用比较带来的断言风险）
    Map<String, dynamic>? promptByName(String name) {
      for (final p in prompts) {
        if ((p['name']?.toString() ?? '') == name) return p;
      }
      return null;
    }

    void buildControllers(Map<String, dynamic> p) {
      argControllers.clear();
      final args = p['arguments'] is List ? (p['arguments'] as List) : const [];
      for (final a in args) {
        if (a is! Map) continue;
        final name = (a['name'] ?? '').toString();
        if (name.isNotEmpty) argControllers[name] = TextEditingController();
      }
    }

    buildControllers(selected);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('调用 Prompt'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: selected['name']?.toString(),
                    isExpanded: true,
                    isDense: true,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: prompts
                        .map((p) => DropdownMenuItem(
                            value: p['name']?.toString() ?? '',
                            child: _dropdownText(p['name']?.toString() ?? '未命名')))
                        .toList(),
                    selectedItemBuilder: _selectedItems<String>(
                        prompts.map((p) => p['name']?.toString() ?? '').toList(),
                        (name) => name.isEmpty ? '未命名' : name),
                    onChanged: (v) {
                      if (v == null) return;
                      final found = promptByName(v);
                      if (found == null) return;
                      setDialogState(() {
                        selected = found;
                        buildControllers(found);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(selected['description']?.toString() ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 12),
                  if (argControllers.isEmpty)
                    const Text('该 Prompt 无需参数', style: TextStyle(fontSize: 13))
                  else
                    ...argControllers.entries.map((e) {
                      final argDefs = selected['arguments'] is List ? (selected['arguments'] as List) : const [];
                      Map<String, dynamic> argDef = const {};
                      for (final a in argDefs) {
                        if (a is Map && (a['name'] ?? '') == e.key) {
                          argDef = Map<String, dynamic>.from(a);
                          break;
                        }
                      }
                      final required = argDef['required'] == true;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextField(
                          controller: e.value,
                          decoration: InputDecoration(
                            labelText: required ? '${e.key} *' : e.key,
                            border: const OutlineInputBorder(),
                           
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                final name = selected['name']?.toString() ?? '';
                final args = <String, dynamic>{};
                for (final e in argControllers.entries) {
                  args[e.key] = e.value.text;
                }
                // 必填校验（防御：参数定义可能不是标准 Map 结构）
                final argDefs = selected['arguments'] is List ? (selected['arguments'] as List) : const [];
                for (final ad in argDefs) {
                  if (ad is! Map) continue;
                  final adName = (ad['name'] ?? '').toString();
                  if (ad['required'] == true && (args[adName] ?? '').toString().isEmpty) {
                    FlutterToastr.show('请填写必填参数: $adName', context, duration: 2, backgroundColor: Colors.red);
                    return;
                  }
                }
                FlutterToastr.show('正在调用 Prompt…', context, duration: 1, backgroundColor: Colors.blue);
                Map<String, dynamic>? result;
                try {
                  // 优先走 MCP 协议（支持参数），失败回退到本地 getPrompt
                  final res = await _mcpSendRequest('prompts/get', {'name': name, 'arguments': args});
                  result = (res?['result'] as Map<String, dynamic>?) ?? res;
                } catch (e) {
                  logger.w('sendRequest prompts/get 失败，回退 getPrompt', error: e);
                }
                result ??= _mcpServer.getPrompt(name);
                if (context.mounted) Navigator.pop(context);
                _showPromptResult(context, name, result);
              },
              child: const Text('调用'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPromptResult(BuildContext context, String name, Map<String, dynamic>? result) {
    // 防御：messages 可能缺失或元素不是标准 Map（异常数据直接白屏）
    final messages = result?['messages'] is List ? (result?['messages'] as List) : const [];
    final text = messages.isEmpty
        ? (result?.toString() ?? '无返回内容')
        : messages.map((m) {
            if (m is! Map) return m.toString();
            final role = m['role'] ?? '';
            final content = m['content'];
            if (content is List) {
              return '[$role]\n${content.map((c) => c is Map ? (c['text'] ?? c.toString()) : c.toString()).join('\n')}';
            }
            return '[$role] $content';
          }).join('\n\n');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Prompt: $name'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(text, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      ),
    );
  }

  // ==================== Tab 5: Roots（目录浏览器） ====================

  Widget _buildRootsTab() {
    if (_roots.isEmpty) {
      return _emptyState(Icons.folder_open, '暂无 Roots', '点击右下角 + 添加 Root\n可添加 proxypin:// 或 file:// 资源根，自由编辑');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _roots.length,
      itemBuilder: (context, index) {
        final r = _roots[index];
        final uri = r['uri']?.toString() ?? '';
        final name = r['name']?.toString() ?? uri;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.indigo, child: Icon(Icons.folder, color: Colors.white, size: 20)),
            title: Text(name),
            subtitle: Text(uri, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: '编辑',
                  onPressed: () => _showRootDialog(context, r),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  tooltip: '删除',
                  onPressed: () => _deleteRoot(r),
                ),
              ],
            ),
            onTap: () => _readRoot(context, uri, name),
          ),
        );
      },
    );
  }

  Future<void> _readRoot(BuildContext context, String uri, String name) async {
    FlutterToastr.show('读取 $name…', context, duration: 1, backgroundColor: Colors.blue);
    String text;
    try {
      final res = await _mcpSendRequest('resources/read', {'uri': uri});
      final result = (res?['result'] as Map<String, dynamic>?) ?? res;
      final contents = (result?['contents'] as List?) ?? [];
      if (contents.isEmpty) {
        text = '空';
      } else {
        text = contents.map((c) {
          final cMap = c is Map ? c : <String, dynamic>{};
          return cMap['text']?.toString() ?? cMap.toString();
        }).join('\n\n');
      }
    } catch (e) {
      text = '读取失败: $e';
      logger.e('读取 Root 失败: $uri', error: e);
    }
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(name, style: const TextStyle(fontSize: 15)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(text, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      ),
    );
  }

  // ==================== Tab 6: 工作流（可视化编辑器） ====================

  Widget _buildWorkflowTab() {
    if (_workflows.isEmpty) {
      return _emptyState(Icons.auto_awesome, '暂无工作流', '点击 + 创建工作流\n可编排多个脚本节点顺序执行');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _workflows.length,
      itemBuilder: (context, index) {
        final wf = _workflows[index];
        final nodes = (wf['nodes'] as List?) ?? [];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: (wf['enabled'] ?? true) ? Colors.green : Colors.grey,
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
            ),
            title: Text(wf['name']?.toString() ?? '未命名工作流'),
            subtitle: Text('${nodes.length} 个节点', style: const TextStyle(fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: wf['enabled'] ?? true,
                  onChanged: (v) async {
                    setState(() => wf['enabled'] = v);
                    await _saveWorkflows();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.play_arrow, color: Colors.green),
                  onPressed: () => _executeWorkflow(wf),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _showWorkflowDialog(context, wf),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  onPressed: () async {
                    setState(() => _workflows.removeAt(index));
                    await _saveWorkflows();
                    FlutterToastr.show('工作流已删除', context, duration: 2, backgroundColor: Colors.green);
                  },
                ),
              ],
            ),
            children: [
              const Divider(),
              if (nodes.isEmpty)
                const ListTile(dense: true, title: Text('无节点', style: TextStyle(fontSize: 12)))
              else
                ...nodes.map<Widget>((n) {
                  final deps = (n['dependencies'] as List?)?.join(', ') ?? '';
                  return ListTile(
                    dense: true,
                    leading: Icon(_scriptTypeIcon(n['type']?.toString()), size: 18),
                    title: Text(n['name']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                    subtitle: Text(deps.isNotEmpty ? '依赖: $deps' : '无依赖', style: const TextStyle(fontSize: 11)),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showWorkflowDialog(BuildContext context, Map<String, dynamic>? existing) async {
    final isEdit = existing != null;
    final nameController = TextEditingController(text: existing?['name']?.toString() ?? '');
    final nodes = List<Map<String, dynamic>>.from(
        (existing?['nodes'] as List?)?.map((n) => Map<String, dynamic>.from(n as Map)) ?? []);

    List<String> scriptNames = [];
    Future<void> loadScripts() async {
      try {
        final mgr = await ScriptManager.instance;
        scriptNames = mgr.list.map((s) => s.name ?? '').where((n) => n.isNotEmpty).toList();
      } catch (e) {
        logger.w('加载脚本列表失败', error: e);
      }
    }

    await loadScripts();

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? '编辑工作流' : '添加工作流'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: '工作流名称', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  _sectionHeader('节点', () {
                    if (scriptNames.isEmpty) {
                      FlutterToastr.show('暂无脚本，先在脚本页添加', context, backgroundColor: Colors.orange);
                      return;
                    }
                    setDialogState(() {
                      final id = 'node_${DateTime.now().millisecondsSinceEpoch}';
                      nodes.add({
                        'id': id,
                        'name': scriptNames.first,
                        'type': 'javascript',
                        'scriptId': scriptNames.first,
                        'dependencies': <String>[],
                      });
                    });
                  }),
                  if (nodes.isEmpty)
                    const Padding(padding: EdgeInsets.all(8), child: Text('点击 + 添加节点', style: TextStyle(fontSize: 12)))
                  else
                    ...nodes.asMap().entries.map((e) {
                      final i = e.key;
                      final n = e.value;
                      final otherNames = nodes.where((nn) => nn['id'] != n['id']).map((nn) => nn['name']?.toString() ?? '').toList();
                      return _removableTile(
                        title: Row(children: [
                          Icon(_scriptTypeIcon(n['type']?.toString()), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              isDense: true,
                              value: n['name']?.toString(),
                              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                              items: scriptNames.map((s) => DropdownMenuItem(value: s, child: _dropdownText(s))).toList(),
                              selectedItemBuilder: _selectedItems<String>(scriptNames, (s) => s),
                              onChanged: (v) => setDialogState(() {
                                n['name'] = v;
                                n['scriptId'] = v;
                              }),
                            ),
                          ),
                        ]),
                        subtitle: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: otherNames.map((dep) {
                            final deps = (n['dependencies'] as List?) ?? [];
                            final selected = deps.contains(dep);
                            return FilterChip(
                              label: Text(dep),
                              selected: selected,
                              onSelected: (sel) => setDialogState(() {
                                final list = (n['dependencies'] as List?) ?? [];
                                if (sel) {
                                  list.add(dep);
                                } else {
                                  list.remove(dep);
                                }
                                n['dependencies'] = list;
                              }),
                            );
                          }).toList(),
                        ),
                        onDelete: () => setDialogState(() => nodes.removeAt(i)),
                      );
                    }),
                  const SizedBox(height: 8),
                  const Text('节点按依赖关系拓扑执行；依赖显示为可点选的标签。',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty) {
                  FlutterToastr.show('请输入工作流名称', context, duration: 2, backgroundColor: Colors.red);
                  return;
                }
                final wf = <String, dynamic>{
                  'id': existing?['id'] ?? 'wf_${DateTime.now().millisecondsSinceEpoch}',
                  'name': nameController.text,
                  'enabled': existing?['enabled'] ?? true,
                  'nodes': nodes,
                };
                if (isEdit) {
                  final idx = _workflows.indexWhere((w) => w['id'] == wf['id']);
                  if (idx != -1) _workflows[idx] = wf;
                } else {
                  _workflows.add(wf);
                }
                await _saveWorkflows();
                if (context.mounted) Navigator.pop(context);
                FlutterToastr.show(isEdit ? '工作流已更新' : '工作流已添加', context, duration: 2, backgroundColor: Colors.green);
                setState(() {});
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeWorkflow(Map<String, dynamic> workflow) async {
    final nodes = (workflow['nodes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (nodes.isEmpty) {
      FlutterToastr.show('工作流没有节点', context, backgroundColor: Colors.orange);
      return;
    }
    if (mounted) FlutterToastr.show('开始执行工作流：${workflow['name']}', context, backgroundColor: Colors.blue);
    await _executeWorkflowNodes(workflow);
    if (mounted) FlutterToastr.show('工作流执行完成', context, backgroundColor: Colors.green);
  }

  /// 工作流节点拓扑执行（UI 无关，供 play 按钮与定时任务执行器复用）
  Future<void> _executeWorkflowNodes(Map<String, dynamic> workflow) async {
    final nodes = (workflow['nodes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    // 拓扑排序
    final ordered = <Map<String, dynamic>>[];
    final added = <String>{};
    var progress = true;
    while (ordered.length < nodes.length && progress) {
      progress = false;
      for (final n in nodes) {
        final id = n['id']?.toString() ?? '';
        if (added.contains(id)) continue;
        final deps = (n['dependencies'] as List?)?.cast<String>() ?? [];
        if (deps.every((d) => added.contains(d) || !nodes.any((nn) => nn['id'] == d))) {
          ordered.add(n);
          added.add(id);
          progress = true;
        }
      }
    }
    for (final n in ordered) {
      try {
        final scriptId = n['scriptId']?.toString() ?? n['name']?.toString() ?? '';
        logger.i('▶ 执行节点 ${n['name']} (scriptId=$scriptId)');
        if (scriptId.isNotEmpty) {
          await _runScriptByName(scriptId);
        } else {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } catch (e) {
        logger.e('节点 ${n['name']} 执行失败', error: e);
      }
    }
  }

  IconData _scriptTypeIcon(String? type) {
    switch (type) {
      case 'javascript': return Icons.javascript;
      case 'dart': return Icons.code;
      case 'shell': return Icons.terminal;
      default: return Icons.description;
    }
  }

  // ==================== 通用 UI 辅助 ====================

  Widget _emptyState(IconData icon, String title, String hint) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(fontSize: 16, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text(hint, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _emptyStateInline(IconData icon, String title, String hint) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(icon, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontSize: 15, color: Colors.grey[600])),
            const SizedBox(height: 6),
            Text(hint, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(Color color, IconData icon, String title, String body) {
    return Card(
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            ]),
            const SizedBox(height: 12),
            Text(body, style: const TextStyle(fontSize: 12, color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, VoidCallback onAdd) {
    return Row(children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      const Spacer(),
      IconButton(icon: const Icon(Icons.add_circle, size: 22), onPressed: onAdd),
    ]);
  }

  Widget _removableTile({required Widget title, Widget? subtitle, required VoidCallback onDelete}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: ListTile(dense: true, title: title, subtitle: subtitle)),
          IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red, size: 20), onPressed: onDelete),
        ],
      ),
    );
  }

  Widget _optionDropdown(List<String> options, String? value, String hint, ValueChanged<String?> onChanged,
      {String emptyHint = ''}) {
    if (options.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(emptyHint, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      );
    }
    return DropdownButtonFormField<String>(
      isExpanded: true,
      isDense: true,
      value: (value != null && options.contains(value)) ? value : null,
      decoration: InputDecoration(border: const OutlineInputBorder(), labelText: hint, isDense: true),
      items: options.map((o) => DropdownMenuItem(value: o, child: _dropdownText(o))).toList(),
      selectedItemBuilder: _selectedItems<String>(options, (o) => o),
      onChanged: onChanged,
    );
  }

  String _formatTime(DateTime time) {
    return '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

/// 已注册事件监听器（保留 callback 引用）
class _RegisteredEventListener {
  final String eventName;
  final String description;
  final EventCallback callback;
  bool enabled;
  _RegisteredEventListener({
    required this.eventName,
    required this.description,
    required this.callback,
    this.enabled = true,
  });
}

/// 可编辑条件行
class _ConditionRow {
  ConditionType type;
  String field;
  Operator operator;
  final TextEditingController valueController = TextEditingController();
  _ConditionRow({this.type = ConditionType.httpRequest, this.field = 'url', this.operator = Operator.equals});
  _ConditionRow.fromCondition(Condition c)
      : type = c.type,
        field = c.field,
        operator = c.operator {
    valueController.text = c.value is RegExp ? (c.value as RegExp).pattern : c.value?.toString() ?? '';
  }
  Condition toCondition() {
    final v = valueController.text;
    final value = switch (operator) {
      Operator.matches => RegExp(v),
      Operator.inList || Operator.notInList => v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
      _ => v,
    };
    return Condition(type: type, field: field, operator: operator, value: value);
  }

  /// 根据条件类型获取可用字段列表
  static List<String> fieldsForType(ConditionType t) {
    switch (t) {
      case ConditionType.httpRequest:
        return ['url', 'method', 'statusCode', 'duration', 'host', 'path', 'contentType', 'responseContentType', 'requestSize', 'responseSize'];
      case ConditionType.proxyStatus:
        return ['status', 'type', 'timestamp'];
      case ConditionType.networkStatus:
        return ['status', 'type', 'timestamp'];
      case ConditionType.systemStatus:
        return ['memoryUsage', 'captureCount', 'diskUsage', 'cpuUsage'];
      case ConditionType.custom:
        return ['customField'];
    }
  }

  /// 获取字段的显示名
  static String fieldDisplayName(ConditionType t, String field) {
    switch (t) {
      case ConditionType.httpRequest:
        switch (field) {
          case 'url': return 'URL';
          case 'method': return '方法';
          case 'statusCode': return '状态码';
          case 'duration': return '耗时(ms)';
          case 'host': return '域名';
          case 'path': return '路径';
          case 'contentType': return '请求 Content-Type';
          case 'responseContentType': return '响应 Content-Type';
          case 'requestSize': return '请求大小';
          case 'responseSize': return '响应大小';
          default: return field;
        }
      case ConditionType.proxyStatus:
        switch (field) {
          case 'status': return '代理状态';
          case 'type': return '类型';
          case 'timestamp': return '时间戳';
          default: return field;
        }
      case ConditionType.networkStatus:
        switch (field) {
          case 'status': return '网络状态';
          case 'type': return '类型';
          case 'timestamp': return '时间戳';
          default: return field;
        }
      case ConditionType.systemStatus:
        switch (field) {
          case 'memoryUsage': return '内存使用(MB)';
          case 'captureCount': return '抓包数量';
          case 'diskUsage': return '磁盘使用(MB)';
          case 'cpuUsage': return 'CPU 使用率(%)';
          default: return field;
        }
      case ConditionType.custom:
        return field;
    }
  }

  /// 枚举型 status 字段的候选值(原始枚举名,与规则引擎 context 比对一致);非枚举字段返回 null
  static List<String>? valueOptions(ConditionType t, String field) {
    switch (t) {
      case ConditionType.proxyStatus:
        return field == 'status' ? ['started', 'stopped', 'paused', 'resumed'] : null;
      case ConditionType.networkStatus:
        return field == 'status' ? ['connected', 'disconnected', 'wifi', 'mobile', 'weak'] : null;
      default:
        return null;
    }
  }

  /// 枚举候选值的中文显示名
  static String valueDisplayName(ConditionType t, String value) {
    switch (t) {
      case ConditionType.proxyStatus:
        switch (value) {
          case 'started': return '已启动';
          case 'stopped': return '已停止';
          case 'paused': return '已暂停';
          case 'resumed': return '已恢复';
          default: return value;
        }
      case ConditionType.networkStatus:
        switch (value) {
          case 'connected': return '已连接';
          case 'disconnected': return '已断开';
          case 'wifi': return 'WiFi';
          case 'mobile': return '移动数据';
          case 'weak': return '弱网';
          default: return value;
        }
      default:
        return value;
    }
  }
}

/// 可编辑操作行
class _ActionRow {
  ActionType type;
  final TextEditingController targetController = TextEditingController();
  _ActionRow({this.type = ActionType.log});
  _ActionRow.fromAction(Action a) : type = a.type {
    if (a.target != null) {
      targetController.text = a.target!;
    } else if (a.parameters != null) {
      targetController.text = jsonEncode(a.parameters);
    }
  }
  Action toAction() {
    final t = targetController.text;
    if (type == ActionType.sendWebhook) {
      return Action(type: type, target: t, parameters: {'url': t});
    }
    Map<String, dynamic>? params;
    try {
      params = t.isEmpty ? null : (jsonDecode(t) as Map<String, dynamic>).cast<String, dynamic>();
    } catch (_) {
      params = {'raw': t};
    }
    return Action(type: type, target: t, parameters: params);
  }
}
