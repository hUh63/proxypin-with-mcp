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

// 把 CodeLint 接到任意 CodeForgeController 上的一层薄封装。
//
// 文本编辑器、JSON 查看器、XML 查看器、JavaScript 页面都用同一套：防抖检查 →
// 行底色 + 行号栏色条 → 结果通过 [report] 暴露给页面（显示条数/问题列表）。
// 这样「语法检查」不是某一个页面的私有能力。
import 'dart:async';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:proxypin/utils/code_lint.dart';

/// 语法检查绑定。
class LintBinding {
  LintBinding({this.chinese = true});

  /// 消息语言（中文用户看中文，其余看英文）。
  final bool chinese;

  /// 最近一次检查结果。
  final ValueNotifier<LintReport?> report = ValueNotifier<LintReport?>(null);

  /// 是否启用自动检查。
  bool enabled = true;

  /// 防抖间隔。
  int debounceMs = 650;

  Timer? _timer;
  bool _running = false;
  bool _disposed = false;

  /// 正在写装饰标记。
  ///
  /// applyDecorations 会 notifyListeners，页面的 controller 监听器会再调
  /// schedule —— 不拦住就变成「每 650ms 自查一次」的死循环（每次都 notify）。
  bool _applying = false;

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    report.dispose();
  }

  /// 内容变化后调用（防抖）。
  void schedule(CodeForgeController controller, {required String langLabel, String? langKey}) {
    if (!enabled || _disposed || _applying) return;
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: debounceMs), () {
      refresh(controller, langLabel: langLabel, langKey: langKey);
    });
  }

  /// 立刻检查一次。
  LintReport refresh(CodeForgeController controller, {required String langLabel, String? langKey}) {
    if (_disposed) return LintReport.empty;
    if (_running) return report.value ?? LintReport.empty;
    _running = true;
    final result = CodeLint.check(controller.text, langLabel: langLabel, langKey: langKey, chinese: chinese);
    _running = false;
    if (_disposed) return result;
    report.value = result;
    applyDecorations(controller, result);
    return result;
  }

  /// 把诊断画成行底色 + 行号栏色条。
  void applyDecorations(CodeForgeController controller, LintReport result) {
    _applying = true;
    try {
      _applyDecorations(controller, result);
    } finally {
      _applying = false;
    }
  }

  void _applyDecorations(CodeForgeController controller, LintReport result) {
    controller.clearLineDecorations();
    controller.clearGutterDecorations();
    if (result.diagnostics.isEmpty) {
      controller.notifyListeners();
      return;
    }
    // 同一行多条诊断时只按最严重的那条染色。
    final worstByLine = <int, LintSeverity>{};
    for (final d in result.diagnostics) {
      final line = d.line - 1;
      if (line < 0) continue;
      final current = worstByLine[line];
      if (current == null || d.severity.index < current.index) worstByLine[line] = d.severity;
    }
    final decorations = <LineDecoration>[];
    final gutters = <GutterDecoration>[];
    worstByLine.forEach((line, severity) {
      final color = switch (severity) {
        LintSeverity.error => Colors.red,
        LintSeverity.warning => Colors.orange,
        LintSeverity.info => Colors.blueGrey,
      };
      decorations.add(LineDecoration(
        id: 'lint-bg-$line',
        startLine: line,
        endLine: line,
        type: LineDecorationType.background,
        color: color.withValues(alpha: 0.12),
      ));
      gutters.add(GutterDecoration(
        id: 'lint-gutter-$line',
        startLine: line,
        endLine: line,
        type: GutterDecorationType.colorBar,
        color: color,
      ));
    });
    controller.addLineDecorations(decorations);
    controller.addGutterDecorations(gutters);
    controller.notifyListeners();
  }

  void clearDecorations(CodeForgeController controller) {
    _applying = true;
    try {
      controller.clearLineDecorations();
      controller.clearGutterDecorations();
      controller.notifyListeners();
    } finally {
      _applying = false;
    }
  }
}

/// 工具栏上的「语法检查结果」小徽标：有错误变红、有警告变橙、干净的显示绿勾。
class LintBadge extends StatelessWidget {
  final ValueListenable<LintReport?> listenable;
  final VoidCallback? onTap;

  const LintBadge({super.key, required this.listenable, this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ValueListenableBuilder<LintReport?>(
      valueListenable: listenable,
      builder: (context, report, _) {
        final count = report?.diagnostics.length ?? 0;
        final color = switch (report?.worst) {
          LintSeverity.error => Colors.red,
          LintSeverity.warning => Colors.orange,
          LintSeverity.info => Colors.blueGrey,
          null => null,
        };
        return InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(count > 0 ? Icons.report_problem_outlined : Icons.check_circle_outline,
                  size: 16, color: color ?? primary),
              if (count > 0) ...[
                const SizedBox(width: 2),
                Text('$count', style: TextStyle(fontSize: 10.5, color: color ?? primary)),
              ],
            ]),
          ),
        );
      },
    );
  }
}
