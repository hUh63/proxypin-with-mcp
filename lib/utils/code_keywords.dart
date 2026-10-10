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
    'this', 'typeof', 'instanceof', 'void', 'delete', 'in', 'of', 'try', 'catch', 'finally',
    'throw', 'async', 'await', 'yield', 'import', 'export', 'from', 'as', 'static', 'get', 'set',
    'null', 'undefined', 'NaN', 'Infinity', 'true', 'false',
    'console', 'window', 'document', 'globalThis', 'JSON', 'Math', 'Date', 'RegExp', 'Error',
    'Promise', 'Object', 'Array', 'String', 'Number', 'Boolean', 'Symbol', 'Map', 'Set', 'WeakMap',
    'WeakSet', 'Proxy', 'Reflect', 'Function', 'BigInt', 'Intl', 'fetch', 'setTimeout',
    'setInterval', 'clearTimeout', 'clearInterval', 'require', 'module', 'exports', 'process',
    'length', 'push', 'pop', 'shift', 'unshift', 'splice', 'slice', 'concat', 'join', 'split',
    'map', 'filter', 'reduce', 'forEach', 'find', 'findIndex', 'some', 'every', 'includes',
    'indexOf', 'sort', 'reverse', 'keys', 'values', 'entries', 'assign', 'freeze', 'parse',
    'stringify', 'then', 'catch', 'finally', 'resolve', 'reject', 'all', 'race', 'toString',
    'valueOf', 'hasOwnProperty', 'trim', 'replace', 'match', 'test', 'exec', 'toFixed', 'addEventListener',
  ];

  static const List<String> typescript = [
    'interface', 'type', 'enum', 'namespace', 'declare', 'module', 'implements', 'extends',
    'private', 'public', 'protected', 'readonly', 'abstract', 'static', 'override', 'declare',
    'as', 'satisfies', 'keyof', 'typeof', 'infer', 'is', 'asserts', 'never', 'unknown', 'any',
    'void', 'string', 'number', 'boolean', 'object', 'symbol', 'bigint', 'undefined', 'null',
    'const', 'let', 'var', 'function', 'class', 'return', 'if', 'else', 'for', 'while', 'do',
    'switch', 'case', 'break', 'continue', 'new', 'this', 'super', 'try', 'catch', 'finally',
    'throw', 'async', 'await', 'yield', 'import', 'export', 'from', 'default', 'true', 'false',
    'Partial', 'Required', 'Readonly', 'Record', 'Pick', 'Omit', 'Exclude', 'Extract', 'NonNullable',
    'ReturnType', 'Parameters', 'Awaited', 'InstanceType', 'Promise', 'Array', 'Map', 'Set',
    'Date', 'RegExp', 'Error', 'JSON', 'Math', 'Object', 'console', 'length', 'push', 'map',
    'filter', 'reduce', 'forEach', 'includes', 'keys', 'values', 'entries', 'toString',
  ];

  static const List<String> dart = [
    'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case', 'catch', 'class',
    'const', 'continue', 'covariant', 'default', 'deferred', 'do', 'dynamic', 'else', 'enum',
    'export', 'extends', 'extension', 'external', 'factory', 'false', 'final', 'finally', 'for',
    'get', 'hide', 'if', 'implements', 'import', 'in', 'interface', 'is', 'late', 'library',
    'mixin', 'new', 'null', 'on', 'operator', 'part', 'required', 'rethrow', 'return', 'sealed',
    'set', 'show', 'static', 'super', 'switch', 'sync', 'this', 'throw', 'true', 'try', 'typedef',
    'var', 'void', 'when', 'while', 'with', 'yield',
    'Future', 'Stream', 'List', 'Map', 'Set', 'String', 'int', 'double', 'num', 'bool', 'Object',
    'Iterable', 'Duration', 'DateTime', 'RegExp', 'Uri', 'BigInt', 'Symbol', 'Function', 'Type',
    'Widget', 'BuildContext', 'State', 'StatelessWidget', 'StatefulWidget', 'ValueNotifier',
    'ChangeNotifier', 'Navigator', 'MaterialApp', 'Scaffold', 'Text', 'Container', 'Column',
    'Row', 'Expanded', 'Padding', 'Center', 'GestureDetector', 'InkWell', 'Icon', 'Image',
    'print', 'toString', 'length', 'isEmpty', 'isNotEmpty', 'add', 'remove', 'contains',
    'map', 'where', 'forEach', 'reduce', 'fold', 'firstWhere', 'any', 'every', 'toList', 'toSet',
    'keys', 'values', 'entries', 'containsKey', 'containsValue', 'indexOf', 'sublist', 'join',
  ];

  static const List<String> python = [
    'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue', 'def', 'del', 'elif',
    'else', 'except', 'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is', 'lambda',
    'None', 'nonlocal', 'not', 'or', 'pass', 'raise', 'return', 'True', 'False', 'try', 'while',
    'with', 'yield', 'match', 'case', 'self', 'cls',
    'print', 'len', 'range', 'enumerate', 'zip', 'map', 'filter', 'sorted', 'reversed', 'sum',
    'min', 'max', 'abs', 'round', 'int', 'float', 'str', 'bool', 'list', 'dict', 'set', 'tuple',
    'frozenset', 'bytes', 'bytearray', 'isinstance', 'issubclass', 'type', 'id', 'hash', 'repr',
    'format', 'open', 'input', 'iter', 'next', 'super', 'property', 'staticmethod', 'classmethod',
    'getattr', 'setattr', 'hasattr', 'delattr', 'vars', 'dir', 'globals', 'locals', 'callable',
    'all', 'any', 'chr', 'ord', 'hex', 'oct', 'bin', 'divmod', 'pow', '__init__', '__name__',
    '__main__', '__str__', '__repr__', '__len__', '__dict__', 'append', 'extend', 'insert',
    'remove', 'pop', 'clear', 'copy', 'keys', 'values', 'items', 'get', 'update', 'update',
    'add', 'discard', 'union', 'intersection', 'difference', 'split', 'join', 'strip', 'replace',
    'lower', 'upper', 'title', 'startswith', 'endswith', 'find', 'index', 'count', 'sort',
  ];

  static const List<String> java = [
    'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char', 'class', 'const',
    'continue', 'default', 'do', 'double', 'else', 'enum', 'extends', 'final', 'finally', 'float',
    'for', 'goto', 'if', 'implements', 'import', 'instanceof', 'int', 'interface', 'long',
    'native', 'new', 'package', 'private', 'protected', 'public', 'return', 'short', 'static',
    'strictfp', 'super', 'switch', 'synchronized', 'this', 'throw', 'throws', 'transient', 'try',
    'void', 'volatile', 'while', 'var', 'record', 'sealed', 'permits', 'yield', 'true', 'false',
    'null',
    'String', 'Integer', 'Long', 'Double', 'Float', 'Boolean', 'Character', 'Byte', 'Short',
    'Object', 'List', 'Map', 'Set', 'ArrayList', 'LinkedList', 'HashMap', 'TreeMap', 'HashSet',
    'Optional', 'Stream', 'StringBuilder', 'StringBuffer', 'Exception', 'RuntimeException',
    'IllegalArgumentException', 'NullPointerException', 'IOException', 'System', 'Arrays',
    'Collections', 'Objects', 'Math', 'Thread', 'Runnable', 'Override', 'Deprecated',
    'length', 'size', 'isEmpty', 'contains', 'add', 'remove', 'get', 'put', 'forEach', 'stream',
    'filter', 'map', 'collect', 'toList', 'toString', 'equals', 'hashCode', 'getClass', 'parseInt',
  ];

  static const List<String> go = [
    'break', 'case', 'chan', 'const', 'continue', 'default', 'defer', 'else', 'fallthrough',
    'for', 'func', 'go', 'goto', 'if', 'import', 'interface', 'map', 'package', 'range', 'return',
    'select', 'struct', 'switch', 'type', 'var', 'nil', 'true', 'false', 'iota',
    'make', 'new', 'len', 'cap', 'append', 'copy', 'delete', 'close', 'panic', 'recover', 'print',
    'println', 'error', 'any', 'comparable',
    'string', 'int', 'int8', 'int16', 'int32', 'int64', 'uint', 'uint8', 'uint16', 'uint32',
    'uint64', 'uintptr', 'float32', 'float64', 'complex64', 'complex128', 'bool', 'byte', 'rune',
    'fmt', 'log', 'os', 'io', 'time', 'strings', 'strconv', 'errors', 'context', 'sync', 'json',
    'http', 'bytes', 'bufio', 'sort', 'math', 'regexp', 'reflect', 'runtime', 'testing', 'url',
    'Printf', 'Println', 'Sprintf', 'Errorf', 'New', 'Marshal', 'Unmarshal', 'FormatInt', 'Atoi',
  ];

  static const List<String> sql = [
    'SELECT', 'FROM', 'WHERE', 'JOIN', 'LEFT', 'RIGHT', 'INNER', 'OUTER', 'FULL', 'CROSS', 'ON',
    'GROUP', 'BY', 'ORDER', 'HAVING', 'LIMIT', 'OFFSET', 'INSERT', 'INTO', 'VALUES', 'UPDATE',
    'SET', 'DELETE', 'CREATE', 'TABLE', 'ALTER', 'DROP', 'INDEX', 'VIEW', 'TRIGGER', 'PROCEDURE',
    'FUNCTION', 'DATABASE', 'SCHEMA', 'AS', 'AND', 'OR', 'NOT', 'NULL', 'IS', 'IN', 'LIKE',
    'BETWEEN', 'EXISTS', 'DISTINCT', 'UNION', 'ALL', 'ASC', 'DESC', 'CASE', 'WHEN', 'THEN',
    'ELSE', 'END', 'WITH', 'RECURSIVE', 'OVER', 'PARTITION', 'ROW_NUMBER', 'RANK', 'DENSE_RANK',
    'EXPLAIN', 'ANALYZE', 'BEGIN', 'COMMIT', 'ROLLBACK', 'TRANSACTION', 'GRANT', 'REVOKE',
    'COUNT', 'SUM', 'AVG', 'MIN', 'MAX', 'COALESCE', 'IFNULL', 'NULLIF', 'CAST', 'CONVERT',
    'PRIMARY', 'KEY', 'FOREIGN', 'REFERENCES', 'UNIQUE', 'DEFAULT', 'CHECK', 'CONSTRAINT',
    'AUTO_INCREMENT', 'INT', 'INTEGER', 'VARCHAR', 'CHAR', 'TEXT', 'DATE', 'DATETIME',
    'TIMESTAMP', 'DECIMAL', 'FLOAT', 'DOUBLE', 'BOOLEAN', 'BLOB',
  ];

  static const List<String> css = [
    'color', 'background', 'margin', 'padding', 'border', 'display', 'position', 'top',
    'left', 'right', 'bottom', 'width', 'height', 'font', 'size', 'flex', 'grid', 'align',
    'justify', 'transition', 'transform', 'opacity', 'content', 'cursor', 'overflow',
    'visibility', 'radius', 'weight', 'important', 'media', 'import',
  ];

  static const List<String> bash = [
    'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'until', 'do', 'done', 'case', 'esac',
    'in', 'function', 'select', 'return', 'exit', 'break', 'continue', 'local', 'export',
    'readonly', 'declare', 'unset', 'source', 'alias', 'eval', 'exec', 'shift', 'set', 'trap',
    'wait', 'read', 'test', 'true', 'false',
    'echo', 'printf', 'cd', 'pwd', 'ls', 'cp', 'mv', 'rm', 'mkdir', 'rmdir', 'touch', 'cat',
    'head', 'tail', 'grep', 'egrep', 'sed', 'awk', 'cut', 'sort', 'uniq', 'wc', 'tr', 'find',
    'xargs', 'tar', 'gzip', 'gunzip', 'zip', 'unzip', 'curl', 'wget', 'ssh', 'scp', 'rsync',
    'chmod', 'chown', 'chgrp', 'ln', 'df', 'du', 'ps', 'top', 'kill', 'killall', 'sleep',
    'date', 'whoami', 'id', 'env', 'sudo', 'which', 'whereis', 'hostname', 'uname', 'uptime',
    'history', 'man', 'tee', 'diff', 'patch', 'basename', 'dirname', 'realpath', 'mktemp',
    'apt', 'yum', 'docker', 'git', 'make', 'nohup', 'sync',
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
