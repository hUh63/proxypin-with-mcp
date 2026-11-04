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

// 目录浏览（编辑器里的「打开文件夹」）。
//
// 不做树形展开：手机竖屏上树一深就没法看了，而且一次渲染几百行很卡。
// 这里用「一层一跳」的方式：目录在上、文件在下，点目录进下一层，点文件直接打开，
// 顶部有面包屑与「上一级」。这是手机上浏览工程目录最省事的形态。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';

const Set<String> _binaryExts = {
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'heic',
  'zip', 'rar', '7z', 'gz', 'tar', 'jar', 'apk', 'aar', 'ipa',
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
  'mp3', 'mp4', 'mkv', 'avi', 'mov', 'wav', 'flac',
  'so', 'dll', 'dylib', 'exe', 'bin', 'class', 'dex', 'o', 'a',
  'ttf', 'otf', 'woff', 'woff2', 'db', 'sqlite', 'keystore', 'jks',
};

const int _maxEntries = 2000;

class _Entry {
  final String name;
  final String path;
  final bool isDir;
  final int size;

  const _Entry(this.name, this.path, this.isDir, this.size);
}

/// 打开目录浏览，返回选中的文件路径（取消返回 null）。
Future<String?> showEditorFileBrowser(BuildContext context, {required Directory root}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FileBrowserSheet(root: root),
  );
}

class _FileBrowserSheet extends StatefulWidget {
  final Directory root;

  const _FileBrowserSheet({required this.root});

  @override
  State<_FileBrowserSheet> createState() => _FileBrowserSheetState();
}

class _FileBrowserSheetState extends State<_FileBrowserSheet> {
  late Directory _dir = widget.root;
  final _query = TextEditingController();
  List<_Entry> _all = const <_Entry>[];
  List<_Entry> _view = const <_Entry>[];
  bool _loading = true;
  String? _error;

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
    setState(() {
      _loading = true;
      _error = null;
    });
    final dirs = <_Entry>[];
    final files = <_Entry>[];
    try {
      await for (final e in _dir.list(followLinks: false)) {
        final parts = e.uri.pathSegments;
        final name = parts.isEmpty ? '' : parts.last;
        if (name.isEmpty || name.startsWith('.')) continue;
        if (e is Directory) {
          dirs.add(_Entry(name, e.path, true, 0));
        } else if (e is File) {
          final dot = name.lastIndexOf('.');
          final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
          if (_binaryExts.contains(ext)) continue;
          var size = 0;
          try {
            size = await e.length();
          } catch (_) {
            // 权限/已删除：按 0 显示
          }
          files.add(_Entry(name, e.path, false, size));
        }
        if (dirs.length + files.length >= _maxEntries) break;
      }
      dirs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (e) {
      _error = '$e';
    }
    if (!mounted) return;
    setState(() {
      _all = [...dirs, ...files];
      _view = _all;
      _loading = false;
    });
  }

  void _enter(Directory d) {
    _dir = d;
    _query.clear();
    _load();
  }

  void _up() {
    final parent = _dir.parent;
    if (parent.path == _dir.path) return;
    _enter(parent);
  }

  void _filter(String q) {
    final query = q.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _view = _all;
      } else {
        _view = _all.where((e) => e.name.toLowerCase().contains(query)).toList();
      }
    });
  }

  static String _sizeText(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: loc.editorBrowserUp,
                  icon: const Icon(Icons.arrow_upward, size: 20),
                  onPressed: _up,
                ),
                Expanded(
                  child: Text(
                    _dir.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  tooltip: loc.refresh,
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _load,
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
              onChanged: _filter,
              decoration: InputDecoration(
                hintText: loc.editorBrowserFilter,
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
                            child: Text(loc.editorBrowserEmpty,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.hintColor)),
                          )
                        : ListView.builder(
                            itemCount: _view.length,
                            itemBuilder: (context, i) {
                              final e = _view[i];
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  e.isDir ? Icons.folder : Icons.insert_drive_file_outlined,
                                  size: 20,
                                  color: e.isDir ? Colors.amber.shade700 : theme.hintColor,
                                ),
                                title: Text(e.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13)),
                                trailing: e.isDir
                                    ? const Icon(Icons.chevron_right, size: 18)
                                    : Text(_sizeText(e.size),
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(color: theme.hintColor)),
                                onTap: () {
                                  if (e.isDir) {
                                    _enter(Directory(e.path));
                                  } else {
                                    Navigator.of(context).pop(e.path);
                                  }
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
