import 'dart:math';

/// 代码片段里的「占位符」（VS Code / VS 的 snippet 语法）：
///
/// - `$1` `$2` … 光标停靠点，按编号顺序跳；
/// - `${1:默认值}` 带默认文本的停靠点，插入后该段是**选中**状态，直接打字即替换；
/// - `$0` 最后停留的位置（会话结束）；
/// - `\$` 是要插入一个真正的美元符号（shell、正则替换里很常见）。
///
/// 为什么只在「片段插入」这条路上解析：普通粘贴/插入的内容里 `$1` 太常见了
/// （shell 位置参数、正则反向引用），全局解析会把正常代码改坏。
///
/// 另一层是**变量**（`[expandSnippetVariables]`）：`$TM_FILENAME`、`$CURRENT_YEAR`、
/// `$SELECTION`、`$UUID` 这些在解析占位符之前先展开成实际文本。变量名不能以数字
/// 开头，所以 `$1` / `${1:默认}` 不会被误当成变量。
class SnippetStop {
  /// 相对插入文本起点的偏移。
  final int start;
  final int end;

  const SnippetStop(this.start, this.end);

  bool get isCaret => start == end;

  @override
  String toString() => 'SnippetStop($start,$end)';
}

class ParsedSnippet {
  /// 去掉占位符标记后真正要插入的文本。
  final String text;

  /// 按跳转顺序排好的停靠点（`$1` → `$n` → `$0`）。没有占位符时为空。
  final List<SnippetStop> stops;

  const ParsedSnippet(this.text, this.stops);

  bool get hasStops => stops.isNotEmpty;
}

/// 解析片段文本，返回「干净文本 + 停靠点」。
ParsedSnippet parseSnippetPlaceholders(String raw) {
  final out = StringBuffer();
  // 编号 → 停靠点。同一个编号出现多次时以**最后一次**为准（和 VS Code 一致）。
  final found = <int, SnippetStop>{};
  var i = 0;
  while (i < raw.length) {
    final c = raw[i];
    // `\$` → 字面美元符
    if (c == '\\' && i + 1 < raw.length && raw[i + 1] == r'$') {
      out.write(r'$');
      i += 2;
      continue;
    }
    if (c != r'$') {
      out.write(c);
      i++;
      continue;
    }
    // `${N:默认值}` / `${N}`
    if (i + 1 < raw.length && raw[i + 1] == '{') {
      final close = raw.indexOf('}', i + 2);
      if (close > 0) {
        final body = raw.substring(i + 2, close);
        final colon = body.indexOf(':');
        final numText = colon < 0 ? body : body.substring(0, colon);
        final def = colon < 0 ? '' : body.substring(colon + 1);
        final n = int.tryParse(numText.trim());
        if (n != null && n >= 0) {
          final start = out.length;
          out.write(def);
          found[n] = SnippetStop(start, out.length);
          i = close + 1;
          continue;
        }
      }
      out.write(c);
      i++;
      continue;
    }
    // `$N`（后面不能再跟标识符字符，否则是 `$foo` 这种普通文本）
    final m = RegExp(r'^\$(\d+)(?![\w])').firstMatch(raw.substring(i));
    if (m != null) {
      final n = int.tryParse(m.group(1)!);
      if (n != null && n >= 0) {
        final start = out.length;
        found[n] = SnippetStop(start, start);
        i += m.group(0)!.length;
        continue;
      }
    }
    out.write(c);
    i++;
  }

  // 排序：1..n 升序，$0 永远最后。
  final keys = found.keys.toList()
    ..sort((a, b) {
      if (a == 0) return 1;
      if (b == 0) return -1;
      return a.compareTo(b);
    });
  return ParsedSnippet(out.toString(), [for (final k in keys) found[k]!]);
}


/// 片段变量展开时需要的上下文。
class SnippetVariables {
  /// 当前文件名（含扩展名）。
  final String fileName;

  /// 当前文件全路径。
  final String filePath;

  /// 当前选中的文本（`$SELECTION`）。
  final String selection;

  /// 当前语言的单行注释符（`$LINE_COMMENT`，如 `//` / `#` / `--`）。
  ///
  /// 这些按语言取值而不是写死，是因为「插入注释模板」是片段里最常见的动作，
  /// 而 HTML/XML 的 `<!-- -->` 和 C 系的 `/* */` 完全是两套写法。
  final String lineComment;

  /// 当前语言的块注释起止（`$BLOCK_COMMENT_START` / `$BLOCK_COMMENT_END`）。
  final String blockCommentStart;
  final String blockCommentEnd;

  const SnippetVariables({
    this.fileName = '',
    this.filePath = '',
    this.selection = '',
    this.lineComment = '',
    this.blockCommentStart = '',
    this.blockCommentEnd = '',
  });

  /// 去掉扩展名的文件名。
  String get fileNameBase {
    final i = fileName.lastIndexOf('.');
    return i > 0 ? fileName.substring(0, i) : fileName;
  }

  /// 所在目录（无路径时返回空）。
  String get directory {
    final p = filePath.isEmpty ? '' : filePath;
    if (p.isEmpty) return '';
    final i = p.lastIndexOf(RegExp(r'[/\\]'));
    return i > 0 ? p.substring(0, i) : '';
  }
}

final _varRe = RegExp(r'\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))');

String _two(int v) => v < 10 ? '0$v' : '$v';

/// 展开片段里的变量（VS Code 的 snippet 变量子集）。
///
/// 不认识的变量**原样保留**——`$foo` 可能是用户真的要写的东西（shell 变量、
/// 模板引擎语法），吃掉它比留着更糟。
String expandSnippetVariables(
  String raw,
  SnippetVariables vars, {
  DateTime? now,
}) {
  if (!raw.contains(r'$')) return raw;
  final t = now ?? DateTime.now();
  return raw.replaceAllMapped(_varRe, (m) {
    final name = m.group(1) ?? m.group(2) ?? '';
    switch (name) {
      case 'TM_FILENAME':
        return vars.fileName;
      case 'TM_FILENAME_BASE':
        return vars.fileNameBase;
      case 'TM_DIRECTORY':
        return vars.directory;
      case 'TM_FILEPATH':
        return vars.filePath;
      case 'SELECTION':
        return vars.selection;
      case 'LINE_COMMENT':
        return vars.lineComment;
      case 'BLOCK_COMMENT_START':
        return vars.blockCommentStart;
      case 'BLOCK_COMMENT_END':
        return vars.blockCommentEnd;
      case 'CURRENT_YEAR':
        return '${t.year}';
      case 'CURRENT_YEAR_SHORT':
        return '${t.year % 100}'.padLeft(2, '0');
      case 'CURRENT_MONTH':
        return _two(t.month);
      case 'CURRENT_DATE':
        return _two(t.day);
      case 'CURRENT_HOUR':
        return _two(t.hour);
      case 'CURRENT_MINUTE':
        return _two(t.minute);
      case 'CURRENT_SECOND':
        return _two(t.second);
      case 'CURRENT_DATETIME':
        return '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
      case 'UUID':
        return _uuid();
      case 'RANDOM':
        return '${_rand.nextInt(1000000)}'.padLeft(6, '0');
      case 'RANDOM_HEX':
        return '${_rand.nextInt(0x1000000).toRadixString(16)}'.padLeft(6, '0');
      default:
        // 未知变量原样返回，别把用户的内容吃掉。
        return m.group(0)!;
    }
  });
}

final _rand = Random();

/// 随机 UUID v4。不用引入 uuid 包，这里只要求「看起来像 UUID 且不重复」。
String _uuid() {
  final b = List<int>.generate(16, (_) => _rand.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
