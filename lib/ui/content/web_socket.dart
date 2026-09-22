import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/utils/lang.dart';
import 'package:proxypin/utils/num.dart';

import '../../l10n/app_localizations.dart';
import '../../network/http/http.dart';
import '../../network/http/websocket.dart';
import '../../network/util/ws_payload_decoder.dart';
import '../../utils/platform.dart';
import '../component/app_dialog.dart';
import '../component/json/json_text.dart';
import '../component/json/json_viewer.dart';
import '../component/json/theme.dart';

///以聊天对话框样式展示websocket消息
class Websocket extends StatelessWidget {
  final ValueWrap<HttpRequest> request;
  final ValueWrap<HttpResponse> response;

  const Websocket(this.request, this.response, {super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    var request = this.request.get();
    if (request == null) {
      return const SizedBox();
    }
    List<WebSocketFrame> messages = List.from(request.messages);
    var response = this.response.get();
    if (response != null) {
      messages.addAll(response.messages);
    }
    messages.sort((a, b) => a.time.compareTo(b.time));

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 15),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        var message = messages[index];
        var avatar = SelectionContainer.disabled(
            child: CircleAvatar(
                backgroundColor: message.isFromClient ? Colors.green : Colors.blue,
                child:
                    Text(message.isFromClient ? 'C' : 'S', style: const TextStyle(fontSize: 18, color: Colors.white))));

        var previewButton = IconButton(
          tooltip: "Preview",
          onPressed: () {
            showDialog(context: context, builder: (context) => _PreviewDialog(bytes: message.payloadData));
          },
          icon: Icon(Icons.expand_more, color: ColorScheme.of(context).primary),
        );

        return Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              mainAxisAlignment: message.isFromClient ? MainAxisAlignment.start : MainAxisAlignment.end,
              children: [
                if (message.isFromClient) avatar,
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                      crossAxisAlignment: message.isFromClient ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                      children: [
                        SelectionContainer.disabled(
                            child:
                                Text(message.time.format(), style: const TextStyle(fontSize: 12, color: Colors.grey))),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          if (!message.isFromClient) previewButton,
                          Flexible(
                            child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: message.isFromClient
                                      ? Colors.green.withValues(alpha: 0.26)
                                      : Colors.blue.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: SelectableText(
                                  _bubbleText(message),
                                  maxLines: 3,
                                  minLines: 1,
                                  contextMenuBuilder: (context, editableTextState) =>
                                      contextMenu(context, editableTextState,
                                          customItem: ContextMenuButtonItem(
                                            label: localizations.download,
                                            onPressed: () => _savePayload(context, message.payloadData),
                                            type: ContextMenuButtonType.custom,
                                          )),
                                )),
                          ),
                          if (message.isFromClient) previewButton,
                        ])
                      ]),
                ),
                const SizedBox(width: 8),
                if (!message.isFromClient) avatar,
              ],
            ));
      },
    );
  }

  /// 列表气泡展示文本：二进制帧先自动解码，尽量给出可读内容（上游 #623）
  static String _bubbleText(WebSocketFrame message) {
    if (!message.isBinary) {
      return message.payloadDataAsString;
    }
    final decoded = WsPayloadDecoder.decode(message.payloadData);
    if (decoded.kind == WsPayloadKind.text || decoded.kind == WsPayloadKind.json) {
      return decoded.text ?? decoded.label;
    }
    // 图片 / 压缩 / 未知二进制：展示识别出的类型标签，点开预览可进一步查看
    return '[${decoded.label}]';
  }
}

class _PreviewDialog extends StatefulWidget {
  final List<int> bytes;

  const _PreviewDialog({required this.bytes});

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  int tabIndex = 0; // 当前选中的 tab（含动态 tab 时用于保持位置）

  /// 每次打开对话框解码一次（字节不变）
  late final WsDecodedPayload _decoded = WsPayloadDecoder.decode(Uint8List.fromList(widget.bytes));
  late final bool _isJson = _decoded.text != null && WsPayloadDecoder.looksJson(_decoded.text!);

  @override
  Widget build(BuildContext context) {
    final tabs = <Tab>[];
    final views = <Widget>[];

    // 图片：直接渲染（上游 #623）
    if (_decoded.hasImage) {
      tabs.add(const Tab(text: 'IMAGE'));
      views.add(_scroll(imageView()));
    }
    // 压缩解压出的文本
    if (_decoded.kind == WsPayloadKind.compressed && _decoded.text != null) {
      tabs.add(const Tab(text: 'DECOMPRESSED'));
      views.add(_scroll(SelectableText(_decoded.text!)));
    }
    // JSON（文本或解压后）
    if (_isJson) {
      tabs.add(const Tab(text: 'JSON Text'));
      views.add(_scroll(jsonText()));
      tabs.add(const Tab(text: 'JSON'));
      views.add(_scroll(jsonView()));
    }
    // 始终提供 TEXT / HEX
    tabs.add(const Tab(text: 'TEXT'));
    views.add(_scroll(SelectableText(safeTextPreview(widget.bytes))));
    tabs.add(const Tab(text: 'HEX'));
    views.add(_scroll(SelectableText(widget.bytes.map(intToHex).join(" "))));

    final initial = tabIndex < tabs.length ? tabIndex : 0;

    return AlertDialog(
      content: SizedBox(
        width: min(MediaQuery.of(context).size.width * 0.8, 700),
        height: min(MediaQuery.of(context).size.height * 0.6, 650),
        child: DefaultTabController(
          length: tabs.length,
          initialIndex: initial,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TabBar(
              isScrollable: true,
              tabs: tabs,
              onTap: (index) {
                setState(() {
                  tabIndex = index;
                });
              },
            ),
            Expanded(child: TabBarView(children: views)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => _savePayload(context, widget.bytes), child: const Text('保存')),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel))
      ],
    );
  }

  Widget _scroll(Widget child) =>
      SingleChildScrollView(padding: const EdgeInsets.all(8.0), child: child);

  /// 图片视图（上游 #623）
  Widget imageView() {
    final bytes = _decoded.imageBytes;
    if (bytes == null) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_decoded.label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => Text('无法渲染图片：$error'),
        ),
      ],
    );
  }

  Widget jsonText() {
    var body = _decoded.text ?? safeTextPreview(widget.bytes);
    dynamic jsonData;
    try {
      jsonData = json.decode(body);
    } catch (e) {
      jsonData = null;
    }

    if (jsonData == null) {
      return SelectableText(safeTextPreview(widget.bytes));
    }

    return JsonText(json: jsonData, indent: Platforms.isDesktop() ? '    ' : '  ', colorTheme: ColorTheme.of(context));
  }

  Widget jsonView() {
    var body = _decoded.text ?? safeTextPreview(widget.bytes);
    return JsonViewer(json.decode(body), colorTheme: ColorTheme.of(context));
  }

  /// Decode bytes to string, non-printable as '.'
  String safeTextPreview(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return bytes.map((b) => b >= 32 && b <= 126 ? String.fromCharCode(b) : '.').join();
    }
  }
}

/// 保存 WebSocket 载荷为文件。
///
/// 桌面端统一走 [Platforms.saveFileAdaptive] 拿路径后自行写盘——`FilePicker.saveFile`
/// 在桌面端不保证写出 bytes（上游 #902 同款问题）。文件扩展名按识别结果给出，
/// 图片存成对应图片格式，文本/JSON 存成 .txt，其余存 .bin。
Future<void> _savePayload(BuildContext context, List<int> bytes) async {
  final decoded = WsPayloadDecoder.decode(Uint8List.fromList(bytes));
  final ext = decoded.imageFormat ??
      ((decoded.kind == WsPayloadKind.text || decoded.kind == WsPayloadKind.json) ? 'txt' : 'bin');
  final String? path = await Platforms.saveFileAdaptive(fileName: 'websocket.$ext');
  if (path == null) return;
  await File(path).writeAsBytes(bytes);
  if (context.mounted) {
    CustomToast.success(AppLocalizations.of(context)!.saveSuccess).show(context);
  }
}
