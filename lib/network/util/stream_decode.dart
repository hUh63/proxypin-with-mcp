/*
 * Copyright 2025 Hongen Wang All rights reserved.
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

/// 带上限的（增量）解码（上游 #456 / #674）。
///
/// 抓包时长与体量上来后，"把完整 body 一次性解压、再整体解码成字符串"是最容易 OOM 的
/// 一步：压缩比可达 10 倍以上，一个 100MB 的响应解出来就是 1GB 级字符串。上游 #456
/// 报的正是长时运行后的 OOM。
///
/// 本模块提供**有界**解压，供只读场景（详情预览、搜索、对比、审计、AI 分析）使用：
///
/// - gzip / deflate：用 `RawZLibFilter` **增量**喂入、累计输出，达到上限**立即停止**。
///   即使压缩比极高，内存占用也被上限钉死——这才是真正的"流式"；
/// - br / zstd：第三方库只提供一次性 API，无法增量。改为**输入超限则不尝试解压**
///   （避免"小输入→巨大输出"的最坏情况），解出后再截断到上限；
/// - 任何解压失败：退回原始字节前缀，绝不抛异常。
///
/// **不要**在需要完整内容的场景（脚本改写、重写规则、代码导出）使用有界解码——
/// 截断会让写出/导出的内容失真；那些路径请继续用 `HttpMessage.decodeBodyString()`。
library;

import 'dart:convert';
import 'dart:io';

import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/util/compress.dart';
import 'package:proxypin/network/util/logger.dart';

/// 有界解码的结果
class BoundedDecodeResult {
  /// 解出的字节（长度不超过请求的上限）
  final List<int> bytes;

  /// 是否因为达到上限而截断（内容不完整）
  final bool truncated;

  /// 是否因为体量过大而**跳过**了压缩解码（此时 [bytes] 是原始压缩字节的前缀）
  final bool skipped;

  /// 解压失败时的说明
  final String? error;

  const BoundedDecodeResult(this.bytes, {this.truncated = false, this.skipped = false, this.error});

  /// 没有拿到可用的解压结果
  bool get failed => error != null;
}

class StreamDecoder {
  /// 未配置「抓包内容上限」时的默认预览解码上限（4 MB）
  static const int defaultMaxBytes = 4 * 1024 * 1024;

  /// 单次喂给 inflate 的输入块大小
  static const int _inputChunk = 64 * 1024;

  /// gzip 的 windowBits（zlib 约定：16 + 15）
  static const int _gzipWindowBits = 31;

  /// 预览解码上限。
  ///
  /// 若用户设置了「抓包内容上限」，解码上限与之一致（存都没存那么多，解更多没意义）；
  /// 否则用 [defaultMaxBytes]。这样不会新增一个需要用户理解的开关。
  static int get limitBytes {
    final kb = Configuration.loaded?.captureBodyLimitKB ?? 0;
    return kb > 0 ? kb * 1024 : defaultMaxBytes;
  }

  /// 同步有界解码：处理 identity / gzip / deflate / br。
  ///
  /// zstd 需要异步 API，见 [decodeZstdBounded]。
  static BoundedDecodeResult decode(List<int> input, String encoding, {int? maxBytes}) {
    final limit = maxBytes ?? limitBytes;
    final enc = encoding.trim().toLowerCase();

    if (input.isEmpty) return const BoundedDecodeResult([]);
    if (enc.isEmpty || enc == 'identity') return _prefix(input, limit);

    if (enc == 'gzip' || enc == 'x-gzip') {
      final result = inflateBounded(input, gzip: true, maxBytes: limit);
      // inflate 失败时按旧行为退回原始字节前缀
      return result.failed ? _prefix(input, limit, error: result.error) : result;
    }

    if (enc == 'deflate') {
      // 规范上 deflate = zlib 包装，但不少服务端实际发的是 raw deflate（旧实现也按 raw 处理）。
      // 先按 raw 解，解不出来再试 zlib 包装。
      final rawResult = inflateBounded(input, gzip: false, raw: true, maxBytes: limit);
      if (!rawResult.failed && rawResult.bytes.isNotEmpty) return rawResult;

      final zlibResult = inflateBounded(input, gzip: false, raw: false, maxBytes: limit);
      if (!zlibResult.failed && zlibResult.bytes.isNotEmpty) return zlibResult;
      return _prefix(input, limit, error: rawResult.error ?? zlibResult.error);
    }

    if (enc == 'br' || enc == 'brotli') {
      if (input.length > limit) {
        // 无法增量解压：宁可不猜，也不冒一次性巨量分配的风险
        return _prefix(input, limit, skipped: true);
      }
      try {
        return _truncate(brDecode(input), limit);
      } catch (e) {
        return _prefix(input, limit, error: '$e');
      }
    }

    // 未知编码：不解码
    return _prefix(input, limit);
  }

  /// 异步有界解码 zstd；编码不是 zstd 时退化为 [decode]。
  static Future<BoundedDecodeResult> decodeAsync(List<int> input, String encoding, {int? maxBytes}) async {
    final limit = maxBytes ?? limitBytes;
    final enc = encoding.trim().toLowerCase();
    if (enc != 'zstd') return decode(input, encoding, maxBytes: limit);

    if (input.isEmpty) return const BoundedDecodeResult([]);
    if (input.length > limit) return _prefix(input, limit, skipped: true);
    try {
      final out = await zstdDecode(input);
      if (out == null) return _prefix(input, limit, error: 'zstd decode returned null');
      return _truncate(out, limit);
    } catch (e) {
      return _prefix(input, limit, error: '$e');
    }
  }

  /// zlib/gzip **增量**解压，达到 [maxBytes] 立即返回。
  ///
  /// 关键点：绝不等整段输入解完；每喂一块就取一次输出，凑够上限就停。
  static BoundedDecodeResult inflateBounded(
    List<int> input, {
    required bool gzip,
    bool raw = false,
    int maxBytes = defaultMaxBytes,
  }) {
    final out = <int>[];
    try {
      final filter = RawZLibFilter.inflateFilter(
        raw: gzip ? false : raw,
        windowBits: gzip ? _gzipWindowBits : ZLibOption.defaultWindowBits,
      );

      for (var start = 0; start < input.length; start += _inputChunk) {
        final end = start + _inputChunk <= input.length ? start + _inputChunk : input.length;
        filter.process(input, start, end);
        // 不声明 end：输入本身可能被裁剪过，声明 end 反而会抛 "incomplete" 错误
        final produced = filter.processed(flush: true);
        if (produced.isEmpty) continue;

        final remain = maxBytes - out.length;
        if (produced.length >= remain) {
          out.addAll(produced.sublist(0, remain));
          return BoundedDecodeResult(out, truncated: true);
        }
        out.addAll(produced);
      }

      return BoundedDecodeResult(out);
    } catch (e) {
      logger.e('inflateBounded error: $e');
      return BoundedDecodeResult(const [], error: '$e');
    }
  }

  /// 原始字节前缀（不解压）
  static BoundedDecodeResult _prefix(List<int> input, int maxBytes, {String? error, bool skipped = false}) {
    if (input.length <= maxBytes) {
      return BoundedDecodeResult(input, error: error, skipped: skipped);
    }
    return BoundedDecodeResult(input.sublist(0, maxBytes), truncated: true, error: error, skipped: skipped);
  }

  /// 把已解出的字节截断到上限
  static BoundedDecodeResult _truncate(List<int> decoded, int maxBytes) {
    if (decoded.length <= maxBytes) return BoundedDecodeResult(decoded);
    return BoundedDecodeResult(decoded.sublist(0, maxBytes), truncated: true);
  }
}

/// 供有界解码结果做文本转换：截断可能切断多字节字符，
/// 因此必须 allowMalformed，不能像全长解码那样抛异常。
String decodeBytesToText(List<int> bytes, String? charset) {
  if (charset == null || charset == 'utf-8' || charset == 'utf8') {
    return utf8.decode(bytes, allowMalformed: true);
  }
  return String.fromCharCodes(bytes);
}
