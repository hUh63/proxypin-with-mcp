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

import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/utils/text_editor_prefs.dart';
import 'package:proxypin/ui/toolbox/text_editor_menus.dart';

/// 文本编辑器的「设置」页：字体与排版 / 辅助显示 / 缩进与折叠。
///
/// 改动即时生效并全局保存（[TextEditorPrefsStore]）。
class TextEditorSettingsPage extends StatefulWidget {
  const TextEditorSettingsPage({super.key, this.allLangs = const <String>[]});

  /// 内核支持的全部语言 label，用于「语法文件管理」。
  final List<String> allLangs;

  @override
  State<TextEditorSettingsPage> createState() => _TextEditorSettingsPageState();
}

class _TextEditorSettingsPageState extends State<TextEditorSettingsPage> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  void _apply(TextEditorPrefs prefs) {
    TextEditorPrefsStore.update(prefs);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.editorSettings, style: const TextStyle(fontSize: 15)),
        centerTitle: true,
      ),
      body: ValueListenableBuilder<TextEditorPrefs>(
        valueListenable: TextEditorPrefsStore.notifier,
        builder: (context, prefs, _) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _groupTitle(localizations.editorSettingsTypography),
              _slider(
                icon: Icons.format_size,
                title: localizations.editorFontSize,
                value: prefs.fontSize,
                min: 10,
                max: 28,
                label: prefs.fontSize.toStringAsFixed(0),
                onChanged: (v) => _apply(prefs.copyWith(fontSize: v)),
              ),
              _slider(
                icon: Icons.format_line_spacing,
                title: localizations.editorLineHeight,
                value: prefs.lineHeight,
                min: 0.8,
                max: 2.0,
                label: '${prefs.lineHeight.toStringAsFixed(1)}x',
                onChanged: (v) => _apply(prefs.copyWith(lineHeight: v)),
              ),
              const Divider(height: 16),
              _groupTitle(localizations.editorSettingsDisplay),
              _switchTile(
                icon: Icons.format_list_numbered,
                title: localizations.editorShowGutter,
                value: prefs.showGutter,
                onChanged: (v) => _apply(prefs.copyWith(showGutter: v)),
              ),
              _switchTile(
                icon: Icons.vertical_split,
                title: localizations.editorGutterDivider,
                value: prefs.gutterDivider,
                onChanged: (v) => _apply(prefs.copyWith(gutterDivider: v)),
              ),
              _switchTile(
                icon: Icons.view_week_outlined,
                title: localizations.editorGuideLines,
                value: prefs.guideLines,
                onChanged: (v) => _apply(prefs.copyWith(guideLines: v)),
              ),
              _switchTile(
                icon: Icons.highlight_alt,
                title: localizations.editorHighlightLine,
                value: prefs.highlightCurrentLine,
                onChanged: (v) => _apply(prefs.copyWith(highlightCurrentLine: v)),
              ),
              _switchTile(
                icon: Icons.space_bar,
                title: localizations.editorHideSingleSpace,
                value: prefs.hideSingleSpace,
                onChanged: (v) => _apply(prefs.copyWith(hideSingleSpace: v)),
              ),
              _switchTile(
                icon: Icons.subdirectory_arrow_left,
                title: localizations.editorSoftWrapArrow,
                value: prefs.softWrapArrow,
                onChanged: (v) => _apply(prefs.copyWith(softWrapArrow: v)),
              ),
              const Divider(height: 16),
              _groupTitle(localizations.editorSettingsIndent),
              _switchTile(
                icon: Icons.tab,
                title: localizations.editorUseTabs,
                value: prefs.useTabs,
                onChanged: (v) => _apply(prefs.copyWith(useTabs: v)),
              ),
              _slider(
                icon: Icons.space_bar,
                title: localizations.editorTabSize,
                value: prefs.tabSize.toDouble(),
                min: 1,
                max: 8,
                divisions: 7,
                label: '${prefs.tabSize}',
                onChanged: (v) => _apply(prefs.copyWith(tabSize: v.round())),
              ),
              _switchTile(
                icon: Icons.unfold_more,
                title: localizations.editorEnableFolding,
                value: prefs.enableFolding,
                onChanged: (v) => _apply(prefs.copyWith(enableFolding: v)),
              ),
              _switchTile(
                icon: Icons.subdirectory_arrow_right,
                title: localizations.editorAutoIndent,
                value: prefs.autoIndent,
                onChanged: (v) => _apply(prefs.copyWith(autoIndent: v)),
              ),
              const Divider(height: 16),
              _groupTitle(localizations.editorSettingsComplete),
              _switchTile(
                icon: Icons.keyboard_return,
                title: localizations.editorEnterSuggestion,
                value: prefs.enterSuggestion,
                onChanged: (v) => _apply(prefs.copyWith(enterSuggestion: v)),
              ),
              _slider(
                icon: Icons.height,
                title: localizations.editorSuggestionHeight,
                value: prefs.suggestionMaxHeight,
                min: 120,
                max: 800,
                divisions: 17,
                label: prefs.suggestionMaxHeight.toStringAsFixed(0),
                onChanged: (v) => _apply(prefs.copyWith(suggestionMaxHeight: v)),
              ),
              _switchTile(
                icon: Icons.spellcheck,
                title: localizations.editorStyleLint,
                value: prefs.styleLint,
                onChanged: (v) => _apply(prefs.copyWith(styleLint: v)),
              ),
              _switchTile(
                icon: Icons.format_color_fill,
                title: localizations.editorHighlightOccurrences,
                value: prefs.highlightOccurrences,
                onChanged: (v) => _apply(prefs.copyWith(highlightOccurrences: v)),
              ),
              const Divider(height: 16),
              _groupTitle(localizations.editorSettingsGesture),
              _switchTile(
                icon: Icons.pinch,
                title: localizations.editorPinchZoom,
                value: prefs.pinchZoom,
                onChanged: (v) => _apply(prefs.copyWith(pinchZoom: v)),
              ),
              _switchTile(
                icon: Icons.zoom_in,
                title: localizations.editorMagnifier,
                value: prefs.magnifier,
                onChanged: (v) => _apply(prefs.copyWith(magnifier: v)),
              ),
              const Divider(height: 16),
              _groupTitle(localizations.editorSettingsMenu),
              ListTile(
                dense: true,
                leading: const Icon(Icons.tune, size: 20),
                title: Text(localizations.editorEditToolMenu, style: const TextStyle(fontSize: 13.5)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => const EditorMenuManagerDialog(),
                ),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.touch_app, size: 20),
                title: Text(localizations.editorEditFloatMenu, style: const TextStyle(fontSize: 13.5)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => const FloatMenuManagerDialog(),
                ),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.category_outlined, size: 20),
                title: Text(localizations.editorSyntaxManager, style: const TextStyle(fontSize: 13.5)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => LanguageManagerDialog(allLangs: widget.allLangs),
                ),
              ),
              const Divider(height: 16),
              _groupTitle(localizations.editorSettingsBehavior),
              _switchTile(
                icon: Icons.short_text,
                title: localizations.editorShortcutBar,
                value: prefs.shortcutBar,
                onChanged: (v) => _apply(prefs.copyWith(shortcutBar: v)),
              ),
              _switchTile(
                icon: Icons.visibility_outlined,
                title: localizations.editorCheckFileModified,
                value: prefs.checkFileModified,
                onChanged: (v) => _apply(prefs.copyWith(checkFileModified: v)),
              ),
              _switchTile(
                icon: Icons.warning_amber_outlined,
                title: localizations.editorConfirmExitTwice,
                value: prefs.confirmExitTwice,
                onChanged: (v) => _apply(prefs.copyWith(confirmExitTwice: v)),
              ),
              _switchTile(
                icon: Icons.content_copy_outlined,
                title: localizations.editorNewFileKeepPrefs,
                value: prefs.newFileKeepPrefs,
                onChanged: (v) => _apply(prefs.copyWith(newFileKeepPrefs: v)),
              ),
              _slider(
                icon: Icons.auto_stories_outlined,
                title: localizations.editorAutoPageSize,
                value: prefs.autoPageSize.toDouble(),
                min: 0,
                max: 1000000,
                divisions: 20,
                label: '${((prefs.autoPageSize == 0 ? 200000 : prefs.autoPageSize) / 1000).toStringAsFixed(0)}k',
                onChanged: (v) => _apply(prefs.copyWith(autoPageSize: v.round())),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text(
                  localizations.editorSettingsNote,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _groupTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      dense: true,
      secondary: Icon(icon, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _slider({
    required IconData icon,
    required String title,
    required double value,
    required double min,
    required double max,
    required String label,
    int? divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 16),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 14))),
          SizedBox(
            width: 120,
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: label,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(label,
                textAlign: TextAlign.right, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
