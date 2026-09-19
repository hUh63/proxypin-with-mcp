/*
 * 抓包内容上限设置（上游 #773 / #456）
 *
 * 超过上限的响应/请求体只保留前 N 字节（压缩体整体释放）用于列表展示，
 * 降低长时间抓包的内存驻留。裁剪发生在代理转发完成之后，不影响实际转发。
 */
import 'package:flutter/material.dart';
import 'package:proxypin/network/bin/configuration.dart';

/// 内容上限档位（KB -> 文案）；0 表示不限
const Map<int, String> captureBodyLimitOptions = {
  0: '不限（保留完整内容，默认）',
  128: '128 KB（只看头部与少量内容）',
  256: '256 KB',
  1024: '1 MB',
  4096: '4 MB',
};

/// 配置值对应的中文描述，用于设置项副标题
String captureBodyLimitLabel(int kb) {
  if (kb <= 0) return '不限：保留完整请求/响应内容';
  if (kb >= 1024) return '上限 ${kb ~/ 1024} MB：超出部分只保留前 ${kb ~/ 1024} MB 用于展示';
  return '上限 $kb KB：超出部分只保留前 $kb KB 用于展示';
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
      return AlertDialog(
        title: const Text('抓包内容上限', style: TextStyle(fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '超过上限的响应/请求体只保留前 N 字节（压缩体整体释放），用于降低长时间抓包的内存占用。'
                  '裁剪在转发完成后进行，不影响实际转发。',
                  style: TextStyle(fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 8),
                for (final entry in captureBodyLimitOptions.entries)
                  RadioListTile<int>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: entry.key,
                    groupValue: captureBodyLimitOptions.containsKey(current) ? current : -1,
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      );
    },
  );
}
