# -*- coding: utf-8 -*-
"""Mr.Drop のアプリアイコン（採用＝最初に作った B 案）。
   形も大きさも B のまま。**上下の位置だけ**真ん中に寄せてある。

   B の雫は先端 y=150・円の中心 y=556・半径 204 なので、
   下端は 760。そのままだと上の余白 150 / 下の余白 264 で 57px 上に寄る。
   → 全体を 57px 下げると、上下とも 207px で揃う。
"""
import subprocess, os

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT = os.path.abspath("../AppIcon.png")

SHIFT = 57      # (1024 - (150 + 760)) / 2 - 150 = 57

HTML = f"""<!doctype html><meta charset="utf-8">
<style>html,body{{margin:0;width:1024px;height:1024px;overflow:hidden}}
.wrap{{position:relative;width:1024px;height:1024px}}
.bg{{position:absolute;inset:0;background:linear-gradient(160deg,#F7FAFF 0%,#DCE8FF 100%)}}
svg{{position:absolute;inset:0;width:1024px;height:1024px}}</style>
<div class="wrap">
  <div class="bg"></div>
  <svg viewBox="0 0 1024 1024">
    <g transform="translate(0,{SHIFT})">
      <path d="M512 150 C 512 150, 716 430, 716 556 a204 204 0 1 1 -408 0 C 308 430, 512 150, 512 150 Z" fill="#1F6FEB"/>
      <path d="M512 452 v168 M430 548 l82 82 82-82" stroke="#fff" stroke-width="46"
            stroke-linecap="round" stroke-linejoin="round" fill="none"/>
    </g>
  </svg>
</div>
"""

src = os.path.abspath("icon-final.html")
open(src, "w", encoding="utf-8").write(HTML)
subprocess.run([CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
                "--force-device-scale-factor=1", "--window-size=1024,1024",
                f"--screenshot={OUT}", f"file://{src}"], check=True, capture_output=True)
print("作りました:", OUT, f"（先端 y={150+SHIFT} / 底 y={760+SHIFT} → 余白は上下とも {150+SHIFT}px）")
