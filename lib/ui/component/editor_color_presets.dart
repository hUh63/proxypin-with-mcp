/*
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

import 'package:flutter/material.dart';

/// 编辑器的「配色方案」。
///
/// 默认的 auto 沿用 atom-one（token 色）+ App 主题底色；另外三套直接取自
/// sora-editor Demo 里的 TextMate 主题（VS Code 同款 scope 配色），
/// 好处是换个配色就能一眼看出这是「编辑器配色」而不是「App 主题」——
/// 深色方案自带暗底，浅色方案自带白底，不会出现 token 色跟底色打架。
enum EditorColorPreset { auto, quietLight, solarizedDark, ayuDark }

/// 当前选中的配色方案。
///
/// 单独用 ValueNotifier 而不是挂在 TextEditorPrefs 上：`editorThemeOf(context)`
/// 在十几个页面里被调用，让它去依赖 toolbox 层的 prefs 会把组件层和编辑器层绑死。
final ValueNotifier<EditorColorPreset> editorColorPresetNotifier =
    ValueNotifier<EditorColorPreset>(EditorColorPreset.auto);

EditorColorPreset editorColorPresetOf(String name) => EditorColorPreset.values.firstWhere(
      (e) => e.name == name,
      orElse: () => EditorColorPreset.auto,
    );

String editorColorPresetName(EditorColorPreset p) => p.name;

String editorColorPresetLabel(EditorColorPreset p) {
  switch (p) {
    case EditorColorPreset.auto:
      return 'Auto';
    case EditorColorPreset.quietLight:
      return 'Quiet Light';
    case EditorColorPreset.solarizedDark:
      return 'Solarized Dark';
    case EditorColorPreset.ayuDark:
      return 'Ayu Dark';
  }
}

Color _c(String hex, [double alpha = 1]) {
  final v = hex.replaceFirst('#', '');
  final rgb = int.parse(v.substring(0, 6), radix: 16);
  return Color(rgb | 0xFF000000).withValues(alpha: alpha);
}

/// Quiet Light
const Map<String, (String, bool)> _quietLightColors = {
  'comment': ('#AAAAAA', true),
  'keyword': ('#7A3E9D', false),
  'string': ('#448C27', false),
  'number': ('#9C5D27', false),
  'literal': ('#448C27', false),
  'function': ('#AA3731', false),
  'type': ('#9C5D27', false),
  'variable': ('#7A3E9D', false),
  'tag': ('#7A3E9D', false),
  'attribute': ('#8190A0', false),
  'operator': ('#777777', false),
  'meta': ('#333333', false),
};

/// Solarized Dark
const Map<String, (String, bool)> _solarizedDarkColors = {
  'comment': ('#586E75', true),
  'keyword': ('#CB4B16', false),
  'string': ('#DC322F', false),
  'number': ('#D33682', false),
  'literal': ('#CB4B16', false),
  'function': ('#268BD2', false),
  'type': ('#CB4B16', false),
  'variable': ('#859900', false),
  'tag': ('#268BD2', false),
  'attribute': ('#93A1A1', false),
  'operator': ('#93A1A1', false),
  'meta': ('#268BD2', true),
};

/// Ayu Dark
const Map<String, (String, bool)> _ayuDarkColors = {
  'comment': ('#ACB6BF', true),
  'keyword': ('#E6B673', false),
  'string': ('#39BAE6', false),
  'number': ('#FF8F40', false),
  'literal': ('#F29668', false),
  'function': ('#F07178', false),
  'type': ('#39BAE6', false),
  'variable': ('#FFB454', false),
  'tag': ('#59C2FF', false),
  'attribute': ('#FFB454', false),
  'operator': ('#F29668', false),
  'meta': ('#ACB6BF', false),
};

/// 把一套配色展开成 re_highlight 认识的主题表。
///
/// re_highlight 的 key 比 TextMate 的 scope 粗，这里做一次向下映射：
/// 一个 token 组没单独配色的，就近取一个语义相近的 key，避免出现
/// 「关键字有颜色、内置函数是纯黑」这种断层。
Map<String, TextStyle> editorPresetThemeOf(EditorColorPreset preset) {
  final table = switch (preset) {
    EditorColorPreset.quietLight => _quietLightColors,
    EditorColorPreset.solarizedDark => _solarizedDarkColors,
    EditorColorPreset.ayuDark => _ayuDarkColors,
    EditorColorPreset.auto => _quietLightColors,
  };
  final bg = switch (preset) {
    EditorColorPreset.quietLight => '#F5F5F5',
    EditorColorPreset.solarizedDark => '#002B36',
    EditorColorPreset.ayuDark => '#0D1017',
    EditorColorPreset.auto => '#FFFFFF',
  };
  final fg = switch (preset) {
    EditorColorPreset.quietLight => '#333333',
    EditorColorPreset.solarizedDark => '#839496',
    EditorColorPreset.ayuDark => '#BFBDB6',
    EditorColorPreset.auto => '#000000',
  };

  TextStyle styleOf(String key, {bool bold = false}) {
    final entry = table[key];
    if (entry == null) return TextStyle(color: _c(fg));
    return TextStyle(
      color: _c(entry.$1),
      fontStyle: entry.$2 ? FontStyle.italic : FontStyle.normal,
      fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
    );
  }

  // 语义相近的 key 复用同一份颜色，保证每种 token 都有明确颜色。
  final aliases = <String, String>{
    'root': 'meta',
    'built_in': 'function',
    'symbol': 'number',
    'class': 'type',
    'title': 'function',
    'section': 'function',
    'subst': 'string',
    'params': 'meta',
    'name': 'meta',
    'attr': 'attribute',
    'property': 'attribute',
    'selector-tag': 'tag',
    'selector-id': 'tag',
    'selector-class': 'tag',
    'selector-attr': 'attribute',
    'selector-pseudo': 'keyword',
    'template-tag': 'tag',
    'template-variable': 'variable',
    'regexp': 'string',
    'addition': 'string',
    'deletion': 'invalid',
    'bullet': 'keyword',
    'link': 'meta',
    'quote': 'comment',
    'code': 'string',
    'doctag': 'comment',
    'strong': 'keyword',
    'emphasis': 'meta',
    'formula': 'meta',
  };

  final theme = <String, TextStyle>{};
  for (final entry in aliases.entries) {
    theme[entry.key] = styleOf(entry.value, bold: entry.key == 'strong');
  }
  for (final key in table.keys) {
    theme[key] = styleOf(key);
  }
  theme['root'] = TextStyle(color: _c(fg), backgroundColor: _c(bg));
  return theme;
}
