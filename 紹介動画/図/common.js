// 図の土台（色・書体・部品）。**1本目の紹介動画と2本目の使い方編で分け合う。**
//
// 🔴 ここを直すと**両方の図が変わります**。片方だけ変えたいときは、
//    呼ぶ側（gen.js / ../図-使い方編/gen.js）で上書きすること。
//
// 🔴 **最初から 1920×1080 で作ること。**あとで引き延ばさないための決まり
//    （紹介動画/台本.md の「画の決まり」）。撮るときは倍率2で撮って半分に縮める。
//
// 色と書体は BOOTH の商品画像（yas-tools-ops/ops/mrdrop-booth-images/gen.py）と揃えてある。
const fs = require("fs");
const path = require("path");

const HERE = __dirname;
const REPO = path.join(HERE, "..", "..");

// アプリのアイコン（1024×1024）を埋め込む。外を見に行かせない
const ICON = fs.readFileSync(path.join(REPO, "ios", "アイコン", "AppIcon.png")).toString("base64");
const ICON_URI = "data:image/png;base64," + ICON;

const CSS = `
*{margin:0;padding:0;box-sizing:border-box;}
body{width:1920px;height:1080px;overflow:hidden;
  background:linear-gradient(150deg,#0f3d9e 0%,#1c5fd0 55%,#2472e8 100%);
  color:#fff;font-weight:500;
  /* 🔴 "Noto Sans JP" を先頭に置くこと。Mac には Hiragino Sans があるので、
     Hiragino を先にすると **Windows で作った図と別の絵になる**（2026-09-12 に実際に食い違った）。
     Windows には Hiragino が無いので、この順にしても Windows 側の出来上がりは変わらない。 */
  font-family:"Noto Sans JP","Hiragino Sans","Yu Gothic UI","Meiryo",system-ui,sans-serif;
  -webkit-font-smoothing:antialiased;}
.wrap{width:1920px;height:1080px;padding:96px 120px;display:flex;flex-direction:column;}
.logo{display:flex;align-items:center;gap:24px;}
.logo img{width:86px;height:86px;border-radius:20px;box-shadow:0 10px 30px rgba(0,0,0,.22);}
.logo .name{font-size:54px;font-weight:700;letter-spacing:.01em;}
.logo .sub{font-size:24px;opacity:.72;border-left:1px solid rgba(255,255,255,.38);padding-left:20px;margin-left:4px;}
h1{font-size:104px;line-height:1.18;font-weight:700;letter-spacing:.01em;}
h2{font-size:76px;line-height:1.22;font-weight:700;}
.lead{font-size:34px;line-height:1.7;opacity:.88;}
.card{background:rgba(255,255,255,.12);border:1px solid rgba(255,255,255,.22);
  border-radius:22px;padding:34px 40px;backdrop-filter:blur(2px);}
.card .ttl{font-size:38px;font-weight:700;margin-bottom:12px;}
.card .dsc{font-size:27px;line-height:1.62;opacity:.9;}
.row{display:flex;gap:36px;align-items:center;}
.grow{flex:1;}
.center{justify-content:center;align-items:center;}
.mid{flex:1;display:flex;flex-direction:column;justify-content:center;}
.foot{font-size:24px;opacity:.72;}
.badge{display:inline-block;background:#fff;color:#1257c7;border-radius:999px;
  padding:14px 34px;font-size:34px;font-weight:700;}
.chip{display:inline-block;border:1px solid rgba(255,255,255,.4);border-radius:999px;
  padding:12px 28px;font-size:28px;}
/* 🔴 テロップは画面の下 y=934〜1050 に出る（2026-09-12 に実機のフレームで実測）。
   ここに物を置くと必ずかぶる。**画面のいちばん下に置く要素には .above-telop を付ける。**
   position:relative なので、まわりのレイアウトは1pxも動かさずに持ち上げられる。 */
.above-telop{position:relative;bottom:90px;}
.big-plus{font-size:88px;font-weight:700;opacity:.85;}
`;

function page(inner) {
  return `<!doctype html><html lang="ja"><meta charset="utf-8"><style>${CSS}</style><body>${inner}</body></html>`;
}
const logo = (sub) =>
  `<div class="logo"><img src="${ICON_URI}"><div class="name">Mr.Drop</div>` +
  (sub ? `<div class="sub">${sub}</div>` : "") + `</div>`;

// ── 部品（SVG） ───────────────────────────────────────────
const phone = (w = 210) => `
<svg width="${w}" viewBox="0 0 210 420" fill="none">
 <rect x="6" y="6" width="198" height="408" rx="34" fill="rgba(255,255,255,.14)" stroke="rgba(255,255,255,.55)" stroke-width="4"/>
 <rect x="70" y="20" width="70" height="16" rx="8" fill="rgba(255,255,255,.55)"/>
 <rect x="34" y="86" width="142" height="104" rx="14" fill="rgba(255,255,255,.42)"/>
 <rect x="34" y="210" width="142" height="20" rx="10" fill="rgba(255,255,255,.3)"/>
 <rect x="34" y="248" width="100" height="20" rx="10" fill="rgba(255,255,255,.3)"/>
 <rect x="34" y="320" width="142" height="46" rx="14" fill="#fff"/>
</svg>`;

const pc = (w = 420) => `
<svg width="${w}" viewBox="0 0 420 320" fill="none">
 <rect x="8" y="8" width="404" height="252" rx="20" fill="rgba(255,255,255,.14)" stroke="rgba(255,255,255,.55)" stroke-width="4"/>
 <rect x="40" y="48" width="160" height="26" rx="8" fill="rgba(255,255,255,.42)"/>
 <rect x="40" y="96" width="340" height="30" rx="8" fill="rgba(255,255,255,.3)"/>
 <rect x="40" y="140" width="340" height="30" rx="8" fill="rgba(255,255,255,.3)"/>
 <rect x="40" y="184" width="240" height="30" rx="8" fill="rgba(255,255,255,.3)"/>
 <rect x="150" y="268" width="120" height="16" rx="8" fill="rgba(255,255,255,.45)"/>
 <rect x="96" y="296" width="228" height="14" rx="7" fill="rgba(255,255,255,.55)"/>
</svg>`;

const arrow = (label) => `
<div style="display:flex;flex-direction:column;align-items:center;gap:16px;min-width:300px;">
 <div style="font-size:28px;opacity:.9;">${label}</div>
 <svg width="300" height="26" viewBox="0 0 300 26" fill="none">
  <path d="M0 13 H268" stroke="#fff" stroke-width="5" stroke-linecap="round"/>
  <path d="M266 2 L296 13 L266 24 Z" fill="#fff"/>
 </svg>
</div>`;

// 雲は円と角丸で組む（1本のパスだと潰れて雲に見えない。実際に一度失敗した）
const cloudX = (w = 260) => `
<svg width="${w}" viewBox="0 0 260 170" fill="none">
 <g fill="rgba(255,255,255,.2)">
  <circle cx="88" cy="96" r="32"/>
  <circle cx="132" cy="74" r="44"/>
  <circle cx="180" cy="98" r="30"/>
  <rect x="70" y="96" width="126" height="36" rx="18"/>
 </g>
 <path d="M96 50 L186 138 M186 50 L96 138" stroke="#ff6b6b" stroke-width="12" stroke-linecap="round"/>
</svg>`;
module.exports = { fs, path, HERE, REPO, ICON_URI, CSS, page, logo, phone, pc, arrow, cloudX };
