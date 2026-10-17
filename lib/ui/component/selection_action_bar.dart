import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/ui/component/multi_select_controller.dart';
import 'package:proxypin/utils/listenable_list.dart';

class SelectionActionBar extends StatelessWidget {
  final MultiSelectController selectionController;
  final VoidCallback? onSelectAll;
  final VoidCallback? onRepeat;
  final VoidCallback? onExport;
  final VoidCallback? onDelete;
  final VoidCallback? onCompare;

  const SelectionActionBar(
      {super.key,
      required this.selectionController,
      this.onSelectAll,
      this.onRepeat,
      this.onExport,
      this.onDelete,
      this.onCompare});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return SizedBox(
        height: 44,
        child: Row(children: [
          const SizedBox(width: 8),
          _SelectLabel(selectionController: selectionController),
          const Spacer(),
          // 6 个默认 48x48 的 IconButton ≈ 288px：窄窗口/手机竖屏 + 左侧面板
          // 拉窄时必然 RenderFlex overflow（右侧按钮被裁掉点不到）。统一压缩。
          if (onSelectAll != null)
            _actionIcon(onPressed: onSelectAll, tooltip: localizations?.selectAll, icon: Icons.select_all),
          if (onRepeat != null)
            _actionIcon(onPressed: onRepeat, tooltip: localizations?.repeat, icon: Icons.repeat),
          if (onCompare != null)
            _actionIcon(onPressed: onCompare, tooltip: localizations?.compare, icon: Icons.compare_arrows),
          if (onExport != null)
            _actionIcon(onPressed: onExport, tooltip: localizations?.export, icon: Icons.share_outlined),
          if (onDelete != null)
            _actionIcon(onPressed: onDelete, tooltip: localizations?.delete, icon: Icons.delete_outline),
          _actionIcon(onPressed: _onCancel, tooltip: localizations?.cancel, icon: Icons.close),
        ]));
  }

  void _onCancel() {
    selectionController.clear();
  }

  Widget _actionIcon({VoidCallback? onPressed, String? tooltip, required IconData icon}) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    );
  }
}

class _SelectLabel extends StatefulWidget {
  final MultiSelectController selectionController;

  const _SelectLabel({required this.selectionController});

  @override
  State<StatefulWidget> createState() => _SelectLabelState();
}

class _SelectLabelState extends State<_SelectLabel> {
  late final OnchangeListEvent<String> _listener;

  @override
  void initState() {
    super.initState();
    _listener = OnchangeListEvent(_onSelectionChanged);
    widget.selectionController.selectedIds.addListener(_listener);
  }

  @override
  void dispose() {
    widget.selectionController.selectedIds.removeListener(_listener);
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final selectLabel = AppLocalizations.of(context)?.selectAction;
    final selectedCount = widget.selectionController.selectedIds.length;
    final label = (selectLabel == null || selectLabel.isEmpty) ? '$selectedCount' : '$selectedCount $selectLabel';

    return Text(label, style: Theme.of(context).textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

class ClearSelectionIntent extends Intent {
  const ClearSelectionIntent();
}
