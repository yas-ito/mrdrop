// 紹介動画のテロップを PNG（透過）で作る。
//
// 🔴 **1920×1080 で作ること。**Premiere 側で拡大しないための決まり
//    （紹介動画/台本.md の「画の決まり」）。撮るときは倍率2で撮って半分に縮める。
//
// 🔴 文字は画像を拡大せず、ここ（HTML）で作る。Premiere のテキストを使わないのは、
//    XML で渡せないため。透過 PNG なら XML にそのまま並べられる。
//
//   node 紹介動画/テロップ/gen.js   → 同じ場所に *.html
//   紹介動画/テロップ/shot.ps1      → _build/紹介動画/テロップ/*.png（1920×1080・透過）

const fs = require("fs");
const path = require("path");
const HERE = __dirname;

const CSS = `
*{margin:0;padding:0;box-sizing:border-box;}
html,body{width:1920px;height:1080px;background:transparent;}
body{font-family:"Hiragino Sans","Noto Sans JP","Yu Gothic UI","Meiryo",system-ui,sans-serif;
  font-weight:700;-webkit-font-smoothing:antialiased;color:#fff;}
.wrap{width:1920px;height:1080px;padding:80px 96px;display:flex;flex-direction:column;}
.bottom{margin-top:auto;}
.top{}
/* 帯（商品画像の見出しと同じ形）。
   🔴 白地・青文字にすること。青地にすると、S1 の図（青）に重ねたとき沈んで見えない。 */
.band{display:inline-block;background:#fff;color:#1257c7;border-radius:999px;
  padding:22px 46px;font-size:52px;letter-spacing:.02em;
  box-shadow:0 14px 40px rgba(0,0,0,.28);}
/* 下の帯（読ませる用） */
.line{display:inline-block;background:rgba(10,26,58,.88);border-radius:18px;
  padding:20px 34px;font-size:46px;line-height:1.35;
  box-shadow:0 12px 34px rgba(0,0,0,.3);}
.line + .line{margin-top:16px;}
.small{font-size:30px;font-weight:500;opacity:.92;padding:14px 26px;}
.num{display:inline-flex;align-items:center;gap:20px;}
.num .n{display:inline-flex;align-items:center;justify-content:center;
  width:64px;height:64px;border-radius:999px;background:#fff;color:#1257c7;font-size:38px;}
.x{color:#ff6b6b;}
.stack{display:flex;flex-direction:column;align-items:flex-start;}
`;

function page(inner) {
  return `<!doctype html><html lang="ja"><meta charset="utf-8"><style>${CSS}</style>` +
         `<body><div class="wrap">${inner}</div></body></html>`;
}
const bottom = (html) => `<div class="bottom stack">${html}</div>`;
const line = (t, cls = "") => `<div class="line ${cls}">${t}</div>`;

const T = {
  // S1
  s1_hitsuken:  `<div class="top"><span class="band">Windows ユーザー必見</span></div>` +
                bottom(line("Mac の「あの機能」を、同じ手軽さで")),
  s1_mendou:    bottom(line("iPhone → Windows は、いまだに面倒")),
  s1_kashitsu:  bottom(line(`ケーブル <span class="x">✕</span>　クラウド <span class="x">✕</span>　チャット <span class="x">✕</span>`) +
                       line("チャットに送ると画質が落ちる", "small")),
  // S2
  s2_direct:    bottom(line("同じ Wi-Fi の中で、直接") + line("インターネットに出ない")),
  // S3
  s3_step1:     bottom(line(`<span class="num"><span class="n">1</span>アプリを開く → PC が自動で出る</span>`)),
  s3_step2:     bottom(line(`<span class="num"><span class="n">2</span>「写真・動画を送る」から選ぶだけ</span>`) +
                       line("IP アドレスを打つ必要はありません", "small")),
  s3_step3:     bottom(line(`<span class="num"><span class="n">3</span>共有ボタンからでも送れる</span>`)),
  s3_sokutei:   bottom(line("2.81GB の動画を 約35秒／76MB毎秒") +
                       line("iPhone 13 Pro Max・iOS 26.6.1・当方の家庭内 Wi-Fi での実測", "small")),
  // S4
  s4_keishiki:  bottom(line("初期設定：写真は JPEG・動画は MP4") +
                       line("動画は詰め替えるだけ＝画質はそのまま", "small")),
  s4_kirikae:   bottom(line("撮ったまま（HEIC・MOV）にも切り替えられる") +
                       line("同じ名前でも上書きしない（(2) が付く）", "small")),
  // S5
  s5_soto:      bottom(line("アカウント登録なし／広告なし／収集なし")),
  s5_tojireba:  bottom(line("閉じれば、誰も送れない")),
  // S6
  s6_hajimeru:  bottom(line("「はじめる.bat」を1回押すだけ") +
                       line("Node.js 同梱／ほかに入れるものなし", "small")),
  s6_kakureru:  bottom(line("見当たらないときは「∧」の中") +
                       line("Windows 11 は新しいアイコンを最初は隠します", "small")),
  s6_suteru:    bottom(line("ZIP も展開したフォルダも、捨てて OK")),
  s6_yameru:    bottom(line("やめるのもワンクリック（アンインストール）")),
  s6_hozonsaki: bottom(line("保存先を、編集用の素材フォルダにできる")),
  // S7
  s7_gyaku:     bottom(line("PC → iPhone もできる") +
                       line("デスクトップの「Mr.Drop送信箱」に置くだけ", "small")),
  // S8
  s8_futatsu:   bottom(line("iPhone アプリ … App Store で無料") +
                       line("パソコン側 … BOOTH ¥500（期間限定）")),
  s8_kankyo:    bottom(line("Windows 10/11・macOS 13 以降") +
                       line("Windows 版・Mac 版 両方入り／同じ Wi-Fi であることが条件です", "small")),
};

for (const [name, html] of Object.entries(T)) {
  fs.writeFileSync(path.join(HERE, name + ".html"), page(html), "utf8");
}
console.log(Object.keys(T).length + " 枚ぶん書きました");
