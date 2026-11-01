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

// 转换工具：进制 / 字节 / 浮点 / 简繁 / 文本。
//
// 这页是把「编码工具箱 Pro Max」里跟编码有关的几块搬到一起：
// 它那边是一个算法一屏、输入框上下堆叠；这里按「一类操作一个 Tab」重排，
// 底部统一「转换 → 结果 → 复制」，输入框保持多行（粘一大段日志不用滚来滚去）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/num_convert.dart';
import 'package:proxypin/utils/smali_tool.dart';
import 'package:proxypin/utils/zh_convert.dart';

class ConvertPage extends StatefulWidget {
  const ConvertPage({super.key});

  @override
  State<ConvertPage> createState() => _ConvertPageState();
}

class _ConvertPageState extends State<ConvertPage> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 6, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.toolboxConvert),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: loc.convertRadix),
            Tab(text: loc.convertBytes),
            Tab(text: loc.convertFloat),
            Tab(text: loc.convertZh),
            Tab(text: loc.convertText),
            Tab(text: 'Smali'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _RadixTab(),
          _BytesTab(),
          _FloatTab(),
          _ZhTab(),
          _TextTab(),
          _SmaliTab(),
        ],
      ),
    );
  }
}

/// 每个 Tab 的公共骨架：上面输入、中间操作、下面结果。
class _ToolScaffold extends StatelessWidget {
  final List<Widget> controls;
  final String inputHint;
  final TextEditingController input;
  final String output;
  final bool mono;

  const _ToolScaffold({
    required this.controls,
    required this.inputHint,
    required this.input,
    required this.output,
    this.mono = true,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: controls),
          const SizedBox(height: 8),
          Expanded(
            flex: 5,
            child: TextField(
              controller: input,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: inputHint,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.all(8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: 5,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(4),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
              child: Stack(children: [
                SingleChildScrollView(
                  child: SelectableText(
                    output.isEmpty ? '—' : output,
                    style: TextStyle(fontSize: 13, fontFamily: mono ? 'monospace' : null),
                  ),
                ),
                if (output.isNotEmpty)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton(
                      tooltip: loc.copy,
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.copy_all_outlined),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: output));
                        if (context.mounted) {
                          FlutterToastr.show(loc.copied, context, duration: 1);
                        }
                      },
                    ),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _chip(String label, bool active, VoidCallback onTap) {
  return ChoiceChip(
    label: Text(label, style: const TextStyle(fontSize: 12)),
    selected: active,
    visualDensity: VisualDensity.compact,
    onSelected: (_) => onTap(),
  );
}

// ---------------- 进制 ----------------

class _RadixTab extends StatefulWidget {
  const _RadixTab();

  @override
  State<_RadixTab> createState() => _RadixTabState();
}

class _RadixTabState extends State<_RadixTab> {
  final _input = TextEditingController();
  int _from = 10;
  int _to = 16;
  String _out = '';

  static const List<int> _radixes = [2, 8, 10, 16, 32, 36];

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _run() {
    final loc = AppLocalizations.of(context)!;
    final r = NumConvert.radix(_input.text, from: _from, to: _to);
    setState(() => _out = r ?? loc.convertInvalid);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return _ToolScaffold(
      input: _input,
      inputHint: loc.convertRadixHint,
      output: _out,
      controls: [
        Text('${loc.convertFrom} ', style: const TextStyle(fontSize: 12)),
        for (final r in _radixes) _chip('$r', _from == r, () => setState(() => _from = r)),
        const SizedBox(width: 8),
        Text('${loc.convertTo} ', style: const TextStyle(fontSize: 12)),
        for (final r in _radixes) _chip('$r', _to == r, () => setState(() => _to = r)),
        FilledButton.tonal(onPressed: _run, child: Text(loc.convert)),
      ],
    );
  }
}

// ---------------- 字节 / ASCII ----------------

class _BytesTab extends StatefulWidget {
  const _BytesTab();

  @override
  State<_BytesTab> createState() => _BytesTabState();
}

class _BytesTabState extends State<_BytesTab> {
  final _input = TextEditingController();
  int _radix = 10;
  String _out = '';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// 两个方向一起给出：用户不用先想「我这是往哪边转」。
  void _run() {
    final loc = AppLocalizations.of(context)!;
    final text = _input.text;
    if (text.isEmpty) {
      setState(() => _out = '');
      return;
    }
    final asBytes = NumConvert.textToBytes(text, radix: _radix, pad: _radix == 16);
    final asText = NumConvert.bytesToText(text);
    final buf = StringBuffer();
    buf.writeln('${loc.convertAsBytes}（$_radix）:');
    buf.writeln(asBytes);
    buf.writeln();
    buf.writeln('${loc.convertAsText}:');
    buf.writeln(asText ?? loc.convertInvalid);
    setState(() => _out = buf.toString());
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return _ToolScaffold(
      input: _input,
      inputHint: loc.convertBytesHint,
      output: _out,
      controls: [
        _chip('DEC', _radix == 10, () => setState(() => _radix = 10)),
        _chip('HEX', _radix == 16, () => setState(() => _radix = 16)),
        _chip('BIN', _radix == 2, () => setState(() => _radix = 2)),
        FilledButton.tonal(onPressed: _run, child: Text(loc.convert)),
        TextButton(
          onPressed: () => setState(() {
            _input.text = '';
            _out = '';
          }),
          child: Text(loc.clear),
        ),
      ],
    );
  }
}

// ---------------- 浮点 ----------------

class _FloatTab extends StatefulWidget {
  const _FloatTab();

  @override
  State<_FloatTab> createState() => _FloatTabState();
}

class _FloatTabState extends State<_FloatTab> {
  final _input = TextEditingController();
  bool _asFloat32 = true;
  String _out = '';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _run() {
    final loc = AppLocalizations.of(context)!;
    final v = _input.text.trim();
    if (v.isEmpty) {
      setState(() => _out = '');
      return;
    }
    final buf = StringBuffer();
    // 输入能当浮点就按「值 → 位模式」，否则按「位模式 → 值」，两个方向都试。
    final hex = NumConvert.doubleToHex(v, asFloat32: _asFloat32);
    if (hex != null) {
      buf.writeln('${loc.convertValueToBits}:');
      buf.writeln('$v  →  $hex');
      buf.writeln();
    }
    final decoded = NumConvert.hexToDouble(v, asFloat32: _asFloat32);
    if (decoded != null) {
      buf.writeln('${loc.convertBitsToValue}:');
      buf.writeln('$v  →  $decoded');
    }
    setState(() => _out = buf.isEmpty ? loc.convertInvalid : buf.toString());
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return _ToolScaffold(
      input: _input,
      inputHint: loc.convertFloatHint,
      output: _out,
      controls: [
        _chip('float32', _asFloat32, () => setState(() => _asFloat32 = true)),
        _chip('float64', !_asFloat32, () => setState(() => _asFloat32 = false)),
        FilledButton.tonal(onPressed: _run, child: Text(loc.convert)),
      ],
    );
  }
}

// ---------------- 简繁 ----------------

class _ZhTab extends StatefulWidget {
  const _ZhTab();

  @override
  State<_ZhTab> createState() => _ZhTabState();
}

class _ZhTabState extends State<_ZhTab> {
  final _input = TextEditingController();
  String _out = '';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _toTrad() => setState(() => _out = ZhConvert.toTraditional(_input.text));

  void _toSimp() => setState(() => _out = ZhConvert.toSimplified(_input.text));

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return _ToolScaffold(
      input: _input,
      inputHint: loc.convertZhHint,
      output: _out,
      mono: false,
      controls: [
        FilledButton.tonal(onPressed: _toTrad, child: Text('${loc.convertSimple} → ${loc.convertTrad}')),
        FilledButton.tonal(onPressed: _toSimp, child: Text('${loc.convertTrad} → ${loc.convertSimple}')),
        Text('${ZhConvert.tableSize} ${loc.convertZhTable}',
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

// ---------------- 文本（反转 / 大小写） ----------------

class _TextTab extends StatefulWidget {
  const _TextTab();

  @override
  State<_TextTab> createState() => _TextTabState();
}

class _TextTabState extends State<_TextTab> {
  final _input = TextEditingController();
  String _out = '';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _apply(String mode) {
    final text = _input.text;
    setState(() {
      _out = switch (mode) {
        'reverse' => NumConvert.reverse(text),
        'upper' => NumConvert.changeCase(text, 'upper'),
        'lower' => NumConvert.changeCase(text, 'lower'),
        'title' => NumConvert.changeCase(text, 'title'),
        _ => NumConvert.changeCase(text, 'swap'),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return _ToolScaffold(
      input: _input,
      inputHint: loc.convertTextHint,
      output: _out,
      mono: false,
      controls: [
        _chip(loc.convertReverse, false, () => _apply('reverse')),
        _chip(loc.convertUpper, false, () => _apply('upper')),
        _chip(loc.convertLower, false, () => _apply('lower')),
        _chip(loc.convertTitle, false, () => _apply('title')),
        _chip(loc.convertSwapCase, false, () => _apply('swap')),
      ],
    );
  }
}


// ---------------- Smali ----------------

class _SmaliTab extends StatefulWidget {
  const _SmaliTab();

  @override
  State<_SmaliTab> createState() => _SmaliTabState();
}

class _SmaliTabState extends State<_SmaliTab> {
  final _input = TextEditingController();
  String _out = '';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _apply(String mode) {
    final loc = AppLocalizations.of(context)!;
    final text = _input.text;
    if (text.trim().isEmpty) {
      setState(() => _out = '');
      return;
    }
    switch (mode) {
      case 'regex':
        setState(() => _out = SmaliTool.toRegex(text.trim()));
      case 'strings':
        final list = SmaliTool.extractStringConstants(text);
        setState(() => _out = list.isEmpty ? loc.convertInvalid : list.join('\n'));
      case 'invokes':
        final list = SmaliTool.extractInvocations(text);
        setState(() => _out = list.isEmpty ? loc.convertInvalid : list.join('\n'));
      case 'java':
        setState(() => _out = SmaliTool.descriptorsToJava(text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return _ToolScaffold(
      input: _input,
      inputHint: loc.convertSmaliHint,
      output: _out,
      controls: [
        _chip(loc.convertSmaliRegex, false, () => _apply('regex')),
        _chip(loc.convertSmaliStrings, false, () => _apply('strings')),
        _chip(loc.convertSmaliInvokes, false, () => _apply('invokes')),
        _chip(loc.convertSmaliJava, false, () => _apply('java')),
      ],
    );
  }
}
