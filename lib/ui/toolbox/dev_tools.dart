/*
 * 开发者小工具集：JWT 解码 · UUID 生成 · SHA 哈希 · Cron 表达式
 * 统一浅排版、跟随主题，移动端/桌面端均可直接导航打开。
 */
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:proxypin/network/util/cron_expression.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';

/// 在工具箱展示的入口页：单页 Tab 形式，减少多页面跳转
class DevToolsPage extends StatefulWidget {
  final int initialIndex;

  const DevToolsPage({super.key, this.initialIndex = 0});

  @override
  State<StatefulWidget> createState() => _DevToolsPageState();
}

class _DevToolsPageState extends State<DevToolsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialIndex.clamp(0, 3));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.toolboxDevTools, style: const TextStyle(fontSize: 16)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: AppLocalizations.of(context)!.devToolCron),
            Tab(text: AppLocalizations.of(context)!.devToolJwt),
            const Tab(text: 'UUID'),
            Tab(text: AppLocalizations.of(context)!.devToolSha),
          ],
        ),
      ),
      body: TabBarView(controller: _tabController, children: const [
        CronToolPage(),
        JwtDecodePage(),
        UuidToolPage(),
        ShaHashPage(),
      ]),
    );
  }
}

// ==================== Cron 表达式 ====================

/// Cron 表达式工具：字段说明 + 常用示例 + 未来执行时间预览
/// 支持「分 时 日 月 星期」，通配符 * , - /
class CronToolPage extends StatefulWidget {
  const CronToolPage({super.key});

  @override
  State<StatefulWidget> createState() => _CronToolPageState();
}

class _CronToolPageState extends State<CronToolPage> {
  final TextEditingController _controller = TextEditingController(text: '0 9 * * 1-5');
  List<DateTime> _nextTimes = [];
  bool _error = false;

  static List<(String, String)> _examples(AppLocalizations loc) => [
    ('0 9 * * 1-5', loc.devToolCronExampleWorkday),
    ('30 8 1 * *', loc.devToolCronExampleMonthly),
    ('0 0 * * *', loc.devToolCronExampleMidnight),
    ('*/15 * * * *', loc.devToolCronExampleEvery15Min),
    ('0 */2 * * *', loc.devToolCronExampleEvery2Hours),
    ('0 12 * * 1', loc.devToolCronExampleMondayNoon),
  ];

  @override
  void initState() {
    super.initState();
    _evaluate(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _evaluate(String input) {
    final cron = CronExpression(input);
    final times = <DateTime>[];
    var t = DateTime.now();
    for (var i = 0; i < 6; i++) {
      final next = cron.next(t);
      if (next == null) {
        setState(() {
          _nextTimes = [];
          _error = true;
        });
        return;
      }
      times.add(next);
      t = next;
    }
    setState(() {
      _nextTimes = times;
      _error = false;
    });
  }


  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final fields = [
      (loc.devToolCronFieldMinute, '0-59'),
      (loc.devToolCronFieldHour, '0-23'),
      (loc.devToolCronFieldDay, '1-31'),
      (loc.devToolCronFieldMonth, '1-12'),
      (loc.devToolCronFieldWeek, loc.devToolCronFieldWeekRange),
    ];
    final input = _controller.text.trim();
    final parts = input.isEmpty ? <String>[] : input.split(RegExp(r'\s+'));

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: loc.devToolCron,
            hintText: loc.devToolCronHint,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.play_arrow, size: 20),
              tooltip: loc.devToolCronParse,
              onPressed: () => _evaluate(_controller.text),
            ),
          ),
          onSubmitted: _evaluate,
        ),
        const SizedBox(height: 6),
        if (_error)
          Text(loc.devToolCronParseError,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
        if (_nextTimes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(loc.devToolCronNextRuns,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 6),
          ..._nextTimes.map((t) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Icon(Icons.schedule, size: 15, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 6),
                  Text('${t.year}-'
                      '${t.month.toString().padLeft(2, '0')}-'
                      '${t.day.toString().padLeft(2, '0')} '
                      '${t.hour.toString().padLeft(2, '0')}:'
                      '${t.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 14)),
                ]),
              )),
        ],
        const Divider(height: 28),
        Text(loc.devToolCronFieldHelp, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
        const SizedBox(height: 6),
        Table(
          columnWidths: const {0: FlexColumnWidth(1.2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1.6)},
          border: TableBorder.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.3), width: 0.5),
          children: [
            for (final (i, f) in fields.indexed)
              TableRow(children: [
                Padding(padding: const EdgeInsets.all(6), child: Text(f.$1, style: const TextStyle(fontSize: 13))),
                Padding(padding: const EdgeInsets.all(6), child: Text(f.$2, style: const TextStyle(fontSize: 12, color: Colors.grey))),
                Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(parts.length > i ? parts[i] : '-', style: const TextStyle(fontSize: 12))),
              ]),
          ],
        ),
        const SizedBox(height: 8),
        Text(loc.devToolCronWildcardHint, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const Divider(height: 28),
        Text(loc.devToolCronExamples, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (expr, desc) in _examples(loc))
              ActionChip(
                label: Text(desc, style: const TextStyle(fontSize: 12)),
                tooltip: expr,
                onPressed: () {
                  _controller.text = expr;
                  _evaluate(expr);
                },
              ),
          ],
        ),
      ],
    );
  }
}

// ==================== JWT 解码 ====================

class JwtDecodePage extends StatefulWidget {
  const JwtDecodePage({super.key});

  @override
  State<StatefulWidget> createState() => _JwtDecodePageState();
}

class _JwtDecodePageState extends State<JwtDecodePage> {
  final TextEditingController _controller = TextEditingController();

  String? _header;
  String? _payload;
  String? _error;
  Map<String, dynamic>? _claims;

  void _decode(AppLocalizations loc) {
    setState(() {
      _header = null;
      _payload = null;
      _error = null;
      _claims = null;
    });
    final token = _controller.text.trim().replaceFirst(RegExp('^Bearer ', caseSensitive: false), '');
    final parts = token.split('.');
    if (parts.length < 2) {
      setState(() => _error = loc.devToolJwtInvalid);
      return;
    }
    try {
      final header = utf8.decode(_base64UrlDecode(parts[0]));
      final payload = utf8.decode(_base64UrlDecode(parts[1]));
      final headerMap = jsonDecode(header);
      final claims = payload.isEmpty ? null : jsonDecode(payload);
      setState(() {
        _header = const JsonEncoder.withIndent('  ').convert(headerMap);
        _payload = const JsonEncoder.withIndent('  ').convert(jsonDecode(payload));
        _claims = claims is Map<String, dynamic> ? claims : null;
      });
    } catch (e) {
      setState(() => _error = loc.devToolJwtDecodeFailed('$e'));
    }
  }

  /// 补齐 Base64Url padding
  List<int> _base64UrlDecode(String input) {
    var s = input.replaceAll('-', '+').replaceAll('_', '/');
    final pad = (4 - s.length % 4) % 4;
    s += '=' * pad;
    return base64.decode(s);
  }

  String? _expText() {
    final exp = _claims?['exp'];
    if (exp is! num) return null;
    final t = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
    final expired = t.isBefore(DateTime.now());
    final loc = AppLocalizations.of(context)!;
    return loc.devToolJwtExpiry('${t.toLocal()}',
        expired ? loc.devToolJwtExpired : loc.devToolJwtValid);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        TextField(
          controller: _controller,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.devToolJwtLabel,
            hintText: AppLocalizations.of(context)!.devToolJwtHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () => _decode(AppLocalizations.of(context)!),
          icon: const Icon(Icons.key, size: 18),
          label: Text(AppLocalizations.of(context)!.decode),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
        ],
        if (_header != null) ...[
          const SizedBox(height: 14),
          _section(AppLocalizations.of(context)!.jwtHeader, _header!),
        ],
        if (_payload != null) ...[
          const SizedBox(height: 12),
          _section(AppLocalizations.of(context)!.jwtPayload, _payload!),
        ],
        if (_expText() != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(AppLocalizations.of(context)!.devToolJwtExpLabel(_expText()!),
                style: const TextStyle(fontSize: 13)),
          ),
      ],
    );
  }

  Widget _section(String title, String body) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.copy, size: 16),
          tooltip: AppLocalizations.of(context)!.copy,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: body));
            FlutterToastr.show(AppLocalizations.of(context)!.aiCopied, context);
          },
        ),
      ]),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? Colors.black45 : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(body,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace', color: Color(0xFFD4D4D4))),
      ),
    ]);
  }
}

// ==================== UUID ====================

class UuidToolPage extends StatefulWidget {
  const UuidToolPage({super.key});

  @override
  State<StatefulWidget> createState() => _UuidToolPageState();
}

class _UuidToolPageState extends State<UuidToolPage> {
  final List<String> _uuids = [];
  final Random _random = Random();
  int _count = 5;
  bool _uppercase = false;

  String _gen() {
    String hex(int n) => List.generate(n, (_) => _random.nextInt(16).toRadixString(16)).join();
    var v = '${hex(8)}-${hex(4)}-4${hex(3)}-${hex(4)}-${hex(12)}';
    return _uppercase ? v.toUpperCase() : v;
  }

  void _generate() {
    setState(() => _uuids
      ..clear()
      ..addAll(List.generate(_count.clamp(1, 50), (_) => _gen())));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(children: [
          Text(AppLocalizations.of(context)!.devToolUuidCount, style: const TextStyle(fontSize: 14)),
          Expanded(
            child: Slider(
              value: _count.toDouble(),
              min: 1,
              max: 20,
              divisions: 19,
              label: '$_count',
              onChanged: (v) => setState(() => _count = v.round()),
            ),
          ),
          SwitchWidgetLite(
            value: _uppercase,
            label: AppLocalizations.of(context)!.devToolUuidUppercase,
            onChanged: (v) => setState(() => _uppercase = v),
          ),
        ]),
        FilledButton.icon(
          onPressed: _generate,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(AppLocalizations.of(context)!.devToolUuidGenerate),
        ),
        const SizedBox(height: 10),
        if (_uuids.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 30),
            child: Center(
                child: Text(AppLocalizations.of(context)!.devToolUuidEmpty,
                    style: TextStyle(color: Colors.grey.shade500))),
          )
        else
          ..._uuids.map((u) => Card(
                elevation: 0,
                margin: const EdgeInsets.symmetric(vertical: 3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.25)),
                ),
                child: ListTile(
                  dense: true,
                  title: Text(u, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                  trailing: const Icon(Icons.copy, size: 16),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: u));
                    FlutterToastr.show(AppLocalizations.of(context)!.aiCopied, context);
                  },
                ),
              )),
        if (_uuids.isNotEmpty)
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _uuids.join('\n')));
              FlutterToastr.show(AppLocalizations.of(context)!.devToolCopiedAll, context);
            },
            icon: const Icon(Icons.copy_all, size: 16),
            label: Text(AppLocalizations.of(context)!.devToolCopyAll),
          ),
      ],
    );
  }
}

/// 轻量开关（带文字标签）
class SwitchWidgetLite extends StatelessWidget {
  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  const SwitchWidgetLite({super.key, required this.value, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label, style: const TextStyle(fontSize: 13)),
      Switch(value: value, onChanged: onChanged),
    ]);
  }
}

// ==================== SHA 哈希 ====================

class ShaHashPage extends StatefulWidget {
  const ShaHashPage({super.key});

  @override
  State<StatefulWidget> createState() => _ShaHashPageState();
}

class _ShaHashPageState extends State<ShaHashPage> {
  final TextEditingController _controller = TextEditingController();

  Map<String, String> get _hashes {
    final input = utf8.encode(_controller.text);
    return {
      'SHA-1': sha1.convert(input).toString(),
      'SHA-256': sha256.convert(input).toString(),
      'SHA-512': sha512.convert(input).toString(),
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        TextField(
          controller: _controller,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.devToolShaInput,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        for (final entry in _hashes.entries) ...[
          Row(children: [
            Text(entry.key,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: AppLocalizations.of(context)!.copy,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: entry.value));
                FlutterToastr.show(AppLocalizations.of(context)!.aiCopied, context);
              },
            ),
          ]),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? Colors.black45 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(entry.value,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ),
          const SizedBox(height: 10),
        ],
        Text(AppLocalizations.of(context)!.devToolShaNote,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }
}
