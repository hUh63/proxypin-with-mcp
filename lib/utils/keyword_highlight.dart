import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KeywordHighlights {
  static bool _enabled = true;
  static bool initialized = false;
  static const String storeKey = "highlightKeywords";

  static final ValueNotifier _keywordsController = ValueNotifier<Map<Color, String>>({});

  static Map<Color, String> get keywords => _keywordsController.value;

  static bool get enabled => _enabled;

  static set enabled(bool value) {
    _enabled = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('highlightEnabled', value);
    });
  }

  static Color? getHighlightColor(String? key) {
    if (key == null || !_enabled) {
      return null;
    }
    for (var entry in _keywordsController.value.entries) {
      if (key.contains(entry.value)) {
        return entry.key;
      }
    }
    return null;
  }

  static addListener(VoidCallback listener) {
    if (!initialized) {
      initialized = true;
      SharedPreferences.getInstance().then((prefs) {
        var enabledVal = prefs.getBool('highlightEnabled');
        if (enabledVal != null) {
          enabled = enabledVal;
        }

        var val = prefs.getString(storeKey);
        if (val == null) {
          return;
        }
        var map = jsonDecode(val);
        var next = Map<Color, String>.from(_keywordsController.value);
        map.forEach((key, value) {
          var color = ColorMapping.getColor(key);
          next[color] = value;
        });
        // 整体替换 value，触发 ValueNotifier 通知（原地修改 Map 不会通知监听者）
        _keywordsController.value = next;
      });
    }
    _keywordsController.addListener(listener);
  }

  static Future<void> saveKeywords(Map<Color, String> keywords) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var map = keywords.map((key, value) => MapEntry(ColorMapping.getColorName(key), value));
    prefs.setString(storeKey, jsonEncode(map));
    _keywordsController.value = keywords;
  }

  static removeListener(VoidCallback listener) {
    _keywordsController.removeListener(listener);
  }
}
