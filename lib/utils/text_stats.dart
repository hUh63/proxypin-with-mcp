import 'dart:convert';

/// 一段文本的统计结果（Notepad++ 的「文档摘要」、VS Code 的 Word Count）。
class TextStats {
  const TextStats({
    this.lines = 0,
    this.words = 0,
    this.chars = 0,
    this.charsNoSpace = 0,
    this.bytes = 0,
    this.maxLineLength = 0,
    this.longestLine = 0,
    this.paragraphs = 0,
  });

  /// 行数。末尾那个换行不算「多一行」（和编辑器状态栏口径一致）。
  final int lines;

  /// 空白分隔的「词」数。
  ///
  /// 中文一长串会被算成 1 个词 —— 想要「字数」看 [charsNoSpace]，它更接近
  /// 中文写作里的字数。
  final int words;

  /// 字符数（含空白和换行）。
  final int chars;

  /// 字符数（不含空白和换行）。
  final int charsNoSpace;

  /// UTF-8 字节数（存盘时大概多大）。
  final int bytes;

  /// 最长一行的字符数。
  final int maxLineLength;

  /// 最长那一行的行号（1 开始）。
  final int longestLine;

  /// 段落数（连续非空行算一段）。
  final int paragraphs;

  /// 统计整段文本。
  static TextStats of(String text) {
    if (text.isEmpty) return const TextStats();
    var lines = 1;
    var words = 0;
    var charsNoSpace = 0;
    var maxLineLength = 0;
    var longestLine = 1;
    var paragraphs = 0;
    var lineLength = 0;
    var line = 1;
    var inWord = false;
    var inParagraph = false;
    // 当前这一行是否已经有非空白字符 —— 段落只在**空行**处断开，
    // 换行本身不是段落边界（否则「a\nb」会被算成两段）。
    var lineHasContent = false;

    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c == 10) {
        if (lineLength > maxLineLength) {
          maxLineLength = lineLength;
          longestLine = line;
        }
        line++;
        lineLength = 0;
        inWord = false;
        if (!lineHasContent) inParagraph = false;
        lineHasContent = false;
        // 末尾的换行不算新的一行。
        if (i != text.length - 1) lines++;
        continue;
      }
      if (c == 13) continue; // \r\n 里的 \r 不算内容
      lineLength++;
      final space = c == 32 || c == 9;
      if (space) {
        inWord = false;
      } else {
        charsNoSpace++;
        lineHasContent = true;
        if (!inWord) {
          words++;
          inWord = true;
        }
        if (!inParagraph) {
          paragraphs++;
          inParagraph = true;
        }
      }
    }
    if (lineLength > maxLineLength) {
      maxLineLength = lineLength;
      longestLine = line;
    }
    return TextStats(
      lines: lines,
      words: words,
      chars: text.length,
      charsNoSpace: charsNoSpace,
      bytes: utf8.encode(text).length,
      maxLineLength: maxLineLength,
      longestLine: longestLine,
      paragraphs: paragraphs,
    );
  }

  /// 统计 [start, end) 这一段（越界会 clamp，反过来传也行）。
  static TextStats ofRange(String text, int start, int end) {
    if (text.isEmpty) return const TextStats();
    var a = start.clamp(0, text.length);
    var b = end.clamp(0, text.length);
    if (a > b) {
      final t = a;
      a = b;
      b = t;
    }
    if (a == b) return const TextStats();
    return of(text.substring(a, b));
  }

  bool get isEmpty => chars == 0;

  /// 人性化的体积。
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 带千分位的数字（`1234567` → `1,234,567`）。
  ///
  /// 统计面板上一眼看得出量级，比数一串数字省事。
  static String formatCount(int value) {
    final text = value.toString();
    if (text.length <= 3) return text;
    final out = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) out.write(',');
      out.write(text[i]);
    }
    return out.toString();
  }
}
