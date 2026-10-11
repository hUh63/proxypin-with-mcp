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

import 'package:proxypin/utils/lang_meta.dart';

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

  // ------------------------------------------------------------ 语言族通用表
  //
  // 190+ 种语言不可能逐个手写，因此按「族」给出通用关键字；语言专属表优先。
  // 多给一些同族语言的关键字并不影响使用，只是候选更宽。

  static const List<String> cFamily = [
    'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'default', 'break',
    'continue', 'return', 'goto', 'class', 'struct', 'union', 'enum',
    'interface', 'extends', 'implements', 'namespace', 'using', 'package',
    'import', 'export', 'module', 'public', 'private', 'protected', 'internal',
    'static', 'final', 'const', 'readonly', 'abstract', 'virtual', 'override',
    'sealed', 'inline', 'extern', 'void', 'int', 'long', 'short', 'char',
    'bool', 'boolean', 'float', 'double', 'byte', 'var', 'let', 'auto',
    'dynamic', 'object', 'string', 'new', 'delete', 'this', 'super', 'self',
    'typeof', 'sizeof', 'instanceof', 'is', 'as', 'in', 'out', 'ref', 'true',
    'false', 'null', 'nullptr', 'undefined', 'try', 'catch', 'finally',
    'throw', 'throws', 'assert', 'lock', 'yield', 'async', 'await', 'volatile',
    'template', 'typename', 'operator', 'friend', 'explicit', 'mutable',
    'constexpr', 'func', 'fn', 'def', 'val', 'when', 'match', 'impl', 'trait',
    'pub', 'mut', 'where', 'defer', 'go', 'chan', 'range', 'nil', 'unsigned',
    'signed', 'register', 'typedef', 'print', 'println', 'fun', 'suspend',
  ];

  static const List<String> hashFamily = [
    'def', 'class', 'if', 'elif', 'else', 'for', 'while', 'break', 'continue',
    'return', 'pass', 'import', 'from', 'as', 'with', 'try', 'except',
    'finally', 'raise', 'lambda', 'yield', 'global', 'nonlocal', 'assert',
    'del', 'in', 'is', 'not', 'and', 'or', 'True', 'False', 'None', 'self',
    'async', 'await', 'print', 'len', 'range', 'str', 'int', 'float', 'list',
    'dict', 'set', 'tuple', 'type', 'isinstance', 'super', 'property',
    'staticmethod', 'classmethod', 'match', 'case', 'end', 'then', 'do',
    'local', 'function', 'nil', 'elsif', 'unless', 'until', 'begin', 'rescue',
    'ensure', 'require', 'include', 'extend', 'puts', 'echo', 'foreach',
  ];

  static const List<String> sqlFamily = [
    'SELECT', 'FROM', 'WHERE', 'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET',
    'DELETE', 'CREATE', 'TABLE', 'VIEW', 'INDEX', 'DROP', 'ALTER', 'ADD',
    'COLUMN', 'CONSTRAINT', 'PRIMARY', 'KEY', 'FOREIGN', 'REFERENCES',
    'UNIQUE', 'NOT', 'NULL', 'DEFAULT', 'JOIN', 'LEFT', 'RIGHT', 'INNER',
    'OUTER', 'FULL', 'CROSS', 'ON', 'USING', 'GROUP', 'BY', 'ORDER', 'HAVING',
    'LIMIT', 'OFFSET', 'UNION', 'ALL', 'DISTINCT', 'AS', 'AND', 'OR', 'IN',
    'EXISTS', 'BETWEEN', 'LIKE', 'CASE', 'WHEN', 'THEN', 'ELSE', 'END',
    'COUNT', 'SUM', 'AVG', 'MIN', 'MAX', 'ASC', 'DESC', 'WITH', 'RECURSIVE',
    'RETURNING', 'BEGIN', 'COMMIT', 'ROLLBACK', 'TRANSACTION', 'DECLARE',
    'FUNCTION', 'PROCEDURE', 'TRIGGER', 'ELSEIF', 'ELSIF', 'LOOP', 'DO',
  ];

  static const List<String> lispFamily = [
    'defun', 'defmacro', 'defvar', 'defparameter', 'defclass', 'defmethod',
    'lambda', 'let', 'let*', 'flet', 'labels', 'if', 'when', 'unless', 'cond',
    'case', 'loop', 'do', 'dolist', 'dotimes', 'progn', 'return', 'block',
    'catch', 'throw', 'quote', 'function', 'setq', 'setf', 'car', 'cdr',
    'cons', 'list', 'append', 'mapcar', 'apply', 'funcall', 'eval', 't', 'nil',
  ];

  static const List<String> percentFamily = [
    'function', 'end', 'if', 'else', 'elseif', 'for', 'while', 'switch',
    'case', 'otherwise', 'try', 'catch', 'do', 'continue', 'break', 'return',
    'global', 'persistent', 'program', 'subroutine', 'implicit', 'integer',
    'real', 'logical', 'character', 'complex', 'dimension', 'parameter',
    'contains', 'call', 'print', 'format', 'module', 'use', 'interface',
    'type', 'classdef', 'properties', 'methods', 'parfor', 'disp', 'fprintf',
    'function_handle', 'endfunction', 'endif', 'endfor', 'endwhile',
  ];

  static const List<String> vbFamily = [
    'Dim', 'As', 'Sub', 'Function', 'End', 'If', 'Then', 'Else', 'ElseIf',
    'For', 'Each', 'Next', 'While', 'Wend', 'Do', 'Loop', 'Until', 'Select',
    'Case', 'Is', 'Try', 'Catch', 'Finally', 'Throw', 'Public', 'Private',
    'Protected', 'Friend', 'Shared', 'Static', 'Class', 'Module', 'Structure',
    'Interface', 'Implements', 'Inherits', 'Overrides', 'Overloads',
    'Property', 'Get', 'Set', 'New', 'Nothing', 'True', 'False', 'And', 'Or',
    'Not', 'Mod', 'ByVal', 'ByRef', 'Optional', 'ReDim', 'Preserve', 'With',
    'GoTo', 'Exit',
  ];

  static const List<String> batchFamily = [
    'if', 'else', 'for', 'in', 'do', 'goto', 'call', 'set', 'setlocal',
    'endlocal', 'echo', 'rem', 'exit', 'pause', 'shift', 'start', 'copy',
    'move', 'del', 'find', 'findstr', 'choice', 'timeout', 'ping', 'pushd',
    'popd', 'cd', 'dir', 'type', 'errorlevel',
  ];

  static const List<String> fortranFamily = [
    'program', 'subroutine', 'function', 'end', 'if', 'then', 'else', 'elseif',
    'do', 'while', 'continue', 'goto', 'call', 'return', 'implicit', 'none',
    'integer', 'real', 'precision', 'complex', 'logical', 'character',
    'dimension', 'parameter', 'allocatable', 'save', 'data', 'common',
    'external', 'intrinsic', 'interface', 'module', 'use', 'contains', 'print',
    'write', 'read', 'format', 'stop', 'cycle', 'exit',
  ];

  // ------------------------------------------------------------ 语言专属表

  static const List<String> kotlin = [
    'fun', 'val', 'var', 'class', 'object', 'interface', 'data', 'sealed',
    'enum', 'companion', 'init', 'constructor', 'open', 'override', 'abstract',
    'private', 'protected', 'internal', 'public', 'suspend', 'inline', 'reified',
    'if', 'else', 'when', 'for', 'while', 'do', 'return', 'break', 'continue',
    'try', 'catch', 'finally', 'throw', 'is', 'as', 'in', 'out', 'by', 'lazy',
    'lateinit', 'companion', 'this', 'super', 'it', 'null', 'true', 'false',
    'import', 'package', 'typealias', 'where', 'vararg', 'crossinline', 'noinline',
  ];

  static const List<String> rust = [
    'fn', 'let', 'mut', 'const', 'static', 'struct', 'enum', 'union', 'trait',
    'impl', 'for', 'in', 'where', 'pub', 'use', 'mod', 'crate', 'self', 'super',
    'if', 'else', 'match', 'loop', 'while', 'return', 'break', 'continue',
    'move', 'ref', 'as', 'dyn', 'async', 'await', 'unsafe', 'extern', 'type',
    'box', 'Some', 'None', 'Ok', 'Err', 'true', 'false', 'String', 'Vec',
    'Option', 'Result', 'Box', 'Rc', 'Arc', 'RefCell', 'Mutex', 'println!',
    'print!', 'format!', 'vec!', 'derive', 'macro_rules', 'unsafe',
  ];

  static const List<String> swift = [
    'func', 'var', 'let', 'class', 'struct', 'enum', 'protocol', 'extension',
    'init', 'deinit', 'subscript', 'typealias', 'associatedtype', 'where',
    'if', 'else', 'guard', 'switch', 'case', 'default', 'for', 'while', 'repeat',
    'return', 'break', 'continue', 'fallthrough', 'throw', 'throws', 'rethrows',
    'do', 'try', 'catch', 'defer', 'as', 'is', 'in', 'public', 'private',
    'fileprivate', 'internal', 'open', 'final', 'static', 'lazy', 'weak',
    'unowned', 'mutating', 'nonmutating', 'convenience', 'required', 'override',
    'import', 'nil', 'true', 'false', 'self', 'super', 'some', 'any', 'await',
    'async', 'actor',
  ];

  static const List<String> php = [
    'function', 'class', 'interface', 'trait', 'abstract', 'final', 'public',
    'private', 'protected', 'static', 'const', 'var', 'new', 'clone', 'echo',
    'print', 'return', 'if', 'else', 'elseif', 'endif', 'switch', 'case',
    'default', 'endswitch', 'for', 'foreach', 'as', 'while', 'endwhile', 'do',
    'break', 'continue', 'try', 'catch', 'finally', 'throw', 'namespace', 'use',
    'require', 'require_once', 'include', 'include_once', 'global', 'isset',
    'unset', 'empty', 'list', 'array', 'true', 'false', 'null', 'this',
    'parent', 'self', 'instanceof', 'extends', 'implements', 'yield', 'fn',
    'match', 'readonly', 'enum', 'declare', 'strict_types',
  ];

  static const List<String> ruby = [
    'def', 'end', 'class', 'module', 'if', 'elsif', 'else', 'unless', 'while',
    'until', 'for', 'in', 'do', 'begin', 'rescue', 'ensure', 'raise', 'return',
    'break', 'next', 'redo', 'retry', 'yield', 'block_given?', 'lambda', 'proc',
    'require', 'require_relative', 'include', 'extend', 'attr_accessor',
    'attr_reader', 'attr_writer', 'module_function', 'private', 'public',
    'protected', 'self', 'super', 'nil', 'true', 'false', 'and', 'or', 'not',
    'then', 'case', 'when', 'puts', 'print', 'p', 'new', 'each', 'map', 'select',
  ];

  static const List<String> c = [
    'auto', 'break', 'case', 'char', 'const', 'continue', 'default', 'do',
    'double', 'else', 'enum', 'extern', 'float', 'for', 'goto', 'if', 'inline',
    'int', 'long', 'register', 'restrict', 'return', 'short', 'signed',
    'sizeof', 'static', 'struct', 'switch', 'typedef', 'union', 'unsigned',
    'void', 'volatile', 'while', 'NULL', 'bool', 'true', 'false', 'printf',
    'malloc', 'free', 'memcpy', 'strlen', 'include', 'define', 'ifdef',
    'ifndef', 'endif', 'pragma', 'typedef', 'wchar_t', 'size_t',
  ];

  static const List<String> cpp = [
    'alignas', 'alignof', 'auto', 'bool', 'break', 'case', 'catch', 'char',
    'class', 'const', 'constexpr', 'continue', 'decltype', 'default', 'delete',
    'do', 'double', 'dynamic_cast', 'else', 'enum', 'explicit', 'export',
    'extern', 'false', 'float', 'for', 'friend', 'goto', 'if', 'inline', 'int',
    'long', 'mutable', 'namespace', 'new', 'noexcept', 'nullptr', 'operator',
    'override', 'private', 'protected', 'public', 'register', 'reinterpret_cast',
    'return', 'short', 'signed', 'sizeof', 'static', 'static_cast', 'struct',
    'switch', 'template', 'this', 'throw', 'true', 'try', 'typedef', 'typeid',
    'typename', 'union', 'unsigned', 'using', 'virtual', 'void', 'volatile',
    'while', 'std', 'string', 'vector', 'map', 'cout', 'cin', 'endl', 'unique_ptr',
    'shared_ptr', 'const_cast', 'static_assert', 'concept', 'requires',
  ];

  static const List<String> csharp = [
    'abstract', 'as', 'base', 'bool', 'break', 'byte', 'case', 'catch', 'char',
    'checked', 'class', 'const', 'continue', 'decimal', 'default', 'delegate',
    'do', 'double', 'else', 'enum', 'event', 'explicit', 'extern', 'false',
    'finally', 'fixed', 'float', 'for', 'foreach', 'goto', 'if', 'implicit',
    'in', 'int', 'interface', 'internal', 'is', 'lock', 'long', 'namespace',
    'new', 'null', 'object', 'operator', 'out', 'override', 'params', 'private',
    'protected', 'public', 'readonly', 'ref', 'return', 'sbyte', 'sealed',
    'short', 'sizeof', 'stackalloc', 'static', 'string', 'struct', 'switch',
    'this', 'throw', 'true', 'try', 'typeof', 'uint', 'ulong', 'unchecked',
    'unsafe', 'ushort', 'using', 'virtual', 'void', 'volatile', 'while', 'var',
    'async', 'await', 'yield', 'record', 'init', 'required', 'nameof', 'when',
  ];

  static const List<String> lua = [
    'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function',
    'goto', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then',
    'true', 'until', 'while', 'require', 'print', 'pairs', 'ipairs', 'type',
    'tostring', 'tonumber', 'table', 'string', 'math', 'io', 'os', 'self',
    'setmetatable', 'getmetatable', 'rawget', 'rawset', 'select', 'pcall',
    'xpcall', 'error', 'assert', 'next', 'unpack',
  ];

  static const List<String> r = [
    'function', 'return', 'if', 'else', 'for', 'while', 'repeat', 'break',
    'next', 'in', 'TRUE', 'FALSE', 'NULL', 'NA', 'NaN', 'Inf', 'library',
    'require', 'source', 'print', 'cat', 'paste', 'c', 'list', 'vector',
    'matrix', 'data.frame', 'factor', 'length', 'names', 'class', 'typeof',
    'sapply', 'lapply', 'apply', 'tapply', 'subset', 'merge', 'summary',
    'mean', 'median', 'sd', 'var', 'sum', 'min', 'max', 'seq', 'rep', 'which',
    'is.na', 'as.numeric', 'as.character', 'as.factor', 'read.csv', 'write.csv',
  ];

  static const List<String> scala = [
    'abstract', 'case', 'catch', 'class', 'def', 'do', 'else', 'extends',
    'false', 'final', 'finally', 'for', 'forSome', 'if', 'implicit', 'import',
    'lazy', 'match', 'new', 'null', 'object', 'override', 'package', 'private',
    'protected', 'return', 'sealed', 'super', 'this', 'throw', 'trait', 'try',
    'true', 'type', 'val', 'var', 'while', 'with', 'yield', 'given', 'using',
    'enum', 'export', 'extension', 'then', 'inline', 'transparent', 'println',
  ];

  static const List<String> perl = [
    'my', 'our', 'local', 'sub', 'package', 'use', 'require', 'if', 'elsif',
    'else', 'unless', 'while', 'until', 'for', 'foreach', 'do', 'last', 'next',
    'redo', 'return', 'die', 'warn', 'print', 'say', 'chomp', 'chop', 'split',
    'join', 'map', 'grep', 'sort', 'keys', 'values', 'each', 'push', 'pop',
    'shift', 'unshift', 'splice', 'scalar', 'ref', 'bless', 'new', 'and', 'or',
    'not', 'defined', 'exists', 'delete', 'undef', 'qw', 'strict', 'warnings',
  ];

  static const List<String> powershell = [
    'function', 'param', 'begin', 'process', 'end', 'if', 'else', 'elseif',
    'switch', 'foreach', 'for', 'while', 'do', 'until', 'break', 'continue',
    'return', 'try', 'catch', 'finally', 'throw', 'trap', 'class', 'enum',
    'filter', 'in', 'notin', 'contains', 'notcontains', 'like', 'match',
    'Get-Item', 'Get-ChildItem', 'Set-Item', 'New-Item', 'Remove-Item',
    'Write-Host', 'Write-Output', 'Read-Host', 'Select-Object', 'Where-Object',
    'ForEach-Object', 'Sort-Object', 'Measure-Object', 'Test-Path', 'Join-Path',
    'Import-Module', 'Get-Command', 'Get-Help', 'true', 'false', 'null',
  ];

  static const List<String> haskell = [
    'module', 'where', 'import', 'qualified', 'as', 'hiding', 'data', 'type',
    'newtype', 'class', 'instance', 'deriving', 'do', 'let', 'in', 'if', 'then',
    'else', 'case', 'of', 'infixl', 'infixr', 'infix', 'default', 'foreign',
    'Int', 'Integer', 'Float', 'Double', 'Char', 'String', 'Bool', 'Maybe',
    'Either', 'Just', 'Nothing', 'Left', 'Right', 'True', 'False', 'map',
    'filter', 'foldl', 'foldr', 'mapM', 'return', 'pure', 'fmap', 'show', 'read',
    'putStrLn', 'print', 'error', 'undefined',
  ];

  static const List<String> objectiveC = [
    'id', 'self', 'super', 'nil', 'Nil', 'YES', 'NO', 'if', 'else', 'for',
    'while', 'do', 'switch', 'case', 'default', 'break', 'continue', 'return',
    'goto', 'int', 'char', 'float', 'double', 'long', 'short', 'unsigned',
    'signed', 'void', 'BOOL', 'NSInteger', 'NSUInteger', 'CGFloat', 'struct',
    'enum', 'union', 'typedef', 'static', 'extern', 'const', 'volatile',
    'inline', 'sizeof', 'interface', 'implementation', 'protocol', 'property',
    'synthesize', 'dynamic', 'nonatomic', 'strong', 'weak', 'copy', 'retain',
    'assign', 'readonly', 'readwrite', 'instancetype', 'IBAction', 'IBOutlet',
  ];

  static const List<String> elixir = [
    'def', 'defmodule', 'defp', 'defmacro', 'defstruct', 'defprotocol',
    'defimpl', 'defdelegate', 'defguard', 'if', 'unless', 'case', 'cond',
    'with', 'for', 'receive', 'try', 'rescue', 'catch', 'after', 'raise',
    'throw', 'do', 'end', 'fn', 'when', 'import', 'alias', 'use', 'require',
    'true', 'false', 'nil', 'and', 'or', 'not', 'in', 'Enum', 'Map', 'List',
    'String', 'Integer', 'Float', 'IO', 'Agent', 'GenServer', 'Supervisor',
    'Task', 'Kernel', 'self', 'puts', 'inspect',
  ];

  static const List<String> clojure = [
    'def', 'defn', 'defn-', 'defmacro', 'defmulti', 'defmethod', 'defprotocol',
    'deftype', 'defrecord', 'let', 'letfn', 'fn', 'if', 'if-let', 'if-not',
    'when', 'when-let', 'when-not', 'cond', 'condp', 'case', 'do', 'doseq',
    'dotimes', 'loop', 'recur', 'for', 'try', 'catch', 'finally', 'throw',
    'ns', 'require', 'import', 'use', 'refer', 'true', 'false', 'nil', 'and',
    'or', 'not', 'map', 'filter', 'reduce', 'apply', 'conj', 'assoc', 'get',
    'str', 'println', 'atom', 'swap!', 'reset!', 'deref',
  ];

  static const List<String> latex = [
    'documentclass', 'usepackage', 'begin', 'end', 'section', 'subsection',
    'subsubsection', 'chapter', 'paragraph', 'title', 'author', 'date',
    'maketitle', 'tableofcontents', 'label', 'ref', 'cite', 'bibliography',
    'bibliographystyle', 'item', 'itemize', 'enumerate', 'description',
    'figure', 'table', 'tabular', 'centering', 'caption', 'includegraphics',
    'textbf', 'textit', 'texttt', 'emph', 'underline', 'footnote', 'href',
    'url', 'frac', 'sqrt', 'sum', 'int', 'lim', 'left', 'right', 'alpha',
    'beta', 'gamma', 'delta', 'lambda', 'mu', 'sigma', 'omega', 'newline',
    'linebreak', 'pagebreak', 'hspace', 'vspace', 'quad', 'qquad', 'textwidth',
  ];

  static const List<String> nix = [
    'let', 'in', 'with', 'rec', 'inherit', 'import', 'if', 'then', 'else',
    'assert', 'true', 'false', 'null', 'builtins', 'pkgs', 'lib', 'mkDerivation',
    'mkIf', 'mkOption', 'mkEnableOption', 'types', 'config', 'options', 'imports',
    'stdenv', 'fetchurl', 'fetchFromGitHub', 'callPackage', 'writeText',
    'writeShellScript', 'runCommand', 'optional', 'optionals', 'map', 'filter',
    'foldl', 'attrNames', 'attrValues', 'mapAttrs', 'genAttrs', 'listToAttrs',
    'toString', 'toJSON', 'fromJSON', 'concatStringsSep', 'concatMapStringsSep',
  ];

  static const List<String> zig = [
    'const', 'var', 'fn', 'pub', 'export', 'extern', 'comptime', 'inline',
    'noinline', 'usingnamespace', 'test', 'if', 'else', 'while', 'for', 'switch',
    'break', 'continue', 'return', 'defer', 'errdefer', 'try', 'catch', 'orelse',
    'unreachable', 'undefined', 'null', 'true', 'false', 'struct', 'enum',
    'union', 'opaque', 'error', 'anytype', 'anyerror', 'void', 'noreturn',
    'type', 'anyframe', 'asm', 'align', 'allowzero', 'volatile', 'nosuspend',
    'suspend', 'resume', 'async', 'await', 'and', 'or', 'std', 'unreachable',
  ];

  /// 语言 key -> 专属关键字表。
  static const Map<String, List<String>> _byKey = {
    'javascript': javascript,
    'typescript': typescript,
    'dart': dart,
    'python': python,
    'java': java,
    'go': go,
    'sql': sql,
    'css': css,
    'scss': css,
    'less': css,
    'bash': bash,
    'shell': bash,
    'yaml': yaml,
    'json': json,
    'xml': xml,
    'http': http,
    'markdown': markdown_,
    'kotlin': kotlin,
    'rust': rust,
    'swift': swift,
    'php': php,
    'ruby': ruby,
    'c': c,
    'cpp': cpp,
    'csharp': csharp,
    'lua': lua,
    'r': r,
    'scala': scala,
    'perl': perl,
    'powershell': powershell,
    'haskell': haskell,
    'objectivec': objectiveC,
    'elixir': elixir,
    'clojure': clojure,
    'latex': latex,
    'nix': nix,
    'zig': zig,
    'graphql': graphql_,
    'ini': ini_,
  };

  static const List<String> markdown_ = [];
  static const List<String> graphql_ = [
    'query', 'mutation', 'subscription', 'fragment', 'on', 'type', 'interface',
    'union', 'enum', 'input', 'scalar', 'schema', 'directive', 'extend', 'implements',
    'true', 'false', 'null', 'Int', 'Float', 'String', 'Boolean', 'ID',
  ];
  static const List<String> ini_ = ['true', 'false', 'yes', 'no', 'on', 'off'];

  static List<String> _familyKeywords(String normalized, String? key) {
    final family = langFamilyOf(key: key, label: normalized);
    switch (family) {
      case LangFamily.c:
        return cFamily;
      case LangFamily.hash:
        return hashFamily;
      case LangFamily.sql:
        return sqlFamily;
      case LangFamily.xml:
        return xml;
      case LangFamily.lisp:
        return lispFamily;
      case LangFamily.percent:
        return percentFamily;
      case LangFamily.vb:
        return vbFamily;
      case LangFamily.batch:
        return batchFamily;
      case LangFamily.fortran:
        return fortranFamily;
      case LangFamily.none:
        return const [];
    }
  }

  /// 按文本编辑页的语言返回关键字集。
  ///
  /// [langLabel] 是展示名，[key] 是 re_highlight 的小写标识（更准确）。
  /// 顺序：语言专属 -> 语言族通用 -> 空。
  static List<String> forLanguage(String langLabel, [String key = '']) {
    final exact = _byKey[key];
    if (exact != null) return exact;

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
      case 'Plain Text':
        return const [];
    }
    return _familyKeywords(langLabel, key.isEmpty ? null : key);
  }
}
