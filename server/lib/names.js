"use strict";
// 受け取った名前を「Windows に安全に置ける1つのファイル名」に変える。
// 🔴 ここが甘いと ../ でどこにでも書けてしまう。だから全部テストで固めてある。
const path = require("path");

const WIN_RESERVED = new Set([
  "CON", "PRN", "AUX", "NUL",
  ...Array.from({ length: 9 }, (_, i) => `COM${i + 1}`),
  ...Array.from({ length: 9 }, (_, i) => `LPT${i + 1}`),
]);

function safeName(raw) {
  let s = raw == null ? "" : String(raw);
  try { s = decodeURIComponent(s); } catch { /* 壊れた % はそのままの文字として扱う */ }

  s = [...s].filter((ch) => { const c = ch.codePointAt(0); return c > 31 && c !== 127; }).join("");  // 制御文字を落とす
  s = s.replace(/\\/g, "/");                      // 区切りを / に揃えてから
  s = s.slice(s.lastIndexOf("/") + 1);            // 🔴 ディレクトリ部分を丸ごと捨てる
  if (s === "." || s === "..") s = "";
  s = s.replace(/[<>:"|?*]/g, "_");               // Windows が受け付けない文字
  s = s.replace(/[. ]+$/, "");                    // 末尾のドットと空白（Windows が黙って消す）
  s = s.trim();
  if (!s) s = "無題";

  const ext = path.extname(s);
  const base = ext ? s.slice(0, -ext.length) : s;
  if (WIN_RESERVED.has(base.toUpperCase())) s = "_" + s;   // CON.txt などは開けなくなる

  if (s.length > 120) {                            // NTFS は255文字。拡張子は残す
    const keep = ext.length > 0 && ext.length <= 20 ? ext : "";
    s = s.slice(0, 120 - keep.length) + keep;
  }
  return s;
}

// 同じ名前がすでにあるときは「写真 (2).jpg」にする。🔴 上書きは絶対にしない。
function uniqueName(name, exists) {
  if (!exists(name)) return name;
  const ext = path.extname(name);
  const base = ext ? name.slice(0, -ext.length) : name;
  for (let i = 2; i < 1000; i++) {
    const c = `${base} (${i})${ext}`;
    if (!exists(c)) return c;
  }
  return `${base} (${Date.now()})${ext}`;
}

// 見た目用。1234567 → 1.2 MB
function humanSize(n) {
  if (!Number.isFinite(n) || n < 0) return "-";
  const u = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
  return (i === 0 ? String(n) : n.toFixed(n < 10 ? 1 : 0)) + " " + u[i];
}

module.exports = { safeName, uniqueName, humanSize };
