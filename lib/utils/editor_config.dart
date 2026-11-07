import 'dart:io';

/// `.editorconfig` 里能影响到编辑器的属性。
///
/// 只收「打开/保存一个文件时会真正用到」的几项，别的（比如 `max_line_length`）
/// 解析出来也不做任何事，索性不认，免得给人「设了没生效」的错觉。
class EditorProperties {
  const EditorProperties({
    this.indentStyle,
    this.indentSize,
    this.tabWidth,
    this.endOfLine,
    this.charset,
    this.trimTrailingWhitespace,
    this.insertFinalNewline,
  });

  /// `space` / `tab`
  final String? indentStyle;

  /// 缩进列数；`indent_size = tab` 会落成 [tabWidth]。
  final int? indentSize;

  final int? tabWidth;

  /// `lf` / `crlf` / `cr`
  final String? endOfLine;

  /// `utf-8` / `utf-8-bom` / `latin1` / `utf-16be` / `utf-16le`
  final String? charset;

  final bool? trimTrailingWhitespace;
  final bool? insertFinalNewline;

  bool get isEmpty =>
      indentStyle == null &&
      indentSize == null &&
      tabWidth == null &&
      endOfLine == null &&
      charset == null &&
      trimTrailingWhitespace == null &&
      insertFinalNewline == null;

  /// 这一份之后覆盖 [other]（`other` 更靠近文件，优先级更高）。
  EditorProperties merge(EditorProperties other) => EditorProperties(
        indentStyle: other.indentStyle ?? indentStyle,
        indentSize: other.indentSize ?? indentSize,
        tabWidth: other.tabWidth ?? tabWidth,
        endOfLine: other.endOfLine ?? endOfLine,
        charset: other.charset ?? charset,
        trimTrailingWhitespace:
            other.trimTrailingWhitespace ?? trimTrailingWhitespace,
        insertFinalNewline: other.insertFinalNewline ?? insertFinalNewline,
      );

  /// 换行符字符串（`\n` / `\r\n` / `\r`）。
  String? get newlineChars => switch (endOfLine) {
        'lf' => '\n',
        'crlf' => '\r\n',
        'cr' => '\r',
        _ => null,
      };
}

/// 一条 `[pattern]` 段。
class EditorConfigSection {
  const EditorConfigSection(this.pattern, this.properties);

  final String pattern;
  final EditorProperties properties;
}

/// 一个 `.editorconfig` 文件。
class EditorConfig {
  EditorConfig(this.sections);

  final List<EditorConfigSection> sections;

  static const int _maxBytes = 512 * 1024;

  /// 解析文本内容。看不懂的行一律跳过（配置文件是给人手写的，容错比严格重要）。
  static EditorConfig parse(String content) {
    final sections = <EditorConfigSection>[];
    var currentPattern = '';
    var props = <String, String>{};

    void flush() {
      if (currentPattern.isEmpty) return;
      final parsed = _propertiesOf(props);
      if (!parsed.isEmpty) {
        sections.add(EditorConfigSection(currentPattern, parsed));
      }
      props = <String, String>{};
    }

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#') || line.startsWith(';')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        flush();
        currentPattern = line.substring(1, line.length - 1).trim();
        continue;
      }
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim().toLowerCase();
      var value = line.substring(eq + 1).trim();
      // 行尾注释：只有前面有空白时才算注释（值里本来可能有 `#`）。
      final hash = value.indexOf(' #');
      if (hash > 0) value = value.substring(0, hash).trim();
      final semi = value.indexOf(' ;');
      if (semi > 0) value = value.substring(0, semi).trim();
      if (key.isEmpty || value.isEmpty) continue;
      props[key] = value;
    }
    flush();
    return EditorConfig(sections);
  }

  static EditorProperties _propertiesOf(Map<String, String> props) {
    int? toInt(String? v) {
      if (v == null) return null;
      final n = int.tryParse(v.trim());
      if (n == null || n <= 0) return null;
      return n.clamp(1, 16);
    }

    bool? toBool(String? v) {
      if (v == null) return null;
      switch (v.trim().toLowerCase()) {
        case 'true':
        case 'yes':
          return true;
        case 'false':
        case 'no':
          return false;
      }
      return null;
    }

    final style = props['indent_style']?.trim().toLowerCase();
    final tabWidth = toInt(props['tab_width']);
    int? indentSize;
    final rawIndent = props['indent_size']?.trim().toLowerCase();
    if (rawIndent == 'tab') {
      indentSize = tabWidth;
    } else {
      indentSize = toInt(rawIndent);
    }
    return EditorProperties(
      indentStyle: (style == 'space' || style == 'tab') ? style : null,
      indentSize: indentSize,
      tabWidth: tabWidth,
      endOfLine: switch (props['end_of_line']?.trim().toLowerCase()) {
        'lf' => 'lf',
        'crlf' => 'crlf',
        'cr' => 'cr',
        _ => null,
      },
      charset: switch (props['charset']?.trim().toLowerCase()) {
        'utf-8' => 'utf-8',
        'utf-8-bom' => 'utf-8-bom',
        'latin1' => 'latin1',
        'utf-16be' => 'utf-16be',
        'utf-16le' => 'utf-16le',
        _ => null,
      },
      trimTrailingWhitespace: toBool(props['trim_trailing_whitespace']),
      insertFinalNewline: toBool(props['insert_final_newline']),
    );
  }

  /// 针对某个路径算出最终生效的属性。
  ///
  /// [relativePath] 是相对 `.editorconfig` 所在目录的路径（用 `/` 分隔）。
  EditorProperties resolve(String relativePath) {
    var result = const EditorProperties();
    for (final section in sections) {
      if (!_match(section.pattern, relativePath)) continue;
      result = result.merge(section.properties);
    }
    return result;
  }

  /// glob 匹配。
  ///
  /// 规则（EditorConfig 规范里最常用的那几条）：
  /// - 模式里没有 `/` 时，匹配任意层级的文件名；
  /// - `*` 不跨 `/`，`**` 跨 `/`，`?` 一个非 `/` 字符；
  /// - `{a,b}` 是「或」，`[abc]` 是字符集。
  static bool _match(String pattern, String path) {
    if (pattern.isEmpty) return false;
    var p = pattern.replaceAll('\\', '/');
    final hasSlash = p.contains('/');
    if (p.startsWith('/')) p = p.substring(1);
    final regex = StringBuffer('^');
    if (!hasSlash) regex.write('(?:.*/)?');
    for (var i = 0; i < p.length; i++) {
      final c = p[i];
      if (c == '*') {
        if (i + 1 < p.length && p[i + 1] == '*') {
          regex.write('.*');
          i++;
        } else {
          regex.write('[^/]*');
        }
      } else if (c == '?') {
        regex.write('[^/]');
      } else if (c == '{') {
        final end = p.indexOf('}', i);
        if (end < 0) {
          regex.write(r'\{');
        } else {
          final parts = p
              .substring(i + 1, end)
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .map(RegExp.escape)
              .join('|');
          regex.write('(?:$parts)');
          i = end;
        }
      } else if (c == '[') {
        final end = p.indexOf(']', i);
        if (end < 0) {
          regex.write(r'\[');
        } else {
          final body = p.substring(i + 1, end);
          // `[!a]` 是「非 a」
          final negate = body.startsWith('!');
          final chars = negate ? body.substring(1) : body;
          regex.write(negate ? '[^$chars]' : '[$chars]');
          i = end;
        }
      } else {
        regex.write(RegExp.escape(c));
      }
    }
    regex.write(r'$');
    try {
      return RegExp(regex.toString(), caseSensitive: true).hasMatch(path);
    } catch (_) {
      return false;
    }
  }

  /// 从 [filePath] 所在目录往上找 `.editorconfig`，逐层合并。
  ///
  /// 越靠近文件的优先级越高（后面覆盖前面），和规范一致。
  static Future<EditorProperties?> loadFor(String filePath) async {
    if (filePath.isEmpty) return null;
    try {
      final normalized = filePath.replaceAll('\\', '/');
      final parts = normalized.split('/');
      if (parts.isEmpty) return null;
      final baseName = parts.removeLast();
      var dir = parts.join('/');
      EditorProperties? merged;
      for (var depth = 0; depth < 8; depth++) {
        if (dir.isEmpty) break;
        final configPath = '$dir/.editorconfig';
        final file = File(configPath);
        if (file.existsSync()) {
          final length = file.lengthSync();
          if (length <= _maxBytes) {
            final text = await file.readAsString();
            final config = EditorConfig.parse(text);
            final rel = _relativeOf(normalized, dir);
            final props = config.resolve(rel);
            if (!props.isEmpty) {
              merged = merged == null ? props : props.merge(merged);
            }
            // 规范里 `root = true` 表示不再往上找。这里简化为「找到就用」：
            // 再往上多半是别的项目，混进来反而奇怪。
            break;
          }
        }
        final idx = dir.lastIndexOf('/');
        if (idx < 0) break;
        dir = idx == 0 ? '/' : dir.substring(0, idx);
        if (dir == '/') break;
      }
      // baseName 只用于确认路径没解析歪，值本身不参与属性计算。
      assert(baseName.isNotEmpty);
      return merged;
    } catch (_) {
      return null;
    }
  }

  static String _relativeOf(String filePath, String dir) {
    final normalizedDir = dir.replaceAll('\\', '/');
    if (filePath.startsWith('$normalizedDir/')) {
      return filePath.substring(normalizedDir.length + 1);
    }
    return filePath;
  }
}
