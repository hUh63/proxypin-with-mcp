/*
 * 日志管理页面 - 查看和管理应用日志
 * 支持过滤、搜索、导出、清除
 */

import 'package:flutter/material.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:proxypin/l10n/app_localizations.dart';

/// 日志级别
enum LogLevel { debug, info, warning, error }

/// 日志条目
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.stackTrace,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'level': level.name,
        'tag': tag,
        'message': message,
        'stackTrace': stackTrace,
      };
}

/// 日志管理器
class LogManager {
  static final LogManager _instance = LogManager._internal();
  factory LogManager() => _instance;
  LogManager._internal();

  final List<LogEntry> _logs = [];
  final int _maxLogs = 500;
  bool _isRecording = true;

  /// 添加日志
  void addLog(LogLevel level, String tag, String message, {String? stackTrace}) {
    if (!_isRecording) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      stackTrace: stackTrace,
    );

    _logs.insert(0, entry);

    // 限制日志数量
    if (_logs.length > _maxLogs) {
      _logs.removeLast();
    }
  }

  /// 调试日志
  void d(String tag, String message) => addLog(LogLevel.debug, tag, message);

  /// 信息日志
  void i(String tag, String message) => addLog(LogLevel.info, tag, message);

  /// 警告日志
  void w(String tag, String message) => addLog(LogLevel.warning, tag, message);

  /// 错误日志
  void e(String tag, String message, {Object? error, StackTrace? stackTrace}) {
    addLog(
      LogLevel.error,
      tag,
      message,
      stackTrace: error != null ? '$error\n$stackTrace' : null,
    );
  }

  /// 获取所有日志
  List<LogEntry> getLogs() => List.unmodifiable(_logs);

  /// 按级别过滤日志
  List<LogEntry> getLogsByLevel(LogLevel level) {
    return _logs.where((log) => log.level == level).toList();
  }

  /// 按标签过滤日志
  List<LogEntry> getLogsByTag(String tag) {
    return _logs.where((log) => log.tag.contains(tag)).toList();
  }

  /// 搜索日志
  List<LogEntry> searchLogs(String query) {
    final lowerQuery = query.toLowerCase();
    return _logs.where((log) {
      return log.message.toLowerCase().contains(lowerQuery) ||
          log.tag.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// 清除日志
  void clear() {
    _logs.clear();
  }

  /// 导出日志到文件
  Future<String> exportLogs() async {
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toString().replaceAll(RegExp(r'[:.]'), '-');
    final filePath = '${directory.path}/proxypin_logs_$timestamp.txt';

    final file = File(filePath);
    final buffer = StringBuffer();

    buffer.writeln('ProxyPin Logs');
    buffer.writeln('Exported at: ${DateTime.now()}');
    buffer.writeln('Total logs: ${_logs.length}');
    buffer.writeln('=' * 60);
    buffer.writeln();

    for (final log in _logs) {
      buffer.writeln('[${log.timestamp}] ${log.level.name.toUpperCase()} ${log.tag}: ${log.message}');
      if (log.stackTrace != null) {
        buffer.writeln(log.stackTrace);
      }
      buffer.writeln();
    }

    await file.writeAsString(buffer.toString());
    return filePath;
  }

  /// 开始记录
  bool get isRecording => _isRecording;

  void startRecording() => _isRecording = true;

  /// 停止记录
  void stopRecording() => _isRecording = false;
}

/// 日志管理页面
class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  final LogManager _logManager = LogManager();
  List<LogEntry> _filteredLogs = [];
  LogLevel? _selectedLevel;
  String _searchQuery = '';
  bool _autoScroll = true;
  Timer? _refreshTimer;
  final ScrollController _listController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 保底提示：确保页面有数据可看（运行日志由 logger 桥接持续写入）
    if (LogManager().getLogs().isEmpty) {
      // 保底提示要在首帧之后才能取 l10n（initState 里禁止访问 Localizations）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          LogManager().i('system', localizations.logViewReadyHint);
        }
      });
    }
    _refreshLogs();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _listController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    // 实时刷新：500ms 轮询，新日志即时上屏
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        _refreshLogs();
      }
    });
  }

  void _refreshLogs() {
    var logs = _logManager.getLogs();

    // 按级别过滤
    if (_selectedLevel != null) {
      logs = logs.where((log) => log.level == _selectedLevel).toList();
    }

    // 按搜索词过滤
    if (_searchQuery.isNotEmpty) {
      logs = _logManager.searchLogs(_searchQuery);
    }

    // 内容无变化（筛选条件相同且条数/首条一致）时跳过重建，避免 500ms 空转
    final filterKey = '${_selectedLevel?.name ?? 'all'}|$_searchQuery';
    if (filterKey == _lastFilterKey &&
        logs.isNotEmpty &&
        _filteredLogs.length == logs.length &&
        _filteredLogs.first.timestamp == logs.first.timestamp) {
      return;
    }
    _lastFilterKey = filterKey;

    setState(() {
      _filteredLogs = logs;
    });
    // 新日志到达：停留在列表顶部附近时自动回顶，让最新日志立即可见
    if (_filteredLogs.isNotEmpty) {
      final topId = _filteredLogs.first.timestamp.microsecondsSinceEpoch;
      if (_lastTopId != topId) {
        _lastTopId = topId;
        if (_listController.hasClients && _listController.offset < 400) {
          _listController.jumpTo(0);
        }
      }
    }
  }

  int _lastTopId = -1;
  String _lastFilterKey = '';

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }

  IconData _getLevelIcon(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Icons.bug_report;
      case LogLevel.info:
        return Icons.info;
      case LogLevel.warning:
        return Icons.warning;
      case LogLevel.error:
        return Icons.error;
    }
  }

  Future<void> _exportLogs() async {
    try {
      final filePath = await _logManager.exportLogs();
      final result = await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'ProxyPin Logs',
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.status == ShareResultStatus.success
                ? localizations.logViewExportSuccess
                : localizations.logViewExportFailed),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.logViewExportError('$e'))),
        );
      }
    }
  }

  void _clearLogs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.logViewClearLogs),
        content: Text(localizations.logViewClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () {
              _logManager.clear();
              _refreshLogs();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(localizations.logViewCleared)),
              );
            },
            child: Text(localizations.confirm, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.logViewTitle,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          // 录制开关（开启后开始记录新日志）
          IconButton(
            icon: Icon(
              _logManager.isRecording ? Icons.fiber_manual_record : Icons.pause_circle_outline,
              size: 20,
              color: _logManager.isRecording ? Colors.red : Colors.grey,
            ),
            tooltip: _logManager.isRecording
                ? localizations.logViewTapToPause
                : localizations.logViewTapToResume,
            onPressed: () {
              setState(() {
                _logManager.isRecording ? _logManager.stopRecording() : _logManager.startRecording();
              });
              FlutterToastr.show(
                _logManager.isRecording
                    ? localizations.logViewRecordingResumed
                    : localizations.logViewRecordingPaused,
                context,
              );
            },
          ),
          // 搜索 / 导出 / 清除 收进菜单，避免标题被挤压截断
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: localizations.logViewMore,
            onSelected: (value) {
              switch (value) {
                case 'search':
                  showSearch(
                    context: context,
                    delegate: LogSearchDelegate(_logManager),
                  ).then((_) => _refreshLogs());
                case 'export':
                  _exportLogs();
                case 'clear':
                  _clearLogs();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                  value: 'search', child: Text(localizations.logViewSearchLogs)),
              PopupMenuItem(
                  value: 'export', child: Text(localizations.logViewExportLogs)),
              PopupMenuItem(
                  value: 'clear', child: Text(localizations.logViewClearLogs)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 级别过滤
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: Text(localizations.all),
                    selected: _selectedLevel == null,
                    onSelected: (selected) {
                      setState(() => _selectedLevel = null);
                      _refreshLogs();
                    },
                  ),
                  const SizedBox(width: 8),
                  ...LogLevel.values.map((level) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(level.name.toUpperCase()),
                      selected: _selectedLevel == level,
                      avatar: Icon(
                        _getLevelIcon(level),
                        size: 18,
                        color: _getLevelColor(level),
                      ),
                      onSelected: (selected) {
                        setState(() => _selectedLevel = selected ? level : null);
                        _refreshLogs();
                      },
                    ),
                  )),
                ],
              ),
            ),
          ),
          
          const Divider(height: 1),
          
          // 日志列表
          Expanded(
            child: _filteredLogs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inbox, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          localizations.logViewNoLogs,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _listController,
                    itemCount: _filteredLogs.length,
                    itemBuilder: (context, index) {
                      final log = _filteredLogs[index];
                      return ListTile(
                        leading: Icon(
                          _getLevelIcon(log.level),
                          color: _getLevelColor(log.level),
                        ),
                        title: Text(
                          log.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${log.tag} • ${_formatTime(log.timestamp)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        trailing: log.stackTrace != null
                            ? const Icon(Icons.bug_report_outlined, size: 20)
                            : null,
                        onTap: () => _showLogDetail(log),
                      );
                    },
                  ),
          ),
          
          // 底部统计（背景随主题，数字按级别配色）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              border: Border(
                  top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(localizations.logViewStatTotal, _logManager.getLogs().length,
                    Theme.of(context).colorScheme.primary),
                _buildStatItem(localizations.logViewStatDebug, _logManager.getLogsByLevel(LogLevel.debug).length,
                    _getLevelColor(LogLevel.debug)),
                _buildStatItem(localizations.logViewStatInfo, _logManager.getLogsByLevel(LogLevel.info).length,
                    _getLevelColor(LogLevel.info)),
                _buildStatItem(localizations.logViewStatWarning, _logManager.getLogsByLevel(LogLevel.warning).length,
                    _getLevelColor(LogLevel.warning)),
                _buildStatItem(localizations.logViewStatError, _logManager.getLogsByLevel(LogLevel.error).length,
                    _getLevelColor(LogLevel.error)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  void _showLogDetail(LogEntry log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(_getLevelIcon(log.level), color: _getLevelColor(log.level)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(log.level.name.toUpperCase()),
            ),
          ],
        ),
        content: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow(localizations.logViewTime, _formatTime(log.timestamp, full: true)),
              _buildDetailRow(localizations.logViewTag, log.tag),
              const SizedBox(height: 16),
              Text(localizations.logViewMessage, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SelectableText(log.message),
              if (log.stackTrace != null) ...[
                const SizedBox(height: 16),
                Text(localizations.logViewStack, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    log.stackTrace!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.close),
          ),
          TextButton(
            onPressed: () {
              // 复制日志内容
              // 这里可以添加复制功能
              Navigator.pop(context);
            },
            child: Text(localizations.copy),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  String _formatTime(DateTime time, {bool full = false}) {
    if (full) {
      return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    }
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}

/// 日志搜索代理
class LogSearchDelegate extends SearchDelegate<String> {
  final LogManager logManager;

  LogSearchDelegate(this.logManager);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
          showResults(context);
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final results = logManager.searchLogs(query);
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final log = results[index];
        return ListTile(
          leading: Icon(
            _getLevelIcon(log.level),
            color: _getLevelColor(log.level),
          ),
          title: Text(log.message),
          subtitle: Text('${log.tag} • ${log.timestamp}'),
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final suggestions = query.isEmpty
        ? <LogEntry>[]
        : logManager.searchLogs(query).take(10).toList();
    
    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final log = suggestions[index];
        return ListTile(
          leading: Icon(
            _getLevelIcon(log.level),
            color: _getLevelColor(log.level),
          ),
          title: Text(log.message),
          subtitle: Text(log.tag),
          onTap: () {
            query = log.message;
            showResults(context);
          },
        );
      },
    );
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }

  IconData _getLevelIcon(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Icons.bug_report;
      case LogLevel.info:
        return Icons.info;
      case LogLevel.warning:
        return Icons.warning;
      case LogLevel.error:
        return Icons.error;
    }
  }
}
