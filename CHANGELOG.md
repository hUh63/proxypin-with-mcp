# Changelog

## v1.24.35 (2026-09-26)

### 修复 v1.24.34 的 CI 失败 + 补齐 waf_page 漏网文案

**修复**：v1.24.34 的 `flutter pub get` 报 `ICU Syntax Error`，构建全挂。原因是我把
`{{PAYLOAD}}` 原样写进了 arb —— arb 的值走 ICU MessageFormat，`{` 是占位符语法，
`{{` 直接解析失败（报 `Expected "identifier" but found "{"`）。

- `wafNeedPlaceholder` / `wafStep3Hint` 改成**参数化**：arb 里写 `{mark}`，代码传 `'{{PAYLOAD}}'`；
- `wafTargetUrl` 干脆去掉花括号字样（占位符说明在 `wafStep3Hint` 与输入框 hint 里已有）。

**顺带补上 v1.24.34 漏掉的 20 处**：上一版我靠 `grep` 找中文字面量，结果**漏报**了
`waf_page.dart` 里 20 处（比对/生成/停止/高级设置/请求间隔/清空结果/复制载荷…）。
这次改用逐字符扫描（`_zhscan.py`）重新过了一遍，`waf_page.dart` 现在代码内中文 **0 处**。

> 工具链也补齐了：`_arbcheck.py`（查 arb 裸花括号 / 未声明占位符）、
> `_zhscan.py`（精确列中文字面量，替代不可靠的 grep）。


## v1.24.34 (2026-09-26)

### 国际化（l10n）第二批：WAF 页 + 使用文档中心

延续 v1.24.33 的机制，这一版清掉两个纯 UI 文件：

- **`waf_page.dart`**（24 个 key，前缀 `waf*`）：全部 25 处 toast / 标题 / 提示 /
  免责声明 / 分批按钮。含插值的几条改成带占位符的 arb 条目
  （`wafDoneAll(total, bypass)`、`wafNextBatch(remaining)`、`wafLimitsHard(min, max)` 等），
  不再手工拼字符串；
- **`guide_center.dart`**（14 个 key，前缀 `guide*`）：AppBar 标题、标记说明弹窗、
  复制/重置/知道了/示例 按钮、渲染降级提示、加载更多等。

**刻意不做**：`guide_center.dart` 里那 27 个 `GuideDoc('id', '中文标题', ...)` 标题
**不提取** —— 它们对应的 `docs/*.md` 只有中文版，把标题翻译了、点进去还是中文，
反而更割裂。等文档有英文版时再一起处理。

两文件现在都不含任何硬编码中文（`guide_center` 仅剩文档标题与注释）。


## v1.24.33 (2026-09-26)

### 国际化（l10n）第一批：安全自检 AI 分析对话框

把 fork 后绕过 l10n 的硬编码中文提取进 arb，这一版先拿
`security_ai_dialog.dart` 做**机制打样** —— 它一次覆盖了 toast / Text / 按钮 /
无 context 的静态方法 / 带参数插值 各种形态，验证通过后按 C→B→A 铺开。

- **新增 21 个 key**（前缀 `securityAi*`）：对话框标题、未配置提示、原始回复回退、
  5 个配置动作名、开关态、应用确认（带 `key` / `value` / `reason` 三个占位符）等；
- `SecurityAiDialog.labelOf` 增加 `BuildContext` 参数 —— 原签名拿不到 l10n；
- **AI prompt 保持中文、刻意不提取**：它是发给模型的指令，不是用户可见文案；
- en / zh 双写；zh_Hant 自动继承简体；es / id / pt / th / vi 缺失 key 按 gen-l10n
  惯例用英文兜底（后续单独补翻译）。


## v1.24.32 (2026-09-26)

### 文档：「功能技巧」补齐新能力，并修掉一处自相矛盾（纯文档，无代码改动）

`docs/features_tips.md` 是按版本累积的功能速查，有几处还停在旧状态：

- **修矛盾**：「黄鸟魔改包分析结论」里写着「明确不借鉴 **WAF 探测与绕过**」，
  但 v1.24.23 起工具箱已经上了「WAF 变异」。补上这条**唯一的例外及其硬边界**
  （不内置载荷字典、不爆破 / 不组合搜索、不并发、不自动利用、不反溯源；
  间隔 ≥100ms、总量 ≤2000 条封死；每次探测必须显式勾选授权）——
  避免读者以为两份文档对不上。
- **安全自检**：标题去掉「被动」；「不发送任何请求」改为「**默认**不发送」，
  并补上 v1.24.30 的两个可选动作（主动核验、AI 分析）及各自护栏。
- **手动 Fuzz**：补字典（内置 22 条边界值种子 + 导入 / JS 脚本）、补自动判定规则
  （5 条，填参数才生效）；边界措辞改为「不提供成套攻击载荷库」。


## v1.24.31 (2026-09-26)

### 文档：补齐 Fuzz 与 WAF 指南（纯文档，无代码改动）

v1.24.27 ~ v1.24.29 给 Fuzz 加了字典和判定规则、给 WAF 探测加了分批与高级设置，
但两份指南还停在旧版本。这次补上：

**`docs/fuzzer_guide.md`**

- 新增「取值从哪来：字典」—— 内置 22 条边界值种子（只读）、手填 / 导入 `.txt`·`.csv`、
  JS 脚本生成（结果数组赋给全局 `result`，本地引擎执行不联网）；
- 新增「自动判定：与基线比什么」—— 5 条规则（默认只开「请求失败」）+ 各自的阈值参数 + 命中标签；
- 「结果怎么读」补命中标签说明；实现细节补 `FuzzDictionary` / `FuzzAnomaly`；
- FAQ 补两条：「字典里是不是藏了攻击载荷」「规则标红了是不是就有漏洞」；
- 定位表、「与其他功能联动」同步更新。

**`docs/waf_guide.md`**

- 新增「分批探测」—— 队列化、一次一批、**基线只发一次**、手动「继续下一批（剩 N）」；
- 新增「高级设置」—— 间隔（100~5000ms）/ 超时（3~60s）/ 单次上限（10~2000 条）的范围，
  以及两条**改不动的硬底线**（间隔 ≥ 100ms、总量 ≤ 2000 条）；
- 边界小节与 FAQ 同步更新。


## v1.24.30 (2026-09-26)

### 新增：安全自检的 AI 分析

自检页新增「AI 分析」：把问题清单（**不含响应体原文**，敏感值已脱敏）交给 AI，
拿回一句话总结 + 最值得先处理的点 + 修复建议。

- AI 若建议调整 ProxyPin 自身设置，只能从一份白名单里挑（SSL 抓包 / 系统代理 / 防缓存 /
  MCP 局域网 / MCP 鉴权）；
- **应用前一律再确认一次**，不做静默改配置；
- AI 回复解析不了就降级成原文展示，不猜。

### 新增：安全自检的「主动核验」

被动审计只能看你已经抓到的那几条流量 —— 如果当时抓的是一个 API 响应，可能压根没带首页的响应头。
「主动核验」补这块：对**已经在抓包里出现过的**域名各发一次 GET，核对 5 个安全响应头在不在
（HSTS / CSP / X-Content-Type-Options / X-Frame-Options / Referrer-Policy）。

护栏：范围只限已抓到的域名、每个域名**只发一次**、串行 + 500ms 间隔、上限 50 个、
开始前必须显式确认。不扫端口、不试协议、不投载荷。

> 定位仍是「配置基线核查」，不是漏洞扫描器：缺了某个头不等于有漏洞，输出只说「缺 X」。

### 变更：安全自检不再是严格只读

自检页原来的定位是「只分析、不发任何请求」。现在增加了两个可选的主动动作
（主动核验、AI 分析），都需要用户显式触发 —— **默认打开页面时仍然是纯被动的**。
`docs/security_audit_guide.md` 已同步说明新的边界。


## v1.24.29 (2026-09-26)

### 新增：手动 Fuzz 支持字典（可导入 / 可脚本生成）

注入项的取值不再只能手敲：

- **内置一组「边界值 / 类型异常」种子**（空值、超长、`null`、`1'`、`../` 等 22 条）——
  用来观察后端怎么处理异常输入，**不是**攻击载荷库；
- **从文件导入**：`.txt` / `.csv` 按行读（`#` 开头为注释）；`.js` 按脚本读；
- **脚本字典**：一段 JS，把结果数组赋给 `result` 即可，例如
  `result = Array.from({length: 8}, (_, i) => 'x'.repeat(i + 1));`，
  产物与静态取值合并去重；编辑器里有「试跑」按钮可以先看展开结果；
- 字典可命名保存、随时复用；注入项上直接显示当前取值条数。

> 工具**不预置攻击载荷库**。取值由你填、导入或算出来 —— 这样它是个通用的取值发生器，
> 而不是拿来就能打别人站的成套字典。

### 新增：Fuzz 自动与基线比对 + 可配规则

每条变体会自动和基线比一遍，命中规则的结果行会亮出标签：

| 规则 | 比什么 | 参数 |
|---|---|---|
| 请求失败 | 连不上 / 超时 / 被中断 | —（默认启用） |
| 状态码变化 | 与基线的状态码不同 | — |
| 长度明显变化 | 响应体长度差超过阈值 | 百分比（默认 20） |
| 响应明显变慢 | 比基线慢超过阈值 | 毫秒（默认 500） |
| 命中关键字 | 响应体出现指定关键字 | 关键字 |

除「请求失败」外默认关闭，由你按需打开并填参数，配置会保存。
规则只标「和基线不一样」，**不代表这里就有漏洞** —— 结论仍然由你下。


## v1.24.28 (2026-09-26)

### 改进：WAF 探测改分批（队列化）

③ 主动探测不再「一口气发完」，改为**一批一批发**：

- 每批发 `单次上限`（默认 200）条，发完即停，按钮变成「继续下一批（剩 N）」——
  **要不要继续始终由你决定**，不会闷头发完；
- 基线只在第一批发一次，后续批次沿用同一条基线做对照，不重复发；
- 「停止」随时可用：停下后队列保留，想继续点「继续下一批」接着发；
- 没有会产生变化的载荷时不再空跑整轮。

条目多时（比如把整套字典喂进来）不会再变成一个无法中断的长任务。


## v1.24.27 (2026-09-26)

### 新增：WAF 探测高级设置

「WAF 变异」③ 主动探测增加「高级设置」（改动会持久化保存）：

- **请求间隔**：默认 300ms，可调，下限 **100ms**；
- **单条超时**：默认 15s，可调 3–60s；
- **单次上限**：默认 200 条，可调，硬顶 **2000 条**。

后两条是刻意保留的硬边界：间隔下限和总量硬顶不可突破 —— 再往下就不是「探测」而是对目标的流量冲击了。

### 优化：①② 与 ③ 的联动可见化

③ 实时显示「本次将探测（由 ①② 决定）：…」。① 识别出 WAF 后套用的推荐组合、② 勾选的技术，
都会立刻反映到这行 —— 不用再猜这次到底会发哪些请求出去。

### 修复：打开「更新日志」卡顿

「使用文档 → 更新日志」要渲染 194KB / 112 个版本。此前是把整个文档构建成几千个 Widget
塞进一个 `Column`（无虚拟化），首帧明显卡顿。改为**分页渲染**：先渲染前 50 个块，
底部「加载更多（已显示 N / M 段）」按需追加。

### 文档：云端协同服务端补齐两种部署场景

`docs/cloud_server_guide.md` 的「四、部署」补上**内网机器**与**云主机**的差异（附对照表）：

- **4.1 内网**：监听 `0.0.0.0`、放行 8788、静态 IP / mDNS 的坑，以及「内网也是明文」的提醒；
- **4.2 云主机**：只听 `127.0.0.1` + Nginx 反代 + Let's Encrypt，**特别标注 WebSocket 升级那两行**
  —— 漏了之后注册登录上传都正常，只有「实时协同」连不上，极易误判成服务端故障；
- **4.3 两套并存**：手动切地址 / SSH 反向隧道 / Tailscale 三种做法，以及「两边数据不会自动同步」；
- 「五、安全」补第 6 条：内网不等于安全，`SECRET` 无论哪种部署都必须改。


## v1.24.25 (2026-09-25)

### 重构：`mcp_server.dart` 拆分

`lib/network/mcp/mcp_server.dart` 长期 5000+ 行，其中工具定义表就占 1200 余行
（90 多个工具的完整 JSON Schema）。把它拆到 `lib/network/mcp/mcp_tools_defs.dart`：

- 用 Dart 的 `part` / `part of`：两个文件同属一个 library，私有成员照常互相可见，无需改 import；
- **只把纯静态的工具定义**抽成 part 里的顶层函数 `_nativeToolsJson()`，主文件保留类方法
  `_buildToolsList()` —— 它还要拼 `..._officialToolsJson()` 这类实例方法，而 part 不能续接类体；
- 主文件 5042 → 3844 行，工具定义单独成文件，之后改工具不必再在 5000 行里翻找。


## v1.24.24 (2026-09-25)

### 修复：移动端与桌面端剩余破坏性操作补二次确认

延续 v1.24.23，把「长按菜单 / 行内按钮的单条删除」普遍缺确认的问题补齐：

移动端：收藏、抓包请求、搜索历史、Hosts、域名黑白名单、应用白名单、应用黑名单、脚本、
请求屏蔽、请求映射、请求重写、解密规则、剪贴板导入配置、移除系统证书、卸载直挂证书、
远程设备侧滑删除、域名白名单移除，以及 MCP 自动化的 Root / 规则 / 工作流 / 事件监听器 / 定时任务。

桌面端：导入配置（覆盖）、AI 对话删除（与同页「清除当前对话」对齐）。

风险最高的几处单独说明：移除系统证书与卸载直挂会直接让 HTTPS 抓包失效；
导入配置（文件 / 剪贴板）会覆盖当前全部配置；删除云端副本不可恢复。

### 优化

- `print` 改走 logger：`EventBus` 事件处理器异常、`RustLib.init` 失败不再只打到 stdout。
- 原生通道补超时兜底：`mcp_screen.dart` 15 处、`native_method.dart` 4 处
  —— 原生因异常或未授权不回 result 时，`await invokeMethod` 原本会永久挂起。

### 已核查、无需改动

- 空 `catch (_) {}` 共 53 处，逐一抽样核查后确认均为刻意的静默忽略
  （探测文件是否存在、关闭连接、可选解析路径），加日志只会制造噪音，故保留原样。


## v1.24.23 (2026-09-25)

### 新增：WAF 主动探测

「WAF 变异」页新增会真发请求的③主动探测：先发一条基线（原始载荷），再逐条发勾选的变异载荷
（串行、每条间隔 300ms），与基线比对后判定「疑似绕过 / 被拦截 / 响应有变化 / 请求失败」。

- 注入位置由 `{{PAYLOAD}}` 占位符指定，URL / 请求头 / 请求体都支持，也可多处同时注入；
- 判定口径：状态码命中拦截码（403/406/418/419/429/501/999）或响应体命中拦截特征词即视为被拦；
  与基线状态码一致且长度差在 15% 以内视为「疑似绕过」；
- 护栏：必须先勾选授权；串行发送 + 固定间隔；单次总量上限 200 条；不产生改变的技术不空发；
  不内置载荷字典、不做组合爆破、不自动利用、不做反溯源。疑似绕过只是线索，结论由人下；
- 新增 `docs/waf_guide.md`，并登记进「使用文档」中心。

### 优化

- MCP `tools/list` 结果加缓存：此前每次调用都重建 90+ 条工具的长描述 JSON，现在只构建一次。
- 术语统一：搜索条件的「Client Host」与详情面板的「Client Address」统一为 `Client Address`。

### 修复：桌面端 7 处破坏性操作缺二次确认

同一页面的「多选批量删除」都有确认，但「右键菜单的单条删除」普遍缺失。本次补齐：

- 收藏列表 → 删除收藏
- 历史记录 → 删除单条历史
- 请求列表 → 删除单条请求
- 请求映射 → 删除单条规则
- 断点规则 → 删除（先快照选中项，避免菜单关闭后选中被清空导致删不掉）
- QUIC 连接页 → 清空记录
- 云端协同 → 删除云端副本


## v1.24.22 (2026-09-25)

### 修复：WAF 变异模块编译失败

两处 Dart 类型问题，都属于「一眼看不出、编译器才认得出」：

1. `WafTechnique` 里访问 `_handlers` 不能只写名字——它是 `WafBypass` 的**静态**成员，Dart 会先在当前类里找，找不到就报 `The getter '_handlers' isn't defined for the type 'WafTechnique'`，必须写成 `WafBypass._handlers`。
2. `RegExp` 匹配结果里 `m[0]` 的类型是 `String?`，直接调 `substring` 过不了编译，要先 `m[0]!`。


## v1.24.21 (2026-09-25)

### WAF 载荷变异工具 + 云端页编译修复

**一、WAF 载荷变异**（工具箱 → WAF 变异）

验证「自己的 WAF 规则够不够」时，需要看到一条载荷的**等价写法**——WAF 靠正则匹配加规范化拦流量，而很多语法的等价形式没被规则覆盖。

- **15 种变异技术**：URL 编码 / 双重 URL 编码 / Unicode / 大小写混用 / 注释分割 `/**/` / 内联注释 `/*!50000*/` / 空白替换 / 关键字双写 / 等价关键字（`and`→`&&`）/ 引号变形 / 字符串拼接 / 换行注入 / 分块编码 / 参数污染 HPP / Base64 与十六进制包装。
- **WAF 特征比对**：把**已经抓到**的响应头或拦截页片段贴进去，按特征匹配 12 类常见 WAF（Cloudflare / AWS WAF / Akamai / 阿里云 / 腾讯云 / ModSecurity / F5 / Imperva / 安全狗 等），**不主动探测**。
- 识别出 WAF 后点一下即套用针对它的推荐组合；结果逐条可复制。

定位是**本地纯字符串变换**——不发任何请求、不自动探测、不自动利用。变换结果拿去「请求构造 / 重放 / 手动 Fuzz」自己发；请只用于你拥有或已获书面授权的目标。

**二、修复：云端协同页编译失败**

`cloud_page.dart` 里 `error ? Colors.red : null` 的类型是 `MaterialColor?`，而 `FlutterToastr.show` 的 `backgroundColor` 参数不接受 null，导致全平台编译失败、0 产物。改为按状态分两次调用。


## v1.24.20 (2026-09-24)

### 云端托管 + 多人实时协同 + 账号（客户端 + 自部署服务端）

**一、云端协同**（工具箱 → 云端协同）

- **账号**：注册 / 登录 / 登出，token 本地持久化；密码在服务端加盐哈希，不存明文。
- **云端托管**：工作区（标准 HAR）存服务端，带 `rev` 版本号做乐观并发控制——两个人同时改同一份时服务端返回 **409**，客户端提示先拉最新的再推。
- **多人实时协同**：WebSocket 长连接。别人的 `workspace.created/updated/deleted` 与在线成员变化**实时**推过来；断线按指数退避自动重连（1s→60s 封顶），25s 心跳保活；事件**不回给发起者自己**，避免自己刚写完又被自己刷一遍。
- **团队**：成员之间共享同一批工作区，成员列表带在线状态，支持按用户名邀请。

**二、服务端（自部署）**

`docs/cloud_server_guide.md` 里是**可直接运行的 Node.js 实现**（唯一依赖 `ws`）：账号、工作区 CRUD、团队、WebSocket 广播、原子写盘都有，附 systemd / Docker 部署样例与安全清单。客户端只依赖这套 REST + WS 契约，**不绑定任何特定托管商**——本仓库不托管云服务。

**三、修复：备份功能此前实际上是「死」的**

顺着「检查备份有没有完善」查下去，发现四处问题，一处比一处严重：

1. **自动备份从未触发** —— `autoBackupConfig()` 有实现、有开关，全仓**没有任何调用点**。现在启动后按配置的间隔真的会备份（`BackupService.autoBackupNow`）。
2. **没有创建入口** —— 备份页只有「查看 / 恢复 / 导出 / 删除」，**没有「立即备份」**。补上之后，配合第 1 条，备份列表才终于会有内容。
3. **恢复会丢一半配置** —— 移动端恢复是**手工逐字段复制**，`Configuration` 40+ 个字段只搬了 18 个，MCP 局域网 / 保活 / AI / QUIC 拦截这些全被丢掉。现在 `applyJson` 与 `fromJson` **共用同一份赋值**，以后新增字段不会再漏。
4. **桌面端恢复等于没做** —— 它把 `importConfig` 的返回值直接丢掉（那只是构造一个新对象、不改单例），却还提示「备份已恢复」。

备份内容也从「只有配置」扩展到 **配置 + 证书 + 脚本 + 各管理器持久化数据 + 工作区**（不备历史抓包流水：体积太大，且历史本身有独立导出）。打包用「单个 JSON + base64」而非 zip——没有编解码 API 变动的风险，文件本身还自描述；恢复时对路径做**目录穿越校验**，避免被篡改的备份写到数据目录之外。


## v1.24.19 (2026-09-24)

### 修复：v1.24.18 编译失败（Dart 字符串里的 shell 命令替换）

`lib/network/util/pinning_helper.dart` 把 shell 的命令替换 `$(tail ...)` 直接写进了 Dart 字符串。`$` 后跟 `(` 在 Dart 里非法——**必须**是标识符或 `{}`——于是全平台编译失败、0 产物。改成 `\$(...)`（转义成字面 `$`）后能正常输出给 shell。

顺带把这条陷阱固化进自检：现在会扫描非 raw 字符串里所有「`$` + 非标识符」的写法（放过合法的 `\$` 转义与 raw string），推送前就能拦住。


## v1.24.18 (2026-09-24)

### 工作区（本地 + 自定义服务端）· SSL Pinning 绕过辅助 · 多机来源标识

**一、工作区**（工具箱 → 工作区）

按项目/环境把抓包数据分开归档，不再全部堆在一个列表里。

- **本地工作区**：新建 / 重命名 / 删除；「保存当前抓包」把当前列表整体存进工作区；「导入到历史」读回来在历史记录里翻。数据落盘是**标准 HAR**（`workspaces/<id>/data.har`），可以直接拿去别的工具看。
- **自定义服务端**：填一个地址 + token，就能把工作区推到自己服务器、从服务器拉回来。契约只有 5 个接口，`docs/workspace_guide.md` 里附了**零依赖 Node.js 参考实现**。客户端直连服务端，不经过本工具代理端口。
- 不配服务端也能完整使用本地工作区——它是可选的。

**二、SSL Pinning 绕过辅助**（工具箱 → SSL Pinning）

此前只能**诊断**「疑似证书固定」，现在补上干预手段：

- 探测设备上的 frida 环境（root / frida-server / frida CLI / frida-inject），缺什么一眼看出；
- **生成** hook 脚本，覆盖 Conscrypt `TrustManagerImpl`、`SSLContext.init`、OkHttp `CertificatePinner`、`HostnameVerifier` 等常见实现；
- 设备上已有 frida-inject（或 frida CLI）时**一键注入**，支持 spawn 模式应对「启动即校验」，注入日志页内可查；没有也能生成脚本拿到电脑端用。

仍然**不打包任何第三方二进制**（frida-server、Xposed 模块都不带），也仍然只应在自己拥有的设备、对有授权的目标使用。

**三、多机镜像：来源设备可见可筛**

多台设备把代理指向同一台 ProxyPin 时，请求详情新增 **Client Address**；搜索范围新增 **Client Host**，输入设备 IP 就能只看那一台的流量——按设备筛完正好归档到对应的工作区。


## v1.24.17 (2026-09-24)

### gRPC over HTTP/2 解帧 + 无 Magisk 设备的系统信任库「root 直挂」

**一、gRPC 解帧（新增）**

此前抓包列表里 gRPC 请求只看得到 `:path` 和状态码，body 是一团二进制。现在把语义层补上：

- **长度前缀分帧**：gRPC 消息体是「1 字节压缩标志 + 4 字节大端长度 + payload」的重复拼接，一个 DATA 帧里可能挤着好几条消息。解码器逐条拆开；长度前缀截断时**不猜**，不产出半条消息。
- **protobuf 盲解**：没有 `.proto` 也能读出字段号、wire type 与值。length-delimited 字段按「可打印文本 → 嵌套消息 → 原始字节」三态判定，嵌套消息递归展开（深度上限 6）；判定嵌套时会**复算一遍长度**确认恰好走完，避免把二进制误认成消息。
- **trailer 与状态**：从 HTTP/2 trailers 取 `grpc-status` / `grpc-message`，状态码翻成 `OK` / `NOT_FOUND` / `UNAVAILABLE` 这类名词。
- 请求详情多一个 **gRPC 页签**（仅当 content-type 是 `application/grpc*` 时出现），字段树直接展开看。
- MCP 新增 **`decode_grpc` 工具**（工具数 92 → **93**）：传 hex/base64 body + content-type + trailers，AI 在分析抓包时就能直接解出服务方法、字段与失败原因。

**二、系统信任库「root 直挂」（新增，补现有方案的缺口）**

证书页原先那个「一键自动安装到系统」走的是 **Magisk 模块**（`/data/adb/modules/proxypin_ca` + `post-fs-data.sh`），前提是设备装了 Magisk / KernelSU / APatch——没有模块管理器的机器只会拿到「未检测到」然后失败。

现在补上另一条路：**用 root 运行时直挂**。

- 做法：把系统信任库目录整个复制出来 → 追加本工具的 CA（文件名按 OpenSSL `X509_NAME_hash`，算错名字系统就不认这张证书）→ **tmpfs 覆盖挂载** → 清点文件数校验。
- 特点：**不写任何持久分区**（完全可逆）、**不必重启设备**（重启目标应用即生效，也可点「重启 zygote」让所有应用立刻感知）；代价是重启后失效，需要时重新挂载。
- 安全：铺回目标目录后清点一次，少于「原有 + 1」立即 `umount` 回滚；任何一步失败都回滚，绝不把设备留在信任库残缺的状态（那会让全部 HTTPS 失败）。
- 配套「卸载直挂」，摘掉覆盖挂载后系统原有信任库原封不动。


## v1.24.16 (2026-09-24)

### 修复：位运算页一按「计算」就报类型转换错误

真机反馈：工具箱 → 计算器 → 位运算，填 `0xF0F0` 与 `0x0FF0` 后计算，报

```
bitwise failed: type 'String' is not a subtype of type 'num?' in type cast
```

根因是引擎里的 `args['b'] as num?`——工具箱输入框传进来的是文本（String），`as` 转换失败会**直接抛异常**（不是返回 null）。更糟的是这一行写在 `switch` 之前**无条件执行**，所以连 `and`/`or`/`xor` 这种根本用不到位移量的运算也会撞上去。

修复：

1. 新增 `_intOf()` 宽松取整，兼容 int / double / 十进制与 `0x`、`0b`、`0o` 文本；`_widthOf`、`_endianSwap` 的同类强转一并换掉，引擎内不再对入参做 `as` 强转。
2. 位移量改为**惰性求值**（`_shiftOf`），只在 shl/shr/sar/rol/ror 分支解析，并对负数与超过 4096 的位移给出明确报错。
3. 位运算页把「操作数 B / 位移量」的语义拆开：位移类运算按**十进制**传 `shift`（此前填 `0x0FF0` 会被当成位移 4080 位），标签与提示跟随运算类型切换。

这类错误**编译器查不出来**——能编译通过、CI 全绿，只有真正运行才暴露。因此补了一个回归自检脚本，覆盖「UI 传文本」与「MCP 传数字」两种入参形态共 47 个用例，外加 CRC / 补码 / 移位 / 字节序的标准向量。


## v1.24.15 (2026-09-23)

### 计算器工具箱 + MCP 计算能力 + 批处理

移植 calculate-mcp（MIT）的能力范围，用 Dart 重新实现，**UI 与 MCP 共用同一套引擎**（`lib/network/util/calc_engine.dart`，30 个纯函数运算）。

1. **工具箱新增「计算器」**（五个页签）：进制/补码（任意精度 + 8/16/32/64 位有符号/无符号补码、大端小端 hex、ASCII）、位运算（含逻辑右移 shr 与算术右移 sar 的区别、循环移位 rol/ror）、字节序翻转、IEEE754 浮点机器码拆解、CRC（crc32/crc16-ccitt/crc16-modbus/crc16-xmodem/crc16-ibm）与哈希（md5/sha1/sha256/sha512）。结果每行可点击复制。
2. **编码器补充 Hex 编解码**（原来只有 URL / Base64 / Unicode / MD5）。
3. **MCP 新增 `calculator` 工具**：一个入口覆盖全部 30 个运算，AI 在分析抓包时可直接算补码、校正字节序、验 CRC、做大数运算，不必靠模型自己猜算术。
4. **MCP 新增 `batch` 工具**：在单次调用里按序执行多个工具调用，用 `{"$step": n, "field": "a.b"}` 引用前序结果，减少多步任务的往返开销。默认首错即停，最大 20 步，禁止嵌套 batch。

批处理的两处安全设计：batch 自己占一个并发名额，内部步骤**不再重复申请名额**（否则 N 个并发 batch 会互相等死）；每一步都走与其他入口相同的 `_runTool`，参数校验 / 并发闸 / 超时 / 指标 / 审计一个不少，并可按 `caller: batch` 过滤审计记录。

工具数 90 → **92**（+`calculator`、+`batch`）。新增文档 `docs/calculator_guide.md`。

> 修正：首版编译失败——`num.parse` 的返回类型是 `num`，而 `ByteData.setFloat32/64` 要求 `double`。已改为 `double.parse` 并把局部变量声明为 `double`。


## v1.24.13 (2026-09-23)

### 抓包自检：补上「SSL 证书固定（疑似）」判定

此前自检能查「代理是否运行 / 系统代理是否指向 / CA 装在系统库还是用户库 / 是否有流量进来」，但当**这些全都正常、用户仍然抓不到某个应用的 HTTPS 时，提示就断了** —— 而这恰恰是最常见的一幕。

- 新增判定项 `ssl_pinning`：统计「只建立了 CONNECT 隧道、却没有任何解密后请求」的域名。判据取的是**差集** —— 出现过解密请求的域名即使也建过隧道也不算嫌疑（宁可漏报，不误报）。
- 仅当 CA 证书判定为 ok 时才触发，避免与「证书没装好」混淆。
- 命中时列出具体域名，并说明这类应用**不是"没网络"，而是拒绝了本工具的证书**，所以主动断开。
- 建议项里补上对应处置方向，并附授权边界说明。
- UI 抓包自检页与 MCP 的 `diagnose_capture` 共用同一份结论（后者直接返回 `toJson()`），两处同时生效。

新增文档 `docs/ssl_pinning_guide.md`：把「应用报无网络」拆成第 0 / 1 / 2 层（流量没进来、系统不信任 CA、应用不信任何证书），逐层给出解法与前提条件，并明确本工具只做**诊断与说明**、不打包任何 hook 模块。


## v1.24.12 (2026-09-23)

### MCP 服务运行时增强

借鉴独立 MCP 内核（LemonKernel）的设计，补齐我们此前缺的四件事，并修掉一个版本声明 bug。

1. **版本单一真源**：`initialize` 此前对外硬编码 `version: '1.3.1'`，而 pubspec 已是 `1.3.2+37` —— 正是 LemonKernel 立项时批评的「版本三处打架」，我们自己也犯了。现统一到 `lib/network/bin/configuration.dart` 的 `appVersion`，关于页与 MCP 同源。
2. **运行指标**：新增 `/healthz`（轻量探活）与 `/metrics`（会话数、SSE 连接、调用量/失败率/超时/被拒、并发水位、工具级耗时）。`get_performance_metrics` 增加 `mcp` 段，与原有的进程内存/抓包统计并列。
3. **per-tool 超时 + 并发闸**：并发上限 16、队列 64、等待 5 秒，超限**立刻拒绝**而不是排队（避免连接与内存堆积）；每个工具可声明独立超时（设备类 30s、shell 60s、导出 60s、默认 120s）。
4. **工具调用审计**：新增 `get_mcp_audit`，记录调用者/工具/耗时/结果/参数名——**不记录参数值**，避免审计日志变成新的泄露面；内存环形缓冲 500 条，支持按工具与失败过滤。
5. **参数强校验**：按工具声明的 `inputSchema` 校验必填/类型/枚举/区间，失败提前返回 `Invalid arguments`。刻意保守：只校验声明过的参数、string 位置宽容接受数字、null 放行。设置页可关闭（默认开启）。
6. **后台保活**：新增 `keep_alive` 工具与设置页开关，用 adb shell 语义命令集（`deviceidle whitelist` / `appops RUN_*_IN_BACKGROUND` / `am set-inactive`）将应用加入电池优化白名单并解除后台限制；通过 **Shizuku / root / Dhizuku** 三通道执行，`auto` 自动挑选。**不需要 root**：Shizuku 提供的 shell 权限即可。

工具数 88 → **90**（+`keep_alive`、+`get_mcp_audit`）。新增 `lib/network/mcp/mcp_runtime.dart`，把「校验 → 并发闸 → 超时 → 指标 → 审计」收敛为单一入口，HTTP / SSE / stdio / UI 内部调用共用，避免某个入口漏审计。

新增文档 `docs/mcp_runtime_guide.md`。


## v1.24.11 (2026-09-23)

### 安全自检补齐注入痕迹识别（SQLi / XSS，被动）

在原有 15 条规则之上新增 2 条：

- `sql-error-signature`（高）：响应体出现数据库报错特征，覆盖 MySQL / PostgreSQL / SQL Server / Oracle / SQLite / 通用 SQLSTATE 六组指纹。命中说明该接口把 SQL 错误回显给了调用方。
- `xss-reflection`（中）：HTML 响应里**逐字原样**回显了带 HTML 元字符的请求参数（query / 表单值，长度 4~256），且未做 HTML 实体编码。

**形态依旧完全被动**：只读分析已抓流量，不发送任何请求、不构造 payload、不做注入探测。这两条读的是"响应里已经存在的证据"，不是"能不能打进去"——边界与原有规则一致。

`xss-reflection` 用三重闸门控制误报，缺一不报：① 响应 Content-Type 是 HTML（回显在 JSON/JS 里不算 XSS 上下文）；② 请求侧存在自带 `<` `>` `"` `'` 的参数值；③ 该值在响应里逐字出现（已被 `&lt;` 转义的不算命中）。

配套改动：

- `SecurityAuditor` 引入风险分类 `transport / headers / credentials / sqli / xss / disclosure / privacy / custom`，新增 `categoryOf(rule)` 与报告级 `byCategory` 统计；`audit(...)` 支持 `onlyCategories` 过滤。
- MCP `get_security_audit` 新增 `category` 参数（逗号分隔，例如 `sqli,xss`），返回新增 `by_category` 计数，每条 issue 带 `category` 字段。工具数不变（仍为 88）。
- `docs/security_audit_guide.md` 同步：规则表、判定要点、实现说明、FAQ（新增"报了 SQL 报错是不是就等于有注入"一问答）。


## v1.24.10 (2026-09-23)

### 修复：点「允许局域网访问」后 MCP 服务显示未运行

**根因**：`McpServer.restart()` 直接调用了默认参数下的 `stop()`，而 `stop()` 会把 `mcpEnabled = false` 写回配置；紧接着 `start()` 开头的启用检查读到 false 就直接 `return`，服务再也不启动。表现为点一下开关 MCP 就"停了"，而且配置被永久写坏——重启应用也不会自动拉起，且无法从表象看出是被写坏的。

**修复**：
- `restart()` 改为 `stop(persistState: false)` + `start(force: true)`：重启属于运行期配置变更，不应改写"用户是否启用"这个持久状态；`force` 同时让它能自愈此前已被写坏的配置。
- `start()` 新增可选参数 `force`（默认 false），仅用于用户显式操作，自动拉起等其它调用点行为不变。
- 设置页「允许局域网访问」开关改为**开、关都触发重启**（此前只在开启时重启，导致关闭后服务仍在 `0.0.0.0` 上监听，属于安全问题），并补上 `isRunning` 守卫，避免服务未运行时被这个开关意外拉起。桌面端与移动端同步修正。


## v1.24.9 (2026-09-23)

### MCP 工具描述统一

- **统一为「功能 + Call this when 场景」句式**：88 个对外工具全部补齐「何时调用」说明，让模型能凭描述自行判断该调用哪个工具，而不是靠猜名字。
  - 自有 49 个工具重写为「一句功能 + Call this when …」，并按 76 列折行、与上游保持一致的排版（单行原文也统一为多行）。
  - 官方 34 个工具（含 2 个对外隐藏的）在原有详尽说明之后追加「何时调用」句，参数说明与语义一字未改。
- **静态自检升级**：描述提取器改为支持 Dart 隐式字符串拼接（相邻字面量），修掉此前把多行描述只取首段造成的 **7 处假阳性**；并把官方工具描述纳入检查。当前报告：自有 58 + 官方 30 = 88 个工具，暴露工具的「何时调用」覆盖率 **100%**。
- 顺带修掉 2 处过短描述（`stop_proxy`、`get_scripts`），改为交代用途与调用时机。


## v1.24.8 (2026-09-23)

### MCP 收口

- **入口合一**：桌面设置页只保留一个 MCP 入口（原「MCP 连接」与「MCP 服务」两项合并），客户端接入向导
  （Claude Code / Codex / Cursor 一键注册）改由该页右上角按钮进入；移动端删除重复的独立设置页
  （`MobileMcpSetting`），统一到 `McpConnectionPage`，并把访问令牌管理与客户端接入命令并入其中。
- **访问令牌开关**：新增 `mcpAuthEnabled`（默认开启）。关闭后局域网无鉴权，UI 以红字警示
  「同一网络内任何设备都可读取抓包内容」；桌面与移动设置页均可切换，切换时自动重启服务。
- **setup_script 完善**：在原有 shell / PowerShell 一键脚本之外，新增 `writeLocalConfig()`——可在本机直接
  写入 Claude Code / Cursor / Codex 的 MCP 配置（合并写入、保留既有字段、写前备份为 `.bak`）。
- **工具精简 102 → 88**：退役 10 个与官方重叠的自有工具（`add_host_mapping`、`add_request_rewrite`、
  `add_response_rewrite`、`add_breakpoint_rule`、`list_breakpoint_rules`、`remove_breakpoint_rule`、
  `block_url`、`calculate_entropy`、`analyze_auth`、`traffic_summary`），隐藏 2 个语义重复的官方工具
  （`clear_session` ≡ `clear_requests`、`replay_flow` ≡ `replay_request`）；对应实现与 UI 中文描述表一并清理。
  同名工具（`generate_code`、`update_script`）仍以自有实现为准。
- **工具表静态自检**：新增自检脚本，覆盖「定义 ↔ 实现」双向一致、重名、命名规范、描述与 schema 完整性、
  协议方法齐备（initialize / ping / tools/list / tools/call）。当前 88 个工具（自有 58 + 官方 30）全部通过。

## v1.24.7 (2026-09-23)

### 修复

- `get_ssl_proxying_list`：`HostFilter` 的白 / 黑名单是 `List<RegExp>`，改为输出正则文本，修正类型错误

## v1.24.6 (2026-09-23)

### 修复

- `mcp_server.dart`：补 `HostFilter` / `McpSetupScript` 的 import（SSL 名单工具与一键配置脚本需要）
- `ui/configuration.dart`：补 network 层 `Configuration` 的 import（MCP 配置转发需要）
- `mobile/setting/mcp.dart`：清掉最后一处 `McpService.instance.port` 残留，`get_client_setup` 去掉无用辅助函数
- 补回 `/mcp/setup.sh` 与 `/mcp/setup.ps1` 端点：上游服务层删除后被漏掉，而移动端设置页的一键配置命令仍在调用

## v1.24.5 (2026-09-23)

### 两套 MCP 合流为一套

以本 fork 自建的 MCP 服务为主体（协议 2026-07-28、Streamable HTTP + SSE、自动化 / 规则引擎 / 调度器、
设备自动化），把上游 v1.3.2 官方 MCP 的能力合并进来，对外只有**一套服务、一张工具表**。

- **工具合流**：官方 32 个工具（规则 CRUD、断点、URL 拦截、Map Local、重定向、改写、Hosts 增删、
  脚本 CRUD 与模板、SSL 代理开关、系统代理、证书状态、重放、构造请求发送、收藏、clear_session、
  toggle_recording）作为「官方工具源」注册进自建 McpServer；同名工具（`generate_code`、`update_script`）
  以本 fork 实现为准。对外工具数 **70 + 32 = 102**。
- **单一服务**：删除上游独立的 `mcp/mcp_service.dart`、`mcp/transport/mcp_http_server.dart`、
  `mcp/protocol/mcp_server.dart`（其 8 个只读工具自有实现已覆盖且更强）；`ToolException` 迁入
  `mcp/protocol/mcp_tool.dart`。桌面与移动端只启动自建 `McpServer`，不再双开。
- **单一配置源**：MCP 配置（端口 / 开关 / 自动启动 / 局域网 / 工具开关 / 脱敏 / token）统一收敛到
  network 层 `Configuration`；UI 层 `AppConfiguration` 的同名字段改为转发，消除「设置页改了、服务读不到」。
- **局域网安全**：新增 Bearer token 鉴权（`mcpAllowLan` 时强制校验，`/health` 放行），token 首次开启自动
  生成并持久化；此前局域网暴露是**无鉴权**的。
- **stdio 桥打通**：自建服务启动时写握手文件、停止时清理，桌面端 `--mcp-stdio` 桥据此发现端口，
  IDE 可以直接本机拉起。
- **工具集扩展**：新增 `get_ssl_proxying_list`（SSL 抓包白 / 黑名单）、`get_tool_catalog`（按能力分组的
  工具目录，便于模型快速定位）、`get_client_setup`（端点 / token 与 Claude Code、Codex、Cursor、curl、
  stdio 的接入命令）。

## v1.24.4 (2026-09-22)

### 构建

- 提交随新依赖解析的 `pubspec.lock`（file_picker 13.x、archive 4.2、logger 2.8 等），并移除 CI 中用于导出 lock 的临时步骤

## v1.24.3 (2026-09-22)

### 构建

- 同步 `pubspec.lock` 至 file_picker 13 / archive 4.2 / logger 2.8 等新依赖解析结果（临时在 CI 中打印后取回提交）

## v1.24.2 (2026-09-22)

### 修复

- 修 `Platforms.saveFileAdaptive` 返回类型引发的调用点不匹配：file_picker 13 的 `saveFile` 返回 `Uri`、
  `getDirectoryPath` 返回路径字符串，这里统一返回文件路径 `String?`，并去掉 11 处调用点多余的 `toFilePath()`
  （`body` / `web_socket` / `favorite` / `history` / `domains` / `request_map` / `request_rewrite` / `script` / `ssl`）

## v1.24.1 (2026-09-22)

### 修复

- 修 v1.24.0 合并上游 v1.3.2 后暴露的编译错误：
  - `desktop.dart` / `mobile.dart`：上游把 `upgradeNoticeV30` 改名 `upgradeNoticeV32`，融合后残留旧判断导致 `Can't find '}'`
  - `request.dart`：`selectedRequestId` 同时残留 ValueNotifier 与旧 static 字段（重复声明）
  - `environment_manager.dart`：上游改用 `resolveBuiltIn` + `$` 前缀体系，删掉本 fork 遗留的私有回落
  - `platform.dart`：`saveFileAdaptive` 返回类型随 file_picker 13（`saveFile` 返回 `Uri`）调整
  - `mcp_server.dart`：`toMap()` 多值头改为返回 List 后，头差异比较统一按字符串归一
  - `ssl.dart`（桌面 / 移动）：删掉 file_picker 迁移后残留的 `result.single` 读取
  - `export_request.dart`：导出目录变量随上游实现（`getDirectoryPath`）改为可变
  - `config_management.dart`（移动）：file_picker 13 已无 `allowMultiple` 参数

## v1.24.0 (2026-09-22)

### 同步上游 v1.3.2（24 commits / 141 文件）

保留本 fork 的全部自研能力，同时吸收上游 v1.3.2 的功能与修复。

**来自上游**

- 内置 MCP 服务（`lib/mcp/**`）：与自建 MCP 并存，共用「MCP 服务」开关，默认关闭
- 环境变量支持内置动态变量：`{{$date}}` `{{$datetime}}` `{{$timestamp}}` `{{$timestampMs}}` `{{$guid}}`/`{{$uuid}}`
  `{{$randomString}}` `{{$randomInt}}`；`$` 前缀保证不会被同名用户变量 shadow
- 请求重写规则支持上移/下移与拖动排序
- 修复 Windows 右键菜单崩溃：改用自绘上下文菜单，移除 `flutter_desktop_context_menu`
- `file_picker` 升级 13.x（federated API）：单文件 `pickFile`、`pickFiles` 返回 List、`saveFile` 返回 `Uri`、
  目录选择 `getDirectoryPath`
- 修复 h2c 明文 HTTP/2（prior-knowledge）抓包与转发、HTTP/2 流顺序保持
- 修复 close-delimited 响应体被丢弃（#844）、不支持解析时对 null 通道强制解包导致的崩溃
- 修复 Android VPN 目的端口同步记录（#530）、请求行 refresh 回调内存泄漏
- 新增 IDNA 主机名归一化（#923），与既有 `idn.dart` 实现并存
- 其他：Windows UAC 提权与 VC++ 运行库随包、更新镜像、窗口尺寸健壮性

**保留本 fork 的既有改动**（上游同期未覆盖或实现不同）

- #871 iOS HTTP/2 `:authority` 沿用客户端原始 Host 头（避免经代理后 403）
- #922 详情页响应到达即刷新、#915 选中态按 requestId 记录（列表重建不丢高亮）
- #902 保存文件走 `Platforms.saveFileAdaptive`；Android 图片保存写临时文件后走系统分享
- #701/#456 大响应降级为原样转发 + 只读路径有界解码
- #674 停止抓包资源释放、#645 脚本 `clearRequests()` / `removeRequest()`
- #705 HostFilter 支持 URL 前缀过滤、#925 重写规则正则分组展开
- #893 批量导出改走真实临时文件（修复 iOS "Is a directory"）
- 自研能力：抓包自检、Fuzzer、采集方案、安全自检、Root 模式（iptables `-w`）、JS 还原、
  Windows 增强接管与残留自愈

### 已知取舍

- 上游与自研各有一套上下文菜单、IDNA、内置变量、MCP 实现，本次一律**并存**而非替换；
  上游实现更完整处（重写规则拖动排序、`getDirectoryPath`、`toMap()` 多值语义）已采用上游版本。

## v1.23.2 (2026-09-22)

### 文档

- 补齐 `docs/features_tips.md`：新增「v1.23.1」段落（Windows 增强接管的定位与为何默认关闭、残留自愈、自检页新增检查项、iptables `-w`），
  以及「近期增强（v1.22.87 ~ v1.22.99）」段落，把 iOS 扩展内存治理、证书诊断分级、Magisk 模块安装系统证书、TUN 模式评估结论补进使用者文档。

## v1.23.1 (2026-09-22)

### 修复

- 修 v1.23.0 引入的编译错误：自检页新增的「Windows 增强接管」项误用了 `AppConfiguration`
  （`winTakeoverEnabled` 实际在 network 层的 `Configuration` 上），并且该文件缺少 `dart:io`。
  v1.23.0 因此在所有平台都没能构建出来，本版是第一个真正包含该项与残留自愈的发布。

## v1.23.0 (2026-09-22)

### 确认 + 改进：Windows 增强接管

**先回答默认状态：`winTakeoverEnabled` 默认是关闭的**（`network/bin/configuration.dart`）。
这个取舍是合理的——WinHTTP 是**系统级**设置、代理环境变量是**用户级**设置，两者都不会随进程退出
自动消失，一旦崩溃残留就会把整机代理指向一个死端口。但这带来一个副作用：功能存在、却没人知道，
于是"某些进程抓不到"（#896）里有一部分其实只是没打开它。

- **补上残留自愈**：启动时除了原有的系统代理自愈，现在还会检查 **WinHTTP 代理**与
  **代理环境变量**是否指向本应用端口，是则清理。只在"指向 127.0.0.1 / localhost 且端口正好是
  本应用端口"时动手，避免误伤用户自己配的其它代理。
- **自检页新增「Windows 增强接管」项**：未开启时直接说明"自带网络栈的应用、WinHTTP 服务、
  CLI 工具（curl/git/node）可能抓不到"，并指路到「偏好设置 → Windows 接管」；开启则显示已覆盖范围。

### 加固：Root 模式的 iptables 命令全部加 `-w`

Android 上 iptables 存在 xtables 锁竞争（系统自身、其它模块、Magisk 服务都在用），
不加 `-w` 会随机失败并报 `Another app is currently holding the xtables lock`——
用户看到的现象是"有时候能开、有时候失败"。现在所有命令都会等待锁而不是直接失败。

## v1.22.99 (2026-09-22)

### 修复：**有 root 也装不进系统证书**（#833 / #652 / #741 / #727 的实质）

之前那句"非 root 设备改不动系统信任库"说偏了——真实情况是**有 root 也常常装不上**：
现代 Android 的 `/system`（受 dm-verity 保护）和 `/apex`（APEX）都是**只读**的，
旧实现直接 `cp` 进去必然失败，用户只拿到一句"安装失败，请确认 Root 和 system 写权限"，无从下手。

- 现在改成落成 **Magisk 模块**（`/data/adb/modules/proxypin_ca/`），由 Magisk 在开机时挂载；
  KernelSU / APatch 都兼容这个目录。
- Android 14+ 的 CA 目录在 APEX 里，模块会额外带一个 `post-fs-data.sh`，
  把证书并入 `/apex/com.android.conscrypt/cacerts`（社区模块的标准做法）。
- 新增「移除已安装的系统证书」按钮（删模块目录，重启生效）。
- 设备上没有 Magisk/KernelSU/APatch（无 `/data/adb/modules`）时会明确说明原因，
  并建议改用"下载证书 + 手动刷模块"，不再只给一句含糊的失败提示。

### 文档：TUN 模式可行性评估

新增 `docs/tun_mode_evaluation.md`（已登记进「使用文档」中心）。结论：**技术可行，但成本极高**。

- TUN 本身不是难点：Windows 用 `wintun.dll`（用户态、微软签名）、macOS 用系统自带 `utun`、
  Linux 用 `/dev/net/tun`，每平台不过几百行，路由用 `0.0.0.0/1` + `128.0.0.0/1` 两条明细路由即可。
- **真正的瓶颈是桌面端没有 IP 协议栈**——从 TUN 读出来的是原始 IP 包，要解析 TCP 状态机、
  UDP/DNS 才能变成可抓可改的 HTTP 流量；而移动端那份是 Kotlin/Swift，**无法复用**，
  最小可用（仅 IPv4 + TCP 80/443）也要 1500~2500 行，完整版 4000 行以上。
- 风险：路由配错会整机断网（需要和 Root 模式同级的清理安全网）、创建虚拟网卡在 Windows 上
  容易被杀软拦、权限门槛比"系统代理"高一档、与系统代理同时开会绕圈。
- 建议优先级为低；若要做，先从 **Windows + 仅 TCP + IPv4** 打通链路。更低成本的替代：
  确认 WinHTTP 接管默认开启、引导目标程序自设代理、在自检页写明边界。

## v1.22.98 (2026-09-22)

### 修复 / 加固：#903 iOS 扩展内存

- **单连接发送缓冲加上限（4MB）**：`Connection.sendBuffer` 是扩展内存里唯一的无上限增长点
  （channel 未 ready 时数据只能堆在这里）。超过上限直接断开这条连接——断一个请求，
  好过整个扩展被系统杀掉（表现为"网络全断 + 小窗消失"）。关闭连接时也会立刻放掉缓冲区，不等 GC。
- **连接数上限 384 → 192**：iOS 给网络扩展的内存配额远小于 App 进程，384 条连接各自的
  socket + 发送缓冲在移动网络下很容易把扩展推到被杀的边缘。
- **内存压力下主动回收**：扩展 RSS 超过 45MB 时按活跃度裁剪到 128 条连接，超过 60MB 裁剪到 48 条
  （最多每 5 秒一次，避免在包处理热路径上反复扫表）。配合 v1.22.88 已有的水位观测，
  现在是"看得见 + 会自救"。
- 说明：iOS 扩展的内存配额是**独立**的，App 设置里的「内存清理」对它无效，所以这部分必须在扩展内自己做。

### 改进：证书诊断能分清"系统库 / 用户库"

- 自检页的「CA 根证书」现在区分证书装在哪：**系统信任库** / **用户证书库** / 未检测到。
  Android 7 起应用默认不信任用户证书，"证书装了却抓不到 HTTPS"多半出在这里——现在会直接点明，
  并给出两条可行路径（root 装进系统证书目录，或给目标 App 配 `network_security_config`）。
- 证书安装页补了两条最容易踩的坑：**安装时要选「CA 证书」而不是「VPN 和应用证书」**；
  Android 14+ 的 CA 目录在 APEX 里，只拷文件不一定生效，通常需要模块做 bind mount。

### 一批"环境类"issue 的甄别结论

- **#833 / #652 / #728 / #741 / #727 / #200（ColorOS、Shamiko、APatch、免 root 安卓 16 证书挂载）**：
  工具侧能做的已做完——证书能装（含 `/system/etc/security/cacerts` 与
  `/apex/com.android.conscrypt/cacerts` 两条路径）、能检测、有引导，本版又补上"装在哪一级信任库"的
  精确诊断。剩下的失败发生在设备侧（Shamiko 白名单未放行、APatch 元模块模式、ColorOS 对系统分区的
  校验等），代理工具无法越权处理。
- **#860（Flutter 应用抓不到）**：**原理上工具侧解决不了**。Flutter 的 Dart 层不走系统信任库，
  用的是自己打包的 CA bundle，证书装到哪一级都无效。只有重打包目标 App 或在已 root 设备上替换其
  CA 资源，这超出代理工具的权限范围。
- **#896（Windows 个别进程抓不到）**：系统代理（WinINET）与 WinHTTP 接管都已实现
  （`windows_takeover.dart`）。抓不到的是完全不走系统代理栈的进程；要覆盖需要 TUN/驱动级接管，
  不在当前架构内。
- **#890 / #584（偶发漏抓）**：QUIC 阻断默认已开启（`blockQuic = true`）并能显示拦截次数，
  浏览器走 UDP/443 的 QUIC 会被阻断回落 TCP 从而可被 MITM。这类反馈更可能是应用自带信任库或
  非标准端口 QUIC，自检页已列排查项。

## v1.22.97 (2026-09-22)

### 工程

- **arm64 deb 从构建矩阵移除**：核实后确认它在 GitHub Actions 上无法产出，三条都是外部限制——
  ① Flutter 官方没有 Linux arm64 的 SDK 产物（`releases_linux.json` 里只有 `stable/linux/`，
  也不存在 `releases_linux_arm64.json`），arm64 runner 上 flutter-action 必然报
  `Unable to determine Flutter version for channel: stable architecture: arm64`；
  ② 从 x64 交叉编译被工具链直接拒绝（已实测：`Cross-build from Linux x64 host to Linux arm64
  target is not currently supported.`）；③ `linux-arm64` 的 engine artifacts 也不存在（404）。
  留着它只会让 workflow 长期标红，所以拿掉，并在 workflow 注释里写明原因与将来的恢复方法
  （官方支持后把 matrix 里的 arm64 项加回 `ubuntu-24.04-arm` 即可）。

## v1.22.96 (2026-09-22)

### 修复

- **#901 多个 Set-Cookie 被合并成一个字符串**：`HttpHeaders.toMap()` 原先把所有多值头一律用 `;`
  连接。对 Set-Cookie 这是**协议错误**——它是唯一禁止合并的响应头（值本身含分号和逗号），
  合并后浏览器会把两个 Cookie 当成一个解析，后一个的 `Max-Age=0` / `expires` 会错误地作用到
  前一个上（脚本里读 `headers['set-cookie']` 拿到的也是错的）。现在按头类型分别处理：
  `Cookie` 用 `; ` 连接、`Set-Cookie` 用换行分隔（保留"多个独立头"的语义）、其余多值头用 `, `
  （RFC 9110 允许的合并形式）。
- **#894 安卓批量导出提示"导出成功：0 请求"**：一条都没写成功时不再谎报成功，改为明确提示
  失败原因（多数是所选目录不可写）并建议改用「导出 HAR」。
- **#892 批量重放 100 次只成功约 70 次**：重放的超时原来只有 3 秒，稍慢的接口会成批失败。
  移动端与桌面端的批量重放超时都放宽到 10 秒。

### 加固（Root 模式抓包，v1.22.92 引入）

- **停止抓包时同步撤销 root 重定向**：否则重定向还在、监听没了，设备会表现为
  "连着 WiFi 但所有 App 上不了网"。
- **抓包未运行时禁止开启 root 模式**：代理端口没在监听时开重定向同样等于断网，现在直接拦住并说明原因。

### 工程

- **arm64 deb：核实后确认无法产出，已从构建矩阵移除**（避免 workflow 长期标红）。
  三条都是外部限制：① Flutter 官方没有 Linux arm64 的 SDK 产物（`releases_linux.json`
  只有 `stable/linux/`，也不存在 `releases_linux_arm64.json`）；② 从 x64 交叉编译被工具链直接拒绝
  （实测：`Cross-build from Linux x64 host to Linux arm64 target is not currently supported.`）；
  ③ `linux-arm64` 的 engine artifacts 也不存在（404）。等官方支持后，把 matrix 里的 arm64 项加回
  `ubuntu-24.04-arm` 即可。

### 长尾 issue 甄别（本轮核对结论）

- **已有实现、无需再动**：#900（环境变量内置变量，`builtin_variables_dialog.dart`）、
  #825（上游代理支持 socks5）、#891（配置导入导出，配置管理页）、#815（iOS「不作为默认路由」，
  已是 `ipLayerProxy` 开关）、#931（停止抓包卡死，`Server.stop()` 各步已有超时保护）。
- **属设备/系统/应用自带信任库，工具侧无法修**：#833 / #652 / #728 / #741 / #727 / #200
  （ColorOS、Shamiko、APatch、免 root 安卓 16 等系统证书挂载）、#860（Flutter 应用自带 CA）、
  #896（Windows 个别进程）、#890 / #584（偶发漏抓，疑 QUIC 走 UDP）。抓包自检页已覆盖对应排查项。
- **需要真机复现才能定位**：#892 的另一半（"另外 30 次都没记录"）与 #773（性能问题）未能在
  静态层面归因，本次只做了能确定的那部分（超时过短）。

## v1.22.95 (2026-09-22)

### 修复

- 修掉把语言版本提升到 Dart 3.13 后才暴露出来的两处非法形参修饰符（上游遗留写法）：
  `inputAddress(var host)` 改成 `String host`（`lib/ui/mobile/widgets/remote_device.dart`）、
  命名参数上的 `final` 去掉（`lib/ui/component/search_condition.dart`）。
  这两处在更严的语言版本下是编译错误，v1.22.94 因此在所有平台都没能构建成功。

## v1.22.94 (2026-09-22)

### 工程

- **提交 `pubspec.lock`**：该文件此前被 `.gitignore` 忽略，导致每次 CI 都重新解析当时最新的
  兼容依赖、构建不可复现（也是"某个依赖的 bug 早被上游修了但没人知道"的成因）。现在把
  CI 里 `flutter pub get` 生成的结果原样提交，依赖树被锁住。
- 同时把 `pubspec.yaml` 的 `environment.sdk` 由 `>=3.0.2` 提升到 `>=3.13.2`，与 lockfile 的
  `sdks` 段对齐（`code_forge 10.14.0` 本身也要求 Dart ^3.13.2）。若本版在你本地报 SDK 版本不足，
  升级 Flutter 即可。
- 顺带说明：`Build Linux DEB (arm64)` 在 CI 上是 flutter-action 报
  `Unable to determine Flutter version for channel: stable architecture: arm64`，
  是 arm64 runner 上的外部问题（amd64 正常产出）。去掉 `continue-on-error` 之后它会如实标红，
  而不是像以前那样静默跳过。

## v1.22.93 (2026-09-22)

### 修复

- 修 v1.22.92 引入的编译错误：`HttpMessage` 上没有 `uri`，WebSocket 规则的 URL 匹配改用
  `requestUrl`（`lib/network/handle/websocket_handle.dart`）。v1.22.92 因此没有产出任何安装包，
  本版是第一个真正包含 WebSocket 帧级操纵与 Root 模式抓包的发布。

## v1.22.92 (2026-09-21)

### 新功能：WebSocket 帧级操纵（#839 Feature Request 1）

现在对 WebSocket 不再只能"看"了，可以真正干预：**改写内容 / 丢弃 / 延迟 / 重复**。
在「WebSocket 拦截」的规则里多了「帧级动作」一栏：选动作 + 写帧内容匹配条件（留空＝该方向所有帧）。

实现边界（刻意保守，宁可少改一帧也不弄坏连接）：

- **没有配置任何动作规则时，转发路径与改造前逐字节一致**（原样转发），零介入；
- 分片帧、`permessage-deflate` 压缩帧、控制帧（ping/pong/close）**不参与内容改写**，仍原样转发；
- 帧边界扫描不出来、或扫描结果与真实字节流对不上时，整段原样放行；
- 帧级处理异常会回退成原样转发并写日志，绝不因拦截失败而丢包。

顺带修掉一个隐含问题：规则管理器以前只在打开过「WebSocket 拦截」页面后才初始化，
应用刚启动时规则列表是空的、规则根本不生效；现在启动即加载。

### 新功能：Root 模式抓包（#839 Feature Request 2，Android）

不开 VPN，用 root 权限把系统出站 TCP 流量重定向到本机代理端口，用来抓那些
「检测到 VPN / 系统代理就拒绝联网」的应用。入口：**设置 → Root 模式抓包**。

安全设计：

- 只有你在设置里主动开启时才会执行特权命令；从没用过的用户不会被唤起 su 授权框；
- 规则只挂在自己的 `PROXYPIN` 链下，**不改动系统任何既有规则**；链内先排除回环地址与
  本 App 自身的 uid（否则代理自己的出站流量会被再重定向一次，形成死循环）；
- 只处理 IPv4，IPv6 保持直连（代理端口只监听 IPv4，硬引过去只会让 IPv6 站点连不上）；
- 与 VPN 抓包互斥，开启前会检查并提示；
- 开启失败立即回滚；App 每次启动会清理上次异常退出残留的规则
  （残留的表现是「连着 WiFi 但所有 App 上不了网」，用户很难自己想到原因）。

需要设备已 root 并授予 su 权限；未 root 设备不受影响（入口只在 Android 显示）。

### 工程

- **CI**：`build-desktop.yml` 与 `build-deb.yml` 的 job 级 `continue-on-error` 一并去掉
  （它会吞掉构建失败、让 run 仍显示 success）。deb 里「arm64 装不上 Flutter 就跳过」的
  自适应逻辑保留，但不再靠它掩盖失败：Set up Flutter 失败会让 job 变红，后续步骤按
  `outcome` 自动跳过。
- **依赖可复现性**：开始提交 `pubspec.lock`。

## v1.22.91 (2026-09-21)

### 修复：#839「高流量下卡顿 / 历史被清空 / 条目点不动」

- **卡顿根因**：请求数达到上限（默认 10000）之后，每来一个新请求都会走一遍
  `domainList.clean()` + `requestSequence.clean()`，而这两个动作是**清空并全量重建**
  （O(n)），也就是说持续超限的高流量下，每个请求都要重建一次整个列表与域名分组。
  已改为增量 `remove()`，只摘掉被丢弃的条目；桌面端同样处理。
- 顺带修好一个体验问题：旧逻辑在超限丢弃/内存清理时会把**筛选条件与选中状态**一起清掉，
  改 remove 后这些状态得以保留。
- 「历史偶尔被完全清空」不是数据丢失：内存到设置阈值时会执行 `cleanupEarlyData(32)`
  （保留最近 32 条），这是既有的内存保护策略，本版让它在清理时不再连带清掉筛选/选中。

### 修复：#839「重写规则的文本编辑器打字时文本跳动 / 字符被删」

- 根因在编辑器依赖 `code_forge` 的上游缺陷（heckmon/code_forge #99：光标跳动、
  重复执行、调整 tab 尺寸时的算术溢出）。本版把依赖下限由 `^10.8.0` 提升到 `^10.14.0`
  固化该修复（10.12.0 起包含，并带来大文档滚动优化 #107、shift+click 选择 #108）。

### 修复：#661 Ubuntu 下「安装证书」失败

- 旧实现直接往 `/usr/local/share/ca-certificates/` 拷贝，普通用户权限不足时抛异常被吞掉，
  用户只看到「安装失败」。现在分三步降级：① 直接写系统库（root 运行时可用）→
  ② `pkexec` 提权（桌面环境会弹出图形授权框）→ ③ 装进**用户级 NSS 库** `~/.pki/nssdb`
  （Chrome/Chromium 实际信任的是它，需 libnss3-tools 提供 certutil）。
  三步都失败会写出明确原因；证书状态检查也一并识别用户级 NSS 库。

### 工程

- **CI**：iOS 工作流去掉 job 级 `continue-on-error: true`。它会吞掉 iOS 编译失败
  （run 仍显示 success，Release 静默缺少 ipa），也无法实现注释里写的「互不阻塞」。
- **依赖可复现性**：`.gitignore` 不再忽略 `pubspec.lock`（应用项目应当提交 lock）。
  此前没有 lock，每次 CI 都会解析出当时最新的兼容依赖，构建不可复现。

### 其他平台 / 长尾 issue 结论

- #913（HTTPS 目标为 IP 时证书 SAN 类型错误）：**已修** —— 证书生成对 IP 目标使用
  iPAddress（context tag 7）而非 dNSName。
- #366（双向认证 mTLS）：**已实现**（与上游 TLS 握手时透传客户端证书）。
- #833 / #652 / #728 / #741 / #727 / #200（ColorOS、Shamiko、APatch、免 root 安卓 16
  等系统证书问题）、#860（Flutter 应用自带 CA）、#896（Windows 个别进程）、
  #890 / #584（偶发漏抓）：属设备/系统/应用自带信任库类，工具侧无法修，
  抓包自检页已列出对应排查项。

## v1.22.90 (2026-09-21)

### 修复：Android 上畸形 TCP options 会让该包的后续处理被整体跳过（与 iOS 同源）

- `vpn/util/PacketUtil.kt` 的 `isPacketCorrupted` 里写着 `i = i + options[++i] - 2`，与 iOS 侧的
  `isPacketCorrupted` 一字不差（同源于 netguard 的 Java 实现）：
  ① kind 5/15 恰好位于 options 末尾时 `options[++i]` **数组越界**；
  ② `options[++i]` 是有符号 Byte，取值 >127 会变成负数，使 `i` **回退**（重复解析）。
  该函数在每个 ACK 包上都会调用。
- 异常虽然会被 `ProxyVpnThread` 的 catch 兜住（不会崩），但它**中断了这个包的后续处理**——
  `acceptAck` 之后的数据推送（PSH）等逻辑被整体跳过，表现为"个别请求莫名卡住/超时"。
- 现在按选项类型步进并全程校验边界（末尾缺长度字节、长度 <2、长度越界一律判定为损坏），
  与 iOS 实现对齐。

### 修复：Android 的 TCP options 解析同样是裸 `ByteBuffer.get()`

- `TCPHeader.handleTcpOptions` 对每个字段都用裸 `packet.get()` / `getShort()` / `getInt()`，
  options 被截断时抛 `BufferUnderflowException`（同样导致该包后续处理被跳过）；
  且 `else` 分支的 `index = index + size - 2` 中 `size` 是有符号 Byte，>127 时 `index` 会回退。
- 现在每一步先检查 `packet.remaining()`，不足即停止解析；长度字节按无符号处理；长度 <2 直接停止。

### 平台对照结论（本轮同步排查了其他平台原生层）

- **Android 其余原生层未发现同类可崩点**：`ConnectionHandler`（`channel!!`、`lastIpHeader!!`）、
  `ProcessInfoManager`（`activity!!`）等都有前置判空或 try/catch 兜底；VPN 读循环本身也有 try/catch。
- **桌面原生层很薄**（抓包逻辑都在 Dart 侧）：Windows 只有崩溃处理器与系统代理清理，
  macOS 只有 AppDelegate 与生命周期通道，Linux 是 Flutter 模板——均无报文解析逻辑，无同类缺陷。

## v1.22.89 (2026-09-21)

### 修复：iOS 批量导出 Request / Response 报 "Is a directory"（上游 #893）

- 现象：iOS 上列表页多选导出 Request / Response / Request+Response（**哪怕只选 1 条**）报
  `FileSystemException: Cannot open file, path = .../Library/Caches/<UUID>/ (OS Error: Is a directory, errno = 21)`，
  系统分享面板打不开；而同样入口导出 HAR、以及详情页单条分享都正常。
- 根因：iOS/iPadOS 分支用的是 `XFile.fromData(...)` + `files.map((f) => f.name)` 交给 share_plus。
  share_plus 需要把内存数据落到临时目录，但拿不到有效文件名时，落盘路径会退化成
  `<tmp>/<uuid>/` 这种**目录**，于是打开"文件"时报 EISDIR。对照可知 HAR 用的是显式文件名列表
  （`fileNameOverrides: [fileName]`）所以正常。
- 修复：新增 `shareExportFiles()`——**先写真实临时文件，再用 `XFile(path)` 分享**，
  文件名同时显式传给 `fileNameOverrides`，不再依赖 `XFile.name` 的取值行为；
  分享完成后延迟 5 分钟清理临时目录（避免分享尚未完成就删文件）。
  HAR 导出也统一走同一路径（同类隐患一并消除）。
- 附带修正一处误导：原先代码里标注"修复 #893"的那段逻辑位于 **Android/桌面分支**，
  而 #893 是 iOS 问题——iOS 分支从未被修到，本次才是真正的修复；注释已改准确。

### 修复：HTTP/2 的 `te` 头违反 RFC 9113（#871 相关）

- RFC 9113 §8.2.2 规定 h2 中 `te` 只允许取值 `trailers`，其它值一律不得出现。
  原实现原样转发客户端的 `te` 值，严格的 upstream（如 Google 前端）会直接拒绝该请求。
  现在只保留合法的 `te: trailers`，其余丢弃。
- **诚实说明**：上游 #871（个别 API 子域经 ProxyPin 固定 403）**未能归因到 h2 编码路径**——
  报告者实测"HTTP2 开关开/关结果相同""同域主站 200、仅该 API 子域 403"，说明问题不在 h2 头编码，
  更可能在连接层特征或该 API 自身的校验。本次只补上这处能静态确认的协议违规，
  其余需要真机抓原始字节比对才能继续。

### 清理：iOS 扩展删除约 42KB 无人调用的代码

- 删除 `ios/ProxyPin/vpn/socket/ClientPacketWriter.swift`：iOS 侧无任何引用
  （Android 侧另有同名 Kotlin 实现，仍在用）。
- 删除 `ios/ProxyPin/vpn/ping/` 整个目录（`GBPing.h/.m`、`GBPingSummary.h/.m`、`GBPingHelper.swift`、
  `ICMPHeader.h`，合计约 40KB ObjC/Swift）：`ConnectionHandler.isReachable` 写死 `return true`，
  从未调用该探测实现，`GBPingHelper` 也无任何引用。ICMP echo 回包由
  `vpn/transport/protocol/ICMPPacket.swift` 处理，不受影响。
- `ProxyPin-Bridging-Header.h` 移除 `#import "GBPing.h"`；`project.pbxproj` 同步删除 30 行登记。

## v1.22.88 (2026-09-21)

### 修复：Android 上「CA 根证书 读取失败」（MissingPluginException）

- 现象：Android 打开抓包自检，CA 根证书一项显示
  `读取失败：MissingPluginException(No implementation found for method isCaInstalled on channel com.proxypin/method)`；
  看起来像证书坏了，其实只是没人实现这个方法。
- 根因：`com.proxypin/method` 通道**只有 iOS 实现**（`ios/Runner/Handlers/MethodHandler.swift`），
  Android 侧从未注册；而抓包自检页对"移动端"统一调用了 `isCaInstalled`。
- 修复三处：
  1. Android 新增 `MethodHandlerPlugin`（通道 `com.proxypin/method`）：`isCaInstalled` 通过
     `AndroidCAStore` 读取系统证书目录与用户凭据、按 DER 字节比对，**不需要 root**；
     `requestLocalNetwork` 恒为 true；其余方法返回 `notImplemented`。
  2. Dart 的 `NativeMethod` 原先只捕获 `PlatformException`，`MissingPluginException` 会漏到上层——
     现在三个方法都兜住，未实现一律按"否"处理，不再让自检变成"读取失败"。
  3. 自检页 Android 未安装时改为给安装引导（而不是照抄 iOS 的"HTTPS 会握手失败"），
     并在 detail 里点明：Android 7 起用户证书默认不被大多数应用信任，要全应用生效需 root 装进系统证书目录。

### 修复：导出根证书"点完没反应 / 找不到文件"

`_exportFile` 与 `_downloadCert` 只在成功时提示，用户取消保存对话框或保存失败时**毫无反馈**，
现象就是"点完导出，但根本没有根证书文件"。现在取消/失败也会提示，并写日志方便排查。

### 新增：iOS 扩展内存水位观测（上游 #903）

- iOS 给网络扩展的内存上限是**独立的**，超限时系统直接杀扩展进程（网络全断 + 小窗消失 + 日志为空）；
  而 App 设置里的「内存清理」只清理 App 进程内的请求列表，对扩展无效。
- 扩展新增 `MemoryMonitor`：读取 `phys_footprint`（不可用时退化 `resident_size`），记录峰值，
  统计连接数 / 所有连接 `sendBuffer` 积压总量 / 单连接最大积压；每次读包采样一次，
  按 10s 节流写系统日志（Console.app 搜索 `extension memory` 可见）。
- 新增通道方法 `getVpnMemory`：App 通过 `sendProviderMessage` 向扩展拉取快照；
  抓包自检页新增「扩展内存」一项，峰值接近 45MB 时预警。
- 本项只做观测，不改变任何转发行为。

### 新增文件

- `ios/ProxyPin/vpn/utils/MemoryMonitor.swift`（已登记进 Xcode 工程）
- `android/app/src/main/kotlin/com/network/proxy/plugin/MethodHandlerPlugin.kt`

## v1.22.87 (2026-09-20)

iOS 的 VPN 扩展（IP 层代理 / `ios/ProxyPin`）专项健壮性审计。扩展是**独立进程**，它的任何一次 trap 都会让整条隧道、也就是设备上所有 App 的流量瞬间中断，所以本轮把所有"能崩/能静默卡死"的点都补齐了。

### 修复：TCP 序号回绕会直接崩溃扩展进程

Swift 的 `+` 在整数溢出时**无条件 trap**（release 也一样）。而 TCP 序号按 RFC 793 必须做 mod 2^32 运算——客户端的 ISN 是随机 32 位，只要它接近 `UInt32.max`，回 ACK 时 `sequenceNumber + 1` 就会溢出崩溃。同样的写法在扩展里共 9 处，全部改成 `&+`：

- `ConnectionHandler`：`ackFinAck` / `sendFinAck` / `sendAckForDisorder` / `sendAck` / `sendLastAck` / `replySynAck`；
- `TCPPacketFactory`：`createRstData` / `createSynAckPacketData`；
- `SocketIOService.pushDataToClient`：`sendNext + buffer.count`——这里原注释写着"处理溢出问题"，但用的是 `+`，一条长连接累计发到 4GB 就会崩在注释旁边。

顺带修掉 `sendAck` 里 `(... + 长度) % UInt32.max`：`% UInt32.max` 既拦不住溢出（`+` 会先 trap），又会在和正好等于 `UInt32.max` 时把序号算成 0。

### 修复：TCP options 解析越界崩溃（畸形选项可稳定触发）

`PacketUtil.isPacketCorrupted` 是"防御性校验"函数，但遇到畸形选项自己会崩——它读 `options[i + 1]` 却从不校验边界，且 `i += Int(options[i + 1]) - 2` 在长度字节小于 2 时会让 `i` 变成负数（下标为负同样崩溃）或原地死循环。该函数在**每个 ACK 报文**上都会跑。现在按选项类型做步进并全程校验边界，异常时直接判定为损坏。

### 修复：UDP 接收循环会永久静默（DNS/QUIC 突然无响应且无日志）

`SocketIOService.readUDP` 里 `guard let data = data, !data.isEmpty else { return }` 直接返回，**没有重新挂起 `receive`**——而 UDP 的零长度数据报是合法的、空读也可能出现。一旦命中，这条 UDP 连接就再也收不到任何数据，现象就是 DNS/QUIC 某一刻突然不通，日志里什么都没有。现在改为重新挂起。

同时修掉两处相关隐患：UDP 读错误时不再只标个标志（改为与 TCP 一致的关闭连接），并且不再裸读写 `isAbortingConnection`（与原生的写入侧一致地取锁）。

**特别说明（易错点）**：UDP 的 `isComplete` 语义与 TCP 完全不同。按 Apple 对 `nw_connection_receive_completion_t` 的说明，TCP 是"整条流的读取方向关闭"时才置位，而 UDP 是"**到达数据报末尾**"就置位——也就是每个数据报都是 `true`。所以 这里绝不能照抄 `readTCP` 的 `if isComplete { 关闭连接 }`，否则第一个 DNS 响应到达时连接就被关掉。代码里已写明这条注释。

### 修复：ICMP 回包字节序错误（ping 一直不通）+ 一处对齐陷阱

`ICMPPacketFactory.parseICMPPacket` 用 `withUnsafeBytes { $0.load(as: UInt16.self) }` 解析：

- `load(as:)` **要求指针对齐**，而这里是在 `removeFirst()` 之后从奇数偏移取址，属于 misaligned raw pointer，会直接 trap；
- `load(as:)` 读的是**本机字节序**（iOS 是小端），而写回时 `FixedWidthInteger.bytes` 用的是大端——`identifier` / `sequenceNumber` 被字节颠倒，回包的 id 与请求对不上，客户端的 ping 永远等不到应答。

现在改成与其他解析器一致的逐字节大端解析，两个问题一起解决。另外 `packetToBuffer` 里对未知 ICMP 类型用了 `fatalError`，改为记录日志（扩展里一次 trap = 全设备断网）。

### 加固：`isPrivateIP` 下标越界

`Int(ip.split(separator: ".")[1])` 只要传入的字符串少于两段就直接越界崩溃；改为按八位组解析，段数不对时安全返回 `false`。

### 小提示：App 里的"内存清理"清不到 VPN 扩展

App 设置里的「内存清理」是"到内存限制自动清理**请求记录**，清理后保留最近 32 条"——它只作用于 App 进程里的抓包列表。iOS 的 VPN 扩展有**独立的内存上限**，两者互不相干。所以把阈值调到多少都不会减少扩展被系统回收的概率（详见上游 issue #903）。

## v1.22.86 (2026-09-20)

iOS 侧通道审计 + 崩溃加固（接 v1.22.85 的"原生不回 result ⇒ Dart 永久挂起"专项）。

### 修复：iOS VPN 通道只在 isRunning 分支回结果，且"未知方法"会误触发一次连接

- `ios/Runner/AppDelegate.swift` 的 `com.proxy/proxyVpn` handler 里只有 `isRunning` 调用了 `result`：`stopVpn` / `restartVpn` / 启动**全都不回结果**，Dart 侧 `await invokeMethod` 永远不会完成（挂起 + 泄漏）；
- 更危险的是它的 `else` 分支：**任何未知方法都被当成"启动 VPN"**。例如 Dart 侧后来新增的 `getQuicBlockedCount`（Android 用来显示 QUIC 拦截计数）落到 iOS 就会用 `host = nil` 去拉起一次 VPN 连接；
- 修复：改成显式 `switch`，每个分支都回 `result`，`getQuicBlockedCount` 明确返回 0，未知方法回 `FlutterMethodNotImplemented`。

### 修复：iOS 小窗进入路径上的崩溃与不回结果（上游 #812 / #724 同族）

- `ios/Runner/pip/PictureInPictureManager.swift` 的 handler 用 `arguments?["proxyPort"] as! Int` 与 `call.arguments as! String` 强解包——参数缺失或类型不符**直接崩溃**；`addData` 分支还完全不调 `result`；
- `setupPip()` 里 `AVPictureInPictureController.init(playerLayer:)!` 是**可失败初始化器**（图层/播放器未就绪时返回 nil），而 `player.play()` 恰好是被注释掉的，返回 nil 就会崩在"进入小窗"这条路径上；
- 修复：参数改为可选绑定（`as? NSNumber` → `intValue`）；每个分支都回 `result`；补上 `exitPictureInPictureMode` 的应答（Dart 侧存在同名封装）；小窗初始化的三处强解包改为守卫，不可用时打印日志并安静返回，不再崩溃。

### 加固：另外两处原生强转（崩溃 → 退化）

- `AudioManager` 的音频中断通知：`userinfo[...] as! UInt?` 改为 `as? NSNumber` + `uintValue`（`userInfo` 的类型由系统决定，转不动就崩）；
- `VpnManager`：`manager.protocolConfiguration as! NETunnelProviderProtocol` 改为可选转换，类型不符/缺失时退化为重建一份 `NETunnelProviderProtocol`（原行为是直接崩溃）；常规路径行为不变。

### Dart

- `PictureInPicture.addData` / `exitPictureInPictureMode` 补 try/catch 与 3 秒超时：`addData` **每个请求都会调**（iOS 小窗里显示 URL），原生不回结果时不能挂住。

## v1.22.85 (2026-09-20)

原生通道健壮性专项：把"原生 handler 抛异常 → 不回 result → Dart 侧 `await invokeMethod` **永久挂起**"这条链路上的坑逐个堵掉（v1.22.84 修的是小窗那一个）。

### 修复：白名单/黑名单页会永久转圈 —— 已卸载的应用（上游 #783）

- 原生 `getAppInfo` 直接同步调 `packageManager.getApplicationInfo()`，**包被卸载后抛 `NameNotFoundException`，`result` 永不回调**；
- Dart 侧其实早就写好了容错（`InstalledApps.getAppInfo(element).catchError(...)` 构造 `inValid` 占位的"未知应用"），但那只在 Future **以异常结束**时才生效——原生不回结果，`catchError` 永远不会触发；
- 于是 `_loadApps()` 里的 `await Future.wait(futures)` 永不完成，`isLoading` 一直是 true，**页面永远转圈**（代码里那个"清除失效应用"按钮也正说明这是已知会出现的场景）；
- 修复：原生包 try/catch 并 `result.error(...)`（让 Dart 的 `catchError` 按原设计生效）；顺带把 `getAppInfo` 挪到工作线程（它要 `loadIcon` 并压成 PNG，放在主线程会卡 UI）；UI 侧 `_loadApps` 改为 `try/finally`，无论成败都结束 loading。

### 修复：VPN 通道全分支无兜底（上游 #812 同族）

- `VpnServicePlugin` 的 4 个方法都没有异常兜底，且直接用 `host!!` / `port!!`——参数缺失即 NPE，`result` 永不回调，Dart 侧 `await isRunning()` 这类调用会永久挂住；
- 修复：整个 handler 包 try/catch（含 API 版本分支），参数缺失回 `INVALID_ARGUMENT`，异常回 `VPN_ERROR`。

### 修复：抓包链路会卡在处理进程信息（上游 #812 同族）

- `ProcessInfoPlugin.getProcessByPort` 的协程里没有任何异常兜底，协程抛异常没人接手，`result` 永不回调；而 Dart 侧这个调用**在抓包链路上被 await**（`lib/network/util/process_info.dart`），一挂就会卡住该连接的处理；
- `getRemoteAddressByPort` 同理，而且它更靠前——ssl 握手（`network.dart`）与请求派发（`channel_dispatcher.dart`）都会 await 它；
- 修复：两处都包 try/catch 并回 error；`port!!` 改为显式校验。

### 修复：MCP / 悬浮球通道只捕 `Exception`，漏掉 `Error`

- `McpPlugin` 两个 handler 用的是 `catch (e: Exception)`；但这条链路上会走到 Shizuku、root、反射代码，**类加载失败等 `Error` 不是 `Exception`**，漏掉同样会导致不回 result；
- 修复：改为 `catch (e: Throwable)`，并补日志。

### 加固：Dart 侧关键调用加超时兜底

- `Vpn.isRunning()`：加 2 秒超时（失败按"未运行"处理），原先若原生不回结果会永久挂起，而它处在小窗进入与状态刷新路径上；
- `Vpn.startVpn/stopVpn/restartVpn`：统一经一个吞掉异常并记日志的内部方法下发，消除 unhandled async error（**保持原本的乐观状态语义不变**——`prepareVpn` 为 false 时系统会弹授权框，用户同意后才真正启动，这里不做回滚以免授权期间状态被错误标成"未启动"）；
- `InstalledApps.getInstalledApps/getAppInfo`：分别加 15 秒 / 5 秒超时；
- `ProcessInfoPlugin.getProcessByPort/getRemoteAddressByPort`：加 3 秒 / 1 秒超时，超时按"查不到"返回 null（调用方本来就接受 null）。

### 说明

- 以上除"已卸载应用导致白名单页转圈"是可复现的确定性缺陷外，其余属于把同类风险一次性堵住；真机可过滤 `ProxyPin` 标签的 `W` 级日志观察是否还有未回 result 的路径。

## v1.22.84 (2026-09-20)

本版针对 #783 同族的"小窗 / 窗口模式"问题（#724 / #812 / #703）做静态定位后的加固。
四处都是**代码里可证实的缺陷**：路由未成对移除、原生异常不回传、进入小窗前排队了多次 await、失败会中断返回键逻辑。

### 修复：小窗路由未成对移除 —— 残留白页 + 返回键错乱（上游 #724 / #783 第 5 条）

- 进入小窗时 `Navigator.push` 无幂等保护，退出时用 `Navigator.maybePop()` 只弹**栈顶**那一个；
- 小窗期间用户若在它上面又打开了断点页（`MultiSelect`/`BreakpointExecutor`）或请求详情页，退出小窗时被弹掉的是那个页面，**小窗路由永久留在栈里**：之后全屏看到的就是它那张几乎空白的请求列表页，返回键语义也跟着乱——这正好对应 #724 的"用几次断点后卡在不相关的白页"；
- 现改为保存路由引用 + 幂等标记，退出时 `removeRoute` **精确移除**小窗路由本身（`lib/ui/mobile/mobile.dart`），并在状态未挂载时直接返回。

### 修复：原生小窗接口异常不回传结果，Flutter 侧永久挂起（上游 #812）

- `PictureInPicturePlugin` 的 `enterPictureInPictureMode` 处理器没有兜底：`activity` 是 `lateinit`（未 attach 时访问即抛异常），系统 `enterPictureInPictureMode()` 也可能抛 `IllegalStateException`；Android O 以下的设备更是**从不回调 `result`**；
- 后果不只是"没进去小窗"：Flutter 侧 `await invokeMethod` 会**永久挂起**，于是返回键处理卡在那里——既不进小窗、也不提示"再按一次退出程序"，连退出都不响应，与 #812 描述的两个现象完全一致；
- 现整个处理器包 try/catch（含 API 版本分支），失败一律 `result.error(...)` 回传，并在 Dart 侧加 3 秒超时兜底（`lib/native/pip.dart`），`inPip` 也按真实结果设置。

### 修复：进入小窗前的多次 await 容易错过系统窗口期（上游 #812 / #703）

- `onUserLeaveHint()` 之后留给调用系统 API 的窗口极短，而原实现在此前还排着 `await AppConfiguration.instance`（首次要读配置）与 `await localIp()`（要枚举网卡）——冷启动首次离开应用时这两步最慢，请求直接错过窗口期，表现为"返回桌面却没有小窗"；弹过更新提示后之所以"正常"，只是因为那段时间把这些 Future 预热完了；
- 现改为只用同步数据源：`AppConfiguration.current`（与代码库其它处一致）+ 启动抓包时缓存下来的代理地址（`PictureInPicture.updateProxy`，在 `SocketLaunch.onStart` 里写入）；并在首页 `initState` 预热本机地址；缓存缺失时（应用重启而 VPN 仍由系统保留）仍回退到异步取地址，行为不退化。

### 修复：进入小窗失败不再阻断返回键逻辑

- `onUserLeaveHint` / `PopScope` 两条路径都补上异常兜底：`enterPictureInPicture()` 内部 try/catch 并返回 false，未 await 的调用点用 `unawaited`，避免 unhandled error；进入失败时返回键会正常走到"再按一次退出程序"分支，而不是静默失灵。

### 说明

- 以上四处的缺陷本身都是**代码可证实的**（路由栈管理、原生 result 回调、await 排队位置）；但 #812 里"冷启动首次必失败"的时序推断无法在本仓库内运行验证，仍需真机 logcat 复核（可过滤 `AppLifecycle` / `pictureInPicture` 日志）。

## v1.22.83 (2026-09-20)

本版集中处理上游 #783 里「用一次就能撞见」的几处状态/性能问题，另补 #705 的写法提示。

### 修复：退出多选后原有高亮被清空（上游 #783 第 6 条）

- `lib/ui/component/multi_select_controller.dart` 之前只有 `selectionMode` 一个状态：单项「选中/高亮」与「显式进入的多选会话」都表现为 `selectionMode == true`，于是按「多选」按钮只能靠 `clear()` 退出，高亮就一起没了；
- 现增加独立的会话标记与进入前快照：进入多选时记下当前高亮，退出时恢复；进入多选仍从空选择开始（避免误删原先高亮的那条），点「取消/关闭」或删除后依旧完全清空。

### 修复：应用列表逐个查版本号，冷启动进入选择页长时间无响应（上游 #783 第 2 条）

- `InstalledAppsPlugin` 为每个应用都调一次 `getPackageInfo()` 取 `versionName`，这是**逐应用一次跨进程调用**，冷启动（PackageManager 缓存未热）时在几百个应用上累计可达数秒；
- 而 UI 从头到尾没有展示过版本号。`ProcessInfo.create()` 增加 `withVersion`（默认 false），列表接口新增同名的可选参数，单应用查询 `getAppInfo` 保持原行为；
- 结果：选择应用页只剩一次 `getInstalledApplications`，不再随应用数量线性变慢。

### 修复：历史记录筛选后进出请求详情，筛选结果被重置（上游 #783 第 3 条）

- `lib/ui/mobile/request/history.dart` 把 `HistoryStorage...getRequests()` 的 Future 和 `ListenableList` 直接建在 `build()` 里：从请求详情返回会触发重建，新的 Future 让 `_FutureWidget` 先回到 loading 分支，把整个列表连同已应用的搜索条件一起卸载，新 Future 完成后再以全新状态重建——表现就是「筛选后点进任意请求再返回，又变回全部链接」；
- 改为在 `initState` 里只取一次并存下来，重建不再重新加载、不再重置筛选；顺带省掉每次重建都重读历史文件。

### 修复：小窗未应用主页的筛选条件（上游 #783 第 4 条）

- 小窗（画中画）此前直接渲染原始请求容器（`lib/ui/mobile/widgets/pip.dart`），主页设置的筛选条件对它无效；
- 现由主列表暴露当前生效的搜索/筛选模型，小窗进入时带上并据此过滤，与主页看到的范围一致。

### 文档

- 域名过滤的添加对话框补充写法提示（`lib/ui/component/domain_add_dialog.dart`，标签 `Host / URL`）：除域名外可直接填 URL 前缀，如 `api.example.com/v1/*`，只拦截指定网址——对应上游 #705 的诉求（能力随 #225 已具备，本版把它显式提示出来）；
- 《功能指南》补充本版说明。

## v1.22.82 (2026-09-20)

### 修复：大响应"报错 + 空白"（上游 #701，属 #456 一族）

解析层对超过 4 MB 的 body 直接抛 `ParserException`，用户看到的就是"响应 200 却没有内容"（#701 报的 10MB 响应）。

- `lib/network/http/parse/body_reader.dart`：超过解析上限时不再抛异常，而是**降级为原样转发**（与 flv / SSE 同一条 `supportedParse=false` 通路）——客户端仍能拿到完整响应，列表里保留头部与前 256 KB 并标注 `bodyTruncated` / `originalBodyLength`；
- 只有"上游尚未连上"的请求中段（无法转发）才保留原来的报错，避免把请求体静默丢掉；
- `codec.dart` 在建立 body 读取器时带上该条件（`clientChannel` 与 `serverChannel` 都在）。

### 新增：只读路径改为有界（增量）解码（上游 #456）

`decodeBodyString` / `bodyAsString` 此前把整个压缩体一次性解压：压缩比 10 倍以上时，100MB 响应就能解出 1GB 级字符串——#456 的长时 OOM 主因之一。

- 新增 `lib/network/util/stream_decode.dart`：
  - gzip / deflate 用 `RawZLibFilter` **增量**喂入、累计输出，达到上限**立即停止**（压缩比再高也不会撑爆内存）；deflate 先按 raw 解，失败再回退 zlib 包装；
  - br / zstd 无增量 API：输入超过上限就不解，解出后再截断；
  - 任何失败都退回原始字节前缀，绝不抛异常；截断可能切断多字节字符，故用 `allowMalformed` 解码。
- `HttpMessage` 新增 `bodyPreview` / `getBodyStringBounded()` / `decodeBodyStringBounded()`，以及 `bodyDecodeTruncated` 标记；解码上限默认 4 MB，若用户设置了「抓包内容上限」则与之一致；
- 迁移**只读**消费方：详情预览（含右下角「预览已截断」提示）、列表搜索、请求对比（含对比页）、安全自检、AI 分析；
- **需要完整内容的路径保持不变**（脚本改写、重写规则、请求编辑、代码导出），避免截断导致写回/导出失真。

### 新增：脚本可自行清理抓包列表（上游 #645）

- 新增 `lib/network/components/js/requests.dart`，脚本运行时注入全局 `clearRequests()` 与 `removeRequest(request.requestId)`；
- `McpBridge.removeRequest(requestId)` 落到主程序请求容器（`ListenableList`），列表 / 域名分组 / 详情页同步刷新；
- 只影响列表展示，不回滚已完成的转发。

### 文档

- 《脚本开发指南》新增「让脚本自己清理抓包列表」一节；《功能指南》补 v1.22.82 说明。

## v1.22.81 (2026-09-20)

### 新增：QPACK 动态表解码 —— HEADERS 里的动态引用不再"占位"（上游 #489 延续）

v1.22.79 的 QPACK 解码只覆盖静态表，引用动态表的字段行一律以 `:dynamic-*` 占位。本版补齐动态表：

- 新增 `lib/network/util/quic/qpack_dynamic_table.dart`：
  - `QpackDynamicTable`：编码器侧动态表的**解码器副本**——按 RFC 9204 §3.2 维护容量 / 插入计数 / 绝对与相对索引，条目大小按 `名字字节数 + 值字节数 + 32` 计，容量不足时从最早条目开始淘汰；
  - `QpackEncoderStreamDecoder`：消费客户端发来的「QPACK 编码器流」（单向流 `0x02`）指令——`Set Dynamic Table Capacity` / `Insert With Name Reference` / `Insert With Literal Name` / `Duplicate`。指令之间无边界标记，故按顺序增量消费：遇不完整指令暂存等待后续字节，遇错位即停（不再连锁误读）；
- `qpack_decoder.dart`：解析字段段前缀（Required Insert Count + Delta Base → 计算 Base），按前基相对索引（`Base - rel - 1`）与后基索引（`Base + i`）解析动态引用并取真实 name/value；无表或状态不足时才回落 `:dynamic-*` 占位，并以 `unresolvedDynamicTable` 标出；
- `quic_probe.dart`：每个会话维护一份动态表副本；识别客户端单向流类型（`0x02` 编码器流的数据按序喂给解码器），HEADERS 只在客户端双向流上解码；
- **边界（诚实）**：真实最大容量由服务端 `SETTINGS_QPACK_MAX_TABLE_CAPACITY` 决定，而我们只解密客户端方向、看不到该 SETTINGS，故按 RFC 推荐值 4096 计算 `MaxEntries`；仅在"实际容量不同 + 连接插入数极大"时 Required Insert Count 的回绕还原可能不成立。

### 修复：停止抓包后仍在处理流量 / 资源不释放（上游 #674）

"停止抓包"后表格仍更新、CPU/RAM 持续上升，根因是多处残留仍在工作。本版逐一收口：

- `Server.stop()`：关闭每个连接的**远程侧通道**——此前只关客户端侧，远程 socket 的读订阅会悬挂、继续解析与转发；
- `Channel`：记录 socket 读订阅并在 `close()` 时取消——此前订阅从不取消，通道"关了"回调还在跑；
- `CombinedEventListener` 增加"停止闸"：`ProxyServer.stop()` 后残留连接/延迟回调一律丢弃，不再更新界面；服务器与代理处理器共用同一个闸；
- 停止时按用户设置的**「抓包内容上限」**统一裁剪列表里已抓消息的 body，及时释放驻留内存（默认"不限"则行为不变）；
- 脚本引擎两处泄漏：① XHR 的 20ms 轮询定时器只建不销——改为**按需拉起、空闲自动停**，且同一运行时幂等；② 运行时因脚本超时/异常被移出池时不再回收——现取消其轮询并销毁，避免长期运行累积空转定时器。

### 文档

- `docs/platform_limits.md` / `docs/features_tips.md` / `docs/extension_guide.md`：QUIC 一节更新为"已支持 QPACK **动态表**"；`get_quic_sessions` 的返回补充 `qpack_dynamic_table` 概览与流类型（工具总数仍为 64）。

## v1.22.80 (2026-09-19)

### 打磨：一致性巡检与联动补齐（无新功能）

对 v1.22.76–79 的新功能做了一轮一致性检查，修掉几处"功能已加、周边未跟上"的地方：

- **MCP `get_quic_sessions` 补上 HTTP/3 头部**：v1.22.79 解出的 QPACK 头部此前只在界面可见，现在也进入工具返回（`headers` 字段），AI 能直接读；
- **HAR 导出的 body 大小改用原始长度**：v1.22.78 的「抓包内容上限」会在转发后裁剪 body，此前导出 HAR 的 `bodySize` / `content.size` 会显示**裁剪后**的大小；现改为优先报告原始大小；
- **MCP 请求详情标记截断**：经 `requestToJson` 的输出（`get_request_details` 等）在 body 被裁剪时带上 `bodyTruncated` / `originalBodySize`，不再静默给不完整内容；
- **文档同步**：《平台与技术边界》QUIC 一节此前仍写"HEADERS 帧不解码"，已更新为**已支持 QPACK 解码（简化子集）**；《扩展与定制指南》补 QPACK 说明；`MCP_INTEGRATION.md` 的工具数由过时的 49 更正为实际的 64。

## v1.22.79 (2026-09-19)

### 新增：QPACK 简化子集解码 —— QUIC 里能看懂 HTTP/3 头部了（上游 #489 延续）

上一版用密钥日志解到 QUIC「流数据层」；本版把 **HTTP/3 HEADERS 帧**里的字段段也解出来：

- 新增 `lib/network/util/quic/qpack_decoder.dart`：按 RFC 9204 解析字段段——Encoded Field Section Prefix、索引字段行（静态表）、名字引用、字面名字 / 值；字符串支持 Huffman（**复用项目已有的 HPACK Huffman 表**，两者是同一套码）；
- 新增 `lib/network/util/quic/qpack_static_table.dart`：RFC 9204 附录 A 的 **99 项静态表**（与 HPACK 的 61 项不同，不可混用）；
- **边界（诚实）**：不支持**动态表**（需按顺序跟踪编码器指令流、跨帧维护插入 / 淘汰，复杂度远超本子集）——引用动态表的字段行以 `:dynamic-*` 占位标出，不猜；
- QUIC 连接页的流预览里，HEADERS 帧会额外显示 **「HTTP/3 头部 · QPACK 已解码 N 项」** 与逐条 `name: value`。

### 文档

- `docs/features_tips.md` 的 QUIC 连接一节补充 QPACK 解码说明与能力边界。

## v1.22.78 (2026-09-19)

### 新增：抓包内容上限（上游 #773 / #456）

长时间或高流量抓包时，把每个请求/响应的**完整 body** 都留在内存里，会让占用随抓包时长持续上涨（#456 OOM）。本版新增用户可调的**内容上限**：

- 设置 → 偏好设置 → **「抓包内容上限」**：可选 不限 / 128 KB / 256 KB / 1 MB / 4 MB（默认**不限**，行为与旧版完全一致）；
- 超过上限的 body 只保留前 N 字节用于列表展示；**压缩体（gzip / br / deflate）整体释放**（截断会破坏压缩流导致无法解码）；详情页标题栏出现 **「已裁剪（原始 X MB）」** 提示；
- **不影响转发**：裁剪发生在代理把响应/请求**写回对端之后**（`clientChannel.write` / `remoteChannel.write` 之后调用），转发始终使用完整字节；
- 新增 `lib/network/util/capture_body_limiter.dart`；配置随「导出配置」一并保存、导入时同步。

### 文档

- `docs/features_tips.md` 新增「抓包内容上限」小节。

## v1.22.77 (2026-09-19)

### 新增：WebSocket 二进制内容自动解码（上游 #623）

WebSocket 的二进制帧（opcode=0x02）本身不带格式信息，此前一律按 UTF-8 展示、多是乱码。本版做**尽力而为**的识别与解码：

- 新增 `lib/network/util/ws_payload_decoder.dart`：按**魔数 + 严格解码**识别——图片（PNG / JPEG / GIF / WebP / BMP）、压缩流（gzip / zlib）、UTF-8 文本、JSON；识别不出时回退为"二进制"并标注大小；
- **消息列表**：二进制气泡直接显示可读内容（文本 / JSON），或在识别为图片 / 压缩时显示类型标签（如 `[PNG 图片 · 12.3 KB]`、`[gzip 解压 → JSON · 1.2 KB]`）；
- **预览对话框**：按内容动态给出标签页——图片渲染成图（IMAGE）、压缩流展示解压后文本（DECOMPRESSED）、JSON 提供结构化视图，始终保留 TEXT / HEX；新增「保存」按钮，扩展名按识别结果给出；
- 误判不影响原始字节：HEX 视图始终可查看原文。

### 修复：WebSocket 保存按钮在桌面端可能写不出文件

- 保存 WebSocket 载荷改用 `Platforms.saveFileAdaptive`（桌面端拿路径后自行写盘），修复与上游 #902 同源的问题（`FilePicker.saveFile` 在桌面端不保证写出 `bytes`）；文件扩展名按识别结果自动给出（图片 / txt / bin）。

### 文档

- `docs/features_tips.md` 的「WebSocket 消息拦截的语义」一节补充二进制自动解码说明。

## v1.22.76 (2026-09-19)

### 新增：QUIC 密钥日志解密（上游 #489：把"能解"变成"真解"）

被动旁路抓包无法推导 QUIC 会话密钥（ECDHE，见《平台与技术边界》）；本版落地**唯一可行路径**——让目标应用导出密钥日志（NSS key log / `SSLKEYLOGFILE`），再离线解密 1-RTT 应用数据：

- **密钥日志导入**：QUIC 连接页右上角「钥匙」按钮导入 keylog 文件（或文本）；解析 `CLIENT_TRAFFIC_SECRET_0` / `SERVER_TRAFFIC_SECRET_0`（自动兼容 Chrome 的 `QUIC_` 前缀），按 **client_random** 建索引（`lib/network/util/quic/quic_keylog.dart`）；
- **1-RTT 解密链路**（`lib/network/util/quic/quic_1rtt.dart`）：short header 去 Header Protection（AES-ECB）→ 按包号派生 nonce → AES-128-GCM 解密 → QUIC varint 帧解析 → 提取 STREAM 数据；密钥由 traffic secret 经 HKDF-Expand-Label 派生 `quic key/iv/hp`（RFC 9001 §5.1）；
- **自动命中**：`QuicProbe` 从 Initial 取出的 ClientHello.random 与导入密钥日志对齐，命中的连接自动解密**客户端方向** 1-RTT；会话项显示「已解密 N 段」，点开查看每段的流 ID / HTTP/3 帧类型 / 长度 / 可读预览（可见 ASCII 原样、其余转 `\xNN`）；
- **交付边界**：只到「QUIC 流数据层」——HEADERS 帧内部是 **QPACK 压缩**，本版不解码，因此给的是逐段预览而非结构化请求；这已足够判断"哪个域名在传什么内容"。

### 新增：MCP 工具补全（QUIC / 安全 / 性能）

- **`get_quic_sessions`**：QUIC 会话列表（SNI、版本、远端、包/字节、最后活动）+ 10 分钟时间轴 + 密钥日志状态 + 已解密流预览；
- **`get_security_audit`**：对已抓流量跑**被动安全自检**（明文 HTTP、敏感泄露、Cookie 属性、安全响应头、CORS 过宽、JWT 等），返回按严重级别汇总与逐条修复建议，支持按 `severity` 过滤；只读、不发请求、不投递载荷；
- **`get_performance_metrics`**：进程内存（当前 / 峰值 RSS）与抓包聚合统计（方法/状态/域名分布、总大小、平均耗时、错误数）。

### 文档

- 《平台与技术边界》QUIC 一节更新为**已支持导入密钥日志解密**；《功能指南》QUIC 连接节同步；《扩展与定制指南》MCP 一节补充三个新工具。

## v1.22.75 (2026-09-18)

### 新增：抓包自检接入 MCP（让 AI 先诊断再建议）

- 自检逻辑从界面抽到 `lib/network/util/capture_diagnose.dart`（**一份结论两处用**）：界面「抓包自检」与新增的 MCP 工具共用；
- 新增 MCP 工具 **`diagnose_capture`**：返回代理服务是否在运行、系统代理指向、CA 证书是否受信任、最近是否有流量（含最新一条距今秒数），以及按检测结果生成的**可执行建议**与常见原因清单；
- 工具描述明确写出使用时机——"用户反馈抓不到包 / 页面打不开 / 流量突然中断时优先调用它"，便于 LLM 自主触发；
- 界面侧同步改为调用同一服务，并在页面上说明"同一结论也可通过 MCP 交给 AI"。

### 新增：QUIC 流量时间轴（上游 #489 持续推进）

- `QuicProbe` 增加时间桶统计：**最近 10 分钟、每 10 秒一格**的包数与字节数（环形槽位，自动滚动、`clear()` 同步重置）；
- QUIC 会话页新增**柱状时间轴**：一眼看出 QUIC 流量是持续还是有突发、最近有没有活动，并显示"共 N 包 · 流量 · 有多少段有流量"。

### 文档：平台与技术边界（上游 #874 / #683 / #489）

新增内置文档 `docs/platform_limits.md`，把三类"做不到"讲透：

- **Mac App Store 应用**：App Sandbox 不读用户级系统代理 + 强制签名；说明为何不做 `pf rdr` 半成品（需 root、要还原原始目标、易断网），以及正确做法是带签名的 Network Extension；给出三条可用替代；
- **鸿蒙**：列出移植所需的工具链、工程与平台适配清单，明确这是独立移植而非加构建目标；
- **QUIC 完整解密**：用 **ECDHE** 解释"为什么旁路抓包在数学上解不开应用数据"，并说明我们已做到的（Initial 解析、SNI、统计、时间轴、拦截回落）与唯一可行路径（导入密钥日志）。

已在「使用文档」中心登记，`quick_start.md` 的平台边界表指向该文档，`pubspec.yaml` assets 同步登记。

### 文档

- `docs/extension_guide.md` 补充 `diagnose_capture` 的使用时机；`docs/features_tips.md` 同步本版说明

## v1.22.74 (2026-09-18)

### 新增：扩展与定制指南（上游 #872）

- 新增内置文档 `docs/extension_guide.md`，把 ProxyPin 现有的**分层扩展点**梳理成一张全景表：
  请求重写 / JS 脚本 / 环境变量（含内置变量）/ 采集方案 / MCP Server / 工作流编排 / 上报与导出 / 只读诊断视图——每项说明"能做什么、从哪进"；
- 给出三个组合示例：给接口动态签名并留证、把流量镜像给自建分析服务、让 LLM 协助排查偶发 500；
- 说明这条路线为何**不做动态二进制插件**：文本化扩展（脚本/规则/配置）可版本管理、可 diff、可跨设备迁移，升级不失效；能力出口走标准协议（MCP），不在应用内开"任意代码执行"的口子；
- 「使用文档」中心登记该指南（`guide_center`），快速上手的「进阶」一节加入口，`pubspec.yaml` 的 assets 同步登记。

### 增强：QUIC 会话视图（上游 #489 持续推进）

- 会话新增**最后活动时间**与**累计字节数**，列表改为按最近活动排序——一眼看出当前哪些域名在走 QUIC；
- 顶部新增统计条：连接数 / 域名数 / 包总数 / 流量 / **活跃连接数**（30 秒内有活动）；
- 新增「复制会话列表」（制表符分隔，可直接粘进表格），便于记录与横向对比。

### 文档

- `docs/features_tips.md` 同步本版说明

## v1.22.73 (2026-09-18)

### 新增：抓包自检（上游 #890 / #860 / #896）

工具箱 →「抓包与重放」组新增**抓包自检**，一页看清"为什么抓不到流量"：

- **四项只读检测**（不改任何系统设置）：
  - 代理服务是否在监听（显示实际端口）
  - 系统代理是否指向本应用（桌面；不一致时提示可能被其它代理工具接管或上次残留未清）
  - CA 根证书是否在信任库（移动端走 `isCaInstalled`；桌面端给出正确安装位置的提示）
  - 最近是否真有流量（请求总数 + 最新一条距今多久）
- **常见原因对号入座**：QUIC/HTTP3、**Flutter 应用（Dart 自带根证书列表，不读系统 CA）**、证书固定（SSL Pinning）、Windows 自带网络栈进程、Mac App Store 沙箱应用、只改代理但应用不理会——每条都给出对策

### 文档

- `docs/quick_start.md`「平台支持边界」补两条：**Flutter 应用抓不到 HTTPS 的原因**（上游 #860）、**旧版本安装包从 Releases 获取**（上游 #881），并登记「抓包自检」入口
- `docs/features_tips.md` 新增本版说明

### 已核实

- **#931**（代理特定应用时连接超时 + 停止抓包卡死）：超时是目标地址不可达（`SocketException: Connection timed out`），错误已被分类展示；停止抓包路径此前已加超时保护，不再卡死。
- **#889**：内容为请求实现游戏外挂（aimbot）的脚本，不属本工具支持范围，不予处理。

## v1.22.72 (2026-09-17)

### #871 深入：HTTP/2 客户端指纹向浏览器对齐

- 连接上游时声明的 SETTINGS 改为与 Chrome 一致：`HEADER_TABLE_SIZE=65536`、`ENABLE_PUSH=0`、`MAX_CONCURRENT_STREAMS=1000`、`INITIAL_WINDOW_SIZE=6291456`（6MB）、`MAX_HEADER_LIST_SIZE=262144`；连接级接收窗口从 983041 提升到 15663105。部分服务端会把客户端 h2 指纹纳入风控，参数明显"非浏览器"时可能直接返回 403。
- **修正一个标识符写错的问题**：原实现把 `MAX_FRAME_SIZE` 的值填进了 `identifier 6`——标准里 6 是 `MAX_HEADER_LIST_SIZE`，等于向对端声明"我只接受 16KB 的头部列表"。现按标准发 5 = `MAX_FRAME_SIZE`、6 = `MAX_HEADER_LIST_SIZE`。

### #560 Linux arm64 安装包

- CI 的 DEB 构建加入 `arm64` 架构（`ubuntu-24.04-arm`），与 amd64 并行。
- 采用**自适应**策略：arm64 runner 上 Flutter SDK 装不成时，Set up Flutter 的失败被 `continue-on-error` 吸收、后续步骤按 outcome 跳过，流程不会变红，也不影响 amd64 产物；工具链就绪后无需改动即可自动产出 arm64 deb。

### 平台能力边界文档化（#874 / #683 / #489）

- `docs/quick_start.md` 新增「平台支持边界」一节，逐条说明现状、原因与替代做法：
  - **Mac App Store 应用**抓不到（沙箱 + 强制签名，系统代理无效；接管需要 Network Extension/TUN 与签名授权，本仓为未签名构建）
  - **鸿蒙**暂未提供构建（需独立 HarmonyOS 工程 + Flutter ohos 分支）
  - **Linux arm64** 由 CI 自适应构建
  - **QUIC** 只做拦截与识别（完整 1-RTT 解密需 TLS1.3 握手状态机与密钥调度，工程量极大），并说明"拦截 QUIC → 回落 TCP"的抓取路径
- 修正快速上手中"支持鸿蒙"的不准确表述。

## v1.22.71 (2026-09-17)

### 修复与加固

- **#871 部分 HTTP/2 API 经抓包固定返回 403**
  - HTTP/2 响应的头部名此前原样下发（可能带大写），而 RFC 9113 §8.2.1 要求**全小写**，且响应里不得出现 `Connection` / `Transfer-Encoding` 等连接相关头；严格客户端会判成协议错误。现统一小写并过滤 hop-by-hop 头。
  - HTTP/2 请求的 `:authority` 此前用 `uri.host` 重建，会丢掉非默认端口；现优先沿用客户端原始 `Host` 头（MITM 场景下它才是权威值）。
- **#886 异常退出后整机断网**
  - 新增**系统代理残留自愈**：桌面端启动时若发现系统代理仍指向 `127.0.0.1:<本应用端口>`、而用户并未开启「系统代理」开关，则自动清理；仅在端口正是本应用端口时才动作，避免误伤 Clash 等其它本地代理工具。
  - 「偏好设置」新增「清除系统代理残留」一键修复入口（Windows 会同时清掉 `ProxyServer` 与 PAC 的 `AutoConfigURL`）。
- **#898 握手失败只显示一串感叹号**
  - 握手失败信息现在带上原始原因，并列出三种常见可能（证书未安装/未信任、对方启用证书固定、非标准 TLS 流量）。
- **#850 iOS 导入 .p12 失败**
  - 导入失败时显示**具体原因**（密码错误 / 文件损坏 / 读取为空），不再只有一句"导入失败"；新增空文件校验。
  - **安全**：导入路径不再把 p12 密码写进日志（桌面端与移动端各一处）。

### 已核实无需改动

- **#926 重写规则排序**：规则列表已按「最新添加在最上面」显示（仅改显示顺序，不影响匹配语义）。

### 文档

- `docs/features_tips.md`：补充 #896 / #895 的排查顺序（Windows 增强接管 → 管理员运行 → 上游 TUN 工具 → 移动端 IP 层代理）

## v1.22.70 (2026-09-17)

### 修复

- **#844（抓包显示响应 200，客户端却超时）**：`ScriptEngine.convertHttpRequest` / `convertHttpResponse` 在脚本改写 body 后只移除了 `Content-Encoding`，没有同步 `Content-Length`。带着旧长度下发时，客户端按旧长度读包、等不到剩余字节就会超时——这正是"抓包看是 200、App 侧超时"的成因之一。现改完 body 立即重算长度并清掉 `Transfer-Encoding`。
- **#915（选中状态莫名消失）**：域名视图在 `build()` 里调用 `selectionController.prune(...)`，而 `build` 会被新请求到来、列表刷新等任意时机触发，于是用户在其它视图里选好的项被按"当前视图"收敛掉。现将收敛动作移到「搜索条件变化」时执行一次。

### 新增

- **#920 从剪贴板导入 / 导出配置**（桌面 + 移动）：配置管理页新增「复制配置到剪贴板」「从剪贴板导入配置」，省掉"导出文件 → 传输到另一台设备 → 导入文件"的来回。导入前校验内容是否为配置 JSON，导入后与文件导入共用同一套配置应用逻辑。
- **#873 脚本日志输出图片**：日志面板支持渲染图片 data URI——`console.log('data:image/png;base64,' + b64)` 即可出图，二维码、验证码之类的内容不必再"复制 → 另行转码"。新增 `lib/utils/data_uri.dart`（解析 + 2MB 上限保护），桌面日志面板与移动端日志窗口均已接入。
- **#900 内置变量可见可复制**：环境变量页新增「内置变量」入口（桌面在标题栏、移动端在 AppBar），列出 `timestamp`、`timestamp_ms`、`datetime`、`date`、`time`、`unix_date`、`uuid` 七个免定义变量，点击即复制 `{{变量名}}`。

### 核实（无需改动）

- **#913（IP 目标 MITM 证书 SAN 类型）**：代码已按 iPAddress（context tag `0x87`）编码 IP，仅域名走 dNSName（`0x82`），符合预期。
- **#906（请求列表全选）**：桌面与移动端均已有全选入口。
- **#927（Android release 构建失败）**：属上游仓库的 Gradle/AGP/Kotlin 版本与 file_picker 12 API 适配问题；本仓 Android 构建在 CI 中稳定通过，且已使用 file_picker 12.x API。

### 文档

- `docs/script_guide.md` 新增「日志里输出图片（二维码等）」
- `docs/environment_guide.md` 内置变量表补充 `{{unix_date}}`，并说明界面入口
- `docs/features_tips.md` 新增本版要点

## v1.22.69 (2026-09-17)

### 修复：界面显示问题（窄屏适配与控件裁切）

- **手动 Fuzz 页**：
  - 「先发基线」开关此前被塞进 24px 高的盒子里，Switch 被压扁显示异常；现改为独立一行，用 `FittedBox` 等比缩放，不再裁切
  - 操作行（开始 / 停止 / 间隔输入框）与开关行在手机上会横向溢出，改为 `Wrap` 自动换行 + 开关单独成行
  - 「注入项 / 组合数 / 添加注入项」一行在英文等较长文案下会溢出，文本加 `Flexible` + 省略号
  - 结果表在窄屏（< 420）下不再挤成一团：隐藏「长度」列，长度并入每行第二行与差异一起显示
- **JS 还原页**：
  - 动作栏（还原 / 美化 / 识别指纹 / 校验 + 日志）单行 `Row` 在窄屏必然溢出，改为 `Wrap` 自动换行
  - 输入区「输入 / 文件名」与「粘贴 / 选择文件 / 清空」挤在同一行，窄屏溢出；按钮改为独立一行 `Wrap`
- **Mock 场景对话框**：内容区此前固定 540 宽，改为 `maxWidth: 540` + 窄屏自适应

### 巡检

- 复查此前新增页面的布局（Fuzz 页、JS 还原页、采集方案页、安全自检页、使用文档中心、发送队列页、Mock 场景对话框），重点排查 `Row` 溢出、控件被固定高度裁切、对话框定宽三类问题；本次共修 6 处
- 配平 / import 断链校验通过

## v1.22.68 (2026-09-16)

### 修复：上游 #923（URL 编码主机名抛 FormatException）

- 目标主机名为 URL 编码域名（如 `%E5%B0%8F%E5%BA%A6.%E4%B8%AD%E5%9B%BD`）或中文域名时，Dart 地址解析会把 `%` 当成 IPv6 link-local 的 scope id 抛 `FormatException`，请求直接失败
- 清洗逻辑下沉为公共工具 `sanitizeConnectHost`（`lib/network/util/idn.dart`）：去 IPv6 方括号 → 非 IPv6 的 `%` 主机做百分号解码 → 中文域名转 Punycode
- **补齐遗漏入口**：`HttpClients.startConnect`（重放 / 脚本 fetch / MCP 出网等直连路径）此前未清洗，现已接入；代理链路 `Client.connect` / `secureConnect` 统一改走同一工具

### 修复：上游 #902（Windows 保存图片无效）

- 桌面端 `file_picker` 的 `saveFile(bytes:)` 在部分平台不会真正写盘，表现为提示"保存成功"但文件不存在
- 改为**只弹保存框拿路径、字节写入交给 `dart:io`**（沿用桌面端既有惯例 `Platforms.saveFileAdaptive`），失败时给出明确提示
- 同名问题一并修掉：工具箱「二维码」的保存图片

### 修复：上游 #925（正则分组匹配失效）

- `_expandRegexGroups` 重写为**单次遍历**展开：支持 `$0`~`$99` 与 `${12}` 写法
  - 多位数分组号不再被拆错（`$11` 不会被当成 `$1` + `1`）
  - 分组内容中恰好含 `$1` 文本时不会被二次替换
  - 越界引用原样保留，便于排查规则写法
- **补齐未展开分组的入口**：修改参数（`updateQueryParam`）、修改头部（`updateHeader`）此前直接把 `$1`/`$2` 原样写回，现已统一展开（修改响应体 / 请求体 / 响应头 / 请求头 / 参数全部生效）

### 新增：上游 #887（高级重放指定时间支持秒）

- 桌面端与移动端的「指定时间」对话框在分钟基础上增加**秒选择**（0~59）
- 仍保留"不早于当前时间"的钳制

### 文档

- `docs/rewrite_guide.md` 新增「正则匹配与分组引用」一节（`$0`~`$99`、`${12}`、各类改写场景与越界行为）
- `docs/features_tips.md` 新增「本版修复要点（v1.22.68）」

### i18n

- 新增 1 条词条（`second`），en / zh / zh_Hant 三份 ARB 同步

## v1.22.67 (2026-09-16)

### 增强：手动 Fuzz —— 多参数组合 + 结果导出

- **多参数组合**：可添加多条「注入项」（位置 + 字段 + 取值），一次跑它们的**笛卡尔积**
  - 组合数在界面上实时预览；总上限 **500** 条，超出自动截断并提示
  - 每条结果标注完整组合标签（如 `page=1 & X-Tenant=a`），便于定位是哪组参数触发的差异
  - 实现：`FuzzInjection` / `FuzzCase` / `RequestFuzzer.buildCases` / `combinationCount` / `buildVariant(template, injections, values)`
- **结果导出**：结果区右上角可导出
  - **CSV**：`index,payload,baseline,status,length,duration_ms,diff,error`，字段自动转义，可直接进表格做筛选统计
  - **JSON**：含生成时间、模板请求、总条数与逐条结构化结果，便于脚本二次处理与留证
  - 实现：`RequestFuzzer.toCsv` / `toJson`，落盘走 `FilePicker.saveFile`

### 修复：上游 #899（安卓内存清理机制）

- **问题**：请求从抓包列表移除后，字节数据要等 GC 才回收，长时间抓包内存持续堆积；清空临时数据也不见下降
- **修复**：列表清理路径改为**显式释放**字节数据（`HttpMessage.releaseBody` / `HttpRequest.release` + `MemoryCleanupMonitor.releaseAll`）
  - 移动端：清空、内存阈值清理、超限丢弃三条路径
  - 桌面端：清空、内存阈值清理两条路径
  - MCP 桥接的 `cleanupEarlyData` 同步释放
- **补齐功能缺口**：桌面端此前**没有**「请求记录上限」的自动丢弃逻辑（仅移动端有），现按同一配置项补齐，超限丢弃时一并释放

### 修复：上游 #885（脚本 + 外部代理导致请求/响应无效）

- **不再静默丢弃请求/响应**：请求脚本、响应脚本未返回有效结果时，此前直接返回 `null` 把这条请求/响应丢掉，表现为页面/接口莫名打不开；现改为**放行原始对象 + 记录告警**（阻断类需求请用「阻止请求」规则）
- **请求脚本异常兜底**：`ScriptInterceptor.onRequest` 增加异常捕获，脚本执行出错时按原样放行，不再让请求直接失败
- **修复编辑器只读残留**：脚本类型从「远程 URL」切回「本地」后，编辑器实例仍是旧的只读实例，输入框点不动、不弹输入法；现按模式 `key` 强制重建编辑器（移动端 + 桌面端）
- **健壮性**：脚本 context 缺失时不再抛 `NoSuchMethod`（`scriptContext` 取用加类型保护）

### i18n

- 新增 9 条词条（注入项 / 添加注入项 / 组合数 / 组合超限 / 导出结果 / 导出 CSV / 导出 JSON / 导出成功 / 导出失败），en / zh / zh_Hant 三份 ARB 同步

### 文档

- `docs/fuzzer_guide.md`：新增「多参数组合（笛卡尔积）」「结果导出（留证）」两节，更新实现细节、限制与 FAQ
- `docs/features_tips.md`：手动 Fuzz 一节补充组合与导出说明

## v1.22.66 (2026-09-16)

### 新功能：手动 Fuzz（变体发送）

- 工具箱「抓包与重放」组新增「**手动 Fuzz**」：选一条模板请求，把你**自己填写的取值**逐条替换进请求并发送，列出每条响应的状态码 / 长度 / 耗时 / 与基线的差异
- 4 种注入位置：URL 查询参数 / 请求头 / JSON 请求体字段 / 请求体占位符（默认 `{{FUZZ}}`）
- 可选「先发基线」自动对照；发送间隔可调；结果可逐条查看完整响应体并复制
- **边界**：不内置攻击载荷或漏洞字典，不自动判定漏洞、不自动利用——发什么、结论是什么，都交给人
- 实现：`RequestFuzzer`（`lib/network/util/request_fuzzer.dart`，复用 `HttpClients.proxyRequest`，与「重放」同一条链路）+ `FuzzerPage`（`lib/ui/component/fuzzer_page.dart`）

### 核实：上游 issue（本轮无需改动）

- #891（配置导入导出）、#892（高级重放的成功/失败记录）、#893（iOS 批量导出 `Is a directory`）、#894（安卓多选导出计数误导）——**均已在代码中实现**（#893 / #894 处有显式修复注释）
- 体检复查：孤儿页面 **0**、多窗口未注册 **0**（脚本自动核对）

### i18n

- 新增 26 条词条，en / zh / zh_Hant 三份 ARB 键集合一致（各 813 键）

### 文档

- 新增内置教程 `docs/fuzzer_guide.md`（定位 / 用法 / 结果解读 / 实现 / 边界 / FAQ），已在「使用文档」中心登记
- `docs/features_tips.md` 新增「手动 Fuzz」一节

## v1.22.65 (2026-09-16)

### 新功能：内置 JS 还原（反混淆 / 反编译）

- 工具箱「查看」组新增「**JS 还原**」：把混淆的 JS 还原成可读代码
- **反混淆**：acorn + jsrestore（8 步流水线：文本清理 → 字符串表解密 → Helper 池内联 → 控制流平坦化 → 常量折叠 / 死代码消除 → 死对象清理 → 语法修复 → 语义命名），每一步输出体积变化
- **格式化**：js-beautify（保留注释、不改变语义）
- 另有「识别指纹」「语法验证」；结果可选中复制、可保存为 `*.restored.js`；输入上限 2 MB
- **实现方式**：`acorn.js` / `jsrestore.js` / `js-beautify.js` 以 assets 打包，用内置 flutter_js 引擎执行；Node 版 jsrestore **源码零改动**，通过 CommonJS 包装 + `fs` / `path` / `process` / `console` 桩直接在引擎里运行
- 全程离线：不联网、不上传代码；反混淆与格式化都不会执行被分析的代码

### 文本编辑器支持 JS 格式化

- 「文本编辑器」把语言选成 `JavaScript`（或打开 `.js`）后，「格式化」按钮生效（底层同一套 js-beautify）

### 修复与改进

- **#843 搜索结果保持原序号**：新增「原始顺序」排序项并设为默认；搜索后结果不再重排，序号与未搜索时一致（便于按序号定位上下文），桌面端域名列表同步
- **#931 停止抓包卡死（缓解）**：给停止流程的关键等待（WS 推送服务停止 / 关闭系统代理 / 关闭代理服务器）加 5 秒超时保护，避免某一步永久阻塞导致状态无法复位、必须强杀进程
- **消除"假按钮"**：2 处列表项移除了空 `onTap`（点了没反应的假可点击）；桌面 SSL 开关行改为**整行可点**（点文字也能切换）

### i18n

- 新增 25 条词条（JS 还原 24 + 原始顺序 1），en / zh / zh_Hant 三份 ARB 键集合一致（各 787 键）

### 文档

- 新增内置教程 `docs/js_restore_guide.md`（实现方式 / 流水线 / 用法 / 联动 / FAQ），已在「使用文档」中心登记
- `docs/features_tips.md` 新增「JS 还原」一节

## v1.22.64 (2026-09-15)

### 代码健康：清理 9 个不可达文件（全局 + 移动端巡检）

巡检方法：扫描全部 `Xxx extends StatefulWidget/StatelessWidget`，与引用点做差集，再逐个 grep 复核。

删除（均无任何引用，合计约 1.4k 行）：

| 文件 | 原因 |
|---|---|
| `lib/ui/content/batch_operations_page.dart` | 批量操作页，与请求列表已有的多选批量删除 / 导出重复 |
| `lib/network/batch/batch_operations.dart` | 仅被上一文件引用，随之成为孤儿 |
| `lib/ui/component/har_manager_page.dart` | HAR 管理页，使用 file_picker 旧 API（`FilePicker.platform`），与 12.x 不兼容；且现有导出 HAR 已可用 |
| `lib/ui/mobile/setting/rule_visual_config.dart` | 规则可视化页，与「MCP 自动化 → 规则引擎」Tab 重复 |
| `lib/ui/component/context_menu_region.dart` | 通用右键菜单组件，无任何使用；项目已统一用 `showContextMenu` |
| `lib/event/{event,enhanced_scheduler,script_executor,rule_visual_config}.dart` | `lib/event` 下仅 `event_bus.dart` 被引用，其余 4 个为孤儿 |

保留 `lib/event/event_bus.dart`（被 `mcp_rule_engine` / `desktop` / `mobile` 引用）。

### 核实：#815「iOS 不作为默认路由」

结论：**平台限制，无法实现**。

- iOS 侧的路由接管本就由「**IP 层代理**」（`ipLayerProxy`）开关控制，**默认不接管默认路由**（走 `NEProxySettings` HTTP 代理）；
- 但 issue 的诉求是「某些 App 检测到 VPN 就闪退」——只要存在 `NEPacketTunnelProvider` 隧道，系统就视为 VPN 连接，App 可通过 `CFNetworkCopySystemProxySettings` / `getifaddrs` 检测到，**与是否接管默认路由无关**，无法规避。

## v1.22.63 (2026-09-15)

### 新功能：安全自检自定义规则支持导入 / 导出

- 「自定义规则」对话框新增「**导入 / 导出**」：导出为 `security-rules.json`（含 `type` / `version` 标识）
- 导入按「名称 + 范围 + 表达式」判重，重复的自动跳过；便于团队统一检测口径、跨设备迁移规则

### 修复与体验

- **修复桌面端「日志」入口打开空窗口**：工具箱调用 `MultiWindow.openWindow('日志查看', 'LogViewerPage')`，但 `multi_window.dart` 未注册该分支（同类页面都注册了，唯独它漏了）
- **工具箱信息组织重构**：原「其他」组塞了 16 个条目，现拆为「实用工具 / 运行与调试 / 抓包与重放 / 其他」四组
- **工具箱条目 i18n 化**：日志 / 性能监控 / API 端点 / QUIC 连接 / 发送队列 / 使用文档 / 开发工具 7 项此前为中文硬编码（英文界面会露中文），现全部接入本地化

### 核实结论（未实现 issue）

- 核实 #756（WebSocket 流量推送服务）、#225（黑白名单按接口过滤）、#401/#715（重放任务队列）、#825（外部代理 SOCKS5）、#133 分享加密——**均已在代码中实现**，无需重复开发
- 仍无法实现：`#815`（iOS 不作为默认路由，需改动 `PacketTunnelProvider` 的原生路由行为且须真机验证）、`#683` / `#560` / `#489` / `#874`（平台能力受限）

### i18n

- 新增 24 条词条（7 条规则导入导出 + 3 条工具箱分组 + 14 条工具箱条目），en / zh / zh_Hant 三份 ARB 键集合一致（各 762 键）

## v1.22.62 (2026-09-15)

### 新功能：安全自检支持自定义规则

- 安全自检页新增「**自定义规则**」：用关键词 / 正则匹配「请求 URL / 请求头 / 请求体 / 响应头 / 响应体 / 全部内容」，命中后按指定等级与建议列入报告
- 适用场景：内置规则覆盖不到的业务字段（自家接口的敏感字段名、内部测试标记、特定业务术语）
- 支持新建 / 编辑 / 启停 / 删除，本地持久化 `security_rules.json`；规则变更后报告即时重算
- 正则非法即时提示并拒绝保存；匹配依旧**只读**，仍然不发送任何请求
- 实现：`CustomSecurityRule` / `SecurityRuleTarget` / `SecurityRuleMatchType`（`lib/network/util/security_audit.dart`）+ `SecurityRuleStore`（`lib/network/util/security_rule_store.dart`）+ 页面内管理 / 编辑对话框

### i18n

- 新增 16 条词条，en / zh / zh_Hant 三份 ARB 键集合一致（各 738 键）

### 文档

- `docs/security_audit_guide.md` 新增「自定义规则」章节

## v1.22.61 (2026-09-15)

### 新功能：安全自检（被动安全基线核查）

- 工具箱新增「**安全自检**」：只读地分析**已抓到的**流量，按 高 / 中 / 低 / 提示 四级列出常见隐患，可筛选、可导出 Markdown 报告
- 覆盖 15 条规则：明文 HTTP 传输、URL / 请求体敏感参数、Cookie 缺 Secure / HttpOnly / SameSite、缺失安全响应头、服务器指纹、私钥 / 密钥泄露、PII、错误堆栈泄露、CORS 过宽、JWT alg=none / 无 exp、HTTP/1.0
- **边界：不发送任何请求**，不做注入探测 / 载荷投递 / 爆破 / 绕过——属于被动扫描（passive scan），不是主动漏洞利用
- 实现：`SecurityAuditor`（`lib/network/util/security_audit.dart`）+ `SecurityAuditPage`（`lib/ui/component/security_audit_page.dart`）
- 去重 + 规模保护（最多 5000 条请求；单条 body 超 512 KB 跳过内容检测）

### i18n

- 新增 16 条词条，en / zh / zh_Hant 三份 ARB 键集合一致（各 722 键）

### 文档

- 新增内置教程 `docs/security_audit_guide.md`（边界 / 规则清单 / 使用 / 实现 / 联动 / 导出格式 / FAQ），已在「使用文档」中心登记
- `docs/features_tips.md` 新增「安全自检」一节

## v1.22.60 (2026-09-15)

### 新功能：采集方案（借鉴 proxypin-mcp-workbench 的 Capture Plan）

- 工具箱新增「**采集方案**」：把一次抓包任务模板化——一组**包含 / 排除域名规则** + 一份**操作步骤清单**
- 「**应用到域名过滤**」一键把方案域名写入白名单 / 黑名单并启用、立即持久化，抓包只聚焦目标业务
- 支持新建 / 编辑 / 复制 / 导出（`*.capture-plan.json`）/ 删除；内置两个方案（移动端 App 抓包排查、接口清单梳理）
- 域名规则：`example.com` 精确、`*.example.com` 子域通配；非法写法保存时自动忽略
- 实现：`CapturePlanManager`（`lib/network/components/manager/capture_plan_manager.dart`）+ `CapturePlanPage`（`lib/ui/component/capture_plan_page.dart`），本地持久化 `capture_plans.json`，桌面多窗口 + 移动端入口齐备
- 边界：只做域名过滤与任务记录，**不自动操作目标 App / 不重放 / 不改写数据**

### i18n

- 新增 27 条词条（采集方案），en / zh / zh_Hant 三份 ARB 键集合一致（各 706 键）

### 文档

- 新增内置教程 `docs/capture_plan_guide.md`（定位 / 使用方法 / 实现细节 / 联动 / 边界 / FAQ），已在「使用文档」中心登记
- `docs/features_tips.md` 新增「采集方案」一节

## v1.22.59 (2026-09-14)

### 新功能：Mock 场景合集（借鉴 proxypin-mcp-workbench）

- 重写规则新增「**场景**」字段：编辑规则时可新建或选择已有场景名，同名规则归为一组
- 「请求重写」页新增「**Mock 场景**」入口：一键启用 / 停用整组、**仅启用**该组、重命名场景、移出分组（规则保留）
- 场景名写入 `request_rewrite.json` 的 `scenario` 字段，随规则导入 / 导出 / 分享一起流转；桌面端改动经多窗口刷新消息同步
- 实现：`RewriteScenarioDialog`（`lib/ui/component/rewrite_scenario_dialog.dart`）+ `RequestRewriteManager` 场景批量方法

### 新功能：导出 JSON（脱敏）

- 请求列表「导入 / 导出」新增「**导出 JSON（脱敏）**」：结构化 JSON（含 app / protocol / 字节数等字段），敏感查询参数自动打码，便于喂给 AI 或脚本

### i18n

- 新增 13 条词条（场景相关 + 导出 JSON），en / zh / zh_Hant 三份 ARB 键集合一致（各 678 键）

### 文档

- `docs/rewrite_guide.md` 新增「Mock 场景合集」章节；`docs/features_tips.md` 新增 2 节

## v1.22.58 (2026-09-14)

### 新功能：导出 CSV（脱敏）（借鉴 proxypin-mcp-workbench）

- 请求列表「导入 / 导出」对话框新增「**导出 CSV（脱敏）**」：一行一条请求，导出 `index/method/url/status/耗时/时间/内容类型/大小`
- 敏感查询参数（`token` / 密码 / 签名等）自动打码为 `***`

### MCP 抓包查询增强（借鉴黄鸟 MCP4HttpCanary）

- `get_recent_requests` 新增 `domain` / `since_time` / `end_time` / `page` / `compact`：支持域名与时间范围过滤、分页翻看更早数据、精简字段以降低 AI 读取 token
- 不带新参数时行为与旧版一致

### 黄鸟（HttpCanary 3.3.6）魔改包分析

- 结论：本体为破解高级版的 HttpCanary 3.3.6，另附一个 **Xposed 模块**（`assets/mcp_module.apk`）直读其数据库并在 18990 端口提供 MCP 服务，源码随包泄漏
- 已借鉴：AI 友好的抓包查询输出；**不借鉴**其攻击性工具（SQLi / XSS / WAF 绕过 / 渗透等），保持调试代理定位

### i18n

- 新增 1 条词条（`exportCsv`），en / zh / zh_Hant 三份 ARB 键集合一致（各 665 键）

### 文档

- `docs/features_tips.md`（新增 3 节）、`MCP_INTEGRATION.md`（工具说明）同步更新

## v1.22.57 (2026-09-14)

### 新功能：网络诊断 / 连接自检（借鉴 proxypin-mcp-workbench）

- 工具箱新增「网络诊断」（桌面端独立子窗口 / 移动端全屏页）：一屏显示 **代理服务状态、监听端口、本机局域网地址、根 CA 证书状态、MCP 服务状态**，并提供手机代理设置 / CA 信任 / 防火墙 / 端口区分等排障提示，关键项可一键复制
- 实现：`lib/ui/toolbox/network_diagnostics.dart`；入口 `lib/ui/toolbox/toolbox.dart`，桌面子窗口分支 `lib/ui/component/multi_window.dart`

### 借鉴 Reqable：cURL 导入健壮性

- 导入 cURL 时忽略**整行 / 行尾注释**（`#`、`//`，仅识别引号外；`https://`、`#fragment` 不受影响）
- 忽略 `-o/--output`、`--proxy` 等**带取值的参数**，避免其取值被误判为请求 URL
- 支持 `\` 续行的多行 cURL 粘贴

### 依赖升级（对齐最新）

- `file_picker` `^12.0.0-beta.7` → `^12.3.0`（改用稳定版）
- `permission_handler` `^12.0.1` → `^13.0.2`
- **`dynamic_color` 保持 `^1.7.0`**：2.x 已迁移到独立的 `material_ui` 包，其 `ColorScheme` 与 Flutter Material 并非同一类型，直接升级会导致 `DynamicColorBuilder` / `ColorScheme.harmonized` 编译失败，故暂不升级（待适配后再跟进）

### 文档

- `docs/features_tips.md` 新增：网络诊断、cURL 导入健壮性、依赖更新、上游 #489 说明、自动化两子系统区分

### 调研结论（不实现）

- **#489 QUIC 完整解码**：QUIC 强制 TLS1.3 + 客户端密钥保护，中间人无法还原 HTTP/3 帧；上游维护者明确回复「目前没计划支持非 HTTP 协议」。保持已有的 QUIC 元数据展示
- **小黄鸟（HttpCanary）**：仓库自 2024 年停更、仅存说明文档，无可借鉴的新实现
- **workbench（魔改版）其余可借鉴项**：抓包项目归档、采集方案、API 资产整理、脱敏数据导出（JSON/CSV）、Mock 场景合集、本机抓包按应用筛选、宽屏双列详情 —— 记录为后续备选

### i18n

- 新增 16 条词条（网络诊断相关），en / zh / zh_Hant 三份 ARB 键集合一致（各 664 键）

## v1.22.56 (2026-09-13)

### 功能补全：孤立管理页面接入 UI 入口

- **WebSocket 拦截管理 / WebSocket 规则管理**：`websocket_intercept_manager.dart`、`websocket_rule_manager_page.dart` 此前已实现但**无任何入口**（文件不可达、从未参与编译）；现接入偏好设置（桌面 / 移动）「高级功能」区（含全局拦截开关、规则增删改、匹配方式与方向）
- **MCP 定时任务管理**：`mcp_task_manager_page.dart` 接入「高级功能」区，管理 MCP 自动化定时任务（触发类型、URL 模式、动作、启停、手动执行）
- 上述 3 个页面完成 **i18n 全覆盖**（用户可见硬编码中文清零），新增 130 条词条；en / zh / zh_Hant 三份 ARB 键集合一致（各 648 键）；并补齐引用的缺失键（`createTask` / `mcpAutomationTasks` / `noAutomationTasks` 等）
- 修正 62 处 `AppLocalizations.of(context)` 漏写 `!`（可空类型），使这些页面可正常编译
- **移除死按钮**：桌面脚本设置页原「工作流」按钮会打开**空窗口**（多窗口工厂 `multiWindow()` 未处理窗口名 `ScriptWorkflowManagerPage`），已移除该按钮与 `openWorkflowManagerWindow()`；工作流引擎本身正常（`server.dart` 已接线 DAG 执行器 → `ScriptManager`），图形界面待按引擎实际 API 重建

### 修复

- **MCP 暂停帧内存泄漏**：`McpBridge._pausedWebSocketDetails` 此前只增不减（永不过期）；新增保留时长 10 分钟 + 上限 256 条的惰性清理 `_purgeExpiredPausedFrames`
- 修正 WebSocket 拦截 `pauseWebSocketMessage` 的误导性注释与文档，明确其为**观测 / 登记语义**（原始字节直通转发不受阻塞或改写）
- `abortWebSocketMessage` 的 `reason` 参数改回固定值，不再随界面语言变化

### 性能

- JSON 查看器：单个对象 / 数组默认最多渲染 1000 个子项，超出部分以「显示全部（共 N 项）」按钮展开，避免打开超大 JSON 时一次性构建海量 Widget 造成卡顿
- `JsonViewer` 由 `StatelessWidget` 改为 `StatefulWidget`：搜索匹配的 `matchKeys` 提升为 State 缓存，并防止 `postFrameCallback` 在同一帧内重复注册堆积

### 代码库规范化

- 删除 4 个**无法编译且不可达**的死代码文件：`ui/component/components.dart`（聚合导出指向不存在的文件）、`ui/component/code_generator_page.dart` 与 `network/util/code_generator.dart`（引用不存在的 `Request` 类型）、`ui/content/script_template_manager_page.dart`（依赖不存在的 `CodeEditorDialog`）
- 全库 339 个 Dart 文件所有 `import` 均可解析（断链由 2 处 → **0 处**）

### 上游 issue

- **#929 / #928**：正文均为乱码（`Tdorojo` / `Todocapa`）、0 评论、无复现步骤，无可修复内容，判定为无效 issue，未做改动
- 复核 #923 / #925 / #926 / #927 / #922 / #901 / #913 等均已在此前版本修复

### 平台限制说明（不实现，非缺陷）

- #683 鸿蒙 / HarmonyOS：Flutter 官方无 HarmonyOS 构建目标，需基于华为 ArkUI/DevEco 另建工程
- #489 QUIC / HTTP3 完整解码：需内核或协议栈级支持，当前仅做透传
- #560 Linux arm64 deb：Flutter 官方未提供 Linux arm64 预编译 SDK

## v1.22.55 (2026-09-13)

### 新功能 / 体验

- **搜索面板快速筛选 chips**：新增状态码分组 chips（2xx/3xx/4xx/5xx），一键写入状态码区间、再点一次取消；与协议 chips（HTTP/HTTPS/WS/SSE/HTTP1/H2）并排展示，与下方状态码区间输入框共用同一组条件，两者始终一致

### i18n 覆盖

- 搜索条件面板：排序字段（时间 / 耗时 / 状态码）与排序方向（升序 / 降序）由硬编码中文改为 l10n
- 移动端请求编辑器：请求/响应 Tab、请求体为空提示、请求体「数据类型」标签改为 l10n（移除 `localeName == 'zh'` 分支）
- 扫码相机授权提示改为 l10n（新增 `grantCameraPermission`）
- 新增词条：`sortBy` / `sortTime` / `sortAsc` / `sortDesc` / `grantCameraPermission` / `quickFilter` / `noMessageBody` / `dataType`（en / zh / zh_Hant 三份 ARB 同步）

### 性能

- 扫码页扫描线动画改为 `AnimatedBuilder` 局部重建，不再每帧 `setState` 重建整页（相机预览 + 底部按钮），降低低端机扫码时的掉帧

### 修复

- 修正 `lib/ui/desktop/setting/request_map.dart`、`lib/ui/mobile/setting/request_map.dart` 中 `logger.dart` 的相对导入多了一层目录（`../../../../`），该路径并不存在；统一改为 `package:proxypin/network/util/logger.dart`

### MCP 健壮性

- SSE 连接数上限 `maxSseConnections`（默认 32）：超过上限的新连接返回 `event: error` 后立即关闭，避免（尤其开启局域网访问后）未认证客户端无限建连耗尽资源
- Streamable HTTP 会话过期 `Timer` 保存引用并在 `stop()` 时统一取消，消除会话定时器泄漏

### 平台限制说明（不实现，非缺陷）

- **#683 鸿蒙 / HarmonyOS**：Flutter 官方无 HarmonyOS 构建目标，需要基于华为 ArkUI/DevEco 另建工程
- **#489 QUIC / HTTP3 完整解码**：需内核或协议栈级支持，当前仅做透传
- **#560 Linux arm64 deb**：Flutter 官方未提供 Linux arm64 预编译 SDK

## v1.22.54 (2026-09-13)

### 新功能：去缓存（Anticache）

- 新增「去缓存」开关（移动端 / 桌面端偏好设置）：请求发出前剥离 `If-Modified-Since` / `If-None-Match` / `If-Range` 并强制 `Cache-Control/Pragma: no-cache`，使服务端返回完整响应（避免命中 304 拿不到 body），便于抓包调试
- 实现：`lib/network/components/anti_cache_interceptor.dart`（`Interceptor`，priority 10，先于改写/脚本清理请求头），由 `server.dart` 按 `configuration.antiCacheEnabled` 注册；下次启动抓包生效
- 参考竞品：mitmproxy 的 anticache、Proxyman 的 No Caching

### 修复

- `Configuration.toJson` 补齐 `winTakeoverEnabled`（v1.22.52 遗漏，导致 Windows 接管开关不持久化）与 `antiCacheEnabled`

### 内置教程（docs/*）

- 常用功能技巧新增「去缓存（Anticache）」章节

## v1.22.53 (2026-09-13)

### 修复并接入：请求对比（Diff）

- 修复「请求对比」页面与对比算法引用了**不存在的 `Request` / `Response` 类型**（该文件因此从未被编译，也从未接入任何入口）——改用 `HttpRequest` / `HttpResponse`，并修正 URL / 方法 / 请求体 / 状态码 / 响应头等字段访问
- **接入请求列表**：多选（勾选）**恰好两条**请求后，工具栏出现「对比」按钮，桌面端与移动端一致；不足两条时提示
- 对比页去掉硬编码浅色底，改主题色（暗色模式可读）；请求体 / 响应体对比改用 `bodyAsString`
- 实现位置：`lib/ui/component/request_compare_page.dart`、`lib/network/util/request_comparator.dart`、`lib/ui/component/selection_action_bar.dart`（`onCompare`）
- 新增文案键：`compareNeedTwo`

### 内置教程（docs/*）

- 常用功能技巧新增「请求对比（Diff）」章节（入口、标签页、修复说明、实现位置）
- MCP 局域网访问章节保持（默认仅 127.0.0.1、tools/call 超时与 isError）

## v1.22.52 (2026-09-13)

### Windows 全局接管增强（上游 #577）

- 新增「Windows 接管增强」（分层代理，桌面端偏好设置开关）：在系统代理之外叠加 **WinHTTP 代理**（`netsh winhttp set proxy`）与**用户环境变量** `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY`（含小写），覆盖更多不走系统代理的应用（curl / git / node / 容器 / 部分沙箱内 CLI）
- 随抓包启动自动应用、抓包停止时自动还原；设置页实时显示 管理员 / Sandboxie / wintun.dll 检测状态
- 新增 `lib/network/util/windows_takeover.dart`；与代理启停联动（`lib/network/bin/server.dart`）
- 说明：真正覆盖"自带网络栈的应用（如 Sandboxie 内微信）"需内核级 TUN（WinTun 驱动 + 用户态协议栈），属原生/驱动级工程，==本版未启用==（避免误加路由导致断网）；已在文档标注现状与后续方案

### MCP 安全与健壮性

- **默认仅监听 127.0.0.1**（新增配置 `mcpAllowLan`，默认 false）；需局域网访问时在偏好设置显式开启并提示风险，切换后自动重启服务
- `capabilities` 不再声明 `roots`（roots 属客户端能力）；`tools/call` 增加参数校验（name 必填 / arguments 类型）、**120 秒超时保护**、工具内部 `{'error': ...}` 统一标记 `isError`
- MCP 文档与外部 Python 网关默认端口统一为 `9010`（此前文档写 17777，与实际不符）

### 性能

- `HttpMessage.getBodyString` 缓存默认（UTF-8）解码结果，避免大响应体被重复解压 / 解码

### 构建

- 维持多平台产物：Android 4 ABI APK / Windows x64 zip / macOS zip / iOS 未签名 ipa / Linux amd64 deb

## v1.22.51 (2026-09-13)

### 构建修复：Windows 桌面产物

- 修复 Windows 构建失败：第三方插件 `permission_handler_windows` 仍使用已废弃的 `<experimental/coroutine>`，在 `windows-latest`（新版 MSVC / VS18）上被升级为硬错误
- 处理：Windows 构建改用 `windows-2022` runner，并加编译器抑制宏 `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`
- 结果为 v1.22.50 全部内容 + 补齐 **Windows** 产物：`proxypin-<ver>-windows-x64.zip`
- 至此随 tag 发布的产物覆盖：**Android（4 ABI APK）/ Windows / macOS / iOS（未签名 ipa）/ Linux（amd64 deb）**

## v1.22.50 (2026-09-13)

### 国际化（i18n）覆盖

- 新功能界面此前为中文硬编码，现全部接入 l10n（`app_en` / `app_zh` / `app_zh_Hant` 三套，其余语言自动回退英文）：
  - WebSocket 流量推送设置区块与订阅端口对话框（上游 #756 后续）
  - 重写规则加密分享：分享方式 / 设置口令 / 输入口令对话框与导入导出调用点（上游 #133）
  - 上游代理协议（HTTP / SOCKS5）标签（上游 #825）
  - 便携模式提示（上游 #285）
- 补齐历史遗留缺失键：`selectAll`、`profileDownload`；本轮新增 40 个键
- 说明：构建期 `generate: true` 由 gen-l10n 自动再生成 `app_localizations*.dart`

### 反人类操作与长文本 / 点击区域统一梳理

- 搜索栏「上一个 / 下一个」点击热区由 17dp 扩大到 44dp（`InkWell` + padding，圆形涟漪）
- 多选操作栏高度 36→44dp，避免压扁 IconButton 的默认触摸高度
- 重写规则列表（移动端）行高 45→48dp、开关列宽 35→48dp、缩放 0.65→0.8，开关更易点中；名称 / URL / 类型列补 `maxLines:1 + ellipsis`
- 重写规则列表（桌面端）名称 / 类型列补 `ellipsis`，开关列加宽，与移动端对齐
- 重写规则表头列宽适配本地化文本并加省略号；语言 / 内存清理下拉框加 `isExpanded: true`
- 通用确认对话框内容改为可滚动，长文件名 / 长规则名不再溢出
- 脚本工作流页脚本预览底色改用主题色 `surfaceContainerHighest`，修复暗色模式浅底浅字不可读；依赖 / 变量 Chip 改用 `primaryContainer` / `secondaryContainer` 语义色

### 隐藏 Bug 修复（代码审查发现）

- HTTP/1 头解析：`_splitHeader` 处理「`X-Foo:` 无值」与「无冒号行」时越界 / 空列表，修复 `RangeError`（`http_parser.dart`）
- HTTP/2：DATA 帧在流上下文缺失（HEADERS 未到或被 RST 清理）时解包崩溃，改为直接转发原始帧（`h2_codec.dart`）
- 通道分发：`remoteChannel!` 空解包崩溃，改为判空丢弃并记录日志（`channel_dispatcher.dart`）
- `HostAndPort.of`：端口 `int.parse` 改 `int.tryParse` 并校验范围，非法端口回退默认端口（`host_port.dart`）
- 响应处理器 `Completer` 二次 `complete` 抛未捕获异常，改为 `isCompleted` 守卫（`http_client.dart`）
- 请求屏蔽配置 `flushConfig` 未 `await` 写盘，可能静默丢失规则；`BlockType.nameOf` 未知类型崩溃，补 `orElse`
- 关键字高亮恢复时原地改 Map 不触发 `ValueNotifier`，改为整体替换（`keyword_highlight.dart`）
- `Strings.splitFirst` / `trimWrap` 按 pattern / wrap 实际长度切分（`lang.dart`）
- AI 分析文本截断按 UTF-16 代理对边界处理，避免半字符乱码（`ai_analyzer.dart`）
- `ip.dart` 移除遗留调试 `main()`，网卡为空时回环兜底，避免 `StateError`

### MCP 服务修复

- **配置资源脱敏**：`resources/read proxypin://config/current` 不再返回 `aiApiKey`、mTLS 私钥路径、上游代理口令（新增 `Configuration.redactSecrets`）；配置文件刷新日志同样脱敏
- **`/messages` 端点**：修复 JSON-RPC 批量数组导致的崩溃；支持批量，非对象请求返回标准 `-32600`
- **`/mcp` 端点**：批量结果为空返回 202；非对象 JSON 返回标准 `-32600` 错误信封

### 上游 issue 核对

- 已修并核对：#923（URL 编码中文域名 → Punycode）、#925（重写规则正则多分组）、#927（Gradle 8.14 / AGP 8.11.1 / Kotlin 2.2.20 已达标，file_picker 12 API 兼容，CI 构建通过）
- 本轮实现：#926（重写规则列表最新显示在最上面；仅改显示顺序，不影响匹配语义）
- #928 标题为 "Lilbo"，内容无意义，不予实现
- #560：Linux `.deb`（amd64）已产出；本轮补齐 **Windows / macOS / iOS** 产物

### 多平台产物（上游 #560）

- 新增 `.github/workflows/build-desktop.yml`：Windows（`proxypin-<ver>-windows-x64.zip`）与 macOS（`proxypin-<ver>-macos.zip`，含 ProxyPin.app）
- 新增 `.github/workflows/build-ios.yml`：iOS 未签名 `.ipa`（`flutter build ios --no-codesign` 后按 Payload 结构打包）
- 三个工作流与 APK 流程相互独立（`continue-on-error`），任一平台失败不影响 Android 产物

## v1.22.49 (2026-09-12)

### 上游 issue 落地审计（核查"做了的是否真的做了"）

对历史 CHANGELOG 声称已实现的 29 项上游 issue 做了**存在性 + 接入点 + 入口可达性**三层核查（脚本化 26 组 / 60 项检查，全部通过），并逐项复核调用链与生效条件。审计发现两处"声称已修、实际未生效"的问题，本轮修复：

- **详情页响应自动刷新（上游 #922）**：此前**只有 WebSocket 消息到达时**才刷新详情页，普通 HTTP 响应到达时不会刷新——请求在详情页打开期间才完成时，页面仍停留在"未响应"。现移动端 / 桌面端 `onResponse` 均按 `requestId` 比对"当前详情页正在看的那条请求"并即时刷新
- **桌面端「备份管理」列表恒空**：写入端（`Configuration` 自动备份）落在数据目录 `~/.proxypin/proxypin_backups`，而桌面备份页读取的却是 `~/proxypin_backups`（直接读 `HOME/USERPROFILE`）——路径不一致导致看不到任何备份、"打开备份目录"也打不开；便携模式下还会跳出程序目录。现统一走 `FileRead.homeDir()`，与写入端及移动端一致（便携模式同样生效）
- **#902 保存图片**复核确认实现正确（iOS 存相册 / Android 写临时文件后调起系统分享 / 桌面 FilePicker），此前审计脚本把路径写成了 `panel.dart` 导致误报，已修正为 `body.dart`

### 反人类操作与联动完善

- **WebSocket 推送端口改为图形化可修改**（上游 #756 后续）：端口此前只能改配置文件，12080 被占用时开关会启动失败并自动回滚，用户无路可走；现新增「订阅端口」入口（移动端 / 桌面端一致），校验 1024~65535，保存后**立即生效**（服务已开启则自动重启监听，失败同步回滚开关并提示）
- **便携模式可见化**（上游 #285 后续）：放置标记文件后界面此前毫无反馈，无从确认是否生效；现桌面设置页在便携模式下显示「便携模式已启用」并给出实际数据目录
- **推送开关状态实况**：开关打开但抓包未运行时，副标题明确提示「已开启，但抓包未运行：启动抓包后自动监听 ws://…」，不再让人误以为正在监听
- 新增共用对话框 `lib/ui/component/ws_traffic_port_dialog.dart`（双端复用，避免两份实现漂移）

### 内置教程完善（docs/*）

- 常用功能技巧补充：WS 推送**端口修改**方式、**便携模式**的识别与数据目录、**备份目录**的实际位置与查看方式

## v1.22.48 (2026-09-12)

### 修复与完善：Linux 安装包（上游 #560）

- 修正 `.github/workflows/build-deb.yml`：补齐 `libayatana-appindicator3-dev` 依赖（`tray_manager` 插件的 Linux 前置依赖，缺失会导致 CMake 直接失败）
- 实测结果：Linux 桌面版构建 + `.deb` 打包**全流程通过**，产物 `proxypin-<version>-linux-amd64.deb`（约 12 MB），tag 发布时自动附加到对应 Release
- 架构范围：**当前仅提供 amd64**——Flutter 官方尚未发布 Linux arm64 的预编译 SDK（`flutter-action` 在 arm64 runner 上无法安装 SDK），arm64 需等待上游工具链支持；矩阵中已保留 arm64 位置与注释，届时补回一行即可
- 独立性：该工作流与 APK 流程完全分离（含 `continue-on-error`），Linux 侧任何异常都不会影响 Android 产物发布

### 内置教程完善（docs/*）

- 常用功能技巧新增「Linux 安装包」说明（获取方式、架构、依赖、实现位置）

## v1.22.47 (2026-09-12)

### 新增：Linux 安装包（arm64 / amd64，上游 #560）

- 新增独立工作流 `.github/workflows/build-deb.yml`：推送 tag 时构建 Linux 桌面版并打包 `.deb`，自动附加到对应 Release
  - 双架构矩阵：**arm64**（`ubuntu-24.04-arm` runner）与 **amd64**
  - 包内容：`/opt/proxypin`（Flutter bundle）+ 桌面快捷方式；声明依赖 `libgtk-3-0`、`ca-certificates`
  - 与 APK 构建流程**完全独立**（`continue-on-error` + 独立 workflow 文件）：即使某个架构的桌面构建失败，Android 产物照常发布，不会出现"因 Linux 失败而整版不发"的情况
- 说明：Linux 桌面链路为实验性支持，首次接入后按 CI 结果迭代；产物只在 tag 构建时上传 Release

## v1.22.46 (2026-09-12)

### 新功能：外部代理支持 SOCKS5（上游 #825）

- 「设置 → 外部代理」新增**协议选择**：HTTP 代理（HTTP CONNECT 隧道，与旧版行为一致）/ **SOCKS5**
- SOCKS5 完整实现 RFC 1928：方法协商（无认证 / 用户名口令）→ RFC 1929 认证 → CONNECT（自动区分 IPv4 / IPv6 / 域名地址类型），并读取 BND.ADDR/BND.PORT 完成握手
- 失败信息明确：版本不符、认证被拒、各错误码（主机不可达 / 连接被拒绝 / 网络不可达 等）均有中文说明
- 实现：新增 `lib/network/util/socks5.dart`（基于 `RawCodec` 的原始字节握手状态机，握手完成即恢复原解码器/处理器）；`HttpClients.connectRequest` 按 `ProxyInfo.protocol` 分流；移动端与桌面端外部代理对话框均加协议选择
- 兼容性：`ProxyInfo.protocol` 默认 `http`，旧配置零感知；顺手去掉了 `ProxyInfo.toString()` 中的口令输出（避免日志泄露凭据）

### 内置教程完善（docs/*）

- 常用功能技巧新增「外部代理（上游代理链）」章节：两种协议、SOCKS5 流程、失败提示、实现位置

### 上游 issue 比对

- 本次实现：#825
- 仍未实现：#560（arm64 deb 安装包——需先补齐并验证 Linux 桌面构建链路，见下一轮评估）、#683（鸿蒙系统支持——依赖 Flutter 对 HarmonyOS 的官方构建支持，当前上游生态尚不具备，属平台级限制）

## v1.22.45 (2026-09-12)

### 新功能：重写规则加密分享（上游 #133）

- 导出重写规则时可选 **「明文分享」或「加密分享」**：加密需设置口令（≥4 位，二次确认），生成 `.enc` 文件；接收方导入时输入相同口令才能还原
- 算法：**PBKDF2-HMAC-SHA256（50,000 次）派生密钥 + AES-256-GCM 认证加密**——口令错误或文件被改动会在解密阶段被认证标签拦下并给出明确提示；内容前缀 `PROXYPIN-ENC1:` 自动识别，**明文格式完全不变、双向兼容**（旧文件仍可直接导入）
- 实现：`lib/utils/secure_share.dart`（加解密）、`lib/ui/component/share_crypto_dialogs.dart`（分享方式/口令对话框）；移动端与桌面端重写规则页均已接入（桌面端导入扩展名白名单补充 `enc`）
- 说明：#133 中「限制使用设备数量」属服务端授权范畴，离线分享场景以「口令保护」作为等价安全手段（口令即访问控制，不联网校验）

### 新功能：便携版（桌面端，上游 #285）

- 在可执行文件同目录放置 `portable`（或 `portable.txt`）标记文件即进入**便携模式**：配置、CA 证书与私钥、脚本、历史等数据全部写入程序目录下的 `proxypin_data/`，整目录拷贝即可携带全部设置与证书
- 未放置标记时行为完全不变（数据仍在系统应用支持目录）
- 实现：`lib/storage/path.dart` 新增 `isPortable()` / 便携解析；并统一配置目录（`file_read.dart`）、证书与私钥（`crts.dart`）、历史（`histories.dart`）、请求阻断与网络条件配置的数据根目录，保证便携模式下**数据无遗漏**

### 已具备等价能力的诉求

- **#815「不作为默认路由」**：现有**应用白名单**即等价能力——只勾选需要抓包的应用，其余流量不经过 VPN（不做默认路由）；本轮补充文档说明与实现注释，无需新增开关

### 内置教程完善（docs/*）

- 常用功能技巧：重写规则补「加密分享」（算法、用法、兼容性说明）；新增「便携版（桌面端）」与「抓包范围控制（不接管全部流量）」两节

### 上游 issue 比对

- 本次实现：#133、#285；确认 #815 已有等价能力
- 仍未实现：#560（arm64 deb 安装包）、#683（鸿蒙系统支持——需平台适配与构建目标）、#825（外部代理 SOCKS5）以及更早的架构类需求

## v1.22.44 (2026-09-11)

### 新功能：WebSocket 实时流量推送（上游 #756）

- **偏好设置 → WebSocket 流量推送**：外部工具 / AI 助手可通过 WebSocket 实时订阅抓包流量，作为 MCP 之外的第二条轻量集成通道
  - 服务端：`WsTrafficServer`（`lib/network/components/ws_traffic_server.dart`，实现 `EventListener`），随代理启动/停止，**开关切换即时生效**（无需重启抓包）
  - 推送消息：`config` / `request` / `response` / `message`（含方法、URL、状态码、耗时、大小；WS 帧含方向与文本载荷，截断至 4KB）；为避免洪泛**不含请求/响应 body**
  - 客户端命令：`ping` / `status` / `list_histories` / `get_history`（历史查询可用开关关闭）
  - 连接即下发配置；设置页副标题实时显示**已连接客户端数**；内置 30 秒心跳，断线自动清理
  - 配置项：`wsTrafficEnabled`（默认关）、`wsTrafficPort`（默认 12080）、`wsTrafficHistoryEnabled`（默认开）

### 新功能：脚本捕获 WebSocket 帧（上游 #722）

- 脚本新增 `onWebSocket(context, ws)` 钩子：**每个 WS 帧解析完成后逐帧回调**，解决旧版「脚本拿不到 WS 数据、rawBody 为空」的问题
  - 可读字段：`url` / `direction`（client_to_server、server_to_client）/ `opcode` / `binary` / `payload`（文本）/ **`rawBody`（字节数组，文本与二进制帧都有）** / `length` / `time`
  - **只读捕获**：不参与转发字节，因此不影响连接稳定性；需要改包请用「WebSocket 拦截」（两者可配合）
  - 仅在脚本中声明 `function onWebSocket(...)` 时才逐帧派发，未声明的脚本零开销；钩子检测用正则匹配函数声明并做 3 秒缓存，避免每帧读盘
  - 实现：`script_manager.dart`（`hasWebSocketHook` / `dispatchWebSocketFrame`） + `websocket_handle.dart`（帧解析后异步派发）

### 内置教程完善（docs/*）

- 脚本开发指南新增「捕获 WebSocket 帧（onWebSocket）」章节（字段表、触发时机、声明要求、与 WebSocket 拦截的配合、实现位置）
- 常用功能技巧新增「WebSocket 流量推送」完整条目（入口、连接地址、消息格式、命令、心跳、实现）
- 功能总览：自动化表新增「WebSocket 流量推送」；脚本行标注 onWebSocket 能力

### 上游 issue 比对

- 本次实现：#756、#722
- 仍未实现（后续排期）：#133（重写规则分享加密与设备数限制）、#825（外部代理 SOCKS5）、#815（非默认路由选项）、#683（鸿蒙）、#560（arm64 deb）、#285（便携版）

## v1.22.43 (2026-09-11)

### 新功能：发送队列（重放任务中心）

- **工具箱 → 发送队列**（上游 #715「查看准备重放的请求列表」+ #401「定时重放任务列表」）：汇总本次运行期间的全部重放任务
  - 每个任务展示：状态徽标（等待发送 / 发送中 / 已完成 / 已取消）、进度条（已发送/总数）、成功 / 失败 / 重试统计、创建与计划时间、最近错误、**待发送请求清单**
  - 单请求多次、批量重放、定时重放三类均已接入：==定时重放不再因关闭对话框而"失联"==，可随时回到队列查看进度
  - 支持单条移除与"清除已结束"，仅保留最近 50 条（内存态，重启清空）
  - 实现：`lib/network/components/repeat_task_manager.dart`（任务登记 + `ValueNotifier` 变更通知）、`lib/ui/component/repeat_queue_page.dart`（列表页）；桌面端为独立子窗口，移动端为页面

### 增强：域名过滤支持 URL / API 级（上游 #225）

- 白名单/黑名单除域名外，现可直接填写 **URL 路径**：如 `api.example.com/v1/` 只抓该接口、`.*\.example\.com/order/.*` 精确到业务路径
- 匹配目标由 `host` 扩展为 `host + path`（`HostFilter.filter(host, path:)`），代理层在请求与响应两处按 `pathAndQuery` 判定；纯域名规则行为与旧版完全一致
- 过滤页说明文案同步更新（简中 / 繁中 / 英文）

### 增强：脚本加载第三方 JS 库（上游 #719）

- 脚本内新增全局 `require(url)` / `loadLibrary(url)`：按 URL 拉取并执行第三方库，返回其 `module.exports`
  - 以 CommonJS 风格包装执行（提供 `module` / `exports` / `require` / `globalThis` / `console`），也兼容把 API 挂到全局的库
  - 同一 URL 只拉取一次并缓存；钩子写为 `async` 后 `const lib = await require('…')` 即可使用
  - 实现：`lib/network/components/js/require.dart`，在运行时初始化时注入

### 内置教程完善（docs/*）

- 脚本开发指南新增「加载第三方 JS 库（require）」章节（用法、CommonJS 约定、缓存与失败处理、实现位置）
- 常用功能技巧新增「发送队列」条目；域名过滤条目补充 URL 路径用法；脚本条目补充 require
- 功能总览工具箱表新增「发送队列」；脚本行标注 require 能力

### 上游 issue 比对

- 本次实现：#715、#401、#225、#719
- 仍未实现（后续排期）：#133（重写规则分享加密与设备数限制）、#722（脚本捕获 WebSocket 数据）、#756（WebSocket 实时流量推送服务）、#715 之外的历史需求（#825 SOCKS5、#815 非默认路由、#683 鸿蒙、#560 arm64 deb、#285 便携版）

## v1.22.42 (2026-09-11)

### 修复：下拉长文本显示不完全（根治，含全局同类排查）

- **规则引擎条件行**：「字段」「运算符」下拉选中长文本（如「请求 Content-Type」）此前只显示前半截（如「请求 Co」）且无省略号、无法查看剩余内容。根因不是宽度分配，而是 `DropdownButtonFormField` 的选中值显示区高度固定，长文本自动换行后第二行被硬裁剪 → 本次改为：**字段与运算符各占整行**（并排的窄框不再压缩长字段）、`isDense` 收紧内边距、菜单项与选中项统一 `maxLines: 1 + TextOverflow.ellipsis + softWrap: false`（单行省略，绝不换行裁切）、并为每个选中值加 **长按/悬停 Tooltip** 查看完整文本
- **同类彻底排查（全库 72 个下拉）**：逐一核对每个下拉的选中值渲染与菜单项高度，修复以下漏网点
  - 规则引擎：条件类型/字段/运算符/值/操作类型/事件类型/优先级，以及工作流节点脚本名、Prompt 名称、脚本·工具·工作流选择器（`_optionDropdown`）——全部补 `isExpanded + isDense + 单行省略 + Tooltip`
  - 搜索条件面板的自绘 `DropdownMenu`：菜单项 `PopupMenuItem` 固定高 35 会裁掉换行文本 → 改单行省略；菜单加 `constraints(minWidth: 200)` 保证长选项完整显示；选中值加单行省略 + Tooltip
  - 请求编辑器「数据类型」下拉（移动/桌面）、请求阻断「类型」下拉（移动/桌面）：补单行省略与 `isExpanded`
  - 加密封装填充方式下拉（PKCS7 / ZeroPadding）、IP 直连下拉（host:port）：补单行省略
  - 其余下拉经核对选项文本较短或已 `isExpanded`，无同类实害

### 修复：上游 issue 落地

- **#901 多值响应头（Set-Cookie）合并转发**（脚本层补齐）：脚本上下文中 `headers` 此前经 `toMap()` 用 `join(";")` 合并多值——而分号正是 Set-Cookie 的参数分隔符，合并后被客户端当成单条 Cookie 解析，导致会话 Cookie 丢失。现改为：**多值头输出字符串数组、单值头保持字符串**（回写侧本就支持数组，单值脚本零改动），既有脚本完全兼容
- **#915 请求列表选中状态消失**（桌面）：单击选中此前记在行 State 实例字段中，新请求从列表头部插入会触发 ListView 元素回收重建，State 销毁即丢高亮。现改为**按 `requestId` 记录选中**，元素无论如何回收重建都能恢复高亮；同时保留「自动阅读」标记逻辑不变
- **#894 批量导出计数失真**（Android）：导出「响应」时无响应的请求不产生文件，此前却仍计入成功数，出现「导出成功：N 请求」而实际文件为 0 的误导提示 → 现仅对真正写出文件的请求计数

### 内置教程完善（docs/*）

- 脚本指南补充「多值响应头语义」：`headers` 中多值头（如 `Set-Cookie`）为数组、单值为字符串，给出读取/改写示例
- 规则引擎指南补充条件行下拉的字段清单与长文本查看方式（长按 Tooltip）
- 功能总览同步「请求列表选中」「批量导出」行为说明

### 上游 issue 比对

- 已实现并核对通过：#913（IP 直连证书 iPAddress SAN）、#920（剪贴板导入导出）、#900（内置通用变量）、#925（正则分组）、#916（数字搜索——重构后的匹配链路已支持）、#894、#901、#915
- 仍未实现（排队/受限于平台能力）：#915 之外的 #133（重写规则加密与设备数限制）、#225（黑白名单 API）、#401（定时重放任务列表）、#715（待发送请求队列）、#719（脚本加载第三方库）、#722（脚本捕获 WebSocket）、#756（WebSocket 流量推送服务）、#874/#825/#815/#683/#560/#285 等平台与架构类需求

## v1.22.41 (2026-09-10)

### 修复与完善

- **规则引擎（条件行）下拉长文本显示不完全**（移动端/桌面端共用弹窗）：条件行中「字段」「运算符」两个下拉原为 1:1 均分宽度，选中长文本（如字段「请求 Content-Type」）换行后被输入框高度裁剪——调整为 ==字段 60% / 运算符 40%== 的弹性分配，最长字段单行完整显示，不再裁切（本修复随 v1.22.40 构建发布，此处补记）
- **QUIC 会话页防御**：连接 ID 不足 6 个十六进制字符时不再触发 `substring` 越界（极短 DCID 场景安全显示）
- 全库排查同类下拉隐患：其余下拉或已 `isExpanded`、或宽度自适应、或选项本身较短，无同类实害

### 内置教程完善（docs/*）

- 新增「QUIC 连接」完整教程节：使用入口、三端实现链路（Kotlin 抄送 → Dart 监听 → 解密解析）、能力边界、与「拦截 QUIC」的联动、开发细节（含 TCP 通道缘由）
- 新增「请求口令分享」节：`PROXYPIN1:` 口令压缩/粘贴导入原理与用法
- AI 分析指南补充「多会话管理」（对话列表新建/切换/删除、清除当前对话）
- 勘误：悬浮球体积 76dp → ==36dp==（与实现一致）

### 说明

- 上游 issue 比对本轮未新增实现项，未实现清单见功能总览末尾链接的讨论记录（#915/#133/#225/#401/#715/#722/#756/#719 及 #901 脚本层部分）


## v1.22.40 (2026-09-09)

### 新功能：QUIC 连接元数据展示（上游 #489 全链路打通）

- **数据捕获（Kotlin VPN 层）**：VPN 抓包运行时，`ConnectionHandler` 会把 UDP:443 的**首个数据包**抄送到本机（同一源地址 30 秒节流，避免洪泛）；与"拦截 QUIC 回落 TCP"互不干扰——回落开启时照常回落抓明文，同时仍可记录 QUIC 连接
- **解析管线（Dart）**：新增 `QuicProbe`（`ProxyServer` 本机 TCP 监听 41745，VPN 层经 TCP 即发即断抄送首包，避免跨语言 UDP 依赖）：QUIC v1 长头解析 → Initial 解密（v1.22.38/39 已交付的密钥派生 + Header Protection + AES-GCM）→ 帧扫描 → **ClientHello 的 SNI 域名提取**（手写 TLS 1.3 ClientHello 解析，失败安全忽略）
- **展示页**：工具箱 → 新增「QUIC 连接」入口（桌面/移动端均支持）——列出每个 QUIC 会话：**SNI 域名 / QUIC 版本（0x1 = v1）/ 源地址 / 首次时间 / 连接 ID / 包与帧统计**；空态与页内说明诚实标注能力边界（HTTP/3 业务明文需 TLS 密钥，无法解密，要看明文请开启「拦截 QUIC」回落）
- 配置开关：偏好设置可关「QUIC 探测」（Configuration.quicProbeEnabled，默认开）

### 说明

- 常见抓不到 QUIC 连接的原因：目标应用默认走 TCP/HTTP2（多数应用如此），仅使用 QUIC 的应用（部分视频/游戏/Google 系）会出现；可临时关闭「拦截 QUIC」重开抓包让 QUIC 流量放行并记录
- QUIC 会话列表为内存态，抓包停止/清空后重置

## v1.22.39 (2026-09-09)

### 上游 #489：QUIC 管线推进

- **QUIC v1 包解析与 Initial 解密器**：新增 `lib/network/util/quic/quic_packet.dart`——
  - 长头包明文字段解析（版本 / DCID / SCID / token）
  - Header Protection 去除（RFC 9001 §5.4：AES-ECB(hp, sample) 掩码解出包号长度与包号）
  - Initial payload AES-128-GCM 解密（nonce = iv ⊕ 包号；标签校验失败安全返回 null）
  - QUIC 帧遍历：CRYPTO 帧数据拼接（内含 TLS ClientHello 前缀，供上层提取 SNI/会话元数据）
- 至此 #489 管线组件齐备：密钥派生（v1.22.38，RFC 9001 A.1 向量校验）→ 包解析/解密 → CRYPTO 数据；
  下一步为把 VPN/root 管道中捕获的 UDP:443 首包接入该管线并展示 QUIC 连接（SNI/版本/帧统计）
- **Root 系统级回落**（v1.22.38 随附）：偏好设置可一键 iptables 丢弃 UDP:443（重启失效，可停用）

### 说明

- 完整 QUIC 业务解密（HTTP/3 请求响应明文）受限于 TLS 1.3 密钥获取，任何抓包工具（Reqable/Clash 等）
  均无法在无密钥注入时解出应用层明文；本实现的目标是**QUIC 连接级元数据**（可识别"哪个 App 在走 QUIC、
  访问哪个域名、建立多少连接），已抓包回落 TCP 仍可看完整请求明文

## v1.22.38 (2026-09-08)

### 界面优化

- **API 端点页统计卡片重设计**：三个卡片从"纯数字+灰字"改为莫奈风——各自带圆角图标徽标（总端点/资源组/总请求），颜色分别取主题 primary/tertiary/secondary，浅色描边+surface 底，深浅模式自适应

### 新功能（上游 #489：QUIC 的 root 能力）

- **系统级 QUIC 回落（Root + iptables）**：偏好设置 → 拦截 QUIC 开关下方新增「启用/停用」——用 root 在系统层 `iptables -I OUTPUT -p udp --dport 443 -j REJECT`，比 VPN 层拦截更早生效（对更多应用起效），一键停用清理规则；执行结果即时反馈
- **QUIC v1 Initial 密钥派生库**：新增 `lib/network/util/quic/quic_keys.dart`——按 RFC 9001 §5.2 / RFC 8446 §7.1 实现 Initial 密钥派生（HKDF-Extract/Expand-Label），**内置 RFC 9001 附录 A.1 官方测试向量自检**（5 组值逐一比对），为后续在 VPN/root 管道中解密 QUIC Initial、提取 SNI/会话元数据铺路

## v1.22.37 (2026-09-08)

### 问题修复

- **请求重写规则正则分组匹配失效**（上游 #925）：修改请求/响应体采用正则替换时只支持 `$1`，`$2`~`$9` 原样输出不替换（工具箱正则却支持多组）。现完整支持 `$0`~`$9` 分组引用（`$0`=整段匹配），并按从大到小替换避免 `$1` 误伤 `$10` 之类文本
- **AI 分析切换会话时消息错乱**：发送请求期间若切换会话，AI 回复会落入新会话；现在发送时锁定原会话对象，异步等待期间无论怎么切换/删除，本次对话始终归属发起时的会话
- **日志页空转优化**：实时轮询 500ms 但内容无变化时不再重建列表（筛选条件变化仍立即刷新）

## v1.22.36 (2026-09-08)

### 问题修复

- **日志管理页真正有日志（决定性根因）**：logger 2.x 默认过滤器 `DevelopmentFilter` 的判定逻辑整段包在 `assert` 里——release 构建中断言被剥离后恒为 false，导致**所有运行日志在正式包中被静默过滤**（此前"选全部也没有一条"）。已显式改用 `ProductionFilter(level: debug)`，release 同样完整记录；配合 500ms 实时刷新，日志页现在能实时看到全部运行日志
- **悬浮球默认位置下移**：初始位置从贴顶 260px 改为屏幕高度约 1/3 处

### 新功能

- **请求口令导入 / 导出（上游 #920）**：请求列表批量操作 →「导出」对话框升级为「导入 / 导出」——
  - `复制口令`：把所选请求（含响应）压缩为一段 `PROXYPIN1:` 口令文本，粘贴分享给他人
  - `从剪贴板导入口令`：粘贴口令一键还原请求到当前列表（含响应），可继续查看/重放
  - 口令采用 JSON+gzip+base64 紧凑编码，导入时自动分配新请求 ID 避免冲突
- **桌面应用图标默认莫奈配色**：自适应图标背景改为莫奈粉彩紫→天蓝柔和渐变、前景 ∞ 图形重绘为白色（五个密度全部重绘）；系统「主题图标」仍使用单色 monochrome 图层随壁纸取色

### UI 优化

- **日志页底部统计条适配主题**：不再硬编码白底（深色模式下刺眼），改随主题 surface；统计数字按级别配色（总数=主题色 / 调试=灰 / 信息=蓝 / 警告=橙 / 错误=红）

## v1.22.35 (2026-09-06)

### 问题修复

- **悬浮球"关闭后进设置页自动启用"**：根因是悬浮球面板原生直写偏好文件时，Dart 侧 SharedPreferences 内存缓存不会自动失效，设置页读到旧的 enabled=true 又把服务拉起；现在面板内所有修改（关闭/换色/透明度/贴边）都会通知 Flutter 同步缓存，设置页展示与面板操作始终一致
- **设置页不再作为悬浮球服务启动点**：服务启动收敛为"冷启动自动恢复（开启过）+ 手动打开开关"两条路径，页面只读状态

### 优化

- **日志管理页实时显示**：刷新周期 2 秒 → 500 毫秒，新日志即时上屏；停留在顶部附近时自动回顶展示最新日志

### 说明

- 上游 #577（Windows TUN 接管 Sandboxie 流量）、#489（QUIC 完整抓包解码）属系统内核/协议级工程，超出当前可交付范围；已有替代方案：Android 端 VPN 抓包模式（TUN 转发）+ QUIC 回落强制走 HTTP/2 抓取；#920（剪贴板口令）规格待确认

## v1.22.34 (2026-09-06)

### 问题修复

- **悬浮球收纳真正生效**：根因是悬浮窗窗口默认受屏幕边界约束，收纳时 2/3 移出屏幕的负坐标被系统 clamp 回屏内（看起来"没收纳"）；为窗口添加 `FLAG_LAYOUT_NO_LIMITS`（允许布局超出屏幕）后，贴边开关开启时 3 秒无操作即正确藏入边缘 2/3 并降低透明度
- **AI 分析页标题完整显示**：「AI分析」不再带省略号；「清除当前对话」并入对话列表面板（新建对话旁），AppBar 减负后标题完整可见

### 说明

- 桌面应用图标走系统莫奈路径：Android 13+ 开启系统「主题图标」后 launcher 自动使用单色图标随壁纸莫奈配色；应用内启动页/品牌图标已随应用主题/莫奈取色渲染
- 上游 #900（环境变量内置时间戳 `{{timestamp}}`/`{{timestamp_ms}}`/日期/UUID）此前版本已实现，可在环境变量/重写规则中直接使用

## v1.22.33 (2026-09-06)

### 悬浮球

- **默认吸附左右两侧**：拖动/点击结束立即完整吸附屏幕边缘（默认行为，无需开关）
- **贴边开关 = 收纳**：开启后 3 秒无操作，悬浮球==藏入屏幕边缘 2/3、只露 1/3==并降低透明度；触碰立即恢复
- **冷启动自动恢复**：开启过悬浮球后，重新打开应用悬浮球随应用启动自动出现（此前恢复逻辑挂在设置页 initState，导致"重进设置页才出现"）；无悬浮窗权限时静默跳过不打扰；首次默认仍关闭
- **面板「设置」→「MCP 设置」**：点击直接跳转应用内 MCP 设置页（不再只是打开应用主页）
- 应用图标配色说明：系统桌面/启动画面图标为编译期静态资源，无法运行时跟随应用主题（系统限制）；Android 13+ 系统「主题图标」开启时 launcher 会使用应用声明的单色图标自动随系统壁纸配色（已支持 monochrome 图层）

### UI 修复

- **AI 分析页标题**：改为「AI分析」，长文本省略号保护，不再截断
- **日志页标题「日志管理」完整显示**：搜索/导出/清除收进「⋮」菜单，AppBar 不再被多个操作按钮挤压（此前最后一个字被裁掉）
- **日志页保底可见**：进入页面即有"日志记录已就绪"提示；应用运行日志（已桥接）实时显示
- **启动页图标容器圆形 → 圆角正方形**：与自适应图标视觉语言一致

## v1.22.32 (2026-09-06)

### 悬浮球

- **尺寸缩小到原来的 1/3**：直径 104dp → ==36dp==，波纹图案适配小尺寸（双弧）
- **贴边行为重做**：贴边 = ==球藏入屏幕边缘 2/3 只露出 1/3==，同时透明度自动降低表示"已收纳"；触碰即恢复原位与原透明度
- **配置面板小型化**：点击悬浮球弹出的窗口缩小（按钮 132dp、整体紧凑），仍始终贴在球旁不重叠
- **透明度修正**：默认改为 255（完全不透明，此前默认 230 导致"透明度调高仍显透"）；球体配色与设置页预览统一（同一渐变算法）
- **「隐藏悬浮球」更名「关闭悬浮球」**：关闭后写回偏好，MCP 设置页开关状态同步（切回页面自动刷新）

### AI 分析

- **多对话管理**：支持==多个独立对话==——AppBar 新增「对话列表」入口（新建/切换/删除会话），首条消息自动命名会话；每个对话消息独立
- **关闭并清除对话**：AppBar 新增「清除当前对话」（确认后清空消息）；会话列表内可单条关闭删除

### 其它

- **启用悬浮球默认关闭**：冷启动不再自动恢复悬浮球服务，需要时到 MCP 设置页手动开启
- 贴边开关打开时，悬浮球 3 秒无操作即收纳至屏幕边缘（露出 1/3、透明度降低）

## v1.22.31 (2026-09-06)

### 问题修复

- **悬浮球图案恢复（∞ 图案消失）**：启动页图标此前用不透明图标整体染色，图案被同色覆盖成纯色块；改为透明底图标（icon_foreground.png）配合染色，∞ 图形完整保留并随主题色变化
- **悬浮球拖动不跟手**：拖动使用窗口 END 坐标系累加屏幕位移，方向相反导致球与手指错位；现以屏幕坐标驱动拖拽，拖动/贴边/面板定位坐标系统一
- **悬浮球配置面板定位修正**：面板始终出现在球的内侧且与球保持 16dp 间距不重叠，垂直与球心对齐，并限制不超出屏幕；此前面板位置随拖动错位漂移
- **「请求 Shizuku 授权」按钮改为常驻**：不再因"已连接/已授权"隐藏入口；未授权显示「请求 Shizuku 授权」，已授权显示绿色「Shizuku 已授权」，点击均可重新检测
- **自定义悬浮球预览与实际一致**：设置页预览从"彩色圆+字母 P"改为与真实悬浮球相同的液态玻璃样式（渐变+高光+波纹），随所选颜色/透明度实时更新
- **日志管理页真实有数据**：此前 451 处运行日志只输出控制台、内存日志队列无写入，日志页恒为空；现 logger 双通道输出（控制台 + 内存），日志页可实时查看/过滤/导出
- **日志页标题截断**：大字体/窄屏下标题被硬裁剪，已加省略号处理

### 优化

- **悬浮球改小**：直径 104dp → 76dp，更轻量不挡内容；面板按钮随之紧凑
- **添加规则弹窗可完整查看**：内容上限放宽至屏高 82%、单行输入框紧凑化，默认状态"条件/操作"区即可见，超高内容弹窗内可滚动查看

## v1.22.30 (2026-09-06)

### 悬浮球重做（液态玻璃）

- **正圆球体**：固定直径正圆，径向渐变球体 + 顶部椭圆高光 + 底部微反光，==不再有描边==；此前 wrap_content + 字母布局导致椭圆
- **图案更换**：球心改为白色同心波纹图案（圆头描边、向外渐弱，像冒泡信号），替代字母 "P"
- **贴球配置面板**：点击悬浮球弹出的窗口出现在==球的内侧==（球在右半屏→面板在左，反之在右），内容改为==悬浮球配置==：`设置`（打开应用，原"打开 ProxyPin"更名）/ `换颜色` / `调透明度` / `贴边：开/关` / `隐藏悬浮球`；不再显示 MCP 状态与刷新状态
- **配置实时同步**：面板内改动（颜色/透明度/贴边/隐藏）实时写回偏好设置，与设置页状态一致

### 问题修复

- **「请求 Shizuku 授权」按钮找回**：v1.22.29 修复 Shizuku 连接后，"Shizuku 运行中"被误当作"已授权"导致按钮永久隐藏；现按钮依据==实际授权状态==显隐（未授权即显示），状态栏显示 已授权/未授权/未连接 三态
- **规则弹窗内容可完整查看**：移除全部下拉的 isDense 高度压缩（选中项换行后不再被垂直裁剪且无法滚动查看）；多行 helperText 此前已配 helperMaxLines，弹窗整体可滚动
- **冷启动顺序修正**：Flutter 首帧前的窗口背景改用启动画面资源（主题色+居中图标），==冷启动全程图标保持在屏==（系统画面→窗口期→原启动页无割裂）；原启动页图标预载完成后再开始放大动画，不再"背景先出、图标后闪现"
- **详情页响应自动刷新**（上游 #922）：请求在详情页打开期间才完成时，响应内容自动刷新，不再停留在"未响应"
- **IP 直连 MITM 证书校验失败**（上游 #913）：SAN 中 IP 地址改用 iPAddress(0x87) 编码二进制地址值；此前一律用 dNSName(0x82) 编码导致部分客户端拒绝证书

### 说明

- 上游 #906（请求列表全选）、#887（高级重放秒间隔）已在之前版本实现

## v1.22.29 (2026-09-06)

### 问题修复

- **Shizuku 授权弹窗永不弹出的根因修复**：Manifest 此前缺少 Shizuku 官方要求的 `ShizukuProvider` 声明，应用始终收不到 Shizuku binder（`pingBinder()` 恒为 false），点击「请求 Shizuku 授权」只会立即失败并提示"未完成授权"。补上声明后：Shizuku 运行中点击按钮正常弹出系统授权弹窗，允许即完成；ProxyPin 也会出现在 Shizuku 的应用管理列表中
- **规则引擎下拉完整显示（彻底版）**：上一版补齐 isExpanded 后下拉项仍残留 `maxLines: 1 + 省略号`（用户实测仍被裁剪），本版彻底移除，条件类型/字段/运算符/值/操作类型超长文本自动换行完整显示
- **悬浮球"开了但看不见"全链路可见反馈**：前台服务启动失败、悬浮窗被系统/厂商拦截时，原生于服务内弹 Toast、Flutter 侧弹提示并展示具体原因；开启成功也有确认提示（含厂商后台权限排查引导），不再静默无反应
- **悬浮球颜色参数解码修复**：Dart 的 ARGB 颜色值超出 Java Int 范围会被解码为 Long，此前按 Int 读取永远取到默认色；现按 Number 正确转换，自定义颜色真实生效
- **悬浮球 MCP 状态透传**：绿色描边此前因参数未透传恒为"已停止"，现真实反映 MCP 服务运行状态
- **悬浮球自动贴边方向修复**：贴边坐标此前按错误坐标系计算会吸附到屏幕中部偏内，现正确吸附左右边缘
- **URL 编码/中文域名连接崩溃**（上游 #923）：含 `%` 的主机名（如 `%E5%B0%8F%E5%BA%A6.%E4%B8%AD%E5%9B%BD`）会被 Dart 误判为 IPv6 scope id 抛 FormatException；连接前自动解码并转换为 Punycode（RFC 3492），中文域名可正常解析连接
- **AI 配置指南代码块深色模式适配**：此前硬编码浅色背景/黑字，深色模式下刺眼；改为主题色自适应

### 个性化

- **冷启动第一屏（系统启动画面）图标化 + 主题色**：系统启动画面显示应用图标，背景跟随深浅模式主题色（浅色白/深色与应用 surface 一致）；Android 12 以下启动背景同样为图标 + 主题色
- **原启动页主题色 + 图标放大 + 图标随主题染色**：背景跟随应用主题（深浅模式/莫奈取色实时生效），应用图标以主题色染色（与 Android 13 themed icon 同风格）做一次克制的放大动画，约 1 秒无缝进入主界面
- 完整链路：==系统画面（图标+主题色）→ 原启动页（主题配色+图标放大）→ 主界面==

### 说明

- 系统启动画面属于编译期静态资源，图标为彩色应用图标、无法运行时跟随应用内主题色/莫奈取色（系统行为限制）；进入应用后由原启动页即时跟随主题并完成图标放大
- 若悬浮球仍不显示且收到失败提示，请按提示检查系统「显示悬浮窗」与厂商「后台弹出界面」权限（MIUI/HyperOS/ColorOS 等厂商系统有独立开关）

## v1.22.28 (2026-09-05)

### 问题修复

- **规则引擎下拉改完整显示**：添加/编辑规则弹窗的条件类型、字段、运算符、值、操作类型下拉选中项不再省略号裁剪，超长文本自动换行完整展示
- **全应用 26 处下拉硬裁剪修复**：扫描全部 DropdownButtonFormField，补齐 isExpanded（选中项不再被挤压裁剪，涉及脚本/重写/请求映射/上报服务器/AI 配置等页面）
- **悬浮球权限流程完善**：MCP 设置页悬浮球区新增「悬浮球权限」入口（实时显示授权状态，未授权点击直达系统设置）；开关在未授权时禁用并提示先授权，避免"开了但看不见"的困惑

### 个性化

- **启动页「跟随主题」模式**（原"透明（跟随主题）"更名推荐）：背景随深浅模式、图标与文字随主题色/莫奈取色变化——想要"原启动页风格 + 配色随主题"选此模式；系统原生启动画面为编译期静态资源，无法运行时跟随主题（系统行为限制）

## v1.22.27 (2026-09-05)

### 问题修复

- **使用文档 RangeError 彻底修复**：根因是重点标记正则的捕获组序号错位（代码取 group(7) 但正则只有 6 个捕获组），导致渲染越界白屏；已修正组号一一对应，各类重点标记（粗体/高亮/下划线/波浪线/删除线/代码）现在正确渲染
- **悬浮球开启后不可见**：根因是缺少"显示在其他应用上层"（悬浮窗）权限时服务静默失败；现在未授权时会**自动跳转系统授权页并明确提示**，授权后回来重新开启即可显示
- **快捷搜索搜不到数字**（上游 #916）：快捷搜索默认范围扩展为 URL/方法/请求头/请求体/响应体（此前不含正文，接口返回的 ID 等数字搜不到）
- **规则引擎添加规则弹窗下拉显示异常**：条件下拉选中项文本超长被硬裁剪只剩一个字，全部下拉改为省略号显示（类型/字段/运算符/值/操作类型）

### 说明

- 原启动页（系统画面）配色说明：系统启动画面为编译期静态资源，可随系统深浅模式切换（浅色白/深色黑），无法跟随应用内主题色运行时变化；需要主题色启动页请选「渐变品牌页」（自动跟随主题与莫奈取色）

## v1.22.26 (2026-09-04)

### 问题修复

- **Shizuku 授权彻底修复**：授权请求改为主线程调用（Shizuku 内部依赖主线程 Handler，此前后台线程调用导致弹窗未弹出、90 秒空等后返回失败）；判定逻辑增加兜底——用户在任何时刻手动授权后，实时权限检查都能识别为已授权
- **预测性返回开关无差异**：根因是关闭开关时传入了空的 PageTransitionsTheme，反而清空了页面默认转场动画；现关闭时不覆盖转场（保留主题默认），开启时才启用 Material 3 预测返回转场。注意实际手势效果需 Android 14+ 且系统启用预测性返回
- **使用文档 RangeError 渲染异常**：渲染器所有截断操作增加安全守卫（对短行不再越界），异常时自动降级为纯文本并显示原因
- **定时任务提示省略号**：重复次数/间隔的说明从单行 hint 改为完整多行说明（helperText），不再省略
- **mTLS 位置调整**：从主题区移至「拦截 QUIC」下方，网络类设置归并

### 说明

- AI 接口地址兼容 Base URL（`https://hmai.n10.top/v1`）与完整接口（`.../chat/completions`）两种填写方式，均自动正确处理
- 启动页配色：渐变品牌页/透明模式颜色自动跟随当前主题色（含莫奈壁纸取色）；系统原生启动页为系统默认纯色画面（不随应用主题，属系统行为）

## v1.22.25 (2026-09-04)

### 崩溃修复

- **悬浮球前台服务崩溃**（`MissingForegroundServiceTypeException`，targetSDK 36）：manifest 为 FloatingBallService 声明 `foregroundServiceType="specialUse"` + 对应权限，`startForeground` 显式携带类型；关闭/退出时的重复 removeView 崩溃（IllegalArgumentException）改为安全移除；悬浮球初始位置调整到屏幕右侧（此前可能在状态栏附近不可见）
- **使用文档白屏防御**：MarkdownLiteView 增加渲染异常兜底（自动降级为纯文本 + 错误提示，不再整页白屏）

### 功能修复

- **启动页还原默认**：移除 Android 12+ 系统启动画面的自定义图标与配色，恢复应用原本的默认系统启动页（纯色无图标）
- **AI 接口地址兼容**：支持填写完整接口地址（`https://hmai.n10.top/v1/chat/completions` 等以 /chat/completions 结尾的地址）与 Base URL 两种形式，自动识别不再重复拼接

## v1.22.24 (2026-09-03)

### 问题修复

- **文本编辑器手机布局溢出**：工具栏改两行自适应布局（语言行 + 工具行），窄屏不再出布局；下载按钮图标改 `save`、长按提示改为「保存」
- **Shizuku 授权提示误导**：去除"请确认 Shizuku 已运行"的错误引导（此前曾拒绝过一次授权会被误判），文案改为引导在弹窗中允许 / 去 Shizuku 应用授权
- **MCP 自动化任务卡片省略号**：定时信息改为完整多行显示不截断
- **请求解密页空态 "-"**：改为带图标与引导文字的空态提示
- **启动页默认系统画面说明**：原启动页（off）下展示时长/自定义小字置灰并说明"系统画面不支持自定义"；展示时长改为**连续滑杆（0.2~5 秒精细调节）**
- **系统启动画面割裂**：Android 12+ 的 system splash 背景与渐变品牌页主色统一（浅色/深色各一套），消除"先原启动页再渐变页"的突兀跳变

### 功能完善

- **日志管理开启按钮**：日志页 AppBar 新增录制开关（红色圆点 = 记录中，点击暂停/开启），并提示状态变化
- **设置页日志入口**：设置页「关于/使用文档」分区新增「日志管理」入口
- **工具箱 AI 分析入口**：工具箱「其他」新增 AI 分析（psychology 图标），与设置页入口一致打开对话页
- **AI 配置增强**：服务商列表式选择（OpenAI/DeepSeek/通义/Kimi/智谱/Ollama/自定义），选中自动填地址与模型建议；支持**从 JSON 文件导入配置**
- **Agent 自定义设置**：AI 配置新增 Agent 模式区——最大工具轮数 1~8 连续可调 + **Agent 附加指令**（注入系统提示词）
- **MCP 连接信息 Health Check**：SSE URL 下方新增 `/health` 健康检查地址
- **MCP 悬浮球**（Android）：启用开关（前台服务提升保活）、3 秒无操作自动贴边开关、自定义样式（6 种预置色 + RGB 取色器 + 透明度滑杆 + **实时圆形预览**）；悬浮球为白色描边圆形 P 字标（运行中绿色粗描边），点击弹出 MCP 快捷面板（状态/打开应用/刷新），再次点击收起
- **预测性返回开关**（Android 14+）：偏好设置莫奈取色下方新增；开启后 Material 3 预测返回页面转场（PredictiveBackPageTransitionsBuilder），关闭维持传统转场（默认关闭，与未加开关前行为一致）
- **AI 图标更换**：工具箱 AI 分析图标改为 psychology
- **内置教程渲染器升级**：
  - 支持多种**重点标记**：`**粗体**`、`==黄色高亮==`、`__实线下划线__`、`~橙色波浪线~`、`~~删除线~~`、`` `等宽代码` ``，文档内容已开始使用
  - 代码块右下角新增「示例」（弹出当前章节演示说明，文档可用 `<!--demo:说明-->` 自定义）与「复制」按钮
  - 阅读页 AppBar 新增**重置/标记说明**按钮（展示全部标记语法、一键复制语法、清除本地状态恢复默认）
- **功能总览文档**：新增 docs/overview.md 全功能索引（入口/用途/文档联动），内置文档置顶展示

### 构建与发布

- **APK 文件名带版本号**（上游 #917）：产物改为 `proxypin-<version>-<abi>.apk`
- 仓库迁移至 proxypin-with-mcp

### 说明

- 上游 #916（纯数字关键词无法搜索）排查中：搜索过滤链路分散在多个列表实现，留待专门版本修复；#922（详情页响应不自动刷新）、#913（IP 直连 MITM 证书 SAN）已记录待办
- 悬浮球启停 MCP：快捷面板当前提供状态/打开应用/刷新；直接启停请使用设置页开关（悬浮球按钮在后续版本接入启停）

## v1.22.23 (2026-08-31)

### 功能完善

- **AI Agent 模式**：AI 分析页新增 🤖 开关——开启后 AI 可自动调用 ProxyPin 功能（查询最近请求/请求详情/API 端点/修改配置等 MCP 工具，文本协议 + 自动执行 + 结果回喂，单次问答最多 3 轮防失控）；关闭时仅接收手动消息，更省 Token 更隐私；开关状态持久化
- **AI 附件多类型多选**：附件从单条请求扩展为三类——抓包请求（最近 30 条多选）、API 端点清单（自动提取统计）、自定义文本（粘贴任意内容），可同时附加多条，气泡中显示可移除标签
- **QUIC 开关移位**：从主题区移至「自动开启抓包」下方，网络行为设置归类更合理

### 内置教程更新

- 新增「AI 分析使用指南」（配置/附件/Agent 模式/多轮对话/隐私说明/开发联动）
- 「常用功能技巧」补充搜索历史、QUIC 拦截、mTLS、AI 分析章节
- 「MCP 自动化指南」补充 Cron 定时方式与重复任务过期自动推进说明
- 「快速上手」功能速览表新增开发工具/AI 分析/使用文档与可选增强（QUIC/mTLS/莫奈/启动页/MCP）

## v1.22.22 (2026-08-31)

### 问题修复

- **定时方式选择 UI 溢出**：新增 Cron 后 5 个 SegmentedButton 一行放不下，改为流式 ChoiceChip 布局（图标+文字，选中高亮）
- **启动页设置内容不可见**：之前默认「原启动页」时所有详细设置被隐藏；现背景模式始终可见，选中渐变/自定义图片/透明后展示时长、自定义图片、小字等详细配置；展示时长默认改为 0.5 秒
- **莫奈取色开关不立即生效**：开关切换后现在触发 MaterialApp 全局重建，主题与启动页取色即时切换
- **Dhizuku 授权改为标准弹窗**：通过 Dhizuku API（运行时反射，编译零依赖）在应用内弹出授权弹窗并等待结果，API 不可用时才回退打开 Dhizuku 应用

### 功能完善

- **AI 分析完整页面**：设置页「AI 分析」入口改为打开对话式页面——消息气泡、多轮上下文、右上角「附加抓包请求」（从最近 30 条选择，与 MCP 工具同源）+ AI 配置入口；请求长按「AI 分析」/桌面右键「AI 分析」均进入对话页并自动附加该请求
- **搜索历史**（上游 #217）：移动端搜索条件面板顶部显示最近 8 条搜索关键词（去重置顶、点击快搜、可清空）
- **双向认证 mTLS**（上游 #366）：与上游服务器 TLS 握手时提供客户端证书（PEM 证书链 + 未加密私钥），偏好设置配置入口（文件选择 + 格式校验 + 加载反馈），对新连接即时生效
- **QUIC 拦截统计**：VPN 层拦截计数上报，偏好设置开关副标题显示「已拦截 N 个 QUIC 包」

### 说明

- HTTP/3 帧级解析（#489 完整形态）需要完整 QUIC 协议栈（TLS1.3 握手解密/包号恢复/流复用 + HTTP/3 帧编解码），Dart 生态无成熟 QUIC 库，工程量数万行；当前「拦截回落」方案已达成"流量可抓包"的实用目标，并新增拦截统计可见性
- 上游 open issues 复核：全库共 91 条（Search API 确认），此前已全部翻阅，无遗漏页

## v1.22.21 (2026-08-30)

### 新功能

- **定时任务支持 Cron 表达式**：MCP 定时任务新增「Cron」模式（分 时 日 月 星期，支持 `* , - /`），输入实时预览下次执行时间与常用示例；新增公共 CronExpression 解析器，与工具箱 Cron 工具共用一套实现；重复任务（每天/每周/间隔/Cron）在应用停用一段时间后重新打开会自动推进到下一个执行点，不再因过期而失效
- **AI 请求分析**（上游 #582）：设置页「MCP Connection」下方新增 AI 分析入口，支持 OpenAI 兼容接口（Base URL / API Key / 模型，Key 加密存储）；请求长按菜单新增「AI 分析」一键分析（接口用途概括 + 请求要点 + 响应要点 + 风险提示，敏感信息自动脱敏要求），带加载态与错误反馈
- **QUIC 拦截（回落抓包）**（上游 #489）：Android VPN 层拦截 UDP:443（QUIC/HTTP3），客户端握手失败后自动回落 TCP HTTP，流量即可正常抓包；偏好设置可开关（默认开启）；Charles 等主流抓包工具同款方案

### 问题修复

- **远程设备假连**（上游 #521）：连接成功后每 10 秒心跳检测，连续 2 次失败自动断开并提示，不再"看着连着其实已断"
- **Root 授权结果判定**：su 命令等待延长至 15 秒并以退出码判定授权结果，UI 明确反馈授权成功/拒绝
- **Dhizuku 授权入口更名「配置 Dhizuku」**：如实反映行为（打开 Dhizuku 应用完成授权），并给出操作提示

### 构建与签名

- **签名固定**：所有构建统一使用 CN=Taffy, C=CN 证书（proxypin-release.jks 随仓库提供，30 年有效期），CI 移除随机生成 keystore 的逻辑，此后版本可互相覆盖安装

### 说明

- TUN 模式（上游 #577）需要集成平台级 tun2socks 二进制，本轮未实现，留待后续版本
- QUIC 完整解析（HTTP/3 帧解析）工程量巨大，本轮采用业界通行的"拦截回落"方案实现可抓包

## v1.22.20 (2026-08-30)

### 问题修复

- **MCP 运行状态持久化**：MCP 自动化页启停服务后写入配置（手动停止后重启应用不再自动拉起）；应用退出时的自动清理不再误记为用户停止；自动化页启动时自动解锁 MCP 总开关
- **启动页开关不生效**：偏好设置的启动页开关此前未接入启动门控，现完全生效；新增「原启动页（默认）」模式——不再在原生启动页之上叠加自定义启动页
- **Shizuku 授权体验重做**（原生）：改用 Shizuku 标准 API（dev.rikka.shizuku:api），点击「请求 Shizuku 授权」直接在应用内弹出系统授权弹窗（等待用户操作返回结果），不再跳转 Shizuku 应用；采用标准 binder API 后 ProxyPin 会出现在 Shizuku 的应用管理列表中，可手动授权；同时修复 Shizuku Shell 命令执行从未生效的问题（原反射调用方式错误）
- **教程入口全面内置化**：脚本 / 请求重写 / 环境变量 / 上报服务器 4 处「使用引导」不再跳转网页，改为打开内置文档（桌面/移动端同步替换）

### 功能完善

- **莫奈取色（Material You）**：Android 12+ 开启后主题与启动页自动跟随壁纸配色（dynamic_color），偏好设置新增开关，低版本自动回退固定主题
- **启动页渐变模式重设计**：主题色渐变（莫奈下跟随壁纸）、细字重宽字距排版、单次淡入上移动效、底部细进度条，移除花哨轮播与弹跳动画
- **工具箱新增「开发工具」**：Cron 表达式（字段说明 + 常用示例 + 未来 6 次执行时间预览）、JWT 解码（Header/Payload 格式化 + 过期时间判断）、UUID v4 批量生成、SHA-1/256/512 哈希
- **内置文档扩至 12 篇**：新增脚本开发指南、请求重写指南、环境变量指南、上报服务器指南
- 「使用文档」入口迁移：从偏好设置移至设置页「关于」下方

### 上游 Issues 调研

- 全量翻阅上游 98 条 open issues（3 页），确认脚本日志机制（#562）现有实现已覆盖；QUIC（#489）、TUN（#577）、AI 分析（#582）、远程设备假连（#521）等大工程项留待后续版本

## v1.22.19 (2026-08-29)

### 功能完善

- **内置文档中心**：新增「使用文档」页面，离线内置全部功能使用教程、规范文档与开发文档（快速上手 / 证书与 HTTPS 抓包 / 常用功能技巧 / MCP 自动化指南 / 工作流编排教程 / 更新日志 / 开发文档 / 项目说明），支持搜索与轻量 Markdown 渲染（标题/列表/代码块/引用/粗体），无需再跳转网站
- **文档入口多点接入**：
  - 工具箱「其他」分组新增「使用文档」（全部文档）
  - MCP 自动化页 AppBar 新增帮助图标（直达 MCP 教程）
  - 工作流管理页 AppBar 新增帮助图标（直达工作流教程）
  - 移动端偏好设置新增「使用文档」入口
- 文档资产打包进应用（docs/*.md、CHANGELOG、README、AGENTS），离线可用

## v1.22.18 (2026-08-29)

### 功能完善

- **MCP 定时任务再增强**：新增「每周」模式（周一~周日多选芯片）；一次性任务支持日历选择执行日期（showDatePicker，最长两年后）；任务卡片每周模式显示选中星期
- **环境变量内置通用变量**（上游 #900）：`{{timestamp}}`、`{{timestamp_ms}}`、`{{datetime}}`、`{{date}}`、`{{time}}`、`{{uuid}}` 可直接引用，无需手动定义
- **多选支持全选**（上游 #906）：请求列表选择模式新增「全选」按钮（桌面/移动端），选中当前可见的全部请求
- **修复 Android 保存图片无效**（上游 #902）：file_picker 在 Android 上 saveFile 不写入字节，改为写临时文件后调起系统分享面板保存

## v1.22.17 (2026-08-28)

### 功能完善

- **MCP 定时任务增强**：新增定时方式选择（一次性 / 每天重复 / 固定间隔）、重复次数上限（留空无限）、间隔分钟数；任务卡片展示模式徽标与执行进度；持久化格式向后兼容旧版 `repeatDaily` 字段
- **MCP blockRequest 真实拦截**：命中「onRequest 触发器 + 拦截动作」的请求在发出前短路返回 403（此前仅打标记不生效）
- **MCP sendNotification 真实通知**：经 EventBus 发布通知事件，桌面/移动端以 toast 展示（此前仅记录日志）
- **规则引擎动作补全**：notify 发送真实通知；startCapture/stopCapture 支持代理启停控制
- **API 端点提取功能修复**：修复 `api_extractor.dart` 引用不存在类型（`Request`/`Response`）导致的编译错误，适配 `HttpRequest`/`HttpResponse`；三种导出（OpenAPI/Postman/JSON）从占位补齐为真实文件保存；桌面请求列表菜单与工具箱新增「API 端点」入口
- **启动页（Splash）**：组件接线到移动端启动流程；偏好设置新增「启动页」配置区块——开关、展示时长（0.5–5s）、背景（默认渐变 / 自定义图片 / 透明跟随主题）、自定义小字
- **日志查看入口**：`LogViewerPage` 接入工具箱「其他」分组
- **弱网离线模式修复**：开启离线后请求被 502 拦截（此前逻辑反转，流量照常放行）

### Bug 修复

- HTTP/2：SETTINGS_MAX_FRAME_SIZE 值错位（误写 maxHeaderListSize）；畸形帧缺伪头时空指针崩溃改为受控异常；RST_STREAM 时清理流上下文防止泄漏；GOAWAY 移除「自动重试」死标记
- HTTP/2 专用客户端通道（`Http2ClientHandler`）实现接收窗口归还：连接建立即扩大连接窗口，按阈值发送连接级/流级 WINDOW_UPDATE，消除大响应窗口耗尽挂起风险
- 脚本执行异常时写入合法状态码 500（此前为非法的 -1）
- 脚本 Dart 内联分支明确提示不支持（无 Dart 运行时），不再静默假装执行
- MCP 自动化 `onRequest`/`onResponse`/`onProxyStart`/`onProxyStop` 触发器接入转发管道与代理生命周期（此前任务静默不执行）
- MCP `modifyResponse` 状态码真实生效（此前丢弃用户参数写入占位值）
- 历史记录持久化串行写队列，消除并发全量重写交错/截断风险
- HistoryTask 空闲 30 秒自动暂停，释放定时器与文件句柄
- HAR 导出流式写入，避免大列表导出时双份内存驻留
- enhanced_scheduler Cron 表达式重写为逐级进位算法，修复跨日/跨月/跨年调度错误

### 工程清理

- 移除 22 个开发过程文档（构建修复记录、旧版审查/验证/优化报告等）
- 移除未接线且与 `api_endpoint_page.dart` 重复的 `api_endpoints_page.dart`
- 文档保留：`README.md`/`README_CN.md`、`AGENTS.md`（开发指南）、`MCP_INTEGRATION.md`、`docs/MCP_AUTOMATION_GUIDE.md`、`docs/WORKFLOW_TUTORIAL.md`

## v1.22.16 (2026-08-27)

### MCP 自动化页面修复

- 运行状态指示器：进入页面不再先闪「已停止」，状态胶囊旁新增启停开关
- TabBar 靠左对齐（`tabAlignment: start`）
- 规则弹窗限制最大宽高、下拉框 `isExpanded`，修复显示异常与断言崩溃
- Prompts 列表/调用弹窗/结果弹窗全链路防御异常数据，修复白屏
- Roots 支持自由添加/编辑/删除并持久化（`mcp_roots.json`），`roots/list` 即时生效
- 新增 `startMcp`/`stopMcp`/`refreshMcpRoots` 桌面端 IPC
