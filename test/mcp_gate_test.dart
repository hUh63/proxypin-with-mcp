/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/// 覆盖 MCP 并发闸（McpGate）：排队、超时拒绝、名额回收。
///
/// 重点回归：等待超时与「名额刚好交接」同时发生时，名额不能凭空消失
/// （旧实现会让 _running 计数漂移，反复命中后闸门永久缩水）。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/mcp/mcp_runtime.dart';

void main() {
  group('McpGate', () {
    test('并发上限内直接执行，结束后名额归还', () async {
      final gate = McpGate(maxConcurrent: 2, queueLimit: 4);
      expect(await gate.run(() async => 1), 1);
      expect(gate.running, 0);
      expect(gate.queued, 0);
    });

    test('满载时排队，名额释放后按序执行', () async {
      final gate = McpGate(maxConcurrent: 1, queueLimit: 4);
      final blocker = Completer<void>();
      final first = gate.run(() async {
        await blocker.future;
        return 'first';
      });
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(gate.running, 1);

      var secondStarted = false;
      final second = gate.run(() async {
        secondStarted = true;
        return 'second';
      });
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(secondStarted, isFalse, reason: '满载时应排队');
      expect(gate.queued, 1);

      blocker.complete();
      expect(await first, 'first');
      expect(await second, 'second');
      expect(gate.running, 0);
      expect(gate.queued, 0);
    });

    test('排队超时返回 busy，且名额没有被吞掉', () async {
      final gate = McpGate(
        maxConcurrent: 1,
        queueLimit: 4,
        waitTimeout: const Duration(milliseconds: 60),
      );
      final blocker = Completer<void>();
      final first = gate.run(() async {
        await blocker.future;
        return 'first';
      });
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await expectLater(
        gate.run(() async => 'never'),
        throwsA(isA<McpBusyException>()),
      );
      expect(gate.queued, 0, reason: '超时后不能留下排队占位');

      blocker.complete();
      await first;
      expect(gate.running, 0);

      // 关键断言：闸门仍可用（旧实现在竞态下会让名额永久缩水）
      expect(await gate.run(() async => 'ok'), 'ok');
      expect(gate.running, 0);
    });

    test('队列满时立即拒绝', () async {
      final gate = McpGate(
        maxConcurrent: 1,
        queueLimit: 1,
        waitTimeout: const Duration(seconds: 5),
      );
      final blocker = Completer<void>();
      final first = gate.run(() async {
        await blocker.future;
        return 'first';
      });
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final queued = gate.run(() async => 'queued'); // 占满队列
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(gate.queued, 1);

      await expectLater(
        gate.run(() async => 'rejected'),
        throwsA(isA<McpBusyException>()),
      );

      blocker.complete();
      await first;
      expect(await queued, 'queued');
      expect(gate.running, 0);
      expect(gate.queued, 0);
    });

    test('任务抛异常时名额同样归还', () async {
      final gate = McpGate(maxConcurrent: 1, queueLimit: 2);
      await expectLater(gate.run(() async => throw StateError('boom')), throwsA(isA<StateError>()));
      expect(gate.running, 0);
      expect(await gate.run(() async => 'after'), 'after');
    });

    test('频繁超时不导致闸门缩水（连续 5 次）', () async {
      final gate = McpGate(
        maxConcurrent: 1,
        queueLimit: 8,
        waitTimeout: const Duration(milliseconds: 30),
      );
      for (var i = 0; i < 5; i++) {
        final blocker = Completer<void>();
        final first = gate.run(() async {
          await blocker.future;
          return i;
        });
        await Future<void>.delayed(const Duration(milliseconds: 3));
        await expectLater(gate.run(() async => -1), throwsA(isA<McpBusyException>()));
        blocker.complete();
        await first;
        expect(gate.running, 0, reason: '第 $i 轮后 running 必须归零');
      }
      expect(await gate.run(() async => 42), 42);
    });
  });
}
