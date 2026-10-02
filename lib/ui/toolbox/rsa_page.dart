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

/// RSA 工具页：加解密（PKCS#1 v1.5 / OAEP）、签名验签、密钥生成。
class RsaPage extends StatefulWidget {
  final String? text;

  const RsaPage({super.key, this.text});

  @override
  State<RsaPage> createState() => _RsaPageState();
}

class _RsaPageState extends State<RsaPage> {
  static const List<String> _modes = <String>['Encrypt', 'Decrypt', 'Sign', 'Verify', 'Generate'];

  final TextEditingController keyController = TextEditingController();
  final TextEditingController inputController = TextEditingController();
  final TextEditingController signatureController = TextEditingController();
  final TextEditingController outputController = TextEditingController();

  String mode = 'Encrypt';
  String signAlgorithm = 'SHA-256';
  bool oaep = false;

  String _modeLabel(String m) => switch (m) {
        'Encrypt' => localizations.encrypt,
        'Decrypt' => localizations.decrypt,
        'Sign' => localizations.commonSign,
        'Verify' => localizations.commonVerify,
        'Generate' => localizations.commonGenerate,
        _ => m,
      };

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    inputController.text = widget.text ?? '';
  }

  @override
  void dispose() {
    keyController.dispose();
    inputController.dispose();
    signatureController.dispose();
    outputController.dispose();
    super.dispose();
  }

  void run() {
    try {
      switch (mode) {
        case 'Generate':
          final pair = RsaTools.generateKeyPair(keySize: 2048);
          keyController.text = pair[1];
          outputController.text = pair[0];
          break;
        case 'Encrypt':
          final ct = RsaTools.encrypt(
              Uint8List.fromList(utf8.encode(inputController.text)), keyController.text,
              oaep: oaep);
          outputController.text = base64.encode(ct);
          break;
        case 'Decrypt':
          final pt = RsaTools.decrypt(base64.decode(inputController.text.trim()), keyController.text,
              oaep: oaep);
          outputController.text = _tryUtf8(pt);
          break;
        case 'Sign':
          final sig = RsaTools.sign(
              Uint8List.fromList(utf8.encode(inputController.text)), keyController.text, signAlgorithm);
          outputController.text = base64.encode(sig);
          break;
        case 'Verify':
          final ok = RsaTools.verify(
              Uint8List.fromList(utf8.encode(inputController.text)),
              base64.decode(signatureController.text.trim()),
              keyController.text,
              signAlgorithm);
          outputController.text = ok ? localizations.cryptoValidSig : localizations.cryptoInvalidSig;
          break;
      }
    } catch (e) {
      outputController.text = '';
      logger.e('RSA error: $e');
      FlutterToastr.show(localizations.commonError('$e'), context, duration: 3, backgroundColor: Colors.red);
    }
  }

  static String _tryUtf8(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return base64.encode(bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final needKey = mode != 'Generate';
    return Scaffold(
      appBar: AppBar(title: const Text('RSA', style: TextStyle(fontSize: 16)), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(15),
        child: ListView(children: [
          Wrap(spacing: 18, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 180,
              child: Row(children: [
                Text(localizations.commonMode),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: mode,
                  items: _modes.map((m) => DropdownMenuItem<String>(value: m, child: Text(_modeLabel(m)))).toList(),
                  onChanged: (v) => setState(() => mode = v!),
                ),
              ]),
            ),
            if (mode == 'Sign' || mode == 'Verify')
              SizedBox(
                width: 240,
                child: Row(children: [
                  Text(localizations.toolboxHash),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: signAlgorithm,
                    items: RsaTools.signAlgorithms
                        .map((a) => DropdownMenuItem<String>(value: a, child: Text(a)))
                        .toList(),
                    onChanged: (v) => setState(() => signAlgorithm = v!),
                  ),
                ]),
              ),
            if (mode == 'Encrypt' || mode == 'Decrypt')
              Row(children: [
                const Text('OAEP'),
                Switch(value: oaep, onChanged: (v) => setState(() => oaep = v)),
              ]),
          ]),
          const SizedBox(height: 12),
          if (needKey) ...[
            SizedBox(
                height: 140,
                child: TextField(
                    controller: keyController,
                    maxLines: 8,
                    onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: decoration(context, label: localizations.cryptoRsaKey))),
            const SizedBox(height: 12),
          ],
          if (mode != 'Generate') ...[
            Text(mode == 'Verify' ? localizations.commonMessage : localizations.inputContent),
            const SizedBox(height: 5),
            SizedBox(
                height: 120,
                child: TextField(
                    controller: inputController,
                    maxLines: 8,
                    onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: decoration(context))),
            const SizedBox(height: 12),
          ],
          if (mode == 'Verify') ...[
            TextField(
                controller: signatureController,
                onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
                decoration: decoration(context, label: localizations.cryptoRsaSignature)),
            const SizedBox(height: 12),
          ],
          Center(
            child: FilledButton(
              style: ButtonStyle(
                  shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
              onPressed: run,
              child: Text(_modeLabel(mode)),
            ),
          ),
          const SizedBox(height: 14),
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
}
