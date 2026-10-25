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

// 编辑器底部的「问题 / 控制台」面板。
//
// 为什么控制台只对 JavaScript 生效：手机上唯一能真跑起来的是内置的 QuickJS 引擎，
// 其它语言（C#/Java/Python…）没有本地运行时，硬造一个「假执行」比不给更糟。
// 所以控制台按**运行后端**分派——JS 走真引擎，其它语言显示当前语言的静态检查结果，
// 并明确告诉用户「切到 JavaScript 才能执行代码」。这也正好回答了「多语法怎么设置」：
// 语法检查按语言画像分派（见 [CodeLint.profileOf]），执行能力按后端分派。
//
// 本文件只依赖 code_lint 与 flutter_js，不碰编辑器内核。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/code_lint.dart';

/// 底部面板的两个页签。
enum EditorConsoleTab { problems, console }

/// 控制台一行输出。
class _Out {
  final String text;
  final Color? color;
  final bool prompt;
  const _Out(this.text, {this.color, this.prompt = false});
}

/// 编辑器底部的「问题 / 控制台」面板。
class EditorConsolePanel extends StatefulWidget {
  /// 最近一次检查结果（null 表示还没跑过）。
  final LintReport? report;

  /// 正在检查。
  final bool checking;

  /// 当前语言展示名与 key（用于提示行）。
  final String language;
  final String? langKey;

  /// 是否有可用的 JS 后端（当前语言是 JavaScript / TypeScript）。
  final bool jsBackend;

  /// 取当前文档全文（「运行文档」用）。
  final String Function() readDocument;

  /// 点击问题行 → 跳到该位置。
  final void Function(LintDiagnostic) onJump;

  /// 修复单条。
  final void Function(LintDiagnostic) onFix;

  /// 修复全部可自动修的问题。
  final VoidCallback? onFixAll;

  final VoidCallback onClose;

  final EditorConsoleTab initialTab;

  const EditorConsolePanel({
    super.key,
    required this.report,
    required this.checking,
    required this.language,
    required this.langKey,
    required this.jsBackend,
    required this.readDocument,
    required this.onJump,
    required this.onFix,
    this.onFixAll,
    required this.onClose,
    this.initialTab = EditorConsoleTab.problems,
  });

  @override
  State<EditorConsolePanel> createState() => _EditorConsolePanelState();
}

class _EditorConsolePanelState extends State<EditorConsolePanel> {
  late EditorConsoleTab _tab = widget.initialTab;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Out> _out = <_Out>[];
  JavascriptRuntime? _rt;
  bool _running = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void didUpdateWidget(covariant EditorConsolePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      setState(() => _tab = widget.initialTab);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _rt?.dispose();
    _rt = null;
    super.dispose();
  }

  // ------------------------------ JS 后端 ------------------------------

  JavascriptRuntime? _ensureRuntime() {
    if (!widget.jsBackend) return null;
    final rt = _rt;
    if (rt != null) return rt;
    try {
      final created = getJavascriptRuntime(xhr: false);
      final callbacks = JavascriptRuntime.channelFunctionsRegistered[created.getEngineInstanceId()];
      callbacks?["ConsoleLog"] = _onConsoleLog;
      _rt = created;
      return created;
    } catch (e) {
      _append('$e', Colors.red);
      return null;
    }
  }

  dynamic _onConsoleLog(dynamic args) {
    if (!mounted) return null;
    try {
      final list = args as List<dynamic>;
      final level = list.isEmpty ? 'log' : '${list.removeAt(0)}';
      final text = list.map((e) => '$e').join(' ');
      _append(text, level == 'error' ? Colors.red : (level == 'warn' ? Colors.orange : null));
    } catch (e) {
      _append('$e', Colors.red);
    }
    return null;
  }

  void _append(String text, [Color? color, bool prompt = false]) {
    if (!mounted) return;
    setState(() {
      _out.add(_Out(text, color: color, prompt: prompt));
      // 一直 log 的脚本会把内存吃光：只保留最近 500 行。
      if (_out.length > 500) _out.removeRange(0, _out.length - 500);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _run(String code, {bool echo = true}) async {
    final source = code.trim();
    if (source.isEmpty || _running) return;
    final rt = _ensureRuntime();
    if (rt == null) return;
    if (echo) _append('> $source', Colors.grey, true);
    setState(() => _running = true);
    try {
      var result = await rt.evaluateAsync(source).timeout(const Duration(seconds: 10));
      if (result.isPromise || result.rawResult is Future) {
        result = await rt.handlePromise(result).timeout(const Duration(seconds: 10));
      }
      if (!mounted) return;
      if (result.isError) {
        _append(result.stringResult ?? localizations.editorConsoleError, Colors.red);
      } else {
        final value = result.stringResult;
        if (value != null && value.isNotEmpty && value != 'undefined' && value != 'null') {
          _append('=> $value', Theme.of(context).colorScheme.primary);
        }
      }
    } catch (e) {
      _append('$e', Colors.red);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  // ------------------------------ UI ------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 216,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.6)),
      ),
      child: Column(children: [
        _header(theme),
        Expanded(child: _tab == EditorConsoleTab.problems ? _problems(theme) : _console(theme)),
      ]),
    );
  }

  Widget _header(ThemeData theme) {
    final report = widget.report;
    final problems = report?.diagnostics.length ?? 0;
    final primary = theme.colorScheme.primary;
    Widget tab(String label, EditorConsoleTab value, String? badgeText, Color? badgeColor) {
      final active = _tab == value;
      return InkWell(
        onTap: () => setState(() => _tab = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: active ? primary : Colors.transparent, width: 2)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active ? primary : theme.textTheme.bodySmall?.color)),
            if (badgeText != null && badgeColor != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(8)),
                child: Text(badgeText, style: const TextStyle(fontSize: 9, color: Colors.white)),
              ),
            ],
          ]),
        ),
      );
    }

    Color? badgeColor;
    switch (report?.worst) {
      case LintSeverity.error:
        badgeColor = Colors.red;
        break;
      case LintSeverity.warning:
        badgeColor = Colors.orange;
        break;
      case LintSeverity.info:
        badgeColor = Colors.blueGrey;
        break;
      case null:
        badgeColor = null;
        break;
    }

    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 2, right: 2),
      child: Row(children: [
        tab(localizations.editorLintIssues, EditorConsoleTab.problems,
            problems > 0 ? '$problems' : null, badgeColor),
        tab(localizations.editorConsole, EditorConsoleTab.console, null, null),
        const Spacer(),
        if (_tab == EditorConsoleTab.problems && (report?.fixableCount ?? 0) > 0)
          TextButton.icon(
            onPressed: widget.onFixAll,
            icon: const Icon(Icons.auto_fix_high, size: 14),
            label: Text(localizations.editorLintFixAll, style: const TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 28)),
          ),
        IconButton(
          onPressed: widget.onClose,
          tooltip: localizations.close,
          icon: const Icon(Icons.close, size: 16),
          visualDensity: VisualDensity.compact,
        ),
      ]),
    );
  }

  Widget _problems(ThemeData theme) {
    final report = widget.report;
    if (widget.checking) {
      return Center(
          child: Text(localizations.editorLintChecking,
              style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color)));
    }
    if (report == null) return _hint(localizations.editorLintIssues, theme);
    if (report.skipped) return _hint(localizations.editorLintSkipped, theme);
    if (report.isEmpty) {
      return Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_outline, size: 15, color: Colors.green),
          const SizedBox(width: 6),
          Text(localizations.editorLintClean, style: const TextStyle(fontSize: 12)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: report.diagnostics.length,
      itemBuilder: (context, i) {
        final d = report.diagnostics[i];
        final color = d.severity == LintSeverity.error
            ? Colors.red
            : d.severity == LintSeverity.warning
                ? Colors.orange
                : Colors.blueGrey;
        return InkWell(
          onTap: () => widget.onJump(d),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Icon(
                  d.severity == LintSeverity.error
                      ? Icons.error_outline
                      : d.severity == LintSeverity.warning
                          ? Icons.warning_amber_outlined
                          : Icons.info_outline,
                  size: 14,
                  color: color),
              const SizedBox(width: 6),
              Text('${d.line}:${d.column}', style: const TextStyle(fontSize: 10.5)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(d.suggestion == null ? d.message : '${d.message} · ${d.suggestion}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5)),
              ),
              if (d.fixable)
                TextButton(
                  onPressed: () => widget.onFix(d),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 26)),
                  child: Text(localizations.editorLintFix, style: const TextStyle(fontSize: 11)),
                ),
            ]),
          ),
        );
      },
    );
  }

  Widget _console(ThemeData theme) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
        child: Row(children: [
          Icon(widget.jsBackend ? Icons.bolt : Icons.info_outline,
              size: 12, color: widget.jsBackend ? Colors.green : Colors.orange),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              widget.jsBackend
                  ? '${localizations.editorConsoleBackend}: JavaScript'
                  : localizations.editorConsoleNoRuntime,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: theme.textTheme.bodySmall?.color),
            ),
          ),
          if (_out.isNotEmpty)
            InkWell(
              onTap: () => setState(_out.clear),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(localizations.editorConsoleClear,
                    style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
              ),
            ),
        ]),
      ),
      Expanded(
        child: _out.isEmpty
            ? Center(
                child: Text(localizations.editorConsoleHint,
                    style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color)))
            : Scrollbar(
                controller: _scroll,
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  itemCount: _out.length,
                  itemBuilder: (context, i) {
                    final o = _out[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text(o.text,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                              color: o.color,
                              fontWeight: o.prompt ? FontWeight.w600 : FontWeight.w400)),
                    );
                  },
                ),
              ),
      ),
      if (widget.jsBackend)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
          child: Row(children: [
            Expanded(
              child: SizedBox(
                height: 34,
                child: TextField(
                  controller: _input,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: localizations.editorConsoleInputHint,
                    hintStyle: const TextStyle(fontSize: 12),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (value) {
                    unawaited(_run(value));
                    _input.clear();
                  },
                ),
              ),
            ),
            IconButton(
              tooltip: localizations.editorConsoleRunDocument,
              onPressed: () => unawaited(_run(widget.readDocument(), echo: true)),
              icon: const Icon(Icons.play_circle_outline, size: 18),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: localizations.editorConsoleRun,
              onPressed: _running
                  ? null
                  : () {
                      final value = _input.text;
                      _input.clear();
                      unawaited(_run(value));
                    },
              icon: _running
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow, size: 18),
              visualDensity: VisualDensity.compact,
            ),
          ]),
        ),
    ]);
  }

  Widget _hint(String text, ThemeData theme) {
    return Center(
        child: Text(text, style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color)));
  }
}
