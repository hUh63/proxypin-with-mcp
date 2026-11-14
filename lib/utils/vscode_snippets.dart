import 'dart:convert';

import 'package:proxypin/utils/tool_snippets.dart';

/// 解析 VS Code 的 `.code-snippets`（或 `.tpl.json`）片段文件。
///
/// 支持两种形态：
/// 1. 单个片段：`{ "name": "...", "prefix": "log", "body": ["..."], "scope": "..." }`
/// 2. 片段集合：`{ "打印日志": { "prefix": "log", "body": ["..."] }, ... }`
///
/// `body` 里的 `$1` / `${1:默认值}` / `$TM_FILENAME` 原样保留 ——
/// 编辑器的片段引擎本来就支持这套占位符与变量，不做转译反而不会变形。
List<ToolSnippet> parseVSCodeSnippets(String raw) {
  dynamic json;
  try {
    json = jsonDecode(raw);
  } catch (_) {
    return const <ToolSnippet>[];
  }
  if (json is! Map) return const <ToolSnippet>[];
  if (json.containsKey('body')) {
    final one = _build('', json);
    return one == null ? const <ToolSnippet>[] : <ToolSnippet>[one];
  }
  final out = <ToolSnippet>[];
  for (final entry in json.entries) {
    final v = entry.value;
    if (v is! Map) continue;
    final s = _build('${entry.key}', v);
    if (s != null) out.add(s);
  }
  return out;
}

ToolSnippet? _build(String fallbackLabel, Map<dynamic, dynamic> m) {
  final body = m['body'];
  var text = '';
  if (body is List) {
    text = body.map((e) => '$e').join('\n');
  } else if (body is String) {
    text = body;
  }
  if (text.trim().isEmpty) return null;

  final prefix = (m['prefix'] ?? '').toString().trim();
  final desc = (m['description'] ?? '').toString().trim();
  var label = fallbackLabel.trim();
  if (label.isEmpty) label = prefix.isNotEmpty ? prefix : desc;
  if (label.isEmpty) label = 'snippet';
  return ToolSnippet(label, text);
}
