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
      'log', 'error', 'warn', 'info', 'debug', 'trace', 'table', 'time', 'group', 'navigator', 'location', 'history', 'screen', 'create', 'seal', 'isFrozen', 'fromEntries', 'defineProperty', 'getPrototypeOf', 'isArray', 'reduceRight', 'findLast', 'lastIndexOf', 'flat', 'flatMap', 'fill', 'copyWithin', 'at', 'toUpperCase', 'toLowerCase', 'trimStart', 'trimEnd', 'replaceAll', 'matchAll', 'search', 'charAt', 'charCodeAt', 'codePointAt', 'padStart', 'padEnd', 'startsWith', 'endsWith', 'repeat', 'substr', 'substring', 'floor', 'ceil', 'round', 'trunc', 'abs', 'max', 'min', 'random', 'pow', 'sqrt', 'cbrt', 'log2', 'log10', 'exp', 'sign', 'hypot', 'parseInt', 'parseFloat', 'isNaN', 'isFinite', 'isInteger', 'isSafeInteger', 'EPSILON', 'MAX_SAFE_INTEGER', 'toPrecision', 'toExponential', 'allSettled', 'any', 'Response', 'Request', 'Headers', 'URL', 'URLSearchParams', 'AbortController', 'AbortSignal', 'now', 'getTime', 'toISOString', 'toLocaleDateString', 'getFullYear', 'getMonth', 'getDate', 'getHours', 'getMinutes', 'TypeError', 'RangeError', 'SyntaxError', 'ReferenceError', 'EvalError', 'URIError', 'setImmediate', 'queueMicrotask', 'querySelector', 'querySelectorAll', 'removeEventListener', 'dispatchEvent', 'createElement', 'createTextNode', 'appendChild', 'removeChild', 'insertBefore', 'replaceChild', 'innerHTML', 'textContent', 'innerText', 'classList', 'style', 'setAttribute', 'getAttribute', 'removeAttribute', 'localStorage', 'sessionStorage', 'indexedDB', 'crypto', 'performance', 'constructor', 'Buffer', '__dirname', '__filename', 'global', 'module.exports', 'debugger', 'with',
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
      'ReadonlyArray', 'ConstructorParameters', 'ThisType', 'PromiseLike', 'Iterable', 'Iterator', 'AsyncIterable', 'AsyncIterator', 'Generator', 'AsyncGenerator', 'Function', 'WeakMap', 'WeakSet', 'Symbol', 'BigInt', 'DeepPartial',
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
      'main', 'yield2', 'then', 'catchError', 'whenComplete', 'timeout', 'Completer', 'Null', 'never', 'Record', 'defer', 'Random', 'Timer', 'Stopwatch', 'HttpClient', 'HttpClientRequest', 'HttpClientResponse', 'jsonDecode', 'jsonEncode', 'utf8', 'utf16', 'base64', 'build', 'setState', 'initState', 'dispose', 'IconButton', 'TextButton', 'ElevatedButton', 'OutlinedButton', 'AppBar', 'ListView', 'GridView', 'Stack', 'Positioned', 'Flexible', 'SizedBox', 'ListTile', 'Divider', 'Card', 'Chip', 'Checkbox', 'Switch', 'Slider', 'ProgressIndicator', 'Theme', 'Colors', 'EdgeInsets', 'TextStyle', 'BoxDecoration', 'BorderRadius', 'BorderDecoration', 'Alignment', 'MainAxisAlignment', 'CrossAxisAlignment', 'TextEditingController', 'FocusNode', 'ScrollController', 'AnimationController', 'Animation', 'Tween', 'Curve', 'red', 'green', 'blue', 'grey', 'black', 'white', 'transparent', 'FutureBuilder', 'StreamBuilder', 'ValueListenableBuilder',
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
      'eval', 'exec', 'compile', 'complex', 'memoryview', 'object', 'reverse', 'setdefault', 'popitem', 'symmetric_difference', 'issubset', 'issuperset', 'rsplit', 'splitlines', 'lstrip', 'rstrip', 'rfind', 'capitalize', 'swapcase', 'zfill', 'center', 'ljust', 'rjust', 'encode', 'decode', 'isdigit', 'isalpha', 'isalnum', 'isspace', 'isupper', 'islower', 'Exception', 'BaseException', 'ValueError', 'TypeError', 'KeyError', 'IndexError', 'AttributeError', 'ImportError', 'ModuleNotFoundError', 'RuntimeError', 'StopIteration', 'FileNotFoundError', 'ZeroDivisionError', 'OSError', 'NotImplementedError', 'AssertionError', 'OverflowError', 'RecursionError', 'PermissionError', 'ConnectionError', 'TimeoutError', 'UnicodeDecodeError', 'os', 'sys', 'json', 're', 'time', 'datetime', 'math', 'random', 'collections', 'itertools', 'functools', 'pathlib', 'typing', 'logging', 'threading', 'subprocess', 'argparse', 'csv', 'hashlib', 'base64', 'urllib', 'socket', 'sqlite3', 'unittest', 'dataclasses', 'asyncio', 'dataclass', 'NamedTuple', 'Enum', 'deque', 'Counter', 'defaultdict', 'OrderedDict',
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
      'out', 'err', 'println', 'print', 'printf', 'format', 'StringJoiner', 'CharSequence', 'Number', 'StrictMath', 'Class', 'Vector', 'LinkedHashMap', 'Hashtable', 'ConcurrentHashMap', 'Properties', 'TreeSet', 'LinkedHashSet', 'Queue', 'Deque', 'ArrayDeque', 'PriorityQueue', 'Iterator', 'ListIterator', 'Collection', 'Iterable', 'Comparable', 'Comparator', 'OptionalInt', 'IntStream', 'LongStream', 'Collectors', 'Function', 'BiFunction', 'Consumer', 'Supplier', 'Predicate', 'UnaryOperator', 'BinaryOperator', 'Callable', 'ExecutorService', 'Executors', 'Future', 'CompletableFuture', 'AtomicInteger', 'AtomicLong', 'AtomicBoolean', 'FileNotFoundException', 'IllegalStateException', 'IndexOutOfBoundsException', 'NumberFormatException', 'ClassCastException', 'UnsupportedOperationException', 'InterruptedException', 'File', 'Files', 'Path', 'Paths', 'Scanner', 'Random', 'UUID', 'LocalDate', 'LocalTime', 'LocalDateTime', 'Instant', 'Duration', 'Period', 'DateTimeFormatter', 'ZoneId', 'ZonedDateTime', 'BigInteger', 'BigDecimal', 'ThreadLocal', 'ClassLoader', 'Method', 'Field', 'clone', 'notify', 'wait', 'values', 'valueOf', 'parseLong', 'parseDouble', 'parseFloat', 'join', 'split', 'replace', 'replaceAll', 'matches', 'startsWith', 'endsWith', 'indexOf', 'lastIndexOf', 'substring', 'charAt', 'isBlank', 'trim', 'strip', 'toUpperCase', 'toLowerCase', 'toCharArray', 'getBytes', 'compareTo', 'equalsIgnoreCase', 'repeat', 'concat', 'intern', 'set', 'containsKey', 'containsValue', 'keySet', 'entrySet', 'clear', 'sort', 'binarySearch', 'asList', 'reduce', 'count', 'findFirst', 'findAny', 'anyMatch', 'allMatch', 'noneMatch', 'sorted', 'distinct', 'limit', 'skip', 'flatMap',
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
      'Print', 'Sprint', 'Sprintln', 'Fprintln', 'Fprintf', 'Scanln', 'Scanf', 'Sscan', 'Args', 'Exit', 'Getenv', 'Setenv', 'Open', 'Create', 'ReadFile', 'WriteFile', 'Mkdir', 'Remove', 'Rename', 'Stat', 'Environ', 'Reader', 'Writer', 'Copy', 'CopyN', 'ReadAll', 'WriteString', 'LimitReader', 'TeeReader', 'MultiWriter', 'Contains', 'HasPrefix', 'HasSuffix', 'Index', 'IndexByte', 'LastIndex', 'Join', 'Split', 'SplitN', 'Replace', 'ReplaceAll', 'TrimSpace', 'TrimPrefix', 'TrimSuffix', 'ToLower', 'ToUpper', 'Repeat', 'Fields', 'Builder', 'NewReader', 'NewReplacer', 'Itoa', 'ParseInt', 'ParseUint', 'ParseFloat', 'FormatFloat', 'Quote', 'Unquote', 'Is', 'As', 'Unwrap', 'Now', 'Since', 'Sleep', 'Until', 'Duration', 'Unix', 'Format', 'Parse', 'Add', 'Sub', 'Truncate', 'After', 'Before', 'Sqrt', 'Pow', 'Abs', 'Max', 'Min', 'Mod', 'Floor', 'Ceil', 'Round', 'Trunc', 'Inf', 'NaN', 'Pi', 'MaxInt64', 'MinInt64', 'Ints', 'Float64s', 'Strings', 'Slice', 'Search', 'IntsAreSorted', 'StringsAreSorted', 'Mutex', 'RWMutex', 'WaitGroup', 'Once', 'Map', 'Pool', 'Cond', 'Background', 'TODO', 'WithCancel', 'WithTimeout', 'WithDeadline', 'WithValue', 'atomic', 'AddInt64', 'LoadInt64', 'StoreInt64', 'CompareAndSwapInt64', 'NewWriter', 'Scanner', 'NewScanner', 'ReadString', 'NewBuffer', 'Buffer', 'Equal', 'encoding', 'NewEncoder', 'NewDecoder', 'net', 'HandleFunc', 'Handle', 'ListenAndServe', 'Get', 'Post', 'Client', 'Server', 'Request', 'Response', 'Query', 'Path', 'Compile', 'MustCompile', 'MatchString', 'FindString', 'FindAllString', 'ReplaceAllString', 'Fatal', 'Fatalf', 'Panic',
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
      'TRUNCATE', 'ROUND', 'ABS', 'CEIL', 'FLOOR', 'CONCAT', 'SUBSTRING', 'TRIM', 'UPPER', 'LOWER', 'LENGTH', 'REPLACE', 'NOW', 'DATEADD', 'DATEDIFF', 'DATE_FORMAT', 'EXTRACT', 'SERIAL', 'IDENTITY', 'int', 'varchar', 'char', 'text', 'date', 'datetime', 'timestamp', 'decimal', 'numeric', 'boolean', 'blob',
  ];

  static const List<String> css = [
    'color', 'background', 'margin', 'padding', 'border', 'display', 'position', 'top',
    'left', 'right', 'bottom', 'width', 'height', 'font', 'size', 'flex', 'grid', 'align',
    'justify', 'transition', 'transform', 'opacity', 'content', 'cursor', 'overflow',
    'visibility', 'radius', 'weight', 'important', 'media', 'import',
      'background-color', 'background-image', 'background-size', 'background-position', 'background-repeat', 'margin-top', 'margin-right', 'margin-bottom', 'margin-left', 'padding-top', 'padding-right', 'padding-bottom', 'padding-left', 'border-top', 'border-radius', 'border-color', 'border-width', 'border-style', 'z-index', 'float', 'clear', 'min-width', 'max-width', 'min-height', 'max-height', 'font-size', 'font-family', 'font-weight', 'font-style', 'line-height', 'letter-spacing', 'word-spacing', 'text-align', 'text-decoration', 'text-transform', 'text-shadow', 'text-overflow', 'white-space', 'word-break', 'word-wrap', 'flex-direction', 'flex-wrap', 'flex-grow', 'flex-shrink', 'flex-basis', 'justify-content', 'align-items', 'align-content', 'align-self', 'gap', 'row-gap', 'column-gap', 'order', 'grid-template-columns', 'grid-template-rows', 'grid-template-areas', 'grid-column', 'grid-row', 'grid-area', 'grid-gap', 'place-items', 'place-content', 'place-self', 'overflow-x', 'overflow-y', 'pointer-events', 'user-select', 'box-shadow', 'box-sizing', 'transition-duration', 'transition-property', 'transition-timing-function', 'transform-origin', 'animation', 'animation-name', 'animation-duration', 'animation-delay', 'animation-iteration-count', 'keyframes', 'outline', 'outline-offset', 'object-fit', 'object-position', 'filter', 'backdrop-filter', 'list-style', 'list-style-type', 'list-style-position', 'vertical-align', 'table-layout', 'border-collapse', 'resize', 'appearance', 'will-change', 'aspect-ratio', 'inset', 'clip-path', 'mask', 'block', 'inline', 'inline-block', 'none', 'absolute', 'relative', 'fixed', 'sticky', 'center', 'space-between', 'space-around', 'space-evenly', 'baseline', 'stretch', 'auto', 'inherit', 'initial', 'unset',
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
      'unalias', 'npm', 'node', 'python', 'pip',
  ];

  static const List<String> yaml = ['true', 'false', 'null', 'yes', 'no'    'on', 'off', 'apiVersion', 'kind', 'metadata', 'spec', 'name', 'namespace', 'labels', 'annotations', 'image', 'ports', 'env', 'volumeMounts', 'volumes', 'replicas', 'selector', 'template', 'containers', 'version', 'dependencies', 'scripts', 'jobs', 'steps',
  ];

  static const List<String> json = ['true', 'false', 'null'];

  static const List<String> xml = ['xml', 'version', 'encoding', 'lang', 'xmlns'    'html', 'head', 'body', 'title', 'meta', 'link', 'script', 'style', 'base', 'div', 'span', 'p', 'a', 'img', 'ul', 'ol', 'li', 'dl', 'dt', 'dd', 'table', 'thead', 'tbody', 'tfoot', 'tr', 'th', 'td', 'caption', 'colgroup', 'col', 'form', 'input', 'button', 'select', 'option', 'optgroup', 'textarea', 'label', 'fieldset', 'legend', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'br', 'hr', 'header', 'footer', 'nav', 'main', 'section', 'article', 'aside', 'video', 'audio', 'source', 'track', 'canvas', 'svg', 'path', 'circle', 'rect', 'line', 'polyline', 'polygon', 'g', 'defs', 'use', 'symbol', 'iframe', 'embed', 'object', 'param', 'strong', 'em', 'b', 'i', 'u', 's', 'small', 'sub', 'sup', 'mark', 'time', 'code', 'pre', 'blockquote', 'cite', 'q', 'abbr', 'address', 'template', 'slot', 'picture', 'figure', 'figcaption', 'details', 'summary', 'dialog',
  ];

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
      'println', 'print', 'final', 'async', 'launch', 'runBlocking', 'withContext', 'coroutineScope', 'listOf', 'mutableListOf', 'mapOf', 'mutableMapOf', 'setOf', 'mutableSetOf', 'arrayOf', 'emptyList', 'Int', 'Long', 'Double', 'Float', 'Boolean', 'Char', 'String', 'Byte', 'Short', 'Unit', 'Any', 'Nothing', 'Array', 'List', 'MutableList', 'Map', 'MutableMap', 'Set', 'MutableSet', 'Pair', 'Triple', 'let', 'run', 'apply', 'also', 'with', 'takeIf', 'takeUnless', 'repeat', 'map', 'filter', 'forEach', 'reduce', 'fold', 'sorted', 'sortedBy', 'reversed', 'distinct', 'first', 'firstOrNull', 'last', 'lastOrNull', 'find', 'single', 'count', 'sum', 'sumOf', 'maxOrNull', 'minOrNull', 'any', 'all', 'none', 'zip', 'joinToString', 'joinTo', 'associateWith', 'groupBy', 'partition', 'flatMap', 'toString', 'equals', 'hashCode', 'copy', 'component1', 'invoke', 'operator', 'infix', 'throws',
  ];

  static const List<String> rust = [
    'fn', 'let', 'mut', 'const', 'static', 'struct', 'enum', 'union', 'trait',
    'impl', 'for', 'in', 'where', 'pub', 'use', 'mod', 'crate', 'self', 'super',
    'if', 'else', 'match', 'loop', 'while', 'return', 'break', 'continue',
    'move', 'ref', 'as', 'dyn', 'async', 'await', 'unsafe', 'extern', 'type',
    'box', 'Some', 'None', 'Ok', 'Err', 'true', 'false', 'String', 'Vec',
    'Option', 'Result', 'Box', 'Rc', 'Arc', 'RefCell', 'Mutex', 'println!',
    'print!', 'format!', 'vec!', 'derive', 'macro_rules', 'unsafe',
      'Self', 'str', 'bool', 'char', 'u8', 'u16', 'u32', 'u64', 'u128', 'usize', 'i8', 'i16', 'i32', 'i64', 'i128', 'isize', 'f32', 'f64', 'Cell', 'RwLock', 'Cow', 'println', 'print', 'format', 'vec', 'eprintln', 'eprint', 'write', 'writeln', 'unwrap', 'expect', 'clone', 'into', 'from', 'to_string', 'len', 'push', 'pop', 'iter', 'into_iter', 'map', 'filter', 'collect', 'fold', 'for_each', 'find', 'any', 'all', 'count', 'sum', 'min', 'max', 'unwrap_or', 'unwrap_or_else', 'unwrap_or_default', 'ok', 'err', 'is_some', 'is_none', 'is_ok', 'is_err', 'HashMap', 'HashSet', 'BTreeMap', 'BTreeSet', 'VecDeque', 'BinaryHeap', 'Iterator', 'IntoIterator', 'Extend', 'From', 'Into', 'TryFrom', 'TryInto', 'Default', 'Clone', 'Copy', 'Debug', 'Display', 'PartialEq', 'Eq', 'Hash',
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
      'Self', 'Int', 'Int8', 'Int16', 'Int32', 'Int64', 'UInt', 'Double', 'Float', 'Bool', 'String', 'Character', 'Array', 'Dictionary', 'Set', 'Optional', 'Any', 'AnyObject', 'print', 'dump', 'map', 'filter', 'reduce', 'forEach', 'sorted', 'compactMap', 'flatMap', 'append', 'insert', 'remove', 'removeAll', 'contains', 'first', 'last', 'count', 'isEmpty', 'indices', 'firstIndex', 'lastIndex', 'min', 'max', 'sum', 'Task', 'escaping', 'autoclosure', 'inout', 'Codable', 'Encodable', 'Decodable', 'Equatable', 'Hashable', 'Comparable', 'Identifiable',
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
      'print_r', 'var_dump', 'count', 'strlen', 'implode', 'explode', 'in_array', 'array_push', 'array_pop', 'array_shift', 'array_unshift', 'array_map', 'array_filter', 'array_reduce', 'array_merge', 'array_merge_recursive', 'array_keys', 'array_values', 'array_slice', 'array_splice', 'array_search', 'array_key_exists', 'array_flip', 'array_unique', 'array_sum', 'array_column', 'sort', 'rsort', 'asort', 'arsort', 'ksort', 'krsort', 'usort', 'uasort', 'uksort', 'shuffle', 'json_encode', 'json_decode', 'serialize', 'unserialize', 'urlencode', 'urldecode', 'htmlspecialchars', 'htmlspecialchars_decode', 'strip_tags', 'nl2br', 'trim', 'ltrim', 'rtrim', 'str_replace', 'str_ireplace', 'str_repeat', 'substr', 'substr_count', 'strpos', 'stripos', 'strrpos', 'strstr', 'stristr', 'strtolower', 'strtoupper', 'ucfirst', 'lcfirst', 'ucwords', 'str_pad', 'str_split', 'strrev', 'sprintf', 'printf', 'vsprintf', 'number_format', 'wordwrap', 'htmlentities', 'addslashes', 'stripslashes', 'preg_match', 'preg_match_all', 'preg_replace', 'preg_replace_callback', 'preg_split', 'preg_quote', 'file_get_contents', 'file_put_contents', 'fopen', 'fclose', 'fgets', 'fputs', 'fwrite', 'file', 'readfile', 'unlink', 'mkdir', 'rmdir', 'is_file', 'is_dir', 'file_exists', 'realpath', 'basename', 'dirname', 'pathinfo', 'scandir', 'glob', 'die', 'exit', 'Exception', 'Error', 'TypeError', 'ValueError', 'ArithmeticError', 'PDO', 'PDOStatement', 'PDOException', 'mysqli', 'Closure', 'ArrayAccess', 'Iterator', 'Countable', 'Serializable', 'Generator', 'IteratorAggregate', 'int', 'string', 'float', 'bool', 'void', 'mixed', 'object', 'callable', 'iterable',
  ];

  static const List<String> ruby = [
    'def', 'end', 'class', 'module', 'if', 'elsif', 'else', 'unless', 'while',
    'until', 'for', 'in', 'do', 'begin', 'rescue', 'ensure', 'raise', 'return',
    'break', 'next', 'redo', 'retry', 'yield', 'block_given?', 'lambda', 'proc',
    'require', 'require_relative', 'include', 'extend', 'attr_accessor',
    'attr_reader', 'attr_writer', 'module_function', 'private', 'public',
    'protected', 'self', 'super', 'nil', 'true', 'false', 'and', 'or', 'not',
    'then', 'case', 'when', 'puts', 'print', 'p', 'new', 'each', 'map', 'select',
      'pp', 'gets', 'load', 'prepend', 'attr', 'defined?', 'loop', 'catch', 'throw', 'each_with_index', 'each_with_object', 'each_slice', 'each_cons', 'reject', 'reduce', 'inject', 'find', 'detect', 'collect', 'sort', 'sort_by', 'sort_by!', 'min', 'max', 'min_by', 'max_by', 'sum', 'count', 'any', 'all', 'none', 'one', 'first', 'last', 'take', 'drop', 'take_while', 'drop_while', 'group_by', 'partition', 'flat_map', 'zip', 'push', 'pop', 'shift', 'unshift', 'length', 'size', 'empty?', 'include?', 'index', 'rindex', 'join', 'split', 'strip', 'chomp', 'chop', 'upcase', 'downcase', 'capitalize', 'swapcase', 'reverse', 'chars', 'bytes', 'lines', 'to_s', 'to_i', 'to_f', 'to_a', 'to_h', 'to_sym', 'to_str', 'inspect', 'respond_to?', 'send', 'public_send', 'freeze', 'frozen?', 'initialize', 'is_a?', 'kind_of?', 'instance_of?', 'equal?', 'eql?', 'nil?', 'String', 'Integer', 'Float', 'Array', 'Hash', 'Symbol', 'Proc', 'Struct', 'Module', 'Class', 'Object', 'Comparable', 'Enumerable', 'StringIO', 'File', 'Dir', 'IO', 'Time', 'Date', 'DateTime', 'select_all', 'find_by', 'where', 'order', 'limit', 'pluck',
  ];

  static const List<String> c = [
    'auto', 'break', 'case', 'char', 'const', 'continue', 'default', 'do',
    'double', 'else', 'enum', 'extern', 'float', 'for', 'goto', 'if', 'inline',
    'int', 'long', 'register', 'restrict', 'return', 'short', 'signed',
    'sizeof', 'static', 'struct', 'switch', 'typedef', 'union', 'unsigned',
    'void', 'volatile', 'while', 'NULL', 'bool', 'true', 'false', 'printf',
    'malloc', 'free', 'memcpy', 'strlen', 'include', 'define', 'ifdef',
    'ifndef', 'endif', 'pragma', 'typedef', 'wchar_t', 'size_t',
      'scanf', 'sscanf', 'fscanf', 'gets', 'fgets', 'puts', 'fputs', 'fopen', 'fclose', 'fprintf', 'sprintf', 'snprintf', 'vprintf', 'vfprintf', 'fread', 'fwrite', 'fseek', 'ftell', 'rewind', 'feof', 'fgetc', 'fputc', 'getchar', 'putchar', 'perror', 'exit', 'atexit', 'atoi', 'atol', 'atoll', 'atof', 'strtol', 'strtoul', 'strtod', 'strtoll', 'strtoull', 'strcmp', 'strncmp', 'strcasecmp', 'strcpy', 'strncpy', 'strcat', 'strncat', 'strstr', 'strchr', 'strrchr', 'strtok', 'strdup', 'memset', 'memmove', 'memcmp', 'memchr', 'calloc', 'realloc', 'qsort', 'bsearch', 'abs', 'labs', 'llabs', 'fabs', 'sqrt', 'cbrt', 'pow', 'exp', 'exp2', 'log', 'log2', 'log10', 'sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'atan2', 'sinh', 'cosh', 'tanh', 'ceil', 'floor', 'round', 'trunc', 'nearbyint', 'fmod', 'remainder', 'hypot', 'fmin', 'fmax', 'rand', 'srand', 'time', 'clock', 'difftime', 'mktime', 'localtime', 'gmtime', 'strftime', 'FILE', 'EOF', 'ptrdiff_t', 'ssize_t', 'off_t', 'time_t', 'clock_t', 'int8_t', 'int16_t', 'int32_t', 'int64_t', 'uint8_t', 'uint16_t', 'uint32_t', 'uint64_t', 'intptr_t', 'uintptr_t', 'va_list', 'va_start', 'va_arg', 'va_end', 'offsetof', 'stdin', 'stdout', 'stderr', 'SEEK_SET', 'SEEK_CUR', 'SEEK_END', 'EXIT_SUCCESS', 'EXIT_FAILURE', 'RAND_MAX', 'BUFSIZ', 'assert', 'static_assert', 'main', 'argc', 'argv', 'intmax_t', '_Bool', '_Atomic',
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
      'cerr', 'clog', 'flush', 'hex', 'dec', 'oct', 'setw', 'setprecision', 'fixed', 'scientific', 'wstring', 'u16string', 'u32string', 'string_view', 'list', 'forward_list', 'deque', 'array', 'set', 'multiset', 'multimap', 'unordered_map', 'unordered_set', 'unordered_multimap', 'unordered_multiset', 'stack', 'queue', 'priority_queue', 'pair', 'tuple', 'optional', 'variant', 'any', 'bitset', 'span', 'function', 'bind', 'ref', 'cref', 'mem_fn', 'invoke', 'weak_ptr', 'make_shared', 'make_unique', 'allocate_shared', 'move', 'forward', 'swap', 'exchange', 'get', 'getline', 'begin', 'end', 'cbegin', 'cend', 'rbegin', 'rend', 'crbegin', 'crend', 'size', 'empty', 'data', 'front', 'back', 'at', 'push_back', 'pop_back', 'push_front', 'pop_front', 'emplace', 'emplace_back', 'emplace_front', 'insert', 'erase', 'clear', 'find', 'count', 'contains', 'reserve', 'resize', 'shrink_to_fit', 'capacity', 'sort', 'stable_sort', 'partial_sort', 'nth_element', 'reverse', 'rotate', 'unique', 'lower_bound', 'upper_bound', 'equal_range', 'binary_search', 'next_permutation', 'prev_permutation', 'fill', 'fill_n', 'copy', 'copy_if', 'copy_n', 'transform', 'accumulate', 'reduce', 'iota', 'generate', 'for_each', 'min', 'max', 'min_element', 'max_element', 'clamp', 'distance', 'advance', 'next', 'prev', 'to_string', 'stoi', 'stol', 'stoul', 'stoll', 'stof', 'stod', 'stold', 'initializer_list', 'allocator', 'iterator', 'const_iterator', 'reverse_iterator', 'enable_if', 'is_same', 'is_integral', 'is_floating_point', 'remove_reference', 'remove_const', 'add_const', 'consteval', 'constinit', 'co_await', 'co_return', 'co_yield', 'final', 'thread_local',
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
      'Console', 'WriteLine', 'Write', 'ReadLine', 'Read', 'WriteAllText', 'ReadAllText', 'ReadAllLines', 'AppendAllText', 'System', 'Collections', 'Generic', 'Linq', 'Text', 'Threading', 'Tasks', 'IO', 'Net', 'Http', 'Diagnostics', 'Globalization', 'List', 'Dictionary', 'HashSet', 'SortedSet', 'SortedDictionary', 'Queue', 'Stack', 'LinkedList', 'KeyValuePair', 'IEnumerable', 'IEnumerator', 'ICollection', 'IList', 'IDictionary', 'IQueryable', 'IComparable', 'IEquatable', 'IDisposable', 'IAsyncEnumerable', 'IObservable', 'ISet', 'ILookup', 'Array', 'Tuple', 'ValueTuple', 'Nullable', 'Guid', 'DateTime', 'TimeSpan', 'DateTimeOffset', 'Random', 'Math', 'Convert', 'Environment', 'GC', 'Buffer', 'Path', 'File', 'Directory', 'Stream', 'FileStream', 'MemoryStream', 'StreamReader', 'StreamWriter', 'StringBuilder', 'String', 'Object', 'Exception', 'ArgumentException', 'ArgumentNullException', 'ArgumentOutOfRangeException', 'InvalidOperationException', 'NotImplementedException', 'NullReferenceException', 'IndexOutOfRangeException', 'KeyNotFoundException', 'FormatException', 'IOException', 'TaskCanceledException', 'ToString', 'Equals', 'GetHashCode', 'GetType', 'MemberwiseClone', 'Dispose', 'Format', 'Join', 'IsNullOrEmpty', 'IsNullOrWhiteSpace', 'Concat', 'Compare', 'Substring', 'IndexOf', 'LastIndexOf', 'Contains', 'StartsWith', 'EndsWith', 'Replace', 'Split', 'Trim', 'TrimStart', 'TrimEnd', 'ToUpper', 'ToLower', 'PadLeft', 'PadRight', 'Insert', 'Remove', 'TrimEnds', 'ToCharArray', 'Select', 'SelectMany', 'Where', 'OrderBy', 'OrderByDescending', 'ThenBy', 'ThenByDescending', 'GroupBy', 'First', 'FirstOrDefault', 'Single', 'SingleOrDefault', 'Last', 'LastOrDefault', 'ElementAt', 'ElementAtOrDefault', 'Any', 'All', 'Count', 'LongCount', 'Sum', 'Average', 'Min', 'Max', 'ToList', 'ToArray', 'ToDictionary', 'ToHashSet', 'ToLookup', 'Skip', 'SkipWhile', 'Take', 'TakeWhile', 'Distinct', 'Zip', 'Aggregate', 'SequenceEqual', 'Union', 'Intersect', 'Except', 'Range', 'Repeat', 'Empty', 'Task', 'ValueTask', 'Run', 'Wait', 'WaitAll', 'WaitAny', 'WhenAll', 'WhenAny', 'Delay', 'FromResult', 'ContinueWith', 'Result', 'dynamic', 'Func', 'Action', 'Predicate', 'partial', 'get', 'set', 'value',
  ];

  static const List<String> lua = [
    'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function',
    'goto', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then',
    'true', 'until', 'while', 'require', 'print', 'pairs', 'ipairs', 'type',
    'tostring', 'tonumber', 'table', 'string', 'math', 'io', 'os', 'self',
    'setmetatable', 'getmetatable', 'rawget', 'rawset', 'select', 'pcall',
    'xpcall', 'error', 'assert', 'next', 'unpack',
      'rawequal', 'rawlen', 'module', 'string.format', 'string.sub', 'string.len', 'string.rep', 'string.find', 'string.gsub', 'string.gmatch', 'string.match', 'string.upper', 'string.lower', 'string.byte', 'string.char', 'string.reverse', 'string.split', 'table.insert', 'table.remove', 'table.concat', 'table.sort', 'table.unpack', 'table.pack', 'table.move', 'table.getn', 'math.floor', 'math.ceil', 'math.abs', 'math.max', 'math.min', 'math.sqrt', 'math.random', 'math.huge', 'math.pi', 'math.sin', 'math.cos', 'math.tan', 'math.log', 'math.exp', 'math.fmod', 'math.modf', 'io.open', 'io.read', 'io.write', 'io.lines', 'io.close', 'io.stdout', 'io.stderr', 'os.time', 'os.date', 'os.clock', 'os.getenv', 'os.exit', 'os.remove', 'os.rename', 'coroutine.create', 'coroutine.resume', 'coroutine.yield', 'coroutine.status', 'coroutine.wrap', 'utf8.char', 'utf8.len', 'utf8.codepoint', 'utf8.offset',
  ];

  static const List<String> r = [
    'function', 'return', 'if', 'else', 'for', 'while', 'repeat', 'break',
    'next', 'in', 'TRUE', 'FALSE', 'NULL', 'NA', 'NaN', 'Inf', 'library',
    'require', 'source', 'print', 'cat', 'paste', 'c', 'list', 'vector',
    'matrix', 'data.frame', 'factor', 'length', 'names', 'class', 'typeof',
    'sapply', 'lapply', 'apply', 'tapply', 'subset', 'merge', 'summary',
    'mean', 'median', 'sd', 'var', 'sum', 'min', 'max', 'seq', 'rep', 'which',
    'is.na', 'as.numeric', 'as.character', 'as.factor', 'read.csv', 'write.csv',
      'paste0', 'sprintf', 'format', 'invisible', 'array', 'numeric', 'integer', 'character', 'logical', 'complex', 'dim', 'nrow', 'ncol', 'head', 'tail', 'str', 'is.null', 'as.integer', 'as.double', 'as.logical', 'vapply', 'mapply', 'Map', 'Reduce', 'Filter', 'Find', 'prod', 'range', 'quantile', 'cumsum', 'diff', 'seq_along', 'seq_len', 'rev', 'sort', 'order', 'rank', 'unique', 'duplicated', 'match', 'rbind', 'cbind', 'aggregate', 'transform', 'within', 'lm', 'glm', 'predict', 'plot', 'hist', 'boxplot', 'pairs', 'setwd', 'getwd', 'read.table', 'write.table', 'save', 'load', 'dplyr', 'tidyr', 'stringr', 'forcats', 'purrr', 'readr', 'tibble', 'ggplot2', 'theme_minimal', 'theme_bw', 'theme_classic', 'labs', 'facet_wrap', 'facet_grid', 'geom_point', 'geom_line', 'geom_bar', 'geom_col', 'geom_histogram', 'geom_boxplot', 'aes', 'group_by', 'summarise', 'summarize', 'mutate', 'filter_arrange',
  ];

  static const List<String> scala = [
    'abstract', 'case', 'catch', 'class', 'def', 'do', 'else', 'extends',
    'false', 'final', 'finally', 'for', 'forSome', 'if', 'implicit', 'import',
    'lazy', 'match', 'new', 'null', 'object', 'override', 'package', 'private',
    'protected', 'return', 'sealed', 'super', 'this', 'throw', 'trait', 'try',
    'true', 'type', 'val', 'var', 'while', 'with', 'yield', 'given', 'using',
    'enum', 'export', 'extension', 'then', 'inline', 'transparent', 'println',
      'print', 'printf', 'require', 'assert', 'List', 'Seq', 'Vector', 'Array', 'ArrayBuffer', 'Map', 'Set', 'ListBuffer', 'Option', 'Some', 'None', 'Either', 'Left', 'Right', 'Try', 'Success', 'Failure', 'map', 'flatMap', 'filter', 'foreach', 'fold', 'foldLeft', 'foldRight', 'reduce', 'reduceLeft', 'collect', 'sorted', 'sortBy', 'sortWith', 'head', 'headOption', 'tail', 'init', 'last', 'lastOption', 'take', 'drop', 'takeWhile', 'dropWhile', 'span', 'partition', 'groupBy', 'zip', 'zipWithIndex', 'mkString', 'toList', 'toSet', 'toMap', 'toSeq', 'reverse', 'distinct', 'contains', 'exists', 'forall', 'find', 'count', 'sum', 'product', 'min', 'max', 'length', 'size', 'isEmpty', 'nonEmpty', 'Int', 'Long', 'Double', 'Float', 'Boolean', 'Char', 'String', 'Unit', 'Any', 'AnyRef', 'Nothing', 'Null', 'Future', 'Await', 'ExecutionContext', 'Promise', 'StringBuilder',
  ];

  static const List<String> perl = [
    'my', 'our', 'local', 'sub', 'package', 'use', 'require', 'if', 'elsif',
    'else', 'unless', 'while', 'until', 'for', 'foreach', 'do', 'last', 'next',
    'redo', 'return', 'die', 'warn', 'print', 'say', 'chomp', 'chop', 'split',
    'join', 'map', 'grep', 'sort', 'keys', 'values', 'each', 'push', 'pop',
    'shift', 'unshift', 'splice', 'scalar', 'ref', 'bless', 'new', 'and', 'or',
    'not', 'defined', 'exists', 'delete', 'undef', 'qw', 'strict', 'warnings',
      'printf', 'sprintf', 'length', 'substr', 'index', 'rindex', 'uc', 'lc', 'ucfirst', 'lcfirst', 'reverse', 'open', 'close', 'read', 'write', 'chdir', 'mkdir', 'unlink', 'rename', 'eval', 'STDIN', 'STDOUT', 'STDERR',
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
      'Write-Error', 'Write-Warning', 'Write-Verbose', 'Write-Debug', 'Get-Content', 'Set-Content', 'Add-Content', 'Clear-Content', 'Get-Process', 'Get-Service', 'Get-Member', 'Get-Date', 'Get-Location', 'Set-Location', 'New-Object', 'Copy-Item', 'Move-Item', 'Rename-Item', 'Split-Path', 'Resolve-Path', 'Get-ItemProperty', 'Set-ItemProperty', 'Group-Object', 'Compare-Object', 'ConvertTo-Json', 'ConvertFrom-Json', 'ConvertTo-Csv', 'ConvertFrom-Csv', 'ConvertTo-Html', 'Select-String', 'Out-File', 'Out-Null', 'Out-String', 'Out-Host', 'Start-Process', 'Stop-Process', 'Start-Service', 'Stop-Service', 'Restart-Service', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Invoke-Expression', 'Invoke-Command', 'Export-Module', 'Remove-Module', 'Import-Csv', 'Export-Csv', 'PSCustomObject', 'ErrorActionPreference', 'VerbosePreference',
  ];

  static const List<String> haskell = [
    'module', 'where', 'import', 'qualified', 'as', 'hiding', 'data', 'type',
    'newtype', 'class', 'instance', 'deriving', 'do', 'let', 'in', 'if', 'then',
    'else', 'case', 'of', 'infixl', 'infixr', 'infix', 'default', 'foreign',
    'Int', 'Integer', 'Float', 'Double', 'Char', 'String', 'Bool', 'Maybe',
    'Either', 'Just', 'Nothing', 'Left', 'Right', 'True', 'False', 'map',
    'filter', 'foldl', 'foldr', 'mapM', 'return', 'pure', 'fmap', 'show', 'read',
    'putStrLn', 'print', 'error', 'undefined',
      'putStr', 'getLine', 'getContents', 'interact', 'readFile', 'writeFile', 'appendFile', 'foldl1', 'foldr1', 'zipWith', 'zip', 'unzip', 'scanl', 'scanr', 'head', 'tail', 'init', 'last', 'length', 'null', 'reverse', 'concat', 'concatMap', 'take', 'drop', 'takeWhile', 'dropWhile', 'elem', 'notElem', 'lookup', 'lines', 'words', 'unlines', 'unwords', 'IO', 'Ordering', 'mapM_', 'forM', 'forM_', 'sequence', 'sequence_', 'when', 'unless', 'forever', 'fromIntegral', 'realToFrac', 'floor', 'ceiling', 'round', 'truncate', 'min', 'max', 'abs', 'sum', 'product', 'minimum', 'maximum', 'any', 'all', 'and', 'or',
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
      'NSLog', 'NSString', 'NSArray', 'NSMutableArray', 'NSDictionary', 'NSMutableDictionary', 'NSSet', 'NSMutableSet', 'NSNumber', 'NSData', 'NSObject', 'CGRect', 'CGPoint', 'CGSize', 'alloc', 'init', 'new', 'mutableCopy', 'description', 'length', 'count', 'objectAtIndex', 'objectForKey', 'setObject', 'forKey', 'addObject', 'removeObject', 'stringWithFormat', 'stringWithContentsOfFile', 'componentsSeparatedByString', 'substringToIndex', 'substringFromIndex', 'stringByAppendingString', 'intValue', 'floatValue', 'doubleValue', 'boolValue', 'autoreleasepool', 'end', 'try', 'catch', 'finally', 'throw', 'UIView', 'UIViewController', 'UILabel', 'UIButton', 'UIImage', 'UIColor', 'UITableView', 'UICollectionView', 'dispatch_async', 'dispatch_sync', 'dispatch_get_main_queue',
  ];

  static const List<String> elixir = [
    'def', 'defmodule', 'defp', 'defmacro', 'defstruct', 'defprotocol',
    'defimpl', 'defdelegate', 'defguard', 'if', 'unless', 'case', 'cond',
    'with', 'for', 'receive', 'try', 'rescue', 'catch', 'after', 'raise',
    'throw', 'do', 'end', 'fn', 'when', 'import', 'alias', 'use', 'require',
    'true', 'false', 'nil', 'and', 'or', 'not', 'in', 'Enum', 'Map', 'List',
    'String', 'Integer', 'Float', 'IO', 'Agent', 'GenServer', 'Supervisor',
    'Task', 'Kernel', 'self', 'puts', 'inspect',
      'else', 'map', 'filter', 'reduce', 'each', 'sum', 'min', 'max', 'count', 'sort', 'sort_by', 'group_by', 'into', 'chunk_every', 'Stream', 'take', 'drop', 'first', 'last', 'length', 'flatten', 'zip', 'unzip', 'delete', 'insert_at', 'replace_at', 'get', 'put', 'has_key', 'keys', 'values', 'merge', 'update', 'new', 'upcase', 'downcase', 'trim', 'split', 'replace', 'slice', 'contains', 'starts_with', 'ends_with', 'to_integer', 'to_float', 'parse', 'to_string', 'digits', 'write', 'gets', 'hd', 'tl', 'is_atom', 'is_binary', 'is_list', 'is_map', 'is_nil', 'async', 'await',
  ];

  static const List<String> clojure = [
    'def', 'defn', 'defn-', 'defmacro', 'defmulti', 'defmethod', 'defprotocol',
    'deftype', 'defrecord', 'let', 'letfn', 'fn', 'if', 'if-let', 'if-not',
    'when', 'when-let', 'when-not', 'cond', 'condp', 'case', 'do', 'doseq',
    'dotimes', 'loop', 'recur', 'for', 'try', 'catch', 'finally', 'throw',
    'ns', 'require', 'import', 'use', 'refer', 'true', 'false', 'nil', 'and',
    'or', 'not', 'map', 'filter', 'reduce', 'apply', 'conj', 'assoc', 'get',
    'str', 'println', 'atom', 'swap!', 'reset!', 'deref',
      'defstruct', 'partial', 'comp', 'juxt', 'complement', 'constantly', 'identity', 'first', 'rest', 'next', 'last', 'butlast', 'nth', 'count', 'empty', 'seq', 'cons', 'dissoc', 'get-in', 'assoc-in', 'update', 'update-in', 'merge', 'merge-with', 'keys', 'vals', 'into', 'concat', 'mapcat', 'interpose', 'flatten', 'distinct', 'sort', 'sort-by', 'reverse', 'range', 'repeat', 'repeatedly', 'iterate', 'take', 'drop', 'take-while', 'drop-while', 'partition', 'group-by', 'subs', 'print', 'prn', 'pr-str', 'format', 'read-string', 'add-watch', 'as',
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
      'textrm', 'textsf', 'prod', 'log', 'ln', 'sin', 'cos', 'tan', 'newpage', 'hline', 'hfill', 'times', 'cdot', 'div', 'pm', 'mp', 'epsilon', 'theta', 'pi', 'phi', 'mathbf', 'mathrm', 'mathcal', 'mathbb', 'vec', 'tiny', 'small', 'footnotesize', 'normalsize', 'large', 'Large', 'huge', 'Huge',
  ];

  static const List<String> nix = [
    'let', 'in', 'with', 'rec', 'inherit', 'import', 'if', 'then', 'else',
    'assert', 'true', 'false', 'null', 'builtins', 'pkgs', 'lib', 'mkDerivation',
    'mkIf', 'mkOption', 'mkEnableOption', 'types', 'config', 'options', 'imports',
    'stdenv', 'fetchurl', 'fetchFromGitHub', 'callPackage', 'writeText',
    'writeShellScript', 'runCommand', 'optional', 'optionals', 'map', 'filter',
    'foldl', 'attrNames', 'attrValues', 'mapAttrs', 'genAttrs', 'listToAttrs',
    'toString', 'toJSON', 'fromJSON', 'concatStringsSep', 'concatMapStringsSep',
      'readFile', 'writeFile', 'readDir', 'readFileType', 'foldl1', 'genList', 'abort', 'throw', 'derivation', 'fetchTarball', 'fetchGit',
  ];

  static const List<String> zig = [
    'const', 'var', 'fn', 'pub', 'export', 'extern', 'comptime', 'inline',
    'noinline', 'usingnamespace', 'test', 'if', 'else', 'while', 'for', 'switch',
    'break', 'continue', 'return', 'defer', 'errdefer', 'try', 'catch', 'orelse',
    'unreachable', 'undefined', 'null', 'true', 'false', 'struct', 'enum',
    'union', 'opaque', 'error', 'anytype', 'anyerror', 'void', 'noreturn',
    'type', 'anyframe', 'asm', 'align', 'allowzero', 'volatile', 'nosuspend',
    'suspend', 'resume', 'async', 'await', 'and', 'or', 'std', 'unreachable',
      'intCast', 'bitCast', 'floatCast', 'ptrCast', 'alignCast', 'enumFromInt', 'ArrayList', 'HashMap', 'StringHashMap', 'AutoHashMap', 'ArrayHashMap', 'i8', 'i16', 'i32', 'i64', 'i128', 'u8', 'u16', 'u32', 'u64', 'u128', 'usize', 'isize', 'f16', 'f32', 'f64', 'f80', 'bool',
  ];

  /// 语言 key -> 专属关键字表。
  static const Map<String, List<String>> _byKey = {
    // 常用内置语言：key 优先命中，避免依赖 Mode.name 恰好等于展示名。
    'json': json,
    'xml': xml,
    'html': xml,
    'xhtml': xml,
    'svg': xml,
    'vue': xml,
    'svelte': xml,
    'css': css,
    'scss': css,
    'less': css,
    'sass': css,
    'stylus': css,
    'javascript': javascript,
    'typescript': typescript,
    'coffeescript': javascript,
    'java': java,
    'groovy': java,
    'python': python,
    'go': go,
    'golang': go,
    'dart': dart,
    'bash': bash,
    'sh': bash,
    'shell': bash,
    'zsh': bash,
    'sql': sql,
    'yaml': yaml,
    'toml': yaml,
    'properties': bash,
    'dockerfile': bash,
    'makefile': bash,
    'cmake': bash,
    'nginx': bash,
    'plaintext': const <String>[],
    'text': const <String>[],
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
