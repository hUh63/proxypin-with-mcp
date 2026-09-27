import 'package:flutter/material.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/http/connection_pool.dart';
import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/platform.dart';

/// 性能监控仪表盘 - 显示连接池与请求性能统计
///
/// 桌面通过子窗口打开时为独立 isolate，`ConnectionPool` 单例与主窗口不共享，
/// 故通过 IPC `getPerformanceStats` 拉取主窗口真实统计；移动端直接读本地单例。
class PerformanceDashboard extends StatefulWidget {
  const PerformanceDashboard({super.key});

  @override
  State<PerformanceDashboard> createState() => _PerformanceDashboardState();
}

class _PerformanceDashboardState extends State<PerformanceDashboard> {
  bool _isRefreshing = false;
  DateTime _lastUpdateTime = DateTime.now();
  Map<String, dynamic>? _stats;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _loadStats();
        _startAutoRefresh();
      }
    });
  }

  Future<void> _loadStats() async {
    try {
      Map<String, dynamic> stats;
      if (Platforms.isDesktop()) {
        // 桌面子窗口：从主窗口拉取连接池统计 + 代理状态
        final res = await DesktopMultiWindow.invokeMainWindowMethod('getPerformanceStats');
        stats = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      } else {
        // 移动端：主进程内直接读单例
        stats = ConnectionPool.instance.getStats();
        stats['proxyRunning'] = ProxyServer.current?.isRunning == true;
        stats['proxyPort'] = ProxyServer.current?.port ?? 0;
      }
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _errorMessage = null;
        _lastUpdateTime = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.perfLoadFailed(e.toString());
        _lastUpdateTime = DateTime.now();
      });
    }
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    await _loadStats();
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _isRefreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.perfTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isRefreshing ? null : _refresh,
            ),
          ],
        ),
        body: _errorMessage != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text(_errorMessage!, style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: Text(AppLocalizations.of(context)!.perfRetry),
                    ),
                  ],
                ),
              )
            : _stats == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(AppLocalizations.of(context)!.perfLoading),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildLastUpdateTime(),
                        const SizedBox(height: 16),
                        _buildProxyStatus(),
                        const SizedBox(height: 16),
                        _buildPerformanceOverview(),
                        const SizedBox(height: 16),
                        _buildConnectionPoolStatus(),
                        const SizedBox(height: 16),
                        _buildPerformanceMetrics(),
                        const SizedBox(height: 16),
                        _buildRequestStats(),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildLastUpdateTime() {
    final time = '${_lastUpdateTime.hour.toString().padLeft(2, '0')}:'
        '${_lastUpdateTime.minute.toString().padLeft(2, '0')}:'
        '${_lastUpdateTime.second.toString().padLeft(2, '0')}';
    return Text(
      AppLocalizations.of(context)!.perfLastUpdate(time),
      style: TextStyle(color: Colors.grey[600], fontSize: 12),
    );
  }

  /// 代理运行状态卡片
  Widget _buildProxyStatus() {
    final running = _stats?['proxyRunning'] == true;
    final port = _stats?['proxyPort'] ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.router, color: running ? Colors.green[700] : Colors.grey),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context)!.perfProxyStatus, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: running ? Colors.green[700] : Colors.grey)),
              const Spacer(),
              Icon(Icons.circle, size: 10, color: running ? Colors.green : Colors.grey),
              const SizedBox(width: 4),
              Text(running ? AppLocalizations.of(context)!.perfRunning : AppLocalizations.of(context)!.perfStopped, style: TextStyle(color: running ? Colors.green : Colors.grey)),
            ]),
            const SizedBox(height: 12),
            _buildMetricRow(AppLocalizations.of(context)!.diagListeningPort, '$port'),
          ],
        ),
      ),
    );
  }

  /// 性能概览卡片
  Widget _buildPerformanceOverview() {
    final stats = _stats ?? const <String, dynamic>{};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.speed, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context)!.perfOverview, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue[700])),
            ]),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(AppLocalizations.of(context)!.perfTotalRequests, '${stats['totalRequests'] ?? 0}', Colors.blue),
                _buildStatItem(AppLocalizations.of(context)!.success, '${stats['successfulRequests'] ?? 0}', Colors.green),
                _buildStatItem(AppLocalizations.of(context)!.fail, '${stats['failedRequests'] ?? 0}', Colors.red),
                _buildStatItem(AppLocalizations.of(context)!.successRate, '${((stats['successRate'] ?? 0.0) as num).toStringAsFixed(1)}%', Colors.orange),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 连接池状态卡片
  Widget _buildConnectionPoolStatus() {
    final stats = _stats ?? const <String, dynamic>{};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.swap_horiz, color: Colors.teal[700]),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context)!.perfConnectionPool, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal[700])),
            ]),
            const SizedBox(height: 16),
            _buildMetricRow(AppLocalizations.of(context)!.perfActiveConnections, '${stats['activeConnections'] ?? 0}'),
            const Divider(height: 24),
            _buildMetricRow(AppLocalizations.of(context)!.perfIdleConnections, '${stats['idleConnections'] ?? 0}'),
            const Divider(height: 24),
            _buildMetricRow(AppLocalizations.of(context)!.retryCountLabel, '${stats['retryCount'] ?? 0}'),
          ],
        ),
      ),
    );
  }

  /// 性能指标卡片
  Widget _buildPerformanceMetrics() {
    final stats = _stats ?? const <String, dynamic>{};
    final avgMs = (stats['avgResponseTimeMs'] as num?) ?? 0;
    final qps = (stats['qps'] as num?) ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.analytics, color: Colors.purple[700]),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context)!.perfMetrics, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple[700])),
            ]),
            const SizedBox(height: 16),
            _buildMetricRow(AppLocalizations.of(context)!.perfAvgResponseTime, '${avgMs.toStringAsFixed(0)}ms'),
            const Divider(height: 24),
            _buildMetricRow(AppLocalizations.of(context)!.perfQps, qps.toStringAsFixed(1)),
          ],
        ),
      ),
    );
  }

  /// 请求统计卡片
  Widget _buildRequestStats() {
    final stats = _stats ?? const <String, dynamic>{};
    final breakdown = stats['requestBreakdown'] as Map<String, dynamic>? ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.list_alt, color: Colors.indigo[700]),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context)!.perfRequestStats, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo[700])),
            ]),
            const SizedBox(height: 16),
            if (breakdown.isNotEmpty) ...[
              ...breakdown.entries.map((entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(entry.key, style: TextStyle(color: Colors.grey[700])),
                        Text('${entry.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )),
            ] else ...[
              Center(
                  child: Text(AppLocalizations.of(context)!.perfNoBreakdown,
                      style: TextStyle(color: Colors.grey[400]))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, MaterialColor color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color[700])),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[700])),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }
}
