import 'dart:io';

import 'package:flutter/material.dart';

/// 工作区文件树（VS 的「解决方案资源管理器」在手机上能落地的最小形态）。
///
/// 编辑器此前只能「打开单个文件」和「扫描工作区做多文件搜索」，中间缺了最常用
/// 的一步：看见目录结构、点着往下走。手机上反复调系统文件选择器进同一个目录，
/// 每次都要从根开始点，是这个编辑器最费手的环节。
///
/// 设计取舍：
/// - **懒加载**：只列出真正展开过的目录，几万文件的项目也能秒开；
/// - **跳过大目录**：`.git`、`node_modules`、`build` 之类列出来只会拖慢和干扰；
/// - **平铺渲染**：把树压成一维列表再喂给 `ListView.builder`，几千项也不掉帧。
class WorkspaceTreeSheet extends StatefulWidget {
  const WorkspaceTreeSheet({super.key, required this.root, required this.onOpenFile});

  /// 工作区根目录。
  final String root;

  /// 点中文件时回调（sheet 自己会先关掉）。
  final void Function(String path) onOpenFile;

  /// 单目录最多列这么多项（超大目录只列前面一部分，避免卡死）。
  static const int maxEntriesPerDir = 800;

  /// 展开后也不值得看的目录。
  static const Set<String> skipDirs = {
    '.git',
    '.svn',
    '.hg',
    '.idea',
    '.gradle',
    '.dart_tool',
    '.venv',
    '.next',
    '.nuxt',
    'node_modules',
    'build',
    'dist',
    'target',
    '__pycache__',
    'Pods',
    '.pub-cache',
  };

  /// 弹出文件树。[root] 为空时什么都不做。
  static Future<void> show(
    BuildContext context, {
    required String root,
    required void Function(String path) onOpenFile,
  }) {
    if (root.isEmpty) return Future<void>.value();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => WorkspaceTreeSheet(root: root, onOpenFile: onOpenFile),
    );
  }

  @override
  State<WorkspaceTreeSheet> createState() => _WorkspaceTreeSheetState();
}

/// 树里的一行。
typedef _TreeRow = ({String path, String name, int depth, bool isDir});

class _WorkspaceTreeSheetState extends State<WorkspaceTreeSheet> {
  /// 已展开的目录路径（根目录默认展开）。
  late final Set<String> _expanded = {widget.root};

  /// 目录内容缓存：path → 子项（已排序）。
  final Map<String, List<FileSystemEntity>> _cache = {};

  /// 正在读盘的目录（显示转圈，同时防重复读）。
  final Set<String> _loading = {};

  @override
  void initState() {
    super.initState();
    _load(widget.root);
  }

  static String _baseName(String path) {
    final i = path.lastIndexOf(Platform.pathSeparator);
    if (i >= 0 && i + 1 < path.length) return path.substring(i + 1);
    final j = path.lastIndexOf('/');
    if (j >= 0 && j + 1 < path.length) return path.substring(j + 1);
    return path;
  }

  Future<void> _load(String dir) async {
    if (_cache.containsKey(dir) || _loading.contains(dir)) return;
    setState(() => _loading.add(dir));
    var items = const <FileSystemEntity>[];
    try {
      items = await Directory(dir).list(followLinks: false).toList();
    } catch (_) {
      // 没权限 / 目录被删：当作空目录，不打断整个浏览。
    }
    final sorted = items.toList()
      ..sort((a, b) {
        final ad = a is Directory;
        final bd = b is Directory;
        if (ad != bd) return ad ? -1 : 1;
        return _baseName(a.path).toLowerCase().compareTo(_baseName(b.path).toLowerCase());
      });
    if (!mounted) return;
    setState(() {
      _loading.remove(dir);
      _cache[dir] = sorted.length > WorkspaceTreeSheet.maxEntriesPerDir
          ? sorted.sublist(0, WorkspaceTreeSheet.maxEntriesPerDir)
          : sorted;
    });
  }

  void _toggleDir(String path) {
    setState(() {
      if (!_expanded.remove(path)) {
        _expanded.add(path);
        _load(path);
      }
    });
  }

  /// 把树压成一维列表（只走已展开 + 已加载的节点）。
  List<_TreeRow> _flatten() {
    final out = <_TreeRow>[];
    void walk(String dir, int depth) {
      final items = _cache[dir];
      if (items == null) return;
      for (final e in items) {
        final name = _baseName(e.path);
        if (e is Directory) {
          if (name.startsWith('.') || WorkspaceTreeSheet.skipDirs.contains(name)) continue;
          out.add((path: e.path, name: name, depth: depth, isDir: true));
          if (_expanded.contains(e.path)) walk(e.path, depth + 1);
        } else if (e is File) {
          out.add((path: e.path, name: name, depth: depth, isDir: false));
        }
      }
    }

    walk(widget.root, 0);
    return out;
  }

  static IconData _iconFor(String name, bool isDir) {
    if (isDir) return Icons.folder_outlined;
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'dart' || 'kt' || 'java' || 'js' || 'ts' || 'c' || 'cpp' || 'h' || 'cs' => Icons.code,
      'md' || 'txt' || 'log' => Icons.description_outlined,
      'json' || 'yaml' || 'yml' || 'toml' || 'ini' || 'xml' => Icons.data_object,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'svg' => Icons.image_outlined,
      'zip' || 'apk' || 'tar' || 'gz' || '7z' || 'jar' => Icons.folder_zip_outlined,
      'sh' || 'bat' || 'ps1' => Icons.terminal,
      _ => Icons.insert_drive_file_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _flatten();
    final rootName = _baseName(widget.root);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 6, 8),
              child: Row(children: [
                Icon(Icons.account_tree_outlined, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(rootName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () {
                    // `_load` 内部会自己 setState（转圈 / 完成），不能在 setState
                    // 的闭包里再调它 —— 先同步改状态，再在外面重新读盘。
                    final open = _expanded.toList();
                    setState(() {
                      _cache.clear();
                      _expanded
                        ..clear()
                        ..add(widget.root);
                    });
                    for (final d in open) {
                      if (d == widget.root) continue;
                      _expanded.add(d);
                      _load(d);
                    }
                  },
                ),
              ]),
            ),
            const Divider(height: 1),
            Flexible(
              child: rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: _loading.contains(widget.root)
                            ? const SizedBox(
                                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text('—', style: TextStyle(color: theme.hintColor)),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final row = rows[i];
                        final busy = _loading.contains(row.path);
                        final open = _expanded.contains(row.path);
                        return InkWell(
                          onTap: () {
                            if (row.isDir) {
                              _toggleDir(row.path);
                            } else {
                              Navigator.of(context).pop();
                              widget.onOpenFile(row.path);
                            }
                          },
                          child: Padding(
                            padding: EdgeInsets.only(left: 10 + row.depth * 14.0),
                            child: Row(children: [
                              if (row.isDir)
                                Icon(open ? Icons.expand_more : Icons.chevron_right,
                                    size: 16, color: theme.hintColor)
                              else
                                const SizedBox(width: 16),
                              const SizedBox(width: 2),
                              Icon(
                                _iconFor(row.name, row.isDir),
                                size: 17,
                                color: row.isDir
                                    ? theme.colorScheme.primary.withValues(alpha: 0.85)
                                    : theme.hintColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(row.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13)),
                              ),
                              if (busy)
                                const Padding(
                                  padding: EdgeInsets.only(right: 12),
                                  child: SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(strokeWidth: 1.6)),
                                ),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
