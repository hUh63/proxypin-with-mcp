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

/// 不可见字符扫描：用于「显示 ASCII 控制字符 / Unicode 特殊字符」的着色与检测报告。

enum SpecialCharKind {
  /// ASCII 空格 / 控制字符（0x00-0x1F、0x20、0x7F）
  ascii,

  /// 零宽、方向控制、特殊空白等 Unicode 字符
  unicode,
}

class SpecialCharHit {
  /// 在全文中的 utf16 下标
  final int index;

  /// 码点
  final int code;

  final SpecialCharKind kind;

  const SpecialCharHit(this.index, this.code, this.kind);
}

class SpecialCharScanner {
  SpecialCharScanner._();

  /// 换行符本身不参与可视化（它是结构，不是"隐藏的内容"）。
  static const int _lf = 0x0A;

  /// 是否 ASCII 空白 / 控制字符（含空格、制表、退格、垂直制表等）。
  static bool isAscii(int code) {
    if (code == _lf) return false;
    return code == 0x20 || code < 0x20 || code == 0x7F;
  }

  /// 是否 Unicode 特殊字符：零宽 / 方向控制 / 非常规空白 / BOM / 私用区等。
  ///
  /// 这些字符大部分字体都没有对应字形，直接显示就是一格空白或直接消失，
  /// 是"看起来一样但实际不同"的常见坑（尤其是从网页复制来的文本）。
  static bool isUnicode(int code) {
    // 零宽与格式字符
    if (code >= 0x200B && code <= 0x200F) return true; // ZWSP/ZWNJ/ZWJ/LRM/RLM
    if (code >= 0x202A && code <= 0x202E) return true; // 方向控制
    if (code >= 0x2060 && code <= 0x2064) return true; // word joiner / 不可见操作符
    if (code >= 0x2066 && code <= 0x2069) return true; // 方向隔离
    if (code == 0xFEFF) return true; // BOM / 零宽不换行空格
    if (code == 0x180E) return true; // 蒙古文元音分隔符

    // 非常规空白
    if (code == 0x00A0) return true; // NBSP
    if (code == 0x1680) return true; // Ogham 空格
    if (code >= 0x2000 && code <= 0x200A) return true; // en/em/thin/hair 空格
    if (code == 0x2028 || code == 0x2029) return true; // 行 / 段分隔符
    if (code == 0x202F) return true; // narrow NBSP
    if (code == 0x205F) return true; // medium math space
    if (code == 0x3000) return true; // 全角空格
    if (code == 0x0085) return true; // NEL

    // 私用区
    if (code >= 0xE000 && code <= 0xF8FF) return true;
    if (code >= 0xF0000 && code <= 0xFFFFD) return true;
    if (code >= 0x100000 && code <= 0x10FFFD) return true;

    return false;
  }

  /// 扫描 [text] 里指定类别（[ascii] / [unicode]）的所有不可见字符。
  ///
  /// 返回按出现顺序排列的命中列表；[limit] 用于避免超长文本把结果撑爆。
  static List<SpecialCharHit> scan(String text, {bool ascii = true, bool unicode = true, int limit = 20000}) {
    final hits = <SpecialCharHit>[];
    if (text.isEmpty) return hits;
    if (!ascii && !unicode) return hits;

    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      // 代理对（emoji 等）跳过低位，避免把正常字符误判
      if (code >= 0xD800 && code <= 0xDBFF) {
        i++;
        continue;
      }
      if (ascii && isAscii(code)) {
        hits.add(SpecialCharHit(i, code, SpecialCharKind.ascii));
      } else if (unicode && isUnicode(code)) {
        hits.add(SpecialCharHit(i, code, SpecialCharKind.unicode));
      }
      if (hits.length >= limit) break;
    }
    return hits;
  }

  /// 把码点渲染成可读的记号，如 `0x09 TAB`、`U+3000 全角空格`。
  static String describe(int code) {
    final hex = code.toRadixString(16).toUpperCase().padLeft(4, '0');
    return 'U+$hex ${_name(code)}';
  }

  static String _name(int code) {
    switch (code) {
      case 0x00:
        return 'NUL';
      case 0x07:
        return 'BEL';
      case 0x08:
        return 'BS';
      case 0x09:
        return 'TAB';
      case 0x0A:
        return 'LF';
      case 0x0B:
        return 'VT';
      case 0x0C:
        return 'FF';
      case 0x0D:
        return 'CR';
      case 0x1B:
        return 'ESC';
      case 0x20:
        return 'SPACE';
      case 0x7F:
        return 'DEL';
      case 0x00A0:
        return 'NBSP';
      case 0x200B:
        return 'ZWSP';
      case 0x200C:
        return 'ZWNJ';
      case 0x200D:
        return 'ZWJ';
      case 0x2028:
        return 'LS';
      case 0x2029:
        return 'PS';
      case 0x3000:
        return 'IDEOGRAPHIC SPACE';
      case 0xFEFF:
        return 'BOM/ZWNBSP';
    }
    return '';
  }
}
