/// 行内 AI 补全（Copilot 式的 ghost text）。
///
/// 只用一次短请求：把光标前后一小段代码发过去，让模型只回「接下来该插什么」，
/// 拿回来交给内核的 `setGhostText` 画成灰字，Tab 接受、Esc 放弃。
///
/// 这里刻意不做多轮、不做上下文索引 —— 行内补全的价值全在「快」，
/// 请求一旦超过一两秒，用户早就自己打完了。
library;

import 'package:proxypin/network/components/ai_analyzer.dart';

/// 一次补全请求的结果：成功给 [text]，失败给 [error]（已是可直接展示的中文）。
class InlineCompletion {
  final String? text;
  final String? error;

  const InlineCompletion({this.text, this.error});

  bool get ok => text != null && text!.isNotEmpty;
}

const String _systemPrompt = '''
You are an inline code completion engine inside a text editor.
The user gives you the code BEFORE the cursor and a short snippet AFTER it.
Reply with ONLY the text that should be inserted at the cursor position.

Rules:
- Never repeat code that already appears before the cursor.
- No explanations, no markdown, no code fences, no language tags.
- Keep it short: at most 10 lines, and stop at a natural boundary
  (end of statement, end of block, or where the AFTER snippet begins).
- Match the surrounding indentation exactly.
- If nothing sensible can be added, reply with a single character: nothing.
''';

/// 「没什么可补」时模型被要求回这个词，这里据此判空。
const String _nothingMarker = 'nothing';

/// 请求一段行内补全。
///
/// [before] 建议给光标前 1~2KB，[after] 给后面 200~500 字符（用来判断该停在哪儿）。
Future<InlineCompletion> requestInlineCompletion({
  required String before,
  required String after,
  required String language,
}) async {
  final buffer = StringBuffer();
  buffer.writeln('Language: ${language.isEmpty ? 'plain text' : language}');
  buffer.writeln('--- BEFORE CURSOR ---');
  buffer.writeln(before);
  buffer.writeln('--- CURSOR HERE ---');
  if (after.trim().isNotEmpty) {
    buffer.writeln('--- AFTER CURSOR ---');
    buffer.writeln(after);
  }
  try {
    final raw = await AiAnalyzer.chat(
      [
        {'role': 'user', 'content': buffer.toString()},
      ],
      systemOverride: _systemPrompt,
    );
    final cleaned = sanitizeCompletion(raw);
    if (cleaned == null) {
      // 模型回了空/「nothing」：不是错误，只是没得补，交给 UI 用本地文案提示。
      return const InlineCompletion();
    }
    return InlineCompletion(text: cleaned);
  } catch (e) {
    return InlineCompletion(error: '$e');
  }
}

/// 清洗模型输出：去围栏、去「重复的已有前缀」、限行数、去首尾空行。
///
/// 抽成纯函数是为了能单测：模型输出的花样太多，光靠 prompt 约束不住。
String? sanitizeCompletion(String raw, {String? currentLinePrefix, int maxLines = 12}) {
  var s = raw.replaceAll('\r\n', '\n').trim();
  if (s.isEmpty) return null;

  // ```dart ... ``` 围栏（模型最常见的「不听话」）
  final fence = RegExp(r'^```[^\n]*\n([\s\S]*?)\n?```$');
  final m = fence.firstMatch(s);
  if (m != null) s = m.group(1)!.trim();

  // 模型偶尔会把整行（含光标前的部分）原样返回，去掉重复部分只留新增。
  final prefix = currentLinePrefix ?? '';
  if (prefix.trim().isNotEmpty && s.startsWith(prefix)) {
    s = s.substring(prefix.length);
  }

  if (s.trim().toLowerCase() == _nothingMarker) return null;

  // 去掉首尾空行（中间的空行是代码的一部分，不能动）
  final lines = s.split('\n');
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  if (lines.isEmpty) return null;
  if (lines.length > maxLines) {
    return lines.take(maxLines).join('\n');
  }
  return lines.join('\n');
}
