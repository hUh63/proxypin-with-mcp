# 网络核心层健壮性加固设计（2026-10-01）

本文件记录一次代码审查中发现的、**需要设计评审与真机验证**后再实施的高风险项。
低风险项（消息帧上界、pending 等待超时、完成集上界、Host 空指针、h2 订阅登记等）
已在 v1.24.75 系列修复，不在本文件范围。

## 1. HTTP/1.1 读事件共享 `ByteBuf` 的跨 `await` 竞态（P0）

**现象**：`ChannelDispatcher` 每个连接复用同一个 `buffer`（`channel_dispatcher.dart:28`），
`channelRead()` 全程读写它，且中途存在多个 `await`（`remoteChannel.writeBytes`、递归 `channelRead`）。
`Socket.listen` 回调不会等待返回的 Future，下一条 socket 事件可在这些 `await` 期间进入并
再次 `buffer.add` / `clearRead`，与正在解码/转发的状态交错。

**影响**：高并发/大流量下请求体、帧边界被交叉改写 → 解析错位、串包、偶发“挂起/空响应”。

**候选方案**：
- A. 每条连接的读处理经 `SequentialTaskQueue` 串行化（HTTP/2 已如此，HTTP/1.1 未走）。
  ⚠️ 注意：`channelRead` 内部会递归 `await channelRead(...)` 处理同一次读入的多帧，
  直接串行化会自锁，需先把递归改为 `while` 迭代（见 §3）。
- B. 每个读事件使用独立 `ByteBuf`，解码状态机改为“边解边消费”并回传余量。

**风险**：改动面大、位于最热路径，**必须**配套压测（大文件上传/下载、HTTP/1.1 keep-alive 并发、
慢客户端）后才能合入。

**验证**：`test/h2c_proxy_test.dart` / `test/close_delimited_test.dart` 为起点，
新增 HTTP/1.1 pipelining + 并发慢读的定向测试。

## 2. `Channel.writeBytes` 无背压（P1）

**现象**：`channel.dart:185-218` 的 `while (_writeQueue.isNotEmpty) { _socket.add(chunk); }`
同步排空写队列，未依据 `_socket.writeBuffer` 限流，`flush()` 未 await。

**影响**：对端慢时数据在 `dart:io` 发送缓冲区堆积，内存放大；大 body 转发易积压。

**候选方案**：写队列长度设阈值；超阈值时暂停上游读取（socket.pause）或等待 `flush()`；
对 `writeBytes` 引入 `await` 语义与背压回压。

**风险**：中高。改动 channel 写路径，可能影响时延与吞吐，需基准测试。

## 3. 三处 O(n²) 拷贝热点（P1）

| 位置 | 问题 | 建议 |
|---|---|---|
| `websocket.dart:296-301` `ByteBuffer.putBytes` | 每段数据整体重新分配 | 可增长缓冲/环形缓冲/游标视图 |
| `h2/h2_codec.dart:417-424,556-563` | DATA/CONTINUATION `sublist` 循环、body 逐帧累积 | `Uint8List.view` / 单次累积 |
| `sse.dart:29-35` | 循环内整体 `toString()`；逐块 UTF-8 解码撕裂多字节 | 增量扫描游标 + 有状态 UTF-8 解码 |

**风险**：中。均可用现有测试（`mqtt_packet_test`、`sse_chunked_test`、`h2_*`）覆盖，但需补大数据量用例。

## 4. `channelRead` 递归处理同一次读入多帧（P1）

`channel_dispatcher.dart` 在 HTTP/2 分支多次 `await channelRead(..., Uint8List(0))` 递归解码
剩余帧。一个读事件含 M 帧即递归 M 层，并放大 §1 的 pending 注册。**建议改为迭代 `while` 循环**，
这也是实施 §1 方案 A 的前置条件。

---

## 建议排期

1. 先做 §4（迭代化）——低风险、是 §1 前置。
2. 再做 §3 的 SSE/WebSocket 缓冲改造（可独立验证）。
3. §1 与 §2 需专项设计与压测，建议单独立项。
