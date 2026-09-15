/*
 * Copyright 2023 Hongen Wang All rights reserved.
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

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';
import 'package:proxypin/network/util/logger.dart';

/// JS 反混淆 / 反编译（内置 jsrestore）。
///
/// 实现方式：把 **acorn**（JS 解析器，单文件 UMD）与 **jsrestore**
/// （Node 版反混淆工具）作为 assets 打入应用，再用内置的 JS 引擎
/// （flutter_js）执行。
///
/// Node 版 jsrestore 只依赖 `fs` / `path` / `acorn` 三个模块和
/// `process.argv` / `process.exit` / `console`，因此这里用
/// **CommonJS 包装 + 桩模块** 的方式直接在引擎里跑它，无需改动其源码：
///
/// - `fs` 桩：把"读文件"变成"读内存里传入的字符串"，写文件则被捕获为输出；
/// - `process` 桩：注入 argv，`exit` 只记录退出码（不终止引擎）；
/// - `console` 桩：把工具的过程输出收集成日志返回给 UI。
///
/// 全程离线、不联网，也不执行被分析代码（只有 `verify` 会在桩环境里尝试加载）。
class JsRestoreResult {
  final bool ok;
  final String output;
  final List<String> logs;
  final int exitCode;

  const JsRestoreResult({
    required this.ok,
    required this.output,
    required this.logs,
    required this.exitCode,
  });

  static const empty = JsRestoreResult(ok: true, output: '', logs: [], exitCode: 0);
}

class JsDeobfuscator {
  /// 输入上限：超过则拒绝（避免 JS 引擎长时间阻塞）
  static const int maxInputBytes = 2 * 1024 * 1024;

  static JavascriptRuntime? _runtime;
  static Future<void>? _restoreInitFuture;
  static Future<void>? _beautifyInitFuture;
  static bool _restoreLoaded = false;
  static bool _beautifyLoaded = false;

  /// 是否已就绪
  static bool get isReady => _runtime != null;

  /// 引擎内的引导代码：桩模块 + `__jsr_run` 入口。
  /// `/*__JSRESTORE_SOURCE__*/` 处会被替换为 jsrestore 源码。
  static const String _bootstrap = r'''
;(function () {
  var __jsr_files = {};
  var __jsr_logs = [];
  var __jsr_exitCode = null;
  globalThis.__jsr_output = '';
  globalThis.__jsr_error = '';

  function __jsr_push(args) {
    var parts = [];
    for (var i = 0; i < args.length; i++) {
      var a = args[i];
      parts.push(typeof a === 'string' ? a : String(a));
    }
    __jsr_logs.push(parts.join(' '));
    if (__jsr_logs.length > 2000) __jsr_logs.shift();
  }

  var __jsr_fs = {
    readFileSync: function (p) {
      var k = String(p);
      if (!(k in __jsr_files)) {
        var e = new Error('ENOENT: no such file, open ' + k);
        e.code = 'ENOENT';
        throw e;
      }
      return __jsr_files[k];
    },
    writeFileSync: function (p, s) { __jsr_files[String(p)] = String(s); },
    existsSync: function (p) { return String(p) in __jsr_files; },
    statSync: function (p) {
      var k = String(p);
      if (!(k in __jsr_files)) {
        var e = new Error('ENOENT: ' + k);
        e.code = 'ENOENT';
        throw e;
      }
      return { size: __jsr_files[k].length };
    },
    mkdirSync: function () {},
    realpathSync: function (p) { return String(p); }
  };

  var __jsr_path = {
    basename: function (p) { var s = String(p).split('/'); return s[s.length - 1]; },
    dirname: function (p) { var i = String(p).lastIndexOf('/'); return i < 0 ? '.' : String(p).slice(0, i); },
    join: function () { var a = []; for (var i = 0; i < arguments.length; i++) a.push(String(arguments[i])); return a.join('/'); },
    extname: function (p) { var b = __jsr_path.basename(p); var i = b.lastIndexOf('.'); return i < 0 ? '' : b.slice(i); }
  };

  var __jsr_process = {
    argv: ['node', 'jsrestore', ''],
    exit: function (c) { __jsr_exitCode = (c === undefined ? 0 : c); },
    platform: 'linux',
    version: 'v18.0.0',
    cwd: function () { return '/'; },
    env: {},
    stdout: { write: function (s) { __jsr_push([s]); } },
    stderr: { write: function (s) { __jsr_push([s]); } }
  };

  var __jsr_console = {
    log: function () { __jsr_push(arguments); },
    error: function () { __jsr_push(arguments); },
    warn: function () { __jsr_push(arguments); },
    info: function () { __jsr_push(arguments); },
    debug: function () { __jsr_push(arguments); }
  };

  function __jsr_require(name) {
    if (name === 'fs') return __jsr_fs;
    if (name === 'path') return __jsr_path;
    if (name === 'acorn') return globalThis.__jsr_acorn;
    throw new Error("Cannot find module '" + name + "'");
  }

  // 原始的 Node 版 jsrestore 源码（CommonJS 包装）
  globalThis.__jsr_factory = function (module, exports, require, process, console) {
/*__JSRESTORE_SOURCE__*/
  };

  globalThis.__jsr_run = function (cmd, fileName, code, outName) {
    __jsr_files = {};
    __jsr_logs = [];
    __jsr_exitCode = null;
    globalThis.__jsr_output = '';
    globalThis.__jsr_error = '';
    __jsr_files[fileName] = code;
    __jsr_process.argv = outName
      ? ['node', 'jsrestore', cmd, fileName, '-o', outName]
      : ['node', 'jsrestore', cmd, fileName];

    var moduleObj = { exports: {} };
    try {
      globalThis.__jsr_factory(moduleObj, moduleObj.exports, __jsr_require, __jsr_process, __jsr_console);
    } catch (e) {
      var msg = (e && e.message) ? e.message : String(e);
      globalThis.__jsr_error = msg;
      __jsr_push(['执行失败: ' + msg]);
      if (__jsr_exitCode === null) __jsr_exitCode = 1;
    }

    if (outName && __jsr_files[outName]) {
      globalThis.__jsr_output = __jsr_files[outName];
    }
    return JSON.stringify({
      exitCode: __jsr_exitCode,
      out: outName || '',
      outputLength: globalThis.__jsr_output.length,
      error: globalThis.__jsr_error,
      logs: __jsr_logs
    });
  };
})();
''';

  /// 确保 JS 引擎已创建（不装载任何模块）
  static Future<void> _ensureRuntime() async {
    _runtime ??= getJavascriptRuntime(xhr: false);
  }

  /// 首次调用时装载 acorn 与 jsrestore（约几百毫秒）
  static Future<void> _ensureJsRestore() async {
    if (_restoreLoaded) return;
    if (_restoreInitFuture != null) {
      await _restoreInitFuture;
      return;
    }
    _restoreInitFuture = _initJsRestore();
    try {
      await _restoreInitFuture;
    } catch (e, t) {
      _restoreInitFuture = null;
      logger.e('初始化 JS 反混淆引擎失败', error: e, stackTrace: t);
      rethrow;
    }
  }

  static Future<void> _initJsRestore() async {
    await _ensureRuntime();
    final runtime = _runtime!;
    final acornSource = await rootBundle.loadString('assets/js/acorn.js');
    final jsrestoreSource = await rootBundle.loadString('assets/js/jsrestore.js');

    // 1) 装载 acorn（UMD → globalThis.__jsr_acorn）
    runtime.evaluate(
      'globalThis.__jsr_acorn = (function () {\n'
      '  var m = { exports: {} };\n'
      '  (function (module, exports, require) {\n'
      '$acornSource\n'
      '  })(m, m.exports, function () { throw new Error("no require"); });\n'
      '  return m.exports;\n'
      '})();',
    );

    // 2) 注入桩与 jsrestore 源码
    runtime.evaluate(_bootstrap.replaceFirst('/*__JSRESTORE_SOURCE__*/', jsrestoreSource));

    // 3) 自检：装载成功才置位
    final probe = runtime.evaluate('typeof globalThis.__jsr_run === "function" && !!globalThis.__jsr_acorn');
    if (probe.stringResult != 'true' && probe.rawResult != true) {
      throw StateError('JS 引擎装载 acorn / jsrestore 失败');
    }

    _restoreLoaded = true;
    logger.d('JS 反混淆引擎就绪');
  }

  /// 首次调用时装载 js-beautify（纯格式化用，约 150KB）
  static Future<void> _ensureBeautify() async {
    if (_beautifyLoaded) return;
    _beautifyInitFuture ??= () async {
      await _ensureRuntime();
      final source = await rootBundle.loadString('assets/js/js-beautify.js');
      _runtime!.evaluate(
        'globalThis.__jsb = (function () {\n'
        '  var m = { exports: {} };\n'
        '  (function (module, exports) {\n'
        '$source\n'
        '  })(m, m.exports);\n'
        '  return (m.exports && m.exports.js_beautify) ? m.exports.js_beautify : m.exports;\n'
        '})();',
      );
      _beautifyLoaded = true;
      logger.d('JS 格式化引擎就绪');
    }();
    await _beautifyInitFuture;
  }

  /// 纯格式化（美化）JS —— 基于 js-beautify，保留注释、不改变语义。
  ///
  /// 与 [run] 的 `restore` 不同：这里只做排版，不做任何反混淆。
  static Future<String> beautify(String code, {int indent = 2}) async {
    if (code.trim().isEmpty) return code;
    if (code.length > maxInputBytes) {
      throw StateError('输入过大');
    }
    await _ensureBeautify();
    final result = _runtime!.evaluate(
      'globalThis.__jsb(${jsonEncode(code)}, '
      '{indent_size: $indent, preserve_newlines: true, max_preserve_newlines: 2, '
      'end_with_newline: false, brace_style: "collapse"})',
    );
    if (result.isError || result.stringResult == null) {
      throw StateError(result.stringResult ?? 'format failed');
    }
    return result.stringResult!;
  }

  /// 执行一次 jsrestore 命令。
  ///
  /// [command]：`detect` / `restore`；[code]：待处理的 JS 源码；
  /// [outName]：还原后的输出文件名（引擎内的虚拟文件名，仅用于取值）。
  static Future<JsRestoreResult> run(
    String command,
    String code, {
    String outName = 'restored.js',
  }) async {
    if (code.trim().isEmpty) {
      return const JsRestoreResult(ok: false, output: '', logs: ['输入为空'], exitCode: 1);
    }
    if (code.length > maxInputBytes) {
      return JsRestoreResult(
        ok: false,
        output: '',
        logs: ['输入过大（${(code.length / 1024 / 1024).toStringAsFixed(1)} MB），上限 '
            '${(maxInputBytes / 1024 / 1024).toStringAsFixed(0)} MB'],
        exitCode: 1,
      );
    }

    await _ensureJsRestore();
    final runtime = _runtime!;

    final summaryResult = runtime.evaluate(
      '__jsr_run(${jsonEncode(command)}, ${jsonEncode('input.js')}, '
      '${jsonEncode(code)}, ${jsonEncode(outName)})',
    );

    if (summaryResult.isError || summaryResult.stringResult == null) {
      return JsRestoreResult(
        ok: false,
        output: '',
        logs: ['JS 执行错误：${summaryResult.stringResult ?? 'unknown'}'],
        exitCode: 1,
      );
    }

    Map<String, dynamic> summary;
    try {
      summary = jsonDecode(summaryResult.stringResult!) as Map<String, dynamic>;
    } catch (e) {
      return JsRestoreResult(
        ok: false,
        output: '',
        logs: ['结果解析失败：$e'],
        exitCode: 1,
      );
    }

    final logs = <String>[];
    final rawLogs = summary['logs'];
    if (rawLogs is List) {
      logs.addAll(rawLogs.map((e) => e.toString()));
    }

    var output = '';
    if (command == 'restore') {
      final outResult = runtime.evaluate('globalThis.__jsr_output');
      output = outResult.stringResult ?? '';
    }

    final exitCode = summary['exitCode'] is int ? summary['exitCode'] as int : 1;
    return JsRestoreResult(
      ok: exitCode == 0,
      output: output,
      logs: logs,
      exitCode: exitCode,
    );
  }

  /// 释放引擎（页面退出时可调用；下次使用会自动重建）
  static void dispose() {
    try {
      _runtime?.dispose();
    } catch (_) {}
    _runtime = null;
    _restoreInitFuture = null;
    _beautifyInitFuture = null;
    _restoreLoaded = false;
    _beautifyLoaded = false;
  }
}
