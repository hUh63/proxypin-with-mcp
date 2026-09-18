/*
 * Copyright 2025 Hongen Wang All rights reserved.
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

/// WebSocket 二进制载荷自动解码（上游 #623）。
///
/// WebSocket 的二进制帧（opcode=0x02）本身不带格式信息，直接按 UTF-8 展示常是乱码。
/// 这里做**尽力而为**的识别与解码，把常见载荷还原成人类可读形式：
///
/// - 图片（PNG / JPEG / GIF / WebP / BMP）→ 交给界面直接渲染；
/// - 压缩流（gzip / zlib）→ 解压后按文本 / JSON 展示；
/// - 文本 / JSON → 直接展示；
/// - 识别不出时回退为“二进制”，界面仍可查看 HEX。
///
/// 识别依据是**魔数 + 严格解码**，即使误判也不影响原始字节——界面始终能用 HEX 看到原文。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 载荷识别结果类别
enum WsPayloadKind {
  /// 空帧
  empty,

  /// 纯文本
  text,

  /// JSON 文本
  json,

  /// 图片（可渲染）
  image,

  /// 压缩流（已解压出内容，见 [WsDecodedPayload.text]）
  compressed,

  /// 未能识别为上述任一种的二进制
  binary,
}

/// 单次解码的结果
class WsDecodedPayload {
  final WsPayloadKind kind;

  /// 人类可读描述（用于列表气泡 / 标题），如 `PNG 图片 · 12.3 KB`
  final String label;

  /// 文本内容（文本 / JSON / 压缩解压后），无法得到时为 null
  final String? text;

  /// 图片原始字节（[kind] == image 时）
  final Uint8List? imageBytes;

  /// 图片格式（png / jpeg / gif / webp / bmp）
  final String? imageFormat;

  /// 压缩流类型（gzip / zlib）
  final String? compression;

  /// 文本是否因超过预览上限而被截断
  final bool truncated;

  const WsDecodedPayload({
    required this.kind,
    required this.label,
    this.text,
    this.imageBytes,
    this.imageFormat,
    this.compression,
    this.truncated = false,
  });

  bool get hasImage => imageBytes != null;
}

/// 二进制载荷解码器（纯函数，无状态）
class WsPayloadDecoder {
  /// 解压 / 文本预览上限（超过只保留前 N 个字符）
  static const int previewLimit = 256 * 1024;

  /// 识别并解码一段二进制载荷
  static WsDecodedPayload decode(Uint8List data) {
    if (data.isEmpty) {
      return const WsDecodedPayload(kind: WsPayloadKind.empty, label: '空帧');
    }

    // 1) 图片
    final imageFormat = _detectImage(data);
    if (imageFormat != null) {
      return WsDecodedPayload(
        kind: WsPayloadKind.image,
        label: '${imageFormat.toUpperCase()} 图片 · ${_humanSize(data.length)}',
        imageBytes: data,
        imageFormat: imageFormat,
      );
    }

    // 2) 压缩流
    final compression = _detectCompression(data);
    if (compression != null) {
      final raw = _decompress(compression, data);
      if (raw != null && raw.isNotEmpty && raw.length != data.length) {
        final text = _asText(raw);
        if (text != null) {
          final truncated = raw.length > previewLimit;
          final shown = truncated ? text.substring(0, previewLimit) : text;
          final isJson = _looksJson(shown);
          return WsDecodedPayload(
            kind: WsPayloadKind.compressed,
            label: '$compression 解压 → ${isJson ? 'JSON' : '文本'} · ${_humanSize(raw.length)}',
            text: shown,
            compression: compression,
            truncated: truncated,
          );
        }
        // 解压出的是二进制
        return WsDecodedPayload(
          kind: WsPayloadKind.compressed,
          label: '$compression 解压 → 二进制 · ${_humanSize(raw.length)}',
          compression: compression,
        );
      }
    }

    // 3) 文本 / JSON
    final text = _asText(data);
    if (text != null) {
      if (_looksJson(text)) {
        return WsDecodedPayload(
          kind: WsPayloadKind.json,
          label: 'JSON · ${_humanSize(data.length)}',
          text: text,
        );
      }
      return WsDecodedPayload(
        kind: WsPayloadKind.text,
        label: '文本 · ${_humanSize(data.length)}',
        text: text,
      );
    }

    // 4) 二进制
    return WsDecodedPayload(
      kind: WsPayloadKind.binary,
      label: '二进制 · ${_humanSize(data.length)}',
    );
  }

  /// 是否为 JSON 文本（供界面判断是否展示 JSON 视图）
  static bool looksJson(String text) => _looksJson(text);

  static String? _detectImage(Uint8List d) {
    if (d.length >= 8 && d[0] == 0x89 && d[1] == 0x50 && d[2] == 0x4e && d[3] == 0x47) {
      return 'png';
    }
    if (d.length >= 3 && d[0] == 0xff && d[1] == 0xd8 && d[2] == 0xff) {
      return 'jpeg';
    }
    if (d.length >= 6 && d[0] == 0x47 && d[1] == 0x49 && d[2] == 0x46 && d[3] == 0x38) {
      return 'gif';
    }
    if (d.length >= 12 &&
        d[0] == 0x52 && d[1] == 0x49 && d[2] == 0x46 && d[3] == 0x46 && // RIFF
        d[8] == 0x57 && d[9] == 0x45 && d[10] == 0x42 && d[11] == 0x50) { // WEBP
      return 'webp';
    }
    if (d.length >= 2 && d[0] == 0x42 && d[1] == 0x4d) {
      return 'bmp';
    }
    return null;
  }

  static String? _detectCompression(Uint8List d) {
    if (d.length >= 2 && d[0] == 0x1f && d[1] == 0x8b) return 'gzip';
    // zlib：首字节 0x78，且前两字节构成的值是 31 的倍数（RFC 1950）
    if (d.length >= 2 && d[0] == 0x78 && (((d[0] << 8) | d[1]) % 31 == 0)) return 'zlib';
    return null;
  }

  static List<int>? _decompress(String type, Uint8List d) {
    try {
      if (type == 'gzip') {
        return GZipCodec().decode(d);
      }
      return ZLibDecoder().convert(d);
    } catch (_) {
      return null;
    }
  }

  /// 严格 UTF-8 解码；失败返回 null（视为非文本）
  static String? _asText(List<int> data) {
    try {
      return utf8.decode(data);
    } catch (_) {
      return null;
    }
  }

  static bool _looksJson(String text) {
    final t = text.trimLeft();
    if (t.isEmpty) return false;
    final c = t.codeUnitAt(0);
    if (c != 0x7b && c != 0x5b) return false; // { 或 [
    try {
      json.decode(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
