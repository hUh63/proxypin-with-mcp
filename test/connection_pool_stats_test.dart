import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/http/connection_pool.dart';

/// 性能面板的「请求量 / 成功率 / 平均耗时 / QPS」原来只由 `ConnectionPool.execute()`
/// 累加，而转发走的是自研网络层、execute() 从未被调用 → 面板长期显示 0。
/// 现在由响应处理链路调用 `recordTraffic()` 上报，这里锁住统计口径。
void main() {
  test('recordTraffic 累加请求量、成功/失败与平均耗时', () {
    final pool = ConnectionPool();

    pool.recordTraffic(elapsedMs: 100, statusCode: 200);
    pool.recordTraffic(elapsedMs: 300, statusCode: 500);

    final stats = pool.getStats();
    expect(stats['totalRequests'], 2);
    expect(stats['successfulRequests'], 1);
    expect(stats['failedRequests'], 1);
    expect(stats['avgResponseTimeMs'], 200);
    expect((stats['successRate'] as double), closeTo(0.5, 1e-9));
  });

  test('3xx 算成功，4xx/5xx 与缺失状态码算失败', () {
    final pool = ConnectionPool();
    pool.recordTraffic(elapsedMs: 10, statusCode: 302);
    pool.recordTraffic(elapsedMs: 10, statusCode: 404);
    pool.recordTraffic(elapsedMs: 10, statusCode: null);

    final stats = pool.getStats();
    expect(stats['successfulRequests'], 1);
    expect(stats['failedRequests'], 2);
  });

  test('负数耗时不会被计入总耗时', () {
    final pool = ConnectionPool();
    pool.recordTraffic(elapsedMs: -500, statusCode: 200);

    expect(pool.getStats()['avgResponseTimeMs'], 0);
  });

  test('QPS 用 5 秒窗口，不会随进程运行时间越来越小', () {
    final pool = ConnectionPool();
    for (var i = 0; i < 10; i++) {
      pool.recordTraffic(elapsedMs: 1, statusCode: 200);
    }
    // 10 条 / 5 秒窗口 = 2.0
    expect(pool.currentQps, closeTo(2.0, 1e-9));
  });
}
