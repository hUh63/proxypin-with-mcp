# 脚本开发指南

脚本可以拦截并修改代理经过的请求与响应，适合 mock 数据、改写参数、自动加签、注入测试数据等场景。

## 工作方式

每个脚本是一个 JavaScript 文件，引擎提供两个钩子，按需实现：

```javascript
// 请求发出前调用，返回修改后的请求；返回 null 表示不拦截
function onRequest(request) {
  return request;
}

// 响应返回前调用，返回修改后的响应
function onResponse(request, response) {
  return response;
}
```

## 常用对象字段

### 请求对象 request

| 字段 / 方法 | 说明 |
|---|---|
| `request.url` | 完整请求地址 |
| `request.method` | GET / POST 等 |
| `request.headers` | 请求头，可直接赋值修改 |
| `request.body` | 请求体文本 |
| `request.queryParameter` | 查询参数 |

### 响应对象 response

| 字段 / 方法 | 说明 |
|---|---|
| `response.status.code` | 状态码，可直接赋值 |
| `response.headers` | 响应头 |
| `response.body` | 响应体文本 |

## 多值响应头（Set-Cookie 等）

同一个名字可能出现多次的头（最典型是 `Set-Cookie`），在脚本里统一以**字符串数组**给出；只有一个值的头仍是普通字符串。

```javascript
function onResponse(request, response) {
  // 单值头：字符串
  console.log(response.headers["content-type"]);

  // 多值头：数组，逐条处理，不要拼接成一个字符串
  var cookies = response.headers["set-cookie"];
  if (Array.isArray(cookies)) {
    response.headers["set-cookie"] = cookies.map(function (c) {
      return c + "; Secure";   // 例：给每条 Cookie 追加 Secure
    });
  }
  return response;
}
```

**为什么不能合并**：`Set-Cookie` 用分号分隔 Cookie 的各个属性（Path / Domain / Expires …）。一旦把多条合并成一条字符串，客户端会把第二条之后的内容当成第一条的属性来解析，导致会话 Cookie 丢失、登录态异常。

**实现细节**（`lib/network/components/js/script_engine.dart` → `headersForScript`）：值个数为 1 时输出字符串、大于 1 时输出字符串数组；回写时数组走 `addValues`（逐条保留）、字符串走 `set`（覆盖单条）。**与抓包转发的联动**：无论脚本是否改写响应头，转发层都会按多值头逐条写出；可在「请求详情 → 响应头」核对每一条 `Set-Cookie`。**兼容性**：既有脚本读取单值头的写法（`response.headers["x"]`）行为完全不变。

## 加载第三方 JS 库（require）

上游 #719：脚本内可加载远程 JS 库，不必把依赖代码整段粘贴进脚本。

```javascript
async function onRequest(context, request) {
  // 按 URL 拉取并执行，返回该库的 module.exports（同 URL 只拉取一次，自动缓存）
  const utils = await require('https://example.com/my-utils.js');
  request.headers['x-sign'] = utils.sign(request.body);
  return request;
}
```

- `require(url)` 与别名 `loadLibrary(url)` 均已提供，返回 Promise，**必须 await**
- 库以 CommonJS 风格执行：可写 `module.exports = {...}` / `exports.foo = ...`；也可把 API 挂到 `globalThis`，加载后直接调用
- 依赖网络（走引擎内置 `fetch`），失败会抛出带原因的异常，可在脚本日志中查看
- 所以钩子需声明为 `async`（`onRequest` / `onResponse` 均支持）

**实现细节**（`lib/network/components/js/require.dart`）：运行时初始化时注入全局 `require`，内部用 `fetch` 取源码 → `new Function('module','exports','require','globalThis','console', code)` 包装执行 → 结果按 URL 缓存到 `globalThis.__proxypinModuleCache`。**与其它功能的联动**：拉取走的是引擎自带网络栈（不受抓包代理影响），但脚本身份与请求改写仍受「脚本启用状态」「脚本执行顺序」控制。

## 示例

### 修改响应状态码

```javascript
function onResponse(request, response) {
  response.status.code = 200;
  return response;
}
```

### Mock 一段 JSON 数据

```javascript
function onResponse(request, response) {
  if (request.url.indexOf("/api/user") > -1) {
    response.body = JSON.stringify({
      id: 1,
      name: "ProxyPin"
    });
    response.headers["content-type"] = "application/json";
  }
  return response;
}
```

### 给请求统一加签名头

```javascript
function onRequest(request) {
  request.headers["x-sign"] = "demo";
  return request;
}
```

## 使用建议

- 脚本按启用状态依次执行，多个脚本同时启用时会链式生效。
- 修改 JSON 时建议先解析再改字段，避免直接拼接字符串。
- 脚本异常会跳过该脚本并记录日志，可在「工具箱 → 性能/日志」中排查。
