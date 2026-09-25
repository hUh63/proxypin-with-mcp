# 云端协同服务端指南

> 客户端入口：工具箱 → **云端协同**。
> 服务端由你自己部署——本仓库不托管任何云服务，只有一个可运行的参考实现。

---

## 一、它提供什么

| 能力 | 说明 |
|---|---|
| 账号 | 注册 / 登录，返回 Bearer token；密码加盐哈希存储，不存明文 |
| 云端托管 | 工作区（标准 HAR）存服务端，版本号 `rev` 递增，支持乐观并发控制 |
| 多人实时协同 | WebSocket 长连接，工作区变更与在线成员实时广播 |
| 团队 | 成员之间共享同一批工作区；带在线状态 |

客户端侧是完整的：账号、推送/拉取、实时事件、成员列表、冲突提示都在「云端协同」页里。

---

## 二、接口契约

统一 `Authorization: Bearer <token>`（除注册/登录）。错误响应 `{"error":"..."}`。

### 账号

| 方法 | 路径 | 请求 | 响应 |
|---|---|---|---|
| POST | `/auth/register` | `{username,password}` | `{token,username,displayName}` |
| POST | `/auth/login` | `{username,password}` | `{token,username,displayName}` |

### 工作区

| 方法 | 路径 | 请求 | 响应 |
|---|---|---|---|
| GET | `/workspaces` | — | `{workspaces:[{id,name,description,updatedAt,requestCount,rev}]}` |
| POST | `/workspaces` | `{name,description,har}` | `{id,rev}` |
| PUT | `/workspaces/{id}` | `{name,description,har,rev}` | `{id,rev}`；`rev` 不匹配返回 **409** |
| GET | `/workspaces/{id}` | — | `{id,name,har,rev}` |
| DELETE | `/workspaces/{id}` | — | `{ok:true}` |

### 团队

| 方法 | 路径 | 请求 | 响应 |
|---|---|---|---|
| GET | `/members` | — | `{members:[{username,online}]}` |
| POST | `/members` | `{username}` | `{ok:true}` |

### 实时

`GET /ws?token=<token>` 升级为 WebSocket。服务端下行 JSON：

```json
{"type":"workspace.updated","data":{"id":"abc","by":"alice"}}
{"type":"workspace.created","data":{"id":"abc","by":"bob"}}
{"type":"workspace.deleted","data":{"id":"abc","by":"bob"}}
{"type":"presence","data":{"online":["alice","bob"]}}
```

客户端可上行 `{"type":"ping"}` 保活（服务端回 `pong`，或直接忽略）。
**事件不会回给发起者自己**——避免自己刚写完又刷一遍。

---

## 三、参考实现（Node.js）

只要一个依赖：

```bash
npm i ws
node cloud-server.js
# 默认 http://0.0.0.0:8788，数据落在 ./cloud-data/db.json
```

环境变量：`PORT`（默认 8788）、`DATA`（数据目录）、`SECRET`（token 签名密钥，**务必改**）。

```js
// cloud-server.js — ProxyPin 云端协同服务端（参考实现）
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8788;
const DATA = process.env.DATA || path.join(__dirname, 'cloud-data');
const SECRET = process.env.SECRET || 'please-change-this-secret';

fs.mkdirSync(DATA, { recursive: true });
const DB_FILE = path.join(DATA, 'db.json');

let db = { users: {}, workspaces: {}, members: [] };
if (fs.existsSync(DB_FILE)) {
  try {
    const loaded = JSON.parse(fs.readFileSync(DB_FILE, 'utf8'));
    db = { users: loaded.users || {}, workspaces: loaded.workspaces || {}, members: loaded.members || [] };
  } catch (e) {
    console.error('db.json 损坏，从空库开始:', e.message);
  }
}
let saveTimer = null;
const save = () => {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    fs.writeFileSync(DB_FILE + '.tmp', JSON.stringify(db));
    fs.renameSync(DB_FILE + '.tmp', DB_FILE);   // 原子替换，避免写一半断电
  }, 200);
};

// ---------- 账号 ----------
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
const newSalt = () => crypto.randomBytes(16).toString('hex');

function makeToken(username) {
  const payload = Buffer.from(`${username}.${Date.now()}`).toString('base64url');
  const sig = crypto.createHmac('sha256', SECRET).update(payload).digest('hex').slice(0, 32);
  return `${payload}.${sig}`;
}
function verifyToken(token) {
  if (!token || !token.includes('.')) return null;
  const idx = token.lastIndexOf('.');
  const payload = token.slice(0, idx);
  const sig = token.slice(idx + 1);
  const expect = crypto.createHmac('sha256', SECRET).update(payload).digest('hex').slice(0, 32);
  if (sig.length !== expect.length) return null;
  if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expect))) return null;
  const username = Buffer.from(payload, 'base64url').toString().split('.')[0];
  return db.users[username] ? username : null;
}

// ---------- 实时 ----------
const clients = new Map();   // ws -> username
function broadcast(type, data, exceptWs) {
  const msg = JSON.stringify({ type, data });
  for (const [ws, user] of clients) {
    if (ws === exceptWs) continue;
    if (ws.readyState === 1) ws.send(msg);
  }
}
function broadcastPresence() {
  broadcast('presence', { online: [...new Set(clients.values())] });
}

// ---------- HTTP ----------
const json = (res, code, obj) => {
  const body = JSON.stringify(obj);
  res.writeHead(code, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) });
  res.end(body);
};
const readBody = (req) => new Promise((resolve) => {
  let s = '';
  req.on('data', (c) => { s += c; if (s.length > 32 * 1024 * 1024) req.destroy(); });
  req.on('end', () => { try { resolve(JSON.parse(s || '{}')); } catch { resolve({}); } });
});
/** 可见的工作区：自己的 + 团队成员共享的 */
const visibleIds = (username) =>
  Object.values(db.workspaces).filter((w) => w.owner === username || db.members.includes(username) === (w.owner !== username) || w.owner === username || db.members.includes(username)).map((w) => w.id);

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const parts = url.pathname.split('/').filter(Boolean);
  const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  const user = verifyToken(token);

  // ---- 账号 ----
  if (req.method === 'POST' && parts[0] === 'auth') {
    const b = await readBody(req);
    const username = String(b.username || '').trim();
    const password = String(b.password || '');
    if (!/^[\w.\-@]{2,32}$/.test(username)) return json(res, 400, { error: 'invalid username' });
    if (password.length < 6) return json(res, 400, { error: 'password must be at least 6 chars' });

    if (parts[1] === 'register') {
      if (db.users[username]) return json(res, 409, { error: 'username already taken' });
      const salt = newSalt();
      db.users[username] = { salt, hash: sha(salt + password), createdAt: new Date().toISOString() };
      if (!db.members.includes(username)) db.members.push(username);
      save();
      return json(res, 200, { token: makeToken(username), username, displayName: username });
    }
    if (parts[1] === 'login') {
      const u = db.users[username];
      if (!u || u.hash !== sha(u.salt + password)) return json(res, 401, { error: 'invalid credentials' });
      return json(res, 200, { token: makeToken(username), username, displayName: username });
    }
    return json(res, 404, { error: 'not found' });
  }

  // 以下都要登录
  if (!user) return json(res, 401, { error: 'unauthorized' });

  // ---- 成员 ----
  if (parts[0] === 'members') {
    if (req.method === 'GET') {
      const online = new Set(clients.values());
      return json(res, 200, { members: db.members.map((m) => ({ username: m, online: online.has(m) })) });
    }
    if (req.method === 'POST') {
      const b = await readBody(req);
      const name = String(b.username || '').trim();
      if (!db.users[name]) return json(res, 404, { error: 'no such user' });
      if (!db.members.includes(name)) {
        db.members.push(name);
        save();
        broadcast('members.updated', { username: name, by: user });
      }
      return json(res, 200, { ok: true });
    }
  }

  // ---- 工作区 ----
  if (parts[0] !== 'workspaces') return json(res, 404, { error: 'not found' });

  // 列表：团队共享，所以成员能看到彼此的工作区
  if (req.method === 'GET' && parts.length === 1) {
    const list = Object.values(db.workspaces)
      .filter((w) => db.members.includes(w.owner) || w.owner === user)
      .map((w) => ({
        id: w.id, name: w.name, description: w.description,
        updatedAt: w.updatedAt, requestCount: w.requestCount || 0, rev: w.rev || 1,
        owner: w.owner,
      }));
    return json(res, 200, { workspaces: list });
  }

  if (req.method === 'POST' && parts.length === 1) {
    const b = await readBody(req);
    const id = crypto.randomBytes(9).toString('hex');
    const har = b.har || null;
    const entries = har && har.log && Array.isArray(har.log.entries) ? har.log.entries.length : 0;
    db.workspaces[id] = {
      id, owner: user, name: b.name || id, description: b.description || '',
      har, requestCount: entries, rev: 1, updatedAt: new Date().toISOString(),
    };
    save();
    broadcast('workspace.created', { id, name: db.workspaces[id].name, by: user });
    return json(res, 200, { id, rev: 1 });
  }

  const id = parts[1];
  const ws = id ? db.workspaces[id] : null;

  if (req.method === 'PUT' && parts.length === 2) {
    if (!ws) return json(res, 404, { error: 'not found' });
    const b = await readBody(req);
    // 乐观并发：带上你会话里的 rev，对不上说明别人已经改过
    if (typeof b.rev === 'number' && b.rev !== ws.rev) {
      return json(res, 409, { error: 'conflict', rev: ws.rev });
    }
    ws.name = b.name || ws.name;
    ws.description = b.description ?? ws.description;
    if (b.har !== undefined) {
      ws.har = b.har;
      ws.requestCount = b.har && b.har.log && Array.isArray(b.har.log.entries) ? b.har.log.entries.length : 0;
    }
    ws.rev = (ws.rev || 1) + 1;
    ws.updatedAt = new Date().toISOString();
    save();
    broadcast('workspace.updated', { id, name: ws.name, rev: ws.rev, by: user });
    return json(res, 200, { id, rev: ws.rev });
  }

  if (req.method === 'GET' && parts.length === 2) {
    if (!ws) return json(res, 404, { error: 'not found' });
    return json(res, 200, { id: ws.id, name: ws.name, har: ws.har, rev: ws.rev || 1 });
  }

  if (req.method === 'DELETE' && parts.length === 2) {
    if (!ws) return json(res, 404, { error: 'not found' });
    delete db.workspaces[id];
    save();
    broadcast('workspace.deleted', { id, by: user });
    return json(res, 200, { ok: true });
  }

  return json(res, 405, { error: 'method not allowed' });
});

// ---------- WebSocket ----------
const wss = new WebSocketServer({ noServer: true });
server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname !== '/ws') return socket.destroy();
  const username = verifyToken(url.searchParams.get('token') || '');
  if (!username) return socket.destroy();
  wss.handleUpgrade(req, socket, head, (ws) => {
    clients.set(ws, username);
    ws.send(JSON.stringify({ type: 'presence', data: { online: [...new Set(clients.values())] } }));
    broadcastPresence();
    ws.on('message', (raw) => {
      try {
        const m = JSON.parse(raw.toString());
        if (m.type === 'ping') ws.send(JSON.stringify({ type: 'pong' }));
      } catch { /* 忽略坏帧 */ }
    });
    ws.on('close', () => { clients.delete(ws); broadcastPresence(); });
    ws.on('error', () => { clients.delete(ws); broadcastPresence(); });
  });
});

server.listen(PORT, '0.0.0.0', () =>
  console.log(`proxypin cloud server on http://0.0.0.0:${PORT}\n  data   = ${DATA}\n  secret = ${SECRET === 'please-change-this-secret' ? '(默认值！生产环境必须改)' : '(已自定义)'}`));
```

---

## 四、部署

先分清部署在哪 —— 两种场景的默认姿势不一样：

| | 内网机器 | 云主机（公网） |
|---|---|---|
| 监听地址 | `0.0.0.0`，同网段都能连 | `127.0.0.1`，公网只从反代进 |
| 对外协议 | HTTP 就够 | **必须 HTTPS**（WSS 自动跟着走） |
| 对外端口 | 8788 | 只开 443，8788 不对外 |
| `SECRET` | 也要改 | 必须换成足够长的随机串 |
| 客户端填 | `http://192.168.x.x:8788` | `https://cloud.example.com` |
| 备份 | 手动拷 `db.json` | 定时拷 + 异地留一份 |

下面给两种跑法；**同时部署两套**（内网一台 + 云上一台）见 4.3。

### 4.1 内网机器（同网段直连）

1. 服务端监听全网卡：`Environment=HOST=0.0.0.0`
2. 放行入站端口：
   - ufw：`sudo ufw allow 8788/tcp`
   - firewalld：`sudo firewall-cmd --add-port=8788/tcp --permanent && sudo firewall-cmd --reload`
   - Windows：高级安全防火墙 → 入站规则 → 新建 → 端口 → 8788 → 允许
3. 查这台机器的内网 IP：`ip addr`（Linux）/ `ipconfig`（Windows）
4. 客户端填 `http://<内网IP>:8788`

**两个容易踩的点：**

- **IP 会变**：路由器 DHCP 续租后地址可能变，客户端就得重填。给这台机器配静态 IP 或 DHCP 保留；用 `hostname.local`（mDNS）也行，但需要网段里有 avahi/Bonjour 解析。
- **HTTP 是明文**：内网也一样。同网段的其他设备（同事电脑、访客 Wi-Fi、智能家居）都能在网线上读到你的 token 和抓包数据。介意的话按 4.2 加一层证书。

### 4.2 云主机（公网）

**别把 8788 直接开到公网。** 让服务端只监听本机，前面放一层反代做 TLS：

1. 服务端只听本机：`Environment=HOST=127.0.0.1`
2. 安全组 / 防火墙只放行 443（和 SSH），**不要开放 8788**
3. Nginx 反代：

```nginx
server {
    listen 443 ssl;
    server_name cloud.example.com;

    ssl_certificate     /etc/letsencrypt/live/cloud.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/cloud.example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8788;
        proxy_http_version 1.1;

        # 实时协同走 WebSocket，这两行不能少
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 3600s;   # 实时连接是长连接，别让它被掐断
    }
}
```

证书用 certbot 签：`sudo certbot --nginx -d cloud.example.com`。

4. 客户端填 `https://cloud.example.com` —— 客户端会自动把实时连接换成 `wss://`，不用手填。

> **最容易漏的是 WebSocket 那两行**：漏了之后注册、登录、上传都正常，只有「实时协同」开关一直连不上，很容易误判成服务端坏了。

### 4.3 内网和云上同时跑

两边各跑一份、各存各的数据，客户端**同一时刻只能连一个**。三种做法：

- **手动切地址**（最省事）：换网络时改一下客户端里的地址。适合"公司一台、家里一台"这种整段时间在同一网络的场景。
- **把内网那台从云上穿出去**：云主机上做反向隧道
  （`ssh -R 8788:127.0.0.1:8788 user@cloud`），再用 Nginx 反代到这条隧道。
  这样客户端始终填一个云上地址、走到哪都能用，**而数据仍然留在你自己内网那台机器上**。
- **组网直连**：Tailscale / WireGuard 把两边拉进一个虚拟内网，客户端填虚拟网段里的地址。

不管哪种，**两边数据不会自动同步**（各存各的 `db.json`）。要么只用一边当主，要么定期把 `db.json` 拷过去覆盖。

**常驻（systemd）**

```ini
# /etc/systemd/system/proxypin-cloud.service
[Unit]
Description=ProxyPin Cloud
After=network.target

[Service]
WorkingDirectory=/opt/proxypin-cloud
ExecStart=/usr/bin/node cloud-server.js
Environment=PORT=8788
Environment=SECRET=换成你自己的随机串
Environment=DATA=/var/lib/proxypin-cloud
Restart=always
User=proxypin

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload && sudo systemctl enable --now proxypin-cloud
```

**Docker**

```dockerfile
FROM node:20-alpine
WORKDIR /app
RUN npm i ws
COPY cloud-server.js .
ENV PORT=8788 DATA=/data
VOLUME /data
EXPOSE 8788
CMD ["node", "cloud-server.js"]
```

> `npm i ws` 是唯一的依赖。不想装的话，可以把它换成自己手写的 WebSocket 升级+帧解析（约 150 行），协议部分照 RFC 6455 实现即可。

---

## 五、安全（务必看）

1. **改 `SECRET`**：默认值是公开的，不改等于没有签名。
2. **上 HTTPS/WSS**：放个 Nginx/Caddy 反代，客户端地址填 `https://...` 即可（客户端会自动把 `wss://` 用于实时连接）。裸 HTTP 会把 token 和抓包数据暴露在网线上。
3. **公网暴露前先想清楚**：这里面是你全部的抓包数据，常含 Cookie、Token、手机号。
4. **数据备份**：就一个 `db.json`，定时拷走即可（注意它是明文存 HAR 的）。
5. 客户端**直连**服务端、不经本工具的代理；如果你在这台机器上同时开着抓包，记得把服务端域名加进 `proxyPassDomains` 或白名单，避免自己抓自己。
6. **内网不等于安全**：内网部署时最容易省掉 `SECRET` 和 HTTPS —— 同网段的任何设备都能明文读到你的 token 和抓包数据。`SECRET` 无论内网还是公网都必须改。

---

## 六、客户端怎么用

1. 工具箱 → **云端协同** → 填服务端地址 → 保存
2. 注册或登录
3. 打开 **实时协同** 开关（状态变绿即已连接）
4. 「把本地工作区推上去」→ 选一个工作区上传
5. 另一台设备 / 另一位成员：登录后点刷新，就能在列表里看到，点 ⬇ 拉到本地
6. 团队成员之间的改动会**实时**推过来，页面下方的事件区能看到 `workspace.updated by alice` 这类记录

冲突时（同一份工作区两个人在改）服务端返回 409，客户端会提示——手动拉一次最新的再推。
