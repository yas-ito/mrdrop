#!/usr/bin/env node
// ほかの人に渡す ZIP を作る。**Node があれば両OSで同じものが作れる。**
//
//   node build/make-package.js                          既定の場所に作る
//   node build/make-package.js out.zip                  出力先を指定する
//   node build/make-package.js --with-node "C:\Program Files\nodejs\node.exe"
//                                                       node.exe も同梱する（受け取る人は Node 不要）
//
// 中身（受け取る人から見える名前）:
//   MrDrop_v<版>_win/はじめる.bat            ← ダブルクリックするだけ
//   MrDrop_v<版>_win/取扱説明書.html
//   MrDrop_v<版>_win/server/…                ← 本体（外部パッケージゼロ）
//   MrDrop_v<版>_win/scripts/install-windows.ps1  ← ずっと使う人だけ
//   MrDrop_v<版>_win/node/node.exe           ← --with-node のときだけ
//
// 🔴 **物を足さない。**最後に「中身がこの一覧とちょうど同じか」を数えて検査している。
//    渡す相手にとって、フォルダに知らない物が入っているのは不安の元でしかない。
//
// ══════════════════════════════════════════════════════════════════════
// 🔴 ZIP を自前で書いている理由（一撃極 build/make-zip.js と同じ）
// ══════════════════════════════════════════════════════════════════════
//   ZIP の汎用フラグ **bit 11** が「ファイル名は UTF-8」の意味。これを立てないと
//   Windows のエクスプローラが CP932 として読み、**日本語のファイル名が化ける**
//   （`はじめる.bat` が `πé╖…` になる）。zip コマンドや macOS の ditto では
//   立てられないことがあるので、自前で書いて確実に立てる。
//
// 🔴 **`node_modules` を入れない。**外部パッケージゼロがこの道具の値打ちなので、
//    そもそも存在しない。将来 npm に手を出したら、ここも作り直しになる。

"use strict";

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const REPO = path.join(__dirname, "..");
const fail = (m) => { console.error("🔴 " + m); process.exit(1); };
const say = (m) => console.log("  " + m);

// ───────── 引数 ─────────
let outArg = null, nodeExe = null;
{
  const a = process.argv.slice(2);
  for (let i = 0; i < a.length; i++) {
    if (a[i] === "--with-node") nodeExe = a[++i];
    else outArg = a[i];
  }
}

// ───────── 版数（package.json と本体で食い違っていないか）─────────
const VERSION = JSON.parse(fs.readFileSync(path.join(REPO, "package.json"), "utf8")).version;
{
  const src = fs.readFileSync(path.join(REPO, "server", "mrdrop.js"), "utf8");
  const m = src.match(/^const VERSION = "([^"]+)"/m);
  if (!m) fail("server/mrdrop.js の VERSION が読めません");
  if (m[1] !== VERSION) fail(`版数が食い違っています: package.json=${VERSION} / mrdrop.js=${m[1]}`);
}
const STEM = `MrDrop_v${VERSION}_win`;
const OUT = path.resolve(outArg || path.join(REPO, "_build", `${STEM}.zip`));
// 🔴 ZIP そのものの名前は ASCII。ダウンロードの途中で化ける経路がまだ世の中にある。
if (/[^\x20-\x7e]/.test(path.basename(OUT))) fail(`ZIP の名前に ASCII 以外が入っている: ${path.basename(OUT)}`);

// ───────── 入れる物を集める ─────────
const read = (rel) => {
  const p = path.join(REPO, rel);
  if (!fs.existsSync(p)) fail(`${rel} がありません`);
  return fs.readFileSync(p);
};

// 🔴 bat は ASCII・CRLF。cmd.exe は .bat を CP932 として読むので、日本語が混ざると壊れる。
//    .gitattributes で CRLF に固定してあるが、ここでも直して検査する（作る側で完結させる）。
let bat = read("はじめる.bat");
if (bat.some((c) => c >= 128)) fail("はじめる.bat に非ASCIIが混ざっています（cmd が CP932 で読むため壊れます）");
bat = Buffer.from(bat.toString("latin1").replace(/\r\n/g, "\n").replace(/\n/g, "\r\n"), "latin1");

// 🔴 ps1 は BOM 付き UTF-8。BOM が無いと PowerShell 5.1 が CP932 として読み、日本語で全滅する。
const ps1 = read("scripts/install-windows.ps1");
if (!(ps1[0] === 0xef && ps1[1] === 0xbb && ps1[2] === 0xbf)) {
  fail("scripts/install-windows.ps1 に BOM がありません（PowerShell 5.1 が日本語を読めなくなります）");
}

const items = [
  ["はじめる.bat", bat],
  ["取扱説明書.html", read("取扱説明書.html")],
  ["server/mrdrop.js", read("server/mrdrop.js")],
  ["server/lib/config.js", read("server/lib/config.js")],
  ["server/lib/http.js", read("server/lib/http.js")],
  ["server/lib/mdns.js", read("server/lib/mdns.js")],
  ["server/lib/names.js", read("server/lib/names.js")],
  ["server/lib/ui.js", read("server/lib/ui.js")],
  ["scripts/install-windows.ps1", ps1],
];
const dirs = ["server/", "server/lib/", "scripts/"];

if (nodeExe) {
  if (!fs.existsSync(nodeExe)) fail(`--with-node の ${nodeExe} がありません`);
  // 🔴 node.exe を配るなら Node.js のライセンス表記も一緒に配る（MIT）。
  //    ライセンス全文は Windows の Node には入っていないので、置いてある所から取る。
  const lic = path.join(path.dirname(nodeExe), "LICENSE");
  if (!fs.existsSync(lic)) {
    fail("node.exe の隣に LICENSE がありません。Node.js は MIT なので、全文を添えずに配ってはいけません。\n" +
         "   https://nodejs.org/dist/" + process.version + "/ の zip 版から LICENSE を持ってきて node.exe の隣に置いてください。");
  }
  dirs.push("node/");
  items.push(["node/node.exe", fs.readFileSync(nodeExe)]);
  items.push(["node/Node.js-LICENSE.txt", fs.readFileSync(lic)]);
}

// ───────── ZIP を書く ─────────
const CRC_TABLE = (function () {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    t[n] = c;
  }
  return t;
})();
function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}
// DOS の日時形式（2秒刻み・1980年起点）
function dosTime(d) {
  return { t: ((d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1)) & 0xffff,
           d: (((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate()) & 0xffff };
}
const FLAG_UTF8 = 0x0800;   // 🔴 bit 11 ＝「ファイル名は UTF-8」

const entries = [];
const now = new Date();
function addFile(name, data, isDir) {
  const nameBuf = Buffer.from(name, "utf8");
  const body = isDir ? Buffer.alloc(0) : zlib.deflateRawSync(data, { level: 9 });
  entries.push({
    name: nameBuf, method: isDir ? 0 : 8, crc: isDir ? 0 : crc32(data),
    comp: body.length, uncomp: isDir ? 0 : data.length, body, time: dosTime(now), isDir,
  });
}

addFile(`${STEM}/`, Buffer.alloc(0), true);
for (const d of dirs) addFile(`${STEM}/${d}`, Buffer.alloc(0), true);
for (const [shown, data] of items) addFile(`${STEM}/${shown}`, data, false);

const chunks = [];
let offset = 0;
for (const e of entries) {
  const h = Buffer.alloc(30);
  h.writeUInt32LE(0x04034b50, 0); h.writeUInt16LE(20, 4); h.writeUInt16LE(FLAG_UTF8, 6);
  h.writeUInt16LE(e.method, 8); h.writeUInt16LE(e.time.t, 10); h.writeUInt16LE(e.time.d, 12);
  h.writeUInt32LE(e.crc, 14); h.writeUInt32LE(e.comp, 18); h.writeUInt32LE(e.uncomp, 22);
  h.writeUInt16LE(e.name.length, 26); h.writeUInt16LE(0, 28);
  e.offset = offset;
  chunks.push(h, e.name, e.body);
  offset += h.length + e.name.length + e.body.length;
}
const cdStart = offset;
for (const e of entries) {
  const c = Buffer.alloc(46);
  c.writeUInt32LE(0x02014b50, 0); c.writeUInt16LE(20, 4); c.writeUInt16LE(20, 6);
  c.writeUInt16LE(FLAG_UTF8, 8); c.writeUInt16LE(e.method, 10);
  c.writeUInt16LE(e.time.t, 12); c.writeUInt16LE(e.time.d, 14);
  c.writeUInt32LE(e.crc, 16); c.writeUInt32LE(e.comp, 20); c.writeUInt32LE(e.uncomp, 24);
  c.writeUInt16LE(e.name.length, 28); c.writeUInt16LE(0, 30); c.writeUInt16LE(0, 32);
  c.writeUInt16LE(0, 34); c.writeUInt16LE(0, 36);
  c.writeUInt32LE(e.isDir ? 0x10 : 0, 38);
  c.writeUInt32LE(e.offset, 42);
  chunks.push(c, e.name);
  offset += c.length + e.name.length;
}
const eocd = Buffer.alloc(22);
eocd.writeUInt32LE(0x06054b50, 0);
eocd.writeUInt16LE(entries.length, 8); eocd.writeUInt16LE(entries.length, 10);
eocd.writeUInt32LE(offset - cdStart, 12); eocd.writeUInt32LE(cdStart, 16);
chunks.push(eocd);

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, Buffer.concat(chunks));

// ───────── 作った物を読み返して確かめる ─────────
// 🔴 「作れた」で終わらせない。**書いた物を読み直して**中身とフラグを確認する。
{
  const b = fs.readFileSync(OUT);
  const names = [];
  let p = 0, flagsOk = true;
  while (p + 4 <= b.length && b.readUInt32LE(p) === 0x04034b50) {
    const flags = b.readUInt16LE(p + 6);
    const nlen = b.readUInt16LE(p + 26), elen = b.readUInt16LE(p + 28), clen = b.readUInt32LE(p + 18);
    names.push(b.toString("utf8", p + 30, p + 30 + nlen));
    if (!(flags & FLAG_UTF8)) flagsOk = false;
    p += 30 + nlen + elen + clen;
  }
  if (!flagsOk) fail("UTF-8フラグ(bit 11)が立っていない。Windows で日本語のファイル名が化ける。");

  const got = names.filter((n) => !n.endsWith("/")).sort();
  const want = items.map(([shown]) => `${STEM}/${shown}`).sort();
  if (got.length !== want.length || got.some((n, i) => n !== want[i])) {
    fail("ZIP の中身が一覧と合っていない:\n" +
         "   入っている: " + got.join("\n              ") + "\n" +
         "   入れるはず: " + want.join("\n              "));
  }
  say(`中身: ${got.length} ファイル`);
  for (const n of names) say("  " + n);
  say("UTF-8フラグ(bit 11): 全エントリで立っている");
  say(nodeExe ? "node.exe: 同梱（受け取る人に Node は要りません）"
              : "node.exe: 同梱していません（受け取る人の PC に Node が要ります）");
}

console.log("");
console.log(`できあがり: ${OUT}`);
console.log(`  サイズ: ${(fs.statSync(OUT).size / 1048576).toFixed(1)} MB`);
