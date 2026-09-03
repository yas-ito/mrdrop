# -*- coding: utf-8 -*-
"""Mr.Drop のアプリアイコン。HTML を Chrome で 1024px に焼く（PNG を直接いじらない）。"""
import subprocess, sys, os

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# 案ごとの中身。背景・雫の色・添える形だけを差し替える。
CASES = {
"A": """
  <div class="bg" style="background:linear-gradient(160deg,#2E7BF6 0%,#1246C8 100%)"></div>
  <svg viewBox="0 0 1024 1024">
    <!-- 受け皿（PC の画面） -->
    <rect x="212" y="640" width="600" height="150" rx="26" fill="#fff" opacity=".22"/>
    <rect x="212" y="640" width="600" height="18" rx="9" fill="#fff" opacity=".38"/>
    <!-- 雫 -->
    <path d="M512 168 C 512 168, 700 424, 700 540 a188 188 0 1 1 -376 0 C 324 424, 512 168, 512 168 Z" fill="#fff"/>
    <path d="M430 470 a108 108 0 0 0 46 128" stroke="#2E7BF6" stroke-width="26" stroke-linecap="round" fill="none" opacity=".35"/>
  </svg>
""",
"B": """
  <div class="bg" style="background:linear-gradient(160deg,#F7FAFF 0%,#DCE8FF 100%)"></div>
  <svg viewBox="0 0 1024 1024">
    <path d="M512 150 C 512 150, 716 430, 716 556 a204 204 0 1 1 -408 0 C 308 430, 512 150, 512 150 Z" fill="#1F6FEB"/>
    <!-- 下向きの矢印＝PC へ送る -->
    <path d="M512 452 v168 M430 548 l82 82 82-82" stroke="#fff" stroke-width="46"
          stroke-linecap="round" stroke-linejoin="round" fill="none"/>
  </svg>
""",
"C": """
  <div class="bg" style="background:linear-gradient(160deg,#111A2E 0%,#0A1020 100%)"></div>
  <svg viewBox="0 0 1024 1024">
    <text x="512" y="660" font-family="-apple-system,Helvetica Neue,sans-serif" font-size="470"
          font-weight="800" fill="#fff" text-anchor="middle" letter-spacing="-18">M</text>
    <path d="M760 214 C 760 214, 856 344, 856 404 a96 96 0 1 1 -192 0 C 664 344, 760 214, 760 214 Z" fill="#2E7BF6"/>
  </svg>
""",
}


# ── AirDrop 風（広がる輪＋雫）。Apple のマークの複製ではなく、同じ意匠を借りたもの ──
CASES["D"] = """
  <div class="bg" style="background:linear-gradient(160deg,#F7FAFF 0%,#E3ECFF 100%)"></div>
  <svg viewBox="0 0 1024 1024">
    <g fill="none" stroke="#1F6FEB" stroke-linecap="round">
      <path d="M262 620 a250 250 0 0 1 500 0" stroke-width="58" opacity=".22"/>
      <path d="M352 620 a160 160 0 0 1 320 0" stroke-width="58" opacity=".45"/>
    </g>
    <path d="M512 300 C 512 300, 646 486, 646 570 a134 134 0 1 1 -268 0 C 378 486, 512 300, 512 300 Z" fill="#1F6FEB"/>
  </svg>
"""

CASES["E"] = """
  <div class="bg" style="background:linear-gradient(160deg,#2E7BF6 0%,#0E39A8 100%)"></div>
  <svg viewBox="0 0 1024 1024">
    <g fill="none" stroke="#fff" stroke-linecap="round">
      <path d="M232 656 a280 280 0 0 1 560 0" stroke-width="62" opacity=".28"/>
      <path d="M332 656 a180 180 0 0 1 360 0" stroke-width="62" opacity=".5"/>
    </g>
    <path d="M512 306 C 512 306, 648 496, 648 582 a136 136 0 1 1 -272 0 C 376 496, 512 306, 512 306 Z" fill="#fff"/>
  </svg>
"""

HTML = """<!doctype html><meta charset="utf-8">
<style>
  html,body{margin:0;width:1024px;height:1024px;overflow:hidden}
  .wrap{position:relative;width:1024px;height:1024px}
  .bg{position:absolute;inset:0}
  svg{position:absolute;inset:0;width:1024px;height:1024px}
</style>
<div class="wrap">%s</div>
"""

def build(key):
    src = os.path.abspath(f"icon-{key}.html")
    out = os.path.abspath(f"../AppIcon-{key}.png")
    open(src, "w", encoding="utf-8").write(HTML % CASES[key])
    subprocess.run([CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=1", "--window-size=1024,1024",
                    f"--screenshot={out}", f"file://{src}"],
                   check=True, capture_output=True)
    return out

for k in sys.argv[1:] or CASES:
    print("作りました:", build(k))
