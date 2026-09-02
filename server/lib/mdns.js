"use strict";
// 最小の mDNS（Bonjour）レスポンダ。`_mrdrop._tcp.local` を広告して、
// iPhone 側が「同じ Wi-Fi にいる PC」を設定ゼロで見つけられるようにする。
//
// 🔴 外部パッケージは使わない。npm install なしでいきなり動くこと自体が価値なので、
//    DNS のパケットは自前で組み立てる。組み立て/読み取りは test/mdns.test.js で往復させて固定。

const dgram = require("dgram");
const os = require("os");
const { EventEmitter } = require("events");

const MDNS_ADDR = "224.0.0.251";
const MDNS_PORT = 5353;
const TYPE = { A: 1, PTR: 12, TXT: 16, SRV: 33, ANY: 255 };
const CLASS_IN = 1;
const FLUSH = 0x8000;          // cache-flush ビット（古い値を捨てさせる）
const DEFAULT_TTL = 120;

// ── 名前の符号化・復号 ───────────────────────────────────────────
function encodeName(name) {
  const labels = String(name).split(".").filter((s) => s.length > 0);
  const out = [];
  for (const l of labels) {
    const b = Buffer.from(l, "utf8");
    if (b.length > 63) throw new Error("ラベルが長すぎる: " + l);
    out.push(Buffer.from([b.length]), b);
  }
  out.push(Buffer.from([0]));
  return Buffer.concat(out);
}

// 🔴 圧縮ポインタ（0xC0）を必ず追えること。Apple の問い合わせは実際に使ってくる。
function readName(buf, off) {
  const parts = [];
  let next = -1;
  let guard = 0;
  for (;;) {
    if (guard++ > 128) throw new Error("名前がループしている");
    if (off >= buf.length) throw new Error("名前が途中で切れている");
    const len = buf[off];
    if (len === 0) { off += 1; if (next < 0) next = off; break; }
    if ((len & 0xc0) === 0xc0) {
      if (off + 1 >= buf.length) throw new Error("圧縮ポインタが切れている");
      const ptr = ((len & 0x3f) << 8) | buf[off + 1];
      if (next < 0) next = off + 2;
      off = ptr;
      continue;
    }
    if (off + 1 + len > buf.length) throw new Error("ラベルが切れている");
    parts.push(buf.subarray(off + 1, off + 1 + len).toString("utf8"));
    off += 1 + len;
  }
  return { name: parts.join("."), off: next };
}

// ── レコードの組み立て ───────────────────────────────────────────
function record(name, type, data, opts = {}) {
  const ttl = opts.ttl === undefined ? DEFAULT_TTL : opts.ttl;
  const flush = opts.flush === undefined ? true : opts.flush;
  const head = Buffer.alloc(10);
  head.writeUInt16BE(type, 0);
  head.writeUInt16BE(CLASS_IN | (flush ? FLUSH : 0), 2);
  head.writeUInt32BE(ttl, 4);
  head.writeUInt16BE(data.length, 8);
  return Buffer.concat([encodeName(name), head, data]);
}

const rdataA = (ip) => Buffer.from(ip.split(".").map((x) => parseInt(x, 10) & 0xff));
const rdataPtr = (target) => encodeName(target);

function rdataSrv(port, target) {
  const b = Buffer.alloc(6);
  b.writeUInt16BE(0, 0);        // priority
  b.writeUInt16BE(0, 2);        // weight
  b.writeUInt16BE(port, 4);
  return Buffer.concat([b, encodeName(target)]);
}

function rdataTxt(obj) {
  const parts = [];
  for (const [k, v] of Object.entries(obj)) {
    const b = Buffer.from(`${k}=${v}`, "utf8");
    if (b.length > 255) throw new Error("TXT の項目が長すぎる: " + k);
    parts.push(Buffer.from([b.length]), b);
  }
  return parts.length ? Buffer.concat(parts) : Buffer.from([0]);
}

function buildMessage(answers, additionals, isResponse) {
  const h = Buffer.alloc(12);
  h.writeUInt16BE(0, 0);                              // mDNS では ID は 0
  h.writeUInt16BE(isResponse ? 0x8400 : 0x0000, 2);   // QR=1 AA=1
  h.writeUInt16BE(isResponse ? 0 : answers.length, 4);
  h.writeUInt16BE(isResponse ? answers.length : 0, 6);
  h.writeUInt16BE(0, 8);
  h.writeUInt16BE(additionals.length, 10);
  return Buffer.concat([h, ...answers, ...additionals]);
}

function buildResponse(answers, additionals = []) { return buildMessage(answers, additionals, true); }

// 🔴 QU ビット（qclass の最上位）を立てないと、答えは 224.0.0.251:5353 宛の
//    マルチキャストでしか返ってこない。こちらが適当な番号で待っていると受け取れない。
//    一問一答で聞くときは必ず「ユニキャストで返して」と頼む。
function buildQuery(name, type, unicastResponse = true) {
  const q = Buffer.alloc(4);
  q.writeUInt16BE(type, 0);
  q.writeUInt16BE(CLASS_IN | (unicastResponse ? 0x8000 : 0), 2);
  return buildMessage([Buffer.concat([encodeName(name), q])], [], false);
}

// ── 読み取り ────────────────────────────────────────────────────
function decodeRecord(buf, name, type, klass, ttl, rdata, rdataOff) {
  const base = { name, type, class: klass & 0x7fff, flush: (klass & FLUSH) !== 0, ttl };
  if (type === TYPE.A && rdata.length === 4) return { ...base, address: Array.from(rdata).join(".") };
  if (type === TYPE.PTR) return { ...base, ptr: readName(buf, rdataOff).name };
  if (type === TYPE.SRV) {
    return { ...base, port: rdata.readUInt16BE(4), target: readName(buf, rdataOff + 6).name };
  }
  if (type === TYPE.TXT) {
    const txt = {};
    let o = 0;
    while (o < rdata.length) {
      const l = rdata[o];
      const s = rdata.subarray(o + 1, o + 1 + l).toString("utf8");
      o += 1 + l;
      if (!s) continue;
      const i = s.indexOf("=");
      if (i < 0) txt[s] = ""; else txt[s.slice(0, i)] = s.slice(i + 1);
    }
    return { ...base, txt };
  }
  return { ...base, rdata };
}

function parseMessage(buf) {
  if (buf.length < 12) throw new Error("パケットが短すぎる");
  const flags = buf.readUInt16BE(2);
  const counts = [buf.readUInt16BE(4), buf.readUInt16BE(6), buf.readUInt16BE(8), buf.readUInt16BE(10)];
  let off = 12;
  const questions = [];
  for (let i = 0; i < counts[0]; i++) {
    const r = readName(buf, off);
    off = r.off;
    if (off + 4 > buf.length) throw new Error("質問が切れている");
    const qclass = buf.readUInt16BE(off + 2);
    questions.push({
      name: r.name,
      type: buf.readUInt16BE(off),
      unicast: (qclass & 0x8000) !== 0,          // QU ビット（ユニキャストで返せの指示）
      class: qclass & 0x7fff,
    });
    off += 4;
  }
  const sections = [[], [], []];
  for (let s = 0; s < 3; s++) {
    for (let i = 0; i < counts[s + 1]; i++) {
      const r = readName(buf, off);
      off = r.off;
      if (off + 10 > buf.length) throw new Error("レコードが切れている");
      const type = buf.readUInt16BE(off);
      const klass = buf.readUInt16BE(off + 2);
      const ttl = buf.readUInt32BE(off + 4);
      const rdlen = buf.readUInt16BE(off + 8);
      const rdataOff = off + 10;
      if (rdataOff + rdlen > buf.length) throw new Error("rdata が切れている");
      sections[s].push(decodeRecord(buf, r.name, type, klass, ttl, buf.subarray(rdataOff, rdataOff + rdlen), rdataOff));
      off = rdataOff + rdlen;
    }
  }
  return {
    isQuery: (flags & 0x8000) === 0,
    questions,
    answers: sections[0],
    authorities: sections[1],
    additionals: sections[2],
  };
}

// ── ネットワーク合わせ ───────────────────────────────────────────
const ip2int = (ip) => ip.split(".").reduce((a, x) => (a << 8 >>> 0) + (parseInt(x, 10) & 0xff), 0) >>> 0;

function localIPv4s() {
  const out = [];
  for (const [name, addrs] of Object.entries(os.networkInterfaces())) {
    for (const a of addrs || []) {
      if (a.family === "IPv4" && !a.internal) out.push({ iface: name, address: a.address, netmask: a.netmask });
    }
  }
  return out;
}

// 🔴 Windows の開発機は NIC が多い（Wi-Fi・有線・Hyper-V・VirtualBox…）。
//    問い合わせてきた相手と同じサブネットの住所を返さないと、iPhone は繋げない。
function addressFacing(remote) {
  const list = localIPv4s();
  if (!list.length) return null;
  try {
    const r = ip2int(remote);
    for (const a of list) {
      const m = ip2int(a.netmask);
      if (((ip2int(a.address) & m) >>> 0) === ((r & m) >>> 0)) return a.address;
    }
  } catch { /* remote が IPv6 などのときは既定へ落ちる */ }
  return list[0].address;
}

// ── レスポンダ本体 ───────────────────────────────────────────────
class Responder extends EventEmitter {
  constructor(opts) {
    super();
    this.serviceType = (opts.serviceType || "_mrdrop._tcp") + ".local";
    this.instance = String(opts.instance || os.hostname()).replace(/\./g, "-");
    this.instanceFqdn = `${this.instance}.${this.serviceType}`;
    this.host = `${String(opts.hostname || os.hostname()).replace(/\./g, "-")}.local`;
    this.port = opts.port;
    this.txt = opts.txt || {};
    this.socket = null;
    this.timers = [];
  }

  start() {
    return new Promise((resolve) => {
      const sock = dgram.createSocket({ type: "udp4", reuseAddr: true });
      this.socket = sock;

      sock.on("error", (err) => {
        // 🔴 5353 が塞がっていても本体は落とさない。ブラウザ経路はそれでも使えるので、
        //    「自動で見つからないだけ」に留めるのが正しい壊れ方。
        this.emit("warn", `mDNS を開始できませんでした（${err.code || err.message}）。自動発見は使えませんが、ブラウザからは使えます。`);
        try { sock.close(); } catch { /* 閉じ済み */ }
        this.socket = null;
        resolve(false);
      });

      sock.bind(MDNS_PORT, () => {
        try { sock.setMulticastTTL(255); } catch { /* 環境による */ }
        try { sock.setMulticastLoopback(true); } catch { /* 自分の広告を自分でも見えるように */ }
        for (const a of localIPv4s()) {
          try { sock.addMembership(MDNS_ADDR, a.address); } catch { /* この NIC は使えない */ }
        }
        sock.on("message", (msg, rinfo) => this._onMessage(msg, rinfo));
        this.announce();
        this.timers.push(setTimeout(() => this.announce(), 1000));
        this.timers.push(setTimeout(() => this.announce(), 3000));
        resolve(true);
      });
    });
  }

  _recordsFor(qname, qtype, ip) {
    const eq = (a, b) => a.toLowerCase() === b.toLowerCase();
    const want = (t) => qtype === t || qtype === TYPE.ANY;
    const srv = record(this.instanceFqdn, TYPE.SRV, rdataSrv(this.port, this.host));
    const txt = record(this.instanceFqdn, TYPE.TXT, rdataTxt(this.txt));
    const a = ip ? record(this.host, TYPE.A, rdataA(ip)) : null;

    if (eq(qname, "_services._dns-sd._udp.local") && want(TYPE.PTR)) {
      return { answers: [record("_services._dns-sd._udp.local", TYPE.PTR, rdataPtr(this.serviceType), { flush: false })], additionals: [] };
    }
    if (eq(qname, this.serviceType) && want(TYPE.PTR)) {
      return {
        answers: [record(this.serviceType, TYPE.PTR, rdataPtr(this.instanceFqdn), { flush: false })],
        additionals: [srv, txt, ...(a ? [a] : [])],
      };
    }
    if (eq(qname, this.instanceFqdn) && want(TYPE.SRV)) {
      return { answers: [srv], additionals: [txt, ...(a ? [a] : [])] };
    }
    if (eq(qname, this.instanceFqdn) && want(TYPE.TXT)) {
      return { answers: [txt], additionals: [srv, ...(a ? [a] : [])] };
    }
    if (eq(qname, this.host) && want(TYPE.A) && a) {
      return { answers: [a], additionals: [] };
    }
    return null;
  }

  _onMessage(msg, rinfo) {
    let m;
    try { m = parseMessage(msg); } catch { return; }     // 壊れたパケットは黙って捨てる
    if (!m.isQuery || !m.questions.length) return;

    const ip = addressFacing(rinfo.address);
    const answers = [];
    const additionals = [];
    let unicast = false;
    for (const q of m.questions) {
      const r = this._recordsFor(q.name, q.type, ip);
      if (!r) continue;
      answers.push(...r.answers);
      additionals.push(...r.additionals);
      if (q.unicast) unicast = true;
    }
    if (!answers.length) return;

    const pkt = buildResponse(answers, additionals);
    // 相手が QU を立てていればユニキャスト。そうでなくても両方に投げておく
    // （重複しても受け側が捨てるだけ。届かないより良い）。
    if (unicast) this._send(pkt, rinfo.port, rinfo.address);
    this._send(pkt, MDNS_PORT, MDNS_ADDR, ip);
  }

  _send(pkt, port, addr, viaAddress) {
    if (!this.socket) return;
    try {
      if (viaAddress) { try { this.socket.setMulticastInterface(viaAddress); } catch { /* 既定のまま */ } }
      this.socket.send(pkt, port, addr, () => {});
    } catch { /* 送れないときは黙って諦める（相手が消えただけ） */ }
  }

  _fullSet(ip, ttl) {
    const o = ttl === undefined ? {} : { ttl };
    return [
      record(this.serviceType, TYPE.PTR, rdataPtr(this.instanceFqdn), { flush: false, ...o }),
      record(this.instanceFqdn, TYPE.SRV, rdataSrv(this.port, this.host), o),
      record(this.instanceFqdn, TYPE.TXT, rdataTxt(this.txt), o),
      ...(ip ? [record(this.host, TYPE.A, rdataA(ip), o)] : []),
    ];
  }

  // 全 NIC へ順に広告する（どの NIC が Wi-Fi かは分からないので全部に出す）
  announce(ttl) {
    for (const a of localIPv4s()) {
      this._send(buildResponse(this._fullSet(a.address, ttl)), MDNS_PORT, MDNS_ADDR, a.address);
    }
  }

  stop() {
    for (const t of this.timers) clearTimeout(t);
    this.timers = [];
    if (!this.socket) return Promise.resolve();
    this.announce(0);                                  // TTL 0 = さよなら。相手の一覧から即消える
    return new Promise((resolve) => {
      setTimeout(() => {
        try { this.socket.close(); } catch { /* 閉じ済み */ }
        this.socket = null;
        resolve();
      }, 120);
    });
  }
}

// 手元で確かめる用。`_mrdrop._tcp.local` を尋ねて、返ってきたものを集める。
function browse(ms = 2500, serviceType = "_mrdrop._tcp.local") {
  return new Promise((resolve) => {
    const found = new Map();
    const sock = dgram.createSocket({ type: "udp4", reuseAddr: true });
    sock.on("error", () => { try { sock.close(); } catch { /* 済み */ } resolve([]); });
    sock.bind(0, () => {
      try { sock.setMulticastTTL(255); sock.setMulticastLoopback(true); } catch { /* 環境による */ }
      for (const a of localIPv4s()) { try { sock.addMembership(MDNS_ADDR, a.address); } catch { /* この NIC は不可 */ } }
      sock.on("message", (msg) => {
        let m;
        try { m = parseMessage(msg); } catch { return; }
        if (m.isQuery) return;
        const all = [...m.answers, ...m.additionals];
        const srv = all.find((r) => r.type === TYPE.SRV);
        if (!srv) return;
        const txt = all.find((r) => r.type === TYPE.TXT);
        const a = all.find((r) => r.type === TYPE.A);
        found.set(srv.name, { name: srv.name, host: srv.target, port: srv.port, address: a && a.address, txt: (txt && txt.txt) || {} });
      });
      sock.send(buildQuery(serviceType, TYPE.PTR), MDNS_PORT, MDNS_ADDR, () => {});
      setTimeout(() => {
        try { sock.close(); } catch { /* 済み */ }
        resolve([...found.values()]);
      }, ms);
    });
  });
}

module.exports = {
  Responder, browse, localIPv4s, addressFacing,
  // テスト用
  TYPE, encodeName, readName, record, rdataA, rdataPtr, rdataSrv, rdataTxt,
  buildResponse, buildQuery, parseMessage,
};
