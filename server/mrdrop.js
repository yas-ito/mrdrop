#!/usr/bin/env node
"use strict";
// Mr.Drop 受信サーバー — iPhone から同じ Wi-Fi のこの PC へ送るための常駐。
//
//   node server/mrdrop.js              ふつうに起動する
//   node server/mrdrop.js --port 9000  番号を変えて起動する
//   node server/mrdrop.js --browse     いま LAN で見えている Mr.Drop を探す（動作確認用）
//
// 🔴 npm install は要らない。外部パッケージを1つも使っていない。

const fs = require("fs");
const path = require("path");
const os = require("os");
const { load } = require("./lib/config");
const { createServer } = require("./lib/http");
const { Responder, browse, localIPv4s } = require("./lib/mdns");

const VERSION = "1.0.0";
const ROOT = path.join(__dirname, "..");
const LOG_DIR = path.join(process.env.LOCALAPPDATA || os.tmpdir(), "MrDrop");
const LOG_FILE = path.join(LOG_DIR, "mrdrop.log");
const LOG_MAX = 2 * 1024 * 1024;

// 画面にも出しつつ、必ずファイルにも残す。
//
// 🔴 「画面が無いときだけファイルに書く」は作ってはいけない。
//    タスクスケジューラから起動された node には**見えないコンソールが割り当てられる**ので、
//    process.stdout.isTTY が true になり、誰も読めない画面に出して終わる（実際に踏んだ）。
//    判定などせず、常に両方へ書くのが正しい。
//
// 🔴 createWriteStream ではなく appendFileSync。セッション0から起動したとき、
//    ストリームの中身が落ちきらないことがあった。行数はたかが知れている。
function makeLogger() {
  let fileOk = true;
  try {
    fs.mkdirSync(LOG_DIR, { recursive: true });
    try {
      if (fs.statSync(LOG_FILE).size > LOG_MAX) fs.renameSync(LOG_FILE, LOG_FILE + ".1");
    } catch { /* まだ無い */ }
  } catch {
    fileOk = false;       // ログを残せなくても、本体は動かす
  }
  return (...a) => {
    const line = a.join(" ");
    console.log(line);
    if (!fileOk) return;
    try {
      // toISOString は UTC。あとで読むのは人なので、地元の時刻で書く。
      const d = new Date();
      const p = (n) => String(n).padStart(2, "0");
      const t = `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ` +
                `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
      fs.appendFileSync(LOG_FILE, t + "  " + line + "\r\n", "utf8");
    } catch { /* 書けなくても止めない */ }
  };
}

function parseArgs(argv) {
  const a = { port: null, browse: false, config: path.join(ROOT, "config.json") };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--port") a.port = Number(argv[++i]);
    else if (argv[i] === "--config") a.config = argv[++i];
    else if (argv[i] === "--browse") a.browse = true;
  }
  return a;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.browse) {
    console.log("LAN を 3 秒ほど探します…");
    const found = await browse(3000);
    if (!found.length) console.log("見つかりませんでした。サーバーが動いているか、ファイアウォールを確かめてください。");
    for (const f of found) {
      console.log(`  ${f.name}`);
      console.log(`    ${f.address || f.host}:${f.port}   ${JSON.stringify(f.txt)}`);
    }
    return;
  }

  const log = makeLogger();
  const cfg = load(args.config);
  if (args.port) cfg.port = args.port;
  cfg.version = VERSION;

  fs.mkdirSync(cfg.inbox, { recursive: true });
  fs.mkdirSync(cfg.outbox, { recursive: true });

  const server = createServer(cfg, log);
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(cfg.port, "0.0.0.0", resolve);
  }).catch((e) => {
    if (e.code === "EADDRINUSE") {
      log(`🔴 ${cfg.port} 番はすでに使われています。config.json の port を変えるか、先に動いている Mr.Drop を終わらせてください。`);
    } else {
      log("🔴 起動できませんでした: " + e.message);
    }
    process.exit(1);
  });

  const hostLabel = os.hostname().replace(/\./g, "-");
  const mdns = new Responder({
    instance: cfg.displayName,
    hostname: hostLabel,
    port: cfg.port,
    txt: { v: VERSION, name: cfg.displayName, path: "/" },
  });
  mdns.on("warn", (m) => log("⚠️ " + m));
  const mdnsOk = await mdns.start();

  const line = "─".repeat(52);
  log("");
  log(`  Mr.Drop ${VERSION}   ${cfg.displayName}`);
  log(line);
  log(`  受信箱  ${cfg.inbox}`);
  log(`  送信箱  ${cfg.outbox}`);
  log(line);
  log("  iPhone の Safari から、このどれかを開いてください:");
  log(`    http://${hostLabel}.local:${cfg.port}`);
  for (const a of localIPv4s()) log(`    http://${a.address}:${cfg.port}      （${a.iface}）`);
  log(line);
  log(mdnsOk
    ? "  自動発見  _mrdrop._tcp で広告中（iPhone アプリは設定なしで見つけます）"
    : "  自動発見  使えません（ブラウザからは使えます）");
  if (cfg.token) log("  合言葉    設定されています（URL に ?t=… が要ります）");
  log(`  記録  ${LOG_FILE}`);
  log("");
  // 🔴 log() ではなく console.log。isTTY はタスク起動時に嘘をつく（見えないコンソールが
  //    割り当てられる）ので、これを log() で書くと記録に「Ctrl+C」が紛れ込む。
  console.log("  終わるには Ctrl+C\n");

  let closing = false;
  const bye = async () => {
    if (closing) return;
    closing = true;
    log("終わります…");
    await mdns.stop();
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 1500).unref();   // 転送中の接続に引きずられない
  };
  process.on("SIGINT", bye);
  process.on("SIGTERM", bye);
}

main().catch((e) => { console.error("🔴", e && e.stack ? e.stack : e); process.exit(1); });
