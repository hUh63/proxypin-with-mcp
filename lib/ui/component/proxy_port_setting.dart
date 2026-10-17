import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/server.dart';

class PortWidget extends StatefulWidget {
  final ProxyServer proxyServer;
  final TextStyle? textStyle;
  final String? title;

  const PortWidget({super.key, required this.proxyServer, this.textStyle, this.title});

  @override
  State<StatefulWidget> createState() {
    return _PortState();
  }
}

class _PortState extends State<PortWidget> {
  final textController = TextEditingController();
  final FocusNode portFocus = FocusNode();

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    textController.text = widget.proxyServer.port.toString();
    portFocus.addListener(() async {
      //失去焦点
      if (!portFocus.hasFocus && textController.text != widget.proxyServer.port.toString()) {
        final port = int.tryParse(textController.text) ?? -1;
        if (port < 0 || port > 65535) {
          textController.text = widget.proxyServer.port.toString();
          FlutterToastr.show("Port out of range 0-65535", context, duration: 3);
          return;
        }

        widget.proxyServer.configuration.port = port;

        if (widget.proxyServer.isRunning) {
          String message = localizations.proxyPortRepeat(widget.proxyServer.port);
          widget.proxyServer.restart().catchError((e) => FlutterToastr.show(message, context, duration: 3));
        }
        widget.proxyServer.configuration.flushConfig();
      }
    });
  }

  @override
  void didUpdateWidget(covariant PortWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 端口可能在别处被改动（配置导入 config_management、MCP set_port），
    // 而 Configuration 不是 Listenable、不会主动通知。父级重建时在这里把
    // 输入框拉回真值，避免页面一直显示进入时的旧端口。用户正在输入时不打断。
    if (portFocus.hasFocus) return;
    final current = widget.proxyServer.port.toString();
    if (textController.text != current) {
      textController.text = current;
    }
  }

  @override
  void dispose() {
    portFocus.dispose();
    textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Padding(padding: EdgeInsets.only(left: 15)),
      Text(widget.title ?? localizations.port, style: widget.textStyle),
      SizedBox(
          width: 80,
          child: TextFormField(
            focusNode: portFocus,
            controller: textController,
            textAlign: TextAlign.center,
            onTapOutside: (event) => portFocus.unfocus(),
            keyboardType: TextInputType.datetime,
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(5),
              FilteringTextInputFormatter.allow(RegExp("[0-9]"))
            ],
            decoration: const InputDecoration(),
          ))
    ]);
  }
}
