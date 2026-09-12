"use strict";
const fs = require("fs");
const path = require("path");
const os = require("os");

// 🔴 既定（本人決定 2026-09-12）。**両OSで同じ場所にする。**
//    ・保存先 … ダウンロードフォルダ**そのもの**。専用のフォルダを勝手に作らない。
//      届いたものは、いつも使う場所へ直接落とす
//      🔴 Mac の ~/Desktop は iCloud 同期の対象なので、保存先には使えない
//        （数GBの動画が勝手に上がる）
//    ・送信箱 … **デスクトップの中の専用フォルダ**。iPhone へ渡す物を置く場所なので、
//      目に見えてすぐ放り込めるデスクトップに置く（本人指示）。
//      🔵 iCloud 同期の心配は薄い。ここに置くのは「いま渡したい物」だけで、
//        大きい動画を置きっぱなしにする場所ではないため
//    ~ は下の expand() が os.homedir() に開く。
const WIN = process.platform === "win32";
const DL = WIN ? "%USERPROFILE%\\Downloads" : "~/Downloads";
const DESK = WIN ? "%USERPROFILE%\\Desktop" : "~/Desktop";
const SEP = WIN ? "\\" : "/";

// 初回に config.json を作る。中身を書き換えれば置き場所も番号も変えられる。
const DEFAULTS = {
  port: 48630,                                   // 一撃極ターボ（48620）とぶつからない番号
  inbox: DL,                                     // 届いたものの保存先。ダウンロードフォルダに直接
  // 🔴 送信箱は**デスクトップの中の専用フォルダ**。デスクトップそのものにはしない。
  //    ここの中身は**同じ Wi-Fi から一覧できる**ので、デスクトップ全体を送信箱にすると
  //    置いてある物が全部見えてしまう。
  outbox: `${DESK}${SEP}Mr.Drop送信箱`,
  name: "",                                      // 空なら PC 名。iPhone にはこれが見える
  token: "",                                     // 空なら合言葉なし（家の LAN 前提）
};

// %USERPROFILE% は Mac/Linux に無い。Windows で書かれた config.json を持ってきたときに
// 「%USERPROFILE%\Downloads」という名前のフォルダを作らないよう、家に落とす。
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

// 設定の置き場所。
//
// 🔴 Windows は**プログラムの隣に置かない**（本人決定 2026-09-12）。
//    展開したフォルダは「はじめる.bat」のあと %LOCALAPPDATA%\MrDrop\app へ写され、
//    元のフォルダは捨てられる。設定が隣にあると、捨てた瞬間に一緒に消える。
//    記録（mrdrop.log）と同じ %LOCALAPPDATA%\MrDrop に置いて、入れ直しても残るようにする。
//    Mac 版アプリはもともと Application Support の config.json を --config で渡してくる
//    （mac/main.swift）ので、考え方は両OSで揃っている。
function defaultFile(root) {
  if (process.platform === "win32") {
    return path.join(process.env.LOCALAPPDATA || os.homedir(), "MrDrop", "config.json");
  }
  return path.join(root, "config.json");
}

module.exports = { load, expand, defaultFile, DEFAULTS };
