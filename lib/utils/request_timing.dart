/*
 * Copyright 2023 Hongen Wang
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
import 'package:proxypin/network/http/http.dart';

/// 单条请求的分阶段耗时（纯计算，无 flutter 依赖，可单测）。
///
/// 分四段（可缺省）：
///  - connect：到服务端的 TCP 连接耗时（**含 DNS 解析** —— Dart 的
///    `Socket.connect` 把域名解析与建连合并成一次调用，因此二者无法分离，
///    这里如实标注为「连接(含 DNS)」）；
///  - tls：TLS 握手耗时；
///  - wait：请求发出到响应头到达（≈ TTFB）；
///  - receive：响应头到响应体读完。
///
/// 连接复用（keep-alive）时没有 connect / tls 耗时——如实为空。
class RequestTiming {
  final int? connectMs;
  final int? tlsMs;
  final int? waitMs;
  final int? receiveMs;
  final int? totalMs;
  final bool reused;

  const RequestTiming({
    this.connectMs,
    this.tlsMs,
    this.waitMs,
    this.receiveMs,
    this.totalMs,
    this.reused = false,
  });

  static RequestTiming of(HttpRequest request) {
    final response = request.response;
    int? wait;
    int? receive;
    int? total;
    if (response != null) {
      // response.responseTime 在响应头解析时写入 ≈ 首字节时间
      wait = response.responseTime.difference(request.requestTime).inMilliseconds;
      final done = response.completeTime;
      if (done != null) {
        receive = done.difference(response.responseTime).inMilliseconds;
        total = done.difference(request.requestTime).inMilliseconds;
      } else {
        total = wait;
      }
    }
    return RequestTiming(
      connectMs: request.connectTimeMs,
      tlsMs: request.tlsTimeMs,
      waitMs: wait,
      receiveMs: receive,
      totalMs: total,
      reused: request.connectionReused,
    );
  }
}
