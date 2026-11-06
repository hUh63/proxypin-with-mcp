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

/// 一个可插入的代码片段模板。
///
/// [body] 是**相对缩进**的模板：插入时会按光标所在行的缩进整体右移，
/// 所以模板里只写相对层级（两个空格一层）。
/// `$0` 是插入后光标落点，会被移除再定位。
class CodeSnippet {
  final String label;
  final String body;

  const CodeSnippet(this.label, this.body);
}

/// 按语言给的多行代码结构模板。
///
/// 与「快捷输入行」（ToolSnippetDefaults，那是短语/符号级的插入）分工：
/// 这里只放**多行结构**（class / for / try / 函数骨架），
/// 是对标 VS 的 IntelliSense snippet 的那一层。
class CodeSnippets {
  static const Map<String, List<CodeSnippet>> _byFamily = {
    'dart': [
      CodeSnippet('class', r'''class $0 {
  
}'''),
      CodeSnippet('函数', r'''Future<void> $0() async {
  
}'''),
      CodeSnippet('main', r'''void main() {
  $0
}'''),
      CodeSnippet('if', r'''if (cond) {
  $0
}'''),
      CodeSnippet('for', r'''for (var i = 0; i < n; i++) {
  $0
}'''),
      CodeSnippet('for-in', r'''for (final item in items) {
  $0
}'''),
      CodeSnippet('try', r'''try {
  $0
} catch (e) {
  
}'''),
      CodeSnippet('switch', r'''switch (value) {
  case 1:
    $0
    break;
  default:
    break;
}'''),
      CodeSnippet('test', r'''test('$0', () {
  expect(actual, expected);
});'''),
    ],
    'java': [
      CodeSnippet('class', r'''public class $0 {
  
}'''),
      CodeSnippet('方法', r'''public void $0() {
  
}'''),
      CodeSnippet('main', r'''public static void main(String[] args) {
  $0
}'''),
      CodeSnippet('if', r'''if (cond) {
  $0
}'''),
      CodeSnippet('for', r'''for (int i = 0; i < n; i++) {
  $0
}'''),
      CodeSnippet('for-each', r'''for (String item : items) {
  $0
}'''),
      CodeSnippet('try', r'''try {
  $0
} catch (Exception e) {
  e.printStackTrace();
}'''),
      CodeSnippet('switch', r'''switch (value) {
  case 1:
    $0
    break;
  default:
    break;
}'''),
    ],
    'python': [
      CodeSnippet('def', r'''def $0():
    
'''),
      CodeSnippet('class', r'''class $0:
    def __init__(self):
        
'''),
      CodeSnippet('if', r'''if cond:
    $0'''),
      CodeSnippet('for', r'''for item in items:
    $0'''),
      CodeSnippet('while', r'''while cond:
    $0'''),
      CodeSnippet('try', r'''try:
    $0
except Exception as e:
    print(e)'''),
      CodeSnippet('with', r'''with open(path) as f:
    $0'''),
      CodeSnippet('main', r'''def main():
    $0


if __name__ == '__main__':
    main()'''),
    ],
    'javascript': [
      CodeSnippet('function', r'''function $0() {
  
}'''),
      CodeSnippet('箭头函数', r'''const $0 = () => {
  
};'''),
      CodeSnippet('class', r'''class $0 {
  constructor() {
    
  }
}'''),
      CodeSnippet('if', r'''if (cond) {
  $0
}'''),
      CodeSnippet('for', r'''for (let i = 0; i < n; i++) {
  $0
}'''),
      CodeSnippet('for-of', r'''for (const item of items) {
  $0
}'''),
      CodeSnippet('try', r'''try {
  $0
} catch (e) {
  console.error(e);
}'''),
      CodeSnippet('promise', r'''new Promise((resolve, reject) => {
  $0
});'''),
      CodeSnippet('async', r'''async function $0() {
  
}'''),
    ],
    'go': [
      CodeSnippet('func', r'''func $0() {
  
}'''),
      CodeSnippet('method', r'''func (r *T) $0() {
  
}'''),
      CodeSnippet('struct', r'''type $0 struct {
  
}'''),
      CodeSnippet('interface', r'''type $0 interface {
  
}'''),
      CodeSnippet('if err', r'''if err != nil {
  return err
}
$0'''),
      CodeSnippet('for', r'''for i := 0; i < n; i++ {
  $0
}'''),
      CodeSnippet('go', r'''go func() {
  $0
}()'''),
      CodeSnippet('switch', r'''switch v {
case 1:
  $0
default:
}'''),
    ],
    'csharp': [
      CodeSnippet('class', r'''public class $0
{
    
}'''),
      CodeSnippet('方法', r'''public void $0()
{
    
}'''),
      CodeSnippet('if', r'''if (cond)
{
    $0
}'''),
      CodeSnippet('for', r'''for (var i = 0; i < n; i++)
{
    $0
}'''),
      CodeSnippet('foreach', r'''foreach (var item in items)
{
    $0
}'''),
      CodeSnippet('try', r'''try
{
    $0
}
catch (Exception ex)
{
    
}'''),
      CodeSnippet('属性', r'''public string $0 { get; set; }'''),
      CodeSnippet('using', r'''using (var stream = File.OpenRead(path))
{
    $0
}'''),
    ],
    'c': [
      CodeSnippet('#include', r'''#include <stdio.h>

$0'''),
      CodeSnippet('main', r'''int main(int argc, char **argv) {
    
    return 0;
}'''),
      CodeSnippet('if', r'''if (cond) {
    $0
}'''),
      CodeSnippet('for', r'''for (int i = 0; i < n; i++) {
    $0
}'''),
      CodeSnippet('struct', r'''typedef struct {
    
} $0;'''),
      CodeSnippet('malloc', r'''buf = malloc(size);
if (buf == NULL) {
    return -1;
}
$0'''),
    ],
    'cpp': [
      CodeSnippet('#include', r'''#include <iostream>

$0'''),
      CodeSnippet('class', r'''class $0 {
public:
    
};'''),
      CodeSnippet('main', r'''int main() {
    $0
    return 0;
}'''),
      CodeSnippet('if', r'''if (cond) {
    $0
}'''),
      CodeSnippet('for', r'''for (int i = 0; i < n; ++i) {
    $0
}'''),
      CodeSnippet('for-range', r'''for (const auto& item : items) {
    $0
}'''),
      CodeSnippet('try', r'''try {
    $0
} catch (const std::exception& e) {
    std::cerr << e.what() << std::endl;
}'''),
    ],
    'php': [
      CodeSnippet('function', r'''function $0() {
    
}'''),
      CodeSnippet('class', r'''class $0 {
    public function __construct() {
        
    }
}'''),
      CodeSnippet('if', r'''if (cond) {
    $0
}'''),
      CodeSnippet('foreach', r'''foreach ($items as $item) {
    $0
}'''),
      CodeSnippet('try', r'''try {
    $0
} catch (Exception $e) {
    echo $e->getMessage();
}'''),
    ],
    'ruby': [
      CodeSnippet('def', r'''def $0
    
end'''),
      CodeSnippet('class', r'''class $0
  def initialize
    
  end
end'''),
      CodeSnippet('if', r'''if cond
  $0
end'''),
      CodeSnippet('each', r'''items.each do |item|
  $0
end'''),
      CodeSnippet('begin', r'''begin
  $0
rescue => e
  puts e
end'''),
    ],
    'kotlin': [
      CodeSnippet('fun', r'''fun $0() {
    
}'''),
      CodeSnippet('class', r'''class $0 {
    
}'''),
      CodeSnippet('if', r'''if (cond) {
    $0
}'''),
      CodeSnippet('for', r'''for (item in items) {
    $0
}'''),
      CodeSnippet('when', r'''when (value) {
    1 -> $0
    else -> {}
}'''),
    ],
    'swift': [
      CodeSnippet('func', r'''func $0() {
    
}'''),
      CodeSnippet('class', r'''class $0 {
    
}'''),
      CodeSnippet('if', r'''if cond {
    $0
}'''),
      CodeSnippet('for', r'''for item in items {
    $0
}'''),
      CodeSnippet('guard', r'''guard let value = optional else {
    return
}
$0'''),
    ],
    'rust': [
      CodeSnippet('fn', r'''fn $0() {
    
}'''),
      CodeSnippet('struct', r'''struct $0 {
    
}'''),
      CodeSnippet('impl', r'''impl $0 {
    
}'''),
      CodeSnippet('match', r'''match value {
    _ => $0,
}'''),
      CodeSnippet('if-let', r'''if let Some(v) = opt {
    $0
}'''),
    ],
    'sql': [
      CodeSnippet('SELECT', r'''SELECT *
FROM $0
WHERE 1 = 1;'''),
      CodeSnippet('INSERT', r'''INSERT INTO $0 (col)
VALUES (value);'''),
      CodeSnippet('UPDATE', r'''UPDATE $0
SET col = value
WHERE 1 = 1;'''),
      CodeSnippet('DELETE', r'''DELETE FROM $0
WHERE 1 = 1;'''),
      CodeSnippet('CREATE TABLE', r'''CREATE TABLE $0 (
  id INTEGER PRIMARY KEY,
  
);'''),
      CodeSnippet('JOIN', r'''SELECT *
FROM a
JOIN b ON b.a_id = a.id
WHERE $0;'''),
    ],
    'html': [
      CodeSnippet('HTML5', r'''<!DOCTYPE html>
<html lang="zh">
<head>
  <meta charset="utf-8">
  <title>$0</title>
</head>
<body>

</body>
</html>'''),
      CodeSnippet('div', r'''<div class="$0">

</div>'''),
      CodeSnippet('table', r'''<table>
  <tr>
    <th>$0</th>
  </tr>
  <tr>
    <td></td>
  </tr>
</table>'''),
      CodeSnippet('form', r'''<form action="$0" method="post">
  <input type="text" name="name">
  <button type="submit">提交</button>
</form>'''),
      CodeSnippet('a', r'''<a href="$0"></a>'''),
      CodeSnippet('script', r'''<script>
  $0
</script>'''),
    ],
    'css': [
      CodeSnippet('规则', r'''.$0 {
  
}'''),
      CodeSnippet('@media', r'''@media (max-width: 768px) {
  $0
}'''),
      CodeSnippet('flex 居中', r'''display: flex;
align-items: center;
justify-content: center;'''),
      CodeSnippet('grid', r'''display: grid;
grid-template-columns: repeat(3, 1fr);
gap: $0;'''),
      CodeSnippet('@keyframes', r'''@keyframes $0 {
  from { opacity: 0; }
  to { opacity: 1; }
}'''),
    ],
    'bash': [
      CodeSnippet('if', r'''if [ -z "$1" ]; then
  $0
fi'''),
      CodeSnippet('for', r'''for f in *; do
  $0
done'''),
      CodeSnippet('case', r'''case "$1" in
  start) $0 ;;
  *) echo "usage" ;;
esac'''),
      CodeSnippet('函数', r'''$0() {
  
}'''),
      CodeSnippet('set -e', r'''set -euo pipefail

$0'''),
    ],
  };

  /// 语言别名 → 上表的 key。
  static const Map<String, String> _alias = {
    'dart': 'dart',
    'java': 'java',
    'python': 'python',
    'kotlin': 'kotlin',
    'swift': 'swift',
    'ruby': 'ruby',
    'php': 'php',
    'rust': 'rust',
    'go': 'go',
    'golang': 'go',
    'c': 'c',
    'cpp': 'cpp',
    'c++': 'cpp',
    'objective-c': 'c',
    'objective-c++': 'cpp',
    'csharp': 'csharp',
    'c#': 'csharp',
    'javascript': 'javascript',
    'js': 'javascript',
    'typescript': 'javascript',
    'ts': 'javascript',
    'jsx': 'javascript',
    'tsx': 'javascript',
    'sql': 'sql',
    'mysql': 'sql',
    'pgsql': 'sql',
    'html': 'html',
    'xml': 'html',
    'vue': 'html',
    'css': 'css',
    'scss': 'css',
    'less': 'css',
    'bash': 'bash',
    'sh': 'bash',
    'shell': 'bash',
    'zsh': 'bash',
  };

  /// 取某个语言的片段表。找不到对应语言时给一份「通用」小表（if/for/try 三件套）。
  static List<CodeSnippet> forLanguage(String label, [String key = '']) {
    final k = key.toLowerCase();
    final l = label.toLowerCase();
    final family = _alias[k] ?? _alias[l] ?? _guessFamily(l);
    if (family != null) return _byFamily[family] ?? const [];
    return _generic;
  }

  static String? _guessFamily(String label) {
    for (final e in _byFamily.keys) {
      if (label.contains(e)) return e;
    }
    return null;
  }

  static const List<CodeSnippet> _generic = [
    CodeSnippet('if', r'''if (cond) {
  $0
}'''),
    CodeSnippet('for', r'''for (var i = 0; i < n; i++) {
  $0
}'''),
    CodeSnippet('try', r'''try {
  $0
} catch (e) {
  
}'''),
  ];

  /// 支持的语言数（设置页/提示用）。
  static int get languageCount => _byFamily.length;
}
