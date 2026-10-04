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

// 内置 JavaScript 编译器前端（词法 → 语法 → 作用域 → 压缩输出）。
//
// 目的：让「压缩代码」能安全地做死代码消除与局部变量重命名，而不是只删注释 / 空白。
// 设计原则是**保守 + 可回退**：只支持一个实用子集，遇到不支持的语法就抛
// [JsUnsupported]，由调用方退回安全压缩——绝不猜测、绝不静默改坏代码。
//
// 支持：var/let/const、函数声明 / 表达式、箭头函数、class（基础）、if/for/while/do/switch、
// return/break/continue/throw/try、数组 / 对象 / 成员 / 调用 / new、一元 / 二元 / 逻辑 /
// 赋值 / 三元 / 逗号、数字 / 字符串 / 正则 / 无插值模板字面量。
// 不支持（回退）：解构、import/export、with、生成器 yield、对象 getter/setter、
// 类字段 / 私有名、可选链、带插值的模板。
//
// 重命名只针对**全程序唯一、且没有任何自由引用**的函数内局部名，新名不与程序里任何
// 已用标识符冲突，因此既不会遮蔽，也不会把自由变量错配。

library;

/// 遇到不支持的语法时抛出，调用方应回退到安全压缩。
class JsUnsupported implements Exception {
  final String message;
  JsUnsupported(this.message);
  @override
  String toString() => 'JsUnsupported: $message';
}

/// 语法错误。
class JsSyntaxError implements Exception {
  final String message;
  JsSyntaxError(this.message);
  @override
  String toString() => 'JsSyntaxError: $message';
}

// ============================== 词法 ==============================

const Set<String> _keywords = {
  'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger', 'default',
  'delete', 'do', 'else', 'export', 'extends', 'finally', 'for', 'function',
  'if', 'import', 'in', 'instanceof', 'new', 'return', 'super', 'switch',
  'this', 'throw', 'try', 'typeof', 'var', 'void', 'while', 'with', 'yield',
  'let', 'static', 'async', 'await', 'of', 'get', 'set',
};

const Set<String> _reservedWords = {
  ..._keywords,
  'true', 'false', 'null', 'undefined', 'arguments', 'eval',
};

class Tok {
  final String type; // num,str,tpl,regex,name,kw,punct,eof
  final String value;
  final int start;
  final int end;
  final bool nlBefore;
  Tok(this.type, this.value, this.start, this.end, this.nlBefore);
  @override
  String toString() => '$type($value)';
}

class _Lexer {
  final String s;
  int i = 0;
  final List<Tok> out = [];
  bool nl = false;

  _Lexer(this.s);

  static const Set<String> _ctrlKeywords = {
    'return', 'typeof', 'instanceof', 'in', 'of', 'new', 'delete', 'void',
    'throw', 'case', 'do', 'else', 'yield', 'await',
  };

  List<Tok> run() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x0A) { nl = true; i++; continue; }
      if (c == 0x0D) { nl = true; i++; if (i < s.length && s.codeUnitAt(i) == 0x0A) i++; continue; }
      if (c == 0x20 || c == 0x09 || c == 0x0B || c == 0x0C || c == 0xA0) { i++; continue; }
      if (c == 0x2F && i + 1 < s.length) {
        final n = s.codeUnitAt(i + 1);
        if (n == 0x2F) { i += 2; while (i < s.length && s.codeUnitAt(i) != 0x0A && s.codeUnitAt(i) != 0x0D) i++; continue; }
        if (n == 0x2A) {
          i += 2;
          while (i + 1 < s.length && !(s.codeUnitAt(i) == 0x2A && s.codeUnitAt(i + 1) == 0x2F)) {
            if (s.codeUnitAt(i) == 0x0A) nl = true;
            i++;
          }
          i = (i + 1 < s.length) ? i + 2 : s.length;
          continue;
        }
      }
      final before = nl;
      final start = i;
      if (_isIdStart(c)) { _readIdent(start, before); continue; }
      if (c >= 0x30 && c <= 0x39) { _readNumber(start, before); continue; }
      if (c == 0x22 || c == 0x27) { _readString(start, before, c); continue; }
      if (c == 0x60) { _readTemplate(start, before); continue; }
      if (c == 0x2F && _regexAllowed()) { _readRegex(start, before); continue; }
      _readPunct(start, before);
    }
    out.add(Tok('eof', '', s.length, s.length, nl));
    return out;
  }

  bool _regexAllowed() {
    for (var k = out.length - 1; k >= 0; k--) {
      final t = out[k];
      if (t.type == 'punct') {
        if (t.value == ')' || t.value == ']' || t.value == '}') return false;
        return true;
      }
      if (t.type == 'num' || t.type == 'str' || t.type == 'tpl' || t.type == 'regex') return false;
      if (t.type == 'name' || t.type == 'kw') return _ctrlKeywords.contains(t.value);
      return true;
    }
    return true;
  }

  bool _isIdStart(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x24 || c == 0x5F || c > 0x7F;
  bool _isIdPart(int c) => _isIdStart(c) || (c >= 0x30 && c <= 0x39);

  void _readIdent(int start, bool before) {
    i++;
    while (i < s.length && _isIdPart(s.codeUnitAt(i))) i++;
    final v = s.substring(start, i);
    out.add(Tok(_keywords.contains(v) ? 'kw' : 'name', v, start, i, before));
    nl = false;
  }

  void _readNumber(int start, bool before) {
    i++;
    if (s.codeUnitAt(start) == 0x30 && i < s.length) {
      final n = s.codeUnitAt(i);
      if (n == 0x78 || n == 0x58 || n == 0x62 || n == 0x42 || n == 0x6F || n == 0x4F) {
        i++;
        while (i < s.length && _isIdPart(s.codeUnitAt(i))) i++;
        out.add(Tok('num', s.substring(start, i), start, i, before));
        nl = false;
        return;
      }
    }
    while (i < s.length && s.codeUnitAt(i) >= 0x30 && s.codeUnitAt(i) <= 0x39) i++;
    if (i < s.length && s.codeUnitAt(i) == 0x2E) { i++; while (i < s.length && s.codeUnitAt(i) >= 0x30 && s.codeUnitAt(i) <= 0x39) i++; }
    if (i < s.length && (s.codeUnitAt(i) == 0x65 || s.codeUnitAt(i) == 0x45)) {
      i++;
      if (i < s.length && (s.codeUnitAt(i) == 0x2B || s.codeUnitAt(i) == 0x2D)) i++;
      while (i < s.length && s.codeUnitAt(i) >= 0x30 && s.codeUnitAt(i) <= 0x39) i++;
    }
    out.add(Tok('num', s.substring(start, i), start, i, before));
    nl = false;
  }

  void _readString(int start, bool before, int q) {
    i++;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x5C) { i += 2; continue; }
      if (c == 0x0A || c == 0x0D) break;
      if (c == q) { i++; break; }
      i++;
    }
    out.add(Tok('str', s.substring(start, i), start, i, before));
    nl = false;
  }

  void _readTemplate(int start, bool before) {
    i++;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x5C) { i += 2; continue; }
      if (c == 0x60) { i++; break; }
      i++;
    }
    out.add(Tok('tpl', s.substring(start, i), start, i, before));
    nl = false;
  }

  void _readRegex(int start, bool before) {
    i++;
    var inClass = false;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x5C) { i += 2; continue; }
      if (c == 0x0A || c == 0x0D) break;
      if (c == 0x5B) inClass = true;
      else if (c == 0x5D) inClass = false;
      else if (c == 0x2F && !inClass) { i++; break; }
      i++;
    }
    while (i < s.length && _isIdPart(s.codeUnitAt(i))) i++;
    out.add(Tok('regex', s.substring(start, i), start, i, before));
    nl = false;
  }

  static const List<String> _puncts = [
    '>>>=', '...', '===', '!==', '**=', '<<=', '>>=', '>>>', '&&=', '||=', '??=',
    '=>', '==', '!=', '<=', '>=', '&&', '||', '??', '?.', '++', '--', '+=', '-=',
    '*=', '/=', '%=', '&=', '|=', '^=', '<<', '>>', '**',
    '{', '}', '(', ')', '[', ']', ';', ',', '<', '>', '+', '-', '*', '/', '%',
    '&', '|', '^', '!', '~', '?', ':', '=', '.',
  ];

  void _readPunct(int start, bool before) {
    for (final p in _puncts) {
      if (s.startsWith(p, i)) {
        i += p.length;
        out.add(Tok('punct', p, start, i, before));
        nl = false;
        return;
      }
    }
    throw JsSyntaxError('unexpected char at $i');
  }
}

// ============================== AST ==============================

abstract class N {}

class Program extends N {
  final List<N> body;
  Program(this.body);
}

class Block extends N {
  final List<N> body;
  Block(this.body);
}

class Empty extends N {}

class ExprStmt extends N {
  final N expr;
  ExprStmt(this.expr);
}

class Decl {
  final String name;
  final N? init;
  Decl(this.name, this.init);
}

class VarDecl extends N {
  final String kind;
  final List<Decl> decls;
  VarDecl(this.kind, this.decls);
}

class If extends N {
  final N test;
  final N cons;
  final N? alt;
  If(this.test, this.cons, this.alt);
}

class For extends N {
  final N? init;
  final N? test;
  final N? update;
  final N body;
  For(this.init, this.test, this.update, this.body);
}

class ForIn extends N {
  final bool isOf;
  final N left;
  final N right;
  final N body;
  ForIn(this.isOf, this.left, this.right, this.body);
}

class While extends N {
  final N test;
  final N body;
  While(this.test, this.body);
}

class DoWhile extends N {
  final N body;
  final N test;
  DoWhile(this.body, this.test);
}

class Return extends N {
  final N? arg;
  Return(this.arg);
}

class BreakContinue extends N {
  final bool isBreak;
  final String? label;
  BreakContinue(this.isBreak, this.label);
}

class Throw extends N {
  final N arg;
  Throw(this.arg);
}

class Try extends N {
  final Block block;
  final String? param;
  final Block? handler;
  final Block? finalizer;
  Try(this.block, this.param, this.handler, this.finalizer);
}

class SwitchCase {
  final N? test;
  final List<N> body;
  SwitchCase(this.test, this.body);
}

class Switch extends N {
  final N disc;
  final List<SwitchCase> cases;
  Switch(this.disc, this.cases);
}

class FuncDecl extends N {
  final String name;
  final List<String> params;
  final Block body;
  final bool isAsync;
  FuncDecl(this.name, this.params, this.body, this.isAsync);
}

class MethodDef {
  final String name;
  final bool isStatic;
  final List<String> params;
  final Block body;
  final bool isAsync;
  MethodDef(this.name, this.isStatic, this.params, this.body, this.isAsync);
}

class ClassDecl extends N {
  final String name;
  final N? superClass;
  final List<MethodDef> methods;
  ClassDecl(this.name, this.superClass, this.methods);
}

class Labeled extends N {
  final String label;
  final N body;
  Labeled(this.label, this.body);
}

class Ident extends N {
  final String name;
  Ident(this.name);
}

class Lit extends N {
  final String raw;
  Lit(this.raw);
}

class ArrayLit extends N {
  final List<N?> elements;
  ArrayLit(this.elements);
}

class Prop {
  final String? key;
  final N value;
  final bool shorthand;
  Prop(this.key, this.value, this.shorthand);
}

class ObjectLit extends N {
  final List<Prop> props;
  ObjectLit(this.props);
}

class Member extends N {
  final N obj;
  final N? prop;
  final String? name;
  Member(this.obj, this.prop, this.name);
}

class Call extends N {
  final N callee;
  final List<N> args;
  Call(this.callee, this.args);
}

class NewExpr extends N {
  final N callee;
  final List<N> args;
  NewExpr(this.callee, this.args);
}

class Unary extends N {
  final String op;
  final N arg;
  Unary(this.op, this.arg);
}

class Update extends N {
  final String op;
  final N arg;
  final bool prefix;
  Update(this.op, this.arg, this.prefix);
}

class Binary extends N {
  final String op;
  final N l;
  final N r;
  Binary(this.op, this.l, this.r);
}

class Assign extends N {
  final String op;
  final N target;
  final N value;
  Assign(this.op, this.target, this.value);
}

class Cond extends N {
  final N test;
  final N cons;
  final N alt;
  Cond(this.test, this.cons, this.alt);
}

class Seq extends N {
  final List<N> exprs;
  Seq(this.exprs);
}

class Spread extends N {
  final N arg;
  Spread(this.arg);
}

class Arrow extends N {
  final List<String> params;
  final N body;
  final bool isAsync;
  Arrow(this.params, this.body, this.isAsync);
}

class FuncExpr extends N {
  final String? name;
  final List<String> params;
  final Block body;
  final bool isAsync;
  FuncExpr(this.name, this.params, this.body, this.isAsync);
}

// ============================== 语法 ==============================

class _Parser {
  final List<Tok> t;
  int p = 0;
  _Parser(this.t);

  Tok get cur => t[p];
  Tok get next => p + 1 < t.length ? t[p + 1] : t[t.length - 1];
  bool isPunct(String v) => cur.type == 'punct' && cur.value == v;
  bool isKw(String v) => cur.type == 'kw' && cur.value == v;
  bool eatPunct(String v) { if (isPunct(v)) { p++; return true; } return false; }
  bool eatKw(String v) { if (isKw(v)) { p++; return true; } return false; }
  void expect(String v) { if (!isPunct(v)) throw JsSyntaxError('expected "$v", got $cur'); p++; }
  void expectKw(String v) { if (!isKw(v)) throw JsSyntaxError('expected "$v", got $cur'); p++; }

  Program parseProgram() {
    final body = <N>[];
    while (cur.type != 'eof') body.add(_statement());
    return Program(body);
  }

  N _statement() {
    if (isPunct('{')) return _block();
    if (isPunct(';')) { p++; return Empty(); }
    if (cur.type == 'kw') {
      switch (cur.value) {
        case 'var':
        case 'let':
        case 'const':
          final d = _varDecl();
          _semicolon();
          return d;
        case 'function':
          return _funcDecl();
        case 'class':
          return _classDecl();
        case 'if':
          return _if();
        case 'for':
          return _for();
        case 'while':
          return _while();
        case 'do':
          return _doWhile();
        case 'return':
          p++;
          final arg = (isPunct(';') || isPunct('}') || cur.type == 'eof' || cur.nlBefore) ? null : _expression();
          _semicolon();
          return Return(arg);
        case 'break':
        case 'continue':
          final b = cur.value == 'break';
          p++;
          String? label;
          if (cur.type == 'name' && !cur.nlBefore) { label = cur.value; p++; }
          _semicolon();
          return BreakContinue(b, label);
        case 'throw':
          p++;
          final a = _expression();
          _semicolon();
          return Throw(a);
        case 'try':
          return _try();
        case 'switch':
          return _switch();
        case 'import':
        case 'export':
          throw JsUnsupported('modules');
      }
      if (cur.value == 'async' && next.type == 'kw' && next.value == 'function') {
        p++;
        return _funcDecl(isAsync: true);
      }
    }
    if (cur.type == 'name' && next.type == 'punct' && next.value == ':') {
      final label = cur.value;
      p += 2;
      return Labeled(label, _statement());
    }
    final e = _expression();
    _semicolon();
    return ExprStmt(e);
  }

  void _semicolon() {
    if (eatPunct(';')) return;
    if (cur.type == 'eof' || isPunct('}') || cur.nlBefore) return;
    throw JsSyntaxError('missing semicolon, got $cur');
  }

  Block _block() {
    expect('{');
    final body = <N>[];
    while (!isPunct('}') && cur.type != 'eof') body.add(_statement());
    expect('}');
    return Block(body);
  }

  VarDecl _varDecl() {
    final kind = cur.value;
    p++;
    final decls = <Decl>[];
    while (true) {
      if (cur.type != 'name') throw JsUnsupported('destructuring');
      final name = cur.value;
      p++;
      N? init;
      if (eatPunct('=')) init = _assign();
      decls.add(Decl(name, init));
      if (!eatPunct(',')) break;
    }
    return VarDecl(kind, decls);
  }

  FuncDecl _funcDecl({bool isAsync = false}) {
    expectKw('function');
    if (isPunct('*')) throw JsUnsupported('generator');
    if (cur.type != 'name') throw JsSyntaxError('function name');
    final name = cur.value;
    p++;
    final params = _params();
    final body = _block();
    return FuncDecl(name, params, body, isAsync);
  }

  List<String> _params() {
    expect('(');
    final params = <String>[];
    while (!isPunct(')')) {
      if (isPunct('...')) throw JsUnsupported('rest parameters');
      if (isPunct('{') || isPunct('[')) throw JsUnsupported('destructuring');
      if (cur.type != 'name') throw JsSyntaxError('param name');
      params.add(cur.value);
      p++;
      if (!eatPunct(',')) break;
    }
    expect(')');
    return params;
  }

  ClassDecl _classDecl() {
    expectKw('class');
    if (cur.type != 'name') throw JsSyntaxError('class name');
    final name = cur.value;
    p++;
    N? superClass;
    if (eatKw('extends')) superClass = _lhsExpr();
    expect('{');
    final methods = <MethodDef>[];
    while (!isPunct('}') && cur.type != 'eof') {
      if (eatPunct(';')) continue;
      var isStatic = false;
      var isAsync = false;
      if (isKw('static') && !(next.type == 'punct' && next.value == '(')) { isStatic = true; p++; }
      if (isKw('async')) { isAsync = true; p++; }
      if (isKw('get') || isKw('set')) throw JsUnsupported('accessors');
      if (!(cur.type == 'name' || cur.type == 'kw')) throw JsUnsupported('class member');
      final mname = cur.value;
      p++;
      if (!isPunct('(')) throw JsUnsupported('class field');
      final params = _params();
      final body = _block();
      methods.add(MethodDef(mname, isStatic, params, body, isAsync));
    }
    expect('}');
    return ClassDecl(name, superClass, methods);
  }

  N _if() {
    expectKw('if');
    expect('(');
    final test = _expression();
    expect(')');
    final cons = _statement();
    N? alt;
    if (eatKw('else')) alt = _statement();
    return If(test, cons, alt);
  }

  N _for() {
    expectKw('for');
    expect('(');
    N? init;
    if (isPunct(';')) {
      p++;
    } else if (isKw('var') || isKw('let') || isKw('const')) {
      init = _varDecl();
      if (isKw('in') || isKw('of')) {
        final isOf = cur.value == 'of';
        p++;
        final right = _expression();
        expect(')');
        return ForIn(isOf, init, right, _statement());
      }
    } else {
      final e = _expression(noIn: true);
      if (isKw('in') || isKw('of')) {
        final isOf = cur.value == 'of';
        p++;
        final right = _expression();
        expect(')');
        return ForIn(isOf, e, right, _statement());
      }
      init = ExprStmt(e);
    }
    expect(';');
    N? test;
    if (!isPunct(';')) test = _expression();
    expect(';');
    N? update;
    if (!isPunct(')')) update = _expression();
    expect(')');
    return For(init, test, update, _statement());
  }

  N _while() {
    expectKw('while');
    expect('(');
    final test = _expression();
    expect(')');
    return While(test, _statement());
  }

  N _doWhile() {
    expectKw('do');
    final body = _statement();
    expectKw('while');
    expect('(');
    final test = _expression();
    expect(')');
    eatPunct(';');
    return DoWhile(body, test);
  }

  N _try() {
    expectKw('try');
    final block = _block();
    String? param;
    Block? handler;
    Block? finalizer;
    if (eatKw('catch')) {
      String? pname;
      if (eatPunct('(')) {
        if (cur.type == 'name') { pname = cur.value; p++; }
        expect(')');
      }
      param = pname;
      handler = _block();
    }
    if (eatKw('finally')) finalizer = _block();
    if (handler == null && finalizer == null) throw JsSyntaxError('try without catch/finally');
    return Try(block, param, handler, finalizer);
  }

  N _switch() {
    expectKw('switch');
    expect('(');
    final disc = _expression();
    expect(')');
    expect('{');
    final cases = <SwitchCase>[];
    while (!isPunct('}') && cur.type != 'eof') {
      N? test;
      if (eatKw('case')) test = _expression();
      else if (eatKw('default')) test = null;
      else throw JsSyntaxError('expected case/default');
      expect(':');
      final body = <N>[];
      while (!isPunct('}') && !isKw('case') && !isKw('default') && cur.type != 'eof') {
        body.add(_statement());
      }
      cases.add(SwitchCase(test, body));
    }
    expect('}');
    return Switch(disc, cases);
  }

  N _expression({bool noIn = false}) {
    final first = _assign(noIn: noIn);
    if (isPunct(',')) {
      final list = <N>[first];
      while (eatPunct(',')) list.add(_assign(noIn: noIn));
      return Seq(list);
    }
    return first;
  }

  static const Map<String, int> _binPrec = {
    '??': 1, '||': 2, '&&': 3,
    '|': 4, '^': 5, '&': 6,
    '==': 7, '!=': 7, '===': 7, '!==': 7,
    '<': 8, '>': 8, '<=': 8, '>=': 8, 'instanceof': 8, 'in': 8,
    '<<': 9, '>>': 9, '>>>': 9,
    '+': 10, '-': 10, '*': 11, '/': 11, '%': 11,
  };

  static const Set<String> _assignOps = {
    '=', '+=', '-=', '*=', '/=', '%=', '**=', '<<=', '>>=', '>>>=', '&=', '|=', '^=', '&&=', '||=', '??=',
  };

  N _assign({bool noIn = false}) {
    final arrow = _tryArrow();
    if (arrow != null) return arrow;
    final left = _conditional(noIn: noIn);
    if (cur.type == 'punct' && _assignOps.contains(cur.value)) {
      final op = cur.value;
      p++;
      final value = _assign(noIn: noIn);
      return Assign(op, left, value);
    }
    return left;
  }

  N? _tryArrow() {
    if (cur.type == 'name' && next.type == 'punct' && next.value == '=>') {
      final name = cur.value;
      p += 2;
      return Arrow([name], _arrowBody(), false);
    }
    if (isKw('async') && next.type == 'name' && p + 2 < t.length && t[p + 2].type == 'punct' && t[p + 2].value == '=>') {
      final name = next.value;
      p += 3;
      return Arrow([name], _arrowBody(), true);
    }
    if (isPunct('(')) {
      final save = p;
      var depth = 0;
      var k = p;
      while (k < t.length) {
        final tk = t[k];
        if (tk.type == 'punct') {
          if (tk.value == '(') depth++;
          else if (tk.value == ')') { depth--; if (depth == 0) break; }
        }
        k++;
      }
      if (k + 1 < t.length && t[k + 1].type == 'punct' && t[k + 1].value == '=>') {
        p++;
        final params = <String>[];
        while (!isPunct(')')) {
          if (isPunct('...')) throw JsUnsupported('rest parameter');
          if (isPunct('{') || isPunct('[')) throw JsUnsupported('destructuring');
          if (cur.type != 'name') { p = save; return null; }
          params.add(cur.value);
          p++;
          if (!eatPunct(',')) break;
        }
        expect(')');
        expect('=>');
        return Arrow(params, _arrowBody(), false);
      }
      p = save;
    }
    return null;
  }

  N _arrowBody() {
    if (isPunct('{')) return _block();
    return _assign();
  }

  N _conditional({bool noIn = false}) {
    final test = _binary(0, noIn: noIn);
    if (eatPunct('?')) {
      final cons = _assign();
      expect(':');
      final alt = _assign(noIn: noIn);
      return Cond(test, cons, alt);
    }
    return test;
  }

  bool _isBinOp(String v, bool noIn) {
    if (v == 'in' && noIn) return false;
    return _binPrec.containsKey(v);
  }

  N _binary(int minPrec, {bool noIn = false}) {
    var left = _unary();
    while (true) {
      String? op;
      if (cur.type == 'punct' && _isBinOp(cur.value, noIn)) op = cur.value;
      else if (cur.type == 'kw' && (cur.value == 'instanceof' || cur.value == 'in') && _isBinOp(cur.value, noIn)) op = cur.value;
      if (op == null) break;
      final prec = _binPrec[op]!;
      if (prec < minPrec) break;
      p++;
      final right = _binary(prec + 1, noIn: noIn);
      left = Binary(op, left, right);
    }
    return left;
  }

  N _unary() {
    if (cur.type == 'kw' && const {'typeof', 'void', 'delete', 'await'}.contains(cur.value)) {
      final op = cur.value;
      p++;
      return Unary(op, _unary());
    }
    if (cur.type == 'punct' && const {'!', '~', '+', '-'}.contains(cur.value)) {
      final op = cur.value;
      p++;
      return Unary(op, _unary());
    }
    if (cur.type == 'punct' && (cur.value == '++' || cur.value == '--')) {
      final op = cur.value;
      p++;
      return Update(op, _unary(), true);
    }
    return _postfix();
  }

  N _postfix() {
    var e = _lhsExpr();
    if (cur.type == 'punct' && (cur.value == '++' || cur.value == '--') && !cur.nlBefore) {
      final op = cur.value;
      p++;
      return Update(op, e, false);
    }
    return e;
  }

  N _lhsExpr() {
    N e = _newOrPrimary();
    while (true) {
      if (eatPunct('.')) {
        if (cur.type != 'name' && cur.type != 'kw') throw JsSyntaxError('member name');
        final name = cur.value;
        p++;
        e = Member(e, null, name);
      } else if (isPunct('[')) {
        p++;
        final prop = _expression();
        expect(']');
        e = Member(e, prop, null);
      } else if (isPunct('(')) {
        e = Call(e, _args());
      } else {
        break;
      }
    }
    return e;
  }

  N _newOrPrimary() {
    if (isKw('new')) {
      p++;
      final callee = _newOrPrimary();
      final args = isPunct('(') ? _args() : <N>[];
      return NewExpr(callee, args);
    }
    return _primary();
  }

  List<N> _args() {
    expect('(');
    final args = <N>[];
    while (!isPunct(')')) {
      if (isPunct('...')) { p++; args.add(Spread(_assign())); }
      else args.add(_assign());
      if (!eatPunct(',')) break;
    }
    expect(')');
    return args;
  }

  N _primary() {
    final tk = cur;
    if (tk.type == 'num' || tk.type == 'str' || tk.type == 'regex' || tk.type == 'tpl') {
      p++;
      if (tk.type == 'tpl' && tk.value.contains(r'${')) throw JsUnsupported('template interpolation');
      return Lit(tk.value);
    }
    if (tk.type == 'name') { p++; return Ident(tk.value); }
    if (tk.type == 'kw') {
      if (tk.value == 'this' || tk.value == 'super') { p++; return Ident(tk.value); }
      if (tk.value == 'true' || tk.value == 'false' || tk.value == 'null') { p++; return Lit(tk.value); }
      if (tk.value == 'function') return _funcExpr();
      if (tk.value == 'class') throw JsUnsupported('class expression');
      if (tk.value == 'async' && next.type == 'kw' && next.value == 'function') { p++; return _funcExpr(isAsync: true); }
      if (tk.value == 'new') return _newOrPrimary();
    }
    if (isPunct('(')) {
      p++;
      final e = _expression();
      expect(')');
      return e;
    }
    if (isPunct('[')) {
      p++;
      final els = <N?>[];
      while (!isPunct(']')) {
        if (isPunct(',')) { els.add(null); p++; continue; }
        if (isPunct('...')) { p++; els.add(Spread(_assign())); }
        else els.add(_assign());
        if (!eatPunct(',')) break;
      }
      expect(']');
      return ArrayLit(els);
    }
    if (isPunct('{')) return _objectLit();
    throw JsSyntaxError('unexpected token $tk');
  }

  N _funcExpr({bool isAsync = false}) {
    expectKw('function');
    String? name;
    if (cur.type == 'name') { name = cur.value; p++; }
    if (isPunct('*')) throw JsUnsupported('generator');
    final params = _params();
    final body = _block();
    return FuncExpr(name, params, body, isAsync);
  }

  N _objectLit() {
    expect('{');
    final props = <Prop>[];
    while (!isPunct('}')) {
      if (isPunct('...')) throw JsUnsupported('object spread');
      if (isPunct('[')) throw JsUnsupported('computed key');
      if (isKw('get') || isKw('set')) throw JsUnsupported('accessor');
      String? key;
      if (cur.type == 'name' || cur.type == 'kw') key = cur.value;
      else if (cur.type == 'num' || cur.type == 'str') key = cur.value;
      else throw JsSyntaxError('object key');
      p++;
      if (eatPunct(':')) {
        props.add(Prop(key, _assign(), false));
      } else {
        if (cur.type == 'name' || cur.type == 'kw') throw JsUnsupported('shorthand method');
        props.add(Prop(key, Ident(key!), true));
      }
      if (!eatPunct(',')) break;
    }
    expect('}');
    return ObjectLit(props);
  }
}

// ============================== 作用域分析 ==============================

class _Binding {
  final String name;
  int refs = 0;
  _Binding(this.name);
}

class _Scope {
  final _Scope? parent;
  final bool fn;
  final Map<String, _Binding> map = {};
  _Scope(this.parent, this.fn);

  _Binding? resolve(String n) {
    _Scope? s = this;
    while (s != null) {
      final b = s.map[n];
      if (b != null) return b;
      s = s.parent;
    }
    return null;
  }

  _Scope fnScope() {
    _Scope s = this;
    while (!s.fn && s.parent != null) s = s.parent!;
    return s;
  }

  void declare(String name) {
    map.putIfAbsent(name, () => _Binding(name));
  }
}

class _RefSite {
  final String name;
  final _Scope scope;
  _RefSite(this.name, this.scope);
}

class _Analyzer {
  final Set<String> allNames = {};
  final List<_RefSite> refs = [];
  final Map<String, List<_Scope>> declScopes = {}; // name -> scopes where declared
  final Set<String> shorthandKeys = {};
  bool danger = false;
  late _Scope program;

  void analyze(N root) {
    program = _Scope(null, false);
    _walk(root, program);
  }

  void _decl(String name, _Scope scope, {bool hoistVar = false}) {
    allNames.add(name);
    final target = hoistVar ? scope.fnScope() : scope;
    target.declare(name);
    declScopes.putIfAbsent(name, () => []).add(target);
  }

  void _ref(String name, _Scope scope) {
    allNames.add(name);
    if (name == 'arguments' || name == 'eval') danger = true;
    refs.add(_RefSite(name, scope));
  }

  void _walk(N n, _Scope s) {
    if (n is Program) { for (final x in n.body) _walk(x, s); }
    else if (n is Block) { final b = _Scope(s, false); for (final x in n.body) _walk(x, b); }
    else if (n is ExprStmt) _walk(n.expr, s);
    else if (n is VarDecl) {
      final hoist = n.kind == 'var';
      for (final d in n.decls) { _decl(d.name, s, hoistVar: hoist); if (d.init != null) _walk(d.init!, s); }
    }
    else if (n is If) { _walk(n.test, s); _walk(n.cons, s); if (n.alt != null) _walk(n.alt!, s); }
    else if (n is For) {
      final fs = _Scope(s, false);
      if (n.init != null) _walk(n.init!, fs);
      if (n.test != null) _walk(n.test!, fs);
      if (n.update != null) _walk(n.update!, fs);
      _walk(n.body, fs);
    }
    else if (n is ForIn) {
      final fs = _Scope(s, false);
      _walk(n.left, fs);
      _walk(n.right, fs);
      _walk(n.body, fs);
    }
    else if (n is While) { _walk(n.test, s); _walk(n.body, s); }
    else if (n is DoWhile) { _walk(n.body, s); _walk(n.test, s); }
    else if (n is Return) { if (n.arg != null) _walk(n.arg!, s); }
    else if (n is BreakContinue) {}
    else if (n is Throw) _walk(n.arg, s);
    else if (n is Try) {
      _walk(n.block, s);
      final cs = _Scope(s, false);
      if (n.param != null) _decl(n.param!, cs);
      if (n.handler != null) _walk(n.handler!, cs);
      if (n.finalizer != null) _walk(n.finalizer!, s);
    }
    else if (n is Switch) {
      _walk(n.disc, s);
      final cs = _Scope(s, false);
      for (final c in n.cases) { if (c.test != null) _walk(c.test!, cs); for (final st in c.body) _walk(st, cs); }
    }
    else if (n is FuncDecl) {
      _decl(n.name, s);
      final fs = _Scope(s, true);
      for (final p in n.params) _decl(p, fs);
      _walk(n.body, fs);
    }
    else if (n is FuncExpr) {
      final fs = _Scope(s, true);
      if (n.name != null) _decl(n.name!, fs);
      for (final p in n.params) _decl(p, fs);
      _walk(n.body, fs);
    }
    else if (n is Arrow) {
      final fs = _Scope(s, true);
      for (final p in n.params) _decl(p, fs);
      _walk(n.body, fs);
    }
    else if (n is ClassDecl) {
      _decl(n.name, s);
      if (n.superClass != null) _walk(n.superClass!, s);
      for (final m in n.methods) {
        final fs = _Scope(s, true);
        for (final p in m.params) _decl(p, fs);
        _walk(m.body, fs);
      }
    }
    else if (n is Labeled) _walk(n.body, s);
    else if (n is Ident) {
      if (n.name == 'this' || n.name == 'super') return;
      _ref(n.name, s);
    }
    else if (n is Lit) {}
    else if (n is ArrayLit) { for (final e in n.elements) if (e != null) _walk(e, s); }
    else if (n is ObjectLit) { for (final pr in n.props) { if (pr.key != null) { allNames.add(pr.key!); if (pr.shorthand) shorthandKeys.add(pr.key!); } _walk(pr.value, s); } }
    else if (n is Member) { _walk(n.obj, s); if (n.name != null) { allNames.add(n.name!); } if (n.prop != null) _walk(n.prop!, s); }
    else if (n is Call) { _walk(n.callee, s); for (final a in n.args) _walk(a, s); }
    else if (n is NewExpr) { _walk(n.callee, s); for (final a in n.args) _walk(a, s); }
    else if (n is Unary) _walk(n.arg, s);
    else if (n is Update) _walk(n.arg, s);
    else if (n is Binary) { _walk(n.l, s); _walk(n.r, s); }
    else if (n is Assign) { _walk(n.target, s); _walk(n.value, s); }
    else if (n is Cond) { _walk(n.test, s); _walk(n.cons, s); _walk(n.alt, s); }
    else if (n is Seq) { for (final e in n.exprs) _walk(e, s); }
    else if (n is Spread) _walk(n.arg, s);
    else if (n is Empty) {}
  }

  /// 计算可重命名集合：全程序唯一声明、且无自由引用、且不在程序顶层。
  Map<String, String> buildRenameMap() {
    final map = <String, String>{};
    if (danger) return map;

    // 自由引用：解析不到绑定的引用
    final freeNames = <String>{};
    for (final r in refs) {
      if (r.scope.resolve(r.name) == null) freeNames.add(r.name);
    }

    final reserved = <String>{...allNames, ..._reservedWords};
    var idx = 0;
    for (final name in allNames) {
      if (_reservedWords.contains(name)) continue;
      if (shorthandKeys.contains(name)) continue;
      if (freeNames.contains(name)) continue;
      final scopes = declScopes[name];
      if (scopes == null || scopes.length != 1) continue; // 必须唯一声明
      if (scopes.first.parent == null) continue; // 不在程序顶层
      var cand = _nameFor(idx);
      idx++;
      while (reserved.contains(cand)) { cand = _nameFor(idx); idx++; }
      reserved.add(cand);
      map[name] = cand;
    }
    return map;
  }

  static String _nameFor(int i) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final base = chars.length;
    var n = i;
    final sb = StringBuffer();
    while (true) {
      sb.write(chars[n % base]);
      n = n ~/ base - 1;
      if (n < 0) break;
    }
    return sb.toString();
  }
}

// ============================== 输出 ==============================

class _Printer {
  final Map<String, String> rename;
  final StringBuffer b = StringBuffer();
  _Printer(this.rename);

  String id(String name) => rename[name] ?? name;

  void write(String s) {
    if (s.isEmpty) return;
    if (b.isNotEmpty) {
      final last = b.toString().codeUnitAt(b.length - 1);
      final f = s.codeUnitAt(0);
      if (_wordLast(last) && _wordLast(f)) {
        b.write(' ');
      } else if ((last == 0x2B || last == 0x2D) && (f == 0x2B || f == 0x2D)) {
        b.write(' ');
      }
    }
    b.write(s);
  }

  static bool _wordLast(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) || c == 0x24 || c == 0x5F || c > 0x7F;

  void program(N n) {
    if (n is Program) { for (final s in n.body) stmt(s); } else { stmt(n); }
  }


  void _sub(N c) {
    if (c is Arrow || c is FuncExpr || c is ObjectLit) {
      write('('); _single(c, false); write(')');
    } else {
      _single(c, false);
    }
  }

  void _blockBody(List<N> body) {
    write('{');
    for (final s in body) stmt(s);
    write('}');
  }

  void stmt(N n) {
    if (n is Empty) return;
    if (n is Block) { _blockBody(n.body); return; }
    if (n is ExprStmt) { _single(n.expr, false); write(';'); return; }
    if (n is VarDecl) { _decl(n); write(';'); return; }
    if (n is If) {
      write('if('); _single(n.test, false); write(')');
      _nested(n.cons);
      if (n.alt != null) { write('else'); _nested(n.alt!); }
      return;
    }
    if (n is For) {
      write('for(');
      if (n.init != null) {
        if (n.init is VarDecl) _decl(n.init as VarDecl);
        else _single((n.init as ExprStmt).expr, false);
      }
      write(';');
      if (n.test != null) _single(n.test!, false);
      write(';');
      if (n.update != null) _single(n.update!, false);
      write(')');
      _nested(n.body);
      return;
    }
    if (n is ForIn) {
      write('for(');
      if (n.left is VarDecl) _decl(n.left as VarDecl);
      else _single(n.left, false);
      write(n.isOf ? ' of ' : ' in ');
      _single(n.right, false);
      write(')');
      _nested(n.body);
      return;
    }
    if (n is While) { write('while('); _single(n.test, false); write(')'); _nested(n.body); return; }
    if (n is DoWhile) { write('do'); _nested(n.body); write('while('); _single(n.test, false); write(')'); write(';'); return; }
    if (n is Return) { write('return'); if (n.arg != null) _single(n.arg!, false); write(';'); return; }
    if (n is BreakContinue) { write(n.isBreak ? 'break' : 'continue'); if (n.label != null) { write(' '); write(n.label!); } write(';'); return; }
    if (n is Throw) { write('throw'); _sub(n.arg); write(';'); return; }
    if (n is Try) {
      write('try'); _blockBody(n.block.body);
      if (n.handler != null) { write('catch'); if (n.param != null) { write('('); write(id(n.param!)); write(')'); } _blockBody(n.handler!.body); }
      if (n.finalizer != null) { write('finally'); _blockBody(n.finalizer!.body); }
      return;
    }
    if (n is Switch) {
      write('switch('); _single(n.disc, false); write('){');
      for (final c in n.cases) {
        if (c.test == null) write('default:'); else { write('case '); _single(c.test!, false); write(':'); }
        for (final st in c.body) stmt(st);
      }
      write('}');
      return;
    }
    if (n is FuncDecl) { write(n.isAsync ? 'async function ' : 'function '); write(id(n.name)); _params(n.params); _blockBody(n.body.body); return; }
    if (n is ClassDecl) {
      write('class '); write(id(n.name));
      if (n.superClass != null) { write(' extends '); _single(n.superClass!, false); }
      write('{');
      for (final m in n.methods) {
        if (m.isStatic) write('static ');
        if (m.isAsync) write('async ');
        write(m.name);
        _params(m.params);
        _blockBody(m.body.body);
      }
      write('}');
      return;
    }
    if (n is Labeled) { write(n.label); write(':'); stmt(n.body); return; }
    _single(n, false); write(';');
  }

  void _nested(N n) {
    if (n is Block) { _blockBody(n.body); } else { stmt(n); }
  }

  void _decl(VarDecl d) {
    write(d.kind);
    write(' ');
    for (var k = 0; k < d.decls.length; k++) {
      if (k > 0) write(',');
      write(id(d.decls[k].name));
      if (d.decls[k].init != null) { write('='); _single(d.decls[k].init!, false); }
    }
  }

  void _params(List<String> ps) {
    write('(');
    for (var k = 0; k < ps.length; k++) { if (k > 0) write(','); write(id(ps[k])); }
    write(')');
  }

  static const Map<String, int> _prec = {
    '??': 1, '||': 2, '&&': 3, '|': 4, '^': 5, '&': 6,
    '==': 7, '!=': 7, '===': 7, '!==': 7,
    '<': 8, '>': 8, '<=': 8, '>=': 8, 'instanceof': 8, 'in': 8,
    '<<': 9, '>>': 9, '>>>': 9, '+': 10, '-': 10, '*': 11, '/': 11, '%': 11,
  };

  int _precOf(N n) {
    if (n is Binary) return _prec[n.op] ?? 99;
    if (n is Assign) return 0;
    if (n is Cond) return 0;
    if (n is Seq) return -1;
    return 99;
  }

  void _wrapChild(N n, int parentPrec, bool isRight) {
    final myPrec = _precOf(n);
    final need = myPrec < parentPrec || (isRight && myPrec == parentPrec && myPrec < 99) || n is Arrow || n is FuncExpr || n is ObjectLit;
    if (need) write('(');
    _single(n, false);
    if (need) write(')');
  }

  void _single(N n, bool _) {
    if (n is Ident) { write(id(n.name)); return; }
    if (n is Lit) { write(n.raw); return; }
    if (n is ArrayLit) {
      write('[');
      for (var k = 0; k < n.elements.length; k++) {
        if (k > 0) write(',');
        final e = n.elements[k];
        if (e != null) _single(e, false);
      }
      write(']');
      return;
    }
    if (n is ObjectLit) {
      write('{');
      for (var k = 0; k < n.props.length; k++) {
        if (k > 0) write(',');
        final pr = n.props[k];
        if (pr.shorthand) {
          write(id(pr.key!));
        } else {
          write(pr.key!);
          write(':');
          _single(pr.value, false);
        }
      }
      write('}');
      return;
    }
    if (n is Member) {
      _sub(n.obj);
      if (n.name != null) { write('.'); write(n.name!); }
      else { write('['); _single(n.prop!, false); write(']'); }
      return;
    }
    if (n is Call) {
      _sub(n.callee);
      write('(');
      for (var k = 0; k < n.args.length; k++) { if (k > 0) write(','); _single(n.args[k], false); }
      write(')');
      return;
    }
    if (n is NewExpr) {
      write('new');
      _sub(n.callee);
      write('(');
      for (var k = 0; k < n.args.length; k++) { if (k > 0) write(','); _single(n.args[k], false); }
      write(')');
      return;
    }
    if (n is Unary) {
      write(n.op);
      if ((n.op == 'typeof' || n.op == 'void' || n.op == 'delete' || n.op == 'await')) write(' ');
      _sub(n.arg);
      return;
    }
    if (n is Update) { if (n.prefix) { write(n.op); _sub(n.arg); } else { _sub(n.arg); write(n.op); } return; }
    if (n is Binary) {
      final my = _prec[n.op] ?? 0;
      _wrapChild(n.l, my, false);
      write(n.op == 'in' || n.op == 'instanceof' ? ' ${n.op} ' : n.op);
      _wrapChild(n.r, my, true);
      return;
    }
    if (n is Assign) { _single(n.target, false); write(n.op); _single(n.value, false); return; }
    if (n is Cond) { _single(n.test, false); write('?'); _single(n.cons, false); write(':'); _single(n.alt, false); return; }
    if (n is Seq) { write('('); for (var k = 0; k < n.exprs.length; k++) { if (k > 0) write(','); _single(n.exprs[k], false); } write(')'); return; }
    if (n is Spread) { write('...'); _sub(n.arg); return; }
    if (n is Arrow) {
      if (n.isAsync) write('async ');
      if (n.params.length == 1 && !n.isAsync) { write(id(n.params[0])); } else { _params(n.params); }
      write('=>');
      if (n.body is Block) { _blockBody((n.body as Block).body); } else { _single(n.body, false); }
      return;
    }
    if (n is FuncExpr) {
      write(n.isAsync ? 'async function' : 'function');
      if (n.name != null) { write(' '); write(id(n.name!)); }
      else write(' ');
      _params(n.params);
      _blockBody(n.body.body);
      return;
    }
    write('0');
  }
}

// ============================== 死代码消除 ==============================

N _dce(N n) {
  if (n is Block) return Block(_dceList(n.body));
  if (n is Program) return Program(_dceList(n.body));
  if (n is If) {
    final test = _dce(n.test);
    if (test is Lit) {
      if (test.raw == 'true') return _dce(n.cons);
      if (test.raw == 'false') return n.alt == null ? Empty() : _dce(n.alt!);
    }
    return If(test, _dce(n.cons), n.alt == null ? null : _dce(n.alt!));
  }
  if (n is While) {
    final test = _dce(n.test);
    if (test is Lit && test.raw == 'false') return Empty();
    return While(test, _dce(n.body));
  }
  if (n is For) return For(n.init, n.test, n.update, _dce(n.body));
  if (n is ForIn) return ForIn(n.isOf, n.left, n.right, _dce(n.body));
  if (n is DoWhile) return DoWhile(_dce(n.body), n.test);
  if (n is FuncDecl) return FuncDecl(n.name, n.params, Block(_dceList(n.body.body)), n.isAsync);
  if (n is FuncExpr) return FuncExpr(n.name, n.params, Block(_dceList(n.body.body)), n.isAsync);
  if (n is Arrow) return Arrow(n.params, n.body is Block ? Block(_dceList((n.body as Block).body)) : n.body, n.isAsync);
  if (n is Try) {
    return Try(
      Block(_dceList(n.block.body)),
      n.param,
      n.handler == null ? null : Block(_dceList(n.handler!.body)),
      n.finalizer == null ? null : Block(_dceList(n.finalizer!.body)),
    );
  }
  if (n is Switch) return Switch(n.disc, n.cases.map((c) => SwitchCase(c.test, _dceList(c.body))).toList());
  if (n is Labeled) return Labeled(n.label, _dce(n.body));
  if (n is ExprStmt) return ExprStmt(_dce(n.expr));
  if (n is ArrayLit) return ArrayLit(n.elements.map((e) => e == null ? null : _dce(e)).toList());
  if (n is ObjectLit) return ObjectLit(n.props.map((p) => Prop(p.key, _dce(p.value), p.shorthand)).toList());
  if (n is Member) return Member(_dce(n.obj), n.prop == null ? null : _dce(n.prop!), n.name);
  if (n is Call) return Call(_dce(n.callee), n.args.map(_dce).toList());
  if (n is NewExpr) return NewExpr(_dce(n.callee), n.args.map(_dce).toList());
  if (n is Unary) return Unary(n.op, _dce(n.arg));
  if (n is Update) return Update(n.op, _dce(n.arg), n.prefix);
  if (n is Binary) return Binary(n.op, _dce(n.l), _dce(n.r));
  if (n is Assign) return Assign(n.op, _dce(n.target), _dce(n.value));
  if (n is Cond) return Cond(_dce(n.test), _dce(n.cons), _dce(n.alt));
  if (n is Seq) return Seq(n.exprs.map(_dce).toList());
  if (n is Spread) return Spread(_dce(n.arg));
  return n;
}

List<N> _dceList(List<N> body) {
  final out = <N>[];
  var done = false;
  for (final s in body) {
    if (done) break;
    final d = _dce(s);
    if (d is Empty) continue;
    out.add(d);
    if (_terminates(d)) done = true;
  }
  return out;
}

bool _terminates(N n) {
  if (n is Return || n is Throw || n is BreakContinue) return true;
  if (n is Block) return n.body.isNotEmpty && _terminates(n.body.last);
  if (n is If) {
    if (n.alt == null) return false;
    return _terminates(n.cons) && _terminates(n.alt!);
  }
  return false;
}

// ============================== 公开 API ==============================

class JsCompiler {
  JsCompiler._();

  /// 只做语法校验：成功返回 null，失败返回错误信息。
  static String? check(String src) {
    try {
      _Parser(_Lexer(src).run()).parseProgram();
      return null;
    } on JsSyntaxError catch (e) {
      return e.message;
    } on JsUnsupported catch (e) {
      return 'unsupported: ${e.message}';
    }
  }

  /// 激进压缩：DCE + 局部变量重命名。解析失败 / 遇到不支持语法时返回 null。
  static String? minify(String src, {bool rename = true}) {
    try {
      final tree = _Parser(_Lexer(src).run()).parseProgram();
      final reduced = _dce(tree) as Program;
      Map<String, String> map = {};
      if (rename) {
        final a = _Analyzer();
        a.analyze(reduced);
        map = a.buildRenameMap();
      }
      final pr = _Printer(map);
      pr.program(reduced);
      return pr.b.toString();
    } on JsSyntaxError {
      return null;
    } on JsUnsupported {
      return null;
    }
  }
}
