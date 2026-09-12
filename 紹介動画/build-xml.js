// Premiere に読み込ませる XML（FCP7 xmeml）を作る。
//
// 🔴 テロップはここでは入れない。**一撃極の「台本を当てる」→「テロップにする（適用）」**で載せる
//    （本人決定 2026-09-12）。だから XML には映像と音声だけを並べる。
// 🔴 2画面（iPhone＋PC）は**先に焼いてある**。Premiere 側で位置合わせをさせない
//    （拡大率や位置は XML 越しだと崩れることがあるため）。
// 🔴 尺は MiniMax の音声の実測値。台本（紹介動画/台本.md）の表と同じ。
//
//   node 紹介動画/build-xml.js
//     → C:\Users\yasma\Desktop\Mr.Drop紹介動画\Mr.Drop紹介動画.xml

const fs = require("fs");
const path = require("path");

const PROJ = "C:\\Users\\yasma\\Desktop\\Mr.Drop紹介動画";
const V = path.join(PROJ, "素材", "映像");
const A = path.join(PROJ, "素材", "音声");
const Z = path.join(PROJ, "素材", "図");
const FPS = 30;
const f = (sec) => Math.round(sec * FPS);

// ── 音声（実測値）───────────────────────────────────────
const AUDIO = [
  ["S1.mp3", 34.9], ["S2.mp3", 15.4], ["S3.mp3", 42.7], ["S4.mp3", 19.7],
  ["S5.mp3", 17.7], ["S6.mp3", 41.6], ["S7.mp3", 9.7],  ["S8.mp3", 30.7],
];
const GAP = 0.5;                       // 場面の切れ目の間

// 各場面の開始時刻を積む
const startOf = [];
{
  let t = 0;
  for (const [, dur] of AUDIO) { startOf.push(t); t += dur + GAP; }
}
const S = (n) => startOf[n - 1];       // S(1) = 0

// ── 映像の並び ─────────────────────────────────────────
// [開始秒, 長さ秒, ファイル, 素材内の開始秒（静止画は 0）]
const VIDEO = [
  // S1 あいさつ／困りごと
  [S(1),        10.0, path.join(Z, "title.png"),                 0],
  [S(1) + 10.0, 12.0, path.join(V, "PC_着弾_1080.mp4"),           0],
  [S(1) + 22.0, 12.9, path.join(V, "iPhone_アプリから送る.mp4"),    0],
  // S2 これは何か
  [S(2),        15.4, path.join(Z, "s2_direct.png"),             0],
  // S3 実演（最大の見せ場）
  [S(3),        32.0, path.join(V, "2画面_アプリから送る.mp4"),     0],
  [S(3) + 32.0, 10.7, path.join(V, "2画面_共有ボタン.mp4"),        0],
  // S4 届く形式
  [S(4),        10.0, path.join(V, "iPhone_アプリから送る.mp4"),   12.0],
  [S(4) + 10.0,  9.7, path.join(V, "PC_着弾_1080.mp4"),           44.0],
  // S5 外に出ない
  [S(5),        11.0, path.join(Z, "s5_home.png"),               0],
  [S(5) + 11.0,  6.7, path.join(V, "PC_トレイメニュー.mp4"),       11.0],
  // S6 入れるのは1回だけ
  [S(6),        15.0, path.join(V, "PC_はじめる_1080.mp4"),       21.0],
  [S(6) + 15.0, 10.0, path.join(V, "PC_済みました画面.mp4"),        0],
  [S(6) + 25.0, 10.0, path.join(V, "PC_トレイメニュー.mp4"),        8.0],
  [S(6) + 35.0,  6.6, path.join(V, "PC_保存先を変える_1080.mp4"),  60.0],
  // S7 PC → iPhone
  [S(7),         9.7, path.join(V, "PC_送信箱_1080.mp4"),          2.3],
  // S8 締め
  [S(8),        12.0, path.join(Z, "s8_two.png"),                0],
  [S(8) + 12.0, 12.0, path.join(V, "PC_BOOTH商品ページ_1080.mp4"), 4.0],
  [S(8) + 24.0,  6.7, path.join(Z, "end.png"),                   0],
];

const TOTAL = S(8) + AUDIO[7][1];

// ── XML を組む ─────────────────────────────────────────
// pathurl は file://localhost/C:/… 形式。日本語はパーセント符号化する
function url(p) {
  return "file://localhost/" + p.replace(/\\/g, "/").split("/").map(encodeURIComponent).join("/").replace("C%3A", "C:");
}
const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const rate = `<rate><timebase>${FPS}</timebase><ntsc>FALSE</ntsc></rate>`;

let fileId = 0;
const seenFile = new Map();
function fileTag(p, isStill, isAudio) {
  const name = path.basename(p);
  if (seenFile.has(p)) return `<file id="${seenFile.get(p)}"/>`;
  const id = "file-" + (++fileId);
  seenFile.set(p, id);
  const dur = isStill ? FPS * 3600 : FPS * 3600;   // 長めに書いておけば足りる
  const media = isAudio
    ? `<media><audio><samplecharacteristics><depth>16</depth><samplerate>48000</samplerate></samplecharacteristics><channelcount>2</channelcount></audio></media>`
    : `<media><video><samplecharacteristics><width>1920</width><height>1080</height></samplecharacteristics></video>${isStill ? "" : "<audio><samplecharacteristics><depth>16</depth><samplerate>48000</samplerate></samplecharacteristics><channelcount>2</channelcount></audio>"}</media>`;
  return `<file id="${id}"><name>${esc(name)}</name><pathurl>${url(p)}</pathurl>${rate}<duration>${dur}</duration>${media}</file>`;
}

let itemId = 0;
function videoItem(startSec, durSec, p, srcStartSec) {
  const isStill = /\.png$/i.test(p);
  const id = "clipitem-" + (++itemId);
  const start = f(startSec), end = f(startSec + durSec);
  const iIn = f(srcStartSec), iOut = f(srcStartSec + durSec);
  return `<clipitem id="${id}"><name>${esc(path.basename(p))}</name>${rate}` +
         `<start>${start}</start><end>${end}</end><in>${iIn}</in><out>${iOut}</out>` +
         `${fileTag(p, isStill, false)}</clipitem>`;
}
function audioItem(startSec, durSec, p) {
  const id = "clipitem-" + (++itemId);
  const start = f(startSec), end = f(startSec + durSec);
  return `<clipitem id="${id}"><name>${esc(path.basename(p))}</name>${rate}` +
         `<start>${start}</start><end>${end}</end><in>0</in><out>${f(durSec)}</out>` +
         `${fileTag(p, false, true)}` +
         `<sourcetrack><mediatype>audio</mediatype><trackindex>1</trackindex></sourcetrack></clipitem>`;
}

const vItems = VIDEO.map(([s, d, p, ss]) => videoItem(s, d, p, ss)).join("");
const aItems = AUDIO.map(([n, d], i) => audioItem(S(i + 1), d, path.join(A, n))).join("");

const xml = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE xmeml>
<xmeml version="4">
<sequence id="sequence-1">
<name>Mr.Drop紹介動画</name>
<duration>${f(TOTAL)}</duration>
${rate}
<media>
<video>
<format><samplecharacteristics>${rate}<width>1920</width><height>1080</height><pixelaspectratio>square</pixelaspectratio></samplecharacteristics></format>
<track>${vItems}</track>
</video>
<audio>
<format><samplecharacteristics><depth>16</depth><samplerate>48000</samplerate></samplecharacteristics></format>
<track>${aItems}</track>
</audio>
</media>
</sequence>
</xmeml>
`;

const outPath = path.join(PROJ, "Mr.Drop紹介動画.xml");
fs.writeFileSync(outPath, xml, "utf8");
console.log("書きました:", outPath);
console.log("全体の尺:", TOTAL.toFixed(1), "秒 =", Math.floor(TOTAL / 60) + "分" + Math.round(TOTAL % 60) + "秒");
console.log("映像", VIDEO.length, "本 ／ 音声", AUDIO.length, "本");
