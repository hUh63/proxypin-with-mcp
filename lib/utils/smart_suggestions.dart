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

import 'dart:math' as math;

import 'code_keywords.dart';

/// 「上下文 + 代码格式」感知的本地补全候选。
///
/// 编辑器内核的本地补全会把「文档里出现过的词」和宿主注入的关键字一起匹配；
/// 这里再往前一步：**根据光标此刻所处的语法位置**给出更贴合当下要写什么的候选。
///
/// * JSON：在 key 位置补文档里已有的 key；在值位置补 `true`/`false`/`null`；
/// * XML / HTML：`<` 后补文档里出现过的标签名，`</` 后补**还没闭合**的标签，
///   标签内部补文档里用过的属性名；
/// * YAML：补文档里已有的 key；
/// * 其它语言：按**缩进**判断你在行首还是块内，把声明类 / 语句类关键字分别提前。
///
/// 返回的候选由内核插到普通候选之前，并保持这里的先后顺序。
class SmartSuggestions {
  SmartSuggestions._();

  /// 扫描文档时最多回看的字符数，避免超大文档拖慢输入。
  static const int _maxScan = 120000;

  /// 一次最多返回的候选数。
  static const int _maxItems = 60;

  /// 语言无关的「声明类」关键字：常见于行首 / 无缩进处。
  static const Set<String> _declarationWords = {
    'class', 'interface', 'enum', 'struct', 'type', 'typedef', 'function', 'func', 'def',
    'const', 'let', 'var', 'final', 'static', 'public', 'private', 'protected', 'internal',
    'abstract', 'declare', 'namespace', 'package', 'import', 'export', 'include', 'extends',
    'implements', 'async', 'await', 'factory', 'operator', 'extension',
    'CREATE', 'TABLE', 'INDEX', 'VIEW', 'ALTER', 'INSERT',
  };

  /// 语言无关的「语句类」关键字：常见于缩进块内。
  static const Set<String> _statementWords = {
    'if', 'else', 'elif', 'for', 'while', 'do', 'switch', 'case', 'default', 'break',
    'continue', 'return', 'try', 'catch', 'except', 'finally', 'throw', 'raise', 'yield',
    'delete', 'print', 'echo', 'with', 'in', 'of', 'is',
    'SELECT', 'FROM', 'WHERE', 'JOIN', 'ON', 'GROUP', 'BY', 'ORDER', 'HAVING', 'LIMIT',
  };

  /// 生成候选。
  ///
  /// [language] 为编辑器当前的语法名（如 `JSON`、`XML / HTML`、`Dart`）；
  /// [documentText] 是整篇文档；[linePrefix] 是光标所在行、光标之前的文本；
  /// [prefix] 是光标前正在输入的那个词的前缀。
  static List<String> suggest({
    required String? language,
    required String documentText,
    required String linePrefix,
    required String prefix,
  }) {
    switch (language ?? '') {
      case 'JSON':
        return _json(documentText, linePrefix, prefix);
      case 'XML / HTML':
        return _xml(documentText, linePrefix, prefix);
      case 'YAML':
        return _yaml(documentText, prefix);
      default:
        return _generic(linePrefix, prefix, language ?? '');
    }
  }

  // ---------------------------------------------------------------------------
  // JSON
  // ---------------------------------------------------------------------------

  static List<String> _json(String doc, String linePrefix, String prefix) {
    final trimmed = linePrefix.trimRight();
    // 值位置：`"key":` 之后（冒号后还没写值）。
    if (RegExp(r':\s*$').hasMatch(trimmed)) {
      return _dedupe(const ['true', 'false', 'null'], prefix);
    }
    // key 位置（行首、`{`、`,`、`"` 之后）：补文档里已有的 key。
    return _dedupe(_jsonKeys(doc), prefix);
  }

  static final RegExp _jsonKeyRe = RegExp(r'"((?:[^"\\\n]|\\.){1,80})"\s*:');

  static List<String> _jsonKeys(String doc) {
    final out = <String>[];
    for (final m in _jsonKeyRe.allMatches(_tail(doc))) {
      out.add(m.group(1)!);
      if (out.length > 400) break;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // XML / HTML
  // ---------------------------------------------------------------------------

  static List<String> _xml(String doc, String linePrefix, String prefix) {
    final tail = _tail(doc);
    final trimmed = linePrefix.trimRight();
    final lt = trimmed.lastIndexOf('<');
    final gt = trimmed.lastIndexOf('>');
    // 光标是否落在一个还没闭合的 `<...` 里面。
    final inTag = lt > gt;
    if (!inTag) {
      // 不在标签里（比如刚写完文本），补文档里出现过的标签名。
      return _dedupe(_xmlTags(tail), prefix);
    }
    final inTagText = trimmed.substring(lt);
    if (inTagText.startsWith('</')) {
      // 闭合标签：补还没有配对的标签，最近打开的最靠前。
      return _dedupe(_unclosedTags(tail), prefix);
    }
    // 标签名之后（出现空白）就是属性位置。
    if (RegExp(r'^<\s*[A-Za-z_][\w:.-]*\s+[^>]*$').hasMatch(inTagText)) {
      return _dedupe([..._xmlAttrs(tail), ..._commonAttrs], prefix);
    }
    return _dedupe([..._xmlTags(tail), ..._commonTags], prefix);
  }

  static const List<String> _commonTags = [
    'div', 'span', 'p', 'a', 'img', 'ul', 'li', 'table', 'tr', 'td', 'input', 'button',
    'item', 'value', 'name', 'entry', 'id', 'type', 'label', 'header', 'body', 'section',
  ];

  static const List<String> _commonAttrs = [
    'id', 'name', 'class', 'type', 'value', 'href', 'src', 'title', 'style', 'width',
    'height', 'target', 'rel', 'placeholder', 'disabled', 'checked', 'xmlns', 'version',
  ];

  static final RegExp _xmlTagRe = RegExp(r'<\s*/?\s*([A-Za-z_][\w:.-]*)');
  static final RegExp _xmlAttrRe = RegExp(r'\s([A-Za-z_][\w:.-]*)\s*=');
  static final RegExp _xmlPairRe = RegExp(
    r'''<\s*(/?)\s*([A-Za-z_][\w:.-]*)((?:"[^"]*"|'[^']*'|[^>])*)>''',
  );

  static List<String> _xmlTags(String doc) {
    final out = <String>[];
    for (final m in _xmlTagRe.allMatches(doc)) {
      out.add(m.group(1)!);
      if (out.length > 400) break;
    }
    return out;
  }

  static List<String> _xmlAttrs(String doc) {
    final out = <String>[];
    for (final m in _xmlAttrRe.allMatches(doc)) {
      out.add(m.group(1)!);
      if (out.length > 200) break;
    }
    return out;
  }

  /// 文档里「开了还没关」的标签，最近打开的排在最前。
  static List<String> _unclosedTags(String doc) {
    const voidTags = {
      'br', 'img', 'input', 'meta', 'link', 'hr', 'area', 'base', 'col', 'embed',
      'source', 'track', 'wbr',
    };
    final stack = <String>[];
    for (final m in _xmlPairRe.allMatches(doc)) {
      final closing = (m.group(1) ?? '') == '/';
      final name = m.group(2)!;
      final rest = m.group(3) ?? '';
      if (closing) {
        final at = stack.lastIndexOf(name);
        if (at >= 0) stack.removeRange(at, stack.length);
      } else if (!rest.trimRight().endsWith('/') &&
          !voidTags.contains(name.toLowerCase())) {
        stack.add(name);
      }
    }
    return stack.reversed.toList();
  }

  // ---------------------------------------------------------------------------
  // YAML
  // ---------------------------------------------------------------------------

  static final RegExp _yamlKeyRe = RegExp(r'^[ \t-]*([A-Za-z_][\w.\-]*)\s*:', multiLine: true);

  static List<String> _yaml(String doc, String prefix) {
    final out = <String>[];
    for (final m in _yamlKeyRe.allMatches(_tail(doc))) {
      out.add(m.group(1)!);
      if (out.length > 400) break;
    }
    return _dedupe(out, prefix);
  }

  // ---------------------------------------------------------------------------
  // 通用：按缩进决定「声明类 / 语句类」的先后
  // ---------------------------------------------------------------------------

  static List<String> _generic(String linePrefix, String prefix, String language) {
    final words = CodeKeywords.forLanguage(language);
    if (words.isEmpty) return const [];
    final indent = linePrefix.length - linePrefix.trimLeft().length;
    final declarationFirst = indent == 0;
    final head = <String>[];
    final tailWords = <String>[];
    for (final w in words) {
      final isDecl = _declarationWords.contains(w);
      final isStmt = _statementWords.contains(w);
      if (isDecl && !isStmt) {
        (declarationFirst ? head : tailWords).add(w);
      } else if (isStmt && !isDecl) {
        (declarationFirst ? tailWords : head).add(w);
      } else {
        tailWords.add(w);
      }
    }
    return _dedupe([...head, ...tailWords], prefix);
  }

  // ---------------------------------------------------------------------------
  // 工具
  // ---------------------------------------------------------------------------

  /// 只看文档尾部，避免超大文档全量扫描。
  static String _tail(String doc) =>
      doc.length <= _maxScan ? doc : doc.substring(doc.length - _maxScan);

  static List<String> _dedupe(Iterable<String> items, String prefix) {
    final lowerPrefix = prefix.toLowerCase();
    final seen = <String>{};
    final out = <String>[];
    for (final raw in items) {
      final s = raw.trim();
      if (s.isEmpty || s == prefix) continue;
      if (prefix.isNotEmpty && !s.toLowerCase().startsWith(lowerPrefix)) continue;
      if (!seen.add(s)) continue;
      out.add(s);
      if (out.length >= _maxItems) break;
    }
    return out;
  }
}
