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
import 'dart:convert';

/// 一种变异技术。
class WafTechnique {
  final String id;
  final String name;
  final String description;

  const WafTechnique(this.id, this.name, this.description);

  /// 具体变换。纯字符串处理，不做任何 IO。
  String Function(String input) get apply => _handlers[id] ?? ((s) => s);
}

/// 一条变异结果。
class WafVariant {
  final String technique;
  final String name;
  final String output;
  final String note;

  const WafVariant({
    required this.technique,
    required this.name,
    required this.output,
    this.note = '',
  });
}

/// WAF 绕过辅助：**载荷变异**。
///
/// 先把边界说清楚，它只做一件事：**在本地把一个载荷变换成若干等价写法**。
///
/// - 不发送任何请求、不自动探测、不自动利用——变换结果由你自己决定怎么用
///   （可以直接扔进本工具的请求构造 / 重放 / Fuzz 里）；
/// - 请只在与你有授权关系的目标上使用（你自己的系统，或已获书面授权的目标）。
///   未授权对他人系统尝试绕过防护措施，可能触犯法律。
///
/// 为什么它有用：WAF 靠「正则匹配 + 规范化」拦流量，而很多语法的**等价写法**
/// 没被规则覆盖（比如 SQL 的空白可以用注释代替、关键字可以大小写混写）。
/// 变异的目的就是把这些等价写法摊开给你看，用于**验证你自己的 WAF 规则够不够**。
class WafBypass {
  WafBypass._();

  /// 全部技术
  static const List<WafTechnique> techniques = [
    WafTechnique('url_encode', 'URL 编码', '空格等特殊字符转 %XX，绕过按原文匹配的规则'),
    WafTechnique('double_url', '双重 URL 编码', '把 % 也编码成 %25，针对只解码一次的 WAF'),
    WafTechnique('unicode', 'Unicode 编码', '转成 \\uXXXX，针对不处理 Unicode 的解析链'),
    WafTechnique('case_mix', '大小写混用', 'SeLeCt —— 针对区分大小写的正则'),
    WafTechnique('comment_split', '注释分割', '用 /**/ 替掉空白，SQL 里等价于空格'),
    WafTechnique('comment_wrap', '内联注释包裹', '/*!50000select*/ —— MySQL 会执行注释里的内容'),
    WafTechnique('whitespace_alt', '空白替换', '空格换 %09/%0a/%0c/+/() 等等价物'),
    WafTechnique('double_write', '关键字双写', 'oorr → or —— 针对只替换一次的过滤器'),
    WafTechnique('keyword_replace', '等价关键字', 'and→&&、or→||、=→like 等语义等价替换'),
    WafTechnique('quote_escape', '引号变形', '单引号/双引号/反引号互换与转义'),
    WafTechnique('concat_string', '字符串拼接', "'a'||'b' / CONCAT —— 绕过对整串字面量的匹配"),
    WafTechnique('newline_inject', '换行/分块注入', '在关键字中间插入换行或 %0d%0a'),
    WafTechnique('chunked', '分块编码', 'HTTP chunked 形式切开载荷'),
    WafTechnique('hpp', '参数污染 (HPP)', '同名参数重复，利用前后端取值不一致'),
    WafTechnique('base64_wrap', 'Base64 包装', '把载荷整体 base64，针对 WAF 之后才解码的场景'),
    WafTechnique('hex_wrap', '十六进制包装', '0x... 形式（数据库层面等价）'),
  ];

  static final Map<String, String Function(String)> _handlers = {
    'url_encode': (s) => Uri.encodeComponent(s),
    'double_url': (s) => Uri.encodeComponent(Uri.encodeComponent(s)),
    'unicode': (s) => s.runes.map((r) => '\\u${r.toRadixString(16).padLeft(4, '0')}').join(),
    'case_mix': _caseMix,
    'comment_split': (s) => s.replaceAll(RegExp(r'\s+'), '/**/'),
    'comment_wrap': (s) => s.replaceAllMapped(
        RegExp(r'[A-Za-z]{2,}'), (m) => '/*!50000${m[0]}*/'),
    'whitespace_alt': (s) => s.replaceAll(' ', '%09'),
    'double_write': _doubleWrite,
    'keyword_replace': _keywordReplace,
    'quote_escape': (s) => s.replaceAll("'", '`').replaceAll('"', "'"),
    'concat_string': (s) => "'${s.replaceAll("'", "'||'")}'",
    'newline_inject': (s) => s.replaceAllMapped(RegExp(r'[A-Za-z]{3,}'),
        (m) => '${m[0].substring(0, 1)}\n${m[0].substring(1)}'),
    'chunked': (s) {
      final bytes = utf8.encode(s);
      if (bytes.isEmpty) {
        return '0\r\n\r\n';
      }
      // 每 4 字节一块的 chunked 形式
      final sb = StringBuffer();
      for (var i = 0; i < bytes.length; i += 4) {
        final end = (i + 4 > bytes.length) ? bytes.length : i + 4;
        final chunk = bytes.sublist(i, end);
        sb.write('${chunk.length.toRadixString(16)}\r\n');
        sb.write(utf8.decode(chunk, allowMalformed: true));
        sb.write('\r\n');
      }
      sb.write('0\r\n\r\n');
      return sb.toString();
    },
    'hpp': (s) => s.contains('=')
        ? s.replaceAllMapped(RegExp(r'([^&]+)=([^&]*)'), (m) => '${m[1]}=${m[2]}&${m[1]}=')
        : s,
    'base64_wrap': (s) => base64.encode(utf8.encode(s)),
    'hex_wrap': (s) => '0x${utf8.encode(s).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
  };

  /// 大小写混用：交替大小写（对英文关键字有效）
  static String _caseMix(String input) {
    final sb = StringBuffer();
    var upper = false;
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      if (RegExp(r'[A-Za-z]').hasMatch(ch)) {
        sb.write(upper ? ch.toUpperCase() : ch.toLowerCase());
        upper = !upper;
      } else {
        sb.write(ch);
      }
    }
    return sb.toString();
  }

  /// 关键字双写：oorr、seselectlect —— 过滤一次后正好还原
  static String _doubleWrite(String input) {
    const keywords = ['or', 'and', 'select', 'union', 'from', 'where', 'exec', 'script'];
    var out = input;
    for (final kw in keywords) {
      final re = RegExp(kw, caseSensitive: false);
      out = out.replaceAllMapped(re, (m) {
        // 每个字符重复一次："or" → "oorr"
        return m[0]!.split('').map((c) => '$c$c').join();
      });
    }
    return out;
  }

  /// 语义等价的关键字替换
  static String _keywordReplace(String input) {
    var out = input;
    const pairs = {
      ' and ': ' && ',
      ' or ': ' || ',
      ' AND ': ' && ',
      ' OR ': ' || ',
    };
    for (final entry in pairs.entries) {
      out = out.replaceAll(entry.key, entry.value);
    }
    return out;
  }

  /// 对一条载荷应用若干技术（按给定顺序叠加）。
  static List<WafVariant> mutate(String payload, List<String> techniqueIds) {
    final out = <WafVariant>[];
    var current = payload;
    for (final id in techniqueIds) {
      final tech = techniques.where((t) => t.id == id).toList();
      if (tech.isEmpty) {
        continue;
      }
      current = tech.first.apply(current);
    }
    if (techniqueIds.isNotEmpty) {
      out.add(WafVariant(
        technique: techniqueIds.join(' + '),
        name: '组合结果（按选择顺序叠加）',
        output: current,
      ));
    }
    // 单项结果也一并给出，方便挑一个够用的
    for (final id in techniqueIds) {
      final tech = techniques.where((t) => t.id == id).toList();
      if (tech.isEmpty) {
        continue;
      }
      out.add(WafVariant(
        technique: tech.first.id,
        name: tech.first.name,
        output: tech.first.apply(payload),
        note: tech.first.description,
      ));
    }
    return out;
  }

  /// 一次生成全部技术的对比结果。
  static List<WafVariant> mutateAll(String payload) {
    return techniques
        .map((t) => WafVariant(
              technique: t.id,
              name: t.name,
              output: t.apply(payload),
              note: t.description,
            ))
        .toList();
  }

  // ---------- 指纹（被动比对，不发请求） ----------

  /// 常见 WAF 的响应特征。用**你已经抓到的**响应去比对，不主动探测。
  static const Map<String, List<String>> fingerprints = {
    'Cloudflare': ['cf-ray', 'cloudflare', '__cfduid', 'cf-mitigated'],
    'AWS WAF': ['awselb', 'x-amzn-requestid', 'awswaf'],
    'Akamai': ['akamai', 'akamaighost', 'x-akamai'],
    '阿里云 WAF': ['aliyungf', 'aliyun', 'yundun', 'blocked by aliyun'],
    '腾讯云 WAF': ['tencent', 'waf.tencent', 'stgw'],
    'ModSecurity': ['mod_security', 'modsecurity', '406 not acceptable'],
    'F5 BIG-IP': ['bigip', 'f5', 'tscookie', 'x-wa-info'],
    'Imperva': ['imperva', 'incapsula', 'visid_incap', 'x-iinfo'],
    'Sucuri': ['sucuri', 'x-sucuri-id'],
    'Fortinet FortiWeb': ['fortiweb', 'fortigate', 'fwsid'],
    '安全狗': ['safedog', 'waf/2.0', 'safedog-flow'],
    'D盾': ['d盾', 'dsafe'],
  };

  /// 用一份响应（头 + 正文片段）推断可能的 WAF。返回命中的名称列表。
  static List<String> detectFrom(String responseText) {
    final lower = responseText.toLowerCase();
    final hits = <String>[];
    fingerprints.forEach((waf, markers) {
      if (markers.any((m) => lower.contains(m.toLowerCase()))) {
        hits.add(waf);
      }
    });
    return hits;
  }

  /// 针对某类 WAF 的推荐技术组合。
  static List<String> suggestFor(String waf) {
    switch (waf) {
      case 'Cloudflare':
        return ['url_encode', 'case_mix', 'comment_split', 'whitespace_alt'];
      case 'ModSecurity':
        return ['comment_split', 'comment_wrap', 'case_mix', 'double_write'];
      case '阿里云 WAF':
      case '腾讯云 WAF':
      case '安全狗':
        return ['double_url', 'comment_split', 'keyword_replace', 'hpp'];
      case 'F5 BIG-IP':
        return ['whitespace_alt', 'case_mix', 'newline_inject'];
      case 'AWS WAF':
        return ['url_encode', 'hpp', 'case_mix'];
      default:
        return ['url_encode', 'comment_split', 'case_mix'];
    }
  }
}
