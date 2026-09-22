import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/passcode.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:proxypin/ui/component/utils.dart';
import 'package:proxypin/ui/configuration.dart';
import 'package:proxypin/utils/har.dart';
import 'package:proxypin/utils/platform.dart';
import 'package:share_plus/share_plus.dart';

enum ExportType {
  request,
  response,
  requestResponse,
  har,
}

void exportRequest(HttpRequest request) async {
  String fileName = "request_${request.hostAndPort?.host}_${request.requestId}.txt";
  var json = copyRawRequest(request);

  var path = await FilePicker.saveFile(fileName: fileName, bytes: utf8.encode(json));
  logger.d("Export request to $path");
}

void exportRequestBody(HttpRequest request) async {
  String fileName = "request_body_${request.hostAndPort?.host}_${request.requestId}.txt";

  var path = await FilePicker.saveFile(
      fileName: fileName, bytes: request.body == null ? Uint8List(0) : Uint8List.fromList(request.body!));
  logger.d("Export request body to $path");
}

void exportResponse(HttpResponse? response) async {
  if (response == null) {
    logger.d("No response to export");
    return;
  }

  String fileName = "response_${response.request?.hostAndPort?.host}_${response.requestId}.txt";
  var json = await copyRawResponse(response);
  var path = await FilePicker.saveFile(fileName: fileName, bytes: utf8.encode(json));
  logger.d("Export response to $path");
}

void exportResponseBody(HttpResponse? response) async {
  if (response == null) {
    return;
  }

  String fileName = "response_body_${response.request?.hostAndPort?.host}_${response.requestId}.txt";

  var path = await FilePicker.saveFile(
      fileName: fileName, bytes: response.body == null ? Uint8List(0) : Uint8List.fromList(response.body!));
  logger.d("Export response body to $path");
}

void exportRequestAndResponse(HttpRequest request, HttpResponse? response) async {
  String fileName = "request_response_${request.hostAndPort?.host ?? ''}_${request.requestId}.txt";

  var json = copyRequest(request, response);
  var path = await FilePicker.saveFile(fileName: fileName, bytes: utf8.encode(json));
  logger.d("Export request and response to $path");
}

void exportHar(HttpRequest request) async {
  String fileName = "har_${request.hostAndPort?.host}_${request.requestId}.har";

  var entry = Har.toHar(request);
  print(entry);
  var har = {
    "log": {
      "version": "1.2",
      "creator": {"name": "ProxyPin", "version": AppConfiguration.version},
      "pages": [
        {
          "title": "ProxyPin Har Export",
          "id": "ProxyPin",
          "startedDateTime": request.requestTime.toUtc().toIso8601String(),
          "pageTimings": {"onContentLoad": -1, "onLoad": -1}
        }
      ],
      "entries": [entry],
    }
  };
  var json = jsonEncode(har);

  var path = await FilePicker.saveFile(fileName: fileName, bytes: utf8.encode(json));
  logger.d("Export har to $path");
}

/// Export response to string with decoded body
Future<String> copyRawResponse(HttpResponse response) async {
  var sb = StringBuffer();
  sb.writeln("${response.protocolVersion} ${response.status.code} ${response.status.reasonPhrase}");
  sb.write(response.headers.headerLines());
  if (response.bodyAsString.isNotEmpty) {
    sb.writeln();
    sb.write(await response.decodeBodyString());
  }
  return sb.toString();
}

/// 生成单个请求的导出文件内容（bytes）
/// 返回 Map: { 'fileName': String, 'bytes': Uint8List }
Future<Map<String, dynamic>?> generateExportFileData(
  HttpRequest request,
  ExportType type,
  int index,
) async {
  var host = request.hostAndPort?.host ?? 'unknown';
  var safeHost = host.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  var prefix = '${index + 1}_$safeHost';

  switch (type) {
    case ExportType.request:
      var content = copyRawRequest(request);
      return {
        'fileName': '${prefix}_request.txt',
        'bytes': utf8.encode(content),
      };
    case ExportType.response:
      if (request.response == null) return null;
      var content = await copyRawResponse(request.response!);
      return {
        'fileName': '${prefix}_response.txt',
        'bytes': utf8.encode(content),
      };
    case ExportType.requestResponse:
      var content = copyRequest(request, request.response);
      return {
        'fileName': '${prefix}_request_response.txt',
        'bytes': utf8.encode(content),
      };
    case ExportType.har:
      return null;
  }
}

/// 把内存中的导出内容写成**真实临时文件**后交给系统分享（iOS / iPadOS 用）。
///
/// 修复 #893：iOS 上原先直接用 `XFile.fromData(bytes, name: ...)` 交给 share_plus，
/// 但 share_plus 需要把内存数据落到临时目录时拿不到有效文件名，最终路径退化成
/// `<tmp>/<uuid>/` 这样的**目录**，抛
/// `FileSystemException: Cannot open file, path = .../Library/Caches/<UUID>/ (OS Error: Is a directory, errno = 21)`，
/// 系统分享面板也不会打开（无论选 1 条还是多条）。
/// 先写真实文件、再用 `XFile(path)` 分享即可绕开；文件名同时显式传给 fileNameOverrides，
/// 不再依赖 `XFile.name` 在不同版本上的取值行为。
Future<void> shareExportFiles(
  List<Map<String, dynamic>> items, {
  String mimeType = 'text/plain',
  Rect? sharePositionOrigin,
}) async {
  final tempDir = await Directory.systemTemp.createTemp('proxypin_export_');
  final files = <XFile>[];
  final names = <String>[];

  for (final item in items) {
    final bytes = item['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) {
      continue;
    }
    final name = (item['fileName'] as String?)?.trim();
    final fileName = (name == null || name.isEmpty) ? 'export.txt' : name;
    final file = File('${tempDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    files.add(XFile(file.path, name: fileName, mimeType: mimeType));
    names.add(fileName);
  }

  if (files.isEmpty) {
    throw StateError('no file to share');
  }

  await SharePlus.instance
      .share(ShareParams(fileNameOverrides: names, files: files, sharePositionOrigin: sharePositionOrigin));

  // 系统分享是异步读取文件的：延迟清理临时目录，避免分享尚未完成就把文件删掉。
  // 未清理时也会落在 App 的 tmp 目录里，由系统回收。
  Future.delayed(const Duration(minutes: 5), () {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (e) {
      logger.d('clean export temp dir failed: $e');
    }
  });
}

/// 批量导出请求 - 桌面端和手机端采用不同策略
/// [requests] 请求列表
/// [folderName] 文件夹名称/文件名前缀
/// [type] 导出类型
/// [context] 上下文
/// [onSuccess] 成功回调，参数为成功导出的文件数
/// [onProgress] 进度回调，参数为当前进度 (0.0-1.0)
Future<void> exportRequestsAsFiles(
  List<HttpRequest> requests,
  String folderName,
  ExportType type, {
  required BuildContext context,
  Function(int successCount)? onSuccess,
  Function(double progress)? onProgress,
}) async {
  try {
    int successCount = 0;
  String? lastError;
    final total = requests.length;

    // 通知开始导出
    onProgress?.call(0.0);

    if (Platforms.isDesktop() || Platform.isAndroid) {
      // 选择导出的父目录（saveFile 会在磁盘上创建空文件，导致无法再以同名创建文件夹）
      final baseDirectory = await FilePicker.getDirectoryPath();
      if (baseDirectory == null) return;
      String selectedDirectory = '$baseDirectory/$folderName';

      // 用户选中的路径可能不是目录（桌面端允许手输文件名），这里兜一层：
      // 不存在就建，选中的是文件则退回它的父目录
      final selectedDir = Directory(selectedDirectory);
      if (!await selectedDir.exists()) {
        await selectedDir.create(recursive: true);
      } else if (!await selectedDir.stat().then((s) => s.type == FileSystemEntityType.directory)) {
        // 如果选择的不是目录而是文件，使用其父目录
        selectedDirectory = selectedDir.parent.path;
      }

      // 创建主文件夹
      final folder = Directory(selectedDirectory);
      if (await File(selectedDirectory).exists()) {
        // 同名路径已是文件（通常是旧版本误导出的空文件），无法创建文件夹
        if (!context.mounted) return;
        final message = '${AppLocalizations.of(context)?.exportFailed}: "$selectedDirectory" is a file, please remove it first';
        FlutterToastr.show(message, context);
        return;
      }
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      for (var i = 0; i < requests.length; i++) {
        try {
          var request = requests[i];
          var host = request.hostAndPort?.host ?? 'unknown';
          var safeHost = host.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
          var prefix = '${i + 1}_$safeHost';

          switch (type) {
            case ExportType.request:
              var content = copyRawRequest(request);
              var file = File('${folder.path}/${prefix}_request.txt');
              await file.writeAsString(content);
              break;
            case ExportType.response:
              if (request.response != null) {
                var content = await copyRawResponse(request.response!);
                var file = File('${folder.path}/${prefix}_response.txt');
                await file.writeAsString(content);
              }
              break;
            case ExportType.requestResponse:
              var content = copyRequest(request, request.response);
              var file = File('${folder.path}/${prefix}_request_response.txt');
              await file.writeAsString(content);
              break;
            case ExportType.har:
              // Handled separately
              break;
          }
          // 上游 #894: 导出「响应」时无响应的请求不产生文件, 也不计入成功数,
          // 避免出现"导出成功: N 请求"而实际文件数为 0 的误导提示
          if (type != ExportType.response || request.response != null) {
            successCount++;
          }

          // 更新进度
          final progress = (i + 1) / total;
          onProgress?.call(progress);
        } catch (e) {
          // 上游 #894：不能只记日志——用户看到的是“导出成功：0 请求”，
          // 根本想不到是文件写不进去。把原因带上。
          lastError ??= e.toString();
          logger.e('Export error: $e');
        }
      }
    } else {
      // 创建所有文件
      List<XFile> files = [];
      List<String> fileNames = [];
      for (var i = 0; i < requests.length; i++) {
        var request = requests[i];
        var data = await generateExportFileData(request, type, i);
        if (data == null) continue;

        files.add(XFile.fromData(data['bytes'] as Uint8List, mimeType: 'text/plain'));
        fileNames.add(data['fileName'] as String);
        successCount++;
      }

      RenderBox? box;
      if (await Platforms.isIpad() && context.mounted) {
        box = context.findRenderObject() as RenderBox?;
      }
      await SharePlus.instance.share(ShareParams(
          // XFile.fromData 在 dart:io 下会忽略 name 参数（XFile.name 取自 path，恒为空），
          // 必须通过 fileNameOverrides 显式提供文件名，否则 share_plus 会得到空字符串
          // 而把目标路径拼成目录，writeAsBytes 报 "Is a directory"。
          fileNameOverrides: fileNames,
          files: files,
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size));
    }

    if (successCount == 0 && requests.isNotEmpty) {
      // 一条都没写成功就别报“导出成功：0 请求”了
      logger.w('export wrote no file, ${requests.length} requests, last error: $lastError');
      if (context.mounted) {
        FlutterToastr.show(
          '导出失败：${requests.length} 条请求都没写出文件'
          '${lastError == null ? '' : '（$lastError）'}，可改用「导出 HAR」',
          context,
        );
      }
      return;
    }
    onSuccess?.call(successCount);
  } catch (e, st) {
    logger.e('Export error: ', error: e, stackTrace: st);
    if (context.mounted) FlutterToastr.show('${AppLocalizations.of(context)?.exportFailed}: $e', context);
  }
}

/// 导出 HAR 文件
Future<void> exportHarFile(
  List<HttpRequest> requests,
  String fileName, {
  required BuildContext context,
  VoidCallback? onSuccess,
  Function(dynamic error)? onError,
}) async {
  try {
    var json = await Har.writeJson(requests, title: fileName);
    var bytes = utf8.encode(json);

    if (Platforms.isDesktop() || Platform.isAndroid) {
      await FilePicker.saveFile(fileName: fileName, bytes: bytes);
    } else {
      RenderBox? box;
      if (await Platforms.isIpad() && context.mounted) {
        box = context.findRenderObject() as RenderBox?;
      }

      logger.d("Export HAR file: $fileName, size: ${bytes.length} bytes");
      // 与 Request/Response 批量导出保持同一策略：真实临时文件 + 显式文件名（#893 同类隐患）
      await shareExportFiles([
        {'fileName': fileName, 'bytes': Uint8List.fromList(bytes)}
      ], mimeType: "application/json", sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size);
    }

    onSuccess?.call();
  } catch (e) {
    logger.e('Export HAR error: $e');
    onError?.call(e);
  }
}

/// 显示导出格式选择对话框
/// [ctx] 上下文
/// [requests] 请求列表
/// [folderName] 导出文件夹/文件名前缀
/// [onExportSuccess] 导出成功回调（一般用于清除选择状态）
void showExportDialog(
  BuildContext ctx,
  List<HttpRequest> requests,
  String folderName, {
  VoidCallback? onExportSuccess,
  void Function(List<HttpRequest> requests)? onImport,
}) {
  final localizations = AppLocalizations.of(ctx)!;

  showDialog(
    context: ctx,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('导入 / 导出'),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onImport != null)
              ListTile(
                leading: const Icon(Icons.content_paste),
                title: const Text('从剪贴板导入口令'),
                subtitle: const Text('粘贴此前导出的口令，还原请求到列表', style: TextStyle(fontSize: 12)),
                onTap: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  try {
                    final imported = decodeRequestPasscode(data?.text ?? '');
                    if (imported.isEmpty) throw const FormatException('口令中没有任何请求');
                    Navigator.pop(context);
                    onImport!(imported);
                    if (ctx.mounted) {
                      FlutterToastr.show('已导入 ${imported.length} 条请求', ctx);
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      FlutterToastr.show('口令无效：$e', ctx, backgroundColor: Colors.red);
                    }
                  }
                },
              ),
            ListTile(
              title: Text(localizations.request),
              onTap: () {
                Navigator.pop(context);
                exportRequestsAsFiles(
                  requests,
                  '${folderName}_request',
                  ExportType.request,
                  context: ctx,
                  onSuccess: (count) {
                    onExportSuccess?.call();
                    if (ctx.mounted) {
                      FlutterToastr.show('${localizations.exportSuccess}: $count ${localizations.request}', ctx);
                    }
                  },
                );
              },
            ),
            ListTile(
              title: Text(localizations.response),
              onTap: () {
                Navigator.pop(context);
                exportRequestsAsFiles(
                  requests,
                  '${folderName}_response',
                  ExportType.response,
                  context: ctx,
                  onSuccess: (count) {
                    onExportSuccess?.call();
                    if (ctx.mounted) {
                      FlutterToastr.show('${localizations.exportSuccess}: $count ${localizations.request}', ctx);
                    }
                  },
                );
              },
            ),
            ListTile(
              title: Text(localizations.requestResponse),
              onTap: () {
                Navigator.pop(context);
                exportRequestsAsFiles(
                  requests,
                  '${folderName}_request_response',
                  ExportType.requestResponse,
                  context: ctx,
                  onSuccess: (count) {
                    onExportSuccess?.call();
                    if (ctx.mounted) {
                      FlutterToastr.show('${localizations.exportSuccess}: $count ${localizations.request}', ctx);
                    }
                  },
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('HAR'),
              onTap: () {
                Navigator.pop(context);
                exportHarFile(
                  requests,
                  '$folderName.har',
                  context: ctx,
                  onSuccess: () {
                    onExportSuccess?.call();
                    if (ctx.mounted) {
                      FlutterToastr.show(localizations.exportSuccess, ctx);
                    }
                  },
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: Text(localizations.exportCsv),
              subtitle: const Text('一行一条请求，敏感查询参数（token / 密码 / 签名等）自动打码',
                  style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                exportRequestsCsv(
                  requests,
                  '$folderName.csv',
                  context: ctx,
                  onSuccess: onExportSuccess,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: Text(localizations.exportJson),
              subtitle: const Text('结构化 JSON，敏感查询参数自动打码，便于喂给 AI 或脚本分析',
                  style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                exportRequestsJson(
                  requests,
                  '$folderName.json',
                  context: ctx,
                  onSuccess: onExportSuccess,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text('复制口令'),
              subtitle: const Text('将所选请求压缩为口令文本，粘贴给他人即可导入', style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: encodeRequestPasscode(requests)));
                if (ctx.mounted) {
                  FlutterToastr.show('口令已复制（${requests.length} 条请求）', ctx);
                }
              },
            ),
          ],
        ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.cancel),
          ),
        ],
      );
    },
  );
}

/// 需要脱敏的查询参数 / 字段名（小写匹配）
const Set<String> _csvSensitiveKeys = {
  'token', 'access_token', 'refresh_token', 'id_token', 'password', 'passwd', 'pwd',
  'secret', 'client_secret', 'api_key', 'apikey', 'auth', 'authorization',
  'session', 'sessionid', 'sid', 'cookie', 'sign', 'signature', 'code', 'key',
};

/// 把 URL 中敏感查询参数的值替换为 ***
String _maskSensitiveInUrl(String url) {
  try {
    final uri = Uri.parse(url);
    if (uri.queryParameters.isEmpty) return url;
    final masked = <String, String>{};
    uri.queryParameters.forEach((k, v) {
      masked[k] = _csvSensitiveKeys.contains(k.toLowerCase()) ? '***' : v;
    });
    return uri.replace(queryParameters: masked).toString();
  } catch (_) {
    return url;
  }
}

/// CSV 字段转义（含逗号 / 引号 / 换行时加引号并转义内部引号）
String _csvCell(String? value) {
  final s = value ?? '';
  if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// 导出为 CSV（脱敏）：一行一条请求，敏感查询参数（token / 密码 / 签名等）自动打码。
/// 借鉴 proxypin-mcp-workbench 的「脱敏数据导出」。
Future<void> exportRequestsCsv(
  List<HttpRequest> requests,
  String fileName, {
  required BuildContext context,
  VoidCallback? onSuccess,
}) async {
  final localizations = AppLocalizations.of(context)!;
  final buffer = StringBuffer();
  buffer.writeln('index,method,url,status,duration_ms,started_at,'
      'request_content_type,response_content_type,request_bytes,response_bytes');
  for (var i = 0; i < requests.length; i++) {
    final r = requests[i];
    final resp = r.response;
    final duration = resp == null ? '' : '${resp.responseTime.difference(r.requestTime).inMilliseconds}';
    buffer.writeln(<String>[
      '${i + 1}',
      r.method.name,
      _csvCell(_maskSensitiveInUrl(r.requestUrl ?? '')),
      resp?.status.code?.toString() ?? '',
      duration,
      _csvCell(r.requestTime.toIso8601String()),
      _csvCell(r.headers.contentType),
      _csvCell(resp?.headers.contentType),
      '${r.body?.length ?? 0}',
      '${resp?.body?.length ?? 0}',
    ].join(','));
  }
  try {
    await FilePicker.saveFile(fileName: fileName, bytes: utf8.encode(buffer.toString()));
    onSuccess?.call();
    if (context.mounted) FlutterToastr.show(localizations.exportSuccess, context);
  } catch (e) {
    if (context.mounted) {
      FlutterToastr.show('${localizations.exportFailed}: $e', context, backgroundColor: Colors.red);
    }
  }
}
/// 导出为 JSON（脱敏）：结构化列表，敏感查询参数自动打码，便于喂给 AI 或脚本分析。
Future<void> exportRequestsJson(
  List<HttpRequest> requests,
  String fileName, {
  required BuildContext context,
  VoidCallback? onSuccess,
}) async {
  final localizations = AppLocalizations.of(context)!;
  final list = <Map<String, dynamic>>[];
  for (var i = 0; i < requests.length; i++) {
    final r = requests[i];
    final resp = r.response;
    list.add({
      'index': i + 1,
      'method': r.method.name,
      'url': _maskSensitiveInUrl(r.requestUrl ?? ''),
      'status': resp?.status.code,
      'duration_ms': resp == null ? null : resp.responseTime.difference(r.requestTime).inMilliseconds,
      'started_at': r.requestTime.toIso8601String(),
      'request_content_type': r.headers.contentType,
      'response_content_type': resp?.headers.contentType,
      'request_bytes': r.body?.length ?? 0,
      'response_bytes': resp?.body?.length ?? 0,
      'app': r.processInfo?.name,
      'protocol': r.protocolVersion,
    });
  }
  final content = const JsonEncoder.withIndent('  ').convert({
    'exported_at': DateTime.now().toIso8601String(),
    'count': list.length,
    'requests': list,
  });
  try {
    await FilePicker.saveFile(fileName: fileName, bytes: utf8.encode(content));
    onSuccess?.call();
    if (context.mounted) FlutterToastr.show(localizations.exportSuccess, context);
  } catch (e) {
    if (context.mounted) {
      FlutterToastr.show('${localizations.exportFailed}: $e', context, backgroundColor: Colors.red);
    }
  }
}
