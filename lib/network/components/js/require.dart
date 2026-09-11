/*
 * 上游 #719：脚本中加载第三方 JS 库
 *
 * 在运行时注入全局 `require(url)` / `loadLibrary(url)`：按 URL 拉取 JS 源码，
 * 以 CommonJS 风格（提供 module / exports / require / globalThis）执行，并缓存结果，
 * 同一 URL 只拉取与执行一次。
 *
 * 用法（脚本内）：
 *   const utils = await require('https://example.com/my-utils.js');
 *   utils.sign('abc');
 * 若库把 API 挂到全局，加载后也可直接调用（如 window.mySign(...)）。
 *
 * 说明：JS 引擎不支持同步阻塞拉取网络，故 require 返回 Promise，需 await；
 * 依赖库需能访问 fetch（由 flutter_js enableFetch2 提供）。
 */
import 'package:flutter_js/flutter_js.dart';

class RequireBridge {
  /// 注入到运行时的 require 实现（纯 JS，逐条满足 CommonJS 约定）
  static const String polyfill = r'''
(function () {
  if (globalThis.require && globalThis.__proxypinRequire) {
    return;
  }
  var cache = globalThis.__proxypinModuleCache || (globalThis.__proxypinModuleCache = {});

  globalThis.require = async function (url) {
    if (url == null) {
      throw new Error('require(url): url 不能为空');
    }
    if (cache[url]) {
      return cache[url].exports;
    }

    var resp = await fetch(url);
    if (!resp || resp.ok === false) {
      throw new Error('require(' + url + ') 拉取失败: ' + (resp ? resp.status : 'no response'));
    }
    var code = await resp.text();
    if (typeof code !== 'string' || code.length === 0) {
      throw new Error('require(' + url + ') 内容为空');
    }

    var module = { exports: {} };
    try {
      // 以 CommonJS 包装执行：库可选择写 module.exports，或把 API 挂到 globalThis
      var fn = new Function('module', 'exports', 'require', 'globalThis', 'console', code);
      fn(module, module.exports, globalThis.require, globalThis, console);
    } catch (e) {
      throw new Error('require(' + url + ') 执行失败: ' + (e && e.message ? e.message : e));
    }

    cache[url] = module;
    return module.exports;
  };

  // 语义化别名，便于阅读
  globalThis.loadLibrary = globalThis.require;
  globalThis.__proxypinRequire = true;
})();
''';

  /// 在运行时注册 require（每个 runtime 初始化时调用一次）
  static void registerRequire(JavascriptRuntime flutterJs) {
    flutterJs.evaluate(polyfill);
  }
}
