/*
 * Copyright 2026 Hongen Wang All rights reserved.
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

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/text_diff.dart';

/// 用真实引擎算块、再按策略合并，最后和期望结果比。
String mergeOf(String left, String right, String Function(int i) pick) {
  final l = left.isEmpty ? const <String>[] : left.split('\n');
  final r = right.isEmpty ? const <String>[] : right.split('\n');
  final blocks = buildDiffBlocks(diffLines(left, right));
  return mergeTwoWay(
    leftLines: l,
    rightLines: r,
    blocks: blocks,
    useRight: (i) => pick(i) == 'R',
  );
}

void main() {
  test('全部用左侧 = 左原文', () {
    const left = 'a\nb\nc';
    const right = 'a\nB\nc\nd';
    expect(mergeOf(left, right, (_) => 'L'), left);
  });

  test('全部用右侧 = 右原文', () {
    const left = 'a\nb\nc';
    const right = 'a\nB\nc\nd';
    expect(mergeOf(left, right, (_) => 'R'), right);
  });

  test('逐块混合：改一处用右、加一行用左', () {
    // a / b→B / c 相同；d 只右侧有
    const left = 'a\nb\nc';
    const right = 'a\nB\nc\nd';
    final merged = mergeOf(left, right, (i) => i == 0 ? 'R' : 'L');
    expect(merged, 'a\nB\nc');
  });

  test('纯删除块选左侧保留、选右侧删除', () {
    const left = 'a\nb\nc\nd';
    const right = 'a\nd';
    expect(mergeOf(left, right, (_) => 'R'), 'a\nd');
    expect(mergeOf(left, right, (_) => 'L'), 'a\nb\nc\nd');
  });

  test('纯新增块选右侧插入、选左侧不插入', () {
    const left = 'a\nd';
    const right = 'a\nb\nc\nd';
    expect(mergeOf(left, right, (_) => 'R'), 'a\nb\nc\nd');
    expect(mergeOf(left, right, (_) => 'L'), 'a\nd');
  });

  test('完全相同的文本合并后不变', () {
    const same = 'x\ny\nz';
    expect(mergeOf(same, same, (_) => 'R'), same);
    expect(mergeOf(same, same, (_) => 'L'), same);
  });

  test('空左 / 空右', () {
    expect(mergeOf('', 'a\nb', (_) => 'R'), 'a\nb');
    expect(mergeOf('', 'a\nb', (_) => 'L'), '');
    expect(mergeOf('a\nb', '', (_) => 'R'), '');
    expect(mergeOf('a\nb', '', (_) => 'L'), 'a\nb');
  });

  test('不丢行也不重复：合并结果的行数落在合理区间', () {
    var left = '';
    var right = '';
    for (var i = 0; i < 200; i++) {
      left += 'L$i\n';
      // 右侧每隔 3 行改一次，另外每隔 7 行多插一行
      right += (i % 3 == 0) ? 'R$i\n' : 'L$i\n';
      if (i % 7 == 0) right += 'extra$i\n';
    }
    final mergedAllRight = mergeOf(left, right, (_) => 'R');
    final mergedAllLeft = mergeOf(left, right, (_) => 'L');
    expect(mergedAllRight, right);
    expect(mergedAllLeft, left);
  });

  test('CRLF 内容：行尾的 \\r 原样保留', () {
    const left = 'a\r\nb\r\nc';
    const right = 'a\r\nB\r\nc';
    final merged = mergeOf(left, right, (_) => 'R');
    expect(merged, 'a\r\nB\r\nc');
  });
}
