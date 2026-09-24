/*
 * Copyright 2023 Hongen Wang
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
import 'package:flutter/services.dart';
import 'package:proxypin/network/util/calc_engine.dart';

/// 计算与编解码工具箱：进制/补码、位运算、字节序、IEEE754、CRC 与哈希。
///
/// 与 MCP 的 `calculator` 工具共用同一个引擎（[CalcEngine]），
/// 所以界面上算出来的结果和让 AI 算出来的结果是同一套实现，不会互相打架。
class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(length: 5, vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('计算器'),
        bottom: TabBar(
          controller: _controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: '进制/补码'),
            Tab(text: '位运算'),
            Tab(text: '字节序'),
            Tab(text: 'IEEE754'),
            Tab(text: 'CRC/哈希'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _controller,
        children: const [
          _IntConvertTab(),
          _BitwiseTab(),
          _EndianTab(),
          _Ieee754Tab(),
          _CrcHashTab(),
        ],
      ),
    );
  }
}

// ==================== 通用小部件 ====================

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final int lines;

  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.lines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: lines,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isDense: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: items
            .map((item) => DropdownMenuItem<T>(value: item, child: Text(labelOf(item))))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// 结果展示：把引擎返回的 Map 逐行列出，点一下即可复制该行取值。
class _ResultView extends StatelessWidget {
  final Map<String, dynamic>? data;

  const _ResultView({this.data});

  @override
  Widget build(BuildContext context) {
    final result = data;
    if (result == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('输入后点「计算」查看结果', style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }
    if (result.containsKey('error')) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('${result['error']}',
            style: const TextStyle(color: Colors.red, fontSize: 13, fontFamily: 'monospace')),
      );
    }
    final rows = result.entries.where((e) => !e.key.startsWith('_')).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows.map((e) {
        final text = e.value is List ? e.value.join(', ') : '${e.value}';
        return InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('已复制 ${e.key}'), duration: const Duration(seconds: 1)));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 150,
                  child: Text(e.key,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  child: SelectableText(
                    text,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _RunButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RunButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          FilledButton(onPressed: onPressed, child: const Text('计算')),
        ],
      ),
    );
  }
}

// ==================== 1. 进制与补码 ====================

class _IntConvertTab extends StatefulWidget {
  const _IntConvertTab();

  @override
  State<_IntConvertTab> createState() => _IntConvertTabState();
}

class _IntConvertTabState extends State<_IntConvertTab> {
  final _value = TextEditingController(text: '0xFFFF');
  int _width = 16;
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _compute() {
    setState(() {
      _result = CalcEngine.run('int_convert', {'value': _value.text, 'width': _width});
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Field(
          label: '数值',
          controller: _value,
          hint: '支持 0x / 0b / 0o / 十进制，可带负号',
        ),
        _Dropdown<int>(
          label: '位宽',
          value: _width,
          items: const [8, 16, 32, 64, 128],
          labelOf: (v) => '$v 位',
          onChanged: (v) => setState(() => _width = v),
        ),
        _RunButton(onPressed: _compute),
        _ResultView(data: _result),
      ],
    );
  }
}

// ==================== 2. 位运算 ====================

class _BitwiseTab extends StatefulWidget {
  const _BitwiseTab();

  @override
  State<_BitwiseTab> createState() => _BitwiseTabState();
}

class _BitwiseTabState extends State<_BitwiseTab> {
  final _a = TextEditingController(text: '0xF0F0');
  final _b = TextEditingController(text: '0x0FF0');
  String _operation = 'and';
  int _width = 32;
  Map<String, dynamic>? _result;

  static const _ops = ['and', 'or', 'xor', 'not', 'shl', 'shr', 'sar', 'rol', 'ror'];
  static const _shiftOps = {'shl', 'shr', 'sar', 'rol', 'ror'};

  bool get _isShift => _shiftOps.contains(_operation);

  @override
  void initState() {
    super.initState();
    _compute();
  }

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _compute() {
    final args = <String, dynamic>{
      'operation': _operation,
      'a': _a.text,
      'width': _width,
    };
    if (_isShift) {
      // 位移量按十进制传，避免「0x0FF0」被当成位移 4080 位
      args['shift'] = _b.text;
    } else if (_operation != 'not') {
      args['b'] = _b.text;
    }
    setState(() => _result = CalcEngine.run('bitwise', args));
  }

  @override
  Widget build(BuildContext context) {
    final needsB = _operation != 'not';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Dropdown<String>(
          label: '运算',
          value: _operation,
          items: _ops,
          labelOf: (v) => v,
          onChanged: (v) => setState(() => _operation = v),
        ),
        _Field(label: '操作数 A', controller: _a),
        if (needsB)
          _Field(
            label: _isShift ? '位移量（十进制）' : '操作数 B',
            controller: _b,
            hint: _isShift ? '例如 4' : '例如 0x0FF0',
          ),
        _Dropdown<int>(
          label: '位宽',
          value: _width,
          items: const [8, 16, 32, 64],
          labelOf: (v) => '$v 位',
          onChanged: (v) => setState(() => _width = v),
        ),
        _RunButton(onPressed: _compute),
        _ResultView(data: _result),
      ],
    );
  }
}

// ==================== 3. 字节序 ====================

class _EndianTab extends StatefulWidget {
  const _EndianTab();

  @override
  State<_EndianTab> createState() => _EndianTabState();
}

class _EndianTabState extends State<_EndianTab> {
  final _value = TextEditingController(text: '0x78563412');
  int? _widthBytes;
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _compute() {
    final args = <String, dynamic>{'value': _value.text};
    if (_widthBytes != null) args['widthBytes'] = _widthBytes;
    setState(() => _result = CalcEngine.run('endian_swap', args));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Field(label: '十六进制数据', controller: _value, hint: '例如 0x78563412'),
        _Dropdown<int>(
          label: '字节宽度',
          value: _widthBytes ?? 0,
          items: const [0, 2, 4, 8, 16],
          labelOf: (v) => v == 0 ? '按输入长度' : '$v 字节',
          onChanged: (v) => setState(() => _widthBytes = v == 0 ? null : v),
        ),
        _RunButton(onPressed: _compute),
        _ResultView(data: _result),
      ],
    );
  }
}

// ==================== 4. IEEE 754 ====================

class _Ieee754Tab extends StatefulWidget {
  const _Ieee754Tab();

  @override
  State<_Ieee754Tab> createState() => _Ieee754TabState();
}

class _Ieee754TabState extends State<_Ieee754Tab> {
  final _value = TextEditingController(text: '0x3f800000');
  String _precision = 'float32';
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _compute() {
    setState(() {
      _result = CalcEngine.run('ieee754', {'value': _value.text, 'precision': _precision});
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Field(
          label: '机器码或数值',
          controller: _value,
          hint: '十六进制机器码（如 0x3f800000）或十进制小数（如 1.5）',
        ),
        _Dropdown<String>(
          label: '精度',
          value: _precision,
          items: const ['float32', 'float64'],
          labelOf: (v) => v,
          onChanged: (v) => setState(() => _precision = v),
        ),
        _RunButton(onPressed: _compute),
        _ResultView(data: _result),
      ],
    );
  }
}

// ==================== 5. CRC 与哈希 ====================

class _CrcHashTab extends StatefulWidget {
  const _CrcHashTab();

  @override
  State<_CrcHashTab> createState() => _CrcHashTabState();
}

class _CrcHashTabState extends State<_CrcHashTab> {
  final _data = TextEditingController(text: '31 32 33 34 35 36 37 38 39');
  String _kind = 'crc32';
  String _inputFormat = 'hex';
  Map<String, dynamic>? _result;

  static const _crcAlgorithms = ['crc32', 'crc16_ccitt', 'crc16_modbus', 'crc16_xmodem', 'crc16_ibm'];
  static const _hashAlgorithms = ['md5', 'sha1', 'sha256', 'sha512'];

  bool get _isCrc => _kind.startsWith('crc');

  @override
  void initState() {
    super.initState();
    _compute();
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  void _compute() {
    setState(() {
      if (_isCrc) {
        _result = CalcEngine.run('crc', {
          'algorithm': _kind,
          'data': _data.text,
          'inputFormat': _inputFormat,
        });
      } else {
        _result = CalcEngine.run('hash', {
          'algorithm': _kind,
          'data': _data.text,
          'inputFormat': _inputFormat,
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Dropdown<String>(
          label: '算法',
          value: _kind,
          items: [..._crcAlgorithms, ..._hashAlgorithms],
          labelOf: (v) => v,
          onChanged: (v) => setState(() => _kind = v),
        ),
        _Dropdown<String>(
          label: '输入格式',
          value: _inputFormat,
          items: const ['hex', 'utf8', 'base64'],
          labelOf: (v) => v,
          onChanged: (v) => setState(() => _inputFormat = v),
        ),
        _Field(label: '数据', controller: _data, lines: 3),
        _RunButton(onPressed: _compute),
        _ResultView(data: _result),
      ],
    );
  }
}
