"use strict";
const fs = require("fs");
const path = require("path");
const os = require("os");

// 置き場所の既定は OS で変える。Windows は昔から使っている表記のまま。
// 🔴 Mac の ~/Desktop は iCloud 同期の対象なので使わない（数GBの動画が勝手に上がる）。
//    Mac/Linux は ~/Downloads に落とす。~ は下の expand() が os.homedir() に開く。
const WIN = process.platform === "win32";
const DESK = WIN ? "%USERPROFILE%\\Desktop" : "~/Downloads";
const SEP = WIN ? "\\" : "/";

// 初回に config.json を作る。中身を書き換えれば置き場所も番号も変えられる。
const DEFAULTS = {
  port: 48630,                                   // 一撃極ターボ（48620）とぶつからない番号
  inbox: `${DESK}${SEP}受信箱`,
  outbox: `${DESK}${SEP}送信箱`,
  name: "",                                      // 空なら PC 名。iPhone にはこれが見える
  token: "",                                     // 空なら合言葉なし（家の LAN 前提）
};

// %USERPROFILE% は Mac/Linux に無い。Windows で書かれた config.json を持ってきたときに
// 「%USERPROFILE%\Desktop\受信箱」という名前のフォルダを作らないよう、家に落とす。
const HOME_VARS = { USERPROFILE: true, HOME: true, HOMEPATH: true };

// Windows 表記に見えるものだけ区切りを / に読み替える。
// 「%VAR%・~・C: で始まる」に絞るのは、Mac のファイル名に使える \ を壊さないため。
function toNativeSep(p) {
  if (WIN) return p;
  return /^(%[^%]+%|~|[A-Za-z]:)[\\/]/.test(p) ? p.replace(/\\/g, "/") : p;
}

function expand(p) {
  return toNativeSep(String(p))
    .replace(/%([^%]+)%/g, (m, k) =>
      process.env[k] || (HOME_VARS[k.toUpperCase()] ? os.homedir() : m))
    .replace(/^~(?=[\\/]|$)/, os.homedir());
}

function load(file) {
  let raw = {};
  if (fs.existsSync(file)) {
    try {
      raw = JSON.parse(fs.readFileSync(file, "utf8"));
    } catch (e) {
      throw new Error(`${file} が読めません（JSON が壊れています）: ${e.message}`);
    }
  } else {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(DEFAULTS, null, 2) + "\n", "utf8");
  }
  const cfg = { ...DEFAULTS, ...raw };
  cfg.port = Number(cfg.port) || DEFAULTS.port;
  cfg.inbox = path.resolve(expand(cfg.inbox));
  cfg.outbox = path.resolve(expand(cfg.outbox));
  cfg.displayName = String(cfg.name || os.hostname());
  cfg.file = file;
  return cfg;
}

module.exports = { load, expand, DEFAULTS };
