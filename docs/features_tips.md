# 常用功能技巧

> 高频功能的用法与最佳实践。

## 请求搜索与过滤

- 顶部搜索框支持关键字、正则匹配 URL
- 高级过滤：方法（GET/POST...）、状态码区间、域名、时间范围、进程/App
- 过滤条件可以组合，命中部分会高亮显示
- 搜索结果支持按时间正序/倒序排列
- **搜索历史**（移动端）：搜索条件面板顶部显示最近 8 条关键词，点击快搜、可清空（上游 #217）
- ==快捷搜索默认覆盖 URL/方法/请求头/请求体/响应体==（上游 #916：搜数字等正文内容也能命中）；精确控制范围请打开搜索条件面板勾选
- ==快速筛选 chips==：搜索条件面板顶部并排提供**协议 chips**（HTTP / HTTPS / WS / SSE / HTTP1 / H2）与**状态码分组 chips**（2xx / 3xx / 4xx / 5xx）——点一下即写入筛选条件，再点一次取消；状态码分组 chips 与下方「状态码区间」输入框共用 `statusCodeFrom/statusCodeTo`，改任一处另一处同步高亮，不会互相覆盖
- 面板文案已全部接入多语言（en / zh / zh_Hant 及 es/id/pt/th/vi），排序字段与方向、协议、状态码分组、相机授权提示等均不再硬编码中文
- 实现：`lib/ui/component/search_condition.dart`（`protocolsWidget()` / `statusGroupWidget()`），桌面端与移动端共用同一组件，改一处两端同时生效

## 请求重放

- 单次重放：右键/长按请求 → 重放；可在编辑器中修改参数后再发
- 批量重放：指定次数、间隔（固定/随机）、失败重试与指数退避
- 重放统计：成功/失败计数一目了然
- 技巧：先在编辑器改好请求体，再设置重放次数做简单压测
- ==发送队列==（上游 #715/#401）：工具箱 → **发送队列** 汇总本次运行期间的所有重放任务——状态（等待发送/发送中/已完成/已取消）、进度条、成功/失败/重试统计、计划时间与**待发送请求清单**；==定时重放的任务不会因关闭对话框而丢失==，可随时回来查看进度；支持清除已结束记录
  - 实现：`lib/network/components/repeat_task_manager.dart`（内存态任务登记 + 变更通知）、`lib/ui/component/repeat_queue_page.dart`（列表页）；单请求多次、批量、定时三类重放均已接入

## 重写规则

支持三种类型：

1. **重定向**：把请求转发到另一个 URL（本地 Mock 服务常用）
2. **请求修改**：按规则改写请求头/体
3. **响应修改**：按规则改写状态码/头/体

规则支持通配符（`*` 与转义 `?`）和正则，可启用/禁用单条规则，支持导入导出分享。

==加密分享==（上游 #133）：导出规则时可选择「加密分享」，设置口令后生成 `.enc` 文件；
接收方导入时输入相同口令才能解密还原，口令错误或文件被改动会明确报错。
实现：`lib/utils/secure_share.dart`（PBKDF2-HMAC-SHA256 派生密钥 + AES-256-GCM 认证加密，
前缀 `PROXYPIN-ENC1:` 自动识别），明文导出格式保持不变、双向兼容。

> 说明：设备数量限制（同一份分享仅限 N 台设备导入）属于服务端授权范畴，离线分享场景下
> 采用「口令保护」作为等价安全手段——口令即访问控制，不依赖联网校验。

## 脚本

- 工具箱 → JavaScript 打开脚本编辑器
- 脚本可处理请求（onRequest）与响应（onResponse）
- 脚本管理页可启用/禁用、按名称组织
- 环境变量：脚本中通过 `env.get('name')` 读取，支持 `{{name}}` 模板替换；内置变量 `{{timestamp}}`、`{{date}}`、`{{uuid}}` 等开箱即用
- ==多值响应头==（如 `Set-Cookie`）在脚本里是**字符串数组**（单值头仍是字符串），逐条处理即可；详见「脚本开发指南 → 多值响应头」（上游 #901）
- ==加载第三方 JS 库==（上游 #719）：`const lib = await require('https://…/utils.js')`，支持 CommonJS 导出或挂到全局；同 URL 自动缓存，详见「脚本开发指南 → require」
- ==捕获 WebSocket 帧==（上游 #722）：定义 `function onWebSocket(context, ws)` 即可逐帧回调，可读方向/文本/`rawBody` 字节数组/长度；只读不改包，详见「脚本开发指南 → onWebSocket」

## 弱网模拟

- 设置 → 弱网：配置上行/下行带宽、请求/响应延迟、抖动、丢包率、离线
- 支持按 URL 单独配置（命中规则的 URL 使用独立参数）
- 用途：测试 App 在弱网下的加载态、重试与容错表现

## 断点调试

- 设置 → 断点：按 URL 规则拦截请求或响应
- 命中断点时弹出编辑器，可修改后放行（Resume）或中止（Abort）
- 适合精确观察与篡改单个请求

## 批量操作

- 列表进入多选模式（支持全选），底部操作栏提供：
  - 批量导出 HAR / JSON
  - 批量删除
  - 批量重放
- iOS 导出使用系统分享面板，避免「Is a directory」错误
- ==导出「响应」时，未拿到响应的请求不计入成功数==，提示中的条数与实际生成文件数一致（上游 #894）
- 安卓导出：选择目标目录后逐条写入文件（`request.txt` / `response.txt` / `request_response.txt`），HAR 走单文件保存

## 请求列表选中与详情（桌面端）

- ==单击选中以请求 ID 记录==：新请求不断涌入时，当前选中的行高亮不会消失（上游 #915）
- 快捷键：`Ctrl/⌘` 点击多选、`Shift` 点击范围选择、`Esc` 取消选择；右键菜单支持重放/导出/复制 curl 等
- 选中的请求详情在右侧面板显示，列表滚动与刷新不影响已打开的详情

## 下拉与长文本

- 规则引擎、搜索条件等处的下拉若选项名较长（如「请求 Content-Type」），框内以**单行 + 省略号**呈现，**不再被换行截断**；长按（移动端）/悬停（桌面端）可查看完整文本
- 实现：下拉统一 `maxLines: 1 + ellipsis + softWrap: false`，并配合 `Tooltip` 与合理宽度分配（`lib/ui/mobile/setting/mcp_automation.dart` 的 `_dropdownText` / `_selectedItems`）
- 搜索条件面板的自绘下拉：菜单宽度设下限（200）保证长选项完整显示，选中值同样单行省略

## 请求口令分享（跨端秒传）

- 把抓到的请求**压缩成一段口令文本**：长按/多选请求 → 导入/导出 → **复制口令**（`PROXYPIN1:` 前缀 + base64Url + gzip 压缩 JSON，体积小、可粘贴到任意聊天/邮件）
- 还原：导入/导出 → **从剪贴板导入口令**，粘贴口令即还原请求到列表（含 URL/方法/头/体，可直接重放）
- 实现位置：`lib/network/http/passcode.dart`（`encodeRequestPasscode`/`decodeRequestPasscode`），入口 `lib/utils/export_request.dart`
- 适用：手机抓到的问题请求发给电脑端排查、把请求分享给同事复现（无需整包导出文件）

## API 端点提取

- 工具箱 → API 端点：从当前流量自动归纳 REST 接口
- 自动合并同资源路径（数字 ID 归一化为 `{id}`）
- 统计调用次数、成功率、平均耗时
- 一键导出 OpenAPI（Swagger）、Postman Collection、JSON

## 外部代理（上游代理链）

- 设置 → 外部代理：把 ProxyPin 的出口流量交给另一个代理（常用于 ProxyPin 上面再挂一层抓包/隧道）
- ==支持两种协议==（上游 #825）：**HTTP 代理**（走 HTTP CONNECT 隧道，与旧版一致）与 **SOCKS5**（RFC 1928，含 RFC 1929 用户名/口令认证）
- 选择 SOCKS5 后，ProxyPin 会在连上代理后完成方法协商 → 认证（若配置）→ CONNECT 目标地址（自动区分 IPv4 / IPv6 / 域名）
- 失败原因会明确提示（如「代理拒绝认证」「主机不可达」「连接被拒绝」等错误码含义）
- 实现：`lib/network/util/socks5.dart`（二进制握手状态机）、`lib/network/http/http_client.dart`（按 `ProxyInfo.protocol` 分流）；配置持久化在 `ProxyInfo.protocol`，旧配置默认 `http`，行为不变

## Hosts 与域名过滤

- 设置 → Hosts：自定义域名解析映射，无需改系统 hosts 文件
- 设置 → 域名过滤：只抓需要的域名，避免干扰
- ==支持按 URL 路径/接口过滤==（上游 #225）：白名单/黑名单除域名外还可填写 URL 路径，例如 `api.example.com/v1/` 只抓该接口、`.*\.example\.com/order/.*` 精确到业务路径；写法支持 `*` 通配，纯域名规则行为与旧版一致
- 实现：`lib/network/components/host_filter.dart`（匹配目标为 `host + path`），代理层在请求与响应两处按 `pathAndQuery` 判定

## 配置管理

- 设置 → 配置管理：一键导出/导入全部配置（规则、脚本、环境等）
- 自动备份：定期在本地生成配置快照，可在备份管理中恢复
- 换机迁移：旧设备导出 → 新设备导入

### 便携版（桌面端，上游 #285）

- 在程序可执行文件同目录放一个名为 `portable`（或 `portable.txt`）的空文件，即进入**便携模式**：配置、CA 证书与私钥、脚本、历史等全部数据写入程序目录下的 `proxypin_data/`，整个文件夹拷到 U 盘/另一台机器即可带着全部设置与证书走
- 不放置标记文件时行为不变（数据在系统应用支持目录）
- 是否生效可直接在**设置 → 偏好设置**看到：便携模式下会显示「便携模式已启用」及实际数据目录（v1.22.49 起），不必再靠翻文件系统确认
- 实现：`lib/storage/path.dart`（`homePath` / `isPortable`），配置目录 `lib/network/util/file_read.dart`、证书 `lib/network/util/crts.dart`、历史 `lib/storage/histories.dart` 均统一走该根目录
- 备份目录（`proxypin_backups/`）同样跟随该根目录；桌面端「备份管理」页与写入端使用**同一路径**（v1.22.49 修复：此前页面读 `~/proxypin_backups` 而写入端写 `~/.proxypin/proxypin_backups`，路径不一致导致列表恒空、"打开备份目录"也打不开）

## 抓包范围控制（不接管全部流量）

- 不想让 VPN 接管所有流量时，用**应用白名单**：设置 → 应用过滤 → 只勾选需要抓包的应用，其余应用的流量不经过 ProxyPin（不做默认路由），避免影响系统与其他 App
- 反向用法：应用黑名单排除不需要抓包的应用
- 上游 #815 的「不作为默认路由」诉求即由该能力实现：白名单为空时才会接管全部流量
- 实现：`lib/native/vpn.dart` 传 `allowApps` / `disallowApps`，Android 侧由 `ProxyVpnService` 调用 `addAllowedApplication` / `addDisallowedApplication`

## 多窗口（桌面端）

- WebSocket、JSON 查看器、文本对比、性能监控等工具支持独立窗口
- 从工具箱点击对应工具即可弹出独立窗口，便于多屏协作

## 快捷键（桌面端）

- 清空列表、搜索等高频操作已绑定快捷键，见工具栏 Tooltip

## QUIC 拦截（Android）

- 设置 → 偏好设置 → 「自动开启抓包」下方：「拦截 QUIC (UDP:443)」开关（默认开启）
- 原理：VPN 层丢弃 UDP 443（QUIC/HTTP3），应用握手失败后自动回落 TCP HTTP，流量即可正常抓包（Charles 同款方案）
- 开关副标题显示已拦截的 QUIC 包数量；修改后需重启抓包生效
- 游戏类 App 走 QUIC 无法抓包/异常时，保持开启可解决（上游 #474/#489）

## QUIC 连接（元数据展示，Android）

- 入口：工具箱 → **QUIC 连接**（移动端 push 新页 / 桌面端独立子窗口，`QuicSessionsPage`）
- ==抓包运行中自动记录==访问过的 QUIC/HTTP3 会话：**SNI 域名 / QUIC 版本 / 源地址 / 首次时间 / 连接 ID / 包与帧统计**；支持清空记录（内存态，停止抓包/清空后重置）
- **实现方式**（三端链路）：Kotlin VPN 层 `ConnectionHandler.handleUDPPacket` 把 UDP:443 首个数据包经**本机 TCP**（41745 端口，即发即断）抄送给 Dart `ProxyServer`（30 秒/源节流防洪泛）→ `QuicProbe` 纯解析（无 socket）：QUIC v1 长头解析 → Header Protection 去除（AES-ECB）→ Initial AES-128-GCM 解密（密钥派生见 v1.22.38，RFC 9001 A.1 向量校验）→ CRYPTO 帧拼接 → 手写 TLS 1.3 ClientHello 解析提取 SNI，任一环节失败安全忽略
- **能力边界（诚实提示）**：HTTP/3 业务明文经 TLS 1.3 加密，无会话密钥无法解密查看——要看明文请开启「拦截 QUIC」让应用回落 TCP；列表头部提示条已注明
- **与其它功能联动**：
  - 「拦截 QUIC」开关（偏好设置）开启时照常回落抓明文，**同时**仍可记录 QUIC 连接（拦截前抄送，互不干扰）
  - 「QUIC 探测」开关（偏好设置 → 自动抓包下方，`Configuration.quicProbeEnabled` 默认开）可整体关闭抄送
  - 常用抓不到的原因：目标应用默认走 TCP/HTTP2；可临时关闭拦截重开抓包观察
- **开发细节**：Dart 监听在 `ProxyServer`（`lib/network/bin/server.dart`，`ServerSocket.bind` loopback 41745）；解析器 `lib/network/util/quic/`（`quic_keys.dart`/`quic_packet.dart`/`quic_probe.dart`）；Kotlin 入口 `ProxyVpnService.forwardQuicProbe` + `ConnectionHandler`；注意 Dart 侧不直接依赖 `dart:io` UDP（DatagramSocket），统一走 TCP 即发即断通道


## WebSocket 流量推送（外部工具集成）

- 入口：设置 → 偏好设置 → **WebSocket 流量推送**（开关即时生效，无需重启抓包）
- 用途：让 AI 助手（Claude Code 等）或外部工具**实时订阅抓包流量**，是 MCP 之外的第二条轻量集成通道
- 连接地址：`ws://127.0.0.1:12080`（默认端口，配置项 `wsTrafficPort`）
- **端口可图形化修改**（v1.22.49 起）：开关下方的「订阅端口」一行点击即可改（限制 1024~65535）；保存后立即生效——服务已开启则自动重启监听，端口被占用会提示并回滚开关。此前端口只能改配置文件，被占用时用户无路可走
- 开关副标题反映**实际运行状态**：若已开启但抓包未运行，会提示「已开启，但抓包未运行：启动抓包后自动监听 …」，避免误以为正在监听
- 推送消息（JSON）：`config` / `request` / `response` / `message` —— 含方法、URL、状态码、耗时、大小；WS 帧含方向（client_to_server / server_to_client）与文本载荷（截断至 4KB）
- 客户端命令：`{"action":"ping"}`、`{"action":"status"}`、`{"action":"list_histories"}`、`{"action":"get_history","name":"<会话名>"}`
- 设置项副标题实时显示**已连接客户端数**；内置 30 秒心跳，断线自动清理
- 「允许订阅端查询历史」可关闭历史读取（仅保留实时推送）
- 实现：`lib/network/components/ws_traffic_server.dart`（实现 `EventListener`，随代理启动/停止，开关切换即时生效）；实时推送**不含请求/响应 body**，避免大流量耗尽带宽

## Linux 安装包（上游 #560）

- Release 页面除 Android APK 外，另附 Linux 安装包：`proxypin-<版本>-linux-amd64.deb`
- 安装：`sudo dpkg -i proxypin-*.deb`（依赖 `libgtk-3-0`、`ca-certificates`；桌面托盘功能需 `libayatana-appindicator3`）
- 架构：**当前仅 amd64**——Flutter 官方尚未提供 Linux arm64 预编译 SDK，arm64 产物需等待上游工具链支持
- 实现：`.github/workflows/build-deb.yml`（独立工作流，与 APK 构建互不影响）；打包脚本参考仓库内 `linux/build.sh`

## 双向认证 mTLS

- 场景：目标服务器要求客户端证书（双向 TLS）
- 设置 → 偏好设置 → 「双向认证 (mTLS)」：开启并选择客户端证书链 PEM 与私钥 PEM（未加密）
- 加载成功后对新建立的 HTTPS 连接生效；重启应用自动恢复
- 注意：不支持 PKCS12 与加密私钥，请先用 openssl 转为未加密 PEM

## AI 分析

- 设置 → MCP Connection → AI 分析：OpenAI 兼容接口对话页
- 附件支持多条抓包请求 / API 端点清单 / 自定义文本（可多类型多选）
- ==多对话管理==：AppBar「对话列表」新建/切换/删除会话，首条消息自动命名；「清除当前对话」一键清空
- Agent 模式（🤖 开关）：AI 自动调用 ProxyPin 功能查询数据；关闭则仅接收手动消息
- 详见「使用文档 → AI 分析使用指南」

## 悬浮球与设备控制

- 入口：设置 → MCP Connection → 悬浮球 / 设备状态
- 悬浮球：==36dp 液态玻璃正圆==（径向渐变 + 高光 + 波纹，无描边，可拖动），==先在「悬浮球权限」入口授权==（未授权时启用开关禁用）；==启用默认关闭==，冷启动后需手动开启
- ==默认吸附左右边缘==：拖动/点击结束立即完整贴边；==贴边开关=收纳==（开启后 3 秒无操作藏入边缘 2/3、露 1/3 并降低透明度，触碰恢复）
- ==冷启动自动恢复==：开启过悬浮球后，重开应用自动出现（无悬浮窗权限时静默跳过）；首次默认关闭；面板内修改（关闭/换色/透明度/贴边）实时同步设置页状态
- 点击悬浮球弹出==球旁小型配置面板==（16dp 间距不重叠、垂直对齐球心）：`MCP 设置`（直达 MCP 设置页）/ `换颜色` / `调透明度` / `贴边开关` / `关闭悬浮球`（==关闭后设置页开关同步==）；配置实时写回偏好；设置页「自定义悬浮球」预览与真实球一致
- 拖动悬浮球可调整位置，拖动时自动从贴边状态唤起
- ==看不到悬浮球？==启动失败会弹窗显示具体原因；按提示检查系统「显示悬浮窗」与厂商「后台弹出界面」权限（MIUI/HyperOS/ColorOS 等有独立开关）
- Shizuku：==按钮常驻==（未授权显示「请求 Shizuku 授权」，已授权显示绿色「Shizuku 已授权」）；点击前确保 Shizuku 应用处于运行状态，授权弹窗在应用内弹出；状态栏显示 已授权/未授权/未连接 三态
- 与 MCP 联动：自动化任务 / 规则引擎 / 工作流执行 Shell 命令时，按 ==Root > Shizuku > Dhizuku== 顺序自动选择可用通道

## 国际化域名与 IP 直连证书

- 含 `%` 的 URL 编码主机名（如中文域名 `%E5%B0%8F%E5%BA%A6.%E4%B8%AD%E5%9B%BD`）连接前自动解码并转换为 Punycode（`xn--…`），不再抛 FormatException（上游 #923）
- ==IP 直连 HTTPS== 的 MITM 证书改用 iPAddress 类型 SAN 编码二进制地址值，修复部分客户端证书校验失败（上游 #913）
- 实现位置：`lib/network/util/idn.dart`（RFC 3492）、`lib/network/util/cert/x509.dart`（SAN 编码）
- 联动：对重写规则 / Hosts / 脚本中的 host 判断不受影响（仍使用原始 host 字符串）

## 详情页实时刷新

- 抓包详情页打开期间请求才完成时，==响应内容自动刷新==，不再停留在"未响应"（上游 #922）；配合请求/响应 Tab 查看完整报文

## 多平台安装包（Windows / macOS / iOS / Linux）

- 推送 `v*` tag 后自动产出多平台安装包并附加到对应 Release：
  - **Android**：4 个 ABI 的 APK（`build-apk.yml`）
  - **Linux**：`proxypin-<版本>-linux-amd64.deb`（`build-deb.yml`；arm64 待 Flutter 官方 Linux arm64 SDK）
  - **Windows**：`proxypin-<版本>-windows-x64.zip`（免安装，解压即用，`build-desktop.yml`）
  - **macOS**：`proxypin-<版本>-macos.zip`（含 `ProxyPin.app`，未签名，首次打开需右键→打开，`build-desktop.yml`）
  - **iOS**：`proxypin-<版本>-ios-unsigned.ipa`（未签名，需自行用证书重签安装，`build-ios.yml`）
- 各工作流彼此独立并带 `continue-on-error`：==任一平台构建失败都不会影响其它产物发布==
- 排查要点：`continue-on-error` 会掩盖单个 job 失败，需到 Actions 里逐个 job 看步骤状态；Linux 桌面构建依赖 `libayatana-appindicator3-dev`（`tray_manager` 需要）
- 实现位置：`.github/workflows/build-apk.yml`、`build-deb.yml`、`build-desktop.yml`、`build-ios.yml`

## 重写规则列表排序（最新在上）

- 重写规则列表中，==最新添加 / 导入的规则显示在最上面==，不必再往下翻找（上游 #926）
- 说明：==仅改变显示顺序，不改变存储顺序==——规则的匹配语义与导出顺序保持不变，不会因排序影响命中结果
- 桌面端与移动端一致；行内开关、双击编辑、右键菜单、多选导出 / 删除仍按真实规则索引工作

## 国际化（多语言）覆盖

- 新功能界面（WebSocket 流量推送、加密分享、SOCKS5 协议、便携模式提示等）已全部接入多语言，跟随系统语言或「偏好设置 → 语言」切换
- 语言资源：`lib/l10n/app_en.arb`（模板）、`app_zh.arb`、`app_zh_Hant.arb` 为主，其余语言缺失键自动回退英文
- ==构建期自动生成==：`pubspec.yaml` 中 `generate: true`，`flutter build` 时会由 gen-l10n 从 ARB 重新生成 `app_localizations*.dart`，因此新增文案只需改 ARB 并加代码引用
- 开发提示：新增界面文案请在 ARB 中加键（英文模板必填），并用 `AppLocalizations.of(context)!.<key>` 引用，不要在代码里写死中文

## MCP 配置资源脱敏

- 通过 MCP 读取 `proxypin://config/current` 时，==敏感字段（AI API Key、mTLS 私钥路径、上游代理口令）已脱敏为 `***`==，避免经 AI 对话 / SSE 泄露
- 配置文件刷新日志同样脱敏
- 实现位置：`lib/network/bin/configuration.dart`（`redactSecrets`）、`lib/network/mcp/mcp_server.dart`（`_readResource`）

## Windows 全局接管（上游 #577）

- 背景：Windows 上只设置 WinINET 系统代理时，==自带网络栈的应用（如微信）、使用 WinHTTP 的组件、CLI 工具、Sandboxie 沙箱内程序==都不会走代理，于是出现"Sandboxie 里的微信抓不到包"
- ==本版提供「Windows 接管增强」（分层代理，安全可回滚）==：在系统代理之外叠加
  - **WinHTTP 代理**（`netsh winhttp set proxy`）——覆盖使用 WinHTTP 的服务与部分应用（需管理员）
  - **用户环境变量** `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY`（含小写）——覆盖 curl / git / node / 包管理器 / 容器等
- 入口：桌面端「偏好设置 → Windows 接管增强」；==随抓包启动自动应用、抓包停止时自动还原==；设置页实时显示 管理员 / Sandboxie / wintun.dll 检测状态
- 实现位置：`lib/network/util/windows_takeover.dart`；联动：代理启停（`lib/network/bin/server.dart` 的 start/stop）
- ==仍未覆盖==：自行直连（含沙箱内自带网络栈）的应用——这类必须使用**真正的 TUN**（内核级虚拟网卡 WinTun + 用户态 TCP/IP 协议栈），属原生/驱动级工程且需驱动签名，==本版未启用==（误加路由会直接断网，故不做半成品）
- 规避建议：Sandboxie 内应用优先尝试"增强接管"；或用支持 TUN 的代理工具作为上游。后续版本将评估引入 WinTun 数据包转发组件

## MCP 局域网访问（安全默认）

- MCP Server ==默认仅监听 `127.0.0.1`==（更安全）；需要局域网 / 其它设备访问时，在「偏好设置 → 允许局域网访问」显式开启（开启后监听 `0.0.0.0`，==且无鉴权，请谨慎==）
- 开关即时生效：切换后自动重启 MCP 服务
- `tools/call` 增加==参数校验与 120 秒超时保护==；工具内部失败统一以 `isError: true` 返回，便于客户端区分成功/失败
- 实现位置：`lib/network/mcp/mcp_server.dart`、`lib/network/bin/configuration.dart`（`mcpAllowLan`）

## 请求对比（Diff）

- 在请求列表中进入==多选（勾选）==，选中**恰好两条请求**，点工具栏的「对比」按钮即可打开对比分析页（桌面端与移动端一致）
- 页面按四个标签展示差异：**概览**（URL / 方法 / 变化统计 / 详细报告）、**请求头**、**请求体**、**响应**（状态码 / 响应头 / 响应体）
- ==说明==：该对比页面与算法此前"已实现但从未接入"，且引用了不存在的 `Request`/`Response` 类型（从未被编译）；本轮修正为 `HttpRequest`/`HttpResponse` 并接入列表
- 实现位置：`lib/ui/component/request_compare_page.dart`（页面）、`lib/network/util/request_comparator.dart`（对比算法）、`SelectionActionBar` 的 `onCompare`（入口）

## 去缓存（Anticache）

- 入口：偏好设置 →「去缓存（Anticache）」开关（移动端 / 桌面端一致）
- 作用：请求发出前==剥离 `If-Modified-Since` / `If-None-Match` / `If-Range`，并强制 `Cache-Control/Pragma: no-cache`==，让服务端每次真正回源、返回完整响应——避免命中 304 拿不到 body，便于抓包与调试
- ==下次启动抓包生效==（拦截器在代理启动时装配）
- 实现位置：`lib/network/components/anti_cache_interceptor.dart`（`Interceptor`，priority 10，先于改写/脚本清理请求头）、`lib/network/bin/server.dart`（按 `antiCacheEnabled` 注册）、`lib/network/bin/configuration.dart`（配置项）
- 参考竞品：mitmproxy 的 anticache、Proxyman 的 No Caching
