# MCP 服务运行时（指标 / 审计 / 保活 / 参数校验）

> 从 v1.24.12 起，MCP 服务有了自己的运行指标、调用审计、后台保活与参数强校验。
> 入口：设置 → **MCP 连接**；监控端点可直接 HTTP 访问。

---

## 1. 运行指标

| 端点 | 用途 |
|---|---|
| `/health`、`/healthz` | 轻量探活：状态、版本、协议版本、在飞调用数。保持极小响应体，供客户端高频探测 |
| `/metrics` | 完整指标：会话数与 SSE 连接数、调用量 / 失败率 / 超时数 / 被拒数、并发水位、工具级耗时与失败统计 |

MCP 工具侧对应 `get_performance_metrics` 的 `mcp` 段（与它原有的「进程内存 + 抓包统计」并列）。

指标随服务重启清零；`started_at` 与 `uptime_seconds` 可用于判断服务是否被系统悄悄重启过。

---

## 2. 工具调用审计

`get_mcp_audit` 返回最近 **500** 条调用记录：

| 字段 | 说明 |
|---|---|
| `at` | 调用时间 |
| `tool` | 工具名 |
| `caller` | 来源：`loopback` / `lan` / `internal` |
| `duration_ms` | 耗时 |
| `ok` | 成功与否 |
| `error` | 失败原因（成功时为空） |
| `arg_keys` | **参数名列表** |
| `arg_bytes` | 参数序列化长度 |

关于隐私：**只记录参数名，不记录参数值**。参数值里可能有抓包正文、令牌、Cookie——审计日志不该成为新的泄露面。

支持 `limit` / `tool` / `only_failed` 过滤，用于「哪个工具在失败」「某个客户端在做什么」。

---

## 3. 并发闸与超时

Dart 标准库没有 Semaphore，这里用「在飞计数 + 等待队列」实现：

| 项 | 值 |
|---|---|
| 并发上限 | 16 |
| 等待队列 | 64 |
| 等待上限 | 5 秒 |
| 超限行为 | **立刻拒绝**，返回 `MCP server is busy` |

**忙时快速失败，而不是排长队**——排长队会让连接和内存一起堆积，最后整台设备都卡。拒绝一次、让调用方稍后重试，代价小得多。

每个工具可声明独立超时，避免一个卡住的设备类调用占满 120 秒：

| 工具类别 | 超时 |
|---|---|
| 设备类（`tap_screen` / `dump_ui` / `screenshot` / `swipe_screen` …）| 30 秒 |
| `shell` | 60 秒 |
| 导出类（`export_har` / `import_har`）| 60 秒 |
| `diagnose_capture` / `get_quic_sessions` | 45 秒 |
| 其它 | 120 秒（默认）|

---

## 4. 后台保活（Shizuku / root / Dhizuku）

MCP 工具 `keep_alive`，或设置页的「**后台保活**」开关。执行的是 **adb shell 语义**的命令集：

| 动作 | 命令 |
|---|---|
| 应用 | `dumpsys deviceidle whitelist +<pkg>`<br>`cmd appops set <pkg> RUN_IN_BACKGROUND allow`<br>`cmd appops set <pkg> RUN_ANY_IN_BACKGROUND allow`<br>`am set-inactive <pkg> false` |
| 还原 | 对应的 `-<pkg>` 与 `default` |
| 查询 | 状态探测（白名单命中 + 两个 appops 当前值）|

含义分别是：进电池优化白名单、解除后台运行限制、取消系统给应用打的「闲置」标记。

**权限通道三选一**，用 `mode` 指定，默认 `auto` 自动挑可用的：

| mode | 通道 | 说明 |
|---|---|---|
| `shizuku` | Shizuku | **不需要 root**，Shizuku 提供 shell 权限即可，推荐 |
| `root` | `su` | 需要 root |
| `dhizuku` | Dhizuku | 设备所有者模式 |
| `auto` | 自动 | 按可用性挑 |

参数 `package` 可省略——省略时默认作用于本应用自身。

> 保活只能**降低**被系统杀掉的概率，不是免死金牌。厂商 ROM 的后台策略各有差异，
> 重度省电模式下仍可能被清；这时需要把应用加入系统的「自启动」白名单（各 ROM 位置不同）。

---

## 5. 参数强校验

按每个工具声明的 `inputSchema` 校验：

- 必填项缺失
- 类型不符（`string` / `integer` / `number` / `boolean` / `array` / `object`）
- 枚举值不在允许集合内
- 数值超出 `minimum` / `maximum`

校验失败会**提前**返回 `Invalid arguments: ...`，而不是让工具跑到一半抛出难以理解的异常。设置页可关闭（默认开启）。

设计上刻意保守：

- 只校验 schema 里**声明过**的参数，未声明的额外参数一律放行（向前兼容，不会因为客户端多传字段而失败）；
- `string` 位置宽容接受数字与布尔；
- 值为 `null` 时交给工具自己处理，不拦。

---

## 6. 实现位置

| 文件 | 职责 |
|---|---|
| `lib/network/mcp/mcp_runtime.dart` | `McpMetrics` 指标、`McpAuditLog` 审计环形缓冲、`McpGate` 并发闸、`McpToolRuntime` 统一执行入口与 schema 校验 |
| `lib/network/mcp/mcp_server.dart` | 接入统一入口（`_runTool`）、`/healthz` 与 `/metrics` 端点、`keep_alive` 与 `get_mcp_audit` 工具实现 |
| `lib/network/bin/configuration.dart` | `appVersion` 版本单一真源、`mcpKeepAlive` / `mcpStrictValidation` 配置项 |

统一入口的意义：参数校验 → 并发闸 → 超时 → 指标 → 审计这条链路只写一遍，
HTTP、SSE、stdio、UI 内部调用都走它，不会出现「某个入口漏了审计」的情况。
