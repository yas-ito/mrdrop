#!/usr/bin/env node
"use strict";
// YasDrop 受信サーバー — iPhone から同じ Wi-Fi のこの PC へ送るための常駐。
//
//   node server/yasdrop.js              ふつうに起動する
//   node server/yasdrop.js --port 9000  番号を変えて起動する
//   node server/yasdrop.js --browse     いま LAN で見えている YasDrop を探す（動作確認用）
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

  const cfg = load(args.config);
  if (args.port) cfg.port = args.port;
  cfg.version = VERSION;

  fs.mkdirSync(cfg.inbox, { recursive: true });
  fs.mkdirSync(cfg.outbox, { recursive: true });

  const server = createServer(cfg);
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(cfg.port, "0.0.0.0", resolve);
  }).catch((e) => {
    if (e.code === "EADDRINUSE") {
      console.error(`🔴 ${cfg.port} 番はすでに使われています。config.json の port を変えるか、先に動いている YasDrop を終わらせてください。`);
    } else {
      console.error("🔴 起動できませんでした:", e.message);
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
  mdns.on("warn", (m) => console.log("⚠️ " + m));
  const mdnsOk = await mdns.start();

  const line = "─".repeat(52);
  console.log("");
  console.log(`  YasDrop ${VERSION}   ${cfg.displayName}`);
  console.log(line);
  console.log(`  受信箱  ${cfg.inbox}`);
  console.log(`  送信箱  ${cfg.outbox}`);
  console.log(line);
  console.log("  iPhone の Safari から、このどれかを開いてください:");
  console.log(`    http://${hostLabel}.local:${cfg.port}`);
  for (const a of localIPv4s()) console.log(`    http://${a.address}:${cfg.port}      （${a.iface}）`);
  console.log(line);
  console.log(mdnsOk
    ? "  自動発見  _yasdrop._tcp で広告中（iPhone アプリは設定なしで見つけます）"
    : "  自動発見  使えません（ブラウザからは使えます）");
  if (cfg.token) console.log("  合言葉    設定されています（URL に ?t=… が要ります）");
  console.log("  終わるには Ctrl+C");
  console.log("");

  let closing = false;
  const bye = async () => {
    if (closing) return;
    closing = true;
    console.log("\n終わります…");
    await mdns.stop();
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 1500).unref();   // 転送中の接続に引きずられない
  };
  process.on("SIGINT", bye);
  process.on("SIGTERM", bye);
}

main().catch((e) => { console.error("🔴", e && e.stack ? e.stack : e); process.exit(1); });
