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

import 'dart:math' as math;

import 'code_keywords.dart';

/// 「上下文 + 代码格式」感知的本地补全候选。
///
/// 编辑器内核的本地补全会把「文档里出现过的词」和宿主注入的关键字一起匹配；
/// 这里再往前一步：**根据光标此刻所处的语法位置**给出更贴合当下要写什么的候选。
///
/// * JSON：在 key 位置补文档里已有的 key；在值位置补 `true`/`false`/`null`；
/// * XML / HTML：`<` 后补文档里出现过的标签名，`</` 后补**还没闭合**的标签，
///   标签内部补文档里用过的属性名；
/// * YAML：补文档里已有的 key；
/// * 其它语言：按**缩进**判断你在行首还是块内，把声明类 / 语句类关键字分别提前。
///
/// 返回的候选由内核插到普通候选之前，并保持这里的先后顺序。
class SmartSuggestions {
  SmartSuggestions._();

  /// 扫描文档时最多回看的字符数，避免超大文档拖慢输入。
  static const int _maxScan = 120000;

  /// 一次最多返回的候选数。
  static const int _maxItems = 60;

  /// 语言无关的「声明类」关键字：常见于行首 / 无缩进处。
  static const Set<String> _declarationWords = {
    'class', 'interface', 'enum', 'struct', 'type', 'typedef', 'function', 'func', 'def',
    'const', 'let', 'var', 'final', 'static', 'public', 'private', 'protected', 'internal',
    'abstract', 'declare', 'namespace', 'package', 'import', 'export', 'include', 'extends',
    'implements', 'async', 'await', 'factory', 'operator', 'extension',
    'CREATE', 'TABLE', 'INDEX', 'VIEW', 'ALTER', 'INSERT',
  };

  /// 语言无关的「语句类」关键字：常见于缩进块内。
  static const Set<String> _statementWords = {
    'if', 'else', 'elif', 'for', 'while', 'do', 'switch', 'case', 'default', 'break',
    'continue', 'return', 'try', 'catch', 'except', 'finally', 'throw', 'raise', 'yield',
    'delete', 'print', 'echo', 'with', 'in', 'of', 'is',
    'SELECT', 'FROM', 'WHERE', 'JOIN', 'ON', 'GROUP', 'BY', 'ORDER', 'HAVING', 'LIMIT',
  };

  /// 生成候选。
  ///
  /// [language] 为编辑器当前的语法名（如 `JSON`、`XML / HTML`、`Dart`）；
  /// [documentText] 是整篇文档；[linePrefix] 是光标所在行、光标之前的文本；
  /// [prefix] 是光标前正在输入的那个词的前缀。
  static List<String> suggest({
    required String? language,
    required String documentText,
    required String linePrefix,
    required String prefix,
  }) {
    switch (language ?? '') {
      case 'JSON':
        return _json(documentText, linePrefix, prefix);
      case 'XML / HTML':
        return _xml(documentText, linePrefix, prefix);
      case 'YAML':
        return _yaml(documentText, prefix);
      case 'CSS':
        return _css(documentText, linePrefix, prefix);
      case 'HTTP':
        return _http(documentText, linePrefix, prefix);
      case 'Markdown':
        return _markdown(documentText, linePrefix, prefix);
      default:
        return _generic(documentText, linePrefix, prefix, language ?? '');
    }
  }

  // ---------------------------------------------------------------------------
  // JSON
  // ---------------------------------------------------------------------------

  static List<String> _json(String doc, String linePrefix, String prefix) {
    final trimmed = linePrefix.trimRight();
    // 值位置：`"key":` 之后（冒号后还没写值）。
    if (RegExp(r':\s*$').hasMatch(trimmed)) {
      return _dedupe(const ['true', 'false', 'null'], prefix);
    }
    // key 位置（行首、`{`、`,`、`"` 之后）：补文档里已有的 key。
    return _dedupe(_jsonKeys(doc), prefix);
  }

  static final RegExp _jsonKeyRe = RegExp(r'"((?:[^"\\\n]|\\.){1,80})"\s*:');

  static List<String> _jsonKeys(String doc) {
    final out = <String>[];
    for (final m in _jsonKeyRe.allMatches(_tail(doc))) {
      out.add(m.group(1)!);
      if (out.length > 400) break;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // XML / HTML
  // ---------------------------------------------------------------------------

  static List<String> _xml(String doc, String linePrefix, String prefix) {
    final tail = _tail(doc);
    final trimmed = linePrefix.trimRight();
    final lt = trimmed.lastIndexOf('<');
    final gt = trimmed.lastIndexOf('>');
    // 光标是否落在一个还没闭合的 `<...` 里面。
    final inTag = lt > gt;
    if (!inTag) {
      // 不在标签里（比如刚写完文本），补文档里出现过的标签名。
      return _dedupe(_xmlTags(tail), prefix);
    }
    final inTagText = trimmed.substring(lt);
    if (inTagText.startsWith('</')) {
      // 闭合标签：补还没有配对的标签，最近打开的最靠前。
      return _dedupe(_unclosedTags(tail), prefix);
    }
    // class="..." 里面：补 Tailwind 之类的常用类名。
    if (_htmlClassRe.hasMatch(trimmed)) {
      return _dedupe(_tailwind, prefix);
    }
    // 标签名之后（出现空白）就是属性位置。
    if (RegExp(r'^<\s*[A-Za-z_][\w:.-]*\s+[^>]*$').hasMatch(inTagText)) {
      final tagName =
          RegExp(r'^<\s*([A-Za-z_][\w:.-]*)').firstMatch(inTagText)?.group(1) ?? '';
      // SVG 元素优先给 SVG 专用属性（viewBox / d / fill / stroke ...）。
      if (_svgTags.contains(tagName.toLowerCase())) {
        return _dedupe([
          ..._xmlAttrs(tail),
          ..._svgAttrs,
          ..._vueAttrs,
          ..._reactAttrs,
          ..._commonAttrs,
        ], prefix);
      }
      return _dedupe([
        ..._xmlAttrs(tail),
        ..._vueAttrs,
        ..._reactAttrs,
        ..._commonAttrs,
      ], prefix);
    }
    return _dedupe([..._xmlTags(tail), ..._commonTags], prefix);
  }

  static final RegExp _htmlClassRe = RegExp(r'''class\s*=\s*["'][^"']*$''');

  /// Vue 指令 / 常用属性（`v-*`、`:` 简写、`@` 简写）。
  static const List<String> _vueAttrs = [
    'v-if', 'v-else', 'v-else-if', 'v-for', 'v-show', 'v-model', 'v-model.lazy',
    'v-model.number', 'v-model.trim', 'v-bind', 'v-on', 'v-once', 'v-pre', 'v-cloak',
    'v-html', 'v-text', 'v-slot', 'is', 'ref', 'key', 'slot', 'slot-scope', 'name',
    'components', 'props', 'emits', 'setup', 'data', 'methods', 'computed', 'watch',
    'directives', 'transition', 'keep-alive',
    ':key', ':class', ':style', ':src', ':href', ':disabled', ':value', ':id', ':type',
    '@click', '@input', '@change', '@submit', '@keyup', '@keydown', '@focus', '@blur',
    '@mouseenter', '@mouseleave',
  ];

  /// React / JSX 常用属性。
  static const List<String> _reactAttrs = [
    'className', 'htmlFor', 'key', 'ref', 'style', 'children', 'dangerouslySetInnerHTML',
    'onClick', 'onChange', 'onInput', 'onSubmit', 'onFocus', 'onBlur', 'onKeyDown',
    'onKeyUp', 'onKeyPress', 'onMouseEnter', 'onMouseLeave', 'onDoubleClick', 'onScroll',
    'value', 'defaultValue', 'checked', 'defaultChecked', 'disabled', 'readOnly',
    'required', 'autoFocus', 'autoComplete', 'placeholder', 'type', 'name', 'id', 'src',
    'href', 'alt', 'width', 'height', 'target', 'rel', 'role', 'data-testid',
    'aria-label', 'aria-hidden', 'suppressContentEditableWarning',
  ];

  /// SVG 元素用的标签名。
  static const Set<String> _svgTags = {
    'svg', 'g', 'defs', 'symbol', 'use', 'path', 'rect', 'circle', 'ellipse', 'line',
    'polyline', 'polygon', 'text', 'tspan', 'textpath', 'image', 'marker', 'pattern',
    'mask', 'clippath', 'lineargradient', 'radialgradient', 'stop', 'filter', 'feblend',
    'fegaussianblur', 'feoffset', 'femerge', 'femergenode', 'fecolormatrix', 'view',
    'switch', 'foreignobject', 'title', 'desc', 'metadata', 'animate', 'animatetransform',
    'animatemotion', 'set',
  };

  /// SVG 专用属性。
  static const List<String> _svgAttrs = [
    'viewBox', 'xmlns', 'xmlns:xlink', 'width', 'height', 'x', 'y', 'x1', 'y1', 'x2', 'y2',
    'cx', 'cy', 'r', 'rx', 'ry', 'fx', 'fy', 'd', 'points', 'transform', 'fill',
    'fill-opacity', 'fill-rule', 'stroke', 'stroke-width', 'stroke-opacity',
    'stroke-linecap', 'stroke-linejoin', 'stroke-dasharray', 'stroke-dashoffset', 'opacity',
    'gradientUnits', 'gradientTransform', 'offset', 'stop-color', 'stop-opacity',
    'preserveAspectRatio', 'xlink:href', 'href', 'font-size', 'font-family', 'font-weight',
    'text-anchor', 'dominant-baseline', 'clip-path', 'mask', 'filter', 'clipPathUnits',
    'maskUnits', 'patternUnits', 'markerWidth', 'markerHeight', 'markerUnits', 'refX', 'refY',
    'orient', 'marker-start', 'marker-mid', 'marker-end', 'vector-effect', 'shape-rendering',
    'textLength', 'lengthAdjust', 'focusable', 'aria-hidden', 'role',
  ];

  /// Tailwind 常用类名（HTML 的 class 属性 / CSS 的 @apply 里都会用到）。
  static const List<String> _tailwind = [
    'container', 'block', 'inline-block', 'inline', 'flex', 'inline-flex', 'grid', 'hidden',
    'flex-row', 'flex-col', 'flex-wrap', 'flex-nowrap', 'flex-1', 'grow', 'shrink-0',
    'items-center', 'items-start', 'items-end', 'items-stretch', 'items-baseline',
    'justify-center', 'justify-between', 'justify-around', 'justify-evenly', 'justify-end',
    'justify-start', 'content-center', 'self-center', 'self-start', 'self-end',
    'grid-cols-1', 'grid-cols-2', 'grid-cols-3', 'grid-cols-4', 'grid-cols-6', 'grid-cols-12',
    'col-span-1', 'col-span-2', 'col-span-3', 'col-span-full',
    'gap-1', 'gap-2', 'gap-3', 'gap-4', 'gap-6', 'gap-8',
    'static', 'relative', 'absolute', 'fixed', 'sticky', 'inset-0', 'top-0', 'right-0',
    'bottom-0', 'left-0', 'z-10', 'z-20', 'z-50',
    'overflow-hidden', 'overflow-auto', 'overflow-scroll', 'overflow-visible',
    'w-full', 'w-1/2', 'w-1/3', 'w-2/3', 'w-1/4', 'w-screen', 'w-auto', 'w-fit', 'w-max',
    'h-full', 'h-screen', 'h-auto', 'h-fit', 'min-w-0', 'max-w-xs', 'max-w-sm', 'max-w-md',
    'max-w-lg', 'max-w-xl', 'max-w-2xl', 'max-w-full',
    'm-0', 'm-1', 'm-2', 'm-3', 'm-4', 'm-6', 'm-8', 'm-auto', 'mx-auto', 'my-auto',
    'mt-1', 'mt-2', 'mt-4', 'mb-2', 'mb-4', 'ml-2', 'mr-2',
    'p-0', 'p-1', 'p-2', 'p-3', 'p-4', 'p-6', 'p-8',
    'px-2', 'px-3', 'px-4', 'px-6', 'py-1', 'py-2', 'py-3', 'py-4', 'pt-2', 'pb-2', 'pl-2', 'pr-2',
    'text-xs', 'text-sm', 'text-base', 'text-lg', 'text-xl', 'text-2xl', 'text-3xl', 'text-4xl',
    'font-thin', 'font-light', 'font-normal', 'font-medium', 'font-semibold', 'font-bold',
    'font-extrabold', 'italic', 'not-italic', 'underline', 'no-underline', 'line-through',
    'uppercase', 'lowercase', 'capitalize', 'truncate',
    'text-left', 'text-center', 'text-right', 'text-justify',
    'leading-none', 'leading-tight', 'leading-normal', 'leading-relaxed', 'leading-loose',
    'tracking-tight', 'tracking-normal', 'tracking-wide',
    'whitespace-nowrap', 'whitespace-pre', 'break-words', 'break-all',
    'text-black', 'text-white', 'text-gray-400', 'text-gray-500', 'text-gray-700',
    'text-gray-900', 'text-blue-500', 'text-blue-600', 'text-red-500', 'text-green-500',
    'bg-white', 'bg-black', 'bg-transparent', 'bg-gray-50', 'bg-gray-100', 'bg-gray-200',
    'bg-gray-800', 'bg-gray-900', 'bg-blue-500', 'bg-blue-600', 'bg-red-500', 'bg-green-500',
    'bg-yellow-400',
    'border', 'border-0', 'border-2', 'border-t', 'border-b', 'border-b-2', 'border-gray-200',
    'border-gray-300', 'border-transparent', 'rounded', 'rounded-md', 'rounded-lg',
    'rounded-xl', 'rounded-full', 'shadow', 'shadow-sm', 'shadow-md', 'shadow-lg', 'shadow-xl',
    'shadow-none', 'opacity-0', 'opacity-50', 'opacity-100',
    'cursor-pointer', 'cursor-not-allowed', 'select-none',
    'transition', 'transition-colors', 'duration-150', 'duration-200', 'duration-300',
    'ease-in-out', 'animate-spin', 'animate-pulse',
    'hover:bg-gray-100', 'hover:opacity-80', 'focus:outline-none', 'dark:bg-gray-900',
  ];

  /// HTML5 常用标签，用于 `<` 之后没什么可参考时的兜底。
  static const List<String> _commonTags = [
    'html', 'head', 'body', 'title', 'meta', 'link', 'script', 'style', 'base', 'noscript',
    'div', 'span', 'p', 'a', 'img', 'br', 'hr', 'strong', 'em', 'b', 'i', 'u', 's', 'small',
    'sub', 'sup', 'mark', 'code', 'pre', 'kbd', 'samp', 'var', 'q', 'blockquote', 'cite',
    'abbr', 'address', 'time', 'wbr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'ul', 'ol', 'li', 'dl', 'dt', 'dd', 'table', 'thead', 'tbody', 'tfoot', 'tr', 'th', 'td',
    'caption', 'colgroup', 'col', 'form', 'input', 'textarea', 'button', 'select', 'option',
    'optgroup', 'label', 'fieldset', 'legend', 'datalist', 'output', 'progress', 'meter',
    'header', 'nav', 'main', 'section', 'article', 'aside', 'footer', 'figure', 'figcaption',
    'details', 'summary', 'dialog', 'template', 'canvas', 'svg', 'video', 'audio', 'source',
    'track', 'iframe', 'embed', 'object', 'param', 'picture', 'map', 'area',
    'item', 'value', 'name', 'entry', 'id', 'type', 'label',
  ];

  /// 常见属性名，用于标签内部的兜底。
  static const List<String> _commonAttrs = [
    'id', 'name', 'class', 'type', 'value', 'href', 'src', 'title', 'style', 'width',
    'height', 'target', 'rel', 'placeholder', 'disabled', 'checked', 'selected', 'readonly',
    'required', 'autofocus', 'multiple', 'min', 'max', 'step', 'pattern', 'for', 'action',
    'method', 'alt', 'role', 'tabindex', 'lang', 'dir', 'charset', 'srcset', 'loading',
    'decoding', 'poster', 'controls', 'loop', 'muted', 'preload', 'crossorigin', 'integrity',
    'download', 'hreflang', 'contenteditable', 'draggable', 'hidden', 'colspan', 'rowspan',
    'xmlns', 'version',
  ];

  static final RegExp _xmlTagRe = RegExp(r'<\s*/?\s*([A-Za-z_][\w:.-]*)');
  static final RegExp _xmlAttrRe = RegExp(r'\s([A-Za-z_][\w:.-]*)\s*=');
  static final RegExp _xmlPairRe = RegExp(
    r'''<\s*(/?)\s*([A-Za-z_][\w:.-]*)((?:"[^"]*"|'[^']*'|[^>])*)>''',
  );

  static List<String> _xmlTags(String doc) {
    final out = <String>[];
    for (final m in _xmlTagRe.allMatches(doc)) {
      out.add(m.group(1)!);
      if (out.length > 400) break;
    }
    return out;
  }

  static List<String> _xmlAttrs(String doc) {
    final out = <String>[];
    for (final m in _xmlAttrRe.allMatches(doc)) {
      out.add(m.group(1)!);
      if (out.length > 200) break;
    }
    return out;
  }

  /// 文档里「开了还没关」的标签，最近打开的排在最前。
  static List<String> _unclosedTags(String doc) {
    const voidTags = {
      'br', 'img', 'input', 'meta', 'link', 'hr', 'area', 'base', 'col', 'embed',
      'source', 'track', 'wbr',
    };
    final stack = <String>[];
    for (final m in _xmlPairRe.allMatches(doc)) {
      final closing = (m.group(1) ?? '') == '/';
      final name = m.group(2)!;
      final rest = m.group(3) ?? '';
      if (closing) {
        final at = stack.lastIndexOf(name);
        if (at >= 0) stack.removeRange(at, stack.length);
      } else if (!rest.trimRight().endsWith('/') &&
          !voidTags.contains(name.toLowerCase())) {
        stack.add(name);
      }
    }
    return stack.reversed.toList();
  }

  // ---------------------------------------------------------------------------
  // YAML
  // ---------------------------------------------------------------------------

  static final RegExp _yamlKeyRe = RegExp(r'^[ \t-]*([A-Za-z_][\w.\-]*)\s*:', multiLine: true);

  static List<String> _yaml(String doc, String prefix) {
    final out = <String>[];
    for (final m in _yamlKeyRe.allMatches(_tail(doc))) {
      out.add(m.group(1)!);
      if (out.length > 400) break;
    }
    return _dedupe(out, prefix);
  }

  // ---------------------------------------------------------------------------
  // CSS
  // ---------------------------------------------------------------------------

  static List<String> _css(String doc, String linePrefix, String prefix) {
    final tail = _tail(doc);
    final trimmed = linePrefix.trimRight();

    // @apply 后面接的是类名（Tailwind 等），给常用类名。
    if (_cssApplyRe.hasMatch(trimmed)) {
      return _dedupe(_tailwind, prefix);
    }

    // at-rule：正在敲 `@media` 这类开头。
    final at = trimmed.lastIndexOf('@');
    if (at >= 0 && !RegExp(r'[\s;{)]').hasMatch(trimmed.substring(at))) {
      return _dedupe(_cssAtRules, prefix);
    }

    final openCount = '{'.allMatches(trimmed).length;
    final closeCount = '}'.allMatches(trimmed).length;
    final inBlock = openCount > closeCount;
    var segStart = trimmed.lastIndexOf('{');
    final afterBrace = trimmed.lastIndexOf('}');
    if (afterBrace > segStart) segStart = afterBrace;
    final afterSemi = trimmed.lastIndexOf(';');
    if (afterSemi > segStart) segStart = afterSemi;
    final segment = trimmed.substring(segStart + 1);

    final declaration =
        RegExp(r'^\s*([A-Za-z][\w-]*)\s*:\s*(.*)$').firstMatch(segment);
    if (inBlock && declaration != null) {
      // 值位置：`display: |` —— 补这个属性的常用取值，再兜底文档里用过的值。
      final prop = declaration.group(1)!.toLowerCase();
      return _dedupe([...?_cssValues[prop], ..._cssDocValues(tail)], prefix);
    }

    // 属性名位置；选择器位置顺带把标签名也补上（`div.xxx` 这类写法）。
    final props = _dedupe([..._cssDocProps(tail), ..._cssCommonProps], prefix);
    if (inBlock) return props;
    return _dedupe([...props, ..._commonTags], prefix);
  }

  static final RegExp _cssApplyRe = RegExp(r'@apply\s+[\w:/-]*$');

  static const List<String> _cssAtRules = [
    '@media', '@import', '@keyframes', '@font-face', '@supports', '@charset', '@page',
    '@layer', '@container', '@namespace',
  ];

  /// 常用属性名（选择器 / 声明块里都会用到）。
  static const List<String> _cssCommonProps = [
    'display', 'position', 'top', 'right', 'bottom', 'left', 'float', 'clear', 'z-index',
    'overflow', 'overflow-x', 'overflow-y', 'width', 'height', 'min-width', 'min-height',
    'max-width', 'max-height', 'margin', 'margin-top', 'margin-right', 'margin-bottom',
    'margin-left', 'padding', 'padding-top', 'padding-right', 'padding-bottom', 'padding-left',
    'border', 'border-width', 'border-style', 'border-color', 'border-radius', 'border-top',
    'border-bottom', 'outline', 'box-shadow', 'box-sizing', 'background', 'background-color',
    'background-image', 'background-position', 'background-repeat', 'background-size',
    'background-clip', 'color', 'opacity', 'visibility', 'content', 'cursor', 'pointer-events',
    'user-select', 'resize', 'font', 'font-family', 'font-size', 'font-weight', 'font-style',
    'line-height', 'letter-spacing', 'text-align', 'text-decoration', 'text-transform',
    'text-indent', 'text-overflow', 'text-shadow', 'white-space', 'word-break', 'word-wrap',
    'overflow-wrap', 'word-spacing', 'vertical-align', 'list-style', 'list-style-type',
    'direction', 'writing-mode', 'filter', 'mix-blend-mode', 'flex', 'flex-direction',
    'flex-wrap', 'flex-grow', 'flex-shrink', 'flex-basis', 'justify-content', 'align-items',
    'align-content', 'align-self', 'order', 'gap', 'row-gap', 'column-gap', 'grid',
    'grid-template-columns', 'grid-template-rows', 'grid-column', 'grid-row', 'grid-area',
    'place-items', 'place-content', 'transition', 'transition-duration', 'transition-property',
    'transform', 'transform-origin', 'animation', 'animation-name', 'animation-duration',
  ];

  /// 「属性 -> 常用取值」。含空格/百分号的值也可以，插入时会替换正在输入的那个词。
  static const Map<String, List<String>> _cssValues = {
    'display': ['block', 'inline', 'inline-block', 'flex', 'inline-flex', 'grid', 'none', 'contents', 'table'],
    'position': ['static', 'relative', 'absolute', 'fixed', 'sticky'],
    'float': ['none', 'left', 'right'],
    'clear': ['none', 'left', 'right', 'both'],
    'overflow': ['visible', 'hidden', 'scroll', 'auto', 'clip'],
    'overflow-x': ['visible', 'hidden', 'scroll', 'auto'],
    'overflow-y': ['visible', 'hidden', 'scroll', 'auto'],
    'visibility': ['visible', 'hidden', 'collapse'],
    'box-sizing': ['content-box', 'border-box'],
    'cursor': ['auto', 'default', 'pointer', 'text', 'move', 'grab', 'grabbing', 'not-allowed', 'help', 'wait', 'crosshair'],
    'pointer-events': ['none', 'auto'],
    'user-select': ['none', 'text', 'all', 'auto'],
    'resize': ['none', 'both', 'horizontal', 'vertical'],
    'width': ['auto', '100%', '100vw', 'fit-content', 'min-content', 'max-content'],
    'height': ['auto', '100%', '100vh'],
    'min-width': ['0', '100%'],
    'max-width': ['none', '100%', '960px', '1200px'],
    'margin': ['0', 'auto'],
    'padding': ['0'],
    'gap': ['0', '8px', '16px'],
    'row-gap': ['0', '8px', '16px'],
    'column-gap': ['0', '8px', '16px'],
    'border-style': ['none', 'solid', 'dashed', 'dotted', 'double', 'groove', 'ridge', 'inset', 'outset'],
    'border-radius': ['0', '4px', '8px', '50%'],
    'opacity': ['0', '0.5', '1'],
    'z-index': ['0', '1', '10', '100'],
    'color': ['000', 'fff', 'red', 'blue', 'green', 'currentColor', 'inherit', 'transparent'],
    'background': ['none', 'transparent', 'fff', '000'],
    'background-color': ['transparent', 'fff', '000'],
    'background-repeat': ['no-repeat', 'repeat', 'repeat-x', 'repeat-y'],
    'background-position': ['center', 'top', 'bottom', 'left', 'right'],
    'background-size': ['cover', 'contain', 'auto'],
    'flex': ['1', 'auto', 'none', '1 0 auto'],
    'flex-direction': ['row', 'row-reverse', 'column', 'column-reverse'],
    'flex-wrap': ['nowrap', 'wrap', 'wrap-reverse'],
    'justify-content': ['flex-start', 'flex-end', 'center', 'space-between', 'space-around', 'space-evenly'],
    'align-items': ['stretch', 'flex-start', 'flex-end', 'center', 'baseline'],
    'align-content': ['stretch', 'flex-start', 'flex-end', 'center', 'space-between', 'space-around'],
    'align-self': ['auto', 'stretch', 'flex-start', 'flex-end', 'center', 'baseline'],
    'order': ['0', '1', '2', '-1'],
    'grid-template-columns': [
      'repeat(2, minmax(0, 1fr))', 'repeat(3, minmax(0, 1fr))', 'repeat(12, minmax(0, 1fr))',
      'repeat(auto-fit, minmax(200px, 1fr))', 'repeat(auto-fill, minmax(200px, 1fr))',
      '1fr', '1fr 1fr', '1fr 2fr', 'minmax(0, 1fr)', 'auto 1fr', 'none', 'subgrid',
    ],
    'grid-template-rows': [
      'auto', '1fr', 'repeat(2, 1fr)', 'repeat(3, minmax(0, 1fr))', 'none', 'subgrid',
    ],
    'grid-template-areas': ['none'],
    'grid-auto-flow': ['row', 'column', 'row dense', 'column dense'],
    'grid-auto-columns': ['auto', 'min-content', 'max-content', '1fr'],
    'grid-auto-rows': ['auto', 'min-content', 'max-content', '1fr'],
    'grid-column': ['auto', 'span 1', 'span 2', 'span 3', '1 / -1', '1 / 3'],
    'grid-row': ['auto', 'span 1', 'span 2', '1 / -1', '1 / 3'],
    'grid-area': ['auto', '1 / 1 / 2 / 2'],
    'justify-items': ['start', 'end', 'center', 'stretch'],
    'justify-self': ['auto', 'start', 'end', 'center', 'stretch'],
    'place-items': ['center', 'start', 'end', 'stretch', 'center start'],
    'place-content': ['center', 'start', 'end', 'space-between', 'space-around', 'stretch'],
    'place-self': ['auto', 'center', 'start', 'end', 'stretch'],
    'font-family': ['serif', 'sans-serif', 'monospace', 'cursive', 'system-ui'],
    'font-weight': ['normal', 'bold', 'bolder', 'lighter', '100', '200', '300', '400', '500', '600', '700', '800', '900'],
    'font-style': ['normal', 'italic', 'oblique'],
    'line-height': ['normal', '1', '1.5', '2'],
    'letter-spacing': ['normal', '0.5px', '1px'],
    'text-align': ['left', 'right', 'center', 'justify', 'start', 'end'],
    'text-decoration': ['none', 'underline', 'line-through', 'overline'],
    'text-transform': ['none', 'uppercase', 'lowercase', 'capitalize'],
    'text-overflow': ['clip', 'ellipsis'],
    'white-space': ['normal', 'nowrap', 'pre', 'pre-wrap', 'pre-line', 'break-spaces'],
    'word-break': ['normal', 'break-all', 'keep-all'],
    'vertical-align': ['baseline', 'top', 'middle', 'bottom', 'sub', 'super', 'text-top', 'text-bottom'],
    'list-style': ['none', 'disc', 'circle', 'square', 'decimal'],
    'list-style-type': ['none', 'disc', 'circle', 'square', 'decimal', 'lower-alpha', 'upper-roman'],
    'direction': ['ltr', 'rtl'],
    'writing-mode': ['horizontal-tb', 'vertical-rl', 'vertical-lr'],
    'transition': ['none', 'all 0.3s', 'all 0.3s ease', 'all 0.2s ease-in-out'],
    'transition-duration': ['0.2s', '0.3s', '1s'],
    'transform': ['none', 'scale(1)', 'translateX(0)', 'rotate(0deg)'],
    'transform-origin': ['center', 'top', 'bottom', 'left', 'right'],
    'animation': ['none'],
    'mix-blend-mode': ['normal', 'multiply', 'screen', 'overlay', 'darken', 'lighten'],
    'filter': ['none', 'blur(2px)', 'brightness(1)', 'grayscale(1)', 'opacity(0.5)'],
  };

  /// 伪类 / 伪元素：提取文档属性名时要排除，避免把 `a:hover` 里的 `a` 当属性。
  static const Set<String> _cssPseudo = {
    'hover', 'focus', 'focus-within', 'focus-visible', 'active', 'visited', 'link', 'any-link',
    'first-child', 'last-child', 'only-child', 'nth-child', 'nth-of-type', 'first-of-type',
    'last-of-type', 'only-of-type', 'not', 'is', 'where', 'has', 'empty', 'target', 'root',
    'before', 'after', 'placeholder', 'checked', 'disabled', 'enabled', 'required', 'valid',
    'invalid', 'read-only', 'read-write', 'selection', 'marker', 'backdrop', 'file-selector-button',
  };

  static final RegExp _cssPropRe = RegExp(r'([A-Za-z][\w-]{2,})\s*:');
  static final RegExp _cssValueRe = RegExp(r':\s*([A-Za-z][\w-]*)');

  static List<String> _cssDocProps(String doc) {
    final out = <String>[];
    for (final m in _cssPropRe.allMatches(doc)) {
      final prop = m.group(1)!.toLowerCase();
      if (_cssPseudo.contains(prop)) continue;
      out.add(prop);
      if (out.length > 300) break;
    }
    return out;
  }

  static List<String> _cssDocValues(String doc) {
    final out = <String>[];
    for (final m in _cssValueRe.allMatches(doc)) {
      out.add(m.group(1)!);
      if (out.length > 200) break;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Markdown
  // ---------------------------------------------------------------------------

  static const List<String> _mdLanguages = [
    'javascript', 'typescript', 'jsx', 'tsx', 'json', 'html', 'xml', 'css', 'scss', 'less',
    'yaml', 'toml', 'ini', 'markdown', 'bash', 'shell', 'sh', 'zsh', 'powershell', 'python',
    'java', 'kotlin', 'scala', 'go', 'rust', 'c', 'cpp', 'csharp', 'php', 'ruby', 'swift',
    'dart', 'sql', 'graphql', 'dockerfile', 'diff', 'text', 'plaintext',
  ];

  static List<String> _markdown(String doc, String linePrefix, String prefix) {
    final trimmed = linePrefix.trimRight();
    // 围栏代码块后面是在写语言名：```js
    if (RegExp(r'^\s*(`{3,}|~{3,})\s*[\w+#.-]*$').hasMatch(trimmed)) {
      return _dedupe(_mdLanguages, prefix);
    }
    // 内嵌 HTML：`<` 之后交给 HTML 那套规则（标签名 / 属性 / class）。
    final lt = trimmed.lastIndexOf('<');
    if (lt >= 0 && lt > trimmed.lastIndexOf('>')) {
      return _xml(doc, linePrefix, prefix);
    }
    return const [];
  }

  // ---------------------------------------------------------------------------
  // HTTP
  // ---------------------------------------------------------------------------

  static const List<String> _httpMethods = [
    'GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS', 'TRACE', 'CONNECT',
  ];

  /// 常见请求 / 响应头。
  static const List<String> _httpHeaders = [
    'Host', 'User-Agent', 'Accept', 'Accept-Encoding', 'Accept-Language', 'Accept-Charset',
    'Authorization', 'Cache-Control', 'Content-Type', 'Content-Length', 'Content-Encoding',
    'Content-Language', 'Content-Disposition', 'Cookie', 'Connection', 'Referer', 'Origin',
    'Range', 'If-Modified-Since', 'If-None-Match', 'If-Match', 'ETag', 'Last-Modified',
    'Date', 'Server', 'Set-Cookie', 'Location', 'Transfer-Encoding', 'Upgrade', 'Via', 'Vary',
    'Access-Control-Allow-Origin', 'Access-Control-Allow-Methods',
    'Access-Control-Allow-Headers', 'Access-Control-Allow-Credentials', 'X-Requested-With',
    'X-Forwarded-For', 'X-Real-IP', 'X-Request-Id', 'Proxy-Authorization', 'Pragma', 'Expires',
    'Keep-Alive', 'TE', 'Trailer', 'Expect',
  ];

  static List<String> _http(String doc, String linePrefix, String prefix) {
    final trimmed = linePrefix.trimRight();
    final names = _dedupe([..._httpHeaders, ..._httpDocHeaders(doc)], prefix);
    // 行首（这一行还什么都没写）通常是请求行 / 状态行，先给方法。
    if (trimmed.trimLeft().isEmpty) {
      return _dedupe([..._httpMethods, ...names], prefix);
    }
    return names;
  }

  static final RegExp _httpHeaderRe =
      RegExp(r'^([A-Za-z][A-Za-z0-9-]{1,40})\s*:', multiLine: true);

  static List<String> _httpDocHeaders(String doc) {
    final out = <String>[];
    for (final m in _httpHeaderRe.allMatches(_tail(doc))) {
      out.add(m.group(1)!);
      if (out.length > 200) break;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // 通用：按缩进决定「声明类 / 语句类」的先后
  // ---------------------------------------------------------------------------

  static final RegExp _memberRe = RegExp(r'\.([A-Za-z_$][\w$]*)');
  static final RegExp _typeRe = RegExp(r'\b([A-Z][A-Za-z0-9_$]{2,})');

  static List<String> _generic(
      String doc, String linePrefix, String prefix, String language) {
    final words = CodeKeywords.forLanguage(language);
    final tail = _tail(doc);
    final trimmed = linePrefix.trimRight();
    // `obj.` 之后：补文档里出现过的成员名。
    if (RegExp(r'\.[\w$]*$').hasMatch(trimmed)) {
      return _dedupe([..._collect(tail, _memberRe, 200), ...words], prefix);
    }
    // `new ` / `extends ` 之后：补文档里的大驼峰类型名。
    if (RegExp(r'\b(new|extends|implements|with|throw)\s+[\w$]*$').hasMatch(trimmed)) {
      final types = _collect(tail, _typeRe, 200);
      if (types.isNotEmpty) return _dedupe([...types, ...words], prefix);
    }
    if (words.isEmpty) return const [];
    final indent = linePrefix.length - linePrefix.trimLeft().length;
    final declarationFirst = indent == 0;
    final head = <String>[];
    final tailWords = <String>[];
    for (final w in words) {
      final isDecl = _declarationWords.contains(w);
      final isStmt = _statementWords.contains(w);
      if (isDecl && !isStmt) {
        (declarationFirst ? head : tailWords).add(w);
      } else if (isStmt && !isDecl) {
        (declarationFirst ? tailWords : head).add(w);
      } else {
        tailWords.add(w);
      }
    }
    return _dedupe([...head, ...tailWords], prefix);
  }

  // ---------------------------------------------------------------------------
  // 工具
  // ---------------------------------------------------------------------------

  /// 用正则从文档里收集去重后的词（保持出现顺序）。
  static List<String> _collect(String doc, RegExp re, int limit) {
    final out = <String>[];
    final seen = <String>{};
    for (final m in re.allMatches(doc)) {
      final w = m.group(1)!;
      if (seen.add(w)) out.add(w);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// 只看文档尾部，避免超大文档全量扫描。
  static String _tail(String doc) =>
      doc.length <= _maxScan ? doc : doc.substring(doc.length - _maxScan);

  static List<String> _dedupe(Iterable<String> items, String prefix) {
    final lowerPrefix = prefix.toLowerCase();
    final seen = <String>{};
    final out = <String>[];
    for (final raw in items) {
      final s = raw.trim();
      if (s.isEmpty || s == prefix) continue;
      if (prefix.isNotEmpty && !s.toLowerCase().startsWith(lowerPrefix)) continue;
      if (!seen.add(s)) continue;
      out.add(s);
      if (out.length >= _maxItems) break;
    }
    return out;
  }
}
