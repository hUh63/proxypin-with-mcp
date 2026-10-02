import 'dart:convert';
import 'dart:typed_data';

import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';

import '../component/buttons.dart';
import '../component/text_field.dart';
import '../../utils/crypto_tools.dart';

/// 哈希 / 消息认证 / 口令散列工具页：Hash、HMAC、Bcrypt。
class HashPage extends StatefulWidget {
  final int initialIndex;

  const HashPage({super.key, this.initialIndex = 0});

  @override
  State<HashPage> createState() => _HashPageState();
}

class _HashPageState extends State<HashPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialIndex.clamp(0, 2));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.toolboxHash, style: const TextStyle(fontSize: 16)),
        centerTitle: true,
        bottom: TabBar(controller: _tabController, tabs: const <Widget>[
          Tab(text: 'Hash'),
          Tab(text: 'HMAC'),
          Tab(text: 'Bcrypt'),
        ]),
      ),
      body: TabBarView(controller: _tabController, children: const <Widget>[
        _HashTab(),
        _HmacTab(),
        _BcryptTab(),
      ]),
    );
  }
}

class _HashTab extends StatefulWidget {
  const _HashTab();

  @override
  State<_HashTab> createState() => _HashTabState();
}

class _HashTabState extends State<_HashTab> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _algorithm = 'SHA-256';

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _compute() {
    try {
      final bytes = Uint8List.fromList(utf8.encode(_input.text));
      _output.text = HashTools.hex(HashTools.digest(_algorithm, bytes));
    } catch (e) {
      _output.text = '';
      FlutterToastr.show(localizations.commonError('$e'), context, duration: 3, backgroundColor: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: ListView(children: [
        SizedBox(
          width: 240,
          child: Row(children: [
            Text(localizations.commonAlgorithm),
            const SizedBox(width: 15),
            DropdownButton<String>(
              value: _algorithm,
              items: HashTools.algorithms
                  .map((a) => DropdownMenuItem<String>(value: a, child: Text(a)))
                  .toList(),
              onChanged: (v) => setState(() => _algorithm = v!),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        SizedBox(
            height: 130,
            child: TextField(
                controller: _input,
                maxLines: 8,
                onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
                decoration: decoration(context, label: localizations.inputContent))),
        const SizedBox(height: 12),
        Center(
          child: FilledButton(
            style: _roundStyle(),
            onPressed: _compute,
            child: Text(localizations.commonCompute),
          ),
        ),
        const SizedBox(height: 12),
        _outputField(context, localizations.output, _output),
        const SizedBox(height: 10),
        _copyButton(context, _output),
      ]),
    );
  }
}

class _HmacTab extends StatefulWidget {
  const _HmacTab();

  @override
  State<_HmacTab> createState() => _HmacTabState();
}

class _HmacTabState extends State<_HmacTab> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _key = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String _algorithm = 'SHA-256';

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  static const List<String> _algorithms = <String>[
    'MD5',
    'SHA-1',
    'SHA-224',
    'SHA-256',
    'SHA-384',
    'SHA-512',
  ];

  @override
  void dispose() {
    _input.dispose();
    _key.dispose();
    _output.dispose();
    super.dispose();
  }

  void _compute() {
    try {
      final bytes = Uint8List.fromList(utf8.encode(_input.text));
      final key = Uint8List.fromList(utf8.encode(_key.text));
      _output.text = HashTools.hex(HashTools.hmac(_algorithm, key, bytes));
    } catch (e) {
      _output.text = '';
      FlutterToastr.show(localizations.commonError('$e'), context, duration: 3, backgroundColor: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: ListView(children: [
        SizedBox(
          width: 240,
          child: Row(children: [
            Text(localizations.commonAlgorithm),
            const SizedBox(width: 15),
            DropdownButton<String>(
              value: _algorithm,
              items: _algorithms
                  .map((a) => DropdownMenuItem<String>(value: a, child: Text(a)))
                  .toList(),
              onChanged: (v) => setState(() => _algorithm = v!),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        TextField(
            controller: _key,
            onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: decoration(context, label: localizations.commonKey)),
        const SizedBox(height: 10),
        SizedBox(
            height: 130,
            child: TextField(
                controller: _input,
                maxLines: 8,
                onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
                decoration: decoration(context, label: localizations.inputContent))),
        const SizedBox(height: 12),
        Center(
          child: FilledButton(
            style: _roundStyle(),
            onPressed: _compute,
            child: Text(localizations.commonCompute),
          ),
        ),
        const SizedBox(height: 12),
        _outputField(context, localizations.output, _output),
        const SizedBox(height: 10),
        _copyButton(context, _output),
      ]),
    );
  }
}

class _BcryptTab extends StatefulWidget {
  const _BcryptTab();

  @override
  State<_BcryptTab> createState() => _BcryptTabState();
}

class _BcryptTabState extends State<_BcryptTab> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _output = TextEditingController();
  final TextEditingController _verify = TextEditingController();
  String _result = '';

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void dispose() {
    _password.dispose();
    _output.dispose();
    _verify.dispose();
    super.dispose();
  }

  void _hash() {
    try {
      _output.text = BCrypt.hashpw(_password.text, BCrypt.gensalt());
    } catch (e) {
      _output.text = '';
      FlutterToastr.show(localizations.commonError('$e'), context, duration: 3, backgroundColor: Colors.red);
    }
  }

  void _check() {
    try {
      final ok = BCrypt.checkpw(_password.text, _verify.text.trim());
      setState(() => _result = ok ? localizations.match : localizations.commonNotMatch);
      FlutterToastr.show(ok ? localizations.match : localizations.commonNotMatch, context,
          duration: 2, backgroundColor: ok ? Colors.green : Colors.red);
    } catch (e) {
      setState(() => _result = '');
      FlutterToastr.show(localizations.commonError('$e'), context, duration: 3, backgroundColor: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: ListView(children: [
        TextField(
            controller: _password,
            onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: decoration(context, label: localizations.password)),
        const SizedBox(height: 12),
        Center(
          child: FilledButton(
            style: _roundStyle(),
            onPressed: _hash,
            child: Text(localizations.toolboxHash),
          ),
        ),
        const SizedBox(height: 12),
        _outputField(context, 'bcrypt', _output),
        const SizedBox(height: 10),
        _copyButton(context, _output),
        const Divider(height: 32),
        TextField(
            controller: _verify,
            onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: decoration(context, label: localizations.cryptoBcryptHash)),
        const SizedBox(height: 10),
        Center(
          child: OutlinedButton(
            style: _roundStyle(),
            onPressed: _check,
            child: Text(localizations.commonVerify),
          ),
        ),
        if (_result.isNotEmpty) ...[
          const SizedBox(height: 10),
          Center(child: Text(_result)),
        ],
      ]),
    );
  }
}

InputDecoration _decoration(BuildContext context, String label) =>
    InputDecoration(border: const OutlineInputBorder(), labelText: label);

Widget _outputField(BuildContext context, String label, TextEditingController controller) {
  return TextFormField(
    controller: controller,
    readOnly: true,
    minLines: 3,
    maxLines: 6,
    decoration: _decoration(context, label),
  );
}

Widget _copyButton(BuildContext context, TextEditingController controller) {
  return FilledButton.icon(
    style: Buttons.buttonStyle,
    onPressed: () {
      Clipboard.setData(ClipboardData(text: controller.text));
      FlutterToastr.show(AppLocalizations.of(context)!.copied, context);
    },
    icon: const Icon(Icons.copy),
    label: Text(AppLocalizations.of(context)!.copy),
  );
}

ButtonStyle _roundStyle() => ButtonStyle(
    shape: WidgetStateProperty.all<RoundedRectangleBorder>(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
