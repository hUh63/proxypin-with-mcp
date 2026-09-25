# 安全自检（Security Self-Audit）

> 对**已经抓到的**流量做安全基线核查，把常见隐患按风险等级列出来，可导出报告、交给 AI 解读。
> 默认是**纯被动**的；另有两个可选动作（主动核验、AI 分析），都需要你显式触发。
> 入口：工具箱 → **安全自检**。

---

## 1. 它能做什么 / 不做什么

### 能做的（被动分析）

- 只读地分析**已抓到的请求 / 响应**，从中识别常见的不安全写法；
- 覆盖：明文传输、敏感信息泄露、Cookie 安全属性、安全响应头、服务器指纹、报错泄露、CORS、JWT、协议版本；
- **注入痕迹**：从响应本身读证据——数据库报错被回显（`sql-error-signature`）、请求参数原样回显进 HTML 且未编码（`xss-reflection`）；
- 结果按 **高 / 中 / 低 / 提示** 分级，可筛选、可导出 Markdown 报告。

### 明确不做的（主动攻击）

- 不构造 SQLi / XSS / 命令注入等 payload，不做拖库、不猜测口令、不探测 WAF；
- 没有扫描器、没有载荷投递、没有注入探测、没有爆破、没有绕过；
- 不做任何"自动利用"。

默认**不发送任何请求**。唯一的主动动作是下一节的「主动核验」和「AI 分析」，
两者都要你主动点击、并且会先弹确认。

> 注入痕迹这一项要特别说明：**它是"看痕迹"，不是"打漏洞"**。
> 判定依据全部来自响应里**已经存在**的内容（数据库报错语句、未编码的回显），请求侧一个字节都不会被改动。
> 所以它能告诉你"这个接口把 SQL 错误吐出来了"，但不能替你确认"这个参数可以被注入"——
> 后者需要书面授权下的主动测试。同一条痕迹，在有授权的测试里是线索，在没有授权时只是噪音。

### 可选的主动动作（都要你显式触发）

**主动核验** —— 对**已经在抓包里出现过的**域名各发一次 GET，核对这几个安全响应头在不在：

| 响应头 | 作用 |
|---|---|
| `Strict-Transport-Security` | HSTS，让浏览器以后只用 HTTPS 访问 |
| `Content-Security-Policy` | CSP，限制页面能加载执行哪些资源 |
| `X-Content-Type-Options` | 禁止浏览器自行猜测 Content-Type |
| `X-Frame-Options` | 防止页面被别的站点嵌套（点击劫持） |
| `Referrer-Policy` | 控制 Referer 带出去多少信息 |

护栏：只限已抓到的域名、每个域名**只发一次**、串行 + 间隔 500ms、上限 50 个、开始前显式确认。
不扫端口、不试协议、不投载荷。证书不校验（只看响应头，不想因为自签证书拿不到结果）。

**AI 分析** —— 把问题清单（**不含响应体原文**，敏感值已脱敏）交给 AI，拿回一句话总结、
最值得先处理的点和修复建议。若 AI 建议调整 ProxyPin 自身设置，只能从一份白名单里挑
（SSL 抓包 / 系统代理 / 防缓存 / MCP 局域网 / MCP 鉴权），**应用前一律再确认一次** ——
不做静默改配置。AI 回复解析不了就降级成原文展示，不猜。

> 为什么要主动：被动审计只能看你已抓到的那几条流量。如果当时抓的是一个 API 响应，
> 可能压根没带首页的响应头 —— 重发一次能把这块补上。

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
| `sql-error-signature` | 高 | 响应体出现数据库报错特征（MySQL / PostgreSQL / SQL Server / Oracle / SQLite / 通用 SQLSTATE） |
| `xss-reflection` | 中 | HTML 响应原样回显了带 `<` `>` `"` `'` 的请求参数（query 或表单值，长度 4~256），**未做 HTML 编码** |

判定原则：**字段名 + 值双重判断**（例如先看是否有 `"phone"` 字段、再看值是否像手机号），
尽量避免把普通数字误报成 PII。

注入痕迹两条的判定要点：

- `sql-error-signature`：只在**响应体**里找数据库报错语句的固定特征。命中即说明"该接口把 SQL 错误回显给了调用方"；
  它不关心请求参数长什么样，也不需要参数可注入——所以它是**证据**，不是**结论**。
- `xss-reflection`：要同时满足三点才判定为反射痕迹，缺一不报：
  1. 响应 `Content-Type` 是 HTML（回显在 JSON / JS 里不算 XSS 上下文，直接跳过）；
  2. 请求侧存在**自带 HTML 元字符**的参数值（`<` `>` `"` `'` 至少一个，长度 4~256）；
  3. 该值在响应里**逐字原样出现**——已经被 `&lt;` 转义的不算命中，这是最主要的误报闸门。

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
- 匹配依旧是**只读**的——自定义规则同样不发送任何请求；
- **导入 / 导出**：对话框底部可把全部规则导出为 `security-rules.json`（含 `type` / `version` 标识）；
  导入时按「名称 + 范围 + 表达式」判重，重复的自动跳过——便于团队统一检测口径或跨设备迁移。

**示例**：

- 名称「内部调试标记」，范围「全部内容」，方式「关键词」，表达式 `debug_internal`，等级「中」；
- 名称「疑似身份证」，范围「响应体」，方式「正则」，表达式 `\d{17}[\dXx]`，等级「高」。

---

## 4. 实现细节（开发）

### 4.1 分析器

文件：`lib/network/util/security_audit.dart`

- `SecuritySeverity` —— 四级枚举，`weight` 用于排序；
- `SecurityIssue` —— 单条风险（规则代号 / 等级 / 标题 / 现象 / 建议 / 方法 / URL / 请求 ID）；
- `SecurityAuditReport` —— 汇总（`issues` + `scannedRequests` + `count(severity)` + `byCategory`）；
- `SecurityAuditor.audit(List<HttpRequest>, {customRules, onlyCategories})` —— 逐请求跑规则，产出报告；
- `SecurityAuditor.categoryOf(rule)` —— 规则代号 → 分类（`transport` / `headers` / `credentials` / `sqli` / `xss` / `disclosure` / `privacy` / `custom`），供按类别筛选与统计。

注入痕迹的两条实现集中在 `// ===== 注入痕迹检测 =====` 段：`_sqlErrorSignatures`（6 组数据库报错正则）
与 `_detectXssReflection(...)`（HTML 上下文 + 元字符候选值 + 逐字回显判定）。两者都只接受字符串输入，
不接触任何网络调用——这也是它们无法"升级"成主动扫描的结构性原因。

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
A：默认不会 —— 打开页面就是纯被动的。只有你点「主动核验」时才会发请求，而且范围只限已抓到的域名、每个域名只发一次、发之前还要确认。

**Q：能检测出"越权 / 注入"这类漏洞吗？**
A：分两半说——**痕迹能看，漏洞不能验**：

- 能看：响应里回显了数据库报错（`sql-error-signature`）、参数被未编码地回显进 HTML（`xss-reflection`）；
- 不能做：往参数里塞 payload 去验证"到底能不能注入"，以及越权访问他人数据——那需要主动发送构造请求，属于授权渗透测试的范畴，本工具不做。

换句话说，自检给出的是**值得优先复核的接口清单**，不是"已确认漏洞"的判定书。

**Q：`sql-error-signature` 报出来了，是不是说明我的接口有 SQL 注入？**
A：不直接等于。它说明的是"这个接口把数据库错误回显给了调用方"，这本身既是信息泄露、也是注入的**常见伴生现象**。
要不要按注入处理，取决于触发这条错误的参数是否可由外部控制——请结合该接口的参数一起判断。
无论结论如何，两件事都值得立刻做：改成参数化查询、关掉生产环境的详细报错。

**Q：MCP 里怎么只查注入类的风险？**
A：`get_security_audit` 支持 `category` 参数（逗号分隔），例如 `category: "sqli,xss"` 只看注入痕迹；
不传则返回全部类别。返回里同时带 `by_category` 计数，便于一眼看风险分布。
