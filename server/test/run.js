#!/usr/bin/env node
"use strict";
// 全部の試験を通す:  node server/test/run.js
const t = require("./t");

const FILES = ["names.test.js", "config.test.js", "mdns.test.js", "http.test.js", "follow.test.js"];

(async () => {
  for (const f of FILES) {
    await require("./" + f)(t);
  }
  const { passed, failed } = t.report();
  console.log("");
  console.log(`${passed} passed, ${failed} failed`);
  if (failed) { console.log("🔴 通っていないものがあります。"); process.exit(1); }
  console.log("全テスト成功");
  process.exit(0);
})().catch((e) => { console.error("🔴 試験そのものが落ちました:", e && e.stack ? e.stack : e); process.exit(1); });
