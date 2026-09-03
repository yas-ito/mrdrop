# -*- coding: utf-8 -*-
"""雫＋波紋。輪は「水面に広がる波紋」（横に平たい楕円）にする。
   縦の弧にするとロケットの脚に見えてしまうため。"""
import subprocess, os, sys
from drop import drop_path

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

def ripple(cx, cy, rx, ry, w, color, o):
    """水面の波紋。楕円の上半分だけを描く（下半分は見えない前提）。"""
    return (f'<path d="M {cx-rx} {cy} A {rx} {ry} 0 0 1 {cx+rx} {cy}" '
            f'stroke="{color}" stroke-width="{w}" stroke-linecap="round" fill="none" opacity="{o}"/>')

def svg(bg, mark, wave, drop_kw, waves):
    d = drop_path(**drop_kw)
    rip = "\n    ".join(ripple(512, y, rx, ry, w, wave, o) for y, rx, ry, w, o in waves)
    return f"""
  <div class="bg" style="background:{bg}"></div>
  <svg viewBox="0 0 1024 1024">
    {rip}
    <path d="{d}" fill="{mark}"/>
  </svg>
"""

HTML = """<!doctype html><meta charset="utf-8">
<style>html,body{margin:0;width:1024px;height:1024px;overflow:hidden}
.wrap{position:relative;width:1024px;height:1024px}
.bg{position:absolute;inset:0}svg{position:absolute;inset:0;width:1024px;height:1024px}</style>
<div class="wrap">%s</div>
"""

DROP = dict(cx=512, cy=418, r=138, height=318, bulge=24)
# 同じ水面（同じ y）から広がる。y をずらすと弧が交差して汚くなる
WAVES = [(772, 198, 54, 38, .5), (772, 310, 86, 38, .24)]

CASES = {
  "I": svg("linear-gradient(160deg,#F7FAFF 0%,#E3ECFF 100%)", "#1F6FEB", "#1F6FEB", DROP, WAVES),
  "J": svg("linear-gradient(160deg,#2E7BF6 0%,#0E39A8 100%)", "#FFFFFF", "#FFFFFF", DROP, WAVES),
}

def build(k):
    src = os.path.abspath(f"icon-{k}.html"); out = os.path.abspath(f"../AppIcon-{k}.png")
    open(src, "w", encoding="utf-8").write(HTML % CASES[k])
    subprocess.run([CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=1", "--window-size=1024,1024",
                    f"--screenshot={out}", f"file://{src}"], check=True, capture_output=True)
    return out

for k in sys.argv[1:] or CASES:
    print("作りました:", build(k))
