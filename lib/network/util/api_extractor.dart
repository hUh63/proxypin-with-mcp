/*
 * API 端点提取器 - 自动识别和分组 API 端点
 * 功能：从请求历史中提取 API 端点，按资源分组，统计使用频率
 */

import 'dart:convert';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/http.dart';

/// API 端点信息
class ApiEndpoint {
  final String path;
  final String method;
  final String domain;
  final String basePath;
  final int callCount;
  final double avgResponseTime;
  final int successCount;
  final int errorCount;
  final List<String> tags;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final Map<String, dynamic> sampleRequest;
  final Map<String, dynamic> sampleResponse;

  ApiEndpoint({
    required this.path,
    required this.method,
    required this.domain,
    required this.basePath,
    required this.callCount,
    this.avgResponseTime = 0,
    this.successCount = 0,
    this.errorCount = 0,
    this.tags = const [],
    required this.firstSeen,
    required this.lastSeen,
    this.sampleRequest = const {},
    this.sampleResponse = const {},
  });

  /// 完整 URL
  String get fullUrl => 'https://$domain$path';

  /// 端点分组键（用于分组显示）
  String get groupKey {
    // 提取资源路径，如 /api/users/123 → /api/users
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length <= 2) return path;
    
    // 移除 ID 部分（数字或 UUID）
    final normalized = segments.map((s) {
      if (RegExp(r'^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$').hasMatch(s)) return '{id}';
      if (RegExp(r'^\d+$').hasMatch(s)) return '{id}';
      return s;
    }).toList();
    
    return '/${normalized.join('/')}';
  }

  /// 资源名称（从路径提取）
  String get resourceName {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return 'root';
    
    // 找到最后一个非 ID 段
    for (var i = segments.length - 1; i >= 0; i--) {
      final segment = segments[i];
      if (!RegExp(r'^[\d]+$').hasMatch(segment)) {
        return segment;
      }
    }
    return segments.first;
  }

  /// 成功率
  double get successRate => callCount > 0 ? successCount / callCount : 0;

  /// 转换为 JSON
  Map<String, dynamic> toJson() => {
    'path': path,
    'method': method,
    'domain': domain,
    'basePath': basePath,
    'callCount': callCount,
    'avgResponseTime': avgResponseTime,
    'successCount': successCount,
    'errorCount': errorCount,
    'tags': tags,
    'firstSeen': firstSeen.toIso8601String(),
    'lastSeen': lastSeen.toIso8601String(),
    'groupKey': groupKey,
    'resourceName': resourceName,
    'successRate': successRate,
  };
}

/// API 端点分组
class ApiEndpointGroup {
  final String name;
  final String basePath;
  final List<ApiEndpoint> endpoints;
  final int totalCalls;
  final double avgResponseTime;

  ApiEndpointGroup({
    required this.name,
    required this.basePath,
    required this.endpoints,
    required this.totalCalls,
    required this.avgResponseTime,
  });

  int get endpointCount => endpoints.length;

  Map<String, dynamic> toJson() => {
    'name': name,
    'basePath': basePath,
    'endpointCount': endpointCount,
    'totalCalls': totalCalls,
    'avgResponseTime': avgResponseTime,
    'endpoints': endpoints.map((e) => e.toJson()).toList(),
  };
}

/// API 端点提取器
class ApiExtractor {
  final Map<String, _EndpointStats> _stats = {};

  /// 从请求列表提取 API 端点
  List<ApiEndpoint> extract(List<HttpRequest> requests, {List<HttpResponse>? responses}) {
    _stats.clear();

    for (var i = 0; i < requests.length; i++) {
      final request = requests[i];
      final response = responses != null && i < responses.length ? responses[i] : null;
      _processRequest(request, response);
    }

    return _stats.values.map((s) => s.toEndpoint()).toList()
      ..sort((a, b) => b.callCount.compareTo(a.callCount));
  }

  /// 按资源分组
  List<ApiEndpointGroup> groupByResource(List<ApiEndpoint> endpoints) {
    final groups = <String, List<ApiEndpoint>>{};

    for (var endpoint in endpoints) {
      final groupKey = endpoint.groupKey;
      groups.putIfAbsent(groupKey, () => []).add(endpoint);
    }

    return groups.entries.map((e) {
      final totalCalls = e.value.fold(0, (sum, ep) => sum + ep.callCount);
      final avgTime = e.value.isEmpty ? 0 : e.value.map((ep) => ep.avgResponseTime).reduce((a, b) => a + b) / e.value.length;
      return ApiEndpointGroup(
        name: e.value.first.resourceName,
        basePath: e.key,
        endpoints: e.value,
        totalCalls: totalCalls,
        avgResponseTime: avgTime.toDouble(),
      );
    }).toList()
      ..sort((a, b) => b.totalCalls.compareTo(a.totalCalls));
  }

  /// 按域分组
  Map<String, List<ApiEndpoint>> groupByDomain(List<ApiEndpoint> endpoints) {
    final groups = <String, List<ApiEndpoint>>{};
    for (var endpoint in endpoints) {
      groups.putIfAbsent(endpoint.domain, () => []).add(endpoint);
    }
    return groups;
  }

  /// 按方法分组
  Map<String, List<ApiEndpoint>> groupByMethod(List<ApiEndpoint> endpoints) {
    final groups = <String, List<ApiEndpoint>>{};
    for (var endpoint in endpoints) {
      groups.putIfAbsent(endpoint.method, () => []).add(endpoint);
    }
    return groups;
  }

  /// 识别 RESTful 模式
  List<Map<String, dynamic>> identifyRestPatterns(List<ApiEndpoint> endpoints, AppLocalizations loc) {
    final patterns = <Map<String, dynamic>>[];
    final resourceGroups = groupByResource(endpoints);

    for (var group in resourceGroups) {
      final methods = group.endpoints.map((e) => e.method).toSet();
      final hasGet = methods.contains('GET');
      final hasPost = methods.contains('POST');
      final hasPut = methods.contains('PUT');
      final hasDelete = methods.contains('DELETE');

      String patternType;
      if (hasGet && hasPost && hasPut && hasDelete) {
        patternType = loc.apiExtractFullCrud;
      } else if (hasGet && hasPost) {
        patternType = loc.apiExtractReadWrite;
      } else if (hasGet) {
        patternType = loc.apiExtractReadOnly;
      } else {
        patternType = loc.apiExtractCustom;
      }

      patterns.add({
        'resource': group.name,
        'basePath': group.basePath,
        'patternType': patternType,
        'methods': methods.toList(),
        'endpointCount': group.endpointCount,
        'totalCalls': group.totalCalls,
        'completeness': _calculateCompleteness(methods),
      });
    }

    return patterns..sort((a, b) => (b['totalCalls'] as int).compareTo(a['totalCalls'] as int));
  }

  double _calculateCompleteness(Set<String> methods) {
    int score = 0;
    if (methods.contains('GET')) score++;
    if (methods.contains('POST')) score++;
    if (methods.contains('PUT') || methods.contains('PATCH')) score++;
    if (methods.contains('DELETE')) score++;
    return score / 4;
  }

  /// 提取路径参数
  List<Map<String, dynamic>> extractPathParameters(List<ApiEndpoint> endpoints) {
    final params = <Map<String, dynamic>>[];
    final paramPattern = RegExp(r'\{([^}]+)\}');

    for (var endpoint in endpoints) {
      final matches = paramPattern.allMatches(endpoint.path);
      for (var match in matches) {
        params.add({
          'endpoint': endpoint.path,
          'method': endpoint.method,
          'parameter': match.group(1),
          'position': match.start,
        });
      }
    }

    return params;
  }

  /// 导出为 OpenAPI/Swagger 格式
  Map<String, dynamic> exportToOpenApi(List<ApiEndpoint> endpoints, AppLocalizations loc,
      {String title = 'ProxyPin API', String version = '1.0.0'}) {
    final paths = <String, Map<String, dynamic>>{};

    for (var endpoint in endpoints) {
      final pathKey = endpoint.groupKey;
      final methodKey = endpoint.method.toLowerCase();

      paths.putIfAbsent(pathKey, () => {});
      paths[pathKey]![methodKey] = {
        'summary': '${endpoint.method} ${endpoint.path}',
        'operationId': '${methodKey}_${endpoint.resourceName}',
        'responses': {
          '200': {'description': 'Successful response'},
        },
      };
    }

    return {
      'openapi': '3.0.0',
      'info': {
        'title': title,
        'version': version,
        'description': loc.apiExtractDocDesc,
      },
      'servers': [
        {'url': 'https://api.example.com'},
      ],
      'paths': paths,
    };
  }

  /// 导出为 Postman Collection 格式
  Map<String, dynamic> exportToPostman(List<ApiEndpoint> endpoints, {String collectionName = 'ProxyPin Collection'}) {
    final items = endpoints.map((endpoint) => {
      'name': '${endpoint.method} ${endpoint.path}',
      'request': {
        'method': endpoint.method,
        'url': {
          'raw': endpoint.fullUrl,
          'protocol': 'https',
          'host': endpoint.domain.split('.'),
          'path': endpoint.path.split('/').where((s) => s.isNotEmpty).toList(),
        },
      },
      'response': endpoint.sampleResponse.isNotEmpty ? [endpoint.sampleResponse] : [],
    }).toList();

    return {
      'info': {
        'name': collectionName,
        'schema': 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
      },
      'item': items,
    };
  }

  void _processRequest(HttpRequest request, HttpResponse? response) {
    final url = request.requestUrl ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final domain = uri.host;
    final path = uri.path;
    final methodName = request.method.name;
    final key = '$methodName:$domain:$path';

    final stats = _stats.putIfAbsent(key, () => _EndpointStats(
      path: path,
      method: methodName,
      domain: domain,
      basePath: _extractBasePath(path),
      firstSeen: DateTime.now(),
      lastSeen: DateTime.now(),
    ));

    stats.callCount++;
    stats.lastSeen = DateTime.now();

    if (response != null) {
      final statusCode = response.status.code;
      if (statusCode >= 200 && statusCode < 400) {
        stats.successCount++;
      } else {
        stats.errorCount++;
      }
      final elapsed = response.request != null
          ? response.responseTime.difference(response.request!.requestTime).inMilliseconds
          : 0;
      stats.totalResponseTime += elapsed > 0 ? elapsed : 0;

      if (stats.sampleResponse.isEmpty) {
        stats.sampleResponse = {
          'statusCode': statusCode,
          'headers': response.headers.toMap(),
          'body': _truncate(response.body == null ? '' : String.fromCharCodes(response.body!), 1000),
        };
      }
    }

    if (stats.sampleRequest.isEmpty) {
      stats.sampleRequest = {
        'headers': request.headers.toMap(),
        'body': _truncate(request.body == null ? '' : String.fromCharCodes(request.body!), 1000),
      };
    }
  }

  String _extractBasePath(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length <= 2) return path;
    
    // 移除 ID 部分
    final normalized = segments.map((s) {
      if (RegExp(r'^\d+$').hasMatch(s)) return '{id}';
      return s;
    }).toList();
    
    return '/${normalized.take(3).join('/')}';
  }

  String _truncate(String str, int maxLen) {
    if (str.length <= maxLen) return str;
    return '${str.substring(0, maxLen)}...';
  }
}

/// 端点统计内部类
class _EndpointStats {
  final String path;
  final String method;
  final String domain;
  final String basePath;
  final DateTime firstSeen;
  DateTime lastSeen;
  int callCount = 0;
  int successCount = 0;
  int errorCount = 0;
  int totalResponseTime = 0;
  Map<String, dynamic> sampleRequest = {};
  Map<String, dynamic> sampleResponse = {};

  _EndpointStats({
    required this.path,
    required this.method,
    required this.domain,
    required this.basePath,
    required this.firstSeen,
    required this.lastSeen,
    this.sampleRequest = const {},
    this.sampleResponse = const {},
  });

  ApiEndpoint toEndpoint() => ApiEndpoint(
    path: path,
    method: method,
    domain: domain,
    basePath: basePath,
    callCount: callCount,
    avgResponseTime: callCount > 0 ? totalResponseTime / callCount : 0,
    successCount: successCount,
    errorCount: errorCount,
    firstSeen: firstSeen,
    lastSeen: lastSeen,
    sampleRequest: sampleRequest,
    sampleResponse: sampleResponse,
  );
}
