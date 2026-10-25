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

// 控制台的「状态」——它属于**文档**，不属于面板。
//
// 面板是个 StatefulWidget：收起再打开、切到别的文档再切回来，State 都会重建，
// 于是刚算出来的结果、敲过的命令、定义过的变量一起消失。而这些东西本来就是
// 「我在这个文件里刚才干了什么」，应该跟着文档走。
//
// 所以把它抽出来挂在 EditorDocument 上：面板只负责渲染和交互，数据留在文档里。
import 'package:proxypin/utils/expr_eval.dart';

/// 控制台一行的类型（决定颜色，界面层映射）。
enum ConsoleLineKind {
  /// 普通输出（console.log）。
  output,

  /// 用户输入的命令回显（`> x`）。
  prompt,

  /// 求值结果（`=> 3`）。
  result,

  /// 错误。
  error,

  /// 警告。
  warn,

  /// 提示（例如「没有运行时」）。
  note,
}

/// 控制台里的一行。
class ConsoleLine {
  final String text;
  final ConsoleLineKind kind;

  const ConsoleLine(this.text, this.kind);

  @override
  String toString() => text;
}

/// 一份文档的控制台状态。
class ConsoleState {
  /// 只保留最近这么多行，一直 log 的脚本不能把内存吃光。
  static const int maxLines = 500;

  /// 命令历史上限。
  static const int maxHistory = 50;

  /// 输出行。
  final List<ConsoleLine> lines = <ConsoleLine>[];

  /// 敲过的命令（上/下方向键翻阅）。
  final List<String> history = <String>[];

  /// 历史翻阅游标（-1 表示不在翻阅中）。
  int historyCursor = -1;

  /// 表达式后端的会话：`a = 1+2` 之后可以直接用 `a`。
  final ExprSession session = ExprSession();

  /// 最近一次成功的结果（「插入到编辑器」用）。
  String? lastResult;

  /// 追加一行。
  void append(String text, ConsoleLineKind kind) {
    lines.add(ConsoleLine(text, kind));
    if (lines.length > maxLines) {
      lines.removeRange(0, lines.length - maxLines);
    }
  }

  /// 记一条命令（相同命令不重复记，连续输入不会把历史挤满）。
  void remember(String command) {
    final source = command.trim();
    if (source.isEmpty) return;
    if (history.isEmpty || history.last != source) {
      history.add(source);
      if (history.length > maxHistory) history.removeAt(0);
    }
    historyCursor = -1;
  }

  /// 清屏（保留命令历史与变量）。
  void clearOutput() {
    lines.clear();
  }

  /// 全清（连命令历史与变量一起）。
  void reset() {
    lines.clear();
    history.clear();
    historyCursor = -1;
    lastResult = null;
    session.reset();
  }
}
