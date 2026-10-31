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

import 'dart:convert';
import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:proxypin/utils/code_lint.dart';
import 'package:path_provider/path_provider.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/toolbox/console_state.dart';

/// 一个打开的编辑文档。
///
/// 每个文档持有自己的 [CodeForgeController] / [UndoRedoController] / [FindController]，
/// 因此切换文档时文本、撤销重做栈、搜索状态都能保留（对应 MT「多文件编辑」的体验）。
class EditorDocument {
  final String id;
  String name;
  String? path;
  String langLabel;

  /// 置顶（排在列表最前）
  bool pinned;

  /// 保留：退出编辑器时不移除，并落盘以便下次进入恢复
  bool retained;

  /// 书签（**字符偏移**，不是行号）。
  ///
  /// 存行号的话，在上面插一行，下面的书签就会指到隔壁行上；
  /// 存偏移再在文本变化时重映射，才能做到「跟着代码走」（VS 就是这样）。
  final Set<int> bookmarks = <int>{};

  /// 有未写回磁盘的修改。
  ///
  /// 挂在文档上而不是页面状态里：多文档时切来切去，「这份改没改过」
  /// 是每份文件自己的属性，放在页面里会被切文档顺手清掉。
  bool dirty = false;

  late final CodeForgeController controller;
  late final UndoRedoController undoController;
  late final FindController findController;

  /// 这份文件的换行符（`\n` / `\r\n` / `\r`）。
  ///
  /// 打开时按内容检测，保存时按它写回 —— 不能让「页面上的全局偏好」决定，
  /// 否则打开一个 CRLF 文件、改一个字保存，整个文件的换行符就被统一改写了。
  String newline = '\n';

  /// 这份文件实际用的编码名（打开时检测 / 用户手动切换）。
  ///
  /// null = 跟随全局偏好（新建文件、或没检测出来）。放文档上是为了
  /// 「打开 GBK 文件」不会把全局编码改掉，进而污染下一个另存为。
  String? encodingName;

  /// 光标导航历史（「后退 / 前进」用，存字符偏移）。
  ///
  /// 挂在文档上而不是页面状态里：多文档时有的一份文件几万字、有的几行，
  /// 共用一条偏移栈等于「在 A 文件后退，跳到 B 文件的第 N 个字符」，
  /// 位置完全是错的。
  final List<int> navStack = <int>[];
  int navIndex = -1;

  /// 最近编辑过的位置（字符偏移，最多 20 个）。同样按文档分开记。
  final List<int> recentEdits = <int>[];

  /// 最近一次语法检查结果（切换文档时直接恢复标记，不用重跑）。
  LintReport? lint;

  /// 产生 [lint] 时的文本快照（增量检查要拿它和新文本比）。
  String? lintText;

  /// 这份文档的控制台状态（输出 / 命令历史 / 会话变量）。
  ///
  /// 挂在文档上而不是面板上：收起面板、切到别的文件再回来，之前算过的东西还在。
  ConsoleState? console;

  /// 取控制台状态（首次访问时创建）。
  ConsoleState get consoleState => console ??= ConsoleState();

  EditorDocument({
    required this.id,
    required this.name,
    this.path,
    this.langLabel = 'Plain Text',
    this.pinned = false,
    this.retained = false,
    String text = '',
  }) {
    controller = CodeForgeController();
    undoController = UndoRedoController();
    findController = FindController(controller);
    if (text.isNotEmpty) controller.text = text;
  }

  String get text => controller.text;

  set text(String value) => controller.text = value;

  void dispose() {
    findController.dispose();
    undoController.dispose();
    controller.dispose();
  }
}

/// 编辑器文档注册表（进程内单例 + 磁盘持久化）。
class EditorDocuments {
  EditorDocuments._();

  static final EditorDocuments instance = EditorDocuments._();

  final List<EditorDocument> _docs = [];
  int _seq = 0;
  bool _restored = false;

  /// 上一次激活的文档 id，用于下次进入编辑器时恢复现场。
  String? _activeId;

  List<EditorDocument> get docs => List.unmodifiable(_docs);

  bool get isEmpty => _docs.isEmpty;

  String? get activeId => _activeId;

  void set activeId(String? id) => _activeId = id;

  EditorDocument? byId(String id) {
    for (final d in _docs) {
      if (d.id == id) return d;
    }
    return null;
  }

  EditorDocument create({
    required String name,
    String text = '',
    String? path,
    String langLabel = 'Plain Text',
    bool retained = false,
  }) {
    _seq++;
    final id = 'd${DateTime.now().microsecondsSinceEpoch}_$_seq';
    final doc = EditorDocument(
      id: id,
      name: name,
      path: path,
      langLabel: langLabel,
      retained: retained,
      text: text,
    );
    _docs.add(doc);
    return doc;
  }

  void remove(String id) {
    final index = _docs.indexWhere((d) => d.id == id);
    if (index < 0) return;
    final doc = _docs.removeAt(index);
    doc.dispose();
    if (_activeId == id) {
      _activeId = _docs.isEmpty ? null : _docs.first.id;
    }
  }

  /// 拖动排序；置顶文档始终保持在最前。
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _docs.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0) target = 0;
    if (target >= _docs.length) target = _docs.length - 1;
    final doc = _docs.removeAt(oldIndex);
    _docs.insert(target, doc);
  }

  void moveToTop(String id) {
    final index = _docs.indexWhere((d) => d.id == id);
    if (index <= 0) return;
    final doc = _docs.removeAt(index);
    _docs.insert(0, doc);
  }

  void replaceAll(List<EditorDocument> docs) {
    _docs
      ..clear()
      ..addAll(docs);
  }

  // ---------- 持久化 ----------

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/text_editor');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 只落盘「保留」的文档；其余视为临时文件，退出即丢。
  Future<void> persist() async {
    try {
      final dir = await _dir();
      // 先清掉旧文件，保证磁盘与内存一致
      await for (final entity in dir.list()) {
        if (entity is File) {
          await entity.delete();
        }
      }
      final kept = _docs.where((d) => d.retained).toList();
      final manifest = <Map<String, dynamic>>[];
      for (final d in kept) {
        await File('${dir.path}/${d.id}.txt').writeAsString(d.text);
        manifest.add({
          'id': d.id,
          'name': d.name,
          'path': d.path,
          'langLabel': d.langLabel,
          'pinned': d.pinned,
          // 书签存偏移，正文一起落盘后偏移依然有效。
          'bookmarks': d.bookmarks.toList(),
        });
      }
      await File('${dir.path}/manifest.json').writeAsString(jsonEncode({
        'docs': manifest,
        'activeId': _activeId,
      }));
    } catch (e) {
      logger.w('persist text editor docs failed', error: e);
    }
  }

  /// 从磁盘恢复上次保留的文档；同一进程只执行一次。
  Future<void> ensureRestored() async {
    if (_restored) return;
    _restored = true;
    try {
      final dir = await _dir();
      final manifestFile = File('${dir.path}/manifest.json');
      if (!await manifestFile.exists()) return;
      final data = jsonDecode(await manifestFile.readAsString());
      if (data is! Map) return;
      final list = data['docs'];
      if (list is! List) return;

      final restored = <EditorDocument>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        final id = raw['id'] as String?;
        if (id == null || id.isEmpty) continue;
        final file = File('${dir.path}/$id.txt');
        if (!await file.exists()) continue;
        final text = await file.readAsString();
        final doc = EditorDocument(
          id: id,
          name: raw['name'] as String? ?? id,
          path: raw['path'] as String?,
          langLabel: raw['langLabel'] as String? ?? 'Plain Text',
          pinned: raw['pinned'] as bool? ?? false,
          retained: true,
          text: text,
        );
        final marks = raw['bookmarks'];
        if (marks is List) {
          for (final mark in marks) {
            if (mark is int && mark >= 0 && mark <= text.length) doc.bookmarks.add(mark);
          }
        }
        restored.add(doc);
      }
      if (restored.isEmpty) return;
      // 置顶的排前面，其余保持磁盘顺序
      _docs.insertAll(0, restored.where((d) => d.pinned));
      _docs.addAll(restored.where((d) => !d.pinned));
      final activeId = data['activeId'] as String?;
      if (activeId != null && byId(activeId) != null) {
        _activeId = activeId;
      } else {
        _activeId = _docs.first.id;
      }
    } catch (e) {
      logger.w('restore text editor docs failed', error: e);
    }
  }
}
