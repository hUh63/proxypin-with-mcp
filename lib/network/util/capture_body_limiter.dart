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

/// 抓包内容上限（上游 #773 / #456）。
///
/// 长时间或高流量抓包时，把每个请求/响应的**完整 body** 都留在内存里，会让
/// 内存随抓包时长持续上涨（#456 OOM）。本模块提供一个用户可调的「内容上限」：
/// 超过上限的 body 只保留前 N 字节（压缩体整体释放）用于列表展示，从而大幅
/// 降低长期驻留内存。
///
/// **安全前提**：裁剪必须发生在**代理转发完成之后**——转发是把消息体重新编码
/// 写给对端的，提前裁剪会破坏转发。调用点见 `http_proxy_handle.dart` 中
/// `clientChannel.write` / `remoteChannel.write` 之后。
library;

import 'package:proxypin/network/bin/configuration.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/util/logger.dart';

class CaptureBodyLimiter {
  /// 在转发完成后裁剪 [message] 的消息体。
  ///
  /// 规则：
  /// - 未开启（上限 <= 0）时不做任何事，行为与旧版一致；
  /// - 未压缩的 body：超过上限则只保留前 N 字节，标记 [HttpMessage.bodyTruncated]；
  /// - 压缩的 body（gzip / br / deflate 等）：截断会破坏压缩流导致无法解码，
  ///   因此整体释放（不展示），同样标记。
  static void limit(HttpMessage message) {
    final limitKB = Configuration.loaded?.captureBodyLimitKB ?? 0;
    if (limitKB <= 0) return;

    final body = message.body;
    if (body == null || body.isEmpty) return;

    final maxBytes = limitKB * 1024;
    if (body.length <= maxBytes) return;

    final originalLength = body.length;
    final compressed = (message.headers.contentEncoding ?? '').isNotEmpty;

    if (compressed) {
      // 压缩体一旦截断就无法再解压，宁可整体释放
      message.releaseBody();
    } else {
      message.body = List<int>.from(body.sublist(0, maxBytes));
    }
    message.bodyTruncated = true;
    message.originalBodyLength = originalLength;

    logger.d('Capture body limit: body ${originalLength ~/ 1024}KB -> '
        '${compressed ? 'released' : '${maxBytes ~/ 1024}KB'} (limit ${limitKB}KB)');
  }

  /// 对一批**已抓取**的请求（含其响应）统一应用内容上限。
  ///
  /// 供"停止抓包"时调用：把此前按上限只做了一半的裁剪补齐，并释放超大 body 的驻留内存。
  /// 未开启上限（<= 0）时不做任何事——默认行为与旧版完全一致。
  static void limitAll(Iterable<HttpRequest> requests) {
    final limitKB = Configuration.loaded?.captureBodyLimitKB ?? 0;
    if (limitKB <= 0) return;

    var count = 0;
    for (final request in requests) {
      limit(request);
      final response = request.response;
      if (response != null) {
        limit(response);
      }
      count++;
    }
    if (count > 0) {
      logger.d('Capture body limit applied to $count retained messages on stop');
    }
  }
}
