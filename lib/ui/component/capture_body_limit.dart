/*
 * 抓包内容上限设置（上游 #773 / #456）
 *
 * 超过上限的响应/请求体只保留前 N 字节（压缩体整体释放）用于列表展示，
 * 降低长时间抓包的内存驻留。裁剪发生在代理转发完成之后，不影响实际转发。
 */
import 'package:flutter/material.dart';
import 'package:proxypin/l10n/app_localizations.dart';
import 'package:proxypin/network/bin/configuration.dart';

/// 内容上限档位（KB -> 文案）；0 表示不限
Map<int, String> captureBodyLimitOptions(AppLocalizations loc) => {
      0: loc.capLimitUnlimitedOption,
      128: loc.capLimitOption128,
      256: '256 KB',
      1024: '1 MB',
      4096: '4 MB',
    };

/// 配置值对应的中文描述，用于设置项副标题
String captureBodyLimitLabel(AppLocalizations loc, int kb) {
  if (kb <= 0) return loc.capLimitUnlimitedDesc;
  if (kb >= 1024) return loc.capLimitSizeMb('${kb ~/ 1024}');
  return loc.capLimitSizeKb('$kb');
}

/// 弹出「抓包内容上限」选择对话框
Future<void> showCaptureBodyLimitDialog(
  BuildContext context,
  Configuration configuration, {
  VoidCallback? onChanged,
}) {
  return showDialog(
    context: context,
    builder: (ctx) {
      final current = configuration.captureBodyLimitKB;
      final localizations = AppLocalizations.of(ctx)!;
      return AlertDialog(
        title: Text(localizations.prefCaptureBodyLimit,
            style: const TextStyle(fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  localizations.capLimitDesc,
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 8),
                for (final entry in captureBodyLimitOptions(localizations).entries)
                  RadioListTile<int>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: entry.key,
                    groupValue: captureBodyLimitOptions(localizations).containsKey(current) ? current : -1,
                    title: Text(entry.value, style: const TextStyle(fontSize: 13)),
                    onChanged: (value) {
                      configuration.captureBodyLimitKB = value ?? 0;
                      configuration.flushConfig();
                      onChanged?.call();
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localizations.close)),
        ],
      );
    },
  );
}
