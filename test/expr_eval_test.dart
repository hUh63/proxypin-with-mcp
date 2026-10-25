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

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/utils/expr_eval.dart';

void main() {
  test('arithmetic precedence', () {
    expect(ExprEval.evaluate('1+2*3').value, 7);
    expect(ExprEval.evaluate('(1+2)*3').value, 9);
    expect(ExprEval.evaluate('2**10').value, 1024);
    expect(ExprEval.evaluate('-3 + 4').value, 1);
    expect(ExprEval.evaluate('10 % 3').value, 1);
  });

  test('division keeps integers when exact', () {
    expect(ExprEval.evaluate('10/2').value, 5);
    expect(ExprEval.evaluate('10/4').value, 2.5);
    expect(ExprEval.evaluate('1/0').isError, isTrue);
  });

  test('numbers in other bases', () {
    expect(ExprEval.evaluate('0x1F').value, 31);
    expect(ExprEval.evaluate('0b1010').value, 10);
    expect(ExprEval.evaluate('1e3').value, 1000.0);
  });

  test('strings and concatenation', () {
    expect(ExprEval.evaluate('"a"+"b"').value, 'ab');
    expect(ExprEval.evaluate("len('abcd')").value, 4);
    expect(ExprEval.evaluate('upper("ab")').value, 'AB');
  });

  test('comparison and logic', () {
    expect(ExprEval.evaluate('1 < 2').value, true);
    expect(ExprEval.evaluate('1 == 1').value, true);
    expect(ExprEval.evaluate('true && false').value, false);
    expect(ExprEval.evaluate('!false').value, true);
    expect(ExprEval.evaluate('1 < 2 ? "y" : "n"').value, 'y');
  });

  test('functions', () {
    expect(ExprEval.evaluate('max(1,5)').value, 5);
    expect(ExprEval.evaluate('min(3,2)').value, 2);
    expect(ExprEval.evaluate('abs(-7)').value, 7);
    expect(ExprEval.evaluate('round(2.6)').value, 3);
    expect(ExprEval.evaluate('hex(255)').value, '0xff');
    expect(ExprEval.evaluate('pow(2,8)').value, 256);
  });

  test('bit operations', () {
    expect(ExprEval.evaluate('6 & 3').value, 2);
    expect(ExprEval.evaluate('6 | 3').value, 7);
    expect(ExprEval.evaluate('1 << 4').value, 16);
  });

  test('errors are reported, never silent', () {
    expect(ExprEval.evaluate('1 +').isError, isTrue);
    expect(ExprEval.evaluate('unknownName').isError, isTrue);
    expect(ExprEval.evaluate('nosuchfn(1)').isError, isTrue);
    expect(ExprEval.evaluate('(1+2').isError, isTrue);
    expect(ExprEval.evaluate('"abc').isError, isTrue);
    expect(ExprEval.evaluate('').isError, isTrue);
  });

  test('format', () {
    expect(ExprEval.format(1.0), '1');
    expect(ExprEval.format(1.5), '1.5');
    expect(ExprEval.format('a'), "'a'");
    expect(ExprEval.format(null), 'null');
    expect(ExprEval.format(true), 'true');
  });
}
