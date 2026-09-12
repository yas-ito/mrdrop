"use strict";
// 受信サーバー本体。
// 🔴 大きい動画（数GB）が来る前提。本文は必ずディスクへ流す。メモリに溜めない。

const http = require("http");
const fs = require("fs");
const fsp = require("fs/promises");
const path = require("path");
const crypto = require("crypto");
const { pipeline } = require("stream/promises");
const { execFile } = require("child_process");
const { safeName, uniqueName, humanSize } = require("./names");
const { page } = require("./ui");

// 書きかけの置き場。保存先と同じドライブに置くので、出来上がりを**移動ではなくリンク**で
// 済ませられる（数GBの動画を二度書きしない）。
//
// 🔴 先頭のドットは Windows では何も隠さない。Mac では見えないので気づけないが、
//    Windows の人の「ダウンロード」に空のフォルダが1つ増えて見える（本人が発見 2026-09-12）。
//    「専用のフォルダを勝手に作らない」と決めた以上、ここも残してはいけない。
//    ・作るときに隠し属性を付ける（Windows）
//    ・空になったら消す。ふだんは存在しない
const PART_DIR = ".mrdrop-part";

// LAN の外からは相手にしない。ルータの穴あけ事故で世界に晒される事態を防ぐ。
function isLocalAddress(ip) {
  if (!ip) return false;
  let s = String(ip);
  if (s.startsWith("::ffff:")) s = s.slice(7);
  if (s === "::1") return true;
  if (/^127\./.test(s)) return true;
  if (/^10\./.test(s)) return true;
  if (/^192\.168\./.test(s)) return true;
  if (/^172\.(1[6-9]|2\d|3[01])\./.test(s)) return true;
  if (/^169\.254\./.test(s)) return true;          // link-local
  const l = s.toLowerCase();
  if (l.startsWith("fe80:")) return true;
  if (/^f[cd]/.test(l)) return true;               // ULA
  return false;
}

const json = (res, code, obj) => {
  const b = Buffer.from(JSON.stringify(obj), "utf8");
  res.writeHead(code, { "content-type": "application/json; charset=utf-8", "content-length": b.length });
  res.end(b);
};
const text = (res, code, s) => {
  const b = Buffer.from(s, "utf8");
  res.writeHead(code, { "content-type": "text/plain; charset=utf-8", "content-length": b.length });
  res.end(b);
};

// 書きかけを本名に変える。
// 🔴 rename は Windows では既存を黙って上書きする。link なら相手がいると EEXIST で
//    失敗してくれるので、これを衝突検出そのものに使う（同時に2枚届いても潰れない）。
// 作業用フォルダを用意する。**新しく作ったときだけ** Windows の隠し属性を付ける。
// 🔴 attrib は出来なくても構わない（見た目の問題で、動きには関わらない）。待たない。
async function ensurePartDir(partDir) {
  let made = false;
  try {
    await fsp.mkdir(partDir);
    made = true;
  } catch (e) {
    if (e.code !== "EEXIST") throw e;
  }
  if (made && process.platform === "win32") {
    try { execFile("attrib", ["+h", partDir], () => {}); } catch { /* 見た目だけの話 */ }
  }
}

// 空なら消す。転送が終わるたびに呼ぶので、ふだんは存在しない状態になる。
// 🔴 同時に別の転送が走っていれば中身があり、rmdir は ENOTEMPTY で失敗する。それでいい。
async function tidyPartDir(partDir) {
  try { await fsp.rmdir(partDir); } catch { /* まだ使っている・もう無い */ }
}

async function commit(tmp, dir, wanted) {
  let candidate = uniqueName(wanted, (n) => fs.existsSync(path.join(dir, n)));
  const ext = path.extname(wanted);
  const base = ext ? wanted.slice(0, -ext.length) : wanted;
  for (let i = 2; i < 1000; i++) {
    try {
      await fsp.link(tmp, path.join(dir, candidate));
      await fsp.rm(tmp, { force: true });
      return candidate;
    } catch (e) {
      if (e.code === "EEXIST") { candidate = `${base} (${i})${ext}`; continue; }
      if (e.code === "EXDEV" || e.code === "EPERM" || e.code === "ENOSYS") {
        // ハードリンクが使えない置き場（ネットワークドライブ等）。ここだけは rename に落とす。
        await fsp.rename(tmp, path.join(dir, candidate));
        return candidate;
      }
      throw e;
    }
  }
  throw new Error("同じ名前が多すぎる");
}

async function listDir(dir) {
  let names;
  try { names = await fsp.readdir(dir); } catch { return []; }
  const out = [];
  for (const n of names) {
    if (n === PART_DIR || n.startsWith(".")) continue;
    try {
      const st = await fsp.stat(path.join(dir, n));
      if (st.isFile()) out.push({ name: n, size: st.size, human: humanSize(st.size), mtime: st.mtimeMs });
    } catch { /* 読んでいる間に消えた */ }
  }
  out.sort((a, b) => b.mtime - a.mtime);
  return out;
}

function createServer(cfg, log = console.log) {
  const inbox = cfg.inbox;
  const outbox = cfg.outbox;
  const partDir = path.join(inbox, PART_DIR);

  const authOk = (req, url) => {
    if (!cfg.token) return true;
    const given = req.headers["x-mrdrop-token"] || url.searchParams.get("t") || "";
    // 長さの違いで漏れないように、固定長のハッシュ同士で比べる
    const h = (s) => crypto.createHash("sha256").update(String(s)).digest();
    return crypto.timingSafeEqual(h(given), h(cfg.token));
  };

  const server = http.createServer(async (req, res) => {
    const remote = req.socket.remoteAddress;
    let url;
    try { url = new URL(req.url, "http://localhost"); } catch { return text(res, 400, "URL が読めません"); }

    if (!isLocalAddress(remote)) {
      log(`🚫 LAN の外から来たので断りました: ${remote}`);
      return text(res, 403, "この道具は同じネットワークの中からだけ使えます。");
    }
    if (!authOk(req, url)) return text(res, 401, "合言葉が違います。");

    try {
      // ── 画面 ──
      if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/index.html")) {
        const b = Buffer.from(page(cfg), "utf8");
        res.writeHead(200, { "content-type": "text/html; charset=utf-8", "content-length": b.length, "cache-control": "no-store" });
        return res.end(b);
      }

      // ── この PC の名乗り（iPhone アプリが最初に叩く） ──
      if (req.method === "GET" && url.pathname === "/api/info") {
        return json(res, 200, { app: "mrdrop", version: cfg.version, name: cfg.displayName, needsToken: !!cfg.token });
      }

      // ── 送信箱の一覧（PC → iPhone） ──
      if (req.method === "GET" && url.pathname === "/api/list") {
        return json(res, 200, { files: await listDir(outbox) });
      }

      // ── 送信箱から1つ落とす ──
      if (req.method === "GET" && url.pathname.startsWith("/get/")) {
        const name = safeName(decodeURIComponent(url.pathname.slice(5)));
        const full = path.join(outbox, name);
        if (path.dirname(path.resolve(full)) !== path.resolve(outbox)) return text(res, 400, "その名前は扱えません");
        let st;
        try { st = await fsp.stat(full); } catch { return text(res, 404, "ありません"); }
        if (!st.isFile()) return text(res, 404, "ありません");
        res.writeHead(200, {
          "content-type": "application/octet-stream",
          "content-length": st.size,
          "content-disposition": `attachment; filename*=UTF-8''${encodeURIComponent(name)}`,
        });
        return pipeline(fs.createReadStream(full), res).catch(() => {});
      }

      // ── 受け取る（iPhone → PC） ──
      if (req.method === "PUT" && url.pathname.startsWith("/put/")) {
        const wanted = safeName(decodeURIComponent(url.pathname.slice(5)));
        await ensurePartDir(partDir);
        const tmp = path.join(partDir, crypto.randomBytes(8).toString("hex") + ".part");
        const started = Date.now();
        try {
          await pipeline(req, fs.createWriteStream(tmp));
        } catch (e) {
          // 🔴 途中で切れたものは絶対に保存先へ出さない。半端なファイルは事故のもと。
          await fsp.rm(tmp, { force: true });
          await tidyPartDir(partDir);
          log(`⚠️ 途中で切れました: ${wanted}（${e.code || e.message}）`);
          return text(res, 400, "途中で切れました");
        }
        const st = await fsp.stat(tmp);
        const declared = req.headers["content-length"] ? Number(req.headers["content-length"]) : null;
        if (declared !== null && Number.isFinite(declared) && st.size !== declared) {
          await fsp.rm(tmp, { force: true });
          await tidyPartDir(partDir);
          log(`⚠️ 大きさが合いません: ${wanted}（${st.size} / ${declared}）`);
          return text(res, 400, "大きさが合いません");
        }
        const saved = await commit(tmp, inbox, wanted);
        await tidyPartDir(partDir);
        const mod = Number(req.headers["x-mrdrop-modified"]);
        if (Number.isFinite(mod) && mod > 0) {
          try { await fsp.utimes(path.join(inbox, saved), new Date(mod), new Date(mod)); } catch { /* 出来なくても構わない */ }
        }
        const secs = (Date.now() - started) / 1000;
        const speed = secs > 0.2 ? `・${humanSize(st.size / secs)}/秒` : "";
        log(`📥 ${saved}  ${humanSize(st.size)}${speed}  ← ${String(remote).replace("::ffff:", "")}`);
        return json(res, 200, { ok: true, saved, size: st.size });
      }

      if (req.method === "GET" && url.pathname === "/health") return text(res, 200, "ok");
      return text(res, 404, "そんな道はありません");
    } catch (e) {
      log(`🔴 ${req.method} ${url.pathname}: ${e && e.stack ? e.stack : e}`);
      if (!res.headersSent) return text(res, 500, "こちらで失敗しました");
      try { res.end(); } catch { /* 済み */ }
    }
  });

  // 大きい動画を Wi-Fi 越しに受ける。既定の2分では足りない。
  server.requestTimeout = 0;
  server.headersTimeout = 60_000;
  server.timeout = 0;
  server.keepAliveTimeout = 30_000;
  return server;
}

module.exports = { createServer, isLocalAddress, commit, listDir, PART_DIR };
