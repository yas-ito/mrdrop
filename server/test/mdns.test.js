"use strict";
// DNS のパケットは自前で組んでいるので、組む→読むの往復をここで固定する。
// 🔴 実機で踏んだら原因が分かりにくい所（圧縮ポインタ・TXT の区切り）を重点的に。
const m = require("../lib/mdns");
const { TYPE, encodeName, readName, record, rdataA, rdataPtr, rdataSrv, rdataTxt,
        buildResponse, buildQuery, parseMessage, addressFacing } = m;

module.exports = async function (t) {
  const { suite, eq, ok, throws } = t;

  const SERVICE = "_yasdrop._tcp.local";
  const INSTANCE = "YASMA-PC." + SERVICE;
  const HOST = "YASMA-PC.local";

  suite("mDNS — 組んだものを読み戻せる", () => {
    const pkt = buildResponse(
      [record(SERVICE, TYPE.PTR, rdataPtr(INSTANCE), { flush: false })],
      [
        record(INSTANCE, TYPE.SRV, rdataSrv(48630, HOST)),
        record(INSTANCE, TYPE.TXT, rdataTxt({ v: "1.0.0", name: "やすの PC" })),
        record(HOST, TYPE.A, rdataA("192.168.1.20")),
      ]
    );
    const p = parseMessage(pkt);
    eq(p.isQuery, false, "応答として読める");
    eq(p.answers.length, 1, "答えは1つ");
    eq(p.answers[0].ptr, INSTANCE, "PTR が実体を指している");
    const srv = p.additionals.find((r) => r.type === TYPE.SRV);
    eq(srv.port, 48630, "SRV の番号");
    eq(srv.target, HOST, "SRV の行き先");
    const txt = p.additionals.find((r) => r.type === TYPE.TXT);
    eq(txt.txt.v, "1.0.0", "TXT の値");
    eq(txt.txt.name, "やすの PC", "TXT に日本語を入れても壊れない");
    const a = p.additionals.find((r) => r.type === TYPE.A);
    eq(a.address, "192.168.1.20", "A の住所");
    ok(a.flush === true, "A には cache-flush が立っている");
  });

  suite("mDNS — 圧縮ポインタ", () => {
    const nameBuf = encodeName(SERVICE);
    const buf = Buffer.concat([Buffer.alloc(12), nameBuf, Buffer.from([0xc0, 0x0c])]);
    const at = 12 + nameBuf.length;
    eq(readName(buf, at).name, SERVICE, "0xC0 のポインタを追える（Apple は実際に使う）");
    eq(readName(buf, at).off, at + 2, "ポインタの次から読み進む");

    const loop = Buffer.concat([Buffer.alloc(12), Buffer.from([0xc0, 0x0c])]);
    throws(() => readName(loop, 12), "自分を指すポインタで無限ループしない");
    throws(() => readName(Buffer.from([5, 97, 98]), 0), "途中で切れた名前は例外にする");
  });

  suite("mDNS — 問い合わせ", () => {
    const q = parseMessage(buildQuery(SERVICE, TYPE.PTR));
    eq(q.isQuery, true, "質問として読める");
    eq(q.questions.length, 1, "質問は1つ");
    eq(q.questions[0].name, SERVICE, "質問の名前");
    eq(q.questions[0].type, TYPE.PTR, "質問の種類");
    // 🔴 ここを false にすると答えが返って来なくなる（実機で踏んだ）。既定で立てること。
    eq(q.questions[0].unicast, true, "既定で QU ビットが立つ＝ユニキャストで返してもらう");
    eq(parseMessage(buildQuery(SERVICE, TYPE.PTR, false)).questions[0].unicast, false, "明示すれば下ろせる");
  });

  suite("mDNS — 壊れた入力", () => {
    throws(() => parseMessage(Buffer.alloc(3)), "短すぎるパケットは例外");
    throws(() => encodeName("a".repeat(64) + ".local"), "63文字を超えるラベルは例外");
  });

  suite("mDNS — どの住所を答えるか", () => {
    const got = addressFacing("192.168.1.99");
    ok(got === null || /^\d+\.\d+\.\d+\.\d+$/.test(got), "住所か null を返す（NIC の数に依らず落ちない）");
    ok(addressFacing("::1") === null || typeof addressFacing("::1") === "string", "IPv6 で来ても落ちない");
  });
};
