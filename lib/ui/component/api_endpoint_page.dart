/*
 * API 端点提取页面 - 自动识别和分组 API 端点
 */

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/api_extractor.dart';
import 'package:proxypin/network/util/logger.dart';

/// API 端点页面
class ApiEndpointPage extends StatefulWidget {
  final List<HttpRequest> requests;
  final List<HttpResponse>? responses;

  const ApiEndpointPage({
    super.key,
    required this.requests,
    this.responses,
  });

  @override
  State<ApiEndpointPage> createState() => _ApiEndpointPageState();
}

class _ApiEndpointPageState extends State<ApiEndpointPage> {
  final ApiExtractor _extractor = ApiExtractor();
  List<ApiEndpoint> _endpoints = [];
  List<ApiEndpointGroup> _groups = [];
  Map<String, dynamic>? _restPatterns;
  bool _isLoading = true;
  String _viewMode = 'group'; // 'group', 'domain', 'method'
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _extractEndpoints();
  }

  void _extractEndpoints() {
    setState(() => _isLoading = true);
    
    Future.delayed(Duration.zero, () {
      final endpoints = _extractor.extract(widget.requests, responses: widget.responses);
      final groups = _extractor.groupByResource(endpoints);
      final patterns = _extractor.identifyRestPatterns(endpoints);
      
      setState(() {
        _endpoints = endpoints;
        _groups = groups;
        _restPatterns = {'patterns': patterns};
        _isLoading = false;
      });
    });
  }

  List<ApiEndpoint> get _filteredEndpoints {
    if (_searchQuery.isEmpty) return _endpoints;
    return _endpoints.where((e) {
      return e.path.contains(_searchQuery) ||
             e.method.contains(_searchQuery) ||
             e.resourceName.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('API 端点 (${_endpoints.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.view_list),
            onPressed: () => _showViewModeSelector(),
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: () => _showExportOptions(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索端点...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),

          // 统计卡片
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                      Icons.link_rounded, '总端点', _endpoints.length.toString(),
                      Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                      Icons.folder_copy_rounded, '资源组', _groups.length.toString(),
                      Theme.of(context).colorScheme.tertiary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                      Icons.alt_route_rounded, '总请求',
                      _endpoints.fold<int>(0, (s, e) => s + e.callCount).toString(),
                      Theme.of(context).colorScheme.secondary),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 内容区域
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _viewMode == 'group'
                    ? _buildGroupView()
                    : _buildListView(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String label, String value, Color accent) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: accent.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Column(
          children: [
            // 图标徽标
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: accent),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: cs.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// 分组视图
  Widget _buildGroupView() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _groups.length,
      itemBuilder: (context, index) {
        final group = _groups[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            leading: CircleAvatar(
              child: Text('${group.endpoints.length}'),
            ),
            title: Text(group.name),
            subtitle: Text('${group.basePath} · ${group.totalCalls} 次请求'),
            trailing: Chip(
              label: Text('${group.avgResponseTime.toStringAsFixed(0)}ms'),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            children: group.endpoints.map((endpoint) {
              return ListTile(
                leading: _getMethodIcon(endpoint.method),
                title: Text(endpoint.path, style: const TextStyle(fontSize: 13)),
                subtitle: Text('${endpoint.callCount} 次 · 成功率 ${endpoint.successRate.toStringAsPercent(0)}'),
                trailing: Text('${endpoint.avgResponseTime.toStringAsFixed(0)}ms'),
                onTap: () => _showEndpointDetail(endpoint),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  /// 列表视图
  Widget _buildListView() {
    final endpoints = _filteredEndpoints;
    
    if (endpoints.isEmpty) {
      return const Center(
        child: Text('没有找到匹配的端点'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: endpoints.length,
      itemBuilder: (context, index) {
        final endpoint = endpoints[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: _getMethodIcon(endpoint.method),
            title: Text(endpoint.path),
            subtitle: Text('${endpoint.domain} · ${endpoint.callCount} 次请求'),
            trailing: Text('${endpoint.avgResponseTime.toStringAsFixed(0)}ms'),
            onTap: () => _showEndpointDetail(endpoint),
          ),
        );
      },
    );
  }

  Widget _getMethodIcon(String method) {
    Color color;
    switch (method) {
      case 'GET': color = Colors.green; break;
      case 'POST': color = Colors.blue; break;
      case 'PUT': color = Colors.orange; break;
      case 'DELETE': color = Colors.red; break;
      case 'PATCH': color = Colors.purple; break;
      default: color = Colors.grey;
    }
    
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        method,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  void _showViewModeSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.view_list),
              title: const Text('分组视图'),
              onTap: () {
                setState(() => _viewMode = 'group');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.list),
              title: const Text('列表视图'),
              onTap: () {
                setState(() => _viewMode = 'list');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.dns),
              title: const Text('按域名分组'),
              onTap: () {
                setState(() => _viewMode = 'domain');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('导出为 OpenAPI'),
              subtitle: const Text('Swagger 格式'),
              onTap: () {
                _exportAsOpenApi();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.post_add),
              title: const Text('导出为 Postman'),
              subtitle: const Text('Collection 格式'),
              onTap: () {
                _exportAsPostman();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('导出为 JSON'),
              onTap: () {
                _exportAsJson();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _exportAsOpenApi() {
    final openApi = _extractor.exportToOpenApi(_endpoints);
    _saveJsonFile('openapi.json', openApi, 'OpenAPI');
  }

  void _exportAsPostman() {
    final postman = _extractor.exportToPostman(_endpoints);
    _saveJsonFile('postman_collection.json', postman, 'Postman');
  }

  void _exportAsJson() {
    final json = _endpoints.map((e) => e.toJson()).toList();
    _saveJsonFile('api_endpoints.json', json, 'JSON');
  }

  /// 将数据保存为 JSON 文件（统一导出入口，带成功/失败反馈）
  Future<void> _saveJsonFile(String fileName, Object data, String label) async {
    try {
      final String content;
      if (data is String) {
        content = data;
      } else {
        content = const JsonEncoder.withIndent('  ').convert(data);
      }
      final Uri? path = await FilePicker.saveFile(fileName: fileName, bytes: utf8.encode(content));
      if (path == null) {
        // 用户取消，无需提示
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label 已导出')));
      }
    } catch (e) {
      logger.e('导出 $label 失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label 导出失败: $e')));
      }
    }
  }

  void _showEndpointDetail(ApiEndpoint endpoint) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${endpoint.method} ${endpoint.path}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('完整 URL', endpoint.fullUrl),
              _buildDetailRow('调用次数', '${endpoint.callCount}'),
              _buildDetailRow('成功率', '${endpoint.successRate.toStringAsPercent(1)}'),
              _buildDetailRow('平均响应时间', '${endpoint.avgResponseTime.toStringAsFixed(0)}ms'),
              _buildDetailRow('首次发现', endpoint.firstSeen.toString()),
              _buildDetailRow('最后访问', endpoint.lastSeen.toString()),
              if (endpoint.tags.isNotEmpty)
                _buildDetailRow('标签', endpoint.tags.join(', ')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}

/// API 端点工具函数
class ApiEndpointUtils {
  static void showEndpoints(BuildContext context, List<HttpRequest> requests, {List<HttpResponse>? responses}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ApiEndpointPage(
          requests: requests,
          responses: responses,
        ),
      ),
    );
  }
}

/// 扩展方法：百分比格式化
extension on double {
  String toStringAsPercent(int decimals) {
    return '${(this * 100).toStringAsFixed(decimals)}%';
  }
}
