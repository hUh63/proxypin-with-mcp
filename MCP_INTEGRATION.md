# ProxyPin MCP 1.3.1 - 完整源码说明

## 概述

本源码基于 ProxyPin 1.3.1 原版，集成了 MCP (Model Context Protocol) 功能，使 AI 代理能够：
- 控制 ProxyPin 代理服务器（启停、配置）
- 搜索和查看捕获的 HTTP 请求
- 重放请求、生成代码
- 添加请求重写、URL 屏蔽、Hosts 映射等规则
- 管理 JavaScript 脚本
- 导入/导出 HAR 文件
- 在 Android 设备上执行 UI 自动化（需无障碍服务或 Root）

ProxyPin 1.3.1 新增功能（已包含在本源码中）：
- 请求断点调试（Breakpoint）
- 弱网络模拟（Weak Network）
- 环境变量管理（Environment Variables）
- 网络条件管理（Network Condition）
- 多语言支持（西班牙语、印尼语、葡萄牙语、泰语、越南语）
- UI 性能优化（虚拟化高亮文本）
- XML/HTML/CSS/JS 格式化工具
- 文本差异对比工具

## MCP 架构

```
┌──────────────┐     JSON-RPC      ┌──────────────────┐     MethodChannel     ┌─────────────────┐
│  Python MCP  │ ◄──────────────► │  Dart MCP Server │ ◄──────────────────► │  Android Native │
│   Server     │    HTTP/SSE       │  (mcp_server.dart)│   (com.proxy/mcpScreen)│  (McpPlugin.kt) │
└──────────────┘                   └──────────────────┘                       └─────────────────┘
                                          │                                          │
                                          ▼                                          ▼
                                   ┌──────────────┐                        ┌──────────────────────┐
                                   │  McpBridge   │                        │ McpAccessibilitySvc  │
                                   │ (流量桥接)    │                        │ (无障碍服务)          │
                                   └──────────────┘                        └──────────────────────┘
```

## 新增/修改文件清单

### Android 原生层 (Kotlin)

| 文件 | 说明 |
|------|------|
| `android/.../plugin/McpPlugin.kt` | **新增** Flutter 插件，桥接 MCP 命令到 Android 无障碍/Shell |
| `android/.../plugin/McpAccessibilityService.kt` | **新增** 无障碍服务，提供 UI 自动化能力 |
| `android/.../MainActivity.kt` | **修改** 注册 McpPlugin |
| `android/.../AndroidManifest.xml` | **修改** 声明无障碍服务 |
| `android/.../res/xml/mcp_accessibility_config.xml` | **新增** 无障碍服务配置 |
| `android/.../res/values/mcp_strings.xml` | **新增** MCP 字符串资源 |

### Dart 层

| 文件 | 说明 |
|------|------|
| `lib/network/mcp/mcp_server.dart` | **新增** MCP Server，实现 JSON-RPC 协议和 49 个工具 |
| `lib/network/mcp/mcp_bridge.dart` | **新增** 流量桥接器，连接 ProxyServer 和 McpServer |
| `lib/native/mcp_screen.dart` | **新增** Dart 端 MethodChannel 桥接，封装设备控制 API |
| `lib/network/bin/configuration.dart` | **修改** 添加 mcpPort 配置（默认 9010） |
| `lib/ui/desktop/desktop.dart` | **修改** 桌面端 MCP 初始化和清理 |
| `lib/ui/mobile/mobile.dart` | **修改** 移动端 MCP 初始化和清理 |

### Python MCP Server

| 文件 | 说明 |
|------|------|
| `mcp-server/proxypin_mcp_server.py` | **新增** Python FastMCP 服务器，对接外部 AI 代理 |

## MCP Server 工具列表

### 代理控制工具 (23 个)

| 工具名 | 功能 |
|--------|------|
| `set_config` | 设置系统代理和 SSL 抓包 |
| `add_host_mapping` | 添加 Hosts 域名映射 |
| `add_response_rewrite` | 添加响应重写规则 |
| `add_request_rewrite` | 添加请求重写规则 |
| `block_url` | 屏蔽 URL |
| `update_script` | 创建/更新 JavaScript 脚本 |
| `get_scripts` | 获取所有脚本 |
| `search_requests` | 高级搜索请求 (支持 URL/方法/状态码/域名/Header/Body/耗时过滤) |
| `get_recent_requests` | 获取最近请求列表 (Legacy) |
| `get_request_details` | 获取请求详情 (含 Body 编码信息) |
| `get_statistics` | 获取请求统计 |
| `export_har` | 导出 HAR 文件 (支持指定 request_ids) |
| `import_har` | 导入 HAR 文件 |
| `generate_code` | 生成 Python/JS/cURL 代码 |
| `get_curl` | 生成 cURL 命令 |
| `replay_request` | 重放请求 |
| `compare_requests` | 对比两个请求 (Header/Body 差异) |
| `find_similar_requests` | 查找相似请求 |
| `extract_api_endpoints` | 提取 API 端点 |
| `start_proxy` | 启动代理服务器 |
| `stop_proxy` | 停止代理服务器 |
| `get_proxy_status` | 获取代理状态 |
| `clear_requests` | 清空请求列表 |

### 设备控制工具 (11 个, 仅 Android)

| 工具名 | 功能 |
|--------|------|
| `get_device_info` | 获取设备信息 (型号/品牌/版本/IP/Root/无障碍状态) |
| `get_current_activity` | 获取当前前台 Activity/包名 |
| `dump_ui` | 导出 UI 层级为 JSON (支持 clickable_only/package_filter) |
| `tap_screen` | 点击坐标 |
| `long_press` | 长按坐标 (可指定时长) |
| `swipe_screen` | 滑动手势 |
| `key_event` | 按键事件 (HOME/BACK/RECENTS/POWER/MENU) |
| `input_text` | 在焦点元素输入文本 |
| `screenshot` | 截屏 (需 Root, 返回 Base64 PNG) |
| `open_accessibility_settings` | 打开无障碍设置页面 |
| `shell` | 执行 Shell 命令 (可选 Root, 可设超时) |

### 断点调试工具 (4 个, 1.3.1+)

| 工具名 | 功能 |
|--------|------|
| `add_breakpoint_rule` | 添加断点规则 (拦截请求/响应, 支持 URL 正则和 HTTP 方法过滤) |
| `remove_breakpoint_rule` | 按 URL pattern 移除断点规则 |
| `list_breakpoint_rules` | 列出所有断点规则及状态 |
| `toggle_breakpoint` | 全局启用/禁用断点调试功能 |

### 弱网络模拟工具 (5 个, 1.3.1+)

| 工具名 | 功能 |
|--------|------|
| `add_weak_network_rule` | 添加弱网络规则 (绑定 URL 和预设方案) |
| `add_custom_network_profile` | 创建自定义弱网络预设 (带宽/延迟/抖动/丢包/离线) |
| `list_weak_network_rules` | 列出所有弱网络规则和预设方案 |
| `remove_weak_network_rule` | 按 URL pattern 移除弱网络规则 |
| `toggle_weak_network` | 全局启用/禁用弱网络模拟功能 |

### 环境变量管理工具 (6 个, 1.3.1+)

| 工具名 | 功能 |
|--------|------|
| `list_environments` | 列出所有环境及变量 (含当前生效变量映射) |
| `set_environment_variable` | 设置/更新/删除环境变量 (支持 `{{name}}` 渲染) |
| `create_environment` | 创建命名环境 (Dev/Staging/Prod) |
| `set_active_environment` | 设置激活环境 (传空取消激活) |
| `remove_environment` | 移除命名环境 (不能移除 Global) |
| `toggle_environment_variables` | 全局启用/禁用环境变量功能 |

## Android 无障碍服务 MethodChannel 方法

| 方法 | 功能 |
|------|------|
| `getDeviceInfo` | 获取设备信息 |
| `getCurrentActivity` | 获取当前前台 Activity |
| `dumpUi` | 导出 UI 层级 |
| `tap` | 点击坐标 |
| `click` | 长按坐标 |
| `swipe` | 滑动手势 |
| `keyEvent` | 按键事件 (HOME/BACK/RECENTS/POWER/MENU) |
| `inputText` | 输入文本 |
| `screenshot` | 截屏 (需 Root) |
| `openAccessibilitySettings` | 打开无障碍设置 |
| `shell` | 执行 Shell 命令 |

## 编译和运行

### Flutter 应用

```bash
cd proxypin-1.3.1
flutter pub get
flutter build apk --release
```

### Python MCP Server

```bash
pip install fastmcp requests
cd mcp-server
python proxypin_mcp_server.py
```

### 配置

MCP Server 默认仅监听 `127.0.0.1:9010`（`mcpAllowLan=false`）；如需局域网访问，在偏好设置中开启「允许局域网访问」（将改为监听 `0.0.0.0`，且无鉴权，请谨慎）。端口可在 `Configuration` 中修改 `mcpPort`。

Python Server 通过环境变量配置：
- `PROXYPIN_HOST`: ProxyPin 主机 (默认 127.0.0.1)
- `PROXYPIN_PORT`: MCP 端口 (默认 9010)

## 技术要点

1. **无协程依赖**: McpPlugin.kt 使用 `CountDownLatch` 替代 `kotlinx.coroutines`，避免额外依赖
2. **UI 层解耦**: McpBridge 提供抽象接口，McpServer 不直接依赖 UI 组件
3. **双模式支持**: Android 端支持无障碍服务和 Root 两种模式
4. **SSE 推送**: 支持 Server-Sent Events 实时推送请求变更
5. **SSE 心跳保活**: 每 30 秒发送 ping 事件，防止连接超时
6. **SSE 死连接清理**: 广播失败时自动移除无效连接
7. **Body 编码**: 自动检测 UTF-8/Base64 编码，正确处理二进制数据
8. **JSON-RPC 通知处理**: 正确处理 `notifications/initialized` 和 `notifications/cancelled`，返回 202 Accepted
9. **类型安全**: 所有 JSON-RPC 参数使用 `num.toInt()` 转换，避免 double/int 类型不匹配
10. **Null 安全**: 对 `params` 字段进行 null 检查，防止 NoSuchMethodError
11. **资源清理**: MCP Server 停止时正确关闭所有 SSE 连接、取消心跳定时器、清除回调
12. **动态超时**: Python 服务器 `shell` 命令根据 `timeout_ms` 动态调整 HTTP 超时
13. **RuleType 匹配**: 根据 RewriteType 自动选择正确的 RuleType（替换 vs 修改），确保重写规则正确生效
14. **SSE 即时刷新**: 广播事件后调用 `flush()` 确保数据立即发送，避免缓冲延迟
15. **进程清理**: Shell 命令超时后调用 `destroyForcibly()` 防止僵尸进程
16. **Root 状态缓存**: `hasRoot()` 结果缓存，避免每次调用都 fork su 进程
17. **命令注入防护**: `inputText` root 路径完整转义特殊字符，防止命令注入
18. **错误信息透明**: `dumpUiViaRoot`/`screenshotViaRoot` 失败时读取 stderr 并抛出详细错误
19. **SSE 线程安全**: SSE 连接列表使用快照遍历模式，避免遍历期间被并发修改导致 ConcurrentModificationError
20. **移动端 system_proxy 适配**: `set_config` 在移动端检测 VPN 运行状态，自动重启 VPN 以应用 system_proxy 变更
21. **断点调试 MCP 适配**: 新增 4 个断点调试工具，支持通过 MCP 添加/移除/列出断点规则和全局开关
22. **弱网络模拟 MCP 适配**: 新增 5 个弱网络工具，支持内置预设(2G/3G/4G/5G/WiFi)和自定义参数
23. **环境变量 MCP 适配**: 新增 6 个环境变量工具，支持环境管理、变量 CRUD、激活切换和全局开关
24. **资源 URI 扩展**: 新增 3 个 MCP 资源 URI (breakpoints/rules, network/conditions, environments/list)
25. **重写规则持久化**: `add_response_rewrite` 和 `add_request_rewrite` 添加 `flushRequestRewriteConfig()` 确保规则持久化
26. **SSE 配置变更通知**: 1.3.1 新功能工具（断点/弱网络/环境变量）在配置变更后广播 `config_changed` SSE 事件，通知连接的 MCP 客户端刷新资源视图
27. **环境变量安全校验**: `set_environment_variable` 在指定 `environment_id` 时严格校验环境是否存在，不存在时返回错误而非静默回退到 Global

## 1.3.1 合并说明

本版本将 MCP 功能从 ProxyPin 1.2.5 合并到 1.3.1，主要变更：

1. **configuration.dart**: 添加 `mcpPort` 字段及序列化/反序列化
2. **AndroidManifest.xml**: 添加 McpAccessibilityService 声明
3. **MainActivity.kt**: 注册 McpPlugin（1.3.1 插件目录结构已调整到 `plugin/` 子目录）
4. **desktop.dart**: 添加 MCP 初始化（McpBridge 容器绑定、UI 清除回调、ProxyServer 监听器）和清理
5. **mobile.dart**: 同上，使用 `MobileApp.container` 和 `MobileApp.requestStateKey`
6. **API 适配**: 1.3.1 中 `RequestRewriteRule` 使用 `UrlPattern.toRegExp()` 替代手动 RegExp 构造，`RequestBlockItem.match` 使用 `UrlPattern.toHostRegExp()`，`ScriptItem` 新增 `remoteUrl` 字段 — 所有这些变更与 MCP 代码完全兼容，无需修改
7. **清理方法适配**: 1.3.1 中请求列表清理方法从 `clearAll()` 改为 `clean()`，已适配
8. **断点调试适配**: 新增 `add_breakpoint_rule`/`remove_breakpoint_rule`/`list_breakpoint_rules`/`toggle_breakpoint` 四个工具，直接操作 `RequestBreakpointManager`
9. **弱网络适配**: 新增 `add_weak_network_rule`/`add_custom_network_profile`/`list_weak_network_rules`/`remove_weak_network_rule`/`toggle_weak_network` 五个工具，操作 `NetworkConditionManager`
10. **环境变量适配**: 新增 `list_environments`/`set_environment_variable`/`create_environment`/`set_active_environment`/`remove_environment`/`toggle_environment_variables` 六个工具，操作 `EnvironmentManager`
11. **set_config 移动端修复**: 1.3.1 中 `setSystemProxyEnable` 仅在桌面端生效，移动端通过 `Vpn.restartVpn` 重启 VPN 应用变更
12. **SSE 线程安全增强**: SSE 连接列表所有遍历操作改用快照模式，避免 `ConcurrentModificationError`
13. **isNotification 清理**: 移除 `_processJsonRpc` 中未使用的 `isNotification` 变量
14. **McpBridge 重注册**: `start_proxy` 工具在新创建 `ProxyServer` 后重新注册 `McpBridge` 监听器
15. **重写规则持久化修复**: `add_response_rewrite`/`add_request_rewrite` 添加 `flushRequestRewriteConfig()` 调用确保规则持久化
16. **SSE 配置变更通知**: 新增 `_notifyConfigChanged` 方法，1.3.1 新功能工具在配置变更后广播 `config_changed` 事件
17. **环境变量安全校验**: `set_environment_variable` 指定 `environment_id` 时校验环境存在性，避免静默回退
18. **工具实现完整性**: 修复 15 个新工具定义在 `_getToolsList` 中声明但未在 `_executeTool` 中实现的问题
