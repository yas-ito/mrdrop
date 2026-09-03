# iOS の 1024 アイコンから、Mac 流儀（角丸・周囲に余白）のアイコンを作る
from PIL import Image, ImageDraw, ImageFilter
import os
HERE = os.path.dirname(os.path.abspath(__file__))
src = Image.open(os.path.join(HERE, "..", "..", "ios", "MrDrop", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")).convert("RGBA")
CANVAS, BODY = 1024, 824            # Apple の Mac アイコン規格: 1024 の中に 824 の角丸四角
R = int(BODY * 185 / 824)           # 角丸半径（規格どおり 185/824）
body = src.resize((BODY, BODY), Image.LANCZOS)
mask = Image.new("L", (BODY, BODY), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, BODY - 1, BODY - 1), radius=R, fill=255)
body.putalpha(mask)
out = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
# うっすら影（Mac のアイコンはこれが無いと浮かない）
shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
sm = Image.new("L", (BODY, BODY), 0)
ImageDraw.Draw(sm).rounded_rectangle((0, 0, BODY - 1, BODY - 1), radius=R, fill=110)
shadow.paste((0, 0, 0, 110), ((CANVAS - BODY) // 2, (CANVAS - BODY) // 2 + 12), sm)
shadow = shadow.filter(ImageFilter.GaussianBlur(14))
out.alpha_composite(shadow)
out.alpha_composite(body, ((CANVAS - BODY) // 2, (CANVAS - BODY) // 2))
out.save(os.path.join(HERE, "icon_1024.png"))
print("ok", out.size)
