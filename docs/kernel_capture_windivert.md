# 内核级免代理抓包（Windows / WinDivert）

> 状态：**实验性功能，尚未在真实 Windows 机器上验证。** 本文档说明实现原理、依赖、
> 安全边界与如何自行联调。

## 1. 它解决什么问题

普通代理抓包需要应用配合：要么在系统/应用里设置 HTTP 代理，要么应用本身忽略代理设置
（硬编码、走原生网络栈、证书校验严格）就抓不到。

内核级抓包在 **Windows 网络栈（WFP 层）** 直接截获出站 TCP 报文，把目标地址改写成
本地代理，从而抓到那些"不认系统代理"的进程——原理与 Fiddler/Charles 的
"capture traffic from non-proxy-aware apps"、以及 anyproxy / Echo / ProxyBridge 等工具一致。

## 2. 为什么用 WinDivert 而不是自研 WFP 驱动

| 方案 | 是否需要自己签名驱动 | 可行性 |
| --- | --- | --- |
| 自研 WFP Callout 驱动 | 需要 **EV 代码签名证书** + WDK + WHQL 门槛 | 本仓库不具备条件 |
| **WinDivert**（basil00/WinDivert） | **不需要**，其 `WinDivert.sys` 已由官方签名 | ✅ 采用 |
| NetFilter SDK | 商业授权（数百美元） | ❌ 不采用 |

WinDivert 是一个用户态的**数据包拦截/重注入**库：我们只需随程序附带官方发布的
`WinDivert.dll` + `WinDivert64.sys`，用 `WinDivertOpen` / `Recv` / `Send` 接口即可，
驱动签名由上游负责。

## 3. 架构

```
应用进程 ── 出站 SYN(80/443) ──▶ [WFP/WinDivert 过滤]
                                     │  handle==单句柄
                                     ├─ 命中「not loopback and (dstPort 80 or 443)」
                                     │    · 不是本进程(selfPid)发出的
                                     │    · 记录 NAT 表: (srcIp:srcPort) → 原始目的 (dstIp:dstPort)
                                     │    · 改写 IPv4.dst = 127.0.0.1, TCP.dstPort = relayPort
                                     │    · 重算校验和 → WinDivertSend 注回
                                     ▼
                            TransparentRelay (127.0.0.1:relayPort)
                                     │  按 peer(ip:port) 反查原始目的
                                     │  CONNECT host:port → 本地 MITM 代理
                                     │  双向 pipe（本进程 → 回程包也会被过滤命中）
                                     ▼
                            既有 MITM 代理 (ProxyServer.current.port)
                                     │  解密 / 记录 / 按脚本改写
                                     ▼
                                    真实服务器

  回程: 「loopback and tcp.SrcPort==relayPort」的包，按 peer 反查 → 把 IPv4.src 改回原始目的
```

关键设计点：

- **单句柄**：只 `WinDivertOpen` 一次，用组合过滤规则同时覆盖"出网"和"回程"两类包。
- **独立 isolate**：抓包/改写循环跑在后台 isolate（`TransparentCapture._entry`），避免
  阻塞 UI 事件循环。
- **NAT 表**：`(clientIp:clientPort) → (originalDstIp:originalDstPort)`，由出站 SYN 建立，
  回程按 peer 查表恢复，连接关闭即清理。
- **不劫持自己**：`getCurrentProcessId()` 得到的 PID 与服务端口反查到的 PID 相同的包一律跳过，
  防止抓包进程自身流量被改写造成回环。
- **Relay 复用既有代理**：`TransparentRelay` 只做"接住连接 + 发 CONNECT + 双向 pipe"，
  真正的 TLS 解密、记录、脚本全部交给现有 MITM 栈，避免重复实现。

## 4. 依赖放置

把 WinDivert 官方发布包中的两个文件放到 **可执行文件同目录**（或系统 PATH / 当前工作目录）：

```
WinDivert.dll
WinDivert64.sys      # 64 位；32 位用 WinDivert32.sys
```

- 下载：https://github.com/basil00/WinDivert/releases
- 若缺失，界面会提示 `Failed: WinDivert not installed`。

## 5. 使用前提与安全边界

1. **必须以管理员身份运行**：加载内核驱动需要管理员权限；否则 `WinDivertOpen` 失败，
   界面提示 `run as administrator`。
2. **它会改动网络路径**：所有（非本进程的）出站 80/443 流量都会被改写到本地代理。
   因此：
   - 关闭抓包时立即 `WinDivertClose` 并清空 NAT 表，恢复原始路径；
   - 程序退出时（`TransparentCapture.stop()`）同样会清理；
   - 与"系统代理"模式**不要同时开**，否则同名流量可能被处理两次。
3. **只处理 IPv4 + TCP**，且仅 80/443（可在 `TransparentCapture.filter` 中调整）。
   IPv6 / UDP / 其它端口不在范围内。
4. **HTTPS 仍需信任代理根证书**：报文被引到本地代理后走的是 MITM，客户端若不信任
   proxypin 的 CA，连接会因证书校验失败而中断（这与普通代理抓包完全一致）。

## 6. 未验证声明（重要）

本功能在 **Linux 构建环境**下开发，仅完成了：

- 纯 Dart 层的 IPv4/TCP 解析、改写、校验和逻辑——已通过本地单元测试
  （`inet_test.dart`，含校验和与独立实现交叉验证）；
- WinDivert FFI 绑定按官方 `windivert.h` 编写（`WINDIVERT_ADDRESS` 结构 80 字节、
  各常量与函数签名一致）；
- 全仓库静态检查（括号配平）通过，CI 五平台编译通过。

**未做**：真实 Windows 上的端到端验证（需管理员权限 + WinDivert 二进制 + 真机）。
实际使用前请自行联调，重点确认：驱动能否加载、NAT 表命中、回程改写、与系统代理的互斥。

## 7. 相关文件

| 文件 | 职责 |
| --- | --- |
| `lib/network/transparent/inet.dart` | 纯 Dart：IPv4/TCP 解析、改写、校验和、NAT key |
| `lib/network/transparent/windivert.dart` | WinDivert FFI 绑定（open/recv/send/calcChecksums/…） |
| `lib/network/transparent/process_lookup.dart` | `GetExtendedTcpTable` 反查端口→PID |
| `lib/network/transparent/transparent_capture.dart` | 单例、过滤规则、抓包/改写 isolate |
| `lib/network/transparent/transparent_relay.dart` | 监听 relayPort，CONNECT 给本地代理并双向 pipe |
| `lib/ui/component/kernel_capture_dialog.dart` | 工具箱对话框（状态/统计/开启/停止/风险确认） |

## 8. 参考

- WinDivert: https://github.com/basil00/WinDivert
- anyproxy / Echo / ProxyBridge：均采用 WinDivert 实现进程级透明重定向
- Windows Filtering Platform (WFP) 概览：Microsoft Learn
