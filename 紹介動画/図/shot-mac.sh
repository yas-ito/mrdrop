#!/bin/bash
# 紹介動画の図を撮る（Chrome ヘッドレス・Mac 版）。shot.ps1 の対になる物。
#
# 🔴 倍率2（3840×2160）で撮ってから 1920×1080 へ**縮める**。拡大は絶対にしない。
#    （紹介動画/台本.md の「画の決まり」）
#
#   bash 紹介動画/図/shot-mac.sh        → _build/紹介動画/図/*.png（1920×1080）
#   bash 紹介動画/図/shot-mac.sh title  → title だけ撮る
#
# 🔴 **書体は gen.js の font-family で "Noto Sans JP" を先頭に固定してある。**
#    Mac には Hiragino Sans があるので、順番を変えると Windows で作った図と別物になる
#    （2026-09-12 に実際に食い違った）。Noto Sans JP が入っていないとここで止める。
# 🔵 shot.ps1 と同じで、先に `node 紹介動画/図/gen.js` で HTML を作ってから撮る。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUT="$REPO/_build/紹介動画/図"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
ONLY="${1:-}"

[ -x "$CHROME" ] || { echo "🔴 Chrome が見つかりません: $CHROME" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "🔴 ffmpeg が見つかりません" >&2; exit 1; }
# 🔴 書体の検査。無いまま撮ると Hiragino で撮れてしまい、見た目が変わる
# 🔴 「コマンド | grep -q」は使わない。pipefail 下では grep が先に抜けると左側が SIGPIPE で
#    落ち、**入っているのに「無い」と言う**（make-mac-app.sh に書いてある罠。ここでも踏んだ）。
FONTS="$(system_profiler SPFontsDataType 2>/dev/null || true)"
case "$FONTS" in
  *"Noto Sans JP"*) ;;
  *) echo "🔴 Noto Sans JP が入っていません。入れてから撮ってください" >&2; exit 1 ;;
esac

mkdir -p "$OUT"
node "$HERE/gen.js" >/dev/null

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for h in "$HERE"/*.html; do
  base="$(basename "$h" .html)"
  [ -z "$ONLY" ] || [ "$base" = "$ONLY" ] || continue
  big="$TMP/${base}_2x.png"
  png="$OUT/$base.png"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --virtual-time-budget=6000 \
    --force-device-scale-factor=2 --window-size=1920,1080 \
    --screenshot="$big" "file://$h" 2>/dev/null || true
  [ -f "$big" ] || { echo "🔴 撮れませんでした: $base" >&2; exit 1; }
  ffmpeg -hide_banner -loglevel error -i "$big" -vf "scale=1920:1080:flags=lanczos" -y "$png"
  # 🔴 「作れた」で終わらせない。大きさを読み返す
  size="$(ffprobe -v error -show_entries stream=width,height -of csv=p=0:s=x "$png")"
  [ "$size" = "1920x1080" ] || { echo "🔴 $base が $size になっています" >&2; exit 1; }
  echo "  $base  $size"
done

echo "できました: $OUT"
