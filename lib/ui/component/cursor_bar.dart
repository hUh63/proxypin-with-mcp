import 'package:flutter/material.dart';

/// 光标移动方向（手机上没有物理方向键，长按空格拖动在长行里很难点准）。
enum CaretMove { left, right, up, down, home, end, pageUp, pageDown }

/// 光标方向键条（对标 Sora Editor 的 Cursor Actions、Termux 的 extra keys）。
///
/// 一行 8 个按钮：左右上下 + 行首/行尾 + 上下翻页。点一下移一格，
/// 配合放大镜比长按拖动精确得多 —— 尤其在一行几百字符的 JSON/日志里。
class CursorBar extends StatelessWidget {
  final void Function(CaretMove move) onMove;
  final VoidCallback? onClose;

  const CursorBar({super.key, required this.onMove, this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget btn(IconData icon, CaretMove move, String tip) => Expanded(
          child: InkWell(
            onTap: () => onMove(move),
            child: Tooltip(
              message: tip,
              child: SizedBox(
                height: 34,
                child: Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        );

    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.4)),
      ),
      child: Row(children: <Widget>[
        btn(Icons.arrow_back, CaretMove.left, '←'),
        btn(Icons.arrow_forward, CaretMove.right, '→'),
        btn(Icons.arrow_upward, CaretMove.up, '↑'),
        btn(Icons.arrow_downward, CaretMove.down, '↓'),
        btn(Icons.first_page, CaretMove.home, 'Home'),
        btn(Icons.last_page, CaretMove.end, 'End'),
        btn(Icons.keyboard_double_arrow_up, CaretMove.pageUp, 'PgUp'),
        btn(Icons.keyboard_double_arrow_down, CaretMove.pageDown, 'PgDn'),
        if (onClose != null)
          SizedBox(
            width: 34,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 15),
              onPressed: onClose,
            ),
          ),
      ]),
    );
  }
}
