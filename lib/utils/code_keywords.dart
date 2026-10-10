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

/// 各语言的常用关键字 / 保留字。
///
/// 作为本地代码补全（`enableLocalSuggestions`）的**额外候选**，与「文档里出现过的词」
/// 一起参与匹配：这样即使文档还几乎是空的，也能补出 `function` / `SELECT` / `class` 这类词。
/// 只放纯标识符，不放带空格/换行的片段，避免污染候选列表。
class CodeKeywords {
  CodeKeywords._();

  static const List<String> javascript = [
    'const', 'let', 'var', 'function', 'return', 'if', 'else', 'for', 'while', 'do',
    'switch', 'case', 'default', 'break', 'continue', 'new', 'class', 'extends', 'super',
    'this', 'typeof', 'instanceof', 'try', 'catch', 'finally', 'throw', 'async', 'await',
    'import', 'export', 'from', 'delete', 'void', 'yield', 'of', 'in', 'null', 'undefined',
    'true', 'false', 'console', 'JSON', 'Promise', 'Object', 'Array', 'Math', 'String',
    'Number', 'Boolean', 'Map', 'Set', 'length', 'push', 'map', 'filter', 'reduce',
  ];

  static const List<String> typescript = [
    'interface', 'type', 'enum', 'implements', 'private', 'public', 'protected', 'readonly',
    'abstract', 'declare', 'namespace', 'any', 'unknown', 'never', 'string', 'number',
    'boolean', 'object', 'void', 'as', 'const', 'let', 'var', 'function', 'return', 'class',
    'extends', 'implements', 'import', 'export', 'from', 'async', 'await', 'null', 'undefined',
    'true', 'false', 'Promise', 'Record', 'Partial', 'Readonly', 'Array',
  ];

  static const List<String> dart = [
    'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch', 'class', 'const',
    'continue', 'covariant', 'default', 'deferred', 'do', 'dynamic', 'else', 'enum', 'export',
    'extends', 'extension', 'external', 'factory', 'false', 'final', 'finally', 'for', 'get',
    'hide', 'if', 'implements', 'import', 'in', 'interface', 'is', 'late', 'library', 'mixin',
    'new', 'null', 'on', 'operator', 'part', 'required', 'rethrow', 'return', 'set', 'show',
    'static', 'super', 'switch', 'sync', 'this', 'throw', 'true', 'try', 'typedef', 'var',
    'void', 'while', 'with', 'yield', 'Future', 'Stream', 'List', 'Map', 'Set', 'String',
    'int', 'double', 'bool', 'Widget', 'BuildContext',
  ];

  static const List<String> python = [
    'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue', 'def', 'del',
    'elif', 'else', 'except', 'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is',
    'lambda', 'None', 'nonlocal', 'not', 'or', 'pass', 'raise', 'return', 'True', 'False',
    'try', 'while', 'with', 'yield', 'self', 'print', 'len', 'range', 'str', 'int', 'float',
    'list', 'dict', 'set', 'tuple', 'enumerate', 'zip',
  ];

  static const List<String> java = [
    'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char', 'class',
    'const', 'continue', 'default', 'do', 'double', 'else', 'enum', 'extends', 'final',
    'finally', 'float', 'for', 'if', 'implements', 'import', 'instanceof', 'int', 'interface',
    'long', 'native', 'new', 'package', 'private', 'protected', 'public', 'return', 'short',
    'static', 'super', 'switch', 'synchronized', 'this', 'throw', 'throws', 'transient', 'try',
    'void', 'volatile', 'while', 'true', 'false', 'null', 'String', 'Integer', 'List', 'Map',
  ];

  static const List<String> go = [
    'break', 'case', 'chan', 'const', 'continue', 'default', 'defer', 'else', 'fallthrough',
    'for', 'func', 'go', 'goto', 'if', 'import', 'interface', 'map', 'package', 'range',
    'return', 'select', 'struct', 'switch', 'type', 'var', 'nil', 'true', 'false', 'make',
    'new', 'len', 'cap', 'append', 'copy', 'delete', 'panic', 'recover', 'string', 'int',
    'bool', 'byte', 'rune', 'error',
  ];

  static const List<String> sql = [
    'SELECT', 'FROM', 'WHERE', 'JOIN', 'LEFT', 'RIGHT', 'INNER', 'OUTER', 'CROSS', 'ON',
    'GROUP', 'BY', 'ORDER', 'HAVING', 'LIMIT', 'OFFSET', 'INSERT', 'INTO', 'VALUES', 'UPDATE',
    'SET', 'DELETE', 'CREATE', 'TABLE', 'ALTER', 'DROP', 'INDEX', 'VIEW', 'AS', 'AND', 'OR',
    'NOT', 'NULL', 'DISTINCT', 'COUNT', 'SUM', 'AVG', 'MIN', 'MAX', 'LIKE', 'BETWEEN',
    'EXISTS', 'UNION', 'ASC', 'DESC',
  ];

  static const List<String> css = [
    'color', 'background', 'margin', 'padding', 'border', 'display', 'position', 'top',
    'left', 'right', 'bottom', 'width', 'height', 'font', 'size', 'flex', 'grid', 'align',
    'justify', 'transition', 'transform', 'opacity', 'content', 'cursor', 'overflow',
    'visibility', 'radius', 'weight', 'important', 'media', 'import',
  ];

  static const List<String> bash = [
    'if', 'then', 'else', 'elif', 'fi', 'for', 'do', 'done', 'while', 'until', 'case', 'esac',
    'function', 'return', 'echo', 'export', 'local', 'read', 'cd', 'ls', 'grep', 'sed', 'awk',
    'curl', 'cat', 'source', 'exit', 'test', 'set', 'unset', 'shift',
  ];

  static const List<String> yaml = ['true', 'false', 'null', 'yes', 'no'];

  static const List<String> json = ['true', 'false', 'null'];

  static const List<String> xml = ['xml', 'version', 'encoding', 'lang', 'xmlns'];

  static const List<String> http = [
    'GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS', 'Host', 'Content-Type',
    'Content-Length', 'Authorization', 'Cookie', 'Accept', 'User-Agent', 'Referer', 'Origin',
    'Cache-Control', 'Connection',
  ];

  /// 按文本编辑页的语言标签（与 `_LangOption.label` 一致）返回关键字集。
  static List<String> forLanguage(String langLabel) {
    switch (langLabel) {
      case 'HTTP':
        return http;
      case 'JSON':
        return json;
      case 'XML / HTML':
        return xml;
      case 'JavaScript':
        return javascript;
      case 'TypeScript':
        return typescript;
      case 'CSS':
        return css;
      case 'SQL':
        return sql;
      case 'YAML':
        return yaml;
      case 'Markdown':
        return const [];
      case 'Bash':
        return bash;
      case 'Python':
        return python;
      case 'Java':
        return java;
      case 'Go':
        return go;
      case 'Dart':
        return dart;
      default:
        return const [];
    }
  }
}
