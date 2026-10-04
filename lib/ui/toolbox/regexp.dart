/*
 * Copyright 2024 Hongen Wang All rights reserved.
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

import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/ui/component/buttons.dart';
import 'package:proxypin/ui/component/snippet_manager.dart';
import 'package:proxypin/ui/component/text_field.dart';
import 'package:proxypin/ui/toolbox/regexp_help.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:proxypin/utils/regexp_util.dart';
import 'package:proxypin/utils/tool_snippets.dart';

///正则表达式工具
///@author Hongen Wang
class RegExpPage extends StatefulWidget {
  final String? windowId;

  const RegExpPage({super.key, this.windowId});

  @override
  State<StatefulWidget> createState() {
    return _RegExpPageState();
  }
}

class _RegExpPageState extends State<RegExpPage> {
  var pattern = TextEditingController();
  var input = HighlightTextEditingController();
  var replaceText = TextEditingController();
  String? resultInput;

  // 修饰符
  RegexpFlags _flags = const RegexpFlags();

  // 快捷插入条目（可自定义）
  List<ToolSnippet> _snippets = ToolSnippetDefaults.regexp;

  // 匹配状态
  RegExp? _regex;
  int _matchCount = 0;
  String? _patternError;
  List<CaptureGroup> _groups = const <CaptureGroup>[];

  bool _onMatch = false;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    pattern.addListener(_scheduleRecompute);
    input.addListener(_scheduleRecompute);
    _loadSnippets();

    if (Platforms.isDesktop() && widget.windowId != null) {
      HardwareKeyboard.instance.addHandler(onKeyEvent);
    }
  }

  Future<void> _loadSnippets() async {
    final saved = await ToolSnippetStore.load('regexp');
    if (!mounted || saved == null) return;
    setState(() => _snippets = saved);
  }

  @override
  void dispose() {
    pattern.removeListener(_scheduleRecompute);
    input.removeListener(_scheduleRecompute);
    pattern.dispose();
    input.dispose();
    replaceText.dispose();
    if (Platforms.isDesktop() && widget.windowId != null) {
      HardwareKeyboard.instance.removeHandler(onKeyEvent);
    }
    super.dispose();
  }

  bool onKeyEvent(KeyEvent event) {
    if (widget.windowId == null) return false;
    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      HardwareKeyboard.instance.removeHandler(onKeyEvent);
      WindowController.fromWindowId(widget.windowId!).close();
      return true;
    }

    return false;
  }

  // ---------- 匹配 ----------

  /// 输入时防抖，避免每个字符都重算高亮。
  void _scheduleRecompute() {
    if (_onMatch) return;
    _onMatch = true;
    Future.delayed(const Duration(milliseconds: 300), () {
      _onMatch = false;
      if (!mounted) return;
      _recompute();
    });
  }

  void _recompute() {
    final p = pattern.text;
    if (p.isEmpty) {
      input.highlightPattern = null;
      setState(() {
        _regex = null;
        _matchCount = 0;
        _patternError = null;
        _groups = const <CaptureGroup>[];
      });
      return;
    }

    try {
      final re = RegExp(p,
          caseSensitive: !_flags.ignoreCase,
          multiLine: _flags.multiLine,
          dotAll: _flags.dotAll,
          unicode: _flags.unicode);
      final matches = re.allMatches(input.text).toList();
      input.highlightPattern = re;
      setState(() {
        _regex = re;
        _patternError = null;
        _matchCount = matches.length;
        _groups = matches.isEmpty ? const <CaptureGroup>[] : captureGroupsOf(matches.first);
      });
    } on FormatException catch (e) {
      input.highlightPattern = null;
      setState(() {
        _regex = null;
        _patternError = e.message;
        _matchCount = 0;
        _groups = const <CaptureGroup>[];
      });
    }
  }

  void _setFlags(RegexpFlags next) {
    setState(() => _flags = next);
    _recompute();
  }

  // ---------- 快捷插入 ----------

  void _insertInto(TextEditingController ctl, String text) {
    final next = ctl.text + text;
    ctl.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length));
  }

  Future<void> _manageSnippets() async {
    final result = await showDialog<List<ToolSnippet>>(
      context: context,
      builder: (_) => SnippetManagerDialog(
        scope: 'regexp',
        items: _snippets,
        defaults: ToolSnippetDefaults.regexp,
      ),
    );
    if (result == null) return;
    setState(() => _snippets = result);
    await ToolSnippetStore.save('regexp', result);
  }

  // ---------- 替换 ----------

  void _runReplace() {
    if (pattern.text.isEmpty) return;
    final re = _regex;
    if (re == null) {
      FlutterToastr.show(localizations.regexpInvalid(_patternError ?? ''), context, duration: 3);
      return;
    }
    final r = replaceWithExpansion(input.text, re, replaceText.text);
    setState(() {
      resultInput = r.text;
    });
    FlutterToastr.show(localizations.regexpReplaced(r.count), context, duration: 2);
  }

  /// 把替换结果写回测试数据，便于继续链式处理。
  void _applyResultToInput() {
    if (resultInput == null) return;
    setState(() {
      input.text = resultInput!;
      resultInput = null;
    });
    _recompute();
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    Color primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
        appBar: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: AppBar(
                title: Text(localizations.regExp, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                centerTitle: true,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.menu_book_outlined, size: 20),
                    tooltip: localizations.regexpHelp,
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (context) => const RegexpHelpPage())),
                  ),
                  IconButton(
                    icon: const Icon(Icons.tune, size: 20),
                    tooltip: localizations.snippetManagerTitle,
                    onPressed: _manageSnippets,
                  ),
                ])),
        resizeToAvoidBottomInset: false,
        body: ListView(padding: const EdgeInsets.all(10), children: [
          TextField(
            controller: pattern,
            minLines: 1,
            maxLines: 3,
            onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: decoration(context,
                label: localizations.regexpPattern,
                hintText: localizations.regexpPatternHint,
                suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () => pattern.clear())),
          ),
          const SizedBox(height: 6),
          _modifierRow(primaryColor),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _insertInto(pattern, r'\d+'), // Only digits
                child: Text(localizations.regexpDigits),
              ),
              TextButton(
                onPressed: () => _insertInto(pattern, r'[a-zA-Z]+'), // Only letters
                child: Text(localizations.regexpLetters),
              ),
              TextButton(
                onPressed: () => _insertInto(pattern, r'[a-zA-Z0-9]+'), // Alphanumeric
                child: Text(localizations.regexpAlphanumeric),
              ),
              TextButton(
                onPressed: () => _insertInto(pattern, r'\w+@\w+\.\w+'), // Email
                child: Text(localizations.regexpEmail),
              ),
              TextButton(
                onPressed: () => _insertInto(pattern, r'(https?|ftp)://[^\s/$.?#].[^\s]*'), // URL
                child: const Text('URL'),
              ),
              TextButton(
                onPressed: () => _insertInto(pattern, r'\d{4}-\d{2}-\d{2}'), // Date (YYYY-MM-DD)
                child: Text(localizations.regexpDate),
              ),
            ],
          ),
          _snippetBar(primaryColor),
          const SizedBox(height: 8),
          _matchStatus(primaryColor),
          const SizedBox(height: 6),
          TextField(
            controller: input,
            minLines: 5,
            maxLines: 8,
            onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: decoration(context, hintText: localizations.enterMatchData),
          ),
          const SizedBox(height: 20),
          //输入替换文本
          Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
                width: 355,
                child: TextField(
                  controller: replaceText,
                  onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: decoration(context,
                      label: localizations.regexpReplaceText, hintText: localizations.regexpReplaceHint),
                )),
            FilledButton.icon(
                onPressed: _runReplace,
                style: Buttons.buttonStyle,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(localizations.commonRun)),
          ]),
          _replaceHelperRow(primaryColor),
          const SizedBox(height: 10),

          if (resultInput != null)
            Row(children: [
              Text(localizations.regexpResult,
                  style: TextStyle(fontSize: 16, color: primaryColor, fontWeight: FontWeight.w500)),
              const SizedBox(width: 15),
              //copy
              IconButton(
                  icon: Icon(Icons.copy, color: primaryColor, size: 18),
                  tooltip: localizations.copy,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: resultInput!));
                    FlutterToastr.show(localizations.copied, context, duration: 3);
                  }),
              IconButton(
                  icon: Icon(Icons.input, color: primaryColor, size: 18),
                  tooltip: localizations.regexpApplyToInput,
                  onPressed: _applyResultToInput),
            ]),
          if (resultInput != null) const SizedBox(height: 5),
          if (resultInput != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: primaryColor, width: 1.2)),
              child: SelectableText.rich(
                showCursor: true,
                TextSpan(
                  children: _buildHighlightedText(),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
        ]));
  }

  /// i / m / s / u 修饰符开关。
  Widget _modifierRow(Color primaryColor) {
    Widget chip(String label, bool selected, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: selected,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onSelected: (_) => onTap(),
        ),
      );
    }

    return Row(children: [
      Text('${localizations.regexpModifiers}:', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
      const SizedBox(width: 6),
      chip('i', _flags.ignoreCase, () => _setFlags(_flags.copyWith(ignoreCase: !_flags.ignoreCase))),
      chip('m', _flags.multiLine, () => _setFlags(_flags.copyWith(multiLine: !_flags.multiLine))),
      chip('s', _flags.dotAll, () => _setFlags(_flags.copyWith(dotAll: !_flags.dotAll))),
      chip('u', _flags.unicode, () => _setFlags(_flags.copyWith(unicode: !_flags.unicode))),
    ]);
  }

  /// 可自定义的元字符 / 片段快捷插入条。
  Widget _snippetBar(Color primaryColor) {
    if (_snippets.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 4),
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _snippets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final s = _snippets[i];
          return ActionChip(
            label: Text(s.label, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onPressed: () => _insertInto(pattern, s.insert),
          );
        },
      ),
    );
  }

  /// 替换框专用符号（插入到替换表达式）。
  Widget _replaceHelperRow(Color primaryColor) {
    const items = [r'$0', r'$1', r'$2', r'\l', r'\u', r'\L', r'\U', r'\$', r'\n', r'\t'];
    return Wrap(
      spacing: 6,
      children: items
          .map((t) => InkWell(
                onTap: () => _insertInto(replaceText, t),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(t, style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: primaryColor)),
                ),
              ))
          .toList(),
    );
  }

  Widget _matchStatus(Color primaryColor) {
    if (pattern.text.isEmpty) {
      return Align(alignment: Alignment.centerLeft, child: Text(localizations.testData));
    }
    if (_patternError != null) {
      return Align(
          alignment: Alignment.centerLeft,
          child: Text(localizations.regexpInvalid(_patternError!),
              style: const TextStyle(color: Colors.red, fontSize: 13)));
    }
    final color = _matchCount > 0 ? Colors.green : Colors.red;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(localizations.testData),
        const SizedBox(width: 10),
        Text(localizations.regexpMatches(_matchCount), style: TextStyle(color: color, fontSize: 13)),
      ]),
      if (_groups.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _groups
                .map((g) => Text(
                      '${g.index}: ${g.value ?? '(空)'}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700], fontFamily: 'monospace'),
                    ))
                .toList(),
          ),
        ),
    ]);
  }

  List<InlineSpan> _buildHighlightedText() {
    if (resultInput == null) return [];
    final re = _regex;
    if (re == null) return [TextSpan(text: input.text)];

    final spans = <InlineSpan>[];
    int start = 0;

    var text = input.text; // Use original input for highlighting
    var matches = re.allMatches(text);

    for (var match in matches) {
      if (start < match.start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      // Calculate the actual replacement text for this match
      var replacement = expandReplacement(replaceText.text, match);
      spans.add(TextSpan(text: replacement, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)));
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return spans;
  }
}
