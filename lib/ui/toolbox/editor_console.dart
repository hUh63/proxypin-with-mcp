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
// 控制台按**后端**分派，而不是按语言写死：
//   * JavaScript / TypeScript → 内置 QuickJS 真执行（console 捕获、Promise、超时）；
//   * 任意语言 → 通用表达式求值器（[ExprEval]），能算数、比大小、拼字符串、调
//     abs/min/round/len 之类函数。这样 C#/Java/Python/Go… 的编辑器也有一个能用的
//     控制台，而不是一句「不支持」。
// 静态检查对所有语言生效（含 HTML 标签、Markdown 围栏、Shell 的 if/fi 配对……），
// 面板里能过滤级别、逐条跳转、单条或全部修复。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/code_lint.dart';
import 'package:proxypin/utils/expr_eval.dart';

/// 底部面板的两个页签。
enum EditorConsoleTab { problems, console }

/// 控制台后端。
enum ConsoleBackend {
  /// 内置 JS 引擎（只有 JS/TS 页面有）。
  js,

  /// 通用表达式求值（任何语言都能用）。
  expr,
}

/// 控制台一行输出。
class _Out {
  final String text;
  final Color? color;
  final bool prompt;
  const _Out(this.text, {this.color, this.prompt = false});
}

/// 编辑器底部的「问题 / 控制台」面板。
class EditorConsolePanel extends StatefulWidget {
  final LintReport? report;
  final bool checking;
  final String language;
  final String? langKey;

  /// 是否有可用的 JS 引擎（当前语言是 JavaScript / TypeScript）。
  final bool jsBackend;

  /// 取当前文档全文。
  final String Function() readDocument;

  /// 取当前选区文本（控制台里的 `$0`）。
  final String Function()? readSelection;

  final void Function(LintDiagnostic) onJump;
  final void Function(LintDiagnostic) onFix;
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
    this.readSelection,
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
  late ConsoleBackend _backend = widget.jsBackend ? ConsoleBackend.js : ConsoleBackend.expr;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Out> _out = <_Out>[];
  final List<String> _history = <String>[];
  int _historyCursor = -1;
  JavascriptRuntime? _rt;
  bool _running = false;

  /// 0=全部 1=仅错误 2=错误+警告
  int _filter = 0;
  int _cursor = 0;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void didUpdateWidget(covariant EditorConsolePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      setState(() => _tab = widget.initialTab);
    }
    if (!widget.jsBackend && _backend == ConsoleBackend.js) {
      _backend = ConsoleBackend.expr;
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

  // ------------------------------ 问题列表 ------------------------------

  List<LintDiagnostic> get _visible {
    final all = widget.report?.diagnostics ?? const <LintDiagnostic>[];
    switch (_filter) {
      case 1:
        return all.where((d) => d.severity == LintSeverity.error).toList(growable: false);
      case 2:
        return all.where((d) => d.severity != LintSeverity.info).toList(growable: false);
      default:
        return all;
    }
  }

  void _goIssue(bool forward) {
    final list = _visible;
    if (list.isEmpty) return;
    var next = _cursor + (forward ? 1 : -1);
    if (next < 0) next = list.length - 1;
    if (next >= list.length) next = 0;
    setState(() => _cursor = next);
    widget.onJump(list[next]);
  }

  // ------------------------------ 控制台 ------------------------------

  JavascriptRuntime? _ensureRuntime() {
    if (_backend != ConsoleBackend.js) return null;
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

  /// 把 `$0` 换成当前选区（JS 后端注入变量，表达式后端直接写字符串字面量）。
  String _withSelection(String source) {
    final selection = widget.readSelection?.call() ?? '';
    if (_backend == ConsoleBackend.expr) {
      return source.replaceAll(r'$0', jsonEncode(selection));
    }
    return source;
  }

  Future<void> _run(String code, {bool echo = true}) async {
    final source = code.trim();
    if (source.isEmpty || _running) return;
    if (echo) {
      _append('> $source', Colors.grey, true);
      if (_history.isEmpty || _history.last != source) {
        _history.add(source);
        if (_history.length > 50) _history.removeAt(0);
      }
      _historyCursor = -1;
    }
    setState(() => _running = true);
    try {
      if (_backend == ConsoleBackend.expr) {
        final result = ExprEval.evaluate(_withSelection(source));
        if (result.isError) {
          _append(result.error!, Colors.red);
        } else {
          _append('=> ${ExprEval.format(result.value)}', Theme.of(context).colorScheme.primary);
        }
        return;
      }

      final rt = _ensureRuntime();
      if (rt == null) return;
      final selection = widget.readSelection?.call() ?? '';
      if (selection.isNotEmpty) {
        try {
          rt.evaluate('globalThis.\$0 = ${jsonEncode(selection)}');
        } catch (_) {
          // 注入失败不影响用户自己的表达式
        }
      }
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

  void _recallHistory(bool forward) {
    if (_history.isEmpty) return;
    var next = _historyCursor + (forward ? -1 : 1);
    if (next < -1) next = _history.length - 1;
    if (next >= _history.length) next = -1;
    _historyCursor = next;
    _input.text = next < 0 ? '' : _history[next];
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
  }

  // ------------------------------ UI ------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 232,
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
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

    return SizedBox(
      height: 34,
      child: Row(children: [
        tab(localizations.editorLintIssues, EditorConsoleTab.problems,
            problems > 0 ? '$problems' : null, badgeColor),
        tab(localizations.editorConsole, EditorConsoleTab.console, null, null),
        const Spacer(),
        if (_tab == EditorConsoleTab.problems) ...[
          _filterButton(),
          IconButton(
            tooltip: localizations.editorLintPrev,
            onPressed: _visible.isEmpty ? null : () => _goIssue(false),
            icon: const Icon(Icons.keyboard_arrow_up, size: 17),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: localizations.editorLintNext,
            onPressed: _visible.isEmpty ? null : () => _goIssue(true),
            icon: const Icon(Icons.keyboard_arrow_down, size: 17),
            visualDensity: VisualDensity.compact,
          ),
          if ((report?.fixableCount ?? 0) > 0)
            IconButton(
              tooltip: localizations.editorLintFixAll,
              onPressed: widget.onFixAll,
              icon: const Icon(Icons.auto_fix_high, size: 16),
              visualDensity: VisualDensity.compact,
            ),
        ],
        IconButton(
          onPressed: widget.onClose,
          tooltip: localizations.close,
          icon: const Icon(Icons.close, size: 16),
          visualDensity: VisualDensity.compact,
        ),
      ]),
    );
  }

  Widget _filterButton() {
    final label = switch (_filter) {
      1 => localizations.editorLintFilterErrors,
      2 => localizations.editorLintFilterWarnings,
      _ => localizations.editorLintFilterAll,
    };
    return TextButton(
      onPressed: () => setState(() => _filter = (_filter + 1) % 3),
      style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 28)),
      child: Text(label, style: const TextStyle(fontSize: 10.5)),
    );
  }

  Widget _problems(ThemeData theme) {
    final report = widget.report;
    if (widget.checking) {
      return _hint(localizations.editorLintChecking, theme);
    }
    if (report == null) return _hint(localizations.editorLintIssues, theme);
    if (report.skipped) return _hint(localizations.editorLintSkipped, theme);
    final list = _visible;
    if (report.isEmpty) {
      return Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_outline, size: 15, color: Colors.green),
          const SizedBox(width: 6),
          Text(localizations.editorLintClean, style: const TextStyle(fontSize: 12)),
        ]),
      );
    }
    if (list.isEmpty) return _hint(localizations.editorLintFilteredEmpty, theme);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final d = list[i];
        final color = switch (d.severity) {
          LintSeverity.error => Colors.red,
          LintSeverity.warning => Colors.orange,
          LintSeverity.info => Colors.blueGrey,
        };
        final icon = switch (d.severity) {
          LintSeverity.error => Icons.error_outline,
          LintSeverity.warning => Icons.warning_amber_outlined,
          LintSeverity.info => Icons.info_outline,
        };
        return InkWell(
          onTap: () {
            _cursor = i;
            widget.onJump(d);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Icon(icon, size: 14, color: color),
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
    final backends = <ConsoleBackend>[
      if (widget.jsBackend) ConsoleBackend.js,
      ConsoleBackend.expr,
    ];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 8, 0),
        child: Row(children: [
          Icon(_backend == ConsoleBackend.js ? Icons.bolt : Icons.functions,
              size: 12, color: _backend == ConsoleBackend.js ? Colors.green : Colors.blueGrey),
          const SizedBox(width: 4),
          Text('${localizations.editorConsoleBackend}:', style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 4),
          DropdownButton<ConsoleBackend>(
            value: _backend,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: TextStyle(fontSize: 10.5, color: theme.textTheme.bodySmall?.color),
            items: backends
                .map((b) => DropdownMenuItem(
                    value: b,
                    child: Text(b == ConsoleBackend.js ? 'JavaScript' : localizations.editorConsoleExpr)))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _backend = v;
                _out.clear();
              });
            },
          ),
          const Spacer(),
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _backend == ConsoleBackend.js
                        ? localizations.editorConsoleHint
                        : localizations.editorConsoleExprHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color),
                  ),
                ),
              )
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
            tooltip: localizations.editorConsoleHistory,
            onPressed: () => _recallHistory(false),
            icon: const Icon(Icons.history, size: 16),
            visualDensity: VisualDensity.compact,
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
