# -*- coding: utf-8 -*-
"""Mr.Drop のアプリアイコン（採用案）。青い雫の中に下向きの矢印＝「PC へ送る」。
   雫は drop.py の接線モデル。PNG は直接加工せず、ここから作り直すこと。"""
import subprocess, os
from drop import drop_classic

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT = os.path.abspath("../AppIcon.png")

# 大きく・丸く。height/R を小さくするほど先が丸くなる（2.2→1.8）
R, HEIGHT = 250, 450
# 🔴 CY は「見た目の真ん中」から逆算する。上の余白＝下の余白 になる位置:
#    (CY - HEIGHT) == 1024 - (CY + R)  →  CY = (1024 + HEIGHT - R) / 2
CX, CY = 512, (1024 + HEIGHT - R) // 2
DROP = drop_classic(CX, CY, R, HEIGHT)
AY = CY - 6                        # 矢印の中心。丸い部分の中に収める
LEN, HALF = 140, 88                # 矢羽根の長さと開き

HTML = f"""<!doctype html><meta charset="utf-8">
<style>html,body{{margin:0;width:1024px;height:1024px;overflow:hidden}}
.wrap{{position:relative;width:1024px;height:1024px}}
.bg{{position:absolute;inset:0;background:linear-gradient(160deg,#F7FAFF 0%,#E3ECFF 100%)}}
svg{{position:absolute;inset:0;width:1024px;height:1024px}}</style>
<div class="wrap">
  <div class="bg"></div>
  <svg viewBox="0 0 1024 1024">
    <path d="{DROP}" fill="#1F6FEB"/>
    <g stroke="#fff" stroke-width="54" stroke-linecap="round" stroke-linejoin="round" fill="none">
      <path d="M {CX} {AY-LEN} V {AY+LEN}"/>
      <path d="M {CX-HALF} {AY+LEN-HALF} L {CX} {AY+LEN} L {CX+HALF} {AY+LEN-HALF}"/>
    </g>
  </svg>
</div>
"""

src = os.path.abspath("icon-final.html")
open(src, "w", encoding="utf-8").write(HTML)
subprocess.run([CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
                "--force-device-scale-factor=1", "--window-size=1024,1024",
                f"--screenshot={OUT}", f"file://{src}"], check=True, capture_output=True)
print("作りました:", OUT)
