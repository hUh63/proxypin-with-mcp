/*
 * JS 引擎桥接单测（md5）。
 *
 * 原文件是 @Tags(['integration']) 的“假测试”：只有 print，无断言，
 * 且往 /Users/wanghongen/Downloads/ 写文件（路径不存在时会抛错）。
 *
 * 这里改为真断言（用 JS 侧调用 md5() 校验桥接注册是否生效），并**保留**
 * @Tags(['integration'])：`getJavascriptRuntime()` 依赖 flutter_js 的原生 JS 运行时
 * （Android/iOS/macOS/Windows 插件），在 CI 容器（Linux + 纯 flutter test）里无法加载，
 * 因此不在 CI 上执行。本地可 `flutter test --tags integration test/js_test.dart`。
 */

@Tags(['integration'])
library;

import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/components/js/md5.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Md5Bridge 注册后，JS 侧可直接调用 md5()', () {
    final js = getJavascriptRuntime();
    try {
      Md5Bridge.registerMd5(js);

      final result = js.evaluate("md5('value')");
      expect(result.stringResult, '2063c1608d6e0baf80249c42e2be5804');
    } finally {
      js.dispose();
    }
  });

  test('flutter_js 可执行多行脚本并取回同步结果', () {
    final js = getJavascriptRuntime();
    try {
      final result = js.evaluate('var a = 1 + 2; a * 3;');
      expect(result.stringResult, '9');
    } finally {
      js.dispose();
    }
  });

  test('Md5Bridge 可处理二进制输入（UTF-8 编码后求 md5）', () {
    final js = getJavascriptRuntime();
    try {
      Md5Bridge.registerMd5(js);
      final result = js.evaluate("md5('中文')");
      expect(result.stringResult, 'a7bac2239fcdcb3a067903d8077c4a07');
    } finally {
      js.dispose();
    }
  });
}
