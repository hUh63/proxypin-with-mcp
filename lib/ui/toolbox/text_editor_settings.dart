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

/// 文本编辑器的「设置」页：字体与排版 / 辅助显示 / 缩进与折叠。
///
/// 改动即时生效并全局保存（[TextEditorPrefsStore]）。
class TextEditorSettingsPage extends StatefulWidget {
  const TextEditorSettingsPage({super.key});

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
