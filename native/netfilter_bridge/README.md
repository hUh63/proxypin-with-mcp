# NetFilter 原生桥（可选组件）

把 **NetFilter SDK** 的数据面接进 proxypin。因为 NetFilter 要求「native 线程**同步**回调 +
在回调里同步改写 `connInfo`」，而 Dart FFI 只有「同线程同步」或「跨线程异步」两种回调
（都不满足，详见 `docs/kernel_drivers.md` §3），所以数据面必须留在**原生侧**，Dart 只做控制面。

## 它做什么

- `nfb_start(driverName, relayPort, selfPid)`：初始化驱动并挂上事件处理器；
- `nfb_add_tcp_rule(port)`：为某 TCP 目的端口加「出站 + 指示连接请求」规则；
- 命中时在 `tcpConnectRequest` 里把目标改写成 `127.0.0.1:relayPort` 并放行，
  原始目标记进 NAT 表；
- `nfb_lookup_original(...)`：本地中继据此用 `CONNECT` 还原真实目标（与 WinDivert 方案共用中继）。

## 前置条件（都必须由你自备）

1. **NetFilter SDK**（商业授权组件）：把 `nfapi.h` 与 `nfapi.lib` 放到 `native/netfilter_bridge/sdk/`；
2. **Windows 构建机**：Visual Studio（含 C++）+ CMake；
3. 运行时把 NetFilter 的 `nfapi.dll` / `nfdriver.sys`（以及驱动安装）放到位。

> ⚠️ 本仓库**不包含、不下载、不分发** NetFilter SDK 的任何文件。

## 构建

```bat
cd native\netfilter_bridge
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release
```

产物：`build\Release\netfilter_bridge.dll`。把它拷到 proxypin 的 exe 同目录即可。

## Dart 侧

`lib/network/transparent/netfilter_bridge.dart` 用 FFI 加载 `netfilter_bridge.dll` 并调用上述函数；
未放 DLL 时 `available == false`，功能优雅降级为不可用。

## 状态

**未在本仓库编译 / 验证**：本环境是 Linux、无 NetFilter SDK、无 Windows 工具链，故这里只提供
接口与实现骨架。请在你的 Windows 机器上编译并自行验证；内核驱动行为改动发生在网络路径上，
务必在可恢复的环境里试用。
