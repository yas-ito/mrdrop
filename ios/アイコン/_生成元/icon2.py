# -*- coding: utf-8 -*-
"""AirDrop 風（広がる輪＋水滴）。水滴は drop.py の接線モデルで作る。"""
import subprocess, os, sys, math
from drop import drop_path

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

def ripples(cx, cy, radii, span_deg, color, widths, opacities):
    """cx,cy を中心に、下側へ広がる弧を描く。"""
    out = []
    for r, w, o in zip(radii, widths, opacities):
        a0 = math.radians(180 + (180 - span_deg) / 2)
        a1 = math.radians(360 - (180 - span_deg) / 2)
        x0, y0 = cx + r * math.cos(a0), cy - r * math.sin(a0)
        x1, y1 = cx + r * math.cos(a1), cy - r * math.sin(a1)
        out.append(f'<path d="M {x0:.1f} {y0:.1f} A {r} {r} 0 0 1 {x1:.1f} {y1:.1f}" '
                   f'stroke="{color}" stroke-width="{w}" stroke-linecap="round" fill="none" opacity="{o}"/>')
    return "\n".join(out)

def svg(bg, mark, ripple_color, bulge):
    # 水滴は少し上に、輪はその下から広がる
    d = drop_path(512, 520, 170, 396, bulge=bulge)
    rip = ripples(512, 690, [232, 330], 150, ripple_color, [58, 58], [.5, .28])
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

CASES = {
  # 白地に青・側面まっすぐ
  "F": svg("linear-gradient(160deg,#F7FAFF 0%,#E3ECFF 100%)", "#1F6FEB", "#1F6FEB", 0),
  # 白地に青・側面ふくらみ（水滴らしい）
  "G": svg("linear-gradient(160deg,#F7FAFF 0%,#E3ECFF 100%)", "#1F6FEB", "#1F6FEB", 30),
  # 青地に白・側面ふくらみ
  "H": svg("linear-gradient(160deg,#2E7BF6 0%,#0E39A8 100%)", "#FFFFFF", "#FFFFFF", 30),
}

def build(k):
    src = os.path.abspath(f"icon-{k}.html")
    out = os.path.abspath(f"../AppIcon-{k}.png")
    open(src, "w", encoding="utf-8").write(HTML % CASES[k])
    subprocess.run([CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=1", "--window-size=1024,1024",
                    f"--screenshot={out}", f"file://{src}"], check=True, capture_output=True)
    return out

for k in sys.argv[1:] or CASES:
    print("作りました:", build(k))
