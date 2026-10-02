# 字节系 / 抖音签名与抓包指南

> 本指南配合「工具箱 → 字节签名」使用。请仅在你**拥有授权**的设备与账号上使用。

## 一、这个工具能做什么

抖音等字节系 App 的请求带有一组**动态签名头**（业内俗称「六神 / 七神签名」）。签名由 App 端算法生成，服务端校验——因此**直接改包会导致签名失效、请求被拒**。

本工具把公开逆向资料里的签名算法内置为纯 JS 引擎（`assets/js/douyin_sign.js`），输入 URL 与请求体即可算出对应签名头，用于：

- 抓包后**分析**签名组成；
- 改包后**重算签名**再重放；
- 在脚本里**自动补签**，让改动后的请求仍能发送。

## 二、签名头速查

| 头 | 含义 | 本工具 |
| --- | --- | --- |
| `X-Khronos` | 秒级时间戳，防重放 | ✅ |
| `X-Gorgon` | 主签名（Android 8404 / iOS 变体） | ✅ |
| `X-Helios` | Feistel 派生签名（Android / iOS 两版） | ✅ |
| `X-SS-Stub` | 请求体的 32 位大写 MD5（GET 无 body 不带） | ✅ |
| `X-Argus` | 安全 SDK 动态码 | ⚠️ 回退实现（原生库不可用） |
| `X-Ladon` | 设备许可 token | ⚠️ 回退实现 |
| `X-TT-Trace-Id` | 链路追踪 ID | ✅ |
| `X-Bogus` / `a_bogus` | **Web 端**签名 | ✅ |

## 三、快捷键用法

1. 抓包里复制目标请求的 **URL**（或仅 `?` 之后的查询串）与 **Body**；
2. 打开「工具箱 → 字节签名」，选平台（Android / iOS），粘贴、点「生成」；
3. 得到各签名头，可逐个复制或「全部复制」；
4. 在重放 / 改写请求时带上这些头。

> Web 端（douyin.com）用第二个标签页算 `X-Bogus` / `a_bogus`。

## 四、在脚本里自动补签

签名库已注入脚本引擎，脚本中可直接调用 `DouyinSign.*`：

```js
async function onRequest(context, request) {
  // 仅对抖音 web 域补签
  if (request.url.indexOf('douyin.com') >= 0) {
    var q = request.url.indexOf('?') >= 0 ? request.url.split('?')[1] : '';
    request.headers['X-Bogus'] = DouyinSign.xBogus(q, '');
    request.headers['a_bogus'] = DouyinSign.aBogus(q, '');
  }
  return request;
}
```

可用方法：`DouyinSign.xgorgon({query, body, khronos, rand})`、`helios({...})`、
`xssStub(body)`、`khronos()`、`sevenGods({query, body, platform})`、`xBogus(query, body)`、
`aBogus(query, userAgent)`。返回值均为字符串/对象，可直接写入 `request.headers`。

## 五、设备与「抓不到」的常见原因

部分 App（含抖音）会做**证书固定 / 双向校验**，仅把代理 CA 装到用户区仍抓不到明文。常见处理：

- 设备 **root** 后把自签 CA 安装为**系统级**证书（Magisk「Move Certificates」或 KernelSU/APatch 模块）；
- 或用其自有网络库的适配方案（需严格对应 **App 版本 + CPU 架构**，例如 `arm64-v8a`），替换后务必修复权限与 SELinux 上下文（`chmod 755` / `chown system:system` / `restorecon -F`），否则会启动闪退；
- 校验方式：`grep <so> /proc/$(pidof <pkg>)/maps` 能看到映射即已加载。

> 版本/架构不匹配会直接失效，操作前务必备份原始文件。

## 六、版本耦合与参数化

算法默认对齐 **v40.5.0**（`aid=1128`）。官方更新后常量可能变化，因此在「参数」标签页把
`AID / 应用版本 / 版本号 / License ID / MSSDK 版本号` 暴露为可改项——**不改代码即可适配新版本**；
算法本身与 Dart 代码解耦（都在 JS 库里），必要时替换 `assets/js/douyin_sign.js` 即可。

## 七、已纳入 / 未纳入

- **已纳入**：X-Gorgon（Android 8404 + iOS 变体，均以参考实现逐字节校验通过）、X-Helios
  （Android / iOS）、X-SS-Stub、X-Khronos、X-TT-Trace-Id、X-Argus / X-Ladon（回退）、
  X-Bogus、a_bogus，以及底层的 MD5 / SM3(变体) / AES-128 / RC4。
- **未纳入**：`X-Medusa`、`TTEncrypt v5`——前者依赖 Protobuf 与自研 AES 表，后者依赖官方原生库，
  移植与校验成本高，暂不内置。

## 八、免责声明

以上算法来自公开逆向资料，**仅供安全研究与授权测试**。请遵守当地法律法规及相关平台的服务条款，
勿用于未授权场景。
