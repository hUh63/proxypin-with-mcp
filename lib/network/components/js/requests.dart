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

import 'package:flutter_js/flutter_js.dart';
import 'package:proxypin/network/mcp/mcp_bridge.dart';

/// 脚本可用的「抓包列表」操作（上游 #645）。
///
/// 脚本运行时可直接调用：
///
/// ```js
/// // 清空当前抓包列表（等同于界面上的垃圾桶）
/// clearRequests();
///
/// // 从列表移除指定请求（例如脚本改写成功后，不想让别人看见这条）
/// // onResponse(context, request, response) 里用 request.requestId
/// removeRequest(request.requestId);
/// ```
///
/// 说明：仅影响**列表展示**，不影响已经发生的转发；请求本身早已按修改后的内容写出。
class RequestsBridge {
  static const String _prelude = '''
    function clearRequests() {
      return sendMessage('clearRequests', '');
    }
    function removeRequest(requestId) {
      return sendMessage('removeRequest', JSON.stringify({requestId: requestId == null ? '' : String(requestId)}));
    }
  ''';

  /// 注册脚本可用的列表操作（幂等）
  static void registerRequests(JavascriptRuntime flutterJs) {
    final channels = JavascriptRuntime.channelFunctionsRegistered[flutterJs.getEngineInstanceId()];
    if (channels != null && channels.containsKey('clearRequests')) {
      return;
    }

    flutterJs.evaluate(_prelude);

    flutterJs.onMessage('clearRequests', (args) {
      // 优先走界面的"清空"（会同时刷新列表状态）；没有接线时退化为直接清空容器
      if (!McpBridge().clearWithUI()) {
        McpBridge().clear();
      }
      return true;
    });

    flutterJs.onMessage('removeRequest', (args) {
      final id = _requestIdOf(args);
      if (id.isEmpty) return false;
      return McpBridge().removeRequest(id);
    });
  }

  /// 容错取值：flutter_js 依 payload 类型可能回传 Map / List / String
  static String _requestIdOf(dynamic args) {
    dynamic value = args;
    if (value is Map) {
      value = value['requestId'];
    } else if (value is List) {
      if (value.isEmpty) return '';
      value = value.first;
      if (value is Map) value = value['requestId'];
    }

    if (value == null) return '';
    final text = value.toString();
    // JSON 字符串可能带上引号
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      return text.substring(1, text.length - 1);
    }
    return text;
  }
}
