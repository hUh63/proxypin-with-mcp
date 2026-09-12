import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/native/mcp_screen.dart';
import 'package:proxypin/native/vpn.dart';
import 'package:proxypin/network/util/mtls.dart';
import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/components/ws_traffic_server.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/storage/path.dart';
import 'package:proxypin/ui/component/widgets.dart';
import 'package:proxypin/ui/component/ws_traffic_port_dialog.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/ui/mobile/setting/config_management.dart';
import 'package:proxypin/ui/mobile/setting/theme.dart';

///设置
///@author wanghongen
class Preference extends StatefulWidget {
  final ProxyServer proxyServer;
  final AppConfiguration appConfiguration;

  const Preference({
    super.key,
    required this.proxyServer,
    required this.appConfiguration,
  });

  @override
  State<StatefulWidget> createState() => _PreferenceState();
}

class _PreferenceState extends State<Preference> {
  late ProxyServer proxyServer;
  late Configuration configuration;
  late AppConfiguration appConfiguration;

  final memoryCleanupController = TextEditingController();
  final memoryCleanupList = [null, 512, 1024, 2048, 4096];

  /// 已拦截的 QUIC 包数（Android VPN 层上报）
  int _quicCount = 0;

  @override
  void initState() {
    super.initState();
    proxyServer = widget.proxyServer;
    configuration = widget.proxyServer.configuration;
    appConfiguration = widget.appConfiguration;

    if (!memoryCleanupList.contains(appConfiguration.memoryCleanupThreshold)) {
      memoryCleanupController.text = appConfiguration.memoryCleanupThreshold
          .toString();
    }
    _loadQuicCount();
  }

  Future<void> _loadQuicCount() async {
    if (!Platform.isAndroid) return;
    try {
      final count = await Vpn.quicBlockedCount();
      if (mounted && count != _quicCount) {
        setState(() => _quicCount = count);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    memoryCleanupController.dispose();
    super.dispose();
  }

  /// 启动页设置区块：开关 / 背景（原启动页·渐变·自定义图片·透明）/ 时长 / 自定义小字
  Widget _buildSplashSection(Color dividerColor) {
    // 展示时长与自定义小字仅在非"原启动页"模式下可编辑
    final splashDetailEditable =
        appConfiguration.splashEnabled && appConfiguration.splashBackground != 'off';
    return Card(
      color: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: [
        ListTile(
          title: const Text('启动页'),
          subtitle: const Text('默认使用系统原生启动页，可切换为自定义品牌页', style: TextStyle(fontSize: 12)),
          trailing: SwitchWidget(
            value: appConfiguration.splashEnabled,
            scale: 0.8,
            onChanged: (value) {
              setState(() => appConfiguration.splashEnabled = value);
              appConfiguration.flushConfig();
            },
          ),
        ),
        // 背景模式始终可见，便于直接切换
        Divider(height: 0, thickness: 0.3, color: dividerColor),
        ListTile(
          title: const Text('背景'),
          trailing: DropdownButton<String>(
            value: appConfiguration.splashBackground,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 'off', child: Text('原启动页（默认）')),
              DropdownMenuItem(value: 'gradient', child: Text('渐变品牌页')),
              DropdownMenuItem(value: 'custom', child: Text('自定义图片')),
              DropdownMenuItem(value: 'transparent', child: Text('跟随主题（推荐）')),
            ],
            onChanged: (v) {
              if (v == null) return;
              if (v == 'custom' && appConfiguration.splashBackgroundPath == null) {
                // 首次切换到自定义图片时立即选图
                _pickSplashBackground();
                return;
              }
              setState(() => appConfiguration.splashBackground = v);
              appConfiguration.flushConfig();
            },
          ),
        ),
        // 展示时长与自定义小字：选原启动页时禁用并说明（系统启动画面不支持注入内容）
        Divider(height: 0, thickness: 0.3, color: dividerColor),
        ListTile(
          title: Text('展示时长',
              style: TextStyle(fontSize: 14, color: splashDetailEditable ? null : Colors.grey)),
          subtitle: Text(
            splashDetailEditable
                ? '${(appConfiguration.splashDurationMs / 1000).toStringAsFixed(2)} 秒'
                : '原启动页为系统画面，不支持自定义时长',
            style: TextStyle(fontSize: 12, color: splashDetailEditable ? null : Colors.grey),
          ),
          trailing: SizedBox(
            width: 150,
            child: Slider(
              value: appConfiguration.splashDurationMs.toDouble(),
              min: 200,
              max: 5000,
              label: '${(appConfiguration.splashDurationMs / 1000).toStringAsFixed(2)}s',
              onChanged: splashDetailEditable
                  ? (v) {
                      setState(() => appConfiguration.splashDurationMs = v.round());
                      appConfiguration.flushConfig();
                    }
                  : null,
            ),
          ),
        ),
        if (splashDetailEditable) ...[
          if (appConfiguration.splashBackground == 'custom') ...[
            Divider(height: 0, thickness: 0.3, color: dividerColor),
            ListTile(
              title: const Text('自定义图片'),
              subtitle: Text(
                appConfiguration.splashBackgroundPath == null ? '未选择' : '已设置，点击更换',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.image_outlined, size: 20),
              onTap: _pickSplashBackground,
            ),
          ],
          Divider(height: 0, thickness: 0.3, color: dividerColor),
          ListTile(
            title: Text('自定义小字',
                style: TextStyle(fontSize: 14, color: splashDetailEditable ? null : Colors.grey)),
            subtitle: Text(
              splashDetailEditable
                  ? (appConfiguration.splashSubtitle?.isNotEmpty == true
                      ? appConfiguration.splashSubtitle!
                      : '默认显示版本信息')
                  : '原启动页不支持自定义小字，切换为渐变/透明后可用',
              style: TextStyle(fontSize: 12, color: splashDetailEditable ? null : Colors.grey),
              maxLines: 2,
            ),
            trailing: Icon(Icons.edit_outlined, size: 18,
                color: splashDetailEditable ? null : Colors.grey),
            onTap: splashDetailEditable ? _editSplashSubtitle : null,
          ),
        ],
      ]),
    );
  }

  /// 选择启动页自定义背景图片，并复制到应用目录持久化
  Future<void> _pickSplashBackground() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      // 复制到应用目录，避免缓存路径失效
      final source = File(file.path!);
      final ext = file.path!.split('.').last.toLowerCase();
      final target = await Paths.getPath('splash_bg.$ext');
      await source.copy(target.path);
      setState(() {
        appConfiguration.splashBackgroundPath = target.path;
        appConfiguration.splashBackground = 'custom';
      });
      appConfiguration.flushConfig();
    } catch (e) {
      logger.e('选择启动页背景失败', error: e);
    }
  }

  /// 编辑启动页自定义小字
  Future<void> _editSplashSubtitle() async {
    final controller = TextEditingController(text: appConfiguration.splashSubtitle ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义小字'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: '副标题文本',
            hintText: '留空恢复默认（显示版本信息）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() => appConfiguration.splashSubtitle = result.isEmpty ? null : result);
    appConfiguration.flushConfig();
  }

  /// mTLS 证书配置弹窗：选择证书链与私钥（PEM），启用后对新连接生效
  Future<bool> _showMtlsDialog() async {
    final chainController = TextEditingController(text: configuration.mtlsChainPath ?? '');
    final keyController = TextEditingController(text: configuration.mtlsKeyPath ?? '');
    var loading = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('双向认证 (mTLS)', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: chainController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: '客户端证书链 (PEM)',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    onPressed: () async {
                      final file = await FilePicker.pickFile(type: FileType.any);
                      if (file?.path != null) {
                        final saved = await Mtls.persist(file!.path!, 'mtls_chain.pem');
                        chainController.text = saved;
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: keyController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: '客户端私钥 (PEM，未加密)',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    onPressed: () async {
                      final file = await FilePicker.pickFile(type: FileType.any);
                      if (file?.path != null) {
                        final saved = await Mtls.persist(file!.path!, 'mtls_key.pem');
                        keyController.text = saved;
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '证书链包含 -----BEGIN CERTIFICATE-----，私钥包含 -----BEGIN PRIVATE KEY-----（不支持加密私钥）。配置后对新建立的 HTTPS 连接生效。',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                final chain = chainController.text.trim();
                final key = keyController.text.trim();
                if (chain.isEmpty || key.isEmpty) {
                  FlutterToastr.show('请先选择证书链与私钥文件', context, backgroundColor: Colors.orange);
                  return;
                }
                if (!Mtls.looksLikePem(chain, 'CERTIFICATE')) {
                  FlutterToastr.show('证书链文件格式不正确（需要 PEM）', context, backgroundColor: Colors.red);
                  return;
                }
                if (!Mtls.looksLikePem(key, 'PRIVATE KEY') && !Mtls.looksLikePem(key, 'EC PRIVATE KEY') &&
                    !Mtls.looksLikePem(key, 'RSA PRIVATE KEY')) {
                  FlutterToastr.show('私钥文件格式不正确（需要未加密 PEM）', context, backgroundColor: Colors.red);
                  return;
                }
                setState(() => loading = true);
                final ok = await Mtls.load(chain, key);
                if (!ok) {
                  setState(() => loading = false);
                  if (context.mounted) {
                    FlutterToastr.show('证书加载失败，请检查文件内容', context, backgroundColor: Colors.red);
                  }
                  return;
                }
                configuration.mtlsChainPath = chain;
                configuration.mtlsKeyPath = key;
                configuration.mtlsEnabled = true;
                configuration.flushConfig();
                if (context.mounted) Navigator.pop(context, true);
              },
              child: loading
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('启用'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() {});
      FlutterToastr.show('mTLS 已启用', context, backgroundColor: Colors.green);
      return true;
    }
    return false;
  }

  @override
  /// 系统级 QUIC 回落（#489 root 能力）：iptables 丢弃全部 UDP:443 强制回落 TCP
  Future<void> _systemQuicFallback(bool enable) async {
    final rootOk = await McpScreen.requestRootAuthorization();
    if (!rootOk) {
      if (mounted) {
        FlutterToastr.show('未获得 Root 授权，无法执行系统级回落', context,
            backgroundColor: Colors.orange);
      }
      return;
    }
    final rule = 'OUTPUT -p udp --dport 443 -j REJECT';
    final cmd = enable ? 'iptables -I $rule' : 'iptables -D $rule';
    final r = await McpScreen.shell(cmd, useSu: true, timeoutMs: 8000);
    final ok = r['success'] == true ||
        (r['code'] is num && (r['code'] as num) == 0);
    if (mounted) {
      FlutterToastr.show(
        ok
            ? (enable ? '系统级回落已启用：UDP:443 将被丢弃（重启系统后失效）' : '系统级回落已停用')
            : '执行失败：${r['stderr'] ?? r['error'] ?? 'iptables 不可用'}',
        context,
        duration: 4,
        backgroundColor: ok ? Colors.green : Colors.red,
      );
    }
  }

  /// 上游 #756：切换 WebSocket 流量推送开关（整行可点，避免只能点很小的开关）
  Future<void> _toggleWsTraffic(bool value) async {
    final localizations = AppLocalizations.of(context)!;
    setState(() => configuration.wsTrafficEnabled = value);
    configuration.flushConfig();
    final ok = await proxyServer.applyWsTraffic();
    if (value && !ok) {
      // 启动失败（多为端口被占用）：回滚开关，避免"开着但没服务"
      setState(() => configuration.wsTrafficEnabled = false);
      configuration.flushConfig();
    }
    if (!mounted) return;
    FlutterToastr.show(
        !value
            ? localizations.wsTrafficStopped
            : ok
                ? localizations.wsTrafficStarted('${configuration.wsTrafficPort}')
                : localizations.wsTrafficStartFailed('${configuration.wsTrafficPort}'),
        context);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    final borderColor = Theme.of(context).dividerColor.withValues(alpha: 0.13);
    final dividerColor = Theme.of(context).dividerColor.withValues(alpha: 0.22);

    Widget section(List<Widget> tiles) => Card(
      color: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: tiles),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          localizations.preference,
          style: const TextStyle(fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          section([
            ListTile(
              title: Text(localizations.language),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _language(context),
            ),
            Divider(height: 0, thickness: 0.3, color: dividerColor),
            MobileThemeSetting(appConfiguration: appConfiguration),
            Divider(height: 0, thickness: 0.3, color: dividerColor),
            ListTile(title: Text(localizations.themeColor)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
              child: themeColor(context),
            ),
            Divider(height: 0, thickness: 0.3, color: dividerColor),
            ListTile(
              title: const Text('莫奈取色'),
              subtitle: const Text(
                'Android 12+ 跟随壁纸配色（主题与启动页自动取色）',
                style: TextStyle(fontSize: 12),
              ),
              trailing: SwitchWidget(
                value: appConfiguration.monetEnabled,
                scale: 0.8,
                onChanged: (value) {
                  setState(() => appConfiguration.monetEnabled = value);
                  appConfiguration.flushConfig();
                  // 触发 MaterialApp 重建，莫奈取色立即生效
                  appConfiguration.globalChange.value = !appConfiguration.globalChange.value;
                },
              ),
            ),
            Divider(height: 0, thickness: 0.3, color: dividerColor),
            ListTile(
              title: const Text('预测性返回'),
              subtitle: const Text(
                'Android 14+ 返回手势预测动画（Material 3 页面转场）',
                style: TextStyle(fontSize: 12),
              ),
              trailing: SwitchWidget(
                value: appConfiguration.predictiveBackEnabled,
                scale: 0.8,
                onChanged: (value) {
                  setState(() => appConfiguration.predictiveBackEnabled = value);
                  appConfiguration.flushConfig();
                  appConfiguration.globalChange.value = !appConfiguration.globalChange.value;
                },
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _buildSplashSection(dividerColor),
          const SizedBox(height: 12),
          section([
            ListTile(
              title: Text(localizations.autoStartup),
              subtitle: Text(
                localizations.autoStartupDescribe,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: SwitchWidget(
                value: proxyServer.configuration.startup,
                scale: 0.8,
                onChanged: (value) {
                  configuration.startup = value;
                  configuration.flushConfig();
                },
              ),
            ),
            if (Platform.isAndroid) ...[
              Divider(height: 0, thickness: 0.3, color: dividerColor),
              ListTile(
                title: const Text('拦截 QUIC (UDP:443)'),
                subtitle: Text(
                  _quicCount > 0
                      ? '已拦截 $_quicCount 个 QUIC 包，强制回落 TCP 使流量可抓包'
                      : '丢弃 UDP 443 强制应用回落 TCP，使 HTTPS 流量可抓包',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: SwitchWidget(
                  value: configuration.blockQuic,
                  scale: 0.8,
                  onChanged: (value) {
                    setState(() => configuration.blockQuic = value);
                    configuration.flushConfig();
                    if (!value) {
                      FlutterToastr.show('已关闭，重新启动抓包后生效', context);
                    }
                  },
                ),
              ),
              // 系统级 QUIC 回落（Root）：iptables 在系统层丢弃 UDP:443，
              // 比 VPN 层拦截更早生效（#489 root 能力）
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '系统级回落（需 Root + iptables）：丢弃全部 UDP:443 强制回落 TCP，重启系统后失效',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _systemQuicFallback(true),
                      icon: const Icon(Icons.power_settings_new, size: 15),
                      label: const Text('启用', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: () => _systemQuicFallback(false),
                      child: const Text('停用', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
              Divider(height: 0, thickness: 0.3, color: dividerColor),
              ListTile(
                title: const Text('双向认证 (mTLS)'),
                subtitle: Text(
                  configuration.mtlsEnabled
                      ? '已启用 · 点击配置客户端证书'
                      : '与上游服务器 TLS 握手时提供客户端证书（PEM）',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: SwitchWidget(
                  value: configuration.mtlsEnabled,
                  scale: 0.8,
                  onChanged: (value) async {
                    if (value) {
                      final ok = await _showMtlsDialog();
                      if (!ok) return;
                    } else {
                      Mtls.unload();
                      setState(() => configuration.mtlsEnabled = false);
                      configuration.flushConfig();
                    }
                  },
                ),
              ),
            ],
            Divider(height: 0, thickness: 0.3, color: dividerColor),
            if (Platform.isAndroid) ...[
              ListTile(
                title: Text(localizations.windowMode),
                subtitle: Text(
                  localizations.windowModeSubTitle,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: SwitchWidget(
                  value: appConfiguration.pipEnabled.value,
                  scale: 0.8,
                  onChanged: (value) {
                    appConfiguration.pipEnabled.value = value;
                    appConfiguration.flushConfig();
                  },
                ),
              ),
              Divider(height: 0, thickness: 0.3, color: dividerColor),
            ],
            ListTile(
              title: Text(localizations.pipIcon),
              subtitle: Text(
                localizations.pipIconDescribe,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: SwitchWidget(
                value: appConfiguration.pipIcon.value,
                scale: 0.8,
                onChanged: (value) {
                  appConfiguration.pipIcon.value = value;
                  appConfiguration.flushConfig();
                },
              ),
            ),
            Divider(height: 0, thickness: 0.3, color: dividerColor),
            ListTile(
              title: Text(localizations.bottomNavigation),
              subtitle: Text(
                localizations.bottomNavigationSubtitle,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: SwitchWidget(
                value: appConfiguration.bottomNavigation,
                scale: 0.8,
                onChanged: (value) {
                  appConfiguration.bottomNavigation = value;
                  appConfiguration.flushConfig();
                },
              ),
            ),
            Divider(height: 0, thickness: 0.3, color: dividerColor),
            ListTile(
              title: Text(localizations.clearConfirm),
              subtitle: Text(
                localizations.clearConfirmSubtitle,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: SwitchWidget(
                value: appConfiguration.clearConfirm,
                scale: 0.8,
                onChanged: (value) {
                  appConfiguration.clearConfirm = value;
                  appConfiguration.flushConfig();
                },
              ),
            ),
          ]),
          const SizedBox(height: 12),
          section([
            ListTile(
              title: Text(localizations.memoryCleanup),
              subtitle: Text(
                localizations.memoryCleanupSubtitle,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: memoryCleanup(context, localizations),
            ),
            Divider(height: 0, thickness: 0.3, color: dividerColor),
            ListTile(
              title: Text(localizations.maxRequestCount),
              subtitle: Text(
                localizations.maxRequestCountSubtitle,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: maxRequestCount(context, localizations),
            ),
          ]),
          const SizedBox(height: 12),
          // WebSocket 实时流量推送（上游 #756）
          section([
            ListTile(
              leading: const Icon(Icons.stream_outlined, color: Colors.teal),
              title: Text(localizations.wsTrafficPush),
              subtitle: Text(
                configuration.wsTrafficEnabled
                    ? (WsTrafficServer.instance.isRunning
                        ? localizations.wsTrafficSubtitleRunning(
                            '${configuration.wsTrafficPort}', '${WsTrafficServer.instance.clientCount}')
                        : localizations.wsTrafficSubtitleNotRunning('${configuration.wsTrafficPort}'))
                    : localizations.wsTrafficSubtitleOff('${configuration.wsTrafficPort}'),
                style: const TextStyle(fontSize: 12),
              ),
              trailing: SwitchWidget(
                value: configuration.wsTrafficEnabled,
                scale: 0.8,
                onChanged: (value) => _toggleWsTraffic(value),
              ),
              onTap: () => _toggleWsTraffic(!configuration.wsTrafficEnabled),
            ),
            if (configuration.wsTrafficEnabled) ...[
              Divider(height: 0, thickness: 0.3, color: dividerColor),
              ListTile(
                title: Text(localizations.wsTrafficHistory),
                subtitle: Text(localizations.wsTrafficHistoryDesc, style: const TextStyle(fontSize: 12)),
                trailing: SwitchWidget(
                  value: configuration.wsTrafficHistoryEnabled,
                  scale: 0.8,
                  onChanged: (value) {
                    setState(() => configuration.wsTrafficHistoryEnabled = value);
                    configuration.flushConfig();
                    WsTrafficServer.instance.broadcastConfig();
                  },
                ),
                onTap: () {
                  setState(() => configuration.wsTrafficHistoryEnabled = !configuration.wsTrafficHistoryEnabled);
                  configuration.flushConfig();
                  WsTrafficServer.instance.broadcastConfig();
                },
              ),
            ],
            // 上游 #756：端口此前只能改配置文件（被占用时开关无法开启），这里提供图形化修改入口
            ListTile(
              title: Text(localizations.wsTrafficPort),
              subtitle: Text(
                configuration.wsTrafficEnabled
                    ? localizations.wsTrafficPortListening('${configuration.wsTrafficPort}')
                    : localizations.wsTrafficPortCurrent('${configuration.wsTrafficPort}'),
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${configuration.wsTrafficPort}',
                    style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.primary)),
                const SizedBox(width: 4),
                Icon(Icons.edit, size: 16, color: Theme.of(context).colorScheme.primary),
              ]),
              onTap: () async {
                final port = await showWsTrafficPortDialog(context, currentPort: configuration.wsTrafficPort);
                if (port == null || port == configuration.wsTrafficPort) return;
                configuration.wsTrafficPort = port;
                configuration.flushConfig();
                if (configuration.wsTrafficEnabled) {
                  final ok = await proxyServer.applyWsTraffic();
                  if (!mounted) return;
                  if (!ok) {
                    setState(() => configuration.wsTrafficEnabled = false);
                    configuration.flushConfig();
                  }
                  FlutterToastr.show(
                      ok
                          ? localizations.wsTrafficPortChangedListening('$port')
                          : localizations.wsTrafficPortChangedFailed('$port'),
                      context);
                } else if (mounted) {
                  FlutterToastr.show(localizations.wsTrafficPortChangedPending('$port'), context);
                }
                if (mounted) setState(() {});
              },
            ),
          ]),
          const SizedBox(height: 12),
          // 配置管理区块
          section([
            ListTile(
              leading: const Icon(Icons.settings_backup_restore, color: Colors.blue),
              title: const Text('配置管理'),
              subtitle: const Text('导入/导出配置，备份或恢复设置'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ConfigManagement(proxyServer: proxyServer),
                  ),
                );
              },
            ),
          ]),
          const SizedBox(height: 15),
        ],
      ),
    );
  }

  Widget themeColor(BuildContext context) {
    return Wrap(
      children: ColorMapping.colors.entries.map((pair) {
        var dividerColor = Theme.of(context).focusColor;
        var background = appConfiguration.themeColor == pair.value
            ? dividerColor
            : Colors.transparent;

        return GestureDetector(
          onTap: () => appConfiguration.setThemeColor = pair.key,
          child: Tooltip(
            message: pair.key,
            child: Container(
              margin: const EdgeInsets.all(4.0),
              decoration: BoxDecoration(
                color: background,
                border: Border.all(color: Colors.transparent, width: 8),
              ),
              child: Dot(color: pair.value, size: 15),
            ),
          ),
        );
      }).toList(),
    );
  }

  //选择语言
  void _language(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          contentPadding: const EdgeInsets.only(left: 5, top: 5),
          actionsPadding: const EdgeInsets.only(bottom: 5, right: 5),
          title: Text(
            localizations.language,
            style: const TextStyle(fontSize: 16),
          ),
          content: Wrap(
            children: [
              TextButton(
                onPressed: () {
                  appConfiguration.language = null;
                  Navigator.of(context).pop();
                },
                child: Text(localizations.followSystem),
              ),
              const Divider(thickness: 0.5, height: 0),
              TextButton(
                onPressed: () {
                  appConfiguration.language = const Locale.fromSubtags(
                    languageCode: 'zh',
                  );
                  Navigator.of(context).pop();
                },
                child: const Text("简体中文"),
              ),
              const Divider(thickness: 0.5, height: 0),
              TextButton(
                onPressed: () {
                  appConfiguration.language = const Locale.fromSubtags(
                    languageCode: 'zh',
                    scriptCode: 'Hant',
                  );
                  Navigator.of(context).pop();
                },
                child: const Text("繁體中文"),
              ),
              const Divider(thickness: 0.5, height: 0),
              TextButton(
                onPressed: () {
                  appConfiguration.language = const Locale.fromSubtags(
                    languageCode: 'vi',
                  );
                  Navigator.of(context).pop();
                },
                child: const Text("Tiếng Việt"),
              ),
              const Divider(thickness: 0.5, height: 0),
              TextButton(
                onPressed: () {
                  appConfiguration.language = const Locale.fromSubtags(
                    languageCode: 'th',
                  );
                  Navigator.of(context).pop();
                },
                child: const Text("ไทย"),
              ),
              const Divider(thickness: 0.5, height: 0),
              TextButton(
                onPressed: () {
                  appConfiguration.language = const Locale.fromSubtags(
                    languageCode: 'es',
                  );
                  Navigator.of(context).pop();
                },
                child: const Text("Español"),
              ),
              const Divider(thickness: 0.5, height: 0),
              TextButton(
                child: const Text("English"),
                onPressed: () {
                  appConfiguration.language = const Locale.fromSubtags(
                    languageCode: 'en',
                  );
                  Navigator.of(context).pop();
                },
              ),
              const Divider(thickness: 0.5),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(localizations.cancel),
            ),
          ],
        );
      },
    );
  }

  bool memoryCleanupOpened = false;

  /// 抓包列表最大保留条数选择
  Widget maxRequestCount(BuildContext context, AppLocalizations localizations) {
    final options = [1000, 5000, 10000, 20000, 0];
    return DropdownButton<int>(
      value: appConfiguration.maxRequestCount,
      onChanged: (val) {
        setState(() {
          appConfiguration.maxRequestCount = val ?? 10000;
        });
        appConfiguration.flushConfig();
      },
      underline: Container(),
      items: [
        for (var option in options)
          DropdownMenuItem(
            value: option,
            child: Text(
              option == 0
                  ? localizations.unlimited
                  : option >= 10000
                  ? '${option ~/ 10000}万'
                  : '$option',
            ),
          ),
      ],
    );
  }

  ///内存清理
  Widget memoryCleanup(BuildContext context, AppLocalizations localizations) {
    try {
      return DropdownButton<int>(
        value: appConfiguration.memoryCleanupThreshold,
        onTap: () => memoryCleanupOpened = true,
        onChanged: (val) {
          memoryCleanupOpened = false;
          setState(() {
            appConfiguration.memoryCleanupThreshold = val;
          });
          appConfiguration.flushConfig();
        },
        underline: Container(),
        items: [
          DropdownMenuItem(value: null, child: Text(localizations.unlimited)),
          const DropdownMenuItem(value: 512, child: Text("512M")),
          const DropdownMenuItem(value: 1024, child: Text("1024M")),
          const DropdownMenuItem(value: 2048, child: Text("2048M")),
          const DropdownMenuItem(value: 4096, child: Text("4096M")),
          DropdownMenuInputItem(
            controller: memoryCleanupController,
            child: Container(
              constraints: BoxConstraints(maxWidth: 65, minWidth: 35),
              child: TextField(
                controller: memoryCleanupController,
                keyboardType: TextInputType.datetime,
                onSubmitted: (value) {
                  setState(() {});
                  appConfiguration.memoryCleanupThreshold = int.tryParse(value);
                  appConfiguration.flushConfig();

                  if (memoryCleanupOpened) {
                    memoryCleanupOpened = false;
                    Navigator.pop(context);
                    return;
                  }
                },
                inputFormatters: [
                  LengthLimitingTextInputFormatter(5),
                  FilteringTextInputFormatter.allow(RegExp("[0-9]")),
                ],
                decoration: InputDecoration(
                  hintText: localizations.custom,
                  suffixText: "M",
                ),
              ),
            ),
          ),
        ],
      );
    } catch (e) {
      appConfiguration.memoryCleanupThreshold = null;
      logger.e(
        'memory button build error',
        error: e,
        stackTrace: StackTrace.current,
      );
      return const SizedBox();
    }
  }
}

class DropdownMenuInputItem extends DropdownMenuItem<int> {
  final TextEditingController controller;

  @override
  int? get value => int.tryParse(controller.text) ?? 0;

  const DropdownMenuInputItem({
    super.key,
    required this.controller,
    required super.child,
  });
}
