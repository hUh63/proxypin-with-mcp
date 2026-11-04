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

// 「快速打开文件」（VS / VS Code 的 Ctrl+P）。
//
// 手机上没有文件树，但在同一个目录里来回切文件是编辑时的刚需：
// 一个项目目录几十个文件，每次都要走系统文件选择器翻半天。
// 这里只列**当前文件所在目录**（一层，不递归）的文本文件，打字即时过滤。
//
// 不做递归：几十层目录一递归就几万个文件，手机上是卡顿而不是便利。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';

/// 这些扩展名不当文本打开（列出来只会误点）。
const Set<String> _skipExts = {
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'heic',
  'zip', 'rar', '7z', 'gz', 'tar', 'jar', 'apk', 'aar', 'ipa',
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
  'mp3', 'mp4', 'mkv', 'avi', 'mov', 'wav', 'flac',
  'so', 'dll', 'dylib', 'exe', 'bin', 'class', 'dex', 'o', 'a',
  'ttf', 'otf', 'woff', 'woff2', 'db', 'sqlite', 'keystore', 'jks',
};

/// 单个目录最多列多少个文件（再多就该用搜索而不是列表了）。
const int _maxFiles = 3000;

class _Entry {
  final String name;
  final String path;
  final int size;

  const _Entry(this.name, this.path, this.size);
}

/// 弹出快速打开面板，返回选中的文件路径（取消返回 null）。
Future<String?> showEditorQuickOpen(BuildContext context, {required Directory dir}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _QuickOpenSheet(dir: dir),
  );
}

class _QuickOpenSheet extends StatefulWidget {
  final Directory dir;

  const _QuickOpenSheet({required this.dir});

  @override
  State<_QuickOpenSheet> createState() => _QuickOpenSheetState();
}

class _QuickOpenSheetState extends State<_QuickOpenSheet> {
  final _query = TextEditingController();
  List<_Entry> _all = const <_Entry>[];
  List<_Entry> _view = const <_Entry>[];
  bool _loading = true;
  String? _error;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final out = <_Entry>[];
    try {
      await for (final e in widget.dir.list(followLinks: false)) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.isEmpty ? '' : e.uri.pathSegments.last;
        if (name.isEmpty || name.startsWith('.')) continue;
        final dot = name.lastIndexOf('.');
        final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
        if (_skipExts.contains(ext)) continue;
        int size = 0;
        try {
          size = await e.length();
        } catch (_) {
          // 权限/已删除：大小显示 0 就行
        }
        out.add(_Entry(name, e.path, size));
        if (out.length >= _maxFiles) break;
      }
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (e) {
      _error = '$e';
    }
    if (!mounted) return;
    setState(() {
      _all = out;
      _view = out;
      _loading = false;
    });
  }

  void _filter(String q) {
    final query = q.trim().toLowerCase();
    setState(() {
      _selected = 0;
      if (query.isEmpty) {
        _view = _all;
        return;
      }
      // 先「文件名包含」，再「路径包含」，命中的按名字长度排（短名更可能是目标）。
      final hits = _all.where((e) => e.name.toLowerCase().contains(query)).toList()
        ..sort((a, b) => a.name.length.compareTo(b.name.length));
      _view = hits;
    });
  }

  void _pick(String path) => Navigator.of(context).pop(path);

  static String _sizeText(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final height = MediaQuery.of(context).size.height * 0.75;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
            child: Row(
              children: [
                const Icon(Icons.bolt, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loc.editorQuickOpen, style: theme.textTheme.titleSmall),
                      Text(
                        widget.dir.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: loc.close,
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _query,
              autofocus: true,
              onChanged: _filter,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) {
                if (_view.isNotEmpty) _pick(_view[_selected.clamp(0, _view.length - 1)].path);
              },
              decoration: InputDecoration(
                hintText: loc.editorQuickOpenHint,
                prefixIcon: const Icon(Icons.search, size: 18),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.error)),
                        ),
                      )
                    : _view.isEmpty
                        ? Center(
                            child: Text(
                              _all.isEmpty
                                  ? loc.editorQuickOpenEmpty
                                  : loc.editorQuickOpenNoMatch,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.hintColor),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _view.length,
                            itemBuilder: (context, i) {
                              final e = _view[i];
                              return ListTile(
                                dense: true,
                                selected: i == _selected,
                                leading: Icon(
                                  _iconFor(e.name),
                                  size: 18,
                                  color: theme.hintColor,
                                ),
                                title: Text(e.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13)),
                                trailing: Text(_sizeText(e.size),
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(color: theme.hintColor)),
                                onTap: () => _pick(e.path),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
    switch (ext) {
      case 'json':
      case 'yaml':
      case 'yml':
      case 'xml':
      case 'toml':
        return Icons.data_object;
      case 'md':
      case 'txt':
        return Icons.article_outlined;
      case 'js':
      case 'ts':
      case 'dart':
      case 'java':
      case 'kt':
      case 'py':
      case 'go':
      case 'rs':
      case 'c':
      case 'cpp':
      case 'h':
        return Icons.code;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}
