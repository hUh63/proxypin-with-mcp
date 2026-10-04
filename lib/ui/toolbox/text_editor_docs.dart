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
import 'package:path_provider/path_provider.dart';
import 'package:proxypin/network/util/logger.dart';

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

  late final CodeForgeController controller;
  late final UndoRedoController undoController;
  late final FindController findController;

  /// 打开文件时的原始换行符（仅用于展示；编辑器内部永远是 \n）
  String newline = '\n';

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
