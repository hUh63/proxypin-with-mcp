import 'package:flutter/material.dart';

/// 程序员符号输入条（对标 Sora Editor 的 SymbolInputView、Termux 的 extra keys）。
///
/// 手机上打 `{}` `[]` `<>` `$` `\` `|` 这些要来回切键盘页 —— 一次两次还行，
/// 写代码就是灾难。这里做成一条常驻的横向条：点一下插入一个符号，
/// 三组（符号 / 数字与运算符 / 常用短语）横滑切换。
///
/// 放在编辑器底部而不是弹层里，是因为「插入一个字符」的交互不能有打开成本。
class SymbolBar extends StatefulWidget {
  /// 点某个按钮时回调要插入的文本。
  final void Function(String text) onInsert;

  /// 关闭按钮（不传就不显示）。
  final VoidCallback? onClose;

  const SymbolBar({super.key, required this.onInsert, this.onClose});

  @override
  State<SymbolBar> createState() => _SymbolBarState();
}

class _Group {
  final String label;
  final List<String> items;
  const _Group(this.label, this.items);
}

const List<_Group> _groups = <_Group>[
  _Group('{}', <String>[
    '{', '}', '[', ']', '(', ')', '<', '>', '"', "'", '`',
    '\\', '/', '|', '&', '*', '+', '-', '=', '!', '?', ':', ';', ',', '.',
    '@', '#', r'$', '%', '^', '~', '_',
  ]),
  _Group('123', <String>[
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    '.', '+', '-', '*', '/', '=', '%', '(', ')', '<', '>',
    '==', '!=', '<=', '>=', '&&', '||', '=>', '->', '+=', '-=',
  ]),
  _Group('Abc', <String>[
    '{ }', '[ ]', '( )', '< >', '// ', '/* */', '/** */',
    '=> ', '!= ', '&& ', '|| ', 'null', 'true', 'false',
    'return ', 'var ', 'void ', 'public ', 'private ',
    'if ()', 'for ()', 'while ()', 'try {}', 'catch ()',
    '\t', '\n',
  ]),
];

class _SymbolBarState extends State<SymbolBar> {
  int _group = 0;
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.4)),
      ),
      child: Row(children: <Widget>[
        // 组切换：三个窄 chip，选中态用主色，未选中用次要色。
        for (var i = 0; i < _groups.length; i++)
          InkWell(
            onTap: () {
              setState(() => _group = i);
              if (_scroll.hasClients) _scroll.jumpTo(0);
            },
            child: Container(
              width: 38,
              alignment: Alignment.center,
              color: i == _group
                  ? theme.colorScheme.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              child: Text(
                _groups[i].label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  fontWeight: i == _group ? FontWeight.w600 : FontWeight.w400,
                  color: i == _group
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        VerticalDivider(width: 1, thickness: 0.4, color: theme.dividerColor),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            itemCount: _groups[_group].items.length,
            itemBuilder: (ctx, i) {
              final s = _groups[_group].items[i];
              final isBlank = s.trim().isEmpty && s.isNotEmpty;
              return InkWell(
                onTap: () => widget.onInsert(s),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 34),
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  alignment: Alignment.center,
                  child: Text(
                    isBlank ? (s == '\n' ? '⏎' : '⇥') : s,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.onClose != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.keyboard_hide, size: 17),
            onPressed: widget.onClose,
          ),
      ]),
    );
  }
}
