# 内核级抓包：三条路线对照与参考

> 本文回答一个问题：**要在 Windows 上抓「不认系统代理」的应用，有哪几条路？各自能实现到什么程度？**
> 结论先行：本仓库落地的是 **WinDivert**（官方已签名驱动，用户态即可）；**NetFilter SDK** 是商业组件，仅做只读探测；**自研 WFP Callout 驱动**在本环境无法编译/签名/验证，只提供参考骨架与构建指南。

---

## 1. 三条路线对照

| 维度 | WinDivert | NetFilter SDK | 自研 WFP Callout |
|---|---|---|---|
| 本质 | 用户态 DLL + **已签名**内核驱动 `WinDivert.sys` | 商业 SDK：用户态 `nfapi` + 内核 `nfdriver` | 自己写内核驱动，注册 WFP 过滤/重定向 |
| 驱动签名 | **官方已签**，我们不用签 | 官方已签（随 SDK 交付） | **必须** EV 证书 + 微软签名（Win10 1607+ 强制） |
| 授权 | LGPLv3，可随应用分发（保留许可） | 商业授权（约 $300–395/项目） | 自研，无授权费 |
| 集成成本 | 低：FFI 调几个函数 | 中：用户态 API 回调 + 回调线程模型 | **高**：WDK 工程 + 驱动调试 + 蓝屏风险 |
| 本仓库支持 | ✅ 已实现（本目录代码） | ⚠️ 仅只读探测（不内置其运行时） | 📄 仅参考骨架 + 构建指南（未编译未验证） |
| 用于 | 出站连接重定向到本地代理 | 同类场景（HTTP Debugger 即用此） | 同类场景 |

**为什么选 WinDivert 做主线**：它把「内核重定向」这件事封装成了用户态 API，驱动由项目自己签名，我们只负责调用。这才是「一个人能做完并维护」的路径。

---

## 2. WinDivert（本仓库主线）

### 2.1 运行前提

1. **管理员权限**：`WinDivertOpen` 需要管理员；否则返回 `ERROR_ACCESS_DENIED`（界面会提示 “需要管理员权限”）。
2. **运行库就位**：把官方发行包里的两个文件放到 **exe 同目录**：
   - `WinDivert.dll`（x64）
   - `WinDivert64.sys`（x64 驱动；`WinDivert.dll` 会在同目录找它）
3. 与「系统代理」互斥使用，避免把自己代理进程的流量再次劫持（代码里已跳过自身 PID 的流量）。

### 2.2 工具箱里的「检测 / 一键放置」

入口：**工具箱 → Runtime → 内核级抓包 → 检测/安装驱动**。该面板会：

- 只读扫描候选目录（exe 同目录 → 当前目录 → `System32` → `PATH`），逐项报告 `WinDivert.dll` / `WinDivert64.sys` 是否在位，并尝试用 `WinDivertHelperVersion` 读出运行库版本；
- **一键放置**：
  - 「下载并安装」——从官方 GitHub Releases 取最新的 `WinDivert-*-A.zip`（先查 API，失败回退到固定 2.2.2 地址），解压出 **x64 的 dll/sys** 写到 exe 同目录；
  - 「从本地压缩包安装」——离线场景选一个官方 zip；
  - 「打开目标目录」——手动拖放。
- 设计约束：**安装包内不分发第三方二进制**，一律由用户主动触发下载或自备。

> 首次放置运行库后建议**重启应用**，让 `DynamicLibrary.open` 从干净状态加载。

### 2.3 工作方式（当前实现）

- **一条组合过滤规则**同时抓两类报文：出站 `tcp.DstPort∈{80,443}` 且非 loopback；以及回程 `loopback` 且 `SrcPort==relayPort`。
- 后台**独立 isolate** 阻塞收包：SYN 时登记 NAT 表 `(clientIp:port)→原始目的`，把目的地址改写成 `127.0.0.1:relayPort`；回程把源地址改回原始目的；FIN/RST 时删表。
- 被抓的连接落到 `relayPort` 后由 `TransparentRelay` 用标准 **HTTP CONNECT** 交给既有 MITM 代理，复用既有的 TLS 解密与脚本能力。
- 只抓 TCP 80/443。非 80/443 的 TCP、UDP/QUIC 不在当前范围内。

---

## 3. NetFilter SDK（商业，仅探测）

NetFilter SDK 与 WinDivert 解决同类问题，但它是**商业授权组件**（HTTP Debugger 用的就是它：随包带 `netfilter2.sys` + 一个持有驱动的服务）。本仓库**不内置**它的运行库，也不引导下载，只做**只读探测**，让用户知道「这台机器上是否已经装了它」：

- 驱动文件：`%SystemRoot%\System32\drivers\nfdriver.sys`
- 服务：`sc query nfdriver` 的 `STATE`
- 用户态库：`nfapi.dll` / `nfapi64.dll` 是否在候选目录

探测结果在同一个「检测/安装驱动」面板的「其它内核抓包能力」区块展示。若要在数据面接入 NetFilter，需要用户自行取得 SDK 授权与运行时库——那超出本仓库的可分发范围。

---

## 4. 自研 WFP Callout 驱动（参考骨架，未编译未验证）

> ⚠️ **重要免责**：下面的骨架**没有在本仓库编译、签名或运行过**。内核驱动写错会导致 **蓝屏（BSOD）**、无法卸载、甚至系统无法启动。请只在**可恢复的测试机/虚拟机**上做，并保留快照。本仓库不提供可编译工程，也不对任何后果负责。

### 4.1 为什么本仓库不做它

- 构建需要 **WDK + Visual Studio**（Windows 环境），本仓库的构建环境（Linux CI）没有；
- 加载需要 **内核驱动签名**：Win10 1607+ 强制，个人可用 **EV 证书**做 attestation signing，或走 WHQL；无有效签名只能开测试模式/禁用强制签名，**不适合交付给用户**；
- 「重定向出站连接」比「过滤」复杂：要处理 flow 关联、重入、IPv6、cleanup，工程量与回归成本都很高。相比之下 WinDivert 已经把这一切做完了。

**结论**：除非有明确的、必须自研驱动的理由（例如要进 Windows 内核做更底层的事），否则不要重复造它。

### 4.2 正确的层：ALE_CONNECT_REDIRECT

要「把出站连接重定向到本地代理」，应使用 **`FWPM_LAYER_ALE_CONNECT_REDIRECT_V4`**（Win8+ 提供，Proxifier 类工具用它），在该层拿到可写的 `FWPS_CONNECT_REQUEST0`，改写 `localAddress` / `localPort` 指向本地代理。**不要**在 `ALE_AUTH_CONNECT` 层直接改 `remoteAddress` 来「假装连上了别处」——那层的语义是授权判定，不是重定向。

### 4.3 关键序列（伪代码，仅供理解结构）

```c
// ---- DriverEntry / 卸载 ----
NTSTATUS DriverEntry(PDRIVER_OBJECT drv, PUNICODE_STRING reg) {
    drv->DriverUnload = OnUnload;
    // 1) 打开 WFP 引擎（内核态用 FwpmEngineOpen0 的 KD 版本在部分文档中标注为需在
    //    用户态打开；内核态通常用 FwpmEngineOpen0(NULL, RPC_C_AUTHN_WINNT, NULL, NULL, &gEngine)）
    FwpmEngineOpen0(NULL, RPC_C_AUTHN_WINNT, NULL, NULL, &gEngine);
    FwpmTransactionBegin0(gEngine, 0);
    FwpmSubLayerAdd0(gEngine, &gSubLayer, NULL);              // 自定义子层，便于按 GUID 清理
    FwpmCalloutAdd0(gEngine, &gCallout, NULL, NULL);          // gCallout.classifyFn = Classify
    FwpmFilterAdd0(gEngine, &gFilter, NULL, NULL);            // 层 = FWPM_LAYER_ALE_CONNECT_REDIRECT_V4
    FwpmTransactionCommit0(gEngine);
    return STATUS_SUCCESS;
}

// ---- 分类回调：改写目的地址 → 本地代理 ----
VOID Classify(const FWPS_INCOMING_VALUES* in, const FWPS_INCOMING_METADATA_VALUES* md,
              void* layerData, const void* ctx, FWPS_CLASSIFY_OUT* out) {
    FWPS_CONNECT_REQUEST0* req = NULL;
    UINT64 classifyHandle = 0;
    if (FwpsAcquireClassifyHandle0(layerData, 0, &classifyHandle) != STATUS_SUCCESS) return;
    if (FwpsAcquireWritableLayerDataPointer0(classifyHandle,
            FWPS_CALLOUT_ALE_CONNECT_REDIRECT, 0, &req, out) == STATUS_SUCCESS) {
        // 跳过自身进程，避免回环
        if (!IsOurProcess(md->processPath)) {
            RtlCopyMemory(&req->localAddress, &gProxyAddr, sizeof(UINT32));
            req->localPort = htons(gProxyPort);
        }
        FwpsApplyModifiedLayerData0(classifyHandle, req, 0);
    }
    FwpsReleaseClassifyHandle0(classifyHandle);
}
```

要点：**跳过自身进程**（否则代理自己的出站又被重定向，形成回环）、只在 `FWPS_RIGHT_ACTION_WRITE` 允许时改、用自定义子层 GUID 保证卸载时能干净删掉所有 filter/callout。

### 4.4 构建与签名步骤（梳理，未在本仓库执行）

1. 安装 **WDK**（与 VS 同版本）+ Windows SDK；新建 “Empty WDM Driver” 工程，放入 `*.c` / `*.h`；
2. 用 **INF** 声明服务（`Kmdf`/`Wdf` 视需要），`DriverType=1`；
3. 编译出 `nfx.sys`（示例名）后，**用 EV 证书对 .cab 提交 Microsoft 做 attestation signing**（或本地测试签名 `signtool sign /a /fd sha256` + 测试模式）；
4. 用 `sc create nfx type= kernel binPath= ...` 注册、`sc start nfx` 加载；
5. 调试用 **WinDbg + 双机内核调试**；卸载务必在 `DriverUnload` 里删干净 filter/callout 再关引擎。

> 再次强调：以上仅为结构参考，**未经编译与真机验证**。若真的要走这条路，建议直接以 WinDivert 的源码为起点（它就是一份可读的 WFP 实现），比从零写省得多。

---

## 5. 真机验证清单

### 5.1 HTTP/2 连接树 + 分阶段耗时

1. 启动代理，用浏览器访问一个 HTTP/2 站点（如 `https://http2.golang.org` 或任一支持的网站）；
2. 请求列表「⋮」→ **连接**：应看到该连接的协议为 `HTTP/2`、`TLS` 标签、客户端地址，展开后每个请求带 `#streamId`；
3. 同一视图右上角 → **连接树自检**：
   - 关注「streamId 覆盖 x/y」是否接近 1；「连接耗时 / TLS 耗时」覆盖是否非零（新建连接时才会计时）；
   - 若出现 `HTTP/2 请求未解析到 streamId` 的提示，说明该请求的 streamId 没解析出来，需要贴报告定位；
4. 「导出 JSON」把报告存下来，可作为问题复现材料。

### 5.2 内核级抓包（WinDivert）

1. 以**管理员**运行，工具箱 → 内核级抓包 → 检测/安装驱动，确认两个文件就位（或一键下载放置）；
2. 先启动代理（内核抓包依赖既有代理端口）；
3. 开启内核抓包，用一个**不认系统代理**的程序访问 `http://` 与 `https://` 目标，应在代理的请求列表里看到它们；
4. 观察面板统计：`重定向 SYN` 增长、`回程` 增长、`跳过自身` 不应异常大；抓不到的站点看 `未匹配`；
5. 关闭内核抓包后，确认网络恢复正常（驱动句柄关闭、NAT 表清空）。

> **如实说明**：以上内核抓包能力在 Linux 构建环境下开发，只有纯 Dart 的报文解析/改写/校验和做过本地单元测试，WinDivert FFI 按官方头文件编写，CI 五端编译通过；**尚未在真实 Windows 真机做端到端验证**。首次使用请留好恢复手段。
