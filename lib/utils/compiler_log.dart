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

// 编译日志解析：把 gcc / clang / cl（MSVC）的输出切成一条条诊断。
//
// 只认「文件:行:列: 等级: 消息」这几种最常见形态；其余行（include 链、
// 代码片段、脱字符 ^）作为上一条的「补充」保留，不丢信息。
// 消息本体交给 [CompilerZh] 翻成中文，原文照样留着（搜报错时要用英文）。

import 'package:proxypin/utils/compiler_zh.dart';

enum CompilerSeverity { error, warning, note }

class CompilerLogEntry {
  final String file;
  final int? line;
  final int? column;
  final String severityCode; // error / fatal error / warning / note
  final String message; // 中文
  final String original; // 英文原文
  final String detail; // 后续续行（代码片段、建议等），原文

  const CompilerLogEntry({
    required this.file,
    required this.line,
    required this.column,
    required this.severityCode,
    required this.message,
    required this.original,
    this.detail = '',
  });

  CompilerSeverity get severity {
    final s = severityCode.toLowerCase();
    if (s.contains('error')) return CompilerSeverity.error;
    if (s.contains('warning')) return CompilerSeverity.warning;
    return CompilerSeverity.note;
  }

  String get position {
    if (line == null) return file;
    return column == null ? '$file:$line' : '$file:$line:$column';
  }
}

class CompilerLogResult {
  final List<CompilerLogEntry> entries;
  final String translated; // 整段中文（含非诊断行）

  const CompilerLogResult(this.entries, this.translated);

  int get errors =>
      entries.where((e) => e.severity == CompilerSeverity.error).length;
  int get warnings =>
      entries.where((e) => e.severity == CompilerSeverity.warning).length;
}

/// gcc / clang：`file.c:12:5: error: message`
final RegExp _gnuRe = RegExp(
  r'^(.*?):(\d+)(?::(\d+))?:\s*(fatal error|error|warning|note|remark)\s*:\s*(.*)$',
  caseSensitive: false,
);

/// MSVC：`file.cpp(12): error C2065: message`
final RegExp _msvcRe = RegExp(
  r'^(.*?)\((\d+)(?:,(\d+))?\)\s*:\s*(fatal error|error|warning|note)\s*([A-Za-z]+\d+)?\s*:\s*(.*)$',
  caseSensitive: false,
);

/// 解析并翻译。返回的 [CompilerLogResult.translated] 是整段中文（保留原行序）。
Future<CompilerLogResult> parseCompilerLog(String text) async {
  final zh = CompilerZh.instance;
  await zh.ensureLoaded();

  final entries = <CompilerLogEntry>[];
  final out = StringBuffer();
  final lines = text.split('\n');
  var lastIndex = -1;
  String? pendingDetail;

  void flushDetail() {
    if (lastIndex >= 0 && pendingDetail != null && pendingDetail!.trim().isNotEmpty) {
      final e = entries[lastIndex];
      entries[lastIndex] = CompilerLogEntry(
        file: e.file,
        line: e.line,
        column: e.column,
        severityCode: e.severityCode,
        message: e.message,
        original: e.original,
        detail: '${e.detail}${e.detail.isEmpty ? '' : '\n'}${pendingDetail!.trimRight()}',
      );
    }
    pendingDetail = null;
  }

  for (final raw in lines) {
    if (raw.trim().isEmpty) {
      flushDetail();
      out.writeln(raw);
      continue;
    }
    final gnu = _gnuRe.firstMatch(raw);
    final msvc = gnu == null ? _msvcRe.firstMatch(raw) : null;
    if (gnu != null || msvc != null) {
      flushDetail();
      final m = gnu ?? msvc!;
      final file = m.group(1)!.trim();
      final line = int.tryParse(m.group(2) ?? '');
      final column = int.tryParse(m.group(3) ?? '');
      final sev = m.group(4) ?? 'error';
      final code = gnu == null ? (m.group(5) ?? '').trim() : '';
      final body = (m.group(gnu != null ? 5 : 6) ?? '').trim();
      // MSVC 的错误码（C2065）保留在消息里，用户搜报错时常常就是搜它。
      final msg = code.isEmpty ? body : '$code: $body';
      final translated = zh.translateLine(msg);
      entries.add(CompilerLogEntry(
        file: file,
        line: line,
        column: column,
        severityCode: sev,
        message: translated,
        original: msg,
      ));
      lastIndex = entries.length - 1;
      // 输出行：把位置和「等级」保留，消息换成中文。
      final pos = column == null ? '$file:$line' : '$file:$line:$column';
      out.writeln('$pos: $sev: $translated');
      continue;
    }
    // 非诊断行：可能是代码片段 / 建议 / include 链
    if (lastIndex >= 0 && (raw.startsWith(' ') || raw.startsWith('\t') || raw.startsWith('^'))) {
      pendingDetail = '${pendingDetail ?? ''}$raw\n';
      out.writeln(raw);
      continue;
    }
    flushDetail();
    out.writeln(zh.translateLine(raw));
  }
  flushDetail();
  return CompilerLogResult(entries, out.toString());
}
