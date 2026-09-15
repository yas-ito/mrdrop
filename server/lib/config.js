"use strict";
const fs = require("fs");
const path = require("path");
const os = require("os");
const { execFileSync } = require("child_process");

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
const SEP = WIN ? "\\" : "/";
const OUTBOX = "Mr.Drop送信箱";              // 送信箱の名前。あちこちに書き散らさない
const FALLBACK_DL = WIN ? "%USERPROFILE%\\Downloads" : "~/Downloads";
const FALLBACK_DESK = WIN ? "%USERPROFILE%\\Desktop" : "~/Desktop";

// 🔴 Windows の「デスクトップ」は %USERPROFILE%\Desktop とは限らない
//    （2026-09-15・買った人の報告で発覚。**同じ所で溶かさないこと**）。
//
//    OneDrive の「PC のフォルダーのバックアップ」が入っていると、本当のデスクトップは
//    %USERPROFILE%\OneDrive\デスクトップ へ移り、%USERPROFILE%\Desktop は
//    **画面に出てこない抜け殻**として残る。そこへ送信箱を作ると、買った人のデスクトップには
//    何も現れない。しかも**エラーは一つも出ない**ので、こちらからは気づけない。
//    ダウンロードも同じように移せる。だから場所は決め打ちせず、必ず OS に聞く。
//
//    🔴 reg.exe では読めない。出力が CP932 なので、日本語を含むパス
//      （…\OneDrive\デスクトップ）を Node が開けない（外部パッケージを入れない方針）。
//      PowerShell なら UTF-8 で出せる。引用符で事故らないよう -EncodedCommand で渡す
//      （CLAUDE.md の罠4と同じ理由。**窓は windowsHide で消す**）。
//    🔵 呼ぶのは「config.json を作るとき」と「古い設定を直すとき」だけ。いちど書けば
//      config.json に実際の場所が入るので、ふだんの起動では聞かない（1秒近くかかるため）。
const ASK = [
  "[Console]::OutputEncoding=New-Object Text.UTF8Encoding $false",
  // デスクトップは .NET が知っている（移してあれば、移した先を返す）
  "[Environment]::GetFolderPath('DesktopDirectory')",
  // ダウンロードは .NET が知らないので、既知フォルダの ID でレジストリから読む
  "$k='HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders'",
  "(Get-ItemProperty -LiteralPath $k).'{374DE290-123F-4565-9164-39C4925E467B}'",
].join(";");

let asked = null;
function askWindows() {
  if (asked) return asked;
  asked = { desktop: null, downloads: null };
  if (!WIN) return asked;
  try {
    const out = execFileSync("powershell", [
      "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
      "-EncodedCommand", Buffer.from(ASK, "utf16le").toString("base64"),
    ], { stdio: ["ignore", "pipe", "ignore"], timeout: 15000, windowsHide: true });
    const lines = out.toString("utf8").split(/\r?\n/);
    asked.desktop = usable(lines[0]);
    asked.downloads = usable(lines[1]);
  } catch {
    // 🔵 聞けなくても起動は止めない。下の FALLBACK_* に退く（今までと同じ場所になる）。
  }
  return asked;
}

// 🔴 名前が違うだけで、**同じ場所**のことがある（2026-09-15・本人の機械で実測）。
//    OneDrive は %USERPROFILE%\OneDrive\デスクトップ を
//    **%USERPROFILE%\Desktop へのジャンクション**にすることがある。パスは2つ、実体は1つ。
//    気づかずに引っ越すと「移した先」＝「移す前」なので、最後の**抜け殻を消す**で
//    **本物を消してしまう**（空なら作り直されるが、開いていたエクスプローラが壊れる）。
//    path.resolve では見抜けない。**実体まで開いて比べること。**
function samePlace(a, b) {
  const norm = (p) => path.resolve(p).replace(/[\\/]+$/, "").toLowerCase();
  if (norm(a) === norm(b)) return true;
  try {
    return norm(fs.realpathSync.native(a)) === norm(fs.realpathSync.native(b));
  } catch {
    return false;                                 // 開けないなら「同じ」とは言わない
  }
}

// 返ってきた答えを疑う。空・相対・%VAR% が残っている物は使わない。
function usable(p) {
  const s = String(p == null ? "" : p).trim();
  if (!s || s.includes("%") || !path.isAbsolute(s)) return null;
  return path.resolve(s);
}

// 初回に config.json を作る。中身を書き換えれば置き場所も番号も変えられる。
function defaults() {
  const win = askWindows();
  return {
    port: 48630,                                   // 一撃極ターボ（48620）とぶつからない番号
    inbox: win.downloads || FALLBACK_DL,           // 届いたものの保存先。ダウンロードフォルダに直接
    // 🔴 送信箱は**デスクトップの中の専用フォルダ**。デスクトップそのものにはしない。
    //    ここの中身は**同じ Wi-Fi から一覧できる**ので、デスクトップ全体を送信箱にすると
    //    置いてある物が全部見えてしまう。
    outbox: `${win.desktop || FALLBACK_DESK}${SEP}${OUTBOX}`,
    name: "",                                      // 空なら PC 名。iPhone にはこれが見える
    token: "",                                     // 空なら合言葉なし（家の LAN 前提）
  };
}

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
    fs.writeFileSync(file, JSON.stringify(defaults(), null, 2) + "\n", "utf8");
  }
  // 🔵 書いてある物が揃っていれば、場所を OS に聞かない（ふだんの起動を遅くしないため）。
  const cfg = fill(raw);
  cfg.port = Number(cfg.port) || 48630;
  cfg.inbox = path.resolve(expand(cfg.inbox));
  cfg.outbox = path.resolve(expand(cfg.outbox));
  cfg.displayName = String(cfg.name || os.hostname());
  cfg.file = file;
  return cfg;
}

function fill(raw) {
  const cfg = { ...raw };
  const missing = ["port", "inbox", "outbox", "name", "token"].filter((k) => cfg[k] === undefined);
  if (missing.length) {
    const def = defaults();
    for (const k of missing) cfg[k] = def[k];
  }
  return cfg;
}

// 🔴 いちど書いた config.json を、あとから直す（2026-09-15）。
//    1.0.0 は %USERPROFILE%\Desktop を決め打ちしていたので、OneDrive を使っている人の
//    送信箱は**画面に出てこない抜け殻**を指したままになっている。**ここでしか気づけない。**
//    黙って本当のデスクトップへ移し、中身も引っ越して、config.json を書き直す。
//
//    🔴 本人が自分で選んだ場所は絶対に触らない（抜け殻をそのまま指しているときだけ動く）。
//    🔴 上書きもしない（この道具の決まり）。同じ名前が先にあったら、そのまま残して見送る。
//
//    🔵 where は**テストから場所を差し替えるため**だけにあります（本物のデスクトップを
//      触らずに引っ越しを測るため）。ふだんは渡しません。
function fixStaleOutbox(cfg, file, where) {
  if (!where && !WIN) return null;
  const stale = path.resolve(where ? where.stale : expand(`${FALLBACK_DESK}${SEP}${OUTBOX}`));
  if (path.resolve(cfg.outbox) !== stale) return null;   // 本人が選んだ場所・もう直っている物
  const desk = where ? where.desktop : askWindows().desktop;   // ここで初めて OS に聞く
  if (!desk) return null;
  const want = path.join(desk, OUTBOX);
  if (path.resolve(want) === stale) return null;         // 移していない人＝直すところが無い
  // 🔴 名前が2つあるだけで、同じ場所のことがある（OneDrive のジャンクション）。
  //    ここを見落とすと、引っ越したつもりで**本物を消す**。
  if (samePlace(path.dirname(stale), desk)) return null;

  let moved = 0;
  let left = 0;
  try {
    fs.mkdirSync(want, { recursive: true });
    for (const name of (fs.existsSync(stale) ? fs.readdirSync(stale) : [])) {
      const from = path.join(stale, name);
      const to = path.join(want, name);
      if (fs.existsSync(to)) { left++; continue; }        // 🔴 上書きしない
      try {
        fs.renameSync(from, to);
        moved++;
      } catch {
        // ドライブが違うと rename は使えない（OneDrive を別の玉に置いている人がいる）。写して消す。
        try {
          fs.cpSync(from, to, { recursive: true });
          fs.rmSync(from, { recursive: true, force: true });
          moved++;
        } catch { left++; }
      }
    }
    if (!left) { try { fs.rmdirSync(stale); } catch { /* 空でなければ残す */ } }
  } catch {
    return null;                                          // 作れない・読めないなら、今までのまま使う
  }

  cfg.outbox = want;
  try {
    const raw = JSON.parse(fs.readFileSync(file, "utf8"));
    raw.outbox = want;
    fs.writeFileSync(file, JSON.stringify(raw, null, 2) + "\n", "utf8");
  } catch {
    // 🔵 書けなくても、この回は新しい場所を使う。次に起動したときにまた直しにくる。
  }
  return { from: stale, to: want, moved, left };
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

module.exports = { load, expand, defaultFile, defaults, askWindows, fixStaleOutbox, OUTBOX };
