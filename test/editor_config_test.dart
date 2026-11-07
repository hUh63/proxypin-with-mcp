import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/editor_config.dart';

void main() {
  group('解析', () {
    test('基本段与属性', () {
      const text = '''
# 注释
root = true

[*]
indent_style = space
indent_size = 4
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = false

[*.dart]
indent_size = 2
''';
      final config = EditorConfig.parse(text);
      expect(config.sections.length, 2);
      final props = config.resolve('lib/main.dart');
      expect(props.indentStyle, 'space');
      expect(props.indentSize, 2);
      expect(props.endOfLine, 'lf');
      expect(props.newlineChars, '\n');
      expect(props.charset, 'utf-8');
      expect(props.trimTrailingWhitespace, isTrue);
      expect(props.insertFinalNewline, isFalse);
    });

    test('indent_size = tab 时取 tab_width', () {
      const text = '[*]\nindent_size = tab\ntab_width = 8\n';
      final props = EditorConfig.parse(text).resolve('a.txt');
      expect(props.indentSize, 8);
      expect(props.tabWidth, 8);
    });

    test('非法值被忽略（不抛异常）', () {
      const text = '[*]\nindent_size = abc\nend_of_line = mac\ncharset = koi8\n'
          'trim_trailing_whitespace = maybe\nindent_style = mixed\n';
      final props = EditorConfig.parse(text).resolve('a.txt');
      expect(props.indentSize, isNull);
      expect(props.endOfLine, isNull);
      expect(props.charset, isNull);
      expect(props.trimTrailingWhitespace, isNull);
      expect(props.indentStyle, isNull);
      expect(props.isEmpty, isTrue);
    });

    test('行尾注释被去掉', () {
      const text = '[*]\nindent_size = 2 # 两格\n';
      expect(EditorConfig.parse(text).resolve('a.txt').indentSize, 2);
    });

    test('空内容不产生段', () {
      expect(EditorConfig.parse('').sections, isEmpty);
      expect(EditorConfig.parse('\n\n# x\n').sections, isEmpty);
    });
  });

  group('glob 匹配', () {
    EditorProperties propsOf(String pattern) {
      final config = EditorConfig.parse('[$pattern]\nindent_size = 7\n');
      return config.resolve('src/lib/main.dart');
    }

    test('无斜杠的模式匹配任意层级的文件名', () {
      final config = EditorConfig.parse('[*.dart]\nindent_size = 2\n');
      expect(config.resolve('main.dart').indentSize, 2);
      expect(config.resolve('a/b/c.dart').indentSize, 2);
      expect(config.resolve('a/b/c.js').indentSize, isNull);
    });

    test('* 不跨目录', () {
      final config = EditorConfig.parse('[src/*.dart]\nindent_size = 3\n');
      expect(config.resolve('src/a.dart').indentSize, 3);
      expect(config.resolve('src/sub/a.dart').indentSize, isNull);
    });

    test('** 跨目录', () {
      final config = EditorConfig.parse('[src/**/*.dart]\nindent_size = 5\n');
      expect(config.resolve('src/sub/deep/a.dart').indentSize, 5);
    });

    test('[jt] 字符集', () {
      final config = EditorConfig.parse('[*.[jt]s]\nindent_size = 9\n');
      expect(config.resolve('a.js').indentSize, 9);
      expect(config.resolve('a.ts').indentSize, 9);
      expect(config.resolve('a.css').indentSize, isNull);
    });

    test('花括号', () {
      final config = EditorConfig.parse('[*.{js,ts}]\nindent_size = 9\n');
      expect(config.resolve('a.js').indentSize, 9);
      expect(config.resolve('a.ts').indentSize, 9);
      expect(config.resolve('a.css').indentSize, isNull);
    });

    test('? 匹配单个字符', () {
      final config = EditorConfig.parse('[a?.txt]\nindent_size = 4\n');
      expect(config.resolve('ab.txt').indentSize, 4);
      expect(config.resolve('abc.txt').indentSize, isNull);
    });

    test('不匹配时返回空属性', () {
      expect(propsOf('[*.rs]').isEmpty, isTrue);
    });
  });

  group('多段覆盖', () {
    test('后面的段覆盖前面的', () {
      const text = '''
[*]
indent_size = 4
end_of_line = lf

[*.dart]
indent_size = 2
''';
      final props = EditorConfig.parse(text).resolve('a.dart');
      expect(props.indentSize, 2);
      expect(props.endOfLine, 'lf');
    });

    test('不匹配的段不影响结果', () {
      const text = '[*]\nindent_size = 4\n[*.rs]\nindent_size = 8\n';
      expect(EditorConfig.parse(text).resolve('a.dart').indentSize, 4);
    });

    test('merge 右边优先', () {
      const a = EditorProperties(indentSize: 4, charset: 'utf-8');
      const b = EditorProperties(indentSize: 2);
      final m = a.merge(b);
      expect(m.indentSize, 2);
      expect(m.charset, 'utf-8');
    });
  });

  group('newlineChars', () {
    test('三种换行符', () {
      expect(const EditorProperties(endOfLine: 'crlf').newlineChars, '\r\n');
      expect(const EditorProperties(endOfLine: 'cr').newlineChars, '\r');
      expect(const EditorProperties(endOfLine: 'lf').newlineChars, '\n');
      expect(const EditorProperties().newlineChars, isNull);
    });
  });
}
