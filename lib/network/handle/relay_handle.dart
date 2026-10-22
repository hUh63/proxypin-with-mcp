import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/util/logger.dart';

class RelayHandler extends ChannelHandler<Object> {
  final Channel remoteChannel;

  RelayHandler(this.remoteChannel);

  @override
  Future<void> channelRead(ChannelContext channelContext, Channel channel, Object msg) async {
    //发送给客户端
    // 不 await 不 catch 的 write 失败时会变成未捕获异步异常：数据被静默丢弃，
    // 两条通道也都不会关闭，客户端表现为「连接还在但这个域名再也不响应」。
    try {
      await remoteChannel.write(channelContext, msg);
    } catch (e, s) {
      logger.e('中转写入失败', error: e, stackTrace: s);
      remoteChannel.close();
      channel.close();
    }
  }

  @override
  void channelInactive(ChannelContext channelContext, Channel channel) {
    remoteChannel.close();
  }
}
