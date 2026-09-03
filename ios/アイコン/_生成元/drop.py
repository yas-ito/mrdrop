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
        # 接線の中点を外へ押し出した二次ベジエ。接点での向きは接線のまま
        def ctrl(p):
            mx, my = (ax + p[0]) / 2, (ay + p[1]) / 2
            nx, ny = (mx - cx), (my - cy)
            n = math.hypot(nx, ny) or 1
            return (mx + nx / n * bulge, my + ny / n * bulge)
        c1, c2 = ctrl(p1), ctrl(p2)
        left  = f"Q {c1[0]:.1f} {c1[1]:.1f} {p1[0]:.1f} {p1[1]:.1f}"
        right = f"Q {c2[0]:.1f} {c2[1]:.1f} {ax:.1f} {ay:.1f}"
    # 先端 → 左の接点 → 下側の円弧 → 右の接点 → 先端
    return (f"M {ax:.1f} {ay:.1f} {left} "
            f"A {r} {r} 0 1 0 {p2[0]:.1f} {p2[1]:.1f} {right} Z")

if __name__ == "__main__":
    print("直線:", drop_path(512, 560, 168, 400))
    print("ふくらみ:", drop_path(512, 560, 168, 400, bulge=26))
