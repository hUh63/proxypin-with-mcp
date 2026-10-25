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

// 通用表达式求值器（纯 Dart，零依赖）。
//
// 为什么需要它：手机上只有 JS 引擎，C#/Java/Python 这些语言没有本地运行时。
// 但「控制台」不该只对 JS 可用——算个数、验算式、试字符串操作是跨语言的需求，
// 所以这里给一个**语言无关**的表达式后端：所有语言的编辑器都能用它算东西。
//
// 支持：整数/小数/0x/0b/科学计数、单双引号字符串、true/false/null、
// 一元 + - !、算术 + - * / % **、比较 == != < <= > >=、逻辑 && || 、位运算 & | ^ << >>、
// 三元 ? :、括号、函数调用（abs/min/max/round/floor/ceil/sqrt/pow/len/hex/bin/upper/lower/trim/int/float/str）。
// 不支持的语法一律返回可读错误，绝不静默给错结果。
library;

import 'dart:math' as math;

/// 求值结果。
class ExprResult {
  final Object? value;
  final String? error;

  const ExprResult._(this.value, this.error);

  const ExprResult.ok(Object? value) : this._(value, null);

  const ExprResult.fail(String message) : this._(null, message);

  bool get isError => error != null;

  @override
  String toString() => isError ? 'error: $error' : '${ExprEval.format(value)}';
}

/// 表达式求值。
class ExprEval {
  /// 求值一个表达式（无变量）。
  static ExprResult evaluate(String source) => evaluateWith(source, const <String, Object?>{});

  /// 求值一个表达式，可带变量表（[ExprSession] 用）。
  static ExprResult evaluateWith(String source, Map<String, Object?> variables) {
    final text = source.trim();
    if (text.isEmpty) return const ExprResult.fail('empty expression');
    try {
      final parser = _Parser(_tokenize(text), variables);
      final value = parser.parseExpression(0);
      if (!parser.atEnd) {
        return ExprResult.fail('unexpected "${parser.current.lexeme}" at ${parser.current.pos}');
      }
      return ExprResult.ok(value);
    } on _ExprError catch (e) {
      return ExprResult.fail(e.message);
    } catch (e) {
      return ExprResult.fail('$e');
    }
  }

  /// 把结果格式化成控制台里显示的样子。
  static String format(Object? value) {
    if (value == null) return 'null';
    if (value is String) return "'$value'";
    if (value is bool) return '$value';
    if (value is int) return '$value';
    if (value is double) {
      if (value.isNaN) return 'NaN';
      if (value.isInfinite) return value > 0 ? 'Infinity' : '-Infinity';
      if (value == value.roundToDouble() && value.abs() < 1e16) return '${value.toInt()}';
      return '$value';
    }
    return '$value';
  }
}

class _ExprError implements Exception {
  final String message;
  const _ExprError(this.message);
}

// ============================== 词法 ==============================

enum _T { num, str, ident, op, lparen, rparen, comma, eof }

class _Tok {
  final _T type;
  final String lexeme;
  final Object? value;
  final int pos;
  const _Tok(this.type, this.lexeme, this.pos, [this.value]);
}

const List<String> _operators = <String>[
  '**', '==', '!=', '<=', '>=', '&&', '||', '<<', '>>', //
  '+', '-', '*', '/', '%', '<', '>', '!', '&', '|', '^', '?', ':',
];

List<_Tok> _tokenize(String src) {
  final out = <_Tok>[];
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      i++;
      continue;
    }
    // 数字
    if (_isDigit(c) || (c == '.' && i + 1 < src.length && _isDigit(src[i + 1]))) {
      final start = i;
      if (c == '0' && i + 1 < src.length && (src[i + 1] == 'x' || src[i + 1] == 'X')) {
        i += 2;
        final hs = i;
        while (i < src.length && _isHex(src[i])) {
          i++;
        }
        if (i == hs) throw _ExprError('bad hex literal at $start');
        out.add(_Tok(_T.num, src.substring(start, i), start, int.parse(src.substring(hs, i), radix: 16)));
        continue;
      }
      if (c == '0' && i + 1 < src.length && (src[i + 1] == 'b' || src[i + 1] == 'B')) {
        i += 2;
        final bs = i;
        while (i < src.length && (src[i] == '0' || src[i] == '1')) {
          i++;
        }
        if (i == bs) throw _ExprError('bad binary literal at $start');
        out.add(_Tok(_T.num, src.substring(start, i), start, int.parse(src.substring(bs, i), radix: 2)));
        continue;
      }
      while (i < src.length && _isDigit(src[i])) {
        i++;
      }
      if (i < src.length && src[i] == '.') {
        i++;
        while (i < src.length && _isDigit(src[i])) {
          i++;
        }
      }
      if (i < src.length && (src[i] == 'e' || src[i] == 'E')) {
        final mark = i;
        i++;
        if (i < src.length && (src[i] == '+' || src[i] == '-')) i++;
        if (i < src.length && _isDigit(src[i])) {
          while (i < src.length && _isDigit(src[i])) {
            i++;
          }
        } else {
          i = mark;
        }
      }
      final raw = src.substring(start, i);
      final parsed = raw.contains('.') || raw.contains('e') || raw.contains('E')
          ? double.tryParse(raw)
          : int.tryParse(raw);
      if (parsed == null) throw _ExprError('bad number "$raw"');
      out.add(_Tok(_T.num, raw, start, parsed));
      continue;
    }
    // 字符串
    if (c == '"' || c == "'") {
      final start = i;
      final quote = c;
      i++;
      final buf = StringBuffer();
      var closed = false;
      while (i < src.length) {
        final ch = src[i];
        if (ch == '\\') {
          if (i + 1 >= src.length) break;
          final next = src[i + 1];
          switch (next) {
            case 'n':
              buf.write('\n');
            case 't':
              buf.write('\t');
            case 'r':
              buf.write('\r');
            case '\\':
              buf.write('\\');
            default:
              // \" 与 \' 等都按「字面字符」处理
              buf.write(next);
          }
          i += 2;
          continue;
        }
        if (ch == quote) {
          i++;
          closed = true;
          break;
        }
        buf.write(ch);
        i++;
      }
      if (!closed) throw _ExprError('unterminated string at $start');
      out.add(_Tok(_T.str, src.substring(start, i), start, buf.toString()));
      continue;
    }
    // 标识符
    if (_isIdentStart(c)) {
      final start = i;
      i++;
      while (i < src.length && _isIdentPart(src[i])) {
        i++;
      }
      final word = src.substring(start, i);
      out.add(_Tok(_T.ident, word, start, word));
      continue;
    }
    if (c == '(') {
      out.add(_Tok(_T.lparen, c, i));
      i++;
      continue;
    }
    if (c == ')') {
      out.add(_Tok(_T.rparen, c, i));
      i++;
      continue;
    }
    if (c == ',') {
      out.add(_Tok(_T.comma, c, i));
      i++;
      continue;
    }
    String? matched;
    for (final op in _operators) {
      if (src.startsWith(op, i)) {
        matched = op;
        break;
      }
    }
    if (matched == null) throw _ExprError('unexpected character "$c" at $i');
    out.add(_Tok(_T.op, matched, i));
    i += matched.length;
  }
  out.add(_Tok(_T.eof, '', src.length));
  return out;
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

bool _isHex(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 0x30 && u <= 0x39) || (u >= 0x61 && u <= 0x66) || (u >= 0x41 && u <= 0x46);
}

bool _isIdentStart(String c) {
  final u = c.codeUnitAt(0);
  return u == 0x5f || (u >= 0x41 && u <= 0x5a) || (u >= 0x61 && u <= 0x7a) || u > 0x7f;
}

bool _isIdentPart(String c) => _isIdentStart(c) || _isDigit(c);

// ============================== 语法 + 求值 ==============================

const Map<String, int> _precedence = <String, int>{
  '||': 1,
  '&&': 2,
  '|': 3,
  '^': 4,
  '&': 5,
  '==': 6,
  '!=': 6,
  '<': 7,
  '>': 7,
  '<=': 7,
  '>=': 7,
  '<<': 8,
  '>>': 8,
  '+': 9,
  '-': 9,
  '*': 10,
  '/': 10,
  '%': 10,
  '**': 11,
};

class _Parser {
  final List<_Tok> tokens;
  final Map<String, Object?> variables;
  int index = 0;

  _Parser(this.tokens, [this.variables = const <String, Object?>{}]);

  _Tok get current => tokens[index];

  bool get atEnd => current.type == _T.eof;

  void advance() {
    if (index < tokens.length - 1) index++;
  }

  bool _isOp(String op) => current.type == _T.op && current.lexeme == op;

  Object? parseExpression(int minPrecedence) {
    var left = _parseUnary();
    while (true) {
      final tok = current;
      // 三元
      if (tok.type == _T.op && tok.lexeme == '?' && minPrecedence <= 0) {
        advance();
        final thenValue = parseExpression(0);
        if (!_isOp(':')) throw _ExprError('expected ":" in conditional at ${current.pos}');
        advance();
        final elseValue = parseExpression(0);
        left = _truthy(left) ? thenValue : elseValue;
        continue;
      }
      if (tok.type != _T.op) break;
      final prec = _precedence[tok.lexeme];
      if (prec == null || prec < minPrecedence) break;
      final op = tok.lexeme;
      advance();
      // ** 右结合
      final right = parseExpression(op == '**' ? prec : prec + 1);
      left = _applyBinary(op, left, right, tok.pos);
    }
    return left;
  }

  Object? _parseUnary() {
    final tok = current;
    if (tok.type == _T.op && (tok.lexeme == '-' || tok.lexeme == '+' || tok.lexeme == '!')) {
      advance();
      final value = _parseUnary();
      switch (tok.lexeme) {
        case '-':
          final n = _toNumber(value, tok.pos);
          return n is int ? -n : -(n as double);
        case '+':
          return _toNumber(value, tok.pos);
        default:
          return !_truthy(value);
      }
    }
    return _parsePrimary();
  }

  Object? _parsePrimary() {
    final tok = current;
    switch (tok.type) {
      case _T.num:
      case _T.str:
        advance();
        return tok.value;
      case _T.lparen:
        advance();
        final value = parseExpression(0);
        if (current.type != _T.rparen) throw _ExprError('missing ")" for "(" at ${tok.pos}');
        advance();
        return value;
      case _T.ident:
        advance();
        final rawName = '${tok.value}';
        final name = rawName.toLowerCase();
        if (current.type == _T.lparen) {
          advance();
          final args = <Object?>[];
          if (current.type != _T.rparen) {
            args.add(parseExpression(0));
            while (current.type == _T.comma) {
              advance();
              args.add(parseExpression(0));
            }
          }
          if (current.type != _T.rparen) throw _ExprError('missing ")" for $name( at ${tok.pos}');
          advance();
          return _call(name, args, tok.pos);
        }
        if (name == 'true') return true;
        if (name == 'false') return false;
        if (name == 'null') return null;
        if (name == 'pi') return 3.141592653589793;
        if (name == 'e') return 2.718281828459045;
        if (variables.containsKey(rawName)) return variables[rawName];
        throw _ExprError('unknown name "$rawName" at ${tok.pos}');
      default:
        throw _ExprError('unexpected "${tok.lexeme.isEmpty ? tok.type.name : tok.lexeme}" at ${tok.pos}');
    }
  }

  Object? _call(String name, List<Object?> args, int pos) {
    switch (name) {
      case 'abs':
        _arity(name, args, 1, pos);
        final n = _toNumber(args[0], pos);
        return n is int ? n.abs() : (n as double).abs();
      case 'min':
      case 'max':
        if (args.isEmpty) throw _ExprError('$name() needs at least one argument');
        final numbers = args.map((e) => _toNumber(e, pos)).toList();
        var acc = numbers.first;
        for (final n in numbers.skip(1)) {
          final cmp = _compare(n, acc);
          if (name == 'min' ? cmp < 0 : cmp > 0) acc = n;
        }
        return acc;
      case 'round':
        _arity(name, args, 1, pos);
        return _toNumber(args[0], pos).toDouble().round();
      case 'floor':
        _arity(name, args, 1, pos);
        return _toNumber(args[0], pos).toDouble().floor();
      case 'ceil':
        _arity(name, args, 1, pos);
        return _toNumber(args[0], pos).toDouble().ceil();
      case 'sqrt':
        _arity(name, args, 1, pos);
        return math.sqrt(_toNumber(args[0], pos).toDouble());
      case 'pow':
        _arity(name, args, 2, pos);
        return math.pow(_toNumber(args[0], pos).toDouble(), _toNumber(args[1], pos).toDouble());
      case 'len':
        _arity(name, args, 1, pos);
        final v = args[0];
        if (v is String) return v.length;
        throw _ExprError('len() expects a string');
      case 'upper':
        _arity(name, args, 1, pos);
        return '${args[0]}'.toUpperCase();
      case 'lower':
        _arity(name, args, 1, pos);
        return '${args[0]}'.toLowerCase();
      case 'trim':
        _arity(name, args, 1, pos);
        return '${args[0]}'.trim();
      case 'hex':
        _arity(name, args, 1, pos);
        return '0x${_toNumber(args[0], pos).toInt().toRadixString(16)}';
      case 'bin':
        _arity(name, args, 1, pos);
        return '0b${_toNumber(args[0], pos).toInt().toRadixString(2)}';
      case 'int':
        _arity(name, args, 1, pos);
        final v = args[0];
        if (v is String) return int.tryParse(v.trim()) ?? (double.tryParse(v.trim())?.toInt() ?? 0);
        return _toNumber(v, pos).toInt();
      case 'float':
        _arity(name, args, 1, pos);
        final v = args[0];
        if (v is String) return double.tryParse(v.trim()) ?? 0.0;
        return _toNumber(v, pos).toDouble();
      case 'str':
        _arity(name, args, 1, pos);
        return ExprEval.format(args[0]);
      default:
        throw _ExprError('unknown function "$name"');
    }
  }

  void _arity(String name, List<Object?> args, int want, int pos) {
    if (args.length != want) {
      throw _ExprError('$name() expects $want argument(s), got ${args.length}');
    }
  }

  Object? _applyBinary(String op, Object? left, Object? right, int pos) {
    switch (op) {
      case '+':
        if (left is String || right is String) return '${_plain(left)}${_plain(right)}';
        final a = _toNumber(left, pos);
        final b = _toNumber(right, pos);
        if (a is int && b is int) return a + b;
        return a.toDouble() + b.toDouble();
      case '-':
        final a = _toNumber(left, pos);
        final b = _toNumber(right, pos);
        if (a is int && b is int) return a - b;
        return a.toDouble() - b.toDouble();
      case '*':
        final a = _toNumber(left, pos);
        final b = _toNumber(right, pos);
        if (a is int && b is int) return a * b;
        return a.toDouble() * b.toDouble();
      case '/':
        final a = _toNumber(left, pos).toDouble();
        final b = _toNumber(right, pos).toDouble();
        if (b == 0) throw _ExprError('division by zero');
        final result = a / b;
        if (result == result.roundToDouble() && a is int && b is int && a % b == 0) {
          return a ~/ b;
        }
        return result;
      case '%':
        final a = _toNumber(left, pos);
        final b = _toNumber(right, pos);
        if (b == 0) throw _ExprError('division by zero');
        if (a is int && b is int) return a % b;
        return a.toDouble() % b.toDouble();
      case '**':
        final a = _toNumber(left, pos).toDouble();
        final b = _toNumber(right, pos).toDouble();
        final result = math.pow(a, b).toDouble();
        if (result == result.roundToDouble() && b >= 0 && result.abs() < 1e15) return result.round();
        return result;
      case '==':
        return _compare(left, right) == 0;
      case '!=':
        return _compare(left, right) != 0;
      case '<':
        return _compare(left, right) < 0;
      case '>':
        return _compare(left, right) > 0;
      case '<=':
        return _compare(left, right) <= 0;
      case '>=':
        return _compare(left, right) >= 0;
      case '&&':
        return _truthy(left) && _truthy(right);
      case '||':
        return _truthy(left) || _truthy(right);
      case '&':
        return _toNumber(left, pos).toInt() & _toNumber(right, pos).toInt();
      case '|':
        return _toNumber(left, pos).toInt() | _toNumber(right, pos).toInt();
      case '^':
        return _toNumber(left, pos).toInt() ^ _toNumber(right, pos).toInt();
      case '<<':
        return _toNumber(left, pos).toInt() << _toNumber(right, pos).toInt();
      case '>>':
        return _toNumber(left, pos).toInt() >> _toNumber(right, pos).toInt();
      default:
        throw _ExprError('unsupported operator "$op"');
    }
  }

  num _toNumber(Object? value, int pos) {
    if (value is num) return value;
    if (value is bool) return value ? 1 : 0;
    if (value is String) {
      final parsed = num.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
    if (value == null) throw _ExprError('null is not a number');
    throw _ExprError('"${_plain(value)}" is not a number');
  }

  bool _truthy(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.isNotEmpty;
    return true;
  }

  int _compare(Object? a, Object? b) {
    if (a is num && b is num) return a.compareTo(b);
    if (a is String && b is String) return a.compareTo(b);
    if (a is bool && b is bool) return a == b ? 0 : (a ? 1 : -1);
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    return '${_plain(a)}'.compareTo('${_plain(b)}');
  }

  String _plain(Object? value) => value is String ? value : ExprEval.format(value);
}

/// 有状态的表达式会话：`a = 1+2` 之后可以直接用 `a*2`。
///
/// 控制台用这个而不是无状态的 [ExprEval.evaluate]，这样「先算一步、再拿结果继续算」
/// 不用复制粘贴。变量表只存在面板生命周期内，关掉面板即丢弃。
class ExprSession {
  final Map<String, Object?> variables = <String, Object?>{};

  void reset() => variables.clear();

  /// 执行一行输入：`name = expr` 赋值，其余当表达式求值。
  ExprResult eval(String source) {
    final text = source.trim();
    if (text.isEmpty) return const ExprResult.fail('empty expression');
    final assign = RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)\s*([\s\S]+)$').firstMatch(text);
    if (assign != null) {
      final value = ExprEval.evaluateWith(assign.group(2)!, variables);
      if (value.isError) return value;
      variables[assign.group(1)!] = value.value;
      return ExprResult.ok(value.value);
    }
    return ExprEval.evaluateWith(text, variables);
  }
}
