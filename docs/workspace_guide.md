# 工作区指南

> 把一个项目的抓包数据单独收起来，并且可以同步到**你自己的**服务端。
> 入口：工具箱 → 工作区。

---

## 一、它解决什么问题

抓的包一多，全堆在同一个列表里就没法用了：测试环境的接口、线上问题复现的、昨天那个 bug 的流量混在一起，想找回当时那批数据只能靠翻历史。

工作区提供的是**按项目/环境分桶**：

- 一个工作区 = 一个容器，装一批抓包数据；
- 数据落盘是**标准 HAR 格式**，可以直接丢给别的工具看，也能整份分享出去；
- 想回看时，「导入到历史」就能在历史记录里翻（复用已有的历史机制，不另造一套）。

工作区与「历史记录」的分工：历史是**自动流水**（抓什么存什么，按时间滚），工作区是**你手动归档的**（挑一次抓包存进去，长期留着）。

---

## 二、本地工作区

| 操作 | 说明 |
|---|---|
| 新建工作区 | 起个名字（如「支付模块」「测试环境」），本地建一条 |
| 保存当前抓包 | 把**当前列表里**的请求整体存进该工作区（覆盖式） |
| 导入到历史 | 把工作区数据读出来，作为一条历史记录导入，可在历史里查看 |
| 重命名 / 删除 | 删除会连同本地数据一起清掉，不可恢复 |

存储位置：`<数据目录>/workspaces/index.json` 存索引，`<数据目录>/workspaces/<id>/data.har` 存数据。数据目录遵循便携模式规则（桌面端把 `portable` 文件放在程序目录即启用）。

> 不配服务端也能完整使用本地工作区——服务端是**可选**的。

---

## 三、自定义服务端

想多人共享、或把数据备份到自己的机器上，就接一个服务端。契约很小，自己写一个几十行的服务就行。

### 配置

工具箱 → 工作区 → 右上角云图标，填：

- **服务端地址**：如 `http://10.0.0.5:8787`（不写 scheme 时按 `http://` 处理）
- **访问令牌**：可留空；填了会以 `Authorization: Bearer <token>` 发送

### 契约

| 方法 | 路径 | 请求体 | 响应 |
|---|---|---|---|
| GET | `/workspaces` | — | `{"workspaces":[{"id","name","description","updatedAt","requestCount"}]}` |
| POST | `/workspaces` | `{"name","description","har"}` | `{"id":"..."}` |
| PUT | `/workspaces/{id}` | `{"name","description","har"}` | `{"id":"..."}` |
| GET | `/workspaces/{id}` | — | `{"id","name","har":{...}}` |
| DELETE | `/workspaces/{id}` | — | 任意 2xx |

- `har` 字段就是标准 HAR（`{"log":{"entries":[...]}}`），可以直接落盘成 `.har` 文件。
- 客户端**直连**服务端，不经过本工具的代理端口（避免自己抓自己）。
- 首次推送走 `POST`（服务端分配 id），之后带上 `serverId` 走 `PUT` 更新。

### 参考实现（Node.js，零依赖）

保存为 `workspace-server.js`，`node workspace-server.js` 即可，默认监听 `8787`：

```js
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 8787;
const TOKEN = process.env.TOKEN || '';          // 留空则不校验
const DATA = path.join(__dirname, 'workspaces');
fs.mkdirSync(DATA, { recursive: true });
const fileOf = id => path.join(DATA, `${id}.json`);

const send = (res, code, obj) => {
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(obj));
};
const readBody = req => new Promise(resolve => {
  let s = '';
  req.on('data', c => (s += c));
  req.on('end', () => { try { resolve(JSON.parse(s || '{}')); } catch { resolve({}); } });
});

http.createServer(async (req, res) => {
  if (TOKEN && (req.headers['authorization'] || '') !== `Bearer ${TOKEN}`) {
    return send(res, 401, { error: 'unauthorized' });
  }
  const parts = req.url.split('?')[0].split('/').filter(Boolean);
  if (parts[0] !== 'workspaces') return send(res, 404, { error: 'not found' });

  if (req.method === 'GET' && parts.length === 1) {
    const list = fs.readdirSync(DATA).map(f => {
      const j = JSON.parse(fs.readFileSync(path.join(DATA, f), 'utf8'));
      return { id: j.id, name: j.name, description: j.description,
               updatedAt: j.updatedAt, requestCount: j.requestCount || 0 };
    });
    return send(res, 200, { workspaces: list });
  }

  if ((req.method === 'POST' && parts.length === 1) ||
      (req.method === 'PUT' && parts.length === 2)) {
    const b = await readBody(req);
    const id = parts[1] || Date.now().toString(36);
    const har = b.har || null;
    const entries = har && har.log && Array.isArray(har.log.entries) ? har.log.entries.length : 0;
    fs.writeFileSync(fileOf(id), JSON.stringify({
      id, name: b.name || id, description: b.description || '',
      har, requestCount: entries, updatedAt: new Date().toISOString()
    }));
    return send(res, 200, { id });
  }

  if (req.method === 'GET' && parts.length === 2) {
    if (!fs.existsSync(fileOf(parts[1]))) return send(res, 404, { error: 'not found' });
    const j = JSON.parse(fs.readFileSync(fileOf(parts[1]), 'utf8'));
    return send(res, 200, { id: j.id, name: j.name, har: j.har });
  }

  if (req.method === 'DELETE' && parts.length === 2) {
    fs.rmSync(fileOf(parts[1]), { force: true });
    return send(res, 200, { ok: true });
  }
  return send(res, 405, { error: 'method not allowed' });
}).listen(PORT, '0.0.0.0', () =>
  console.log(`workspace server on http://0.0.0.0:${PORT}  data=${DATA}`));
```

### 安全

- **一定要设 TOKEN**，哪怕是内网——这个接口拿到就能读你全部的抓包数据。
- 抓包数据里常带 Cookie、Token、手机号，别把服务端裸露到公网。
- 服务端只存 `.har`，不做任何解析，越简单越安全。

---

## 四、和「多机镜像」的配合

多台设备（手机 A、手机 B）把代理都指向同一台电脑上的 ProxyPin 时，流量会汇总到一个列表里。想只看某台设备：

- 请求详情里的 **Client Address** 就是发起方的地址；
- 搜索范围勾上 **Client Host**，输入那台设备的 IP 就能筛出来。

按设备筛完之后，正好可以「保存当前抓包」归档到对应的项目工作区。
