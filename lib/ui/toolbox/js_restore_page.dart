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

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/js_deobfuscator.dart';
import 'package:proxypin/network/util/logger.dart';

/// JS 还原（内置 jsrestore）：把混淆的 JS 反混淆 / 反编译成可读代码。
///
/// 全程离线执行（acorn + jsrestore 都以 assets 打入，用内置 JS 引擎运行），
/// 不联网、不上传代码、也不执行被分析的代码本身。
class JsRestorePage extends StatefulWidget {
  const JsRestorePage({super.key});

  @override
  State<JsRestorePage> createState() => _JsRestorePageState();
}

class _JsRestorePageState extends State<JsRestorePage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _outputScroll = ScrollController();
  final ScrollController _logScroll = ScrollController();

  bool _running = false;
  String _output = '';
  List<String> _logs = [];
  bool _showLogs = false;
  String _lastAction = '';
  String? _inputFileName;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void dispose() {
    _inputController.dispose();
    _outputScroll.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      if (mounted) FlutterToastr.show(localizations.jsRestoreClipboardEmpty, context);
      return;
    }
    setState(() {
      _inputController.text = text;
      _inputFileName = null;
    });
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['js', 'txt', 'mjs']);
      if (result == null || result.isEmpty) return;
      final file = result.single;
      final content = await file.xFile.readAsString();
      if (!mounted) return;
      setState(() {
        _inputController.text = content;
        _inputFileName = file.name;
      });
    } catch (e, t) {
      logger.e('读取 JS 文件失败', error: e, stackTrace: t);
      if (mounted) FlutterToastr.show(localizations.jsRestoreLoadFailed, context);
    }
  }

  Future<void> _run(String action, {String command = 'restore'}) async {
    final code = _inputController.text;
    if (code.trim().isEmpty) {
      FlutterToastr.show(localizations.jsRestoreEmptyInput, context);
      return;
    }
    setState(() {
      _running = true;
      _lastAction = action;
      _output = '';
      _logs = [];
    });

    try {
      // 让 loading 先绘制出来（evaluate 是同步的，会阻塞一会儿）
      await Future.delayed(const Duration(milliseconds: 80));

      // 纯格式化：只做排版美化，不做任何反混淆
      if (command == 'beautify') {
        final pretty = await JsDeobfuscator.beautify(code);
        if (!mounted) return;
        setState(() {
          _running = false;
          _output = pretty;
          _logs = ['${localizations.jsRestoreBeautify}: ${code.length} → ${pretty.length}'];
          _showLogs = false;
        });
        return;
      }

      final result = await JsDeobfuscator.run(command, code);
      if (!mounted) return;
      setState(() {
        _running = false;
        _output = result.output;
        _logs = result.logs;
        _showLogs = result.output.isEmpty || !result.ok;
      });
      if (!result.ok && result.output.isEmpty) {
        FlutterToastr.show(localizations.jsRestoreFailed, context);
      }
    } catch (e, t) {
      logger.e('JS 还原失败', error: e, stackTrace: t);
      if (!mounted) return;
      setState(() {
        _running = false;
        _logs = ['${localizations.jsRestoreInitFailed}: $e'];
        _showLogs = true;
      });
    }
  }

  Future<void> _copyOutput() async {
    if (_output.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _output));
    if (mounted) FlutterToastr.show(localizations.jsRestoreCopied, context);
  }

  Future<void> _saveOutput() async {
    if (_output.isEmpty) return;
    try {
      final base = (_inputFileName ?? 'input.js').replaceAll(RegExp(r'\.(js|txt|mjs)$'), '');
      final Uri? path = await FilePicker.saveFile(
        fileName: '$base.restored.js',
        bytes: utf8.encode(_output),
      );
      if (path == null) return;
      if (mounted) FlutterToastr.show(localizations.jsRestoreSaveSuccess, context);
    } catch (e, t) {
      logger.e('保存还原结果失败', error: e, stackTrace: t);
      if (mounted) FlutterToastr.show('${localizations.jsRestoreSaveFailed} $e', context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.jsRestore),
        actions: [
          if (_output.isNotEmpty) ...[
            IconButton(
              tooltip: localizations.jsRestoreCopy,
              onPressed: _copyOutput,
              icon: const Icon(Icons.copy_all_outlined, size: 20),
            ),
            IconButton(
              tooltip: localizations.jsRestoreSave,
              onPressed: _saveOutput,
              icon: const Icon(Icons.save_alt_outlined, size: 20),
            ),
          ],
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          _buildTips(),
          _buildInputArea(cs),
          _buildActionBar(cs),
          Expanded(child: _buildOutputArea(cs)),
        ],
      ),
    );
  }

  Widget _buildTips() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: cs.primary.withValues(alpha: 0.05),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 15, color: cs.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              localizations.jsRestoreTips,
              style: TextStyle(fontSize: 11.5, height: 1.35, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(localizations.jsRestoreInput,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              if (_inputFileName != null)
                Expanded(
                  child: Text(_inputFileName!,
                      style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
          // 操作按钮单独一行自动换行，窄屏不再挤在标题右侧导致溢出
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _running ? null : _paste,
                icon: const Icon(Icons.content_paste_go, size: 16),
                label: Text(localizations.jsRestorePaste, style: const TextStyle(fontSize: 12)),
              ),
              TextButton.icon(
                onPressed: _running ? null : _pickFile,
                icon: const Icon(Icons.folder_open, size: 16),
                label: Text(localizations.jsRestorePickFile, style: const TextStyle(fontSize: 12)),
              ),
              if (_inputController.text.isNotEmpty)
                IconButton(
                  tooltip: localizations.jsRestoreClear,
                  visualDensity: VisualDensity.compact,
                  onPressed: _running
                      ? null
                      : () => setState(() {
                            _inputController.clear();
                            _inputFileName = null;
                            _output = '';
                            _logs = [];
                          }),
                  icon: const Icon(Icons.backspace_outlined, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _inputController,
            minLines: 5,
            maxLines: 8,
            style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: localizations.jsRestoreInputHint,
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding: const EdgeInsets.all(10),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      // 4 个动作按钮 + 日志按钮在窄屏放不下一行，改为自动换行，避免溢出
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: _running ? null : () => _run(localizations.jsRestoreRestore, command: 'restore'),
            icon: _running && _lastAction == localizations.jsRestoreRestore
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_fix_high, size: 17),
            label: Text(localizations.jsRestoreRestore),
          ),
          OutlinedButton.icon(
            onPressed: _running ? null : () => _run(localizations.jsRestoreBeautify, command: 'beautify'),
            icon: const Icon(Icons.format_align_left, size: 17),
            label: Text(localizations.jsRestoreBeautify),
          ),
          OutlinedButton.icon(
            onPressed: _running ? null : () => _run(localizations.jsRestoreDetect, command: 'detect'),
            icon: const Icon(Icons.fingerprint, size: 17),
            label: Text(localizations.jsRestoreDetect),
          ),
          OutlinedButton.icon(
            onPressed: _running ? null : () => _run(localizations.jsRestoreVerify, command: 'verify'),
            icon: const Icon(Icons.fact_check_outlined, size: 17),
            label: Text(localizations.jsRestoreVerify),
          ),
          if (_logs.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() => _showLogs = !_showLogs),
              icon: Icon(_showLogs ? Icons.expand_more : Icons.chevron_right, size: 18),
              label: Text(localizations.jsRestoreLogs, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildOutputArea(ColorScheme cs) {
    if (_running) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(localizations.jsRestoreRunning, style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }

    if (_showLogs && _logs.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Scrollbar(
          controller: _logScroll,
          child: SingleChildScrollView(
            controller: _logScroll,
            child: SelectableText(
              _logs.join('\n'),
              style: const TextStyle(fontSize: 11.5, height: 1.4, fontFamily: 'monospace'),
            ),
          ),
        ),
      );
    }

    if (_output.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_fix_high_outlined, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 10),
            Text(localizations.jsRestoreNoOutput, style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Scrollbar(
        controller: _outputScroll,
        child: SingleChildScrollView(
          controller: _outputScroll,
          padding: const EdgeInsets.all(10),
          child: SelectableText(
            _output,
            style: const TextStyle(fontSize: 12, height: 1.45, fontFamily: 'monospace'),
          ),
        ),
      ),
    );
  }
}
