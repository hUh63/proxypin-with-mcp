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

void main() {
  print(HostFilter.filter("stackoverflow.com"));
}

/// @author wanghongen
/// 2023/7/26
class HostFilter {
  /// 白名单
  static final Whites whitelist = Whites();

  /// 黑名单
  static final Blacks blacklist = Blacks();

  /// 是否过滤
  ///
  /// [host] 主机名；[path] 可选，请求路径（含查询串）。
  /// 上游 #225：除了按域名过滤，还支持按 URL 路径/接口过滤——
  /// 传入 path 时匹配目标是 `host + path`，于是规则既可写 `.*\.apple\.com`
  /// （域名，行为与旧版一致），也可写 `api\.example\.com/v1/` 只抓某个接口。
  ///
  /// 连接建立阶段拿不到 path（只有 host），此时对**含 `/` 的路径型规则**不做
  /// 否决：白名单视为"可能命中"（不排除），黑名单视为"未命中"（不过滤），
  /// 把最终判定推迟到请求/响应阶段按完整 URL 进行——否则白名单会误杀整个域名、
  /// 黑名单会过度过滤。
  static bool filter(String? host, {String? path}) {
    if (host == null) {
      return false;
    }

    var hasPath = path != null && path.isNotEmpty;
    var target = hasPath ? '$host$path' : host;

    bool ruleMatches(RegExp rule, {required bool assumePathHit}) {
      if (rule.hasMatch(target)) {
        return true;
      }
      if (hasPath || !rule.pattern.contains('/')) {
        return false;
      }
      // 无 path 信息时的路径型规则：保守处理，避免误判
      return assumePathHit;
    }

    //如果白名单不为空，不在白名单里都是黑名单
    if (whitelist.enabled) {
      return whitelist.list.every((element) => !ruleMatches(element, assumePathHit: true));
    }

    if (blacklist.enabled) {
      return blacklist.list.any((element) => ruleMatches(element, assumePathHit: false));
    }
    return false;
  }
}

///
abstract class HostList {
  /// 列表
  final List<RegExp> list = [];
  bool enabled = false;

  ///加载配置
  void load(Map<String, dynamic>? map) {
    if (map == null) {
      return;
    }
    List? list = map['list'];
    this.list.clear();
    list?.forEach((element) {
      this.list.add(RegExp(element));
    });
    enabled = map['enabled'] == true;
  }

  void add(String reg) {
    var regExp = RegExp(reg.replaceAll("*", ".*"));
    list.removeWhere((element) => element.pattern == regExp.pattern);
    list.add(regExp);
  }

  void remove(String reg) {
    list.removeWhere((element) => element.pattern == reg.replaceAll("*", ".*"));
  }

  void removeIndex(List<int> index) {
    for (var element in index) {
      list.removeAt(element);
    }
  }

  // json序列化
  Map<String, dynamic> toJson() {
    return {
      'list': list.map((e) => e.pattern).toList(),
      'enabled': enabled,
    };
  }
}

///白名单
class Whites extends HostList {}

///黑名单
class Blacks extends HostList {
  Blacks() {
    enabled = true;
    list.add(RegExp(".*.apple.com"));
    list.add(RegExp(".*.icloud.com"));
  }
}
