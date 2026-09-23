# 计算器与批处理

> 工具箱里的「计算器」和 MCP 的 `calculator` / `batch` 工具，**共用同一套 Dart 引擎**
> （`lib/network/util/calc_engine.dart`）。所以你在界面上算出来的结果，和让 AI 算出来的
> 结果是同一份实现，不会互相打架。

---

## 1. 工具箱 → 计算器

五个页签，都是抓包 / 协议分析最常用的：

| 页签 | 解决什么问题 |
|---|---|
| **进制/补码** | `0xFFFF` 到底是 65535 还是 -1？按 8/16/32/64 位给出无符号与**有符号补码**、二进制、八进制、大端/小端十六进制、ASCII |
| **位运算** | and / or / xor / not / shl / shr（逻辑右移）/ **sar（算术右移）** / **rol / ror（循环移位）**，可设 8/16/32/64 位宽 |
| **字节序** | 把 `0x78563412` 从大端翻成小端。支持按字节宽度或按输入长度 |
| **IEEE754** | 十六进制机器码 ↔ 浮点值：拆出符号位、指数、尾数与数值分类（normal / subnormal / infinity / nan）|
| **CRC/哈希** | crc32 / crc16-ccitt / crc16-modbus / crc16-xmodem / crc16-ibm，以及 md5 / sha1 / sha256 / sha512 |

结果区的每一行都能**点一下复制**。输入格式（hex / utf8 / base64）可切换。

另外「编码器」页也补了 **Hex 编解码**（原来只有 URL / Base64 / Unicode / MD5）。

---

## 2. MCP 工具 `calculator`

一个工具，30 个运算，用 `op` 选择。

```json
{ "op": "int_convert", "value": "0xFFFF", "width": 16 }
{ "op": "crc",         "algorithm": "crc16_modbus", "data": "31 32 33", "inputFormat": "hex" }
{ "op": "bitwise",     "operation": "rol", "a": "0x80000001", "b": "1", "width": 32 }
{ "op": "ieee754",     "value": "0x3f800000", "precision": "float32" }
{ "op": "endian_swap", "value": "0x78563412", "widthBytes": 4 }
```

| 分组 | op |
|---|---|
| 数制与二进制 | `int_convert` `bitwise` `endian_swap` `ieee754` `crc` `hash` `mod_op` `codec` |
| 基础算术 | `add` `subtract` `multiply` `division` `modulo` `sum` `floor` `ceiling` `round` |
| 统计 | `mean` `median` `mode` `min` `max` |
| 三角函数 | `sin` `cos` `tan` `arcsin` `arccos` `arctan` `degrees_to_radians` `radians_to_degrees` |

几点说明：

- 整数运算走 **大整数**，`add` / `multiply` 这类不会因为超出 64 位而丢精度；除法会同时给出商与余数。
- `bitwise` 里 `shr` 是**逻辑**右移（把值当无符号看），`sar` 是**算术**右移（保留符号）——这两个在解析协议字段时经常搞混。
- `inputFormat` 支持 `hex` / `utf8` / `base64`，`data` 里可以带空格或 `0x` 前缀，会被自动清理。

---

## 3. MCP 工具 `batch`：一次调用跑多步

MCP 每一步调用都有一次往返开销。当一个任务要串好几步（比如"解 base64 → 换字节序 → 算 CRC"），
`batch` 让你在**一次调用**里按序执行，并引用前面的结果。

```json
{
  "steps": [
    { "tool": "calculator", "args": { "op": "codec", "action": "from_base64", "input": "c2VjcmV0" } },
    { "tool": "calculator", "args": { "op": "endian_swap", "value": {"$step": 0, "field": "result"}, "widthBytes": 4 } },
    { "tool": "calculator", "args": { "op": "crc", "algorithm": "crc32", "data": {"$step": 1, "field": "input_be_hex"}, "inputFormat": "hex" } }
  ]
}
```

**引用语法**：`{"$step": 序号, "field": "字段路径"}`

- `$step` 是前面步骤的序号（从 0 开始）
- `field` 支持点路径，如 `"result.hex"`；省略 `field` 就是取整份结果
- 引用可以出现在 `args` 的任意深度（嵌套在对象或数组里都行）

**行为与限制**：

| 项 | 说明 |
|---|---|
| 执行顺序 | 严格按 `steps` 数组顺序 |
| 出错处理 | 默认遇到第一个失败就停（`stop_on_error: false` 可改为继续跑完）|
| 最大步数 | 20（防止一次请求把服务拖住）|
| 嵌套 | **不允许** `batch` 里再调 `batch` |
| 审计 | 每一步都会留下独立的调用记录，可在 `get_mcp_audit` 里按 `caller: batch` 过滤 |

每一步都走与普通调用**完全相同**的入口，所以参数校验、并发闸、超时、指标、审计一个都不会少。

---

## 4. 常见用法

**用 AI 分析一段报文**
> "这段响应的第 3 个字段是 4 字节小端浮点，帮我解出来" → AI 会调 `calculator` 的 `ieee754` + `endian_swap`。

**校验和不对**
> "帮我确认这个报文的 CRC16-Modbus 是否正确" → `calculator` 的 `crc`。

**一串转换**
> "把这串 base64 解开、转成十六进制、算 sha256" → 一个 `batch` 搞定，省掉三次往返。

---

## 5. 实现位置

| 文件 | 职责 |
|---|---|
| `lib/network/util/calc_engine.dart` | 全部 30 个运算的实现，纯函数，UI 与 MCP 共用 |
| `lib/ui/toolbox/calculator_page.dart` | 工具箱里的五个页签 |
| `lib/network/mcp/mcp_server.dart` | `calculator` 与 `batch` 两个工具的接入 |

计算引擎是完全无状态的：给定相同输入必然得到相同输出，不读配置、不写文件、不发起网络请求。
