"use strict";
// ごく小さい試験の道具。外部パッケージは入れない方針なので自前。
let passed = 0, failed = 0;

function suite(name, fn) { console.log("\n" + name); return fn(); }
function ok(cond, msg) {
  if (cond) { passed++; console.log("  ok   " + msg); }
  else { failed++; console.log("  NG   " + msg); }
}
function eq(got, want, msg) {
  const same = Object.is(got, want) || JSON.stringify(got) === JSON.stringify(want);
  ok(same, msg + (same ? "" : `　（得た: ${JSON.stringify(got)} / 期待: ${JSON.stringify(want)}）`));
}
function throws(fn, msg) { try { fn(); ok(false, msg); } catch { ok(true, msg); } }

module.exports = { suite, ok, eq, throws, report: () => ({ passed, failed }) };
