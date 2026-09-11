"use strict";
// 🔴 いちばん大事なのは「Mac でカレントに変な名前のフォルダを作らない」こと。
//    既定値が Windows 表記だった頃、Mac では %USERPROFILE%\Downloads という
//    名前のフォルダがカレントにできていた。ここを必ず踏む。
const fs = require("fs");
const os = require("os");
const path = require("path");
const { load, expand, DEFAULTS } = require("../lib/config");

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
    eq(outbox, path.join(os.homedir(), "Downloads", "Mr.Drop送信箱"), "送信箱は専用のフォルダ");
    ok(outbox !== inbox, "🔴 送信箱と保存先が同じ場所になっていない");
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
};
