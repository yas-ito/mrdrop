"use strict";
// 配る物そのものの検査。**中身ではなく、入口が本当につながっているか**を見る。
//
// 🔴 ここが要る理由（2026-09-12 に3回踏んだ）。
//    .bat と .ps1 の本文は、直すときにスクリプト（Node の文字列）で書き換えている。
//    そのとき `\s` `\r` のような並びが**エスケープとして食われて、区切りの \ が消える**。
//
//      アンインストール.bat : "scripts\settings-windows.ps1" → "scriptssettings-windows.ps1"
//      settings-windows.ps1 : "scripts\run-once.bat"         → "scripts" + CR + "un-once.bat"
//
//    どちらも**目で読むと正しく見える**（\ が1つ消えているだけ）。本人が実機で押して
//    「エラー」と言うまで気づけなかった。人の目では止まらないので、機械で見張る。
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "..");
const BS = String.fromCharCode(92);          // 🔴 この行自体に \ を書かない（同じ事故を防ぐ）

// 配る .bat（build/make-package.js の BATS と同じ顔ぶれ）
const BATS = ["はじめる.bat", "アンインストール.bat", "保存先を変える.bat", "保存先を開く.bat", "scripts/run-once.bat"];

// 同梱ビルド（--with-node）のときだけ現れるもの。ソースの木には無くてよい。
const ONLY_IN_PACKAGE = ["node/node.exe"];

module.exports = async function (t) {
  const { suite, eq, ok } = t;

  suite("配る物 — .bat が指す先が本当にある", () => {
    for (const b of BATS) {
      const abs = path.join(ROOT, b);
      if (!fs.existsSync(abs)) { ok(false, `${b} がありません`); continue; }
      const src = fs.readFileSync(abs, "latin1");

      // %~dp0 に続く、引用符・改行までの中身を全部拾う
      const refs = [...src.matchAll(/%~dp0([^"\r\n]*)/g)].map((m) => m[1]).filter((x) => x.length);
      ok(refs.length > 0, `${b} が何かを指している`);

      for (const r of refs) {
        // %~dp0..\x → 配布物の根から見た x
        const rel = r.startsWith("..") ? r.replace(/^\.\.[\\/]/, "") : path.join(path.dirname(b), r);
        const asPosix = rel.split(BS).join("/");
        if (asPosix === "..") continue;                       // cd /d "%~dp0.." だけの行
        if (ONLY_IN_PACKAGE.includes(asPosix)) continue;      // 同梱のときだけ出る
        ok(fs.existsSync(path.join(ROOT, asPosix)),
           `🔴 ${b} が指す ${r} が実在する`);
      }
    }
  });

  // 🔴 区切りが消えた形を名指しで拒む。上の実在チェックで大半は捕まるが、
  //    案内文の中（実行されない文字列）に出た場合はここでしか捕まらない。
  //    実際 settings-windows.ps1 の案内文がそうだった。
  suite("配る物 — 区切りの消えた道が文面に無い", () => {
    const files = [...BATS, "scripts/install-windows.ps1", "scripts/settings-windows.ps1", "取扱説明書.html"];
    const bad = [
      "scriptssettings-windows.ps1",
      "scriptsinstall-windows.ps1",
      "scriptsrun-once.bat",
      "serverm rdrop.js".replace(" ", ""),   // servermrdrop.js
    ];
    for (const f of files) {
      const abs = path.join(ROOT, f);
      if (!fs.existsSync(abs)) continue;
      const src = fs.readFileSync(abs, "utf8");
      for (const b of bad) {
        ok(!src.includes(b), `${f} に「${b}」が無い`);
      }
      // 生の CR（CRLF の片割れではないもの）が本文に紛れていないか
      const stray = src.split("\r\n").join("\n").includes("\r");
      ok(!stray, `🔴 ${f} に裸の CR が紛れていない（\\r が食われた跡）`);
    }
  });

  suite("配る物 — .bat は ASCII・.ps1 は BOM 付き", () => {
    for (const b of BATS) {
      const abs = path.join(ROOT, b);
      if (!fs.existsSync(abs)) continue;
      const buf = fs.readFileSync(abs);
      ok(!buf.some((c) => c >= 128), `🔴 ${b} は ASCII だけ（cmd は CP932 で読む）`);
      ok(buf.includes(13), `${b} は CRLF`);
    }
    for (const p of ["scripts/install-windows.ps1", "scripts/settings-windows.ps1"]) {
      const abs = path.join(ROOT, p);
      if (!fs.existsSync(abs)) continue;
      const buf = fs.readFileSync(abs);
      ok(buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf,
         `🔴 ${p} は BOM 付き UTF-8（無いと PowerShell 5.1 が CP932 で読む）`);
    }
  });

  suite("配る物 — 入れたあとの入口がそろっている", () => {
    const ps1 = path.join(ROOT, "scripts", "install-windows.ps1");
    if (!fs.existsSync(ps1)) { ok(true, "install-windows.ps1 が無い"); return; }
    const src = fs.readFileSync(ps1, "utf8");
    for (const name of ["保存先を変える", "保存先を開く", "取扱説明書", "Mr.Drop をアンインストール"]) {
      ok(src.includes(name + ".lnk"), `スタートメニューに「${name}」を作る`);
    }
    // 🔴 「やめる」は「一旦止める」とも読めて迷う（本人が実際に迷った 2026-09-12）。
    ok(!src.includes("をやめる.lnk"), "🔴 古い「Mr.Drop をやめる」という名前は残っていない");
    eq(fs.existsSync(path.join(ROOT, "やめる.bat")), false, "🔴 古い やめる.bat は残っていない");
  });
};
