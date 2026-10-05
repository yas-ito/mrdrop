// 台本（../台本-使い方編.md）から、貼り付けるだけの2つのテキストを作る。
//
//   node 紹介動画/音声-使い方編/build-text.js
//     → minimax-貼る.txt        … MiniMax Audio（Web）にそのまま貼る（<#2#> で場面を分ける）
//     → 台本を当てる-貼る.txt   … 一撃極の「台本を当てる」にそのまま貼る（1行＝テロップ1枚）
//
// 🔴 **直すのは台本1か所。**ここで作る2つは毎回作り直すものなので、直接書き換えないこと。
//
// 読ませる字と、画に出す字は**別物**です:
//   MiniMax    … かな書き（「アイフォン」）。記号や英字は読み間違えるため
//   テロップ   … ふつうの表記（「iPhone」）。読む物ではなく、見る物なので
// 「台本を当てる」は表記の違いを吸収します（whisper が「アイフォン」と書いても
// 台本側の「iPhone」に差し替わる。一撃極 client/script-align.js の隙間の処理）。

const fs = require("fs");
const path = require("path");

const HERE = __dirname;
const SCRIPT = path.join(HERE, "..", "台本-使い方編.md");

// 🔴 一撃極の「1行の最大文字数」の既定値。ここを超えると赤い文字数オーバーになる
//    （client/index.html の srt-maxlen。既定 20・最大 30）
//    🔴 ここは 18。一撃極の「1行の最大文字数」も **18 に変えてから**当てること
const MAX_LINE = 18;
// 🔴 **18字ちょうどに収める**（本人指示 2026-09-16・20字から変更）。テロップとして
//    読みやすい長さ。超える行を1行も作らないこと。
const LIMIT = MAX_LINE;

const md = fs.readFileSync(SCRIPT, "utf8");

// ── ① MiniMax に貼る物（かな書き）──────────────────────
// 「### S1」〜「### S6」の下の ``` ``` を読む
const kana = [];
for (const m of md.matchAll(/^### (S\d)\n```\n([\s\S]*?)\n```/gm)) {
  kana.push({ id: m[1], text: m[2].trim() });
}
if (kana.length === 0) throw new Error("🔴 読み上げ用のかな書きが見つかりません");

// 場面の切れ目は <#2#>（2秒のポーズ）。あとで silencedetect で見つけて切り分ける。
// 🔴 場面の中の改行は、そのまま渡すと読点くらいの間にしかならない。それでよい
//    （文の間まで2秒空けると、切り分けが場面の切れ目と区別できなくなる）。
const minimax = kana.map((k) => k.text).join("\n<#2#>\n");

// ── ② 一撃極の「台本を当てる」に貼る物（見る字）────────
// 各場面の「**ナレーション**」の引用（> で始まる行）を拾う
const naration = [];
for (const m of md.matchAll(/^## (S\d) [^\n]*\n[\s\S]*?\*\*ナレーション\*\*\n((?:> [^\n]*\n)+)/gm)) {
  const lines = m[2].split("\n").filter(Boolean).map((l) => l.replace(/^> /, "").trim());
  naration.push({ id: m[1], lines });
}
if (naration.length === 0) throw new Error("🔴 ナレーションが見つかりません");

// テロップは句読点を出さない（本人の既存の字幕に合わせた）。区切りに使ってから最後に消す。
// 🔴 **1文字だけの行や「それから」だけの行を作らない。**
//    読点で切りっぱなしにすると必ずそうなる（最初に作ったとき実際にそうなった）。
//    切りどころで細かく割ってから、20字に収まる限り**詰め直す**。
const JOSHI = "をはがにでともへの";

// 🔴 読点を消すと日本語と英字がくっつく（「あの機能をWindows でも」）。
//    読点の前後が英数字なら、消すのではなく空白にする。
function clean(t) {
  return t
    .replace(/([、。])(?=[A-Za-z0-9])/g, " ")
    .replace(/(?<=[A-Za-z0-9])([、。])/g, " ")
    .replace(/[、。]/g, "")
    .replace(/ {2,}/g, " ")
    .trim();
}
// 🔴 長さは**消したあとの字数**で数える。読点込みで数えると、
//    くっつけられるはずの行がくっつかない（「先日」だけの行ができた）。
const len = (t) => clean(t).length;
const MIN_LINE = 6;   // これより短い行は、隣とくっつける

// 文を「切ってよい所」で細かく割る（読点 → 助詞 → それでも長ければ半分ずつ）
function pieces(sentence) {
  // 🔴 読点は**残したまま**割る。先に消すと、詰め直したときに
  //    日本語と英字がくっつく（「あの機能をWindows でも」）。消すのは最後。
  let out = sentence.split(/(?<=、)/).filter((x) => x);
  const byJoshi = [];
  for (const p of out) {
    if (len(p) <= MAX_LINE) { byJoshi.push(p); continue; }
    let rest = p;
    while (len(rest) > MAX_LINE) {
      // 🔴 切りどころは「左も右も MIN_LINE 以上」になる所から選ぶ。
      //    後ろから貪欲に取ると、右に1〜2字だけ残る行ができる（実際に「2つ」ができた）。
      const hi = Math.min(MAX_LINE, rest.length - MIN_LINE);
      let cut = -1;
      for (let i = hi; i > MIN_LINE; i--) {
        if (JOSHI.includes(rest[i - 1])) { cut = i; break; }
      }
      if (cut < 0) break;
      byJoshi.push(rest.slice(0, cut));
      rest = rest.slice(cut);
    }
    if (rest) byJoshi.push(rest);
  }
  // 🔴 ここまでで切れない塊は、**半端な1文字を残さないように**均等に割る
  const even = [];
  for (const p of byJoshi) {
    if (len(p) <= MAX_LINE) { even.push(p); continue; }
    const n = Math.ceil(p.length / MAX_LINE);
    const w = Math.ceil(p.length / n);
    for (let i = 0; i < p.length; i += w) even.push(p.slice(i, i + w));
  }
  return even;
}

// 18字に収まる限り詰め直す（短い断片が単独の行にならないようにする）
function pack(ps) {
  const out = [];
  for (const p of ps) {
    const last = out[out.length - 1];
    if (last && len(last + p) <= MAX_LINE) out[out.length - 1] = last + p;
    else out.push(p);
  }
  // それでも短いまま残った行は、前の行にくっつける（18字を1〜2字超えても、割るよりは読める）
  for (let i = out.length - 1; i > 0; i--) {
    if (len(out[i]) < MIN_LINE && len(out[i - 1] + out[i]) <= MAX_LINE) {
      out[i - 1] += out[i];
      out.splice(i, 1);
    }
  }
  return out;
}

const telopLines = [];
for (const n of naration) {
  for (const line of n.lines) {
    for (const sentence of line.split("。").filter((x) => x.trim())) {
      for (const t of pack(pieces(sentence))) {
        const t2 = clean(t);
        if (t2) telopLines.push(t2);
      }
    }
  }
}

// ── 書き出し ──────────────────────────────────────────
fs.writeFileSync(path.join(HERE, "minimax-貼る.txt"), minimax + "\n", "utf8");
fs.writeFileSync(path.join(HERE, "台本を当てる-貼る.txt"), telopLines.join("\n") + "\n", "utf8");

// 🔴 「作れた」で終わらせない。読み返して、困る所があれば言う
const longest = Math.max(...telopLines.map((l) => l.length));
const over = telopLines.filter((l) => l.length > LIMIT);
const chars = minimax.replace(/<#2#>/g, "").replace(/\s/g, "").length;

console.log("minimax-貼る.txt      ", kana.length + "場面 / 読む字 約" + chars + "字（＝クレジット）");
console.log("台本を当てる-貼る.txt ", telopLines.length + "枚 / いちばん長い行 " + longest + "字");
console.log("");
console.log("🔴 一撃極の「文字起こし」タブ →「1行の最大文字数」を " + longest + " にしてから当ててください");
console.log("   （足りないと、超えた行が赤い文字数オーバーになります）");
if (over.length) {
  console.log("🔴 " + LIMIT + "字を超えた行が " + over.length + " 行あります（一撃極の上限は30字）:");
  over.forEach((l) => console.log("   " + l));
  process.exitCode = 1;
}
