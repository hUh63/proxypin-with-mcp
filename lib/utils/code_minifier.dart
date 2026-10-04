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

import 'package:proxypin/utils/lang.dart';

/// 代码「压缩」工具（保守实现）。
///
/// 与格式化相反，这里只做**不改变语义**的收缩：删注释、去缩进、合并多余空白，
/// 不做变量重命名、死代码消除等需要完整 AST 的激进优化——本工具没有内置各语言的
/// 编译器前端，一旦激进变换算错就会悄悄改坏用户代码。
///
/// 各语言策略：
/// - JSON：委托 `JSON.compact`（解析失败原样返回）；
/// - CSS：删注释 + 去缩进 + 合并空白 + 去掉 `{};:,` 周围空白；
///   `calc(...)` 内运算符两侧的空格**保留**，否则会算错；
/// - HTML / XML：删注释（保留 IE 条件注释）+ 合并空白；
///   `<pre>` / `<textarea>` / `<script>` / `<style>` 内部**原样保留**；
/// - JavaScript / TypeScript：删注释 + 去缩进 + 合并行内空白，**换行全部保留**
///   （因此 ASI 行为不变）；字符串 / 模板串 / 正则字面量内部逐字符保留。
class CodeMinifier {
  CodeMinifier._();

  static const Set<String> _supported = {'JSON', 'CSS', 'XML / HTML', 'JavaScript', 'TypeScript'};

  static bool supports(String langLabel) => _supported.contains(langLabel);

  /// 压缩；不支持的语言返回 null。
  static String? minify(String langLabel, String text) {
    if (text.trim().isEmpty) return text;
    switch (langLabel) {
      case 'JSON':
        return JSON.compact(text);
      case 'CSS':
        return _minifyCss(text);
      case 'XML / HTML':
        return _minifyMarkup(text);
      case 'JavaScript':
      case 'TypeScript':
        return _minifyJs(text);
      default:
        return null;
    }
  }

  static bool _isSpace(int code) =>
      code == 0x20 || code == 0x09 || code == 0x0D || code == 0x0C;

  static bool _isWordChar(String c) =>
      c.isNotEmpty && (RegExp(r'[A-Za-z0-9_$]').hasMatch(c));

  // ------------------------------ CSS ------------------------------

  static String _minifyCss(String src) {
    final out = StringBuffer();
    var i = 0;
    var pendingSpace = false;
    var lastChar = '';

    void writeChar(String c) {
      out.write(c);
      lastChar = c;
    }

    while (i < src.length) {
      final c = src[i];

      // 注释
      if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
        final end = src.indexOf('*/', i + 2);
        i = end < 0 ? src.length : end + 2;
        pendingSpace = true;
        continue;
      }
      // 字符串 / url() 内容原样保留
      if (c == '"' || c == "'") {
        final start = i;
        i++;
        while (i < src.length) {
          if (src[i] == '\\') {
            i += 2;
            continue;
          }
          if (src[i] == c) {
            i++;
            break;
          }
          i++;
        }
        writeChar(src.substring(start, i));
        pendingSpace = false;
        continue;
      }
      if (_isSpace(src.codeUnitAt(i)) || c == '\n') {
        pendingSpace = true;
        i++;
        continue;
      }

      final tight = const {'{', '}', ';', ':', ','}.contains(c);
      if (pendingSpace && !tight && lastChar.isNotEmpty && !const {'{', '}', ';', ':', ','}.contains(lastChar)) {
        writeChar(' ');
      }
      pendingSpace = false;
      writeChar(c);
      i++;
    }
    return out.toString().trim();
  }

  // -------------------------- HTML / XML --------------------------

  static const List<String> _preformatted = ['pre', 'textarea', 'script', 'style'];

  static String _minifyMarkup(String src) {
    final out = StringBuffer();
    var i = 0;
    var pendingSpace = false;
    var lastChar = '';
    String? protectUntil;

    void writeChar(String s) {
      out.write(s);
      if (s.isNotEmpty) lastChar = s[s.length - 1];
    }

    while (i < src.length) {
      // pre / textarea / script / style 内部原样输出
      if (protectUntil != null) {
        final idx = src.toLowerCase().indexOf('</$protectUntil', i);
        if (idx < 0) {
          writeChar(src.substring(i));
          break;
        }
        writeChar(src.substring(i, idx));
        i = idx;
        protectUntil = null;
        continue;
      }

      // 注释
      if (src.startsWith('<!--', i)) {
        final end = src.indexOf('-->', i + 4);
        final body = end < 0 ? src.substring(i) : src.substring(i, end + 3);
        i = end < 0 ? src.length : end + 3;
        // 保留 IE 条件注释
        if (body.contains('[if') || body.contains('[endif')) writeChar(body);
        pendingSpace = true;
        continue;
      }

      if (src[i] == '<') {
        final end = src.indexOf('>', i);
        final tag = end < 0 ? src.substring(i) : src.substring(i, end + 1);
        if (pendingSpace && lastChar.isNotEmpty && !lastChar.contains('>')) writeChar(' ');
        pendingSpace = false;
        writeChar(tag);
        i = end < 0 ? src.length : end + 1;

        final m = RegExp(r'^<\s*([a-zA-Z][\w:-]*)').firstMatch(tag);
        if (m != null && !tag.startsWith('</') && !tag.endsWith('/>')) {
          final name = m.group(1)!.toLowerCase();
          if (_preformatted.contains(name)) protectUntil = name;
        }
        continue;
      }

      if (_isSpace(src.codeUnitAt(i)) || src[i] == '\n') {
        pendingSpace = true;
        i++;
        continue;
      }

      if (pendingSpace && lastChar.isNotEmpty) writeChar(' ');
      pendingSpace = false;
      writeChar(src[i]);
      i++;
    }
    return out.toString().trim();
  }

  // ------------------------ JavaScript / TS ------------------------

  /// `return /re/` 这类需要按正则解析的上下文关键字。
  static const Set<String> _regexKeywords = {
    'return', 'typeof', 'instanceof', 'in', 'of', 'new', 'delete', 'void',
    'throw', 'case', 'do', 'else', 'yield', 'await',
  };

  static String _minifyJs(String src) {
    final out = StringBuffer();
    var i = 0;
    var pendingSpace = false;
    var lineHasContent = false;
    var lastChar = '';
    final word = StringBuffer();

    void push(String s) {
      out.write(s);
      if (s.isNotEmpty) {
        lastChar = s[s.length - 1];
        if (_isWordChar(lastChar)) {
          word.write(lastChar);
        } else {
          word.clear();
        }
      }
      lineHasContent = true;
      pendingSpace = false;
    }

    void endLine() {
      if (lineHasContent) {
        out.write('\n');
        lastChar = '\n';
        word.clear();
      }
      lineHasContent = false;
      pendingSpace = false;
    }

    bool regexAllowed() {
      if (lastChar.isEmpty) return true;
      if (word.length > 0 && _regexKeywords.contains(word.toString())) return true;
      return '([{,;:=!&|?+-*%~^<>'.contains(lastChar);
    }

    while (i < src.length) {
      final c = src[i];

      // 换行
      if (c == '\n') {
        endLine();
        i++;
        continue;
      }
      if (_isSpace(src.codeUnitAt(i))) {
        pendingSpace = true;
        i++;
        continue;
      }

      // 行注释
      if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
        final end = src.indexOf('\n', i);
        i = end < 0 ? src.length : end;
        pendingSpace = true;
        continue;
      }
      // 块注释（含换行时按换行处理，保住 ASI）
      if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
        final end = src.indexOf('*/', i + 2);
        final stop = end < 0 ? src.length : end + 2;
        final hasNewline = src.substring(i, stop).contains('\n');
        i = stop;
        pendingSpace = true;
        if (hasNewline) endLine();
        continue;
      }

      // 字符串
      if (c == '"' || c == "'") {
        final start = i;
        i++;
        while (i < src.length) {
          if (src[i] == '\\') {
            i += 2;
            continue;
          }
          if (src[i] == c) {
            i++;
            break;
          }
          i++;
        }
        push(src.substring(start, i));
        continue;
      }

      // 模板字符串（含 ${} 内插，整体原样保留）
      if (c == '`') {
        final start = i;
        i++;
        var depth = 0;
        while (i < src.length) {
          final d = src[i];
          if (d == '\\') {
            i += 2;
            continue;
          }
          if (d == r'$' && i + 1 < src.length && src[i + 1] == '{') {
            depth++;
            i += 2;
            continue;
          }
          if (d == '}' && depth > 0) {
            depth--;
            i++;
            continue;
          }
          if (d == '`' && depth == 0) {
            i++;
            break;
          }
          i++;
        }
        push(src.substring(start, i));
        continue;
      }

      // 正则字面量
      if (c == '/' && regexAllowed()) {
        final start = i;
        i++;
        var closed = false;
        var inClass = false;
        while (i < src.length) {
          final d = src[i];
          if (d == '\\') {
            i += 2;
            continue;
          }
          if (d == '\n') break;
          if (d == '[') {
            inClass = true;
          } else if (d == ']') {
            inClass = false;
          } else if (d == '/' && !inClass) {
            i++;
            closed = true;
            break;
          }
          i++;
        }
        if (closed) {
          while (i < src.length && RegExp(r'[a-z]').hasMatch(src[i])) {
            i++;
          }
          push(src.substring(start, i));
          continue;
        }
        i = start; // 未闭合：按除号走下面的通用分支
      }

      // 通用字符
      if (pendingSpace && lineHasContent && lastChar.isNotEmpty) {
        final needSpace = (_isWordChar(lastChar) && _isWordChar(c)) ||
            (lastChar == '+' && c == '+') ||
            (lastChar == '-' && c == '-');
        if (needSpace) out.write(' ');
      }
      pendingSpace = false;
      out.write(c);
      lastChar = c;
      lineHasContent = true;
      if (_isWordChar(c)) {
        word.write(c);
      } else {
        word.clear();
      }
      i++;
    }

    return out.toString().trim();
  }
}
