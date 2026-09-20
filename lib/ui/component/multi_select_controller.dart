import 'package:get/get.dart';
import 'package:proxypin/utils/listenable_list.dart';

class MultiSelectController {
  final ListenableList<String> selectedIds = ListenableList<String>();

  String? _anchorId;
  RxBool selectionMode = false.obs;

  bool get isSelectionMode => selectionMode.value;

  int get selectedCount => selectedIds.length;

  bool contains(String requestId) => selectedIds.contains(requestId);

  ///是否处于"用户显式进入的多选会话"。
  ///
  /// 与 [selectionMode] 不同：单个请求被"选中/高亮"时 [selectionMode] 同样是 true，
  /// 但那只是"有选中项"。上游 #783 第 6 条要求退出多选后恢复原有高亮，
  /// 因此必须把这两种状态区分开。
  bool _multiSelectSession = false;

  ///进入多选前的高亮项快照，退出多选时恢复
  List<String>? _highlightBeforeMultiSelect;
  String? _anchorBeforeMultiSelect;

  void clear() {
    _multiSelectSession = false;
    _highlightBeforeMultiSelect = null;
    _anchorBeforeMultiSelect = null;
    if (selectedIds.isEmpty && !selectionMode.value) {
      return;
    }
    selectedIds.clear();
    _anchorId = null;
    selectionMode.value = false;
  }

  void remove(String requestId) {
    selectedIds.remove(requestId);
  }

  void enterSelectionMode([String? requestId]) {
    selectionMode.value = true;
    if (requestId != null) {
      selectedIds.add(requestId);
      _anchorId = requestId;
    }
  }

  /// 全选（上游 issue #906）：选中当前列表的全部请求 ID
  void selectAll(Iterable<String> ids) {
    selectionMode.value = true;
    selectedIds.clear();
    selectedIds.addAll(ids);
  }

  void selectOnly(String requestId) {
    selectionMode.value = true;
    selectedIds
      ..clear()
      ..add(requestId);
    _anchorId = requestId;
  }

  /// 切换多选模式。
  ///
  /// 进入时记下当前高亮项，退出时恢复 —— 否则"请求高亮后进入多选、再退出"
  /// 会把高亮一起清掉（上游 #783 第 6 条）。
  /// 进入多选后仍从空选择开始（保持原有行为，避免误删原先高亮的那条请求）。
  void toggleSelectionMode([String? requestId]) {
    if (_multiSelectSession) {
      _multiSelectSession = false;
      final highlight = _highlightBeforeMultiSelect;
      final anchor = _anchorBeforeMultiSelect;
      _highlightBeforeMultiSelect = null;
      _anchorBeforeMultiSelect = null;

      if (highlight != null && highlight.isNotEmpty) {
        selectionMode.value = true;
        selectedIds
          ..clear()
          ..addAll(highlight);
        _anchorId = anchor;
        return;
      }
      clear();
      return;
    }

    _highlightBeforeMultiSelect = List<String>.from(selectedIds);
    _anchorBeforeMultiSelect = _anchorId;
    _multiSelectSession = true;
    selectedIds.clear();
    _anchorId = null;
    selectionMode.value = true;
    if (requestId != null) {
      selectedIds.add(requestId);
      _anchorId = requestId;
    }
  }

  void toggle(String requestId) {
    selectionMode.value = true;
    if (selectedIds.contains(requestId)) {
      selectedIds.remove(requestId);
    } else {
      selectedIds.add(requestId);
    }

    if (selectedIds.isEmpty) {
      clear();
      return;
    }

    _anchorId = requestId;
  }

  void selectRange(List<String> orderedIds, String requestId) {
    final targetIndex = orderedIds.indexOf(requestId);
    if (targetIndex < 0) {
      return;
    }

    final anchorIndex = _anchorId == null ? -1 : orderedIds.indexOf(_anchorId!);
    if (anchorIndex < 0) {
      selectOnly(requestId);
      return;
    }

    final start = anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final end = anchorIndex > targetIndex ? anchorIndex : targetIndex;
    selectionMode.value = true;
    selectedIds
      ..clear()
      ..addAll(orderedIds.sublist(start, end + 1));
    _anchorId = requestId;
  }

  void prune(Iterable<String> visibleIds) {
    final visibleIdSet = visibleIds.toSet();
    selectedIds.removeWhere((requestId) => !visibleIdSet.contains(requestId));

    if (selectedIds.isEmpty) {
      clear();
      return;
    }

    selectionMode.value = true;
    if (_anchorId == null || !selectedIds.contains(_anchorId)) {
      _anchorId = selectedIds.last;
    }
  }
}

class MultiSelectListener<T> extends ListenerListEvent<T> {
  final Function(List<T> items) onChange;

  MultiSelectListener(this.onChange);

  @override
  void onAdd(T item) => onChange.call([item]);

  @override
  void onRemove(T item) => onChange.call([item]);

  @override
  void onUpdate(T item) => onChange.call([item]);

  @override
  void onBatchRemove(List<T> items) => onChange.call(items);

  @override
  void clear(List<T> items) => onChange.call(items);
}
