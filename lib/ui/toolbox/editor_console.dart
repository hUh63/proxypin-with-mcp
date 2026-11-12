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
import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/code_lint.dart';
import 'package:proxypin/ui/toolbox/console_state.dart';
import 'package:proxypin/utils/expr_eval.dart';
import 'package:proxypin/utils/js_debug.dart';

/// 底部面板的两个页签。
enum EditorConsoleTab { problems, console, debug }

/// 控制台后端。
enum ConsoleBackend {
  /// 内置 JS 引擎（只有 JS/TS 页面有）。
  js,

  /// 通用表达式求值（任何语言都能用）。
  expr,
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

  /// 断点行（0-based，跟编辑器行号栏一致）。
  final Set<int> breakpoints;

  /// 断点变更（调试页里增删时回写，让行号栏的红点跟着变）。
  final ValueChanged<Set<int>>? onBreakpointsChanged;

  /// 从调试页跳到某一行。
  final ValueChanged<int>? onJumpToLine;

  final void Function(LintDiagnostic) onJump;
  final void Function(LintDiagnostic) onFix;
  final VoidCallback? onFixAll;
  final VoidCallback onClose;

  final EditorConsoleTab initialTab;

  /// 当前语言是不是「编程语言」。非编程语言（JSON / YAML / Markdown / 纯文本…）
  /// 不给控制台入口 —— 它们没有运行时概念，给个能算表达式的框只会让人困惑。
  final bool programming;

  /// 被关掉的规则（不产出诊断）。
  final Set<String> disabledRules;

  /// 被问题栏关掉的严重程度（两边共用同一份状态，和 VS 的筛选一致）。
  final Set<LintSeverity> hiddenSeverities;

  /// 打开规则开关面板。
  final VoidCallback? onOpenRules;

  /// 把一段文本插入到编辑器（控制台的「插入」）。
  final ValueChanged<String>? onInsertText;

  /// 控制台状态。由文档持有，所以收起面板 / 切走文档再回来，
  /// 输出、命令历史、定义过的变量都还在。
  final ConsoleState state;

  /// 面板初始高度（来自偏好；用户拖过之后会记住）。
  final double? initialHeight;

  /// 拖拽结束时的回调（只在结束时上报，拖动过程不落盘）。
  final ValueChanged<double>? onHeightChanged;

  const EditorConsolePanel({
    super.key,
    required this.report,
    required this.checking,
    required this.language,
    required this.langKey,
    required this.jsBackend,
    required this.readDocument,
    this.readSelection,
    this.breakpoints = const <int>{},
    this.onBreakpointsChanged,
    this.onJumpToLine,
    required this.onJump,
    required this.onFix,
    this.onFixAll,
    required this.onClose,
    this.initialTab = EditorConsoleTab.problems,
    this.hiddenSeverities = const <LintSeverity>{},
    this.programming = false,
    this.disabledRules = const <String>{},
    this.onOpenRules,
    this.onInsertText,
    required this.state,
    this.initialHeight,
    this.onHeightChanged,
  });

  @override
  State<EditorConsolePanel> createState() => _EditorConsolePanelState();
}

class _EditorConsolePanelState extends State<EditorConsolePanel> {
  late EditorConsoleTab _tab = _initialTabOf(widget);

  static EditorConsoleTab _initialTabOf(EditorConsolePanel w) {
    if (!w.programming) return EditorConsoleTab.problems;
    // 非 JS 语言没有调试页签，别把 _tab 设到一个显示不出来的值上。
    if (w.initialTab == EditorConsoleTab.debug && !w.jsBackend) {
      return EditorConsoleTab.console;
    }
    return w.initialTab;
  }
  late ConsoleBackend _backend = widget.jsBackend ? ConsoleBackend.js : ConsoleBackend.expr;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  JavascriptRuntime? _rt;
  bool _running = false;

  /// 多行输入模式（终端里写 for/if 这种多语句时用；Enter 换行，▶ 才执行）。
  bool _multiline = false;

  /// JS 侧的 stdin 预置（readLine/readInt/print）只装一次。
  bool _preludeReady = false;

  // ── JS 调试（行级断点）──
  /// 当前停在第几行（1-based，0 表示没停住）。
  int _debugLine = 0;
  /// 「继续」时要给这一行加一次「跳过」——引擎没法从异常点恢复，只能重跑。
  int _debugSkipLine = 0;

  /// 控制台状态（输出 / 命令历史 / 会话变量）——由文档持有。
  ConsoleState get _state => widget.state;

  List<ConsoleLine> get _out => _state.lines;

  /// 0=全部 1=仅错误 2=错误+警告
  int _filter = 0;
  int _cursor = 0;

  /// 问题列表的搜索词（VS「错误列表」顶部那行搜索）。
  String _search = '';
  final TextEditingController _searchInput = TextEditingController();

  /// 按规则过滤（点顶部统计 chip 切换）。
  String? _ruleFilter;

  /// 面板高度（顶部有拖拽条可调）。手机上控制台一开就吃掉大半屏，
  /// 固定 232dp 时想看下面几行代码只能关掉面板。
  late double _height = widget.initialHeight ?? 232;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void didUpdateWidget(covariant EditorConsolePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换文档/换语言后，按规则过滤就不该留着了（那些规则可能已经不存在）。
    if (oldWidget.language != widget.language && _ruleFilter != null) {
      _ruleFilter = null;
    }
    if (oldWidget.initialTab != widget.initialTab) {
      setState(() => _tab = _initialTabOf(widget));
    }
    if (!widget.jsBackend && _backend == ConsoleBackend.js) {
      _backend = ConsoleBackend.expr;
    }
    // 语言从编程语言切到数据格式（例如 .json）：控制台页签直接收起。
    if (!widget.programming &&
        (_tab == EditorConsoleTab.console || _tab == EditorConsoleTab.debug)) {
      _tab = EditorConsoleTab.problems;
    }
    if (!widget.jsBackend && _tab == EditorConsoleTab.debug) {
      _tab = EditorConsoleTab.console;
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _searchInput.dispose();
    _scroll.dispose();
    _dbgScroll.dispose();
    _rt?.dispose();
    _rt = null;
    super.dispose();
  }

  // ------------------------------ 问题列表 ------------------------------

  List<LintDiagnostic> get _visible {
    final all = widget.report?.diagnostics ?? const <LintDiagnostic>[];
    final filtered = switch (_filter) {
      1 => all.where((d) => d.severity == LintSeverity.error).toList(growable: false),
      2 => all.where((d) => d.severity != LintSeverity.info).toList(growable: false),
      _ => all,
    };
    var visible = widget.hiddenSeverities.isEmpty
        ? filtered
        : filtered.where((d) => !widget.hiddenSeverities.contains(d.severity)).toList(growable: false);
    final rule = _ruleFilter;
    if (rule != null) {
      visible = visible.where((d) => d.code == rule).toList(growable: false);
    }
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return visible;
    return visible
        .where((d) =>
            d.message.toLowerCase().contains(q) || d.code.toLowerCase().contains(q))
        .toList(growable: false);
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

  // ------------------------------ JS 调试 ------------------------------

  final ScrollController _dbgScroll = ScrollController();

  Widget _debug(ThemeData theme) {
    final bps = widget.breakpoints.toList()..sort();
    final paused = _debugLine > 0;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 4, 0),
        child: Row(children: [
          Icon(Icons.bug_report_outlined,
              size: 13, color: paused ? Colors.orange : Colors.blueGrey),
          const SizedBox(width: 4),
          Text(
            paused ? localizations.editorDebugPausedAt(_debugLine) : localizations.editorDebugTitle,
            style: TextStyle(fontSize: 10.5, color: paused ? Colors.orange : null),
          ),
          const Spacer(),
          _barIcon(
            tooltip: localizations.editorDebugRun,
            onPressed: _running ? null : () => unawaited(_debugRun()),
            icon: const Icon(Icons.play_arrow, size: 18),
          ),
          _barIcon(
            tooltip: localizations.editorDebugContinue,
            onPressed: paused && !_running ? () => unawaited(_debugRun(resume: true)) : null,
            icon: const Icon(Icons.skip_next, size: 17),
          ),
          _barIcon(
            tooltip: localizations.editorDebugRunTests,
            onPressed: _running ? null : () => unawaited(_runTests()),
            icon: const Icon(Icons.science_outlined, size: 17),
          ),
          _barIcon(
            tooltip: localizations.editorDebugStop,
            onPressed: (paused || _running) ? _debugStop : null,
            icon: const Icon(Icons.stop, size: 17),
          ),
          if (bps.isNotEmpty)
            _barIcon(
              tooltip: localizations.editorDebugClearBreakpoints,
              onPressed: () => widget.onBreakpointsChanged?.call(<int>{}),
              icon: const Icon(Icons.not_interested, size: 16),
            ),
          _barIcon(
            tooltip: localizations.editorConsoleClear,
            onPressed: () => setState(_state.reset),
            icon: const Icon(Icons.delete_outline, size: 16),
          ),
        ]),
      ),
      if (bps.isNotEmpty)
        SizedBox(
          height: 30,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            itemCount: bps.length,
            separatorBuilder: (_, __) => const SizedBox(width: 4),
            itemBuilder: (_, i) {
              final line = bps[i];
              return InputChip(
                label: Text('${line + 1}', style: const TextStyle(fontSize: 10.5)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onPressed: () => widget.onJumpToLine?.call(line),
                onDeleted: () {
                  final next = Set<int>.from(widget.breakpoints)..remove(line);
                  widget.onBreakpointsChanged?.call(next);
                },
              );
            },
          ),
        ),
      Expanded(child: _debugOutput(theme)),
    ]);
  }

  Widget _debugOutput(ThemeData theme) {
    if (_out.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            localizations.editorDebugHint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color),
          ),
        ),
      );
    }
    return SelectionArea(
      child: ListView.builder(
        controller: _dbgScroll,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
        itemCount: _out.length,
        itemBuilder: (_, i) {
          final o = _out[i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(
              o.text,
              style: TextStyle(
                fontSize: 11.5,
                fontFamily: 'monospace',
                color: _lineColor(theme, o.kind),
                fontWeight:
                    o.kind == ConsoleLineKind.prompt ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          );
        },
      ),
    );
  }

  /// 插桩后的代码必须还能被解析：不通过就退回原样整篇运行。
  ///
  /// 宁可少一个断点，也不能让用户按下调试之后看到的是自己脚本的 SyntaxError。
  bool _jsParses(JavascriptRuntime rt, String code) {
    try {
      final r = rt.evaluate(
          '(function(){try{new Function(${jsonEncode(code)});return "ok"}catch(e){return "err"}})()');
      return r.stringResult == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// 命中时把全局变量打出来（局部变量拿不到——引擎没有作用域内省）。
  void _appendSnapshot(JavascriptRuntime rt) {
    try {
      final r = rt.evaluate('(function(){var out=[];'
          'for(var k in globalThis){'
          'if(/^(__pp|console|print|readLine|readInt|readFloat|globalThis)/.test(k))continue;'
          'if(k.indexOf("__")===0)continue;'
          'var v=globalThis[k];var t=typeof v;if(t==="function")continue;'
          'var s;try{s=JSON.stringify(v)}catch(e){s=String(v)}'
          'if(s===undefined)continue;if(s&&s.length>160)s=s.slice(0,160)+"...";'
          'out.push(k+" = "+s)}'
          'return out.join("\\n")})()');
      final text = r.stringResult;
      if (text.trim().isEmpty) {
        _append(localizations.editorDebugNoVars, ConsoleLineKind.note);
        return;
      }
      for (final line in text.split('\n')) {
        if (line.trim().isEmpty) continue;
        _append(line, ConsoleLineKind.result);
      }
    } catch (_) {
      // 快照失败不影响调试本身
    }
  }

  Future<void> _debugRun({bool resume = false}) async {
    if (_running) return;
    final source = widget.readDocument();
    if (source.trim().isEmpty) return;
    final bps = widget.breakpoints;
    if (!resume) {
      setState(() {
        _debugLine = 0;
        _debugSkipLine = 0;
      });
    }
    if (bps.isEmpty) {
      _append(localizations.editorDebugNoBreakpoints, ConsoleLineKind.note);
      // 不要把整篇源码回显到输出里（几百行会把面板刷满）。
      await _run(source, echo: false);
      return;
    }
    if (_backend != ConsoleBackend.js) {
      _append(localizations.editorTermNoRuntime, ConsoleLineKind.warn);
      return;
    }
    if (source.length > 200000) {
      _append(localizations.editorTooLargeToProcess, ConsoleLineKind.warn);
      return;
    }
    setState(() => _running = true);
    try {
      final rt = _ensureRuntime();
      if (rt == null) {
        _append(localizations.editorTermNoRuntime, ConsoleLineKind.warn);
        return;
      }
      // 「继续」= 把刚才停下的那处断点记成跳过，然后从头重跑到下一个断点。
      // 引擎没法从异常点恢复，所以副作用（console 输出、外部调用）会重来一遍。
      if (!resume) {
        rt.evaluate('globalThis.__ppHits = {}; globalThis.__ppSkip = {};');
      } else if (_debugSkipLine > 0) {
        rt.evaluate('globalThis.__ppSkip[$_debugSkipLine] = '
            '(globalThis.__ppSkip[$_debugSkipLine]||0) + 1;');
      }
      rt.evaluate(JsDebug.prelude(bps));

      final instrumented = JsDebug.instrument(source);
      final useInstrumented = _jsParses(rt, instrumented);
      if (!useInstrumented) _append(localizations.editorDebugNoInstrument, ConsoleLineKind.warn);
      _append(
        '▶ ${localizations.editorDebugRunning}${resume ? ' (${localizations.editorDebugContinue})' : ''}',
        ConsoleLineKind.prompt,
      );

      final code = useInstrumented ? instrumented : source;
      final result = await rt.evaluateAsync(code).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (result.isError) {
        final line = JsDebug.breakLineFrom(result.stringResult);
        if (line != null) {
          setState(() {
            _debugLine = line;
            _debugSkipLine = line;
          });
          _append(localizations.editorDebugPausedAt(line), ConsoleLineKind.note);
          _appendSnapshot(rt);
        } else {
          setState(() {
            _debugLine = 0;
            _debugSkipLine = 0;
          });
          _append(result.stringResult, ConsoleLineKind.error);
        }
      } else {
        setState(() {
          _debugLine = 0;
          _debugSkipLine = 0;
        });
        _append(localizations.editorDebugFinished, ConsoleLineKind.note);
      }
    } catch (e) {
      _append('$e', ConsoleLineKind.error);
    } finally {
      if (mounted) {
        setState(() => _running = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_dbgScroll.hasClients) return;
          _dbgScroll.jumpTo(_dbgScroll.position.maxScrollExtent);
        });
      }
    }
  }

  /// 跑当前文件里的 `test(...)` / `it(...)` 用例。
  ///
  /// 用干净运行时：上一次调试/运行留下的变量不该影响用例。跑之前先装骨架
  /// （test / it / describe / expect），再 eval 用户代码完成注册，最后统一执行。
  Future<void> _runTests() async {
    if (_running) return;
    final src = widget.readDocument();
    final cases = JsDebug.collectTests(src);
    if (cases.isEmpty) {
      _append(localizations.editorDebugNoTests, ConsoleLineKind.note);
      return;
    }
    if (src.length > 200000) {
      _append(localizations.editorTooLargeToProcess, ConsoleLineKind.warn);
      return;
    }
    if (_backend != ConsoleBackend.js) {
      _append(localizations.editorTermNoRuntime, ConsoleLineKind.warn);
      return;
    }
    setState(() => _running = true);
    try {
      _resetRuntime();
      final rt = _ensureRuntime();
      if (rt == null) {
        _append(localizations.editorTermNoRuntime, ConsoleLineKind.warn);
        return;
      }
      rt.evaluate(JsDebug.testHarness);
      try {
        rt.evaluate(src);
      } catch (e) {
        _append('${localizations.editorDebugTestsLoadFailed}: $e', ConsoleLineKind.error);
        return;
      }
      final raw = rt.evaluate('globalThis.__ppRunCases()').stringResult;
      final list = jsonDecode(raw) as List<dynamic>;
      var pass = 0;
      var fail = 0;
      for (final item in list) {
        final row = item as List<dynamic>;
        final name = '${row[0]}';
        if (row[1] == true) {
          pass++;
          _append('✓ $name', ConsoleLineKind.result);
        } else {
          fail++;
          _append('✗ $name — ${row[2]}', ConsoleLineKind.error);
        }
      }
      _append(
        localizations.editorDebugTestsSummary(pass, fail),
        fail > 0 ? ConsoleLineKind.warn : ConsoleLineKind.note,
      );
    } catch (e) {
      _append('$e', ConsoleLineKind.error);
    } finally {
      if (mounted) {
        setState(() => _running = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_dbgScroll.hasClients) return;
          _dbgScroll.jumpTo(_dbgScroll.position.maxScrollExtent);
        });
      }
    }
  }

  void _debugStop() {
    setState(() {
      _debugLine = 0;
      _debugSkipLine = 0;
    });
    _append(localizations.editorDebugStopped, ConsoleLineKind.note);
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
      _installPrelude(created);
      return created;
    } catch (e) {
      _append('$e', ConsoleLineKind.error);
      return null;
    }
  }

  dynamic _onConsoleLog(dynamic args) {
    if (!mounted) return null;
    try {
      final list = args as List<dynamic>;
      final level = list.isEmpty ? 'log' : '${list.removeAt(0)}';
      final text = list.map((e) => '$e').join(' ');
      _append(text,
          level == 'error'
              ? ConsoleLineKind.error
              : (level == 'warn' ? ConsoleLineKind.warn : ConsoleLineKind.output));
    } catch (e) {
      _append('$e', ConsoleLineKind.error);
    }
    return null;
  }

  /// 给 QuickJS 装一套「终端」预置：readLine / readInt / readFloat / print。
  ///
  /// 浏览器沙箱没有真 stdin，所以用全局队列 `__ppStdin` 模拟：`/stdin 5 7` 先压
  /// 两行进队列，脚本里 `const a = readInt()` 就能依次取到 —— 这样「程序从标准
  /// 输入读、往标准输出写」的交互在手机/桌面上都能真跑起来。
  void _installPrelude(JavascriptRuntime rt) {
    if (_preludeReady) return;
    try {
      rt.evaluate(_preludeSource);
      _preludeReady = true;
    } catch (e) {
      _append('prelude: $e', ConsoleLineKind.error);
    }
  }

  /// 预置脚本本体（一次性装进 JS 全局）。
  static const String _preludeSource =
      'globalThis.__ppStdin = globalThis.__ppStdin || [];'
      'if (!globalThis.__ppPrelude) {'
      'globalThis.__ppPrelude = 1;'
      'globalThis.readLine = function () { return globalThis.__ppStdin.length ? '
      'String(globalThis.__ppStdin.shift()) : null; };'
      'globalThis.readInt = function () { var v = globalThis.readLine(); '
      'if (v === null) return null; var n = parseInt(v, 10); return isNaN(n) ? null : n; };'
      'globalThis.readFloat = function () { var v = globalThis.readLine(); '
      'if (v === null) return null; var n = parseFloat(v); return isNaN(n) ? null : n; };'
      'globalThis.print = function () { '
      'console.log(Array.prototype.slice.call(arguments).join(" ")); };'
      'globalThis.__ppRemaining = function () { return JSON.stringify(globalThis.__ppStdin); };'
      '}';

  /// 把控制台里的 stdin 队列灌进 JS，运行完再用 [_pullStdin] 取回剩下的。
  void _pushStdin(JavascriptRuntime rt) {
    try {
      rt.evaluate('globalThis.__ppStdin = ${jsonEncode(_state.stdin)}');
    } catch (_) {
      // 预置没装上时忽略
    }
  }

  void _pullStdin(JavascriptRuntime rt) {
    try {
      final r = rt.evaluate('globalThis.__ppRemaining ? globalThis.__ppRemaining() : "[]"');
      final raw = r.stringResult;
      if (raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _state.stdin
          ..clear()
          ..addAll(decoded.map((e) => '$e'));
      }
    } catch (_) {
      // 忽略
    }
  }

  void _append(String text, [ConsoleLineKind kind = ConsoleLineKind.output]) {
    if (!mounted) return;
    setState(() => _state.append(text, kind));
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
      _append('> $source', ConsoleLineKind.prompt);
      _state.remember(source);
    }
    // 以 / 开头的是终端命令，不送去求值（/help /clear /run /stdin …）
    if (source.startsWith('/')) {
      await _terminalCommand(source);
      return;
    }
    if (!mounted) return;
    setState(() => _running = true);
    try {
      if (_backend == ConsoleBackend.expr) {
        final result = _state.session.eval(_withSelection(source));
        if (result.isError) {
          _append(result.error!, ConsoleLineKind.error);
        } else {
          final formatted = ExprEval.format(result.value);
          _state.lastResult = formatted;
          _append('=> $formatted', ConsoleLineKind.result);
        }
        return;
      }

      final rt = _ensureRuntime();
      if (rt == null) return;
      // 终端语义：先把 stdin 队列灌进去，跑完再取回剩余的（脚本读走多少一目了然）
      _pushStdin(rt);
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
        _append(result.stringResult, ConsoleLineKind.error);
      } else {
        final value = result.stringResult;
        if (value.isNotEmpty && value != 'undefined' && value != 'null') {
          _state.lastResult = value;
          _append('=> $value', ConsoleLineKind.result);
        }
      }
    } catch (e) {
      _append('$e', ConsoleLineKind.error);
    } finally {
      final rt = _rt;
      if (rt != null) _pullStdin(rt);
      if (mounted) setState(() => _running = false);
    }
  }

  /// 重置 JS 运行时（`/reset` 用：变量、预置、剩余 stdin 全部清掉）。
  void _resetRuntime() {
    _preludeReady = false;
    _rt?.dispose();
    _rt = null;
  }

  /// 编辑 stdin 队列（给脚本喂输入）。
  Future<void> _editStdin() async {
    final loc = localizations;
    final ctrl = TextEditingController(text: _state.stdin.join('\n'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.editorTermStdin),
        content: TextField(
          controller: ctrl,
          minLines: 4,
          maxLines: 10,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
          decoration: InputDecoration(
            hintText: loc.editorTermStdinHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.save),
          ),
        ],
      ),
    );
    final text = ctrl.text;
    ctrl.dispose();
    if (ok != true) return;
    if (!mounted) return;
    setState(() {
      _state.clearStdin();
      _state.pushStdin(text
          .split('\n')
          .map((e) => e.trimRight())
          .where((e) => e.isNotEmpty));
    });
    // 立刻同步给运行中的 JS（没跑过脚本时队列就是全部输入）
    final rt = _rt;
    if (rt != null) _pushStdin(rt);
  }

  /// 终端命令。都是「本地动作」，永远不会被送去求值。
  Future<void> _terminalCommand(String raw) async {
    final loc = localizations;
    final space = raw.indexOf(' ');
    final cmd = (space < 0 ? raw : raw.substring(0, space)).toLowerCase();
    final rest = space < 0 ? '' : raw.substring(space + 1).trim();
    switch (cmd) {
      case '/help':
      case '/?':
        _append(loc.editorTermHelp, ConsoleLineKind.note);
        return;
      case '/clear':
        setState(_state.clearOutput);
        return;
      case '/reset':
        setState(_state.reset);
        _resetRuntime();
        _append(loc.editorTermReset, ConsoleLineKind.note);
        return;
      case '/run':
        if (_backend != ConsoleBackend.js) {
          _append(loc.editorTermNoRuntime, ConsoleLineKind.warn);
          return;
        }
        final doc = widget.readDocument();
        // 整篇丢给 QuickJS 会是同步解析：几十万字符能把 UI 卡住十几秒，
        // 这里设个上限，超了就明确告诉用户（而不是「点了没反应」）。
        if (doc.length > 200000) {
          _append(loc.editorTooLargeToProcess, ConsoleLineKind.warn);
          return;
        }
        await _run(doc, echo: false);
        return;
      case '/stdin':
        if (rest.isEmpty) {
          _append(loc.editorTermStdinCount(_state.stdin.length), ConsoleLineKind.note);
          return;
        }
        // 多个值用 | 分隔（值里可能含空格）
        final lines = rest
            .split('|')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
        _state.pushStdin(lines);
        _append(loc.editorTermStdinAdded(lines.length), ConsoleLineKind.note);
        return;
      case '/stdin-clear':
        setState(_state.clearStdin);
        _append(loc.editorTermStdinCleared, ConsoleLineKind.note);
        return;
      case '/lang':
        _append(
            '${widget.language} · ${_backend == ConsoleBackend.js ? 'JS runtime' : 'expression'}',
            ConsoleLineKind.note);
        return;
      case '/copy':
        await _copyOutput();
        return;
      default:
        _append(loc.editorTermUnknown(cmd), ConsoleLineKind.error);
    }
  }

  Future<void> _copyText(String text, String hint) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(hint), duration: const Duration(milliseconds: 1200)),
    );
  }

  Future<void> _copyOutput() async {
    if (_out.isEmpty) return;
    await _copyText(_out.map((e) => e.text).join('\n'), localizations.copied);
  }

  /// 把问题列表导出成 Markdown（贴 issue / 发给同事都方便），直接进剪贴板。
  Future<void> _copyReport() async {
    final report = widget.report;
    if (report == null || report.diagnostics.isEmpty) return;
    final buffer = StringBuffer()
      ..writeln('# ${localizations.editorLintIssues}')
      ..writeln()
      ..writeln('- ${widget.language}: ${report.diagnostics.length}'
          ' (${report.errorCount} error / ${report.warningCount} warning / ${report.infoCount} info)')
      ..writeln()
      ..writeln('| line | severity | rule | message |')
      ..writeln('| --- | --- | --- | --- |');
    for (final d in report.diagnostics) {
      final message = (d.suggestion == null ? d.message : '${d.message} · ${d.suggestion}')
          .replaceAll('|', '\\|');
      buffer.writeln('| ${d.line}:${d.column} | ${d.severity.name} | `${d.code}` | $message |');
    }
    await _copyText(buffer.toString(), localizations.copied);
  }

  void _insertLast() {
    final value = _state.lastResult;
    final insert = widget.onInsertText;
    if (value == null || insert == null) return;
    insert(value);
  }

  void _recallHistory(bool forward) {
    final history = _state.history;
    if (history.isEmpty) return;
    var next = _state.historyCursor + (forward ? -1 : 1);
    if (next < -1) next = history.length - 1;
    if (next >= history.length) next = -1;
    _state.historyCursor = next;
    _input.text = next < 0 ? '' : history[next];
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
  }

  // ------------------------------ UI ------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.6)),
      ),
      child: Column(children: [
        _dragHandle(theme),
        _header(theme),
        Expanded(
          child: switch (_tab) {
            EditorConsoleTab.problems => _problems(theme),
            EditorConsoleTab.console => _console(theme),
            EditorConsoleTab.debug => _debug(theme),
          },
        ),
      ]),
    );
  }

  /// 顶部拖拽条：上下拖动改面板高度。
  ///
  /// 用 `onVerticalDragUpdate` 而不是 GestureDetector 的 onPan：面板里还有
  /// 列表要滚，横向手势不能抢。
  Widget _dragHandle(ThemeData theme) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) {
        setState(() => _height = (_height - d.delta.dy).clamp(120.0, 460.0));
      },
      // 拖动过程中不落盘：每像素写一次偏好没有意义。
      onVerticalDragEnd: (_) => widget.onHeightChanged?.call(_height),
      child: SizedBox(
        height: 12,
        width: double.infinity,
        child: Center(
          child: Container(
            width: 36,
            height: 3,
            decoration: BoxDecoration(
              color: theme.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  /// 输出行的颜色（按行类型）。
  Color? _lineColor(ThemeData theme, ConsoleLineKind kind) {
    switch (kind) {
      case ConsoleLineKind.error:
        return Colors.red;
      case ConsoleLineKind.warn:
        return Colors.orange;
      case ConsoleLineKind.prompt:
        return Colors.grey;
      case ConsoleLineKind.result:
        return theme.colorScheme.primary;
      case ConsoleLineKind.note:
        return theme.textTheme.bodySmall?.color;
      case ConsoleLineKind.output:
        return null;
    }
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
        if (widget.programming)
          tab(localizations.editorTerminal, EditorConsoleTab.console, null, null),
        if (widget.jsBackend)
          tab(localizations.editorDebugTab, EditorConsoleTab.debug,
              _debugLine > 0 ? '$_debugLine' : null, Colors.orange),
        // 窄屏（360dp）上这条按钮区会超出宽度：问题页有 7 个图标按钮 + 2 个页签。
        // 包一层「右对齐 + 横向可滑」，挤不下就滑过去，不会再出 Row overflow 的黄黑条。
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_tab == EditorConsoleTab.problems) ...[
                  _barIcon(
                    tooltip: localizations.editorLintRules,
                    onPressed: widget.onOpenRules,
                    icon: const Icon(Icons.tune, size: 16),
                  ),
                  _barIcon(
                    tooltip: localizations.editorLintReport,
                    onPressed: (widget.report?.diagnostics.isEmpty ?? true) ? null : _copyReport,
                    icon: const Icon(Icons.description_outlined, size: 16),
                  ),
                  _filterButton(),
                  _barIcon(
                    tooltip: localizations.editorLintPrev,
                    onPressed: _visible.isEmpty ? null : () => _goIssue(false),
                    icon: const Icon(Icons.keyboard_arrow_up, size: 17),
                  ),
                  _barIcon(
                    tooltip: localizations.editorLintNext,
                    onPressed: _visible.isEmpty ? null : () => _goIssue(true),
                    icon: const Icon(Icons.keyboard_arrow_down, size: 17),
                  ),
                  if ((report?.fixableCount ?? 0) > 0)
                    _barIcon(
                      tooltip: localizations.editorLintFixAll,
                      onPressed: widget.onFixAll,
                      icon: const Icon(Icons.auto_fix_high, size: 16),
                    ),
                ],
                _barIcon(
                  tooltip: localizations.close,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, size: 16),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  /// 控制台页签行里的小图标按钮：34dp（默认 48 太占地方，这一行最多要放 7 个）。
  Widget _barIcon({
    required String tooltip,
    required VoidCallback? onPressed,
    required Widget icon,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
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
    // 注意：过滤后为空时**不能**直接 return——那样顶部统计 chips 也没了，
    // 用户就没法把「按规则过滤」撤掉，会卡在一个空列表里。
    return Column(children: [
      // 搜索框：VS 的「错误列表」就有这一行，按说明或规则名过滤。
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
        child: TextField(
          controller: _searchInput,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            isDense: true,
            hintText: localizations.search,
            hintStyle: const TextStyle(fontSize: 12),
            prefixIcon: const Icon(Icons.search, size: 15),
            prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            suffixIcon: _search.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 14),
                    visualDensity: VisualDensity.compact,
                    tooltip: localizations.clear,
                    onPressed: () {
                      _searchInput.clear();
                      setState(() => _search = '');
                    },
                  ),
            contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
      ),
      if (_ruleStats.isNotEmpty) _ruleChips(theme),
      Expanded(
        child: list.isEmpty
            ? _hint(localizations.editorLintFilteredEmpty, theme)
            : _problemList(theme, list),
      ),
    ]);
  }

  /// 按规则统计（VS「错误列表」也支持按工具/规则分组看）。
  Map<String, int> get _ruleStats {
    final counts = <String, int>{};
    for (final d in widget.report?.diagnostics ?? const <LintDiagnostic>[]) {
      counts[d.code] = (counts[d.code] ?? 0) + 1;
    }
    return counts;
  }

  Widget _ruleChips(ThemeData theme) {
    final stats = _ruleStats;
    if (stats.length < 2) return const SizedBox.shrink();
    final chinese = Localizations.localeOf(context).languageCode.startsWith('zh');
    final entries = stats.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    String labelOf(String? code) {
      if (code == null) return localizations.editorLintAllRules;
      final rule = LintRules.byCode(code);
      if (rule == null) return code;
      return chinese ? rule.nameZh : rule.nameEn;
    }

    final total = stats.values.fold<int>(0, (a, b) => a + b);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
      child: Row(children: [
        _ruleChip(labelOf(null), total, _ruleFilter == null, () {
          setState(() => _ruleFilter = null);
        }),
        for (final e in entries.take(8)) ...[
          const SizedBox(width: 6),
          _ruleChip(labelOf(e.key), e.value, _ruleFilter == e.key, () {
            setState(() => _ruleFilter = _ruleFilter == e.key ? null : e.key);
          }),
        ],
      ]),
    );
  }

  Widget _ruleChip(String label, int count, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text('$label ($count)', style: const TextStyle(fontSize: 10.5)),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
    );
  }

  Widget _problemList(ThemeData theme, List<LintDiagnostic> list) {
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
        padding: const EdgeInsets.fromLTRB(10, 2, 4, 0),
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
                _state.clearOutput();
                _state.lastResult = null;
              });
            },
          ),
          const Spacer(),
          if (_out.isNotEmpty) ...[
            IconButton(
              tooltip: localizations.editorConsoleCopyAll,
              onPressed: _copyOutput,
              icon: const Icon(Icons.copy_all_outlined, size: 16),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: localizations.editorConsoleClear,
              onPressed: () => setState(_state.reset),
              icon: const Icon(Icons.delete_outline, size: 16),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ]),
      ),
      Expanded(
        child: _out.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    // 终端首屏直接把命令列出来（/run /stdin /reset…），
                    // 比一句「输入表达式执行」有用得多。
                    _backend == ConsoleBackend.js
                        ? localizations.editorTermHelp
                        : localizations.editorConsoleExprHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color),
                  ),
                ),
              )
            : SelectionArea(
                child: Scrollbar(
                  controller: _scroll,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final o in _out)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: Text(o.text,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontFamily: 'monospace',
                                      color: _lineColor(theme, o.kind),
                                      fontWeight: o.kind == ConsoleLineKind.prompt
                                          ? FontWeight.w600
                                          : FontWeight.w400)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 4, 6),
        child: Row(children: [
          // 终端提示符：和真正的 shell 一样，「❯」后面才是用户输入
          Padding(
            padding: const EdgeInsets.only(right: 6, left: 2),
            child: Text(
              _multiline ? '…' : '❯',
              style: TextStyle(
                fontSize: 14,
                height: 1,
                fontFamily: 'monospace',
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: _multiline ? 4 : 1,
              textInputAction:
                  _multiline ? TextInputAction.newline : TextInputAction.done,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: InputDecoration(
                isDense: true,
                hintText: _multiline
                    ? localizations.editorTermMultilineHint
                    : localizations.editorConsoleInputHint,
                hintStyle: const TextStyle(fontSize: 12),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                if (_multiline) return;
                unawaited(_run(value));
                _input.clear();
              },
            ),
          ),
          // 多行模式（写 for/if 这种多语句时用 Enter 换行，▶ 才执行）
          IconButton(
            tooltip: localizations.editorTermMultiline,
            onPressed: () => setState(() => _multiline = !_multiline),
            icon: Icon(_multiline ? Icons.wrap_text : Icons.notes, size: 16),
            color: _multiline ? theme.colorScheme.primary : null,
            visualDensity: VisualDensity.compact,
          ),
          // stdin 队列：给脚本喂标准输入
          InkWell(
            onTap: _editStdin,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.keyboard_return, size: 16,
                    color: _state.stdin.isEmpty ? null : theme.colorScheme.primary),
                if (_state.stdin.isNotEmpty)
                  Text('${_state.stdin.length}',
                      style: TextStyle(
                          fontSize: 9.5, color: theme.colorScheme.primary)),
              ]),
            ),
          ),
          IconButton(
            tooltip: localizations.editorConsoleHistory,
            onPressed: () => _recallHistory(false),
            icon: const Icon(Icons.history, size: 16),
            visualDensity: VisualDensity.compact,
          ),
          if (widget.onInsertText != null)
            IconButton(
              tooltip: localizations.editorConsoleInsert,
              onPressed: _state.lastResult == null ? null : _insertLast,
              icon: const Icon(Icons.input, size: 16),
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
