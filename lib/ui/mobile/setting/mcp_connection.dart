import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/mcp/mcp_names.dart';
import 'package:proxypin/network/mcp/mcp_server.dart';
import 'package:proxypin/native/mcp_screen.dart';
import 'package:proxypin/utils/ip.dart';
import 'package:proxypin/ui/mobile/setting/mcp_automation.dart';

/// MCP 设置页面
/// 展示 MCP 服务状态、自动启动、连接信息、AI 配置指南、控制模式、可用工具列表
class McpConnectionPage extends StatefulWidget {
  const McpConnectionPage({super.key});

  @override
  State<McpConnectionPage> createState() => _McpConnectionPageState();
}

class _McpConnectionPageState extends State<McpConnectionPage> with WidgetsBindingObserver {
  Map<String, dynamic>? _deviceInfo;
  bool _loading = true;
  String? _deviceIp;

  // 端口输入控制器
  late TextEditingController _portController;
  // 配置中的端口（可能与运行中端口不同）
  int _configuredPort = 9010;
  // MCP 服务是否启用
  bool _mcpEnabled = true;
  // MCP 是否随应用启动自动启动
  bool _mcpAutoStart = false;
  // 工具启用状态（工具名 -> 是否启用）
  Map<String, bool> _toolsEnabled = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _portController = TextEditingController(text: '9010');
    // 注册状态变化回调，实现实时更新
    McpServer().onStatusChanged = _onMcpStatusChanged;
    _loadInfo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 清除回调，避免页面销毁后仍被调用
    McpServer().onStatusChanged = null;
    _portController.dispose();
    super.dispose();
  }

  /// 监听应用生命周期变化（用于检测从系统设置返回）
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 刷新设备状态；同步悬浮球开关（悬浮球面板内"关闭悬浮球"会写偏好）
      _refreshDeviceInfo();
      _syncFloatingBallFromPrefs();
    }
  }

  /// MCP 服务器状态变化时刷新 UI
  void _onMcpStatusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // ==================== 悬浮球 ====================
  bool _overlayPermissionGranted = false;
  bool floatingBallEnabled = false;
  bool floatingBallAutoDock = true;
  int floatingBallColor = 0xFF6750A4; // 预置主色
  int floatingBallAlpha = 255; // 透明度 0-255（默认不透明，避免"看起来还是透"）

  String get floatingBallColorDesc =>
      '颜色 #${floatingBallColor.toRadixString(16).substring(2).toUpperCase()} · 透明度 ${(floatingBallAlpha / 255 * 100).round()}%';

  static const _floatingChannel = MethodChannel('com.proxy/floatingBall');

  /// 查询悬浮窗权限状态
  Future<bool> _queryOverlayPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final r = await _floatingChannel.invokeMethod('checkOverlay');
      return r is Map && r['granted'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadFloatingBallConfig() async {
    _overlayPermissionGranted = await _queryOverlayPermission();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      // 启用默认关闭（首次/未配置时），用户开启后记住选择
      floatingBallEnabled = prefs.getBool('floatingBallEnabled') ?? false;
      floatingBallAutoDock = prefs.getBool('floatingBallAutoDock') ?? true;
      floatingBallColor = prefs.getInt('floatingBallColor') ?? 0xFF6750A4;
      floatingBallAlpha = prefs.getInt('floatingBallAlpha') ?? 255;
    });
    // 页面只负责展示状态，不在此启动服务：
    // 服务启动由 ① 冷启动 main 自动恢复（开启过）② 用户手动打开开关 两条路径负责，
    // 避免"面板关闭后进入本页又把球拉起来"的复活问题
  }

  /// 从偏好同步悬浮球状态（应用切回前台时调用，保持与悬浮球面板"关闭悬浮球"操作一致）
  Future<void> _syncFloatingBallFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      floatingBallEnabled = prefs.getBool('floatingBallEnabled') ?? false;
      floatingBallAutoDock = prefs.getBool('floatingBallAutoDock') ?? true;
      floatingBallColor = prefs.getInt('floatingBallColor') ?? 0xFF6750A4;
      floatingBallAlpha = prefs.getInt('floatingBallAlpha') ?? 255;
    });
  }

  Future<void> _saveFloatingBallConfig({bool showFeedback = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('floatingBallEnabled', floatingBallEnabled);
    await prefs.setBool('floatingBallAutoDock', floatingBallAutoDock);
    await prefs.setInt('floatingBallColor', floatingBallColor);
    await prefs.setInt('floatingBallAlpha', floatingBallAlpha);
    _updateFloatingBall(showFeedback: showFeedback);
  }

  /// 通知原生悬浮球服务（启用/更新/关闭）
  Future<void> _updateFloatingBall({bool showFeedback = false}) async {
    if (!Platform.isAndroid) return;
    try {
      final result = await _floatingChannel.invokeMethod(floatingBallEnabled ? 'start' : 'stop', {
        'autoDock': floatingBallAutoDock,
        'color': floatingBallColor,
        'alpha': floatingBallAlpha,
        'running': McpServer().isRunning,
      });
      if (!mounted) return;
      // 缺少悬浮窗权限：原生已跳转系统设置页，这里给出明确提示
      if (result is Map && result['needOverlayPermission'] == true) {
        FlutterToastr.show('悬浮球需要"显示在其他应用上层"权限，已为你打开系统设置，授权后回来重新开启',
            context, duration: 4, backgroundColor: Colors.orange);
        return;
      }
      // 启动/停止失败：展示原生返回的具体原因（不再静默无反应）
      if (result is Map && result['success'] == false) {
        FlutterToastr.show(
            '悬浮球${floatingBallEnabled ? "启动" : "停止"}失败：${result['error'] ?? '未知原因'}',
            context, duration: 4, backgroundColor: Colors.red);
        return;
      }
      // 用户手动开启时给出成功反馈 + 厂商系统拦截的兜底引导
      if (showFeedback && floatingBallEnabled) {
        FlutterToastr.show('悬浮球已开启；若屏幕上看不到，请检查系统「显示悬浮窗」与厂商「后台弹出界面」权限',
            context, duration: 4, backgroundColor: Colors.green);
      }
    } catch (e) {
      logger.w('悬浮球服务调用失败', error: e);
      if (mounted && showFeedback) {
        FlutterToastr.show('悬浮球调用失败：$e', context, duration: 4, backgroundColor: Colors.red);
      }
    }
  }

  /// 悬浮球样式自定义：预置颜色 + 取色器 + 透明度 + 实时预览
  Future<void> _showFloatingBallStyleDialog() async {
    var color = Color(floatingBallColor);
    var alpha = floatingBallAlpha;
    final presets = <String, Color>{
      'M3 紫': const Color(0xFF6750A4),
      '深海蓝': const Color(0xFF1565C0),
      '翡翠绿': const Color(0xFF2E7D32),
      '珊瑚橙': const Color(0xFFEF6C00),
      '玫瑰红': const Color(0xFFC2185B),
      '石墨黑': const Color(0xFF37474F),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('自定义悬浮球', style: TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              // 实时预览：液态玻璃球（渐变 + 高光 + 波纹），与真实悬浮球一致
              Center(
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: color.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Opacity(
                    opacity: (alpha / 255).clamp(0.2, 1.0),
                    child: CustomPaint(
                      size: const Size(76, 76),
                      painter: _GlassBallPreviewPainter(color: color),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('预置颜色', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final entry in presets.entries)
                    GestureDetector(
                      onTap: () => setDialogState(() => color = entry.value),
                      child: Column(children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: entry.value,
                            border: Border.all(
                              color: color.value == entry.value.value ? Colors.white : Colors.transparent,
                              width: 2,
                            ),
                            boxShadow: [BoxShadow(color: entry.value.withValues(alpha: 0.3), blurRadius: 6)],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(entry.key, style: const TextStyle(fontSize: 10)),
                      ]),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // 取色器（滑杆调 RGB 简化实现）
              const Text('自定义颜色（RGB）', style: TextStyle(fontSize: 12, color: Colors.grey)),
              _colorSlider('R', color.red, (v) => setDialogState(() => color = Color.fromARGB(255, v, color.green, color.blue))),
              _colorSlider('G', color.green, (v) => setDialogState(() => color = Color.fromARGB(255, color.red, v, color.blue))),
              _colorSlider('B', color.blue, (v) => setDialogState(() => color = Color.fromARGB(255, color.red, color.green, v))),
              const SizedBox(height: 8),
              Text('透明度 ${(alpha / 255 * 100).round()}%', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Slider(
                value: alpha.toDouble(),
                min: 80,
                max: 255,
                onChanged: (v) => setDialogState(() => alpha = v.round()),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            ElevatedButton(
              onPressed: () {
                setDialogState(() {});
                Navigator.pop(context, true);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        floatingBallColor = color.value;
        floatingBallAlpha = alpha;
      });
      await _saveFloatingBallConfig();
    }
  }

  Widget _colorSlider(String label, int value, ValueChanged<int> onChanged) {
    return Row(children: [
      SizedBox(width: 18, child: Text(label, style: const TextStyle(fontSize: 12))),
      Expanded(
        child: Slider(
          value: value.toDouble(),
          min: 0,
          max: 255,
          divisions: 255,
          label: '$value',
          onChanged: (v) => onChanged(v.round()),
        ),
      ),
    ]);
  }

  /// 重新加载设备信息（授权返回后刷新状态）
  Future<void> _loadDeviceInfo() async {
    if (!McpScreen.isSupported) return;
    _deviceInfo = await McpScreen.getDeviceInfo();
  }

  /// 刷新设备信息（静默刷新，不显示 loading）
  Future<void> _refreshDeviceInfo() async {
    if (!McpScreen.isSupported || !mounted) return;
    final info = await McpScreen.getDeviceInfo();
    if (mounted) {
      setState(() => _deviceInfo = info);
    }
  }

  Future<void> _loadInfo() async {
    setState(() => _loading = true);
    try {
      _deviceIp = await localIp();
      final config = await Configuration.instance;
      _configuredPort = config.mcpPort;
      _mcpEnabled = config.mcpEnabled;
      _mcpAutoStart = config.mcpAutoStart;
      _toolsEnabled = Map<String, bool>.from(config.mcpToolsEnabled);
      _portController.text = _configuredPort.toString();
      await _loadFloatingBallConfig();
      if (McpScreen.isSupported) {
        _deviceInfo = await McpScreen.getDeviceInfo();
      }
      await _loadFloatingBallConfig();
      if (McpScreen.isSupported) {
        _deviceInfo = await McpScreen.getDeviceInfo();
      }
    } catch (e) {
      // ignore
    }
    setState(() => _loading = false);
  }

  /// 切换 MCP 服务开关
  Future<void> _toggleMcpService(bool enabled) async {
    final config = await Configuration.instance;
    config.mcpEnabled = enabled;
    await config.flushConfig();

    if (enabled) {
      await McpServer().start();
    } else {
      await McpServer().stop();
    }

    setState(() {
      _mcpEnabled = enabled;
    });
  }

  /// 切换自动启动开关
  Future<void> _toggleAutoStart(bool enabled) async {
    final config = await Configuration.instance;
    config.mcpAutoStart = enabled;
    await config.flushConfig();
    setState(() {
      _mcpAutoStart = enabled;
    });
    final loc = AppLocalizations.of(context)!;
    FlutterToastr.show(
      enabled ? loc.mcpAutoStartEnabled : loc.mcpAutoStartDisabled,
      context,
    );
  }

  /// 切换单个工具启用状态
  Future<void> _toggleTool(String name, bool enabled) async {
    final config = await Configuration.instance;
    config.mcpToolsEnabled[name] = enabled;
    await config.flushConfig();
    setState(() {
      _toolsEnabled[name] = enabled;
    });
  }

  /// 应用新端口
  Future<void> _applyPort() async {
    final newPort = int.tryParse(_portController.text.trim());
    if (newPort == null || newPort < 1 || newPort > 65535) {
      final loc = AppLocalizations.of(context)!;
      FlutterToastr.show(loc.mcpPortInvalid, context);
      return;
    }

    if (newPort == _configuredPort) {
      final loc = AppLocalizations.of(context)!;
      FlutterToastr.show(loc.mcpPortUnchanged, context);
      return;
    }

    final config = await Configuration.instance;
    config.mcpPort = newPort;
    await config.flushConfig();

    // 如果 MCP 服务正在运行，重启以应用新端口
    if (config.mcpEnabled) {
      await McpServer().restart();
    }

    setState(() {
      _configuredPort = newPort;
    });
    final loc = AppLocalizations.of(context)!;
    FlutterToastr.show(loc.mcpPortApplied(newPort.toString()), context);
  }

  /// 重新生成局域网访问令牌（运行中会重启服务使旧令牌立即失效）
  Future<void> _regenerateToken() async {
    final c = Configuration.loaded;
    if (c == null) return;
    c.mcpToken = McpServer.generateToken();
    ConfigAutoSave.markChanged();
    try {
      if (McpServer().isRunning) {
        await McpServer().restart();
      }
    } catch (e) {
      _showSnack('重新生成令牌失败：$e');
    }
    if (mounted) setState(() {});
  }

  /// 各主流 AI 客户端的接入命令（合并自旧版独立设置页）
  Map<String, String> _clientCommands(String endpoint) {
    final token = McpServer().token ?? '';
    final host = endpoint.replaceFirst('/mcp', '');
    return {
      'Claude Code': 'claude mcp add ${McpClientNames.mobile} -s user --transport http $endpoint'
          '${token.isEmpty ? '' : ' --header "Authorization: Bearer $token"'}',
      'Codex': 'export PROXYPIN_MCP_TOKEN="$token"\n'
          'codex mcp add ${McpClientNames.mobile} --url $endpoint --bearer-token-env-var PROXYPIN_MCP_TOKEN',
      'curl 自检': 'curl -s${token.isEmpty ? '' : ' -H "Authorization: Bearer $token"'} $endpoint '
          '-H "Content-Type: application/json" '
          '-d \'{"jsonrpc":"2.0","id":1,"method":"tools/list"}\'',
      '一键配置(shell)': token.isEmpty
          ? '（需先开启局域网访问以生成令牌）'
          : 'curl -s -H "Authorization: Bearer $token" $host/mcp/setup.sh | sh',
      '一键配置(PowerShell)': token.isEmpty
          ? '（需先开启局域网访问以生成令牌）'
          : 'irm -Headers @{ Authorization = "Bearer $token" } $host/mcp/setup.ps1 | iex',
    };
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  /// 复制文本到剪贴板
  void _copyText(String text, String tip) {
    Clipboard.setData(ClipboardData(text: text));
    FlutterToastr.show(tip, context);
  }

  @override
  Widget build(BuildContext context) {
    final mcpServer = McpServer();
    final port = _configuredPort;
    final ip = _deviceIp ?? '127.0.0.1';
    final apiUrl = 'http://$ip:$port/mcp';
    final sseUrl = 'http://$ip:$port/sse';
    final healthUrl = 'http://$ip:$port/health';
    final isRunning = mcpServer.isRunning;
    final lastError = mcpServer.lastError;

    final mode = _deviceInfo?['mode'] as String? ?? 'none';
    final hasRoot = _deviceInfo?['hasRoot'] as bool? ?? false;
    final hasShizuku = _deviceInfo?['hasShizuku'] as bool? ?? false;
    // hasShizuku 只代表 Shizuku 正在运行（binder 已连接），不代表本应用已获授权
    final shizukuGranted = _deviceInfo?['shizukuGranted'] as bool? ?? false;
    final hasDhizuku = _deviceInfo?['hasDhizuku'] as bool? ?? false;
    final accessibilityEnabled =
        _deviceInfo?['accessibilityEnabled'] as bool? ?? false;

    final configJson = const JsonEncoder.withIndent('  ').convert({
      'mcpServers': {
        'proxypin': {'url': apiUrl},
      },
    });

    final tools = mcpServer.getTools();

    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP 设置'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const McpAutomationPage()),
              );
            },
            tooltip: '自动化配置',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 远程接入与安全（合并自旧版独立设置页）
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('允许局域网访问'),
                        subtitle: const Text('开启后同一网络内的设备可连接本机 MCP 服务', style: TextStyle(fontSize: 12)),
                        value: Configuration.loaded?.mcpAllowLan ?? false,
                        onChanged: (v) async {
                          final c = Configuration.loaded;
                          if (c == null) return;
                          setState(() => c.mcpAllowLan = v);
                          ConfigAutoSave.markChanged();
                          // 开、关都要重启：只处理「开」会让服务在关闭后继续监听 0.0.0.0。
                          // 未运行的实例不必被这个开关拉起来，下次启动时应用配置即可。
                          if (McpServer().isRunning) await McpServer().restart();
                        },
                      ),
                      const Divider(height: 0),
                      SwitchListTile(
                        title: const Text('访问令牌鉴权'),
                        subtitle: Text(
                          (Configuration.loaded?.mcpAuthEnabled ?? true)
                              ? '要求 Bearer token（推荐）'
                              : '已关闭：同一网络内任何设备都可读取抓包内容！',
                          style: TextStyle(
                            fontSize: 12,
                            color: (Configuration.loaded?.mcpAuthEnabled ?? true) ? null : Colors.red,
                          ),
                        ),
                        value: Configuration.loaded?.mcpAuthEnabled ?? true,
                        onChanged: (v) async {
                          final c = Configuration.loaded;
                          if (c == null) return;
                          setState(() => c.mcpAuthEnabled = v);
                          ConfigAutoSave.markChanged();
                          if (McpServer().isRunning) await McpServer().restart();
                        },
                      ),
                      const Divider(height: 0),
                      SwitchListTile(
                        title: const Text('后台保活'),
                        subtitle: const Text(
                            '把本应用加入电池优化白名单并解除后台限制，降低抓包与 MCP 服务被系统杀掉的可能（需 Shizuku / root / Dhizuku 之一）',
                            style: TextStyle(fontSize: 12)),
                        value: Configuration.loaded?.mcpKeepAlive ?? false,
                        onChanged: (v) async {
                          final c = Configuration.loaded;
                          if (c == null) return;
                          setState(() => c.mcpKeepAlive = v);
                          ConfigAutoSave.markChanged();
                          try {
                            await McpServer().setKeepAlive(v);
                          } catch (e) {
                            debugPrint('keep-alive failed: $e');
                          }
                        },
                      ),
                      const Divider(height: 0),
                      SwitchListTile(
                        title: const Text('参数强校验'),
                        subtitle: const Text('按工具声明的 inputSchema 校验参数，尽早提示调用错误（立即生效）',
                            style: TextStyle(fontSize: 12)),
                        value: Configuration.loaded?.mcpStrictValidation ?? true,
                        onChanged: (v) async {
                          final c = Configuration.loaded;
                          if (c == null) return;
                          setState(() => c.mcpStrictValidation = v);
                          ConfigAutoSave.markChanged();
                          McpServer().setStrictValidation(v);
                        },
                      ),
                      const Divider(height: 0),
                      ListTile(
                        leading: const Icon(Icons.key),
                        title: const Text('访问令牌'),
                        subtitle: Text(
                          McpServer().token ?? '未生成（开启局域网访问后自动生成）',
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              tooltip: '复制',
                              onPressed: () {
                                final t = McpServer().token;
                                if (t != null) _copyText(t, '令牌已复制');
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh, size: 18),
                              tooltip: '重新生成（旧令牌立即失效）',
                              onPressed: _regenerateToken,
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 0),
                      ExpansionTile(
                        leading: const Icon(Icons.terminal),
                        title: const Text('AI 客户端接入命令'),
                        subtitle: const Text('Claude Code / Codex / curl / 一键脚本', style: TextStyle(fontSize: 12)),
                        childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        children: [
                          for (final entry in _clientCommands(apiUrl).entries)
                            ListTile(
                              dense: true,
                              title: Text(entry.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              subtitle: Text(entry.value,
                                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                              trailing: IconButton(
                                icon: const Icon(Icons.copy, size: 16),
                                onPressed: () => _copyText(entry.value, '已复制'),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // MCP 服务开关与端口配置
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('MCP 服务'),
                        subtitle: Text(
                          _mcpEnabled
                              ? (isRunning
                                    ? '运行中，端口 $port'
                                    : (lastError != null
                                          ? '出错：$lastError'
                                          : '已启用（未运行）'))
                              : '已停用',
                          style: const TextStyle(fontSize: 12),
                        ),
                        secondary: Icon(
                          _mcpEnabled
                              ? (isRunning
                                    ? Icons.cloud_done
                                    : Icons.cloud_queue)
                              : Icons.cloud_off,
                          color: _mcpEnabled
                              ? (isRunning ? Colors.green : Colors.orange)
                              : Colors.grey,
                        ),
                        value: _mcpEnabled,
                        onChanged: _toggleMcpService,
                      ),
                      const Divider(height: 0),
                      SwitchListTile(
                        title: const Text('自动启动'),
                        subtitle: const Text(
                          '应用启动时自动运行 MCP 服务（默认开启）',
                          style: TextStyle(fontSize: 12),
                        ),
                        secondary: const Icon(
                          Icons.auto_awesome,
                          color: Colors.purple,
                        ),
                        value: _mcpAutoStart,
                        onChanged: _toggleAutoStart,
                      ),
                      const Divider(height: 0),
                      // 端口配置
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            const Text('服务端口'),
                            const SizedBox(width: 16),
                            Expanded(
                              child: SizedBox(
                                height: 40,
                                child: TextField(
                                  controller: _portController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(5),
                                  ],
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    border: OutlineInputBorder(),
                                    hintText: '9010',
                                  ),
                                  style: const TextStyle(fontSize: 14),
                                  onSubmitted: (_) => _applyPort(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _applyPort,
                              child: const Text('应用'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 连接信息
                Text('连接信息', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'MCP 协议版本：${McpServer.protocolVersion}（无状态核心，兼容旧版握手）',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('设备 IP'),
                        subtitle: Text(ip),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: () => _copyText(ip, '已复制设备 IP'),
                        ),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        title: const Text('API URL（Streamable HTTP）'),
                        subtitle: Text(apiUrl),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: () => _copyText(apiUrl, '已复制 API URL'),
                        ),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        title: const Text('SSE URL（旧版传输）'),
                        subtitle: Text(sseUrl),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: () => _copyText(sseUrl, '已复制 SSE URL'),
                        ),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        title: const Text('Health Check（健康检查）'),
                        subtitle: Text(healthUrl),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: () => _copyText(healthUrl, '已复制 Health Check URL'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 悬浮球设置
                Text('悬浮球', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '桌面悬浮球显示 MCP 运行状态，点击弹出快捷面板；前台服务可提升应用保活能力',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          _overlayPermissionGranted ? Icons.check_circle : Icons.error_outline,
                          size: 20,
                          color: _overlayPermissionGranted ? Colors.green : Colors.orange,
                        ),
                        title: const Text('悬浮球权限'),
                        subtitle: Text(
                          _overlayPermissionGranted ? '已授权"显示在其他应用上层"' : '未授权——点击前往系统设置开启，否则悬浮球无法显示',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: _overlayPermissionGranted
                            ? const Text('已授权', style: TextStyle(fontSize: 12, color: Colors.green))
                            : const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () async {
                          if (!_overlayPermissionGranted) {
                            // 未授权：跳转系统悬浮窗权限设置页
                            try {
                              await _floatingChannel.invokeMethod('openOverlaySettings');
                            } catch (_) {}
                            await Future.delayed(const Duration(milliseconds: 600));
                          }
                          final granted = await _queryOverlayPermission();
                          if (mounted) setState(() => _overlayPermissionGranted = granted);
                        },
                      ),
                      const Divider(height: 0),
                      SwitchListTile(
                        title: const Text('启用悬浮球'),
                        subtitle: Text(
                          _overlayPermissionGranted
                              ? '悬浮窗展示 MCP 状态，提升保活能力'
                              : '请先完成上方悬浮球权限授权',
                          style: const TextStyle(fontSize: 12),
                        ),
                        value: floatingBallEnabled,
                        onChanged: _overlayPermissionGranted
                            ? (v) {
                                setState(() => floatingBallEnabled = v);
                                _saveFloatingBallConfig(showFeedback: true);
                              }
                            : null,
                      ),
                      const Divider(height: 0),
                      SwitchListTile(
                        title: const Text('3 秒无操作自动贴边'),
                        subtitle: const Text('悬浮球自动吸附屏幕边缘，避免遮挡', style: TextStyle(fontSize: 12)),
                        value: floatingBallAutoDock,
                        onChanged: floatingBallEnabled
                            ? (v) {
                                setState(() => floatingBallAutoDock = v);
                                _saveFloatingBallConfig();
                              }
                            : null,
                      ),
                      const Divider(height: 0),
                      ListTile(
                        title: const Text('自定义悬浮球样式'),
                        subtitle: Text(floatingBallColorDesc, style: const TextStyle(fontSize: 12)),
                        trailing: const Icon(Icons.palette_outlined, size: 20),
                        onTap: floatingBallEnabled ? _showFloatingBallStyleDialog : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // AI 配置指南
                Text('AI 配置指南', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(
                          '将以下配置写入 AI 客户端的 MCP 配置文件中，即可让 '
                          'Cursor / Windsurf / Claude Desktop / Cherry Studio '
                          '等支持 MCP 的 AI 工具读取抓包数据并控制 ProxyPin。'
                          '请确保手机与电脑处于同一局域网，且 MCP 服务已开启。'
                          '服务器同时支持最新无状态协议（2026-07-28）与旧版握手协议。',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                16,
                              ),
                              child: SelectableText(
                                configJson,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: IconButton(
                                icon: const Icon(Icons.copy, size: 20),
                                onPressed: () =>
                                    _copyText(configJson, '已复制 AI 配置'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 控制模式
                Text('控制模式', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.settings_applications),
                        title: const Text('当前模式'),
                        trailing: Text(
                          switch (mode) {
                            'none' => 'none',
                            'root' => 'Root',
                            'shizuku' => 'Shizuku',
                            'dhizuku' => 'Dhizuku',
                            'accessibility' => '无障碍',
                            _ => mode,
                          },
                          style: TextStyle(
                            color: mode == 'none'
                                ? Colors.orange
                                : Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        leading: const Icon(Icons.admin_panel_settings),
                        title: const Text('Root 权限'),
                        trailing: Text(
                          hasRoot ? '可用' : '不可用',
                          style: TextStyle(
                            color: hasRoot ? Colors.green : Colors.grey,
                          ),
                        ),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        leading: const Icon(Icons.security),
                        title: const Text('Shizuku'),
                        trailing: Text(
                          shizukuGranted
                              ? '已授权'
                              : (hasShizuku ? '未授权' : '未连接'),
                          style: TextStyle(
                            color: shizukuGranted
                                ? Colors.green
                                : (hasShizuku ? Colors.orange : Colors.grey),
                          ),
                        ),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        leading: const Icon(Icons.verified_user),
                        title: const Text('Dhizuku'),
                        trailing: Text(
                          hasDhizuku ? '可用' : '不可用',
                          style: TextStyle(
                            color: hasDhizuku ? Colors.green : Colors.grey,
                          ),
                        ),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        leading: const Icon(Icons.accessibility),
                        title: const Text('无障碍服务'),
                        trailing: Text(
                          accessibilityEnabled ? '可用' : '未开启',
                          style: TextStyle(
                            color: accessibilityEnabled
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!accessibilityEnabled && McpScreen.isSupported) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.accessibility),
                      label: const Text('打开无障碍设置'),
                      onPressed: () async {
                        await McpScreen.openAccessibilitySettings();
                      },
                    ),
                  ),
                ],
                if (McpScreen.isSupported) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: Icon(
                        shizukuGranted ? Icons.verified_user : Icons.security,
                        size: 20,
                        color: shizukuGranted ? Colors.green : null,
                      ),
                      label: Text(shizukuGranted ? 'Shizuku 已授权' : '请求 Shizuku 授权'),
                      onPressed: () async {
                        final ok = await McpScreen.requestShizukuAuthorization();
                        if (!mounted) return;
                        FlutterToastr.show(
                          ok
                              ? 'Shizuku 已授权'
                              : '未完成授权：请确认 Shizuku 正在运行，并到 Shizuku 应用中选择本应用授权；或在弹窗中选择“允许”',
                          context,
                          duration: 3,
                          backgroundColor: ok ? Colors.green : Colors.orange,
                        );
                        // 授权后重新检测状态
                        await _loadDeviceInfo();
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ],
                if (McpScreen.isSupported && !hasRoot) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.admin_panel_settings),
                      label: const Text('请求 Root 授权'),
                      onPressed: () async {
                        final ok = await McpScreen.requestRootAuthorization();
                        if (!mounted) return;
                        FlutterToastr.show(
                          ok ? 'Root 已授权' : '授权未完成：请在 Magisk/KernelSU 弹窗中允许，或确认设备已 Root',
                          context,
                          duration: 3,
                          backgroundColor: ok ? Colors.green : Colors.orange,
                        );
                        // 授权后重新检测状态
                        await _loadDeviceInfo();
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ],
                if (McpScreen.isSupported && !hasDhizuku) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.verified_user),
                      label: const Text('请求 Dhizuku 授权'),
                      onPressed: () async {
                        final ok = await McpScreen.requestDhizukuAuthorization();
                        if (!mounted) return;
                        FlutterToastr.show(
                          ok ? 'Dhizuku 已授权' : '授权未完成：请确认已安装 Dhizuku 并完成 Owner 激活',
                          context,
                          duration: 3,
                          backgroundColor: ok ? Colors.green : Colors.orange,
                        );
                        // 授权后重新检测状态
                        await _loadDeviceInfo();
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // 可用工具列表
                Row(
                  children: [
                    Text(
                      '可用工具',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '共 ${tools.length} 个',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '关闭的工具将从工具列表中隐藏，AI 无法调用。',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < tools.length; i++) ...[
                        if (i > 0) const Divider(height: 0, indent: 16),
                        _ToolTile(
                          tool: tools[i],
                          enabled: _toolsEnabled[tools[i]['name']] ?? true,
                          onChanged: (v) =>
                              _toggleTool(tools[i]['name'] as String, v),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新'),
                    onPressed: _loadInfo,
                  ),
                ),
              ],
            ),
    );
  }
}

/// 单个工具卡片：工具名 + 中文备注 + 启用开关
class _ToolTile extends StatelessWidget {
  final Map<String, dynamic> tool;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ToolTile({
    required this.tool,
    required this.enabled,
    required this.onChanged,
  });

  /// 工具中文备注
  static const Map<String, String> _notes = {
    'set_config': '修改 ProxyPin 配置（系统代理、SSL 抓包开关）',
    'export_har': '将抓包记录导出为 HAR 文件',
    'import_har': '导入 HAR 文件到抓包记录',
    'search_requests': '按 URL、方法、状态码、域名等条件搜索请求',
    'generate_code': '根据请求生成代码（curl、Python、Go、JavaScript、Node.js）',
    'get_curl': '生成请求对应的 cURL 命令',
    'get_recent_requests': '获取最近抓到的请求列表',
    'get_request_details': '获取指定请求的完整详情（请求/响应头与体、Cookie）',
    'start_proxy': '启动代理服务',
    'stop_proxy': '停止代理服务',
    'get_proxy_status': '查询代理服务运行状态',
    'clear_requests': '清空抓包记录',
    'replay_request': '重放指定请求',
    'update_script': '更新注入页面的 JS 脚本',
    'get_scripts': '获取已配置的 JS 脚本列表',
    'get_statistics': '获取抓包统计信息',
    'compare_requests': '对比两个请求的差异',
    'find_similar_requests': '查找与指定请求相似的请求',
    'extract_api_endpoints': '从抓包记录中提取 API 端点聚合信息',
    'find_sensitive_data': '搜索请求中的敏感数据（密码、密钥、手机号、身份证等）',
    'get_cookie_info': '分析域名的 Cookie（值、HttpOnly、Secure、过期时间）',
    'get_domain_summary': '统计域名的流量摘要（方法、状态码、平均耗时、错误数）',
    'get_pending_intercepts': '查看断点拦截队列中待处理的请求/响应',
    'approve_intercept': '放行断点拦截（可修改请求后放行）',
    'reject_intercept': '拒绝断点拦截（中止请求或丢弃响应）',
    'toggle_breakpoint': '启用或停用断点拦截',
    'add_weak_network_rule': '添加弱网模拟规则（限速、延迟等）',
    'add_custom_network_profile': '添加自定义网络档位',
    'list_weak_network_rules': '列出所有弱网规则',
    'remove_weak_network_rule': '移除弱网规则',
    'toggle_weak_network': '启用或停用弱网模拟',
    'list_environments': '列出所有环境',
    'set_environment_variable': '设置环境变量值',
    'create_environment': '创建新环境',
    'set_active_environment': '切换当前活动环境',
    'remove_environment': '删除指定环境',
    'toggle_environment_variables': '启用或停用环境变量',
    'get_device_info': '获取设备信息（型号、系统版本、Root 状态）',
    'get_current_activity': '获取当前前台 Activity',
    'dump_ui': '导出当前界面的 UI 层级树',
    'tap_screen': '模拟点击屏幕坐标',
    'long_press': '模拟长按屏幕坐标',
    'swipe_screen': '模拟滑动屏幕',
    'key_event': '发送按键事件（如返回键、音量键）',
    'input_text': '向当前输入框输入文本',
    'screenshot': '截取当前屏幕',
    'open_accessibility_settings': '打开系统无障碍设置页',
    'shell': '执行 Shell 命令（支持 Root/Shizuku/Dhizuku 模式）',
  };

  @override
  Widget build(BuildContext context) {
    final name = tool['name'] as String? ?? '';
    final note = _notes[name] ?? (tool['description'] as String? ?? '');
    return ListTile(
      dense: true,
      title: Text(
        name,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          note,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: Switch(value: enabled, onChanged: onChanged),
    );
  }
}

/// 液态玻璃球预览绘制（与原生悬浮球一致的径向渐变 + 高光 + 波纹图案）
class _GlassBallPreviewPainter extends CustomPainter {
  final Color color;
  const _GlassBallPreviewPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    final light = Color.lerp(color, Colors.white, 0.42)!;
    final dark = Color.lerp(color, Colors.black, 0.38)!;

    // 球体径向渐变（左上亮 → 主色 → 右下暗）
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment(-0.32, -0.38),
        radius: 1.32,
        colors: [light, color, dark],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    canvas.drawCircle(Offset(cx, cy), r, paint);

    // 顶部玻璃高光
    final hlPaint = Paint()..color = Colors.white.withValues(alpha: 0.32);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx - r * 0.24, cy - r * 0.59),
          width: r * 0.64,
          height: r * 0.46),
      hlPaint,
    );
    // 底部微弱反光
    final glPaint = Paint()..color = Colors.white.withValues(alpha: 0.13);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx + r * 0.02, cy + r * 0.55),
          width: r * 0.64,
          height: r * 0.22),
      glPaint,
    );

    // 白色同心波纹（右上方向弧）
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    const alphas = [0.95, 0.62, 0.36];
    for (var i = 0; i < 3; i++) {
      wavePaint.strokeWidth = r * (0.085 - i * 0.016);
      wavePaint.color = Colors.white.withValues(alpha: alphas[i]);
      final rr = r * (0.20 + i * 0.21);
      canvas.drawArc(
        Rect.fromCenter(
            center: Offset(cx, cy + r * 0.10),
            width: rr * 2,
            height: rr * 2),
        // 248° 起、扫 124°（与原生 Kotlin 绘制角度一致）
        4.33,
        2.16,
        false,
        wavePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_GlassBallPreviewPainter old) => old.color != color;
}
