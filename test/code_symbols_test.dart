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
import 'package:proxypin/utils/code_symbols.dart';

void main() {
  test('Dart：方法体里的调用归到方法名', () {
    final lines = [
      'class A {',
      '  void load() {',
      '    fetchData();',
      '  }',
      '}',
    ];
    expect(CodeSymbols.enclosingCaller(lines, 2), 'load');
  });

  test('Dart：嵌套函数取最近的那一层', () {
    final lines = [
      'void outer() {',
      '  void inner() {',
      '    doIt();',
      '  }',
      '}',
    ];
    expect(CodeSymbols.enclosingCaller(lines, 2), 'inner');
  });

  test('顶层调用返回 null', () {
    final lines = ['void main() {}', 'doIt();'];
    expect(CodeSymbols.enclosingCaller(lines, 1), isNull);
  });

  test('控制语句不算函数（if / for / while）', () {
    final lines = [
      'void run() {',
      '  if (a) {',
      '    doIt();',
      '  }',
      '}',
    ];
    // 命中行缩进 4，往上 `if` 缩进 2 但被黑名单挡掉 → 继续找 → run
    expect(CodeSymbols.enclosingCaller(lines, 2), 'run');
  });

  test('Python：def 里的调用', () {
    final lines = [
      'def handler():',
      '    do_it()',
      '',
      'do_it()',
    ];
    expect(CodeSymbols.enclosingCaller(lines, 1), 'handler');
    // 顶层调用（缩进 0）没有外层
    expect(CodeSymbols.enclosingCaller(lines, 3), isNull);
  });

  test('Go：方法体', () {
    final lines = [
      'func (s *Svc) Run() {',
      '\tgo s.doIt()',
      '}',
    ];
    expect(CodeSymbols.enclosingCaller(lines, 1), 'Run');
  });

  test('注释行与空行被跳过', () {
    final lines = [
      'void a() {',
      '  // 说明',
      '',
      '  /* 块注释 */',
      '  x();',
      '}',
    ];
    expect(CodeSymbols.enclosingCaller(lines, 4), 'a');
  });

  test('以分号结尾的行不当函数（调用语句）', () {
    final lines = [
      'void a() {',
      '  bar(x);',
      '  doIt();',
      '}',
    ];
    // 命中行缩进 2，bar(x); 缩进 2 且以 ; 结束 → 跳过，最后落到 a
    expect(CodeSymbols.enclosingCaller(lines, 2), 'a');
  });

  test('嵌套过深时按 maxLookBack 放弃', () {
    final lines = ['void a() {'];
    for (var i = 0; i < 100; i++) {
      lines.add('  x();');
    }
    expect(CodeSymbols.enclosingCaller(lines, 100, maxLookBack: 50), isNull);
    expect(CodeSymbols.enclosingCaller(lines, 100), 'a');
  });

  test('越界行号返回 null 而不是抛', () {
    expect(CodeSymbols.enclosingCaller(const [], 0), isNull);
    expect(CodeSymbols.enclosingCaller(const ['a'], -1), isNull);
    expect(CodeSymbols.enclosingCaller(const ['a'], 5), isNull);
  });

  test('indentOf 把 Tab 记 2 列', () {
    expect(CodeSymbols.indentOf('    x'), 4);
    expect(CodeSymbols.indentOf('\t\tx'), 4);
    expect(CodeSymbols.indentOf('x'), 0);
  });

  test('declaredName：函数与类都能认', () {
    expect(CodeSymbols.declaredName('  Future<void> load() async {'), 'load');
    expect(CodeSymbols.declaredName('class Foo {'), 'Foo');
    expect(CodeSymbols.declaredName('public final class Bar {'), 'Bar');
    expect(CodeSymbols.declaredName('  if (x) {'), isNull);
    expect(CodeSymbols.declaredName(''), isNull);
  });
}
