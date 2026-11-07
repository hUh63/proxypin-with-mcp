import 'dart:convert';

/// 一条任务（注释里的 TODO / FIXME 之类）。
class TodoHit {
  const TodoHit({
    required this.line,
    required this.tag,
    required this.text,
  });

  /// 1 开始的行号。
  final int line;

  /// 归一化成大写的标签，如 TODO / FIXME。
  final String tag;

  /// 标签后面的说明文字（已 trim，可能为空）。
  final String text;
}

/// 扫描源码注释里的任务标记。
///
/// 对应 VS 的「任务列表」窗口：把散落在代码里的 TODO/FIXME 集中列出来，
/// 点一下就能跳过去。不依赖语言语法分析，只认「注释起始符 + 标记」这种
/// 最通用的写法。
class TodoScanner {
  TodoScanner._();

  /// 默认认的标记。
  ///
  /// 顺序有意义：展示时的排序按这个顺序（TODO 最多，放最前）。
  static const List<String> defaultTags = <String>[
    'TODO',
    'FIXME',
    'HACK',
    'XXX',
    'BUG',
    'NOTE',
    'OPTIMIZE',
    'REVIEW',
  ];

  /// 注释起始符：行注释、块注释、HTML 注释、SQL/Lua 的 `--`、汇编/ini 的 `;`。
  ///
  /// 故意**不含**裸 `"` / `'`：否则字符串里的 "TODO" 会满屏命中。
  static const String _commentStart =
      r'//+|#+|/\*+|\*+|<!--|--|;+|\{-+';

  static final RegExp _pattern = RegExp(
    '(?:^|[\\s(\\[{,;:])$_commentStart\\s*(' + defaultTags.join('|') + r')'
    r'\b[:\s]*([^\r\n]*)',
    caseSensitive: false,
  );

  /// 扫一段文本。
  ///
  /// [tags] 可以只关心其中几个（比如只看 FIXME）；[limit] 是硬上限，防止
  /// 在一个几万行的文件里刷出成百上千条把 UI 卡住。
  static List<TodoHit> scan(
    String text, {
    List<String> tags = defaultTags,
    int limit = 500,
  }) {
    final result = <TodoHit>[];
    if (text.isEmpty) return result;
    final wanted = tags.map((t) => t.toUpperCase()).toSet();
    var line = 1;
    var lineStart = 0;
    for (var i = 0; i <= text.length; i++) {
      final atEnd = i == text.length;
      if (!atEnd && text.codeUnitAt(i) != 10) continue;
      final lineText = text.substring(lineStart, i);
      final hit = _scanLine(lineText, line, wanted);
      if (hit != null) {
        result.add(hit);
        if (result.length >= limit) return result;
      }
      line++;
      lineStart = i + 1;
    }
    return result;
  }

  static TodoHit? _scanLine(String line, int number, Set<String> wanted) {
    if (line.isEmpty) return null;
    // 快速排除：整行连标记的字母都没有就不用跑正则。
    final upper = line.toUpperCase();
    var maybe = false;
    for (final tag in wanted) {
      if (upper.contains(tag)) {
        maybe = true;
        break;
      }
    }
    if (!maybe) return null;
    for (final match in _pattern.allMatches(line)) {
      final tag = match.group(1)?.toUpperCase();
      if (tag == null || !wanted.contains(tag)) continue;
      var rest = match.group(2) ?? '';
      rest = _trimDecoration(rest);
      return TodoHit(line: number, tag: tag, text: rest);
    }
    return null;
  }

  /// 去掉说明文字两头的修饰：`*/`、`-->`、`//` 这些收尾符号不该出现在列表里。
  static String _trimDecoration(String raw) {
    var text = raw.trim();
    // 去掉行尾的注释收尾符
    for (final tail in <String>['*/', '-->', '-}', '}', '-->']) {
      while (text.endsWith(tail)) {
        text = text.substring(0, text.length - tail.length).trimRight();
      }
    }
    // 去掉行首多余的分隔（`TODO: - 说明` 里那个 `-`）
    if (text.startsWith('- ') || text.startsWith('* ')) {
      text = text.substring(2).trimLeft();
    }
    if (text.startsWith(':') || text.startsWith('：')) {
      text = text.substring(1).trimLeft();
    }
    if (text.length > 300) text = '${text.substring(0, 300)}…';
    return text;
  }

  /// 统计每个标签有多少条（给筛选条用）。
  static Map<String, int> countByTag(List<TodoHit> hits) {
    final map = <String, int>{};
    for (final hit in hits) {
      map[hit.tag] = (map[hit.tag] ?? 0) + 1;
    }
    return map;
  }

  /// 按标签顺序排序（同标签内保持原行号顺序）。
  static List<TodoHit> sortByTag(List<TodoHit> hits,
      {List<String> tags = defaultTags}) {
    final order = <String, int>{};
    for (var i = 0; i < tags.length; i++) {
      order[tags[i].toUpperCase()] = i;
    }
    final copy = List<TodoHit>.from(hits);
    copy.sort((a, b) {
      final oa = order[a.tag] ?? 99;
      final ob = order[b.tag] ?? 99;
      if (oa != ob) return oa.compareTo(ob);
      return a.line.compareTo(b.line);
    });
    return copy;
  }

  /// 以 UTF-8 字节数粗判是否值得扫（超大的就跳过）。
  static bool tooLarge(String text, {int maxBytes = 4 * 1024 * 1024}) {
    if (text.length > maxBytes) return true;
    return utf8.encode(text).length > maxBytes;
  }
}
