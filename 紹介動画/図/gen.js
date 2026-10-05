// 紹介動画で使う図を HTML で作る（Chrome ヘッドレスで撮る）。
//
// 🔴 **最初から 1920×1080 で作ること。**あとで引き延ばさないための決まり
//    （紹介動画/台本.md の「画の決まり」）。撮るときは倍率2で撮って半分に縮める。
//
// 色と書体は BOOTH の商品画像（yas-tools-ops/ops/mrdrop-booth-images/gen.py）と揃えてある。
//
//   node 紹介動画/図/gen.js          → 同じ場所に *.html ができる
//   紹介動画/図/shot.ps1             → _build/紹介動画/図/*.png（1920×1080）

// 🔵 色・書体・部品は common.js（使い方編の図と分け合っています）
const { fs, path, HERE, ICON_URI, page, logo, phone, pc, arrow, cloudX } = require("./common.js");


// ── 1. タイトル ───────────────────────────────────────────
const title = page(`<div class="wrap">
 ${logo("iPhone → パソコン ファイル転送")}
 <div class="mid">
  <h1>iPhone のデータを、<br>Windows に送れる。</h1>
  <div class="lead" style="margin-top:40px;">同じ Wi-Fi の中で、そのまま。インターネットに出ません。</div>
 </div>
 <div class="row above-telop" style="gap:20px;">
  <div class="chip">Windows 10 / 11</div><div class="chip">macOS 13 以降</div>
  <div class="chip">iPhone アプリは無料</div>
 </div>
</div>`);

// ── 2. S2 直接送る ────────────────────────────────────────
const direct = page(`<div class="wrap">
 ${logo("同じ Wi-Fi の中で、直接")}
 <div class="mid">
  <div class="row center" style="gap:56px;">
   ${phone(230)}
   ${arrow("同じ Wi-Fi")}
   ${pc(470)}
  </div>
  <div class="row center" style="margin-top:56px;gap:30px;">
   ${cloudX(210)}
   <div style="font-size:38px;font-weight:700;">インターネットに出ません</div>
  </div>
 </div>
</div>`);

// ── 3. S5 外に出ない ──────────────────────────────────────
const home = page(`<div class="wrap">
 ${logo("写真は、外に出ません")}
 <div class="mid">
  <div class="row center" style="gap:60px;">
   <div style="border:5px dashed rgba(255,255,255,.55);border-radius:28px;padding:56px 70px;">
    <div style="font-size:30px;opacity:.85;margin-bottom:28px;">あなたの家の Wi-Fi</div>
    <div class="row" style="gap:48px;align-items:center;">${phone(180)}${pc(360)}</div>
   </div>
   ${cloudX(240)}
  </div>
  <div class="row" style="margin-top:52px;gap:22px;">
   <div class="chip">アカウント登録なし</div><div class="chip">広告なし</div>
   <div class="chip">データ収集なし</div><div class="chip">閉じれば、誰も送れない</div>
  </div>
 </div>
</div>`);

// ── 4. S8 2つで動く ───────────────────────────────────────
const two = page(`<div class="wrap">
 ${logo("2つで動きます")}
 <div class="mid">
  <div class="row center" style="gap:40px;">
   <div class="card grow"><div class="ttl">iPhone アプリ</div>
    <div class="dsc">送る側。App Store で<b>無料</b>。<br>写真アプリの共有ボタンから送れます。</div>
    <div style="margin-top:24px;"><span class="badge">無料</span></div></div>
   <div class="big-plus">＋</div>
   <div class="card grow"><div class="ttl">パソコン側</div>
    <div class="dsc">受け取る側。<b>これが商品です</b>。<br>Windows 版と Mac 版の両方が入っています。</div>
    <div style="margin-top:24px;"><span class="badge">BOOTH ¥500</span></div></div>
  </div>
  <div class="lead" style="margin-top:48px;text-align:center;">
   ※ iPhone とパソコンが同じ Wi-Fi につながっていることが条件です
  </div>
 </div>
</div>`);

// ── 5. エンディング ───────────────────────────────────────
const end = page(`<div class="wrap">
 ${logo("")}
 <div class="mid" style="align-items:center;text-align:center;">
  <h2>ご視聴ありがとうございました</h2>
  <div class="lead" style="margin-top:36px;">よろしければ、チャンネル登録と、いいねを。</div>
  <div class="row" style="margin-top:52px;gap:22px;">
   <div class="chip">yas-tools.booth.pm</div>
   <div class="chip">App Store で「Mr.Drop」</div>
  </div>
 </div>
 <div class="foot above-telop" style="text-align:center;">yas-tools</div>
</div>`);

// ── 6. S1 困りごと（台本「ケーブル／クラウド／チャットの3語を×印つきのカードで順に出す」）─
// 🔴 3枚で1組。ナレーションの順に出すので、まだ言っていないカードは薄くしておく。
const xmark = (on) => `
<svg width="60" height="60" viewBox="0 0 60 60" fill="none">
 <circle cx="30" cy="30" r="27" fill="rgba(255,255,255,${on ? ".16" : ".08"})"
   stroke="rgba(255,255,255,${on ? ".62" : ".3"})" stroke-width="3"/>
 <path d="M19 19 L41 41 M41 19 L19 41" stroke="#fff" stroke-width="5" stroke-linecap="round"
   opacity="${on ? "1" : ".45"}"/>
</svg>`;

const PROBLEMS = [
  ["ケーブル", "つないでも、途中で止まる"],
  ["クラウド", "上げて、落とし直す。時間がかかる"],
  ["メール・チャット", "写真が圧縮されて、画質が落ちる"],
];
const problem = (n) => page(`<div class="wrap">
 ${logo("いまは、こうなっています")}
 <div class="mid">
  <h2 style="margin-bottom:52px;">iPhone から Windows へ写真を移すのは、<br>いまだに面倒です。</h2>
  <div class="row" style="gap:30px;align-items:stretch;">
   ${PROBLEMS.map(function (it, i) {
     var on = i < n;
     return `<div class="card grow" style="${on ? "" : "opacity:.22;"}">
      <div class="row" style="gap:20px;align-items:center;">${xmark(on)}
       <div class="ttl" style="margin:0;">${it[0]}</div></div>
      <div class="dsc" style="margin-top:20px;">${it[1]}</div></div>`;
   }).join("")}
  </div>
 </div>
</div>`);

// ── 7. S4 届く形式 ────────────────────────────────────────
// 🔴 写真は「解像度はそのまま」、動画は「無劣化」と**書き分ける**（Windows 側の指摘 2026-09-12）。
//    写真の HEIC→JPEG は iOS が変換し直すので、厳密には「画質は変わらない」とは言えない。
const format = page(`<div class="wrap">
 ${logo("届く形式")}
 <div class="mid">
  <div class="row center" style="gap:36px;align-items:stretch;">
   <div class="card grow"><div class="ttl">写真　HEIC → JPEG</div>
    <div class="dsc">どのパソコンでも、そのまま開けます。<br><b>解像度はそのままです。</b></div></div>
   <div class="card grow"><div class="ttl">動画　MOV → MP4</div>
    <div class="dsc">容器を詰め替えるだけなので、<br><b>画質は変わりません（無劣化）。</b></div></div>
  </div>
  <div class="lead" style="margin-top:46px;text-align:center;">
   初期設定は「PC で扱いやすい形式にする」が<b>入</b>になっています
  </div>
 </div>
</div>`);

// ── 8. S4 アプリの中で切り替えられる ──────────────────────
const toggle = (on) => `
<svg width="124" height="70" viewBox="0 0 124 70" fill="none">
 <rect x="2" y="2" width="120" height="66" rx="33" fill="${on ? "#34c759" : "rgba(255,255,255,.22)"}"/>
 <circle cx="${on ? 89 : 35}" cy="35" r="27" fill="#fff"/>
</svg>`;
const switchFmt = page(`<div class="wrap">
 ${logo("撮ったままの形式で送りたいときは")}
 <div class="mid">
  <div class="lead" style="margin-bottom:30px;">iPhone アプリ →「送る形式」</div>
  <div class="card">
   <div class="row" style="align-items:center;gap:40px;">
    <div class="grow">
     <div class="ttl" style="margin:0;">PC で扱いやすい形式にする</div>
     <div class="dsc" style="margin-top:14px;">切ると、撮ったままの形式（HEIC・MOV）のまま送ります。</div>
    </div>
    ${toggle(true)}
   </div>
  </div>
  <div class="lead" style="margin-top:46px;">アプリの中で、いつでも切り替えられます。</div>
 </div>
</div>`);

// ── 9. S8 App Store ───────────────────────────────────────
const appstore = page(`<div class="wrap">
 ${logo("")}
 <div class="mid" style="align-items:center;text-align:center;">
  <img src="${ICON_URI}" style="width:230px;height:230px;border-radius:52px;
    box-shadow:0 18px 50px rgba(0,0,0,.28);">
  <h2 style="margin-top:44px;">App Store で「Mr.Drop」</h2>
  <div class="lead" style="margin-top:26px;">iPhone アプリは<b>無料</b>です。</div>
  <div style="margin-top:40px;"><span class="badge">無料でダウンロード</span></div>
 </div>
</div>`);

for (const [name, html] of [
  ["title.html", title],
  ["s2_direct.html", direct],
  ["s5_home.html", home],
  ["s8_two.html", two],
  ["end.html", end],
  ["s1_p1.html", problem(1)],
  ["s1_p2.html", problem(2)],
  ["s1_p3.html", problem(3)],
  ["s4_format.html", format],
  ["s4_switch.html", switchFmt],
  ["s8_appstore.html", appstore],
]) {
  fs.writeFileSync(path.join(HERE, name), html, "utf8");
  console.log("書きました:", name);
}
