"use strict";
// Mac 版アプリの子プロセスとして回すときの約束: --follow-stdin なら stdin が閉じたら自分から終わる。
// 🔴 親（アプリ）が強制終了されても、受信サーバーだけが番号を握って残らない、をここで固定する。
//    本物の入口（server/mrdrop.js）を別プロセスで立てて確かめる（parseArgs だけ試しても意味がない）。
const fs = require("fs");
const fsp = require("fs/promises");
const os = require("os");
const path = require("path");
const net = require("net");
const { spawn } = require("child_process");

function freePort() {
  return new Promise((r) => {
    const s = net.createServer();
    s.listen(0, "127.0.0.1", () => { const p = s.address().port; s.close(() => r(p)); });
  });
}

module.exports = async function (t) {
  const { suite, ok } = t;

  await suite("--follow-stdin（親が消えたら自分で終わる）", async () => {
    const base = await fsp.mkdtemp(path.join(os.tmpdir(), "mrdrop-follow-"));
    const cfgFile = path.join(base, "config.json");
    fs.writeFileSync(cfgFile, JSON.stringify({
      inbox: path.join(base, "in"), outbox: path.join(base, "out"), token: "", name: "follow-test",
    }));
    const port = await freePort();
    const child = spawn(process.execPath,
      [path.join(__dirname, "..", "mrdrop.js"), "--config", cfgFile, "--port", String(port), "--follow-stdin"],
      { stdio: ["pipe", "pipe", "pipe"] });
    let out = "";
    child.stdout.on("data", (d) => { out += d; });
    child.stderr.on("data", (d) => { out += d; });

    const started = await new Promise((r) => {
      const timer = setTimeout(() => r(false), 8000);
      child.stdout.on("data", () => { if (out.includes("Ctrl+C")) { clearTimeout(timer); r(true); } });
    });
    ok(started, "立ち上がる" + (started ? "" : "　（出力: " + out.slice(-200) + "）"));
    ok(child.exitCode === null, "stdin を握っている間は生きている");

    child.stdin.end();                       // 親が消えたのと同じ（パイプが閉じる）
    const code = await new Promise((r) => {
      const timer = setTimeout(() => r(null), 4000);
      child.on("exit", (c, sig) => { clearTimeout(timer); r(c === null ? "signal:" + sig : c); });
    });
    ok(code !== null, "stdin が閉じたら 4 秒以内に終わる" + (code === null ? "（終わらなかった）" : ""));
    if (code === null) child.kill("SIGKILL");
    ok(out.includes("終わります"), "ふつうの終わり方（mDNS の別れを打ってから）で終わる");
    await fsp.rm(base, { recursive: true, force: true });
  });
};
