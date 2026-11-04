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

// 「编译诊断」页：粘贴 gcc / clang / cl 的输出 → 中文诊断 + 可定位。
//
// 为什么要这一页：手机上没有编译器，但很多人是在手机上改代码、把编译放到
// 服务器上跑，拿回来的就是一大段英文报错。这里把英文翻成中文，并且能按
// `文件:行:列` 定位回编辑器。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/utils/compiler_log.dart';

class CompilerLogPage extends StatefulWidget {
  /// 当前编辑器文件路径：用来判断「这条诊断是不是本文件的」，能跳就跳。
  final String currentPath;

  const CompilerLogPage({super.key, this.currentPath = ''});

  static Future<CompilerLogEntry?> show(BuildContext context,
      {String currentPath = ''}) {
    return Navigator.of(context).push<CompilerLogEntry>(
      MaterialPageRoute(builder: (_) => CompilerLogPage(currentPath: currentPath)),
    );
  }

  @override
  State<CompilerLogPage> createState() => _CompilerLogPageState();
}

class _CompilerLogPageState extends State<CompilerLogPage> {
  final _input = TextEditingController();
  CompilerLogResult? _result;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.isEmpty) return;
      _input.text = text;
      await _parse();
    } catch (e) {
      logger.w('$e');
    }
  }

  Future<void> _parse() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // 4000 条规则 × 行数，给一帧时间把 loading 画出来
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final r = await parseCompilerLog(text);
      if (!mounted) return;
      setState(() {
        _result = r;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  bool _isSameFile(String file) {
    final cur = widget.currentPath;
    if (cur.isEmpty || file.isEmpty) return false;
    if (cur == file) return true;
    final a = cur.split(RegExp(r'[/\\]')).last;
    final b = file.split(RegExp(r'[/\\]')).last;
    return a == b;
  }

  Future<void> _copyAll() async {
    final r = _result;
    if (r == null) return;
    await Clipboard.setData(ClipboardData(text: r.translated));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.copied)));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final r = _result;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.compilerLogTitle),
        actions: [
          if (r != null)
            IconButton(
              tooltip: loc.compilerLogCopyAll,
              icon: const Icon(Icons.copy_all, size: 20),
              onPressed: _copyAll,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        children: [
          TextField(
            controller: _input,
            minLines: 6,
            maxLines: 10,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace', height: 1.45),
            decoration: InputDecoration(
              hintText: loc.compilerLogHint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _parse,
                  icon: const Icon(Icons.translate, size: 18),
                  label: Text(loc.compilerLogParse),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _paste,
                icon: const Icon(Icons.content_paste, size: 18),
                label: Text(loc.compilerLogPaste),
              ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ),
          if (r != null) ...[
            const SizedBox(height: 12),
            Text(
              loc.compilerLogSummary('${r.errors}', '${r.warnings}'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            if (r.entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(loc.compilerLogEmpty,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor)),
              )
            else
              for (final e in r.entries) _entryCard(theme, loc, e),
          ],
        ],
      ),
    );
  }

  Widget _entryCard(ThemeData theme, AppLocalizations loc, CompilerLogEntry e) {
    final color = switch (e.severity) {
      CompilerSeverity.error => Colors.red,
      CompilerSeverity.warning => Colors.orange,
      CompilerSeverity.note => Colors.blueGrey,
    };
    final canJump = e.line != null && _isSameFile(e.file);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (canJump) {
            Navigator.of(context).pop(e);
            return;
          }
          Clipboard.setData(ClipboardData(text: e.position));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${e.position}  ${loc.copied}')),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 34,
                margin: const EdgeInsets.only(right: 10, top: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.position,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: theme.hintColor,
                            ),
                          ),
                        ),
                        if (canJump)
                          Text(loc.compilerLogJump,
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.primary)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(e.message,
                        style: const TextStyle(fontSize: 13, height: 1.4)),
                    if (e.original.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          e.original,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.35,
                            color: theme.hintColor,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    if (e.detail.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          e.detail.trimRight(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.35,
                            color: theme.hintColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
