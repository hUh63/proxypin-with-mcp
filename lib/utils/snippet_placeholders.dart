/// 代码片段里的「占位符」（VS Code / VS 的 snippet 语法）：
///
/// - `$1` `$2` … 光标停靠点，按编号顺序跳；
/// - `${1:默认值}` 带默认文本的停靠点，插入后该段是**选中**状态，直接打字即替换；
/// - `$0` 最后停留的位置（会话结束）；
/// - `\$` 是要插入一个真正的美元符号（shell、正则替换里很常见）。
///
/// 为什么只在「片段插入」这条路上解析：普通粘贴/插入的内容里 `$1` 太常见了
/// （shell 位置参数、正则反向引用），全局解析会把正常代码改坏。
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
