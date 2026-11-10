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

// 哈希审计页：识别 hash 类型 + 字典/掩码恢复弱口令。
//
// 定位是**自有数据审计**：自家库导出、自己的取证镜像、自己搭的靶机。
// 界面上把话说清楚，不做成「拿到别人 hash 就能破」的样子。
//
// 引擎在 lib/utils/hash_audit.dart（纯 Dart，有单测）；这一层只做交互。

import 'dart:async';
import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, rootBundle;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/hash_audit.dart';

class HashAuditPage extends StatefulWidget {
  const HashAuditPage({super.key, this.initialText});

  /// 从别处（抓包详情）带进来的 hash。
  final String? initialText;

  static Future<void> show(BuildContext context, {String? text}) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HashAuditPage(initialText: text),
    ));
  }

  @override
  State<HashAuditPage> createState() => _HashAuditPageState();
}

class _HashAuditPageState extends State<HashAuditPage> {
  late final TextEditingController _input =
      TextEditingController(text: widget.initialText ?? '');
  final TextEditingController _mask = TextEditingController();

  List<HashTarget> _targets = const [];
  bool _useCommon = true;
  bool _useWords = false;
  int _ruleLevel = 0;
  final List<String> _localWords = [];

  HashCrackSession? _session;
  bool _running = false;
  int _tried = 0;
  int _foundCount = 0;
  DateTime? _startedAt;
  Timer? _ticker;
  final Map<String, String> _results = {};
  int _unsupportedCount = 0;

  static List<String>? _commonWords;
  static List<String>? _wordListWords;

  AppLocalizations get loc => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    // bcrypt 校验交给 bcrypt 包（utils 层不硬依赖它）
    HashAudit.bcryptImpl = (pw, hash) => BCrypt.checkpw(pw, hash);
    if ((widget.initialText ?? '').isNotEmpty) {
      _recognize();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _session?.cancel();
    _input.dispose();
    _mask.dispose();
    super.dispose();
  }

  void _toast(String msg, {Color color = Colors.blue}) {
    if (!mounted) return;
    FlutterToastr.show(msg, context, duration: 3, backgroundColor: color);
  }

  void _recognize() {
    final list = HashAudit.parseAll(_input.text);
    setState(() {
      _targets = list;
      _unsupportedCount = list.where((t) => !t.kind.recoverable).length;
    });
    if (list.isEmpty) {
      _toast(loc.hashAuditNoHash, color: Colors.orange);
    }
  }

  Future<List<String>> _loadAssetWords(String asset) async {
    final cached = asset.contains('common') ? _commonWords : _wordListWords;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(asset);
    final list = raw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (asset.contains('common')) {
      _commonWords = list;
    } else {
      _wordListWords = list;
    }
    return list;
  }

  Future<void> _pickDict() async {
    try {
      final picked = await FilePicker.pickFile(type: FileType.any);
      if (picked == null) return;
      final bytes = await picked.xFile.readAsBytes();
      if (!mounted) return;
      final text = utf8.decode(bytes, allowMalformed: true);
      final list = text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      setState(() => _localWords
        ..clear()
        ..addAll(list));
      _toast(loc.hashAuditDictLoaded(list.length), color: Colors.green);
    } catch (e) {
      _toast('${loc.fail}: $e', color: Colors.red);
    }
  }

  Future<void> _start() async {
    if (_targets.isEmpty) {
      _recognize();
      if (_targets.isEmpty) return;
    }
    final targets = _targets.where((t) => t.kind.recoverable).toList();
    if (targets.isEmpty) {
      _toast(loc.hashAuditNothingRecoverable, color: Colors.orange);
      return;
    }
    if (_session != null) {
      _toast(loc.hashAuditAlreadyRunning, color: Colors.orange);
      return;
    }
    setState(() {
      _running = true;
      _tried = 0;
      _foundCount = 0;
      _results.clear();
      _startedAt = DateTime.now();
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || !_running) return;
      setState(() {});
    });

    final words = <String>[];
    try {
      if (_useCommon) {
        words.addAll(await _loadAssetWords('assets/wordlists/common.txt'));
      }
      if (_useWords) {
        words.addAll(await _loadAssetWords('assets/wordlists/words.txt'));
      }
    } catch (e) {
      if (mounted) _toast('${loc.fail}: $e', color: Colors.red);
    }
    words.addAll(_localWords);

    final masks = _mask.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (words.isEmpty && masks.isEmpty) {
      setState(() => _running = false);
      _ticker?.cancel();
      _toast(loc.hashAuditNeedSource, color: Colors.orange);
      return;
    }

    final job = CrackJob(
      targets: targets,
      words: words,
      masks: masks,
      ruleLevel: _ruleLevel,
    );
    final session = await HashCrackSession.start(
      job,
      onProgress: (p) {
        if (!mounted) return;
        setState(() {
          _tried = p.tried;
          _foundCount = p.found;
        });
      },
      onFound: (raw, plain) {
        if (!mounted) return;
        setState(() => _results[raw] = plain);
      },
    );
    _session = session;
    await session.result;
    if (!mounted) return;
    _ticker?.cancel();
    setState(() {
      _running = false;
      _session = null;
    });
  }

  void _stop() {
    _session?.cancel();
    _ticker?.cancel();
    setState(() {
      _running = false;
      _session = null;
    });
  }

  String _elapsed() {
    final start = _startedAt;
    if (start == null) return '0.0s';
    final ms = DateTime.now().difference(start).inMilliseconds;
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }

  String _rate() {
    final start = _startedAt;
    if (start == null || _tried == 0) return '0';
    final sec = DateTime.now().difference(start).inMilliseconds / 1000.0;
    if (sec <= 0) return '0';
    final r = _tried / sec;
    if (r >= 1000000) return '${(r / 1000000).toStringAsFixed(2)}M/s';
    if (r >= 1000) return '${(r / 1000).toStringAsFixed(1)}K/s';
    return '${r.toStringAsFixed(0)}/s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.hashAudit, style: const TextStyle(fontSize: 15)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        children: [
          // 用途声明：这类工具最容易被误会，写在最上面
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.tertiaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(Icons.verified_user_outlined, size: 16, color: cs.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loc.hashAuditDesc,
                  style: TextStyle(fontSize: 11.5, height: 1.4, color: cs.onTertiaryContainer),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _input,
            maxLines: 7,
            minLines: 4,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
            decoration: InputDecoration(
              labelText: loc.hashAuditInput,
              hintText: loc.hashAuditInputHint,
              border: const OutlineInputBorder(),
              isDense: true,
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton.tonalIcon(
              onPressed: _running ? null : _recognize,
              icon: const Icon(Icons.search, size: 18),
              label: Text(loc.hashAuditRecognize),
            ),
            const SizedBox(width: 8),
            if (_running)
              OutlinedButton.icon(
                onPressed: _stop,
                icon: const Icon(Icons.stop, size: 18),
                label: Text(loc.hashAuditStop),
              )
            else
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(loc.hashAuditStart),
              ),
          ]),
          if (_targets.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('${loc.hashAuditRecognized(_targets.length)}'
                '${_unsupportedCount > 0 ? ' · ${loc.hashAuditUnsupported(_unsupportedCount)}' : ''}'),
            const SizedBox(height: 6),
            ..._targets.map((t) {
              final plain = _results[t.raw];
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    t.kind.recoverable ? Icons.check_circle_outline : Icons.info_outline,
                    size: 18,
                    color: t.kind.recoverable ? Colors.green : cs.outline,
                  ),
                  title: Text(
                    t.display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                  subtitle: Text(
                    '${t.kind.label}'
                    '${plain != null ? '  →  $plain' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: plain != null ? Colors.green : cs.onSurfaceVariant,
                      fontWeight: plain != null ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  trailing: plain == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: plain));
                            _toast(loc.copied);
                          },
                        ),
                ),
              );
            }),
          ],
          const SizedBox(height: 14),
          const Divider(height: 20),
          Text(loc.hashAuditAttack, style: const TextStyle(fontWeight: FontWeight.w600)),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _useCommon,
            onChanged: _running ? null : (v) => setState(() => _useCommon = v ?? false),
            title: Text(loc.hashAuditDictCommon, style: const TextStyle(fontSize: 13)),
            subtitle: Text(loc.hashAuditDictCommonHint,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _useWords,
            onChanged: _running ? null : (v) => setState(() => _useWords = v ?? false),
            title: Text(loc.hashAuditDictWords, style: const TextStyle(fontSize: 13)),
            subtitle: Text(loc.hashAuditDictWordsHint,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
          Row(children: [
            Expanded(
              child: Text(
                _localWords.isEmpty
                    ? loc.hashAuditDictNone
                    : loc.hashAuditDictLoaded(_localWords.length),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
            TextButton.icon(
              onPressed: _running ? null : _pickDict,
              icon: const Icon(Icons.file_open, size: 16),
              label: Text(loc.hashAuditImportDict, style: const TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 6),
          TextField(
            controller: _mask,
            maxLines: 3,
            minLines: 1,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
            decoration: InputDecoration(
              labelText: loc.hashAuditMask,
              hintText: '?l?l?l?l   ?u?l?l?l?d?d   ?d?d?d?d?d?d',
              helperText: loc.hashAuditMaskHint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final m in const ['?d?d?d?d', '?l?l?l?l', '?u?l?l?l?d?d', '?l?l?l?l?l?l'])
                ActionChip(
                  label: Text(m, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                  onPressed: _running
                      ? null
                      : () {
                          _mask.text = _mask.text.trim().isEmpty ? m : '${_mask.text.trim()}\n$m';
                          setState(() {});
                        },
                ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: _ruleLevel,
            isExpanded: true,
            isDense: true,
            decoration: InputDecoration(
              labelText: loc.hashAuditRules,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(value: 0, child: Text(loc.hashAuditRulesOff)),
              DropdownMenuItem(value: 1, child: Text(loc.hashAuditRulesBasic)),
              DropdownMenuItem(value: 2, child: Text(loc.hashAuditRulesLeet)),
            ],
            onChanged: _running ? null : (v) => setState(() => _ruleLevel = v ?? 0),
          ),
          if (_running || _tried > 0) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: null,
              minHeight: 3,
              backgroundColor: cs.surfaceContainerHighest,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${loc.hashAuditTried(_tried)} · ${_rate()} · ${_elapsed()}',
                    style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                  ),
                ),
                Text(
                  loc.hashAuditFoundCount(_foundCount),
                  style: TextStyle(
                      fontSize: 11.5,
                      color: _foundCount > 0 ? Colors.green : cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
