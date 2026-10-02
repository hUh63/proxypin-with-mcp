import 'dart:convert';
import 'dart:io' show gzip, zlib;

import 'package:crypto/crypto.dart';
import 'package:proxypin/ui/component/multi_window_compat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/network/util/logger.dart';

import '../component/buttons.dart';

///编码类型
enum EncoderType {
  url,
  base64,
  base32,
  hex,
  unicode,
  html,
  gzip,
  deflate,
  urlParams,
  md5;

  static EncoderType nameOf(String name) {
    for (var value in values) {
      if (value.name == name) {
        return value;
      }
    }
    return url;
  }
}

class EncoderWidget extends StatefulWidget {
  final EncoderType type;
  final WindowController? windowController;
  final String? text;

  const EncoderWidget({super.key, required this.type, this.windowController, this.text});

  @override
  State<EncoderWidget> createState() => _EncoderState();
}

class _EncoderState extends State<EncoderWidget> with SingleTickerProviderStateMixin {
  List<Tab> _tabs(AppLocalizations l) => [
        const Tab(text: 'URL'),
        const Tab(text: 'Base64'),
        const Tab(text: 'Base32'),
        const Tab(text: 'Hex'),
        const Tab(text: 'Unicode'),
        const Tab(text: 'HTML'),
        const Tab(text: 'GZip'),
        const Tab(text: 'Deflate'),
        Tab(text: l.encoderParams),
        const Tab(text: 'MD5'),
      ];

  late EncoderType type;
  late TabController tabController;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  String inputText = '';
  TextEditingController outputTextController = TextEditingController();

  @override
  void initState() {
    super.initState();
    type = widget.type;
    inputText = widget.text ?? '';

    tabController = TabController(initialIndex: type.index, length: EncoderType.values.length, vsync: this);
    HardwareKeyboard.instance.addHandler(onKeyEvent);
  }

  @override
  void dispose() {
    tabController.dispose();
    HardwareKeyboard.instance.removeHandler(onKeyEvent);
    super.dispose();
  }

  bool onKeyEvent(KeyEvent event) {
    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      HardwareKeyboard.instance.removeHandler(onKeyEvent);
      tabController.dispose();
      widget.windowController?.close();
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
          title: Text('${type.name.toUpperCase()}${localizations.encode}', style: const TextStyle(fontSize: 16)),
          centerTitle: true,
          bottom: TabBar(
            controller: tabController,
            isScrollable: true,
            tabs: _tabs(localizations),
            onTap: (index) {
              setState(() {
                type = EncoderType.values[index];
                outputTextController.clear();
              });
            },
          )),
      body: Container(
        padding: const EdgeInsets.all(10),
        child: ListView(
          children: <Widget>[
            Text(localizations.encodeInput),
            const SizedBox(height: 5),
            TextFormField(
                initialValue: inputText,
                minLines: 5,
                maxLines: 10,
                onChanged: (text) => inputText = text,
                decoration: const InputDecoration(border: OutlineInputBorder())),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                FilledButton(onPressed: encode, child: Text('${type.name.toUpperCase()}${localizations.encode}')),
                const SizedBox(width: 20),
                type == EncoderType.md5
                    ? const SizedBox()
                    : OutlinedButton(
                        onPressed: decode, child: Text('${type.name.toUpperCase()}${localizations.decode}')),
              ],
            ),
            Text(localizations.encodeResult),
            const SizedBox(height: 5),
            TextFormField(
              controller: outputTextController,
              readOnly: true,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            FilledButton(
                style: Buttons.buttonStyle,
                child: Text(localizations.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: outputTextController.text));
                  FlutterToastr.show(localizations.copied, context);
                }),
          ],
        ),
      ),
    );
  }

  ///编码
  void encode() {
    var result = '';
    try {
      switch (type) {
        case EncoderType.url:
          result = Uri.encodeFull(inputText);
        case EncoderType.base64:
          result = base64.encode(utf8.encode(inputText));
        case EncoderType.md5:
          result = md5.convert(utf8.encode(inputText)).toString();
        case EncoderType.hex:
          result = utf8.encode(inputText).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        case EncoderType.unicode:
          result = encodeToUnicode(inputText);
        case EncoderType.base32:
          result = encodeBase32(utf8.encode(inputText));
        case EncoderType.html:
          result = htmlEscape.convert(inputText);
        case EncoderType.gzip:
          result = gzipEncode(inputText);
        case EncoderType.deflate:
          result = zlibEncode(inputText);
        case EncoderType.urlParams:
          result = encodeQuery(inputText);
      }
    } catch (e) {
      FlutterToastr.show(localizations.encodeFail, context);
    }
    outputTextController.text = result;
  }

  ///解码
  void decode() {
    var result = '';
    try {
      switch (type) {
        case EncoderType.url:
          result = Uri.decodeFull(inputText);
        case EncoderType.base64:
          // base64.
          var text = inputText.replaceAll('.', '');
          if (text.length % 4 != 0) {
            text = text.padRight(text.length + (4 - text.length % 4), '=');
          }
          Uint8List compressed = base64.decode(text);
          try {
            result = utf8.decode(compressed);
          } catch (e) {
            result = String.fromCharCodes(compressed);
          }
        case EncoderType.hex:
          var hexText = inputText.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
          if (hexText.length.isOdd) hexText = '0$hexText';
          final bytes = <int>[];
          for (var i = 0; i < hexText.length; i += 2) {
            bytes.add(int.parse(hexText.substring(i, i + 2), radix: 16));
          }
          try {
            result = utf8.decode(bytes);
          } catch (e) {
            result = String.fromCharCodes(bytes);
          }
        case EncoderType.md5:
        case EncoderType.unicode:
          result = decodeFromUnicode(inputText);
        case EncoderType.base32:
          result = utf8.decode(decodeBase32(inputText), allowMalformed: true);
        case EncoderType.html:
          result = unescapeHtml(inputText);
        case EncoderType.gzip:
          result = gzipDecode(inputText);
        case EncoderType.deflate:
          result = zlibDecode(inputText);
        case EncoderType.urlParams:
          result = decodeQuery(inputText);
      }
    } catch (e, t) {
      logger.e("$e", error: e, stackTrace: t);
      FlutterToastr.show(localizations.decodeFail, context);
    }
    outputTextController.text = result;
  }

  String encodeToUnicode(String input) {
    return input.runes.map((rune) => '\\u${rune.toRadixString(16).padLeft(4, '0')}').join();
  }

  String decodeFromUnicode(String input) {
    return input.replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'), (match) {
      return String.fromCharCode(int.parse(match.group(1)!, radix: 16));
    });
  }

  static const String _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  String encodeBase32(List<int> bytes) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final b in bytes) {
      buffer = (buffer << 8) | (b & 0xff);
      bits += 8;
      while (bits >= 5) {
        out.write(_base32Alphabet[(buffer >> (bits - 5)) & 31]);
        bits -= 5;
      }
    }
    if (bits > 0) {
      out.write(_base32Alphabet[(buffer << (5 - bits)) & 31]);
    }
    while (out.length % 8 != 0) {
      out.write('=');
    }
    return out.toString();
  }

  List<int> decodeBase32(String input) {
    final clean = input.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');
    final out = <int>[];
    var buffer = 0;
    var bits = 0;
    for (var i = 0; i < clean.length; i++) {
      final v = _base32Alphabet.indexOf(clean[i]);
      if (v < 0) continue;
      buffer = (buffer << 5) | v;
      bits += 5;
      if (bits >= 8) {
        out.add((buffer >> (bits - 8)) & 0xff);
        bits -= 8;
      }
    }
    return out;
  }

  String unescapeHtml(String input) {
    var result = input
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&');
    result = result.replaceAllMapped(
        RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
    result = result.replaceAllMapped(
        RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)));
    return result;
  }

  String gzipEncode(String input) {
    return base64.encode(gzip.encode(utf8.encode(input)));
  }

  String gzipDecode(String input) {
    return utf8.decode(gzip.decode(base64.decode(input.trim())), allowMalformed: true);
  }

  String zlibEncode(String input) {
    return base64.encode(zlib.encode(utf8.encode(input)));
  }

  String zlibDecode(String input) {
    return utf8.decode(zlib.decode(base64.decode(input.trim())), allowMalformed: true);
  }

  String encodeQuery(String input) {
    final params = <String, String>{};
    for (final line in input.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final idx = t.indexOf('=');
      if (idx < 0) {
        params[t] = '';
      } else {
        params[t.substring(0, idx).trim()] = t.substring(idx + 1).trim();
      }
    }
    return params.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
  }

  String decodeQuery(String input) {
    final out = <String>[];
    for (final pair in input.split('&')) {
      if (pair.trim().isEmpty) continue;
      final idx = pair.indexOf('=');
      if (idx < 0) {
        out.add(Uri.decodeQueryComponent(pair.trim()));
      } else {
        out.add('${Uri.decodeQueryComponent(pair.substring(0, idx).trim())} = '
            '${Uri.decodeQueryComponent(pair.substring(idx + 1).trim())}');
      }
    }
    return out.join('\n');
  }
}
