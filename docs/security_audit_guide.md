# 安全自检（Security Self-Audit）

> 对**已经抓到的**流量做被动安全基线核查，把常见隐患按风险等级列出来，可导出报告。
> 入口：工具箱 → **安全自检**。

---

## 1. 它能做什么 / 不做什么

### 能做的（被动分析）

- 只读地分析**已抓到的请求 / 响应**，从中识别常见的不安全写法；
- 覆盖：明文传输、敏感信息泄露、Cookie 安全属性、安全响应头、服务器指纹、报错泄露、CORS、JWT、协议版本；
- 结果按 **高 / 中 / 低 / 提示** 分级，可筛选、可导出 Markdown 报告。

### 明确不做的（主动攻击）

- **不发送任何请求**——没有扫描器、没有载荷投递、没有注入探测、没有爆破、没有绕过；
- 不构造 SQLi / XSS / 命令注入等 payload，不做拖库、不猜测口令、不探测 WAF；
- 不做任何"自动利用"。

这套设计对应的是安全测试里的**被动扫描（passive scan）**：看着已有的流量说话。
它回答的是"我抓到的这些接口，有哪些写法看起来不安全"，而不是"这些接口能不能被攻破"。
后者需要书面授权下的主动测试，不属于抓包工具的职责。

> 一句话：**它检查的是"配置与数据的卫生状况"，不是"漏洞能不能打"。**

---

## 2. 打开与使用

1. 先抓一段流量（确认目标 App / 站点已经有请求进来）；
2. 打开工具箱 → **安全自检**；
3. 稍等片刻，页面会给出：分析请求数 + 四级风险计数 + 风险卡片列表；
4. 顶部筛选条可按等级过滤；点右上角「导出报告」保存 Markdown。

风险卡片包含：等级标签、标题、涉及的请求（`方法 URL`，可选中复制）、现象说明、修复建议。

---

## 3. 规则清单

| 代号 | 等级 | 触发条件 |
|---|---|---|
| `plaintext-http-sensitive` | 高 | `http://` 传输，且 URL 查询串或请求体含 password / token 等敏感字段 |
| `plaintext-http-body` | 中 | `http://` 且带请求体（非 GET） |
| `sensitive-in-url` | 中 | URL 查询串出现 password / token / sign / session 等参数名 |
| `plaintext-password-body` | 中 / 高 | 请求体或表单中出现 `password` / `pwd` 字段（HTTP 下升为高） |
| `cookie-weak-flag` | 低 / 中 | `Set-Cookie` 缺少 Secure / HttpOnly / SameSite（同时缺 Secure+HttpOnly 升为中） |
| `missing-security-headers` | 低 | HTML 响应同时缺 `X-Content-Type-Options` 与 `Content-Security-Policy` |
| `server-fingerprint` | 提示 | 响应暴露 `Server` / `X-Powered-By` / `X-AspNet-Version` / `X-Generator` |
| `private-key-leak` | 高 | 响应体出现 PEM 私钥标记 |
| `secret-in-response` | 高 | 响应体明文返回 password / apiKey / accessKey 等字段或 AWS Access Key |
| `pii-in-response` | 中 | 响应体含身份证 / 手机号字段（字段名 + 值双重判断，降低误报） |
| `error-disclosure` | 中 | 4xx/5xx 响应体出现堆栈 / SQL 报错特征 |
| `cors-wildcard-credentials` | 中 | `Access-Control-Allow-Origin: *` 且 `Access-Control-Allow-Credentials: true` |
| `jwt-alg-none` | 高 | 令牌声明 `alg=none`（未签名） |
| `jwt-no-expiry` | 低 | JWT 载荷缺少 `exp` |
| `http-1-0` | 提示 | 使用 HTTP/1.0 |

判定原则：**字段名 + 值双重判断**（例如先看是否有 `"phone"` 字段、再看值是否像手机号），
尽量避免把普通数字误报成 PII。

### 3.1 自定义规则

内置规则只覆盖通用问题。要想检测**自家业务特有**的内容（内部字段名、测试标记、业务术语），
在自检页右上角点「**自定义规则**」自己加：

| 字段 | 说明 |
|---|---|
| 规则名称 | 命中后在报告里显示的标题 |
| 匹配范围 | 请求 URL / 请求头 / 请求体 / 响应头 / 响应体 / 全部内容 |
| 匹配方式 | **关键词**（忽略大小写包含）或**正则**（忽略大小写，多行） |
| 表达式 | 关键词本身，或正则；正则非法会即时提示并拒绝保存 |
| 风险等级 | 高 / 中 / 低 / 提示，决定报告里的分组 |
| 修复建议 | 选填；不填则给出默认提示 |

- 规则可随时**启停**，改动后报告即时重算；
- 规则保存在 `security_rules.json`（与配置同目录）；
- 匹配依旧是**只读**的——自定义规则同样不发送任何请求。

**示例**：

- 名称「内部调试标记」，范围「全部内容」，方式「关键词」，表达式 `debug_internal`，等级「中」；
- 名称「疑似身份证」，范围「响应体」，方式「正则」，表达式 `\d{17}[\dXx]`，等级「高」。

---

## 4. 实现细节（开发）

### 4.1 分析器

文件：`lib/network/util/security_audit.dart`

- `SecuritySeverity` —— 四级枚举，`weight` 用于排序；
- `SecurityIssue` —— 单条风险（规则代号 / 等级 / 标题 / 现象 / 建议 / 方法 / URL / 请求 ID）；
- `SecurityAuditReport` —— 汇总（`issues` + `scannedRequests` + `count(severity)`）；
- `SecurityAuditor.audit(List<HttpRequest>)` —— 逐请求跑规则，产出报告。

关键约束：

- **去重**：按 `规则代号 + 方法 + URL` 去重，同一接口不重复刷屏；
- **规模保护**：单次最多分析 `maxRequests = 5000` 条（取最新的），单条 body 超过 `maxBodyBytes = 512 KB` 时跳过内容检测，只做头部检测，避免大流量下卡顿；
- **容错**：body 解码失败 / URL 解析失败一律降级为空串，不影响其它规则。

### 4.2 页面

文件：`lib/ui/component/security_audit_page.dart`

- 构造时接收 `List<HttpRequest>`，在 `initState` 的下一帧跑分析（不阻塞首屏）；
- 页面骨架文案走 `AppLocalizations`（`securityAudit*` 键）；规则自身的标题 / 现象 / 建议是技术描述，保持中文常量；
- 报告导出走 `FilePicker.saveFile(fileName:, bytes:)`。

### 4.3 入口

工具箱（`lib/ui/toolbox/toolbox.dart`）→ `IconText(... securityAudit ...)`，从 `requestContainer` 取当前请求列表，
用 `Navigator.push` 打开页面（页面需要传参，因此不走桌面多窗口）。

---

## 5. 与其他功能联动

- **采集方案**：先用方案把域名收敛到目标业务，再做安全自检，报告更聚焦；
- **域名过滤 / 应用筛选**：缩小范围后自检，减少无关噪音；
- **导出（CSV / JSON / HAR）**：自检报告 + 原始报文可一起归档，作为整改前后的对照证据；
- **API 端点**：自检发现的问题接口，可到 API 端点页看它在清单里的分布与调用频次；
- **MCP**：`get_recent_requests` 支持按 domain 过滤，便于把某业务的流量交给 AI 二次分析。

---

## 6. 导出报告格式

导出的 Markdown 形如：

```markdown
# ProxyPin 安全自检

- 已分析请求: 128
- 风险项: 6

## 高危 (2)

- **明文 HTTP 传输敏感信息** — `POST http://api.example.com/login`
  - ...现象说明...
  - 建议: 改用 HTTPS；...

## 中危 (3)
...
```

---

## 7. FAQ

**Q：为什么什么都没检测出来？**
A：可能是这次抓的流量确实规范，也可能是范围太小。试着抓全一个完整功能流程再看。

**Q：会不会误报？**
A：规则基于"字段名 + 值"双重判断，已尽量收敛，但仍可能误报（例如测试环境故意明文）。
请把结果当作**线索**，逐条人工确认。

**Q：它会主动测试这些接口吗？**
A：不会。全程只读本地已抓到的数据，不产生任何新请求。

**Q：能检测出"越权 / 注入"这类漏洞吗？**
A：不能——那需要主动发送构造请求，属于授权渗透测试的范畴，本工具不做。
