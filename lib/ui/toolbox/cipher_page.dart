import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/util/logger.dart';

import '../component/buttons.dart';
import '../component/text_field.dart';
import '../../utils/crypto_tools.dart';

/// 通用对称加解密工具页：AES / DES / 3DES / SM4 / ChaCha20 / XOR。
/// 密钥与 IV 支持 `base64:` 前缀，否则按 UTF-8 文本处理。
class CipherPage extends StatefulWidget {
  final String initialAlgorithm;
  final String? text;

  const CipherPage({super.key, this.initialAlgorithm = 'AES', this.text});

  @override
  State<CipherPage> createState() => _CipherPageState();
}

class _CipherPageState extends State<CipherPage> {
  final TextEditingController inputController = TextEditingController();
  final TextEditingController outputController = TextEditingController();
  final TextEditingController keyController = TextEditingController();
  final TextEditingController ivController = TextEditingController();

  late String algorithm;
  String mode = 'CBC';
  String padding = 'PKCS7';
  late int keyLength;
  String outputEncoding = 'Base64';

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    algorithm = widget.initialAlgorithm;
    keyLength = CipherTools.defaultKeyLength(algorithm);
    inputController.text = widget.text ?? '';
  }

  @override
  void dispose() {
    inputController.dispose();
    outputController.dispose();
    keyController.dispose();
    ivController.dispose();
    super.dispose();
  }

  bool get _isStream => CipherTools.isStream(algorithm);

  bool get _hasKeyLength => CipherTools.keyLengthsOf(algorithm).isNotEmpty;

  Uint8List _inputBytes(bool encrypt) {
    final raw = inputController.text.trim();
    if (encrypt) {
      return Uint8List.fromList(utf8.encode(inputController.text));
    }
    if (outputEncoding == 'Hex') {
      return _hexDecode(raw);
    }
    return Uint8List.fromList(base64.decode(raw));
  }

  String _outputText(Uint8List bytes, bool encrypt) {
    if (encrypt) {
      return outputEncoding == 'Hex' ? _toHex(bytes) : base64.encode(bytes);
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return _toHex(bytes);
    }
  }

  void process(bool encrypt) {
    try {
      final result = CipherTools.process(
        _inputBytes(encrypt),
        algorithm: algorithm,
        encrypt: encrypt,
        key: keyController.text,
        mode: mode,
        padding: padding,
        iv: ivController.text,
        keyLength: keyLength,
      );
      outputController.text = _outputText(result, encrypt);
    } catch (e) {
      outputController.text = '';
      logger.e('Cipher error: $e');
      FlutterToastr.show(encrypt ? localizations.cryptoEncryptFailed : localizations.cryptoDecryptFailed, context,
          duration: 3, backgroundColor: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(algorithm, style: const TextStyle(fontSize: 16)), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(15),
        child: ListView(children: [
          const SizedBox(height: 5),
          SizedBox(
              height: 130,
              child: TextField(
                  controller: inputController,
                  maxLines: 8,
                  onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: decoration(context, label: localizations.inputContent))),
          const SizedBox(height: 12),
          Wrap(spacing: 18, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _dropdown(localizations.commonAlgorithm, algorithm, CipherTools.algorithms, (v) {
              setState(() {
                algorithm = v!;
                final lens = CipherTools.keyLengthsOf(algorithm);
                keyLength = CipherTools.defaultKeyLength(algorithm);
                if (lens.isEmpty) keyLength = 0;
                if (CipherTools.isStream(algorithm)) {
                  mode = 'ECB';
                  padding = 'None';
                }
              });
            }, width: 150),
            if (!_isStream)
              _dropdown(localizations.commonMode, mode, CipherTools.modes,
                  (v) => setState(() => mode = v!), width: 130),
            if (!_isStream)
              _dropdown(localizations.commonPadding, padding, CipherTools.paddings,
                  (v) => setState(() => padding = v!), width: 160),
            if (_hasKeyLength)
              DropdownButton<int>(
                value: keyLength,
                items: CipherTools.keyLengthsOf(algorithm)
                    .map((l) => DropdownMenuItem<int>(value: l, child: Text(localizations.commonBits('$l'))))
                    .toList(),
                onChanged: (v) => setState(() => keyLength = v!),
              ),
            _dropdown(localizations.format, outputEncoding, const ['Base64', 'Hex'],
                (v) => setState(() => outputEncoding = v!), width: 150),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 18, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _field(localizations.commonKey, keyController, 64),
            if (!_isStream) _field('IV', ivController, 32),
          ]),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton(
                  style: _roundStyle(),
                  onPressed: () => process(true),
                  child: Text(localizations.encrypt)),
              const SizedBox(width: 60),
              FilledButton(
                  style: _roundStyle(),
                  onPressed: () => process(false),
                  child: Text(localizations.decrypt)),
            ],
          ),
          const SizedBox(height: 5),
          Text(localizations.output),
          const SizedBox(height: 5),
          TextFormField(
            controller: outputController,
            readOnly: true,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            style: Buttons.buttonStyle,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: outputController.text));
              FlutterToastr.show(localizations.copied, context);
            },
            icon: const Icon(Icons.copy),
            label: Text(localizations.copy),
          ),
        ]),
      ),
    );
  }

  Widget _dropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged,
      {double width = 180}) {
    return SizedBox(
      width: width,
      child: Row(children: [
        Text(label),
        const SizedBox(width: 10),
        DropdownButton<String>(
          value: value,
          items: items.map((v) => DropdownMenuItem<String>(value: v, child: Text(v))).toList(),
          onChanged: onChanged,
        ),
      ]),
    );
  }

  Widget _field(String label, TextEditingController controller, int maxLength) {
    return SizedBox(
      width: 300,
      child: Row(children: [
        SizedBox(width: 40, child: Text(label)),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            maxLength: maxLength,
            onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
                border: OutlineInputBorder(),
                counterText: '',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
          ),
        ),
      ]),
    );
  }

  ButtonStyle _roundStyle() => ButtonStyle(
      shape: WidgetStateProperty.all<RoundedRectangleBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));

  static String _toHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Uint8List _hexDecode(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s+'), '');
    if (clean.length.isOdd) {
      throw FormatException(localizations.cryptoHexEvenLength);
    }
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
