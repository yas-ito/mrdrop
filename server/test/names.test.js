"use strict";
const { safeName, uniqueName, humanSize } = require("../lib/names");

module.exports = async function (t) {
  const { suite, eq, ok } = t;

  suite("ファイル名 — どこにでも書かせない", () => {
    eq(safeName("../../evil.txt"), "evil.txt", "上に登る ../ を捨てる");
    eq(safeName("..\\..\\evil.txt"), "evil.txt", "Windows の ..\\ も捨てる");
    eq(safeName("C:\\Windows\\System32\\drivers\\etc\\hosts"), "hosts", "絶対パスでも名前だけ残す");
    eq(safeName("/etc/passwd"), "passwd", "Unix の絶対パスも同じ");
    eq(safeName(".."), "無題", "..だけなら名前にしない");
    eq(safeName("."), "無題", ".だけなら名前にしない");
    eq(safeName(""), "無題", "空なら無題");
    eq(safeName(null), "無題", "null でも落ちない");
  });

  suite("ファイル名 — Windows の作法", () => {
    eq(safeName('a<b>c:d"e|f?g*h.txt'), "a_b_c_d_e_f_g_h.txt", "使えない記号は _ にする");
    eq(safeName("CON.txt"), "_CON.txt", "予約名は開けなくなるので頭に _");
    eq(safeName("com1"), "_com1", "COM1 も小文字で来る");
    eq(safeName("normal.txt"), "normal.txt", "ふつうの名前はそのまま");
    eq(safeName("写真 2026-09-02.HEIC"), "写真 2026-09-02.HEIC", "日本語と空白はそのまま残す");
    eq(safeName("IMG_0001 (1).MOV"), "IMG_0001 (1).MOV", "括弧も残す（消してはいけない）");
    eq(safeName("name.txt.  "), "name.txt", "末尾のドットと空白は Windows が消すので先に消す");
    ok(safeName("a".repeat(300) + ".mov").length <= 120, "長すぎる名前は詰める");
    ok(safeName("a".repeat(300) + ".mov").endsWith(".mov"), "詰めても拡張子は残す");
  });

  suite("ファイル名 — 制御文字", () => {
    eq(safeName("a\r\nb.txt"), "ab.txt", "改行を混ぜられても落とす");
    eq(safeName("a\u0000b.txt"), "ab.txt", "NUL も落とす");
    eq(safeName("%E5%86%99%E7%9C%9F.jpg"), "写真.jpg", "URL 符号化を戻す");
    eq(safeName("100%.txt"), "100%.txt", "壊れた % は文字として扱う（例外にしない）");
  });

  suite("同じ名前が来たとき", () => {
    const have = new Set(["a.jpg"]);
    eq(uniqueName("a.jpg", (n) => have.has(n)), "a (2).jpg", "2 を足す");
    have.add("a (2).jpg");
    eq(uniqueName("a.jpg", (n) => have.has(n)), "a (3).jpg", "空くまで数える");
    eq(uniqueName("b.jpg", (n) => have.has(n)), "b.jpg", "空いていればそのまま");
    eq(uniqueName("noext", (n) => n === "noext"), "noext (2)", "拡張子が無くても足せる");
  });

  suite("大きさの表示", () => {
    eq(humanSize(0), "0 B", "0");
    eq(humanSize(1023), "1023 B", "1KB 未満");
    eq(humanSize(1024), "1.0 KB", "ちょうど 1KB");
    eq(humanSize(1024 * 1024 * 3.5), "3.5 MB", "MB");
    eq(humanSize(-1), "-", "変な値でも落ちない");
  });
};
