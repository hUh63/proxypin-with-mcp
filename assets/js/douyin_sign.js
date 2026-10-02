/**
 * Douyin / ByteDance signature toolkit — pure JavaScript (engine-agnostic).
 * ======================================================================
 * Consolidated from open reverse-engineering material (Android + iOS + web).
 * Exposes `globalThis.DouyinSign` with:
 *   md5 / sm3Hex / aes128Ecb / rc4            — primitives
 *   xssStub                                   — X-SS-Stub (uppercase MD5 of body)
 *   khronos / traceId                         — X-Khronos / X-TT-Trace-Id
 *   xgorgon / xgorgonIos                      — X-Gorgon (Android 8404 / iOS)
 *   helios / heliosIos                        — X-Helios (Android / iOS)
 *   argus / ladon                             — X-Argus / X-Ladon (deterministic fallback)
 *   xBogus / aBogus                           — X-Bogus / a_bogus (web)
 *   sevenGods                                 — orchestrator returning a header map
 *
 * All version-bound constants are参数化 with defaults, so callers can override
 * without patching the code (见 defaults).
 */
(function (global) {
  'use strict';

  // ------------------------------------------------------------------ utils
  function utf8Bytes(str) {
    var out = [], i, c;
    for (i = 0; i < str.length; i++) {
      c = str.charCodeAt(i);
      if (c < 0x80) out.push(c);
      else if (c < 0x800) { out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f)); }
      else if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
        var c2 = str.charCodeAt(i + 1);
        var cp = 0x10000 + ((c & 0x3ff) << 10) + (c2 & 0x3ff);
        i++;
        out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
      } else { out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f)); }
    }
    return out;
  }

  function toBytes(v) {
    if (v == null) return [];
    if (typeof v === 'string') return utf8Bytes(v);
    if (Array.isArray(v)) return v.slice();
    if (typeof Uint8Array !== 'undefined' && v instanceof Uint8Array) return Array.prototype.slice.call(v);
    return utf8Bytes(String(v));
  }

  var HEX = '0123456789abcdef';
  function bytesToHex(a) { var s = '', i; for (i = 0; i < a.length; i++) s += HEX[(a[i] >> 4) & 15] + HEX[a[i] & 15]; return s; }
  function hexToBytes(h) { var a = [], i; for (i = 0; i < h.length; i += 2) a.push(parseInt(h.substr(i, 2), 16)); return a; }
  function rotl32(x, c) { return ((x << c) | (x >>> (32 - c))) >>> 0; }

  var B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  function b64encode(bytes) {
    var out = '', i, b0, b1, b2;
    for (i = 0; i < bytes.length; i += 3) {
      b0 = bytes[i] & 255;
      b1 = i + 1 < bytes.length ? bytes[i + 1] & 255 : 0;
      b2 = i + 2 < bytes.length ? bytes[i + 2] & 255 : 0;
      out += B64[b0 >> 2] + B64[((b0 & 3) << 4) | (b1 >> 4)];
      out += i + 1 < bytes.length ? B64[((b1 & 15) << 2) | (b2 >> 6)] : '=';
      out += i + 2 < bytes.length ? B64[b2 & 63] : '=';
    }
    return out;
  }

  function u32be(n) { n = n >>> 0; return [(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255]; }
  function u32le(n) { n = n >>> 0; return [n & 255, (n >>> 8) & 255, (n >>> 16) & 255, (n >>> 24) & 255]; }

  // -------------------------------------------------------------------- MD5
  var MD5_S = [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21];
  var MD5_K = (function () { var k = [], i; for (i = 0; i < 64; i++) k[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296) >>> 0; return k; })();

  function md5Digest(bytes) {
    var a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
    var msg = bytes.slice();
    var bitLen = bytes.length * 8;
    msg.push(0x80);
    while (msg.length % 64 !== 56) msg.push(0);
    var lenLo = (bitLen % 4294967296) >>> 0, lenHi = Math.floor(bitLen / 4294967296) >>> 0;
    for (var i = 0; i < 4; i++) msg.push((lenLo >>> (8 * i)) & 255);
    for (var j = 0; j < 4; j++) msg.push((lenHi >>> (8 * j)) & 255);

    for (var off = 0; off < msg.length; off += 64) {
      var M = [], t;
      for (t = 0; t < 16; t++) M[t] = msg[off + 4 * t] | (msg[off + 4 * t + 1] << 8) | (msg[off + 4 * t + 2] << 16) | (msg[off + 4 * t + 3] << 24);
      var A = a0, B = b0, C = c0, D = d0, F, g;
      for (t = 0; t < 64; t++) {
        if (t < 16) { F = (B & C) | (~B & D); g = t; }
        else if (t < 32) { F = (D & B) | (~D & C); g = (5 * t + 1) % 16; }
        else if (t < 48) { F = B ^ C ^ D; g = (3 * t + 5) % 16; }
        else { F = C ^ (B | ~D); g = (7 * t) % 16; }
        F = (F + A + MD5_K[t] + M[g]) >>> 0;
        A = D; D = C; C = B;
        B = (B + rotl32(F, MD5_S[t])) >>> 0;
      }
      a0 = (a0 + A) >>> 0; b0 = (b0 + B) >>> 0; c0 = (c0 + C) >>> 0; d0 = (d0 + D) >>> 0;
    }
    var out = [a0, b0, c0, d0], r = [];
    for (var q = 0; q < 4; q++) { r.push(out[q] & 255, (out[q] >>> 8) & 255, (out[q] >>> 16) & 255, (out[q] >>> 24) & 255); }
    return r;
  }
  function md5Hex(v) { return bytesToHex(md5Digest(toBytes(v))); }

  // -------------------------------------------------------------------- SM3
  function sm3le(e, r) { return (e << (r %= 32) | e >>> 32 - r) >>> 0; }
  function sm3de(e) { return 0 <= e && e < 16 ? 2043430169 : 16 <= e && e < 64 ? 2055708042 : 0; }
  function sm3pe(e, r, t, n) { return 0 <= e && e < 16 ? (r ^ t ^ n) >>> 0 : 16 <= e && e < 64 ? (r & t | r & n | t & n) >>> 0 : 0; }
  function sm3he(e, r, t, n) { return 0 <= e && e < 16 ? (r ^ t ^ n) >>> 0 : 16 <= e && e < 64 ? (r & t | ~r & n) >>> 0 : 0; }

  function SM3() { this.reg = []; this.chunk = []; this.size = 0; this.reset(); }
  SM3.prototype.reset = function () {
    this.reg = [1937774191, 1226093241, 388252375, 3666478592, 2842636476, 372324522, 3817729613, 2969243214];
    this.chunk = []; this.size = 0;
  };
  SM3.prototype.write = function (e) {
    var a = typeof e === 'string' ? (function (s) {
      var n = encodeURIComponent(s).replace(/%([0-9A-F]{2})/g, function (m, r) { return String.fromCharCode('0x' + r); });
      var arr = new Array(n.length); for (var i = 0; i < n.length; i++) arr[i] = n.charCodeAt(i); return arr;
    })(e) : (e.slice ? e.slice() : Array.prototype.slice.call(e));
    this.size += a.length;
    var f = 64 - this.chunk.length;
    if (a.length < f) { this.chunk = this.chunk.concat(a); }
    else {
      this.chunk = this.chunk.concat(a.slice(0, f));
      while (this.chunk.length >= 64) {
        this._compress(this.chunk);
        this.chunk = f < a.length ? a.slice(f, Math.min(f + 64, a.length)) : [];
        f += 64;
      }
    }
  };
  SM3.prototype.sum = function (e) {
    if (e) { this.reset(); this.write(e); }
    this._fill();
    for (var f = 0; f < this.chunk.length; f += 64) this._compress(this.chunk.slice(f, f + 64));
    var i = new Array(32);
    for (var g = 0; g < 8; g++) {
      var c = this.reg[g];
      i[4 * g + 3] = (255 & c) >>> 0; c >>>= 8;
      i[4 * g + 2] = (255 & c) >>> 0; c >>>= 8;
      i[4 * g + 1] = (255 & c) >>> 0; c >>>= 8;
      i[4 * g] = (255 & c) >>> 0;
    }
    this.reset();
    return i;
  };
  SM3.prototype._compress = function (t) {
    if (t.length < 64) return;
    var r = new Array(132), n, a;
    for (n = 0; n < 16; n++) { r[n] = (t[4 * n] << 24 | t[4 * n + 1] << 16 | t[4 * n + 2] << 8 | t[4 * n + 3]) >>> 0; }
    for (n = 16; n < 68; n++) { a = r[n - 16] ^ r[n - 9] ^ sm3le(r[n - 3], 15); a = a ^ sm3le(a, 15) ^ sm3le(a, 23); r[n] = (a ^ sm3le(r[n - 13], 7) ^ r[n - 6]) >>> 0; }
    for (n = 0; n < 64; n++) r[n + 68] = (r[n] ^ r[n + 4]) >>> 0;
    var i = this.reg.slice(0), c, o, s, u, b;
    for (c = 0; c < 64; c++) {
      o = sm3le(i[0], 12) + i[4] + sm3le(sm3de(c), c);
      o = (4294967295 & o) >>> 0;
      s = (o >>> 7 ^ sm3le(i[0], 12)) >>> 0;
      u = sm3pe(c, i[0], i[1], i[2]);
      u = (4294967295 & (u + i[3] + s + r[c + 68])) >>> 0;
      b = sm3he(c, i[4], i[5], i[6]);
      b = (4294967295 & (b + i[7] + o + r[c])) >>> 0;
      i[3] = i[2]; i[2] = sm3le(i[1], 9); i[1] = i[0]; i[0] = u;
      i[7] = i[6]; i[6] = sm3le(i[5], 19); i[5] = i[4]; i[4] = (b ^ sm3le(b, 9) ^ sm3le(b, 17)) >>> 0;
    }
    for (var l = 0; l < 8; l++) this.reg[l] = (this.reg[l] ^ i[l]) >>> 0;
  };
  SM3.prototype._fill = function () {
    var a = 8 * this.size;
    var f = this.chunk.push(128) % 64;
    if (64 - f < 8) f -= 64;
    for (; f < 56; f++) this.chunk.push(0);
    for (var i = 0; i < 4; i++) this.chunk.push(Math.floor(a / 4294967296) >>> 8 * (3 - i) & 255);
    for (var j = 0; j < 4; j++) this.chunk.push(a >>> 8 * (3 - j) & 255);
  };
  // a_bogus 专用 SM3 变体（与抖音 web 签名实现逐字节对齐；非 GB/T 32905 标准 SM3）
  function sm3Hex(v) { var s = new SM3(); var d = s.sum(toBytes(v)); return bytesToHex(d); }

  // ------------------------------------------------------------ AES-128 ECB
  var AES_SBOX = [
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16];

  function aesExpandKey(key) {
    var w = [], i;
    for (i = 0; i < 4; i++) w[i] = [key[4 * i], key[4 * i + 1], key[4 * i + 2], key[4 * i + 3]];
    var rcon = 1;
    for (i = 4; i < 44; i++) {
      var t = w[i - 1].slice();
      if (i % 4 === 0) {
        t.push(t.shift());
        t = [AES_SBOX[t[0]] ^ rcon, AES_SBOX[t[1]], AES_SBOX[t[2]], AES_SBOX[t[3]]];
        rcon = ((rcon << 1) ^ ((rcon & 0x80) ? 0x1b : 0)) & 0xff;
      }
      w[i] = [w[i - 4][0] ^ t[0], w[i - 4][1] ^ t[1], w[i - 4][2] ^ t[2], w[i - 4][3] ^ t[3]];
    }
    return w;
  }
  function aesEncryptBlock(key, block) {
    var w = aesExpandKey(key);
    var s = block.slice();
    function addRoundKey(round) {
      for (var cc = 0; cc < 4; cc++) {
        for (var rr = 0; rr < 4; rr++) s[4 * cc + rr] ^= w[round * 4 + cc][rr];
      }
    }
    function sub() { for (var i = 0; i < 16; i++) s[i] = AES_SBOX[s[i]]; }
    function shift() {
      var t = s[1]; s[1] = s[5]; s[5] = s[9]; s[9] = s[13]; s[13] = t;
      t = s[2]; s[2] = s[10]; s[10] = t;
      t = s[6]; s[6] = s[14]; s[14] = t;
      t = s[15]; s[15] = s[11]; s[11] = s[7]; s[7] = s[3]; s[3] = t;
    }
    function mix() {
      for (var cc = 0; cc < 4; cc++) {
        var a = s[4 * cc], b = s[4 * cc + 1], d = s[4 * cc + 2], e = s[4 * cc + 3];
        s[4 * cc] = xtime(a) ^ xtime(b) ^ b ^ d ^ e;
        s[4 * cc + 1] = a ^ xtime(b) ^ xtime(d) ^ d ^ e;
        s[4 * cc + 2] = a ^ b ^ xtime(d) ^ xtime(e) ^ e;
        s[4 * cc + 3] = xtime(a) ^ a ^ b ^ d ^ xtime(e);
      }
    }
    addRoundKey(0);
    for (var rd = 1; rd <= 9; rd++) { sub(); shift(); mix(); addRoundKey(rd); }
    sub(); shift(); addRoundKey(10);
    return s;
  }
  function xtime(a) { return ((a << 1) ^ ((a & 0x80) ? 0x1b : 0)) & 0xff; }
  function aes128Ecb(key, data) {
    var k = toBytes(key), d = toBytes(data), out = [], i;
    for (i = 0; i + 16 <= d.length; i += 16) out = out.concat(aesEncryptBlock(k, d.slice(i, i + 16)));
    return out;
  }

  // -------------------------------------------------------------------- RC4
  function rc4(bytes, key) {
    var s = [], i, j = 0, t, out = [], x = 0, k;
    for (i = 0; i < 256; i++) s[i] = i;
    for (i = 0; i < 256; i++) { j = (j + s[i] + key[i % key.length]) % 256; t = s[i]; s[i] = s[j]; s[j] = t; }
    j = 0;
    for (k = 0; k < bytes.length; k++) {
      x = (x + 1) & 255; j = (j + s[x]) & 255; t = s[x]; s[x] = s[j]; s[j] = t;
      out[k] = (bytes[k] ^ s[(s[x] + s[j]) & 255]) & 255;
    }
    return out;
  }

  // iOS 变体：参考实现中的置换为 `s[i], s[j] = s[j], s[j]`（s[j] 未变，非标准 RC4）。
  // 为与参考产物逐字节一致，这里忠实复刻该变体。
  function rc4IosQuirk(bytes, key) {
    var s = [], i, j = 0;
    for (i = 0; i < 256; i++) s[i] = i;
    for (i = 0; i < 256; i++) { j = (j + s[i] + key[i % key.length]) % 256; s[i] = s[j]; }
    var ks = [], ii = 0, t;
    j = 0;
    for (var k = 0; k < bytes.length; k++) {
      ii = (ii + 1) % 256; j = (j + s[ii]) % 256; s[ii] = s[j]; t = (s[ii] + s[j]) % 256; ks.push(s[t]);
    }
    var out = [];
    for (var m = 0; m < bytes.length; m++) out[m] = (ks[m] ^ bytes[m]) & 255;
    return out;
  }

  // ------------------------------------------------------- 64-bit (lo/hi) ops
  function ror64(a, n) {
    n %= 64;
    if (n === 0) return [a[0], a[1]];
    var lo = a[0], hi = a[1];
    if (n < 32) return [((lo >>> n) | (hi << (32 - n))) >>> 0, ((hi >>> n) | (lo << (32 - n))) >>> 0];
    n -= 32;
    return [((hi >>> n) | (lo << (32 - n))) >>> 0, ((lo >>> n) | (hi << (32 - n))) >>> 0];
  }
  function add64(a, b) {
    var lo = a[0] + b[0];
    var carry = lo >= 4294967296 ? 1 : 0;
    var hi = a[1] + b[1] + carry;
    return [lo >>> 0, hi >>> 0];
  }
  function xor64(a, b) { return [(a[0] ^ b[0]) >>> 0, (a[1] ^ b[1]) >>> 0]; }
  function xor64i(a, i) { return [(a[0] ^ i) >>> 0, a[1]]; }
  function u64FromLE8(bytes, off) {
    return [(bytes[off] | bytes[off + 1] << 8 | bytes[off + 2] << 16 | bytes[off + 3] << 24) >>> 0,
            (bytes[off + 4] | bytes[off + 5] << 8 | bytes[off + 6] << 16 | bytes[off + 7] << 24) >>> 0];
  }
  var HEX_TABLE = '0123456789abcdef';

  // ------------------------------------------------------------ Douyin core
  var defaults = {
    aid: 1128,
    platform: 'android',
    appVersion: '40.5.0',
    versionCode: 400500,
    licenseId: 1588093228,
    // Android MSSDK v4.0.5 / iOS MSSDK v04.09.00
    mssdkVersionCodeAndroid: 67503104,
    mssdkVersionCodeIos: 67698689,
    sdkVerAndroid: 'v04.05.00-ml-android',
    sdkVerIos: 'v04.09.00-ml-iOS'
  };

  function xssStub(body) {
    if (body == null || body === '' || (body.length === 0)) return '';
    return md5Hex(toBytes(body)).toUpperCase();
  }

  function khronos() { return Math.floor(Date.now() / 1000); }

  function traceId() {
    var s = '';
    for (var i = 0; i < 32; i++) s += HEX[Math.floor(Math.random() * 16)];
    return s;
  }

  function rnd16() { return Math.floor(Math.random() * 65536); }

  function reverseBits8(n) {
    var r = 0, i;
    for (i = 0; i < 8; i++) { r = (r << 1) | (n & 1); n >>= 1; }
    return r & 255;
  }
  function swapNibbles(n) { return (((n & 0x0f) << 4) | ((n >> 4) & 0x0f)) & 255; }

  // X-Gorgon — Android 8404
  function xgorgon(opts) {
    opts = opts || {};
    var body = opts.body, query = opts.query || '', kh = opts.khronos != null ? opts.khronos : khronos();
    var xgRand = opts.rand != null ? (opts.rand & 0xffff) : rnd16();
    var xgSeed = 320;
    var mssdk = opts.mssdkVersionCode != null ? opts.mssdkVersionCode : defaults.mssdkVersionCodeAndroid;
    var bmd5 = (body != null && body !== '' && !(body.length === 0)) ? md5Digest(toBytes(body)) : null;

    var data = md5Digest(toBytes(query)).slice(0, 4);
    data = data.concat(bmd5 ? bmd5.slice(0, 4) : [0, 0, 0, 0]);
    data = data.concat([0, 0, 0, 0]);
    data = data.concat(u32le(mssdk));
    data = data.concat(u32be(kh));

    var magic = [0x4a, 0x16, 0x47, 0x6c];
    var key = [magic[0], xgSeed & 255, magic[1], (xgRand >> 8) & 255, magic[2], magic[3], (xgSeed >> 8) & 255, xgRand & 255];
    var out = rc4(data, key), i, a, b;
    for (i = 0; i < out.length; i++) {
      a = out[i];
      out[i] = swapNibbles(a);
      a = (i + 1 < out.length) ? out[i + 1] : out[0];
      a = (a ^ out[i]) & 255;
      a = reverseBits8(a);
      out[i] = (~(a ^ 20)) & 255;
    }
    var res = [0x84, 0x04].concat(u32le(xgRand).slice(0, 2)).concat(u32le(xgSeed).slice(0, 2)).concat(out);
    return bytesToHex(res);
  }

  // X-Gorgon — iOS (randoms injected for determinism)
  function xgorgonIos(opts) {
    opts = opts || {};
    var query = opts.query || '', body = opts.body, kh = opts.khronos != null ? opts.khronos : khronos();
    var rand1 = opts.rand1 != null ? opts.rand1 : Math.floor(Math.random() * 256);
    var rand2 = opts.rand2 != null ? opts.rand2 : [0, 0x20, 0x40, 0x60, 0x80, 0xa0, 0xc0, 0xe0][Math.floor(Math.random() * 8)];
    var suffix = opts.suffix || (function () { var s = ''; for (var i = 0; i < 4; i++) s += HEX[Math.floor(Math.random() * 16)]; return s; })();

    var arr = [];
    arr = arr.concat(query ? hexToBytes(md5Hex(query).substr(0, 8)) : [0, 0, 0, 0]);
    arr = arr.concat(body ? hexToBytes(md5Hex(toBytes(body)).substr(0, 8)) : [0, 0, 0, 0]);
    arr = arr.concat([0x01, 0x01, 0x05, 0x04]);
    arr = arr.concat(u32be(kh));

    var key = [0x05, 0x00, 0x50, rand1, 0x47, 0x1e, 0x00, rand2];
    var cipher = rc4IosQuirk(arr, key);
    var n = cipher.length, i, a, b;
    for (i = 0; i < n; i++) {
      a = swapNibbles(cipher[i]);
      b = cipher[(i + 1) % n];
      var x = (a ^ b) & 255;
      var bin = x.toString(2); while (bin.length < 8) bin = '0' + bin;
      var leftRev = bin.substr(0, 4).split('').reverse().join('');
      var rightRev = bin.substr(4).split('').reverse().join('');
      cipher[i] = (parseInt(rightRev + leftRev, 2) ^ 0xeb) & 255;
    }
    var res = [0x84, 0x04, rand2 & 255, rand1 & 255].concat(hexToBytes(suffix)).concat(cipher);
    return bytesToHex(res);
  }

  // X-Helios — Android (64-bit Feistel, 34 rounds)
  function helios(opts) {
    opts = opts || {};
    var kh = opts.khronos != null ? opts.khronos : khronos();
    var rand = opts.rand != null ? (opts.rand >>> 0) : Math.floor(Math.random() * 4294967296);
    var aid = opts.aid != null ? opts.aid : defaults.aid;

    var data = u32le(rand).concat(utf8Bytes(String(aid)));
    var keySum = md5Digest(data);
    var keys = [], i;
    for (i = 0; i < 16; i++) { keys[2 * i] = HEX_TABLE.charCodeAt(keySum[i] >> 4); keys[2 * i + 1] = HEX_TABLE.charCodeAt(keySum[i] & 15); }

    var hashTable = [u64FromLE8(keys, 0)];
    var keyMatrix = [u64FromLE8(keys, 0), u64FromLE8(keys, 8), u64FromLE8(keys, 16), u64FromLE8(keys, 24)];
    var buf0 = keyMatrix[0], buf8 = keyMatrix[1];
    keyMatrix.shift(); keyMatrix.shift();
    for (i = 0; i < 0x22; i++) {
      var x9 = buf0, x8 = buf8;
      x8 = ror64(x8, 8);
      x8 = add64(x8, x9);
      x8 = xor64i(x8, i);
      keyMatrix.push(x8);
      x8 = xor64(x8, ror64(x9, 61));
      hashTable.push(x8);
      buf0 = x8; buf8 = keyMatrix[0]; keyMatrix.shift();
    }

    var msg = utf8Bytes(String(kh) + '-' + (opts.licenseId != null ? opts.licenseId : defaults.licenseId) + '-' + aid);
    // PKCS7 pad to 16
    var padLen = 16 - (msg.length % 16);
    for (i = 0; i < padLen; i++) msg.push(padLen);

    var out = [];
    for (var off = 0; off < msg.length; off += 16) {
      var d0 = u64FromLE8(msg, off), d1 = u64FromLE8(msg, off + 8);
      for (i = 0; i < 0x22; i++) {
        d1 = xor64(hashTable[i], add64(d0, ror64(d1, 8)));
        d0 = xor64(d1, ror64(d0, 61));
      }
      out = out.concat(u32le(d0[0])).concat(u32le(d0[1])).concat(u32le(d1[0])).concat(u32le(d1[1]));
    }
    return b64encode(u32le(rand).concat(out));
  }

  // X-Helios — iOS (AES-128-ECB based)
  function heliosIos(opts) {
    opts = opts || {};
    var kh = opts.khronos != null ? opts.khronos : khronos();
    var rand = opts.rand != null ? (opts.rand >>> 0) : Math.floor(Math.random() * 4294967296);
    var aid = opts.aid != null ? opts.aid : defaults.aid;
    var licenseId = opts.licenseId != null ? opts.licenseId : defaults.licenseId;

    var plain = utf8Bytes(String(kh) + '-' + licenseId + '-' + aid);
    var padLen = 16 - (plain.length % 16);
    for (var i = 0; i < padLen; i++) plain.push(padLen);

    var randBytes = u32le(rand);
    var keybuf = utf8Bytes(md5Hex(randBytes.concat(utf8Bytes(String(aid)))));
    var key = keybuf.slice(0, 16), aesInput = keybuf.slice(16);
    var tmp1 = aesEncryptBlock(key, aesInput);
    var tmp2 = aesEncryptBlock(key, tmp1);
    var x = tmp1.concat(tmp2), y = [];
    for (i = 0; i < x.length; i++) y[i] = (x[i] ^ plain[i]) & 255;
    return b64encode(randBytes.concat(y));
  }

  // X-Argus / X-Ladon — deterministic fallback (native impls unavailable)
  function ladon(opts) {
    opts = opts || {};
    var kh = opts.khronos != null ? opts.khronos : khronos();
    return b64encode(u32be(kh));
  }
  function argus(opts) {
    opts = opts || {};
    var kh = opts.khronos != null ? opts.khronos : khronos();
    return b64encode(u32le(kh));
  }

  // ------------------------------------------------------------ a_bogus / X-Bogus
  var BASE64_TABLES = {
    s0: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=',
    s1: 'Dkdpgh4ZKsQB80/Mfvw36XI1R25+WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe=',
    s2: 'Dkdpgh4ZKsQB80/Mfvw36XI1R25-WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe=',
    s3: 'ckdp1h4ZKsUB80/Mfvw36XIgR25+WQAlEi7NLboqYTOPuzmFjJnryx9HVGDaStCe',
    s4: 'Dkdpgh2ZmsQB80/MfvV36XI1R45-WUAlEixNLwoqYTOPuzKFjJnry79HbGcaStCe'
  };

  function customBase64Encode(longStr, tableKey) {
    tableKey = tableKey || 's2';
    var constant = { 0: 16515072, 1: 258048, 2: 4032, str: BASE64_TABLES[tableKey] };
    var result = '', lound = 0, longInt = getLongInt(lound, longStr), i;
    for (i = 0; i < (longStr.length / 3) * 4; i++) {
      if (Math.floor(i / 4) !== lound) { lound += 1; longInt = getLongInt(lound, longStr); }
      var k = i % 4, temp = 0;
      if (k === 0) result += constant.str.charAt((longInt & constant[0]) >> 18);
      else if (k === 1) result += constant.str.charAt((longInt & constant[1]) >> 12);
      else if (k === 2) result += constant.str.charAt((longInt & constant[2]) >> 6);
      else result += constant.str.charAt(longInt & 63);
    }
    return result;
  }
  function getLongInt(round, s) { round = round * 3; return (s.charCodeAt(round) << 16) | (s.charCodeAt(round + 1) << 8) | (s.charCodeAt(round + 2)); }
  function generRandom(r, o) {
    return [(r & 255 & 170) | o[0] & 85, (r & 255 & 85) | o[0] & 170, (r >> 8 & 255 & 170) | o[1] & 85, (r >> 8 & 255 & 85) | o[1] & 170];
  }
  function rc4Str(plaintext, key) {
    var s = [], i, j = 0, t;
    for (i = 0; i < 256; i++) s[i] = i;
    for (i = 0; i < 256; i++) { j = (j + s[i] + key.charCodeAt(i % key.length)) % 256; t = s[i]; s[i] = s[j]; s[j] = t; }
    var ci = 0; j = 0; var cipher = [];
    for (i = 0; i < plaintext.length; i++) {
      ci = (ci + 1) % 256; j = (j + s[ci]) % 256; t = s[ci]; s[ci] = s[j]; s[j] = t;
      cipher.push(String.fromCharCode(s[(s[ci] + s[j]) % 256] ^ plaintext.charCodeAt(i)));
    }
    return cipher.join('');
  }

  var _bogusIndex = 0;
  function xBogus(query, body) {
    if (!body || body.length === 0) body = '00000000000000000000000000000000';
    var sm3 = new SM3();
    var qH2 = sm3.sum(sm3.sum(query));
    var bH2 = sm3.sum(sm3.sum(body));
    _bogusIndex++;
    var lIdx = 63 & _bogusIndex;
    var payload = [(0 << 6) | lIdx, (0x0401 >> 8) & 255, 0xff & 0x0401, 0, qH2[14], qH2[15], bH2[14], bH2[15], 255 & Math.floor(255 * Math.random())];
    var checksum = 0; for (var i = 0; i < payload.length; i++) checksum ^= payload[i];
    var full = payload.concat([checksum]);
    var randKey = 255 & Math.floor(255 * Math.random());
    var payloadStr = String.fromCharCode.apply(null, full);
    var sBox = [], j = 0, t;
    for (i = 0; i < 256; i++) sBox[i] = i;
    for (i = 0; i < 256; i++) { j = (j + sBox[i] + randKey) % 256; t = sBox[i]; sBox[i] = sBox[j]; sBox[j] = t; }
    var ci = 0, cj = 0, cipher = [];
    for (i = 0; i < payloadStr.length; i++) {
      ci = (ci + 1) % 256; cj = (cj + sBox[ci]) % 256; t = sBox[ci]; sBox[ci] = sBox[cj]; sBox[cj] = t;
      cipher.push(String.fromCharCode(sBox[(sBox[ci] + sBox[cj]) % 256] ^ payloadStr.charCodeAt(i)));
    }
    return customBase64Encode(String.fromCharCode(0) + String.fromCharCode(randKey) + cipher.join(''), 's2');
  }

  function aBogus(query, userAgent) {
    userAgent = userAgent || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36';
    var windowEnvStr = '1536|747|1536|834|0|30|0|0|1536|834|1536|864|1525|747|24|24|Win32';
    var randList = [];
    randList = randList.concat(generRandom(Math.random() * 10000, [3, 45]));
    randList = randList.concat(generRandom(Math.random() * 10000, [1, 0]));
    randList = randList.concat(generRandom(Math.random() * 10000, [1, 5]));
    var randPrefix = String.fromCharCode.apply(null, randList);

    var sm3 = new SM3();
    var startTime = Date.now();
    var urlParamsList = sm3.sum(sm3.sum(query + 'cus'));
    var cus = sm3.sum(sm3.sum('cus'));
    var ua = sm3.sum(customBase64Encode(rc4Str(userAgent, String.fromCharCode(0, 1, 14)), 's3'));
    var endTime = Date.now();

    var b = { 8: 3, 10: endTime, 15: { aid: 6383, pageId: 6241 }, 16: startTime, 18: 44 };
    b[20] = (b[16] >> 24) & 255; b[21] = (b[16] >> 16) & 255; b[22] = (b[16] >> 8) & 255; b[23] = b[16] & 255;
    b[24] = (b[16] / 256 / 256 / 256 / 256) >> 0; b[25] = (b[16] / 256 / 256 / 256 / 256 / 256) >> 0;
    var A = [0, 1, 14];
    b[26] = (A[0] >> 24) & 255; b[27] = (A[0] >> 16) & 255; b[28] = (A[0] >> 8) & 255; b[29] = A[0] & 255;
    b[30] = (A[1] / 256) & 255; b[31] = (A[1] % 256) & 255; b[32] = (A[1] >> 24) & 255; b[33] = (A[1] >> 16) & 255;
    b[34] = (A[2] >> 24) & 255; b[35] = (A[2] >> 16) & 255; b[36] = (A[2] >> 8) & 255; b[37] = A[2] & 255;
    b[38] = urlParamsList[21]; b[39] = urlParamsList[22]; b[40] = cus[21]; b[41] = cus[22]; b[42] = ua[23]; b[43] = ua[24];
    b[44] = (b[10] >> 24) & 255; b[45] = (b[10] >> 16) & 255; b[46] = (b[10] >> 8) & 255; b[47] = b[10] & 255;
    b[48] = b[8]; b[49] = (b[10] / 256 / 256 / 256 / 256) >> 0; b[50] = (b[10] / 256 / 256 / 256 / 256 / 256) >> 0;
    b[52] = (b[15].pageId >> 24) & 255; b[53] = (b[15].pageId >> 16) & 255; b[54] = (b[15].pageId >> 8) & 255; b[55] = b[15].pageId & 255;
    b[57] = b[15].aid & 255; b[58] = (b[15].aid >> 8) & 255; b[59] = (b[15].aid >> 16) & 255; b[60] = (b[15].aid >> 24) & 255;

    var winEnv = [];
    for (var idx = 0; idx < windowEnvStr.length; idx++) winEnv.push(windowEnvStr.charCodeAt(idx));
    b[64] = winEnv.length; b[65] = b[64] & 255; b[66] = (b[64] >> 8) & 255;
    b[69] = 0; b[70] = b[69] & 255; b[71] = (b[69] >> 8) & 255;
    b[72] = b[18] ^ b[20] ^ b[26] ^ b[30] ^ b[38] ^ b[40] ^ b[42] ^ b[21] ^ b[27] ^ b[31] ^ b[35] ^ b[39] ^ b[41] ^ b[43] ^ b[22] ^
      b[28] ^ b[36] ^ b[23] ^ b[29] ^ b[37] ^ b[44] ^ b[45] ^ b[46] ^ b[47] ^ b[48] ^ b[49] ^ b[50] ^
      b[52] ^ b[53] ^ b[54] ^ b[55] ^ b[57] ^ b[58] ^ b[59] ^ b[60] ^ b[65] ^ b[66] ^ b[70] ^ b[71];

    var bb = [b[18], b[20], b[52], b[26], b[30], b[34], b[58], b[38], b[40], b[53], b[42], b[21], b[27], b[54], b[55], b[31],
      b[35], b[57], b[39], b[41], b[43], b[22], b[28], b[60], b[36], b[23], b[29], b[37], b[44], b[45],
      b[59], b[46], b[47], b[48], b[49], b[50], b[65], b[66], b[70], b[71]];
    bb = bb.concat(winEnv).concat(b[72]);
    var rc4Res = rc4Str(String.fromCharCode.apply(null, bb), String.fromCharCode(121));
    return customBase64Encode(randPrefix + rc4Res, 's4') + '=';
  }

  // ------------------------------------------------------------- orchestrator
  function sevenGods(opts) {
    opts = opts || {};
    var kh = opts.khronos != null ? opts.khronos : khronos();
    var query = opts.query || '';
    var body = opts.body;
    var platform = opts.platform || defaults.platform;
    var gorgon = platform === 'ios'
      ? xgorgonIos({ query: query, body: body, khronos: kh, rand1: opts.rand1, rand2: opts.rand2, suffix: opts.suffix })
      : xgorgon({ query: query, body: body, khronos: kh, rand: opts.rand, mssdkVersionCode: opts.mssdkVersionCode });
    var hel = platform === 'ios'
      ? heliosIos({ khronos: kh, rand: opts.heliosRand, aid: opts.aid, licenseId: opts.licenseId })
      : helios({ khronos: kh, rand: opts.heliosRand, aid: opts.aid, licenseId: opts.licenseId });
    var out = {
      'X-Khronos': String(kh),
      'X-Gorgon': gorgon,
      'X-Helios': hel,
      'X-Argus': argus({ khronos: kh }),
      'X-Ladon': ladon({ khronos: kh }),
      'X-TT-Trace-Id': traceId()
    };
    var stub = xssStub(body);
    if (stub) out['X-SS-Stub'] = stub;
    return out;
  }

  var DouyinSign = {
    defaults: defaults,
    md5: md5Hex,
    sm3Hex: sm3Hex,
    aes128Ecb: function (key, data) { return bytesToHex(aes128Ecb(key, data)); },
    rc4: function (data, key) { return bytesToHex(rc4(toBytes(data), toBytes(key))); },
    bytesToHex: bytesToHex,
    xssStub: xssStub,
    khronos: khronos,
    traceId: traceId,
    xgorgon: xgorgon,
    xgorgonIos: xgorgonIos,
    helios: helios,
    heliosIos: heliosIos,
    argus: argus,
    ladon: ladon,
    xBogus: xBogus,
    aBogus: aBogus,
    sevenGods: sevenGods
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = DouyinSign;
  global.DouyinSign = DouyinSign;
})(typeof globalThis !== 'undefined' ? globalThis : this);
