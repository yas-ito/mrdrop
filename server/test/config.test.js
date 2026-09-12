"use strict";
// 🔴 いちばん大事なのは「Mac でカレントに変な名前のフォルダを作らない」こと。
//    既定値が Windows 表記だった頃、Mac では %USERPROFILE%\Downloads という
//    名前のフォルダがカレントにできていた。ここを必ず踏む。
const fs = require("fs");
const os = require("os");
const path = require("path");
const { load, expand, defaultFile, DEFAULTS } = require("../lib/config");

module.exports = async function (t) {
  const { suite, eq, ok } = t;

  suite("置き場所 — 既定値はどの OS でも家の中に落ちる", () => {
    const inbox = path.resolve(expand(DEFAULTS.inbox));
    const outbox = path.resolve(expand(DEFAULTS.outbox));
    ok(inbox.startsWith(os.homedir() + path.sep), "保存先の既定は家の中（" + inbox + "）");
    ok(outbox.startsWith(os.homedir() + path.sep), "送信箱の既定は家の中");
    ok(!inbox.includes("%"), "🔴 展開されずに残った %VAR% がフォルダ名にならない");
    ok(!inbox.includes(path.sep + path.sep), "区切りが二重になっていない");

    // 🔴 既定は**両OSともダウンロードフォルダそのもの**（本人決定 2026-09-12）。
    //    専用のフォルダを勝手に作らない。ここが変わったら、それは仕様変更。
    eq(inbox, path.join(os.homedir(), "Downloads"), "両OSともダウンロードフォルダそのもの");
    ok(!inbox.endsWith("受信箱"), "🔴 「受信箱」という名前のフォルダを作らない（やめた名前）");

    // 🔴 送信箱だけは専用のフォルダ。中身が同じ Wi-Fi から一覧できるので、
    //    ダウンロードフォルダそのものにすると置いてある物が全部見えてしまう。
    // 🔴 送信箱はデスクトップの中の専用フォルダ（本人指示 2026-09-12）。
    //    iPhone へ渡す物を置く場所なので、目に見えてすぐ放り込める所に置く。
    //    デスクトップ「そのもの」にはしない（中身が同じ Wi-Fi から一覧できるため）。
    eq(outbox, path.join(os.homedir(), "Desktop", "Mr.Drop送信箱"), "送信箱はデスクトップの中の専用フォルダ");
    ok(outbox !== inbox, "🔴 送信箱と保存先が同じ場所になっていない");
  });

  // 🔴 settings-windows.ps1 の Read-Config にも同じ既定が書いてある。
  //    ここがずれると、一度も起動していない人が先に「保存先を変える.bat」を押したとき、
  //    間違った既定が config.json に書き込まれて固定される（Mac 側の指摘 2026-09-12・実際にずれていた）。
  //    手で揃えるのは必ずまた外すので、機械で突き合わせる。
  suite("置き場所 — PowerShell 側の既定と食い違っていない", () => {
    const ps1 = path.join(__dirname, "..", "..", "scripts", "settings-windows.ps1");
    if (!fs.existsSync(ps1)) { ok(true, "settings-windows.ps1 が無い（配布物の中では省かれる）"); return; }
    const src = fs.readFileSync(ps1, "utf8");
    const pick = (k) => (src.match(new RegExp(k + String.raw`\s*=\s*"([^"]+)"`)) || [])[1];
    // 🔴 文字どおり突き合わせない。既定の**書き方**は OS で変わるため
    //    （JS は Mac で "~/Downloads"、PowerShell はいつも "%USERPROFILE%\Downloads"）、
    //    そのまま比べると **Mac では何を直しても必ず赤くなる**（2026-09-12 に Mac で発覚）。
    //    見たいのは書き方ではなく「**同じ場所を指しているか**」なので、expand() に通してから比べる。
    const where = (v) => (typeof v === "string" ? path.resolve(expand(v)) : String(v));
    eq(where(pick("inbox")), where(DEFAULTS.inbox), "inbox の既定がそろっている");
    eq(where(pick("outbox")), where(DEFAULTS.outbox), "outbox の既定がそろっている");
    eq(String((src.match(/port\s*=\s*(\d+)/) || [])[1]), String(DEFAULTS.port), "port の既定がそろっている");
  });

  suite("置き場所 — Windows で書いた config.json を Mac へ持っていっても読める", () => {
    eq(path.resolve(expand("%USERPROFILE%\\Downloads\\素材")),
       path.join(os.homedir(), "Downloads", "素材"),
       "🔴 %USERPROFILE% は Mac でも家に落ちる（フォルダ名にしない）");
    eq(path.resolve(expand("%HOME%/素材")), path.join(os.homedir(), "素材"), "%HOME% も同じ");
    eq(path.resolve(expand("~/Downloads/素材")),
       path.join(os.homedir(), "Downloads", "素材"), "~ は家に開く");
    eq(path.resolve(expand("~")), path.resolve(os.homedir()), "~ だけでも家");
  });

  suite("置き場所 — やり過ぎない", () => {
    eq(expand("%NOPE_MRDROP%/x"), "%NOPE_MRDROP%/x", "知らない %VAR% は勝手に家にしない");
    eq(expand("メモ\\一覧.txt"), "メモ\\一覧.txt",
       "Windows 表記に見えない \\ は触らない（Mac のファイル名を壊さないため）");
    eq(expand("/var/tmp/素材"), "/var/tmp/素材", "ふつうの絶対パスはそのまま");
  });

  suite("設定ファイル — 初回に作る", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mrdrop-cfg-"));
    const file = path.join(dir, "config.json");
    try {
      const cfg = load(file);
      ok(fs.existsSync(file), "無ければ作る");
      eq(cfg.port, DEFAULTS.port, "番号は既定のまま");
      ok(path.isAbsolute(cfg.inbox), "保存先は絶対パスになっている");
      ok(cfg.inbox.startsWith(os.homedir() + path.sep), "🔴 カレントではなく家の中に作る");
      ok(String(cfg.displayName).length > 0, "名前が空なら PC 名が入る");

      // 書いてある値が既定より優先される（~ も展開される）
      fs.writeFileSync(file, JSON.stringify({ inbox: "~/保存先テスト", port: "48631" }), "utf8");
      const cfg2 = load(file);
      eq(cfg2.inbox, path.join(os.homedir(), "保存先テスト"), "書いてあれば そちらを使う");
      eq(cfg2.port, 48631, "文字列で書かれた番号も数にする");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  // 🔴 設定ファイルはプログラムの隣に置かない（本人が実際につまずいた 2026-09-12）。
  //    Windows は展開したフォルダを %LOCALAPPDATA%\MrDrop\app へ写して、
  //    元のフォルダは捨ててよい作りにした。設定が隣にあると、捨てた瞬間に消える。
  suite("設定ファイル — 置き場所", () => {
    const got = defaultFile("/どこか/app");
    if (process.platform === "win32") {
      const want = path.join(process.env.LOCALAPPDATA, "MrDrop", "config.json");
      eq(got, want, "🔴 Windows は %LOCALAPPDATA%\\MrDrop\\config.json（記録と同じ場所）");
      ok(!got.startsWith(path.resolve("/どこか/app") + path.sep),
         "🔴 プログラムの隣には置かない（展開フォルダを捨てても設定は残る）");
    } else {
      eq(got, path.join("/どこか/app", "config.json"),
         "Mac は今までどおり隣（アプリは --config で Application Support を渡してくる）");
    }
  });

  // 🔴 settings-windows.ps1 が別の config.json を読み書きしていたら、
  //    「保存先を変える」を押しても常駐側には何も効かない（黙って外れるのが一番こまる）。
  suite("設定ファイル — PowerShell 側と同じ場所を見ている", () => {
    const ps1 = path.join(__dirname, "..", "..", "scripts", "settings-windows.ps1");
    if (!fs.existsSync(ps1)) { ok(true, "settings-windows.ps1 が無い（配布物の中では省かれる）"); return; }
    const src = fs.readFileSync(ps1, "utf8");
    ok(/\$AppDir\s*=\s*Join-Path \$env:LOCALAPPDATA "MrDrop"/.test(src),
       "置き場所は %LOCALAPPDATA%\\MrDrop");
    ok(/\$CfgFile\s*=\s*Join-Path \$AppDir "config.json"/.test(src),
       "🔴 config.json はその中（server/lib/config.js の defaultFile と同じ）");
  });

  // 🔴 入れたあとのフォルダに .bat を置かない。cmd.exe は実行中の .bat を掴んだまま
  //    行単位で読み直すので、「やめる」で自分のいるフォルダを消すと途中で壊れる。
  //    入れたあとの入口はスタートメニューのショートカット（powershell を直接呼ぶ）。
  suite("入れ方 — 写すものに .bat を混ぜない", () => {
    const ps1 = path.join(__dirname, "..", "..", "scripts", "install-windows.ps1");
    if (!fs.existsSync(ps1)) { ok(true, "install-windows.ps1 が無い"); return; }
    const src = fs.readFileSync(ps1, "utf8");
    const dirs = (src.match(/\$CopyDirs\s*=\s*@\(([^)]*)\)/) || [])[1];
    const files = (src.match(/\$CopyFiles\s*=\s*@\(([^)]*)\)/) || [])[1];
    ok(dirs != null && files != null, "写すものの一覧が読めた");
    ok(!/\.bat/i.test(String(files)), "🔴 写すファイルの一覧に .bat が無い");
    // 🔴 一覧だけ見ても足りない。scripts\ をまるごと写すので、その中の run-once.bat が
    //    すり抜けていた（2026-09-12 実測）。robocopy 側の除外まで見ること。
    ok(/robocopy[^\n]*\/XF[^\n]*\*\.bat/.test(src),
       "🔴 フォルダを写すときも .bat を除いている（run-once.bat がすり抜けない）");
    // 🔴 除外だけでは足りない。robocopy の /XF は /MIR でも消さないので、
    //    古い版が置いていった .bat が残り続ける（2026-09-12 実測）。
    ok(/Get-ChildItem -LiteralPath \$AppRoot -Recurse -Filter \*\.bat[\s\S]{0,200}Remove-Item/.test(src),
       "🔴 写したあとに .bat を掃いている（古い版の置き土産まで消す）");
    ok(/"server"/.test(String(dirs)) && /"scripts"/.test(String(dirs)) && /"node"/.test(String(dirs)),
       "server・scripts・node は写す");
    ok(/取扱説明書\.html/.test(String(files)), "取扱説明書は写す（スタートメニューから開くため）");
    ok(/Start Menu.Programs.Mr\.Drop/.test(src), "スタートメニューに入口を作っている");
    ok(/Remove-Item -LiteralPath \$AppDir -Recurse -Force/.test(src),
       "🔴 やめるときは入れたものを消す（アンインストールがある）");
  });
};
