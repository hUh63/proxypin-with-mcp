import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 宏的一步：在某处删掉 [removed]、插入 [inserted]。
///
/// 用「改动前后文本的差异」表示而不是记按键：撤销、粘贴、多光标编辑都能被如实记录，
/// 回放时也不需要重放按键时序。
class EditorMacroStep {
  final int offset;
  final String removed;
  final String inserted;

  const EditorMacroStep({
    required this.offset,
    required this.removed,
    required this.inserted,
  });

  Map<String, dynamic> toJson() => {'o': offset, 'r': removed, 'i': inserted};

  static EditorMacroStep? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final o = raw['o'];
    if (o is! num) return null;
    return EditorMacroStep(
      offset: o.toInt(),
      removed: (raw['r'] as String?) ?? '',
      inserted: (raw['i'] as String?) ?? '',
    );
  }
}

/// 一个具名宏。
class EditorMacro {
  final String name;
  final List<EditorMacroStep> steps;

  const EditorMacro({required this.name, required this.steps});

  /// 列表里显示的摘要（`12 步 · 3.4 KB`）。
  int get weight => steps.fold<int>(0, (a, s) => a + s.removed.length + s.inserted.length);

  Map<String, dynamic> toJson() => {
        'name': name,
        'steps': [for (final s in steps) s.toJson()],
      };

  static EditorMacro? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String || name.isEmpty) return null;
    final steps = <EditorMacroStep>[];
    final list = raw['steps'];
    if (list is List) {
      for (final e in list) {
        final s = EditorMacroStep.fromJson(e);
        if (s != null) steps.add(s);
      }
    }
    if (steps.isEmpty) return null;
    return EditorMacro(name: name, steps: steps);
  }
}

/// 具名宏的存档。
///
/// 上限 20 条、单条 500 步（和录制时的上限一致）：宏是「重复性动作的快捷方式」，
/// 存几百条反而找不到。读的时候逐条容错 —— 一条坏数据不能让整份列表消失。
class EditorMacroStore {
  static const String key = 'text_editor_macros_v1';
  static const int maxMacros = 20;
  static const int maxSteps = 500;

  static Future<List<EditorMacro>> load() async {
    try {
      final raw = await SharedPreferencesAsync().getString(key);
      if (raw == null || raw.isEmpty) return <EditorMacro>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <EditorMacro>[];
      final out = <EditorMacro>[];
      for (final e in decoded) {
        final m = EditorMacro.fromJson(e);
        if (m != null && out.length < maxMacros) out.add(m);
      }
      return out;
    } catch (_) {
      return <EditorMacro>[];
    }
  }

  static Future<void> save(List<EditorMacro> macros) async {
    try {
      final list = macros.length > maxMacros ? macros.sublist(0, maxMacros) : macros;
      await SharedPreferencesAsync()
          .setString(key, jsonEncode([for (final m in list) m.toJson()]));
    } catch (_) {
      // 存档失败不影响当前会话里已经录好的宏。
    }
  }
}
