// 精简版 Emmet：把 `div.card>ul.list>li.item$*3` 这类缩写展开成 HTML。
//
// 为什么放 lib/utils 且不依赖 flutter：解析与生成都是纯字符串处理，能直接单测
// —— 展开错一个缩进、少一个闭合标签，肉眼很难在几十行里发现。
//
// 只实现最常用的子集：`tag` / `#id` / `.class` / `[attr=value]` / `{text}` /
// `*n` 重复 / `>` 子级 / `+` 兄弟 / `$` 序号。不支持 `^`（爬升）、`()`（分组）、
// `|`（文本管道）：这些在手机键盘上输入成本高，收益也小。

/// 展开结果：生成的代码 + 建议的光标位置（相对 [text] 起始的偏移）。
class EmmetExpansion {
  final String text;
  final int caretOffset;

  const EmmetExpansion(this.text, this.caretOffset);
}

const Set<String> _voidTags = <String>{
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img',
  'input', 'link', 'meta', 'param', 'source', 'track', 'wbr',
};

class _EmmetNode {
  String tag = '';
  String? id;
  final List<String> classes = <String>[];
  final List<MapEntry<String, String>> attrs = <MapEntry<String, String>>[];
  String text = '';
  int repeat = 1;
  final List<_EmmetNode> children = <_EmmetNode>[];
}

/// 展开 Emmet 缩写；缩写不合法（或没有可展开内容）时返回 null。
///
/// [indentUnit] 是每一级的缩进（跟随编辑器的 Tab / 空格设置）。
EmmetExpansion? expandEmmet(String abbreviation, {String indentUnit = '  '}) {
  final abbr = abbreviation.trim();
  if (abbr.isEmpty || abbr.contains('\n')) return null;
  try {
    final nodes = _parseSiblings(abbr);
    if (nodes.isEmpty) return null;
    final out = StringBuffer();
    for (final n in nodes) {
      _emit(n, 0, out, indentUnit);
    }
    final text = out.toString().replaceFirst(RegExp(r'\n+$'), '');
    if (text.isEmpty) return null;
    return EmmetExpansion(text, text.length);
  } catch (_) {
    return null;
  }
}

List<_EmmetNode> _parseSiblings(String s) {
  final parts = _splitTop(s, '+');
  final nodes = <_EmmetNode>[];
  for (final p in parts) {
    final n = _parseChain(p);
    if (n != null) nodes.add(n);
  }
  return nodes;
}

_EmmetNode? _parseChain(String s) {
  final parts = _splitTop(s, '>');
  if (parts.isEmpty) return null;
  final root = _parseElem(parts.first);
  var cur = root;
  for (var i = 1; i < parts.length; i++) {
    final child = _parseElem(parts[i]);
    cur.children.add(child);
    cur = child;
  }
  return root;
}

_EmmetNode _parseElem(String raw) {
  var s = raw.trim();
  final node = _EmmetNode();

  // 重复次数：末尾的 `*n`
  final rep = RegExp(r'\*(\d+)$').firstMatch(s);
  if (rep != null) {
    node.repeat = int.tryParse(rep.group(1)!) ?? 1;
    if (node.repeat < 1) node.repeat = 1;
    if (node.repeat > 200) node.repeat = 200; // 兜底：别一次展开出上千行
    s = s.substring(0, rep.start);
  }

  // 文本 {..}（可以有多个，按顺序拼）
  final textBuf = StringBuffer();
  s = _extractBraces(s, '{', '}', (c) => textBuf.write(c));
  node.text = textBuf.toString();

  // 属性 [a=b c]
  s = _extractBraces(s, '[', ']', (content) {
    for (final pair in content.split(RegExp(r'\s+'))) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      if (eq < 0) {
        node.attrs.add(MapEntry<String, String>(pair, ''));
      } else {
        node.attrs.add(MapEntry<String, String>(
            pair.substring(0, eq), pair.substring(eq + 1)));
      }
    }
  });

  // tag
  final tagMatch = RegExp(r'^[A-Za-z][\w-]*').firstMatch(s);
  if (tagMatch != null) {
    node.tag = tagMatch.group(0)!;
    s = s.substring(tagMatch.end);
  }

  // #id / .class（可多个，顺序无关）
  for (final m in RegExp(r'[.#]([\w-]+)').allMatches(s)) {
    final v = m.group(1)!;
    if (m.group(0)!.startsWith('#')) {
      node.id = v;
    } else {
      node.classes.add(v);
    }
  }

  return node;
}

/// 取走 [s] 里所有 `open ... close` 段交给 [onContent]，返回剩下的部分。
String _extractBraces(String s, String open, String close, void Function(String) onContent) {
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    if (s[i] == open) {
      final j = s.indexOf(close, i + 1);
      if (j < 0) {
        out.write(s.substring(i));
        break;
      }
      onContent(s.substring(i + 1, j));
      i = j + 1;
    } else {
      out.write(s[i]);
      i++;
    }
  }
  return out.toString();
}

/// 按 [sep] 切分，但跳过 `[]` `{}` `()` 内部的分隔符。
List<String> _splitTop(String s, String sep) {
  final parts = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == '[' || ch == '{' || ch == '(') depth++;
    if (ch == ']' || ch == '}' || ch == ')') depth--;
    if (depth == 0 && ch == sep) {
      parts.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  parts.add(buf.toString());
  return parts.where((p) => p.trim().isNotEmpty).toList(growable: false);
}

void _emit(_EmmetNode n, int depth, StringBuffer out, String unit) {
  final tag = n.tag.isEmpty ? 'div' : n.tag;
  final pad = unit * depth;
  for (var r = 1; r <= n.repeat; r++) {
    final idx = '$r';
    final id = n.id?.replaceAll(r'$', idx);
    final cls = n.classes.map((c) => c.replaceAll(r'$', idx)).join(' ');
    final attrs = StringBuffer();
    if (id != null && id.isNotEmpty) attrs.write(' id="$id"');
    if (cls.isNotEmpty) attrs.write(' class="$cls"');
    for (final a in n.attrs) {
      final key = a.key.replaceAll(r'$', idx);
      final value = a.value.replaceAll(r'$', idx);
      attrs.write(value.isEmpty ? ' $key' : ' $key="$value"');
    }
    final text = n.text.replaceAll(r'$', idx);

    if (_voidTags.contains(tag.toLowerCase())) {
      out.writeln('$pad<$tag$attrs />');
    } else if (n.children.isEmpty) {
      out.writeln('$pad<$tag$attrs>$text</$tag>');
    } else {
      out.writeln('$pad<$tag$attrs>');
      for (final c in n.children) {
        _emit(c, depth + 1, out, unit);
      }
      out.writeln('$pad</$tag>');
    }
  }
}
