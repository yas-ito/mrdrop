// 使い方編（2本目）の図を HTML で作る（Chrome ヘッドレスで撮る）。
//
//   node 紹介動画/図-使い方編/gen.js       → 同じ場所に *.html ができる
//   bash 紹介動画/図-使い方編/shot-mac.sh  → _build/使い方編/図/*.png（1920×1080）
//
// 🔴 色・書体・部品は ../図/common.js（1本目と分け合っています）。
//    ここを直しても1本目の図は変わりませんが、common.js を直すと**両方変わります**。
//
// 🔴 メニューの文言は tray/MrDropTray.cs の実物と**1字も違えないこと**。
//    図が実物と違うと、見た人が探して見つからない（説明書の嘘と同じ事故）。
//    2026-09-16 に MrDropTray.cs の 83〜104 行から写しました。

const { fs, path, ICON_URI, page, logo, phone, pc } = require("../図/common.js");

const HERE = __dirname;

// ── この動画だけの見た目 ──────────────────────────────────
const EXTRA = `
<style>
/* Windows のメニューを模した白いカード。地が青なので、文字は濃紺で置く */
.menu{background:#fbfcfe;border-radius:18px;padding:18px 0;width:640px;
  box-shadow:0 26px 70px rgba(0,0,0,.36);color:#16233c;}
.menu .mi{font-size:30px;line-height:1;padding:19px 34px;white-space:nowrap;
  display:flex;align-items:center;gap:14px;}
.menu .mi.dim{opacity:.34;}
/* 🔴 説明している項目だけ明るく＝ナレーションと合わせて1枚ずつ切り替える */
.menu .mi.on{background:#1c5fd0;color:#fff;font-weight:700;border-radius:10px;
  margin:0 12px;padding:19px 22px;}
.menu .state{font-size:25px;color:#3f7a3f;padding:10px 34px 18px;display:flex;gap:10px;}
.menu .sep{height:1px;background:rgba(0,0,0,.12);margin:12px 26px;}
.menu .mi .chk{font-size:24px;opacity:.7;}

.explain{flex:1;display:flex;flex-direction:column;justify-content:center;gap:34px;}
.explain .ttl{font-size:56px;font-weight:700;line-height:1.25;}
.explain .dsc{font-size:31px;line-height:1.68;opacity:.9;}
.stage{display:flex;align-items:center;gap:30px;flex-wrap:wrap;}
.tag{font-size:25px;opacity:.82;margin-top:12px;white-space:nowrap;}
/* 気をつけてほしい所は、絵文字ではなく黄色の帯と「！」で見せる */
.note.warn{border-left-color:#ffd166;}
.note.warn::before{content:"！";display:inline-flex;align-items:center;justify-content:center;
  width:38px;height:38px;border-radius:999px;background:#ffd166;color:#16233c;
  font-weight:700;font-size:26px;margin-right:14px;vertical-align:-8px;}
.note{font-size:26px;opacity:.86;border-left:4px solid rgba(255,255,255,.5);padding-left:20px;line-height:1.6;}
.taskbar{background:rgba(9,22,54,.55);border:1px solid rgba(255,255,255,.22);
  border-radius:16px;padding:16px 26px;display:flex;align-items:center;gap:22px;}
.taskbar .ico{width:64px;height:64px;border-radius:14px;}
.taskbar .cap{font-size:26px;opacity:.9;}
</style>`;

const pg = (inner) => page(EXTRA + inner);

// ── 部品 ──────────────────────────────────────────────────

// フォルダ。中に何が入っているかを小片で見せる（空なら files=0）
const folder = (label, { w = 320, files = 3, sub = "", open = false } = {}) => `
<div style="display:flex;flex-direction:column;align-items:center;min-width:${w}px;">
 <svg width="${w}" viewBox="0 0 320 250" fill="none">
  <path d="M18 62 h96 l26 30 h162 a16 16 0 0 1 16 16 v124 a16 16 0 0 1 -16 16 H18
           a16 16 0 0 1 -16 -16 V78 a16 16 0 0 1 16 -16 z"
        fill="rgba(255,255,255,${open ? ".3" : ".2"})" stroke="rgba(255,255,255,.62)" stroke-width="4"/>
  ${Array.from({ length: files }, (_, i) =>
    `<rect x="${44 + i * 74}" y="132" width="58" height="58" rx="8" fill="rgba(255,255,255,.55)"/>` +
    `<circle cx="${60 + i * 74}" cy="150" r="7" fill="rgba(28,95,208,.75)"/>`).join("")}
 </svg>
 <div style="font-size:29px;font-weight:700;margin-top:14px;white-space:nowrap;">${label}</div>
 ${sub ? `<div class="tag">${sub}</div>` : ""}
</div>`;

// 太い矢印（横）。上に短い言葉を置ける
const arw = (label = "", w = 180) => `
<div style="display:flex;flex-direction:column;align-items:center;gap:12px;min-width:${w}px;">
 ${label ? `<div style="font-size:26px;opacity:.9;">${label}</div>` : ""}
 <svg width="${w}" height="30" viewBox="0 0 ${w} 30" fill="none">
  <path d="M0 15 H${w - 30}" stroke="#fff" stroke-width="6" stroke-linecap="round"/>
  <path d="M${w - 32} 3 L${w} 15 L${w - 32} 27 Z" fill="#fff"/>
 </svg>
</div>`;

// メニュー。on に番号（1〜5）を渡すと、その項目だけ明るくする
const ITEMS = [
  "受信先を開く",
  "送信箱を開く",
  "受信先を変える...",
  "送信箱を移動する...",
  "この PC の名前を変える...",
];
const menu = (on = 0) => `
<div class="menu">
 <div class="state">● 動いています</div>
 <div class="sep"></div>
 ${ITEMS.map((t, i) =>
    `<div class="mi ${on === i + 1 ? "on" : on ? "dim" : ""}">${t}</div>`).join("\n ")}
 <div class="mi ${on ? "dim" : ""}">取扱説明書</div>
 <div class="mi ${on ? "dim" : ""}"><span class="chk">✓</span>Windows 起動時に自動で開始</div>
 <div class="sep"></div>
 <div class="mi ${on ? "dim" : ""}">Mr.Drop をアンインストール</div>
 <div class="mi ${on ? "dim" : ""}">終了</div>
</div>`;

// 左にメニュー・右に説明、の共通の骨
const item = (n, ttl, dsc, stage, note = "") => pg(`<div class="wrap">
 ${logo("設定")}
 <div class="mid">
  <div class="row" style="gap:64px;align-items:center;">
   ${menu(n)}
   <div class="explain">
    <div class="ttl">${ttl}</div>
    <div class="dsc">${dsc}</div>
    <div class="stage">${stage}</div>
    ${note ? `<div class="note">${note}</div>` : ""}
   </div>
  </div>
 </div>
</div>`);

// ── 0. 全景（ここで全部の設定ができます）───────────────────
const all = pg(`<div class="wrap">
 ${logo("設定")}
 <div class="mid">
  <div class="row" style="gap:70px;align-items:center;">
   ${menu(0)}
   <div class="explain">
    <div class="ttl">設定は、右下のアイコンを<br>右クリック。</div>
    <div class="dsc">届き先を変える・送信箱を移す・パソコンの名前を変える。<br>
      全部ここでできます。設定の画面を別に開く必要はありません。</div>
    <div class="taskbar">
     <img class="ico" src="${ICON_URI}">
     <div class="cap">タスクバーの右下（時計のとなり）</div>
    </div>
    <div class="note warn">見当たらないときは <b>「∧」</b> の中にいます。<br>
      Windows 11 は、新しいアイコンを最初は隠します。</div>
   </div>
  </div>
 </div>
</div>`);

// ── 1. 受信先を開く ───────────────────────────────────────
const item1 = item(1,
  "受信先を開く",
  "iPhone から送った物が入る場所を、そのまま開きます。<br>届いたか確かめたいときに。",
  `${phone(150)}${arw("送る", 170)}${folder("受信先", { w: 300, files: 3, sub: "はじめは ダウンロード", open: true })}`);

// ── 2. 送信箱を開く ───────────────────────────────────────
const item2 = item(2,
  "送信箱を開く",
  "iPhone へ渡したい物を置くフォルダです。<br>デスクトップを探さなくても、ここから開けます。",
  `${folder("Mr.Drop送信箱", { w: 300, files: 2, sub: "デスクトップの中", open: true })}${arw("受け取る", 170)}${phone(150)}`,
  "デスクトップを OneDrive に移している方も、ここから確実に開けます。");

// ── 3. 受信先を変える ─────────────────────────────────────
const item3 = item(3,
  "受信先を変える...",
  "届き先を、好きなフォルダに変えられます。",
  `${folder("ダウンロード", { w: 250, files: 2 })}${arw("変える", 160)}${folder("編集の素材フォルダ", { w: 250, files: 3 })}`,
  "動画編集の素材フォルダにしておくと、iPhone で撮った素材が、<br>そのまま<b>作業する場所に届きます</b>。");

// ── 4. 送信箱を移動する ───────────────────────────────────
const item4 = item(4,
  "送信箱を移動する...",
  "送信箱のフォルダごと、好きな場所へ移せます。",
  `${folder("Mr.Drop送信箱", { w: 250, files: 3, sub: "デスクトップ" })}${arw("フォルダごと", 190)}${folder("Mr.Drop送信箱", { w: 250, files: 3, sub: "好きな場所" })}`,
  "<b>中身も一緒に付いていきます。</b>デスクトップを散らかしたくない方へ。");

// ── 5. この PC の名前を変える ─────────────────────────────
const nameList = (a, b) => `
<div style="display:flex;flex-direction:column;gap:16px;">
 ${[a, b].map((t, i) => `
 <div style="background:rgba(255,255,255,${i ? ".26" : ".12"});border:2px solid rgba(255,255,255,${i ? ".7" : ".3"});
   border-radius:14px;padding:18px 26px;font-size:30px;${i ? "font-weight:700;" : "opacity:.7;"}
   display:flex;align-items:center;gap:16px;min-width:430px;">
  <svg width="34" height="34" viewBox="0 0 34 34" fill="none" style="flex:none;">
   <rect x="2" y="4" width="30" height="20" rx="3" fill="rgba(255,255,255,.75)"/>
   <rect x="13" y="26" width="8" height="3" rx="1.5" fill="rgba(255,255,255,.75)"/>
   <rect x="8" y="29" width="18" height="3" rx="1.5" fill="rgba(255,255,255,.75)"/>
  </svg>${t}
 </div>`).join("")}
</div>`;

const item5 = item(5,
  "この PC の名前を変える...",
  "iPhone の画面に出てくる、このパソコンの名前です。",
  `${phone(150)}${arw("", 130)}${nameList("DESKTOP-7F3K2X", "編集用パソコン")}`,
  "パソコンが何台もある方は、分かりやすい名前にしておくと<b>間違えません</b>。");


// ── S1 あいさつ（0:00〜）────────────────────────────────
// 前回のサムネを持ってきて「先日の、あれです」を1枚で分からせる。
// 🔴 元は ~/Documents/サムネ画像/Mr.Drop/thumb_A.png（1280×720）。
//    800px に縮めた物をこのフォルダに置いてある＝**リポジトリだけで作り直せる**。
//    本人がサムネを差し替えたら、ここも入れ替えること。
const PREV = "data:image/png;base64," +
  fs.readFileSync(path.join(HERE, "前回のサムネ.png")).toString("base64");

// 往復の矢印。行きは白、帰りは黄色。**今回できるようになったのは帰りの方**
const both = (top, bottom, w = 330) => `
<div style="display:flex;flex-direction:column;align-items:center;gap:16px;min-width:${w}px;">
 <div style="font-size:27px;opacity:.9;">${top}</div>
 <svg width="${w}" height="26" viewBox="0 0 ${w} 26" fill="none">
  <path d="M0 13 H${w - 30}" stroke="#fff" stroke-width="6" stroke-linecap="round"/>
  <path d="M${w - 32} 1 L${w} 13 L${w - 32} 25 Z" fill="#fff"/>
 </svg>
 <svg width="${w}" height="26" viewBox="0 0 ${w} 26" fill="none">
  <path d="M32 13 H${w}" stroke="#ffd166" stroke-width="6" stroke-linecap="round"/>
  <path d="M34 1 L0 13 L34 25 Z" fill="#ffd166"/>
 </svg>
 <div style="font-size:27px;color:#ffd166;font-weight:700;">${bottom}</div>
</div>`;

// 目次の1行。今回の目玉（③）だけ黄色で立てる
const num = (n, t, hot = false) => `
<div style="display:flex;align-items:center;gap:26px;border-radius:18px;padding:22px 32px;
  background:rgba(255,255,255,${hot ? ".24" : ".10"});
  border:2px solid rgba(255,255,255,${hot ? ".85" : ".26"});">
 <div style="flex:none;width:58px;height:58px;border-radius:999px;display:flex;
   align-items:center;justify-content:center;font-size:32px;font-weight:700;
   background:${hot ? "#ffd166" : "rgba(255,255,255,.9)"};color:#16233c;">${n}</div>
 <div style="font-size:${hot ? 38 : 34}px;font-weight:${hot ? 700 : 500};">${t}</div>
 ${hot ? `<div style="margin-left:auto;font-size:25px;color:#ffd166;font-weight:700;white-space:nowrap;">★ 今回の目玉</div>` : ""}
</div>`;

// 1. タイトル（冒頭2秒）
const s1title = pg(`<div class="wrap" style="justify-content:center;align-items:center;text-align:center;">
 <img src="${ICON_URI}" style="width:196px;height:196px;border-radius:44px;box-shadow:0 22px 62px rgba(0,0,0,.34);">
 <h1 style="margin-top:42px;">Mr.Drop</h1>
 <div class="badge" style="margin-top:30px;font-size:44px;padding:18px 56px;">使い方</div>
 <div class="lead" style="margin-top:34px;">iPhone ⇄ パソコン　写真も動画も、そのまま</div>
</div>`);

// 2. 先日の動画（＝前回の続きです）
const s1before = pg(`<div class="wrap">
 ${logo("使い方")}
 <div class="mid">
  <div class="row" style="gap:64px;align-items:center;">
   <div style="position:relative;flex:none;">
    <img src="${PREV}" style="width:740px;border-radius:20px;display:block;
      border:3px solid rgba(255,255,255,.5);box-shadow:0 26px 70px rgba(0,0,0,.42);">
    <div style="position:absolute;left:26px;top:-24px;background:#fff;color:#1257c7;
      border-radius:999px;padding:10px 30px;font-size:27px;font-weight:700;">先日の動画</div>
   </div>
   <div class="explain" style="gap:30px;">
    <div class="ttl" style="font-size:52px;">おかげさまで好評でした。<br>アップデートしました。</div>
    <div class="dsc">iPhone で撮った写真や動画を、<br>Windows のパソコンへ、そのまま送れる。</div>
    <div class="stage" style="gap:16px;">${phone(110)}${arw("送る", 140)}${pc(210)}</div>
   </div>
  </div>
 </div>
</div>`);

// 3. 今回のアップデート（往復できるようになった）
const s1now = pg(`<div class="wrap">
 ${logo("使い方")}
 <div class="mid">
  <h2 style="text-align:center;">さらに使いやすく、自分好みに。</h2>
  <div class="row center" style="margin-top:30px;">
   <div class="badge" style="font-size:34px;">★ みなさまのご要望にお応えしました</div>
  </div>
  <div class="row center" style="gap:44px;margin-top:44px;">
   ${phone(170)}${both("送る（前から）", "受け取る（今回から）", 340)}${pc(380)}
  </div>
 </div>
</div>`);

// 4. 目次（最初から最後まで通してお見せします）
const s1menu = pg(`<div class="wrap">
 ${logo("使い方")}
 <div class="mid">
  <h2>最初から最後まで、通してお見せします。</h2>
  <div style="display:flex;flex-direction:column;gap:16px;margin-top:36px;">
   ${num(1, "アプリから送る")}
   ${num(2, "写真アプリの共有ボタンから送る")}
   ${num(3, "パソコン → iPhone", true)}
   ${num(4, "設定の変え方")}
  </div>
 </div>
</div>`);


// ── S6 締め（3:27〜）──────────────────────────────────────
// ふきだし。コメント欄の声を、言葉のまま見せる
const bubble = (t) => `
<div style="background:rgba(255,255,255,.2);border:2px solid rgba(255,255,255,.58);
  border-radius:22px;padding:22px 34px;font-size:32px;line-height:1.45;white-space:nowrap;">${t}</div>`;

// 1. 値段（Windows 版と Mac 版、両方入って ワンコイン）
const s6price = pg(`<div class="wrap">
 ${logo("")}
 <div class="mid" style="align-items:center;text-align:center;">
  <h2>Windows 版と Mac 版、両方入って。</h2>
  <div class="row center" style="gap:26px;margin-top:40px;">
   <div class="chip" style="font-size:32px;">Windows 版</div>
   <div class="big-plus" style="font-size:52px;">＋</div>
   <div class="chip" style="font-size:32px;">Mac 版</div>
  </div>
  <div style="display:flex;align-items:baseline;gap:22px;margin-top:44px;">
   <div style="font-size:50px;font-weight:700;opacity:.9;">ワンコイン</div>
   <div style="font-size:132px;font-weight:700;line-height:1;">¥500</div>
  </div>
  <div class="foot" style="margin-top:34px;">
   ※ iPhone アプリは App Store で無料　／　同じ Wi-Fi につながっていることが条件です</div>
 </div>
</div>`);

// 2. 発売記念・まもなく終了（🔴 ここは一番伝えたい所なので、黄色で立てる）
const s6limited = pg(`<div class="wrap">
 ${logo("")}
 <div class="mid" style="align-items:center;text-align:center;">
  <div class="badge" style="background:#ffd166;color:#16233c;font-size:38px;padding:18px 48px;">
   発売記念の価格です</div>
  <h2 style="margin-top:42px;">まもなく終了します。</h2>
  <div class="lead" style="margin-top:32px;font-size:40px;">気になった方は、お早めにどうぞ。</div>
 </div>
</div>`);

// 3. BOOTH（概要欄にリンクがある、を「↓」で分からせる）
const s6booth = pg(`<div class="wrap">
 ${logo("")}
 <div class="mid" style="align-items:center;text-align:center;">
  <h2>詳しい内容は、BOOTH のページへ。</h2>
  <div class="card" style="margin-top:44px;width:920px;text-align:left;">
   <div class="row" style="gap:28px;align-items:center;">
    <img src="${ICON_URI}" style="width:96px;height:96px;border-radius:22px;flex:none;">
    <div style="flex:1;">
     <div class="ttl" style="margin-bottom:8px;">Mr.Drop</div>
     <div class="dsc" style="white-space:nowrap;">写真も動画も、そのままパソコンへ</div>
    </div>
    <div class="badge" style="flex:none;">¥500</div>
   </div>
  </div>
  <div class="chip" style="margin-top:34px;font-size:32px;">yas-tools.booth.pm</div>
  <div class="lead" style="margin-top:28px;">↓ 概要欄にリンクがあります</div>
 </div>
</div>`);

// 4. ご意見から生まれました（コメントを促す）
const s6voice = pg(`<div class="wrap">
 ${logo("")}
 <div class="mid" style="align-items:center;text-align:center;">
  <h2>みなさまのご意見から生まれました。</h2>
  <div class="badge" style="margin-top:32px;">ありがとうございます</div>
  <div class="row center" style="gap:30px;margin-top:42px;">
   ${bubble("こんなアプリがほしい")}
   ${bubble("ここを直してほしい")}
  </div>
  <div class="lead" style="margin-top:38px;font-size:36px;">ぜひ、コメントで教えてください。</div>
 </div>
</div>`);

// 5. 締めのカード
const s6end = pg(`<div class="wrap">
 <div class="mid" style="align-items:center;text-align:center;">
  <img src="${ICON_URI}" style="width:150px;height:150px;border-radius:34px;
    box-shadow:0 18px 50px rgba(0,0,0,.3);">
  <h2 style="margin-top:36px;">ご視聴ありがとうございました</h2>
  <div class="lead" style="margin-top:30px;font-size:36px;">
   よろしければ、チャンネル登録と高評価を。</div>
  <div class="row" style="margin-top:44px;gap:22px;">
   <div class="chip">yas-tools.booth.pm</div>
   <div class="chip">App Store で「Mr.Drop」</div>
  </div>
 </div>
 <div class="foot above-telop" style="text-align:center;">yas-tools</div>
</div>`);

for (const [name, html] of [
  ["s1_title.html", s1title],
  ["s1_before.html", s1before],
  ["s1_now.html", s1now],
  ["s1_menu.html", s1menu],
  ["s5_all.html", all],
  ["s5_item1.html", item1],
  ["s5_item2.html", item2],
  ["s5_item3.html", item3],
  ["s5_item4.html", item4],
  ["s5_item5.html", item5],
  ["s6_price.html", s6price],
  ["s6_limited.html", s6limited],
  ["s6_booth.html", s6booth],
  ["s6_voice.html", s6voice],
  ["s6_end.html", s6end],
]) {
  fs.writeFileSync(path.join(HERE, name), html, "utf8");
  console.log("書きました:", name);
}
