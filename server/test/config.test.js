"use strict";
// 🔴 いちばん大事なのは「Mac でカレントに変な名前のフォルダを作らない」こと。
//    既定値が Windows 表記だった頃、Mac では %USERPROFILE%\Downloads という
//    名前のフォルダがカレントにできていた。ここを必ず踏む。
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");
const { load, expand, defaultFile, defaults, askWindows, fixStaleOutbox, OUTBOX } = require("../lib/config");

const WIN = process.platform === "win32";

module.exports = async function (t) {
  const { suite, eq, ok } = t;

  // 🔴 Windows の「デスクトップ」「ダウンロード」は %USERPROFILE% の下とは限らない
  //    （OneDrive の「PC のフォルダーのバックアップ」。2026-09-15・買った人の報告で発覚）。
  //    だから「%USERPROFILE%\Desktop であること」ではなく「**OS が言う場所であること**」を見る。
  const realDesk = path.resolve((WIN && askWindows().desktop) || path.join(os.homedir(), "Desktop"));
  const realDL = path.resolve((WIN && askWindows().downloads) || path.join(os.homedir(), "Downloads"));

  suite("置き場所 — 既定値はどの OS でも家の中に落ちる", () => {
    const def = defaults();
    const inbox = path.resolve(expand(def.inbox));
    const outbox = path.resolve(expand(def.outbox));
    ok(!inbox.includes("%"), "🔴 展開されずに残った %VAR% がフォルダ名にならない");
    ok(!inbox.includes(path.sep + path.sep), "区切りが二重になっていない");
    ok(path.isAbsolute(inbox) && path.isAbsolute(outbox), "どちらも絶対パスになっている");

    // 🔴 既定は**両OSともダウンロードフォルダそのもの**（本人決定 2026-09-12）。
    //    専用のフォルダを勝手に作らない。ここが変わったら、それは仕様変更。
    eq(inbox, realDL, "両OSともダウンロードフォルダそのもの（" + inbox + "）");
    ok(!inbox.endsWith("受信箱"), "🔴 「受信箱」という名前のフォルダを作らない（やめた名前）");

    // 🔴 送信箱だけは専用のフォルダ。中身が同じ Wi-Fi から一覧できるので、
    //    ダウンロードフォルダそのものにすると置いてある物が全部見えてしまう。
    // 🔴 送信箱はデスクトップの中の専用フォルダ（本人指示 2026-09-12）。
    //    iPhone へ渡す物を置く場所なので、目に見えてすぐ放り込める所に置く。
    //    デスクトップ「そのもの」にはしない（中身が同じ Wi-Fi から一覧できるため）。
    eq(outbox, path.join(realDesk, OUTBOX), "送信箱はデスクトップの中の専用フォルダ");
    ok(outbox !== inbox, "🔴 送信箱と保存先が同じ場所になっていない");
  });

  // 🔴 これが 2026-09-15 の取りこぼしそのものです。%USERPROFILE%\Desktop を決め打ちしていたので、
  //    OneDrive でデスクトップを移している人の送信箱は「画面に出てこない抜け殻」の中にできていた。
  //    **エラーは一つも出ませんでした。**買った人に言われるまで気づけません。
  suite("置き場所 — デスクトップの場所を OS に聞いている", () => {
    if (!WIN) { ok(true, "Windows でだけ測れる（Mac の ~/Desktop は動かない）"); return; }
    const win = askWindows();
    ok(win.desktop && fs.existsSync(win.desktop), "デスクトップの本当の場所を取れた（" + win.desktop + "）");
    ok(win.downloads && fs.existsSync(win.downloads), "ダウンロードの本当の場所を取れた（" + win.downloads + "）");
  });

  // 🔴 settings-windows.ps1 にも同じ既定が書いてある。ここがずれると、
  //    一度も起動していない人が先に「保存先を変える.bat」を押したとき、
  //    間違った既定が config.json に書き込まれて固定される（Mac 側の指摘 2026-09-12・実際にずれていた）。
  //    手で揃えるのは必ずまた外すので、機械で突き合わせる。
  suite("置き場所 — PowerShell 側の既定と食い違っていない", () => {
    const ps1 = path.join(__dirname, "..", "..", "scripts", "settings-windows.ps1");
    if (!fs.existsSync(ps1)) { ok(true, "settings-windows.ps1 が無い（配布物の中では省かれる）"); return; }
    const src = fs.readFileSync(ps1, "utf8");

    // 🔵 Mac からはここまで（powershell が無いので走らせられない）。読み方が同じかを見る。
    ok(/GetFolderPath\('DesktopDirectory'\)/.test(src), "デスクトップは OS に聞いている（決め打ちしていない）");
    ok(src.includes("{374DE290-123F-4565-9164-39C4925E467B}"), "ダウンロードは既知フォルダの ID で読んでいる");
    ok(!/outbox\s*=\s*"%USERPROFILE%/.test(src), "🔴 %USERPROFILE%\\Desktop の決め打ちが戻っていない");
    if (!WIN) { ok(true, "同じ場所を指すかどうかは Windows で測る"); return; }

    // 🔴 文字どおり突き合わせない。見たいのは書き方ではなく「**同じ場所を指しているか**」。
    //    PowerShell 側に -PrintDefaults を用意してあるので、走らせた答えを比べる。
    const out = execFileSync("powershell", [
      "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ps1, "-PrintDefaults",
    ], { stdio: ["ignore", "pipe", "ignore"], timeout: 30000, windowsHide: true });
    const ps = JSON.parse(out.toString("utf8"));
    const def = defaults();
    const where = (v) => path.resolve(expand(String(v)));
    eq(where(ps.inbox), where(def.inbox), "inbox の既定がそろっている");
    eq(where(ps.outbox), where(def.outbox), "outbox の既定がそろっている");
    eq(Number(ps.port), def.port, "port の既定がそろっている");
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
      eq(cfg.port, defaults().port, "番号は既定のまま");
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

  // 🔴 1.0.0 が %USERPROFILE%\Desktop を決め打ちしていた分の後始末（2026-09-15）。
  //    すでに買った人の config.json は、画面に出てこない抜け殻を指したままになっている。
  //    起動したときに黙って直す。**中身も一緒に引っ越す**（置いていくと、消えたように見える）。
  suite("送信箱 — 古い設定を直して、中身も引っ越す", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mrdrop-outbox-"));
    try {
      const stale = path.join(dir, "抜け殻デスクトップ", OUTBOX);
      const desk = path.join(dir, "本当のデスクトップ");
      const file = path.join(dir, "config.json");
      fs.mkdirSync(stale, { recursive: true });
      fs.mkdirSync(desk, { recursive: true });
      fs.writeFileSync(path.join(stale, "渡したい書類.txt"), "中身", "utf8");
      fs.mkdirSync(path.join(stale, "フォルダごと"));
      fs.writeFileSync(path.join(stale, "フォルダごと", "中の物.txt"), "中身", "utf8");
      fs.writeFileSync(file, JSON.stringify({ port: 48630, outbox: stale, name: "テスト機" }), "utf8");

      const cfg = { outbox: stale };
      const moved = fixStaleOutbox(cfg, file, { stale, desktop: desk });
      const after = () => JSON.parse(fs.readFileSync(file, "utf8"));

      ok(moved && moved.moved === 2, "中身を引っ越した（2 個）");
      eq(cfg.outbox, path.join(desk, OUTBOX), "送信箱は本当のデスクトップの中になった");
      ok(fs.existsSync(path.join(desk, OUTBOX, "渡したい書類.txt")), "ファイルが新しい場所にある");
      ok(fs.existsSync(path.join(desk, OUTBOX, "フォルダごと", "中の物.txt")), "フォルダごと移っている");
      ok(!fs.existsSync(stale), "🔴 空になった抜け殻は残さない（同じ物が2か所にあると必ず迷う）");
      eq(after().outbox, path.join(desk, OUTBOX), "config.json も書き直してある");
      eq(after().name, "テスト機", "🔴 ほかの設定は触らない");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  suite("送信箱 — 古い設定を直すとき、やり過ぎない", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mrdrop-outbox2-"));
    try {
      const stale = path.join(dir, "抜け殻", OUTBOX);
      const desk = path.join(dir, "デスクトップ");
      const file = path.join(dir, "config.json");
      fs.mkdirSync(stale, { recursive: true });
      fs.mkdirSync(path.join(desk, OUTBOX), { recursive: true });
      fs.writeFileSync(file, JSON.stringify({ outbox: stale }), "utf8");

      // 🔴 本人が自分で選んだ場所は触らない
      const mine = { outbox: path.join(dir, "本人が選んだ場所") };
      eq(fixStaleOutbox(mine, file, { stale, desktop: desk }), null, "自分で選んだ場所には手を出さない");
      eq(mine.outbox, path.join(dir, "本人が選んだ場所"), "指したままにする");

      // 🔴 デスクトップを移していない人（抜け殻がそのまま本物）には、何もしない
      eq(fixStaleOutbox({ outbox: stale }, file, { stale, desktop: path.dirname(stale) }), null,
         "デスクトップを移していない人には何もしない");

      // 🔴 同じ名前が先にあったら上書きしない（この道具の決まり）
      fs.writeFileSync(path.join(stale, "同じ名前.txt"), "あとから来た方", "utf8");
      fs.writeFileSync(path.join(desk, OUTBOX, "同じ名前.txt"), "先にあった方", "utf8");
      const moved = fixStaleOutbox({ outbox: stale }, file, { stale, desktop: desk });
      eq(moved.left, 1, "先にあった物は見送る");
      eq(fs.readFileSync(path.join(desk, OUTBOX, "同じ名前.txt"), "utf8"), "先にあった方", "🔴 上書きしない");
      ok(fs.existsSync(path.join(stale, "同じ名前.txt")), "🔴 移せなかった物は消さない（前の場所に残す）");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  // 🔴 名前が違うだけで、**同じ場所**のことがある（2026-09-15・本人の機械で実際に起きた）。
  //    OneDrive が `%USERPROFILE%\OneDrive\デスクトップ` を `%USERPROFILE%\Desktop` への
  //    **ジャンクション**にしていた。パスは2つ、実体は1つ。気づかずに引っ越すと
  //    「移した先」＝「移す前」なので、最後の**抜け殻を消す**で本物を消してしまう。
  //    （実際に一瞬消えて作り直され、開いていたエクスプローラが壊れた。）
  suite("送信箱 — 名前が2つあるだけの同じ場所は、触らない", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mrdrop-junction-"));
    const realDesk = path.join(dir, "Desktop");
    const linkDesk = path.join(dir, "OneDrive", "デスクトップ");
    try {
      const stale = path.join(realDesk, OUTBOX);
      const file = path.join(dir, "config.json");
      fs.mkdirSync(stale, { recursive: true });
      fs.mkdirSync(path.dirname(linkDesk), { recursive: true });
      fs.writeFileSync(path.join(stale, "大事な物.txt"), "消えたら困る", "utf8");
      fs.writeFileSync(file, JSON.stringify({ outbox: stale }), "utf8");

      try {
        fs.symlinkSync(realDesk, linkDesk, WIN ? "junction" : "dir");
      } catch {
        ok(true, "この環境ではジャンクションを作れない（ここは測れません）");
        return;
      }

      const cfg = { outbox: stale };
      eq(fixStaleOutbox(cfg, file, { stale, desktop: linkDesk }), null, "同じ場所なので何もしない");
      eq(cfg.outbox, stale, "送信箱の場所も変えない");
      ok(fs.existsSync(stale), "🔴 本物を消していない");
      eq(fs.readFileSync(path.join(stale, "大事な物.txt"), "utf8"), "消えたら困る", "🔴 中身も無事");
    } finally {
      try { fs.rmSync(linkDesk, { force: true }); } catch { /* ジャンクションを先に外す */ }
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  // 🔴 送信箱はデスクトップの中だが、**デスクトップの場所は人によって違う**。
  //    見つからない人のために、常駐アイコンから必ず開けるようにした（2026-09-15）。
  //    呼ぶ側（常駐アイコン）と受ける側（.ps1）が食い違うと、押しても何も起きない。
  suite("送信箱 — 常駐アイコンから開ける・変えられる", () => {
    const cs = path.join(__dirname, "..", "..", "tray", "MrDropTray.cs");
    const ps1 = path.join(__dirname, "..", "..", "scripts", "settings-windows.ps1");
    if (!fs.existsSync(cs) || !fs.existsSync(ps1)) { ok(true, "元のソースが無い（配布物の中では省かれる）"); return; }
    const csSrc = fs.readFileSync(cs, "utf8");
    const psSrc = fs.readFileSync(ps1, "utf8");
    ok(/ToolStripMenuItem\("送信箱を開く"[\s\S]{0,80}-OpenOutbox/.test(csSrc), "メニューに「送信箱を開く」がある");
    ok(/\[switch\]\$OpenOutbox/.test(psSrc), "🔴 .ps1 が -OpenOutbox を受ける（押して何も起きないのが一番こまる）");
    ok(/if \(\$OpenOutbox\)/.test(psSrc), "受けたあと、実際に開いている");

    // 🔴 場所も変えられる（本人の指示 2026-09-15）。中身の引っ越しは .ps1 に一本化。
    ok(/ToolStripMenuItem\("送信箱を変える\.\.\."[\s\S]{0,60}ChangeOutbox/.test(csSrc),
       "メニューに「送信箱を変える...」がある");
    ok(/-ChooseOutbox -FromTray/.test(csSrc), "変えたあとに常駐を入れ直す（-FromTray）");
    ok(/\[switch\]\$ChooseOutbox/.test(psSrc), "🔴 .ps1 が -ChooseOutbox を受ける");
    ok(/if \(\$ChooseOutbox\)/.test(psSrc), "受けたあと、実際に選ばせている");
    ok(/Move-OutboxContents \$now \$new/.test(psSrc), "🔴 中身も一緒に引っ越している");
    ok(/Test-SamePlace \$new \(Get-InboxPath\)/.test(psSrc),
       "🔴 保存先と同じ場所は断っている（届いた物が全部見えてしまう）");

    // 🔴 .cs を直してビルドを忘れると、配るのは古いアイコンのまま。機械で見る。
    const exe = path.join(__dirname, "..", "..", "tray", "MrDropTray.exe");
    if (!fs.existsSync(exe)) { ok(true, "MrDropTray.exe が無い"); return; }
    const bin = fs.readFileSync(exe);
    ok(bin.includes(Buffer.from("送信箱を開く", "utf16le")),
       "🔴 作り直した MrDropTray.exe にも入っている（build\\build-tray.ps1 を忘れていない）");
    ok(bin.includes(Buffer.from("送信箱を変える...", "utf16le")), "🔴 「送信箱を変える...」も入っている");
  });

  // 🔴 送信箱の場所を変えられるようにした（本人の指示 2026-09-15）。
  //    **中身も一緒に引っ越す**こと。場所だけ変えると前の送信箱のファイルが置き去りになり、
  //    説明書の「送信箱は動かさないでください」と食い違う。
  //    🔴 ファイルを失いかねない処理なので、.ps1 の引っ越しを**直接呼んで**固める。
  suite("送信箱を変える — 中身の引っ越し", () => {
    const ps1 = path.join(__dirname, "..", "..", "scripts", "settings-windows.ps1");
    if (!WIN || !fs.existsSync(ps1)) { ok(true, "Windows でだけ測れます"); return; }
    const move = (from, to) => JSON.parse(execFileSync("powershell", [
      "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ps1,
      "-MoveOutboxFrom", from, "-MoveOutboxTo", to,
    ], { stdio: ["ignore", "pipe", "ignore"], timeout: 60000, windowsHide: true }).toString("utf8"));

    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mrdrop-move-"));
    const link = path.join(dir, "別名");
    try {
      // ① ふつうに引っ越す
      const from = path.join(dir, "前の送信箱");
      const to = path.join(dir, "新しい送信箱");
      fs.mkdirSync(from, { recursive: true });
      fs.writeFileSync(path.join(from, "渡したい書類.txt"), "中身", "utf8");
      fs.mkdirSync(path.join(from, "フォルダごと"));
      fs.writeFileSync(path.join(from, "フォルダごと", "中の物.txt"), "中身", "utf8");

      const r1 = move(from, to);
      eq(r1.moved, 2, "中身が引っ越した（2 個）");
      eq(r1.left, 0, "見送った物は無い");
      ok(r1.removed, "空になった前の送信箱は片付けた");
      ok(fs.existsSync(path.join(to, "渡したい書類.txt")), "ファイルが新しい場所にある");
      ok(fs.existsSync(path.join(to, "フォルダごと", "中の物.txt")), "フォルダごと移っている");
      ok(!fs.existsSync(from), "前の場所は残っていない");

      // ② 同じ名前が先にあったら上書きしない
      const a = path.join(dir, "a");
      const b = path.join(dir, "b");
      fs.mkdirSync(a); fs.mkdirSync(b);
      fs.writeFileSync(path.join(a, "同じ名前.txt"), "あとから来た方", "utf8");
      fs.writeFileSync(path.join(b, "同じ名前.txt"), "先にあった方", "utf8");
      fs.writeFileSync(path.join(a, "ぶつからない物.txt"), "移る", "utf8");

      const r2 = move(a, b);
      eq(r2.moved, 1, "ぶつからない物だけ移った");
      eq(r2.left, 1, "同じ名前は見送った");
      ok(!r2.removed, "🔴 残った物があるので、前の場所は消さない");
      eq(fs.readFileSync(path.join(b, "同じ名前.txt"), "utf8"), "先にあった方", "🔴 上書きしない");
      ok(fs.existsSync(path.join(a, "同じ名前.txt")), "🔴 移せなかった物は消さない");

      // ③ 🔴 名前が2つあるだけの同じ場所（ジャンクション）。ここで消したら大事故
      const real = path.join(dir, "実体");
      fs.mkdirSync(real);
      fs.writeFileSync(path.join(real, "大事な物.txt"), "消えたら困る", "utf8");
      fs.symlinkSync(real, link, "junction");

      const r3 = move(real, link);
      ok(r3.same, "同じ場所だと気づいた");
      eq(r3.moved, 0, "何も動かしていない");
      ok(!r3.removed, "🔴 消していない");
      eq(fs.readFileSync(path.join(real, "大事な物.txt"), "utf8"), "消えたら困る", "🔴 中身は無事");
    } finally {
      try { fs.rmSync(link, { force: true }); } catch { /* ジャンクションを先に外す */ }
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  // 🔴 どの版が入っているかは、入れ替えのたびに必ず要る（1.0.1 と 1.0.2 で実際に困った）。
  //    雫を右クリックしたら、いちばん上で分かるようにしてある（本人の指示 2026-09-15）。
  //    🔴 版数を C# に書き写さないこと。写すと本体とずれて、黙って食い違う。
  suite("常駐アイコン — 入っている版が分かる", () => {
    const cs = path.join(__dirname, "..", "..", "tray", "MrDropTray.cs");
    if (!fs.existsSync(cs)) { ok(true, "元のソースが無い（配布物の中では省かれる）"); return; }
    const src = fs.readFileSync(cs, "utf8");
    ok(/string ReadVersion\(\)/.test(src), "版数を読む口がある");
    ok(src.includes('const VERSION = \\"([^\\"]+)\\"'), "server/mrdrop.js の VERSION から読んでいる");
    ok(!/"\d+\.\d+\.\d+"/.test(src), "🔴 版数を書き写していない（ここがずれると見分けられなくなる）");
    ok(/stateItem\.Text\s*=[^;]*versionText/.test(src), "右クリックのいちばん上に出している");

    const exe = path.join(__dirname, "..", "..", "tray", "MrDropTray.exe");
    if (!fs.existsSync(exe)) { ok(true, "MrDropTray.exe が無い"); return; }
    ok(fs.readFileSync(exe).includes(Buffer.from("   バージョン ", "utf16le")),
       "🔴 作り直した exe にも入っている（build\\build-tray.ps1 を忘れていない）");
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
