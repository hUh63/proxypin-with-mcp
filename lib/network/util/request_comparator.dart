/*
 * 请求对比分析器 - 详细的请求差异对比
 * 支持：URL、Headers、Body、响应 对比
 *
 * 注意：本文件此前引用不存在的 Request/Response 类型（从未被编译器编译），
 * 现改为正确的 HttpRequest / HttpResponse。
 */

import 'package:proxypin/network/http/http.dart';

/// 对比结果类型
enum CompareType {
  added, // 新增
  removed, // 删除
  modified, // 修改
  unchanged, // 未变
}

/// 字段对比结果
class FieldCompare {
  final String fieldName;
  final String? oldValue;
  final String? newValue;
  final CompareType type;

  FieldCompare({
    required this.fieldName,
    this.oldValue,
    this.newValue,
    this.type = CompareType.unchanged,
  });

  bool get hasChanged => type != CompareType.unchanged;
}

/// 对比结果
class ComparisonResult {
  final HttpRequest? requestA;
  final HttpRequest? requestB;
  final HttpResponse? responseA;
  final HttpResponse? responseB;

  // URL 对比
  final bool urlChanged;

  // 方法对比
  final bool methodChanged;

  // 请求头对比
  final List<FieldCompare> headerDiffs;

  // 请求体对比
  final FieldCompare? bodyDiff;

  // 查询参数对比
  final List<FieldCompare> queryDiffs;

  // 响应状态码对比
  final bool statusCodeChanged;

  // 响应头对比
  final List<FieldCompare> responseHeaderDiffs;

  // 响应体对比
  final FieldCompare? responseBodyDiff;

  // 总体统计
  final int totalChanges;
  final String summary;

  ComparisonResult({
    this.requestA,
    this.requestB,
    this.responseA,
    this.responseB,
    this.urlChanged = false,
    this.methodChanged = false,
    this.headerDiffs = const [],
    this.bodyDiff,
    this.queryDiffs = const [],
    this.statusCodeChanged = false,
    this.responseHeaderDiffs = const [],
    this.responseBodyDiff,
    this.totalChanges = 0,
    this.summary = '',
  });

  /// 是否有变化
  bool get hasChanges => totalChanges > 0;

  /// 获取变化详情文本
  String get detailedReport {
    final buffer = StringBuffer();
    buffer.writeln('=== 请求对比报告 ===\n');

    if (urlChanged) {
      buffer.writeln('URL 变化:');
      buffer.writeln('  - 旧：${requestA?.requestUrl}');
      buffer.writeln('  + 新：${requestB?.requestUrl}\n');
    }

    if (methodChanged) {
      buffer.writeln('方法变化:');
      buffer.writeln('  - ${requestA?.method.name} → + ${requestB?.method.name}\n');
    }

    if (headerDiffs.isNotEmpty) {
      buffer.writeln('请求头变化 (${headerDiffs.length}):');
      for (var diff in headerDiffs) {
        if (diff.type == CompareType.added) {
          buffer.writeln('  + ${diff.fieldName}: ${diff.newValue}');
        } else if (diff.type == CompareType.removed) {
          buffer.writeln('  - ${diff.fieldName}: ${diff.oldValue}');
        } else if (diff.type == CompareType.modified) {
          buffer.writeln('  ~ ${diff.fieldName}:');
          buffer.writeln('      旧：${diff.oldValue}');
          buffer.writeln('      新：${diff.newValue}');
        }
      }
      buffer.writeln();
    }

    if (bodyDiff != null && bodyDiff!.hasChanged) {
      buffer.writeln('请求体变化:');
      if (bodyDiff!.type == CompareType.modified) {
        buffer.writeln('  旧：${_truncate(bodyDiff!.oldValue, 200)}');
        buffer.writeln('  新：${_truncate(bodyDiff!.newValue, 200)}');
      }
      buffer.writeln();
    }

    if (queryDiffs.isNotEmpty) {
      buffer.writeln('查询参数变化 (${queryDiffs.length}):');
      for (var diff in queryDiffs) {
        if (diff.type == CompareType.added) {
          buffer.writeln('  + ${diff.fieldName}=${diff.newValue}');
        } else if (diff.type == CompareType.removed) {
          buffer.writeln('  - ${diff.fieldName}=${diff.oldValue}');
        } else if (diff.type == CompareType.modified) {
          buffer.writeln('  ~ ${diff.fieldName}: ${diff.oldValue} → ${diff.newValue}');
        }
      }
      buffer.writeln();
    }

    if (statusCodeChanged) {
      buffer.writeln('状态码变化:');
      buffer.writeln('  - ${responseA?.status.code} → + ${responseB?.status.code}\n');
    }

    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('总计变化：$totalChanges 处');
    buffer.writeln('对比结果：${hasChanges ? "存在差异" : "完全相同"}');

    return buffer.toString();
  }

  String _truncate(String? str, int maxLen) {
    if (str == null) return 'null';
    if (str.length <= maxLen) return str;
    return '${str.substring(0, maxLen)}... (${str.length} 字符)';
  }
}

/// 请求对比分析器
class RequestComparator {
  /// 对比两个请求
  ComparisonResult compare(HttpRequest requestA, HttpRequest requestB,
      {HttpResponse? responseA, HttpResponse? responseB}) {
    int changes = 0;
    final headerDiffs = <FieldCompare>[];
    final queryDiffs = <FieldCompare>[];

    final urlA = requestA.requestUrl ?? '';
    final urlB = requestB.requestUrl ?? '';

    // URL 对比
    final urlChanged = urlA != urlB;
    if (urlChanged) changes++;

    // 方法对比
    final methodChanged = requestA.method != requestB.method;
    if (methodChanged) changes++;

    // 请求头对比
    final mapA = requestA.headers.toMap();
    final mapB = requestB.headers.toMap();
    final allHeaders = <String>{...mapA.keys, ...mapB.keys};
    for (var key in allHeaders) {
      final valueA = mapA[key];
      final valueB = mapB[key];
      if (valueA == null && valueB != null) {
        headerDiffs.add(FieldCompare(fieldName: key, newValue: valueB, type: CompareType.added));
        changes++;
      } else if (valueA != null && valueB == null) {
        headerDiffs.add(FieldCompare(fieldName: key, oldValue: valueA, type: CompareType.removed));
        changes++;
      } else if (valueA != valueB) {
        headerDiffs
            .add(FieldCompare(fieldName: key, oldValue: valueA, newValue: valueB, type: CompareType.modified));
        changes++;
      }
    }

    // 查询参数对比
    final uriA = requestA.requestUri;
    final uriB = requestB.requestUri;
    final allQueryKeys = <String>{...?uriA?.queryParameters.keys, ...?uriB?.queryParameters.keys};
    for (var key in allQueryKeys) {
      final valueA = uriA?.queryParameters[key];
      final valueB = uriB?.queryParameters[key];
      if (valueA == null && valueB != null) {
        queryDiffs.add(FieldCompare(fieldName: key, newValue: valueB, type: CompareType.added));
        changes++;
      } else if (valueA != null && valueB == null) {
        queryDiffs.add(FieldCompare(fieldName: key, oldValue: valueA, type: CompareType.removed));
        changes++;
      } else if (valueA != valueB) {
        queryDiffs
            .add(FieldCompare(fieldName: key, oldValue: valueA, newValue: valueB, type: CompareType.modified));
        changes++;
      }
    }

    // 请求体对比
    FieldCompare? bodyDiff;
    final bodyA = requestA.bodyAsString;
    final bodyB = requestB.bodyAsString;
    if (bodyA != bodyB) {
      bodyDiff = FieldCompare(
        fieldName: 'body',
        oldValue: bodyA.isEmpty ? null : bodyA,
        newValue: bodyB.isEmpty ? null : bodyB,
        type: bodyA.isEmpty
            ? CompareType.added
            : (bodyB.isEmpty ? CompareType.removed : CompareType.modified),
      );
      changes++;
    }

    // 响应状态码对比
    bool statusCodeChanged = false;
    if (responseA != null && responseB != null && responseA.status.code != responseB.status.code) {
      statusCodeChanged = true;
      changes++;
    }

    // 响应头对比
    final responseHeaderDiffs = <FieldCompare>[];
    if (responseA != null && responseB != null) {
      final rMapA = responseA.headers.toMap();
      final rMapB = responseB.headers.toMap();
      final allRespHeaders = <String>{...rMapA.keys, ...rMapB.keys};
      for (var key in allRespHeaders) {
        final valueA = rMapA[key];
        final valueB = rMapB[key];
        if (valueA == null && valueB != null) {
          responseHeaderDiffs.add(FieldCompare(fieldName: key, newValue: valueB, type: CompareType.added));
          changes++;
        } else if (valueA != null && valueB == null) {
          responseHeaderDiffs.add(FieldCompare(fieldName: key, oldValue: valueA, type: CompareType.removed));
          changes++;
        } else if (valueA != valueB) {
          responseHeaderDiffs
              .add(FieldCompare(fieldName: key, oldValue: valueA, newValue: valueB, type: CompareType.modified));
          changes++;
        }
      }
    }

    // 响应体对比
    FieldCompare? responseBodyDiff;
    if (responseA != null && responseB != null) {
      final rBodyA = responseA.bodyAsString;
      final rBodyB = responseB.bodyAsString;
      if (rBodyA != rBodyB) {
        responseBodyDiff = FieldCompare(
          fieldName: 'body',
          oldValue: rBodyA.isEmpty ? null : rBodyA,
          newValue: rBodyB.isEmpty ? null : rBodyB,
          type: rBodyA.isEmpty
              ? CompareType.added
              : (rBodyB.isEmpty ? CompareType.removed : CompareType.modified),
        );
        changes++;
      }
    }

    return ComparisonResult(
      requestA: requestA,
      requestB: requestB,
      responseA: responseA,
      responseB: responseB,
      urlChanged: urlChanged,
      methodChanged: methodChanged,
      headerDiffs: headerDiffs,
      bodyDiff: bodyDiff,
      queryDiffs: queryDiffs,
      statusCodeChanged: statusCodeChanged,
      responseHeaderDiffs: responseHeaderDiffs,
      responseBodyDiff: responseBodyDiff,
      totalChanges: changes,
      summary: '共 $changes 处变化',
    );
  }
}
