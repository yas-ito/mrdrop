# -*- coding: utf-8 -*-
"""水滴の輪郭を接線から作る。円と直線が接するので、つなぎ目に角が出ない。"""
import math

def drop_path(cx, cy, r, height, bulge=0.0):
    """cy は円の中心。height は円の中心から先端までの距離。
    bulge>0 で側面をふくらませる（0 なら直線＝きっちりした形）。"""
    d = height
    if d <= r:
        raise ValueError("先端が円の中に入っています")
    L = math.sqrt(d * d - r * r)          # 接線の長さ
    tx = r * L / d                        # 接点（中心が原点・先端が真上）
    ty = -r * r / d
    ax, ay = cx, cy - d                   # 先端
    p1 = (cx - tx, cy + ty)               # 左の接点
    p2 = (cx + tx, cy + ty)               # 右の接点
    if bulge <= 0:
        left  = f"L {p1[0]:.1f} {p1[1]:.1f}"
        right = f"L {ax:.1f} {ay:.1f}"
    else:
        # 🔴 ふくらませても、**接点では接線の向きを保つ**こと。
        #    外へ押し出すだけだと肩に折れ目が出る（実際に出た）。
        #    → 接点側の制御点は A→T の直線上に置き、先端側だけ外へ振る。
        def ctrls(p):
            dx, dy = p[0] - ax, p[1] - ay
            nx, ny = -dy, dx                      # 接線に垂直な向き
            n = math.hypot(nx, ny) or 1
            side = 1 if p[0] < cx else -1          # 左右それぞれ外向きへ
            c1 = (ax + dx * 0.38 + nx / n * bulge * side,
                  ay + dy * 0.38 + ny / n * bulge * side)
            c2 = (ax + dx * 0.74, ay + dy * 0.74)  # 直線上＝接点で接する
            return c1, c2
        a1, a2 = ctrls(p1)
        b1, b2 = ctrls(p2)
        left  = f"C {a1[0]:.1f} {a1[1]:.1f} {a2[0]:.1f} {a2[1]:.1f} {p1[0]:.1f} {p1[1]:.1f}"
        right = f"C {b2[0]:.1f} {b2[1]:.1f} {b1[0]:.1f} {b1[1]:.1f} {ax:.1f} {ay:.1f}"
    # 先端 → 左の接点 → 下側の円弧 → 右の接点 → 先端
    return (f"M {ax:.1f} {ay:.1f} {left} "
            f"A {r} {r} 0 1 0 {p2[0]:.1f} {p2[1]:.1f} {right} Z")

if __name__ == "__main__":
    print("直線:", drop_path(512, 560, 168, 400))
    print("ふくらみ:", drop_path(512, 560, 168, 400, bulge=26))
