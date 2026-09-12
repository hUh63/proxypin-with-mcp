/*
 * 请求对比分析页面 - 详细的请求差异对比
 *
 * 修复：此前引用不存在的 Request/Response 类型（故从未被编译、也从未接入），
 * 现改为 HttpRequest / HttpResponse，并接入请求列表（见 RequestCompareUtils.showCompare）。
 */

import 'package:flutter/material.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/request_comparator.dart';

/// 请求对比页面
class RequestComparePage extends StatefulWidget {
  final HttpRequest requestA;
  final HttpRequest requestB;
  final HttpResponse? responseA;
  final HttpResponse? responseB;

  const RequestComparePage({
    super.key,
    required this.requestA,
    required this.requestB,
    this.responseA,
    this.responseB,
  });

  @override
  State<RequestComparePage> createState() => _RequestComparePageState();
}

class _RequestComparePageState extends State<RequestComparePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ComparisonResult _result;
  final RequestComparator _comparator = RequestComparator();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _result = _comparator.compare(
      widget.requestA,
      widget.requestB,
      responseA: widget.responseA,
      responseB: widget.responseB,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('请求对比'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '概览'),
            Tab(text: '请求头'),
            Tab(text: '请求体'),
            Tab(text: '响应'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildHeadersTab(),
          _buildBodyTab(),
          _buildResponseTab(),
        ],
      ),
    );
  }

  /// 概览标签页
  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    _result.hasChanges ? Icons.warning_amber : Icons.check_circle,
                    size: 64,
                    color: _result.hasChanges ? Colors.orange : Colors.green,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _result.hasChanges ? '存在差异' : '完全相同',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: _result.hasChanges ? Colors.orange : Colors.green),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '共 ${_result.totalChanges} 处变化',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildComparisonCard(
            'URL',
            widget.requestA.requestUrl ?? '',
            widget.requestB.requestUrl ?? '',
            changed: _result.urlChanged,
          ),
          const SizedBox(height: 12),
          _buildComparisonCard(
            '方法',
            widget.requestA.method.name,
            widget.requestB.method.name,
            changed: _result.methodChanged,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('变化统计', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _buildStatRow('请求头变化', _result.headerDiffs.length),
                  _buildStatRow('参数变化', _result.queryDiffs.length),
                  _buildStatRow('请求体变化', (_result.bodyDiff?.hasChanged ?? false) ? 1 : 0),
                  if (_result.statusCodeChanged) _buildStatRow('状态码变化', 1),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('详细报告', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SelectableText(
                    _result.detailedReport,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 请求头对比标签页
  Widget _buildHeadersTab() {
    if (_result.headerDiffs.isEmpty) {
      return const Center(child: Text('请求头无变化'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _result.headerDiffs.length,
      itemBuilder: (context, index) {
        final diff = _result.headerDiffs[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: _getChangeTypeIcon(diff.type),
            title: Text(diff.fieldName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (diff.oldValue != null)
                  Text('旧：${diff.oldValue}',
                      style: TextStyle(color: diff.type == CompareType.removed ? Colors.red : null)),
                if (diff.newValue != null)
                  Text('新：${diff.newValue}',
                      style: TextStyle(color: diff.type == CompareType.added ? Colors.green : null)),
              ],
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  /// 请求体对比标签页
  Widget _buildBodyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_result.bodyDiff == null || !_result.bodyDiff!.hasChanged)
            const Center(child: Text('请求体无变化'))
          else
            _buildCodeDiff(
              '请求体 A',
              widget.requestA.bodyAsString,
              '请求体 B',
              widget.requestB.bodyAsString,
            ),
        ],
      ),
    );
  }

  /// 响应标签页
  Widget _buildResponseTab() {
    if (widget.responseA == null && widget.responseB == null) {
      return const Center(child: Text('无响应数据'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.responseA != null && widget.responseB != null)
            _buildComparisonCard(
              '状态码',
              '${widget.responseA!.status.code}',
              '${widget.responseB!.status.code}',
              changed: _result.statusCodeChanged,
            ),
          const SizedBox(height: 16),
          Text('响应头变化 (${_result.responseHeaderDiffs.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_result.responseHeaderDiffs.isEmpty)
            const Text('无变化')
          else
            ..._result.responseHeaderDiffs.map((diff) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      _getChangeTypeIcon(diff.type, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${diff.fieldName}: ${diff.oldValue ?? ''} → ${diff.newValue ?? ''}'),
                      ),
                    ],
                  ),
                )),
          const SizedBox(height: 16),
          if ((_result.responseBodyDiff?.hasChanged ?? false))
            _buildCodeDiff(
              '响应体 A',
              widget.responseA?.bodyAsString ?? '',
              '响应体 B',
              widget.responseB?.bodyAsString ?? '',
            ),
        ],
      ),
    );
  }

  Widget _buildComparisonCard(String label, String valueA, String valueB, {required bool changed}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (changed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('已修改', style: TextStyle(color: Colors.orange[800], fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildValuePanel('A', valueA)),
                const SizedBox(width: 16),
                Icon(Icons.arrow_forward, size: 16, color: Theme.of(context).colorScheme.outline),
                const SizedBox(width: 16),
                Expanded(child: _buildValuePanel('B', valueB)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildValuePanel(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('请求 $label', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 4),
        SelectableText(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ],
    );
  }

  Widget _buildCodeDiff(String labelA, String codeA, String labelB, String codeB) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildCodePanel(labelA, codeA)),
        const SizedBox(width: 8),
        Expanded(child: _buildCodePanel(labelB, codeB)),
      ],
    );
  }

  Widget _buildCodePanel(String label, String code) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[850],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: SelectableText(
              code.isEmpty ? '(空)' : code,
              style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text('$count', style: TextStyle(fontWeight: FontWeight.bold, color: count > 0 ? Colors.orange : null)),
        ],
      ),
    );
  }

  Widget _getChangeTypeIcon(CompareType type, {double size = 24}) {
    switch (type) {
      case CompareType.added:
        return Icon(Icons.add_circle, color: Colors.green, size: size);
      case CompareType.removed:
        return Icon(Icons.remove_circle, color: Colors.red, size: size);
      case CompareType.modified:
        return Icon(Icons.edit, color: Colors.orange, size: size);
      case CompareType.unchanged:
        return Icon(Icons.check_circle, color: Colors.grey, size: size);
    }
  }
}

/// 对比工具函数
class RequestCompareUtils {
  static void showCompare(
    BuildContext context,
    HttpRequest requestA,
    HttpRequest requestB, {
    HttpResponse? responseA,
    HttpResponse? responseB,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RequestComparePage(
          requestA: requestA,
          requestB: requestB,
          responseA: responseA,
          responseB: responseB,
        ),
      ),
    );
  }
}
