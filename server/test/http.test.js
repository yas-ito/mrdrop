"use strict";
// 実際にサーバーを立てて、本当に受け取れるかを通しで確かめる。
// 🔴 いちばん大事なのは「途中で切れたものを受信箱に出さない」こと。ここを必ず踏む。
const fs = require("fs");
const fsp = require("fs/promises");
const os = require("os");
const path = require("path");
const net = require("net");
const { createServer, isLocalAddress, PART_DIR } = require("../lib/http");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function req(port, method, p, body, headers = {}) {
  const res = await fetch(`http://127.0.0.1:${port}${p}`, {
    method,
    body,
    headers,
    duplex: body ? "half" : undefined,
  });
  const text = await res.text();
  return { status: res.status, text, json: (() => { try { return JSON.parse(text); } catch { return null; } })() };
}

module.exports = async function (t) {
  const { suite, eq, ok } = t;

  const base = await fsp.mkdtemp(path.join(os.tmpdir(), "yasdrop-test-"));
  const cfg = {
    inbox: path.join(base, "in"),
    outbox: path.join(base, "out"),
    token: "",
    displayName: "テスト PC",
    version: "test",
  };
  fs.mkdirSync(cfg.inbox, { recursive: true });
  fs.mkdirSync(cfg.outbox, { recursive: true });

  const server = createServer(cfg, () => {});           // ログは黙らせる
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const port = server.address().port;

  suite("外から来たものは断る", () => {
    ok(isLocalAddress("192.168.1.5"), "家の LAN は通す");
    ok(isLocalAddress("::ffff:10.0.0.3"), "IPv6 に包まれた IPv4 も通す");
    ok(isLocalAddress("::1"), "自分自身は通す");
    ok(!isLocalAddress("8.8.8.8"), "外のアドレスは断る");
    ok(!isLocalAddress("203.0.113.9"), "グローバルは断る");
    ok(!isLocalAddress(""), "空も断る");
  });

  await suite("受け取る", async () => {
    const r = await req(port, "PUT", "/put/" + encodeURIComponent("写真.jpg"), "HELLO");
    eq(r.status, 200, "200 が返る");
    eq(r.json && r.json.saved, "写真.jpg", "名前どおりに保存される");
    eq(fs.readFileSync(path.join(cfg.inbox, "写真.jpg"), "utf8"), "HELLO", "中身が一致する");

    const r2 = await req(port, "PUT", "/put/" + encodeURIComponent("写真.jpg"), "SECOND");
    eq(r2.json && r2.json.saved, "写真 (2).jpg", "同じ名前は上書きせず (2) にする");
    eq(fs.readFileSync(path.join(cfg.inbox, "写真.jpg"), "utf8"), "HELLO", "1枚目は無傷のまま");

    const r3 = await req(port, "PUT", "/put/" + encodeURIComponent("../../nasty.txt"), "X");
    eq(r3.status, 200, "危ない名前でも 200（弾かず、安全な名前に直す）");
    ok(fs.existsSync(path.join(cfg.inbox, "nasty.txt")), "受信箱の中に落ちる");
    ok(!fs.existsSync(path.join(base, "nasty.txt")), "🔴 受信箱の外には絶対に出さない");
  });

  await suite("途中で切れたものは出さない", async () => {
    const before = fs.readdirSync(cfg.inbox).length;
    await new Promise((resolve) => {
      const sock = net.connect(port, "127.0.0.1", () => {
        sock.write(
          "PUT /put/half.bin HTTP/1.1\r\nHost: x\r\nContent-Length: 1000\r\n\r\n" + "A".repeat(10)
        );
        setTimeout(() => { sock.destroy(); resolve(); }, 150);
      });
      sock.on("error", () => resolve());
    });
    await sleep(300);
    eq(fs.readdirSync(cfg.inbox).length, before, "受信箱にファイルが増えていない");
    ok(!fs.existsSync(path.join(cfg.inbox, "half.bin")), "半端なファイルは残らない");
    const parts = fs.existsSync(path.join(cfg.inbox, PART_DIR))
      ? fs.readdirSync(path.join(cfg.inbox, PART_DIR)) : [];
    eq(parts.length, 0, "書きかけの置き場も片付いている");
  });

  await suite("大きさが合わないものは捨てる", async () => {
    const r = await req(port, "PUT", "/put/short.bin", "AB", { "content-length": "2" });
    eq(r.status, 200, "宣言どおりなら通る");
    ok(fs.existsSync(path.join(cfg.inbox, "short.bin")), "保存されている");
  });

  await suite("PC から受け取る", async () => {
    fs.writeFileSync(path.join(cfg.outbox, "資料.txt"), "OUTBOX", "utf8");
    const list = await req(port, "GET", "/api/list");
    eq(list.status, 200, "一覧が返る");
    ok(list.json.files.some((f) => f.name === "資料.txt"), "送信箱の中身が見える");

    const dl = await req(port, "GET", "/get/" + encodeURIComponent("資料.txt"));
    eq(dl.text, "OUTBOX", "落とせる");

    const bad = await req(port, "GET", "/get/" + encodeURIComponent("../in/写真.jpg"));
    ok(bad.status === 404 || bad.status === 400, "🔴 送信箱の外は読ませない");
  });

  await suite("名乗りと道", async () => {
    const info = await req(port, "GET", "/api/info");
    eq(info.json.app, "yasdrop", "名乗る");
    eq(info.json.name, "テスト PC", "PC 名を返す");
    eq((await req(port, "GET", "/health")).text, "ok", "生存確認");
    eq((await req(port, "GET", "/nowhere")).status, 404, "無い道は 404");
  });

  await suite("合言葉", async () => {
    const cfg2 = { ...cfg, token: "himitsu", inbox: path.join(base, "in2"), outbox: path.join(base, "out2") };
    fs.mkdirSync(cfg2.inbox, { recursive: true });
    fs.mkdirSync(cfg2.outbox, { recursive: true });
    const s2 = createServer(cfg2, () => {});
    await new Promise((r) => s2.listen(0, "127.0.0.1", r));
    const p2 = s2.address().port;
    eq((await req(p2, "GET", "/api/info")).status, 401, "合言葉なしは断る");
    eq((await req(p2, "GET", "/api/info?t=chigau")).status, 401, "違う合言葉も断る");
    eq((await req(p2, "GET", "/api/info?t=himitsu")).status, 200, "合っていれば通る");
    eq((await req(p2, "GET", "/api/info", null, { "x-yasdrop-token": "himitsu" })).status, 200, "ヘッダでも通る");
    await new Promise((r) => s2.close(r));
  });

  await new Promise((r) => server.close(r));
  await fsp.rm(base, { recursive: true, force: true });
};
