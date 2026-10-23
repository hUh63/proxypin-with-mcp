import 'dart:io';
import 'dart:typed_data';

import 'package:brotli/brotli.dart';
import 'package:proxypin/network/util/logger.dart';
import 'package:zstandard/zstandard.dart';

///GZIP 解压缩
List<int> gzipDecode(List<int> byteBuffer) {
  GZipCodec gzipCodec = GZipCodec();
  try {
    return gzipCodec.decode(byteBuffer);
  } catch (e) {
    logger.e("gzipDecode error: $e");
    return byteBuffer;
  }
}

///GZIP 压缩
List<int> gzipEncode(List<int> input) {
  return GZipCodec().encode(input);
}

///br 解压缩
List<int> brDecode(List<int> byteBuffer) {
  try {
    return brotli.decode(byteBuffer);
  } catch (e) {
    logger.e("brDecode error: $e");
    return byteBuffer;
  }
}

///zstd 解压缩
Future<List<int>?> zstdDecode(List<int> byteBuffer) async {
  final zstandard = Zstandard();
  try {
    return zstandard.decompress(Uint8List.fromList(byteBuffer));
  } catch (e) {
    logger.e("zstdDecode error: $e");
    return byteBuffer;
  }
}


///zlib
///
/// `Content-Encoding: deflate` 实际有两种写法：RFC1950 的 zlib 包装（0x78 开头，
/// 绝大多数服务器）与 RFC1951 的裸 deflate（部分 IIS/老服务）。
/// 旧实现只试 `ZLibDecoder(raw: true)`（裸 deflate）→ 标准 zlib 数据解不出来，
/// 抓包列表里这类响应体一直是乱码/原始压缩字节。这里两种都试。
List<int> zlibDecode(List<int> byteBuffer) {
  try {
    return ZLibCodec().decode(byteBuffer);
  } catch (_) {
    try {
      return ZLibDecoder(raw: true).convert(byteBuffer);
    } catch (e) {
      logger.e("zlibDecode error: $e");
      return byteBuffer;
    }
  }
}