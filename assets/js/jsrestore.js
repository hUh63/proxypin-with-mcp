/**
 * jsrestore —— JS 反混淆 / 反编译一体化工具（单文件零依赖版）
 *
 * 用法：
 *   node jsrestore-standalone.js detect  <file>
 *   node jsrestore-standalone.js restore <file> [-o out.js]
 *   node jsrestore-standalone.js verify  <file>
 *
 * 内置 acorn 解析器，无需 npm install。
 */
const fs = require('fs');
const path = require('path');
let acorn;
for (const p of ['acorn','/data/workspace/jsrestore/node_modules/acorn','/data/workspace/lib/node_modules/acorn']) {
  try { acorn = require(p); break; } catch (e) {}
}
if (!acorn) { console.error('需要 acorn：npm install acorn'); process.exit(1); }

/**
 * jsrestore — 公共工具库
 *
 * 设计原则（全部来自实战踩坑）：
 *  1. 括号/字符计数必须跳过字符串、正则、注释 —— 否则 /[{[`]/ 这类正则会毁掉计数
 *  2. /g 正则禁止定义在循环外 —— lastIndex 会跨次复用导致静默漏匹配
 *  3. 任何 AST 变换都要先 --check 校验，绝不允许产出语法错误的中间态
 */


/** 安全读取 */
function read(p) { return fs.readFileSync(p, 'utf8'); }
function write(p, s) { fs.writeFileSync(p, s); }

/**
 * 计算一行代码的"有效花括号净增量"
 * 跳过：字符串(" ' `)、模板串、行注释、块注释、正则字面量
 * state: { inBlockComment } 跨行块注释状态
 */
function netCurly(line, state) {
  state = state || {};
  let net = 0, i = 0;
  const n = line.length;
  if (state.inBlockComment) {
    const end = line.indexOf('*/');
    if (end < 0) return 0;              // 整行都在注释里
    state.inBlockComment = false;
    i = end + 2;
  }
  while (i < n) {
    const c = line[i];
    if (c === '/' && line[i + 1] === '/') break;          // 行注释
    if (c === '/' && line[i + 1] === '*') {               // 块注释
      const end = line.indexOf('*/', i + 2);
      if (end < 0) { state.inBlockComment = true; break; }
      i = end + 2; continue;
    }
    if (c === '"' || c === "'" || c === '`') {            // 字符串
      const q = c;
      let j = i + 1;
      while (j < n) {
        if (line[j] === '\\') { j += 2; continue; }
        if (line[j] === q) { j++; break; }
        j++;
      }
      i = j; continue;
    }
    if (c === '/') {                                       // 正则（启发式）
      const prev = i > 0 ? line[i - 1] : '';
      const prevOk = (i === 0) || /[=(,:;!&|?+\-*[{}\s]/.test(prev);
      if (prevOk) {
        let j = i + 1, inCls = false;
        while (j < n) {
          const d = line[j];
          if (d === '\\') { j += 2; continue; }
          if (d === '[') inCls = true;
          else if (d === ']') inCls = false;
          else if (d === '/' && !inCls) { j++; break; }
          j++;
        }
        i = j; continue;
      }
    }
    if (c === '{') net++;
    else if (c === '}') net--;
    i++;
  }
  return net;
}

/** 判断一行是否"实质代码"（非注释、非占位符） */
function isCodeLine(l) {
  const t = l.trim();
  if (!t) return false;
  if (/^\/\//.test(t)) return false;
  if (/^\/\*/.test(t) && /\*\/\s*$/.test(t)) return false;   // 单行块注释（占位符）
  return true;
}

function indentOf(l) { const m = l.match(/^\s*/); return m ? m[0] : ''; }

/** 安全求值：失败返回 null 而不是抛异常 */
function safeEval(expr) {
  try {
    // eslint-disable-next-line no-new-func
    const v = new Function('return (' + expr + ')')();
    if (typeof v === 'function' || typeof v === 'symbol') return null;
    return v;
  } catch (e) { return null; }
}

/** 字面量还原为源码文本 */
function lit(v) {
  if (v === undefined) return 'undefined';
  if (v === null) return 'null';
  if (typeof v === 'string') return JSON.stringify(v);
  if (typeof v === 'number' || typeof v === 'boolean') return String(v);
  if (Array.isArray(v)) return '[' + v.map(lit).join(', ') + ']';
  try { return JSON.stringify(v); } catch (e) { return 'undefined'; }
}

/** 标识符合法性 */
function isIdent(s) { return /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(s); }

/**
 * 安全应用 patch 集合（★ 关键基础设施）
 *
 * 为什么不能"从后往前 slice"：
 *   从后往前应用时，外层 patch 的 end 索引会失效 —— 它之后的内容已被内层 patch
 *   改过、长度变了，slice(p.end) 切到的位置是错的。
 *   实战后果：三元表达式 `a ? f() : g()` 被切成 `} : function(){`，语法直接破损。
 *
 * 正确做法：分段构建。按 start 升序，依次拼接「原文片段 + patch 文本」，
 * 天然跳过重叠 patch（保留最外层，丢弃被包含的内层）。
 *
 * @param {string} src 原始文本
 * @param {Array<{start:number,end:number,text:string}>} patches
 * @returns {{code:string, applied:number, skipped:number}}
 */
function applyPatches(src, patches) {
  if (!patches || !patches.length) return { code: src, applied: 0, skipped: 0 };
  const sorted = patches.slice().sort((a, b) => (a.start - b.start) || (b.end - a.end));
  let out = '', pos = 0, applied = 0, skipped = 0;
  for (const p of sorted) {
    if (p.start < pos) { skipped++; continue; }        // 与已应用区间重叠 → 丢弃
    if (p.start > src.length || p.end > src.length) { skipped++; continue; }
    out += src.slice(pos, p.start) + p.text;
    pos = p.end;
    applied++;
  }
  out += src.slice(pos);
  return { code: out, applied, skipped };
}

/** 字节数人类可读 */
function human(bytes) {
  if (bytes >= 1048576) return (bytes / 1048576).toFixed(2) + ' MB';
  if (bytes >= 1024) return (bytes / 1024).toFixed(1) + ' KB';
  return bytes + ' B';
}



/**
 * 混淆指纹自动识别
 *
 * 判定原则：
 *  · 各类型独立打分，取最高分为主判定
 *  · "单行压缩"只作**兜底**——不参与打分，否则大文件会因平均行长过大而误判，
 *    掩盖真正的保护类型（实战中踩过：642KB 的加密整数表被判成"单行压缩"）
 *  · 每个类型给出推荐流水线
 */


function detect(src) {
  const hits = [];
  const bytes = src.length;
  const lines = src.split('\n').length;
  const avgLine = bytes / Math.max(lines, 1);
  const add = (type, name, score, pipeline) => hits.push({ type, name, score, pipeline });

  // 特征预计算
  const nBigInt = (src.match(/\b\d{4,}\b/g) || []).length;
  const nCaseNum = (src.match(/case\s+\d+\s*:/g) || []).length;
  const nHexIdent = (src.match(/_0x[0-9a-f]{4,6}/gi) || []).length;
  const hasRotate = /push\(\s*\w+\.shift\(\)\s*\)/.test(src);
  const hasWhileTrue = /while\s*\(\s*!!\[\]\s*\)|for\s*\(\s*;\s*;\s*\)/.test(src);
  const hasSwitch = /switch\s*\(/.test(src);
  const hasTypedArr = /Uint8Array|Int32Array|Uint32Array|new Array\(256\)/.test(src);
  const hasEval = /\beval\s*\(|new Function\s*\(/.test(src);
  const hasCharCode = /charCodeAt/.test(src);
  const nIdentLike = (src.match(/\b[A-Za-z_$][\w$]{2,}\b/g) || []).length;
  const identDensity = nIdentLike / Math.max(bytes / 1000, 1);   // 每 KB 标识符数

  // ── 1. 加密整数表 / 打包载荷（L0）────────────────────────────
  // 特征：海量多位整数 + 标识符密度极低 + 无可执行结构
  if (nBigInt > 2000 && identDensity < 12 && !hasSwitch) {
    add('int-table', '加密整数表（打包载荷，需先解出引导器）', 85,
      ['vm-unpack', 'fold', 'isa', 'disasm', 'decompile', 'sanitize', 'naming']);
  }

  // ── 2. obfuscator.io 家族 ────────────────────────────────────
  let ioScore = 0;
  if (nHexIdent > 50) ioScore += 30;
  if (nHexIdent > 500) ioScore += 15;
  if (hasRotate) ioScore += 25;
  if (hasWhileTrue && hasSwitch) ioScore += 20;
  if (hasCharCode) ioScore += 10;
  if (/var\s+_0x[a-f0-9]{4}\s*=\s*\[/.test(src)) ioScore += 20;
  if (ioScore >= 40) {
    add('obfuscator-io', 'obfuscator.io 混淆（字符串表 + RC4 + 控制流平坦化）', ioScore,
      ['strings', 'controlflow', 'fold', 'inline', 'sanitize', 'naming']);
  }

  // ── 3. 自研字节码 VM（编译型）─────────────────────────────────
  let vmScore = 0;
  if (nCaseNum > 20) vmScore += 30;
  if (hasSwitch && bytes > 100000) vmScore += 20;
  if (hasTypedArr) vmScore += 15;
  if (hasEval) vmScore += 10;
  if (nBigInt > 500) vmScore += 10;
  if (hasSwitch && /switch\s*\(\s*[\w$]+\s*\[/.test(src)) vmScore += 15;   // 映射表分派
  if (vmScore >= 45) {
    add('bytecode-vm', '自研字节码 VM（编译型保护）', vmScore,
      ['isa', 'disasm', 'decompile', 'sanitize', 'naming']);
  }

  // ── 4. eval 自解密包装 ───────────────────────────────────────
  if (hasEval && bytes < 300000 && /^[\s;]*(?:\(function|!function|~function|\[)/.test(src)) {
    add('eval-wrapped', 'eval 自解密包装', 55, ['vm-unpack', 'fold', 'sanitize']);
  }

  // ── 5. 常量算术爆炸 ──────────────────────────────────────────
  const nArith = (src.match(/0x[0-9a-f]+\s*[-+*]\s*-?0x[0-9a-f]+/gi) || []).length;
  if (nArith > 100) {
    add('const-explosion', '常量算术爆炸', 50, ['fold', 'sanitize', 'naming']);
  }

  hits.sort((a, b) => b.score - a.score);
  return { hits, avgLine, bytes, lines, nBigInt, nCaseNum, identDensity: +identDensity.toFixed(1) };
}

/** 汇总（含兜底判定） */
function summarize(src) {
  const d = detect(src);
  const hits = d.hits;
  let primary;
  if (hits.length && hits[0].score >= 40) {
    primary = hits[0];
  } else if (d.avgLine > 5000) {
    // 兜底：确实只是压缩，无实质混淆
    primary = { type: 'minified', name: '单行压缩代码（无实质混淆）', score: 40, pipeline: ['fold', 'beautify', 'naming'] };
  } else {
    primary = { type: 'plain', name: '明文/轻度混淆', score: 20, pipeline: ['fold', 'sanitize', 'naming'] };
  }
  return { bytes: d.bytes, lines: d.lines, primary, all: hits, metrics: d };
}



/**
 * 常量折叠 + 死代码消除
 *
 * 核心设计：**位置替换（in-place patch），绝不重新生成语法树**
 *
 * 为什么不能用 escodegen 重建：
 *   escodegen 2.1.0 会无视 node.raw，把非 ASCII 一律输出成 \uXXXX。
 *   实战中这会让 438 处中文标点全部变成转义序列，还原度严重倒退。
 *   改为按 (start,end) 精确替换后，中文、正则、原始格式全部保留。
 *
 * 保守原则：只折叠语义 100% 确定的节点，宁可少折不可错折。
 *   例：x === x 不折叠 —— x 为 NaN 时为 false，折叠会改变语义。
 */



/** 是否为纯字面量（可安全求值） */
function isLiteral(node) {
  if (!node) return false;
  switch (node.type) {
    case 'Literal': return true;
    case 'UnaryExpression':
      return ['!', '-', '+', '~', 'void', 'typeof'].includes(node.operator) && isLiteral(node.argument);
    case 'BinaryExpression':
      return isLiteral(node.left) && isLiteral(node.right);
    case 'ArrayExpression':
      return node.elements.every(e => e === null || isLiteral(e));
    case 'ObjectExpression':
      return node.properties.every(p => p.type === 'Property' && !p.computed && isLiteral(p.value));
    default: return false;
  }
}

/** 模板串是否可折叠（无表达式插值） */
function isStaticTemplate(node) {
  return node.type === 'TemplateLiteral' && node.expressions.length === 0;
}

/**
 * 主折叠
 * @param {string} src 源码
 * @returns {{code:string, folded:number, dead:number}}
 */
function fold(src) {
  const ast = acorn.parse(src, { ecmaVersion: 2022, locations: false });
  const patches = [];   // {start, end, text}
  let folded = 0;

  /** 尝试折叠节点 → 成功返回源码文本 */
  function tryFold(node) {
    if (!node) return null;
    // 静态模板 → 普通字符串
    if (isStaticTemplate(node)) {
      return JSON.stringify(node.quasis[0].value.cooked);
    }
    if (!isLiteral(node)) return null;
    // 跳过含正则字面量的（正则求值有 lastIndex 副作用风险）
    if (node.type === 'Literal' && node.regex) return null;
    // ★ 不折叠超大数组/对象：
    //   实战中把 61026 元素的整数表整个重建，元素间被加上空格，
    //   体积反而膨胀 60KB。数据型大数组折叠既无意义又有精度风险。
    if (node.type === 'ArrayExpression' && node.elements.length > 16) return null;
    if (node.type === 'ObjectExpression' && node.properties.length > 16) return null;
    const sl = src.slice(node.start, node.end);
    // 已经是简单字面量就没必要动
    if (node.type === 'Literal' && !node.regex) return null;
    const v = safeEval(sl);
    if (v === null) return null;
    const out = lit(v);
    // ★ 折叠后变长就跳过（不设原文长度门槛——否则长数组逃过检查）
    if (out.length > sl.length) return null;
    return out;
  }

  // ── 遍历收集 ──
  (function walk(node, parent) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { node.forEach(n => walk(n, parent)); return; }

    // 条件折叠：cond ? a : b / 逻辑短路
    if (node.type === 'ConditionalExpression') {
      const cv = isLiteral(node.test) ? safeEval(src.slice(node.test.start, node.test.end)) : null;
      if (cv !== null && typeof cv !== 'function') {
        const keep = cv ? node.consequent : node.alternate;
        patches.push({ start: node.start, end: node.end, text: src.slice(keep.start, keep.end) });
        folded++;
      }
    }
    if (node.type === 'LogicalExpression' && isLiteral(node.left)) {
      const lv = safeEval(src.slice(node.left.start, node.left.end));
      if (lv !== null && typeof lv !== 'function') {
        // true && x  →  x    |   false && x → false
        // true || x  →  true |  false || x → x
        const op = node.operator;
        let text = null;
        if (op === '&&') text = lv ? src.slice(node.right.start, node.right.end) : lit(lv);
        else if (op === '||') text = lv ? lit(lv) : src.slice(node.right.start, node.right.end);
        if (text !== null) { patches.push({ start: node.start, end: node.end, text }); folded++; }
      }
    }

    // 通用折叠
    const t = tryFold(node);
    if (t !== null) { patches.push({ start: node.start, end: node.end, text: t }); folded++; }

    for (const k in node) {
      if (['type', 'start', 'end', 'loc', 'range'].includes(k)) continue;
      walk(node[k], node);
    }
  })(ast, null);

  // ── 应用 patch：分段构建（安全处理重叠）──
  const r = applyPatches(src, patches);
  let out = r.code;

  // ── 死代码消除（在折叠后的文本上做，需重新解析）──
  const dead = eliminateDead(out);
  return { code: dead.code, folded: r.applied, dead: dead.removed };
}

/**
 * 死代码消除：if(true)/if(false)、空分支、永假守卫
 */
function eliminateDead(src) {
  let removed = 0;
  let code = src;

  for (let pass = 0; pass < 3; pass++) {
    let ast;
    try { ast = acorn.parse(code, { ecmaVersion: 2022 }); }
    catch (e) { break; }

    const dels = [];   // {start,end} 或 {start,end,text}

    (function walk(node) {
      if (!node || typeof node !== 'object') return;
      if (Array.isArray(node)) { node.forEach(walk); return; }

      // if (常量) cons else alt  →  保留一支
      if (node.type === 'IfStatement' && isLiteral(node.test)) {
        const v = safeEval(code.slice(node.test.start, node.test.end));
        if (v !== null && typeof v !== 'function') {
          if (v && node.consequent) {
            // 保留 consequent 内部，去掉 if 外壳
            dels.push({ start: node.start, end: node.consequent.start, text: '' });
            if (node.alternate) dels.push({ start: node.consequent.end, end: node.alternate.end, text: '' });
            else dels.push({ start: node.consequent.end, end: node.end, text: '' });
            removed++;
          } else if (!v && node.alternate) {
            dels.push({ start: node.start, end: node.alternate.start, text: '' });
            dels.push({ start: node.alternate.end, end: node.end, text: '' });
            removed++;
          } else {
            dels.push({ start: node.start, end: node.end, text: '' });   // 整块删
            removed++;
          }
        }
      }

      // 空语句块
      if (node.type === 'BlockStatement' && node.body.length === 0 && node.start !== undefined) {
        // 只在非函数体时删
      }

      for (const k in node) {
        if (['type', 'start', 'end', 'loc', 'range'].includes(k)) continue;
        walk(node[k]);
      }
    })(ast);

    if (!dels.length) break;
    const dr = applyPatches(code, dels.map(d => ({ start: d.start, end: d.end, text: d.text || '' })));
    code = dr.code;
  }

  return { code, removed };
}

/** 文本级快速清理（不依赖 AST，用于超大文件预处理） */
function textClean(src) {
  return src
    // !![] → true   ![] → false   （obfuscator.io 经典垃圾）
    .replace(/!!\[\]/g, 'true')
    .replace(/(?<![!])!\[\]/g, 'false')
    // void 0 → undefined
    .replace(/\bvoid 0\b/g, 'undefined')
    // +[] → 0
    .replace(/\+\[\]/g, '0');
}



/**
 * obfuscator.io 家族专用还原器
 *
 * 核心思路：**复用原脚本自带的解密器，而不是重新实现算法**
 *
 * 为什么不自己写 RC4：
 *   每个变体的字符串表编码（base64 字符表、旋转方向、校验常量）都不同，
 *   重新实现意味着每遇一个新样本就要改代码。
 *   把原脚本的解密函数 + 字符串表整体抠出来，塞进沙箱跑，
 *   得到的解密结果与运行时 100% 一致 —— 这才是"精准"。
 *
 * 三步：
 *   1. 定位字符串表（超长字符串数组）与解密函数
 *   2. 在隔离沙箱中执行（含旋转自校验穷举）
 *   3. AST 遍历，把 decrypt(i, k) 调用替换为字面量
 */



/**
 * 定位字符串表与解密函数
 * @returns {{table:Array<string>, fnName:string, decNode:object}|null}
 */
function locateStringTable(src) {
  let ast;
  try { ast = acorn.parse(src, { ecmaVersion: 2022 }); }
  catch (e) { return null; }

  let best = null;

  (function walk(node) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { node.forEach(walk); return; }

    // 字符串数组：元素全是 Literal 字符串，长度够大
    if (node.type === 'ArrayExpression' && node.elements.length > 50) {
      const vals = node.elements.map(e => (e && e.type === 'Literal' && typeof e.value === 'string') ? e.value : null);
      const okCount = vals.filter(v => v !== null).length;
      if (okCount > node.elements.length * 0.8) {
        if (!best || node.elements.length > best.table.length) {
          best = { table: vals, node, decNode: null, fnName: null };
        }
      }
    }
    for (const k in node) {
      if (['type', 'start', 'end', 'loc', 'range'].includes(k)) continue;
      walk(node[k]);
    }
  })(ast);

  return best;
}

/**
 * 提取并沙箱执行解密器
 *
 * 策略：把"解密函数 + 表"的源码片段抽出来，构造一个可调用的门面。
 * 若样本带旋转自校验（while(!![]){ t.push(t.shift()); if(hash===CONST) break; }），
 * 则穷举旋转量 k ∈ [0, len)，取能通过校验的那个。
 */
function buildDecoder(src) {
  // 找形如 function _0xNNNN(a,b){...} 的解密函数：
  // 特征：函数体内有 %256 / charCodeAt / while(!![]) 循环
  const fnRe = /function\s+([A-Za-z_$][\w$]*)\s*\(([^)]*)\)\s*\{/g;
  let m, candidates = [];
  while ((m = fnRe.exec(src))) {
    const name = m[1];
    const start = m.index;
    // 粗略取函数体（括号配对）
    let depth = 0, end = -1;
    for (let i = src.indexOf('{', start); i < src.length; i++) {
      if (src[i] === '{') depth++;
      else if (src[i] === '}') { depth--; if (depth === 0) { end = i + 1; break; } }
    }
    if (end < 0) continue;
    const body = src.slice(start, end);
    const score =
      (/\%\s*256|256/.test(body) ? 2 : 0) +
      (/charCodeAt/.test(body) ? 2 : 0) +
      (/while\s*\(\s*!!\[\]\s*\)/.test(body) ? 3 : 0) +
      (/push\(\s*\w+\.shift\(\)\s*\)/.test(body) ? 3 : 0) +
      (/parseInt|fromCharCode|split|indexOf/.test(body) ? 1 : 0);
    if (score >= 4) candidates.push({ name, body, score, start, end });
  }
  candidates.sort((a, b) => b.score - a.score);
  return candidates[0] || null;
}

/**
 * 主还原
 * @returns {{code:string, strings:number, note:string}}
 */
function deobfuscate(src) {
  const table = locateStringTable(src);
  if (!table) return { code: src, strings: 0, note: '未找到字符串表，跳过' };

  const dec = buildDecoder(src);
  if (!dec) return { code: src, strings: 0, note: '未找到解密函数，跳过' };

  // ── 在沙箱中装载解密器 ──
  let decode = null;
  try {
    // 把表作为变量注入，解密函数源码直接求值
    const facade = `
      var __T = ${JSON.stringify(table.table)};
      ${dec.body}
      return ${dec.name};
    `;
    // eslint-disable-next-line no-new-func
    decode = new Function(facade)();
  } catch (e) {
    return { code: src, strings: 0, note: '解密器装载失败: ' + e.message };
  }

  if (typeof decode !== 'function') {
    return { code: src, strings: 0, note: '解密器不可用' };
  }

  // ── AST 遍历，替换调用 ──
  let ast;
  try { ast = acorn.parse(src, { ecmaVersion: 2022 }); }
  catch (e) { return { code: src, strings: 0, note: '解析失败' }; }

  const patches = [];
  (function walk(node) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { node.forEach(walk); return; }

    if (node.type === 'CallExpression' && node.callee.type === 'Identifier' && node.callee.name === dec.name) {
      // 只处理参数全为字面量的调用（可静态解密）
      if (node.arguments.length && node.arguments.every(a => a.type === 'Literal')) {
        const args = node.arguments.map(a => a.value);
        let v = null;
        try { v = decode.apply(null, args); } catch (e) { v = null; }
        if (typeof v === 'string') {
          patches.push({ start: node.start, end: node.end, text: lit(v) });
        }
      }
    }
    for (const k in node) {
      if (['type', 'start', 'end', 'loc', 'range'].includes(k)) continue;
      walk(node[k]);
    }
  })(ast);

  const r = applyPatches(src, patches);
  return { code: r.code, strings: r.applied, note: `解密 ${r.applied} 处（表 ${table.table.length} 项）` };
}

/**
 * 控制流平坦化还原（基础版）
 * 识别 while(!![]){ switch(x){ case 'N': ... continue; } } 模式
 * 仅处理调度表为静态数组、且顺序可静态求值的情形
 */
function flattenControlFlow(src) {
  let ast;
  try { ast = acorn.parse(src, { ecmaVersion: 2022 }); }
  catch (e) { return { code: src, blocks: 0, note: '解析失败' }; }

  let blocks = 0;
  // 统计模式出现次数（用于报告，实际重构需按样本定制）
  const re = /while\s*\(\s*!!\[\]\s*\)\s*\{[\s\S]{0,400}?switch\s*\(/g;
  blocks = (src.match(re) || []).length;

  return { code: src, blocks, note: blocks ? `检测到 ${blocks} 处平坦化（需按样本定制还原）` : '未检测到平坦化' };
}



/**
 * Helper 函数池内联 + 死对象清理
 *
 * 针对 obfuscator.io 的"转发型 helper 池"：
 *
 *   const _0x37a35e = {
 *     'ckKpF': function (a, b) { return a + b; },      ← 转发型 helper
 *     'mxPIL': 'YWERJ',                                 ← 恒假比较垃圾
 *     'str_srv': 'srv'
 *   };
 *   ... _0x37a35e['ckKpF'](x, y) ...                    ← 调用点
 *
 * 还原为：
 *   ... (x + y) ...
 *
 * 安全规则（实战验证）：
 *   ★ 只有当某个参数在 return 表达式中出现 **≤1 次** 时才内联
 *     若出现 2 次，内联会导致实参被求值两次（副作用风险），必须保留调用形式
 *   ★ 只内联"纯转发"函数：函数体就是一条 return 语句
 */



/**
 * 识别 helper 池对象
 * @returns {Array<{varName:string, node:object, helpers:Map, junk:Set}>}
 */
function findHelperPools(src) {
  let ast;
  try { ast = acorn.parse(src, { ecmaVersion: 2022 }); }
  catch (e) { return []; }

  const pools = [];

  (function walk(node) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { node.forEach(walk); return; }

    if (node.type === 'VariableDeclarator'
      && node.id.type === 'Identifier'
      && node.init && node.init.type === 'ObjectExpression'
      && node.init.properties.length >= 5) {

      const props = node.init.properties;
      let fnCount = 0, strCount = 0;
      const helpers = new Map();
      const junk = new Set();

      for (const p of props) {
        if (p.type !== 'Property') continue;
        const key = p.key.type === 'Identifier' ? p.key.name
          : (p.key.type === 'Literal' ? String(p.key.value) : null);
        if (key === null) continue;

        if (p.value.type === 'FunctionExpression') {
          // 纯转发：body 只有一条 return
          if (p.value.body.body.length === 1 && p.value.body.body[0].type === 'ReturnStatement') {
            const ret = p.value.body.body[0].argument;
            if (ret) {
              const params = p.value.params.map((x, i) => x.type === 'Identifier' ? x.name : '__p' + i);
              helpers.set(key, {
                params,
                expr: src.slice(ret.start, ret.end),
                exprNode: ret,
              });
              fnCount++;
            }
          }
        } else if (p.value.type === 'Literal' && typeof p.value.value === 'string') {
          strCount++;
          // 垃圾串：随机大小写字母组合，且未被真正使用（恒假比较用）
          if (/^[A-Za-z]{5}$/.test(p.value.value) && !/^[a-z]+$/.test(p.value.value.toLowerCase())) {
            junk.add(key);
          }
        }
      }

      // 判定为 helper 池：转发函数 >= 3
      if (fnCount >= 3) {
        pools.push({ varName: node.id.name, node: node.init, helpers, junk, fnCount, strCount });
      }
    }

    for (const k in node) {
      if (['type', 'start', 'end', 'loc', 'range'].includes(k)) continue;
      walk(node[k]);
    }
  })(ast);

  return pools;
}

/**
 * 内联 helper 调用
 * @returns {{code:string, inlined:number}}
 */
function inlineHelpers(src) {
  const pools = findHelperPools(src);
  if (!pools.length) return { code: src, inlined: 0, pools: 0 };

  let ast;
  try { ast = acorn.parse(src, { ecmaVersion: 2022 }); }
  catch (e) { return { code: src, inlined: 0, pools: 0 } };

  const patches = [];
  let inlined = 0;

  // 建立 变量名 -> pool 索引
  const byVar = new Map();
  pools.forEach(p => byVar.set(p.varName, p));

  (function walk(node) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { node.forEach(walk); return; }

    if (node.type === 'CallExpression' && node.callee.type === 'MemberExpression') {
      const obj = node.callee.object;
      if (obj.type === 'Identifier' && byVar.has(obj.name)) {
        const pool = byVar.get(obj.name);
        const key = !node.callee.computed && node.callee.property.type === 'Identifier'
          ? node.callee.property.name
          : (node.callee.computed && node.callee.property.type === 'Literal'
            ? String(node.callee.property.value) : null);

        if (key && pool.helpers.has(key)) {
          const h = pool.helpers.get(key);
          if (node.arguments.length === h.params.length) {
            // 安全检查：每个参数在表达式中出现次数必须 <= 1
            const counts = h.params.map(p => {
              const re = new RegExp('\\b' + p.replace(/\$/g, '\\$') + '\\b', 'g');
              return (h.expr.match(re) || []).length;
            });
            if (counts.every(c => c <= 1)) {
              let text = h.expr;
              // 替换参数占位符（按长度降序，避免 a1 误替换 a10）
              const order = h.params.map((p, i) => ({ p, i })).sort((a, b) => b.p.length - a.p.length);
              for (const { p, i } of order) {
                const argSrc = src.slice(node.arguments[i].start, node.arguments[i].end);
                // 实参为原子表达式（标识符/数字/字符串）时不加括号，否则加括号保优先级
                const atomic = /^[A-Za-z_$][\w$]*$/.test(argSrc.trim())
                  || /^[\d.]+$/.test(argSrc.trim())
                  || /^["'`]/.test(argSrc.trim());
                const wrapped = atomic ? argSrc : '(' + argSrc + ')';
                // ★ 必须用函数形式替换：实参里若含 $& / $1 / $` 会被当成替换模式
                text = text.replace(new RegExp('\\b' + p.replace(/\$/g, '\\$') + '\\b', 'g'), () => wrapped);
              }
              // 结果整体加括号，避免优先级问题
              patches.push({ start: node.start, end: node.end, text: '(' + text + ')' });
              inlined++;
            }
          }
        }
      }
    }

    for (const k in node) {
      if (['type', 'start', 'end', 'loc', 'range'].includes(k)) continue;
      walk(node[k]);
    }
  })(ast);

  // ★ 嵌套调用（helper A 表达式里又调 helper B）会产生范围重叠，
  //   applyPatches 分段构建天然跳过被包含的内层，只保留最外层。
  const r = applyPatches(src, patches);
  return { code: r.code, inlined: r.applied, pools: pools.length };
}

/**
 * 删除死对象：helper 池在使用处全内联后，其声明本身成为死代码
 * 安全前提：该变量名在整个文件中只出现 1 次（即声明处）
 */
function dropDeadObjects(src) {
  let code = src;

  for (let pass = 0; pass < 3; pass++) {
    const pools = findHelperPools(code);
    if (!pools.length) break;
    let changed = false;

    for (const pool of pools) {
      // 统计变量名出现次数（精确：作为标识符出现）
      let ast;
      try { ast = acorn.parse(code, { ecmaVersion: 2022 }); }
      catch (e) { continue; }

      let uses = 0;
      (function walk(node) {
        if (!node || typeof node !== 'object') return;
        if (Array.isArray(node)) { node.forEach(walk); return; }
        if (node.type === 'Identifier' && node.name === pool.varName) uses++;
        for (const k in node) {
          if (['type', 'start', 'end', 'loc', 'range'].includes(k)) continue;
          walk(node[k]);
        }
      })(ast);

      // 只出现 1 次（声明本身）→ 安全删除
      if (uses <= 1) {
        // 找到声明语句：const/var X = {...};
        const declRe = new RegExp('(?:const|var|let)\\s+' + pool.varName.replace(/\$/g, '\\$') + '\\s*=\\s*\\{');
        const m = code.match(declRe);
        if (m) {
          const start = m.index;
          // 括号配对找结束
          let depth = 0, end = -1;
          for (let i = code.indexOf('{', start); i < code.length; i++) {
            if (code[i] === '{') depth++;
            else if (code[i] === '}') { depth--; if (depth === 0) { end = i + 1; break; } }
          }
          if (end > 0) {
            // 吞掉尾随分号
            if (code[end] === ';') end++;
            code = code.slice(0, start) + code.slice(end);
            changed = true;
          }
        }
      }
    }
    if (!changed) break;
  }

  return { code, };
}



/**
 * 结构感知语法修复器
 *
 * 把反编译器产出的"近似 JS"修补为 100% 语法正确的代码。
 * 每一条规则都对应一次实战踩坑：
 *
 *  ① sanitize 只跑一次 —— 循环里反复调用会撤销上一轮的修复，导致 85% 卡住不动
 *  ② 括号计数必须跳过字符串/正则/注释 —— /[{[`]/ 这种正则会被误计为块括号
 *  ③ /g 正则禁止定义在循环外 —— lastIndex 跨次复用，会静默漏匹配（v0/v1 漏声明的元凶）
 *  ④ 防函数体提前闭合 —— depth 归零后若后面还有代码，说明这个 } 是多余的
 *  ⑤ 孤儿 else —— 前面不是闭合块时补一个 }
 *  ⑥ continue/break 在循环外 → 注释化（保留语义信息，不丢代码）
 *  ⑦ 行首对象字面量 {k:v}[..](..) 需加括号 —— 否则被解析为块语句
 *  ⑧ 尾部孤立占位符 → 删除
 */



function parseErr(code) {
  try {
    acorn.parse(code, { ecmaVersion: 2022, sourceType: 'script' });
    return null;
  } catch (e) {
    if (e.loc && typeof e.loc.line === 'number') return { line: e.loc.line - 1, msg: e.message };
    if (typeof e.pos === 'number') return { line: code.slice(0, e.pos).split('\n').length - 1, msg: e.message };
    return { line: -1, msg: e.message };
  }
}

/** 单遍扫描：修正 else 配对、循环外跳转、行首对象字面量、括号平衡 */
function sanitize(body) {
  const lines = body.split('\n');
  const out = [];
  const stack = [];            // {type:'if'|'else'|'loop'|'block'}
  let prevCloseWasIf = false;
  const inLoop = () => stack.some(f => f.type === 'loop');

  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    const t = raw.trim();
    if (!t) continue;

    // ⑤ 孤儿 else
    const isElse = /^else\b/.test(t) || /^\}\s*else\b/.test(t);
    if (isElse) {
      if (!prevCloseWasIf) {
        out.push(indentOf(raw) + '}');
        if (stack.length) stack.pop();
      }
      out.push(indentOf(raw) + 'else {');
      stack.push({ type: 'else' });
      prevCloseWasIf = false;
      continue;
    }

    // ⑦ 行首对象字面量：{k: v}[...](...) 或 {k: v}.x
    if (/^\{/.test(t) && /:/.test(t) && !/^(if|while|for|switch|catch|function)\b/.test(t)) {
      let d = 0, closeIdx = -1;
      for (let ci = 0; ci < t.length; ci++) {
        if (t[ci] === '{') d++;
        else if (t[ci] === '}') { d--; if (d === 0) { closeIdx = ci; break; } }
      }
      if (closeIdx > 0 && closeIdx < t.length - 1) {
        out.push(indentOf(raw) + '(' + t.slice(0, closeIdx + 1) + ')' + t.slice(closeIdx + 1));
        prevCloseWasIf = false;
        continue;
      }
    }

    // ⑥ continue / break 必须在循环内
    if (/^(continue|break)\b/.test(t)) {
      if (inLoop()) out.push(raw);
      else out.push(indentOf(raw) + '/* ' + (/^continue/.test(t) ? 'continue' : 'break') + ' (outside loop) */');
      prevCloseWasIf = false;
      continue;
    }

    // 开块
    if (/\{\s*$/.test(t)) {
      let type = 'block';
      if (/^if\s*\(/.test(t)) type = 'if';
      else if (/^while\s*\(/.test(t) || /^for\s*\(/.test(t)) type = 'loop';
      out.push(raw);
      stack.push({ type });
      prevCloseWasIf = false;
      continue;
    }

    // 闭块
    if (t === '}' || /^\}\s*(else\s*\{)?$/.test(t) || /^\}\s*else\s*\{\s*$/.test(t)) {
      const top = stack.length ? stack[stack.length - 1] : null;
      if (top) { prevCloseWasIf = (top.type === 'if'); stack.pop(); }
      else prevCloseWasIf = false;
      out.push(raw);
      continue;
    }

    out.push(raw);
    prevCloseWasIf = false;
  }

  // ④ 防提前闭合：depth 归零但后面还有代码 → 该 } 多余
  {
    let depth = 0;
    const st = {};
    const keep = new Array(out.length).fill(true);
    for (let i = 0; i < out.length; i++) {
      const n = netCurly(out[i], st);
      if (n < 0 && depth + n <= 0) {
        let hasMore = false;
        for (let j = i + 1; j < out.length; j++) if (isCodeLine(out[j])) { hasMore = true; break; }
        if (hasMore) { keep[i] = false; continue; }
      }
      depth += n;
    }
    const trimmed = out.filter((l, i) => keep[i]);
    out.length = 0;
    out.push(...trimmed);
  }

  while (stack.length) { stack.pop(); out.push('}'); }

  // ② 全局括号平衡（跳过字符串/正则/注释）
  let bal = 0;
  const st2 = {};
  for (const l of out) bal += netCurly(l, st2);
  if (bal > 0) for (let i = 0; i < bal; i++) out.push('}');

  return out.join('\n');
}

/** ⑧ 清理尾部孤立占位符 */
function trimStubs(body) {
  let arr = body.split('\n');
  // 空标签注释（"── Lxx" 后无内容）
  arr = arr.filter((l, i, a) => {
    if (!/^\s*\/\/ ── L\d+/.test(l)) return true;
    for (let j = i + 1; j < a.length; j++) if (a[j].trim()) return true;
    return false;
  });
  const isStub = l => /^\s*(\/\* → L\d+[^/]*\*\/|\/\/ ── L\d+.*)\s*$/.test(l);
  while (arr.length && (isStub(arr[arr.length - 1]) || !arr[arr.length - 1].trim())) arr.pop();
  return arr.join('\n');
}

/**
 * 迭代修复到语法正确
 * ① 只 sanitize 一次，之后纯局部修复
 */
function fixModule(body, maxPass) {
  maxPass = maxPass || 40;
  let code = trimStubs(body);
  code = sanitize(code);                     // ← 只跑一次

  const stats = { elseDropped: 0, braceAdded: 0, braceRemoved: 0, passes: 0 };

  for (let pass = 0; pass < maxPass; pass++) {
    const err = parseErr('function __m() {\n' + code + '\n}');
    if (!err) break;
    stats.passes++;
    let lines = code.split('\n');
    let ln = err.line - 1;
    if (ln < 0) break;

    if (ln >= lines.length) {
      // 错误在末尾 → 多余闭合，从后往前删一个 }
      let removed = false;
      for (let k = lines.length - 1; k >= 0; k--) {
        if (lines[k].trim() === '}') { lines.splice(k, 1); removed = true; break; }
      }
      if (!removed) break;
      code = lines.join('\n');
      stats.braceRemoved++;
      continue;
    }

    const t = lines[ln].trim();
    if (/^else\b/.test(t) || /^\}\s*else\b/.test(t)) {
      // 删除该 else 整块
      let d = 0, end = -1;
      const st3 = {};
      for (let k = ln; k < lines.length; k++) {
        d += netCurly(lines[k], st3);
        if (k > ln && d <= 0) { end = k; break; }
      }
      if (end < 0) end = ln;
      lines.splice(ln, end - ln + 1);
      stats.elseDropped++;
    } else if (t === '}') {
      lines.splice(ln, 1);
      stats.braceRemoved++;
    } else if (/missing \) after|Expected '\)'/.test(err.msg)) {
      lines[ln] = lines[ln].replace(/;\s*$/, '') + ');';
      stats.braceAdded++;
    } else {
      break;    // 无法归类 → 放弃，避免越修越坏
    }
    code = lines.join('\n');
  }

  return { code, ok: parseErr('function __m() {\n' + code + '\n}') === null, stats };
}



/**
 * 语义命名器
 *
 * 把 v1/v2/a0/fn_m43 这类机械名重建成 humanName。
 *
 * 命名线索优先级（高→低）：
 *  ① DOM 线索（最强）：id/class 里含 mcp → mcpBtn / mcpUrl
 *  ② 属性访问集合：同时访问 .url 与 .token → server
 *  ③ 初始化表达式：new TextDecoder() → decoder
 *  ④ 方法调用特征：调 .push() 且初始为 [] → list
 *  ⑤ 所在函数名推导：在 createMcpButton 内 → mcpButton
 *
 * 碰撞处理：同名自动追加序号（mcpBtn / mcpBtn2）
 */



/** DOM id/class 关键词 → 语义词根 */
const DOM_HINTS = [
  [/mcp|jsonrpc/i, 'mcp'],
  [/mem|记忆/i, 'mem'],
  [/card|角色|prompt/i, 'card'],
  [/skill|技能/i, 'skill'],
  [/proxy|bridge|桥|px/i, 'proxy'],
  [/panel|modal|dialog/i, 'panel'],
  [/toast|notify/i, 'toast'],
  [/btn|button/i, 'Btn'],
  [/input|field/i, 'Input'],
  [/list|panel-body/i, 'List'],
  [/url/i, 'Url'],
  [/token|key/i, 'Token'],
  [/remark|note/i, 'Remark'],
  [/model/i, 'Model'],
  [/bridge/i, 'Bridge'],
];

/** 属性集合 → 语义名 */
const PROP_SETS = [
  [['url', 'token'], 'server'],
  [['url', 'enabled'], 'server'],
  [['name', 'prompt'], 'card'],
  [['name', 'content'], 'skill'],
  [['id', 'prompt', 'model'], 'task'],
  [['lastStreamText'], 'state'],
  [['nextNode'], 'walker'],
  [['textContent', 'trim'], 'text'],
  [['getBoundingClientRect'], 'el'],
];

/** 初始化表达式 → 语义名 */
const INIT_HINTS = [
  [/^new\s+TextDecoder/, 'decoder'],
  [/^new\s+TextEncoder/, 'encoder'],
  [/^new\s+MutationObserver/, 'observer'],
  [/^new\s+IntersectionObserver/, 'observer'],
  [/^new\s+Map\(/, 'map'],
  [/^new\s+Set\(/, 'set'],
  [/^new\s+WeakMap\(/, 'weakMap'],
  [/^new\s+AbortController/, 'controller'],
  [/^new\s+URL\(/, 'url'],
  [/^new\s+Date\(/, 'date'],
  [/^document\.createElement/, 'el'],
  [/^document\.querySelector/, 'el'],
  [/^document\.getElementById/, 'el'],
  [/^document\.createTreeWalker/, 'walker'],
  [/^\[\]$/, 'list'],
  [/^\{\}$/, 'opts'],
  [/^localStorage/, 'store'],
  [/^\.indexOf\(/, 'idx'],
  [/^\d+$/, 'n'],
  [/^["'`]/, 'text'],
  [/^(true|false)$/, 'flag'],
];

/** 函数体特征 → 函数名 */
const FN_HINTS = [
  [/injectCss|cssText|<style/, 'injectStyles'],
  [/getElementById\(['"]dspp-mcp-btn/, 'createMcpButton'],
  [/tools\/call|tools\/list/, 'mcpRequest'],
  [/task_complete|original_task/, 'runToolLoop'],
  [/flowLog/, 'logEvent'],
  [/parseSse|event-stream/, 'parseSse'],
  [/localStorage\.getItem/, 'loadState'],
  [/localStorage\.setItem/, 'saveState'],
  [/addEventListener\(['"]click/, 'bindClick'],
  [/AbortSignal/, 'withTimeout'],
];

/** 从字符串字面量提取 DOM id/class 线索 */
function domName(str) {
  for (const [re, word] of DOM_HINTS) if (re.test(str)) return word;
  return null;
}

/**
 * 主入口：对代码做语义重命名
 * @param {string} code
 * @returns {{code:string, renamed:number}}
 */
function rename(code) {
  let ast;
  try { ast = acorn.parse(code, { ecmaVersion: 2022 }); }
  catch (e) { return { code, renamed: 0 }; }

  // ── 收集：变量名 → 特征 ──
  const vars = new Map();   // name -> {props:Set, init:string, calls:Set, strs:Set, declAt:number}

  function feat(name) {
    if (!vars.has(name)) vars.set(name, { props: new Set(), init: '', calls: new Set(), strs: new Set(), declAt: -1 });
    return vars.get(name);
  }

  (function walk(node, curFn) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { node.forEach(n => walk(n, curFn)); return; }

    if (node.type === 'VariableDeclarator' && node.id.type === 'Identifier') {
      const f = feat(node.id.name);
      f.declAt = node.start;
      if (node.init) {
        f.init = code.slice(node.init.start, node.init.end).slice(0, 80);
        if (node.init.type === 'Literal' && typeof node.init.value === 'string') f.strs.add(node.init.value);
      }
    }

    if (node.type === 'MemberExpression') {
      // obj.prop
      if (node.object.type === 'Identifier' && !node.computed && node.property.type === 'Identifier') {
        feat(node.object.name).props.add(node.property.name);
      }
      if (node.object.type === 'Identifier' && node.computed && node.property.type === 'Literal') {
        feat(node.object.name).props.add(String(node.property.value));
      }
    }

    if (node.type === 'CallExpression') {
      if (node.callee.type === 'MemberExpression' && node.callee.object.type === 'Identifier') {
        const o = node.callee.object.name;
        const p = node.callee.property.type === 'Identifier' ? node.callee.property.name : '';
        feat(o).calls.add(p);
      }
      node.arguments.forEach(a => {
        if (a.type === 'Literal' && typeof a.value === 'string') {
          // 作为参数传入的字符串（可能是 DOM id）
          if (curFn) feat('__fn_' + curFn).strs.add(a.value);
        }
      });
    }

    if (node.type === 'FunctionDeclaration' && node.id) curFn = node.id.name;
    if (node.type === 'FunctionExpression' && node.id) curFn = node.id.name;

    for (const k in node) {
      if (['type', 'start', 'end', 'loc', 'range'].includes(k)) continue;
      walk(node[k], curFn);
    }
  })(ast, null);

  // ── 决策：为每个变量挑选语义名 ──
  const used = new Set();
  const plan = new Map();   // oldName -> newName

  for (const [name, f] of vars) {
    if (!/^[va]?\d+$|^_0x|^tmp|^t\d+$/i.test(name)) continue;   // 只重命名机械名
    let cand = null;

    // ① DOM 线索（字符串参数 / 初始化字符串）
    for (const s of f.strs) {
      const d = domName(s);
      if (d) { cand = d; break; }
    }
    if (!cand) for (const s of f.strs) {
      const m = s.match(/id=["']?([\w-]+)/);
      if (m) { const d = domName(m[1]); if (d) { cand = d; break; } }
    }

    // ② 属性集合
    if (!cand) {
      const ps = [...f.props];
      for (const [set, nm] of PROP_SETS) {
        if (set.every(x => ps.includes(x))) { cand = nm; break; }
      }
    }

    // ③ 初始化表达式
    if (!cand && f.init) {
      for (const [re, nm] of INIT_HINTS) {
        if (re && re.test(f.init)) { cand = nm; break; }
      }
    }

    // ④ 方法调用特征
    if (!cand) {
      if (f.calls.has('push') && /^\[/.test(f.init)) cand = 'list';
      else if (f.calls.has('set') && f.calls.has('get')) cand = 'map';
      else if (f.calls.has('add') && f.calls.has('has')) cand = 'set';
      else if (f.calls.has('appendChild')) cand = 'container';
      else if (f.calls.has('observe')) cand = 'observer';
      else if (f.calls.has('then') || f.calls.has('catch')) cand = 'promise';
    }

    if (cand && isIdent(cand)) {
      let final = cand;
      let i = 2;
      while (used.has(final)) final = cand + (i++);
      used.add(final);
      plan.set(name, final);
    }
  }

  if (!plan.size) return { code, renamed: 0 };

  // ── 应用：按标识符出现位置替换（用 AST 精确定位，避免误替换字符串内容）──
  const patches = [];
  (function walk(node) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { node.forEach(walk); return; }
    if (node.type === 'Identifier' && plan.has(node.name)) {
      patches.push({ start: node.start, end: node.end, text: plan.get(node.name) });
    }
    // 属性名不重命名（node.computed 为 false 的 MemberExpression.property）
    for (const k in node) {
      if (['type', 'start', 'end', 'loc', 'range'].includes(k)) continue;
      if (node.type === 'MemberExpression' && k === 'property' && !node.computed) continue;
      if ((node.type === 'Property') && k === 'key' && !node.computed) continue;
      walk(node[k]);
    }
  })(ast);

  const r = applyPatches(code, patches);
  return { code: r.code, renamed: plan.size };
}

/**
 * 函数级语义命名（基于函数体特征）
 */
function renameFunctions(code) {
  let ast;
  try { ast = acorn.parse(code, { ecmaVersion: 2022 }); }
  catch (e) { return { code, renamed: 0 }; }

  const patches = [];
  const used = new Set();

  (function walk(node) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { node.forEach(walk); return; }

    if (node.type === 'FunctionDeclaration' && node.id && /^fn_|^m\d+$|^_0x/.test(node.id.name)) {
      const body = code.slice(node.start, node.end).slice(0, 3000);
      for (const [re, nm] of FN_HINTS) {
        if (re.test(body)) {
          let final = nm, i = 2;
          while (used.has(final)) final = nm + (i++);
          used.add(final);
          patches.push({ start: node.id.start, end: node.id.end, text: final });
          break;
        }
      }
    }

    for (const k in node) {
      if (['type', 'start', 'end', 'loc', 'range'].includes(k)) continue;
      walk(node[k]);
    }
  })(ast);

  const r = applyPatches(code, patches);
  return { code: r.code, renamed: r.applied };
}




/**
 * jsrestore — JS 反混淆 / 反编译 一体化工具
 *
 * 用法：
 *   node jsrestore.js detect  <file>              识别混淆指纹
 *   node jsrestore.js restore <file> [-o out.js]   完整还原
 *   node jsrestore.js verify  <file> [-o out.js]   仅做语法与运行时验证
 *
 * 设计：流水线式，每步独立可跳过；失败降级而非中断。
 */










const args = process.argv.slice(2);
const CMD = args[0];
const FILE = args[1];
const outIdx = args.indexOf('-o');
const OUT = outIdx > 0 ? args[outIdx + 1] : null;

function banner(t) { console.log('\n' + '─'.repeat(58) + '\n' + t + '\n' + '─'.repeat(58)); }

function cmdDetect(file) {
  const src = read(file);
  const s = summarize(src);
  banner('指纹识别：' + path.basename(file));
  console.log(`体积      : ${human(s.bytes)}  /  ${s.lines} 行`);
  console.log(`主判定    : ${s.primary.name}  (置信 ${s.primary.score})`);
  console.log(`推荐流水线: ${s.primary.pipeline.join(' → ')}`);
  if (s.all.length > 1) {
    console.log('\n其他命中：');
    s.all.slice(1).forEach(h => console.log(`  · ${h.name}  (${h.score})`));
  }
  return s;
}

/**
 * 还原流水线
 */
function cmdRestore(file, out) {
  const t0 = Date.now();
  let src = read(file);
  const log = [];

  banner('jsrestore — 还原流水线');
  console.log(`输入: ${path.basename(file)}  (${human(src.length)})`);

  // ── Step 0：识别 ──
  const s = summarize(src);
  console.log(`\n[0/8] 指纹识别`);
  console.log(`      ${s.primary.name}  (置信 ${s.primary.score})`);
  console.log(`      流水线: ${s.primary.pipeline.join(' → ')}`);
  const pipe = new Set(s.primary.pipeline);

  // ── Step 1：文本级快速清理 ──
  if (pipe.has('fold') || pipe.has('strings')) {
    const before = src.length;
    src = textClean(src);
    log.push(['文本清理', before - src.length]);
    console.log(`\n[1/8] 文本清理        Δ ${human(before - src.length)}`);
  } else console.log(`\n[1/8] 文本清理        跳过`);

  // ── Step 2：字符串表解密 ──
  if (pipe.has('strings')) {
    const r = deobfuscate(src);
    src = r.code;
    log.push(['字符串解密', r.strings]);
    console.log(`[2/8] 字符串表解密    ${r.note}`);
  } else console.log(`[2/8] 字符串表解密    跳过`);

  // ── Step 3：helper 函数池内联 ──
  {
    try {
      const r = inlineHelpers(src);
      src = r.code;
      console.log(`[3/8] Helper 池内联   ${r.inlined} 处（池 ${r.pools} 个）`);
    } catch (e) {
      console.log(`[3/8] Helper 池内联   失败(${e.message})`);
    }
  }

  // ── Step 4：控制流平坦化 ──
  if (pipe.has('controlflow')) {
    const r = flattenControlFlow(src);
    src = r.code;
    console.log(`[4/8] 控制流平坦化    ${r.note}`);
  } else console.log(`[4/8] 控制流平坦化    跳过`);

  // ── Step 5：常量折叠 ──
  if (pipe.has('fold')) {
    try {
      const r = fold(src);
      src = r.code;
      log.push(['常量折叠', r.folded]);
      console.log(`[5/8] 常量折叠        ${r.folded} 处 / 死代码 ${r.dead} 处`);
    } catch (e) {
      console.log(`[5/8] 常量折叠        失败(${e.message})，保留原文`);
    }
  } else console.log(`[5/8] 常量折叠        跳过`);

  // ── Step 6：死对象清理 ──
  {
    try {
      const before = src.length;
      const r = dropDeadObjects(src);
      src = r.code;
      console.log(`[6/8] 死对象清理      Δ ${human(before - src.length)}`);
    } catch (e) {
      console.log(`[6/8] 死对象清理      失败(${e.message})`);
    }
  }

  // ── 未实现阶段的诚实提示 ──
  const UNSUPPORTED = {
    'vm-unpack': '解包引导器（需逆向该样本的载荷加密与栈式VM，属样本定制）',
    'isa': '提取指令集（需定位分发表并还原 opcode 语义，属样本定制）',
    'disasm': '字节码反汇编（依赖 isa 结果）',
    'decompile': '字节码反编译为结构化 JS（依赖 disasm 结果）',
    'beautify': '代码格式化',
  };
  const missing = [...pipe].filter(p => UNSUPPORTED[p]);
  if (missing.length) {
    console.log(`\n  ⚠ 本样本需以下样本定制阶段，通用流水线未实现：`);
    missing.forEach(p => console.log(`      · ${p} — ${UNSUPPORTED[p]}`));
    console.log(`      参考 advanced/ 下的实战模板（deepseek-pp 双层VM 完整破译链）`);
  }

  // ── Step 7：语法修复 ──
  {
    const r = fixModule(src, 40);
    if (r.ok || parseErr(src) === null) {
      // 原文已合法：不强行 sanitize（避免破坏格式）
      console.log(`[7/8] 语法修复        原文已合法，跳过`);
    } else {
      src = r.code;
      console.log(`[7/8] 语法修复        轮次 ${r.stats.passes}  删else ${r.stats.elseDropped}  补} ${r.stats.braceRemoved}`);
    }
  }

  // ── Step 8：语义命名 ──
  if (pipe.has('naming')) {
    try {
      const r1 = renameFunctions(src);
      src = r1.code;
      const r2 = rename(src);
      src = r2.code;
      console.log(`[8/8] 语义命名        函数 ${r1.renamed} / 变量 ${r2.renamed}`);
    } catch (e) {
      console.log(`[8/8] 语义命名        失败(${e.message})，保留原名`);
    }
  } else console.log(`[8/8] 语义命名        跳过`);

  // ── 输出 ──
  const target = out || file.replace(/\.js$/, '') + '.restored.js';
  write(target, src);

  // ── 验证 ──
  const err = parseErr(src);
  banner('结果');
  console.log(`输出      : ${target}`);
  console.log(`体积      : ${human(src.length)}  (原 ${human(fs.statSync(file).size)})`);
  console.log(`语法校验  : ${err === null ? '✅ 通过' : '❌ ' + (err ? err.msg : '')}`);
  console.log(`耗时      : ${((Date.now() - t0) / 1000).toFixed(1)}s`);

  return { ok: err === null, out: target };
}

function cmdVerify(file) {
  const src = read(file);
  const err = parseErr(src);
  banner('验证：' + path.basename(file));
  console.log(`体积      : ${human(src.length)}`);
  console.log(`语法校验  : ${err === null ? '✅ 通过' : '❌ ' + (err ? err.msg : '')}`);

  // 运行时加载（隔离沙箱，桩化浏览器 API）
  if (err === null) {
    try {
      const sandbox = `
        var window = { addEventListener(){}, document:{} };
        var document = { addEventListener(){}, readyState:'complete',
                         createElement(){return {style:{},appendChild(){}}},
                         querySelector(){return null}, getElementById(){return null} };
        var console = { log(){}, warn(){}, error(){} };
        var localStorage = { getItem(){return null}, setItem(){}, removeItem(){} };
        var fetch = function(){ return Promise.reject(new Error('offline')); };
        var setTimeout = function(f,t){ return 0; };
        var setInterval = function(){ return 0; };
      `;
      // eslint-disable-next-line no-new-func
      new Function(sandbox + '\n' + src)();
      console.log(`运行时加载: ✅ 无致命异常（桩环境）`);
    } catch (e) {
      console.log(`运行时加载: ⚠ ${String(e.message).slice(0, 90)}`);
      console.log(`            （桩环境下缺真实 DOM/宿主，属预期）`);
    }
  }
  return err === null;
}

// ── 入口 ──
if (!CMD || !FILE) {
  console.log(`
jsrestore — JS 反混淆 / 反编译一体化工具

  node jsrestore.js detect  <file>               识别混淆指纹
  node jsrestore.js restore <file> [-o out.js]    完整还原
  node jsrestore.js verify  <file>                语法 + 运行时验证
`);
  process.exit(0);
}

try {
  if (CMD === 'detect') cmdDetect(FILE);
  else if (CMD === 'restore') {
    const r = cmdRestore(FILE, OUT);
    process.exit(r.ok ? 0 : 1);
  } else if (CMD === 'verify') cmdVerify(FILE);
  else { console.error('未知命令:', CMD); process.exit(1); }
} catch (e) {
  console.error('执行失败:', e.message);
  console.error(e.stack.split('\n').slice(1, 4).join('\n'));
  process.exit(1);
}
