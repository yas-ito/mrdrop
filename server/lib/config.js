"use strict";
const fs = require("fs");
const path = require("path");
const os = require("os");

// 初回に config.json を作る。中身を書き換えれば置き場所も番号も変えられる。
const DEFAULTS = {
  port: 48630,                                   // 一撃極ターボ（48620）とぶつからない番号
  inbox: "%USERPROFILE%\\Desktop\\受信箱",
  outbox: "%USERPROFILE%\\Desktop\\送信箱",
  name: "",                                      // 空なら PC 名。iPhone にはこれが見える
  token: "",                                     // 空なら合言葉なし（家の LAN 前提）
};

function expand(p) {
  return String(p)
    .replace(/%([^%]+)%/g, (m, k) => process.env[k] || m)
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
