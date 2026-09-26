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

  String get floatingBallColorDesc {
    final loc = AppLocalizations.of(context)!;
    final hex = floatingBallColor.toRadixString(16).substring(2).toUpperCase();
    final percent = (floatingBallAlpha / 255 * 100).round();
    return loc.mcpConnFloatingBallColorDesc(hex, percent);
  }

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
    final loc = AppLocalizations.of(context)!;
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
        FlutterToastr.show(loc.mcpConnFloatingBallNeedOverlayPermission,
            context, duration: 4, backgroundColor: Colors.orange);
        return;
      }
      // 启动/停止失败：展示原生返回的具体原因（不再静默无反应）
      if (result is Map && result['success'] == false) {
        final reason =
            (result['error'] ?? loc.mcpConnUnknownReason).toString();
        FlutterToastr.show(
            floatingBallEnabled
                ? loc.mcpConnFloatingBallStartFailed(reason)
                : loc.mcpConnFloatingBallStopFailed(reason),
            context, duration: 4, backgroundColor: Colors.red);
        return;
      }
      // 用户手动开启时给出成功反馈 + 厂商系统拦截的兜底引导
      if (showFeedback && floatingBallEnabled) {
        FlutterToastr.show(loc.mcpConnFloatingBallStartedHint,
            context, duration: 4, backgroundColor: Colors.green);
      }
    } catch (e) {
      logger.w('悬浮球服务调用失败', error: e);
      if (mounted && showFeedback) {
        FlutterToastr.show(loc.mcpConnFloatingBallCallFailed(e.toString()), context,
            duration: 4, backgroundColor: Colors.red);
      }
    }
  }

  /// 悬浮球样式自定义：预置颜色 + 取色器 + 透明度 + 实时预览
  Future<void> _showFloatingBallStyleDialog() async {
    final loc = AppLocalizations.of(context)!;
    var color = Color(floatingBallColor);
    var alpha = floatingBallAlpha;
    final presets = <String, Color>{
      loc.mcpConnPresetM3Purple: const Color(0xFF6750A4),
      loc.mcpConnPresetDeepSeaBlue: const Color(0xFF1565C0),
      loc.mcpConnPresetEmeraldGreen: const Color(0xFF2E7D32),
      loc.mcpConnPresetCoralOrange: const Color(0xFFEF6C00),
      loc.mcpConnPresetRoseRed: const Color(0xFFC2185B),
      loc.mcpConnPresetGraphiteBlack: const Color(0xFF37474F),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(loc.mcpConnCustomFloatingBall, style: const TextStyle(fontSize: 16)),
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
              Text(loc.mcpConnPresetColors, style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
              Text(loc.mcpConnCustomColorRgb, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              _colorSlider('R', color.red, (v) => setDialogState(() => color = Color.fromARGB(255, v, color.green, color.blue))),
              _colorSlider('G', color.green, (v) => setDialogState(() => color = Color.fromARGB(255, color.red, v, color.blue))),
              _colorSlider('B', color.blue, (v) => setDialogState(() => color = Color.fromARGB(255, color.red, color.green, v))),
              const SizedBox(height: 8),
              Text(loc.mcpConnOpacityPercent((alpha / 255 * 100).round()),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Slider(
                value: alpha.toDouble(),
                min: 80,
                max: 255,
                onChanged: (v) => setDialogState(() => alpha = v.round()),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(loc.cancel)),
            ElevatedButton(
              onPressed: () {
                setDialogState(() {});
                Navigator.pop(context, true);
              },
              child: Text(loc.mcpConnConfirm),
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
    final loc = AppLocalizations.of(context)!;
    final c = Configuration.loaded;
    if (c == null) return;
    c.mcpToken = McpServer.generateToken();
    ConfigAutoSave.markChanged();
    try {
      if (McpServer().isRunning) {
        await McpServer().restart();
      }
    } catch (e) {
      _showSnack(loc.mcpConnRegenerateTokenFailed(e.toString()));
    }
    if (mounted) setState(() {});
  }

  /// 各主流 AI 客户端的接入命令（合并自旧版独立设置页）
  Map<String, String> _clientCommands(String endpoint) {
    final loc = AppLocalizations.of(context)!;
    final token = McpServer().token ?? '';
    final host = endpoint.replaceFirst('/mcp', '');
    return {
      'Claude Code': 'claude mcp add ${McpClientNames.mobile} -s user --transport http $endpoint'
          '${token.isEmpty ? '' : ' --header "Authorization: Bearer $token"'}',
      'Codex': 'export PROXYPIN_MCP_TOKEN="$token"\n'
          'codex mcp add ${McpClientNames.mobile} --url $endpoint --bearer-token-env-var PROXYPIN_MCP_TOKEN',
      loc.mcpConnCurlSelfCheck: 'curl -s${token.isEmpty ? '' : ' -H "Authorization: Bearer $token"'} $endpoint '
          '-H "Content-Type: application/json" '
          '-d \'{"jsonrpc":"2.0","id":1,"method":"tools/list"}\'',
      loc.mcpConnOneClickConfigShell: token.isEmpty
          ? loc.mcpConnNeedLanAccessForToken
          : 'curl -s -H "Authorization: Bearer $token" $host/mcp/setup.sh | sh',
      loc.mcpConnOneClickConfigPowershell: token.isEmpty
          ? loc.mcpConnNeedLanAccessForToken
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
    final loc = AppLocalizations.of(context)!;
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
        title: Text(loc.mcpConnSettingsTitle),
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
            tooltip: loc.mcpConnAutomationConfig,
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
                        title: Text(loc.mcpAllowLan),
                        subtitle: Text(loc.mcpConnAllowLanHint,
                            style: const TextStyle(fontSize: 12)),
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
                        title: Text(loc.mcpConnTokenAuth),
                        subtitle: Text(
                          (Configuration.loaded?.mcpAuthEnabled ?? true)
                              ? loc.mcpConnTokenAuthRequired
                              : loc.mcpConnTokenAuthDisabled,
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
                        title: Text(loc.mcpConnKeepAlive),
                        subtitle: Text(
                            loc.mcpConnKeepAliveDesc,
                            style: const TextStyle(fontSize: 12)),
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
                        title: Text(loc.mcpConnStrictValidation),
                        subtitle: Text(loc.mcpConnStrictValidationDesc,
                            style: const TextStyle(fontSize: 12)),
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
                        title: Text(loc.mcpAccessToken),
                        subtitle: Text(
                          McpServer().token ?? loc.mcpConnTokenNotGenerated,
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              tooltip: loc.mcpCopy,
                              onPressed: () {
                                final t = McpServer().token;
                                if (t != null) _copyText(t, loc.mcpConnTokenCopied);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh, size: 18),
                              tooltip: loc.mcpConnRegenerateTokenTooltip,
                              onPressed: _regenerateToken,
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 0),
                      ExpansionTile(
                        leading: const Icon(Icons.terminal),
                        title: Text(loc.mcpConnClientCommands),
                        subtitle: Text(loc.mcpConnClientCommandsSubtitle,
                            style: const TextStyle(fontSize: 12)),
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
                                onPressed: () => _copyText(entry.value, loc.mcpCopied),
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
                        title: Text(loc.mcpService),
                        subtitle: Text(
                          _mcpEnabled
                              ? (isRunning
                                    ? loc.mcpServiceRunning(port.toString())
                                    : (lastError != null
                                          ? loc.mcpServiceError(lastError)
                                          : loc.mcpServiceEnabledNotRunning))
                              : loc.mcpServiceDisabled,
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
                        title: Text(loc.mcpConnAutoStart),
                        subtitle: Text(
                          loc.mcpAutoStartDescribe,
                          style: const TextStyle(fontSize: 12),
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
                            Text(loc.mcpConnServicePort),
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
                              child: Text(loc.securityAiApply),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 连接信息
                Text(loc.mcpConnConnectionInfo, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  loc.mcpConnProtocolVersion(McpServer.protocolVersion),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(loc.mcpConnDeviceIp),
                        subtitle: Text(ip),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: () => _copyText(ip, loc.mcpConnDeviceIpCopied),
                        ),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        title: Text(loc.mcpConnApiUrl),
                        subtitle: Text(apiUrl),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: () => _copyText(apiUrl, loc.mcpConnApiUrlCopied),
                        ),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        title: Text(loc.mcpConnSseUrl),
                        subtitle: Text(sseUrl),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: () => _copyText(sseUrl, loc.mcpConnSseUrlCopied),
                        ),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        title: Text(loc.mcpConnHealthCheck),
                        subtitle: Text(healthUrl),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: () => _copyText(healthUrl, loc.mcpConnHealthCheckUrlCopied),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 悬浮球设置
                Text(loc.mcpConnFloatingBall, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  loc.mcpConnFloatingBallDesc,
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
                        title: Text(loc.mcpConnFloatingBallPermission),
                        subtitle: Text(
                          _overlayPermissionGranted ? loc.mcpConnOverlayGranted : loc.mcpConnOverlayNotGranted,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: _overlayPermissionGranted
                            ? Text(loc.mcpAuthGranted,
                                style: const TextStyle(fontSize: 12, color: Colors.green))
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
                        title: Text(loc.mcpConnEnableFloatingBall),
                        subtitle: Text(
                          _overlayPermissionGranted
                              ? loc.mcpConnFloatingBallEnabledDesc
                              : loc.mcpConnFloatingBallPermissionRequired,
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
                        title: Text(loc.mcpConnAutoDock),
                        subtitle: Text(loc.mcpConnAutoDockDesc,
                            style: const TextStyle(fontSize: 12)),
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
                        title: Text(loc.mcpConnCustomFloatingBallStyle),
                        subtitle: Text(floatingBallColorDesc, style: const TextStyle(fontSize: 12)),
                        trailing: const Icon(Icons.palette_outlined, size: 20),
                        onTap: floatingBallEnabled ? _showFloatingBallStyleDialog : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // AI 配置指南
                Text(loc.mcpConnAiConfigGuide, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(
                          loc.mcpConnAiConfigGuideDesc,
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
                                    _copyText(configJson, loc.mcpConnAiConfigCopied),
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
                Text(loc.mcpConnControlMode, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.settings_applications),
                        title: Text(loc.mcpConnCurrentMode),
                        trailing: Text(
                          switch (mode) {
                            'none' => 'none',
                            'root' => 'Root',
                            'shizuku' => 'Shizuku',
                            'dhizuku' => 'Dhizuku',
                            'accessibility' => loc.mcpConnAccessibility,
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
                        title: Text(loc.mcpConnRootPermission),
                        trailing: Text(
                          hasRoot ? loc.mcpConnAvailable : loc.mcpConnUnavailable,
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
                              ? loc.mcpAuthGranted
                              : (hasShizuku
                                    ? loc.mcpConnNotGranted
                                    : loc.notConnected),
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
                          hasDhizuku ? loc.mcpConnAvailable : loc.mcpConnUnavailable,
                          style: TextStyle(
                            color: hasDhizuku ? Colors.green : Colors.grey,
                          ),
                        ),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        leading: const Icon(Icons.accessibility),
                        title: Text(loc.mcpConnAccessibilityService),
                        trailing: Text(
                          accessibilityEnabled ? loc.mcpConnAvailable : loc.mcpConnNotEnabled,
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
                      label: Text(loc.mcpConnOpenAccessibilitySettings),
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
                      label: Text(
                          shizukuGranted ? loc.mcpConnShizukuGranted : loc.mcpConnRequestShizuku),
                      onPressed: () async {
                        final ok = await McpScreen.requestShizukuAuthorization();
                        if (!mounted) return;
                        FlutterToastr.show(
                          ok
                              ? loc.mcpConnShizukuGranted
                              : loc.mcpConnShizukuAuthIncomplete,
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
                      label: Text(loc.mcpConnRequestRoot),
                      onPressed: () async {
                        final ok = await McpScreen.requestRootAuthorization();
                        if (!mounted) return;
                        FlutterToastr.show(
                          ok ? loc.mcpConnRootGranted : loc.mcpConnRootAuthIncomplete,
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
                      label: Text(loc.mcpConnRequestDhizuku),
                      onPressed: () async {
                        final ok = await McpScreen.requestDhizukuAuthorization();
                        if (!mounted) return;
                        FlutterToastr.show(
                          ok ? loc.mcpConnDhizukuGranted : loc.mcpConnDhizukuAuthIncomplete,
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
                      loc.mcpConnAvailableTools,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      loc.mcpConnToolCount(tools.length),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  loc.mcpConnDisabledToolsHint,
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
                    label: Text(loc.refresh),
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
  static Map<String, String> _notes(AppLocalizations loc) => <String, String>{
    'set_config': loc.mcpConnToolSetConfig,
    'export_har': loc.mcpConnToolExportHar,
    'import_har': loc.mcpConnToolImportHar,
    'search_requests': loc.mcpConnToolSearchRequests,
    'generate_code': loc.mcpConnToolGenerateCode,
    'get_curl': loc.mcpConnToolGetCurl,
    'get_recent_requests': loc.mcpConnToolGetRecentRequests,
    'get_request_details': loc.mcpConnToolGetRequestDetails,
    'start_proxy': loc.mcpConnToolStartProxy,
    'stop_proxy': loc.mcpConnToolStopProxy,
    'get_proxy_status': loc.mcpConnToolGetProxyStatus,
    'clear_requests': loc.mcpConnToolClearRequests,
    'replay_request': loc.mcpConnToolReplayRequest,
    'update_script': loc.mcpConnToolUpdateScript,
    'get_scripts': loc.mcpConnToolGetScripts,
    'get_statistics': loc.mcpConnToolGetStatistics,
    'compare_requests': loc.mcpConnToolCompareRequests,
    'find_similar_requests': loc.mcpConnToolFindSimilarRequests,
    'extract_api_endpoints': loc.mcpConnToolExtractApiEndpoints,
    'find_sensitive_data': loc.mcpConnToolFindSensitiveData,
    'get_cookie_info': loc.mcpConnToolGetCookieInfo,
    'get_domain_summary': loc.mcpConnToolGetDomainSummary,
    'get_pending_intercepts': loc.mcpConnToolGetPendingIntercepts,
    'approve_intercept': loc.mcpConnToolApproveIntercept,
    'reject_intercept': loc.mcpConnToolRejectIntercept,
    'toggle_breakpoint': loc.mcpConnToolToggleBreakpoint,
    'add_weak_network_rule': loc.mcpConnToolAddWeakNetworkRule,
    'add_custom_network_profile': loc.mcpConnToolAddCustomNetworkProfile,
    'list_weak_network_rules': loc.mcpConnToolListWeakNetworkRules,
    'remove_weak_network_rule': loc.mcpConnToolRemoveWeakNetworkRule,
    'toggle_weak_network': loc.mcpConnToolToggleWeakNetwork,
    'list_environments': loc.mcpConnToolListEnvironments,
    'set_environment_variable': loc.mcpConnToolSetEnvironmentVariable,
    'create_environment': loc.mcpConnToolCreateEnvironment,
    'set_active_environment': loc.mcpConnToolSetActiveEnvironment,
    'remove_environment': loc.mcpConnToolRemoveEnvironment,
    'toggle_environment_variables': loc.mcpConnToolToggleEnvironmentVariables,
    'get_device_info': loc.mcpConnToolGetDeviceInfo,
    'get_current_activity': loc.mcpConnToolGetCurrentActivity,
    'dump_ui': loc.mcpConnToolDumpUi,
    'tap_screen': loc.mcpConnToolTapScreen,
    'long_press': loc.mcpConnToolLongPress,
    'swipe_screen': loc.mcpConnToolSwipeScreen,
    'key_event': loc.mcpConnToolKeyEvent,
    'input_text': loc.mcpConnToolInputText,
    'screenshot': loc.mcpConnToolScreenshot,
    'open_accessibility_settings': loc.mcpConnToolOpenAccessibilitySettings,
    'shell': loc.mcpConnToolShell,
  };

  @override
  Widget build(BuildContext context) {
    final name = tool['name'] as String? ?? '';
    final note = _notes(AppLocalizations.of(context)!)[name] ??
        (tool['description'] as String? ?? '');
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
