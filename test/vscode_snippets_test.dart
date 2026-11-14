// VS Code 片段文件解析：格式有两种（单片段 / 集合），且 `body` 可以是数组或字符串。
// 这里锁住 label 的取值优先级与 body 的拼接方式 —— 导入后片段列表一乱就很难认。
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/vscode_snippets.dart';

void main() {
  group('parseVSCodeSnippets', () {
    test('集合形态：键名当 label，body 数组按行拼', () {
      const raw = '''
{
  "打印日志": { "prefix": "log", "body": ["console.log('\$1');", "\$2"] },
  "函数": { "prefix": "fn", "body": ["function \$1() {", "\t\$0", "}"] }
}''';
      final list = parseVSCodeSnippets(raw);
      expect(list.length, 2);
      expect(list.first.label, '打印日志');
      expect(list.first.insert, "console.log('\$1');\n\$2");
      expect(list.last.label, '函数');
    });

    test('单片段形态（顶层直接带 body）', () {
      const raw = '{"name": "if", "prefix": "if", "body": ["if (\$1) {", "}"]}';
      final list = parseVSCodeSnippets(raw);
      expect(list.length, 1);
      // 顶层没有集合键，label 退回 prefix
      expect(list.first.label, 'if');
      expect(list.first.insert, 'if (\$1) {\n}');
    });

    test('body 是字符串也能用', () {
      const raw = '{"x": {"prefix": "x", "body": "hello \$1"}}';
      final list = parseVSCodeSnippets(raw);
      expect(list.first.insert, 'hello \$1');
    });

    test('缺 body / body 为空的对象被跳过', () {
      const raw = '{"a": {"prefix": "a"}, "b": {"body": []}, "c": {"body": ["ok"]}}';
      final list = parseVSCodeSnippets(raw);
      expect(list.length, 1);
      expect(list.first.label, 'c');
    });

    test('非 JSON / 非对象返回空', () {
      expect(parseVSCodeSnippets('not json'), isEmpty);
      expect(parseVSCodeSnippets('[1,2,3]'), isEmpty);
      expect(parseVSCodeSnippets(''), isEmpty);
    });

    test('没有键名时用 description，再退回 snippet', () {
      // 键名为空 → 用 description
      final withDesc = parseVSCodeSnippets('{"": {"description": "desc", "body": ["x"]}}');
      expect(withDesc.first.label, 'desc');
      // prefix / description 都没有 → 兜底 snippet
      final bare = parseVSCodeSnippets('{"": {"body": ["x"]}}');
      expect(bare.first.label, 'snippet');
    });
  });
}
