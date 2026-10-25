# 应用分身 / 多用户（user 999）下的抓包（上游 #975）

## 现象

Android 16/17 上，**应用分身**（或工作资料等非 user 0 profile）里的 App 在开启 VPN 抓包后**完全没网**：
连本机代理端口的连接一直停在 `SYN_SENT`，`Recv-Q` 恒为 0，也就是 SYN 根本没送到监听端。
主空间里的其它 App 同时是正常的。

## 根因

两层原因叠加：

1. **系统代理通告**：VPN 通过 `VpnService.Builder.setHttpProxy(...)` 告诉系统「所有 HTTP(S) 走
   `127.0.0.1:<proxyPort>`」。分身里的 App 于是去连**本机回环端口**。
2. **回环被内核拦**：新系统在 netd/BPF 层限制「跨 profile 访问 loopback」
   （`android.permission.USE_LOOPBACK_INTERFACE`，该 flag 是 aconfig readonly，改不动；
   即使反编译加权限并重签、`dumpsys` 显示 granted，连通性也完全不变）。
   结果就是 SYN 发不出去 —— App 表现为彻底断网，而不是「抓不到包」。

用 root 起的监听做服务端则可以收到连接，说明限制就在 App 侧那次 `connect()` 上。

## 我们的修复

1. **VPN 新增「是否通告 HTTP 代理」开关**（设置 → VPN 通告 HTTP 代理，默认开）。
   关掉后 `Builder` 不再调用 `setHttpProxy`，VPN 变成**纯 TUN**：
   App 不会再去连回环端口，也就不会因为第 2 层限制而断网。
2. **纯 TUN 下的 TLS 由内置 TCP 栈接管**：tun 里的连接照旧转给本地代理端口。
   TLS 首包不是合法 HTTP 请求行，因此由 `ConnectionHandler` 先替客户端发一条
   `CONNECT host:port HTTP/1.1` 建隧道，代理回的 `HTTP/1.1 200 ...` 由
   `Connection.addReceivedData` 吞掉（不进隧道），之后 TLS 字节原样透传。
   也就是说：关掉通告之后**HTTPS 仍然能抓**，不牺牲能力。

## 使用建议

- 只需要抓主空间 App：保持默认（通告开），性能最好。
- 需要抓应用分身 / 工作资料里的 App，或发现分身里的 App 断网：
  到设置里关掉「VPN 通告 HTTP 代理」，重新开启 VPN。
- 如果 VPN 本身覆盖不到分身（系统按 profile 隔离 VPN），至少不会再出现
  「分身 App 完全没网」，只是这些 App 的流量不进 tun、抓不到。
  这种情况下可以叠加 Root 重定向（`RootProxyManager` 的 iptables 规则对**所有 uid**生效，
  包括 `999xxxxx`）来覆盖分身流量。

## 相关代码

| 位置 | 作用 |
|---|---|
| `lib/network/bin/configuration.dart` | `vpnHttpProxyNotice` 配置项（缺键按开启处理） |
| `lib/native/vpn.dart` | 传给原生的 `setSystemProxy = enableSystemProxy && vpnHttpProxyNotice` |
| `ProxyVpnService.createVpnInterface` | `setSystemProxy` 为 false 时不调用 `setHttpProxy` |
| `ConnectionHandler.initProxyConnect` | TLS 首包先补 `CONNECT` 建隧道 |
| `Connection.addReceivedData` | 吞掉代理的 CONNECT 响应头 |

## IPv6 与 UDP：纯 TUN 模式下不受影响

排查时确认过两件事，免得再被怀疑成缺陷：

- **IPv6**：VPN 只 `addAddress(VIRTUAL_HOST, 32)` + `addRoute("0.0.0.0", 0)`，
  没有配置 IPv6 地址与路由，系统不会把 IPv6 流量送进 tun —— 它走物理网络，
  既不抓包也不会被黑洞。`handlePacket` 只解析 IPv4 头是与此一致的，不是遗漏。
  真的需要抓 IPv6 时才需要补 `addAddress` / `addRoute("::", 0)` 与
  `IP6Header` 解析（`IPPacketFactory` 目前只有 IPv4）。
- **UDP**：`ConnectionHandler.handleUDPPacket` 已经有完整的 UDP 会话转发
  （`ConnectionManager.createUDPConnection` + `protect()` 直连），QUIC 元数据
  探测与 `blockQuic` 丢弃也都在。纯 TUN 不改这段逻辑，所以 QUIC 仍按开关处理。

## 超时兜底

`proxyTunnelPending` 有 10 秒超时（`proxyTunnelStart`）：代理一直不回响应头时
（端口填错、对端不是我们的代理），`Connection.addReceivedData` 会放弃吞头、
把已收到的字节原样透传，避免客户端 TLS 握手一直挂着。
