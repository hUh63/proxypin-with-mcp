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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/dir_diff.dart';

void main() {
  late Directory root;
  late String left;
  late String right;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dd_');
    left = '${root.path}${Platform.pathSeparator}L';
    right = '${root.path}${Platform.pathSeparator}R';
    Directory(left).createSync(recursive: true);
    Directory(right).createSync(recursive: true);
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  void write(String rootDir, String rel, String content) {
    final f = File('$rootDir${Platform.pathSeparator}'
        '${rel.replaceAll('/', Platform.pathSeparator)}');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  void writeBytes(String rootDir, String rel, List<int> bytes) {
    final f = File('$rootDir${Platform.pathSeparator}'
        '${rel.replaceAll('/', Platform.pathSeparator)}');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
  }

  DirDiffEntry of(DirDiffResult r, String path) =>
      r.entries.firstWhere((e) => e.relativePath == path);

  test('相同 / 修改 / 仅一侧 都能区分', () async {
    write(left, 'a.txt', 'hello');
    write(right, 'a.txt', 'hello');
    write(left, 'b.txt', 'hello');
    write(right, 'b.txt', 'world');
    write(left, 'only-left.txt', 'x');
    write(right, 'only-right.txt', 'y');

    final r = await DirDiff.compare(left, right);
    expect(r.error, isNull);
    expect(of(r, 'a.txt').status, DirDiffStatus.same);
    expect(of(r, 'b.txt').status, DirDiffStatus.modified);
    expect(of(r, 'only-left.txt').status, DirDiffStatus.leftOnly);
    expect(of(r, 'only-right.txt').status, DirDiffStatus.rightOnly);
    expect(r.countOf(DirDiffStatus.same), 1);
    expect(r.differentCount, 3);
  });

  test('子目录按 / 拼相对路径，且能递归', () async {
    write(left, 'pkg/src/main.dart', 'void main() {}');
    write(right, 'pkg/src/main.dart', 'void main() { }');
    final r = await DirDiff.compare(left, right);
    final e = of(r, 'pkg/src/main.dart');
    expect(e.status, DirDiffStatus.modified);
    expect(e.name, 'main.dart');
    expect(e.dir, 'pkg/src');
  });

  test('大小不同直接判二进制差异（不读内容）', () async {
    write(left, 'x.bin', 'aaa');
    write(right, 'x.bin', 'aaaa');
    final r = await DirDiff.compare(left, right);
    expect(of(r, 'x.bin').status, DirDiffStatus.binaryModified);
  });

  test('含 0 字节的文件内容不同时算二进制差异', () async {
    writeBytes(left, 'y.bin', [1, 2, 0, 4]);
    writeBytes(right, 'y.bin', [1, 9, 0, 4]);
    final r = await DirDiff.compare(left, right);
    expect(of(r, 'y.bin').status, DirDiffStatus.binaryModified);
  });

  test('文本内容不同算修改（即使含非 ASCII）', () async {
    write(left, 'zh.txt', '中文内容');
    write(right, 'zh.txt', '中文內容');
    final r = await DirDiff.compare(left, right);
    expect(of(r, 'zh.txt').status, DirDiffStatus.modified);
  });

  test('跳过 node_modules / .git 等目录', () async {
    write(left, 'node_modules/x.js', 'a');
    write(right, 'node_modules/x.js', 'b');
    write(left, '.git/config', 'a');
    write(left, 'keep.txt', 'k');
    write(right, 'keep.txt', 'k');
    final r = await DirDiff.compare(left, right);
    expect(r.entries.map((e) => e.relativePath).toList(), ['keep.txt']);
  });

  test('compareContent=false 时同大小一律算相同', () async {
    write(left, 'a.txt', 'hello');
    write(right, 'a.txt', 'world');
    final r = await DirDiff.compare(left, right, compareContent: false);
    expect(of(r, 'a.txt').status, DirDiffStatus.same);
  });

  test('空文件两侧都算相同', () async {
    write(left, 'empty.txt', '');
    write(right, 'empty.txt', '');
    final r = await DirDiff.compare(left, right);
    expect(of(r, 'empty.txt').status, DirDiffStatus.same);
  });

  test('目录不存在时返回错误码而不是抛异常', () async {
    final r = await DirDiff.compare('$left/nope', right);
    expect(r.error, 'left-missing');
    final r2 = await DirDiff.compare(left, '$right/nope');
    expect(r2.error, 'right-missing');
    final r3 = await DirDiff.compare('', right);
    expect(r3.error, 'empty');
  });

  test('compareFiles 一致返回 null、不一致返回原因', () async {
    write(left, 'f.txt', 'same');
    write(right, 'f.txt', 'same');
    expect(
        await DirDiff.compareFiles('$left${Platform.pathSeparator}f.txt',
            '$right${Platform.pathSeparator}f.txt'),
        isNull);
    write(right, 'f.txt', 'different');
    expect(
        await DirDiff.compareFiles('$left${Platform.pathSeparator}f.txt',
            '$right${Platform.pathSeparator}f.txt'),
        isNotNull);
  });

  test('相同的空目录对不产生任何条目', () async {
    final r = await DirDiff.compare(left, right);
    expect(r.entries, isEmpty);
    expect(r.hasDifference, isFalse);
  });
}
