import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/storage/favorites.dart';

WebSocketFrame _frame(int index, {bool fromClient = true, int payloadBytes = 1024}) {
  final frame = WebSocketFrame(
    fin: true,
    opcode: 0x01,
    mask: false,
    payloadLength: payloadBytes,
    maskingKey: 0,
    payloadData: Uint8List.fromList(List.filled(payloadBytes, index % 255)),
    time: DateTime.fromMillisecondsSinceEpoch(1710000000000 + index),
  );
  frame.isFromClient = fromClient;
  return frame;
}

void main() {
  test('trimFavoriteMessages caps websocket frame count', () {
    final request = HttpRequest(HttpMethod.get, 'https://example.com/ws');
    final response = HttpResponse(HttpStatus.ok);
    final favorite = Favorite(request, response: response);

    for (int i = 0; i < FavoriteStorage.maxWebSocketMessagesPerFavorite + 20; i++) {
      request.messages.add(_frame(i, fromClient: true, payloadBytes: 256));
    }

    final changed = FavoriteStorage.trimFavoriteMessages(favorite);
    expect(changed, isTrue);
    expect(
      favorite.websocketMessageCount <= FavoriteStorage.maxWebSocketMessagesPerFavorite,
      isTrue,
    );

    // newest frame remains
    final newestTime = request.messages.last.time.millisecondsSinceEpoch;
    expect(newestTime, 1710000000000 + FavoriteStorage.maxWebSocketMessagesPerFavorite + 19);
  });

  test('trimFavoriteMessages caps websocket payload bytes and keeps newest', () {
    final request = HttpRequest(HttpMethod.get, 'https://example.com/ws');
    final response = HttpResponse(HttpStatus.ok);
    final favorite = Favorite(request, response: response);

    // 120 帧 × 16KB = 1.875MB，必须超过 maxWebSocketPayloadBytesPerFavorite(1MB)
    // 才会触发按字节裁剪。原先用 3KB（合计 360KB）达不到阈值，函数会正确地
    // 返回 false，测试却断言 true——属测试数据未越过阈值。
    for (int i = 0; i < 120; i++) {
      final frame = _frame(i, fromClient: i.isEven, payloadBytes: 16 * 1024);
      if (i.isEven) {
        request.messages.add(frame);
      } else {
        response.messages.add(frame);
      }
    }

    final changed = FavoriteStorage.trimFavoriteMessages(favorite);
    expect(changed, isTrue);

    final totalBytes = request.messages.fold<int>(0, (sum, e) => sum + e.payloadData.length) +
        response.messages.fold<int>(0, (sum, e) => sum + e.payloadData.length);
    expect(totalBytes <= FavoriteStorage.maxWebSocketPayloadBytesPerFavorite, isTrue);

    // newest timestamp should still exist after trimming
    final all = [...request.messages, ...response.messages]..sort((a, b) => a.time.compareTo(b.time));
    expect(all.last.time.millisecondsSinceEpoch, 1710000000000 + 119);
  });
}

