"use strict";
// 配る物そのものの検査。**中身ではなく、入口が本当につながっているか**を見る。
//
// 🔴 ここが要る理由（2026-09-12 に何度も踏んだ）。
//    .bat と .ps1 と、このテスト自身を、スクリプト（Node の文字列）で書き換えると、
//    `\s` `\r` `\R` のような並びが**エスケープとして食われて、区切りの \ が消える**。
//
//      アンインストール.bat : "scripts\settings-windows.ps1" → "scriptssettings-windows.ps1"
//      settings-windows.ps1 : "scripts\run-once.bat"         → "scripts" + CR + "un-once.bat"
//
//    どちらも**目で読むと正しく見える**（\ が1つ消えているだけ）。本人が実機で押して
//    「エラー」と言うまで気づけなかった。人の目では止まらないので、機械で見張る。
//
// 🔴 このファイルの中でも、判定に使う \ は必ず BS 変数から組み立てること。
//    直接書くと、次に誰かがスクリプトで触ったときに同じ形で消える。
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "..");
const BS = String.fromCharCode(92);
// PowerShell の変数記号。ここに直接書くと、このファイル自身が下の検査に引っかかる。
const SIGIL = String.fromCharCode(36);

// 配る .bat（build/make-package.js の BATS と同じ顔ぶれ）
const BATS = ["はじめる.bat", "アンインストール.bat", "保存先を変える.bat", "保存先を開く.bat", "scripts/run-once.bat"];

// 同梱ビルド（--with-node）のときだけ現れるもの。ソースの木には無くてよい。
const ONLY_IN_PACKAGE = ["node/node.exe"];

module.exports = async function (t) {
  const { suite, eq, ok } = t;

  const installer = path.join(ROOT, "scripts", "install-windows.ps1");
  const installerSrc = fs.existsSync(installer) ? fs.readFileSync(installer, "utf8") : "";

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
        ok(fs.existsSync(path.join(ROOT, asPosix)), `🔴 ${b} が指す ${r} が実在する`);
      }
    }
  });

  // 🔴 区切りが消えた形を名指しで拒む。上の実在チェックで大半は捕まるが、
  //    案内文の中（実行されない文字列）に出た場合はここでしか捕まらない。
  //    実際 settings-windows.ps1 の案内文がそうだった。
  suite("配る物 — 区切りの消えた道が文面に無い", () => {
    const files = [...BATS, "scripts/install-windows.ps1", "scripts/settings-windows.ps1",
                   "build/build-tray.ps1", "tray/MrDropTray.cs", "取扱説明書.html"];
    const bad = ["scriptssettings-windows.ps1", "scriptsinstall-windows.ps1",
                 "scriptsrun-once.bat", "servermrdrop.js", "nodenode.exe", "appMrDropTray.exe"];
    for (const f of files) {
      const abs = path.join(ROOT, f);
      if (!fs.existsSync(abs)) continue;
      const src = fs.readFileSync(abs, "utf8");
      for (const b of bad) ok(!src.includes(b), `${f} に「${b}」が無い`);
      // 生の CR（CRLF の片割れではないもの）が本文に紛れていないか
      ok(!src.split("\r\n").join("\n").includes("\r"),
         `🔴 ${f} に裸の CR が紛れていない（食われた跡）`);
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
    for (const p of ["scripts/install-windows.ps1", "scripts/settings-windows.ps1", "build/build-tray.ps1"]) {
      const abs = path.join(ROOT, p);
      if (!fs.existsSync(abs)) continue;
      const buf = fs.readFileSync(abs);
      ok(buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf,
         `🔴 ${p} は BOM 付き UTF-8（無いと PowerShell 5.1 が CP932 で読む）`);
    }
  });

  suite("配る物 — 入れたあとの入口がそろっている", () => {
    if (!installerSrc) { ok(true, "install-windows.ps1 が無い"); return; }
    // ふだんの入口はタスクバーの常駐アイコン。スタートメニューは「閉じた人が戻る道」。
    for (const name of ["Mr.Drop", "取扱説明書", "Mr.Drop をアンインストール"]) {
      ok(installerSrc.includes(name + ".lnk"), `スタートメニューに「${name}」を作る`);
    }
    // 🔴 「やめる」は「一旦止める」とも読めて迷う（本人が実際に迷った 2026-09-12）。
    ok(!installerSrc.includes("をやめる.lnk"), "🔴 古い「Mr.Drop をやめる」という名前は残っていない");
    eq(fs.existsSync(path.join(ROOT, "やめる.bat")), false, "🔴 古い やめる.bat は残っていない");
  });

  // 🔴 常駐はタスクスケジューラ（S4U）をやめて、タスクバーのアイコンが本体を抱える形にした
  //    （本人決定 2026-09-12）。S4U は「動いているかがどこにも見えない」のが致命的だった。
  suite("配る物 — 常駐はタスクバーのアイコンが受け持つ", () => {
    const exe = path.join(ROOT, "tray", "MrDropTray.exe");
    ok(fs.existsSync(exe), "🔴 MrDropTray.exe が作ってある（build/build-tray.ps1）");
    if (fs.existsSync(exe)) ok(fs.statSync(exe).size > 10000, "中身がある");

    const cs = path.join(ROOT, "tray", "MrDropTray.cs");
    if (fs.existsSync(cs)) {
      const src = fs.readFileSync(cs, "utf8");
      ok(src.includes("--follow-stdin"), "🔴 本体を --follow-stdin で抱える（閉じたら本体も終わる）");
      ok(src.includes("RedirectStandardInput"), "標準入力を握っている");
      ok(src.includes("CreateNoWindow"), "🔴 黒い画面を出さない");
      // 🔴 既定値を書き写さない。config.js とずれたときに黙って食い違う
      ok(!src.includes("48630"), "🔴 番号の既定をここに書き写していない");
      ok(!src.includes("Downloads"), "🔴 保存先の既定をここに書き写していない");
      // 設定を触る操作は .ps1 に任せる（実装を2つ持たない）
      ok(src.includes("settings-windows.ps1"), "設定は scripts/settings-windows.ps1 に任せる");
    }

    const buildPs1 = path.join(ROOT, "build", "build-tray.ps1");
    if (fs.existsSync(buildPs1)) {
      const src = fs.readFileSync(buildPs1, "utf8");
      ok(src.includes("/target:winexe"), "🔴 winexe でビルドする（console だと黒い画面が出る）");
      ok(src.includes("csc.exe"), "Windows 標準の C# コンパイラだけで作る（SDK 不要）");
    }

    if (installerSrc) {
      const runKey = "CurrentVersion" + BS + "Run";
      ok(installerSrc.includes(runKey), "自動起動はレジストリの Run（管理者が要らない）");
      ok(installerSrc.includes("Unregister-ScheduledTask"),
         "🔴 昔の S4U タスクを片付ける（残すと二重起動で両方死ぬ）");
      ok(!installerSrc.includes("Register-ScheduledTask -TaskName"), "🔴 もうタスクは作らない");
      ok(installerSrc.includes("MrDropTray.exe"), "常駐アイコンを写して動かす");
    }
  });

  // 🔴 iPhone の一覧で取り違える事故（Mac が実機で踏んだ 2026-09-12）。
  //    `yas`（Windows）と `yasnoMac-mini-local`（Mac）が並び、yas を選んで送って
  //    「Mac に届かない＝消えた」と思った。動きは正常で、分からないのは名前の方だった。
  //    既定の加工では区別が付かない（ホスト名が短いのは偶然）。自分で付けられる口を作る。
  suite("配る物 — この PC の名前を変えられる", () => {
    const ps1 = path.join(ROOT, "scripts", "settings-windows.ps1");
    if (fs.existsSync(ps1)) {
      const src = fs.readFileSync(ps1, "utf8");
      ok(src.includes("-ChooseName") || src.includes(SIGIL + "ChooseName"), "🔴 -ChooseName がある");
      ok(src.includes(SIGIL + "cfg.name"), "config.json の name に書く");
    }
    const cs = path.join(ROOT, "tray", "MrDropTray.cs");
    if (fs.existsSync(cs)) {
      const src = fs.readFileSync(cs, "utf8");
      ok(src.includes("この PC の名前を変える"), "🔴 タスクバーのメニューに項目がある");
      ok(src.includes("-ChooseName"), "中身は .ps1 に任せる（設定の書き方を2か所に持たない）");
    }
  });

  // 🔴 PowerShell の自動変数を自分の変数名に使わない（`host` はホストオブジェクト、
  //    `args` は引数配列）。上書きは効かず、黙って別の物を読む。実際に書いてしまった。
  suite("配る物 — PowerShell の自動変数を奪っていない", () => {
    const files = ["scripts/install-windows.ps1", "scripts/settings-windows.ps1",
                   "build/build-tray.ps1", "build/make-tray-icon.ps1"];
    const reserved = ["host", "args", "input", "error", "true", "false", "null", "pwd", "pid", "home"];
    for (const f of files) {
      const abs = path.join(ROOT, f);
      if (!fs.existsSync(abs)) continue;
      const lines = fs.readFileSync(abs, "utf8").split("\n");
      for (const name of reserved) {
        const bad = lines.some((line) => {
          const t = line.trim();
          if (t.startsWith("#")) return false;                      // 注釈は見ない
          return new RegExp(BS + SIGIL + name + BS + "s*=[^=]").test(t);
        });
        ok(!bad, `${f} で ${SIGIL}${name} を自分の変数に使っていない`);
      }
    }
  });

  // 🔴 同じ値が2か所にあると必ずずれる（今日それで公開事故を起こした）。
  suite("配る物 — 作り直したら出品用も揃う", () => {
    const mk = path.join(ROOT, "build", "make-package.js");
    if (!fs.existsSync(mk)) { ok(true, "make-package.js が無い"); return; }
    const src = fs.readFileSync(mk, "utf8");
    ok(src.includes("出品"), "🔴 _build/出品/ も自動で揃える");
    ok(src.includes("MrDropTray.exe"), "常駐アイコンを ZIP に入れる");
  });
};
