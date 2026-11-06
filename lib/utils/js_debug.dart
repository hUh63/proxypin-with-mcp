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

// JavaScript 的行级调试支持（纯 Dart，可单测）。
//
// 内置的 QuickJS 没有调试协议，拿不到真正的「暂停/单步」。这里用**行级插桩**做等价物：
// 在每一处「确定是语句开头」的行首插入 `__ppProbe(N);`，探针命中用户设的断点时
// 抛一个可识别的异常，宿主侧捕获后就知道停在第几行 —— 全局变量还留在引擎里，
// 可以直接读出来给人看。
//
// 三条纪律（都是踩出来的）：
//   1. **只插确定安全的位置**：行首必须是语句起点，且当前不在「对象字面量 / 类体 /
//      函数参数列表」里面 —— 否则会插出 `{ a: 1, __ppProbe(3); b: 2 }` 这种语法错。
//   2. **插完必须校验**：宿主侧会先用 `new Function(src)` 试解析一遍，不通过就退回
//      不插桩的整篇运行。宁可少断点，也不能让用户的脚本变成 SyntaxError。
//   3. 「继续」是**重跑**：JS 引擎没法从异常点恢复，所以继续时把已命中的那处断点
//      记成「跳过 n 次」，重新从头执行到下一个断点。副作用会重复，UI 上要说明。
import 'dart:convert';

/// 一个 `test('名字', fn)` / `it('名字', fn)` 用例。
class JsTestCase {
  final String name;
  final int line;

  const JsTestCase(this.name, this.line);
}

class JsDebug {
  /// 探针函数名。
  static const String probe = '__ppProbe';

  /// 断点命中的异常前缀。
  static const String breakTag = '__PP_BREAK__:';

  /// 调试预置：断点表、命中计数、需要跳过的次数、探针函数。
  ///
  /// `skip` 是「这一行前 n 次命中不要停」——「继续」就是把它加一。
  static String prelude(Set<int> breakpoints) {
    final bp = <String, int>{};
    for (final line in breakpoints) {
      bp['$line'] = 1;
    }
    return 'globalThis.__ppBp = ${jsonEncode(bp)};\n'
        'globalThis.__ppHits = globalThis.__ppHits || {};\n'
        'globalThis.__ppSkip = globalThis.__ppSkip || {};\n'
        'globalThis.$probe = function (line) {\n'
        '  if (!globalThis.__ppBp[line]) return;\n'
        '  globalThis.__ppHits[line] = (globalThis.__ppHits[line] || 0) + 1;\n'
        '  var skip = globalThis.__ppSkip[line] || 0;\n'
        '  if (globalThis.__ppHits[line] > skip) {\n'
        "    throw '$breakTag' + line;\n"
        '  }\n'
        '};\n';
  }

  /// 极简测试骨架：`test/it/describe/expect` 都装到全局，跑完能取回结果。
  ///
  /// 只做「够用的断言」——真正的 Jest 装不进来（要打包几百 KB），而编辑器里
  /// 想跑的就是「写个用例验证一段逻辑」，toBe / toEqual / toBeTruthy / toContain
  /// 已经覆盖绝大多数。
  static const String testHarness = r"""
globalThis.__ppCases = [];
globalThis.__ppShow = function (v) {
  try {
    if (typeof v === 'string') return JSON.stringify(v);
    var s = JSON.stringify(v);
    return s === undefined ? String(v) : s;
  } catch (e) { return String(v); }
};
globalThis.__ppTest = function (name, fn) {
  globalThis.__ppCases.push([String(name), fn]);
};
globalThis.test = globalThis.__ppTest;
globalThis.it = globalThis.__ppTest;
globalThis.describe = function (name, fn) { if (typeof fn === 'function') fn(); };
globalThis.expect = function (a) {
  function fail(msg) { throw new Error(msg); }
  var api = {
    toBe: function (b) { if (a !== b) fail('expect(' + __ppShow(a) + ').toBe(' + __ppShow(b) + ')'); },
    toEqual: function (b) {
      var x = JSON.stringify(a), y = JSON.stringify(b);
      if (x !== y) fail('expect(' + __ppShow(a) + ').toEqual(' + __ppShow(b) + ')');
    },
    toBeTruthy: function () { if (!a) fail('expect(' + __ppShow(a) + ').toBeTruthy()'); },
    toBeFalsy: function () { if (a) fail('expect(' + __ppShow(a) + ').toBeFalsy()'); },
    toContain: function (b) { if (String(a).indexOf(b) < 0) fail('expect(' + __ppShow(a) + ').toContain(' + __ppShow(b) + ')'); },
    toBeGreaterThan: function (b) { if (!(a > b)) fail('expect(' + __ppShow(a) + ').toBeGreaterThan(' + __ppShow(b) + ')'); },
    toBeLessThan: function (b) { if (!(a < b)) fail('expect(' + __ppShow(a) + ').toBeLessThan(' + __ppShow(b) + ')'); },
    toBeNull: function () { if (a !== null) fail('expect(' + __ppShow(a) + ').toBeNull()'); },
    toBeUndefined: function () { if (a !== undefined) fail('expect(' + __ppShow(a) + ').toBeUndefined()'); }
  };
  api.not = {
    toBe: function (b) { if (a === b) fail('expect(' + __ppShow(a) + ').not.toBe(' + __ppShow(b) + ')'); },
    toEqual: function (b) {
      var x = JSON.stringify(a), y = JSON.stringify(b);
      if (x === y) fail('expect(' + __ppShow(a) + ').not.toEqual(' + __ppShow(b) + ')');
    }
  };
  return api;
};
globalThis.__ppRunCases = function () {
  var out = [];
  for (var i = 0; i < globalThis.__ppCases.length; i++) {
    var c = globalThis.__ppCases[i];
    var ok = true, msg = '';
    try { c[1](); } catch (e) { ok = false; msg = (e && e.message) ? String(e.message) : String(e); }
    out.push([c[0], ok, msg]);
  }
  return JSON.stringify(out);
};
""";

  /// 在安全位置的行首插入探针。
  ///
  /// 返回插桩后的源码；一行都插不进去时原样返回（调用方据此提示「无法插桩」）。
  static String instrument(String src) {
    final lines = src.split('\n');
    final out = <String>[];
    // 花括号栈：true = 块（可以插），false = 对象字面量 / 类体 / 参数（不能插）。
    final blocks = <bool>[];
    // 上一行是否「语句可以结束」——只有能结束时，下一行才可能是新的语句。
    var prevEnds = true;
    var inserted = 0;

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final line = raw.trimRight();
      final t = line.trimLeft();

      // 只看最内层：类体/对象字面量这一层不能插，但它的方法体是下一层，可以插。
      final safe = prevEnds && _isStatementStart(t) && (blocks.isEmpty || blocks.last);
      if (safe) {
        final indent = line.substring(0, line.length - t.length);
        out.add('$indent$probe(${i + 1});');
        inserted++;
      }
      out.add(raw);

      _trackBlocks(line, blocks);
      prevEnds = _endsStatement(_stripLineComment(line));
    }
    return inserted == 0 ? src : out.join('\n');
  }

  /// 从引擎的错误信息里取出断点行号（1-based）。
  static int? breakLineFrom(String? message) {
    if (message == null) return null;
    final at = message.indexOf(breakTag);
    if (at < 0) return null;
    final rest = message.substring(at + breakTag.length);
    final m = RegExp(r'^\d+').firstMatch(rest);
    return m == null ? null : int.tryParse(m.group(0)!);
  }

  /// 扫出 `test('名字', ...)` / `it('名字', ...)` 用例（单引号 / 双引号 / 反引号）。
  static List<JsTestCase> collectTests(String src) {
    // 名字引号用捕获组，结尾再反向引用一次，保证 `test("a')` 这种不会被当成用例。
    final re = RegExp('(?:test|it)\\s*\\(\\s*([\'"`])((?:\\\\.|(?!\\1).)*)\\1');
    final out = <JsTestCase>[];
    for (final m in re.allMatches(src)) {
      // 前一个字符是 `.` 或标识符字符 → 是 obj.test(...) / mytest(...)，不是用例。
      if (m.start > 0) {
        final prev = src[m.start - 1];
        if (prev == '.' || RegExp(r'[A-Za-z0-9_$]').hasMatch(prev)) continue;
      }
      final name = m.group(2) ?? '';
      if (name.isEmpty) continue;
      final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
      out.add(JsTestCase(name, line));
    }
    return out;
  }

  // ── 内部：行分类 ────────────────────────────────────────────────

  static bool _isStatementStart(String t) {
    if (t.isEmpty) return false;
    // 注释行永远不插（注释里插入代码会变成语法错）。
    if (t.startsWith('//') || t.startsWith('/*') || t.startsWith('*')) return false;
    // 续行 / 块的分隔符：这些开头的行不是语句起点。
    for (final w in const ['else', 'catch', 'finally', 'case ', 'default:']) {
      if (t.startsWith(w)) return false;
    }
    const lead = ')]}.,?:=><&|+-*/%!~^';
    final c = t[0];
    if (lead.contains(c)) return false;
    // 语句起点：标识符 / 字面量 / 分组 / 数组 / 对象 / 一元操作符。
    return RegExp(r'''^[A-Za-z_$(\[{'"`0-9]''').hasMatch(t);
  }

  static bool _endsStatement(String line) {
    final s = line.trimRight();
    if (s.isEmpty) return true;
    // `outer:` 这类标签行后面紧跟着的必须是它标注的那条语句；
    // 中间插一条探针，`break outer` 就找不到标签了（SyntaxError）。
    if (RegExp(r'^[A-Za-z_$][\w$]*:$').hasMatch(s)) return false;
    final last = s[s.length - 1];
    if (last == ';' || last == '{' || last == '}' || last == ':') return true;
    // `if (x)` / `foo(a)` 结尾：块头或完整表达式，都可以从下一行开始插。
    if (last == ')') return true;
    // 这些结尾说明语句还没写完。
    if (last == ',' || last == '(' || last == '[' || last == '=' || last == '>') {
      return false;
    }
    if (s.endsWith('&&') || s.endsWith('||') || s.endsWith('+') || s.endsWith('-')) {
      return false;
    }
    return false;
  }

  /// 维护花括号栈：判断 `{` 是「块」还是「对象字面量 / 类体」。
  static void _trackBlocks(String line, List<bool> blocks) {
    final s = _stripLineComment(line);
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '{') {
        blocks.add(_isBlockOpen(s.substring(0, i)));
      } else if (c == '}' && blocks.isNotEmpty) {
        blocks.removeLast();
      }
    }
  }

  /// `{` 前面那段文本决定它是块还是对象字面量。
  static bool _isBlockOpen(String prefix) {
    final p = prefix.trimRight();
    if (p.isEmpty) return true;
    if (p.endsWith('=>')) return true;
    if (p.endsWith('return') || p.endsWith('typeof') || p.endsWith('yield')) return false;
    // 类体里只能写方法和字段，插一条语句就是语法错。
    if (RegExp(r'\bclass\b').hasMatch(p)) return false;
    final last = p[p.length - 1];
    // 这些符号后面跟的 `{` 是「值」（对象字面量 / 解构 / 箭头函数返回对象）。
    if ('=([,:?&|+-*/%!<>'.contains(last)) return false;
    return true;
  }

  /// 去掉行尾注释（粗略，够用：不处理字符串里出现 `//` 的情况）。
  static String _stripLineComment(String line) {
    var inS = '';
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inS.isNotEmpty) {
        if (c == '\\') {
          i++;
        } else if (c == inS) {
          inS = '';
        }
        continue;
      }
      if (c == '"' || c == "'" || c == '`') {
        inS = c;
        continue;
      }
      if (c == '/' && i + 1 < line.length && line[i + 1] == '/') {
        return line.substring(0, i);
      }
    }
    return line;
  }
}
