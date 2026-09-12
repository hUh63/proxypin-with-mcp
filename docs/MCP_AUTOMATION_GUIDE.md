# ProxyPin MCP 自动化功能使用指南

> 版本：v1.17.0+  
> 最后更新：2026-08-21

---

## 📖 目录

1. [功能概览](#功能概览)
2. [定时任务](#定时任务)
3. [事件监听](#事件监听)
4. [规则引擎](#规则引擎)
5. [工作流编排](#工作流编排)
6. [最佳实践](#最佳实践)
7. [常见问题](#常见问题)

---

## 功能概览

ProxyPin v1.12.0+ 引入了完整的 MCP（Man-in-the-Middle Control Protocol）自动化功能，支持：

| 功能模块 | 描述 | 触发方式 |
|---------|------|---------|
| **定时任务** | 按计划执行的自动化任务 | Cron 表达式 |
| **事件监听** | 响应系统事件的自动化任务 | 事件触发 |
| **规则引擎** | 基于 HTTP 请求条件的自动化 | 请求匹配 |
| **工作流编排** | 多脚本顺序/并行执行 | 手动/自动触发 |

### 访问入口

**移动端**: 设置 → MCP 自动化 → 4 个标签页  
**桌面端**: 脚本 → 工作流管理 / 控制台

---

## 定时任务

### 创建定时任务

1. 打开 **MCP 自动化** 页面
2. 切换到 **定时任务** 标签页
3. 点击右下角 `+` 按钮

### 配置触发器

#### Cron 表达式语法

> **v1.22.22 起**：定时方式选择器支持 5 种模式（一次性 / 每天 / 每周 / 间隔 / Cron），流式布局自适应换行；
> 选择 Cron 后可实时预览下次执行时间，并提供常用示例一键填入。
> 重复任务（每天/每周/间隔/Cron）在应用停用一段时间后重新打开，会自动推进到下一个执行点，不会因过期失效。


```
秒 分 时 日 月 星期
```

**常用示例**:

| 表达式 | 含义 |
|--------|------|
| `0 0 * * * ?` | 每小时整点执行 |
| `0 0 12 * * ?` | 每天 12:00 执行 |
| `0 0/5 * * * ?` | 每 5 分钟执行 |
| `0 0 9-18 * * ?` | 每天 9:00-18:00 每小时执行 |
| `0 0 1 ? * MON` | 每周一 01:00 执行 |

#### 事件触发器

| 事件名称 | 触发时机 |
|---------|---------|
| `proxy.started` | 代理启动时 |
| `proxy.stopped` | 代理停止时 |
| `proxy.paused` | 代理暂停时 |
| `network.connected` | 网络连接时 |
| `network.disconnected` | 网络断开时 |

### 配置动作

支持 9 种动作类型：

| 动作类型 | 描述 | 参数示例 |
|---------|------|---------|
| `modifyRequest` | 修改请求头/体 | `{"headers": {"X-Custom": "value"}}` |
| `modifyResponse` | 修改响应头/体 | `{"statusCode": 200}` |
| `blockRequest` | 拦截请求 | `{"reason": "Blocked"}` |
| `replayRequest` | 重放请求 | `{"url": "https://..."}` |
| `exportData` | 导出数据 | `{"format": "har", "path": "/sdcard/export.har"}` |
| `runScript` | 执行脚本 | `{"language": "javascript", "script": "..."}` |
| `sendNotification` | 发送通知 | `{"title": "提醒", "content": "内容"}` |
| `callWebhook` | 调用 Webhook | `{"url": "https://...", "method": "POST"}` |
| `log` | 记录日志 | `{"message": "日志内容"}` |

### 示例：每天导出 HAR 数据

```json
{
  "name": "每日数据导出",
  "enabled": true,
  "trigger": {
    "type": "cron",
    "cronExpression": "0 0 23 * * ?"
  },
  "actions": [
    {
      "type": "exportData",
      "params": {
        "format": "har",
        "path": "/sdcard/proxypin/daily_export.har"
      }
    }
  ]
}
```

---

## 事件监听

### 订阅事件

1. 打开 **MCP 自动化** → **事件监听** 标签页
2. 点击 `+` 添加事件订阅
3. 选择事件类型并配置回调

### 内置事件类型

#### 网络状态事件

```dart
enum NetworkStatus {
  connected,     // 网络连接
  disconnected,  // 网络断开
  wifi,          // WiFi 连接
  mobile,        // 移动数据
  weak,          // 弱网
}
```

#### 代理状态事件

```dart
enum ProxyStatus {
  started,   // 代理启动
  stopped,   // 代理停止
  paused,    // 代理暂停
  resumed,   // 代理恢复
}
```

### 示例：代理启动时自动加载规则

```json
{
  "name": "代理启动加载规则",
  "enabled": true,
  "trigger": {
    "type": "event",
    "eventName": "proxy.started"
  },
  "actions": [
    {
      "type": "runScript",
      "params": {
        "language": "javascript",
        "script": "mcp.loadRules('/sdcard/proxypin/rules.json');"
      }
    }
  ]
}
```

---

## 规则引擎

### 创建 HTTP 请求规则

1. 打开 **MCP 自动化** → **规则引擎** 标签页
2. 点击 `+` 创建规则
3. 配置匹配条件和动作

### 条件类型

| 条件类型 | 描述 |
|---------|------|
| `httpRequest` | HTTP 请求条件 |
| `networkStatus` | 网络状态条件 |
| `proxyStatus` | 代理状态条件 |
| `systemStatus` | 系统状态条件 |
| `custom` | 自定义条件 |

### 条件行的构成

每一条条件由四段组成，自上而下依次选择：

```
[条件类型]   ← 决定「字段」的可选项
[字段] [运算符]
[值]         ← 随字段与运算符自动切换控件
```

**字段候选项由「条件类型」决定**（`_ConditionRow.fieldsForType`）：

| 条件类型 | 可选字段（下拉中显示的中文名） |
|---------|------------------------------|
| `httpRequest` | URL、方法、状态码、耗时(ms)、域名、路径、**请求 Content-Type**、**响应 Content-Type**、请求大小、响应大小 |
| `proxyStatus` | 代理状态、类型、时间戳 |
| `networkStatus` | 网络状态、类型、时间戳 |
| `systemStatus` | 内存使用(MB)、抓包数量、磁盘使用(MB)、CPU 使用率(%) |

切换条件类型时，字段会自动重置为该类型的第一个可选值，已填的值会被清空（避免残留无效组合）。

**长字段显示**：像「请求 Content-Type」这类较长的字段名，在字段框内以**单行 + 省略号**呈现，不会换行截断；按住（移动端）/悬停（桌面端）字段或选项可查看完整文本。**字段与运算符各占整行**，长字段在任意屏幕宽度与字号下都能完整显示。

**与值编辑器的联动**（`_buildValueEditor`）：选定字段与运算符后，值输入框会自动变形——代理/网络状态等枚举型字段配合 `=` / `≠` 时给出**下拉选项**，其余情况（数值、正则、列表、时间戳等）使用**文本框**；`matches` 按正则解析，`inList` / `notInList` 按逗号拆分为列表（见 `_ConditionRow.toCondition`）。

**开发位置**：条件行的 UI 与字段映射在 `lib/ui/mobile/setting/mcp_automation.dart`（桌面端复用同一弹窗组件），下拉统一走 `_dropdownText` / `_selectedItems` 保证「长文本不裁切 + 省略可查全」。

### 操作符（14 种）

| 操作符 | 描述 | 示例 |
|--------|------|------|
| `equals` | 等于 | `method == 'GET'` |
| `notEquals` | 不等于 | `statusCode != 404` |
| `greaterThan` | 大于 | `contentLength > 1000` |
| `lessThan` | 小于 | `responseTime < 500` |
| `contains` | 包含 | `url.contains('api')` |
| `startsWith` | 以...开头 | `url.startsWith('https://')` |
| `endsWith` | 以...结尾 | `url.endsWith('.json')` |
| `matches` | 正则匹配 | `url.matches(r'^https://.*\.com$')` |
| `inList` | 在列表中 | `method in ['GET', 'POST']` |
| `notInList` | 不在列表中 | `method notIn ['DELETE']` |
| `exists` | 字段存在 | `headers exists` |
| `notExists` | 字段不存在 | `authorization notExists` |

### 规则优先级

| 优先级 | 数值 | 说明 |
|--------|------|------|
| `low` | 0 | 低优先级 |
| `normal` | 1 | 普通优先级（默认） |
| `high` | 2 | 高优先级 |
| `critical` | 3 | 关键优先级 |

### 示例：拦截所有非 HTTPS 请求

```json
{
  "id": "block_http",
  "name": "拦截 HTTP 请求",
  "enabled": true,
  "priority": "high",
  "conditions": [
    {
      "type": "httpRequest",
      "field": "scheme",
      "operator": "equals",
      "value": "http"
    }
  ],
  "actions": [
    {
      "type": "blockRequest",
      "params": {
        "reason": "仅允许 HTTPS 请求",
        "statusCode": 403
      }
    }
  ]
}
```

### 示例：自动添加请求头

```json
{
  "id": "add_headers",
  "name": "添加自定义头",
  "enabled": true,
  "urlPattern": "*/api/*",
  "conditions": [
    {
      "type": "httpRequest",
      "field": "method",
      "operator": "inList",
      "value": ["POST", "PUT"]
    }
  ],
  "actions": [
    {
      "type": "modifyRequest",
      "params": {
        "headers": {
          "X-ProxyPin": "true",
          "X-Timestamp": "{{timestamp}}"
        }
      }
    }
  ]
}
```

---

## 工作流编排

### 创建工作流

1. 打开 **MCP 自动化** → **工作流** 标签页
2. 点击 `+` 创建工作流
3. 添加节点并配置依赖关系

### 节点类型

| 脚本类型 | 描述 | 适用场景 |
|---------|------|---------|
| `javascript` | JavaScript 脚本 | 快速原型、数据处理 |
| `dart` | Dart 脚本 | 复杂逻辑、类型安全 |
| `shell` | Shell 脚本 | 系统命令、文件操作 |

### 依赖管理

工作流引擎使用 **DAG（有向无环图）** 管理节点依赖：

```
节点 A → 节点 B → 节点 C
         ↓
       节点 D
```

- 节点 B 和 D 依赖节点 A
- 节点 C 依赖节点 B
- 节点 B 和 D 可并行执行

### 变量替换

支持 `{{variable}}` 语法：

```javascript
// 脚本中使用变量
const url = "{{baseUrl}}/api/users";
const token = "{{authToken}}";

// 执行时传入变量
{
  "baseUrl": "https://api.example.com",
  "authToken": "Bearer xyz123"
}
```

### 失败重试机制

```json
{
  "retryConfig": {
    "maxRetries": 3,        // 最大重试次数
    "retryInterval": 5000,  // 重试间隔 (ms)
    "backoffMultiplier": 2  // 退避倍数
  }
}
```

### 示例：API 测试工作流

```json
{
  "id": "api_test_workflow",
  "name": "API 自动化测试",
  "description": "执行登录→获取数据→验证结果",
  "enabled": true,
  "nodes": [
    {
      "id": "login",
      "name": "登录",
      "scriptType": "javascript",
      "script": "const token = await api.login(username, password); return token;"
    },
    {
      "id": "fetch_data",
      "name": "获取数据",
      "scriptType": "javascript",
      "script": "const data = await api.get('/users', {headers: {Authorization: '{{login}}'}}); return data;",
      "dependencies": ["login"]
    },
    {
      "id": "validate",
      "name": "验证结果",
      "scriptType": "javascript",
      "script": "assert(fetch_data.length > 0);",
      "dependencies": ["fetch_data"]
    }
  ],
  "variables": {
    "username": "test_user",
    "password": "test_pass"
  }
}
```

### 执行模式

| 模式 | 描述 | 适用场景 |
|------|------|---------|
| **顺序执行** | 按依赖顺序依次执行 | 有严格先后顺序的任务 |
| **并行执行** | 无依赖节点并行执行 | 独立任务批量处理 |

---

## 最佳实践

### 1. 任务命名规范

```
✅ 推荐：daily_export_har、block_http_requests、api_test_workflow
❌ 避免：task1、test、abc
```

### 2. 错误处理

```javascript
// 在脚本中添加错误处理
try {
  const result = await api.request();
  return result;
} catch (error) {
  logger.error(`请求失败：${error.message}`);
  notify('任务失败', error.message);
  throw error; // 触发重试
}
```

### 3. 日志记录

```javascript
// 使用 logger 记录关键信息
logger.d('调试信息');
logger.i('普通信息');
logger.w('警告信息');
logger.e('错误信息');
```

### 4. 性能优化

- 避免在高频率触发器中使用复杂脚本
- 使用规则优先级减少不必要的匹配
- 工作流中合理设置并行节点

### 5. 安全建议

- 不要在脚本中硬编码敏感信息
- 使用环境变量或加密存储密钥
- 定期导出配置备份
- ==默认只监听 `127.0.0.1`==：MCP 的 `Allow LAN access`（`mcpAllowLan`）关闭时仅本机可连；开启后监听所有网卡且**无鉴权**，仅建议在受信内网临时开启
- ==SSE 连接数上限==：服务端最多保持 32 条并行 SSE 连接（`McpServer.maxSseConnections`），超限的建连请求会收到 `event: error` 并被立即关闭，避免未认证客户端无限建连耗尽资源；正常 IDE 客户端（Cursor / VSCode / Claude）通常只会占用 1~2 条
- ==会话定时器回收==：Streamable HTTP 的 `Mcp-Session-Id` 会话设有 1 小时过期定时器，停止 MCP 服务时会连同心跳定时器一起取消并清空会话表，不会在后台残留定时器

---

## 常见问题

### Q1: 定时任务不执行？

**检查项**:
1. 任务是否启用（enabled: true）
2. Cron 表达式是否正确
3. 应用是否有后台运行权限
4. 查看日志确认触发记录

### Q2: 规则不匹配？

**检查项**:
1. 规则是否启用
2. 条件配置是否正确
3. 优先级是否合理
4. URL 模式是否匹配

### Q3: 工作流执行失败？

**检查项**:
1. 查看执行历史中的错误信息
2. 检查节点依赖是否形成循环
3. 验证脚本语法是否正确
4. 确认变量替换是否正确

### Q4: 如何备份配置？

**方法**:
1. 移动端：设置 → 配置管理 → 导出配置
2. 桌面端：文件 → 导出配置
3. 配置文件位置：`/sdcard/ProxyPin/config.json`

### Q5: 如何调试脚本？

**方法**:
1. 使用 `logger.d()` 输出调试信息
2. 在桌面端使用脚本控制台实时查看日志
3. 使用 `try-catch` 捕获异常

---

## 附录

### Cron 表达式生成器

访问在线工具：https://cron.qqe2.com/

### 脚本模板库

内置 12 个预定义模板：
- JavaScript: 6 个（请求修改、响应处理、数据提取等）
- Dart: 3 个（复杂逻辑、类型转换等）
- Shell: 3 个（文件操作、系统命令等）

### 技术支持

- GitHub Issues: https://github.com/hUh63/apk/issues
- 文档更新：v1.17.0+
